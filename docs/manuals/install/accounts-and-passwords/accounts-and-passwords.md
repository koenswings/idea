---
title: "IDEA Kit: Accounts and Passwords"
subtitle: "Classroom computers, Engines, apps, router, switch and Wi-Fi"
audience: "Version 1.1, 22 October 2026"
cover_logo: "yes"
---
**Status:** Authoritative · **Maintained by:** Marco (with Atlas) · 22 October 2026 (v1.1: generic Engine names, Pi keyboard login, switch added, cover version + date only)

<div class="note">
<b>Keep this sheet private.</b> It lists the IDEA default passwords. They all follow one rule: account name + <code>911!</code> (for example <code>admin</code> → <code>admin911!</code>). Do not leave this sheet at the school.
</div>

## How to reach things

| What | How |
|---|---|
| Students' Wi-Fi | Network `IDEA`, password `idea911!`. Console and apps only, no internet. |
| Teachers' Wi-Fi | Network `IDEA-Teachers`, password `idea-teachers911!`. Console and apps, plus internet if the router has internet. |
| IDEA Console | Browser: `http://<sticker-name>.local`, where `<sticker-name>` is the name on the Engine's sticker (for example `http://brave-otter.local`). Each Engine's Console shows the apps of all the school's Engines. On a classroom computer, the IDEA icon opens it. |
| Apps | Open them from the Console with **Open ↗**. You do not need their addresses. |

## Classroom computers (Ubuntu)

| Account | Username | Password | Notes |
|---|---|---|---|
| Student desktop | `learner` (shown as Learner) | none | Logs in by itself. Joins Wi-Fi `IDEA` by itself. |
| Support admin (hidden) | `admin` | `admin911!` | Only at the keyboard: **Not listed?** on the login screen, or `su - admin` in a terminal. |
| Remote SSH | `admin` | SSH: key only, no password | |

## Engines (Raspberry Pi 5)

| Account | Username | Password | Notes |
|---|---|---|---|
| Remote SSH | `pi` | SSH: key only, no password | The same on every Engine. |
| Local (keyboard) login | `pi` | `pi911!` | Only at the Engine's own keyboard and screen. |

## Apps (the same on every Engine)

| App | Username | Password | Notes |
|---|---|---|---|
| IDEA Console: Operator | `admin` | `admin911!` | Person icon (top right) → **Operator Login**. Students and teachers use the Console without logging in. |
| Kolibri (school "IDEA School") | `admin` | `admin911!` | Super admin. No teachers or learners yet: the admin creates them. |
| Kolibri Demo ("IDEA Demo School") | `admin` | `admin911!` | Super admin |
| | `teacher1`, `teacher2` | `teacher1911!`, `teacher2911!` | Coaches of class Grade 5 |
| | `learner1`, `learner2`, `learner3` | none | Learners type their username only |
| Nextcloud | `admin` | `admin911!` | Administrator |
| | `teacher1` | `teacher1911!` | Group teachers |
| | `learner1` | `learner1911!` | Group learners |
| Nextcloud Demo | `admin` | `admin911!` | Administrator |
| | `teacher1`, `teacher2` | `teacher1911!`, `teacher2911!` | Group teachers |
| | `learner1`, `learner2`, `learner3` | `learner1911!`, `learner2911!`, `learner3911!` | Group learners. Nextcloud learners do need a password. |
| Wikipedia, Wikipedia (Demo) | none | none | No login |

## Router, switch and Wi-Fi

| What | Username / network | Password | Notes |
|---|---|---|---|
| Router web page (Cudy, LuCI) | `root` | `admin911!` | `http://10.42.0.1`, from a computer plugged into the router by cable (not over Wi-Fi). If it is refused, contact IDEA support. |
| Router SSH | `root` | `admin911!` | Only from a computer plugged in by cable |
| PoE switch web page (TP-Link) | `admin` | `admin911!` | `http://10.42.0.10`, from a computer plugged in by cable |
| Wi-Fi students | `IDEA` | `idea911!` | 2.4 and 5 GHz. Students cannot reach each other's devices. |
| Wi-Fi teachers | `IDEA-Teachers` | `idea-teachers911!` | 2.4 and 5 GHz |
