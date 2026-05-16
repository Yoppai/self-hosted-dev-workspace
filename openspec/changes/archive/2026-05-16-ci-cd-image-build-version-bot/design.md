# Design: CI/CD Image Build & Version Bot

## Technical Approach

Self-hosted ARM64 GitHub Actions runner on the Oracle Cloud VPS (Docker container, `DOCKER_HOST` socket binding) builds all 4 images natively without QEMU. Uses `docker/build-push-action` with `type=gha` cache (`mode=max`). Single workflow with job dependencies: `dev-base` and `kasmvnc` in parallel, then `opencode` and `codenomad` in parallel after `dev-base`. Images pushed to GHCR with `latest`, `sha-{7}`, and version tags. Final step POSTs to Dokploy webhook. Dependabot scans weekly; patch PRs auto-merge if CI passes.

## Architecture Decisions

| Decision | Choice | Alternatives Rejected | Rationale |
|---|---|---|---|
| Runner architecture | Self-hosted ARM64 runner on Oracle VPS | GitHub-hosted ARM64 runners ($0.008/min); QEMU emulation (5-10× slower) | Free, native ARM64 builds, leverages existing infra. Builds ~3–5 min vs 15–30 min via QEMU. |
| Registry | GHCR (`ghcr.io/yoppai/self-hosted-dev-workspace/*`) | Docker Hub (rate limits, extra credentials) | Free for private repos, `GITHUB_TOKEN` auth, no pull limits within Actions. |
| Build ordering | Sequential with parallel where possible | All parallel (breaks `FROM dev-base` dependency) | `dev-base` + `kasmvnc` parallel; `opencode` + `codenomad` after `dev-base`. Respects Dockerfile dependency graph. |
| Compose strategy | Keep single `docker-compose.yml` with both `build:` and `image:` | Separate `docker-compose.prod.yml` | Dokploy uses `image:` when present; `docker compose build` uses `build:` locally. One file, zero drift. |
| Version bot | Dependabot (`.github/dependabot.yml`) | Renovate (more config, overkill); custom bot (high effort) | Zero config beyond YAML; covers Docker FROM + npm ARG pins; auto-merge patches natively. |
| Auto-merge patches | GitHub Action workflow (`dependabot-auto-merge.yml`) | Dependabot native auto-merge (limited) | Uses `ghcli` to merge after CI passes; labels filter for `dependencies` + `patch`; blocks on failure. |

## Data Flow

```
Git push → GitHub Actions → Self-hosted runner (ARM64, Docker socket)
  ├── Job: dev-base ──→ build ──→ push GHCR (latest, sha-7)
  ├── Job: kasmvnc ──→ build ──→ push GHCR (latest, sha-7)  [parallel with dev-base]
  ├── Job: opencode ──→ build ──→ push GHCR (latest, sha-7, opencode-{v})  [needs dev-base]
  ├── Job: codenomad ──→ build ──→ push GHCR (latest, sha-7, codenomad-{v})  [needs dev-base]
  └── Job: deploy ──→ POST Dokploy webhook ──→ Dokploy pulls & restarts
```

**Dependabot flow:**

```
Weekly cron (Mon) → Dependabot scans Dockerfiles + docker-compose.yml
  → Patch update → Open PR + label `dependencies`, `patch` → CI passes → Auto-merge → Deploy
  → Minor/Major → Open PR + label `dependencies`, `minor`/`major` → Await manual review
```

## File Changes

| File | Action | Description |
|---|---|---|
| `.github/workflows/build-images.yml` | Create | Main CI: build, validate, push, deploy |
| `.github/workflows/dependabot-auto-merge.yml` | Create | Merges patch PRs after CI passes |
| `.github/dependabot.yml` | Create | Docker + npm scanning, weekly schedule |
| `.github/actions/docker-build-push/action.yml` | Create | Composite: login, buildx, cache, push |
| `scripts/setup-runner.sh` | Create | One-time runner registration on VPS |
| `docker-compose.yml` | Modify | Update `image:` refs to GHCR paths for Dokploy pull |
| `dev-base/Dockerfile` | Modify | Ensure `FROM` is Dependabot-friendly (already is) |
| `opencode/Dockerfile` | Modify | Ensure `ARG OPENCODE_VERSION` is Dependabot-friendly (already is) |
| `codenomad/Dockerfile` | Modify | Ensure `ARG` pins are Dependabot-friendly (already is) |
| `kasmvnc/Dockerfile` | Modify | Ensure `FROM` is Dependabot-friendly (already is) |

## Workflow Design

### `build-images.yml`

**Triggers:** `push: main`, `pull_request`, `workflow_dispatch` (input: `no-cache` boolean), `schedule: cron '0 6 * * 1'`

**Jobs:**
1. `changes` — `dorny/paths-filter` to detect which Dockerfiles changed (for PR optimization)
2. `dev-base` — build + push `ghcr.io/yoppai/self-hosted-dev-workspace/dev-base`
3. `kasmvnc` — build + push `ghcr.io/yoppai/self-hosted-dev-workspace/kasmvnc-workspace`
4. `opencode` — needs `dev-base`; build + push `ghcr.io/.../opencode-server`
5. `codenomad` — needs `dev-base`; build + push `ghcr.io/.../codenomad-server`
6. `validate` — needs all builds; runs `scripts/arm64-validate.sh`
7. `smoke` — needs validate; runs `scripts/smoke-test.sh --build-only`
8. `deploy` — needs smoke; POSTs `secrets.DOKPLOY_DEPLOY_WEBHOOK_URL` (non-fatal on failure)

**Tagging per image:**
- All: `latest`, `sha-${GITHUB_SHA::7}`
- `opencode-server`: additionally `opencode-${OPENCODE_VERSION}`
- `codenomad-server`: additionally `codenomad-${CODENOMAD_VERSION}`

### `dependabot-auto-merge.yml`

**Trigger:** `pull_request` (labeled `dependencies`)
**Condition:** Actor == `dependabot[bot]`, label contains `patch`, all checks pass
**Action:** `gh pr merge --auto --squash` via `GITHUB_TOKEN`

### `dependabot.yml`

5 `package-ecosystem: docker` entries: `/dev-base`, `/opencode`, `/codenomad`, `/kasmvnc`, `/`
- `schedule: interval: weekly, day: monday`
- `labels: [dependencies, docker]`
- `open-pull-requests-limit: 10`

## Dokploy Integration Design

**Webhook:** Dokploy generates a unique POST URL per service. Stored as `DOKPLOY_DEPLOY_WEBHOOK_URL` secret. The `deploy` job sends an empty POST; failure is non-fatal (warning annotation).

**Compose behavior:** Dokploy reads `docker-compose.yml`. Services with both `build:` and `image:` will use the `image:` reference if the image exists in the registry. Since CI pushes to GHCR with `latest`, Dokploy pulls the CI-built image instead of rebuilding locally.

**Rollback:** If a deployed image is broken, Dokploy keeps previous containers running if health checks fail. Manual rollback: push a fixed image or revert the commit triggering the build.

## Security Design

| Concern | Mitigation |
|---|---|
| GHCR auth | `GITHUB_TOKEN` with `packages: write` (Actions-generated, no manual secret) |
| Dokploy webhook | URL stored in `secrets.DOKPLOY_DEPLOY_WEBHOOK_URL`; never logged or echoed |
| Runner isolation | Runner container has only `DOCKER_HOST` socket mount; no workspace volumes, no host filesystem access |
| Secrets in layers | `ARG` values for versions are non-sensitive; API keys injected at runtime via `environment:` in compose, never in Dockerfiles |
| Auto-merge safety | Only patch-level Dependabot PRs; CI must pass; actor strictly `dependabot[bot]` |

## Testing Strategy

| Layer | What | Approach |
|---|---|---|
| Unit | Composite action logic | Validate action YAML syntax with `actionlint` |
| Integration | Build workflow on PR | PR triggers build for changed images only; no push |
| E2E | Full main-branch flow | Push to main → validate ARM64 → smoke test → push → webhook |

## Migration / Rollout

No migration required. New files are additive. Rollback: disable workflow in GitHub UI, stop runner container, revert to manual `docker build`.

## Open Questions

- [ ] Should the self-hosted runner run on a separate lightweight VM instead of the production VPS?
- [ ] Should Dependabot group all Docker updates into a single PR to reduce noise?
- [ ] Should the weekly rebuild rebuild `dev-base` from scratch (picks up OS patches) or only child images?
