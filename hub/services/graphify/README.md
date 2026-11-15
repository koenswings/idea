# graphify-serve (hub service, idea#485)

A plain static web server on the hub Pi `idea`. It serves the existing graphify output in `/home/pi/graphify-out` on port **8083**, on all interfaces. That output is the 5 May 2026 79-node knowledge graph of the idea repo's design and process docs: `graph.html`, `graph.json`, `GRAPH_REPORT.md` and the Obsidian notes. This folder only records the service in the repo so it can be installed and drift-checked like the others. It does not change what is served.

- The rebuild stays retired. There is no cron, no rebuild script and **no LLM key** (proposal #408; Koen 2026-11-13: "it stays in").
- Turning graphify into an IDEA App is a separate backlog item (idea#481) and out of scope here.

## Service checklist (proposal #408)

- **What it does:** serves `~/graphify-out` over HTTP on `0.0.0.0:8083` (Python `http.server`, stdlib only).
- **How it runs:** systemd **user** unit `graphify-serve.service`, as `pi` (linger on), `Restart=on-failure`, `WantedBy=default.target`, so it comes back after a reboot. Installed to `~/.config/systemd/user/graphify-serve.service`.
- **Code on the hub:** none of its own. It uses the system `/usr/bin/python3`. The old virtualenv `~/graphify-env` (377M, from the retired rebuild) is not needed to serve and is left alone.
- **State:** `~/graphify-out` (95 files, 556K, dated 5 May 2026). This is content, not code. It is not in the repo and is never written by `install.sh`. Restore it from a backup if it is lost; never rebuild it here.
- **Env keys:** none. There is no `.env.example` because the service needs no keys.
- **Logs:** `journalctl --user -u graphify-serve.service` (request lines from `http.server`).
- **Install / update** (on the hub as `pi`, after a merged PR and Koen's OK for the deploy): `sh ~/idea/hub/services/graphify/install.sh`. If the deployed unit differs, it is first backed up to `~/.idea-hub-backups/graphify/<stamp>/`. Then the script reloads, enables and restarts the unit. The restart means a few seconds without the graph. Afterwards run `~/idea/hub/check.sh --service graphify` (no drift) and `curl -sI http://127.0.0.1:8083/graph.html` (200).
- **Safe to re-run:** yes. It refuses if `~/graphify-out` is missing and never writes that folder.
- **Roll back:** `cp ~/.idea-hub-backups/graphify/<stamp>/graphify-serve.service ~/.config/systemd/user/`, then `systemctl --user daemon-reload && systemctl --user restart graphify-serve.service`.

## Open point before the deploy

The deployed unit on `idea` was **not** read for this PR, because no Pi was touched. The unit here was written from the read-only survey of 13 Nov (#408): `python3 -m http.server 8083`, all interfaces, `/home/pi/graphify-out`, user unit. If the live unit uses the `~/graphify-env` python, or other options, `hub/check.sh --service graphify` will show it as drift. Then either this file is updated to match by PR, or Steve decides the system python is fine. `install.sh` backs up the live unit before it replaces anything.

## Tests

    cd hub/services/graphify && python3 -m unittest discover -s tests -v

`test_install.py` runs `install.sh` against a fake `$HOME` with stub `systemctl` and `loginctl`. It checks that the unit is installed and enabled, that the served files are unchanged byte for byte across re-runs, that a differing unit is backed up first, and that it refuses without `~/graphify-out`. A further test starts the unit's exact `ExecStart` command (with `%h` set to a temp home and a free port in place of 8083) and fetches `graph.html`. On the box, `systemd-analyze --user verify` passes for the unit. `hub/tests/check.test.sh` covers the graphify drift checks.
