# Design: Self-Hosted Workspace MVP

## Technical Approach

Build a single `dev-base` ARM64 image with common tooling, then create service-specific overlays for `opencode`, CodeNomad, and KasmVNC. `code-server` uses the official pinned image directly. All containers run as UID 1000 to share volumes without permission fixes. Cloudflare Access guards every public route; Traefik terminates HTTPS. Secrets live in Dokploy env vars only.

## Architecture Decisions

### Decision: Base Image Strategy

| Option | Tradeoff | Decision |
|---|---|---|
| One shared `dev-base` image | Simpler builds, consistent toolchain, smaller total footprint | ✅ **Chosen** |
| Individual images per service | More flexibility, but duplicated tooling and version drift | Rejected — harder to maintain on ARM64 |

**Rationale**: A single base reduces build time on the A1 Flex and guarantees Node.js, Bun, pnpm, and Git versions are identical across opencode, CodeNomad, and KasmVNC.

### Decision: Volume Mount Model

| Volume | Shared By | Rationale |
|---|---|---|
| `workspace_projects` | All 4 services | Single source of truth for repositories |
| `workspace_profile` | opencode, code-server, KasmVNC | Shared `~/.config`, `~/.ssh`, OAuth tokens |
| `workspace_home` | KasmVNC only | Desktop session home; isolated to avoid cache pollution |
| `opencode_config` | opencode, CodeNomad (ro) | Global opencode config, agents, skills, MCP |
| `codenomad_config` | CodeNomad only | Session state and chat history |
| `code_server_config` | code-server only | VS Code: extensions and settings |
| `kasm_config` | KasmVNC only | VNC password and desktop settings |
| `toolchains` | CLI services | User-installed binaries (`~/.local`, `~/.bun`) |
| `package_caches` | Build/CLI containers | Optional npm/pnpm/bun caches |

**Rule**: Project data and tool state MUST NOT share the same volume.

### Decision: UID/GID Strategy

| Aspect | Choice | Rationale |
|---|---|---|
| UID/GID | 1000:1000 | Matches `coder` user in official code-server image; avoids `chown` at runtime |
| Implementation | Hard-coded in every Dockerfile `USER` directive | Guarantees consistency at image build time |
| Read-only mounts | `:ro` where appropriate | Prevents accidental cross-service state corruption |

### Decision: Secrets Model

| Layer | Storage | Examples |
|---|---|---|
| Service secrets | Dokploy env vars | `ANTHROPIC_API_KEY`, `CODE_SERVER_PASSWORD` |
| Interactive auth | `workspace_profile` volume | OAuth tokens, `~/.ssh`, `~/.gitconfig` |
| Image build | None | No `ARG` or `ENV` secrets in Dockerfiles |

### Decision: Routing Model

| Domain | Service | Internal Port | Auth Layers |
|---|---|---|---|
| `code.workspace.dev` | code-server | 8080 | Cloudflare Access → code-server password |
| `ai.workspace.dev` | opencode-server | 4096 | Cloudflare Access → basic auth |
| `codenomad.workspace.dev` | CodeNomad | 9899 | Cloudflare Access → username/password |
| `desktop.workspace.dev` | KasmVNC | 6901 | Cloudflare Access → VNC password |

Traefik terminates HTTPS; internal services speak plain HTTP. No ports published directly.

### Decision: Image Build Order

```
dev-base/Dockerfile
  → opencode/Dockerfile
  → codenomad/Dockerfile
kasmweb/core-ubuntu-jammy:1.16.0
  → kasmvnc/Dockerfile
codercom/code-server:4.97.2 (official, no build)
```

## Data Flow

```
Browser
  → Cloudflare Access (JWT)
  → Dokploy / Traefik (HTTPS termination)
  → Service container (HTTP)
  → Shared volume (workspace_projects / workspace_profile)
```

Containers communicate by service name on the internal `workspace-net` bridge. KasmVNC is the only service with a `deploy.resources.limits.memory` cap (4 GB).

## File Changes

| File | Action | Description |
|---|---|---|
| `docker-compose.yml` | Create | 4 services, 9 named external volumes, internal network |
| `dev-base/Dockerfile` | Create | Ubuntu Jammy ARM64 base with Node.js, Bun, pnpm, Git |
| `opencode/Dockerfile` | Create | Custom opencode server image |
| `codenomad/Dockerfile` | Create | CodeNomad with opencode CLI in PATH |
| `kasmvnc/Dockerfile` | Create | KasmVNC desktop with dev tools overlay |
| `.env.example` | Create | Dokploy env var template (placeholders only) |
| `scripts/smoke-test.sh` | Create | Post-deploy validation script |
| `scripts/bootstrap.sh` | Create | One-shot toolchain bootstrap into shared volumes |

## Interfaces / Contracts

**Environment variables** (injected by Dokploy at runtime):
- `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`
- `CODE_SERVER_PASSWORD`, `OPENCODE_SERVER_PASSWORD`
- `CODENOMAD_USERNAME`, `CODENOMAD_PASSWORD`
- `KASMVNC_PASSWORD`

**Ports** (internal only):
- `code-server`: 8080
- `opencode-server`: 4096
- `codenomad-server`: 9899
- `kasmvnc-workspace`: 6901

## Testing Strategy

| Layer | What | Approach |
|---|---|---|
| Build | ARM64 compatibility | `docker compose build` on `linux/arm64` host |
| Integration | Service startup | `docker compose up -d` + health checks |
| Integration | Volume sharing | Write from opencode, read from code-server |
| Integration | Secret isolation | `docker inspect` confirms no secrets in image env |
| E2E | Routing + auth | `curl` via Cloudflare Access wall before DNS cutover |

## Migration / Rollout

No migration required — greenfield project. Deploy volumes once as `external: true`, then deploy the Compose service. Rollback: redeploy previous Dokploy revision; external volumes preserve state.

## Open Questions

- [ ] Confirm CodeNomad `--http-port` flag and exact opencode CLI version pinning
- [ ] Validate KasmVNC `kasmweb/core-ubuntu-jammy:1.16.0` ARM64 digest on target host
- [ ] Decide if `package_caches` volume justifies the disk growth risk
