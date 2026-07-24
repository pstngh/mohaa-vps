# MOHAA server (systemd, Debian 13)

Runs the MOHAA dedicated server under systemd: starts at boot, auto-restarts on
crash, logs to the journal. Server lives in `/home/debian/moh`.

## 0. First-time VPS setup (fresh box)

Skip this if you already have a non-root `debian` user with sudo. On a brand-new
VPS you usually start as `root` with nothing installed.

**As `root`** — update, install sudo, create the `debian` user:

```bash
apt update && apt -y upgrade
apt -y install sudo git
adduser debian                 # prompts for a password; creates /home/debian
usermod -aG sudo debian        # give it sudo
```

**From your Mac** — set up key login for the new user, then log in as it:

```bash
ssh-copy-id debian@YOUR_VPS_IP
ssh debian@YOUR_VPS_IP
```

Confirm sudo works (should print `root`):

```bash
sudo whoami
```

**(Recommended) disable direct root SSH** — only after `ssh debian@...` works:

```bash
sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sudo systemctl restart ssh
```

**Get the game files to `/home/debian/moh`.** Copy from your Mac (or old box):

```bash
scp -r ~/path/to/moh debian@YOUR_VPS_IP:/home/debian/
```

If the folder ended up in the wrong place or owned by root, move it and fix
ownership in one go (adjust the source path):

```bash
sudo mv /home/moh /home/debian/moh
sudo chown -R debian:debian /home/debian/moh
sudo chmod +x /home/debian/moh/omohaaded
ls -ld /home/debian/moh        # should show: debian debian
```

Everything below assumes you are logged in as `debian` with the game in
`/home/debian/moh`.

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

**GitHub converts the list for you.** A GitHub Action
(`.github/workflows/blocklist.yml`) watches `ipfilter.cfg`, converts it to the
ready-to-load `mohaa-blocklist.nft`, validates the syntax, and commits it back.
So the server never runs the conversion — it just copies the validated file and
loads it.

The server only ever needs the finished `mohaa-blocklist.nft` — not the repo,
not the converter. Grab just that file with a throwaway shallow clone, load it,
and delete the clone.

Install nftables (the `nft` command isn't on the box by default) and pull the
built file into place:

```bash
sudo apt install -y nftables git
cd /tmp
git clone --depth 1 https://github.com/pstngh/mohaa-vps.git
sudo mkdir -p /etc/nftables.d
sudo cp /tmp/mohaa-vps/mohaa-blocklist.nft /etc/nftables.d/
sudo cp /tmp/mohaa-vps/mohaa-blocklist.service /etc/systemd/system/
rm -rf /tmp/mohaa-vps
sudo systemctl daemon-reload
sudo systemctl enable --now mohaa-blocklist.service
```

Check it's active:

```bash
sudo nft list set inet mohaa_blocklist blocked | head
```

You should see a list of blocked CIDR ranges.

**When the ban list changes:** edit `ipfilter.cfg` in the repo and push (or edit
it on GitHub directly). The Action regenerates and commits `mohaa-blocklist.nft`.
Then pull just the new file onto the server:

```bash
cd /tmp
git clone --depth 1 https://github.com/pstngh/mohaa-vps.git
sudo cp /tmp/mohaa-vps/mohaa-blocklist.nft /etc/nftables.d/
rm -rf /tmp/mohaa-vps
sudo systemctl restart mohaa-blocklist
```

It reloads atomically — no server restart needed.

> The server keeps nothing but `/etc/nftables.d/mohaa-blocklist.nft` and the
> service unit. No permanent clone, no converter script on the box.

> The drop is scoped to the game ports (12203/12300 UDP), so it can't lock you
> out of SSH even if you connect from a listed range. To block those IPs from
> *everything* instead, remove the `udp dport { ... }` line from
> `blocklist-update.sh` in the repo and push — the Action rebuilds the file.

### Turn the blocklist off / on

Off (stays off through reboots; deletes nothing):

```bash
sudo systemctl disable --now mohaa-blocklist.service
sudo nft delete table inet mohaa_blocklist
```

Back on:

```bash
sudo systemctl enable --now mohaa-blocklist.service
```

`disable` stops it loading at boot; `nft delete table` just unloads the live
rules. The `.nft` file and service unit stay on disk, so turning it back on
needs nothing re-downloaded.

## 4. Daily reboot at midnight (Eastern)

Reboots the box every day at 00:00 `America/New_York` (auto-adjusts for
EST/EDT). A systemd timer triggers a reboot service. On reboot the game server
and blocklist come back automatically (both are enabled).

```bash
sudo tee /etc/systemd/system/mohaa-reboot.service > /dev/null <<'EOF'
[Unit]
Description=Scheduled system reboot

[Service]
Type=oneshot
ExecStart=/usr/bin/systemctl reboot
EOF
sudo tee /etc/systemd/system/mohaa-reboot.timer > /dev/null <<'EOF'
[Unit]
Description=Daily reboot at midnight (America/New_York)

[Timer]
OnCalendar=*-*-* 00:00:00 America/New_York
Persistent=false

[Install]
WantedBy=timers.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now mohaa-reboot.timer
systemctl list-timers mohaa-reboot.timer --no-pager
```

The last command shows the next fire time so you can confirm it. To stop the
daily reboot later: `sudo systemctl disable --now mohaa-reboot.timer`.

## 5. Daily use

```bash
sudo systemctl start mohaa
sudo systemctl stop mohaa
sudo systemctl restart mohaa
sudo systemctl status mohaa
journalctl -u mohaa -f     # live logs, Ctrl-C to quit
```

## 6. Change launch options

Re-paste the block in step 1 with your new options (it overwrites the file),
then `sudo systemctl restart mohaa`.
