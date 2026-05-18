# Proposal: Dokploy Deployment Pipeline

## Intent

Connect the existing CI-built images to Dokploy so the workspace deploys automatically after each GHCR push. The `notify-dokploy` job currently POSTs to a generic webhook; we need Dokploy-side configuration to receive and act on it.

## Scope

### In Scope
- Dokploy Compose service setup (Raw source) with `docker-compose.prod.yml`
- GHCR registry registration in Dokploy
- Environment variables configuration in Dokploy
- CI webhook integration fix (`notify-dokploy` job)
- Bootstrap script pre-execution for external volumes
- Domain/Traefik validation

### Out of Scope
- Dokploy server installation (already running)
- Cloudflare Access configuration (separate change)
- Volume backup/restore automation
- Multi-arch image builds

## Capabilities

### New Capabilities
- `dokploy-deployment`: Dokploy-side configuration for Compose service, registry auth, env vars, and webhook

### Modified Capabilities
- `ci-cd-pipeline`: Update `notify-dokploy` job to POST to Dokploy Compose webhook URL with correct payload

## Approach

**Strategy A** from exploration: Raw Compose source + Webhook trigger.

| Component | Decision | Rationale |
|-----------|----------|-----------|
| Compose source | Raw YAML paste | Avoids git clone clearing repo directory |
| Deploy trigger | Webhook POST | Simplest; existing job maps directly |
| Registry | GHCR with `write:packages` token | Already pushing there; Dokploy needs pull auth |
| Domains | Traefik labels in YAML | Keeps config in version control |
| Volumes | Named + external pre-created | `bootstrap.sh` runs before first deploy |

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `.github/workflows/build-images.yml` | Modified | `notify-dokploy` job: update secret name, payload, error handling |
| `docker-compose.prod.yml` | Unchanged | Already references GHCR images and Traefik labels |
| `scripts/bootstrap.sh` | Unchanged | Must run on VPS before first Dokploy deploy |
| GitHub secrets | New | `DOKPLOY_WEBHOOK_URL` replaces `DOKPLOY_WEBHOOK_URL` |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| External volumes missing | Medium | Run `bootstrap.sh` before first deploy |
| GHCR auth token expires | Low | Document renewal; use Dokploy registry test |
| Webhook URL rotation | Low | Store in GitHub secrets; update once if needed |
| Dokploy Traefik label conflict | Low | Labels are honored as-is by Dokploy |

## Rollback Plan

1. Stop the Dokploy Compose service in UI.
2. Re-run previous working image tags via Dokploy or `docker compose` manually.
3. Revert CI workflow change if webhook causes issues.

## Dependencies

- Dokploy server installed and accessible.
- GHCR images already pushed (existing CI pipeline).
- `scripts/bootstrap.sh` executed on VPS.

## Success Criteria

- [ ] Dokploy Compose service created with Raw source containing `docker-compose.prod.yml`.
- [ ] GHCR registry registered and test-pull succeeds.
- [ ] All 8 env vars set in Dokploy Environment tab.
- [ ] `notify-dokploy` CI job POSTs to Dokploy webhook and returns 2xx.
- [ ] Dokploy redeploys within 60s of webhook, pulling new images.
- [ ] All 4 services healthy after redeploy.
- [ ] `workspace_projects` data survives redeploy.
