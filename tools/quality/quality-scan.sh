#!/usr/bin/env bash
# quality-scan.sh — IDEA platform quality gate (PR + full/scheduled scan)
# Spec: proposals/quality-scan-implementation.md / docs/grok-bot-setup.md §5
# Layout: agent-*-dev at ${IDEA_ROOT}/agents/<name>; app-* at …/agents/agent-app-dev/<name>
# See proposals/pi-checkout-layout.md
# Exit: 0 clean, 1 violations (error/critical/docs-review), 2 script error
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IDEA_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${IDEA_ROOT}" ]]; then
  echo "ERROR: cannot resolve idea repo root" >&2
  exit 2
fi

FLEET_FIND="${IDEA_ROOT}/tools/fleet/find-available-pi.sh"
FLEET_STATE="${IDEA_ROOT}/fleet-state.json"
BOT_NAME="${BOT_NAME:-unknown}"

DEFAULT_REPOS=(
  idea
  agent-engine-dev
  agent-console-dev
  agent-app-dev
  app-kolibri
  app-nextcloud
  app-kiwix
  app-milkwise
)

MODE="full"
REPO_ROOT=""
REPOS=()
PR_REPO=""
PR_BASE=""
PR_HEAD=""
# Internal: allow fixtures/selftest to avoid real Pi SSH (not a public --skip-tests)
QUALITY_SCAN_DRY_RUN_TESTS="${QUALITY_SCAN_DRY_RUN_TESTS:-0}"

usage() {
  cat >&2 <<'EOF'
Usage:
  quality-scan.sh [--repo-root <dir>] [--repos a,b,c]
  quality-scan.sh --pr --repo <name> --base <sha> --head <sha> [--repo-root <dir>]

Paths (canonical Pi / local layout):
  idea            → <IDEA_ROOT>
  agent-*-dev     → <IDEA_ROOT>/agents/<name>
  app-*           → <IDEA_ROOT>/agents/agent-app-dev/<name>
  --repo-root DIR → override parent of agents/ (fixtures: DIR/agents/<name>)
  remote tests    → same nesting under /home/pi/idea/
EOF
}

die() { echo "ERROR: $*" >&2; exit 2; }

# --- CLI ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr) MODE="pr"; shift ;;
    --repo) PR_REPO="${2:-}"; shift 2 ;;
    --repos)
      IFS=',' read -ra REPOS <<< "${2:-}"
      shift 2
      ;;
    --base) PR_BASE="${2:-}"; shift 2 ;;
    --head) PR_HEAD="${2:-}"; shift 2 ;;
    --repo-root) REPO_ROOT="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

# --repo-root overrides the parent of agents/ (default: IDEA_ROOT itself).
# Canonical: agent-*-dev at ${IDEA_ROOT}/agents/<name>; app-* under agents/agent-app-dev/.
if [[ -z "$REPO_ROOT" ]]; then
  REPO_ROOT="$IDEA_ROOT"
fi
REPO_ROOT="$(cd "$REPO_ROOT" && pwd)"

if [[ "$MODE" == "pr" ]]; then
  [[ -n "$PR_REPO" ]] || die "--pr requires --repo"
  [[ -n "$PR_BASE" ]] || die "--pr requires --base"
  [[ -n "$PR_HEAD" ]] || die "--pr requires --head"
  REPOS=("$PR_REPO")
elif [[ ${#REPOS[@]} -eq 0 ]]; then
  REPOS=("${DEFAULT_REPOS[@]}")
fi

# --- Finding accumulators (temp files for jq assembly) ---
TMPDIR_SCAN="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_SCAN"' EXIT
FINDINGS_FILE="$TMPDIR_SCAN/findings.jsonl"
RESULTS_FILE="$TMPDIR_SCAN/results.jsonl"
: >"$FINDINGS_FILE"
: >"$RESULTS_FILE"

add_finding() {
  # repo rule severity path message [label]
  local repo="$1" rule="$2" severity="$3" path="$4" message="$5"
  local label="${6:-}"
  if [[ -z "$label" ]]; then
    case "$severity" in
      docs-review) label="docs-review" ;;
      *) label="quality" ;;
    esac
  fi
  jq -nc \
    --arg repo "$repo" --arg rule "$rule" --arg severity "$severity" \
    --arg path "$path" --arg message "$message" --arg label "$label" \
    '{repo:$repo,rule:$rule,severity:$severity,path:$path,message:$message,label:$label}' \
    >>"$FINDINGS_FILE"
}

# --- Helpers ---
repo_path() {
  # idea → IDEA_ROOT
  # app-* → ${REPO_ROOT}/agents/agent-app-dev/<name>
  # other agent repos → ${REPO_ROOT}/agents/<name>
  # REPO_ROOT defaults to IDEA_ROOT (nested layout). Override with --repo-root
  # for fixtures (e.g. tools/quality/testdata/agents/<fixture>).
  local name="$1"
  if [[ "$name" == "idea" ]]; then
    echo "$IDEA_ROOT"
  elif [[ "$name" == app-* ]]; then
    echo "${REPO_ROOT}/agents/agent-app-dev/${name}"
  else
    echo "${REPO_ROOT}/agents/${name}"
  fi
}

repo_domain() {
  case "$1" in
    agent-engine-dev) echo "engine" ;;
    agent-console-dev) echo "console" ;;
    agent-app-dev|app-*) echo "app-dev" ;;
    *) echo "" ;;
  esac
}

count_pis() {
  if [[ ! -f "$FLEET_STATE" ]]; then
    echo 0
    return
  fi
  jq '[keys[] | select(startswith("_")|not)] | length' "$FLEET_STATE"
}

pi_host_for() {
  local pi="$1"
  jq -r --arg pi "$pi" '.[$pi].host // .[$pi].tailscale // empty' "$FLEET_STATE" 2>/dev/null || true
}

this_hostname() {
  hostname -s 2>/dev/null || hostname 2>/dev/null || echo ""
}

# Resolve Pi for tests. Prints: STATUS|PI_NAME|REASON
# STATUS: selected | skipped
resolve_pi() {
  local domain="$1"
  local count selected=""
  count="$(count_pis)"

  if [[ -z "$domain" ]]; then
    echo "skipped||no_domain"
    return
  fi

  if [[ ! -x "$FLEET_FIND" ]]; then
    echo "skipped||find_unavailable"
    return
  fi

  set +e
  selected="$("$FLEET_FIND" "$domain" 2>/dev/null)"
  local rc=$?
  set -e

  if [[ $rc -eq 0 && -n "$selected" ]]; then
    echo "selected|${selected}|"
    return
  fi

  # Single-Pi golden exception
  if [[ "$count" -eq 1 ]]; then
    local only
    only="$(jq -r '[keys[] | select(startswith("_")|not)][0]' "$FLEET_STATE")"
    if [[ -n "$only" && "$only" != "null" ]]; then
      echo "selected|${only}|single_pi_exception"
      return
    fi
  fi

  echo "skipped||no_idle_pi"
}


git_in() {
  local root="$1"; shift
  git -C "$root" "$@"
}

# True only when $root is the toplevel of its own git work tree (not a nested path
# inside another repo such as idea/tools/quality/testdata/...).
is_git_repo_root() {
  local root="$1" top
  git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  top="$(git -C "$root" rev-parse --show-toplevel 2>/dev/null)" || return 1
  [[ "$(cd "$root" && pwd -P)" == "$(cd "$top" && pwd -P)" ]]
}


list_tracked_or_all() {
  # Prefer tracked files when git repo; else find
  local root="$1"
  shift
  if is_git_repo_root "$root"; then
    git_in "$root" ls-files -- "$@" 2>/dev/null || true
  else
    # non-git fixture: find relative paths
    (
      cd "$root" || exit 0
      for pat in "$@"; do
        # shellcheck disable=SC2086
        find . -path "./$pat" 2>/dev/null | sed 's|^\./||'
      done
    ) || true
  fi
}

# Files changed in PR range (relative paths)
pr_changed_files() {
  local root="$1"
  git_in "$root" diff --name-only "${PR_BASE}..${PR_HEAD}" 2>/dev/null || true
}

file_in_pr_range() {
  local root="$1" rel="$2"
  pr_changed_files "$root" | grep -qxF "$rel"
}

# --- Structure checks ---
check_structure() {
  local repo="$1" root="$2"
  local f

  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    add_finding "$repo" "structure.docs_source" "error" "$f" \
      "Source file under docs/ is not allowed"
  done < <(
    {
      if is_git_repo_root "$root"; then
        git_in "$root" ls-files 'docs/**/*.ts' 'docs/**/*.js' 'docs/**/*.tsx' 'docs/**/*.jsx' 2>/dev/null || true
        git_in "$root" ls-files docs/ 2>/dev/null | grep -E '\.(ts|js|tsx|jsx)$' || true
      else
        find "$root/docs" \( -name '*.ts' -o -name '*.js' -o -name '*.tsx' -o -name '*.jsx' \) 2>/dev/null \
          | sed "s|^${root}/||" || true
      fi
    } | sort -u
  )

  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    add_finding "$repo" "structure.md_in_src" "error" "$f" \
      "Markdown file under src/ is not allowed"
  done < <(
    if is_git_repo_root "$root"; then
      git_in "$root" ls-files src/ 2>/dev/null | grep -E '\.md$' || true
    else
      find "$root/src" -name '*.md' 2>/dev/null | sed "s|^${root}/||" || true
    fi
  )

  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    add_finding "$repo" "structure.test_in_src" "error" "$f" \
      "Test/spec file under src/ is not allowed (tests live in test/)"
  done < <(
    if is_git_repo_root "$root"; then
      git_in "$root" ls-files src/ 2>/dev/null | grep -E '\.(test|spec)\.(ts|js|tsx|jsx)$' || true
    else
      find "$root/src" \( -name '*.test.ts' -o -name '*.test.js' -o -name '*.test.tsx' -o -name '*.test.jsx' \
        -o -name '*.spec.ts' -o -name '*.spec.js' -o -name '*.spec.tsx' -o -name '*.spec.jsx' \) 2>/dev/null \
        | sed "s|^${root}/||" || true
    fi
  )
}

# --- Hygiene ---
is_mock_or_test_path() {
  local p="$1"
  [[ "$p" == *"/__mocks__/"* || "$p" == *"/mocks/"* || "$p" == *"/mock/"* \
    || "$p" == *".test."* || "$p" == *".spec."* \
    || "$p" == *"/test/"* || "$p" == *"/tests/"* \
    || "$p" == *"/__tests__/"* ]]
}

scan_hygiene_file() {
  local repo="$1" root="$2" rel="$3"
  local abs="${root}/${rel}"
  [[ -f "$abs" ]] || return 0
  local line lineno=0

  # Credentials — conservative patterns; exclude env access lines
  while IFS= read -r line || [[ -n "$line" ]]; do
    lineno=$((lineno + 1))
    # skip env-based
    if echo "$line" | grep -qE 'process\.env|import\.meta\.env'; then
      continue
    fi
    if echo "$line" | grep -qiE \
      '(api[_-]?key|secret[_-]?key|access[_-]?token|auth[_-]?token|password|private[_-]?key)\s*[:=]\s*['\''"][^'\''"]{8,}['\''"]'; then
      add_finding "$repo" "hygiene.credentials" "error" "${rel}:${lineno}" \
        "Possible hardcoded credential"
    fi
  done <"$abs"

  # console.log (src only, not mocks/tests)
  if [[ "$rel" == src/* ]] && ! is_mock_or_test_path "$rel"; then
    lineno=0
    while IFS= read -r line || [[ -n "$line" ]]; do
      lineno=$((lineno + 1))
      if echo "$line" | grep -qE 'console\.log\s*\('; then
        add_finding "$repo" "hygiene.console_log" "error" "${rel}:${lineno}" \
          "console.log in production src/"
      fi
    done <"$abs"
  fi

  # TODO/FIXME without issue ref
  lineno=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    lineno=$((lineno + 1))
    if echo "$line" | grep -qE '\b(TODO|FIXME)\b'; then
      if ! echo "$line" | grep -qE '(#[0-9]+|github\.com/.+/issues/[0-9]+)'; then
        add_finding "$repo" "hygiene.todo_without_issue" "error" "${rel}:${lineno}" \
          "TODO/FIXME without linked issue (#N or GitHub URL)"
      fi
    fi
  done <"$abs"

  # Commented-out blocks >5 consecutive comment lines → warning
  local comment_run=0 comment_start=0
  lineno=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    lineno=$((lineno + 1))
    if echo "$line" | grep -qE '^\s*(//|#|\*)'; then
      if [[ $comment_run -eq 0 ]]; then comment_start=$lineno; fi
      comment_run=$((comment_run + 1))
    else
      if [[ $comment_run -gt 5 ]]; then
        add_finding "$repo" "hygiene.commented_block" "warning" "${rel}:${comment_start}" \
          "Commented-out block longer than 5 lines (${comment_run} lines)"
      fi
      comment_run=0
    fi
  done <"$abs"
  if [[ $comment_run -gt 5 ]]; then
    add_finding "$repo" "hygiene.commented_block" "warning" "${rel}:${comment_start}" \
      "Commented-out block longer than 5 lines (${comment_run} lines)"
  fi
}

check_hygiene() {
  local repo="$1" root="$2"
  local f
  local files=()

  if is_git_repo_root "$root"; then
    mapfile -t files < <(git_in "$root" ls-files \
      'src/**/*.ts' 'src/**/*.js' 'src/**/*.tsx' 'src/**/*.jsx' \
      'scripts/**/*.ts' 'scripts/**/*.js' 'scripts/**/*.sh' \
      2>/dev/null || true)
    # Fallback broader listing
    if [[ ${#files[@]} -eq 0 ]]; then
      mapfile -t files < <(
        git_in "$root" ls-files 2>/dev/null | grep -E '^(src|scripts)/' | grep -E '\.(ts|js|tsx|jsx|sh)$' || true
      )
    fi
  else
    mapfile -t files < <(
      find "$root/src" "$root/scripts" \( -name '*.ts' -o -name '*.js' -o -name '*.tsx' -o -name '*.jsx' -o -name '*.sh' \) 2>/dev/null \
        | sed "s|^${root}/||" || true
    )
  fi

  for f in "${files[@]+"${files[@]}"}"; do
    [[ -z "$f" ]] && continue
    scan_hygiene_file "$repo" "$root" "$f"
  done
}

# --- Docs currency ---
check_docs_currency() {
  local repo="$1" root="$2"
  [[ -d "$root/docs" ]] || return 0

  local docs_files=()
  mapfile -t docs_files < <(
    if is_git_repo_root "$root"; then
      git_in "$root" ls-files docs/ 2>/dev/null | grep -v '^docs/INDEX\.md$' || true
    else
      find "$root/docs" -type f ! -name 'INDEX.md' 2>/dev/null | sed "s|^${root}/||" || true
    fi
  )

  # empty docs/ is fine
  local non_index_count=0
  for f in "${docs_files[@]+"${docs_files[@]}"}"; do
    [[ -n "$f" ]] && non_index_count=$((non_index_count + 1))
  done

  if [[ $non_index_count -gt 0 && ! -f "$root/docs/INDEX.md" ]]; then
    add_finding "$repo" "docs.missing_index" "error" "docs/INDEX.md" \
      "docs/ exists with files but docs/INDEX.md is missing"
    return
  fi

  if [[ -f "$root/docs/INDEX.md" ]]; then
    local index_content
    index_content="$(cat "$root/docs/INDEX.md")"
    for f in "${docs_files[@]+"${docs_files[@]}"}"; do
      [[ -z "$f" ]] && continue
      local base name
      base="$(basename "$f")"
      # listed if INDEX mentions path or basename
      if ! echo "$index_content" | grep -qF "$f" && ! echo "$index_content" | grep -qF "$base"; then
        add_finding "$repo" "docs.missing_from_index" "error" "$f" \
          "docs/ file not listed in docs/INDEX.md"
      fi
    done
  fi

  # --pr extras
  if [[ "$MODE" == "pr" ]]; then
    local changed=()
    mapfile -t changed < <(pr_changed_files "$root")
    local new_doc=0 index_changed=0 agents_needed=0 agents_changed=0
    local c
    for c in "${changed[@]+"${changed[@]}"}"; do
      [[ -z "$c" ]] && continue
      if [[ "$c" == docs/* && "$c" != "docs/INDEX.md" ]]; then
        # new file in range: appears in head but not base
        if ! git_in "$root" cat-file -e "${PR_BASE}:${c}" 2>/dev/null; then
          new_doc=1
        fi
      fi
      if [[ "$c" == "docs/INDEX.md" ]]; then index_changed=1; fi
      if [[ "$c" == "AGENTS.md" ]]; then agents_changed=1; fi
      if [[ "$c" == "package.json" || "$c" == "pnpm-lock.yaml" || "$c" == "AGENTS.md" \
         || "$c" == .github/workflows/* || "$c" == Dockerfile* \
         || "$c" == scripts/deploy* || "$c" == scripts/*deploy* ]]; then
        # bash glob: use case
        :
      fi
      case "$c" in
        package.json|pnpm-lock.yaml|.github/workflows/*|Dockerfile*|Dockerfile|scripts/deploy*|scripts/*deploy*)
          agents_needed=1
          ;;
      esac
    done
    if [[ $new_doc -eq 1 && $index_changed -eq 0 ]]; then
      add_finding "$repo" "docs.index_not_updated" "error" "docs/INDEX.md" \
        "New docs/ file in PR range requires docs/INDEX.md update in same range"
    fi
    if [[ $agents_needed -eq 1 && -f "$root/AGENTS.md" && $agents_changed -eq 0 ]]; then
      add_finding "$repo" "docs.agents_not_updated" "error" "AGENTS.md" \
        "Build/test/deploy path changes require AGENTS.md update when it exists"
    fi
  fi
}

# --- Staleness (full only) ---
latest_commit_ts() {
  local root="$1"; shift
  # args: pathspecs
  local ts
  ts="$(git_in "$root" log -1 --pretty=%ct -- "$@" 2>/dev/null || true)"
  echo "${ts:-0}"
}

check_staleness() {
  local repo="$1" root="$2"
  is_git_repo_root "$root" || return 0

  local related=()
  related+=(src config.yaml compose.yaml app.yaml package.json)
  # Dockerfiles
  mapfile -t -O ${#related[@]} related < <(
    git_in "$root" ls-files 2>/dev/null | grep -E '^Dockerfile' || true
  )
  case "$repo" in
    agent-engine-dev) related+=(scripts) ;;
    agent-console-dev)
      related+=(scripts/deploy-fleet.sh)
      mapfile -t -O ${#related[@]} related < <(
        git_in "$root" ls-files 'scripts/*deploy*' 2>/dev/null || true
      )
      ;;
    app-*|agent-app-dev) related+=(compose.yaml app.yaml) ;;
  esac

  local tip
  tip="$(latest_commit_ts "$root" "${related[@]}")"
  [[ "$tip" == "0" ]] && tip="$(latest_commit_ts "$root")"

  if [[ -d "$root/docs" ]]; then
    local df doc_ts age
    while IFS= read -r df; do
      [[ -z "$df" ]] && continue
      doc_ts="$(latest_commit_ts "$root" "$df")"
      [[ "$doc_ts" == "0" ]] && continue
      if [[ "$tip" -gt 0 && $(( tip - doc_ts )) -gt $((30 * 86400)) ]]; then
        age=$(( (tip - doc_ts) / 86400 ))
        add_finding "$repo" "staleness.doc" "docs-review" "$df" \
          "Doc last commit is ${age} days older than related source tip"
      fi
    done < <(git_in "$root" ls-files docs/ 2>/dev/null || true)
  fi

  if [[ -f "$root/AGENTS.md" ]]; then
    local build_related=(package.json pnpm-lock.yaml package-lock.json scripts .github/workflows)
    local build_tip agents_ts
    build_tip="$(latest_commit_ts "$root" "${build_related[@]}")"
    agents_ts="$(latest_commit_ts "$root" AGENTS.md)"
    if [[ "$build_tip" -gt 0 && "$agents_ts" -gt 0 && $(( build_tip - agents_ts )) -gt $((14 * 86400)) ]]; then
      local d=$(( (build_tip - agents_ts) / 86400 ))
      add_finding "$repo" "staleness.agents" "docs-review" "AGENTS.md" \
        "AGENTS.md is ${d} days older than build-related tip"
    fi
  fi
}

# --- Domain bake-ins ---
find_store_templates() {
  local root="$1"
  if is_git_repo_root "$root"; then
    git_in "$root" ls-files 2>/dev/null | grep -iE '(^|/)store[^/]*template[^/]*\.json$' || true
  else
    find "$root" -maxdepth 3 -iname 'store*template*.json' 2>/dev/null | sed "s|^${root}/||" || true
  fi
}

check_bakeins_engine() {
  local repo="$1" root="$2"
  local f
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    if [[ "$MODE" == "pr" ]]; then
      if pr_changed_files "$root" | grep -qxF "$f"; then
        add_finding "$repo" "engine.store_template_touch" "error" "$f" \
          "store-template.json must not be modified"
      fi
    else
      # Full scan: tracked store-template is a hard constraint surface —
      # flag if dirty vs HEAD or if last commit solely touched it recently is not required;
      # Axle rule: any touch is error. On full scan report if working tree differs from HEAD
      # OR if the file appears in unstaged/staged changes.
      if is_git_repo_root "$root"; then
        if ! git_in "$root" diff --quiet HEAD -- "$f" 2>/dev/null \
          || ! git_in "$root" diff --cached --quiet -- "$f" 2>/dev/null; then
          add_finding "$repo" "engine.store_template_touch" "error" "$f" \
            "store-template.json has local modifications (must not be modified)"
        fi
        if git_in "$root" log -1 --name-only --pretty=format: HEAD 2>/dev/null | grep -qxF "$f"; then
          add_finding "$repo" "engine.store_template_touch" "error" "$f" \
            "Latest commit modified store-template.json (must not be modified)"
        fi
      else
        # Non-git fixtures: presence of store-template marks a deliberate fail case
        add_finding "$repo" "engine.store_template_touch" "error" "$f" \
          "store-template.json must not be modified (fixture/non-git presence)"
      fi
    fi
  done < <(find_store_templates "$root")
}

check_bakeins_console() {
  local repo="$1" root="$2"
  local f files=()
  if is_git_repo_root "$root"; then
    mapfile -t files < <(git_in "$root" ls-files src/ 2>/dev/null | grep -E '\.(tsx|jsx|ts|js)$' || true)
  else
    mapfile -t files < <(
      find "$root/src" \( -name '*.tsx' -o -name '*.jsx' -o -name '*.ts' -o -name '*.js' \) 2>/dev/null \
        | sed "s|^${root}/||" || true
    )
  fi
  local helper="${SCRIPT_DIR}/lib-console-bakeins.py"
  for f in "${files[@]+"${files[@]}"}"; do
    [[ -z "$f" || ! -f "$root/$f" ]] && continue
    while IFS=$'\t' read -r marker rule path msg; do
      [[ "$marker" == "FIND" ]] || continue
      add_finding "$repo" "$rule" "error" "$path" "$msg"
    done < <(python3 "$helper" "$root/$f" "$f" 2>/dev/null || true)
  done
}

check_bakeins() {
  local repo="$1" root="$2"
  case "$repo" in
    agent-engine-dev|fixture-engine*) check_bakeins_engine "$repo" "$root" ;;
    agent-console-dev|fixture-console*) check_bakeins_console "$repo" "$root" ;;
  esac
}

# --- Tests ---
run_tests_for_repo() {
  local repo="$1" root="$2"
  # outputs via globals / findings; prints JSON object for checks.tests to stdout
  local domain status pi reason
  domain="$(repo_domain "$repo")"

  if [[ "$repo" == "idea" || "$repo" == fixture-* ]]; then
    # idea / fixtures: structural only
    if [[ "$repo" == fixture-* ]]; then
      jq -nc '{status:"skipped",reason:"fixture_structural_only"}'
      return
    fi
    jq -nc '{status:"skipped",reason:"idea_structural_only"}'
    return
  fi

  if [[ -z "$domain" ]]; then
    jq -nc '{status:"skipped",reason:"no_domain"}'
    return
  fi

  # Apps without smoke harness
  if [[ "$domain" == "app-dev" ]]; then
    local smokes=()
    mapfile -t smokes < <(find "$root/tests" -name 'smoke.mjs' 2>/dev/null || true)
    if [[ ${#smokes[@]} -eq 0 ]]; then
      jq -nc '{status:"skipped",reason:"no-harness"}'
      return
    fi
  fi

  IFS='|' read -r status pi reason < <(resolve_pi "$domain")

  if [[ "$status" != "selected" ]]; then
    jq -nc --arg r "${reason:-no_idle_pi}" '{status:"skipped",reason:$r}'
    return
  fi

  local host run_local=0
  host="$(pi_host_for "$pi")"
  local me
  me="$(this_hostname)"

  if [[ "${FLEET_LOCAL:-0}" == "1" || "${QUALITY_SCAN_LOCAL_TESTS:-0}" == "1" \
     || "$me" == "$pi" || "$me" == *"$pi"* ]]; then
    run_local=1
  fi

  if [[ "$QUALITY_SCAN_DRY_RUN_TESTS" == "1" ]]; then
    jq -nc --arg pi "$pi" --arg host "${host:-}" --arg reason "${reason:-}" \
      '{status:"skipped",reason:"dry_run_tests",pi:$pi,host:$host,note:$reason}'
    return
  fi

  local cmd=()
  case "$domain" in
    engine)
      if grep -q '"test:full"' "$root/package.json" 2>/dev/null; then
        cmd=(pnpm test:full)
      else
        cmd=(pnpm test)
      fi
      ;;
    console)
      cmd=(bash -c 'pnpm test && pnpm typecheck')
      ;;
    app-dev)
      # run all smoke.mjs
      cmd=(bash -c 'set -e; for f in tests/*/smoke.mjs tests/smoke.mjs; do [ -f "$f" ] || continue; node "$f"; done')
      ;;
  esac

  local out rc=0 detail=""
  if [[ $run_local -eq 1 ]]; then
    set +e
    out="$(cd "$root" && "${cmd[@]}" 2>&1)"
    rc=$?
    set -e
    detail="local on ${me:-host}"
  else
    if [[ -z "$host" ]]; then
      jq -nc --arg pi "$pi" '{status:"skipped",reason:"pi_unreachable",pi:$pi,detail:"no host in fleet-state"}'
      return
    fi
    # Attempt SSH
    set +e
    if ! ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new \
        "pi@${host}" "true" 2>/dev/null; then
      set -e
      jq -nc --arg pi "$pi" --arg host "$host" \
        '{status:"skipped",reason:"pi_unreachable",pi:$pi,host:$host}'
      return
    fi
    # Remote path: nested under idea/agents (Koen locked layout 2026-09-24;
    # app-* under agent-app-dev — Koen correction same day)
    local remote_path
    if [[ "$repo" == app-* ]]; then
      remote_path="/home/pi/idea/agents/agent-app-dev/${repo}"
    else
      remote_path="/home/pi/idea/agents/${repo}"
    fi
    # Quote each argv for the remote shell (idea#69): ${cmd[*]} drops the
    # quotes around bash -c 'pnpm test && pnpm typecheck', so SSH ran bare
    # `pnpm` (help text, rc=1) and falsely reported tests.failed.
    local remote_cmd
    printf -v remote_cmd '%q ' "${cmd[@]}"
    out="$(ssh -o BatchMode=yes -o ConnectTimeout=30 "pi@${host}" \
      "cd ${remote_path} && ${remote_cmd}" 2>&1)"
    rc=$?
    set -e
    detail="ssh pi@${host}"
  fi

  if [[ $rc -ne 0 ]]; then
    local sev="error"
    if [[ "$domain" == "engine" && "$MODE" == "full" ]]; then
      sev="critical"
    fi
    add_finding "$repo" "tests.failed" "$sev" "." \
      "Tests failed (rc=${rc}) via ${detail}: $(echo "$out" | tail -c 500)"
    jq -nc --arg pi "$pi" --arg detail "$detail" --argjson rc "$rc" \
      '{status:"failed",pi:$pi,detail:$detail,exit_code:$rc}'
  else
    jq -nc --arg pi "$pi" --arg detail "$detail" \
      '{status:"passed",pi:$pi,detail:$detail}'
  fi
}

# --- Per-repo scan ---
scan_repo() {
  local repo="$1"
  local root
  root="$(repo_path "$repo")"

  if [[ ! -d "$root" ]]; then
    add_finding "$repo" "repo.missing" "error" "$root" "Repo directory not found"
    jq -nc --arg repo "$repo" \
      '{repo:$repo,checks:{tests:{status:"skipped",reason:"repo_missing"},structure:{},hygiene:{},docs_currency:{},staleness:{},bakeins:{}}}' \
      >>"$RESULTS_FILE"
    return
  fi

  local before after
  before="$(wc -l <"$FINDINGS_FILE" | tr -d ' ')"

  check_structure "$repo" "$root"
  check_hygiene "$repo" "$root"
  check_docs_currency "$repo" "$root"
  if [[ "$MODE" == "full" ]]; then
    check_staleness "$repo" "$root"
  fi
  check_bakeins "$repo" "$root"

  local tests_json
  tests_json="$(run_tests_for_repo "$repo" "$root")"

  after="$(wc -l <"$FINDINGS_FILE" | tr -d ' ')"
  local repo_findings
  repo_findings="$(sed -n "$((before + 1)),${after}p" "$FINDINGS_FILE")"

  # Summarize check buckets by rule prefix
  local structure_n hygiene_n docs_n stale_n bake_n
  structure_n="$(echo "$repo_findings" | grep -c '"rule":"structure\.' || true)"
  hygiene_n="$(echo "$repo_findings" | grep -c '"rule":"hygiene\.' || true)"
  docs_n="$(echo "$repo_findings" | grep -c '"rule":"docs\.' || true)"
  stale_n="$(echo "$repo_findings" | grep -c '"rule":"staleness\.' || true)"
  bake_n="$(echo "$repo_findings" | grep -cE '"rule":"(engine|console)\.' || true)"

  jq -nc \
    --arg repo "$repo" \
    --argjson tests "$tests_json" \
    --argjson structure "$structure_n" \
    --argjson hygiene "$hygiene_n" \
    --argjson docs_currency "$docs_n" \
    --argjson staleness "$stale_n" \
    --argjson bakeins "$bake_n" \
    '{repo:$repo,checks:{tests:$tests,structure:{findings:$structure},hygiene:{findings:$hygiene},docs_currency:{findings:$docs_currency},staleness:{findings:$staleness},bakeins:{findings:$bakeins}}}' \
    >>"$RESULTS_FILE"
}

# --- Main ---
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

for r in "${REPOS[@]}"; do
  r="$(echo "$r" | xargs)" # trim
  [[ -z "$r" ]] && continue
  scan_repo "$r"
done

# Assemble report
FINDINGS_JSON="$(jq -s '.' "$FINDINGS_FILE" 2>/dev/null || echo '[]')"
RESULTS_JSON="$(jq -s '.' "$RESULTS_FILE" 2>/dev/null || echo '[]')"

VIOLATIONS="$(echo "$FINDINGS_JSON" | jq '[.[] | select(.severity=="error" or .severity=="critical" or .severity=="docs-review")] | length')"
WARNINGS="$(echo "$FINDINGS_JSON" | jq '[.[] | select(.severity=="warning")] | length')"
TESTS_FAILED="$(echo "$RESULTS_JSON" | jq '[.[] | select(.checks.tests.status=="failed")] | length')"
TESTS_SKIPPED="$(echo "$RESULTS_JSON" | jq '[.[] | select(.checks.tests.status=="skipped")] | length')"

OK=true
if [[ "$VIOLATIONS" -gt 0 || "$TESTS_FAILED" -gt 0 ]]; then
  OK=false
fi

REPOS_JSON="$(printf '%s\n' "${REPOS[@]}" | jq -R . | jq -s .)"

REPORT="$(jq -nc \
  --arg ts "$TS" \
  --arg mode "$MODE" \
  --argjson repos "$REPOS_JSON" \
  --argjson ok "$OK" \
  --argjson violations "$VIOLATIONS" \
  --argjson tests_failed "$TESTS_FAILED" \
  --argjson tests_skipped "$TESTS_SKIPPED" \
  --argjson results "$RESULTS_JSON" \
  --argjson findings "$FINDINGS_JSON" \
  '{ts:$ts,mode:$mode,repos:$repos,ok:$ok,summary:{violations:$violations,tests_failed:$tests_failed,tests_skipped:$tests_skipped,warnings:($findings|map(select(.severity=="warning"))|length)},results:$results,findings:$findings}')"

echo "$REPORT"

# Audit (exit 0 or 1 only — also write on violations)
YEAR="$(date -u +%Y)"
AUDIT_FILE="${IDEA_ROOT}/audit/audit-${YEAR}.jsonl"
mkdir -p "$(dirname "$AUDIT_FILE")"
jq -nc \
  --arg ts "$TS" \
  --arg bot "$BOT_NAME" \
  --arg mode "$MODE" \
  --argjson repos "$REPOS_JSON" \
  --argjson ok "$OK" \
  --argjson violation_count "$VIOLATIONS" \
  '{ts:$ts,bot:$bot,action:"quality_scan",mode:$mode,repos:$repos,ok:$ok,violation_count:$violation_count}' \
  >>"$AUDIT_FILE"

if [[ "$OK" == "true" ]]; then
  exit 0
else
  exit 1
fi
