#!/usr/bin/env bash
# idea-router-enrol.dropbear.test.sh — password mode (idea#276) over a REAL SSH server: a throwaway dropbear on
# 127.0.0.1 with password-only login for a throwaway user whose login shell is a mock router. Real ssh, scp, sshpass.
# Proves: enrol PASS in password mode, key mode is refused, and the password is never in argv, `ps`, output or logs.
# Needs: sudo (user + dropbear on a high port), dropbear, sshpass. No router touched. Exit 0 = all pass, 77 = skipped.
set -uo pipefail
SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/idea-router-enrol"
pass=0; fail=0
check() { local n="$1"; shift; if "$@"; then echo "PASS $n"; pass=$((pass+1)); else echo "FAIL $n"; fail=$((fail+1)); fi; }
DROPBEAR=$(command -v dropbear || echo /usr/sbin/dropbear)
for t in sshpass dropbearkey ssh scp; do command -v "$t" >/dev/null || { echo "SKIP: $t missing"; exit 77; }; done
if [ ! -x "$DROPBEAR" ] || ! sudo -n true 2>/dev/null; then echo "SKIP: needs dropbear and passwordless sudo"; exit 77; fi

WORK="$(mktemp -d)"; chmod 755 "$WORK"
TUSER="idrt$$"; PORT=$((20000 + RANDOM % 20000))
PW="fake-pw-$(head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n')-not-real"   # generated now, never committed
SECRET="FAKE-TEST-KEY-$RANDOM-not-real"
DBPID=""; PSPID=""
cleanup() {
  [ -n "$PSPID" ] && kill "$PSPID" 2>/dev/null
  [ -n "$DBPID" ] && sudo -n kill "$DBPID" 2>/dev/null
  sudo -n userdel "$TUSER" 2>/dev/null
  sudo -n sed -i "\#^$WORK/fakesh\$#d" /etc/shells
  sudo -n rm -rf "$WORK"
}
trap cleanup EXIT

# Mock router login shell: dropbear runs "<shell> -c <command>". State lives in $WORK/r (owned by the test user).
cat > "$WORK/fakesh" <<SH
#!/usr/bin/env bash
R="$WORK/r"; cmd="\$2"
case "\$cmd" in
  true) exit 0 ;;
  "scp -t /tmp/tskey"|"scp -t -- /tmp/tskey") exec scp -t "\$R/tskey" ;;
  *"/etc/idea/sticker"*) n=\$(sed -n "s/.*hostname='\\([a-z-]*\\)'.*/\\1/p" <<<"\$cmd"); echo "\$n" > "\$R/sticker"; echo "\$n" > "\$R/hostname" ;;
  "tailscale status --json"*)
     [ -f "\$R/up" ] || { echo '{"BackendState":"NeedsLogin","Self":{"Online":false}}'; exit 0; }
     printf '{"BackendState":"Running","Self":{"HostName":"%s","Online":true,"Tags":["tag:idea"]}}\n' "\$(cat "\$R/hostname")" ;;
  "chmod 600 /tmp/tskey") [ -f "\$R/tskey" ] ;;
  "tailscale up"*) grep -q -- '--auth-key=file:/tmp/tskey' <<<"\$cmd" && [ -s "\$R/tskey" ] && touch "\$R/up" ;;
  "rm -f /tmp/tskey") rm -f "\$R/tskey" ;;
  "test ! -e /tmp/tskey") [ ! -e "\$R/tskey" ] ;;
  "tailscale ip -4"*) echo 100.64.1.2 ;;
  *) echo "mock: unknown \$cmd" >&2; exit 1 ;;
esac
SH
chmod 755 "$WORK/fakesh"
echo "$WORK/fakesh" | sudo -n tee -a /etc/shells >/dev/null
sudo -n useradd -M -d "$WORK/r" -s "$WORK/fakesh" "$TUSER"
mkdir -p "$WORK/r"; sudo -n chown "$TUSER" "$WORK/r"
printf '%s:%s\n' "$TUSER" "$PW" | sudo -n chpasswd          # stdin, not argv
dropbearkey -t ed25519 -f "$WORK/hostkey" >/dev/null 2>&1
sudo -n "$DROPBEAR" -F -E -r "$WORK/hostkey" -p "127.0.0.1:$PORT" -P "$WORK/db.pid" 2> "$WORK/dropbear.log" &
for _ in $(seq 50); do [ -s "$WORK/db.pid" ] && break; sleep 0.1; done
DBPID=$(cat "$WORK/db.pid" 2>/dev/null)
[ -n "$DBPID" ] || { echo "FAIL dropbear did not start"; cat "$WORK/dropbear.log"; exit 1; }

# argv loggers in front of the real tools, and a ps sampler for the whole run
mkdir -p "$WORK/bin"
for t in ssh scp sshpass; do
  printf '#!/usr/bin/env bash\necho "%s $*" >> "%s/argv.log"\nexec %s "$@"\n' "$t" "$WORK" "$(command -v $t)" > "$WORK/bin/$t"
done
chmod +x "$WORK/bin/"*
( while :; do ps -eo args >> "$WORK/ps.log" 2>/dev/null; sleep 0.05; done ) & PSPID=$!

printf '%s\n' "$SECRET" > "$WORK/key"; chmod 600 "$WORK/key"
printf '%s\n' "$PW" > "$WORK/pw"; chmod 600 "$WORK/pw"
run() { HOME="$WORK/home" IDEA_ROUTER_USER="$TUSER" IDEA_ROUTER_PORT="$PORT" IDEA_FLEET_KEY="$WORK/key" \
        IDEA_ROUTER_LOG="$WORK/enrol.log" IDEA_VERIFY_SLEEP=0 SSH="$WORK/bin/ssh" SCP="$WORK/bin/scp -O" \
        SSHPASS_CMD="$WORK/bin/sshpass" bash "$SCRIPT" "$@" >> "$WORK/out" 2>&1; }
noleak() { ! grep -qF "$1" "$WORK/out" "$WORK/enrol.log" "$WORK/argv.log" "$WORK/ps.log" "$WORK/dropbear.log" 2>/dev/null; }

run sunny-robin 127.0.0.1; rc=$?
check "key mode against password-only dropbear -> rc 4" [ "$rc" = 4 ]

IDEA_ROUTER_PASSWORD_FILE="$WORK/pw" run sunny-robin 127.0.0.1; rc=$?
check "password mode over real SSH enrols (rc 0)" [ "$rc" = 0 ]
check "dropbear saw password auth" grep -qi "password auth succeeded" "$WORK/dropbear.log"
check "sticker written on mock router" [ "$(sudo -n cat "$WORK/r/sticker" 2>/dev/null)" = sunny-robin ]
check "fleet key removed from mock router" sudo -n test ! -e "$WORK/r/tskey"
check "real sshpass called as sshpass -e" grep -q '^sshpass -e ' "$WORK/argv.log"

rm -f "$WORK/r/up" 2>/dev/null; sudo -n rm -f "$WORK/r/up"
run --password-stdin sunny-robin 127.0.0.1 < "$WORK/pw"; rc=$?
check "--password-stdin over real SSH enrols (rc 0)" [ "$rc" = 0 ]

kill "$PSPID" 2>/dev/null; PSPID=""
check "ps sampler captured the run" grep -q sshpass "$WORK/ps.log"
check "password never in argv, ps, output, logs" noleak "$PW"
check "fleet key never in argv, ps, output, logs" noleak "$SECRET"
echo "$pass passed, $fail failed"; [ "$fail" = 0 ]
