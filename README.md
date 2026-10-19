# tor-ddos-compat

**Connection limits for a Tor relay's ORPort on any Debian or Ubuntu box, with the same commands
the stopped `tor-ddos` scripts had.** Independent reimplementation; no code from that project.

```sh
bash <(curl -Ls https://raw.githubusercontent.com/EnovaMaker/tor-ddos-compat/main/download.sh)
```

## If you used `Enkidu-6/tor-ddos`

That project was shut down in May 2026 and its relay lists went with it, so the scripts now run
against lists that are no longer updated. **Moving over takes one command:** run the line above from
the directory where you ran the old one. It finds your `ipv4.txt`, offers to reuse your addresses
and ports, installs the scripts into `./tor`, and applies the rules.

| You used to run | Now |
|---|---|
| `download.sh` | same, from the URL above |
| `multi.sh` after each reboot | same |
| `update.sh` | same: saves and restores the block lists, writes `update-rules.sh` |
| `refresh-authorities.sh` in cron | same |
| `compare.sh`, `remove.sh`, `remove-dual-or.sh` | same |
| `conntrack.sh` | same, and still works on its own |
| `ipset -L tor-<ip>-<port>` | same set names: `tor-<ip>-<port>`, `allow-list`, `4-or`, `dual-or` |

The relay lists come from [`tor-relay-lists`](https://github.com/EnovaMaker/tor-relay-lists), which
keeps the old file names: if you read the old lists yourself, change `Enkidu-6` to `EnovaMaker` in
the URL and nothing else.

## What it does

One connection per address to your ORPort; relays running several Tor instances on one address get
two. An address that keeps asking after being refused is blocked for 12 hours, and what it already
held open gets a TCP reset. Directory authorities and anything in `allow-extra.txt` are never
touched. Rules live in the `mangle` table's `PREROUTING` chain, ahead of connection handling.

Needs `iptables`, `ipset` and `curl`; on Debian and Ubuntu it installs what is missing.

## What is different, on purpose

- **Your own firewall is left alone.** The scripts use their own chains (`TORDDOS` in `mangle`,
  `TORDDOS-IN` in `INPUT`) and never flush the table.
- **What triggers the block.** A source held to one connection can never open a third, so
  "a third open connection" cannot be the trigger. Here it is *repeated refusals*: more than ten
  refused attempts, then more than ten per minute.
- **Snowflake.** The consensus does not list Snowflake servers, so there is no list for them yet.
  Put their addresses in `allow-extra.txt`, one per line.
- **Kernel settings** (`tcp_fin_timeout`, SYN cookies, port range, SYN backlog) are applied at run
  time only. Make them permanent in `/etc/sysctl.d/` if you want them to survive a reboot.

## Verification

`nix build .#checks.x86_64-linux.compat -L` boots a relay and two clients and runs the real scripts:
the one-command install, the one-connection limit, the block and the reset, the allow list,
`compare.sh` and `remove.sh`, `update.sh` keeping the block list, and `conntrack.sh`.

## Status

Not production-tested. **Not yet tried against a real old `ipv4.txt`:** it is read tolerantly
(an address, then ports on the same line), but I have only seen the format described, not a file.
If yours is not picked up, `download.sh` asks for the address and ports again.

Independent of the Tor Project and of the author of `tor-ddos`. Written from that project's public
README and release notes, never its scripts (the repository carries no licence). MIT.
