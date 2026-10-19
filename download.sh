#!/usr/bin/env bash
# One command to install:
#   bash <(curl -Ls https://raw.githubusercontent.com/EnovaMaker/tor-ddos-compat/main/download.sh)
# Downloads the scripts to $PWD/tor, asks for your addresses and ORPorts, and applies the rules.
# SPDX-License-Identifier: MIT
set -u
BASE="${TORDDOS_BASE_URL:-https://raw.githubusercontent.com/EnovaMaker/tor-ddos-compat/main}"
FILES="lib.sh rules.sh multi.sh update.sh refresh-authorities.sh compare.sh remove.sh remove-dual-or.sh conntrack.sh"
[ "$(id -u)" = 0 ] || { echo "Run this as root (or with sudo)." >&2; exit 1; }
DEST="$PWD/tor"
mkdir -p "$DEST"

# An earlier installation of the older scripts (or of these): offer to reuse its addresses and ports.
OLD=$(find / -xdev -name ipv4.txt -path '*tor*' -not -path "$DEST/*" 2>/dev/null | head -1)
if [ -n "$OLD" ] && [ ! -s "$DEST/ipv4.txt" ]; then
  echo "Found an earlier configuration: $OLD"
  if [ -n "${TORDDOS_REUSE:-}" ]; then a=$TORDDOS_REUSE; else read -r -p "Reuse its addresses and ports? [Y/n] " a; fi
  if [ "${a:-Y}" != n ] && [ "${a:-Y}" != N ]; then
    cp "$OLD" "$DEST/ipv4.txt"
    [ -s "$(dirname "$OLD")/ipv6.txt" ] && cp "$(dirname "$OLD")/ipv6.txt" "$DEST/ipv6.txt"
  fi
fi

for f in $FILES; do
  if [ -n "${TORDDOS_LOCAL_SRC:-}" ]; then
    cp "$TORDDOS_LOCAL_SRC/$f" "$DEST/$f"
  else
    curl -fsSL "$BASE/$f" -o "$DEST/$f" || { echo "could not download $f" >&2; exit 1; }
  fi
  chmod +x "$DEST/$f"
done

if [ ! -s "$DEST/ipv4.txt" ]; then
  if [ -n "${TORDDOS_IPV4:-}" ]; then
    ip4=$TORDDOS_IPV4; ports=${TORDDOS_PORTS:-}; ip6=${TORDDOS_IPV6:-}
  else
    read -r -p "Your relay's IPv4 address: " ip4
    read -r -p "ORPort(s), separated by spaces: " ports
    read -r -p "Your IPv6 address (empty for none): " ip6
  fi
  for p in $ports; do echo "$ip4 $p"; done > "$DEST/ipv4.txt"
  if [ -n "$ip6" ]; then for p in $ports; do echo "$ip6 $p"; done > "$DEST/ipv6.txt"; fi
fi

"$DEST/refresh-authorities.sh" && "$DEST/rules.sh"
cat <<EOM

Done. After every reboot run:  $DEST/multi.sh
To refresh the lists daily, add this to cron (once):
  (crontab -l ; echo "0 0 * * * $DEST/refresh-authorities.sh") | crontab -
EOM
