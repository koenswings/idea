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

# ── Helpers ───────────────────────────────────────────────────────────────────

info()    { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()      { echo -e "\033[1;32m[OK]\033[0m    $*"; }
warn()    { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
die()     { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }
heading() { echo -e "\n\033[1m$*\033[0m"; }

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
  local template="${IDEA_DIR}/openclaw/.env.template"

  if [[ -f "${env_file}" ]]; then
    warn ".env already exists at ${env_file} — skipping"
    warn "Delete it and re-run to reconfigure credentials."
    return
  fi

  cp "${template}" "${env_file}"

  echo ""
  echo "  Enter your credentials. Input is hidden."
  echo ""

  local key val
  for key in ANTHROPIC_API_KEY TELEGRAM_BOT_TOKEN GITHUB_TOKEN; do
    read -rsp "  ${key}: " val; echo ""
    sed -i "s|^${key}=.*|${key}=${val}|" "${env_file}"
  done

  ok "Credentials written to ${env_file}"
  warn "Back this file up securely — it is gitignored and not in any repo."
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
  local template="${IDEA_DIR}/openclaw/openclaw.json"
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

  # Restart gateway to pick up new config
  info "Restarting openclaw-gateway..."
  cd "${OPENCLAW_DIR}"
  docker compose restart openclaw-gateway
  cd - >/dev/null
  ok "openclaw-gateway restarted with IDEA config"
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
  configure_agent_envs
  start_openclaw
  setup_tailscale
  print_summary
}

main "$@"
