# Tasks: CI/CD Image Build & Version Bot

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | ~490 |
| 400-line budget risk | High |
| Chained PRs recommended | Yes |
| Suggested split | PR 1 (Foundation + Composite Action) → PR 2 (Workflows + Compose) → PR 3 (Dependabot + Docs) |
| Delivery strategy | auto-chain |
| Chain strategy | stacked-to-main |

Decision needed before apply: No
Chained PRs recommended: Yes
Chain strategy: stacked-to-main
400-line budget risk: High

### Suggested Work Units

| Unit | Goal | Likely PR | Notes |
|------|------|-----------|-------|
| 1 | Foundation: runner setup script, composite action, directory structure | PR 1 | Targets main; no CI deps yet |
| 2 | Core CI: build workflow, compose image refs, smoke-test CI compat, webhook | PR 2 | Targets main; depends on PR 1 merged (action.yml referenced) |
| 3 | Bot + Docs: Dependabot config, auto-merge workflow, documentation | PR 3 | Targets main; independent of PR 2 but best after CI is live |

## Phase 1: Foundation [WU1 — Complete]

- [x] 1.1 Create `.github/actions/docker-build-push/action.yml` composite action with buildx, GHA cache (`mode=max`), GHCR login, and push steps
  - Fix: Added `no-cache` input and `provenance: false` for `load: true` compatibility
- [x] 1.2 Create `scripts/setup-runner.sh` to register the ARM64 self-hosted runner on the Oracle VPS via Docker with `DOCKER_HOST` socket binding and `restart: unless-stopped`
- [x] 1.3 Document required GitHub repository secrets (`DOKPLOY_DEPLOY_WEBHOOK_URL`, `DOKPLOY_WEBHOOK_SECRET`) in `.github/README.md` (placeholder; full doc in Phase 4)

## Phase 2: CI/CD Pipeline [WU1 — Complete] [WU3 — Fixed]

- [x] 2.1 Create `.github/workflows/build-images.yml` with jobs: `changes` (paths-filter), `dev-base`, `kasmvnc` (parallel), `opencode`, `codenomad` (needs dev-base), `validate` (arm64-validate.sh), `smoke` (smoke-test.sh --build-only), `deploy` (Dokploy webhook POST, non-fatal on failure); triggers: push:main, pull_request, workflow_dispatch (no-cache input), schedule (weekly Mon 06:00)
  - Fix: Added `pull_request` trigger (CRITICAL 1)
  - Fix: Added `schedule` trigger weekly Mon 03:00 UTC (CRITICAL 2)
  - Fix: Restructured to push AFTER validate via separate `push-images` job (CRITICAL 3)
  - Fix: Added `changes` job with `dorny/paths-filter` for per-job change detection (CRITICAL 4)
  - Fix: Wired `no-cache` input to cache control; schedule always uses no-cache
  - Fix: Changed smoke test from `--ci` to `--build-only` per spec
  - Fix: Reused `arm64-validate.sh --check-only` for builder setup validation
  - Fix: Changed webhook failure annotations from `echo` to `::warning::`
- [x] 2.2 Update `docker-compose.yml` `image:` refs for custom services to `ghcr.io/yoppai/self-hosted-dev-workspace/{service}:latest` so Dokploy pulls CI-built images instead of rebuilding locally
- [x] 2.3 Update `scripts/smoke-test.sh` to accept `CI=true` env var and skip runtime stack startup / teardown when `--build-only` is passed, ensuring exit code 0 on successful builds only
- [x] 2.4 Verify tagging strategy in workflow: all images get `latest` and `sha-${GITHUB_SHA::7}`; `opencode-server` additionally gets `opencode-${OPENCODE_VERSION}`; `codenomad-server` additionally gets `codenomad-${CODENOMAD_VERSION}`
  - Fix: Tagging now happens in `push-images` job (retag from local daemon), not during build

## Phase 3: Version-Checking Bot [WU2 — Complete] [WU3 — Fixed]

- [x] 3.1 Create `.github/dependabot.yml` with docker + npm entries, weekly Monday schedule, labels `[dependencies, type:chore]`, open-pull-requests-limit 5
  - Fix: Added `opencode/package.json` and `codenomad/package.json` for functional npm tracking (CRITICAL 5)
- [x] 3.2 Create `.github/workflows/dependabot-auto-merge.yml` triggered on `pull_request_target`; condition: actor == `dependabot[bot]`; semver parsed from PR title; patch → approve + auto-merge; major/minor → comment requiring manual review

## Phase 4: Documentation [WU2 — Complete] [WU3 — Updated]

- [x] 4.1 Append CI/CD section to `docs/prd-self-hosted-workspace.md` covering: self-hosted runner, GHCR push, Dokploy webhook, Dependabot auto-merge, v1.2 roadmap phase, CI/CD risks
- [x] 4.2 Create `.github/README.md` with: runner setup instructions, secret checklist, workflow trigger guide, troubleshooting (runner offline, webhook failure, cache miss), and Dependabot version checking
  - Fix: Updated build-images job graph and push architecture docs
