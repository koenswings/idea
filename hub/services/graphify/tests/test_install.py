"""graphify install.sh against a fake $HOME with stub systemctl/loginctl, plus the unit's own
ExecStart run on a free port. Box only: never touches a Pi or the box's user session."""
import configparser, hashlib, os, socket, subprocess, sys, tempfile, time, unittest, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..")
INSTALL = os.path.join(SRC, "install.sh")
UNIT = os.path.join(SRC, "graphify-serve.service")


def rd(p, mode="r"):
    with open(p, mode) as f: return f.read()


def tree(d):
    out = {}
    for root, _, files in os.walk(d):
        for n in files:
            p = os.path.join(root, n); out[os.path.relpath(p, d)] = hashlib.sha256(rd(p, "rb")).hexdigest()
    return out


class InstallTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); t = self.tmp.name
        self.home = os.path.join(t, "home"); self.bin = os.path.join(t, "bin"); os.makedirs(self.bin)
        self.out = os.path.join(self.home, "graphify-out"); os.makedirs(os.path.join(self.out, "obsidian"))
        for n, b in (("graph.html", "<html>graph</html>"), ("graph.json", "{}"), ("obsidian/a.md", "# a")):
            with open(os.path.join(self.out, n), "w") as f: f.write(b)
        self.calls = os.path.join(t, "calls")
        for n, body in (("systemctl", '#!/bin/sh\necho "systemctl $*" >> "%s"\n[ "$2" = is-active ] && echo active\nexit 0\n' % self.calls),
                        ("loginctl", "#!/bin/sh\necho yes\n")):
            p = os.path.join(self.bin, n)
            with open(p, "w") as f: f.write(body)
            os.chmod(p, 0o755)
        self.env = dict(os.environ, HOME=self.home, PATH=self.bin + os.pathsep + os.environ["PATH"])
        self.unit = os.path.join(self.home, ".config/systemd/user/graphify-serve.service")

    def tearDown(self): self.tmp.cleanup()

    def sh(self, *a): return subprocess.run(["sh", INSTALL, *a], cwd="/", env=self.env, capture_output=True, text=True)

    def test_install_and_rerun_never_touch_served_files(self):
        before = tree(self.out)
        for _ in range(2):
            r = self.sh(); self.assertEqual(r.returncode, 0, r.stderr)
            self.assertEqual(rd(self.unit), rd(UNIT)); self.assertEqual(tree(self.out), before)
        calls = rd(self.calls)
        self.assertIn("systemctl --user enable graphify-serve.service", calls)
        self.assertIn("systemctl --user restart graphify-serve.service", calls)
        self.assertFalse(os.path.exists(os.path.join(self.home, ".idea-hub-backups")), "same unit: no backup")

    def test_differing_unit_is_backed_up_first(self):
        os.makedirs(os.path.dirname(self.unit))
        with open(self.unit, "w") as f: f.write("[Service]\nExecStart=/home/pi/graphify-env/bin/python -m http.server 8083\n")
        old = rd(self.unit)
        r = self.sh(); self.assertEqual(r.returncode, 0, r.stderr)
        root = os.path.join(self.home, ".idea-hub-backups/graphify"); [bk] = os.listdir(root)
        self.assertEqual(rd(os.path.join(root, bk, "graphify-serve.service")), old)
        self.assertEqual(rd(self.unit), rd(UNIT))

    def test_refuses_without_served_dir(self):
        os.rename(self.out, self.out + ".aside")
        r = self.sh(); self.assertEqual(r.returncode, 1); self.assertIn("never rebuilds", r.stderr)
        self.assertFalse(os.path.exists(self.unit)); self.assertFalse(os.path.exists(self.calls))

    def test_stage_makes_no_systemctl_calls(self):
        r = self.sh("--stage"); self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue(os.path.isfile(self.unit)); self.assertFalse(os.path.exists(self.calls))

    def test_unit_execstart_serves_the_folder(self):
        cp = configparser.ConfigParser(strict=False, interpolation=None); cp.optionxform = str; cp.read(UNIT)
        cmd = cp["Service"]["ExecStart"].replace("%h", self.home)
        self.assertNotIn("graphify-env", cmd); self.assertIn(" 8083 ", cmd); self.assertIn("--bind 0.0.0.0", cmd)
        s = socket.socket(); s.bind(("127.0.0.1", 0)); port = s.getsockname()[1]; s.close()
        argv = cmd.replace(" 8083 ", " %d " % port).replace("0.0.0.0", "127.0.0.1").split()
        argv[0] = sys.executable if not os.path.exists(argv[0]) else argv[0]
        p = subprocess.Popen(argv, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            for _ in range(50):
                try:
                    with urllib.request.urlopen("http://127.0.0.1:%d/graph.html" % port, timeout=2) as r:
                        self.assertEqual(r.status, 200); self.assertEqual(r.read(), b"<html>graph</html>"); break
                except OSError: time.sleep(0.1)
            else: self.fail("server did not answer")
        finally: p.terminate(); p.wait(5)


if __name__ == "__main__":
    unittest.main()
