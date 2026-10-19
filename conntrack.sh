#!/usr/bin/env bash
# What is connected to your relay: totals, how many are relays or authorities, and addresses with more than
# two connections. Works on its own, with or without the other scripts. Needs only `conntrack`.
# SPDX-License-Identifier: MIT
. "$(dirname "$0")/lib.sh"
command -v conntrack >/dev/null 2>&1 || { echo "Install conntrack (conntrack-tools) first."; exit 1; }
ports=$(read_targets "$HERE/ipv4.txt" | awk '{print $2}' | sort -u | paste -sd'|' -)
touch "$LISTS_DIR/relays-v4.txt" "$LISTS_DIR/authorities-v4.txt"
conntrack -L -p tcp 2>/dev/null | grep ESTABLISHED \
  | { if [ -n "$ports" ]; then grep -E "dport=($ports) "; else cat; fi; } \
  | sed -n 's/^[^ ]* *[0-9]* *[0-9]* *ESTABLISHED src=\([0-9a-fA-F.:]*\) .*/\1/p' > "$LISTS_DIR/.ct" || true
total=$(wc -l < "$LISTS_DIR/.ct")
rel=$(grep -Fxc -f "$LISTS_DIR/relays-v4.txt" "$LISTS_DIR/.ct" || true)
auth=$(grep -Fxc -f "$LISTS_DIR/authorities-v4.txt" "$LISTS_DIR/.ct" || true)
echo "Established connections: $total   from relays: ${rel:-0}   from directory authorities: ${auth:-0}"
echo "Addresses with more than two connections (fewest first):"
sort "$LISTS_DIR/.ct" | uniq -c | awk '$1>2' | sort -n
