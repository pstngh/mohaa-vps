# MOHAA server as a systemd service (Debian 13)

This replaces the old `screen` + init-style scripts (`gsload.sh`, `gs.sh`) with a
native **systemd** service. systemd handles all three things you wanted:

| Old way | New way |
|---|---|
| `gs.sh` — `while true` loop that relaunches on crash | `Restart=always` + `RestartSec=2` |
| `gsload.sh` — `screen -d -m` to background it | systemd runs & supervises the process |
| Manually running `gsload.sh start` at boot | `systemctl enable` (starts at boot) |
| `server.log` written by the loop | `journalctl` (the systemd journal) |

You no longer need `screen`, `gs.sh`, or `gsload.sh`.

## Install

1. Copy the unit file into place (needs root):

   ```bash
   sudo cp mohaa.service /etc/systemd/system/mohaa.service
   ```

2. Make sure `omohaaded` is executable and owned by the `debian` user:

   ```bash
   chmod +x /home/debian/moh/omohaaded
   ```

3. Reload systemd, enable at boot, and start now:

   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable --now mohaa.service
   ```

   (`enable` = start at boot, `--now` = also start immediately. That single
   command replaces both `gsload.sh start` and adding it to boot.)

## Everyday commands

These replace `gsload.sh {start|stop|restart}`:

```bash
sudo systemctl start mohaa      # start
sudo systemctl stop mohaa       # stop (systemd kills it cleanly, no more grep+kill)
sudo systemctl restart mohaa    # restart
sudo systemctl status mohaa     # is it running? last exit code, recent log lines
```

## Watching the logs (replaces `tail -f server.log`)

```bash
journalctl -u mohaa -f          # live follow
journalctl -u mohaa -n 200      # last 200 lines
journalctl -u mohaa --since "1 hour ago"
```

The game also still writes its own log inside `/home/debian/moh` because of
`+set logfile 2` in the launch line — that's unchanged.

## Firewall

The server listens on two **UDP** ports (from the launch line):

| Port | Purpose |
|---|---|
| `12203/udp` | Game traffic (`+set net_port 12203`) |
| `12300/udp` | Server browser / query (`+set net_queryport 12300`) |

Run a firewall with a default-deny-inbound policy. `ufw` is the simplest choice
and still uses the modern nftables backend under the hood:

```bash
sudo apt update && sudo apt install -y ufw
sudo ufw allow 22/tcp
sudo ufw allow 12203/udp
sudo ufw allow 12300/udp
sudo ufw enable
```

> ⚠️ Allow `22/tcp` **before** running `ufw enable`, or you'll lock yourself out
> of SSH.

Verify the resulting policy:

```bash
sudo ufw status verbose
```

You should see `deny (incoming)`, `allow (outgoing)`, and the three allow rules
above. Note: this is UDP, not TCP — opening `12203/tcp` does nothing for this
server. If you're on a VPS, also open the same two UDP ports in your provider's
cloud firewall (control panel), which is separate from the OS firewall.

## Notes / tuning

- **User:** the service runs as `debian`, not root. Adjust `User=`/`Group=` and
  the paths if your install lives elsewhere.
- **Crash-loop protection:** `StartLimitIntervalSec=0` means systemd will keep
  restarting forever, exactly like the old `while true` loop. If you'd rather it
  stop after repeated instant crashes (so a broken config doesn't spin forever),
  delete that line — the default is 5 restarts within 10s before it gives up,
  and you'd clear the failed state with `systemctl reset-failed mohaa`.
- **`network-online.target`:** the server waits for the network to be up before
  starting at boot, so it can bind port 12203.
- **Multiple servers:** copy the unit to `mohaa-ffa.service`,
  `mohaa-tdm.service`, etc., each with its own `net_port` / `net_queryport` and
  `Description`, then `enable --now` each one.
