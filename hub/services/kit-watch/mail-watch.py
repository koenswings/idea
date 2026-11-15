#!/usr/bin/env python3
"""Zero-AI support-mail watcher (hub service idea#484).

Posts {type,count,newestReceived} (no content) to the routine webhook for new message ids only.
Run by the systemd --user timer kit-watch.timer (oneshot kit-watch.service), as pi.

Paths and endpoints (all optional; the defaults are what the hub uses):
  KIT_WATCH_HOME       state dir: mail-state.json, watch.log    (default ~/kit-watch)
  KIT_WATCH_ENV        secrets file, mode 600                   (default ~/.config/kit-watch/env)
  MAIL_WATCH_INBOX     inbox to watch                           (default idea-support@agentmail.to)
  MAIL_WATCH_API_BASE  AgentMail API base (tests point it at a fake server; default https://api.agentmail.to)
Secrets read from KIT_WATCH_ENV (never logged): AGENTMAIL_API_KEY, KIT_WEBHOOK_URL, KIT_WEBHOOK_KEY.
Flags: --dry-run (print, change nothing), --init (mark every current message as seen).
"""
import json, os, shlex, sys, urllib.request, urllib.error, urllib.parse, datetime, fcntl
from zoneinfo import ZoneInfo

D = os.environ.get("KIT_WATCH_HOME") or os.path.expanduser("~/kit-watch")
STATE = f"{D}/mail-state.json"; LOG = f"{D}/watch.log"
ENVF = os.environ.get("KIT_WATCH_ENV") or os.path.expanduser("~/.config/kit-watch/env")
INBOX = os.environ.get("MAIL_WATCH_INBOX") or "idea-support@agentmail.to"
API = (os.environ.get("MAIL_WATCH_API_BASE") or "https://api.agentmail.to").rstrip("/")
DRY = "--dry-run" in sys.argv; INIT = "--init" in sys.argv
BXL = ZoneInfo("Europe/Brussels")


def now(): return datetime.datetime.now(BXL).isoformat(timespec="seconds")


def log(m):
    try:
        if os.path.exists(LOG) and os.path.getsize(LOG) > 1_000_000: os.replace(LOG, LOG + ".1")
        with open(LOG, "a") as f: f.write(f"{now()} [mail] {m}\n")
    except Exception: pass
    if DRY or INIT: print(m)


def env(path=None):
    """KEY=VALUE lines, shell-style quoting allowed; parsed in-process (values never on a command line)."""
    e = {}
    with open(path or ENVF) as f:
        for l in f:
            l = l.strip()
            if not l or l.startswith("#"): continue
            if l.startswith("export "): l = l[7:].lstrip()
            k, _, v = l.partition("=")
            if k: e[k.strip()] = "".join(shlex.split(v))
    return e


def fetch(key):
    msgs = []; tok = None
    for _ in range(20):
        q = {"limit": 100}
        if tok: q["page_token"] = tok
        u = f"{API}/v0/inboxes/{urllib.parse.quote(INBOX)}/messages?" + urllib.parse.urlencode(q)
        with urllib.request.urlopen(urllib.request.Request(u, headers={"Authorization": f"Bearer {key}"}), timeout=20) as r:
            d = json.load(r)
        msgs += d.get("messages", []); tok = d.get("next_page_token")
        if not tok: break
    return msgs


def ts(m): return m.get("timestamp") or m.get("created_at") or m.get("received_at")


def save(st):
    with open(STATE + ".tmp", "w") as f: json.dump(st, f, indent=1)
    os.replace(STATE + ".tmp", STATE)


def main():
    os.makedirs(D, exist_ok=True)
    lock = open(f"{D}/.mail.lock", "w")
    try: fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError: return
    e = env()
    st = json.load(open(STATE)) if os.path.exists(STATE) else None
    try: msgs = fetch(e["AGENTMAIL_API_KEY"])
    except urllib.error.HTTPError as ex:
        if ex.code != 429: log(f"ERROR AgentMail HTTP {ex.code}")
        return
    except Exception as ex: log(f"ERROR AgentMail {type(ex).__name__}"); return
    ids = {m.get("message_id") for m in msgs if m.get("message_id")}
    if st is None or INIT:
        st = {"seen": sorted(ids), "pending": [], "installedAt": now()}
        save(st); log(f"init: {len(ids)} existing messages marked seen"); return
    seen = set(st["seen"]); pend = {p["id"]: p for p in st["pending"]}
    for m in msgs:
        i = m.get("message_id")
        if i and i not in seen and i not in pend: pend[i] = {"id": i, "received": ts(m)}
    st["lastCheck"] = now()
    if pend and 7 <= datetime.datetime.now(BXL).hour <= 23:
        newest = max((p["received"] or "" for p in pend.values()), default=None)
        try: newest = datetime.datetime.fromisoformat(newest.replace("Z", "+00:00")).astimezone(BXL).isoformat(timespec="seconds")
        except Exception: pass
        payload = {"type": "support-mail", "count": len(pend), "newestReceived": newest}
        if DRY: print("WOULD POST:", json.dumps(payload))
        else:
            try:
                req = urllib.request.Request(e["KIT_WEBHOOK_URL"], data=json.dumps(payload).encode(), method="POST",
                    headers={"Content-Type": "application/json", "Authorization": f"Bearer {e['KIT_WEBHOOK_KEY']}"})
                with urllib.request.urlopen(req, timeout=30) as r: code = r.status
                log(f"POSTED support-mail count={len(pend)} -> HTTP {code}")
                if 200 <= code < 300: seen |= set(pend); pend = {}
            except urllib.error.HTTPError as ex: log(f"POST failed HTTP {ex.code} (retry next run)")
            except Exception as ex: log(f"POST failed {type(ex).__name__} (retry next run)")
    elif pend: log(f"QUEUED {len(pend)} new mail(s) (quiet hours)")
    elif DRY: print(f"no new messages ({len(ids)} in inbox, {len(seen)} seen)")
    if not DRY:
        st["seen"] = sorted(seen); st["pending"] = list(pend.values()); save(st)


if __name__ == "__main__":
    main()
