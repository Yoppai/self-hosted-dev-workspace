# Tasks: Dokploy Deployment Pipeline

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | ~60–90 (CI job + docs) |
| 400-line budget risk | Low |
| Chained PRs recommended | No |
| Suggested split | Single PR |
| Delivery strategy | auto-chain |
| Chain strategy | stacked-to-main |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: stacked-to-main
400-line budget risk: Low

### Suggested Work Units

| Unit | Goal | Likely PR | Notes |
|------|------|-----------|-------|
| 1 | Update CI webhook + docs | PR 1 | Targets main; includes verification steps |

## Phase 1: CI Pipeline Changes

- [x] 1.1 Rename secret reference in `notify-dokploy` job from `secrets.DOKPLOY_WEBHOOK_URL` to `secrets.DOKPLOY_WEBHOOK_URL`
- [x] 1.2 Remove `DOKPLOY_WEBHOOK_SECRET` env var and conditional header from the `curl` command
- [x] 1.3 Update webhook payload to `{"repository":"...","sha":"...","ref":"..."}` with `github.repository`, `github.sha`, `github.ref`
- [x] 1.4 Preserve `continue-on-error: true` and warn-on-failure behavior (HTTP non-2xx logs warning, workflow does not fail)

## Phase 2: Documentation

- [x] 2.1 Add Dokploy deployment guide to `docs/deploy-dokploy.md` covering: Compose raw source setup, GHCR registry auth, environment variables, webhook URL source
- [x] 2.2 Document required GitHub repository secrets (`DOKPLOY_WEBHOOK_URL`) and where to obtain it (Dokploy UI → Service → Webhook)

## Phase 3: Verification

- [x] 3.1 Validate updated `.github/workflows/build-images.yml` syntax with `actionlint` or `gh workflow run` dry-run
- [ ] 3.2 Trigger a test push to main (or workflow_dispatch) and verify `notify-dokploy` job POSTs to Dokploy and receives HTTP 2xx
- [ ] 3.3 Confirm Dokploy redeploy initiates within 60 seconds and all four services report healthy
