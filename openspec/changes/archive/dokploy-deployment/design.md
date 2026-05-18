# Design: Dokploy Deployment Pipeline

## Technical Approach

Map the existing CI-built ARM64 images to a single Dokploy Docker Compose service using **Raw YAML source**. The `docker-compose.prod.yml` (already GHCR-ready) is pasted into Dokploy. A GitHub Actions webhook POST triggers redeploy after every successful `push-images` job. External volumes are pre-created by `scripts/bootstrap.sh` with UID 1000 ownership before first deploy.

## Architecture Decisions

| Decision | Choice | Alternatives Rejected | Rationale |
|----------|--------|----------------------|-----------|
| Compose source type | Raw YAML paste | Git source (auto-deploy) | Git clone would clear bind-mount directories; raw keeps Dokploy stateless |
| Deploy trigger | Webhook POST to Compose URL | Dokploy API `compose.deploy` | Webhook URL is built-in, no API key management, maps 1:1 to existing `notify-dokploy` job |
| Registry auth | GHCR PAT (`read:packages`) | Docker Hub / ACR | Images already push to GHCR; PAT is single credential |
| Volume strategy | 3 external + 6 auto-created | All external / all auto-created | External volumes need UID 1000 pre-seeding; internal state volumes (config, caches) can be auto-created |
| Env var injection | Dokploy Environment tab | `.env` file in repo | Secrets must not be committed; Dokploy UI is the secure source |

## Data Flow

```
Developer pushes to main
        │
        ▼
┌─────────────────────┐
│  GitHub Actions CI  │  (self-hosted ARM64 runner)
│  build → validate   │
│  → push-images      │
└──────────┬──────────┘
           │  Images: ghcr.io/yoppai/self-hosted-dev-workspace/*:latest
           ▼
┌─────────────────────┐     POST webhook
│       GHCR          │ ──────────────────────►┌─────────────────────┐
│  (ghcr.io)          │  secrets.DOKPLOY_     │      Dokploy        │
└─────────────────────┘   COMPOSE_WEBHOOK_URL  │  Compose service    │
                                                 │  (Raw source)       │
                                                 └──────────┬──────────┘
                                                            │  Pull latest images
                                                            ▼
                                                 ┌─────────────────────┐
                                                 │   Docker Compose    │
                                                 │  workspace-net      │
                                                 │  4 services + 9 vols│
                                                 └──────────┬──────────┘
                                                            │
                              ┌─────────────────────────────┼─────────────────────────────┐
                              │                             │                             │
                              ▼                             ▼                             ▼
                    code-server           opencode-server         codenomad-server         kasmvnc-workspace
                    (port 8080)           (port 4096)              (port 9898)             (port 6901)
                    Traefik labels        Traefik labels           Traefik labels          Traefik labels
                    code.ws...            ai.ws...                 codenomad.ws...         desktop.ws...
```

## Component Design

### Dokploy Project / Service Structure
- **Project**: `self-hosted-workspace` (or existing Dokploy project)
- **Service**: `workspace-compose` — type: **Docker Compose**, source: **Raw**
- Paste the full contents of `docker-compose.prod.yml` into the Raw source editor
- No `build:` sections in the YAML — only `image:` references to GHCR

### Docker Compose Adjustments for Dokploy
No YAML changes are required. `docker-compose.prod.yml` is already Dokploy-compatible:
- All services use `image:` pointing to GHCR
- Traefik labels are present and self-contained
- `restart: unless-stopped` is present
- No host port bindings (Traefik is sole ingress)
- `shm_size: 2gb` and `deploy.resources.limits.memory: 4g` on KasmVNC

> **Note**: Dokploy runs its own Traefik instance. The labels in `docker-compose.prod.yml` are honored as dynamic configuration. Dokploy attaches containers to its `dokploy-network` automatically; our internal `workspace-net` bridge is kept for service-to-service DNS.

### GHCR Registry Configuration
1. In Dokploy → Registries → Add Registry
2. **Registry URL**: `https://ghcr.io`
3. **Username**: `yoppai` (or `${github.repository_owner}`)
4. **Password**: Personal Access Token with `read:packages` scope
5. Test-pull image: `ghcr.io/yoppai/self-hosted-dev-workspace/opencode-server:latest`

### Environment Variable Mapping

| Variable | Used By | Source |
|----------|---------|--------|
| `ANTHROPIC_API_KEY` | opencode-server, codenomad-server | Dokploy Environment tab |
| `OPENAI_API_KEY` | opencode-server, codenomad-server | Dokploy Environment tab |
| `CODE_SERVER_PASSWORD` | code-server | Dokploy Environment tab |
| `OPENCODE_SERVER_USERNAME` | opencode-server | Dokploy Environment tab |
| `OPENCODE_SERVER_PASSWORD` | opencode-server | Dokploy Environment tab |
| `CODENOMAD_SERVER_USERNAME` | codenomad-server | Dokploy Environment tab |
| `CODENOMAD_SERVER_PASSWORD` | codenomad-server | Dokploy Environment tab |
| `KASMVNC_PASSWORD` | kasmvnc-workspace | Dokploy Environment tab |

Dokploy injects these as environment variables into the Compose execution context. The `${VAR:?err}` syntax in `docker-compose.prod.yml` causes Docker Compose to fail fast if any required variable is missing.

### Volume Mount Strategy

| Volume | Type | Pre-create? | Rationale |
|----------|------|-------------|-----------|
| `workspace_projects` | External | Yes (`bootstrap.sh`) | Shared projects across all services; must have UID 1000 |
| `workspace_profile` | External | Yes (`bootstrap.sh`) | Shared `.config`, `.ssh`; must have UID 1000 |
| `toolchains` | External | Yes (`bootstrap.sh`) | Shared `~/.local/bin`; must have UID 1000 |
| `workspace_home` | Named (auto) | No | KasmVNC desktop home; auto-created OK |
| `opencode_config` | Named (auto) | No | opencode global config; first writer sets ownership |
| `codenomad_config` | Named (auto) | No | CodeNomad sessions; isolated per service |
| `code_server_config` | Named (auto) | No | VS Code extensions; isolated per service |
| `kasm_config` | Named (auto) | No | VNC settings; isolated per service |
| `package_caches` | Named (auto) | No | npm/pnpm caches; ephemeral OK |

## CI/CD Pipeline Design

### Current State Analysis
- `build-images.yml` already has a `notify-dokploy` job (lines 337–374)
- It uses `secrets.DOKPLOY_WEBHOOK_URL` and `secrets.DOKPLOY_WEBHOOK_SECRET`
- It POSTs a generic JSON payload with `event: deploy`

### Required Changes
1. **Secret name migration**: `DOKPLOY_WEBHOOK_URL` → `DOKPLOY_WEBHOOK_URL`
2. **Payload simplification**: Dokploy Compose webhooks accept a simple POST (often empty body or minimal JSON). The exact payload is a trigger signal; repository/sha metadata is nice-to-have.
3. **Error handling**: Keep `continue-on-error: true` and warn-on-failure behavior — images are already in GHCR.

### New `notify-dokploy` Job Design

```yaml
notify-dokploy:
  name: Notify Dokploy
  runs-on: self-hosted
  needs: push-images
  if: success()
  continue-on-error: true

  steps:
    - name: POST to Dokploy Compose webhook
      env:
        DOKPLOY_URL: ${{ secrets.DOKPLOY_WEBHOOK_URL }}
      run: |
        if [[ -z "$DOKPLOY_URL" ]]; then
          echo "::warning::DOKPLOY_WEBHOOK_URL not configured — skipping"
          exit 0
        fi

        HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
          -X POST \
          -H "Content-Type: application/json" \
          -d '{"repository":"${{ github.repository }}","sha":"${{ github.sha }}","ref":"${{ github.ref }}"}' \
          "$DOKPLOY_URL" 2>/dev/null || echo "000")

        if [[ "$HTTP_STATUS" =~ ^[23] ]]; then
          echo "✅ Dokploy webhook accepted (HTTP ${HTTP_STATUS})"
        else
          echo "::warning::Dokploy webhook returned HTTP ${HTTP_STATUS}"
        fi
```

### Webhook Payload
- **Method**: `POST`
- **URL**: Dokploy Compose service webhook URL (unique per service, found in Dokploy UI → Service → Webhook)
- **Body**: `{"repository":"...","sha":"...","ref":"..."}`
- **Response**: HTTP 200 on success; Dokploy initiates redeploy within ~10–60s

## Bootstrap Script Design

`scripts/bootstrap.sh` already exists and is correct. No changes needed.

| Property | Status |
|----------|--------|
| Idempotency | ✅ Safe to run multiple times; `mkdir -p` and `chown` are idempotent |
| Volume auto-creation | ✅ Creates volume via `docker volume create` if missing |
| Permission handling | ✅ Sets `TARGET_UID:TARGET_GID` (default 1000:1000) on volume roots |
| Dry-run support | ✅ `--dry-run` flag previews actions |

**Pre-deploy requirement**: Run `sudo ./scripts/bootstrap.sh` on the Dokploy VPS before the first Compose deploy.

## Traefik / Domain Configuration

### Label Mapping
The existing labels in `docker-compose.prod.yml` map directly to Dokploy's Traefik:

| Service | Host Rule | Entrypoint | Cert Resolver | Backend Port |
|---------|-----------|------------|---------------|--------------|
| code-server | `code.workspace.yoppai.dev` | `websecure` | `letsencrypt` | 8080 |
| opencode-server | `ai.workspace.yoppai.dev` | `websecure` | `letsencrypt` | 4096 |
| codenomad-server | `codenomad.workspace.yoppai.dev` | `websecure` | `letsencrypt` | 9898 |
| kasmvnc-workspace | `desktop.workspace.yoppai.dev` | `websecure` | `letsencrypt` | 6901 |

> `codenomad-server` and `kasmvnc-workspace` use `loadbalancer.server.scheme=https` because their backends serve HTTPS directly.

### Cloudflare Access Integration
- DNS A/AAAA records for the 4 subdomains point to the Dokploy VPS IP
- Cloudflare Access policies sit **in front of** Traefik (at the Cloudflare edge)
- No changes to Traefik labels or Dokploy config needed for Access
- Out of scope for this change (see proposal Out of Scope)

### HTTPS Certificate Handling
- `tls.certresolver=letsencrypt` on all routers
- Dokploy's built-in Traefik is assumed to have a `letsencrypt` resolver configured
- Certificates are provisioned automatically on first request

## Deployment Flow

### First-Time Setup Flow
1. Run `scripts/bootstrap.sh` on VPS to create external volumes with UID 1000
2. In Dokploy UI: Create Project → Create Compose service → Select **Raw source**
3. Paste contents of `docker-compose.prod.yml`
4. Registries → Add GHCR registry with PAT (`read:packages`)
5. Environment tab → Add all 8 environment variables
6. Save and Deploy
7. Verify: all 4 services show healthy; domains respond with TLS

### Normal Deploy Flow (Code Change → Deployed)
1. Developer pushes to `main` (or merges PR)
2. `build-images.yml` triggers on path-filtered changes
3. Jobs: `changes` → `build-*` → `validate` → `push-images` → `notify-dokploy`
4. `notify-dokploy` POSTs to Dokploy Compose webhook URL
5. Dokploy queues redeploy, pulls `latest` images from GHCR
6. Containers restart with new images; volumes persist
7. Health checks pass; deployment marked successful

### Rollback Flow
1. In Dokploy UI: Stop the Compose service (or click previous deployment)
2. Edit `docker-compose.prod.yml` in Dokploy UI: replace `:latest` with a known-good `sha-{7}` tag
3. Redeploy; containers start with previous image
4. Alternatively: `docker compose pull` + `docker compose up -d` manually on VPS
5. Data in `workspace_projects` and other volumes remains intact

## File Changes

| File | Action | Description |
|------|--------|-------------|
| `.github/workflows/build-images.yml` | Modify | Update `notify-dokploy` job: change secret name to `DOKPLOY_WEBHOOK_URL`, simplify payload, remove `DOKPLOY_WEBHOOK_SECRET` reference |
| `docker-compose.prod.yml` | Reference only | No changes; already Dokploy-compatible |
| `scripts/bootstrap.sh` | Reference only | No changes; already correct |
| `.env.example` | Reference only | No changes; serves as variable reference |

## Testing Strategy

| Layer | What to Test | Approach |
|-------|-------------|----------|
| Integration | Webhook POST succeeds | Trigger workflow on test branch; verify Dokploy receives 2xx |
| Integration | Registry test-pull | In Dokploy UI, click Test Registry after adding GHCR PAT |
| E2E | Full deploy chain | Push to main, verify redeploy completes within 60s, all services healthy |
| E2E | Volume persistence | Write a file to `workspace_projects`, redeploy, verify file still exists |

## Migration / Rollout

No migration required. This is a new Dokploy-side configuration connecting existing CI artifacts.

## Open Questions

- [ ] Confirm Dokploy's built-in Traefik has a `letsencrypt` cert resolver named exactly `letsencrypt` (vs `default` or another name).
- [ ] Verify the Dokploy Compose webhook URL format — some versions use a simple URL with token query param, others require headers.

---
*Design generated by sdd-design phase for change `dokploy-deployment`.*
