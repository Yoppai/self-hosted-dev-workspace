# CI/CD — Self-Hosted Workspace

This document describes the CI/CD pipeline for the Self-Hosted Workspace project: how images are built, where they're promoted, how Renovate tracks dependencies, and the GitHub Actions workflow architecture.

---

## Quick links

| Resource | Location |
|----------|----------|
| Build pipeline | `.github/workflows/build-images.yml` |
| PR validation | `.github/workflows/pr-validation.yml` |
| Renovate config | `.github/renovate.json` |
| Composite action | `.github/actions/docker-build-push/action.yml` |

---

## Runner architecture

Image builds use **GitHub-hosted `ubuntu-latest` runners** with QEMU emulation + Docker Buildx for cross-platform ARM64 builds. No self-hosted runners required.

Previously this project used a self-hosted ARM64 VPS runner (Oracle Cloud A1 Flex). The setup script (`scripts/setup-runner.sh`) is retained for reference but is no longer used in CI.

---

## Required GitHub secrets

These secrets must be configured in the repository's **Settings → Secrets and variables → Actions**:

| Secret | Used by | Purpose |
|--------|---------|---------|
| `DOKPLOY_WEBHOOK_URL` | `build-images.yml` | POST deploy trigger to Dokploy Compose webhook after successful build |

> 💡 GHCR authentication uses GitHub's built-in `GITHUB_TOKEN` — no manual secret needed. The workflow declares `permissions.packages: write`, which auto-provisions the token.
> `DOKPLOY_WEBHOOK_URL` is obtained from Dokploy UI → Service → Webhook. The old `DOKPLOY_WEBHOOK_SECRET` secret is no longer used.

---

## Workflows overview

### build-images.yml

The main CI pipeline triggered on:
- **Push to `main`**: builds changed images (path-filtered), validates, promotes to GHCR
- **Pull request**: builds affected images (path-filtered), validates, skips promotion
- **Workflow dispatch**: manual rebuild with optional `no-cache` flag
- **Schedule**: weekly (Monday 03:00 UTC), rebuilds all images from scratch (no-cache)

**Architecture**: Registry handoff with three phases:
1. **Build** → Cross-builds ARM64 images via QEMU + Buildx on `ubuntu-latest`, pushes only `sha-<short>` tags to GHCR.
2. **Validate** → Pulls `sha-*` images from GHCR, verifies architecture (arm64/aarch64), runs runtime smoke checks.
3. **Promote** → Uses `docker buildx imagetools create` to attach `latest` and version tags to validated `sha-*` images. No layer re-push.

`latest` and version tags are NEVER published before validation passes.

Job dependency graph:

```
changes (paths-filter)
  ├── build-dev-base ─┬─ build-opencode ─┐
  │                   ├─ build-codenomad ┤
  ├── build-kasmvnc ──┘                   ├─ validate ── promote-images ── notify-dokploy
  └─ (build-all flag)                     ┘
```

**Change detection** (`dorny/paths-filter`):
- `build-dev-base` runs if `dev-base/`, `opencode/`, or `codenomad/` changed
- `build-kasmvnc` runs only if `kasmvnc/` changed
- `build-opencode` and `build-codenomad` run automatically when `build-dev-base` runs
- On `schedule` or `workflow_dispatch`: all images rebuild regardless

Tagging strategy per image:
- **All**: `latest`, `sha-{commit}`
- **opencode-server**: additionally `opencode-{OPENCODE_VERSION}`
- **codenomad-server**: additionally `codenomad-{CODENOMAD_VERSION}`

Tags are applied during the `promote-images` job, which reuses the Dockerfile
ARG extraction logic from the composite action to generate version tags.

### pr-validation.yml

Lightweight PR checks running on `ubuntu-latest`:
- **Lint**: validates Dockerfile syntax (hadolint)
- **Compose validation**: ensures `docker-compose.yml` and `docker-compose.prod.yml` are valid
- **Secret audit**: checks for hardcoded placeholder secrets

### dependabot-auto-merge.yml

Removed — Renovate handles auto-merge natively via `automerge: true` in
`.github/renovate.json`. No separate workflow needed. Requires the Renovate
GitHub App installed on the repository and "Allow auto-merge" enabled in
repo settings.

---

## Local development

Use `docker-compose.yml` for local builds — it has `build:` sections for custom images:

```bash
cp .env.example .env
docker compose build
docker compose up -d
```

For production, `docker-compose.prod.yml` references CI-built images from GHCR. Dokploy uses this file to pull pre-built images instead of rebuilding locally.

---

## Renovate version checking

Renovate scans for outdated dependencies weekly (Monday 09:00 UTC).
It requires the [Renovate GitHub App](https://github.com/apps/renovate)
installed on this repository.

| Manager | Scope | What it checks |
|---------|-------|---------------|
| **Dockerfile** (built-in) | `dev-base/`, `kasmvnc/` | Base image `FROM` updates (ubuntu, kasmweb) |
| **docker-compose** (built-in) | `docker-compose.yml`, `docker-compose.prod.yml` | External image updates (codercom/code-server) |
| **Regex** (custom) | `opencode/Dockerfile` | `ARG OPENCODE_VERSION` — checks npm for `opencode-ai` |
| **Regex** (custom) | `codenomad/Dockerfile` | `ARG OPENCODE_VERSION` + `ARG CODENOMAD_VERSION` — checks npm for `opencode-ai` + `@neuralnomads/codenomad` |

> **Why Renovate instead of Dependabot**: Dependabot cannot update `ARG`
> values inside Dockerfiles — it only touches `FROM` lines. Renovate's
> `regex` custom manager extracts and updates `ARG *_VERSION` directly,
> syncing the Dockerfile with the latest npm release automatically.

**Grouping**: All `opencode-ai` updates (across `opencode/Dockerfile` and
`codenomad/Dockerfile`) are grouped into a single PR.

**Auto-merge policy**: Patch and digest updates auto-merge once CI passes.
Major and minor updates require manual review.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| QEMU build timeout | ARM64 emulation on x86_64 is slow | Expected — first build (kasmvnc especially) may take 20–40 min; subsequent builds use GHA cache |
| Workflow fails on push | `GITHUB_TOKEN` lacks `packages` scope | Verify `permissions.packages: write` is set in the workflow file |
| Webhook POST fails | `DOKPLOY_WEBHOOK_URL` missing or changed | Non-fatal — images remain in GHCR; deploy manually via Dokploy UI; verify webhook URL in Dokploy → Service → Webhook |
| Cache miss, slow builds | `no-cache` was set, or GHA cache evicted | Next scheduled build will populate cache; cache uses `type=gha,mode=max` |
