# Proposal: CI/CD Image Build & Version Bot

## Intent

Eliminate manual ARM64 image builds and version drift. Today, all 4 Docker images are built by hand on the dev machine, tags are only `:latest`, and dependency bumps (opencode-ai, codenomad, base images) are discovered by accident. This change automates the build → push → deploy loop and introduces a bot that proactively opens PRs when upstream versions change.

## Scope

### In Scope
- GitHub Actions workflow: self-hosted ARM64 runner, layer-cached builds, GHCR push, Dokploy webhook trigger
- Dependabot configuration for Docker + npm dependency tracking
- Tagging strategy (`latest`, `sha-{7}`, version tags for npm-pinned images)
- Trigger strategy: `push:main`, `pull_request`, `workflow_dispatch`, weekly no-cache rebuild

### Out of Scope
- Image signing (Cosign) — follow-up security hardening
- Separate `docker-compose.prod.yml` — keep `build:` in compose for now; evolve later
- Custom version bot (Renovate) — Dependabot is sufficient; Renovate is a future upgrade path
- GitHub-hosted ARM64 runners — we use the existing VPS

## Capabilities

### New Capabilities
- `ci-cd-pipeline`: Build, tag, cache, push, and trigger deploy for all 4 ARM64 images via GitHub Actions
- `version-checking-bot`: Automated detection of outdated Docker base images and npm packages in Dockerfiles; auto-PR for patches, review-required PRs for minor/major

### Modified Capabilities
- `workspace-orchestration`: Adds Dokploy webhook trigger as a deployment step after CI push

## Approach

Self-hosted ARM64 GitHub Actions runner deployed as a Docker container on the existing Oracle Cloud VPS (4 OCPU / 24 GB). Runner uses `DOCKER_HOST` socket binding for native ARM64 builds — no QEMU. Builds use `docker/build-push-action` with `type=gha` cache (`mode=max`). Single workflow with job dependencies: `kasmvnc` and `dev-base` in parallel; `opencode` and `codenomad` after `dev-base`. Images pushed to GHCR (`ghcr.io/yoppai/self-hosted-dev-workspace/*`) using `GITHUB_TOKEN`. Final step POSTs to Dokploy deploy webhook. Dependabot runs weekly, scanning each image directory plus root for `docker-compose.yml`.

## Affected Areas

| Area | Impact | Description |
|---|---|---|
| `.github/workflows/` | New | Build + deploy workflow |
| `.github/dependabot.yml` | New | Version bot configuration |
| `docker-compose.yml` | Modified | Webhook trigger integration; may adjust `image:` refs |
| `dev-base/Dockerfile` | Modified | Ensure ARG/FROM patterns are Dependabot-friendly |
| `opencode/Dockerfile` | Modified | Ensure ARG/FROM patterns are Dependabot-friendly |
| `codenomad/Dockerfile` | Modified | Ensure ARG/FROM patterns are Dependabot-friendly |
| `kasmvnc/Dockerfile` | Modified | Ensure FROM pattern is Dependabot-friendly |

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Self-hosted runner offline | Medium | Docker auto-restart policy; health check; fallback QEMU workflow if critical |
| Runner resource contention with workspace | Low | Pin runner CPU/memory limits; builds are short (~3–5 min) |
| Dokploy webhook failure | Low | Non-fatal; CI still passes; manual redeploy available |
| Dependabot opens too many PRs | Low | Weekly schedule; auto-merge patches; group if needed later |

## Rollback Plan

1. Disable the workflow in GitHub UI → Actions tab → workflow → Disable.
2. Stop the self-hosted runner container: `docker stop github-runner`.
3. Revert to manual builds with existing `docker build` commands.
4. Dokploy continues to build from source via `build:` in compose.

## Dependencies

- GitHub repository secret `DOKPLOY_DEPLOY_WEBHOOK_URL` configured
- Self-hosted runner registered and online
- Dokploy service configured to receive webhook
- GHCR write permission enabled for `GITHUB_TOKEN`

## Success Criteria

- [ ] Push to `main` triggers a workflow that builds all 4 images for `linux/arm64`, pushes them to GHCR with `latest` + `sha-{7}` tags, and calls Dokploy webhook
- [ ] Pull request builds changed images only (no push)
- [ ] Weekly scheduled build completes a no-cache full rebuild
- [ ] Dependabot opens PRs when Docker base images or npm ARG versions are outdated
- [ ] Patch-level Dependabot PRs auto-merge if CI passes
