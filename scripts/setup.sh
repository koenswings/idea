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
#   3. Prompts for credentials and writes secrets/ files
#   4. Installs OpenClaw natively (npm install -g, systemd daemon as pi user)
#   5. Applies IDEA's openclaw.json (agent roster, Telegram bindings)
#   6. Connects to Tailscale
#   7. Prints first-run instructions
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
AGENTS_DIR="${IDEA_DIR}/agents"
SECRETS_DIR="${IDEA_DIR}/platform/secrets"
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

# ── Step 1b: Docker DNS configuration ───────────────────────────────────────────
#
# Tailscale rewrites /etc/resolv.conf on the host to use its own nameserver
# (100.100.100.100). Docker inherits this, causing container DNS to miss
# Docker-internal service names like 'mission-control-db'.
# Locking Docker's daemon DNS to 127.0.0.11 (Docker's embedded resolver)
# prevents this permanently, regardless of Tailscale state.

configure_docker_dns() {
  heading "Step 1b — Docker DNS configuration"

  local daemon_json="/etc/docker/daemon.json"

  if sudo python3 -c "
import json
with open('${daemon_json}') as f:
    d = json.load(f)
print('ok' if d.get('dns') == ['127.0.0.11'] else 'missing')
" 2>/dev/null | grep -q '^ok$'; then
    ok "Docker DNS already set to 127.0.0.11"
    return
  fi

  info "Setting Docker DNS to 127.0.0.11 in ${daemon_json}..."
  sudo python3 -c "
import json
try:
    with open('${daemon_json}') as f:
        d = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    d = {}
d['dns'] = ['127.0.0.11']
with open('${daemon_json}', 'w') as f:
    json.dump(d, f, indent=2)
"

  info "Restarting Docker to apply DNS config..."
  sudo systemctl restart docker
  sleep 3
  ok "Docker DNS configured and restarted"
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

  # Secrets are stored in platform/secrets/ as individual files (root-owned)
  # so they can be bind-mounted selectively by Docker services.
  sudo mkdir -p "${SECRETS_DIR}"

  local need_input=false
  [[ ! -f "${SECRETS_DIR}/anthropic_api_key.txt" ]] && need_input=true
  [[ ! -f "${SECRETS_DIR}/mc_db_password.txt" ]]    && need_input=true

  if [[ "${need_input}" == "false" ]]; then
    ok "Secrets already present in ${SECRETS_DIR} — skipping"
    return
  fi

  echo ""
  echo "  Enter your credentials. Input is hidden."
  echo ""

  if [[ ! -f "${SECRETS_DIR}/anthropic_api_key.txt" ]]; then
    local anthropic_key
    read -rsp "  ANTHROPIC_API_KEY: " anthropic_key; echo ""
    echo -n "${anthropic_key}" | sudo tee "${SECRETS_DIR}/anthropic_api_key.txt" >/dev/null
    sudo chown pi:pi "${SECRETS_DIR}/anthropic_api_key.txt"
    sudo chmod 600   "${SECRETS_DIR}/anthropic_api_key.txt"
    ok "anthropic_api_key.txt written"
  fi

  if [[ ! -f "${SECRETS_DIR}/mc_db_password.txt" ]]; then
    local mc_db_password
    mc_db_password=$(python3 -c "import secrets; print(secrets.token_urlsafe(16))")
    echo -n "${mc_db_password}" | sudo tee "${SECRETS_DIR}/mc_db_password.txt" >/dev/null
    sudo chmod 600 "${SECRETS_DIR}/mc_db_password.txt"
    ok "mc_db_password.txt written (auto-generated)"
  fi

  warn "Back up ${SECRETS_DIR}/ securely — these files are gitignored."
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

  local api_key
  api_key=$(cat "${SECRETS_DIR}/anthropic_api_key.txt")

  for repo in "${AGENT_REPOS[@]}"; do
    local dest="${AGENTS_DIR}/${repo}/.env"
    if [[ -f "${dest}" ]]; then
      ok "${repo}/.env — already present"
    else
      echo "ANTHROPIC_API_KEY=${api_key}" > "${dest}"
      ok "Wrote ${repo}/.env"
    fi
  done
}

# ── Step 5: Install and start OpenClaw (native) ───────────────────────────────

start_openclaw() {
  heading "Step 5 — OpenClaw (native)"

  # Install OpenClaw globally if not already present
  if ! command -v openclaw &>/dev/null; then
    info "Installing OpenClaw natively..."
    npm install -g openclaw@latest
    ok "OpenClaw installed: $(openclaw --version)"
  else
    ok "OpenClaw already installed: $(openclaw --version)"
  fi

  # Create workspace symlink so agent path refs (/home/node/workspace/...) resolve
  if [[ ! -L /home/node/workspace ]]; then
    info "Creating /home/node/workspace symlink..."
    sudo mkdir -p /home/node
    sudo ln -sfn "${IDEA_DIR}" /home/node/workspace
    ok "Symlink: /home/node/workspace -> ${IDEA_DIR}"
  else
    ok "Symlink /home/node/workspace already present"
  fi

  # Apply IDEA's openclaw config
  apply_openclaw_config

  # Install and start systemd daemon
  if systemctl --user is-active openclaw-gateway &>/dev/null; then
    ok "openclaw-gateway service already running — restarting to pick up new config..."
    systemctl --user restart openclaw-gateway
  else
    info "Installing openclaw-gateway systemd service..."
    openclaw gateway install

    # Inject ANTHROPIC_API_KEY into the service environment
    local api_key
    api_key=$(cat "${SECRETS_DIR}/anthropic_api_key.txt")
    local dropin_dir="${HOME}/.config/systemd/user/openclaw-gateway.service.d"
    mkdir -p "${dropin_dir}"
    printf '[Service]\nEnvironment="ANTHROPIC_API_KEY=%s"\n' "${api_key}" > "${dropin_dir}/env.conf"
    chmod 600 "${dropin_dir}/env.conf"

    systemctl --user daemon-reload
    systemctl --user start openclaw-gateway
    ok "openclaw-gateway started"
  fi
}

apply_openclaw_config() {
  local template="${IDEA_DIR}/platform/openclaw.json"
  local deployed="${HOME}/.openclaw/openclaw.json"

  if [[ ! -f "${template}" ]]; then
    warn "platform/openclaw.json not found — skipping config apply"
    return
  fi

  info "Applying IDEA openclaw.json..."
  mkdir -p "${HOME}/.openclaw"

  python3 - "${template}" "${deployed}" << 'PYEOF'
import sys, re, json, os

template_path, deployed_path = sys.argv[1], sys.argv[2]

def load_json5(path):
    with open(path) as f:
        content = f.read()
    content = re.sub(r'//[^\n]*', '', content)
    content = re.sub(r',(\s*[}\]])', r'\1', content)
    return json.loads(content)

config = load_json5(template_path)

# Preserve existing gateway tokens if present
try:
    existing = json.load(open(deployed_path))
    gw = existing.get('gateway', {})
    if gw.get('remote', {}).get('token'):
        config.setdefault('gateway', {}).setdefault('remote', {})
        config['gateway']['remote']['token'] = gw['remote']['token']
    if gw.get('auth', {}).get('token'):
        config.setdefault('gateway', {}).setdefault('auth', {})
        config['gateway']['auth'] = gw['auth']
except (FileNotFoundError, json.JSONDecodeError):
    pass

with open(deployed_path, 'w') as f:
    json.dump(config, f, indent=2)

print(f"  Applied to {deployed_path}")
PYEOF

  # Apply cron jobs
  apply_cron_jobs
  ok "openclaw.json applied"
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

  # Write platform/.env if needed (MC_LOCAL_AUTH_TOKEN + MC_DB_PASSWORD)
  if [[ ! -f "${platform_dir}/.env" ]]; then
    info "Writing platform/.env..."
    local mc_token mc_db_password
    mc_token=$(python3 -c "import secrets; print(secrets.token_urlsafe(48))")
    mc_db_password=$(cat "${SECRETS_DIR}/mc_db_password.txt")
    printf 'MC_LOCAL_AUTH_TOKEN=%s\nMC_DB_PASSWORD=%s\n' "${mc_token}" "${mc_db_password}" \
      | sudo tee "${platform_dir}/.env" >/dev/null
    sudo chmod 600 "${platform_dir}/.env"
    ok "platform/.env written"
  else
    ok "platform/.env already present"
  fi

  info "Starting Mission Control platform..."
  docker compose -f "${platform_dir}/compose.yaml" up -d
  ok "Mission Control started"

  # Install the socat proxy that bridges the Docker network to the gateway
  install_mc_proxy
}

# ── MC gateway proxy (socat) ──────────────────────────────────────────────────
# MC backend runs in Docker and connects to the OpenClaw gateway via WebSocket.
# Tailscale Serve strips ?token= query params on WS upgrades, so we can't route
# through it. Instead a socat proxy listens on the Docker bridge (172.20.0.1:18790)
# and forwards to the loopback gateway (127.0.0.1:18789).
install_mc_proxy() {
  local service_file="${HOME}/.config/systemd/user/openclaw-mc-proxy.service"

  if systemctl --user is-active openclaw-mc-proxy &>/dev/null; then
    ok "openclaw-mc-proxy already running"
    return
  fi

  if ! command -v socat &>/dev/null; then
    info "Installing socat..."
    sudo apt-get install -y -q socat
  fi

  info "Installing openclaw-mc-proxy systemd service..."
  mkdir -p "${HOME}/.config/systemd/user"
  cat > "${service_file}" << 'UNIT'
[Unit]
Description=OpenClaw MC Gateway Proxy (Docker bridge -> loopback:18789)
After=network.target openclaw-gateway.service
PartOf=openclaw-gateway.service

[Service]
Type=simple
ExecStart=/usr/bin/socat TCP-LISTEN:18790,bind=172.20.0.1,reuseaddr,fork TCP:127.0.0.1:18789
Restart=always
RestartSec=3

[Install]
WantedBy=default.target
UNIT

  systemctl --user daemon-reload
  systemctl --user enable --now openclaw-mc-proxy
  ok "openclaw-mc-proxy started (172.20.0.1:18790 → 127.0.0.1:18789)"
}

# ── Step 5c: Pi crontab for nightly identity backup ───────────────────────────

setup_backup_cron() {
  heading "Step 5c — Nightly identity backup cron"

  local log_dir="/home/pi/idea/logs"
  local log_file="${log_dir}/agent-backup.log"
  local cron_line="0 3 * * * /home/pi/idea/scripts/backup-agent-identities.sh >> ${log_file} 2>&1"

  mkdir -p "${log_dir}"

  if crontab -l 2>/dev/null | grep -q "backup-agent-identities"; then
    ok "Backup cron already present"
  else
    (crontab -l 2>/dev/null; echo "${cron_line}") | crontab -
    ok "Nightly backup cron added (03:00 UTC daily) → logs: ${log_file}"
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

  local mc_platform_token
  mc_platform_token=$(sudo grep -Po '(?<=MC_LOCAL_AUTH_TOKEN=)\S+' "${IDEA_DIR}/platform/.env" 2>/dev/null || echo "")

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
  echo "  OpenClaw UI:      http://${ts_ip}:18789"
  echo "  Mission Control:  http://${ts_ip}:8000"
  echo ""
  echo "  Next steps:"
  echo ""
  echo "  1. Check OpenClaw gateway:  openclaw gateway status"
  echo "     Check Telegram:           openclaw channels status"
  echo ""
  echo "  2. Start all agent claude sessions:"
  echo "     bash ${IDEA_DIR}/scripts/start-agents.sh"
  echo ""
  echo "  3. Open Tabby — connect to all 5 agent tabs"
  echo ""
  echo "  4. Run /init in each agent's Telegram group to bootstrap"
  echo ""
  echo "  Secrets: ${IDEA_DIR}/platform/secrets/   ← keep this safe"
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
  configure_docker_dns
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
