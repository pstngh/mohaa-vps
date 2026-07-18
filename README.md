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

The `blocklist-update.sh` script and the `ipfilter.cfg` list both live in this
repo, so clone it once and run everything from there.

Install nftables (the `nft` command isn't on the box by default) and clone the
repo:

```bash
sudo apt install -y nftables git
cd /home/debian
git clone https://github.com/pstngh/mohaa-vps.git
```

Build + load the blocklist from the repo:

```bash
sudo bash /home/debian/mohaa-vps/blocklist-update.sh /home/debian/mohaa-vps/ipfilter.cfg
```

Install the boot service (reloads the blocklist on every boot):

```bash
sudo cp /home/debian/mohaa-vps/mohaa-blocklist.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable mohaa-blocklist.service
```

Check it's active:

```bash
sudo nft list set inet mohaa_blocklist blocked | head
```

You should see a list of blocked CIDR ranges.

**When the ban list changes:** update `ipfilter.cfg` and re-run the script:

```bash
cd /home/debian/mohaa-vps && git pull
sudo bash /home/debian/mohaa-vps/blocklist-update.sh /home/debian/mohaa-vps/ipfilter.cfg
```

It reloads atomically — no restart needed.

> The drop is scoped to the game ports (12203/12300 UDP), so it can't lock you
> out of SSH even if you connect from a listed range. To block those IPs from
> *everything* instead, remove the `udp dport { ... }` line from
> `blocklist-update.sh` and re-run it.

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
