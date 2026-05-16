# CI/CD — Self-Hosted Workspace

This document describes the CI/CD pipeline for the Self-Hosted Workspace project: how images are built, where they're pushed, how Renovate tracks dependencies, and what's needed to set up a self-hosted runner.

---

## Quick links

| Resource | Location |
|----------|----------|
| Build pipeline | `.github/workflows/build-images.yml` |
| PR validation | `.github/workflows/pr-validation.yml` |
| Renovate config | `.github/renovate.json` |
| Composite action | `.github/actions/docker-build-push/action.yml` |
| Runner setup script | `scripts/setup-runner.sh` |

---

## Self-hosted runner setup

All image builds run on a self-hosted ARM64 runner (Oracle Cloud A1 Flex VPS) for native ARM64 performance. Set it up with:

```bash
# On the VPS (as root):
export GITHUB_PAT="ghp_..."
sudo ./scripts/setup-runner.sh
```

The script:
- Downloads the GitHub Actions runner binary for `arm64`
- Creates a `gh-runner` system user
- Registers the runner with the repository
- Installs a `systemd` service with auto-restart on boot

**Labels assigned**: `arm64`, `self-hosted`, `dev-workspace`

---

## Required GitHub secrets

These secrets must be configured in the repository's **Settings → Secrets and variables → Actions**:

| Secret | Used by | Purpose |
|--------|---------|---------|
| `GHCR_TOKEN` | `build-images.yml` | Push images to `ghcr.io/yoppai/self-hosted-dev-workspace/*` |
| `DOKPLOY_WEBHOOK_URL` | `build-images.yml` | POST deploy trigger to Dokploy after successful build |
| `DOKPLOY_WEBHOOK_SECRET` | `build-images.yml` | Shared secret for webhook authentication |

> ⚠️ `GHCR_TOKEN` requires `packages: write` scope. Create it as a fine-grained token with access to this repository only.

---

## Workflows overview

### build-images.yml

The main CI pipeline triggered on:
- **Push to `main`**: builds changed images (path-filtered), validates, pushes to GHCR
- **Pull request**: builds affected images (path-filtered), validates, skips push
- **Workflow dispatch**: manual rebuild with optional `no-cache` flag
- **Schedule**: weekly (Monday 03:00 UTC), rebuilds all images from scratch (no-cache)

**Architecture**: Images are NEVER pushed before validation. Build jobs use
`load: true` only (no push). A separate `push-images` job runs only after
`validate` succeeds on the `main` branch. This prevents broken images from
reaching production.

Job dependency graph:

```
changes (paths-filter)
  ├── build-dev-base ─┬─ build-opencode ─┐
  │                   ├─ build-codenomad ┤
  ├── build-kasmvnc ──┘                   ├─ validate ── push-images ── notify-dokploy
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

Tags are applied during the `push-images` job, which reuses the Dockerfile
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
| Runner offline | VPS rebooted, container stopped | Check `systemctl status actions.runner.*` on VPS; runner has `restart: unless-stopped` |
| Workflow fails on push | `GHCR_TOKEN` missing or expired | Verify token in repo secrets; create new fine-grained PAT with `packages: write` |
| Webhook POST fails | Dokploy URL changed or unreachable | Non-fatal — images remain in GHCR; deploy manually via Dokploy UI |
| Cache miss, slow builds | `no-cache` was set, or GHA cache evicted | Next scheduled build will populate cache; cache uses `type=gha,mode=max` |
