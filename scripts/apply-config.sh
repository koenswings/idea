#!/usr/bin/env bash
# apply-config.sh — apply openclaw.json changes to the running system
#
# Use this after merging changes to idea/platform/openclaw.json.
# For a full install on a fresh Pi, use setup.sh instead.

set -euo pipefail

IDEA_DIR="/home/pi/idea"
CONFIG_TEMPLATE="${IDEA_DIR}/platform/openclaw.json"
CONFIG_DEPLOYED="${HOME}/.openclaw/openclaw.json"
ENV_FILE="${IDEA_DIR}/platform/.env"

[[ -f "${ENV_FILE}" ]] || { echo "Missing ${ENV_FILE} — run setup.sh first"; exit 1; }
[[ -f "${CONFIG_TEMPLATE}" ]] || { echo "Missing ${CONFIG_TEMPLATE}"; exit 1; }

source "${ENV_FILE}"

echo "Applying openclaw.json..."

python3 - "${CONFIG_TEMPLATE}" "${CONFIG_DEPLOYED}" "${TELEGRAM_BOT_TOKEN}" << 'PYEOF'
import sys, re, json

template_path, deployed_path, bot_token = sys.argv[1], sys.argv[2], sys.argv[3]

def load_json5(path):
    with open(path) as f:
        content = f.read()
    content = re.sub(r'//[^\n]*', '', content)
    content = re.sub(r',(\s*[}\]])', r'\1', content)
    return json.loads(content)

config = load_json5(template_path)
config['channels']['telegram']['botToken'] = bot_token

try:
    existing = json.load(open(deployed_path))
    token = existing.get('gateway', {}).get('remote', {}).get('token')
    if token:
        config.setdefault('gateway', {}).setdefault('remote', {})['token'] = token
except (FileNotFoundError, json.JSONDecodeError):
    pass

with open(deployed_path, 'w') as f:
    json.dump(config, f, indent=2)
print(f"Written to {deployed_path}")
PYEOF

echo "Restarting openclaw-gateway..."
cd "${IDEA_DIR}"
docker compose -f platform/compose.yaml restart openclaw-gateway
echo "Done."
