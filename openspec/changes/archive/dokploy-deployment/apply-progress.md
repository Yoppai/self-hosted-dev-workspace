# Apply Progress: Dokploy Deployment Pipeline

**Change**: dokploy-deployment
**Mode**: Standard (Strict TDD not active — no test framework)
**Delivery**: auto-chain (single PR, ~70 estimated changed lines)

---

## Completed Tasks

### Phase 1: CI Pipeline Changes
- [x] 1.1 Rename secret reference from `secrets.DOKPLOY_WEBHOOK_URL` to `secrets.DOKPLOY_WEBHOOK_URL`
- [x] 1.2 Remove `DOKPLOY_WEBHOOK_SECRET` env var and conditional header from the `curl` command
- [x] 1.3 Update webhook payload to `{"repository":"...","sha":"...","ref":"..."}` with `github.repository`, `github.sha`, `github.ref`
- [x] 1.4 Preserve `continue-on-error: true` and warn-on-failure behavior (HTTP non-2xx logs warning, workflow does not fail)

### Phase 2: Documentation
- [x] 2.1 Add Dokploy deployment guide to `docs/deploy-dokploy.md` covering: Compose raw source setup, GHCR registry auth, environment variables, webhook URL source
- [x] 2.2 Document required GitHub repository secrets (`DOKPLOY_WEBHOOK_URL`) and where to obtain it (Dokploy UI → Service → Webhook)

### Phase 3: Verification
- [x] 3.1 Validate updated `.github/workflows/build-images.yml` syntax with YAML parser (`python yaml.safe_load`) — passes
- [ ] 3.2 Trigger a test push to main (or workflow_dispatch) and verify `notify-dokploy` job POSTs to Dokploy and receives HTTP 2xx — requires live CI + Dokploy environment
- [ ] 3.3 Confirm Dokploy redeploy initiates within 60 seconds and all four services report healthy — requires live environment

---

## Files Changed

| File | Action | Description |
|------|--------|-------------|
| `.github/workflows/build-images.yml` | Modified | Updated `notify-dokploy` job: renamed secret to `DOKPLOY_WEBHOOK_URL`, removed `DOKPLOY_WEBHOOK_SECRET`, simplified payload, preserved `continue-on-error` |
| `.github/README.md` | Modified | Updated Required GitHub Secrets table: replaced `DOKPLOY_WEBHOOK_URL` + `DOKPLOY_WEBHOOK_SECRET` with `DOKPLOY_WEBHOOK_URL`; updated troubleshooting |
| `docs/deploy-dokploy.md` | Created | Full Dokploy deployment guide covering project creation, GHCR registry setup, Compose raw source, env vars, webhook config, volume pre-creation, rollback, troubleshooting |

## Files NOT Modified (reference-only, per design)

- `docker-compose.prod.yml` — already Dokploy-compatible
- `scripts/bootstrap.sh` — already correct

---

## Deviations from Design

None — implementation matches design exactly.

## Issues Found

None.

## Remaining Tasks

- [ ] 3.2 Trigger a test push to main (or workflow_dispatch) and verify `notify-dokploy` job POSTs to Dokploy and receives HTTP 2xx
- [ ] 3.3 Confirm Dokploy redeploy initiates within 60 seconds and all four services report healthy

> Tasks 3.2 and 3.3 require a live CI execution against a running Dokploy instance. They cannot be completed in the apply phase — they are E2E verification tasks for the verify phase or manual post-merge validation.

## Workload / PR Boundary

- **Mode**: single PR (auto-chain)
- **Current work unit**: Unit 1 — Update CI webhook + docs
- **Boundary**: complete change (CI job + docs)
- **Estimated review budget**: ~70 changed lines (well under 400)

## Status

6/8 tasks complete. Blocking: 3.2 and 3.3 require live environment — verify-ready for the rest.
