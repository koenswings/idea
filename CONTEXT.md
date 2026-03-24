# CONTEXT.md — IDEA Mission and Technology

*Read this file at the start of every session. It gives you the shared foundation of knowledge
that every IDEA team member — regardless of role — needs to work accurately and consistently.*

---

## The Mission

**IDEA** (Initiative for Digital Education in Africa) deploys offline computing infrastructure
into rural African schools that have no internet access and no on-site IT support.

**The problem we solve:** Schools in rural Africa often have teachers and students who could benefit
enormously from digital learning tools — but they have no reliable internet, limited electricity,
and no technical staff to manage complex systems. Existing solutions assume connectivity and
technical expertise that simply isn't there.

**Our approach:** We put a Raspberry Pi in each school. It runs completely offline, requires no
internet, no cloud account, and no IT knowledge to operate. Teachers and students get access to
curated educational applications — Kolibri for structured learning content, Nextcloud for file
sharing and collaboration, offline Wikipedia for reference — all accessible from any device on
the school's local Wi-Fi.

**Who we serve:** Teachers and school coordinators in rural African schools. They are our primary
users. Our product must be simple enough to operate without training, and robust enough to run
unattended for weeks.

---

## The Solution

### The Engine

The **Engine** is the core software running on each school's Raspberry Pi. It is a TypeScript /
Node.js application. It does several things:

- **Detects and processes App Disks** — USB drives or SSDs that contain educational applications
  bundled with metadata
- **Manages app instances** — starts, stops, and updates Docker containers based on the
  applications found on inserted disks
- **Synchronises state** — when multiple Pis are on the same school network, they share state
  using Automerge (a CRDT library), with no central server required
- **Serves the Console UI** — provides a local web interface accessible on the school's LAN

The Engine is designed to run **unattended**. It starts automatically, handles errors gracefully,
and does not require any human intervention during normal operation. Reliability is the primary
design constraint — more important than features, performance, or convenience.

### The Console

The **Console** is the operator-facing interface for the Engine network. It has two forms:

- **Web app** — served by the Engine on the school's local LAN; accessible from any browser on
  the same network (no internet required)
- **Chrome Extension** — provides the same interface from the browser toolbar, useful for school
  IT coordinators who manage multiple schools

The Console shows the state of all connected Engines, the App Disks inserted in each, and the
running app instances. It allows a coordinator to manage apps across the whole school network from
a single screen.

The Console is built with **Solid.js** and communicates with the Engine over a local API. It must
work fully offline — no CDNs, no external dependencies, no cloud calls.

### App Disks

An **App Disk** is a USB drive or SSD that contains one or more educational applications. Each
disk includes a `compose.yaml` file with an `x-app` metadata block that describes its contents:
app name, version, title, and configuration. When a teacher or coordinator inserts an App Disk
into a school Pi, the Engine reads the metadata and starts the appropriate Docker containers
automatically.

App Disks are the **primary distribution mechanism** for getting applications into schools. There
is no app store, no download, no installer — you carry a disk to the school and plug it in. This
design is deliberate: it works in places with no internet and no technical expertise.

### Offline-First Design

Every component of the IDEA system is designed to work **without internet**. This is not a
feature — it is the foundational constraint that shapes every technical decision.

Concretely, this means:
- No component makes outbound network calls to external services
- All assets (fonts, libraries, icons) are served locally
- No analytics, no telemetry, no cloud authentication
- Teacher guides work as printed pages or locally-served HTML — never remote URLs
- The Engine and Console function identically whether or not there is internet outside the school

When evaluating any change to the system, ask: "Does this still work with no internet?" If the
answer is no, the design is wrong.

### Data Synchronization

When multiple Pis are on the same school network, they need to share state — which apps are
running, what disks are inserted, what the current configuration is. The Engine uses
**Automerge**, a CRDT (Conflict-free Replicated Data Type) library, to synchronise this state
peer-to-peer across the local network.

CRDTs allow concurrent updates from multiple devices to be merged automatically without conflicts
and without a central server. This means:
- No single Pi is the "master" — all are equal peers
- A Pi that was offline rejoins the network and syncs automatically
- No database server to manage, no coordination protocol to maintain

### Physical Web App Management

"Physical web app management" is how we describe the act of installing, updating, or removing
applications from school computers **by physically carrying a disk to the location**.

This is intentionally low-tech. A school can receive a new application by a coordinator driving
to the school and inserting an updated App Disk. The Engine handles everything from there. There
is no remote management, no VPN, no SSH access required for routine operations.

This model has important implications for every role:
- **Teacher guides** must assume the teacher has a disk, not a download link
- **Programme Manager content** must explain this clearly — it sounds unusual to a tech-savvy reader
- **Fundraising proposals** should highlight this as a feature (resilience, low maintenance cost)
  not a limitation
- **Engine development** must keep the disk insert/detection/startup flow rock-solid

---

## Guiding Principles

These principles apply across all roles. When in doubt, they are the tiebreaker.

**Reliability over features.** A school computer that works 99% of the time is worth ten times
one with more features that sometimes fails. Every team member should treat reliability as a
first-class constraint.

**Offline by default.** If something requires internet to work, it does not belong in the
system. This applies to documentation, teacher guides, and tooling as much as to the software
itself.

**Teacher-friendly.** Our end users are not technical. Instructions must be in plain language,
with numbered steps, and assume nothing about prior experience. Jargon is a barrier.

**Honest and direct.** We are a small team doing real work for real schools. No corporate
language, no inflated claims, no hedging. If something is uncertain, say so.

**The mission is real.** The schools we serve exist. The teachers and students are real people
with limited resources and genuine needs. Every decision we make has downstream impact on them.
