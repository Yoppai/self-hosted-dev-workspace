# Archive: CI/CD Image Build & Version Bot

**Date archived**: 2026-05-16
**Last updated**: 2026-05-16 (post-archive: Renovate switch + domain update)
**Change name**: ci-cd-image-build-version-bot
**Previous location**: `openspec/changes/ci-cd-image-build-version-bot/`
**Archive location**: `openspec/changes/archive/2026-05-16-ci-cd-image-build-version-bot/`

---

## Change Summary

Automate ARM64 Docker image builds, tagging, caching, and GHCR push for all 4 workspace images via GitHub Actions with a self-hosted ARM64 runner on the Oracle Cloud VPS. Introduce a version-checking bot (Renovate) that proactively detects outdated Docker base images and npm packages in Dockerfile ARGs, opening PRs with auto-merge for patch-level updates. Add Dokploy webhook integration for automatic redeployment after CI image push.

**Capabilities delivered**:
- **ci-cd-pipeline**: Build, cache, validate, push, and deploy all 4 ARM64 images via GitHub Actions
- **version-checking-bot**: Renovate-driven Docker + npm dependency tracking with regex custom managers for ARG updates, auto-merge for patches
- **workspace-orchestration** (delta): Dokploy webhook deployment trigger and Compose image references

---

## Files Created (12 new)

| File | Purpose |
|------|---------|
| `.github/actions/docker-build-push/action.yml` | Composite action: buildx, GHA cache, GHCR login, push |
| `.github/workflows/build-images.yml` | Main CI: build, validate, push, deploy workflow |
| `.github/workflows/pr-validation.yml` | PR validation workflow for Dockerfile changes |
| `.github/renovate.json` | Renovate config: regex managers for ARG updates + built-in Docker managers |
| `.github/README.md` | Runner setup, secrets, workflow guide, troubleshooting |
| `docker-compose.prod.yml` | Production compose file with GHCR image references |
| `scripts/setup-runner.sh` | Self-hosted ARM64 runner registration script |
| `openspec/changes/ci-cd-image-build-version-bot/exploration.md` | SDD exploration artifact |
| `openspec/changes/ci-cd-image-build-version-bot/proposal.md` | SDD proposal artifact |
| `openspec/changes/ci-cd-image-build-version-bot/design.md` | SDD design artifact |

## Files Modified (5)

| File | Description |
|------|-------------|
| `scripts/smoke-test.sh` | Added `--build-only` / `CI=true` mode for CI usage |
| `docker-compose.yml` | Added dev vs prod comment; changed all Traefik Host() rules from `*.workspace.dev` to `*.workspace.yoppai.dev` |
| `docker-compose.prod.yml` | Changed all Traefik Host() rules from `*.workspace.dev` to `*.workspace.yoppai.dev` |
| `docs/prd-self-hosted-workspace.md` | Added v1.2 section covering CI/CD, Renovate, webhook |
| `openspec/changes/ci-cd-image-build-version-bot/tasks.md` | Marked 11/11 tasks complete with fix notes |

---

## Specs Synced to Source of Truth

| Domain | Action | Details |
|--------|--------|---------|
| `ci-cd-pipeline` | Created | New spec: 8 requirements, 12 scenarios covering runner, build, triggers, caching, notifications, validation, smoke tests |
| `version-checking-bot` | Created | New spec: 7 requirements, 10 scenarios covering Docker/npm scanning, schedule, auto-merge, grouping |
| `workspace-orchestration` | Updated | Merged 2 ADDED requirements (Dokploy Webhook Deployment Trigger, Compose Image References) + 1 MODIFIED requirement (Dokploy Integration — added 2 new scenarios) |

### Canonical spec locations
- `openspec/specs/ci-cd-pipeline/spec.md`
- `openspec/specs/version-checking-bot/spec.md`
- `openspec/specs/workspace-orchestration/spec.md`

---

## Verification Result

**Verdict: PASS WITH WARNINGS**

| Metric | Value |
|--------|-------|
| Tasks total | 11 |
| Tasks complete | 11 |
| Compliance | 26/31 scenarios compliant, 4 partial, 1 not implemented |
| CRITICAL issues | 0 (5 resolved in WU3) |

### Remaining Warnings (2)

1. **ARM64 validation not fully via `scripts/arm64-validate.sh`** — Spec requires reusing the script; validate job runs `--check-only` and then inline `docker inspect`. A new `--verify-existing` mode in the script would close this gap.

2. **No explicit build failure notification mechanism** — Spec requires "post a workflow status notification when any build job fails." No Slack/Discord/email step exists; only GitHub native notifications.

### Resolved Post-Archive (3)

3. ~~**Dependabot labels don't match spec**~~ → Replaced Dependabot with Renovate; labels now `[dependencies, type:chore]` via `renovate.json`.

4. ~~**No `groups` configuration**~~ → Added `groups` for `opencode-ai` in Renovate config, then replaced Dependabot entirely with Renovate which groups natively.

5. ~~**Dependabot npm updates `package.json` instead of Dockerfile ARG**~~ → Replaced Dependabot with Renovate. Renovate's regex custom managers update `ARG *_VERSION` directly in Dockerfiles — no manual sync needed.

### Remaining Suggestions (3)

1. **`setup-runner.sh` hardcodes repo owner** — `Yoppai/self-hosted-dev-workspace` hardcoded; consider `GITHUB_REPOSITORY` env var parameterization.

2. **smoke-test.sh `--build-only` rebuilds images redundantly in CI** — Buildx already loads images; smoke test rebuilds from scratch. Consider `--validate-existing` mode.

3. **Redundant duplicate Docker entries in `dependabot.yml`** — Two identical `docker` ecosystem entries at `/`; consolidating avoids potential duplicate PRs.

---

## Known Limitations

- **No image signing (Cosign)**: Deferred to follow-up security hardening.
- **No KasmVNC password rotation**: Deferred to separate change.
- **Runner runs on production VPS**: Currently colocated with the workspace; dedicated runner VM is a future optimization.

---

## Implementation Notes

- **Delivery**: 3 chained PRs (auto-chain, stacked-to-main)
- **Work Units**: WU1 (Foundation + Core CI) → WU2 (Bot + Docs) → WU3 (Critical Fixes)
- **Features implemented late (WU3 fixes)**: `pull_request` trigger, weekly `schedule` trigger, push-after-validate safety gate, per-job change detection via `dorny/paths-filter`
- **Post-archive changes**:
  - **Renovate switch**: Replaced Dependabot with Renovate (`.github/renovate.json`). Renovate's regex custom managers update `ARG *_VERSION` directly in Dockerfiles — no manual ARG/package.json sync. Deleted `dependabot.yml`, `dependabot-auto-merge.yml`, `opencode/package.json`, `codenomad/package.json`.
  - **Domain update**: Changed all Traefik `Host()` rules from `*.workspace.dev` to `*.workspace.yoppai.dev` in both compose files.
- **Schedule time deviation**: Design specified Mon 06:00 UTC; actual uses Mon 03:00 UTC to avoid peak CI hours
- **Validate job deviation**: Design specified `arm64-validate.sh` script; implemented as `--check-only` + inline `docker inspect` to avoid redundant image rebuilds
- **Provenance fix**: Added `provenance: false` to composite action for `load: true` compatibility with buildx
- **Webhook architecture**: `push-images` job runs AFTER validate on `main` only; deploy job sends POST to `DOKPLOY_DEPLOY_WEBHOOK_URL` with `continue-on-error: true`

---

## Engram Artifact IDs

| Artifact | Engram ID | Type |
|----------|-----------|------|
| Proposal | #1089 | architecture |
| Spec | #1090 | architecture |
| Design | #1092 | architecture |
| Tasks | #1093 | architecture |
| Apply Progress | #1096 | architecture |
| Verify Report | #1095 | decision |
| Archive Report | *(this file)* | architecture |
