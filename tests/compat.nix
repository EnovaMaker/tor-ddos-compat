# SPDX-License-Identifier: MIT
# Two clients and a relay, running the real scripts end to end: the one-command install, the
# one-connection limit, the 12-hour block, the reset of what a blocked source held, the
# allow list, compare/remove, and update keeping the block list.
{ pkgs, src }:

let
  scenario = pkgs.writeText "scenario.py" ''
    import json, socket, sys
    addr, port, want, extra = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])

    def connect():
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(1.5)
        try:
            s.connect((addr, port))
            return s
        except OSError:
            s.close()
            return None

    held, got, refused = [], [], []
    for _ in range(want):
        s = connect(); got.append(s is not None)
        if s: held.append(s)
    for _ in range(extra):
        s = connect(); refused.append(s is not None)
        if s: held.append(s)
    reset = None
    if held:
        try:
            held[0].send(b"x"); held[0].settimeout(3)
            reset = (held[0].recv(10) == b"")
        except (ConnectionResetError, BrokenPipeError):
            reset = True
        except OSError:
            reset = False
    print(json.dumps({"wanted": got, "extra": refused, "old_connection_reset": reset}))
  '';

  client = { pkgs, ... }: { environment.systemPackages = [ pkgs.python3 ]; };
in
pkgs.testers.runNixOSTest {
  name = "tor-ddos-compat";

  nodes = {
    relay = { lib, pkgs, ... }: {
      networking.firewall.enable = false;
      environment.systemPackages = with pkgs; [ iptables ipset conntrack-tools curl bash gawk gnugrep coreutils findutils ];
      boot.kernelModules = [ "ip_set" "ip_set_hash_ip" "xt_set" "xt_connlimit" "xt_hashlimit" "xt_conntrack" ];
      # Holds each connection open: the scripts count concurrent connections.
      systemd.services.fake-orport = {
        wantedBy = [ "multi-user.target" ];
        serviceConfig.ExecStart =
          "${lib.getExe' pkgs.socat "socat"} TCP-LISTEN:19001,fork,reuseaddr SYSTEM:'sleep 300'";
      };
    };
    client = client;
    clientb = client;
  };

  testScript = ''
    import json

    start_all()
    relay.wait_for_unit("multi-user.target")
    relay.wait_for_open_port(19001)
    client.wait_for_unit("multi-user.target")
    clientb.wait_for_unit("multi-user.target")

    rip = relay.succeed("ip -4 -o addr show dev eth1 | awk '{print $4}' | cut -d/ -f1").strip()
    cip = client.succeed("ip -4 -o addr show dev eth1 | awk '{print $4}' | cut -d/ -f1").strip()
    bip = clientb.succeed("ip -4 -o addr show dev eth1 | awk '{print $4}' | cut -d/ -f1").strip()
    print(rip, cip, bip)

    # A published feed, as a local directory. Layout and names as on the real one.
    relay.succeed("mkdir -p /srv/feed")
    relay.succeed(f"printf '10.0.0.1\\n10.0.0.2\\n10.0.0.3\\n10.0.0.4\\n{bip}\\n' > /srv/feed/authorities-v4.txt")
    relay.succeed("printf '2001:db8::1\\n2001:db8::2\\n2001:db8::3\\n2001:db8::4\\n' > /srv/feed/authorities-v6.txt")
    for n in ["2-or", "2-or-v6", "above2-or", "above2-or-v6", "above1-or", "above1-or-v6"]:
        relay.succeed(f"printf '10.9.9.9\\n' > /srv/feed/{n}.txt" if "v6" not in n else f"printf '2001:db8:9::9\\n' > /srv/feed/{n}.txt")
    relay.succeed(f"(seq 1 1100 | sed 's/^/10.8.0./;s/\\.\\([0-9]*\\)$/.\\1/' ; echo {cip}) > /srv/feed/relays-v4.txt")
    relay.succeed("(seq 1 600 | sed 's/^/2001:db8:8::/') > /srv/feed/relays-v6.txt")

    env = f"TORDDOS_LOCAL_SRC=${src} TORDDOS_LISTS_URL=file:///srv/feed/ TORDDOS_IPV4={rip} TORDDOS_PORTS=19001"

    with subtest("the one-command install runs and applies the rules"):
        relay.succeed(f"mkdir -p /root/w && cd /root/w && {env} bash ${src}/download.sh")
        sets = relay.succeed("ipset list -n")
        for s in [f"tor-{rip}-19001", "allow-list", "dual-or", "4-or"]:
            assert s in sets, (s, sets)
        assert "19001" in relay.succeed("iptables -t mangle -S TORDDOS")

    with subtest("the authorities list fills the allow list"):
        assert bip in relay.succeed("ipset list allow-list")
        assert "193.187.88.46" in relay.succeed("ipset list allow-list"), "snowflake.txt not loaded"
        assert "2a0c:dd40:1:b::46" in relay.succeed("ipset list allow-list-v6 || true"), "snowflake v6 not loaded"

    def run(m, want, extra):
        return json.loads(m.succeed(f"python3 ${scenario} {rip} 19001 {want} {extra}"))

    with subtest("an ordinary source keeps one connection and the rest are refused"):
        r = run(client, 1, 1)
        assert r["wanted"] == [True] and r["extra"] == [False], r

    with subtest("a source that keeps asking is blocked, and what it held is reset"):
        client.succeed("sleep 2")
        r = run(client, 1, 14)
        assert r["wanted"] == [True] and not any(r["extra"]), r
        assert r["old_connection_reset"] is True, r
        assert cip in relay.succeed(f"ipset list tor-{rip}-19001")

    with subtest("a blocked source stays blocked with nothing open"):
        r = run(client, 1, 0)
        assert r["wanted"] == [False], r

    with subtest("an allowed source is never limited"):
        r = run(clientb, 6, 0)
        assert all(r["wanted"]), r

    with subtest("compare.sh lists the relay caught in the block list; remove.sh releases it"):
        out = relay.succeed("cd /root/w/tor && echo 3 | ./compare.sh")
        assert cip in out and "Relays in the block list: 1" in out, out
        relay.succeed("cd /root/w/tor && ./remove.sh")
        assert cip not in relay.succeed(f"ipset list tor-{rip}-19001")

    with subtest("update.sh keeps the block list"):
        r = run(client, 1, 14)   # blocked again
        assert cip in relay.succeed(f"ipset list tor-{rip}-19001")
        relay.succeed("cd /root/w/tor && TORDDOS_LISTS_URL=file:///srv/feed/ ./update.sh")
        assert cip in relay.succeed(f"ipset list tor-{rip}-19001")
        assert "update-rules.sh" in relay.succeed("ls /root/w/tor")

    with subtest("conntrack.sh reports on its own"):
        out = relay.succeed("cd /root/w/tor && ./conntrack.sh")
        assert "Established connections" in out, out
  '';
}
