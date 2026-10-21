---
title: "IDEA Classroom Computer: Installation Manual"
subtitle: "Raspberry Pi 400 or Pi 500 + Raspberry Pi Monitor + the IDEA client image"
audience: "Version 2.2, 21 October 2026"
cover_logo: "yes"
---
**Status:** Authoritative (follows the student client image proposal and the student client browser proposal; the client image is not yet boot-tested on hardware, see the README) · **Maintained by:** Marco (with Atlas) · 21 October 2026 (v2.2: field-install review; preparation steps, teacher Wi-Fi switching and reset switching removed; image update from the Console)


# Introduction

This manual sets up one classroom computer: a Raspberry Pi 400 or Raspberry Pi 500 keyboard computer with the official 15.6" Raspberry Pi Monitor, running the **IDEA client image** (Ubuntu Desktop 26.04 with everything already set up). The same image works on both models.

## How to use this manual

*How the manual is organised and where to start.*

This manual is for installing a computer that the IDEA team has already prepared: its microSD card already has the IDEA client image. Work through it from start to finish for the first computer. For the next ones, the wiring (chapter 2), the first boot (chapter 4) and the checklist (chapter 5) are enough.

| Chapter | What you do |
|---|---|
| 1. What is in the boxes | Check that every part is there |
| 2. Wiring | Connect the computer and the monitor |
| 3. The IDEA client image | Read what the computer already does by itself |
| 4. First boot | Switch on, open the Console, check the Wi-Fi |
| 5. Checklist for each computer | Test each computer before you hand it over |
| 6. Update the IDEA client image | Put a newer image on a card, from the Console |
| Appendices | Troubleshooting and sources |

Each step has:

1. **Do:** what to do.
2. **✔ Check:** how to see that it worked.

Where the Pi 400 and the Pi 500 differ, the manual says so. Everywhere else, the text is the same for both. Numbers in square brackets, such as [1], point to the sources in Appendix B.

<div class="note">
<b>Conventions.</b>
<ul>
<li>IDEA default passwords follow the public convention <code>&lt;name&gt;911!</code>: the account or network name followed by <code>911!</code>. The student account <code>learner</code> has <b>no</b> password.</li>
<li>Values in <code>&lt;ANGLE BRACKETS&gt;</code> are placeholders. <code>&lt;SCHOOL&gt;</code>: the school name, for labels only. <code>&lt;STICKER&gt;</code>: the two-word sticker name of an Engine, for example <code>brave-otter</code>.</li>
</ul>
</div>

# 1. What is in the boxes

*Check that you have every part before you start.*

## 1.1 Raspberry Pi 400

*The parts of a Pi 400 computer.*

| ☐ | Item | Use |
|---|---|---|
| ☐ | Raspberry Pi 400 keyboard computer (US QWERTY keyboard) | The computer |
| ☐ | Raspberry Pi 15 W USB-C power supply (5.1 V / 3 A) | Powers the computer **and** the monitor |
| ☐ | Raspberry Pi USB mouse | Mouse |
| ☐ | 16 GB microSD card | The computer's card |

## 1.2 Raspberry Pi 500

*The parts of a Pi 500 computer.*

| ☐ | Item | Use |
|---|---|---|
| ☐ | Raspberry Pi 500 keyboard computer (US QWERTY keyboard) | The computer |
| ☐ | Raspberry Pi 27 W USB-C power supply (5.1 V / 5 A) | Powers the computer **and** the monitor |
| ☐ | Raspberry Pi USB mouse | Mouse |
| ☐ | 32 GB microSD card | The computer's card |

Use each power supply only with its own model: the 27 W supply with a Pi 500, the 15 W supply with a Pi 400 [1].

Check the **plug** of the power supply. Zimbabwe uses Type G (UK-style) and Type D sockets. If the plug is different, use a good adapter for each computer, or a power strip that takes the plug.

## 1.3 Raspberry Pi Monitor 15.6"

*The monitor and its cables.*

| ☐ | Item |
|---|---|
| ☐ | Raspberry Pi Monitor: 15.6", 1920 × 1080 IPS, built-in stand, 2 × 1.2 W speakers [2] |
| ☐ | **USB-A to USB-C cable**: powers the monitor from the computer [2] |
| ☐ | **micro-HDMI to HDMI cable**: carries the picture from the computer to the monitor |

Monitor connectors: **HDMI** in (standard size, HDMI 1.4), **USB-C** (power in only), **3.5 mm** audio out. On the back are buttons for standby, brightness up/down and volume up/down [2].

# 2. Wiring

*Connect the cables in the right order.*

The Pi 400 and the Pi 500 have the same ports on their back edge: two **micro-HDMI** ports, one **USB-C** power port, two blue **USB 3.0** ports, one white **USB 2.0** port, Ethernet, the **microSD** slot and the GPIO header [1]. Small icons are printed next to each port. The diagram shows the cables, not the exact order of the ports on your model: follow the icons.

![Keyboard computer and monitor wiring](diagrams/m2-wiring.svg)

| Cable | From | To |
|---|---|---|
| 1 | The computer's own power supply (wall socket) | Computer **USB-C power** port |
| 2 | Computer **micro-HDMI** port (either one) | Monitor **HDMI** (micro-HDMI to HDMI cable) |
| 3 | Computer **USB 3.0** port (blue) | Monitor **USB-C** (USB-A to USB-C cable) |
| 4 | Mouse | Computer **USB 2.0** port (white). Raspberry Pi recommends the white port for the mouse [1]. |

The monitor takes its power from the computer, so one power supply runs both. The monitor then works in **Power Saving mode**: brightness up to 50 % and volume up to 60 % [3]. Plug nothing else power-hungry into the computer's USB ports: only the mouse, and at most a USB stick.

**Do (in this order):**

1. Check that the microSD card is in the slot, contacts facing down.
2. Connect cable 2 (HDMI), cable 3 (monitor power) and cable 4 (mouse).
3. Connect cable 1 (power) **last**. The computer starts at once.

**✔ Check:**

* The computer's LED lights up. Within 10-20 seconds the monitor shows a picture (rainbow/boot screen or Ubuntu logo).
* Press the monitor's brightness-up button: the on-screen bar stops at 50. That is Power Saving mode, as expected [3].
* The picture stays stable for 5 minutes with no flashing.

If you get no picture, move cable 2 to the other micro-HDMI port.

# 3. The IDEA client image

Every classroom computer runs the same **IDEA client image**. It is the official Ubuntu Desktop **26.04.1 LTS** for Raspberry Pi with the IDEA settings built in. There is **no Ubuntu setup wizard** and nothing to configure by hand.

| What | In the IDEA client image |
|---|---|
| Models | **One image for the Pi 400 and the Pi 500.** It picks the right display settings for each model at boot, so a card can move between a Pi 400 and a Pi 500. |
| Student account | `learner`, logs in **automatically**, **no password**. It cannot change Wi-Fi (it cannot even list the networks), install software, add users or change the time. |
| Admin account | `admin` (hidden from the login screen), password `admin911!`. The password only works at the keyboard: remote login (SSH) accepts the IDEA support keys only. |
| Browser | **Google Chrome** is the only browser (Firefox is removed). Google is the default search engine. Chrome asks no first-run questions and never offers to save passwords. |
| The IDEA icon | One **IDEA** icon on the desktop and in the dock (the app bar on the left). It opens the IDEA start page, which finds the Console (section 4.2). Chrome also opens the start page as its home page. |
| Apps | LibreOffice (Writer, Calc, Impress), GCompris, Tux Paint, TuxMath, TuxType, KTurtle, Kalzium, Marble, Stellarium and a few games. No app asks first-start questions. |
| No pop-ups | No "choose a password for the new keyring", no Ubuntu welcome tour, no LibreOffice or GCompris first-start questions. |
| Updates | **Off.** The computer never updates itself, so it stays as tested. A newer image is written to the card from the Console (chapter 6). |
| Computer name | Set at first boot: `idea-pc-` plus the last 4 characters of the Pi's serial number, for example `idea-pc-3f2a`. |
| Wi-Fi | Joins the school's student Wi-Fi `IDEA` (password `idea911!`) by itself. It is the only network on the card (teacher computers: 4.3). |
| Keyboard, time zone | US keyboard layout (QWERTY), British English for dates and spelling, time zone Harare (Africa/Harare). |
| Reset on every restart | **On.** Every restart puts the computer back as it was written: files saved on the computer and changed settings are gone. Students save their work in Nextcloud. |

# 4. First boot

*Start the computer for the first time and check that it works.*

## 4.1 Start the computer

*Switch the computer on with the IDEA card.*

1. Check that the IDEA card is in (contacts facing down). Wire it as in chapter 2 and connect power last.
2. The first boot takes a few minutes: the card's partition is grown, and the computer gives itself its name and new keys. About 1-2 minutes after the very first start it restarts once by itself, to switch on the reset on restart. This happens only once.
3. The desktop of the `learner` account opens by itself. There is no wizard and no password.

**✔ Check:** you see the desktop with the **IDEA** icon, and the IDEA icon in the dock on the left. No pop-up asks for anything.

## 4.2 Opening the Console

*Open the school's IDEA Console, with one click or by typing its address.*

Every school uses the same addresses (*IDEA School Server: Installation Manual*). The Console is at `http://idea.local`, whichever and however many Engines the school has.

### 4.2.1 The IDEA icon and the start page

Click the **IDEA** icon (desktop or dock). Chrome opens the **IDEA start page**, which looks for the Console in this order, and opens the first one that answers:

1. the computer's **home Engine**, if the IDEA team gave it one;
2. the **last Engine** that worked on this computer;
3. **`http://idea.local`**: the IDEA router answers it with the Engines that are switched on, so it works with one Engine or many.

The start page always has a **sticker-name field**. If no Engine answers, it says so in plain words and asks for a sticker name: type the name on any Engine's sticker, for example `brave-otter`, and press Enter.

The Console lists **every** Engine of the school, whichever one you opened.

**✔ Check:** the IDEA Console opens within a few seconds and lists every Engine of the school.

### 4.2.2 The manual way: open the Console by its sticker name

This always works, also on a laptop, a phone or a computer without the IDEA image:

1. In any browser, type **`http://<STICKER>.local`**, the sticker name of any Engine, for example `http://brave-otter.local` (http, not https).
2. Set that address as the browser's **home page**, or ★ **bookmark** it.

`http://idea.local` works the same way. Sticker names work from the Wi-Fi too: the IDEA router passes them on between the wired network and the Wi-Fi.

## 4.3 Wi-Fi: IDEA or IDEA-Teachers

*Check that the computer is on the right Wi-Fi network.*

The pre-flashed IDEA school router creates two Wi-Fi networks (*IDEA School Server: Installation Manual*, "The school router's Wi-Fi networks and default passwords"). The passwords are the IDEA defaults until the school changes them:

| Who uses this computer | Network |
|---|---|
| Students (default) | `IDEA`, password `idea911!`: Console and apps only, no internet |
| Teacher's computer | `IDEA-Teachers`, password `idea-teachers911!`: Console and apps, plus internet (on by default; staff can switch it off) |

The IDEA image joins `IDEA` by itself; it is the only network on the card. Only a computer that the head teacher names for a teacher gets `IDEA-Teachers`: ask the IDEA team for it. Keep the `IDEA-Teachers` password for teacher computers.

If the school changes the `IDEA` password, every classroom computer needs the new one. Ask the IDEA team before you change it. A card that is written from the IDEA image comes back with `idea911!`.

**✔ Check:** at school, the Wi-Fi icon shows "IDEA". Ubuntu may say "limited connectivity" or show no internet: that is **normal** on IDEA.

## 4.4 The admin account and the reset on restart

*The account for repairs, and why changes do not last.*

You need `admin` only for repairs. On the login screen choose **Not listed?**, type `admin` and the password `admin911!`. Or, in a terminal of the learner account (**Ctrl+Alt+T**): `su - admin`.

Every restart undoes all changes, also an admin's. `sudo idea-client-mode status` shows whether the reset is on: it says `running: overlay`.

## 4.5 Final touches

*Small things to finish the computer.*

* Switch off: on a **Pi 400** with **Fn + F10**, on a **Pi 500** with the **power key** in the top-right corner of the keyboard [1], or the system menu → Power Off. Wait until the screen is black before you pull the plug.
* The monitor's speakers work over HDMI. If there is no sound, choose *HDMI* under **Settings → Sound → Output**.
* Label the card and the computer: `<SCHOOL> - idea-pc-____` (the name from **Settings → System → About**).

# 5. Checklist for each computer

*Check each computer before you hand it over.*

| ☐ | Test | Expected |
|---|---|---|
| ☐ | Wiring as in chapter 2, power plugged in last | Picture within about 20 s, no flashing |
| ☐ | Monitor brightness up | Bar stops at 50 (Power Saving mode, expected) |
| ☐ | First boot | Learner desktop opens by itself, no wizard, no pop-ups (no keyring question) |
| ☐ | About | Settings → System → About: Raspberry Pi 400 or 500, Ubuntu 26.04.1 LTS, name `idea-pc-____` |
| ☐ | Wi-Fi | Connected to `IDEA` (or `IDEA-Teachers` on a teacher's computer) |
| ☐ | IDEA icon (desktop and dock) | Opens the Console, which lists **every** Engine of the school |
| ☐ | Sticker name | `http://<STICKER>.local` in Chrome opens the Console |
| ☐ | Apps open from the Console | Kolibri / Nextcloud / Wikipedia open (and their Demo copies) |
| ☐ | Keyboard | Typing `@` and `"` gives those characters (US layout) |
| ☐ | Reset on restart | `sudo idea-client-mode status` (as admin) says `running: overlay` |
| ☐ | LibreOffice Writer | Opens straight away, no first-start questions |
| ☐ | No internet on IDEA | `https://example.com` does not open (expected) |
| ☐ | Power stable | No lightning-bolt or under-voltage warning during 10 minutes of use |
| ☐ | Label | Card and computer labelled `<SCHOOL> - idea-pc-____` |

# 6. Update the IDEA client image

*Put a newer IDEA client image on a computer's card, from the Console.*

The computer never updates itself. To give it a newer image, or to repair a broken card, an Engine writes the image to the card. The Engine keeps the verified client images, and the Console shows which version it has [4].

**Do:**

1. Switch the classroom computer off (4.5) and take its microSD card out.
2. Put the card in a **USB card reader** and plug the reader into one of the Engine's USB ports.
3. Open the Console (4.2) and select that **Engine**. Under **Client cards**, the line *Client image* shows the version on the Engine, and the reader appears with the card in it.
4. Click **Flash…** next to the card. Choose the image version (the newest is marked *current*) and click **Next**.
5. Check the summary (card, size, what is on it now, image). Everything on the card is wiped. Click **Wipe and flash**.
6. Wait while the Console shows the steps. Do not remove the card. When it says **Done – safe to remove**, unplug the reader and take the card out.
7. Put the card back in the computer and start it (4.1).

**✔ Check:** the computer starts as on its first boot (4.1) and passes the checklist (chapter 5). A freshly written card shows as *Ubuntu* in the Console until it has been used once; that is normal.

Nothing on the computer needs saving first: students keep their work on the Engine (Nextcloud).

# Appendix A. Troubleshooting

*Quick fixes for common problems.*

| Problem | Try |
|---|---|
| No picture | Move cable 2 to the other micro-HDMI port. Check that the monitor isn't in standby (press ⏻). |
| Monitor flashes on and off | Turn brightness and volume down [3]. Unplug extra USB devices. Last resort: a separate USB-C supply for the monitor. |
| Very slow first boot | That is normal: the first boot resizes the card. Give it 5 minutes. |
| Wi-Fi 'IDEA' not shown | Is the router on? (*IDEA School Server: Installation Manual*, "Router: check the pre-flashed IDEA router".) |
| Start page says no Engine found | Is an Engine switched on? Type a sticker name in the field, or try `http://<STICKER>.local` (4.2.2). Check that the computer is on IDEA/IDEA-Teachers. |
| `IDEA-Teachers` is not in the Wi-Fi menu | Expected: the student account can't list networks. Ask the IDEA team (4.3). |
| Files or settings are gone after a restart | Expected: the reset on restart (4.4). Save work in Nextcloud. |
| An app in the Console does not open | Its Engine may be switched off or at another school: the Console still shows its apps (known problem, no fix yet). Use the apps of this school's Engine. |
| Desktop IDEA icon shows a red cross | Use the IDEA icon in the dock; log out and in once. Report it to the IDEA team. |
| Something is broken beyond repair | Write the card again from the Console (chapter 6). Nothing on the computer needs saving: students keep their work on the Engine (Nextcloud). |

# Appendix B. Sources (read on 12-21 October 2026)

*Where the facts in this manual come from.*

1. Raspberry Pi documentation, *Keyboard computers* (Pi 400 and Pi 500 kit contents, ports, power input 15 W / 27 W supply, power key on the Pi 500, Fn + F10 on the Pi 400, mouse in the white USB 2.0 port): `raspberrypi.com/documentation/computers/keyboard-computers.html`, and *Power supply* (15 W supply for the Pi 400, 27 W for the Pi 5 family): `raspberrypi.com/documentation/computers/raspberry-pi.html#power-supply`.
2. Raspberry Pi, *Raspberry Pi Monitor* product page (specification, USB-C power cable, buttons): `https://www.raspberrypi.com/products/raspberry-pi-monitor/`.
3. Raspberry Pi documentation, *Raspberry Pi Monitor* (Power Saving mode when powered from a Raspberry Pi: 0-50 % brightness / 0-60 % volume; Full Power mode needs 1.5 A USB-PD): `raspberrypi.com/documentation/accessories/monitor.html`.
4. IDEA Console code (`agent-console-dev`, main), *Client cards* and *Flash client card* (idea#201 §10.2); IDEA Engine code (`agent-engine-dev`, main), `idea-flash-card` and the client image store `/var/lib/idea/client-images`.
5. IDEA client image build (`idea` repository, `tools/client-image`) (`client-image.conf`, `browser.sh` Chrome policy, `README.md` "Reset on reboot", `files/50-idea-learner.rules`, `files/idea-client-mode`) and issue #285 (learner Wi-Fi lock).
