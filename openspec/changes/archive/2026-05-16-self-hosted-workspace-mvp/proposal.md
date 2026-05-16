# Proposal: Self-Hosted Workspace MVP

## Intent

Centralize the development environment on an Oracle Cloud A1 Flex VPS managed by Dokploy, enabling browser-based access to IDEs, AI coding tools, and a remote desktop from any device without per-device configuration.

## Scope

### In Scope
- Docker Compose service with `code-server`, `opencode`, CodeNomad, and KasmVNC
- Shared Docker volumes for projects, config, and toolchains with standardized UID/GID
- Custom ARM64 images for services without official upstream support
- Cloudflare Access + Dokploy/Traefik HTTPS routing for all public endpoints
- `.env.example` template and smoke-test validation script

### Out of Scope
- Multi-tenancy or team isolation
- Kubernetes orchestration
- Ephemeral per-repo provisioning
- Production application deployments
- GPU-intensive workloads or mobile simulators
- Automated backup jobs (deferred to v1.1)

## Capabilities

### New Capabilities
- `workspace-orchestration`: Compose service definition, networking, and Traefik routing for all 4 services
- `dev-base-image`: Shared ARM64 base image with Git, Node.js, Bun, pnpm, and common shells
- `opencode-server`: Custom image running opencode in server mode with config/skills persistence
- `codenomad-server`: Custom image with CodeNomad and opencode CLI in PATH, session persistence
- `kasmvnc-workspace`: Custom KasmVNC desktop image with dev tools overlay and resource limits
- `volume-persistence`: Shared volume strategy for projects, profile, home, and per-tool config with UID 1000
- `secret-management`: Dokploy env var integration; no secrets committed or embedded in images

### Modified Capabilities
- None (greenfield project)

## Approach

Use a single `dev-base` ARM64 image with common tooling, then build service-specific overlays for `opencode`, CodeNomad, and KasmVNC. `code-server` uses the official pinned image directly. All containers run as UID 1000 to share volumes without permission fixes. Cloudflare Access guards every public route; Traefik terminates HTTPS. Secrets live in Dokploy env vars only.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `docker-compose.yml` | New | Main Compose with 4 services, 9 named volumes, internal network |
| `dev-base/Dockerfile` | New | Shared Ubuntu Jammy ARM64 base image |
| `opencode/Dockerfile` | New | Custom opencode server image |
| `codenomad/Dockerfile` | New | Custom CodeNomad image with opencode in PATH |
| `kasmvnc/Dockerfile` | New | Custom KasmVNC desktop with dev tools |
| `.env.example` | New | Dokploy env var template (placeholders only) |
| `scripts/smoke-test.sh` | New | Post-deploy validation script |
| `scripts/bootstrap.sh` | New | One-shot toolchain bootstrap into shared volumes |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| UID mismatch on shared volumes | Medium | Standardize 1000:1000 in all images; validate in smoke test |
| CodeNomad/opencode version coupling | Medium | Pin both versions; test together before deploy |
| KasmVNC high resource usage | High | Limit to 4 GB RAM; monitor during MVP |
| ARM64 build failure for custom images | Low | Validate `docker compose build` on ARM64 before accepting |
| Cloudflare Access misconfiguration | Low | Test auth wall with curl before pointing DNS |

## Rollback Plan

Redeploy the previous Dokploy service revision. All state lives in external named volumes, so rolling back the Compose service does not destroy project files or configuration. If volume corruption occurs, restore from the manual backup taken before the deploy.

## Dependencies

- Dokploy instance with Traefik enabled on Oracle A1 Flex
- Cloudflare Access policies configured for 4 subdomains
- ARM64 Docker build environment or buildx emulator

## Success Criteria

- [ ] All public routes protected by Cloudflare Access with HTTPS
- [ ] Internal auth enabled on every exposed service
- [ ] `workspace_projects` readable/writable from all 4 tools
- [ ] Restarting containers preserves extensions, skills, MCP config, and user settings
- [ ] Redeploying the Compose service does not delete project files
- [ ] All images/builds verified on `linux/arm64`
- [ ] No secrets in repository or embedded in images
