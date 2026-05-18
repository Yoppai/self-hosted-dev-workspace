# Exploration: Dokploy Deployment Strategies

## Current State

The project is at **post-apply, pre-deploy** stage. All 27 tasks are complete, all 10 fixes applied. The project has:

- **`docker-compose.yml`** (local dev) — builds from source, Traefik labels, named volumes, health checks
- **`docker-compose.prod.yml`** — references GHCR images (`ghcr.io/yoppai/self-hosted-dev-workspace/*:latest`), no `build:` sections
- **Full CI/CD pipeline** (`build-images.yml`) — self-hosted ARM64 runner builds → validates → pushes to GHCR → currently has a `notify-dokploy` job that POSTs to a webhook secret
- **PR validation**, **Renovate** dep management, **ARM64 validation**, **secret audit**, **smoke tests**, **bootstrap script**
- **9 named volumes** — 3 external (pre-created by bootstrap), 6 auto-created
- **Traefik labels** embedded in every service — domains, TLS certresolver, loadbalancer ports
- **Health checks** on every service

**What's NOT designed yet**: the specific Dokploy-side deployment configuration — how the Compose file reaches Dokploy, how volumes are provisioned, how env vars are injected, how the webhook triggers a redeploy, how GHCR credentials are configured.

---

## 1. Deployment Methods Matrix

### 1.1 Dokploy Docker Compose (Raw Source)

| Aspect | Detail |
|--------|--------|
| **How it works** | Paste YAML content of `docker-compose.prod.yml` into Dokploy's RAW/YAML editor for a Compose service. Dokploy stores the content internally. |
| **Source updates** | Manual: re-paste when Compose changes. Or use API/MCP to update the compose content. |
| **Image pulling** | Dokploy pulls from configured registries (GHCR). Must register GHCR as a registry in Dokploy with proper credentials. |
| **Volume handling** | Named volumes (`external: true`) must pre-exist or be auto-created. Bind mounts (`../files/`) survive redeploy — named volumes survive redeploy. |
| **Env vars** | Set in Dokploy Environment tab → written to `.env` file → referenced via `${VAR}` in compose. |
| **Deploy trigger** | Click "Deploy" in UI, or POST to its webhook URL, or call API `compose.deploy`. |
| **Traefik** | Traefik labels in compose YAML are honored — Dokploy auto-creates/attaches to its Traefik network. |

**Pros:**
- No git clone on deploy — repo directory clearing issue does NOT apply
- Full control over compose file content
- Works perfectly with CI-pushed GHCR images (pull-only)
- Named volumes survive redeploy without risk of git-cleared repo dirs
- Can use MCP/API to update compose content programmatically
- Environment tab is clean UI for all 8+ env vars

**Cons:**
- Compose YAML changes must be synced manually (or via API) — not automatic from git
- Initial setup requires UI steps (paste YAML, register GHCR, create volumes)
- No version history of compose content in Dokploy

**Complexity: Low-Medium** — one-time setup, then deploy via webhook

---

### 1.2 Dokploy Docker Compose (Git Source)

| Aspect | Detail |
|--------|--------|
| **How it works** | Connect GitHub repo as source. Dokploy clones the repo on every deploy and uses `docker-compose.prod.yml`. |
| **Source updates** | Automatic: push to repo → webhook → Dokploy clones and deploys. |
| **Image pulling** | Same — pulls from GHCR with registered credentials. |
| **Volume handling** | **WARNING**: Dokploy performs `git clone` on every deploy, which clears the repository directory. Relative path bind mounts (`./`) are lost. Named volumes still survive. |
| **Env vars** | Same as Raw but you can also commit a `.env.production` file. |
| **Deploy trigger** | Auto-deploy toggle on GitHub push, or webhook, or manual. |

**Pros:**
- Compose changes auto-deploy on `git push`
- Git-tracked history of Compose changes
- One less manual step

**Cons:**
- **CRITICAL RISK**: Dokploy docs explicitly warn that `git clone` on each deploy clears the repo directory. If you need files from the repo inside a container via relative bind mounts, they disappear after deployment #2. For this project, all volumes are Docker named volumes — so this risk is lower, but it means we cannot use repo-relative bind mounts in the future.
- Slower deploys (git clone every time)
- Branch matching required (default branch vs deploy branch)
- For a single-user personal workspace, auto-deploy on every push may be excessive

**Complexity: Low** — most automation, but introduces branch-matching risk

---

### 1.3 Dokploy Application per Service (4 separate apps)

| Aspect | Detail |
|--------|--------|
| **How it works** | Create 4 Dokploy Applications, each with Build Type = "Docker Image" pointing to individual GHCR images. |
| **Source** | Docker Image type — just provide the image tag. |
| **Volume handling** | Application-level volume management (bind mounts, named volumes via Advanced → Volumes). |
| **Env vars** | Per-application environment tab. |
| **Traefik** | Domain management through Application's Domains tab. |
| **Deploy trigger** | Per-application webhooks or API calls. |

**Pros:**
- Independent lifecycle per service (stop/start/deploy individually)
- Each service has its own deployment history and rollback
- Simpler UI per service
- No Compose file to manage

**Cons:**
- **No internal Docker network** — services cannot resolve each other by hostname (no `depends_on`, no `opencode-server` → `code-server` communication)
- Each service is isolated — cross-service volume sharing works but container DNS does not
- CodeNomad depends on opencode-server (needs network connectivity) — this would require Traefik routing between apps
- More Dokploy entities to manage (4x the config)
- No `depends_on` — startup ordering must be handled manually
- Resource limits per app are separate configs
- Health checks per app are separate configs
- **NOT RECOMMENDED for this project** — cross-service dependency is a hard requirement

**Complexity: Medium** — more entities, more config, broken networking

---

### 1.4 CI-Only Strategy (Dokploy bypass)

| Aspect | Detail |
|--------|--------|
| **How it works** | Don't use Dokploy for deployment at all — SSH into VPS and `docker compose pull && docker compose up -d` directly. |
| **Automation** | GitHub Actions SSH into VPS and run commands. |
| **Pros** | Maximum control, no Dokploy deployment complexity. |
| **Cons** | Loses ALL Dokploy features: no Traefik configuration, no env var management, no monitoring, no rollback UI, no backup integration, no webhook management. Requires SSH key management in CI. |
| **Complexity** | High — reinventing the wheel |

**NOT RECOMMENDED** — defeats the purpose of using Dokploy.

---

### 1.5 Dokploy Compose Template

Dokploy has a `compose_templates` tool and `compose_deployTemplate` endpoint. This uses pre-baked compose templates. Limited flexibility for custom multi-service stacks like this workspace — designed more for quick-start apps.

**Complexity: Low** setup, but **High** customization effort. NOT RECOMMENDED for a custom 4-service stack.

---

### 1.6 Dokploy CLI / MCP Server

| Aspect | Detail |
|--------|--------|
| **How it works** | Use `dokploy app create` or `dokploy compose create` from CLI or the MCP server (`@sattva/dokploy-mcp`) with 449 tools. |
| **Key MCP tools** | `compose_create`, `compose_update`, `compose_deploy`, `compose_one`, `application_saveBuildType`, `application_saveEnvironment`, `registry_create`, `domain_create`, `mounts_create`, `deployment_all` |
| **Pros** | Fully scriptable, no UI needed, can automate initial setup |
| **Cons** | Initial setup still complex, MCP server must be configured, CLI is less feature-rich than UI |
| **Complexity** | Medium — great for automation, but requires MCP setup |

---

## 2. CI/CD Integration Patterns

### 2.1 Current Pipeline (build-images.yml)

```
changes → build-dev-base → build-opencode → validate → push-images → notify-dokploy
                          ├─ build-codenomad ┘
         └─ build-kasmvnc ┘
```

The current `notify-dokploy` job POSTs to a generic webhook URL with a JSON payload:
```json
{"event":"deploy","repository":"${{ github.repository }}","sha":"${{ github.sha }}","ref":"${{ github.ref }}"}
```

**Problem**: This webhook isn't tied to Dokploy's actual Compose service webhook — it's a generic POST. For this to work, the webhook URL must be the Dokploy Compose service's webhook URL, and the payload must match what Dokploy expects (or use Dokploy's API directly).

### 2.2 Recommended CI/CD Pattern

```
Option A: GitHub Actions → Build & Push to GHCR → POST to Dokploy webhook → Dokploy pulls images & redeploys
Option B: GitHub Actions → Build & Push to GHCR → POST to Dokploy API (compose.deploy) → Dokploy pulls & redeploys
Option C: GitHub Actions → Build → Dokploy builds directly (not recommended — slow, no CI validation)
```

**Option A (Webhook)** is simplest — Dokploy generates a webhook URL per Compose service. POST to it triggers a deploy. No auth needed on the webhook itself (Dokploy handles this).

**Option B (API)** is more robust — uses `x-api-key` auth, can specify exact application/service ID, more reliable than webhook.

### 2.3 ARM64 Build Strategies

| Strategy | Where builds run | Pros | Cons |
|----------|-----------------|------|------|
| **Self-hosted ARM64 runner** (current design) | Oracle VPS | Native ARM64, fastest builds, leverages VPS resources | Runner uses VPS CPU/RAM (noisy neighbor), needs systemd auto-restart |
| **Cross-compile on GitHub runners** | `ubuntu-latest` + QEMU | No self-hosted runner needed | QEMU emulation is 5-10x slower, unreliable for complex builds |
| **Dokploy builds** | Dokploy's build server | No CI pipeline needed | Slow, no validation before deploy, no CI gating |
| **Multi-arch buildx** | Self-hosted + manifest | Single manifest for ARM64/AMD64 | More complex, not needed for single-arch target |

**Recommendation**: **Keep self-hosted ARM64 runner** — it's already designed and scripted (`scripts/setup-runner.sh`). The Oracle A1 Flex has 4 OCPU and 24 GB RAM — plenty for both the runner and the running services.

---

## 3. Dokploy API Capabilities Relevant to This Stack

### For Initial Setup:

| Operation | MCP Tool / API | Relevance |
|-----------|---------------|-----------|
| Register GHCR registry | `registry_create` | **CRITICAL** — lets Dokploy pull from GHCR |
| Create Compose service | `compose_create` | Core — create the multi-service deployment |
| Set environment variables | `compose_saveEnvironment` or Environment tab | All 8+ env vars (AI keys, passwords) |
| Create named volumes | Dokploy handles mount points; volumes from compose YAML are auto-created or must pre-exist | `workspace_projects`, `workspace_profile`, `toolchains` are `external: true` |
| Add domains/Traefik | `domain_create` OR rely on Traefik labels in compose YAML | Traefik labels in the Compose YAML are sufficient |
| Deploy first time | `compose_deploy` | Initial deployment |
| Get webhook URL | `compose_refreshToken` or from UI | For CI/CD trigger |

### For Ongoing Operations:

| Operation | MCP Tool / API | Relevance |
|-----------|---------------|-----------|
| Trigger redeploy | `compose_deploy` or Webhook POST | After CI pushes new images |
| Check deployment status | `deployment_allByCompose` | Monitor deploy progress |
| Read logs | Dashboard UI (WebSocket only) | Debug failures |
| Stop/Start | `compose_stop` / `compose_start` | Maintenance |
| Update environment | `compose_saveEnvironment` | Rotate API keys |
| Configure volume backups | `volumeBackups_create` | Backup workspace data |
| Setup notifications | `notification_createTelegram` etc. | Deploy notifications |
| Scheduled tasks | `schedule_create` | Nightly volume backups |

---

## 4. ARM64 Considerations

### Current State: Fully Addressed

- All images are built for `linux/arm64` natively on the self-hosted runner
- `docker-compose.prod.yml` uses `ghcr.io/yoppai/self-hosted-dev-workspace/*` images
- `scripts/arm64-validate.sh` verifies architecture post-build
- Upstream images (code-server, kasmweb) already support ARM64

### Dokploy-Specific Concerns

- **Dokploy itself** runs on ARM64 (Oracle A1 Flex is ARM64) — confirmed working
- **GHCR must be registered** in Dokploy as a registry with credentials
- **`docker compose pull`** (what Dokploy does internally) works identically on ARM64 — no special config needed
- **Image tagging** must be consistent between CI push and Compose file reference

---

## 5. Deployment Strategies Comparison

| Criteria | Strategy A: Raw Compose + Webhook | Strategy B: Git Compose + Auto-Deploy | Strategy C: 4 Apps + Docker Image |
|----------|-----------------------------------|---------------------------------------|------------------------------------|
| **Setup complexity** | Medium (paste YAML, register GHCR, set env vars) | Low (connect GitHub repo) | Medium (4 apps × volumes × env × domains) |
| **Ongoing effort** | Low (webhook triggers pull) | Very Low (auto-deploy on push) | Medium (4 webhooks or 4 API calls) |
| **Reliability** | High — no git clone on deploy | Medium — git clone risk on deploy | Low — no cross-service networking |
| **Rollback** | Dokploy Compose rollback | Dokploy Compose rollback | Per-service rollback (better) |
| **Volume safety** | ✅ Named volumes survive | ⚠️ Git clone clears repo dir | ✅ Named volumes managed per app |
| **Network** | ✅ Internal bridge works | ✅ Internal bridge works | ❌ No cross-service DNS |
| **CI integration** | Webhook POST (exists already) | GitHub auto-deploy | 4x API calls or webhooks |
| **Env var management** | ✅ Dokploy Environment tab | ✅ Dokploy Environment tab | ✅ Per-app Environment tab |
| **ARM64** | ✅ Same for all | ✅ Same for all | ✅ Same for all |
| **Security** | ✅ GHCR registry auth | ✅ GHCR registry auth | ✅ Registry auth per app |
| **Single-user suitability** | ✅ Excellent | ✅ Excellent but overkill | ❌ Not designed for multi-service |

### Winner: **Strategy A — Docker Compose (Raw) + Webhook**

This project is a single-user personal workspace with a multi-service Compose stack. Strategy A provides:
- Full cross-service networking via `workspace-net`
- Safe volume handling (no git clone clearing)
- Existing CI webhook notification that maps directly to Dokploy's webhook
- Clean env var management in one place
- Single deploy trigger for all 4 services
- Dokploy handles Traefik via existing labels in the YAML

---

## 6. Detailed Pipeline Design

### Recommended: GitHub Actions → GHCR → Dokploy Webhook

```yaml
# Changes to build-images.yml notify-dokploy job:
notify-dokploy:
    name: Trigger Dokploy Deploy
    runs-on: self-hosted
    needs: push-images
    if: success()
    steps:
      - name: Trigger Dokploy Compose redeploy
        env:
          DOKPLOY_WEBHOOK_URL: ${{ secrets.DOKPLOY_WEBHOOK_URL }}
        run: |
          curl -s -X POST "$DOKPLOY_WEBHOOK_URL" \
            -H "Content-Type: application/json" \
            -d '{"event":"deploy"}'
```

The webhook URL is obtained from Dokploy's Compose service → Deployments → Webhook URL.

### Alternative: GitHub Actions → GHCR → Dokploy API

```yaml
notify-dokploy:
    ...
    steps:
      - name: Trigger Dokploy deploy via API
        env:
          DOKPLOY_URL: ${{ secrets.DOKPLOY_URL }}
          DOKPLOY_API_KEY: ${{ secrets.DOKPLOY_API_KEY }}
          COMPOSE_ID: ${{ secrets.DOKPLOY_COMPOSE_ID }}
        run: |
          curl -s -X POST "${DOKPLOY_URL}/api/compose.deploy" \
            -H "Content-Type: application/json" \
            -H "x-api-key: ${DOKPLOY_API_KEY}" \
            -d "{\"composeId\":\"${COMPOSE_ID}\"}"
```

### Manual CI Build → Push → Deploy Flow

1. Developer pushes to `main`
2. Self-hosted runner builds images (path-filtered, dependency-ordered)
3. ARM64 validation runs on each image
4. Smoke tests run (`--build-only` mode)
5. Images pushed to GHCR with `latest`, `sha-{7}`, and version tags
6. Dokploy webhook/API triggered
7. Dokploy pulls new images and redeploys Compose stack
8. Health checks verify all services are healthy

---

## 7. Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| **Dokploy git clone clears repo** on Git source deploy | Medium (only Strategy B) | High — volumes lose bind-mount files | Use Strategy A (Raw source) — no git clone |
| **GHCR registry auth fails** | Low | High — can't pull images | Test registry connection in Dokploy, regenerate token before expiry |
| **Webhook URL changes** | Low | Medium — CI can't trigger deploy | Dokploy generates stable webhook URLs; store in GitHub secrets |
| **Named volumes not pre-created** for `external: true` | Medium | High — containers fail to start | Run `scripts/bootstrap.sh` on VPS before first deploy |
| **Dokploy Traefik labels conflict** with Dokploy's own Traefik | Low | Medium — broken routing | Compose YAML labels are honored as-is; Dokploy attaches to its internal Traefik network |
| **Self-hosted runner offline** | Low | Medium — no new builds | systemd auto-restart, weekly schedule as safety net |
| **Dokploy version upgrade breaks API** | Low | Medium — CI integration breaks | Pin CI to use API endpoints, not implementation details |
| **Env var rotation** requires Dokploy UI update | Low | Low — rare operation | Document process; can use MCP `compose_saveEnvironment` |
| **Volume backup not configured** | Medium | High — data loss risk | Configure `volumeBackups_create` post-deploy |

---

## 8. Volume Strategy vs Dokploy

Current volume design uses **Docker named volumes** — which is exactly what Dokploy recommends for persistence:

| Volume | Type | Dokploy S3 Backup Support | Notes |
|--------|------|--------------------------|-------|
| `workspace_projects` | `external: true` | ✅ | Pre-created by bootstrap.sh, UID 1000 |
| `workspace_profile` | `external: true` | ✅ | Pre-created by bootstrap.sh |
| `toolchains` | `external: true` | ✅ | Pre-created by bootstrap.sh |
| `workspace_home` | Auto-created | ✅ | Dokploy creates on first deploy |
| `opencode_config` | Auto-created | ✅ | Dokploy creates on first deploy |
| `codenomad_config` | Auto-created | ✅ | Dokploy creates on first deploy |
| `code_server_config` | Auto-created | ✅ | Dokploy creates on first deploy |
| `kasm_config` | Auto-created | ✅ | Dokploy creates on first deploy |
| `package_caches` | Auto-created | ✅ | Dokploy creates on first deploy |

**Important**: `external: true` volumes (workspace_projects, workspace_profile, toolchains) must be created *before* Dokploy's first deploy — either via `scripts/bootstrap.sh` or `docker volume create`. Dokploy won't create them because they're marked external.

---

## 9. Env Var Strategy vs Dokploy

Current design uses `${VAR_NAME:?err}` syntax in docker-compose.yml — this is fully compatible with Dokploy's Environment tab.

Dokploy writes env vars to a `.env` file in the deploy directory, and the Compose file uses `env_file` or `${VAR}` references.

**For this project**: Set all 8 env vars in Dokploy's Environment tab:
- `ANTHROPIC_API_KEY` (AI provider)
- `OPENAI_API_KEY` (AI provider)
- `CODE_SERVER_PASSWORD` (auth)
- `OPENCODE_SERVER_USERNAME` (auth)
- `OPENCODE_SERVER_PASSWORD` (auth)
- `CODENOMAD_SERVER_USERNAME` (auth)
- `CODENOMAD_SERVER_PASSWORD` (auth)
- `KASMVNC_PASSWORD` (auth)

No `.env` file in the Compose YAML is needed — `${VAR:?err}` pulls from Dokploy's `.env`.

---

## 10. Traefik/Domain Strategy vs Dokploy

Current Compose YAML has all Traefik labels embedded per service. Dokploy honors these labels when deploying a Compose service — the containers are attached to Dokploy's Traefik network, and labels are read by Traefik for routing.

**Alternative**: Let Dokploy manage domains through its Domains tab (per service in Compose). This would mean *removing* Traefik labels from the YAML and configuring domains in Dokploy's UI. 

**Recommendation**: **Keep Traefik labels in the YAML** — it keeps domain configuration in version control, allows easy per-service config, and Dokploy supports this approach for Compose services.

---

## 11. Next Steps (for Proposal Phase)

### Immediate Actions (Pre-Deploy)

1. **Decide source type**: Raw YAML vs Git source — recommend **Raw** for safety
2. **Register GHCR registry** in Dokploy with `write:packages` token
3. **Run bootstrap.sh** on VPS to create `external: true` volumes
4. **Create Compose service** in Dokploy with `docker-compose.prod.yml` content
5. **Set environment variables** in Dokploy Environment tab (all 8)
6. **Get Compose webhook URL** from Dokploy → Deployments tab
7. **Update `build-images.yml`** `notify-dokploy` job to POST to the correct webhook URL
8. **Add `DOKPLOY_WEBHOOK_URL`** secret to GitHub repository
9. **First deployment**: Click "Deploy" in Dokploy UI (or via API)

### Post-Deploy

10. **Configure volume backups** via `volumeBackups_create` to S3
11. **Configure notification** (Telegram/Slack) for deploy status
12. **Test webhook-triggered deploy**: push a change to GHCR images
13. **Verify health checks** in Dokploy monitoring
14. **Set up scheduled tasks** for periodic volume cleanup

### Ready for Proposal

**Yes** — this exploration has sufficient information for the proposal phase. The key decisions needed:

1. **Compose source type**: Raw vs Git (recommend: Raw)
2. **Deploy trigger**: Webhook vs API (recommend: Webhook — simpler, already partially designed)
3. **Domain management**: Labels in YAML vs Dokploy UI (recommend: Labels in YAML)
4. **GHCR registry setup**: Dokploy's built-in registry integration (recommend: Register GHCR with `write:packages` token)

---

## Affected Areas

- `.github/workflows/build-images.yml` — `notify-dokploy` job needs webhook URL updated
- `docker-compose.prod.yml` — may need minor adjustments (env vs env_file)
- `scripts/bootstrap.sh` — already correct for pre-Dokploy setup
- GitHub secrets — add `DOKPLOY_WEBHOOK_URL` or `DOKPLOY_API_KEY` + `DOKPLOY_COMPOSE_ID`

## Approaches Compared

1. **Docker Compose + Raw Source + Webhook** (RECOMMENDED)
   - Pros: No git clone risk, existing CI webhook maps cleanly, full control, safe volumes
   - Cons: Manual compose sync, initial UI setup
   - Effort: Low (one-time setup) + Low (ongoing automation)

2. **Docker Compose + Git Source + Auto-Deploy**
   - Pros: Git-tracked compose, auto-deploy on push
   - Cons: Git clone clears repo dirs, branch-matching issues
   - Effort: Very Low (near zero after setup)

3. **4 Separate Dokploy Applications**
   - Pros: Independent lifecycle, per-service rollbacks
   - Cons: No cross-service networking — breaks CodeNomad→opencode dependency
   - Effort: Medium (4x configuration)

## Recommendation

**Strategy A**: Deploy as a single Dokploy Docker Compose service using **Raw source** with `docker-compose.prod.yml`, register **GHCR as a registry** for image pull auth, set **env vars in Dokploy Environment tab**, and trigger redeploys via the **Dokploy Compose webhook URL** from GitHub Actions.

## Risks

- External named volumes (`workspace_projects`, `workspace_profile`, `toolchains`) must pre-exist — bootstrap.sh must run before first deploy
- GHCR `write:packages` token needs periodic renewal
- Dokploy version upgrades may affect API/webhook behavior
- Self-hosted runner offline blocks the build→push→deploy pipeline

## Ready for Proposal

Yes. The exploration provides clear direction. The proposal phase should produce a concrete deployment plan with step-by-step Dokploy setup instructions, specific webhook URL configuration, and CI pipeline modifications.
