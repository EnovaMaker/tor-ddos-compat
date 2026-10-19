#!/usr/bin/env bash
# Refresh rules and lists without a reboot. Block lists are saved and restored, so nobody gets a second chance.
# Also writes update-rules.sh: the rules in plain text, for review (it will not survive a reboot).
# SPDX-License-Identifier: MIT
. "$(dirname "$0")/lib.sh"; need_root
ipset save > "$HERE/ipsets.saved" 2>/dev/null
"$HERE/refresh-authorities.sh" >/dev/null
"$HERE/multi.sh"
{
  echo "#!/usr/bin/env bash"
  echo "# Plain-text copy of the rules currently in force. For review only."
  iptables -t mangle -S $CHAIN 2>/dev/null
  ip6tables -t mangle -S $CHAIN 2>/dev/null
  iptables -S TORDDOS-IN 2>/dev/null
} | sed 's/^-/# -/' > "$HERE/update-rules.sh"
echo "Updated. Rules for review: $HERE/update-rules.sh"
