#!/usr/bin/env python3
"""mock-stock-ui.py - a tiny stand-in for the Cudy STOCK web UI (idea#277 tests). No router is touched.
Usage: mock-stock-ui.py <statedir> <portfile> <stock-password-file>
  /                     login form (password only); POST /login sets a session cookie
  backup page           STOCK_BACKUP_PATH with an "Export" button that downloads a config file
  upgrade page          STOCK_UPGRADE_PATH: file input + Upload; the reply shows MD5 and size and a Proceed button
  POST /proceed         "flashes": writes intermediate to <statedir>/stage (the mock router then answers on SSH)
Env FAKE_PAGE_MD5=1 makes the page show a wrong MD5. Every request is appended to <statedir>/http.log."""
import email.parser, email.policy, hashlib, http.server, os, secrets, sys, urllib.parse

STATE, PORTFILE, PWFILE = sys.argv[1:4]
PW = open(PWFILE).read().split("\n")[0]
SESS = secrets.token_hex(8)
UPG = "/cgi-bin/luci/admin/setup"
BAK = "/cgi-bin/luci/admin/system/backup"

def page(body):
    return f"<!doctype html><html><head><title>Cudy</title></head><body>{body}</body></html>".encode()

class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        with open(os.path.join(STATE, "http.log"), "a") as f:
            f.write(f"{self.command} {self.path}\n")
    def authed(self):
        return f"sysauth={SESS}" in (self.headers.get("Cookie") or "")
    def send(self, code, body, ctype="text/html", extra=()):
        self.send_response(code); self.send_header("Content-Type", ctype)
        for k, v in extra: self.send_header(k, v)
        self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)
    def login_page(self):
        self.send(200, page('<form method="post" action="/login"><input type="password" name="luci_password">'
                            '<button type="submit">Login</button></form>'))
    def do_GET(self):
        if not self.authed(): return self.login_page()
        path = self.path.split("?")[0]
        if path == "/": return self.send(200, page("<h1>Status</h1>"))
        if path == BAK:
            return self.send(200, page('<h1>Backup</h1><a href="/backup.bin" download>Export</a>'))
        if path == "/backup.bin":
            return self.send(200, b"MOCK-STOCK-CONFIG\n" * 64, "application/octet-stream",
                             [("Content-Disposition", 'attachment; filename="cudy-config.bin"')])
        if path == UPG:
            return self.send(200, page(f'<h1>Firmware</h1><form method="post" enctype="multipart/form-data" action="{UPG}?active=autoupgrade">'
                                       '<input type="file" name="image"><button type="submit">Upload</button></form>'))
        self.send(404, page("not found"))
    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0); data = self.rfile.read(n)
        path = self.path.split("?")[0]
        if path == "/login":
            if urllib.parse.parse_qs(data.decode(errors="replace")).get("luci_password", [""])[0] == PW:
                return self.send(302, b"", extra=[("Set-Cookie", f"sysauth={SESS}; Path=/"), ("Location", "/")])
            return self.login_page()
        if not self.authed(): return self.login_page()
        if path == UPG:
            msg = email.parser.BytesParser(policy=email.policy.default).parsebytes(
                b"Content-Type: " + self.headers["Content-Type"].encode() + b"\r\n\r\n" + data)
            blob = b""
            for part in msg.iter_parts():
                if part.get_filename(): blob = part.get_payload(decode=True)
            with open(os.path.join(STATE, "uploaded.bin"), "wb") as f: f.write(blob)
            md5 = hashlib.md5(blob).hexdigest()
            if os.environ.get("FAKE_PAGE_MD5"): md5 = "0" * 32
            return self.send(200, page(f'<p>Firmware MD5: {md5}</p><p>Size: {len(blob):,} bytes</p>'
                                       '<form method="post" action="/proceed"><button type="submit">Proceed</button></form>'))
        if path == "/proceed":
            with open(os.path.join(STATE, "stage"), "w") as f: f.write("intermediate\n")
            return self.send(200, page("<p>Upgrading, do not power off</p>"))
        self.send(404, page("not found"))

srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
with open(PORTFILE + ".tmp", "w") as f: f.write(str(srv.server_address[1]))
os.rename(PORTFILE + ".tmp", PORTFILE)
srv.serve_forever()
