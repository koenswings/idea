---
title: "IDEA Field Install Manual: Classroom Computer"
subtitle: "Raspberry Pi 400 or Pi 500 + Raspberry Pi Monitor + the IDEA client image"
audience: "Version 2.5, 25 October 2026"
cover_logo: "yes"
---
**Status:** Authoritative · **Maintained by:** Marco (with Atlas) · 25 October 2026 (v2.5: sticker names, idea.local as the easy way in; v2.4: opening paragraph restored, wiring diagram arrows fixed)


# Introduction

This manual sets up one classroom computer: a Raspberry Pi 400 or Raspberry Pi 500 keyboard computer with the official 15.6" Raspberry Pi Monitor, running the **IDEA client image** (Ubuntu Desktop 26.04 with everything already set up). The same image works on both models.

Each step has:

1. **Do:** what to do.
2. **✔ Check:** how to see that it worked.

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

| ☐ | Item | Use |
|---|---|---|
| ☐ | Raspberry Pi 400 keyboard computer (US QWERTY keyboard) | The computer |
| ☐ | Raspberry Pi 15 W USB-C power supply (5.1 V / 3 A) | Powers the computer **and** the monitor |
| ☐ | Raspberry Pi USB mouse | Mouse |
| ☐ | 16 GB microSD card | The computer's card |

## 1.2 Raspberry Pi 500

| ☐ | Item | Use |
|---|---|---|
| ☐ | Raspberry Pi 500 keyboard computer (US QWERTY keyboard) | The computer |
| ☐ | Raspberry Pi 27 W USB-C power supply (5.1 V / 5 A) | Powers the computer **and** the monitor |
| ☐ | Raspberry Pi USB mouse | Mouse |
| ☐ | 32 GB microSD card | The computer's card |

## 1.3 Raspberry Pi Monitor 15.6"

| ☐ | Item |
|---|---|
| ☐ | Raspberry Pi Monitor: 15.6", 1920 × 1080 IPS, built-in stand, 2 × 1.2 W speakers |
| ☐ | **USB-A to USB-C cable**: powers the monitor from the computer |
| ☐ | **micro-HDMI to HDMI cable**: carries the picture from the computer to the monitor |

# 2. Wiring

*Connect the cables in the right order.*

The Pi 400 and the Pi 500 have the same ports on their back edge: two **micro-HDMI** ports, one **USB-C** power port, two blue **USB 3.0** ports, one white **USB 2.0** port, Ethernet, the **microSD** slot and the GPIO header. Small icons are printed next to each port. The diagram shows the cables, not the exact order of the ports on your model: follow the icons.

![Keyboard computer and monitor wiring](diagrams/m2-wiring.svg)

| Cable | From | To |
|---|---|---|
| 1 | The computer's own power supply (wall socket) | Computer **USB-C power** port |
| 2 | Computer **micro-HDMI** port (either one) | Monitor **HDMI** (micro-HDMI to HDMI cable) |
| 3 | Computer **USB 3.0** port (blue) | Monitor **USB-C** (USB-A to USB-C cable) |
| 4 | Mouse | Computer **USB 2.0** port (white). Raspberry Pi recommends the white port for the mouse. |

The monitor takes its power from the computer, so one power supply runs both. The monitor then works in **Power Saving mode**: brightness up to 50 % and volume up to 60 %. Plug nothing else power-hungry into the computer's USB ports: only the mouse, and at most a USB stick.

<div class="note">
<b>Option: power the monitor from its own power supply.</b>
<p>Instead of cable 3, the monitor can get its own power supply, plugged into the monitor's <b>USB-C</b> port. It then runs in <b>Full Power mode</b>: brightness and volume go up to 100 %. This also stops the flashing on and off that a weak USB supply can cause.</p>
<ul>
<li><b>What it must be:</b> a USB-C power supply with <b>USB Power Delivery (USB-PD)</b> that gives at least <b>5 V / 1.5 A</b>. The monitor uses only 4.5-6.5 W, so a small supply is enough.</li>
<li><b>Suitable:</b> an official Raspberry Pi USB-C supply, such as a spare 15 W (5.1 V / 3 A) or 27 W (5.1 V / 5 A) supply, or any USB-C charger marked "PD" with a 5 V / 1.5 A or higher output. Use a USB-C to USB-C cable if the supply has no fixed cable.</li>
<li><b>Not suitable:</b> any supply with a USB-A socket, or a USB-C supply without USB-PD: the monitor stays in Power Saving mode.</li>
<li>If the bar still stops at 50, press and hold the brightness-up button for 3 seconds to switch to Full Power mode.</li>
<li>It needs one more wall socket per computer.</li>
</ul>
</div>

**Do (in this order):**

1. Check that the microSD card is in the slot, contacts facing down.
2. Connect cable 2 (HDMI), cable 3 (monitor power) and cable 4 (mouse).
3. Connect cable 1 (power) **last**. The computer starts at once.

**✔ Check:**

* The computer's LED lights up. Within 10-20 seconds the monitor shows a picture (rainbow/boot screen or Ubuntu logo).
* Press the monitor's brightness-up button: the on-screen bar stops at 50. That is Power Saving mode, as expected.
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

Every school uses the same addresses (*IDEA Field Install Manual: School Server*). The easy way in is `http://idea.local`: it opens the Console on whichever Engine answers, whichever and however many Engines the school has, and that Console lists every Engine. To reach one particular Engine, use its sticker name (4.2.2).

### 4.2.1 The IDEA icon and the start page

Click the **IDEA** icon (desktop or dock). Chrome opens the **IDEA start page**, which looks for the Console in this order, and opens the first one that answers:

1. the computer's **home Engine**, if the IDEA team gave it one;
2. the **last Engine** that worked on this computer;
3. **`http://idea.local`**: it opens on whichever Engine answers, so it works with one Engine or many.

The start page always has a **sticker-name field**. If no Engine answers, it says so in plain words and asks for a sticker name: type the name on any Engine's sticker (two lowercase words, for example `brave-otter`), and press Enter.

The Console lists **every** Engine of the school, whichever one you opened.

**✔ Check:** the IDEA Console opens within a few seconds and lists every Engine of the school.

### 4.2.2 Open one particular Engine by its sticker name

Use this to reach one particular Engine. It always works, also on a laptop, a phone or a computer without the IDEA image:

1. In any browser, type **`http://<STICKER>.local`**, the sticker name of any Engine, for example `http://brave-otter.local` (http, not https).
2. Set that address as the browser's **home page**, or ★ **bookmark** it.

`http://idea.local` also works in any browser and opens whichever Engine answers. Both work from the Wi-Fi as well as on a cable.

## 4.3 Wi-Fi: IDEA or IDEA-Teachers

*Check that the computer is on the right Wi-Fi network.*

The pre-flashed IDEA school router creates two Wi-Fi networks (*IDEA Field Install Manual: School Server*, "The school router's Wi-Fi networks and default passwords"). The passwords are the IDEA defaults until the school changes them:

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

* Switch off: on a **Pi 400** with **Fn + F10**, on a **Pi 500** with the **power key** in the top-right corner of the keyboard, or the system menu → Power Off. Wait until the screen is black before you pull the plug.
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

The computer never updates itself. To give it a newer image, or to repair a broken card, an Engine writes the image to the card. The Engine keeps the verified client images, and the Console shows which version it has.

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
| Monitor flashes on and off | Turn brightness and volume down. Unplug extra USB devices. Last resort: give the monitor its own power supply (box in chapter 2). |
| Very slow first boot | That is normal: the first boot resizes the card. Give it 5 minutes. |
| Wi-Fi 'IDEA' not shown | Is the router on? (*IDEA Field Install Manual: School Server*, "Router: check the pre-flashed IDEA router".) |
| Start page says no Engine found | Is an Engine switched on? Type a sticker name in the field, or try `http://<STICKER>.local` (4.2.2). Check that the computer is on IDEA/IDEA-Teachers. |
| `IDEA-Teachers` is not in the Wi-Fi menu | Expected: the student account can't list networks. Ask the IDEA team (4.3). |
| Files or settings are gone after a restart | Expected: the reset on restart (4.4). Save work in Nextcloud. |
| An app in the Console does not open | Its Engine may be switched off or at another school: the Console still shows its apps (known problem, no fix yet). Use the apps of this school's Engine. |
| Desktop IDEA icon shows a red cross | Use the IDEA icon in the dock; log out and in once. Report it to the IDEA team. |
| Something is broken beyond repair | Write the card again from the Console (chapter 6). Nothing on the computer needs saving: students keep their work on the Engine (Nextcloud). |
