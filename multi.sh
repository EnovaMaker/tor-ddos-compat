#!/usr/bin/env bash
# Run after each reboot: ipsets and rules do not survive one. Restores the block lists saved by update.sh.
# SPDX-License-Identifier: MIT
D="$(cd "$(dirname "$0")" && pwd)"
[ -s "$D/ipsets.saved" ] && ipset restore -exist < "$D/ipsets.saved" 2>/dev/null
exec "$D/rules.sh"
