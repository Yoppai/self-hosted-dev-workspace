# Exploration: CI/CD Image Build & Version Bot

## Executive Summary

This exploration covers building ARM64 Docker images in CI, automated dependency version checking, Dokploy integration, and security considerations for `self-hosted-dev-workspace`. The recommendation is **two separate changes**: (1) CI/CD pipeline using a **self-hosted ARM64 GitHub Actions runner** on the existing Oracle Cloud VPS, building 4 images with layer caching, pushing to **GHCR**, and triggering Dokploy via webhook; (2) a **Dependabot**-based version checker for npm + Docker dependencies, with auto-merge for patches and PRs for minor/major bumps.

---

## 1. Current State

- **No CI/CD exists**. All 4 Docker images are built manually with `docker build --platform linux/arm64` on the dev machine.
- **No .github/ directory** in the repo.
- Images tagged only with `:latest` — no SHA or version tracking.
- Version pins hardcoded as ARG defaults in Dockerfiles (e.g., `opencode-ai@1.15.1`).
- **Dokploy** runs on the same Oracle Cloud VPS, handles Traefik HTTPS, and can auto-deploy on git push or webhook.
- Repository: `github.com/Yoppai/self-hosted-dev-workspace` (private).
- All builds **must** target `linux/arm64`.

### Build Dependency Graph

```
dev-base (no deps)
  ├── opencode-server (FROM dev-base:latest)
  └── codenomad-server (FROM dev-base:latest)
kasmvnc-workspace (independent — FROM kasmweb/core-ubuntu-jammy)
```

Optimal parallelization: `dev-base` → `opencode-server` + `codenomad-server` in parallel; `kasmvnc` runs independently alongside `dev-base`.

---

## 2. CI/CD Pipeline Options

### 2.1 Runner Architecture

| Approach | Pros | Cons | Effort |
|---|---|---|---|
| **Self-hosted ARM64 runner** (on Oracle Cloud VPS) | Free, native ARM64 (no QEMU), full control, leverages existing infra, fast builds (4 OCPU) | Requires runner setup + maintenance; runner consumes VPS resources | Medium |
| GitHub-hosted ARM64 runner | Zero maintenance, native ARM64 | ~$0.008/min (private repo), limited concurrent jobs | Low |
| QEMU emulation (buildx on x86 runner) | Works on any runner, no infra cost | **5-10x slower** for ARM64 builds, cache invalidation issues, flaky with complex images | Low (but slow) |
| Hybrid: QEMU for PR checks, self-hosted for publish | Best of both worlds | Complex setup, two workflows | High |

**Recommended: Self-hosted ARM64 runner** — run as a Docker container on the same Oracle Cloud VPS. The VPS has 4 OCPU and 24 GB RAM, more than enough to run a build runner alongside the workspace containers. The runner authenticates via a GitHub Personal Access Token stored as a GitHub secret.

Why not QEMU: Building 4 ARM64 images (especially Node.js compilation in `npm install -g`) through QEMU emulation on an x86 GitHub runner would take 15-30+ minutes per build. Self-hosted native ARM64 makes each build ~3-5 minutes with caching.

### 2.2 Docker Layer Caching

**Recommended: `type=gha`** (GitHub Actions cache backend for BuildKit).

- No external storage needed — cache stored in GitHub Actions itself.
- Cache key: `dev-base` by Dockerfile hash; child images by Dockerfile hash + dev-base layer digest.
- Cache scope: per-branch, with `mode=max` to cache all layers (not just final).
- Estimated savings: dev-base rarely changes (OS + Node.js install); child images rebuild on npm version bumps. Cache reduces child image rebuilds from ~3 min to ~30s.

Alternatives considered:
- `type=registry` (push cache layers to GHCR): works but increases storage and pull times. Not needed for this scale.
- `type=local` (save/load cache via artifact): slower, manual cleanup needed.

### 2.3 Build Orchestration

Single workflow with job dependencies:

```yaml
jobs:
  kasmvnc:            # no deps, runs in parallel with dev-base
  dev-base:           # no deps, runs in parallel with kasmvnc
    outputs:
      digest: ${{ steps.build.outputs.digest }}
  opencode:           # needs dev-base
    needs: [dev-base]
  codenomad:          # needs dev-base
    needs: [dev-base]
```

`kasmvnc` is fully independent and can build in parallel with everything.

### 2.4 Registry Destination

**Recommended: GHCR (ghcr.io)** — primary and only registry for CI builds.

Why GHCR:
- **Free** for public AND private repos (no pull rate limits within GitHub Actions).
- **Integrated auth**: `GITHUB_TOKEN` with `packages: write` permission — no extra secrets.
- **Same org as repo**: `ghcr.io/yoppai/self-hosted-dev-workspace/opencode-server:latest`.
- Docker Hub alternative considered but rejected due to rate limits on pulls and needing separate credentials.

### 2.5 Tagging Strategy

| Tag | Purpose | Updated |
|---|---|---|
| `latest` | Always points to most recent successful build | Every build → main |
| `sha-{7}` | Exact version for traceability (`sha-abc1234`) | Every build → main |
| `{version}` | For npm-pinned images, mirrors the pinned version | When ARG changes |
| `pr-{number}` | Preview tag for PR builds | On PR (optional) |

**For `dev-base`**: `latest` + `sha-{7}`. Version tag doesn't apply (it's the base platform).

**For `opencode-server`**: `latest` + `sha-{7}` + `opencode-{version}` (e.g., `opencode-1.15.1`).

**For `codenomad-server`**: `latest` + `sha-{7}` + `codenomad-{version}` (e.g., `codenomad-0.16.0`).

**For `kasmvnc-workspace`**: `latest` + `sha-{7}`.

### 2.6 Trigger Strategy

| Trigger | Behavior | Why |
|---|---|---|
| `push: main` | Build all 4 images + push + Dokploy webhook | Standard CI: every commit ships |
| `pull_request` | Build only changed images (no push) | Validate PR doesn't break build |
| `workflow_dispatch` | Manual: pick which image(s) to build | One-off rebuilds, testing |
| `schedule: weekly` | Full rebuild (no cache from scratch) | Pick up OS security patches |

Weekly scheduled rebuild with `--no-cache` ensures `apt-get update` in dev-base picks up latest security patches for ubuntu:jammy.

---

## 3. Version-Checking Bot

### 3.1 Tool Comparison

| Tool | Docker FROM | npm packages | NodeSource LTS | PRs | Auto-merge | Complexity |
|---|---|---|---|---|---|---|
| **Dependabot** (GitHub-native) | ✅ Yes | ✅ Yes | ❌ No | ✅ Yes | ✅ Patches only | Zero |
| **Renovate Bot** | ✅ Yes | ✅ Yes | ⚠️ Custom regex | ✅ Yes | ✅ Configurable | Low |
| Custom GitHub Action | ✅ Yes | ✅ Yes | ✅ Yes | ✅ Yes | ✅ Custom | High |
| Manual (no bot) | ❌ | ❌ | ❌ | ❌ | ❌ | Zero but neglect |

### 3.2 Recommended: Dependabot (with Renovate as upgrade path)

**Dependabot** is the right choice for this project:
- Zero configuration (one YAML file: `.github/dependabot.yml`)
- Covers the two main dependency types: Docker (FROM pins) and npm (package.json not in repo but ARG defaults in Dockerfiles)
- Will scan Dockerfiles and detect hardcoded version strings like `ARG OPENCODE_VERSION=1.15.1`
- Opens individual PRs for each outdated dependency
- Can auto-merge patch updates (`@dependabot merge` or `group:patch` config)
- For private repos, Dependabot v2 is enabled by default in GitHub Free

**Limitation acknowledged**: Dependabot **cannot** check NodeSource LTS script versions (`setup_lts.x` points to "latest LTS" so there's no version to pin there). This is acceptable — NodeSource LTS is a rolling release and the script itself is updated by NodeSource.

**Renovate** would be the upgrade path if:
- Need to group `opencode-ai` + `@neuralnomads/codenomad` bumps into a single PR (they're tested together)
- Need custom regex managers for non-standard version pins
- Want automatic PR merging with branch protection rules

### 3.3 What Dependabot Covers

| Dependency | File | Dependabot Support |
|---|---|---|
| `opencode-ai` (npm) | `opencode/Dockerfile`, `codenomad/Dockerfile` (ARG) | ✅ Detected via Dockerfile ARG |
| `@neuralnomads/codenomad` (npm) | `codenomad/Dockerfile` (ARG) | ✅ Detected via Dockerfile ARG |
| `kasmweb/core-ubuntu-jammy` (Docker) | `kasmvnc/Dockerfile` (FROM) | ✅ Detected via Docker FROM |
| `codercom/code-server` (Docker) | `docker-compose.yml` (image) | ✅ Detected via compose `image:` |
| `ubuntu:jammy` (Docker) | `dev-base/Dockerfile` (FROM) | ✅ Detected via Docker FROM |
| Node.js LTS (indirect via nodesource) | `dev-base/Dockerfile` | ❌ Rolling release, no version to pin |

### 3.4 What the Bot Should DO

| Version Change | Action | Rationale |
|---|---|---|
| **Patch** (e.g., 1.15.1 → 1.15.2) | Auto-create PR + auto-merge if CI passes | Low risk, security fixes |
| **Minor** (e.g., 1.15.1 → 1.16.0) | Create PR, notify for review | May have breaking changes |
| **Major** (e.g., 1.15.1 → 2.0.0) | Create PR with warning label, manual review required | Breaking changes expected |
| **Docker base image** (e.g., ubuntu:jammy SHA) | Create PR, manual review | Base image changes can have subtle runtime effects |
| **Node.js LTS** (indirect) | Manual check (scheduled reminder or manual) | Can't automate — check quarterly |

### 3.5 Dependabot Configuration

```yaml
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: "docker"
    directory: "/dev-base"
    schedule:
      interval: "weekly"
  - package-ecosystem: "docker"
    directory: "/opencode"
    schedule:
      interval: "weekly"
  - package-ecosystem: "docker"
    directory: "/codenomad"
    schedule:
      interval: "weekly"
  - package-ecosystem: "docker"
    directory: "/kasmvnc"
    schedule:
      interval: "weekly"
  - package-ecosystem: "docker"
    directory: "/"
    schedule:
      interval: "weekly"
    # Covers docker-compose.yml (code-server image)
```

---

## 4. Integration with Dokploy

### 4.1 The Dokploy Deployment Flow

Dokploy supports multiple deploy triggers:
- **Git push**: Auto-deploys when a new commit is pushed to the configured branch
- **Webhook**: POST to a unique URL triggers redeployment
- **Manual**: Via Dokploy dashboard

### 4.2 Recommended: CI pushes images → CI calls Dokploy webhook

```
Git push → GitHub Actions builds images
  → pushes to GHCR (latest + sha tags)
  → POSTs to Dokploy webhook URL
  → Dokploy pulls new images + docker compose up -d
```

**Why webhook over git push**: The compose file references images by `build:` + `image:` tags. Dokploy needs to run `docker compose pull` to get new layers but won't do this automatically unless triggered. The webhook triggers a fresh `docker compose pull && docker compose up -d`.

### 4.3 Critical Design Decision: Compose File for Production

**Problem**: The current `docker-compose.yml` has both `build:` and `image:` sections for custom images. When Dokploy runs `docker compose up -d`, it will try to build from source (which requires the full git repo context and Dockerfiles to be present).

**Solution paths**:

| Option | Pros | Cons |
|---|---|---|
| **A. Keep `build:` in compose, Dokploy builds too** | Single compose file | Duplicate build (CI builds AND Dokploy builds); waste of VPS CPU |
| **B. Remove `build:` in compose, use only `image:`** | Clean separation: CI builds, Dokploy pulls | Need to maintain two compose variants or a post-CI compose patch |
| **C. Use `docker-compose.yml` for local dev, `docker-compose.prod.yml` for Dokploy** | Clear separation of concerns | Two files to maintain |
| **D. CI writes SHA-tagged image references to compose, commits and pushes** | Dokploy auto-deploys on git push, no webhook needed | CI commits to repo = extra git operations, potential conflicts |

**Recommendation: Option A for now, evolve to B or C later.**

For the MVP: Dokploy runs on the same VPS and has access to the git repo (including subdirectories). Let Dokploy build from source — the first build is slow, but subsequent builds benefit from Docker layer caching on the VPS. The CI pipeline is "pre-flight" validation that images build correctly; Dokploy's build is the actual deployment artifact.

**Long-term**: Evolve to Option C — a `docker-compose.prod.yml` that references GHCR images directly, removing the `build:` sections. CI pushes images, then updates the prod compose file.

### 4.4 Dokploy Webhook Implementation

After the CI build + push, the final workflow step makes a POST request:

```yaml
- name: Trigger Dokploy deploy
  run: |
    curl -X POST "${{ secrets.DOKPLOY_DEPLOY_WEBHOOK_URL }}"
```

The webhook URL is stored as a GitHub Actions secret. Dokploy generates this URL per service in its dashboard.

---

## 5. Security Considerations

### 5.1 Credentials in GitHub Actions

| Secret | Source | Used For |
|---|---|---|
| `GITHUB_TOKEN` | Auto-generated by Actions | Pushing to GHCR (automatic) |
| `DOKPLOY_DEPLOY_WEBHOOK_URL` | Dokploy dashboard | Triggering Dokploy deploy |
| `ACTIONS_RUNNER_TOKEN` | GitHub → self-hosted runner | Runner registration (one-time) |

**No Docker Hub credentials needed** if using GHCR exclusively. No API keys in the build environment.

### 5.2 Self-Hosted Runner Security

Running a self-hosted runner on the production VPS introduces risk:
- **Risk**: A compromised CI workflow could execute arbitrary code on the VPS.
- **Mitigation**: Run the runner in a Docker container with limited volume mounts, no access to host Docker socket (except Docker-outside-of-Docker for building), and no access to workspace volumes.
- **Better mitigation**: Run the runner on a separate VPS or as a GitHub Codespace. For a personal project, the risk is acceptable.

**Recommendation**: Run the runner as a Docker container on the VPS, using the `DOCKER_HOST` env var to connect to the host Docker socket ONLY for building images (Docker-outside-of-Docker pattern). The runner container itself has no access to workspace data.

### 5.3 Supply Chain Security — Image Signing

**Cosign (Sigstore)**: Industry standard for container image signing.

| Approach | Pros | Cons | Effort |
|---|---|---|---|
| **Keyless signing** (OIDC) | No key management, GitHub-native OIDC | Requires `id-token: write` permission; image must be attestable | Medium |
| **No signing** (MVP) | Simpler, faster | No supply chain security | None |
| **Cosign + private key** | Full control | Key management burden | High |

**Recommendation**: Skip signing for MVP. Add Cosign keyless signing as a follow-up. This is a personal project with a single deployment target — the threat model doesn't warrant signing overhead yet.

### 5.4 Secret Scanning

GitHub's built-in secret scanning is automatic for public repos. For this private repo:
- **Push protection**: Enable in repo Settings → Code security → Secret scanning → Push protection
- This blocks commits containing known secret patterns (API keys, tokens)
- The `.gitignore` already excludes `.env` — good practice

---

## 6. Risks and Unknowns

| Risk | Impact | Likelihood | Mitigation |
|---|---|---|---|
| Self-hosted runner goes offline | CI fails until runner restarts | Medium | Health check + auto-restart (Docker restart policy); have a fallback QEMU workflow |
| Runner resource contention with workspace containers | Slower builds, degraded service | Low | 4 OCPU + 24 GB RAM is ample; pin runner CPU/memory via Docker resources |
| Dokploy webhook fails or changes | CI passes but deploy doesn't happen | Low | Webhook failure is non-fatal; can manually redeploy from Dokploy dashboard |
| Dependabot opens too many PRs | Notification fatigue | Low | Configure grouping; auto-merge patches |
| NodeSource LTS script URL changes | Base image OS packages fall behind | Low | Dev-base rarely changes; manual check when needed |
| GHCR storage limits | Can't push more images | Low (free tier: 500 MB → 2 GB for private) | Clean up old SHA tags periodically; `latest` + current SHA is enough |
| ARM64 runner image drift | Runner has different Docker version than expected | Low | Pin runner image version; automate runner updates |

---

## 7. Dependency Between CI/CD and Version Bot

**The CI/CD pipeline and the version bot are independent** in implementation but interdependent in value:

```
Version bot bumps ARG version in Dockerfile
  → PR merged to main
    → CI/CD builds image with new version
      → Pushes to GHCR
        → Dokploy redeploys
```

- The **CI/CD pipeline** is the foundation — builds happen regardless of version bumps.
- The **version bot** creates the *input* for new builds (version bumps).
- Neither strictly requires the other, but together they form a complete "bump → build → deploy" pipeline.

**Parallel implementation risk**: If CI/CD doesn't exist yet, the version bot's PRs will bump versions but nothing will build them. **Sequence**: Build CI/CD first, then add version bot.

---

## 8. One Change or Two?

**Recommendation: TWO separate changes.**

| Aspect | Change 1: CI/CD Pipeline | Change 2: Version Bot |
|---|---|---|
| **Scope** | GitHub Actions workflow, self-hosted runner setup, GHCR push, Dokploy webhook | `.github/dependabot.yml`, auto-merge config |
| **Files touched** | `.github/workflows/build.yml`, runner setup scripts | `.github/dependabot.yml` |
| **Risk** | Higher (runner setup, build config, secrets) | Minimal (just config) |
| **Effort** | Medium (3-5 days) | Low (1 day) |
| **Can ship independently** | Yes (CI builds without version bot) | Technically yes (PRs created, but nothing builds them) |
| **Testing complexity** | Medium (need to verify ARM64 build + push + deploy) | Low (Dependabot is GitHub-managed) |

**Recommended order**: Change 1 (CI/CD) → Change 2 (Version Bot). They can overlap in the same branch/PR chain but should be reviewed separately.

### 8.1 Chained PR Forecast

**Change 1 (CI/CD)**: ~250-350 lines (.github/workflows, possibly runner setup script, minor compose adjustments). Within 400-line budget — single PR.

**Change 2 (Version Bot)**: ~30-50 lines (.github/dependabot.yml only). Well within budget — single PR.

No chaining needed for either change individually.

---

## 9. Recommendation Summary

1. **Runner**: Self-hosted ARM64 runner on existing Oracle Cloud VPS (Docker container, DOCKER_HOST socket binding for native ARM64 builds).
2. **Build**: `docker/build-push-action` with `type=gha` layer caching, multi-job dependency graph.
3. **Registry**: GHCR (`ghcr.io/yoppai/self-hosted-dev-workspace/*`) — no credentials needed beyond `GITHUB_TOKEN`.
4. **Tags**: `latest` + `sha-{7}` for all images; version tags for npm-pinned images.
5. **Triggers**: Push to main (build all + deploy), PR (build changed only), weekly schedule (no-cache rebuild), manual dispatch.
6. **Dokploy**: POST to deploy webhook as final CI step. Initial deploy keeps `build:` in compose; evolve to prod compose file later.
7. **Version bot**: Dependabot with weekly schedule, auto-merge for patches, PR for minor/major.
8. **Security**: GHCR via GITHUB_TOKEN, no image signing for MVP, GitHub secret scanning push protection.
9. **Order**: CI/CD first → Version bot second (two separate changes).

### Key Open Questions for Design Phase

- Should the self-hosted runner run on the same VPS as workspace services, or on a separate lightweight VM?
- Should we modify docker-compose.yml for production (remove `build:`), or keep as-is and let Dokploy build?
- Dependabot grouping: separate PRs per image, or group all Docker updates into one?
- Weekly rebuild: should dev-base be rebuilt from scratch weekly, or just the child images?
