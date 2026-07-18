# MOHAA server as a systemd service (Debian 13)

Replaces the old `screen` + init scripts (`gsload.sh`, `gs.sh`) with a native
**systemd** service. systemd handles startup at boot, crash auto-restart, and
logging — no more `screen`, no `while true` loop, no `kill`-by-grep.

| Old way | New way |
|---|---|
| `gs.sh` — `while true` loop that relaunches on crash | `Restart=always` + `RestartSec=2` |
| `gsload.sh` — `screen -d -m` to background it | systemd runs & supervises the process |
| Running `gsload.sh start` at boot | `systemctl enable` (starts at boot) |
| `server.log` written by the loop | `journalctl` (the systemd journal) |

Every step below is copy-pasteable straight into PuTTY. Server lives in
`/home/debian/moh`, runs as user `debian`.

---

## 1. Install + start the service

Paste this whole block. It writes the unit file, enables it at boot, and starts
it now:

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

The `<<'EOF'` is quoted on purpose so the shell writes the `+set` args literally
instead of trying to expand them.

You should see `Active: active (running)`. Done — it's live and will start on
every boot.

---

## 2. Firewall (do this once)

The box has no firewall by default. Lock it down to SSH + the two game ports:

```bash
sudo apt update && sudo apt install -y ufw
sudo ufw allow 22/tcp
sudo ufw allow 12203/udp
sudo ufw allow 12300/udp
sudo ufw enable
sudo ufw status verbose
```

> ⚠️ The `22/tcp` line keeps SSH open — it runs before `enable`, so you won't be
> locked out. Don't remove it.

The two game ports are **UDP** (`12203` = game, `12300` = server browser).
Opening them as TCP does nothing. If your VPS provider has its own cloud
firewall in the control panel, open the same two UDP ports there too.

---

## 3. Everyday commands

These replace `gsload.sh {start|stop|restart}`:

```bash
sudo systemctl start mohaa      # start
sudo systemctl stop mohaa       # stop
sudo systemctl restart mohaa    # restart
sudo systemctl status mohaa     # running? recent log lines
```

---

## 4. Logs (replaces `tail -f server.log`)

```bash
journalctl -u mohaa -f              # live follow (Ctrl-C to quit)
journalctl -u mohaa -n 200          # last 200 lines
journalctl -u mohaa --since "1 hour ago"
```

---

## 5. Verify it's healthy

Check it's listening on both UDP ports:

```bash
sudo ss -ulnp | grep omohaaded
```

You should see `0.0.0.0:12203` and `0.0.0.0:12300`.

Prove the auto-restart works — kill it and watch systemd bring it back after 2s
with a new PID:

```bash
sudo systemctl kill mohaa
sleep 3
systemctl status mohaa --no-pager | grep -E 'Active|Main PID'
```

---

## 6. Retire the old setup (optional, once you're happy)

```bash
rm -f /home/debian/moh/gs.sh /home/debian/moh/gsload.sh
sudo apt remove -y screen        # only if nothing else uses screen
```

---

## Changing the launch options later

Edit the `ExecStart=` line, then reload + restart:

```bash
sudo nano /etc/systemd/system/mohaa.service   # edit ExecStart=, save with Ctrl-O, exit Ctrl-X
sudo systemctl daemon-reload
sudo systemctl restart mohaa
```

Or just re-paste the whole block from step 1 with the new options — it
overwrites the file.

---

## Notes

- **Crash-loop:** `StartLimitIntervalSec=0` means systemd retries forever, like
  the old `while true` loop. To make it give up after repeated instant crashes,
  delete that line; clear a failed state with `sudo systemctl reset-failed mohaa`.
- **Boot ordering:** `network-online.target` makes it wait for the network
  before binding the ports at boot.
- **Game's own log:** `+set logfile 2` still writes a log inside
  `/home/debian/moh` — unchanged from before.
- **Harmless script errors:** `Script Error` lines in the log from
  `maps/dm/*.scr` are from the game's map/admin-mod scripts, not the service —
  ignore them.
- **Multiple servers:** copy the step-1 block but change the service name
  (`mohaa-tdm.service`), `Description`, `net_port`, and `net_queryport`, then
  `enable --now` each one.
