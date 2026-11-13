#!/usr/bin/env python3
"""Render architecture.png (house colours) from the same structure as architecture.dot."""
from math import hypot
from pathlib import Path

import matplotlib.pyplot as plt
from matplotlib.patches import FancyArrowPatch, FancyBboxPatch

OUT = Path(__file__).resolve().parent / "architecture.png"

NAVY = "#0b1f33"
NAVY2 = "#1e3a5f"
BLUE = "#1d4ed8"
EXIST_FILL, EXIST_EDGE = "#f8fafc", "#1e3a5f"
NEW_FILL, NEW_EDGE, NEW_TEXT = "#fef3c7", "#b45309", "#9a3412"
DEF_FILL, DEF_EDGE = "#f8fafc", "#64748b"
ISO_FILL, ISO_EDGE, ISO_TEXT = "#e2e8f0", "#94a3b8", "#64748b"
KIT_BG, TS_BG, IDEA_BG = "#eef2f6", "#dbeafe", "#f1f5f9"
TEAL, PULL, INK, MUTED, ALERT = "#0f766e", "#1d4ed8", "#0f172a", "#475569", "#9f1239"

# Flow colours
C_LAN = "#1e3a5f"       # school LAN / HTTP
C_USAGE = "#b45309"     # usage data on the kit and on idea
C_HOST = "#334155"      # Engine hosts the usage module
C_UPLINK = "#0f766e"    # Tailscale uplink / LocalAPI
C_SSH = "#1d4ed8"       # E1 pull over SSH
C_HTTPS = "#0369a1"     # dashboard → browser
C_DEFER = "#64748b"     # D2 later

# Near print width so type does not collapse when the PNG is scaled to the PDF column.
FIG_W, FIG_H, DPI = 7.55, 5.92, 230
ARROW_LW = 1.65


def rbox(ax, x, y, w, h, fc, ec, lw=1.05, ls="-", radius=0.012, zorder=3):
    ax.add_patch(FancyBboxPatch(
        (x, y), w, h,
        boxstyle=f"round,pad=0.002,rounding_size={radius}",
        facecolor=fc, edgecolor=ec, linewidth=lw, linestyle=ls,
        mutation_aspect=FIG_W / FIG_H, zorder=zorder,
    ))


def txt(ax, x, y, s, size=7.4, color=INK, weight="normal", ha="center", va="center",
        style="normal", zorder=4):
    ax.text(
        x, y, s, fontsize=size, color=color, fontweight=weight, fontstyle=style,
        ha=ha, va=va, zorder=zorder, fontfamily="DejaVu Sans", linespacing=1.22,
    )


def point_along(pts, frac):
    if len(pts) == 1:
        return pts[0]
    seglens = [hypot(b[0] - a[0], b[1] - a[1]) for a, b in zip(pts, pts[1:])]
    total = sum(seglens) or 1.0
    target = max(0.0, min(1.0, frac)) * total
    acc = 0.0
    for (x1, y1), (x2, y2), sl in zip(pts, pts[1:], seglens):
        if acc + sl >= target:
            t = 0.0 if sl == 0 else (target - acc) / sl
            return (x1 + t * (x2 - x1), y1 + t * (y2 - y1))
        acc += sl
    return pts[-1]


def flow(ax, pts, color, lw=ARROW_LW, ls="-", label=None, label_frac=0.5,
         label_dx=0.0, label_dy=0.0, arrowstyle="-|>", mutation_scale=13.5,
         label_size=6.15, label_pad=0.18):
    """Polyline arrow. Label sits on the path (white background) so it stays readable."""
    pts = [(float(p[0]), float(p[1])) for p in pts]
    if len(pts) < 2:
        return
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    ax.plot(
        xs, ys, color=color, linewidth=lw, linestyle=ls,
        solid_capstyle="round", solid_joinstyle="miter",
        dash_capstyle="round", zorder=2, clip_on=True,
    )
    ax.add_patch(FancyArrowPatch(
        pts[-2], pts[-1],
        arrowstyle=arrowstyle, mutation_scale=mutation_scale,
        linewidth=lw, color=color, linestyle=ls,
        shrinkA=0.4, shrinkB=0.4, zorder=2.2, clip_on=True,
    ))
    if label:
        x, y = point_along(pts, label_frac)
        ax.text(
            x + label_dx, y + label_dy, label,
            fontsize=label_size, color=color, ha="center", va="center",
            zorder=6, fontfamily="DejaVu Sans", linespacing=1.15,
            bbox=dict(boxstyle=f"round,pad={label_pad}", facecolor="white",
                      edgecolor="none", alpha=0.94),
        )


def shaft(ax, pts, color, lw=ARROW_LW, ls="-"):
    """Line without an arrowhead (for buses)."""
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    ax.plot(
        xs, ys, color=color, linewidth=lw, linestyle=ls,
        solid_capstyle="round", solid_joinstyle="miter", zorder=2, clip_on=True,
    )


def fan(ax, origin, targets, y_bus, color, label=None, label_dx=0.0, label_dy=0.0):
    """Orthogonal fan-out: origin → bus → each target, arrowheads only on the drops."""
    ox, oy = origin
    shaft(ax, [(ox, oy), (ox, y_bus)], color)
    txs = [t[0] for t in targets] + [ox]
    shaft(ax, [(min(txs), y_bus), (max(txs), y_bus)], color)
    if label:
        ax.text(
            (min(txs) + max(txs)) / 2 + label_dx, y_bus + label_dy, label,
            fontsize=6.15, color=color, ha="center", va="center",
            zorder=6, fontfamily="DejaVu Sans",
            bbox=dict(boxstyle="round,pad=0.18", facecolor="white",
                      edgecolor="none", alpha=0.94),
        )
    for tx, ty in targets:
        flow(ax, [(tx, y_bus), (tx, ty)], color)


STYLES = {
    "exist": (EXIST_FILL, EXIST_EDGE, INK, 1.05, "-"),
    "new": (NEW_FILL, NEW_EDGE, NEW_TEXT, 1.15, "-"),
    "defer": (DEF_FILL, DEF_EDGE, MUTED, 1.05, "--"),
    "iso": (ISO_FILL, ISO_EDGE, ISO_TEXT, 1.0, "-"),
    "acl": ("#eff6ff", BLUE, "#1e3a8a", 1.1, "-"),
    "people": ("#e0f2fe", "#0369a1", "#0c4a6e", 1.1, "-"),
}


def node(ax, x, y, w, h, lines, kind="exist"):
    """lines: first is the title; the rest are body. Vertically centred as a block."""
    fc, ec, tc, lw, ls = STYLES[kind]
    rbox(ax, x, y, w, h, fc, ec, lw=lw, ls=ls, zorder=3)
    n = len(lines)
    gap = h / (n + 1.15)
    top = y + h - gap * 0.85
    for i, line in enumerate(lines):
        yy = top - i * gap
        txt(ax, x + w / 2, yy, line,
            size=8.2 if i == 0 else 7.15,
            color=tc, weight="bold" if i == 0 else "normal")
    return (x, y, w, h)


def cx(b): return b[0] + b[2] / 2
def cy(b): return b[1] + b[3] / 2
def top(b): return b[1] + b[3]
def bot(b): return b[1]
def left(b): return b[0]
def right(b): return b[0] + b[2]


def chip(ax, x, y, kind, label):
    fc, ec, _, lw, ls = STYLES[kind]
    rbox(ax, x, y, 1.35, 2.15, fc, ec, lw=1.0, ls=ls, radius=0.01)
    txt(ax, x + 1.65, y + 1.05, label, size=6.6, color=NAVY2, ha="left")


def flow_key(ax, x, y, color, label, ls="-"):
    shaft(ax, [(x, y), (x + 2.6, y)], color, ls=ls)
    ax.add_patch(FancyArrowPatch(
        (x + 1.6, y), (x + 2.6, y),
        arrowstyle="-|>", mutation_scale=11, linewidth=ARROW_LW,
        color=color, linestyle=ls, shrinkA=0, shrinkB=0, zorder=2.2,
    ))
    txt(ax, x + 3.0, y, label, size=6.05, color=NAVY2, ha="left")


def main():
    fig, ax = plt.subplots(figsize=(FIG_W, FIG_H), dpi=DPI)
    ax.set_xlim(0, 100)
    ax.set_ylim(0, 100)
    ax.set_axis_off()
    fig.patch.set_facecolor("white")
    ax.set_facecolor("white")

    txt(ax, 0.9, 97.65,
        "Field-usage monitoring  ·  new and existing modules",
        size=8.8, color=NAVY, weight="bold", ha="left")
    chip(ax, 56.6, 95.95, "exist", "Existing")
    chip(ax, 69.6, 95.95, "new", "New in this proposal")
    chip(ax, 88.6, 95.95, "defer", "Deferred (D2)")

    # Clusters sit under arrows (zorder 0) so flows remain visible across them.
    rbox(ax, 0.45, 5.35, 39.55, 88.35, KIT_BG, NAVY2, lw=1.25, radius=0.016, zorder=0)
    txt(ax, 20.2, 91.35, "Field kit  ·  one school", size=8.3, color=NAVY, weight="bold")
    txt(ax, 20.2, 89.35, "Works fully offline. Usernames never leave.", size=6.3, color=MUTED)

    rbox(ax, 41.15, 20.55, 14.55, 54.05, TS_BG, BLUE, lw=1.25, radius=0.016, zorder=0)
    txt(ax, 48.42, 72.85, "Tailscale tailnet", size=7.8, color="#1e3a8a", weight="bold")

    rbox(ax, 56.85, 5.35, 42.55, 88.35, IDEA_BG, NAVY, lw=1.25, radius=0.016, zorder=0)
    txt(ax, 78.1, 91.35, "idea  ·  programme hub Pi", size=8.3, color=NAVY, weight="bold")
    txt(ax, 78.1, 89.35, "Stores every uplink sample and every usage summary.", size=6.3, color=MUTED)

    # —— School LAN ———————————————————————————————————————————
    clients = node(ax, 1.65, 81.90, 15.20, 5.90, ["Classroom clients", "shared OS login"], "exist")
    router = node(ax, 20.35, 81.90, 16.50, 5.90, ["Router", "school Wi-Fi"], "exist")

    kolibri = node(ax, 1.65, 71.55, 11.40, 6.55, ["Kolibri", "own database"], "exist")
    nextcloud = node(ax, 13.60, 71.55, 13.00, 6.55, ["Nextcloud", "+ DB + Collabora"], "exist")
    kiwix = node(ax, 27.15, 71.55, 9.70, 6.55, ["Kiwix", "ZIM reader"], "exist")

    k_hook = node(ax, 1.65, 61.15, 11.40, 6.35, ["Kolibri hook", "read-only query"], "new")
    nc_hook = node(ax, 13.60, 61.15, 13.00, 6.35, ["Nextcloud hook", "read-only query"], "new")
    kx_proxy = node(ax, 27.15, 61.15, 9.70, 6.35, ["Kiwix proxy", "access log"], "new")

    engine = node(ax, 1.65, 45.35, 16.00, 11.70,
                  ["Engine  (pm2)", "Console on port 80", "Automerge store", "usage never stored here"],
                  "exist")
    usage = node(ax, 21.85, 45.35, 15.00, 11.70,
                 ["Usage module (new)", "Presence sampler (5 min)", "Hook runner", "or idea-usage process"],
                 "new")

    summaries = node(ax, 1.65, 31.15, 23.85, 10.40,
                     ["Day summaries", "/var/lib/idea/usage/<day>/",
                      "<instanceId>.json · pi-owned", "role-level counts, no names"],
                     "new")

    export = node(ax, 1.65, 18.55, 16.15, 9.05, ["Restricted export", "SSH forced command"], "new")
    kit_ts = node(ax, 21.15, 18.55, 15.70, 9.05, ["Tailscale client", "tag:idea"], "exist")

    d2 = node(ax, 1.65, 9.55, 23.85, 7.15,
              ["D2 Console Usage panel", "later · this kit only · not v1"], "defer")

    txt(ax, 20.2, 7.85, "Kits stay on Engine commit adfd9d3 until a field update.",
        size=5.95, color=MUTED)
    txt(ax, 20.2, 6.30, "Every other kit is identical: tag:idea, no kit-to-kit path.",
        size=5.95, color=MUTED)

    # —— Tailscale ——————————————————————————————————————————————
    acl = node(ax, 41.95, 54.15, 12.70, 14.60,
               ["ACL  (idea#375)", "tag:idea-hub on idea", "→ tag:idea port 22", "no kit-to-kit traffic"], "acl")
    uplink = node(ax, 41.95, 41.85, 12.70, 9.35, ["Uplink events", "Online  /  LastSeen"], "exist")
    pullb = node(ax, 41.95, 23.55, 12.70, 15.30,
                 ["E1 pull", "restricted SSH", "role-level counts", "until reachable"], "new")

    # —— idea ——————————————————————————————————————————————————
    idea_eng = node(ax, 58.05, 80.85, 18.55, 7.15, ["Engine (existing)", "Console :80 · Automerge"], "exist")
    milk = node(ax, 78.00, 80.85, 19.55, 7.15, ["MilkWise", ":3333 / :3334 · untouched"], "iso")

    rbox(ax, 58.05, 20.85, 39.50, 56.85, "#fffbeb", NEW_EDGE, lw=1.15, radius=0.014, zorder=0)
    txt(ax, 77.80, 75.90, "app-usage-dashboard   ·   an IDEA App on idea", size=7.15, color=NEW_TEXT, weight="bold")
    txt(ax, 77.80, 73.85, "No Docker socket. Does not query school databases itself.", size=6.05, color=NEW_TEXT)

    collector = node(ax, 59.25, 56.85, 36.90, 12.55,
                     ["Collector  ·  no LLM", "Tailscale LocalAPI trigger (watch + 60s poll)",
                      "every state change and every 5-min check",
                      "on kit-online: pull summaries since last success"], "new")
    sqlite = node(ax, 59.25, 41.55, 21.55, 11.35,
                  ["SQLite store", "uplink history + day summaries",
                   "help events · pull log", "on idea only · not in git"], "new")
    backup = node(ax, 83.55, 41.55, 12.60, 11.35, ["Daily backup", "copy of SQLite"], "new")
    web = node(ax, 59.25, 26.15, 36.90, 11.55,
               ["Web dashboard", "scorecard, presence, per-instance charts",
                "grey = no data · never retracts a kit", "port not :80, :3333 or :3334"], "new")
    people = node(ax, 66.55, 7.85, 24.40, 9.55,
                  ["Koen / Marco browser", "dashboard over Tailscale"], "people")

    # —— Flows ——————————————————————————————————————————————————
    # School LAN: clients → router → app instances
    flow(ax, [(right(clients), cy(clients)), (left(router), cy(router))],
         C_LAN, label="HTTP")
    y_lan = 80.05
    fan(ax, (cx(router), bot(router)),
        [(cx(kolibri), top(kolibri)), (cx(nextcloud), top(nextcloud)), (cx(kiwix), top(kiwix))],
        y_lan, C_LAN, label="HTTP (school LAN)")

    # clients (via the LAN / right corridor) → Kiwix proxy
    x_right = 38.15
    flow(ax, [(right(router), cy(router)), (x_right, cy(router)),
              (x_right, cy(kx_proxy)), (right(kx_proxy), cy(kx_proxy))],
         C_LAN, label="to proxy", label_frac=0.78, label_dx=0.35)

    # Hooks query the apps (request direction)
    flow(ax, [(cx(k_hook), top(k_hook)), (cx(kolibri), bot(kolibri))],
         C_USAGE, label="read-only query")
    flow(ax, [(cx(nc_hook), top(nc_hook)), (cx(nextcloud), bot(nextcloud))],
         C_USAGE, label="read-only query")
    flow(ax, [(cx(kx_proxy), top(kx_proxy)), (cx(kiwix), bot(kiwix))],
         C_USAGE, label="access log")

    # Hook runner → each hook (docker exec)
    y_exec = 59.45
    fan(ax, (cx(usage), top(usage)),
        [(cx(k_hook), bot(k_hook)), (cx(nc_hook), bot(nc_hook)), (cx(kx_proxy), bot(kx_proxy))],
        y_exec, C_USAGE, label="docker exec")

    # Engine hosts the usage module; Automerge is not on this path
    flow(ax, [(right(engine) + 0.45, cy(engine)), (left(usage) - 0.45, cy(usage))],
         C_HOST, label="hosts", arrowstyle="<|-|>", label_dx=-0.45, label_dy=0.0, label_pad=0.08)

    # Presence sampler (inside the usage module) writes day summaries
    flow(ax, [(24.00, bot(usage)), (24.00, top(summaries))],
         C_USAGE, label="write", label_dx=2.55)

    # Day summaries → restricted export
    flow(ax, [(8.00, bot(summaries)), (8.00, top(export))],
         C_USAGE, label="read")

    # D2 later (dashed), routed down the kit's right corridor so it does not
    # cross the SSH lane or pass through the export / Tailscale-client boxes.
    flow(ax, [(right(summaries), cy(summaries)), (x_right, cy(summaries)),
              (x_right, cy(d2)), (right(d2), cy(d2))],
         C_DEFER, ls="--", label="later", label_frac=0.58)

    # Tailscale client → uplink events → collector (LocalAPI)
    x_up = 40.50
    flow(ax, [(right(kit_ts), cy(kit_ts)), (x_up, cy(kit_ts)),
              (x_up, cy(uplink)), (left(uplink), cy(uplink))],
         C_UPLINK, label="uplink events", label_frac=0.45, label_dx=-2.15)
    x_api = 55.35
    flow(ax, [(right(uplink), cy(uplink)), (x_api, cy(uplink)),
              (x_api, 64.20), (left(collector), 64.20)],
         C_UPLINK, label="LocalAPI", label_frac=0.97, label_dx=0.55, label_dy=1.85)

    # Collector → E1 pull → restricted export (SSH, counts come back)
    x_pull = 56.45
    y_ssh = 30.50
    flow(ax, [(left(collector), 58.40), (x_pull, 58.40),
              (x_pull, y_ssh), (left(pullb), y_ssh)],
         C_SSH)
    x_ssh = 18.50
    flow(ax, [(left(pullb) + 0.15, y_ssh), (x_ssh, y_ssh),
              (x_ssh, cy(export)), (right(export) - 0.2, cy(export))],
         C_SSH, label="SSH · role-level counts", label_frac=0.36, arrowstyle="<|-|>")

    # idea store and dashboard
    flow(ax, [(cx(sqlite), bot(collector)), (cx(sqlite), top(sqlite))],
         C_USAGE, label="write")
    flow(ax, [(right(sqlite), cy(sqlite)), (left(backup), cy(backup))],
         C_USAGE, label="copy")
    flow(ax, [(cx(sqlite), bot(sqlite)), (cx(sqlite), top(web))],
         C_USAGE, label="read")
    flow(ax, [(cx(people), bot(web)), (cx(people), top(people))],
         C_HTTPS, label="HTTPS (tailnet)")

    # MilkWise deliberately has no arrows.

    # Flow-colour key
    flow_key(ax, 1.2, 3.82, C_LAN, "school LAN / HTTPS")
    flow_key(ax, 22.6, 3.82, C_USAGE, "usage data")
    flow_key(ax, 38.4, 3.82, C_UPLINK, "uplink / LocalAPI")
    flow_key(ax, 57.8, 3.82, C_SSH, "SSH pull")
    flow_key(ax, 73.4, 3.82, C_DEFER, "deferred (D2)", ls="--")

    txt(ax, 50.0, 1.40,
        "Nothing usage-related is written to the shared Automerge store, so one school’s counts can never appear at another school.",
        size=6.25, color=ALERT)

    fig.subplots_adjust(left=0.012, right=0.988, top=0.99, bottom=0.012)
    fig.savefig(OUT, dpi=DPI, facecolor="white")
    print(f"wrote {OUT}  {OUT.stat().st_size} bytes  {int(FIG_W*DPI)}x{int(FIG_H*DPI)}")
    plt.close(fig)


if __name__ == "__main__":
    main()
