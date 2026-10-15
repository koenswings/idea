---
title: "IDEA Student Client – Browser, App Icons and Finding the Servers"
subtitle: "Follow-up to the student client image: Koen's feedback of 2026-10-15"
audience: "Proposal · Status: Draft"
---

**Author:** Steve (Lead Bot)
**Date:** 2026-10-15
**Status:** Draft
**Follows:** `2026-10-15-student-client-image.md` (idea#201, approved and merged; frozen)

# Problem or opportunity

Koen reviewed the merged student client image and asked for three changes:

1. **Chrome rather than Firefox** as the browser.
2. **Icons** for Nextcloud, Kolibri, Kiwix and the other apps, so students do not need bookmarks.
3. **No fixed server address.** The merged proposal points every bookmark at `10.42.0.2`. A school can have
   more than one server Pi, an app can live on any Engine, and an Engine can be switched off or moved.
   How does a client find the right server?

The merged proposal also says "Manual 2" for the client install manual. That label is confusing. Merged
proposals are frozen, so the correction is recorded here (see the last section).

# 1. Browser: Google Chrome (.deb), not Firefox

**Correction.** In chat we said Google Chrome does not exist for the Pi. That is no longer true: Google
shipped official **arm64 Linux** builds of Chrome on 30 July 2026 (`.deb` for Debian/Ubuntu,
`google-chrome-stable_current_arm64.deb`) [1][2]. So Koen can have real Chrome.

| Option | Package | Offline / updates | Verdict |
|---|---|---|---|
| **Google Chrome stable** | Official arm64 `.deb` from Google | Plain `.deb`; we remove Google's apt source and `apt-mark hold` it | **Recommended** |
| Chromium (Ubuntu) | `chromium-browser` is a **snap** wrapper | Snap refreshes must be held; snap sandbox blocks some features (e.g. app shortcuts) [3] | Not used |
| Chromium (xtradeb PPA) | Community `.deb` for 26.04 arm64 [4] | Needs pinning so the PPA does not replace other packages; unofficial | **Fallback** if Chrome fails on the Pi |
| Firefox (merged design) | Mozilla `.deb` | Works | Replaced, per Koen |

**How it is built into the image** (`tools/client-image/customise.sh`):

* Download the pinned Chrome `.deb` once, store it with its SHA-256 in the image build inputs, install with
  `apt install ./google-chrome-stable_<ver>_arm64.deb`.
* Delete `/etc/apt/sources.list.d/google-chrome.list` and the cron job that re-adds it, then
  `apt-mark hold google-chrome-stable`. This keeps the decision "updates off; a new tested image is the update".
* Chrome policy file in `/etc/opt/chrome/policies/managed/idea.json`: no first-run screen, no sign-in, no
  update checks, no default-browser prompt, home page = the IDEA start page (section 3).
* Chrome becomes the default browser; Firefox is not installed.
* **Snaps:** none in the student path (unchanged); any snap left in the base stays held.

**To test first (risk):** Chrome on arm64 is new. Check it starts and plays video on both a **Pi 400 and a
Pi 500** with the Ubuntu raspi kernel. If it fails, use the xtradeb Chromium `.deb` with the same hold and policy
(`/etc/chromium/policies/managed/`), and tell Koen.

# 2. Desktop and app-menu icons

Each app gets a `.desktop` file in `/usr/share/applications/` (app menu) and a copy on the learner desktop
(GNOME "Desktop Icons" extension, already in Ubuntu Desktop). Each opens Chrome in **app mode**: its own
window, no address bar, its own icon:

```
Exec=google-chrome-stable --app=http://idea.local/go/nextcloud
```

Icons: Nextcloud, Kolibri, Kiwix, Scratch, GeoGebra, plus **"School apps"** (the start page). New apps
added to an Engine later appear on the start page without a new image.

**Nextcloud desktop sync client: not recommended.** The computers are shared and students have no personal
accounts. A sync client would keep one student's files on the disk for the next student, and would be logged
in as whoever used it last. Nextcloud in the browser does not have this problem.

# 3. How a client finds the servers

## What the server manual sets up today

From `docs/manuals/install/install-manual-school-server/`:

* Every school uses the **same addresses**: router `10.42.0.1`, Pi #1 `10.42.0.2`, Pi #2 `10.42.0.3`
  (DHCP reservations on the router), students on Wi-Fi `10.42.1.0/24`, teachers on `10.42.2.0/24`.
* Each Pi gets a two-word **sticker name** (e.g. `brave-otter`), set as hostname. The Console address on the
  sticker is `http://<STICKER>.local` (mDNS via avahi).
* Engines already find each other with mDNS and share one Automerge store that lists every Engine, disk and
  running app. This is what the Console shows.

So two servers per school is already the normal design, and the router reservation only covers two Pis.

## Options

| Option | Works with many servers / moved apps? | Offline, no per-school config? | Notes |
|---|---|---|---|
| A. Fixed IP `10.42.0.2` in icons | **No.** Breaks if Pi #1 is off or the app is on Pi #2 | Yes | Merged design |
| B. Sticker names `<name>.local` | **No.** The name differs per school, so needs per-school config | No | Fine for humans, not for an image |
| C. One shared mDNS name `idea.local` answered by **every** Engine, serving a start page | **Yes.** Any live Engine answers; the page lists all Engines and apps | **Yes** | **Recommended** |
| D. Static page in the image that queries Engines itself | Yes, but must hard-code IPs or do mDNS in a browser (not possible) | Partly | Logic in the image goes stale; needs a reflash to change |

**mDNS on clients.** Ubuntu Desktop ships avahi and `libnss-mdns`, so `.local` names resolve for every
program, and Chrome uses the system resolver for them. mDNS does not cross subnets: the router must reflect
mDNS between `10.42.0.0/24` and the Wi-Fi subnets (`avahi` reflector or the OpenWrt `umdns`/`mdns-repeater`
package). The Console sticker address `http://<STICKER>.local` already needs this, so it is the same work,
done once in `school-router-setup.sh`, the same at every school.

## Recommendation: option C, the IDEA start page at `http://idea.local`

* **Every Engine** publishes the extra mDNS name `idea.local` and serves a small **start page** on port 80.
  Several Engines answering the same name is fine for a client: it uses the first answer, and any live Engine
  has the full picture.
* The page is built from the **Automerge store** the Console already uses: all Engines that are online, and the
  apps running on them, with big icons for students. A click opens the app on the Engine where it runs.
* **Short links** `http://idea.local/go/<app>` redirect to wherever that app is running now (if it runs on two
  Engines, the first online one). The desktop icons use these links, so icons never contain an IP or a school
  name.
* If the app is not running anywhere, the page says so in plain words ("Kolibri is not running. Ask your
  teacher.") instead of a browser error.
* **Fallback when mDNS fails** (e.g. the router reflector is missing): the router's DNS (dnsmasq) also answers
  `idea.local` → `10.42.0.2` and `10.42.0.3`. Set the same way at every school.
* Must coexist with the avahi hostname fix (`2026-10-13-avahi-hostname-clash.md`): publish `idea.local`
  through the Pi's own avahi, not a second mDNS responder. Several Engines publishing the same name must not
  trigger avahi's rename-on-conflict; Axle confirms the exact mechanism during implementation.

**Work:**

| Who | What |
|---|---|
| Axle (Engine) | publish `idea.local`; serve start page and `/go/<app>` on port 80 from the store |
| Pixel (Console) | start page UI (student-friendly, reuses Console components) |
| Atlas (Ops) | mDNS reflector + dnsmasq fallback in `school-router-setup.sh`; test with 2 Engines, one switched off |
| Client image worker | Chrome, policies, `.desktop` icons pointing at `idea.local/go/...` |
| Marco (docs) | client and server install manuals, tutorial |

**Test:** two Engines on one network, app on Engine 2 only: the icon opens it. Switch Engine 1 off: the start
page still loads. Move the app's disk to Engine 1: the same icon follows it. From the student Wi-Fi subnet.

# 4. Correction: "Manual 2"

The merged proposal says "Manual 2" for the client install manual. Use **"the client install manual"**
everywhere instead. The folder rename to `install-manual-client` stays a separate PR (as agreed). The
implementation branch (`feat/client-image-build`) does not use "Manual 2"; new docs must not either.

# Decision needed

1. Google Chrome `.deb` (held, no Google repo) as the browser, xtradeb Chromium as fallback?
2. Start page at `http://idea.local` on every Engine, icons via `/go/<app>`, router mDNS reflector + DNS
   fallback (option C)?

# References

[1] Google, "Download and install Google Chrome" (arm64 .deb for Debian/Ubuntu): https://support.google.com/chrome/answer/95346
[2] Calibre, "Chrome lands on arm64" (30 July 2026): https://calibreapp.com/blog/chrome-for-linux-arm64
[3] Ask Ubuntu, "Installing non-snap version of Chromium": https://askubuntu.com/questions/1569051
[4] XtraDeb Chromium: https://xtradeb.net/apps/chromium/
