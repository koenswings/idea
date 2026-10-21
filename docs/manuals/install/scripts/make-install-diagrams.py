#!/usr/bin/env python3
"""Generates the SVG diagrams for the two IDEA install manuals.
Run:  python3 make-install-diagrams.py   (both manuals' build.py run it)
m1-*.svg -> ../install-manual-school-server/diagrams/, m2-*.svg -> ../install-manual-classroom-computer/diagrams/"""
import os
BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIRS = {"m1": os.path.join(BASE, "install-manual-school-server", "diagrams"),
        "m2": os.path.join(BASE, "install-manual-classroom-computer", "diagrams")}
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
        """Polyline; arrowheads are drawn as explicit triangles (no SVG markers: WeasyPrint ignores marker orient)."""
        d = f' stroke-dasharray="{dash}"' if dash else ''
        pts = list(pts)
        L = max(14, sw * 4.0); W = max(12, sw * 3.2)
        def head(tip, prev):
            import math
            dx, dy = tip[0] - prev[0], tip[1] - prev[1]; n = math.hypot(dx, dy) or 1
            ux, uy = dx / n, dy / n
            bx, by = tip[0] - ux * L, tip[1] - uy * L
            s.add(f'<polygon points="{tip[0]},{tip[1]} {bx - uy*W/2},{by + ux*W/2} {bx + uy*W/2},{by - ux*W/2}" fill="{color}"/>')
            return (bx + ux, by + uy)
        draw = pts[:]
        heads = []
        if arrow: heads.append((pts[-1], pts[-2])); draw[-1] = (pts[-1][0] - (pts[-1][0]-pts[-2][0]) / (abs(pts[-1][0]-pts[-2][0]) + abs(pts[-1][1]-pts[-2][1]) or 1) * L * 0.9,
                                                                 pts[-1][1] - (pts[-1][1]-pts[-2][1]) / (abs(pts[-1][0]-pts[-2][0]) + abs(pts[-1][1]-pts[-2][1]) or 1) * L * 0.9)
        if arrow_start: heads.append((pts[0], pts[1])); draw[0] = (pts[0][0] - (pts[0][0]-pts[1][0]) / (abs(pts[0][0]-pts[1][0]) + abs(pts[0][1]-pts[1][1]) or 1) * L * 0.9,
                                                                   pts[0][1] - (pts[0][1]-pts[1][1]) / (abs(pts[0][0]-pts[1][0]) + abs(pts[0][1]-pts[1][1]) or 1) * L * 0.9)
        pts_s = " ".join(f"{x},{y}" for x, y in draw)
        s.add(f'<polyline points="{pts_s}" fill="none" stroke="{color}" stroke-width="{sw}" stroke-linejoin="round" stroke-linecap="butt"{d}/>')
        for tip, prev in heads: head(tip, prev)
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
        os.makedirs(DIRS[name[:2]], exist_ok=True); open(os.path.join(DIRS[name[:2]], name), "w").write(svg)
        S.colors = set()

C_WAN, C_UP, C_POE1, C_POE2, C_PWR = "#e0a100", "#1f77b4", "#2ca02c", "#9467bd", "#d62728"

# ---------------------------------------------------------------- M1 wiring
def wiring():
    s = S(1140, 740)
    s.text(550, 32, "School server wiring - which cable goes into which port", 20, "bold")
    # Starlink dish
    s.add('<ellipse cx="90" cy="130" rx="55" ry="22" fill="#f4f4f4" stroke="#333" stroke-width="2"/>')
    s.add('<line x1="90" y1="152" x2="90" y2="190" stroke="#333" stroke-width="4"/>')
    s.text(90, 95, "Starlink dish", 14, "bold")
    s.text(90, 212, "(outside, clear\nview of the sky)", 11, fill="#555")
    # Starlink router
    s.rect(30, 300, 170, 120, fill="#f7f7f7")
    s.text(115, 325, "Starlink router", 14, "bold")
    s.text(115, 345, "Bypass mode = ON\n(its Wi-Fi is OFF)", 11, fill="#a00")
    s.port(92, 378, "ETH*", fill="#ffe9a8")
    s.line([(90, 190), (90, 260), (60, 260), (60, 300)], "#555", 5)
    s.text(150, 255, "Starlink cable\n(already attached)", 10, anchor="start", fill="#555")
    # Cudy router
    cx, cy = 300, 470
    s.rect(cx, cy, 380, 120, fill="#eef5ff")
    s.text(cx + 190, cy + 24, "Cudy WR3000S v1 (OpenWrt)  -  10.42.0.1", 14, "bold")
    s.text(cx + 190, cy + 42, "rear panel, left to right", 10, italic=True, fill="#555")
    s.port(cx + 12, cy + 55, "PWR", fill="#fbd5d5")
    s.port(cx + 70, cy + 55, "RST", fill="#ddd", w=36)
    labels = ["LAN4", "LAN3", "LAN2", "LAN1", "WAN"]
    xs = {}
    for i, l in enumerate(labels):
        x = cx + 116 + i * 52
        s.port(x, cy + 55, l, fill="#ffe9a8" if l == "WAN" else ("#cfe3ff" if l == "LAN1" else "#e8e8e8"))
        xs[l] = x + 23
    # wifi waves
    for r in (30, 50, 70):
        s.add(f'<path d="M {cx+190-r} {cy-8-r*0.2} A {r} {r} 0 0 1 {cx+190+r} {cy-8-r*0.2}" fill="none" stroke="#1f77b4" stroke-width="2.5"/>')
    s.text(cx + 190, cy - 90, "Wi-Fi: 'IDEA' (students) + 'IDEA-Teachers'", 12, "bold", fill="#1f77b4")
    # cable 1: starlink ETH -> WAN
    s.line([(115, 412), (115, 445), (xs["WAN"], 445), (xs["WAN"], cy + 55)], C_WAN, 5)
    s.badge(250, 445, 1, C_WAN)
    # Switch
    sx, sy = 740, 300
    s.rect(sx, sy, 330, 120, fill="#f0fff0")
    s.text(sx + 165, sy + 86, "TP-Link TL-SG105PE  -  10.42.0.10", 14, "bold")
    s.text(sx + 165, sy + 104, "ports 1-4 = PoE+ (power out), port 5 = normal", 10, italic=True, fill="#555")
    spx = {}
    for i in range(1, 6):
        x = sx + 15 + (i - 1) * 52
        s.port(x, sy + 12, f"{i}", fill="#c9f0c9" if i < 5 else "#cfe3ff")
        s.text(x + 23, sy + 60, "PoE+" if i < 5 else "uplink", 10, fill="#555")
        spx[i] = x + 23
    s.port(sx + 280, sy + 12, "DC", fill="#fbd5d5", w=38)
    # cable 2: LAN1 -> switch 5
    s.line([(xs["LAN1"], cy + 89), (xs["LAN1"], cy + 140), (1115, cy + 140), (1115, 270), (spx[5], 270), (spx[5], sy + 12)], C_UP, 5)
    s.badge(1115, 450, 2, C_UP)
    # Pis
    for k, (px, ip, port, col) in enumerate([(740, "10.42.0.2-.9 (DHCP)", 1, C_POE1), (920, "10.42.0.2-.9 (DHCP)", 2, C_POE2)]):
        py = 80
        s.rect(px, py, 150, 120, fill="#fff5f5")
        s.text(px + 75, py + 22, "Engine 1 (Pi 5)" if k == 0 else "Engines 2-4", 14, "bold")
        s.text(px + 75, py + 40, ip if k == 0 else "optional, ports 2-4", 12, fill="#333")
        s.text(px + 75, py + 56, "PoE+ HAT + NVMe", 10, fill="#555")
        s.port(px + 52, py + 72, "ETH", fill="#c9f0c9")
        s.text(px + 75, py + 140, "no USB-C power cable", 10, italic=True, fill="#a00")
        # cable
        xin = px + 75
        yy = 245 - k*16
        s.line([(spx[port], sy + 12), (spx[port], yy), (xin, yy), (xin, py + 106)], col, 5)
        s.badge((spx[port] + xin) / 2 if k else spx[port], yy, 3 + k, col)
    # power
    s.text(cx + 35, cy + 165, "12 V adapter (in the box)", 10, fill=C_PWR, anchor="start")
    s.line([(cx + 35, cy + 89), (cx + 35, cy + 145)], C_PWR, 3, dash="6,4")
    s.line([(sx + 318, sy + 33), (sx + 345, sy + 33), (sx + 345, sy + 180)], C_PWR, 3, dash="6,4")
    s.text(sx + 300, sy + 196, "53.5 V adapter", 10, fill=C_PWR)
    s.line([(40, 390), (40, 470)], C_PWR, 3, dash="6,4")
    s.text(40, 485, "Starlink PSU", 10, fill=C_PWR, anchor="start")
    # legend
    lx, ly = 40, 670
    s.text(lx, ly - 12, "Cables (all Cat5e/Cat6 Ethernet):", 12, "bold", anchor="start")
    items = [(1, C_WAN, "Starlink ETH -> Cudy WAN"), (2, C_UP, "Cudy LAN1 -> switch port 5"),
             (3, C_POE1, "switch port 1 -> Engine 1 (always)"), (4, C_POE2, "ports 2-4 -> one cable per extra Engine")]
    for i, (n, c, t) in enumerate(items):
        x = lx + i * 265
        s.badge(x + 12, ly + 12, n, c)
        s.text(x + 32, ly + 17, t, 12, anchor="start")
    s.text(lx, ly + 52, "* Starlink Gen 3 router: use its Ethernet (LAN) port. Gen 2 router: needs the Starlink Ethernet Adapter.  Dashed red = mains power adapters.", 10, anchor="start", fill="#555")
    s.save("m1-wiring.svg")

# ---------------------------------------------------------------- M1 zones
def zones():
    s = S(1100, 640)
    s.text(550, 30, "Network zones and what may talk to what", 20, "bold")
    s.rect(430, 250, 240, 120, fill="#eef5ff", sw=3)
    s.text(550, 285, "Cudy router", 16, "bold")
    s.text(550, 307, "OpenWrt firewall", 12)
    s.text(550, 327, "LAN 10.42.0.1 | IDEA 10.42.1.1", 11)
    s.text(550, 345, "IDEA-Teachers 10.42.2.1", 11)
    def zone(x, y, w, h, title, sub, fill):
        s.rect(x, y, w, h, fill=fill)
        s.text(x + w/2, y + 26, title, 15, "bold")
        s.text(x + w/2, y + 48, sub, 11, fill="#333")
    zone(420, 60, 260, 110, "WAN  (Starlink -> internet)", "zone: wan", "#fff7e0")
    zone(780, 230, 290, 170, "LAN  10.42.0.0/24  (wired)", "zone: lan\nEngines 10.42.0.2-.9 (by DHCP)\nswitch 10.42.0.10\n(Console: http://idea.local)", "#f0fff0")
    zone(30, 130, 300, 140, "Wi-Fi 'IDEA'  10.42.1.0/24", "zone: students\nlaptops / classroom computers\nclient isolation ON", "#fff0f0")
    zone(30, 380, 300, 140, "Wi-Fi 'IDEA-Teachers'  10.42.2.0/24", "zone: teachers\nteacher laptops / phones", "#f5f0ff")
    zone(420, 470, 260, 110, "tailscale0", "zone: tailscale\nadmin access to the router only", "#eefaff")
    G, R, O = "#2ca02c", "#d62728", "#ff7f0e"
    # students -> Pis allowed
    s.line([(330, 190), (760, 190), (760, 280), (780, 280)], G, 4, arrow=True)
    s.text(545, 183, "ALLOW: to the Engines (10.42.0.2-.9) only", 11, "bold", fill=G)
    # students -> WAN blocked
    s.line([(250, 130), (250, 100), (420, 100)], R, 4, dash="8,6", arrow=True)
    s.text(30, 70, "BLOCKED (no forwarding):\ninternet, outside DNS, VPNs", 11, "bold", fill=R, anchor="start")
    # teachers -> Pis
    s.line([(330, 430), (740, 430), (740, 360), (780, 360)], G, 4, arrow=True)
    s.text(545, 446, "ALLOW: to the Engines (10.42.0.2-.9)", 11, "bold", fill=G)
    # teachers -> WAN toggle
    s.line([(200, 380), (200, 330), (370, 330), (370, 140), (420, 140)], O, 4, dash="3,5", arrow=True)
    s.text(377, 230, "ON/OFF switch:\nrule 'Teachers-Internet'", 11, "bold", fill=O, anchor="start")
    # lan -> wan
    s.line([(925, 230), (925, 115), (680, 115)], G, 4, arrow=True)
    s.text(930, 170, "ALLOW: Pi updates\n+ Tailscale", 11, "bold", fill=G, anchor="start")
    # router input
    s.text(550, 400, "IDEA / Teachers -> router itself: only DHCP + DNS", 11, fill="#333")
    s.text(550, 620, "Green = allowed, red dashed = blocked, orange dotted = can be switched on/off. Replies to allowed traffic are always let back in.", 11, fill="#555")
    s.save("m1-zones.svg")

# ---------------------------------------------------------------- M1 flashing
def flashing():
    s = S(1100, 300)
    s.text(550, 30, "Flashing the Cudy WR3000S v1: two uploads (always over a LAN cable)", 18, "bold")
    boxes = [("Cudy stock firmware", "http://192.168.10.1", "#f4f4f4"),
             ("Cudy-signed OpenWrt\n(intermediate)", "http://192.168.1.1\nno Wi-Fi!", "#fff7e0"),
             ("Official OpenWrt\n25.12.5", "http://192.168.1.1", "#eef5ff"),
             ("IDEA school router", "http://10.42.0.1", "#f0fff0")]
    arrows = ["upload\ncudy_wr3000s-v1-\nsysupgrade_*.bin", "Flash image\n(squashfs-sysupgrade.bin)\nKeep settings: OFF", "run\nschool-router-\nsetup.sh"]
    for i, (t, sub, f) in enumerate(boxes):
        x = 20 + i * 275
        s.rect(x, 80, 200, 120, fill=f)
        s.text(x + 100, 115, t, 14, "bold")
        s.text(x + 100, 165, sub, 11, fill="#333")
        if i < 3:
            s.line([(x + 205, 140), (x + 270, 140)], "#1f77b4", 4, arrow=True)
            s.text(x + 237, 225, arrows[i], 10, fill="#1f77b4")
    s.save("m1-flash.svg")

# ---------------------------------------------------------------- M1 tailscale
def tailnet():
    s = S(1100, 360)
    s.text(550, 30, "Tailscale: who can reach what", 20, "bold")
    s.rect(420, 60, 260, 90, fill="#eefaff")
    s.text(550, 92, "Admins (group:admins)", 14, "bold")
    s.text(550, 115, "Koen, Justice, support staff\nlaptops", 11)
    for i, (n, x) in enumerate([("School A", 60), ("School B", 420), ("School C", 780)]):
        s.rect(x, 220, 260, 110, fill="#f0fff0")
        s.text(x + 130, 248, f"{n}  (tag:idea)", 14, "bold")
        s.text(x + 130, 272, ["router\nbrave-otter  (1 Engine)", "router\nquick-lynx - tidy-crane  (2)", "router\nbold-gecko - warm-finch\nsoft-wren - keen-ibis  (4)"][i], 11)
        s.line([(550, 150), (x + 130, 215)], "#2ca02c", 3, arrow=True)
    s.line([(320, 300), (420, 300)], "#d62728", 3, dash="6,5", arrow=True, arrow_start=True)
    s.line([(680, 300), (780, 300)], "#d62728", 3, dash="6,5", arrow=True, arrow_start=True)
    s.text(370, 290, "no", 12, "bold", fill="#d62728")
    s.text(730, 290, "no", 12, "bold", fill="#d62728")
    s.text(550, 352, "Green: admins reach every tag:idea device. Red: tag:idea reaches nothing, not even its own school. One tag, one key. No exit nodes.", 11, fill="#555")
    s.save("m1-tailscale.svg")

# ---------------------------------------------------------------- M2 Pi 400 wiring
def pi400():
    s = S(1100, 640)
    s.text(550, 30, "Raspberry Pi 400 or Pi 500 + Raspberry Pi Monitor: which cable goes where", 20, "bold")
    # Pi 400 rear strip (as seen from behind)
    px, py = 230, 330
    s.rect(px, py, 640, 150, fill="#fff0f3", stroke="#c51a4a", sw=3, rx=14)
    s.text(px + 320, py + 135, "Keyboard computer - back edge (schematic: follow the icons printed next to each port)", 12, "bold", fill="#c51a4a")
    ports = [("GPIO", 70, "#ddd"), ("SD", 46, "#ddd"), ("micro\nHDMI", 46, "#cfe3ff"), ("micro\nHDMI ", 46, "#eee"),
             ("USB-C\nPWR", 56, "#fbd5d5"), ("USB3", 46, "#bcd4ff"), ("USB3", 46, "#bcd4ff"), ("USB2", 46, "#fff"), ("ETH", 50, "#eee")]
    x = px + 20; pos = {}
    for lab, w, f in ports:
        s.rect(x, py + 30, w, 44, fill=f, stroke="#222", rx=4, sw=1.5)
        ls = lab.split("\n")
        for i, l in enumerate(ls):
            s.text(x + w/2, py + 50 + i*13 - (6 if len(ls) > 1 else -4), l, 10, "bold")
        pos.setdefault(lab, []).append(x + w/2)
        x += w + 18
    s.text(px + 320, py + 105, "microSD card with the IDEA client image in the SD slot, contacts facing down", 10, italic=True, fill="#555")
    # PSU
    s.rect(380, 560, 200, 60, fill="#fbd5d5")
    s.text(480, 585, "The computer's own USB-C PSU", 12, "bold")
    s.text(480, 603, "(Pi 400: 15 W, Pi 500: 27 W) -> wall socket", 10)
    pwr = pos["USB-C\nPWR"][0]
    s.line([(480, 560), (480, 520), (pwr, 520), (pwr, py + 74)], "#d62728", 5, arrow=True)
    s.badge(430, 520, 1, "#d62728")
    # monitor
    mx, my = 300, 70
    s.rect(mx, my, 500, 170, fill="#f7f7f7", sw=3)
    s.text(mx + 250, my + 30, "Raspberry Pi Monitor 15.6\" - rear connectors", 14, "bold")
    s.port(mx + 140, my + 70, "HDMI", fill="#cfe3ff", w=60)
    s.port(mx + 260, my + 70, "USB-C", fill="#fbd5d5", w=60, sub="power in")
    s.port(mx + 370, my + 70, "3.5mm", fill="#eee", w=60, sub="audio out")
    # HDMI cable
    h0 = pos["micro\nHDMI"][0]
    s.line([(h0, py + 30), (h0, 280), (mx + 170, 280), (mx + 170, my + 104)], "#1f77b4", 5, arrow=True)
    s.badge(h0 - 0, 300, 2, "#1f77b4")
    s.text(h0 - 18, 268, "micro-HDMI -> HDMI\n(either micro-HDMI port)", 10, anchor="end", fill="#1f77b4")
    # USB power to monitor
    u3 = pos["USB3"][0]
    s.line([(u3, py + 30), (u3, 300), (mx + 290, 300), (mx + 290, my + 104)], "#ff7f0e", 5, arrow=True)
    s.badge(u3 + 22, 300, 3, "#ff7f0e")
    s.text(u3 + 40, 285, "USB-A -> USB-C\n(monitor power cable)", 10, anchor="start", fill="#ff7f0e")
    # mouse
    u2 = pos["USB2"][0]
    s.add(f'<ellipse cx="{u2+150}" cy="560" rx="28" ry="40" fill="#fff" stroke="#333" stroke-width="2"/>')
    s.text(u2 + 150, 615, "mouse", 11)
    s.line([(u2, py + 74), (u2, 540), (u2 + 122, 540)], "#555", 4)
    s.badge(u2 + 60, 540, 4, "#555")
    s.text(40, 360, "Monitor runs in\n'Power Saving mode':\nbrightness max 50 %\nvolume max 60 %", 12, "bold", anchor="start", fill="#a05000")
    s.save("m2-wiring.svg")

def budget():
    s = S(1000, 330)
    s.text(500, 30, "USB power budget of a Pi 400 (5 V, current in amps) - from raspberrypi.com docs", 16, "bold")
    scale = 360  # px per amp
    x0 = 330
    rows = [("Pi 400: max for ALL USB ports together", 0, 1.2, "#2ca02c", "1.2 A limit"),
            ("Monitor, typical use (4.5-6.5 W)", 0.9, 1.3, "#ff7f0e", "0.9 - 1.3 A"),
            ("Monitor 'Full Power mode' needs", 0, 1.5, "#d62728", "1.5 A over USB-PD"),
            ("Mouse (approx.)", 0, 0.1, "#777", "~0.1 A")]
    for i, (lab, a, b, c, note) in enumerate(rows):
        y = 70 + i * 55
        s.text(x0 - 10, y + 22, lab, 12, anchor="end")
        if a > 0:
            s.rect(x0, y + 4, a * scale, 28, fill="#ffe6cc", stroke="#ffe6cc", rx=2, sw=1)
        s.rect(x0 + a * scale, y + 4, (b - a) * scale, 28, fill=c, stroke=c, rx=2, sw=1)
        s.text(x0 + b * scale + 8, y + 23, note, 11, anchor="start")
    s.add(f'<line x1="{x0+1.2*scale}" y1="60" x2="{x0+1.2*scale}" y2="290" stroke="#2ca02c" stroke-width="2" stroke-dasharray="5,4"/>')
    for a in (0, 0.5, 1.0, 1.5):
        s.text(x0 + a * scale, 305, f"{a:.1f} A", 10, fill="#555")
    s.text(500, 325, "Conclusion: it works only in Power Saving mode, with nothing else power-hungry on USB. Never force Full Power mode on a Pi 400.", 11, "bold", fill="#a00")
    s.save("m2-budget.svg")

def cards():
    s = S(1100, 260)
    s.text(550, 28, "Preparing many micro-SD cards", 18, "bold")
    steps = [("1. Get the IDEA image", "idea-client-26.04-<date>.img.xz\nfrom the IDEA team\n+ check SHA-256"),
             ("2. Write each card", "Raspberry Pi Imager\n'Use custom' -> the .img.xz\n(about 10 min/card)"),
             ("3. Home Engine (optional)", "idea-home.txt on the\nboot partition:\nthe Engine's sticker name"),
             ("4. First boot", "Pi 400 or Pi 500:\nno wizard, learner\nlogs in by itself"),
             ("5. Check + label", "IDEA icon opens the\nConsole; label the PC\nwith its idea-pc name")]
    for i, (t, sub) in enumerate(steps):
        x = 15 + i * 218
        s.rect(x, 60, 195, 150, fill=["#eef5ff", "#fff7e0", "#f4f4f4", "#f0fff0", "#fff0f0"][i])
        s.text(x + 97, 90, t, 13, "bold")
        s.text(x + 97, 125, sub, 10.5)
        if i < 4:
            s.line([(x + 197, 135), (x + 216, 135)], "#1f77b4", 4, arrow=True)
    s.text(550, 240, "One image for every Pi 400 and Pi 500. A card can move between the two models.", 11, fill="#555")
    s.save("m2-cards.svg")

def timeline():
    s = S(1100, 250)
    s.text(550, 28, "Where to do each step", 18, "bold")
    s.rect(20, 50, 640, 180, fill="#eef5ff")
    s.text(340, 78, "In Belgium (home internet as 'WAN')", 15, "bold")
    s.text(40, 108, "- check the pre-flashed IDEA router\n- join the Pis to Tailscale\n- set the switch password\n- install Raspberry Pi OS + IDEA Engine on each Pi\n- download App/content (Kolibri, Wikipedia ZIMs...)\n- full test with the final checklist, then label and pack", 12, anchor="start")
    s.rect(690, 50, 390, 180, fill="#f0fff0")
    s.text(885, 78, "On site (with Starlink)", 15, "bold")
    s.text(710, 108, "- install dish, activate Starlink\n- Starlink app: Bypass mode ON\n- cable everything (wiring diagram)\n- power on, wait 5 minutes\n- check Tailscale is back online\n- final checklist with a laptop", 12, anchor="start")
    s.save("m1-where.svg")

for f in (wiring, zones, flashing, tailnet, pi400, budget, cards, timeline):
    f()
print("ok")
