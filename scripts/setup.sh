#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# IDEA — Installation Script
#
# Sets up the full IDEA virtual company environment on a fresh Raspberry Pi.
#
# USAGE
#   git clone https://github.com/koenswings/idea /home/pi/idea
#   cd /home/pi/idea
#   bash scripts/setup.sh
#
# WHAT THIS DOES
#   1. Installs system dependencies (Docker, git, tmux, Node.js, Tailscale)
#   2. Clones all 5 agent repos into agents/
#   3. Prompts for credentials and writes openclaw/.env
#   4. Installs OpenClaw via Docker (clones openclaw repo, runs docker-setup.sh)
#   5. Applies IDEA's openclaw.json (agent roster, Telegram bindings)
#   6. Configures the Telegram channel
#   7. Connects to Tailscale
#   8. Prints first-run instructions
#
# IDEMPOTENT
#   Safe to re-run. Each step checks whether it has already been done.
#
# REQUIREMENTS
#   Raspberry Pi OS (Bookworm or later), internet connection, user: pi
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Constants ─────────────────────────────────────────────────────────────────

IDEA_DIR="/home/pi/idea"
OPENCLAW_DIR="/home/pi/openclaw"
AGENTS_DIR="${IDEA_DIR}/agents"
GITHUB_ACCOUNT="koenswings"

AGENT_REPOS=(
  "agent-operations-manager"
  "agent-engine-dev"
  "agent-console-dev"
  "agent-site-dev"
  "agent-programme-manager"
)

AGENT_IDENTITIES_REPO="agent-identities"

# ── Helpers ───────────────────────────────────────────────────────────────────

info()    { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()      { echo -e "\033[1;32m[OK]\033[0m    $*"; }
warn()    { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
die()     { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }
heading() { echo -e "\n\033[1m$*\033[0m"; }

# Set a key=value in a .env file — replaces existing line, appends if absent
set_env_var() {
  local file="$1" key="$2" value="$3"
  if grep -q "^${key}=" "${file}" 2>/dev/null; then
    sed -i "s|^${key}=.*|${key}=${value}|" "${file}"
  else
    echo "${key}=${value}" >> "${file}"
  fi
}

require_root_or_sudo() {
  if [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
    warn "This script will run some commands with sudo. You may be prompted for your password."
  fi
}

# ── Step 1: System dependencies ───────────────────────────────────────────────

install_deps() {
  heading "Step 1 — System dependencies"

  # Docker
  if ! command -v docker &>/dev/null; then
    info "Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker pi
    warn "Docker installed. You may need to log out and back in for group membership to apply."
    warn "If docker commands fail with permission errors, run: newgrp docker"
  else
    ok "Docker: $(docker --version)"
  fi

  # Docker Compose plugin
  if ! docker compose version &>/dev/null 2>&1; then
    info "Installing Docker Compose plugin..."
    sudo apt-get update -qq && sudo apt-get install -y -q docker-compose-plugin
  else
    ok "Docker Compose: $(docker compose version --short)"
  fi

  # git
  if ! command -v git &>/dev/null; then
    sudo apt-get update -qq && sudo apt-get install -y -q git
  fi
  ok "git: $(git --version)"

  # tmux (for Tabby SSH session persistence — see design doc CLAUDE.md chapter)
  if ! command -v tmux &>/dev/null; then
    sudo apt-get update -qq && sudo apt-get install -y -q tmux
  fi
  ok "tmux: $(tmux -V)"

  # Node.js 22 (required by OpenClaw)
  local node_major
  node_major=$(node -e 'process.stdout.write(process.versions.node.split(".")[0])' 2>/dev/null || echo "0")
  if [[ "${node_major}" -lt 22 ]]; then
    info "Installing Node.js 22..."
    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - -q
    sudo apt-get install -y -q nodejs
  fi
  ok "Node.js: $(node --version)"

  # Python 3 (used by this script for JSON config merging)
  if ! command -v python3 &>/dev/null; then
    sudo apt-get update -qq && sudo apt-get install -y -q python3
  fi
  ok "python3: $(python3 --version)"
}

# ── Step 2: Clone agent repos ─────────────────────────────────────────────────

clone_agent_repos() {
  heading "Step 2 — Agent repos"
  mkdir -p "${AGENTS_DIR}"

  for repo in "${AGENT_REPOS[@]}"; do
    local dest="${AGENTS_DIR}/${repo}"
    if [[ -d "${dest}/.git" ]]; then
      ok "${repo} — already present"
    else
      info "Cloning ${repo}..."
      git clone "https://github.com/${GITHUB_ACCOUNT}/${repo}.git" "${dest}"
      ok "Cloned ${repo}"
    fi
  done
}

# ── Step 3: Credentials ───────────────────────────────────────────────────────

configure_credentials() {
  heading "Step 3 — Credentials"

  local env_file="${IDEA_DIR}/openclaw/.env"

  if [[ -f "${env_file}" ]]; then
    warn ".env already exists at ${env_file} — skipping"
    warn "Delete it and re-run to reconfigure credentials."
    return
  fi

  mkdir -p "${IDEA_DIR}/openclaw"

  echo ""
  echo "  Enter your credentials. Input is hidden."
  echo ""

  local anthropic_key telegram_token github_token
  read -rsp "  ANTHROPIC_API_KEY: " anthropic_key; echo ""
  read -rsp "  TELEGRAM_BOT_TOKEN: " telegram_token; echo ""
  read -rsp "  GITHUB_TOKEN: " github_token; echo ""

  # Auto-generate the Mission Control platform token (no user input needed)
  local mc_token
  mc_token=$(python3 -c "import secrets; print(secrets.token_urlsafe(48))")

  cat > "${env_file}" <<EOF
ANTHROPIC_API_KEY=${anthropic_key}
TELEGRAM_BOT_TOKEN=${telegram_token}
GITHUB_TOKEN=${github_token}
MC_PLATFORM_TOKEN=${mc_token}
EOF

  ok "Credentials written to ${env_file}"
  ok "MC_PLATFORM_TOKEN auto-generated"
  warn "Back this file up securely — it is gitignored and not in any repo."
}

# ── Step 3b: Restore identity and memory files from agent-identities ──────────

restore_identity_files() {
  heading "Step 3b — Restore identity & memory files"

  local identities_dir="${IDEA_DIR}/agent-identities-restore"

  if [[ ! -d "${identities_dir}/.git" ]]; then
    info "Cloning agent-identities backup repo..."
    git clone "https://github.com/${GITHUB_ACCOUNT}/${AGENT_IDENTITIES_REPO}.git" "${identities_dir}"
  else
    ok "agent-identities already present — pulling latest"
    git -C "${identities_dir}" pull --ff-only origin main
  fi

  local identity_files="AGENTS.md SOUL.md IDENTITY.md USER.md TOOLS.md HEARTBEAT.md MEMORY.md"

  for repo in "${AGENT_REPOS[@]}"; do
    local src="${identities_dir}/${repo}"
    local dest="${AGENTS_DIR}/${repo}"

    if [[ ! -d "${src}" ]]; then
      warn "No identity backup found for ${repo} — skipping"
      continue
    fi

    for f in ${identity_files}; do
      [[ -f "${src}/${f}" ]] && cp "${src}/${f}" "${dest}/${f}"
    done

    [[ -d "${src}/memory" ]]  && rsync -a "${src}/memory/"  "${dest}/memory/"
    [[ -d "${src}/outputs" ]] && rsync -a "${src}/outputs/" "${dest}/outputs/"

    ok "Restored identity + memory for ${repo}"
  done

  rm -rf "${identities_dir}"
}

# ── Step 4: Write agent .env files ────────────────────────────────────────────

configure_agent_envs() {
  heading "Step 4 — Agent .env files"

  local env_src="${IDEA_DIR}/openclaw/.env"

  for repo in "${AGENT_REPOS[@]}"; do
    local dest="${AGENTS_DIR}/${repo}/.env"
    if [[ -f "${dest}" ]]; then
      ok "${repo}/.env — already present"
    else
      cp "${env_src}" "${dest}"
      ok "Wrote ${repo}/.env"
    fi
  done
}

# ── Step 5: Install and start OpenClaw ────────────────────────────────────────

start_openclaw() {
  heading "Step 5 — OpenClaw"

  # Clone the OpenClaw repo if not already present
  if [[ ! -d "${OPENCLAW_DIR}/.git" ]]; then
    info "Cloning OpenClaw into ${OPENCLAW_DIR}..."
    git clone https://github.com/openclaw/openclaw.git "${OPENCLAW_DIR}"
  else
    ok "OpenClaw repo already present at ${OPENCLAW_DIR}"
  fi

  # Run docker-setup.sh if the gateway container is not yet running
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^openclaw-gateway$"; then
    ok "openclaw-gateway already running"
  else
    info "Running OpenClaw Docker setup..."
    info "  The setup wizard will prompt you for an Anthropic API key."
    info "  Use the key from ${IDEA_DIR}/openclaw/.env (ANTHROPIC_API_KEY)."
    echo ""

    source "${IDEA_DIR}/openclaw/.env"
    export OPENCLAW_EXTRA_MOUNTS="${IDEA_DIR}:/home/node/workspace:rw"
    export ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY}"

    cd "${OPENCLAW_DIR}"
    bash docker-setup.sh
    cd - >/dev/null
  fi

  # Apply IDEA's openclaw.json on top of the auto-generated config
  apply_openclaw_config
}

apply_openclaw_config() {
  local template="${IDEA_DIR}/platform/openclaw.json"
  local deployed="${HOME}/.openclaw/openclaw.json"
  local env_file="${IDEA_DIR}/openclaw/.env"

  source "${env_file}"

  info "Applying IDEA openclaw.json..."

  # Use Python to merge configs:
  #   - Start from the IDEA template (strips JSON5 comments)
  #   - Preserve gateway.remote.token from the auto-generated config
  #   - Substitute {{TELEGRAM_BOT_TOKEN}}
  python3 - "${template}" "${deployed}" "${TELEGRAM_BOT_TOKEN}" << 'PYEOF'
import sys, re, json

template_path, deployed_path, bot_token = sys.argv[1], sys.argv[2], sys.argv[3]

def load_json5(path):
    with open(path) as f:
        content = f.read()
    content = re.sub(r'//[^\n]*', '', content)   # strip // comments
    content = re.sub(r',(\s*[}\]])', r'\1', content)  # strip trailing commas
    return json.loads(content)

# Load IDEA template
config = load_json5(template_path)

# Substitute bot token
config['channels']['telegram']['botToken'] = bot_token

# Preserve auto-generated gateway token if present
try:
    existing = json.load(open(deployed_path))
    if existing.get('gateway', {}).get('remote', {}).get('token'):
        config.setdefault('gateway', {}).setdefault('remote', {})
        config['gateway']['remote']['token'] = existing['gateway']['remote']['token']
except (FileNotFoundError, json.JSONDecodeError):
    pass

with open(deployed_path, 'w') as f:
    json.dump(config, f, indent=2)

print(f"  Applied to {deployed_path}")
PYEOF

  # Apply cron jobs
  apply_cron_jobs

  # Restart gateway to pick up new config and cron jobs
  info "Restarting openclaw-gateway..."
  cd "${OPENCLAW_DIR}"
  docker compose restart openclaw-gateway
  cd - >/dev/null
  ok "openclaw-gateway restarted with IDEA config"
}

apply_cron_jobs() {
  local cron_template="${IDEA_DIR}/platform/cron-jobs.json"
  local cron_dir="${HOME}/.openclaw/cron"
  local cron_file="${cron_dir}/jobs.json"

  if [[ ! -f "${cron_template}" ]]; then
    warn "platform/cron-jobs.json not found — skipping cron setup"
    return
  fi

  mkdir -p "${cron_dir}"
  cp "${cron_template}" "${cron_file}"
  ok "Cron jobs applied ($(python3 -c "import json; d=json.load(open('${cron_file}')); print(len(d['jobs']),'jobs')"))"
}

# ── Step 5b: Mission Control platform ────────────────────────────────────────

start_mission_control() {
  heading "Step 5b — Mission Control"

  local platform_dir="${IDEA_DIR}/platform"

  if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "mission-control"; then
    ok "Mission Control already running"
    return
  fi

  if [[ ! -f "${platform_dir}/compose.yaml" ]]; then
    die "platform/compose.yaml not found — cannot start Mission Control"
  fi

  # Write platform/.env from openclaw/.env if needed
  if [[ ! -f "${platform_dir}/.env" ]]; then
    info "Writing platform/.env..."
    source "${IDEA_DIR}/openclaw/.env"
    echo "MC_LOCAL_AUTH_TOKEN=${MC_PLATFORM_TOKEN}" > "${platform_dir}/.env"
    ok "platform/.env written (MC_LOCAL_AUTH_TOKEN set)"
  else
    ok "platform/.env already present"
  fi

  info "Starting Mission Control platform..."
  docker compose -f "${platform_dir}/compose.yaml" up -d
  ok "Mission Control started"
}

# ── Step 5c: Pi crontab for nightly identity backup ───────────────────────────

setup_backup_cron() {
  heading "Step 5c — Nightly identity backup cron"

  local cron_line="0 3 * * * /home/pi/idea/scripts/backup-agent-identities.sh >> /var/log/agent-backup.log 2>&1"

  if crontab -l 2>/dev/null | grep -q "backup-agent-identities"; then
    ok "Backup cron already present"
  else
    (crontab -l 2>/dev/null; echo "${cron_line}") | crontab -
    ok "Nightly backup cron added (03:00 UTC daily)"
  fi
}

# ── Step 5d: Provision per-agent MC auth tokens ───────────────────────────────
#
# Generates a fresh AUTH_TOKEN for each board lead agent, hashes it with
# PBKDF2-SHA256, updates the MC database, and writes the plaintext token to
# each agent's .env file.
#
# Requires: Mission Control DB must be running (Step 5b).
# Works for restore scenarios where agents already exist in the DB.
# On a true fresh install (no existing DB), agents won't be present yet —
# this step skips them gracefully; re-run after /init bootstraps all agents.

provision_agent_tokens() {
  heading "Step 5d — Agent MC tokens"

  # Map repo name → MC agent display name (must match agents.name in DB)
  declare -A AGENT_NAMES=(
    ["agent-operations-manager"]="Atlas"
    ["agent-engine-dev"]="Axle"
    ["agent-console-dev"]="Pixel"
    ["agent-site-dev"]="Beacon"
    ["agent-programme-manager"]="Marco"
  )

  source "${IDEA_DIR}/openclaw/.env"
  local mc_platform_token="${MC_PLATFORM_TOKEN}"

  # Wait for MC DB to be healthy
  info "Waiting for Mission Control DB..."
  local retries=30
  until docker exec openclaw-mission-control-db-1 pg_isready -U postgres &>/dev/null 2>&1; do
    retries=$((retries - 1))
    [[ ${retries} -le 0 ]] && die "Mission Control DB did not become ready in time"
    sleep 2
  done
  ok "MC DB ready"

  local any_provisioned=false

  for repo in "${AGENT_REPOS[@]}"; do
    local agent_name="${AGENT_NAMES[${repo}]:-}"
    local dest="${AGENTS_DIR}/${repo}/.env"

    if [[ -z "${agent_name}" ]]; then
      warn "No agent name mapping for ${repo} — skipping"
      continue
    fi

    # Check agent exists as board lead in DB
    local agent_count
    agent_count=$(docker exec openclaw-mission-control-db-1 psql -U postgres mission_control \
      -tAc "SELECT COUNT(*) FROM agents WHERE name='${agent_name}' AND is_board_lead=true" \
      | tr -d '[:space:]')

    if [[ "${agent_count:-0}" -eq 0 ]]; then
      warn "${agent_name} — not in MC DB yet (re-run after /init bootstraps agents)"
      continue
    fi

    # Look up board_id
    local board_id
    board_id=$(docker exec openclaw-mission-control-db-1 psql -U postgres mission_control \
      -tAc "SELECT board_id FROM agents WHERE name='${agent_name}' AND is_board_lead=true LIMIT 1" \
      | tr -d '[:space:]')

    # Generate fresh random token
    local token
    token=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")

    # Hash with PBKDF2-SHA256 (Django-compatible, 200000 iterations)
    local token_hash
    token_hash=$(echo "${token}" | python3 - << 'PYEOF'
import sys, hashlib, base64, os
pw = sys.stdin.readline().strip()
salt = base64.urlsafe_b64encode(os.urandom(16)).decode().rstrip('=')
dk = hashlib.pbkdf2_hmac('sha256', pw.encode(), salt.encode(), 200000)
print("pbkdf2_sha256$200000$" + salt + "$" + base64.b64encode(dk).decode())
PYEOF
)

    # Update the DB
    docker exec openclaw-mission-control-db-1 psql -U postgres mission_control \
      -c "UPDATE agents SET agent_token_hash='${token_hash}' \
          WHERE name='${agent_name}' AND is_board_lead=true" &>/dev/null

    # Write/update agent .env (idempotent — replaces existing values)
    set_env_var "${dest}" "AUTH_TOKEN"        "${token}"
    set_env_var "${dest}" "MC_PLATFORM_TOKEN" "${mc_platform_token}"
    set_env_var "${dest}" "BOARD_ID"          "${board_id}"

    ok "${agent_name} — AUTH_TOKEN provisioned, BOARD_ID=${board_id}"
    any_provisioned=true
  done

  if [[ "${any_provisioned}" == "false" ]]; then
    warn "No agents provisioned — MC DB may be empty (fresh install)"
    warn "After first /init in each agent group, re-run: bash scripts/setup.sh"
  fi
}

# ── Step 6: Tailscale ─────────────────────────────────────────────────────────

setup_tailscale() {
  heading "Step 6 — Tailscale"

  if command -v tailscale &>/dev/null && tailscale status &>/dev/null 2>&1; then
    ok "Tailscale already connected: $(tailscale ip -4 2>/dev/null)"
    return
  fi

  info "Installing Tailscale..."
  curl -fsSL https://tailscale.com/install.sh | sh

  echo ""
  read -rsp "  Tailscale auth key (tskey-auth-...): " ts_key; echo ""
  sudo tailscale up --auth-key="${ts_key}" --hostname="openclaw-pi"

  ok "Tailscale connected: $(tailscale ip -4 2>/dev/null)"
}

# ── Summary ───────────────────────────────────────────────────────────────────

print_summary() {
  local ts_ip
  ts_ip=$(tailscale ip -4 2>/dev/null || echo "<tailscale-ip>")

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo " IDEA — Setup Complete"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "  OpenClaw UI:      https://${ts_ip}"
  echo "  Mission Control:  http://${ts_ip}:8000"
  echo ""
  echo "  Next steps:"
  echo ""
  echo "  1. Open OpenClaw UI and paste the gateway token"
  echo "     (token is in ${OPENCLAW_DIR}/.env as OPENCLAW_GATEWAY_TOKEN)"
  echo ""
  echo "  2. Start all agent claude sessions:"
  echo "     bash ${IDEA_DIR}/scripts/start-agents.sh"
  echo ""
  echo "  3. Open Tabby — connect to all 5 agent tabs"
  echo "     (see idea/openclaw/README.md → Tabby setup)"
  echo ""
  echo "  4. Run /init in each agent's Telegram group to bootstrap"
  echo ""
  echo "  Credentials: ${IDEA_DIR}/openclaw/.env   ← keep this safe"
  echo ""
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo " IDEA — Installation Script"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  require_root_or_sudo
  install_deps
  clone_agent_repos
  configure_credentials
  restore_identity_files
  configure_agent_envs
  start_openclaw
  start_mission_control
  provision_agent_tokens
  setup_backup_cron
  setup_tailscale
  print_summary
}

main "$@"
