#!/usr/bin/env bash
# Create the AI01 `whatsapp-mcp` Portainer git stack (endpoint 4) and print its webhook URL.
# Needs: AI01_PORTAINER_API_TOKEN (e.g. from ~/.cursor/mcp.secrets.env) and WHATSAPP_API_KEY.
# Optional: WHATSAPP_PAIR_PHONE (digits, country code first) to start pairing on first deploy.
# Never echo the response body: it contains the stack Env.
set -euo pipefail

PORTAINER_URL="${PORTAINER_URL:-https://192.168.99.154:9443}"
ENDPOINT_ID="${ENDPOINT_ID:-4}"
STACK_NAME="${STACK_NAME:-whatsapp-mcp}"

if [ -z "${AI01_PORTAINER_API_TOKEN:-}" ] && [ -f "$HOME/.cursor/mcp.secrets.env" ]; then
  AI01_PORTAINER_API_TOKEN="$(sed -n 's/^AI01_PORTAINER_API_TOKEN=//p' "$HOME/.cursor/mcp.secrets.env" | head -1)"
fi
: "${AI01_PORTAINER_API_TOKEN:?set AI01_PORTAINER_API_TOKEN}"
: "${WHATSAPP_API_KEY:?set WHATSAPP_API_KEY (op://ai01/christoalto-WhatsApp-MCP/api_key)}"
export AI01_PORTAINER_API_TOKEN WHATSAPP_API_KEY WHATSAPP_PAIR_PHONE="${WHATSAPP_PAIR_PHONE:-}"

payload="$(mktemp)"
trap 'rm -f "$payload"' EXIT
python3 - "$STACK_NAME" > "$payload" <<'PY'
import json, os, sys, uuid
env = {"WHATSAPP_API_KEY": os.environ["WHATSAPP_API_KEY"], "WHATSAPP_MCP_TOOLSETS": "all"}
if os.environ.get("WHATSAPP_PAIR_PHONE"):
    env["WHATSAPP_PAIR_PHONE"] = os.environ["WHATSAPP_PAIR_PHONE"]
print(json.dumps({
    "Name": sys.argv[1],
    "RepositoryURL": "https://github.com/cjam28/whatsapp-mcp-extended",
    "RepositoryReferenceName": "refs/heads/ai01",
    "ComposeFile": "deploy/ai01/docker-compose.yml",
    "RepositoryAuthentication": False,
    "AutoUpdate": {"Webhook": str(uuid.uuid4()), "ForceUpdate": False, "ForcePullImage": False},
    "Env": [{"name": k, "value": v} for k, v in env.items()],
}))
PY

echo "Creating stack $STACK_NAME (Portainer builds both images; can take several minutes)..."
resp="$(curl -skS --max-time 1200 -X POST \
  -H "X-API-Key: $AI01_PORTAINER_API_TOKEN" -H "Content-Type: application/json" \
  -d @"$payload" "$PORTAINER_URL/api/stacks/create/standalone/repository?endpointId=$ENDPOINT_ID")"
python3 -c '
import json, sys
d = json.loads(sys.argv[1])
if "Id" not in d:
    print("ERROR:", d.get("message"), d.get("details")); sys.exit(1)
print("stack id:", d["Id"])
print("webhook: https://aiport.christoalto.com/api/stacks/webhooks/" + d["AutoUpdate"]["Webhook"])
' "$resp"
