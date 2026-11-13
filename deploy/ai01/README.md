# AI01 deploy (branch `ai01`)

`whatsapp-mcp-extended` runs on AI01 (AppServer LXC 101, Portainer endpoint 4) as the git-linked stack
**`whatsapp-mcp`**. The stack points at this repo, branch `ai01`, compose file `deploy/ai01/docker-compose.yml`. GitHub Actions builds the images to GHCR (`ghcr.io/cjam28/whatsapp-bridge` and `whatsapp-mcp`, tagged `:ai01` and `:sha-<rev>`). Portainer can't build on AI01: its BuildKit fails with "frame too large".
MCPHub (https://mcp.christoalto.com) reaches it at `http://whatsapp-mcp:8081/mcp` over `mcp_net`. The hub group is
`whatsapp` (`/mcp/$smart/whatsapp`).

| Container | Role |
|---|---|
| `whatsapp-bridge` | Go/whatsmeow daemon. Holds the WhatsApp session in volume `whatsapp-mcp_whatsapp_store` |
| `whatsapp-mcp` | FastMCP server, streamable HTTP on `:8081`. No auth, so no host port and no public route |
| `whatsapp-pair` | One-shot helper that requests a phone pairing code when `WHATSAPP_PAIR_PHONE` is set and the bridge isn't linked |

## Stack env

| Var | Required | Notes |
|---|---|---|
| `WHATSAPP_API_KEY` | yes | Bridge API key. Stored at `op://ai01/christoalto-WhatsApp-MCP/api_key` |
| `WHATSAPP_PAIR_PHONE` | while pairing | Country code + number, digits only |
| `WHATSAPP_MCP_TOOLSETS` | no | Defaults to `all` |
| `WHATSAPP_ALLOWLIST_JIDS` | no | Restricts outgoing sends to these JIDs |
| `ANTIBAN_*`, `WA_PRESENCE_MODE`, `PRESENCE_PING_ENABLED` | no | Rate-limit tuning (below) |

## Rate limiting (this is a personal number)

Upstream ships the anti-ban layer **off**. This deploy turns it on:

- **Spacing.** Every send, reaction, edit, delete and poll goes through one queue with a random 3–8 s gap (1–3 s for reactions), plus a typing delay of 40 ms per character.
- **Daily cap.** Upstream removes the cap entirely once `ANTIBAN_WARMUP_DAYS` have passed, so warm-up is set to 3650 days. The cap starts at 30 sends a day and climbs about 0.18 per day, reaching roughly 95 a day after a year. 72 hours with no sends resets it to day 0. The state lives in `store/antiban_warmup.json` on the volume.
- **Risk pause.** Disconnects, stream errors and failed sends (403) raise a risk score. At 50, all sends stop (`antiban: health monitor paused sends`), and they resume once the score decays to 30.
- **Presence.** `human` mode goes online only briefly around sends, and the 20-minute "online" ping is off.

Upstream's warning still applies: this is an unofficial client, and WhatsApp bans automation.

## Pair or re-pair

**QR page (easiest):** set `WHATSAPP_QR_PAGE=1` in the stack env, then redeploy. Open http://192.168.99.154:8095 (LAN or Tailscale only) and scan it from WhatsApp → Settings → Linked devices → Link a device. The bridge only issues QR codes for about 2 minutes after it starts. If the page says the code expired, restart `whatsapp-bridge`. When the page says *Linked*, set `WHATSAPP_QR_PAGE=0` and redeploy. The page proxies only `GET /qr` → bridge `/api/qr`, a route this fork adds; the API key stays server-side.

**Phone code (no camera):**

1. Set `WHATSAPP_PAIR_PHONE` in the stack env, then redeploy (or start the `whatsapp-pair` container).
2. Read the code from the `whatsapp-pair` logs: lines starting `PAIR_REQUEST … "code":"XXXX-XXXX"`. A new code is printed every 2.5 minutes, for 10 minutes.
3. On the phone, open WhatsApp → Settings → Linked devices → Link a device → **Link with phone number instead**, and enter the code.
4. The helper logs `PAIRED` and exits 0. The session survives restarts and redeploys.

Re-pairing is only needed if the phone has been offline for more than 14 days, the device was unlinked, or WhatsApp revoked the session. The bridge then reports `needs_pairing: true`.

## Deploy and upgrade

- Pushing to `ai01` runs `.github/workflows/ai01-deploy.yml`: it builds and pushes both images, then POSTs the stack webhook (repo secret `AI01_WHATSAPP_STACK_WEBHOOK`). The stack force-pulls `:ai01`. To pin a revision, set `WHATSAPP_IMAGE_TAG=sha-<rev>` in the stack env.
- To take an upstream release, merge `upstream/main` into `ai01` and push.
- Creating the stack from scratch: `deploy/ai01/portainer-create-stack.sh`.
