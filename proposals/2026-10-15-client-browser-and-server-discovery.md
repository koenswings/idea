---
title: "IDEA Student Client – Browser, Console Shortcut and Finding the Servers"
subtitle: "Follow-up to the student client image: Koen's feedback of 2026-10-15"
audience: "Proposal · Status: Draft"
---

**Author:** Steve (Lead Bot)
**Date:** 2026-10-15
**Status:** Draft (revised 2026-10-15 after Koen's review: one Console shortcut, no app icons)
**Follows:** `2026-10-15-student-client-image.md` (idea#201, approved and merged; frozen)

# Problem or opportunity

Koen reviewed the merged student client image and asked for three changes:

1. **Chrome rather than Firefox** as the browser.
2. **An easy way to reach the apps** without typing an address. After review, Koen chose **one desktop
   shortcut that opens the Console**. No per-app icons: the Console already lists the apps and opens them, and
   per-app icons would replace that.
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
  update checks, no default-browser prompt, home page = the local start page `file:///usr/share/idea/start.html` (section 2).
* Chrome becomes the default browser; Firefox is not installed.
* **Snaps:** none in the student path (unchanged); any snap left in the base stays held.

**To test first (risk):** Chrome on arm64 is new. Check it starts and plays video on both a **Pi 400 and a
Pi 500** with the Ubuntu raspi kernel. If it fails, use the xtradeb Chromium `.deb` with the same hold and policy
(`/etc/chromium/policies/managed/`), and tell Koen.

# 2. One desktop shortcut: "IDEA" opens the Console of the home Engine

**Home Engine.** A client is always flashed **from** a specific Engine (Engine §10, Console Flash dialog).
The flash operation writes that Engine's unique mDNS name (e.g. `<engine-hostname>.local`) onto the card
as the client's **home Engine**: a one-line file `idea-home.txt` on the card's FAT boot partition, which
the client reads into `/etc/idea/home-engine` at boot. The name is **not** baked into the generic image, so
there is still one image for every school and every Engine.

The image has **one** shortcut, `idea-console.desktop`, in `/usr/share/applications/` (app menu) and on the
learner desktop (GNOME "Desktop Icons" extension, already in Ubuntu Desktop):

```
Name=IDEA
Exec=google-chrome-stable file:///usr/share/idea/start.html
```

`start.html` is a small local page in the image (also Chrome's home page). It goes through three steps:

1. Try the **home Engine's Console** (`http://<home-engine>.local`) with a quick probe, timeout ~1-2 s.
   If it answers, open it.
   * *Proposal (optional):* then try the **last Engine name that worked** from the sticker field below,
     remembered in the browser's `localStorage`.
2. Otherwise try **`http://idea.local`** (any Engine, section 3) the same way.
3. Otherwise show a friendly message: "No IDEA server found. Check that the computer is connected to the
   school network, or ask your teacher." No browser error screen.

**Sticker-name field.** Under the automatic attempt, `start.html` always shows a small field: "Or type the
name on the server's sticker". The sticker name is the Engine's mDNS hostname (e.g. `brave-otter`). On submit
the page tries `http://<name>.local` the same way and opens that Engine's Console, or shows a friendly
message: "No server called brave-otter was found. Check the name on the sticker and the network." When
automatic discovery fails (step 3), the field is shown **prominently** with that message.
Input is validated before use: lower-case letters, digits and hyphens only (a trailing `.local` is
stripped), 1-63 characters, no leading or trailing hyphen; anything else gets a friendly "letters, numbers
and - only" hint and is never put into a URL.

The student then picks an app in the Console, as today. There are **no per-app icons** and no list of apps
outside the Console: the Console stays the one place that lists and opens apps, so new apps on an Engine
appear without a new image.

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
| C. One shared mDNS name `idea.local` answered by **every** Engine, serving the Console | **Yes.** Any live Engine answers; its Console shows all Engines and apps | **Yes** | **Recommended** |
| D. Static page in the image that queries Engines itself | Yes, but must hard-code IPs or do mDNS in a browser (not possible) | Partly | Logic in the image goes stale; needs a reflash to change |

**mDNS on clients.** Ubuntu Desktop ships avahi and `libnss-mdns`, so `.local` names resolve for every
program, and Chrome uses the system resolver for them. mDNS does not cross subnets: the router must reflect
mDNS between `10.42.0.0/24` and the Wi-Fi subnets (`avahi` reflector or the OpenWrt `umdns`/`mdns-repeater`
package). The Console sticker address `http://<STICKER>.local` already needs this, so it is the same work,
done once in `school-router-setup.sh`, the same at every school.

## Recommendation: home Engine first, option C `http://idea.local` as fallback

* The client's first choice is its **home Engine** (section 2). `idea.local` is the fallback when the home
  Engine is off or moved.
* **Every Engine** publishes the extra mDNS name `idea.local`. A request to `http://idea.local` (port 80)
  serves or redirects to **that Engine's Console**. Nothing new is built for students: the Console already
  shows every Engine and app from the shared Automerge store, and opens an app on the Engine where it runs.
* No `/go/<app>` links and no extra start page; they would duplicate the Console.
* **Tested on the pool (Axle, 2026-10-15): several Engines cannot all hold `idea.local`.** avahi treats a
  second claim as a conflict: the first Engine wins and the others fail silently (no `idea-2.local` appears).
  With one holder it works well: 50/50 lookups answered in about 20 ms, Console HTTP 200 in 10/10 tries.
  A planned handover (holder stops cleanly) completes in about 6 s.
* **Chosen design: one holder, automatic takeover.** Every Engine runs a small `idea.local` publisher that
  registers the name through the Pi's own avahi over D-Bus (an address record, `-R`, no second mDNS responder,
  compatible with `2026-10-13-avahi-hostname-clash.md`). If the name is taken it retries every 2-5 s. The holder
  serves the Console; when it leaves, another Engine takes the name within seconds. No election via the store.
* **Remaining risk:** a real power-off sends no avahi goodbye, so clients may keep the dead address for up to
  the 120 s record TTL. This must be proven during implementation by an **automated power-cut test on a pool
  Pi** (not wizardly-hugle).
* **Backup:** the router's DNS (dnsmasq) also answers `idea.local` with `10.42.0.2` and `10.42.0.3`, set the
  same way at every school. Either way the shortcut in the image stays the same.

**Work:**

| Who | What |
|---|---|
| Axle (Engine) | Flash writes the home-Engine name (`idea-home.txt`) onto the card (Engine §10); `idea.local` publisher with retry/takeover; port 80 serves/redirects to the Console; automated power-cut test on a pool Pi |
| Pixel (Console) | Flash dialog shows which Engine becomes the home Engine |
| Atlas (Ops) | mDNS reflector + dnsmasq fallback in `school-router-setup.sh`; test with 2 Engines, one switched off |
| Client image worker | Chrome, policies, `start.html` (home Engine → optional last-used name → `idea.local` → friendly message; sticker-name field with validation), boot step reading `idea-home.txt`, the one `idea-console.desktop` shortcut |
| Marco (docs) | the client install manual, the school server install manual, the tutorial |

**Tests** (from the student Wi-Fi subnet, two Engines on one network):

* Client flashed from Engine 1: the shortcut opens Engine 1's Console.
* The same card works in a Pi 400 and a Pi 500, and the image file itself contains no Engine name.
* Home Engine off: the shortcut falls back to `idea.local` and opens the other Engine's Console.
* Type Engine 2's sticker name in the field: Engine 2's Console opens. Type an unknown name: friendly "not
  found" message. Type `Brave Otter!`, `../x` or a URL: rejected with the hint, no request is made.
* *(If the optional memory is accepted)* After using the field for Engine 2 and switching the home Engine
  off: Engine 2 is tried before `idea.local`.
* Both Engines off: the sticker field is shown prominently with the friendly "no server found, check the network" message appears, no browser error.
* Cut power to the `idea.local` holder: another Engine takes over and clients reach the Console within the
  120 s TTL (automated, pool Pi).

# 4. Correction: "Manual 2"

The merged proposal says "Manual 2" for the client install manual. Use **"the client install manual"**
everywhere instead. The folder rename to `install-manual-client` stays a separate PR (as agreed). The
implementation branch (`feat/client-image-build`) does not use "Manual 2"; new docs must not either.

# Decision needed

1. Google Chrome `.deb` (held, no Google repo) as the browser, xtradeb Chromium as fallback?
2. One desktop shortcut opening the local `start.html`: home Engine (written by the flash), then
   `http://idea.local`, then a friendly message; no per-app icons?
3. A sticker-name field on `start.html` (always small, prominent when discovery fails), hostname-safe input
   only?
4. *Optional:* remember the last name that worked (`localStorage`), tried after the home Engine and before
   `idea.local`?
5. `idea.local` with one holder and automatic takeover, router mDNS reflector, router DNS as backup?

# References

[1] Google, "Download and install Google Chrome" (arm64 .deb for Debian/Ubuntu): https://support.google.com/chrome/answer/95346
[2] Calibre, "Chrome lands on arm64" (30 July 2026): https://calibreapp.com/blog/chrome-for-linux-arm64
[3] Ask Ubuntu, "Installing non-snap version of Chromium": https://askubuntu.com/questions/1569051
[4] XtraDeb Chromium: https://xtradeb.net/apps/chromium/
