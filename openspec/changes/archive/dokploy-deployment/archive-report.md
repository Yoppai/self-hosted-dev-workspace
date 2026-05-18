# Archive Report: Dokploy Deployment Pipeline

**Change**: dokploy-deployment
**Archived**: 2026-05-16
**Archive Path**: `openspec/changes/archive/dokploy-deployment/`
**Artifact Mode**: hybrid

## Summary

The `dokploy-deployment` change connected the existing CI-built GHCR images to Dokploy by configuring a Raw Compose service, GHCR registry auth, env vars, and a webhook redeploy trigger. The CI `notify-dokploy` job was updated to POST to the Dokploy Compose webhook URL.

## Specs Synced

| Domain | Action | Details |
|--------|--------|---------|
| `dokploy-deployment` | Created (new domain) | 8 requirements, 16 scenarios — full spec copied to `openspec/specs/dokploy-deployment/spec.md` |
| `ci-cd-pipeline` | Updated (delta appended) | +1 requirement (Dokploy Deploy Trigger), 3 scenarios appended to `openspec/specs/ci-cd-pipeline/spec.md` |

## Archive Contents

| Artifact | Status |
|----------|--------|
| exploration.md | ✅ |
| proposal.md | ✅ |
| spec (dokploy-deployment) | ✅ |
| spec (ci-cd-pipeline delta) | ✅ |
| design.md | ✅ |
| tasks.md | ✅ (6/8 complete; 2 deferred to live env) |
| apply-progress.md | ✅ |
| verify-report.md | ✅ (PASS verdict) |

## Engram Observations (for traceability)

| Topic Key | Observation ID |
|-----------|---------------|
| `sdd/dokploy-deployment/explore` | #1102 |
| `sdd/dokploy-deployment/proposal` | #1103 |
| `sdd/dokploy-deployment/spec` | #1104 |
| `sdd/dokploy-deployment/design` | #1105 |
| `sdd/dokploy-deployment/tasks` | #1106 |
| `sdd/dokploy-deployment/apply-progress` | #1107 |
| `sdd/dokploy-deployment/verify-report` | #1108 |
| `sdd/dokploy-deployment/archive-report` | (this report) |

## Volume State Notes

- **3 external volumes** (`workspace_projects`, `workspace_profile`, `toolchains`) must be pre-created via `scripts/bootstrap.sh` with UID 1000 before first Dokploy deploy.
- **6 auto-created volumes** (workspace_home, opencode_config, codenomad_config, code_server_config, kasm_config, package_caches) are created by Docker Compose on first deploy.
- No volume migration was required — this is a greenfield Dokploy deployment configuration.

## Open Items

- Tasks 3.2 and 3.3 (E2E webhook + redeploy verification) are deferred to manual post-merge validation against the live Dokploy instance.
- Two design open questions remain: confirm Dokploy's `letsencrypt` cert resolver name, and verify Compose webhook URL format.

## SDD Cycle Complete

| Phase | Status |
|-------|--------|
| Explore | ✅ |
| Propose | ✅ |
| Spec | ✅ |
| Design | ✅ |
| Tasks | ✅ |
| Apply | ✅ (6/8 tasks) |
| Verify | ✅ (PASS) |
| Archive | ✅ (this report) |
