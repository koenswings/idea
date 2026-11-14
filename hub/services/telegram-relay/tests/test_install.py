"""install.sh against a fake $HOME with a stub systemctl: re-runs keep a real env file untouched."""
import os, stat, subprocess, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
INSTALL = os.path.join(HERE, "..", "install.sh")

class InstallTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = os.path.join(self.tmp.name, "home")
        self.bin = os.path.join(self.tmp.name, "bin")
        os.makedirs(self.home); os.makedirs(self.bin)
        self.calls = os.path.join(self.tmp.name, "systemctl.calls")
        stub = os.path.join(self.bin, "systemctl")
        with open(stub, "w") as f:
            f.write('#!/bin/sh\necho "$*" >> "%s"\n[ "$2" = is-active ] && echo active\nexit 0\n' % self.calls)
        os.chmod(stub, 0o755)
        self.env = dict(os.environ, HOME=self.home, PATH=self.bin + os.pathsep + os.environ["PATH"])

    def tearDown(self):
        self.tmp.cleanup()

    def run_install(self, cwd="/"):
        # Run from an unrelated cwd: install.sh must find its own files.
        return subprocess.run(["sh", INSTALL], cwd=cwd, env=self.env, capture_output=True, text=True)

    def envfile(self):
        return os.path.join(self.home, ".config/tg-relay/env")

    def test_first_install_creates_env_with_webhook_keys(self):
        kw = os.path.join(self.home, ".config/kit-watch"); os.makedirs(kw)
        with open(os.path.join(kw, "env"), "w") as f:
            f.write("KIT_WEBHOOK_URL=http://x\nKIT_WEBHOOK_KEY=k1\nOTHER=nope\n")
        r = self.run_install(); self.assertEqual(r.returncode, 0, r.stderr)
        with open(self.envfile()) as f: body = f.read()
        self.assertEqual(body, "TELEGRAM_BOT_TOKEN=\nKIT_WEBHOOK_URL=http://x\nKIT_WEBHOOK_KEY=k1\n")
        self.assertEqual(stat.S_IMODE(os.stat(self.envfile()).st_mode), 0o600)
        for p in ("tg-relay/tg_relay.py", "tg-relay/tg-send", ".config/systemd/user/tg-relay.service"):
            self.assertTrue(os.path.isfile(os.path.join(self.home, p)), p)
        self.assertNotIn("k1", r.stdout + r.stderr)

    def test_first_install_without_kit_watch_env(self):
        r = self.run_install(); self.assertEqual(r.returncode, 0, r.stderr)
        with open(self.envfile()) as f: self.assertEqual(f.read(), "TELEGRAM_BOT_TOKEN=\n")
        self.assertEqual([n for n in os.listdir(os.path.dirname(self.envfile())) if n != "env"], [])

    def test_rerun_keeps_real_env(self):
        real = "TELEGRAM_BOT_TOKEN=123:real\nKIT_WEBHOOK_URL=http://x\nKIT_WEBHOOK_KEY=k1\n"
        os.makedirs(os.path.dirname(self.envfile()))
        with open(self.envfile(), "w") as f: f.write(real)
        for _ in range(2):
            r = self.run_install(); self.assertEqual(r.returncode, 0, r.stderr)
            with open(self.envfile()) as f: self.assertEqual(f.read(), real)
            self.assertNotIn("123:real", r.stdout + r.stderr)
        with open(self.calls) as f: calls = f.read()
        self.assertIn("--user enable tg-relay.service", calls)
        self.assertNotIn("--system", calls)

if __name__ == "__main__":
    unittest.main()
