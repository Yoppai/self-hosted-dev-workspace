# Deploy to Dokploy — Self-Hosted Workspace

This guide covers deploying the workspace Compose stack to Dokploy using CI-built images from GHCR.

## Prerequisites

- A Dokploy instance running on your VPS
- Repository access to [`yoppai/self-hosted-dev-workspace`](https://github.com/yoppai/self-hosted-dev-workspace)
- Docker installed on the VPS (Dokploy handles this)
- A GitHub Personal Access Token with `read:packages` scope for GHCR auth

---

## Required GitHub Secrets

Set this in **Settings → Secrets and variables → Actions**:

| Secret | Purpose | Where to get it |
|--------|---------|-----------------|
| `DOKPLOY_WEBHOOK_URL` | POST deploy trigger to Dokploy | Dokploy UI → Service → Webhook |

> 💡 GHCR authentication for the CI workflow uses GitHub's built-in `GITHUB_TOKEN` — no PAT setup required. For Dokploy's registry pull access (Step 3), you still need a PAT with `read:packages`.

> The `DOKPLOY_WEBHOOK_SECRET` secret is no longer used — Dokploy Compose webhook does not require an auth header.

---

## Step 1: Pre-create External Volumes

Before the first Dokploy deploy, run `scripts/bootstrap.sh` on the VPS to create external volumes with correct permissions:

```bash
# On the Dokploy VPS:
sudo ./scripts/bootstrap.sh
```

This creates three external volumes with UID 1000 ownership:
- `workspace_projects` — shared project files
- `workspace_profile` — shared `.config`, `.ssh`, OAuth tokens
- `toolchains` — user-installed toolchains (`~/.local/bin`)

> **Idempotent**: Safe to run multiple times. Use `--dry-run` to preview actions.

---

## Step 2: Create Dokploy Project

1. Log into your Dokploy dashboard
2. Go to **Projects** → **New Project**
3. Name: `self-hosted-workspace`
4. Click **Create**

---

## Step 3: Add GHCR Registry

1. In Dokploy, go to **Registries** → **Add Registry**
2. **Registry URL**: `https://ghcr.io`
3. **Username**: `yoppai` (the GitHub owner)
4. **Password**: Your GitHub PAT with `read:packages` scope
5. Click **Test** to verify authentication
6. Test-pull image: `ghcr.io/yoppai/self-hosted-dev-workspace/opencode-server:latest`
7. Click **Save**

---

## Step 4: Create Compose Service (Raw Source)

1. Inside the project, click **New Service** → **Docker Compose**
2. **Source type**: **Raw**
3. **Service name**: `workspace-compose`
4. Paste the full contents of [`docker-compose.prod.yml`](../docker-compose.prod.yml) into the editor
5. Dokploy will parse it and display all four services, networks, and volumes

> ⚠️ `docker-compose.prod.yml` references only `image:` tags (no `build:` sections). All images are pre-built by CI and pushed to GHCR.

---

## Step 5: Configure Environment Variables

In the **Environment** tab of the Compose service, add these variables:

| Variable | Description |
|----------|-------------|
| `ANTHROPIC_API_KEY` | Anthropic API key for opencode-server and CodeNomad |
| `OPENAI_API_KEY` | OpenAI API key for opencode-server and CodeNomad |
| `CODE_SERVER_PASSWORD` | Password for code-server web UI |
| `OPENCODE_SERVER_USERNAME` | Username for opencode-server (default: `opencode`) |
| `OPENCODE_SERVER_PASSWORD` | Password for opencode-server |
| `CODENOMAD_SERVER_USERNAME` | Username for CodeNomad server |
| `CODENOMAD_SERVER_PASSWORD` | Password for CodeNomad server |
| `KASMVNC_PASSWORD` | VNC password for KasmVNC desktop |

> The `docker-compose.prod.yml` uses `${VAR:?err}` syntax — Dokploy will fail fast on deploy if any required variable is missing.

---

## Step 6: Configure Webhook URL

1. In the Compose service settings, go to **Webhook**
2. Copy the webhook URL — it looks like `https://your-dokploy.com/api/compose/abc123/trigger`
3. Save this as the `DOKPLOY_WEBHOOK_URL` secret in your GitHub repository

---

## Step 7: Deploy

1. Click **Save** and then **Deploy**
2. Dokploy pulls images from GHCR, creates networks and auto-created volumes, and starts all four services
3. Monitor the deployment log for any errors

### Post-deploy Verification

| Check | Expected |
|-------|----------|
| `code.workspace.yoppai.dev` | VS Code login page, HTTPS |
| `ai.workspace.yoppai.dev` | opencode-server reachable, HTTPS |
| `codenomad.workspace.yoppai.dev` | CodeNomad UI, HTTPS |
| `desktop.workspace.yoppai.dev` | KasmVNC desktop login, HTTPS |

---

## Normal Deploy Flow (Code Change → Deployed)

Once everything is configured, the automated flow is:

1. Developer pushes to `main` (or merges PR)
2. `build-images.yml` triggers on path-filtered changes
3. Jobs run: `changes` → `build-*` → `validate` → `push-images` → `notify-dokploy`
4. `notify-dokploy` POSTs to the Dokploy Compose webhook URL with repository metadata
5. Dokploy queues redeploy, pulls the `latest` images from GHCR
6. Containers restart with new images; volumes persist
7. Health checks pass

> Webhook failures are **non-fatal** — images are already in GHCR and can be deployed manually via the Dokploy UI.

---

## Rollback

1. In Dokploy UI: Stop the Compose service (or click a previous deployment)
2. Edit `docker-compose.prod.yml` in Dokploy: replace `:latest` with a known-good `sha-{7}` tag
3. Redeploy; containers start with the previous image
4. Data in `workspace_projects` and other volumes remains intact

---

## Volume Reference

| Volume | Type | Created by | Contents |
|--------|------|------------|----------|
| `workspace_projects` | External | `bootstrap.sh` | Shared project repositories |
| `workspace_profile` | External | `bootstrap.sh` | `.config`, `.ssh`, OAuth tokens |
| `toolchains` | External | `bootstrap.sh` | `~/.local/bin`, installed tools |
| `workspace_home` | Named (auto) | Docker | KasmVNC desktop home |
| `opencode_config` | Named (auto) | Docker | Global opencode config |
| `codenomad_config` | Named (auto) | Docker | CodeNomad sessions |
| `code_server_config` | Named (auto) | Docker | VS Code extensions |
| `kasm_config` | Named (auto) | Docker | VNC settings |
| `package_caches` | Named (auto) | Docker | npm/pnpm/bun caches |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| Deploy fails: "volume not found" | External volume not pre-created | Run `sudo ./scripts/bootstrap.sh` on VPS |
| Container exits immediately | Missing env var | Check Environment tab has all required variables |
| Webhook POST returns 4xx | Wrong webhook URL | Copy URL from Dokploy UI → Service → Webhook |
| Image pull fails | GHCR token expired | Regenerate PAT with `read:packages` scope |
| Domain returns 502 | Service not healthy yet | Wait for health check `start_period` to complete |
| "letsencrypt" cert resolver not found | Dokploy Traefik config | Check Dokploy Traefik has `letsencrypt` resolver configured |
