# MOHAA server (systemd, Debian 13)

Runs the MOHAA dedicated server under systemd: starts at boot, auto-restarts on
crash, logs to the journal. Server lives in `/home/debian/moh`.

## 1. Install + start

```bash
chmod +x /home/debian/moh/omohaaded
sudo tee /etc/systemd/system/mohaa.service > /dev/null <<'EOF'
[Unit]
Description=MOHAA Dedicated Server (FFA, port 12203)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=debian
Group=debian
WorkingDirectory=/home/debian/moh
ExecStart=/home/debian/moh/omohaaded +set com_target_game 0 +set net_port 12203 +set developer 1 +set logfile 2 +set net_queryport 12300 +exec server_opm.cfg
Restart=always
RestartSec=2
StartLimitIntervalSec=0
StandardOutput=journal
StandardError=journal
SyslogIdentifier=mohaa

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now mohaa.service
sudo systemctl status mohaa --no-pager
```

Look for `Active: active (running)`.

## 2. Firewall (once)

```bash
sudo apt update && sudo apt install -y ufw
sudo ufw allow 22/tcp
sudo ufw allow 12203/udp
sudo ufw allow 12300/udp
sudo ufw enable
```

## 3. IP blocklist (ban list via nftables)

`ipfilter.cfg` is a ~5,600-entry ban list (wildcard format). ufw can't handle a
list that size, so the blocklist runs as an nftables set that drops those IPs on
the game ports. It coexists with the ufw rules from step 2.

Install once (the `nft` command isn't on the box by default):

```bash
sudo apt install -y nftables
```

Create the updater script (converts the wildcard list to nftables + loads it):

```bash
sudo tee /usr/local/sbin/mohaa-blocklist-update.sh > /dev/null <<'EOF'
#!/bin/bash
set -euo pipefail
SRC="${1:-/home/debian/moh/main/ipfilter.cfg}"
OUT="/etc/nftables.d/mohaa-blocklist.nft"
GAME_PORTS="12203, 12300"
[[ -f "$SRC" ]] || { echo "ipfilter source not found: $SRC" >&2; exit 1; }
mkdir -p "$(dirname "$OUT")"
elements=$(awk '
  { gsub(/[ \t\r]/, "") }
  /^$/ { next }
  /^#/ { next }
  {
    n = split($0, a, ".")
    if (n != 4) next
    if (a[1]=="*") next
    if (a[2]=="*") { print a[1]".0.0.0/8";            next }
    if (a[3]=="*") { print a[1]"."a[2]".0.0/16";      next }
    if (a[4]=="*") { print a[1]"."a[2]"."a[3]".0/24"; next }
    print $0"/32"
  }' "$SRC" | paste -sd, -)
count=$(printf '%s' "$elements" | tr ',' '\n' | grep -c .)
tee "$OUT" > /dev/null <<NFT
table inet mohaa_blocklist {}
delete table inet mohaa_blocklist
table inet mohaa_blocklist {
	set blocked {
		type ipv4_addr
		flags interval
		auto-merge
		elements = { $elements }
	}
	chain input {
		type filter hook input priority -150; policy accept;
		udp dport { $GAME_PORTS } ip saddr @blocked drop
	}
}
NFT
nft -f "$OUT"
echo "Loaded $count blocked ranges."
EOF
sudo chmod +x /usr/local/sbin/mohaa-blocklist-update.sh
```

Make it reload at boot:

```bash
sudo tee /etc/systemd/system/mohaa-blocklist.service > /dev/null <<'EOF'
[Unit]
Description=MOHAA firewall blocklist (nftables set)
After=network-pre.target ufw.service
Wants=network-pre.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/nft -f /etc/nftables.d/mohaa-blocklist.nft
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable mohaa-blocklist.service
```

Now build + load the blocklist (point it at your `ipfilter.cfg` — change the
path if yours lives elsewhere):

```bash
sudo /usr/local/sbin/mohaa-blocklist-update.sh /home/debian/moh/main/ipfilter.cfg
```

Check it's active:

```bash
sudo nft list set inet mohaa_blocklist blocked | head
```

**When the ban list changes:** edit `ipfilter.cfg`, then re-run
`sudo /usr/local/sbin/mohaa-blocklist-update.sh <path>` — it reloads atomically.

> The drop is scoped to the game ports (12203/12300 UDP), so it can't lock you
> out of SSH even if you connect from a listed range. To block those IPs from
> *everything* instead, remove the `udp dport { ... }` part of the rule in the
> script.

## 4. Daily use

```bash
sudo systemctl start mohaa
sudo systemctl stop mohaa
sudo systemctl restart mohaa
sudo systemctl status mohaa
journalctl -u mohaa -f     # live logs, Ctrl-C to quit
```

## 5. Change launch options

Re-paste the block in step 1 with your new options (it overwrites the file),
then `sudo systemctl restart mohaa`.
