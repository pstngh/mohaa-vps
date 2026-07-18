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

## 3. Daily use

```bash
sudo systemctl start mohaa
sudo systemctl stop mohaa
sudo systemctl restart mohaa
sudo systemctl status mohaa
journalctl -u mohaa -f     # live logs, Ctrl-C to quit
```

## Change launch options

Re-paste the block in step 1 with your new options (it overwrites the file),
then `sudo systemctl restart mohaa`.
