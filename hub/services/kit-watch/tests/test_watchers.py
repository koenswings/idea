"""kit-watch.py and mail-watch.py against a fake tailscale CLI, a fake webhook and a fake AgentMail API.
Box only: fake HOME, fake env values. Never touches a Pi, a real env file or the network."""
import http.server, json, os, stat, subprocess, sys, tempfile, threading, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..")
def rd(p):
    with open(p) as f: return f.read()


FAKE_KEY = "fake-key-" + os.urandom(4).hex()


class Fake(http.server.BaseHTTPRequestHandler):
    posts = []; messages = []; status = 200
    def log_message(self, *a): pass
    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        Fake.posts.append({"path": self.path, "auth": self.headers.get("Authorization"), "body": json.loads(self.rfile.read(n))})
        self.send_response(Fake.status); self.end_headers()
    def do_GET(self):
        body = json.dumps({"messages": Fake.messages}).encode()
        self.send_response(200); self.send_header("Content-Type", "application/json"); self.end_headers(); self.wfile.write(body)


class Base(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.srv = http.server.HTTPServer(("127.0.0.1", 0), Fake)
        threading.Thread(target=cls.srv.serve_forever, daemon=True).start()
        cls.base = "http://127.0.0.1:%d" % cls.srv.server_port

    @classmethod
    def tearDownClass(cls): cls.srv.shutdown(); cls.srv.server_close()

    def setUp(self):
        Fake.posts = []; Fake.messages = []; Fake.status = 200
        self.tmp = tempfile.TemporaryDirectory(); t = self.tmp.name
        self.home = os.path.join(t, "home"); self.kw = os.path.join(self.home, "kit-watch")
        os.makedirs(os.path.join(self.home, ".config/kit-watch"))
        self.envf = os.path.join(self.home, ".config/kit-watch/env")
        with open(self.envf, "w") as f:
            f.write(f"# comment\nKIT_WEBHOOK_URL='{self.base}/hook'\nKIT_WEBHOOK_KEY={FAKE_KEY}\nexport AGENTMAIL_API_KEY=\"{FAKE_KEY}\"\n")
        os.chmod(self.envf, 0o600)
        self.peers = os.path.join(t, "peers.json"); self.write_peers({})
        self.ts = os.path.join(t, "tailscale")
        with open(self.ts, "w") as f: f.write('#!/bin/sh\necho "$@" > "%s.args"\ncat "%s"\n' % (self.ts, self.peers))
        os.chmod(self.ts, 0o755)
        self.env = dict(os.environ, HOME=self.home, KIT_WATCH_TAILSCALE=self.ts, MAIL_WATCH_API_BASE=self.base, TZ="UTC")
        for k in ("KIT_WATCH_HOME", "KIT_WATCH_ENV", "KIT_WATCH_TAILSCALE_SOCKET"): self.env.pop(k, None)

    def tearDown(self): self.tmp.cleanup()

    def write_peers(self, online):
        peers = {str(i): {"DNSName": d + ".tail2d60.ts.net.", "Online": True, "TailscaleIPs": ["100.64.0.%d" % (i + 1)]} for i, d in enumerate(online)}
        with open(self.peers, "w") as f: json.dump({"Peer": peers}, f)

    def run_py(self, name, *args, hour=None):
        code = ("import datetime,runpy,sys;"
                "sys.argv=[%r]+%r;" % (name, list(args)))
        if hour is not None:
            # Pin the Brussels hour so quiet-hours behaviour is deterministic.
            code += ("R=datetime.datetime;\n"
                     "class F(R):\n  @classmethod\n  def now(c,tz=None): return R(2026,11,15,%d,30,tzinfo=tz)\n"
                     "datetime.datetime=F;" % hour)
        code += "runpy.run_path(%r, run_name='__main__')" % os.path.join(SRC, name)
        return subprocess.run([sys.executable, "-c", code], env=self.env, capture_output=True, text=True, timeout=60)

    def logtext(self):
        p = os.path.join(self.kw, "watch.log")
        return rd(p) if os.path.exists(p) else ""


class KitWatchTest(Base):
    def test_posts_once_per_device_with_default_home(self):
        self.write_peers(["sunny-robin"])
        r = self.run_py("kit-watch.py", hour=12); self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(len(Fake.posts), 1)
        p = Fake.posts[0]; self.assertEqual(p["path"], "/hook"); self.assertEqual(p["auth"], "Bearer " + FAKE_KEY)
        self.assertEqual(p["body"]["device"], "sunny-robin"); self.assertEqual(p["body"]["tailscaleIP"], "100.64.0.1")
        self.assertEqual(len(p["body"]["remaining"]), 5)
        r = self.run_py("kit-watch.py", hour=12); self.assertEqual(len(Fake.posts), 1, "second run must not re-post")
        st = json.loads(rd(os.path.join(self.kw, "state.json")))
        self.assertTrue(st["devices"]["sunny-robin"]["seenAt"])
        self.assertNotIn(FAKE_KEY, self.logtext() + r.stdout + r.stderr)
        self.assertEqual(rd(self.ts + ".args").split(), ["status", "--json"], "no --socket unless configured")

    def test_socket_flag_when_configured(self):
        self.env["KIT_WATCH_TAILSCALE_SOCKET"] = "/run/x.sock"
        self.run_py("kit-watch.py", hour=12)
        self.assertEqual(rd(self.ts + ".args").split(), ["--socket=/run/x.sock", "status", "--json"])

    def test_quiet_hours_queue_then_post(self):
        self.write_peers(["kind-panda"])
        self.run_py("kit-watch.py", hour=3); self.assertEqual(Fake.posts, [])
        self.assertIn("QUEUED kind-panda", self.logtext())
        self.run_py("kit-watch.py", hour=8); self.assertEqual(len(Fake.posts), 1)

    def test_failed_post_retries(self):
        Fake.status = 500; self.write_peers(["happy-zebra"])
        self.run_py("kit-watch.py", hour=12); self.assertIn("failed HTTP 500", self.logtext())
        Fake.status = 200; self.run_py("kit-watch.py", hour=12)
        self.assertEqual([p["body"]["device"] for p in Fake.posts], ["happy-zebra", "happy-zebra"])

    def test_all_seen_disables_without_touching_crontab(self):
        devs = ["sunny-robin", "happy-zebra", "kind-panda", "sunny-robin-router", "happy-zebra-router", "kind-panda-router"]
        self.write_peers(devs)
        bin_ = os.path.join(self.tmp.name, "bin"); os.makedirs(bin_)
        with open(os.path.join(bin_, "crontab"), "w") as f: f.write('#!/bin/sh\ntouch "%s/crontab.called"\n' % self.tmp.name)
        os.chmod(os.path.join(bin_, "crontab"), 0o755); self.env["PATH"] = bin_ + os.pathsep + self.env["PATH"]
        self.run_py("kit-watch.py", hour=12)
        self.assertEqual(len(Fake.posts), 6); self.assertTrue(os.path.exists(os.path.join(self.kw, "DISABLED")))
        self.assertFalse(os.path.exists(os.path.join(self.tmp.name, "crontab.called")))
        self.run_py("kit-watch.py", hour=12); self.assertEqual(len(Fake.posts), 6)

    def test_dry_run_posts_nothing(self):
        self.write_peers(["sunny-robin"])
        r = self.run_py("kit-watch.py", "--dry-run", hour=12)
        self.assertIn("WOULD POST", r.stdout); self.assertEqual(Fake.posts, [])
        self.assertFalse(os.path.exists(os.path.join(self.kw, "state.json")))

    def test_custom_home_and_env(self):
        alt = os.path.join(self.tmp.name, "alt"); self.env["KIT_WATCH_HOME"] = alt
        self.env["KIT_WATCH_ENV"] = self.envf; self.write_peers(["sunny-robin"])
        self.run_py("kit-watch.py", hour=12)
        self.assertTrue(os.path.exists(os.path.join(alt, "state.json"))); self.assertEqual(len(Fake.posts), 1)


class MailWatchTest(Base):
    def test_init_then_new_mail_posts_count_only(self):
        Fake.messages = [{"message_id": "a", "timestamp": "2026-11-15T10:00:00Z", "subject": "secret subject"}]
        r = self.run_py("mail-watch.py", hour=12); self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(Fake.posts, []); self.assertIn("init: 1", self.logtext())
        Fake.messages.append({"message_id": "b", "timestamp": "2026-11-15T11:00:00Z", "subject": "secret subject"})
        self.run_py("mail-watch.py", hour=12)
        self.assertEqual(len(Fake.posts), 1)
        self.assertEqual(Fake.posts[0]["body"], {"type": "support-mail", "count": 1, "newestReceived": "2026-11-15T12:00:00+01:00"})
        self.run_py("mail-watch.py", hour=12); self.assertEqual(len(Fake.posts), 1)
        self.assertNotIn("secret subject", json.dumps(Fake.posts) + self.logtext())
        self.assertNotIn(FAKE_KEY, self.logtext())

    def test_quiet_hours_queue(self):
        self.run_py("mail-watch.py", hour=12)
        Fake.messages = [{"message_id": "c", "timestamp": "2026-11-15T01:00:00Z"}]
        self.run_py("mail-watch.py", hour=2); self.assertEqual(Fake.posts, [])
        self.assertIn("QUEUED 1", self.logtext())
        self.run_py("mail-watch.py", hour=7); self.assertEqual(len(Fake.posts), 1)


class EnvParseTest(unittest.TestCase):
    def test_env_values_match_old_bash_printf_parsing(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location("kw", os.path.join(SRC, "mail-watch.py"))
        m = importlib.util.module_from_spec(spec)
        sys_argv = sys.argv; sys.argv = ["x"]
        try: spec.loader.exec_module(m)  # main() only runs under __main__
        finally: sys.argv = sys_argv
        with tempfile.NamedTemporaryFile("w", delete=False) as f:
            f.write("A=plain\nB='single quoted'\nC=\"double\"\nexport D=x\n# E=commented\n\nF=a b\n")
        try:
            self.assertEqual(m.env(f.name), {"A": "plain", "B": "single quoted", "C": "double", "D": "x", "F": "ab"})
        finally: os.unlink(f.name)


if __name__ == "__main__":
    unittest.main()
