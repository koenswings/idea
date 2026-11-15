#!/usr/bin/env python3
"""Zero-AI-cost Zimbabwe kit watcher (idea#288, hub service idea#484).

Posts to the routine webhook ONCE per device, on that device's first Online in the tailnet.
Run by the systemd --user timer kit-watch.timer (oneshot kit-watch.service), as pi.

Paths (all optional; the defaults are what the hub uses):
  KIT_WATCH_HOME              state dir: state.json, watch.log, DISABLED   (default ~/kit-watch)
  KIT_WATCH_ENV               secrets file, mode 600                       (default ~/.config/kit-watch/env)
  KIT_WATCH_TAILSCALE         tailscale CLI                                (default: tailscale on PATH)
  KIT_WATCH_TAILSCALE_SOCKET  tailscaled socket; unset = the CLI default   (the hub uses the system tailscaled)
Secrets read from KIT_WATCH_ENV (never logged): KIT_WEBHOOK_URL, KIT_WEBHOOK_KEY.
"""
import json, os, shlex, subprocess, sys, urllib.request, urllib.error, datetime, fcntl
from zoneinfo import ZoneInfo

D = os.environ.get("KIT_WATCH_HOME") or os.path.expanduser("~/kit-watch")
STATE = f"{D}/state.json"; LOG = f"{D}/watch.log"; DISABLED = f"{D}/DISABLED"
ENVF = os.environ.get("KIT_WATCH_ENV") or os.path.expanduser("~/.config/kit-watch/env")
TS = os.environ.get("KIT_WATCH_TAILSCALE") or "tailscale"
SOCK = os.environ.get("KIT_WATCH_TAILSCALE_SOCKET") or ""
DEVICES = {"sunny-robin": "engine", "happy-zebra": "engine", "kind-panda": "engine",
           "sunny-robin-router": "router", "happy-zebra-router": "router", "kind-panda-router": "router"}
DOMAIN = ".tail2d60.ts.net."
BXL = ZoneInfo("Europe/Brussels")
DRY = "--dry-run" in sys.argv


def now(): return datetime.datetime.now(BXL).isoformat(timespec="seconds")


def log(m):
    try:
        if os.path.exists(LOG) and os.path.getsize(LOG) > 1_000_000: os.replace(LOG, LOG + ".1")
        with open(LOG, "a") as f: f.write(f"{now()} {m}\n")
    except Exception: pass
    if DRY: print(m)


def env(path=None):
    """KEY=VALUE lines, shell-style quoting allowed. Parsed in-process (shlex), so values
    never appear on a command line (the old version ran `bash -c printf` per value)."""
    e = {}
    with open(path or ENVF) as f:
        for l in f:
            l = l.strip()
            if not l or l.startswith("#"): continue
            if l.startswith("export "): l = l[7:].lstrip()
            k, _, v = l.partition("=")
            if k: e[k.strip()] = "".join(shlex.split(v))
    return e


def tailscale_peers():
    cmd = [TS] + ([f"--socket={SOCK}"] if SOCK else []) + ["status", "--json"]
    out = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    return json.loads(out.stdout).get("Peer", {}).values()


def main():
    os.makedirs(D, exist_ok=True)
    if os.path.exists(DISABLED) and not DRY: return
    lock = open(f"{D}/.lock", "w"); fcntl.flock(lock, fcntl.LOCK_EX)
    st = json.load(open(STATE)) if os.path.exists(STATE) else {"devices": {d: {"kind": k, "seenAt": None} for d, k in DEVICES.items()}}
    try:
        peers = tailscale_peers()
    except Exception as ex:
        log(f"ERROR tailscale status: {type(ex).__name__}"); return
    # match by exact MagicDNS name (hostnames like atlas-box repeat; DNS names are unique)
    by = {p.get("DNSName", ""): p for p in peers}
    st["lastCheck"] = now()
    for dev, kind in DEVICES.items():
        p = by.get(dev + DOMAIN); s = st["devices"][dev]
        if s["seenAt"]: continue
        if not s.get("detectedAt"):
            if not p or not p.get("Online"): continue
            s["detectedAt"] = now(); s["tailscaleIP"] = (p.get("TailscaleIPs") or [None])[0]
        if not (7 <= datetime.datetime.now(BXL).hour <= 23):
            log(f"QUEUED {dev} (quiet hours 00-07)"); continue
        seen = s["detectedAt"]
        already = [d for d, x in st["devices"].items() if x["seenAt"]]
        remaining = [d for d in DEVICES if d != dev and d not in already]
        payload = {"type": "kit-device", "device": dev, "kind": kind, "tailscaleIP": s.get("tailscaleIP"),
                   "seenAt": seen, "alreadySeen": already, "remaining": remaining}
        if DRY:
            s.pop("detectedAt", None); print("WOULD POST:", json.dumps(payload)); continue
        try:
            e = env()
            req = urllib.request.Request(e["KIT_WEBHOOK_URL"], data=json.dumps(payload).encode(), method="POST",
                  headers={"Content-Type": "application/json", "Authorization": f"Bearer {e['KIT_WEBHOOK_KEY']}"})
            with urllib.request.urlopen(req, timeout=30) as r: code = r.status
            log(f"POSTED {dev} -> HTTP {code}")
            if 200 <= code < 300:
                s["seenAt"] = seen; s["tailscaleIP"] = payload["tailscaleIP"]
        except urllib.error.HTTPError as ex: log(f"POST {dev} failed HTTP {ex.code} (will retry next run)")
        except Exception as ex: log(f"POST {dev} failed {type(ex).__name__} (will retry next run)")
    if not DRY:
        with open(STATE + ".tmp", "w") as f: json.dump(st, f, indent=1)
        os.replace(STATE + ".tmp", STATE)
        if all(x["seenAt"] for x in st["devices"].values()):
            # All seen: stop for good. The timer keeps firing, but every run returns at the
            # DISABLED check above (the old cron version removed its own crontab line instead).
            with open(DISABLED, "w") as f: f.write(now())
            log("All 6 seen; disabling.")
    else:
        for d in DEVICES:
            p = by.get(d + DOMAIN)
            print(f"{d}: {'ONLINE' if p and p.get('Online') else 'offline' if p else 'NOT IN TAILNET'} ip={p and p['TailscaleIPs'][0]} seenAt={st['devices'][d]['seenAt']}")


if __name__ == "__main__":
    main()
