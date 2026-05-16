## Exploration: Self-Hosted Workspace MVP

### Current State

Greenfield project. No source code exists yet. The `docs/prd-self-hosted-workspace.md` defines the full vision. `openspec/config.yaml` is pre-configured with rules for this change. The target infrastructure is an Oracle Cloud A1 Flex VPS (4 OCPU, 24 GB RAM, 200 GB disk, ARM64, Ubuntu) managed by Dokploy.

### Image Compatibility Checks

| Service | ARM64 Official Image? | Notes |
|---|---|---|
| `code-server` | ✅ `codercom/code-server` | Official image supports `linux/arm64` since v4.x. UID 1000 by default. |
| `opencode` | ⚠️ No official image | Must build custom image from base. CLI binary compiles to ARM64. |
| CodeNomad | ⚠️ No official image | Must build custom image. Runs on Node.js/Bun + opencode CLI. ARM64 build supported via `bun run build:linux-arm64`. |
| KasmVNC | ✅ `kasmweb/core-ubuntu-jammy` | Official images support ARM64. Desktop workspace images also available. |

### Affected Areas

- `docker-compose.yml` — **(to create)** Main Compose file with all 4 services, networks, volumes
- `dev-base/Dockerfile` — **(to create)** Base image with Git, Node.js, Bun, pnpm, common dev tools
- `opencode/Dockerfile` — **(to create)** Custom image for opencode server mode
- `codenomad/Dockerfile` — **(to create)** Custom image for CodeNomad with opencode in PATH
- `kasmvnc/Dockerfile` — **(to create)** Custom KasmVNC workspace with dev tools overlay
- `.env.example` — **(to create)** Environment variable template for Dokploy secrets
- `scripts/smoke-test.sh` — **(to create)** Post-deploy validation script
- `scripts/bootstrap.sh` — **(to create)** One-shot user toolchain bootstrap
- `docs/prd-self-hosted-workspace.md` — Existing PRD (source of truth)
- `openspec/config.yaml` — Project config (already set up for this change)
- `openspec/changes/self-hosted-workspace-mvp/` — Active change folder

### Approach

#### A. Image Strategy

**Recommendation**: Single base image + service-specific overlays.

1. **`dev-base`** — Ubuntu Jammy ARM64 base with:
   - Git, curl, wget, ca-certificates, sudo
   - Node.js (LTS via nodesource)
   - Bun (official install script)
   - pnpm (via npm)
   - Python3, build-essential, gcc
   - Common shells (bash, zsh)
   - UID 1000 (coder) with passwordless sudo
   - Standard PATH: `~/.local/bin:~/.bun/bin:~/.npm-global/bin`

2. **`code-server`** — Can use the **official image** directly (`codercom/code-server:latest`) with volume mounts. No custom image needed for MVP unless we want to pre-install extensions.

3. **`opencode-server`** — Custom image from `dev-base`:
   - Install opencode CLI binary (`linux/arm64`)
   - Entrypoint: `opencode start --port 4096 --host 0.0.0.0`
   - Config + skills + agents persisted via `workspace_profile` volume

4. **`codenomad-server`** — Custom image from `dev-base`:
   - Install opencode CLI in PATH (same binary as above, or shared volume)
   - Install CodeNomad (npm/pnpm global or bun)
   - Entrypoint: `codenomad --https=false --http=true --http-port 9899 --workspace-root /workspace/projects`
   - Auth: `--username` / `--password` from Dokploy env vars (do NOT use `--dangerously-skip-auth` since Cloudflare Access is defense-in-depth, not the sole auth)

5. **`kasmvnc-workspace`** — Custom image from `kasmweb/core-ubuntu-jammy:1.16.0` (or latest stable ARM64):
   - Install dev tools (Node.js, Bun, pnpm, Git, opencode CLI, editor CLIs)
   - Mount `workspace_projects` for file access
   - VNC password from env var
   - Non-root user matching UID 1000

#### B. Compose Structure

```yaml
version: "3.9"

services:
  code-server:
    image: codercom/code-server:4.97.2  # pinned
    platform: linux/arm64
    container_name: workspace-code-server
    environment:
      - PASSWORD=${CODE_SERVER_PASSWORD}
      - DOCKER_USER=coder
    volumes:
      - workspace_projects:/home/coder/project
      - code_server_config:/home/coder/.config
      - workspace_profile:/home/coder/.local:ro  # read-only for global tools
    networks:
      - workspace-net
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3

  opencode-server:
    build:
      context: ./opencode
      dockerfile: Dockerfile
    platform: linux/arm64
    container_name: workspace-opencode
    environment:
      - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
      - OPENAI_API_KEY=${OPENAI_API_KEY}
      - OPENCODE_SERVER_PASSWORD=${OPENCODE_SERVER_PASSWORD}
    volumes:
      - workspace_projects:/workspace/projects
      - opencode_config:/home/coder/.config/opencode
      - workspace_profile:/home/coder/.config  # shared config (gentle-ai, agents, MCP)
      - toolchains:/home/coder/.local
    networks:
      - workspace-net
    restart: unless-stopped

  codenomad-server:
    build:
      context: ./codenomad
      dockerfile: Dockerfile
    platform: linux/arm64
    container_name: workspace-codenomad
    environment:
      - CODENOMAD_USERNAME=${CODENOMAD_USERNAME}
      - CODENOMAD_PASSWORD=${CODENOMAD_PASSWORD}
      - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
      - OPENAI_API_KEY=${OPENAI_API_KEY}
    volumes:
      - workspace_projects:/workspace/projects
      - opencode_config:/home/coder/.config/opencode:ro  # read access to opencode config
      - codenomad_config:/home/coder/.config/codenomad
      - workspace_profile:/home/coder/.config
    networks:
      - workspace-net
    restart: unless-stopped
    depends_on:
      - opencode-server

  kasmvnc-workspace:
    build:
      context: ./kasmvnc
      dockerfile: Dockerfile
    platform: linux/arm64
    container_name: workspace-kasmvnc
    environment:
      - VNC_PW=${KASMVNC_PASSWORD}
      - TZ=UTC
    volumes:
      - workspace_projects:/home/coder/projects
      - workspace_home:/home/coder
      - kasm_config:/home/coder/.vnc
    networks:
      - workspace-net
    restart: unless-stopped
    shm_size: "2gb"
    deploy:
      resources:
        limits:
          memory: 4g

volumes:
  workspace_projects:
    external: true  # created once, shared across redeploys
  workspace_profile:
    external: true
  workspace_home:
    external: true
  opencode_config:
    external: true
  codenomad_config:
    external: true
  code_server_config:
    external: true
  kasm_config:
    external: true
  toolchains:
    external: true
  package_caches:
    external: true

networks:
  workspace-net:
    driver: bridge
    internal: false  # needed for Traefik routing
```

#### C. Volume Ownership Strategy

**Critical decision**: All containers MUST use the same UID:GID (1000:1000) for shared volume access.

| Container | Default UID | Action needed |
|---|---|---|
| code-server | 1000 (coder) | ✅ Match — no change needed |
| opencode-server | 1000 (custom) | ✅ Match from base image |
| CodeNomad | 1000 (custom) | ✅ Match from base image |
| KasmVNC | 1000 (kasm-user) | Verify; may need `--user` flag or `USER` directive |

- `workspace_profile` must mount with UID 1000 across all consumers.
- Containers that need read-only access to `workspace_profile` (e.g., code-server reading global skills but not writing them) SHOULD mount it `:ro`.
- DO NOT run `chown` in entrypoints — set the correct UID at image build time.

#### D. Secrets Boundaries

| Secret | Source | Exposed to |
|---|---|---|
| `ANTHROPIC_API_KEY` | Dokploy env var | opencode-server, CodeNomad |
| `OPENAI_API_KEY` | Dokploy env var | opencode-server, CodeNomad |
| `CODE_SERVER_PASSWORD` | Dokploy env var | code-server |
| `OPENCODE_SERVER_PASSWORD` | Dokploy env var | opencode-server (basic auth) |
| `CODENOMAD_USERNAME` / `CODENOMAD_PASSWORD` | Dokploy env var | CodeNomad |
| `KASMVNC_PASSWORD` | Dokploy env var | KasmVNC |
| SSH keys (`~/.ssh/*`) | `workspace_profile` volume | Containers that mount workspace_profile (opencode, code-server, KasmVNC) |
| OAuth tokens | `workspace_profile` volume | opencode (gentle-ai auth), toolchain configs |

**Rules**:
- API keys → Dokploy secrets/env vars ONLY. Never in Dockerfile, never committed.
- SSH keys → workspace_profile volume. Generate once, persist across redeploys.
- OAuth tokens → workspace_profile volume. Generated on first login, survive redeploy.
- No secrets in `docker-compose.yml` — use `${VARIABLE}` references filled by Dokploy.
- The `.env.example` file MUST be a template with placeholder values, never real keys.

#### E. Dokploy Routing Notes

| Domain | Target Service | Internal Port |
|---|---|---|
| `code.workspace.dev` | `code-server` | `8080` |
| `ai.workspace.dev` | `opencode-server` | `4096` |
| `codenomad.workspace.dev` | `codenomad-server` | `9899` (HTTP) |
| `desktop.workspace.dev` | `kasmvnc-workspace` | `6901` |

- All routing via Dokploy/Traefik with HTTPS termination.
- Cloudflare Access sits in front of each domain, providing JWTAuth before traffic reaches Traefik.
- Internal auth per app is BACKUP — Cloudflare Access is the primary gate.
- CodeNomad uses HTTP port 9899 internally (no TLS inside compose network); Traefik handles HTTPS termination.
- opencode-server uses port 4096 (HTTP); Traefik terminates HTTPS.

#### F. Validation / Smoke Tests

**Post-deploy checks** (implement in `scripts/smoke-test.sh`):

| # | Check | What to verify |
|---|---|---|
| 1 | ARM64 image build | `docker compose build` succeeds for `linux/arm64` |
| 2 | All containers start | `docker compose up -d` → all show `healthy` or `Up` |
| 3 | code-server accessible | `curl -s -o /dev/null -w "%{http_code}" http://localhost:8080` → 200 or 302 |
| 4 | opencode server health | `curl -s http://localhost:4096/health` → 200 |
| 5 | CodeNomad UI | `curl -s -o /dev/null -w "%{http_code}" http://localhost:9899` → 200 |
| 6 | KasmVNC UI | `curl -s -k https://localhost:6901` → 200 (self-signed cert) |
| 7 | Volume persistence | Write file from one container, read from another on same volume |
| 8 | Secret isolation | `docker inspect` container → no secrets in env (Dokploy injects at runtime) |
| 9 | Workspace profile shared | Verify `~/.config/gentle-ai` or similar is visible across opencode + code-server |
| 10 | Restart survival | `docker compose restart` → files, configs, and sessions intact |

**Manual acceptance checklist** (from PRD):
- [ ] Cloudflare Access on every public route
- [ ] HTTPS via Dokploy/Traefik
- [ ] Internal auth per app enabled
- [ ] `workspace_projects` read/write from all dev tools
- [ ] Restart does not delete extensions, skills, MCP config, or user settings
- [ ] Redeploy does not delete project files
- [ ] All images confirmed ARM64
- [ ] No secrets in repo or embedded in images

### Files to Create

```
my-workspace/
├── docker-compose.yml              # Main Compose file — all services, volumes, networks
├── .env.example                    # Template for Dokploy env vars (placeholders only)
├── dev-base/
│   └── Dockerfile                  # Shared base dev image (Node.js, Bun, pnpm, Git)
├── opencode/
│   └── Dockerfile                  # opencode server image
├── codenomad/
│   └── Dockerfile                  # CodeNomad server image with opencode in PATH
├── kasmvnc/
│   └── Dockerfile                  # KasmVNC workspace image with dev tooling
├── scripts/
│   ├── bootstrap.sh                # One-shot: install user toolchains into shared volumes
│   └── smoke-test.sh               # Post-deploy validation
└── openspec/
    └── changes/
        └── self-hosted-workspace-mvp/
            ├── exploration.md       # This file
            ├── proposal.md          # (next phase)
            ├── specs/               # (next phases)
            ├── design.md
            └── tasks.md
```

### Key Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| **UID mismatch on shared volumes** | Medium | High — write failures across containers | Standardize 1000:1000 across all images; validate in smoke test #7 |
| **CodeNomad opencode coupling** | Medium | Medium — version incompatibility | Pin both versions in Dockerfile; test together in CI |
| **KasmVNC resource usage** | High | Medium — 24 GB RAM shared with other services | Set `deploy.resources.limits.memory: 4g`; monitor during MVP |
| **ARM64 image not available for opencode** | Low | High — blocks the service | Build from source; opencode CLI compiles for ARM64 |
| **Volume sprawl (9 volumes)** | Medium | Low — operational complexity | Document each volume's purpose and consumers in Compose comments |
| **Cloudflare Access misconfig** | Low | Critical — public exposure | Test with curl before pointing real DNS; validate auth wall on every route |

### Ready for Proposal

**Yes.** The PRD is comprehensive and all key technical decisions have clear options. The exploration reveals:

1. **CodeNomar + opencode coupling** needs explicit version pinning in the proposal.
2. **UID strategy** must be decided and documented early — it affects ALL Dockerfiles.
3. **Volume count (9)** is manageable but needs clear documentation to avoid confusion during maintenance.
4. **Image build order** matters: `dev-base` must be built first, then `opencode-server`, then `codenomad-server`.

The orchestrator should proceed to `sdd-propose` to define scope, approach, and rollback plan.
