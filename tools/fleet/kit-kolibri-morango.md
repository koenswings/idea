# kit-kolibri-morango.sh (idea#288 first contact, Kolibri ids)

Applies app-kolibri#8 (merged) to every Kolibri instance (real + Demo) on ONE Engine:
adds `- MORANGO_SYSTEM_ID=idea-${hostname}-${port}` to the kolibri service `environment:` of the
instance's own `compose.yaml` (right after `- KOLIBRI_LISTEN_PORT=${port}`, same line as #8; compose renders
it from the instance `.env`), then restarts only that instance through the Engine (`stopInstance <id> <diskId>`,
`startInstance <id> <diskId>` pushed into engineDB.commands, the Console's path; never raw docker), one at a time,
waiting until `/api/public/info/` answers and the container env shows the expected value.

    ./kit-kolibri-morango.sh --host <tailscale-name> [--ip <ip>] [--dry-run]

Decision per instance (compose line / running container env):
- template or literal `idea-<host>-<port>` + container has it -> SKIP (Kid's hand-applied literal lines count)
- line present, container lacks it -> RESTART only
- no line -> PATCH + RESTART (PATCH only if the container already has the value)
- different value, duplicate lines, no port, unsupported layout -> CONFLICT, not touched, exit 13
Kolibri = Engine instance whose app (instanceOf) starts with `kolibri`, except `kolibri-channel-builder`
(Demo instances are app `kolibri` named e.g. "Kolibri Demo"). Containers not managed by the Engine are only noted.

Safety: per-host box lock `/tmp/idea-kolibri-morango-<host>.lock` (busy -> 75); refuses idea/wh, idea02,
wizardly-hugle; health check (temp <=75 C, Console on config.yaml httpPort, no unhealthy/restarting app
containers, every Kolibri answers) before, before each change and after each restart; compose backups go to
`~/quarantine/kolibri-morango-<ts>/` on the Pi (nothing deleted). Logs: `/workspace/idea288/logs/`.
Only change besides the compose line: an untracked helper `script/.zz-kolibri-morango.ts` is written into the
Engine checkout (read-only list + command sender; source `kit-kolibri-morango-engine.ts`).

Exit codes: 0 ok | 2 usage/refused | 3 unreachable/helper | 10 hot | 11 Console/app down | 12 ids not unique
after | 13 conflict | 14 stop or start failed, or health timeout | 75 busy.

Tests: `tools/fleet/kit-kolibri-morango.test.sh` (fixtures in `tools/fleet/kit-kolibri-morango-test/`) (unit + mock Pi end-to-end: dry run changes nothing, real run patches+restarts the
Demo only, rerun is all SKIP, hot=10, busy=75, conflict=13, refused host=2).
