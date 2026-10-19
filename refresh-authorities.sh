#!/usr/bin/env bash
# Daily (cron): refresh the lists of authorities, relays and multi-instance relays, and reload the ipsets.
# SPDX-License-Identifier: MIT
. "$(dirname "$0")/lib.sh"; need_root
for f in authorities-v4:5 authorities-v6:4 2-or:1 2-or-v6:1 above2-or:1 above2-or-v6:1 above1-or:1 above1-or-v6:1 relays-v4:1000 relays-v6:500; do
  fetch_list "${f%%:*}" "${f##*:}"
done
load_all_sets
echo "Lists refreshed."
