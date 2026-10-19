#!/usr/bin/env bash
# Apply the rules. Run after every reboot (multi.sh does the same), or use update.sh to refresh.
# SPDX-License-Identifier: MIT
. "$(dirname "$0")/lib.sh"; need_root; ensure_deps

# Kernel settings for a relay that handles many connections (runtime only).
sysctl -qw net.ipv4.tcp_fin_timeout=20 net.ipv4.tcp_syncookies=1 net.ipv4.tcp_tw_reuse=1 \
           net.ipv4.ip_local_port_range="10000 65000" net.ipv4.tcp_max_syn_backlog=8192 >/dev/null 2>&1 || true

load_all_sets

apply() { # iptables-command family targets-file
  local ipt=$1 fam=$2 file=$3 sfx="" t a p bs m s
  [ "$fam" = inet6 ] && sfx="-v6"
  mapfile -t T < <(read_targets "$file")
  [ ${#T[@]} -gt 0 ] || return 0
  $ipt -t mangle -N $CHAIN 2>/dev/null || $ipt -t mangle -F $CHAIN
  $ipt -t mangle -C PREROUTING -j $CHAIN 2>/dev/null || $ipt -t mangle -I PREROUTING -j $CHAIN
  # Only our own INPUT chain is rebuilt; the operator's rules are never flushed.
  $ipt -N TORDDOS-IN 2>/dev/null || $ipt -F TORDDOS-IN
  $ipt -C INPUT -j TORDDOS-IN 2>/dev/null || $ipt -I INPUT -j TORDDOS-IN
  for t in "${T[@]}"; do
    set -- $t; a=$1; p=$2; bs=$(blockset "$a" "$p" "$fam")
    ipset create -exist "$bs" hash:ip family "$fam" hashsize 4096 timeout 43200
    m="-p tcp -d $a --dport $p"
    # 1. Authorities and anything on the allow list are never touched.
    $ipt -t mangle -A $CHAIN $m -m set --match-set allow-list$sfx src -j ACCEPT
    # 2. A source on the block list gets no new connection; what it already holds is reset in TORDDOS-IN.
    $ipt -t mangle -A $CHAIN $m -m conntrack --ctstate NEW -m set --match-set "$bs" src -j DROP
    # 3. Relays running several Tor instances on one address may hold two connections.
    for s in dual-or$sfx 4-or$sfx; do
      $ipt -t mangle -A $CHAIN $m -m set --match-set $s src -m connlimit --connlimit-mask 32 --connlimit-above 2 -j SET --add-set "$bs" src
      $ipt -t mangle -A $CHAIN $m -m set --match-set $s src -m connlimit --connlimit-mask 32 --connlimit-above 2 -j DROP
      $ipt -t mangle -A $CHAIN $m -m set --match-set $s src -j ACCEPT
    done
    # 4. Everyone else holds one connection. One that keeps asking after being refused is blocked.
    $ipt -t mangle -A $CHAIN $m -m conntrack --ctstate NEW -m connlimit --connlimit-mask 32 --connlimit-above 1 \
         -m hashlimit --hashlimit-name "td-$p$sfx" --hashlimit-mode srcip --hashlimit-above 10/minute --hashlimit-burst 10 \
         -j SET --add-set "$bs" src
    $ipt -t mangle -A $CHAIN $m -m connlimit --connlimit-mask 32 --connlimit-above 1 -j DROP
    $ipt -t mangle -A $CHAIN $m -j ACCEPT
    # Close what a blocked source already holds open, as soon as it sends anything.
    $ipt -A TORDDOS-IN $m -m set --match-set "$bs" src -j REJECT --reject-with tcp-reset
  done
}

apply iptables inet "$HERE/ipv4.txt"
command -v ip6tables >/dev/null 2>&1 && apply ip6tables inet6 "$HERE/ipv6.txt"
echo "Rules applied."
