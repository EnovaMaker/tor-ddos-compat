# Shared helpers. Sourced by the other scripts; not meant to be run on its own.
# SPDX-License-Identifier: MIT
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LISTS_URL="${TORDDOS_LISTS_URL:-https://raw.githubusercontent.com/EnovaMaker/tor-relay-lists/main/}"
LISTS_DIR="$HERE/lists"
CHAIN=TORDDOS
mkdir -p "$LISTS_DIR"

need_root() { [ "$(id -u)" = 0 ] || { echo "Run this as root (or with sudo)." >&2; exit 1; }; }

# Install what is missing, on Debian and Ubuntu only; elsewhere say what to install.
ensure_deps() {
  local missing=()
  for c in iptables ipset curl; do command -v "$c" >/dev/null 2>&1 || missing+=("$c"); done
  [ ${#missing[@]} -eq 0 ] && return 0
  if [ -r /etc/os-release ] && grep -qiE 'debian|ubuntu' /etc/os-release && command -v apt-get >/dev/null 2>&1; then
    apt-get install -y "${missing[@]}" conntrack
  else
    echo "Missing: ${missing[*]}. Install them with your package manager and run this again." >&2
    exit 1
  fi
}

# Config: ipv4.txt / ipv6.txt, one "address port" per line (several lines for several ORPorts).
# An existing file is read tolerantly: the first address-looking token is the address,
# and every other all-digit token on the line is a port.
read_targets() { # file -> lines "addr port"
  [ -s "$1" ] || return 0
  grep -v '^[[:space:]]*#' "$1" | while read -r line; do
    addr=""
    for t in $line; do
      if [ -z "$addr" ] && printf '%s' "$t" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$|^[0-9a-fA-F]*:[0-9a-fA-F:]+$'; then
        addr=$t
      elif [ -n "$addr" ] && printf '%s' "$t" | grep -qE '^[0-9]{1,5}$'; then
        echo "$addr $t"
      fi
    done
  done
}

fetch_list() { # name minimum-entries; the previous copy is kept if the download fails or is too short
  local name=$1 min=${2:-1} tmp
  tmp=$(mktemp)
  if curl -fsSL --max-time 60 "$LISTS_URL$name.txt" -o "$tmp" \
     && [ "$(grep -cE '^[0-9a-fA-F.:/]+$' "$tmp")" -ge "$min" ]; then
    grep -E '^[0-9a-fA-F.:/]+$' "$tmp" > "$LISTS_DIR/$name.txt"
  else
    echo "could not refresh $name (kept the previous copy)" >&2
  fi
  rm -f "$tmp"
}

load_set() { # setname family listfile
  [ -s "$3" ] || return 0
  ipset create -exist "$1" hash:ip family "$2" maxelem 262144
  ipset create -exist "$1.new" hash:ip family "$2" maxelem 262144
  ipset flush "$1.new"
  grep -E '^[0-9a-fA-F.:]+$' "$3" | while read -r a; do ipset add -exist "$1.new" "$a" 2>/dev/null; done
  ipset swap "$1.new" "$1"
  ipset destroy "$1.new"
}

load_all_sets() {
  local extra="$HERE/allow-extra.txt" snow="$HERE/snowflake.txt"
  # allow-list: directory authorities, plus anything the operator adds by hand
  { cat "$LISTS_DIR/authorities-v4.txt" "$snow" "$extra" 2>/dev/null; } | grep -E '^[0-9.]+$' > "$LISTS_DIR/.allow4" || true
  { cat "$LISTS_DIR/authorities-v6.txt" "$snow" "$extra" 2>/dev/null; } | grep ':' > "$LISTS_DIR/.allow6" || true
  ipset create -exist allow-list hash:ip family inet
  ipset create -exist allow-list-v6 hash:ip family inet6
  ipset create -exist dual-or hash:ip family inet
  ipset create -exist dual-or-v6 hash:ip family inet6
  ipset create -exist 4-or hash:ip family inet
  ipset create -exist 4-or-v6 hash:ip family inet6
  load_set allow-list    inet  "$LISTS_DIR/.allow4"
  load_set allow-list-v6 inet6 "$LISTS_DIR/.allow6"
  load_set dual-or       inet  "$LISTS_DIR/2-or.txt"
  load_set dual-or-v6    inet6 "$LISTS_DIR/2-or-v6.txt"
  load_set 4-or          inet  "$LISTS_DIR/above2-or.txt"
  load_set 4-or-v6       inet6 "$LISTS_DIR/above2-or-v6.txt"
}

blockset() { # addr port family -> name of the block-list set
  if [ "$3" = inet ]; then echo "tor-$1-$2"; else echo "tor6-$2"; fi
}
