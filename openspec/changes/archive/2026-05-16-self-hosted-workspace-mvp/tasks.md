# Tasks: Self-Hosted Workspace MVP

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | ~400–450 |
| 400-line budget risk | Medium |
| Chained PRs recommended | Yes |
| Suggested split | PR 1 (foundation) → PR 2 (core services) → PR 3 (desktop + verify) |
| Delivery strategy | auto-chain |
| Chain strategy | stacked-to-main |

Decision needed before apply: No
Chained PRs recommended: Yes
Chain strategy: stacked-to-main
400-line budget risk: Medium

### Suggested Work Units

| Unit | Goal | Likely PR | Notes |
|------|------|-----------|-------|
| 1 | Foundation image + env + bootstrap | PR 1 | base=main; dev-base must build first |
| 2 | Core services + Compose wiring | PR 2 | base=main; depends on PR 1 image |
| 3 | KasmVNC + smoke tests | PR 3 | base=main; depends on PR 1+2 |

## Phase 1: Foundation

- [x] 1.1 Create `dev-base/Dockerfile`: Ubuntu Jammy ARM64, Node.js LTS, Bun, pnpm, Git, bash/zsh, non-root `UID 1000`
- [x] 1.2 Create `.env.example`: placeholders for `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `CODE_SERVER_PASSWORD`, `OPENCODE_SERVER_PASSWORD`, `CODENOMAD_USERNAME`, `CODENOMAD_PASSWORD`, `KASMVNC_PASSWORD`
- [x] 1.3 Create `scripts/bootstrap.sh`: one-shot init of `workspace_projects`, `workspace_profile`, `toolchains` dirs with correct ownership

## Phase 2: Core Services

- [x] 2.1 Create `opencode/Dockerfile`: `FROM dev-base`, install opencode server, expose `4096`, mount `opencode_config` and `workspace_projects`
- [x] 2.2 Create `codenomad/Dockerfile`: `FROM dev-base`, install CodeNomad, ensure `opencode` binary in `PATH`, expose `9898/9899`, mount `codenomad_config` and `workspace_projects`
- [x] 2.3 Create `docker-compose.yml`: 3 services (code-server, opencode, CodeNomad), 9 named volumes (3 external, 6 auto-created), internal `workspace-net`, Traefik labels for HTTPS routing per subdomain. KasmVNC deferred to slice 3.
- [x] 2.4 Add health checks and `depends_on` ordering to compose services

## Phase 3: Desktop & Integration

- [x] 3.1 Create `kasmvnc/Dockerfile`: overlay dev tools on `kasmweb/core-ubuntu-jammy:1.16.0`, enforce `UID 1000`, declare `deploy.resources.limits.memory: 4g`
- [x] 3.2 Add KasmVNC service to `docker-compose.yml` with `workspace_projects`, `workspace_home`, `kasm_config` mounts and Traefik routing to `desktop.workspace.dev`

## Phase 4: Testing & Verification

- [x] 4.1 Create `scripts/smoke-test.sh`: build ARM64 images, start stack, verify service ports respond, write/read shared volume cross-container, inspect images for secrets
- [x] 4.2 Create `scripts/arm64-validate.sh`: multi-arch build validation script with buildx/QEMU; target-host instructions mode for native ARM64 builds
- [x] 4.3 Create `scripts/secret-audit.sh`: inspect image Config.Env, Config.Labels, and layer history for embedded secrets

## Phase 5: Cleanup

- [x] 5.1 Document deploy/rollback/volume notes in `openspec/changes/self-hosted-workspace-mvp/README.md`
- [x] 5.2 Cross-check all proposal success criteria are satisfied (see apply-progress for detailed matrix)
