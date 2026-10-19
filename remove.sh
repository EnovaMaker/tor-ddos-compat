#!/usr/bin/env bash
# Release every Tor relay from the block list. Suitable for cron.
# SPDX-License-Identifier: MIT
. "$(dirname "$0")/lib.sh"; need_root
[ -s "$LISTS_DIR/relays-v4.txt" ] || exit 0
touch "$LISTS_DIR/relays-v6.txt"
for s in $(ipset list -n | grep -E '^tor6?-'); do
  ipset list "$s" | sed -n '/^Members:/,$p' | tail -n +2 | awk '{print $1}' \
    | grep -Fx -f "$LISTS_DIR/relays-v4.txt" -f "$LISTS_DIR/relays-v6.txt" \
    | while read -r a; do ipset del "$s" "$a" 2>/dev/null; done
done
exit 0
