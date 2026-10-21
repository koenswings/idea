import json, os, sys, tempfile, threading, unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import tg_relay

class Fake:
    def __init__(self):
        self.calls, self.hooks, self.updates, self.rate_limit_once = [], [], [], False
        fake = self
        class H(BaseHTTPRequestHandler):
            def log_message(self, *a): pass
            def _send(self, obj, code=200, raw=None):
                b = raw if raw is not None else json.dumps(obj).encode()
                self.send_response(code); self.end_headers(); self.wfile.write(b)
            def do_GET(self):
                self._send(None, raw=b"PHOTOBYTES")
            def do_POST(self):
                body = json.loads(self.rfile.read(int(self.headers["Content-Length"])) or b"{}")
                if self.path == "/hook":
                    fake.hooks.append((self.headers.get("Authorization"), body)); return self._send({})
                method = self.path.rsplit("/", 1)[1]
                if method == "sendMessage" and fake.rate_limit_once:
                    fake.rate_limit_once = False
                    return self._send({"ok": False, "error_code": 429, "parameters": {"retry_after": 0.01}}, 429)
                fake.calls.append((method, body))
                res = True
                if method == "getUpdates": res, fake.updates = fake.updates, []
                elif method == "createForumTopic": res = {"message_thread_id": 77, "name": body["name"]}
                elif method == "sendMessage": res = {"message_id": len(fake.calls)}
                elif method == "getFile": res = {"file_path": "photos/p1.jpg"}
                self._send({"ok": True, "result": res})
        self.srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
        threading.Thread(target=self.srv.serve_forever, daemon=True).start()
        self.url = f"http://127.0.0.1:{self.srv.server_port}"
    def sent(self, method="sendMessage"):
        return [b for m, b in self.calls if m == method]

KOEN, JUST, STRANGER, GROUP = 100, 200, 300, -500

def priv(uid, text, mid=1, first="X", **extra):
    m = {"message_id": mid, "from": {"id": uid, "first_name": first}, "chat": {"id": uid, "type": "private"}, "date": 1, "text": text}
    m.update(extra); return {"update_id": mid, "message": m}

def grp(text, thread=None, uid=KOEN):
    m = {"message_id": 9, "from": {"id": uid, "first_name": "Koen"}, "chat": {"id": GROUP, "type": "supergroup"}, "text": text}
    if thread: m["message_thread_id"] = thread
    return {"update_id": 9, "message": m}

def cb(data, uid=KOEN):
    return {"update_id": 5, "callback_query": {"id": "q1", "from": {"id": uid}, "data": data}}

class RelayTest(unittest.TestCase):
    def setUp(self):
        self.f = Fake(); self.d = tempfile.mkdtemp()
        self.r = tg_relay.Relay("TOKEN", base=self.d, api_base=self.f.url, webhook_url=self.f.url + "/hook", webhook_key="K")
        self.r.handle_update(priv(KOEN, "/start", first="Koen"))
        self.r.handle_update(grp("/setup"))
        self.f.calls.clear()
    def tearDown(self): self.f.srv.shutdown()

    def approve_justice(self):
        self.r.handle_update(priv(JUST, "/start", first="Justice"))
        self.r.handle_update(cb(f"ok:{JUST}"))
        self.f.calls.clear()

    def test_bootstrap(self):
        st = self.r.read_state()
        self.assertEqual(st["admin_id"], KOEN); self.assertEqual(st["monitor_chat_id"], GROUP)

    def test_setup_by_non_admin_ignored(self):
        self.r.handle_update({"update_id": 3, "message": {"message_id": 3, "from": {"id": STRANGER}, "chat": {"id": -9, "type": "group"}, "text": "/setup"}})
        self.assertEqual(self.r.read_state()["monitor_chat_id"], GROUP)

    def test_approve_flow(self):
        self.r.handle_update(priv(JUST, "/start", first="Justice"))
        s = self.f.sent()
        self.assertEqual(s[0]["chat_id"], JUST); self.assertIn("approve", s[0]["text"])
        self.assertEqual(s[1]["chat_id"], KOEN)
        self.assertEqual([b["text"] for b in s[1]["reply_markup"]["inline_keyboard"][0]], ["Approve", "Reject"])
        self.r.handle_update(cb(f"ok:{JUST}"))
        self.assertEqual(self.f.sent("createForumTopic")[0], {"chat_id": GROUP, "name": "Justice"})
        self.assertEqual(self.r.read_state()["users"][str(JUST)]["topic_id"], 77)

    def test_reject_and_non_admin_callback(self):
        self.r.handle_update(priv(JUST, "/start", first="Justice"))
        self.r.handle_update(cb(f"ok:{JUST}", uid=STRANGER))
        self.assertNotIn(str(JUST), self.r.read_state()["users"])
        self.r.handle_update(cb(f"no:{JUST}"))
        st = self.r.read_state(); self.assertNotIn(str(JUST), st["users"]); self.assertEqual(st["pending"], {})

    def test_unknown_sender_ignored(self):
        self.r.handle_update(priv(STRANGER, "hello"))
        self.assertEqual(self.f.calls, []); self.assertEqual(self.f.hooks, [])

    def test_mirror_and_webhook(self):
        self.approve_justice()
        self.r.handle_update(priv(JUST, "Console won't open", mid=11, first="Justice"))
        self.assertEqual(self.f.sent()[0], {"chat_id": GROUP, "text": "Justice: Console won't open", "message_thread_id": 77})
        auth, p = self.f.hooks[0]
        self.assertEqual(auth, "Bearer K")
        self.assertEqual((p["type"], p["from_id"], p["text"], p["topic_id"], p["paused"], p["message_id"]),
                         ("telegram_message", JUST, "Console won't open", 77, False, 11))

    def test_photo_downloaded(self):
        self.approve_justice()
        self.r.handle_update(priv(JUST, None, mid=12, first="Justice", photo=[{"file_id": "a"}, {"file_id": "b"}], caption="screen"))
        path = self.f.hooks[0][1]["files"][0]
        self.assertTrue(path.startswith(os.path.join(self.d, "files")))
        self.assertEqual(open(path, "rb").read(), b"PHOTOBYTES")

    def test_tg_send_and_as_koen(self):
        self.approve_justice()
        self.r.send_to_field(JUST, "Restart the Engine")
        self.r.send_to_field(JUST, "Fix this week", as_koen=True)
        t = [(b["chat_id"], b["text"]) for b in self.f.sent()]
        self.assertEqual(t, [(JUST, "Restart the Engine"), (GROUP, "Bot: Restart the Engine"),
                             (JUST, "Koen: Fix this week"), (GROUP, "Koen (via bot): Fix this week")])

    def test_escalate_and_approve_draft(self):
        self.approve_justice()
        key = self.r.escalate(JUST, "Kolibri error", "Use disk 1 for now")
        card = self.f.sent()[0]
        self.assertEqual(card["chat_id"], GROUP); self.assertEqual(card["message_thread_id"], 77)
        self.assertEqual([b["text"] for b in card["reply_markup"]["inline_keyboard"][0]], ["Approve draft", "Reply myself"])
        self.assertFalse(any(b["chat_id"] == JUST for b in self.f.sent()))
        self.r.handle_update(cb(f"ad:{key}"))
        self.assertIn({"chat_id": JUST, "text": "Use disk 1 for now"}, self.f.sent())
        self.r.handle_update(cb(f"ad:{key}"))  # second tap: nothing resent
        self.assertEqual(sum(1 for b in self.f.sent() if b["chat_id"] == JUST), 1)

    def test_reply_myself_pauses(self):
        self.approve_justice()
        key = self.r.escalate(JUST, "x", "y")
        self.r.handle_update(cb(f"rm:{key}"))
        self.assertTrue(self.r.read_state()["users"][str(JUST)]["paused"])
        self.assertFalse(any(b["chat_id"] == JUST for b in self.f.sent()))

    def test_koen_relay(self):
        self.approve_justice()
        self.r.handle_update(grp("Use the first disk today", thread=77))
        t = [(b["chat_id"], b["text"]) for b in self.f.sent()]
        self.assertEqual(t, [(JUST, "Koen: Use the first disk today"), (GROUP, "✓ sent to Justice")])

    def test_non_admin_in_group_ignored(self):
        self.approve_justice()
        self.r.handle_update(grp("hi", thread=77, uid=STRANGER))
        self.assertEqual(self.f.calls, [])

    def test_pause_resume_payload(self):
        self.approve_justice()
        self.r.handle_update(grp("/pause", thread=77))
        self.r.handle_update(priv(JUST, "still there?", mid=13, first="Justice"))
        self.assertTrue(self.f.hooks[-1][1]["paused"])
        self.r.handle_update(grp("/resume", thread=77))
        self.r.handle_update(priv(JUST, "ok", mid=14, first="Justice"))
        self.assertFalse(self.f.hooks[-1][1]["paused"])

    def test_retry_after(self):
        self.approve_justice()
        self.f.rate_limit_once = True
        self.assertTrue(self.r.send(JUST, "hi"))

    def test_poll_once_offset(self):
        self.approve_justice()
        self.f.updates = [priv(JUST, "a", mid=40, first="Justice")]
        self.assertEqual(self.r.poll_once(timeout=0), 1)
        self.assertEqual(self.r.read_state()["offset"], 41)
        self.assertEqual(self.f.sent("getUpdates")[0]["timeout"], 0)

if __name__ == "__main__":
    unittest.main()
