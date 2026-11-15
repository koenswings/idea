"""install.sh against a fake $HOME with stub systemctl/crontab/loginctl. Box only; never touches a Pi,
the box's own user session, its crontab, or a real env file."""
import os, stat, subprocess, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
INSTALL = os.path.join(HERE, "..", "install.sh")
OLD_CRON = ("* * * * * flock -n /home/pi/kit-watch/.cron-kit.lock timeout 90 /usr/bin/python3 /home/pi/kit-watch/kit-watch.py >/dev/null 2>&1\n"
            "* * * * * flock -n /home/pi/kit-watch/.cron-mail.lock timeout 90 /usr/bin/python3 /home/pi/kit-watch/mail-watch.py >/dev/null 2>&1\n")


def rd(p):
    with open(p) as f: return f.read()


class InstallTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); t = self.tmp.name
        self.home = os.path.join(t, "home"); self.bin = os.path.join(t, "bin"); self.st = os.path.join(t, "st")
        for d in (self.home, self.bin, self.st): os.makedirs(d)
        self.calls = os.path.join(t, "calls")
        self.cron = os.path.join(self.st, "crontab")
        stubs = {
            "systemctl": '#!/bin/sh\necho "systemctl $*" >> "{c}"\n'
                         'case "$2" in is-enabled) cat "{s}/enabled" 2>/dev/null || echo disabled;; '
                         'is-active) cat "{s}/active" 2>/dev/null || echo inactive;; '
                         'show) case "$4" in Result) cat "{s}/result" 2>/dev/null || echo success;; '
                         '*) cat "{s}/ran" 2>/dev/null || echo 0;; esac;; esac\nexit 0\n',
            "crontab": '#!/bin/sh\necho "crontab $*" >> "{c}"\n'
                       'if [ "$1" = -l ]; then [ -e "{s}/crontab" ] && cat "{s}/crontab" || {{ echo "no crontab for pi" >&2; exit 1; }}; '
                       'else cat "$1" > "{s}/crontab"; fi\n',
            "loginctl": '#!/bin/sh\necho yes\n',
        }
        for n, body in stubs.items():
            p = os.path.join(self.bin, n)
            with open(p, "w") as f: f.write(body.format(c=self.calls, s=self.st))
            os.chmod(p, 0o755)
        self.env = dict(os.environ, HOME=self.home, PATH=self.bin + os.pathsep + os.environ["PATH"])

    def tearDown(self): self.tmp.cleanup()

    def sh(self, *args):
        return subprocess.run(["sh", INSTALL, *args], cwd="/", env=self.env, capture_output=True, text=True)

    def p(self, rel): return os.path.join(self.home, rel)

    def test_fresh_install(self):
        r = self.sh(); self.assertEqual(r.returncode, 0, r.stderr)
        for rel in ("kit-watch/kit-watch.py", "kit-watch/mail-watch.py", ".config/systemd/user/kit-watch.service", ".config/systemd/user/kit-watch.timer"):
            self.assertTrue(os.path.isfile(self.p(rel)), rel)
        self.assertEqual(stat.S_IMODE(os.stat(self.p("kit-watch")).st_mode), 0o700)
        self.assertEqual(stat.S_IMODE(os.stat(self.p(".config/kit-watch/env")).st_mode), 0o600)
        self.assertEqual(rd(self.p(".config/kit-watch/env")), "KIT_WEBHOOK_URL=\nKIT_WEBHOOK_KEY=\nAGENTMAIL_API_KEY=\n")
        calls = rd(self.calls)
        self.assertIn("systemctl --user enable kit-watch.timer", calls)
        self.assertIn("systemctl --user start kit-watch.timer", calls)
        self.assertNotIn("enable kit-watch.service", calls)
        self.assertNotIn("crontab -r", calls); self.assertNotIn("crontab /", calls, "plain install never writes the crontab")
        self.assertEqual(sorted(os.listdir(self.p(".config/kit-watch"))), ["env"])

    def test_rerun_keeps_real_env_and_state(self):
        real = "KIT_WEBHOOK_URL=https://hook.invalid/x\nKIT_WEBHOOK_KEY=real-k\nAGENTMAIL_API_KEY=real-a\n"
        os.makedirs(self.p(".config/kit-watch")); os.makedirs(self.p("kit-watch"))
        with open(self.p(".config/kit-watch/env"), "w") as f: f.write(real)
        os.chmod(self.p(".config/kit-watch/env"), 0o644)
        state = {"state.json": '{"devices": {}}', "mail-state.json": '{"seen": ["a"]}', "watch.log": "old log\n", "DISABLED": "x"}
        for n, b in state.items():
            with open(self.p("kit-watch/" + n), "w") as f: f.write(b)
        for _ in range(2):
            r = self.sh(); self.assertEqual(r.returncode, 0, r.stderr)
            self.assertEqual(rd(self.p(".config/kit-watch/env")), real)
            for n, b in state.items(): self.assertEqual(rd(self.p("kit-watch/" + n)), b, n)
            self.assertNotIn("real-k", r.stdout + r.stderr); self.assertNotIn("real-a", r.stdout + r.stderr)
        self.assertEqual(stat.S_IMODE(os.stat(self.p(".config/kit-watch/env")).st_mode), 0o600)

    def test_install_mentions_old_cron_but_leaves_it(self):
        with open(self.cron, "w") as f: f.write("0 1 * * * echo keep\n" + OLD_CRON)
        r = self.sh(); self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("--remove-cron", r.stdout)
        self.assertEqual(rd(self.cron), "0 1 * * * echo keep\n" + OLD_CRON)

    def test_remove_cron_refuses_until_timer_ran(self):
        with open(self.cron, "w") as f: f.write(OLD_CRON)
        self.sh()
        r = self.sh("--remove-cron"); self.assertEqual(r.returncode, 1); self.assertIn("refusing", r.stderr)
        self.assertEqual(rd(self.cron), OLD_CRON)
        for n, v in (("enabled", "enabled"), ("active", "active"), ("ran", "12345"), ("result", "exit-code")):
            with open(os.path.join(self.st, n), "w") as f: f.write(v + "\n")
        r = self.sh("--remove-cron"); self.assertEqual(r.returncode, 1, "a failed last run must also refuse")
        self.assertEqual(rd(self.cron), OLD_CRON)

    def test_remove_cron_after_good_run(self):
        keep = "0 1 * * * echo keep\n"
        with open(self.cron, "w") as f: f.write(keep + OLD_CRON)
        self.sh()
        for n in (".cron-kit.lock", ".cron-mail.lock"): open(self.p("kit-watch/" + n), "w").close()
        for n, v in (("enabled", "enabled"), ("active", "active"), ("ran", "12345"), ("result", "success")):
            with open(os.path.join(self.st, n), "w") as f: f.write(v + "\n")
        r = self.sh("--remove-cron"); self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(rd(self.cron), keep)
        bk_root = self.p(".idea-hub-backups/kit-watch"); [bk] = os.listdir(bk_root)
        self.assertEqual(rd(os.path.join(bk_root, bk, "crontab.pi.before")), keep + OLD_CRON)
        self.assertEqual(sorted(os.listdir(os.path.join(bk_root, bk))), [".cron-kit.lock", ".cron-mail.lock", "crontab.pi.after", "crontab.pi.before"])
        self.assertFalse(os.path.exists(self.p("kit-watch/.cron-kit.lock")))
        r = self.sh("--remove-cron"); self.assertEqual(r.returncode, 0); self.assertIn("nothing to remove", r.stdout)
        self.assertEqual(rd(self.cron), keep)

    def test_refuses_root_and_unknown_option(self):
        self.assertEqual(self.sh("--bogus").returncode, 2)


if __name__ == "__main__":
    unittest.main()
