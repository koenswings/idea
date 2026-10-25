---
title: "IDEA Field Install Manual: School Server"
subtitle: "Raspberry Pi 5 Engines + Cudy router + PoE switch + Starlink"
audience: "Version 1.8, 25 October 2026"
cover_logo: "yes"
---
**Status:** Authoritative · **Maintained by:** Marco (with Atlas) · 25 October 2026 (v1.8: sticker names, idea.local as the easy way in; v1.7: opening paragraph, parts list = what IDEA delivers, diagram arrows fixed)


# Introduction

This manual sets up the IDEA school server: one or more Raspberry Pi 5 **Engines** with a pre-flashed Cudy router, a PoE switch and a Starlink internet connection. The Engines bring the IDEA Console, Kolibri, Nextcloud and Wikipedia to the school's computers and phones over the school's own Wi-Fi, and they keep working without internet. Everything arrives already set up: you connect it, check it and hand it over.

Each step has:

1. **Do:** what to do.
2. **✔ Check:** how to see that it worked. Go on once the check passes.

<div class="note">
<b>Conventions.</b>
<ul>
<li>IDEA default passwords follow the public convention <code>&lt;name&gt;911!</code>: router <code>root</code> / <code>admin911!</code>, switch <code>admin</code> / <code>admin911!</code>, Pi user <code>pi</code> / <code>pi911!</code> (keyboard only; SSH is key-only), classroom computer <code>admin</code> / <code>admin911!</code>, Wi-Fi <code>IDEA</code> / <code>idea911!</code> and <code>IDEA-Teachers</code> / <code>idea-teachers911!</code>. This manual has no secret keys or tokens in it.</li>
<li>Values in <code>&lt;ANGLE BRACKETS&gt;</code> are placeholders. <code>&lt;STICKER&gt;</code>: the sticker name of an Engine, two lowercase words with no digits, for example <code>brave-otter</code> (see 5). <code>&lt;ENGINE-IP&gt;</code>: the address of the Engine you are working on (<code>10.42.0.2</code> to <code>.9</code>).</li>
<li>Where this manual says "each Engine", do the step once per Engine. A school starts with one Engine and can add more later.</li>
</ul>
</div>

# 1. What is in the boxes

*Check that you have every part before you start.*

| ☐ | Item |
|---|---|
| ☐ | Cudy WR3000S router (pre-flashed, with IDEA sticker), its 12 V power adapter and an Ethernet cable |
| ☐ | TP-Link TL-SG105PE PoE+ switch (ports 1-4 PoE+) and its 53.5 V power adapter |
| ☐ | Per Engine: Raspberry Pi 5 Engine, assembled with PoE+ HAT and NVMe SSD, with its name on a sticker on the case |
| ☐ | Per Engine: Files Disk |
| ☐ | Per Engine: Backup Disk |
| ☐ | Ethernet patch cables: one per Engine, plus one for the router-switch link |
| ☐ | Plug adapters for Type G / Type D sockets |
| ☐ | Starlink kit, one of:<ul><li><b>Standard</b>: dish, router, cable, power supply</li><li><b>Mini</b>: dish with built-in router, kickstand and mount, DC power cable, power supply</li></ul> |
| ☐ | Ethernet cable from Starlink to the router (Cudy WAN port) |

# 2. Wiring

*Which cable goes where, and who can reach what.*

![Wiring diagram: which cable goes into which port](diagrams/m1-wiring.svg)

| Cable | From | To | Notes |
|---|---|---|---|
| 1 | Starlink Ethernet port | Cudy **WAN** port (yellow) | Standard Gen 3: the router's Ethernet port. Gen 2: Starlink Ethernet Adapter. Mini: the port on the Mini itself. Use the Starlink-to-router Ethernet cable from chapter 1. |
| 2 | Cudy **LAN1** | Switch **port 5** | Port 5 is the only port without PoE. Use it for the uplink. |
| 3 | Switch **port 1** (PoE+) | Engine 1 Ethernet | This cable powers Engine 1. Every school has at least this one. |
| 4… | Switch **ports 2, 3, 4** (PoE+) | Engines 2, 3, 4 (if the school has them) | One cable per extra Engine. Leave unused ports empty. |

The Engines get **no** USB-C power supply: the PoE+ HAT takes power from the Ethernet cable. Never connect a USB-C supply at the same time as PoE. A free switch port can also take an extra access point instead of an Engine.

## 2.1 Who connects where

![Who connects where, and what they can open](diagrams/m1-zones.svg)

Students and teachers never plug into the switch: they use the Wi-Fi. Only the Engines (and the router) are on cables.

# 3. Router: check the pre-flashed IDEA router

*Check that the router arrived with the IDEA settings.*

The router arrives pre-flashed with the IDEA settings. You do **not** flash it yourself. A router without an IDEA sticker is not pre-flashed: do not use it, and tell the IDEA team.

## 3.1 Read the labels

1. Turn the Cudy over. The Cudy label shows the model (**WR3000S**), the hardware version (**V1.0**) and the serial number. Write the serial number on the fill-in sheet (Appendix B).
2. The IDEA sticker shows the router's own name, the Wi-Fi name `IDEA`, the password `idea911!` and `http://10.42.0.1`.

**✔ Check:** the Cudy label says WR3000S V1.x and there is an IDEA sticker.

## 3.2 Check the IDEA settings

1. Switch the router on: plug the Cudy router's own power adapter (the 12 V adapter from the Cudy box) into the round **power** socket on the back of the router, and into a wall socket. Wait 2 minutes.
2. Connect your laptop with an Ethernet cable to the router port marked **LAN2**. Leave the **WAN** port empty for now.
3. Browse to `http://10.42.0.1` and log in as `root` with `admin911!`.

**✔ Check (all four):**

* Your laptop gets `10.42.0.1xx`. The LuCI page footer shows the IDEA image version.
* **Network → Wireless** lists `IDEA` and `IDEA-Teachers` on both radios, all enabled.
* A phone can join `IDEA` with `idea911!` and gets an address `10.42.1.x`.
* **Network → Firewall → Traffic Rules** lists `Teachers-Internet`, ticked (on).

<div class="note">
<b>Factory reset.</b> Holding the reset button gives back these IDEA defaults (Wi-Fi, passwords, firewall, <code>10.42.0.1</code>),
not plain OpenWrt. So a reset never leaves a school with an open network,.
</div>

## 3.3 The school router's Wi-Fi networks and default passwords

| What | Name | Default password | Who uses it |
|---|---|---|---|
| Student Wi-Fi | `IDEA` | `idea911!` | Students' and classroom computers and phones. Reaches **only** the Engines (Console, Kolibri, Nextcloud, Wikipedia). No internet. |
| Teacher Wi-Fi | `IDEA-Teachers` | `idea-teachers911!` | Teachers. Reaches the Engines. Internet is **on** by default. |
| Router admin (LuCI and SSH on the wired LAN) | user `root` | `admin911!` | The installer and the IDEA team only. Over Tailscale the router accepts SSH keys only. |

Give the students the `IDEA` network and its password. Give only the teachers the `IDEA-Teachers` network and its password.

## 3.4 Internet and Tailscale

1. Plug an internet connection (the Starlink router on site, or any router with internet) into the Cudy **WAN** port.
2. LuCI **Status → Overview** should show an IPv4 WAN address.

**✔ Check:**

* `ssh root@10.42.0.1 'ping -c3 openwrt.org'` gets replies.
* `ssh root@10.42.0.1 tailscale status` shows the router online, with tag `tag:idea`. The router is already on the tailnet; you need no key for it.

# 4. Switch: TP-Link TL-SG105PE

*Set up the switch that powers the Engines.*

The switch has 5 gigabit ports; ports 1-4 give PoE+ (up to 30 W each, 65 W in total). Its factory login is `admin` / `admin`, which you replace. **PoE Auto Recovery** pings a device and power-cycles its port when the device stops answering.

1. Connect switch port 5 to Cudy LAN1. Power the switch. Wait 1 minute.
2. Find the switch in LuCI **Status → Overview → Active DHCP Leases**. Click **Set Static** and give it `10.42.0.10`. Then power-cycle the switch.
3. Browse to `http://10.42.0.10`. Log in with the factory default. **System → User Account**: set the IDEA default `admin911!`.
4. Optional watchdog, under **PoE → PoE Auto Recovery**:
   * Enable it globally.
   * For each port with an Engine: Ping IP = that Engine's address from the fill-in sheet. (The router normally keeps giving an Engine the same address; if you move Engines between ports, update this.)
   * **Startup Delay 300 s** (a Pi takes a few minutes to boot and start the Engine)
   * Interval 60 s, Failure Threshold 5, Break Time 15 s

**✔ Check:** you can log in with the new password and the old one fails. PoE Status shows every port with an Engine "on" with a few watts each once the Pis are connected.

<div class="note">
The switch is not on Tailscale, so nobody can reach it from outside the school. The watchdog is the only automatic power reset.
An admin can still reach its web page through a Pi with an SSH tunnel: <code>ssh -L 8080:10.42.0.10:80 pi@&lt;pi-tailscale-ip&gt;</code>, then open <code>http://localhost:8080</code>.
</div>

# 5. The Engines

*Connect each Engine and check that it works.*

The Engines arrive installed: operating system, IDEA Engine and Console, Tailscale, apps and content, and the name on the sticker. You do **not** install anything on them.

**The sticker name.** Each Engine has its own name: two lowercase words, an adjective and a noun, with no digits, for example `brave-otter`. The installer picks the name, prints it at the end of the install and saves it on the Engine in `/home/pi/STICKER.txt`. That name is written on the sticker on the case. Engines have no numbers: the sticker name is how everyone tells them apart.

**Two ways to open the Console.**

* **The easy way:** `http://idea.local`. It opens the Console on whichever Engine answers first, and that Console lists every Engine of the school.
* **One particular Engine:** `http://<STICKER>.local`, with the name from the sticker on its case, for example `http://brave-otter.local`. Its Console lists every Engine too.

## 5.1 Connect and check

1. Plug the first Engine into switch **port 1** (further Engines into ports 2, 3, 4). The PoE+ HAT powers it. Wait 3-5 minutes.
2. In LuCI **Status → Overview → DHCP leases**, find each Engine by its sticker name and write its address on the fill-in sheet. Which Engine gets which address is not fixed and does not matter.

**✔ Check:**

* Every Engine's address is between `10.42.0.2` and `.9`.

* A laptop on the wired LAN or on the Wi-Fi `IDEA` opens `http://idea.local`, and also `http://<STICKER>.local` for each sticker, and each time sees the IDEA Console with **every** Engine of this school listed.
* In the Console, each app shows as *Running* and opens.

<div class="note">
<b>If an Engine has an address from <code>10.42.0.100</code> to <code>.199</code>.</b> The router gives every device on a cable an address. An Engine introduces itself to the router as an IDEA Engine and then gets one of the Engine addresses, <code>.2</code> to <code>.9</code>. Any other device on a cable, for example your laptop, gets an ordinary address from <code>.100</code> to <code>.199</code>. The Wi-Fi networks <code>IDEA</code> and <code>IDEA-Teachers</code> may only reach the Engine addresses. So an Engine with a <code>.1xx</code> address did not introduce itself as an Engine: it works for a laptop on a cable, but students and teachers on the Wi-Fi cannot open its Console or apps.
<b>What to do:</b> restart that Engine (unplug its cable from the switch for 10 seconds, plug it back in, wait 5 minutes) and look again. If it still has a <code>.1xx</code> address, tell the IDEA team.
</div>

## 5.2 The apps on each Engine

| Console card | What it is |
|---|---|
| **Kolibri** | The school's own Kolibri (school *IDEA School*) with 14 channels, for example CK-12, PhET, OpenStax and African Storybook. Only the `admin` account exists: the school creates its own teachers and learners. |
| **Kolibri Demo** | A separate practice Kolibri: *IDEA Demo School*, class *Grade 5*, the demo accounts and the three IDEA-DEMO channels (Maths, Grade 5 Science, Early Reading). Used in the *IDEA for Teachers: Tutorial*. |
| **Nextcloud** | The school's own Nextcloud, with the accounts `admin`, `teacher1` and `learner1`. |
| **Nextcloud Demo** | A separate practice Nextcloud with the demo accounts and the folders *Worksheets* and *Teacher Notes*. |
| **Wikipedia** | The full English Wikipedia, offline. |
| **Wikipedia (Demo)** | Wikipedia in Simple English, used in the *IDEA for Teachers: Tutorial*. |

The Demo apps are for training: the *IDEA for Teachers: Tutorial* uses them for all its exercises (chapters 3 to 8), with the demo accounts in its appendix *Demo accounts*. So the school's own apps stay clean.

<div class="warn">
<b>Known problem: apps of an Engine that is not there.</b> Once two Engines have been on the same network, each one keeps
listing the other one and its apps after they are apart (switched off, or at another school). Those apps look normal in
the Console, but they <b>won't open</b>. There is no fix yet. Tell the teachers to use the apps marked
"on <i>their own Engine's name</i>".
</div>

## 5.3 Tell the IDEA team which Engines this school has

Send the IDEA team one short message per school: the school name and the sticker name of each Engine, for example "Kasese Primary: brave-otter, calm-heron". The sticker names are all we need; there is no numbering to add. Send it again whenever an Engine moves to another school.

**✔ Check:** the IDEA team confirms that they have the names.

# 6. Taking backups

*Keep a copy of every app on the Backup Disk.*

Each Engine's **Backup Disk** takes full backups of every app, with its content. A full backup of all apps takes about 2 h 15 min and stops each app while it runs, so run backups outside lesson time. How to run one: *IDEA for Teachers: Tutorial*, chapter 12.

# 7. On site: connect Starlink and final cabling

*Connect everything at the school.*

Starlink is only the internet on the Cudy **WAN** port. The school network works fully without it.

1. **Install and activate Starlink** with the Starlink app (dish outside with a clear view of the sky). The **IDEA
   project** owns the Starlink account; use the IDEA project's app login. Check that it works with a phone on the Starlink Wi-Fi, and check the app for obstructions. Write the Starlink model (Standard Gen 3 / Gen 2, or Mini)
   on the fill-in sheet.
2. **Bypass mode:** with the phone still on the Starlink Wi-Fi, open the **Starlink app → Settings → Bypass mode** and
   switch it on. On a Gen 3 router the light turns violet.

   <div class="warn">Bypass mode switches the Starlink Wi-Fi off for good: from now on all Wi-Fi comes from the Cudy.
   It can only be undone with a factory reset of the Starlink router (Standard) or of the Mini itself. Do it last, after Starlink itself works.</div>

3. **Cable 1:** connect Starlink's Ethernet port to the Cudy **WAN** port. Nothing else plugs into Starlink.

    * Standard Gen 3 router: remove the rubber cover at the back and use one of its Ethernet ports.
    * Standard Gen 2 router: Starlink Ethernet Adapter between the router and the dish cable; its port goes to the Cudy WAN.
    * Mini: remove the rubber **Starlink Plug** from the port on the Mini to reach its Ethernet (RJ45) port, and plug in the Starlink-to-router Ethernet cable from chapter 1.

4. Cable the rest exactly as in the wiring diagram: cable 2 (Cudy LAN1 → switch port 5), then one cable per Engine.
   Plug in the power adapters: Starlink, Cudy, switch. The Pis start by themselves through PoE.
5. **Power:** Starlink uses its own power supply in its own mains socket; it is not powered over Ethernet (PoE). It uses far more power than the rest: Standard about 75–100 W, Mini 25–40 W on average (60 W at most). If there is a UPS, put the **Cudy and the switch** (and so the Engines) on it, and keep Starlink on mains unless the UPS is large.
6. Wait 5 minutes. Leave the Cudy WAN on DHCP and keep bypass on.

**✔ Check:**

* LuCI → **Status → Overview** shows a WAN address from Starlink (normally `100.x.x.x`: that is Starlink's shared
  address, which is normal and fine for Tailscale).
* `tailscale status` (on your laptop, on the tailnet) shows the router and every Engine's sticker name online.
* The switch's PoE LEDs are on for every port with an Engine.
* Unplug cable 1 for a minute: a laptop on `IDEA` still opens the Console. Plug it back in: Tailscale comes back by itself.

# 8. Final checklist

*Check that everything works before you leave.*

| ☐ | Test | How | Expected |
|---|---|---|---|
| ☐ | Laptop on **IDEA** opens Console | Join Wi-Fi `IDEA` with `idea911!`, browse to `http://idea.local` | IDEA Console loads, every Engine listed. The laptop has an address `10.42.1.x`. |
| ☐ | Console by sticker name | Laptop on Wi-Fi `IDEA`: browse to `http://<STICKER>.local` (each sticker) | That Engine's Console loads, every Engine listed |
| ☐ | Every Engine reachable | Browse to `http://<ENGINE-IP>` for each Engine | Console loads on each |
| ☐ | **Apps open from the Wi-Fi** | Laptop on `IDEA`: in the Console, click **Open** on each app of each Engine | Every app opens. "Refused" for all apps of one Engine: its address is outside `.2`-`.9` (5.1). |
| ☐ | Only this school's Engines | Console → Operator Login → the network list | Every Engine of this school has a green dot. A red dot is an Engine that is not here: see the known problem in 5.2. |
| ☐ | Disks | The same list, under each Engine | The Files Disk (badge *files*) and the Backup Disk (badge *backup*) are listed |
| ☐ | **No internet on IDEA** | Browse to `https://example.com`. In a terminal: `ping -c2 1.1.1.1`, `nslookup example.com 1.1.1.1` | All fail (time-out / refused) |
| ☐ | Router admin closed on IDEA | Browse to `http://10.42.1.1` and `http://10.42.0.1` | Fails |
| ☐ | Students isolated | From phone A on IDEA, ping laptop B on IDEA | Fails |
| ☐ | **Teachers: Pis yes, internet on** | Join `IDEA-Teachers` with `idea-teachers911!`. Open `http://idea.local`, then `https://example.com` | Console yes, internet yes |
| ☐ | Pis have internet (updates) | `ssh pi@<ENGINE-IP> 'curl -sI https://deb.debian.org | head -1'` | `HTTP/... 200` |
| ☐ | **Every Engine visible in Tailscale** | `tailscale status` on an admin laptop, or the admin console | Every sticker name (and the router) online, tagged `tag:idea` |
| ☐ | Stickers and report | Look at every case | Each sticker matches `hostname` on that Pi (and `/home/pi/STICKER.txt`). The IDEA team has the names (5.3). |
| ☐ | Power fine | `ssh pi@<ENGINE-IP> vcgencmd get_throttled` (for each Engine) | `throttled=0x0`. If you see anything but `0x0`, check the cable and switch port and tell the IDEA team. |
| ☐ | Reboot test | Pull the switch's power for 10 s, then plug it back in | After about 5 minutes, all of the above pass again |

# Appendix A. Troubleshooting

*Quick fixes for common problems.*

| Problem | Try |
|---|---|
| A Pi does not start | Check the PoE LED on that switch port and swap the cable. Try another PoE+ port. |
| `throttled` is not `0x0` | Power problem: check the cable and HAT and switch budget. |
| Console doesn't load from Wi-Fi but does from LAN | Is the Engine in `10.42.0.2`-`.9` (5.1)? Try `http://<STICKER>.local` as well as `http://idea.local`: if only one of them fails, tell the IDEA team which one. |
| All apps of one Engine "refused" from Wi-Fi, fine on a cable | The Engine's address is outside `10.42.0.2`-`.9`. Check its lease in LuCI and tell the IDEA team. |
| The Console shows apps that don't open | Their Engine is switched off or at another school: known problem (5.2). Use the apps of this school's Engines. |
| Tailscale offline after a move | `ssh` in and run `tailscale status`. Check the WAN on the router. Starlink must be in bypass mode. |

# Appendix B. Fill-in sheet for this school

*Write down the details of this school as you go.*

| Item | Value |
|---|---|
| School name | ______________________ |
| Router | `10.42.0.1`, hostname `idea-router` |
| Engine 1 (switch port 1) | address 10.42.0.\_\_\_\_ (the router gives Engines `.2` to `.9`), sticker name \_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_ |
| Engine 2 (port 2, if fitted) | address 10.42.0.\_\_\_\_, sticker name \_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_ |
| Engine 3 (port 3, if fitted) | address 10.42.0.\_\_\_\_, sticker name \_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_ |
| Engine 4 (port 4, if fitted) | address 10.42.0.\_\_\_\_, sticker name \_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_ |
| Starlink kit | model (Standard Gen 3 / Gen 2 / Mini) ______, bypass on ☐ |
| Switch | `10.42.0.10`, MAC (on its label) ____:____:____:____:____:____ |
| Wi-Fi students | SSID `IDEA`, password `idea911!`, subnet `10.42.1.0/24` |
| Wi-Fi teachers | SSID `IDEA-Teachers`, password `idea-teachers911!`, subnet `10.42.2.0/24` |
| Tailscale tag | `tag:idea` (the same for every school) |
| Cudy serial number (label) | ______________________ (date code: ______) |
