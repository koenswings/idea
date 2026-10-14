#!/usr/bin/env python3
"""Generates the SVG diagrams for the Justice remote-access guide (same drawing helpers as ../../install-guides/diagrams/make_diagrams.py).
Run:  python3 make_diagrams.py   (writes *.svg next to this file)"""
import os
OUT = os.path.dirname(os.path.abspath(__file__))
FONT = "DejaVu Sans, Arial, sans-serif"

class S:
    def __init__(s, w, h):
        s.w, s.h, s.p = w, h, []
    def add(s, x): s.p.append(x)
    def rect(s, x, y, w, h, fill="#fff", stroke="#333", rx=8, sw=2, dash=None):
        d = f' stroke-dasharray="{dash}"' if dash else ''
        s.add(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}"{d}/>')
    def text(s, x, y, t, size=14, weight="normal", anchor="middle", fill="#111", italic=False):
        st = ' font-style="italic"' if italic else ''
        for i, line in enumerate(t.split("\n")):
            line = line.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
            s.add(f'<text x="{x}" y="{y + i*size*1.25}" font-family="{FONT}" font-size="{size}" font-weight="{weight}" text-anchor="{anchor}" fill="{fill}"{st}>{line}</text>')
    def line(s, pts, color="#333", sw=4, dash=None, arrow=False, arrow_start=False):
        d = f' stroke-dasharray="{dash}"' if dash else ''
        m = ' marker-end="url(#ah-%s)"' % color.strip('#') if arrow else ''
        ms = ' marker-start="url(#as-%s)"' % color.strip('#') if arrow_start else ''
        pts_s = " ".join(f"{x},{y}" for x, y in pts)
        s.add(f'<polyline points="{pts_s}" fill="none" stroke="{color}" stroke-width="{sw}" stroke-linejoin="round" stroke-linecap="round"{d}{m}{ms}/>')
        s.colors.add(color)
    colors = set()
    def port(s, x, y, label, fill="#e8e8e8", w=46, h=34, sub=None, subfill="#555"):
        s.rect(x, y, w, h, fill=fill, stroke="#222", rx=4, sw=1.5)
        s.text(x + w/2, y + h/2 + 5, label, size=11, weight="bold")
        if sub: s.text(x + w/2, y + h + 14, sub, size=10, fill=subfill)
    def badge(s, x, y, n, color):
        s.add(f'<circle cx="{x}" cy="{y}" r="13" fill="{color}" stroke="#fff" stroke-width="2"/>')
        s.text(x, y + 5, str(n), size=13, weight="bold", fill="#fff")
    def save(s, name):
        defs = []
        for c in s.colors:
            cid = c.strip('#')
            defs.append(f'<marker id="ah-{cid}" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="5" markerHeight="5" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="{c}"/></marker>')
            defs.append(f'<marker id="as-{cid}" viewBox="0 0 10 10" refX="2" refY="5" markerWidth="5" markerHeight="5" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="{c}"/></marker>')
        svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{s.w}" height="{s.h}" viewBox="0 0 {s.w} {s.h}">'
               f'<defs>{"".join(defs)}</defs><rect width="100%" height="100%" fill="#ffffff"/>' + "".join(s.p) + '</svg>')
        open(os.path.join(OUT, name), "w").write(svg)
        S.colors = set()

C_WAN, C_UP, C_POE1, C_POE2, C_PWR = "#e0a100", "#1f77b4", "#2ca02c", "#9467bd", "#d62728"


C_KOEN, C_JUS, C_TS, C_BAD = "#1f77b4", "#2ca02c", "#9467bd", "#d62728"

def device(s, x, y, w, h, title, sub, fill):
    s.rect(x, y, w, h, fill=fill)
    s.text(x + w/2, y + 28, title, 15, "bold")
    s.text(x + w/2, y + 52, sub, 11, fill="#333")

# ------------------------------------------------ overview
def overview():
    s = S(1140, 470)
    s.text(570, 32, "How Justice reaches wizardly-hugle", 20, "bold")
    # Justice side
    s.rect(20, 60, 300, 330, fill="#f0fff0", stroke=C_JUS, dash="8,5")
    s.text(170, 86, "Justice (Zimbabwe or anywhere)", 13, "bold", fill=C_JUS)
    device(s, 45, 105, 250, 120, "Justice's device", "Raspberry Pi with Ubuntu,\nlaptop, phone or tablet\n+ Tailscale app", "#ffffff")
    s.rect(45, 245, 250, 125, fill="#ffffff")
    s.text(170, 270, "Web browser", 15, "bold")
    s.text(170, 294, "http://100.115.60.6:8081\n(IDEA Console)\nKolibri, Nextcloud, Kiwix", 11, fill="#333")
    s.line([(170, 228), (170, 242)], "#555", 3)
    # Internet cloud
    s.text(570, 112, "Internet", 17, "bold")
    s.text(570, 132, "(Starlink, mobile data, Wi-Fi...)", 11, fill="#555")
    s.add('<ellipse cx="570" cy="230" rx="215" ry="85" fill="#f6f1ff" stroke="%s" stroke-width="2"/>' % C_TS)
    s.line([(300, 205), (840, 205)], C_TS, 6, arrow=True, arrow_start=True)
    s.text(570, 240, "Tailscale: a private,", 13, "bold", fill=C_TS)
    s.text(570, 258, "encrypted tunnel through the internet", 13, "bold", fill=C_TS)
    s.text(570, 345, "Nothing on wizardly-hugle is open to the public internet.", 11, italic=True, fill="#555")
    # Belgium side
    s.rect(820, 60, 300, 330, fill="#eef5ff", stroke=C_KOEN, dash="8,5")
    s.text(970, 86, "Koen's home (Belgium)", 13, "bold", fill=C_KOEN)
    s.rect(845, 105, 250, 265, fill="#ffffff")
    s.text(970, 132, "wizardly-hugle", 16, "bold")
    s.text(970, 152, "IDEA demo server, 100.115.60.6", 11, fill="#333")
    apps = [("IDEA Console  :8081", "#cfe3ff"), ("Kolibri  :54189", "#e3f5e3"), ("Nextcloud  :50065", "#e3f5e3"),
            ("Kiwix (Wikipedia)  :61312", "#e3f5e3"), ("MilkWise: do not touch", "#fbd5d5")]
    for i, (a, f) in enumerate(apps):
        s.rect(865, 168 + i * 38, 210, 30, fill=f, rx=4, sw=1.2)
        s.text(970, 188 + i * 38, a, 11, "bold", fill="#a00" if "MilkWise" in a else "#111")
    s.text(570, 430, "Justice signs in to Tailscale with his own account. Koen shares only this one machine with him.", 12, fill="#333")
    s.text(570, 452, "The apps keep their own sign-in: Koen sends the passwords separately.", 12, fill="#333")
    s.save("overview.svg")

# ------------------------------------------------ share flow
def flow():
    s = S(1140, 520)
    s.text(570, 32, "Getting access: five steps", 20, "bold")
    s.rect(20, 55, 1100, 200, fill="#f0fff0", stroke=C_JUS, sw=1.5)
    s.text(36, 80, "JUSTICE", 14, "bold", anchor="start", fill=C_JUS)
    s.rect(20, 290, 1100, 200, fill="#eef5ff", stroke=C_KOEN, sw=1.5)
    s.text(36, 315, "KOEN", 14, "bold", anchor="start", fill=C_KOEN)
    steps = [
        (40, 95, C_JUS, "1", "Create a Tailscale\naccount and install\nTailscale (Part B)"),
        (260, 95, C_JUS, "2", "Send Koen the\nemail address of\nthe Tailscale account"),
        (480, 330, C_KOEN, "3", "Admin console:\nMachines > wizardly-hugle\n... menu > Share"),
        (700, 95, C_JUS, "4", "Open the invite\n(email or link)\nand accept it"),
        (920, 95, C_JUS, "5", "wizardly-hugle is\nin the machine list:\nopen the Console"),
    ]
    for x, y, c, n, t in steps:
        s.rect(x, y, 190, 140, fill="#ffffff", stroke=c)
        s.badge(x + 22, y + 22, n, c)
        s.text(x + 105, y + 52, t, 12)
    s.line([(230, 165), (258, 165)], "#555", 3, arrow=True)
    s.line([(355, 237), (355, 400), (478, 400)], "#555", 3, arrow=True)
    s.text(365, 300, "email address", 10, anchor="start", fill="#555")
    s.line([(672, 400), (795, 400), (795, 238)], "#555", 3, arrow=True)
    s.text(805, 300, "invite email\nor invite link", 10, anchor="start", fill="#555")
    s.line([(890, 165), (918, 165)], "#555", 3, arrow=True)
    s.text(905, 400, "Later: Koen can revoke\nthe share at any time\n(Part A, section 2.3)", 12, anchor="start", fill="#a00")
    s.save("flow.svg")

# ------------------------------------------------ what Justice sees
def privacy():
    s = S(1140, 430)
    s.text(570, 32, "What the share gives Justice, and what it does not", 20, "bold")
    s.rect(20, 60, 480, 320, fill="#eef5ff", stroke=C_KOEN)
    s.text(260, 88, "Koen's tailnet (private network)", 14, "bold", fill=C_KOEN)
    others = ["Koen's laptop", "Koen's phone", "other IDEA Pis", "test machines"]
    for i, o in enumerate(others):
        s.rect(45 + (i % 2) * 220, 110 + (i // 2) * 70, 200, 50, fill="#eeeeee", stroke="#999", sw=1.5)
        s.text(145 + (i % 2) * 220, 140 + (i // 2) * 70, o, 12, fill="#777")
    s.text(260, 270, "Justice cannot see or reach these", 12, "bold", fill=C_BAD)
    s.rect(130, 290, 260, 70, fill="#ffffff", stroke=C_KOEN, sw=3)
    s.text(260, 318, "wizardly-hugle", 15, "bold")
    s.text(260, 340, "shared with Justice only", 11, fill="#333")
    s.rect(640, 60, 480, 320, fill="#f0fff0", stroke=C_JUS)
    s.text(880, 88, "Justice's own tailnet", 14, "bold", fill=C_JUS)
    for i, o in enumerate(["Ubuntu Pi", "phone / laptop"]):
        s.rect(665 + i * 220, 110, 200, 50, fill="#ffffff", stroke=C_JUS, sw=1.5)
        s.text(765 + i * 220, 140, o, 12)
    s.rect(750, 290, 260, 70, fill="#ffffff", stroke=C_KOEN, sw=3, dash="6,4")
    s.text(880, 318, "wizardly-hugle (shared)", 14, "bold")
    s.text(880, 340, "appears in Justice's list", 11, fill="#333")
    s.line([(392, 325), (746, 325)], C_TS, 4, arrow=True)
    s.text(570, 312, "share", 12, "bold", fill=C_TS)
    s.line([(870, 165), (870, 286)], C_JUS, 3, arrow=True)
    s.text(880, 225, "Justice's devices can open\nwizardly-hugle's web pages", 11, anchor="start", fill=C_JUS)
    s.line([(780, 286), (780, 168)], C_BAD, 3, dash="6,5", arrow=True)
    s.text(770, 225, "wizardly-hugle cannot\nstart connections to\nJustice's devices", 11, anchor="end", fill=C_BAD)
    s.text(570, 412, "Koen's other machines stay hidden. Koen can stop the share at any time.", 12, fill="#333")
    s.save("privacy.svg")

# ------------------------------------------------ troubleshooting checks
def checks():
    s = S(1140, 300)
    s.text(570, 30, "If something does not work: check in this order", 20, "bold")
    items = [("1", "Tailscale on?", "app connected /\ntailscale status"),
             ("2", "Signed in?", "your own account\n(not logged out)"),
             ("3", "Share accepted?", "wizardly-hugle\nin your list"),
             ("4", "Server online?", "tailscale ping\n100.115.60.6"),
             ("5", "Right address?", "http:// and the\nright port number")]
    for i, (n, t, sub) in enumerate(items):
        x = 25 + i * 225
        s.rect(x, 60, 190, 170, fill="#fff4e5", stroke="#ff7f0e")
        s.badge(x + 24, 84, n, "#ff7f0e")
        s.text(x + 95, 125, t, 15, "bold")
        s.text(x + 95, 160, sub, 12, fill="#333")
        if i < 4: s.line([(x + 192, 145), (x + 222, 145)], "#555", 3, arrow=True)
    s.text(570, 270, "Stop at the first check that fails; section 4 says what to do.", 12, fill="#333")
    s.save("checks.svg")

for f in (overview, flow, privacy, checks):
    f()
print("ok")
