---
title: "IDEA School Server: Installation Manual"
subtitle: "Raspberry Pi 5 Engines + Cudy router + PoE switch + Starlink"
audience: "Version 1.4, 21 October 2026"
cover_logo: "yes"
---
**Status:** Authoritative · **Maintained by:** Marco (with Atlas) · 21 October 2026 (v1.4: review in line with the classroom computer manual: intro and parts list shortened; IDEA-team preparation, hand flashing, scripts and sources removed; wiring consolidated)


# Introduction

Each step has:

1. **Do:** what to do.
2. **✔ Check:** how to see that it worked. Go on once the check passes.

<div class="note">
<b>Conventions.</b>
<ul>
<li>IDEA default passwords follow the public convention <code>&lt;name&gt;911!</code>: router <code>root</code> / <code>admin911!</code>, switch <code>admin</code> / <code>admin911!</code>, Pi user <code>pi</code> / <code>pi911!</code> (keyboard only; SSH is key-only), classroom computer <code>admin</code> / <code>admin911!</code>, Wi-Fi <code>IDEA</code> / <code>idea911!</code> and <code>IDEA-Teachers</code> / <code>idea-teachers911!</code>. This manual has no secret keys or tokens in it.</li>
<li>Values in <code>&lt;ANGLE BRACKETS&gt;</code> are placeholders. <code>&lt;STICKER&gt;</code>: the two-word sticker name of an Engine, for example <code>brave-otter</code>. <code>&lt;ENGINE-IP&gt;</code>: the address of the Engine you are working on (<code>10.42.0.2</code> to <code>.9</code>).</li>
<li>Where this manual says "each Engine", do the step once per Engine. A school starts with one Engine and can add more later.</li>
</ul>
</div>

# 1. What is in the boxes

*Check that you have every part before you start.*

## 1.1 Router

| ☐ | Item |
|---|---|
| ☐ | Cudy WR3000S router (pre-flashed, with IDEA sticker) + 12 V adapter + Ethernet cable |

## 1.2 Switch

| ☐ | Item |
|---|---|
| ☐ | TP-Link TL-SG105PE PoE+ switch (ports 1-4 PoE+) + 53.5 V adapter |

## 1.3 Engines (one set per Engine)

| ☐ | Item |
|---|---|
| ☐ | Raspberry Pi 5 Engine, assembled with PoE+ HAT and NVMe SSD, sticker with its name on the case |
| ☐ | Files Disk |
| ☐ | Backup Disk |

## 1.4 Cables and power

| ☐ | Item |
|---|---|
| ☐ | Ethernet patch cables: one per Engine, plus one for the router-switch link |
| ☐ | Plug adapters for Type G / Type D sockets |
| ☐ | Power strip, ideally with surge protection |

## 1.5 Starlink

| ☐ | Item |
|---|---|
| ☐ | Starlink kit: dish, router, cable, power supply (Gen 2 also: Starlink Ethernet Adapter) |

# 2. Wiring

*Which cable goes where, and who can reach what.*

![Wiring diagram: which cable goes into which port](diagrams/m1-wiring.svg)

| Cable | From | To | Notes |
|---|---|---|---|
| 1 | Starlink router, Ethernet port | Cudy **WAN** port (yellow) | Gen 3 router: built-in LAN port. Gen 2: Starlink Ethernet Adapter. Mini: its Ethernet cable. |
| 2 | Cudy **LAN1** | Switch **port 5** | Port 5 is the only port without PoE. Use it for the uplink. |
| 3 | Switch **port 1** (PoE+) | Engine 1 Ethernet | This cable powers Engine 1. Every school has at least this one. |
| 4… | Switch **ports 2, 3, 4** (PoE+) | Engines 2, 3, 4 (if the school has them) | One cable per extra Engine. Leave unused ports empty. |

The Engines get **no** USB-C power supply: the PoE+ HAT takes power from the Ethernet cable. Never connect a USB-C supply at the same time as PoE. A free switch port can also take an extra access point instead of an Engine.

## 2.1 Network zones

![Network zones and allowed traffic](diagrams/m1-zones.svg)

* **IDEA (students):** devices reach only the Engines, however many there are (Console, Kolibri, Nextcloud, Wikipedia). There is no forwarding to the internet, so outside DNS servers, VPNs and websites are all blocked. Students on the IDEA Wi-Fi cannot reach each other either (client isolation).
* **IDEA-Teachers:** devices reach the Pis. Internet goes through **one** firewall rule, `Teachers-Internet`, which staff can switch off and on again (chapter 8). It starts **on**.
* **LAN (wired):** the Pis may reach the internet for updates and Tailscale. They do not route traffic for anyone else.
* **Tailscale:** the router and every Engine join the IDEA tailnet with the one fleet tag `tag:idea`. Admins reach every device. Devices with `tag:idea` reach nothing, not even each other. There are no exit nodes and no subnet routes.

# 3. Router: check the pre-flashed IDEA router

*Check that the router arrived with the IDEA settings.*

The router arrives pre-flashed with the IDEA settings. You do **not** flash it yourself. A router without an IDEA sticker is not pre-flashed: do not use it, and tell the IDEA team.

## 3.1 Read the labels

1. Turn the Cudy over. The Cudy label shows the model (**WR3000S**), the hardware version (**V1.0**) and the serial number. Write the serial number on the fill-in sheet (Appendix B).
2. The IDEA sticker shows the router's own name, the Wi-Fi name `IDEA`, the password `idea911!` and `http://10.42.0.1`.

**✔ Check:** the Cudy label says WR3000S V1.x and there is an IDEA sticker.

## 3.2 Check the IDEA settings

1. Connect the 12 V adapter. Connect your laptop with a cable to **LAN2**. Leave WAN empty.
2. Browse to `http://10.42.0.1` and log in as `root` with `admin911!`.

**✔ Check (all four):**

* Your laptop gets `10.42.0.1xx`. The LuCI page footer shows the IDEA image version.
* **Network → Wireless** lists `IDEA` and `IDEA-Teachers` on both radios, all enabled.
* A phone can join `IDEA` with `idea911!` and gets an address `10.42.1.x`.
* **Network → Firewall → Traffic Rules** lists `Teachers-Internet`, ticked (on).

<div class="note">
<b>Factory reset.</b> Holding the reset button gives back these IDEA defaults (Wi-Fi, passwords, firewall, <code>10.42.0.1</code>),
not plain OpenWrt. So a reset never leaves a school with an open network, but it does undo password changes from chapter 9.
</div>

## 3.3 The school router's Wi-Fi networks and default passwords

| What | Name | Default password | Who uses it |
|---|---|---|---|
| Student Wi-Fi | `IDEA` | `idea911!` | Students' and classroom computers and phones. Reaches **only** the Engines (Console, Kolibri, Nextcloud, Wikipedia). No internet. |
| Teacher Wi-Fi | `IDEA-Teachers` | `idea-teachers911!` | Teachers. Reaches the Engines. Internet is **on** by default; staff can switch it off (chapter 8). |
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

## 5.1 Connect and check

1. Plug the first Engine into switch **port 1** (further Engines into ports 2, 3, 4). The PoE+ HAT powers it. Wait 3-5 minutes.
2. In LuCI **Status → Overview → DHCP leases**, find each Engine by its sticker name and write its address on the fill-in sheet. Which Engine gets which address is not fixed and does not matter.

**✔ Check:**

* Every Engine's address is between `10.42.0.2` and `.9`. An address from `.100` to `.199` means the Engine works on the cable but Wi-Fi devices are refused: tell the IDEA team.
* A laptop on the wired LAN or on the Wi-Fi `IDEA` opens `http://<STICKER>.local` (the name on any sticker) and `http://idea.local`, and sees the IDEA Console with **every** Engine of this school listed.
* In the Console, each app shows as *Running* and opens.

## 5.2 The apps on each Engine

| Console card | What it is |
|---|---|
| **Kolibri** | The school's own Kolibri (school *IDEA School*) with 14 channels, for example CK-12, PhET, OpenStax and African Storybook. Only the `admin` account exists: the school creates its own teachers and learners. |
| **Kolibri Demo** | A separate practice Kolibri: *IDEA Demo School*, class *Grade 5*, the demo accounts and the three IDEA-DEMO channels (Maths, Grade 5 Science, Early Reading). The teacher tutorial uses it. |
| **Nextcloud** | The school's own Nextcloud, with the accounts `admin`, `teacher1` and `learner1`. |
| **Nextcloud Demo** | A separate practice Nextcloud with the demo accounts and the folders *Worksheets* and *Teacher Notes*. |
| **Wikipedia** | The full English Wikipedia, offline. |
| **Wikipedia (Demo)** | Wikipedia in Simple English, used in the tutorial. |

Everything the teacher tutorial shows is done in the Demo apps, so the school's own apps stay clean. Each Engine's **Backup Disk** takes full backups of every app. A full backup takes about 2 h 15 min and stops each app while it runs, so run backups outside lesson time (*IDEA for Teachers: Tutorial*, chapter 12).

<div class="warn">
<b>Known problem: apps of an Engine that is not there.</b> Once two Engines have been on the same network, each one keeps
listing the other one and its apps after they are apart (switched off, or at another school). Those apps look normal in
the Console, but they <b>won't open</b>. There is no fix yet. Tell the teachers to use the apps marked
"on <i>their own Engine's name</i>".
</div>

## 5.3 Tell the IDEA team which Engines this school has

Send the IDEA team one short message per school: the school name and the sticker name of each Engine. Send it again whenever an Engine moves to another school.

**✔ Check:** the IDEA team confirms that they have the names.

# 6. On site: connect Starlink and final cabling

*Connect everything at the school.*

Starlink is only the internet on the Cudy **WAN** port. The school network works fully without it.

1. **Install and activate Starlink** with the Starlink app (dish outside with a clear view of the sky). The **IDEA
   project** owns the Starlink account; use the IDEA project's app login. Check that it works with a phone on the Starlink Wi-Fi, and check the app for obstructions. Write the router
   generation on the fill-in sheet.
2. **Bypass mode:** with the phone still on the Starlink Wi-Fi, open the **Starlink app → Settings → Bypass mode** and
   switch it on. On a Gen 3 router the light turns violet.

   <div class="warn">Bypass mode switches the Starlink Wi-Fi off for good: from now on all Wi-Fi comes from the Cudy.
   It can only be undone with a factory reset of the Starlink router. Do it last, after Starlink itself works.</div>

3. **Cable 1:** Gen 3 router: remove the rubber cover at the back and connect one of its Ethernet ports to the Cudy
   **WAN** port. Gen 2 router: Starlink Ethernet Adapter between the router and the dish cable, adapter port to the
   Cudy WAN. Starlink Mini: its Ethernet cable to the Cudy WAN. Nothing else plugs into the Starlink router.
4. Cable the rest exactly as in the wiring diagram: cable 2 (Cudy LAN1 → switch port 5), then one cable per Engine.
   Plug in the power adapters: Starlink, Cudy, switch. The Pis start by themselves through PoE.
5. **Power:** if there is a UPS, put the **Cudy, the switch** (and so the Engines) on it. Starlink uses far more power
   (about 75–100 W); keep it on mains unless the UPS is large.
6. Wait 5 minutes. Leave the Cudy WAN on DHCP and keep bypass on.

**✔ Check:**

* LuCI → **Status → Overview** shows a WAN address from Starlink (normally `100.x.x.x`: that is Starlink's shared
  address, which is normal and fine for Tailscale).
* `tailscale status` (on your laptop, on the tailnet) shows the router and every Engine's sticker name online.
* The switch's PoE LEDs are on for every port with an Engine.
* Unplug cable 1 for a minute: a laptop on `IDEA` still opens the Console. Plug it back in: Tailscale comes back by itself.

# 7. Final checklist

*Check that everything works before you leave.*

| ☐ | Test | How | Expected |
|---|---|---|---|
| ☐ | Laptop on **IDEA** opens Console | Join Wi-Fi `IDEA` with `idea911!`, browse to `http://idea.local` | IDEA Console loads, every Engine listed. The laptop has an address `10.42.1.x`. |
| ☐ | Console by sticker name | Laptop on Wi-Fi `IDEA`: browse to `http://<STICKER>.local` (each sticker) | Console loads, every Engine listed |
| ☐ | Every Engine reachable | Browse to `http://<ENGINE-IP>` for each Engine | Console loads on each |
| ☐ | **Apps open from the Wi-Fi** | Laptop on `IDEA`: in the Console, click **Open** on each app of each Engine | Every app opens. "Refused" for all apps of one Engine: its address is outside `.2`-`.9` (5.1). |
| ☐ | Only this school's Engines | Console → Operator Login → the network list | Every Engine of this school has a green dot. A red dot is an Engine that is not here: see the known problem in 5.2. |
| ☐ | Disks | The same list, under each Engine | The Files Disk (badge *files*) and the Backup Disk (badge *backup*) are listed |
| ☐ | **No internet on IDEA** | Browse to `https://example.com`. In a terminal: `ping -c2 1.1.1.1`, `nslookup example.com 1.1.1.1` | All fail (time-out / refused) |
| ☐ | Router admin closed on IDEA | Browse to `http://10.42.1.1` and `http://10.42.0.1` | Fails |
| ☐ | Students isolated | From phone A on IDEA, ping laptop B on IDEA | Fails |
| ☐ | **Teachers: Pis yes, internet on** | Join `IDEA-Teachers` with `idea-teachers911!`. Open `http://idea.local`, then `https://example.com` | Console yes, internet yes |
| ☐ | **Teachers: internet switched off** | Switch off `Teachers-Internet` (chapter 8), then reload `https://example.com` | Internet stops. Switch it on again: internet works. |
| ☐ | Pis have internet (updates) | `ssh pi@<ENGINE-IP> 'curl -sI https://deb.debian.org | head -1'` | `HTTP/... 200` |
| ☐ | **Every Engine visible in Tailscale** | `tailscale status` on an admin laptop, or the admin console | Every sticker name (and the router) online, tagged `tag:idea` |
| ☐ | Stickers and report | Look at every case | Each sticker matches `hostname` on that Pi. The IDEA team has the names (5.3). |
| ☐ | Power fine | `ssh pi@<ENGINE-IP> vcgencmd get_throttled` (for each Engine) | `throttled=0x0`. If you see anything but `0x0`, check the cable and switch port and tell the IDEA team. |
| ☐ | Reboot test | Pull the switch's power for 10 s, then plug it back in | After about 5 minutes, all of the above pass again |

# 8. Switching teacher internet off and on

*Turn internet on the teacher Wi-Fi off or on.*

Internet on the teacher Wi-Fi `IDEA-Teachers` is **on** by default. Staff can switch it off, also from far away, and switch it on again later.

**LuCI** (from a wired laptop at the school, or over Tailscale): **Network → Firewall → Traffic Rules** → `Teachers-Internet` → untick **Enable** to switch it off, or tick it to switch it back on → **Save & Apply**.

**SSH:**

```bash
# OFF
ssh root@10.42.0.1 "uci set firewall.teachers_internet.enabled='0' && uci commit firewall && service firewall reload"
# ON again (the default)
ssh root@10.42.0.1 "uci set firewall.teachers_internet.enabled='1' && uci commit firewall && service firewall reload"
```

**✔ Check:** a teacher laptop on IDEA-Teachers cannot (off) or can (on) open `https://example.com`. Connections that were already open may last a few more seconds.

Switch it on only when the head teacher asks, and off again when the lesson is over. It does not go off by itself.

# 9. Tell the school, and change the default passwords

*Hand over to the school and set new passwords.*

**Tell the head teacher and the teachers:**

* **Students** join Wi-Fi **`IDEA`** with **`idea911!`**. It opens the IDEA Console, Kolibri, Nextcloud and Wikipedia, and nothing else: no internet.
* **Teachers** join Wi-Fi **`IDEA-Teachers`** with **`idea-teachers911!`**. It reaches the same apps. Internet is on; staff can switch it off (chapter 8).
* Teachers keep the `IDEA-Teachers` password to themselves.
* **Opening the Console:** on a classroom computer, click the **IDEA** icon on the desktop or in the dock (*IDEA Classroom Computer: Installation Manual*). On any other device, type **`http://idea.local`** or **`http://<STICKER>.local`** (the name on any Engine's sticker), and set it as the browser's home page or bookmark it.
* **Default accounts** follow the `<name>911!` convention, for example `admin` / `admin911!`. The student account on the classroom computers, `learner`, has no password, and Kolibri learners sign in with only their username.
* **Teacher computers:** the classroom computers join `IDEA`. For a computer on `IDEA-Teachers`, ask the IDEA team.
* **Classroom computers reset at every restart.** Anything saved on the computer itself is gone after a restart: save work in Nextcloud.
* **Apps that won't open:** see the known problem in 5.2.

**Change the passwords once the school is running.** The defaults are easy on purpose, but anyone who knows the pattern can guess them.
The head teacher picks new passwords (at least 8 characters, different for students and teachers). Then, from a wired laptop:

1. LuCI → **Network → Wireless** → **Edit** on `IDEA` (both radios) → **Wireless Security → Key** → **Save & Apply**. The same for `IDEA-Teachers`.
2. LuCI → **System → Administration → Router Password** for `root`.
3. The switch password (chapter 4). For the classroom computers' `admin` password, ask the IDEA team.

**✔ Check:** a phone joins with the new password and not with the old one. Every device on that Wi-Fi must join again with the new password.

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
| Starlink kit | router generation (Gen 3 / Gen 2 / Mini) ______, bypass on ☐ |
| Switch | `10.42.0.10`, MAC (on its label) ____:____:____:____:____:____ |
| Wi-Fi students | SSID `IDEA`, password `idea911!` (until changed), subnet `10.42.1.0/24` |
| Wi-Fi teachers | SSID `IDEA-Teachers`, password `idea-teachers911!` (until changed), subnet `10.42.2.0/24` |
| Tailscale tag | `tag:idea` (the same for every school) |
| Cudy serial number (label) | ______________________ (date code: ______) |
