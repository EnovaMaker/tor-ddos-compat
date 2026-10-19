#!/usr/bin/env bash
# Compare the block list with the list of all Tor relays, and optionally release the relays.
# SPDX-License-Identifier: MIT
. "$(dirname "$0")/lib.sh"; need_root
mapfile -t T < <(read_targets "$HERE/ipv4.txt")
[ ${#T[@]} -gt 0 ] || { echo "No ipv4.txt found next to this script."; exit 1; }
for t in "${T[@]}"; do
  set -- $t; bs=$(blockset "$1" "$2" inet)
  echo "== $bs"
  ipset list "$bs" 2>/dev/null | sed -n '/^Members:/,$p' | tail -n +2 | awk '{print $1}' | sort -u \
    | grep -Fxf "$LISTS_DIR/relays-v4.txt" | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n > "$LISTS_DIR/.caught" || true
  cat "$LISTS_DIR/.caught"
  echo "Relays in the block list: $(wc -l < "$LISTS_DIR/.caught")"
done
echo
echo "1) release all relays   2) release only relays running more than one Tor instance   3) leave as is"
read -r -p "> " c
case "$c" in
  1) exec "$HERE/remove.sh" ;;
  2) exec "$HERE/remove-dual-or.sh" ;;
  *) echo "Left as is." ;;
esac
