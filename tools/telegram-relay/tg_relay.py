#!/usr/bin/env python3
"""IDEA field-support Telegram relay (option (e) of proposal 2026-10-20-telegram-field-support).

Stdlib only. Long-polls Telegram getUpdates (no AI), keeps an allowlist,
mirrors field messages into a per-person topic of Koen's monitor group and
forwards each message to the "Box watcher events" webhook.
"""
import fcntl, json, logging, logging.handlers, os, secrets, sys, time, urllib.error, urllib.parse, urllib.request
from contextlib import contextmanager

HOME = os.path.expanduser("~")
BASE = os.environ.get("TG_RELAY_HOME", os.path.join(HOME, "tg-relay"))
ENV_FILE = os.environ.get("TG_RELAY_ENV", os.path.join(HOME, ".config/tg-relay/env"))
log = logging.getLogger("tg-relay")


def load_env(path=ENV_FILE):
    env = {}
    try:
        for line in open(path, encoding="utf-8"):
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                env[k.strip()] = v.strip().strip('"').strip("'")
    except FileNotFoundError:
        pass
    for k in ("TELEGRAM_BOT_TOKEN", "KIT_WEBHOOK_URL", "KIT_WEBHOOK_KEY", "TELEGRAM_API_BASE"):
        if os.environ.get(k):
            env[k] = os.environ[k]
    return env


def setup_logging(base=BASE):
    os.makedirs(base, exist_ok=True)
    h = logging.handlers.RotatingFileHandler(os.path.join(base, "relay.log"), maxBytes=500_000, backupCount=1)
    h.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
    log.addHandler(h); log.setLevel(logging.INFO)


def display_name(u):
    return " ".join(x for x in (u.get("first_name"), u.get("last_name")) if x) or u.get("username") or str(u.get("id"))


class Relay:
    def __init__(self, token, base=BASE, api_base="https://api.telegram.org", webhook_url=None, webhook_key=None):
        self.token, self.base, self.api_base = token, base, api_base.rstrip("/")
        self.webhook_url, self.webhook_key = webhook_url, webhook_key
        self.state_path = os.path.join(base, "state.json")
        self.files_dir = os.path.join(base, "files")
        os.makedirs(self.files_dir, exist_ok=True)

    # ---------- state (shared with tg-send, guarded by flock) ----------
    @contextmanager
    def state(self):
        with open(self.state_path + ".lock", "a") as lk:
            fcntl.flock(lk, fcntl.LOCK_EX)
            try:
                with open(self.state_path) as f:
                    st = json.load(f)
            except (FileNotFoundError, json.JSONDecodeError):
                st = {}
            for k, d in (("admin_id", None), ("monitor_chat_id", None), ("offset", 0),
                         ("users", {}), ("pending", {}), ("drafts", {})):
                st.setdefault(k, d)
            yield st
            tmp = self.state_path + ".tmp"
            with open(tmp, "w") as f:
                json.dump(st, f, indent=1)
            os.chmod(tmp, 0o600); os.replace(tmp, self.state_path)

    def read_state(self):
        with self.state() as st:
            return json.loads(json.dumps(st))

    # ---------- Telegram API ----------
    def api(self, method, http_timeout=30, /, **params):
        url = f"{self.api_base}/bot{self.token}/{method}"
        data = json.dumps(params).encode()
        for attempt in range(5):
            req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
            try:
                with urllib.request.urlopen(req, timeout=http_timeout) as r:
                    res = json.load(r)
            except urllib.error.HTTPError as e:
                try:
                    res = json.load(e)
                except Exception:
                    res = {"ok": False, "description": f"HTTP {e.code}"}
            if res.get("ok"):
                return res.get("result")
            ra = (res.get("parameters") or {}).get("retry_after")
            if ra:
                log.warning("%s rate limited, retry after %ss", method, ra)
                time.sleep(min(float(ra), 60)); continue
            log.error("%s failed: %s", method, res.get("description"))
            return None
        return None

    def send(self, chat_id, text, topic_id=None, buttons=None):
        p = {"chat_id": chat_id, "text": text}
        if topic_id:
            p["message_thread_id"] = topic_id
        if buttons:
            p["reply_markup"] = {"inline_keyboard": [[{"text": t, "callback_data": d} for t, d in buttons]]}
        return self.api("sendMessage", **p)

    def mirror(self, st, uid, text, buttons=None):
        u = st["users"].get(str(uid))
        if st["monitor_chat_id"] and u and u.get("topic_id"):
            return self.send(st["monitor_chat_id"], text, u["topic_id"], buttons)
        if st["admin_id"]:  # no topic yet: fall back to Koen's private chat
            return self.send(st["admin_id"], f"[{u['name'] if u else uid}] {text}", None, buttons)

    def download(self, file_id, hint):
        f = self.api("getFile", file_id=file_id)
        if not f or not f.get("file_path"):
            return None
        name = f"{int(time.time())}-{hint}-{os.path.basename(f['file_path'])}"
        dest = os.path.join(self.files_dir, name)
        try:
            with urllib.request.urlopen(f"{self.api_base}/file/bot{self.token}/{f['file_path']}", timeout=60) as r, open(dest, "wb") as out:
                out.write(r.read())
            return dest
        except Exception as e:
            log.error("download failed: %s", type(e).__name__)
            return None

    def webhook(self, payload):
        if not self.webhook_url:
            log.warning("no webhook configured; payload dropped"); return False
        req = urllib.request.Request(self.webhook_url, data=json.dumps(payload).encode(), method="POST",
                                     headers={"Content-Type": "application/json", "Authorization": f"Bearer {self.webhook_key}"})
        for attempt in range(3):
            try:
                with urllib.request.urlopen(req, timeout=30) as r:
                    log.info("webhook %s for msg %s", r.status, payload.get("message_id")); return True
            except urllib.error.HTTPError as e:
                log.warning("webhook HTTP %s (try %d)", e.code, attempt + 1)
            except Exception as e:
                log.warning("webhook error %s (try %d)", type(e).__name__, attempt + 1)
            time.sleep(2 * (attempt + 1))
        return False

    # ---------- outbound (tg-send) ----------
    def send_to_field(self, uid, text, as_koen=False):
        with self.state() as st:
            u = st["users"].get(str(uid))
            if not u:
                raise SystemExit(f"user {uid} not on allowlist")
            out = f"Koen: {text}" if as_koen else text
            r = self.send(int(uid), out)
            self.mirror(st, uid, ("Koen (via bot): " if as_koen else "Bot: ") + text)
            log.info("sent to %s (as_koen=%s)", uid, as_koen)
            return r

    def escalate(self, uid, summary, draft):
        with self.state() as st:
            if str(uid) not in st["users"]:
                raise SystemExit(f"user {uid} not on allowlist")
            key = secrets.token_hex(4)
            st["drafts"][key] = {"user_id": str(uid), "text": draft}
            self.mirror(st, uid, f"⚑ Escalation: {summary}\nDraft: \"{draft}\"",
                        [("Approve draft", f"ad:{key}"), ("Reply myself", f"rm:{key}")])
            log.info("escalation %s for %s", key, uid)
            return key

    # ---------- inbound ----------
    def poll_once(self, timeout=50):
        st = self.read_state()
        ups = self.api("getUpdates", timeout + 10, offset=st["offset"], timeout=timeout,
                       allowed_updates=["message", "callback_query"])
        for u in ups or []:
            try:
                self.handle_update(u)
            except Exception:
                log.exception("update %s failed", u.get("update_id"))
            with self.state() as s:
                s["offset"] = max(s["offset"], u["update_id"] + 1)
        return len(ups or [])

    def handle_update(self, u):
        if "callback_query" in u:
            return self.on_callback(u["callback_query"])
        m = u.get("message")
        if not m or "from" not in m:
            return
        if m["chat"]["type"] == "private":
            return self.on_private(m)
        return self.on_group(m)

    def on_private(self, m):
        frm, text = m["from"], m.get("text") or m.get("caption") or ""
        uid, name = str(frm["id"]), display_name(frm)
        with self.state() as st:
            if st["admin_id"] is None and text.startswith("/start"):
                st["admin_id"] = frm["id"]
                log.warning("ADMIN registered: id %s (%s)", uid, name)
                self.send(frm["id"], "You are registered as admin. Next: add me to the monitor group and send /setup there.")
                return
            if frm["id"] == st["admin_id"]:
                return  # Koen talks to the bot via the monitor group
            if uid not in st["users"]:
                if text.startswith("/start") and uid not in st["pending"]:
                    st["pending"][uid] = {"name": name, "username": frm.get("username")}
                    self.send(frm["id"], "Hello! Koen needs to approve you first. You'll get a message here when that's done.")
                    if st["admin_id"]:
                        self.send(st["admin_id"], f"New field person wants access: {name} (@{frm.get('username') or '-'}, id {uid})",
                                  buttons=[("Approve", f"ok:{uid}"), ("Reject", f"no:{uid}")])
                    log.info("pending /start from %s", uid)
                else:
                    log.info("ignored message from unknown %s", uid)
                return
            usr = st["users"][uid]
        files = []
        if m.get("photo"):
            p = self.download(m["photo"][-1]["file_id"], uid)
            p and files.append(p)
        if m.get("document"):
            p = self.download(m["document"]["file_id"], uid)
            p and files.append(p)
        shown = text + "".join(f"\n[file: {os.path.basename(p)}]" for p in files)
        with self.state() as st:
            self.mirror(st, uid, f"{usr['name']}: {shown}")
            usr = st["users"][uid]
        payload = {"type": "telegram_message", "from_id": frm["id"], "from_name": usr["name"], "chat_id": m["chat"]["id"],
                   "text": text, "message_id": m["message_id"], "topic_id": usr.get("topic_id"),
                   "ts": m.get("date", int(time.time())), "paused": bool(usr.get("paused")), "files": files}
        self.webhook(payload)

    def on_group(self, m):
        text = m.get("text") or ""
        with self.state() as st:
            if m["from"]["id"] != st["admin_id"]:
                return
            chat = m["chat"]["id"]
            if text.startswith("/setup"):
                st["monitor_chat_id"] = chat
                log.warning("monitor group set to %s", chat)
                self.send(chat, "This group is now the IDEA Support Monitor. Approved field people each get a topic here.")
                return
            if chat != st["monitor_chat_id"] or not m.get("message_thread_id"):
                return
            tid = m["message_thread_id"]
            uid = next((k for k, v in st["users"].items() if v.get("topic_id") == tid), None)
            if not uid:
                return
            usr = st["users"][uid]
            if text.startswith("/pause"):
                usr["paused"] = True
                self.send(chat, f"Paused: I won't answer {usr['name']} myself. You reply here.", tid)
            elif text.startswith("/resume"):
                usr["paused"] = False
                self.send(chat, "Resumed: I answer obvious questions again.", tid)
            elif text and not text.startswith("/"):
                self.send(int(uid), f"Koen: {text}")
                self.send(chat, f"✓ sent to {usr['name']}", tid)
            log.info("koen action in topic %s", tid)

    def on_callback(self, q):
        data = q.get("data", "")
        with self.state() as st:
            if q["from"]["id"] != st["admin_id"]:
                self.api("answerCallbackQuery", callback_query_id=q["id"]); return
            kind, _, arg = data.partition(":")
            note = ""
            if kind == "ok" and arg in st["pending"]:
                info = st["pending"].pop(arg)
                topic = None
                if st["monitor_chat_id"]:
                    t = self.api("createForumTopic", chat_id=st["monitor_chat_id"], name=info["name"][:120])
                    topic = t and t.get("message_thread_id")
                st["users"][arg] = {"name": info["name"], "topic_id": topic, "paused": False}
                self.send(int(arg), "You're approved. Write here any time; I'll answer or ask Koen.")
                note = f"Approved {info['name']}"
            elif kind == "no" and arg in st["pending"]:
                info = st["pending"].pop(arg); note = f"Rejected {info['name']}"
            elif kind in ("ad", "rm") and arg in st["drafts"]:
                d = st["drafts"].pop(arg); usr = st["users"].get(d["user_id"])
                if usr and kind == "ad":
                    self.send(int(d["user_id"]), d["text"]); note = "Draft sent"
                    self.mirror(st, d["user_id"], "Bot: " + d["text"])
                elif usr:
                    usr["paused"] = True; note = "Paused"
                    self.mirror(st, d["user_id"], f"Koen chose: Reply myself. Paused for {usr['name']}; type your answer here, /resume when done.")
            else:
                note = "Already handled"
            log.info("callback %s: %s", kind, note)
        self.api("answerCallbackQuery", callback_query_id=q["id"], text=note)


def main():
    setup_logging()
    env = load_env()
    if not env.get("TELEGRAM_BOT_TOKEN"):
        log.warning("no TELEGRAM_BOT_TOKEN set; relay not started"); return 0
    r = Relay(env["TELEGRAM_BOT_TOKEN"], api_base=env.get("TELEGRAM_API_BASE", "https://api.telegram.org"),
              webhook_url=env.get("KIT_WEBHOOK_URL"), webhook_key=env.get("KIT_WEBHOOK_KEY"))
    log.info("relay started")
    while True:
        try:
            r.poll_once()
        except Exception as e:
            log.error("poll error %s", type(e).__name__); time.sleep(10)


if __name__ == "__main__":
    sys.exit(main())
