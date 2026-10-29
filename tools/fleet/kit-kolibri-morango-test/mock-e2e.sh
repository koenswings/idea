#!/usr/bin/env bash
# Mock end-to-end: a fake Pi (dirs + fake tsx/docker/curl/vcgencmd) behind SSH_CMD. Returns 0 if all scenarios pass.
set -u; S="$1"; T="$(cd "$(dirname "$0")" && pwd)"; W="$(mktemp -d)"; F=0; trap 'rm -rf "$W"' EXIT
chk(){ [ "$2" = "$3" ] || { echo "  mock FAIL $1: got '$2' want '$3'"; F=1; }; }
setup(){
  rm -rf "$W/r"; R="$W/r"; mkdir -p "$R/home/idea/agents/agent-engine-dev/script" "$R/home/idea/agents/agent-engine-dev/node_modules/.bin" "$R/instances/kol-real" "$R/instances/kol-demo" "$R/bin" "$R/state"
  printf 'port: 4321\nhttpPort: 80\n' > "$R/home/idea/agents/agent-engine-dev/config.yaml"
  sed 's/^/x/;s/^x//' "$T/compose-pr8.yaml" > "$R/instances/kol-real/compose.yaml"; printf 'port=62650\nhostname=fakepi\n' > "$R/instances/kol-real/.env"
  cp "$T/compose-pr7.yaml" "$R/instances/kol-demo/compose.yaml"; printf 'port=64439\nhostname=fakepi\n' > "$R/instances/kol-demo/.env"
  echo idea-fakepi-62650 > "$R/state/env-kol-real"; : > "$R/state/env-kol-demo"; echo 50.0 > "$R/state/temp"
  cat > "$R/home/idea/agents/agent-engine-dev/node_modules/.bin/tsx" <<'X'
#!/usr/bin/env bash
shift; m="$1"; shift
if [ "$m" = list ]; then
 echo '{"id":"kol-real","name":"Kolibri","instanceOf":"kolibri","status":"Running","diskId":"D1","device":"sda2","port":""}'
 echo '{"id":"kol-demo","name":"Kolibri Demo","instanceOf":"kolibri","status":"Running","diskId":"D1","device":"sda2","port":""}'
 echo '{"id":"cb","name":"Channel builder","instanceOf":"kolibri-channel-builder","status":"Running","diskId":"D1","device":"sda2","port":""}'
else echo "$*" >> "$MR/state/cmds"
 [ "$1" = stopInstance ] && [ -f "$MR/state/failstop" ] && { echo '{"trace":"stopInstance","status":"error","error":"mock"}'; exit 4; }
 if [ "$1" = startInstance ]; then d="$MR/instances/$2"; p=$(sed -n 's/^port=//p' $d/.env)
  v=$(grep -E 'MORANGO_SYSTEM_ID=' $d/compose.yaml | sed -E 's/.*MORANGO_SYSTEM_ID=//' | sed "s/\${hostname}/fakepi/;s/\${port}/$p/"); echo "$v" > "$MR/state/env-$2"; fi
 echo '{"trace":"x","status":"ok"}'; fi
X
  cat > "$R/bin/docker" <<'X'
#!/usr/bin/env bash
case "$*" in
 *"ps -q --filter label=com.docker.compose.project="*) a="$*"; p="${a##*project=}"; p="${p%% *}"; [ -f "$MR/state/env-$p" ] && echo "$p";;
 inspect*) v=$(cat "$MR/state/env-$2"); [ -n "$v" ] && echo "MORANGO_SYSTEM_ID=$v"; echo PATH=/x;;
 *"ps --format"*) echo kol-real-kolibri-1; echo kol-demo-kolibri-1; echo idea168-kolibri-orphan;;
 *"ps -a"*) echo "kol-real-kolibri-1 Up (healthy)";;
esac
X
  cat > "$R/bin/curl" <<'X'
#!/usr/bin/env bash
u="${*: -1}"; case "$u" in
 *api/public/info*) p=$(echo "$u" | sed -E 's#.*:([0-9]+)/.*#\1#'); id=kol-real; [ $p = 64439 ] && id=kol-demo
   v=$(cat "$MR/state/env-$id"); [ -z "$v" ] && h=ae9d538a3bebce9c600a548c586dd69b || h=$(printf %s "$v" | md5sum | cut -c1-32); echo "{\"instance_id\":\"$h\"}";;
 *) printf 200;; esac
X
  printf '#!/usr/bin/env bash\necho "temp=$(cat $MR/state/temp)'"'"'C"\n' > "$R/bin/vcgencmd"
  echo '#!/usr/bin/env bash' > "$R/bin/hostname"; echo 'echo fakepi' >> "$R/bin/hostname"
  chmod +x "$R"/bin/* "$R/home/idea/agents/agent-engine-dev/node_modules/.bin/tsx"
  cat > "$W/ssh" <<X
#!/usr/bin/env bash
shift; c=\$(printf %s "\$*" | sed -E "s#(^|[ =;])/(instances|disks)/#\\1$R/\\2/#g; s#~/#$R/home/#g")
# Like real ssh, the mock forwards (and so drains) the caller's stdin; only an upload ("cat > ...") uses it.
case "\$c" in "cat > "*) MR="$R" PATH="$R/bin:\$PATH" HOME="$R/home" bash -c "\$c" ;;
  *) MR="$R" PATH="$R/bin:\$PATH" HOME="$R/home" bash -c "\$c" </dev/null; rc=\$?; [ -t 0 ] || cat >/dev/null; exit \$rc ;; esac
X
  chmod +x "$W/ssh"
}
run(){ SSH_CMD="$W/ssh" LOGDIR="$W/logs" HEALTH_WAIT=20 bash "$S" --host fakepi --ip 10.9.9.9 "$@" < /dev/null > "$W/out" 2>&1; echo $?; }
# 1 dry run: plans SKIP real, PATCH_RESTART demo, changes nothing
setup; h0=$(md5sum "$R"/instances/*/compose.yaml)
chk dry-rc "$(run --dry-run)" 0
chk dry-nochange "$(md5sum "$R"/instances/*/compose.yaml)" "$h0"
chk dry-nocmds "$([ -f "$R/state/cmds" ] && echo cmds || echo none)" none
chk dry-skip "$(grep -c 'PLAN Kolibri (kol-real).*-> SKIP' "$W/out")" 1
chk dry-patch "$(grep -c 'PLAN Kolibri_Demo (kol-demo).*expected=idea-fakepi-64439 compose=none container=<unset> -> PATCH_RESTART' "$W/out")" 1
chk dry-notbuilder "$(grep -c 'id=cb' "$W/out")" 0
chk dry-found-all "$(grep -c 'found Kolibri instance' "$W/out")" 2   # stdin regression: every listed instance is seen
chk dry-orphan "$(grep -c 'idea168-kolibri-orphan is not an Engine-managed' "$W/out")" 1
chk dry-dupbefore "$(grep -c 'BEFORE: ids NOT unique' "$W/out")" 0   # real already fixed -> unique
# 2 real run
chk real-rc "$(run)" 0
chk real-cmds "$(tr '\n' ';' < "$R/state/cmds")" "stopInstance kol-demo D1;startInstance kol-demo D1;"
chk real-backup "$(ls "$R"/home/quarantine/kolibri-morango-*/kol-demo-compose.yaml | wc -l)" 1
chk real-unique "$(grep -c 'AFTER: ids unique' "$W/out")" 1
chk real-env "$(cat "$R/state/env-kol-demo")" idea-fakepi-64439
# 3 idempotent second run: all SKIP, no commands
rm -f "$R/state/cmds"; chk rerun-rc "$(run)" 0; chk rerun-nocmd "$([ -f "$R/state/cmds" ] && echo cmds || echo none)" none
chk rerun-skip "$(grep -c -- '-> SKIP' "$W/out")" 2
# 4 hot Pi -> 10 ; 5 lock busy -> 75 ; 6 conflict -> 13 ; 7 refused host
setup; echo 76.2 > "$R/state/temp"; chk hot "$(run)" 10
setup; exec 9>>/tmp/idea-kolibri-morango-fakepi.lock; flock -n 9; chk busy "$(run --dry-run)" 75; flock -u 9; exec 9>&-
setup; sed -i 's/idea-\${hostname}-\${port}/idea-other-1/' "$R/instances/kol-real/compose.yaml"; chk conflict "$(run)" 13
setup; touch "$R/state/failstop"; chk stopfail "$(run)" 14; chk stopfail-nostart "$(grep -c startInstance "$R/state/cmds")" 0
chk refuse "$(SSH_CMD=false LOGDIR="$W/logs" bash "$S" --host idea02 >/dev/null 2>&1; echo $?)" 2
exit $F
