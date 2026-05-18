# CI/CD Pipeline Specification

## Purpose

Automate ARM64 Docker image builds, tagging, caching, and GHCR push for all workspace images via GitHub Actions.

## Requirements

### Requirement: Self-Hosted Runner Registration

The system MUST register an ARM64 GitHub Actions self-hosted runner on the Oracle Cloud VPS.

#### Scenario: Runner online

- GIVEN the runner container is deployed with Docker socket binding
- WHEN the runner starts
- THEN it connects to GitHub and appears in the repository's runner list
- AND it accepts CI jobs within 60 seconds

#### Scenario: Runner auto-restart

- GIVEN the runner container is configured with `restart: unless-stopped`
- WHEN the VPS reboots
- THEN the runner container restarts automatically
- AND re-registers with GitHub if needed

### Requirement: Build Ordering

The system MUST build images in dependency order: `dev-base` before `opencode` and `codenomad`; `kasmvnc` independent.

#### Scenario: Push to main

- GIVEN a commit is pushed to `main`
- WHEN the workflow runs
- THEN `dev-base` and `kasmvnc` build in parallel
- AND `opencode` and `codenomad` build only after `dev-base` succeeds

#### Scenario: PR with changed files

- GIVEN a PR modifies only `opencode/Dockerfile`
- WHEN the workflow runs
- THEN only `dev-base`, `opencode`, and `codenomad` build
- AND `kasmvnc` is skipped

### Requirement: GHCR Push and Tagging

The system MUST push all images to GHCR with `latest`, `sha-{7}`, and version tags.

#### Scenario: Main branch push

- GIVEN a successful build on `main`
- WHEN the push job runs
- THEN each image receives `latest` and `sha-{7}` tags
- AND npm-pinned images receive a `{package}-{version}` tag

#### Scenario: Version tag collision

- GIVEN a version tag already exists in GHCR
- WHEN the workflow pushes the same tag
- THEN the new image overwrites the existing tag

### Requirement: Build Triggers

The system MUST support `push:main`, `pull_request`, `workflow_dispatch`, and weekly `schedule` triggers.

#### Scenario: Manual rebuild

- GIVEN a maintainer triggers `workflow_dispatch`
- WHEN selecting "Rebuild all images (no cache)"
- THEN the workflow runs with cache disabled
- AND all images rebuild from scratch

#### Scenario: Weekly no-cache rebuild

- GIVEN the weekly cron trigger fires
- WHEN the scheduled workflow runs
- THEN it builds all images with `no-cache`
- AND pushes updated `latest` tags

### Requirement: Layer Caching

The system MUST use `type=gha` BuildKit cache with `mode=max` for all image builds.

#### Scenario: Cached child build

- GIVEN `dev-base` layers are unchanged
- WHEN `opencode` builds
- THEN `dev-base` layers are fetched from cache
- AND `opencode` build completes in under 60 seconds

### Requirement: Build Failure Notifications

The system MUST post a workflow status notification when any build job fails.

#### Scenario: dev-base build failure

- GIVEN `dev-base` build fails
- WHEN the workflow completes
- THEN a failure notification is posted
- AND downstream jobs (`opencode`, `codenomad`) do not run

### Requirement: ARM64 Validation

The system MUST reuse `scripts/arm64-validate.sh` to verify every image is `linux/arm64`.

#### Scenario: Post-build validation

- GIVEN all images built successfully
- WHEN the validation step runs
- THEN `arm64-validate.sh` executes against each image
- AND any image without `arm64` architecture fails the workflow

### Requirement: Smoke Tests

The system MUST reuse `scripts/smoke-test.sh --build-only` after successful builds.

#### Scenario: Smoke test pass

- GIVEN all images built and validated
- WHEN `smoke-test.sh --build-only` runs in CI
- THEN it completes with exit code 0
- AND the workflow proceeds to push

#### Scenario: Smoke test failure

- GIVEN a child image has a runtime error
- WHEN smoke tests run
- THEN the workflow fails before pushing to GHCR

### Requirement: Dokploy Deploy Trigger

The system MUST send a webhook POST to Dokploy's Compose service webhook URL after images are successfully pushed to GHCR.

#### Scenario: Successful deploy notification

- GIVEN the `push-images` job completed successfully on `main`
- WHEN the `notify-dokploy` job runs
- THEN it POSTs to `secrets.DOKPLOY_WEBHOOK_URL`
- AND the payload includes repository, SHA, and ref
- AND the job returns success on HTTP 2xx

#### Scenario: Webhook URL not configured

- GIVEN `DOKPLOY_WEBHOOK_URL` is unset
- WHEN the `notify-dokploy` job runs
- THEN it logs a warning and exits cleanly
- AND the workflow does not fail

#### Scenario: Webhook failure

- GIVEN the webhook URL is configured but Dokploy returns 4xx or 5xx
- WHEN the POST executes
- THEN the job logs a non-fatal warning with the HTTP status
- AND the workflow continues (images are already in GHCR)
