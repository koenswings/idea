# upgrade-tailscale — USB Upgrade Package

Adds Tailscale remote support capability to existing field Engine Pis.

## Contents

| File | Purpose |
|---|---|
| `install.sh` | Runs on the Pi to install Tailscale and the activation script |
| `tailscale_<version>_arm64.tgz` | Tailscale binaries (download separately — see below) |
| `tailscaled.service` | Systemd service definition |
| `debug-authkey` | IDEA Tailnet auth key (added by Koen before distributing USB) |
| `tailscale-debug-activate.sh` | Installed to `/usr/local/bin/` on the Pi |

## Preparing a USB drive (Koen / IDEA technical staff)

```bash
# 1. Download Tailscale ARM64 static binary
TSVER=$(curl -s https://pkgs.tailscale.com/stable/ | grep -oP 'tailscale_\K[\d.]+(?=_arm64.tgz)' | head -1)
curl -L "https://pkgs.tailscale.com/stable/tailscale_${TSVER}_arm64.tgz" \
     -o tailscale_${TSVER}_arm64.tgz

# 2. Copy the debug-authkey from the Tailscale admin console
#    (reusable ephemeral key, tag:school-pi — see platform/keys.md)
echo "<your-auth-key>" > debug-authkey

# 3. Copy all files to a USB drive:
#    install.sh, tailscale_*.tgz, tailscaled.service,
#    debug-authkey, tailscale-debug-activate.sh

# 4. Test on Koen's Pi before distributing (see design doc Part 5)
```

## Field use (coordinator)

See `field/tailscale-debug-upgrade-tapiwa.md` in the programme manager workspace.
