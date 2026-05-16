# Version-Checking Bot Specification

## Purpose

Proactively detect outdated Docker base images and npm packages via Dependabot, opening PRs with appropriate merge policies.

## Requirements

### Requirement: Docker Dependency Scanning

The system MUST configure Dependabot to scan all `Dockerfile` base images and `docker-compose.yml` external images.

#### Scenario: Base image update available

- GIVEN `ubuntu:jammy` has a new digest
- WHEN Dependabot scans weekly
- THEN it opens a PR updating the `FROM` line
- AND labels it `docker`, `dependencies`

#### Scenario: Compose image update available

- GIVEN `codercom/code-server:4.97.2` has a new patch release
- WHEN Dependabot scans
- THEN it opens a PR updating the `image:` line in `docker-compose.yml`

### Requirement: npm Dependency Scanning

The system MUST configure Dependabot to scan `ARG` version pins for `opencode-ai` and `@neuralnomads/codenomad` in Dockerfiles.

#### Scenario: opencode-ai patch release

- GIVEN `opencode-ai@1.15.2` is released
- WHEN Dependabot scans
- THEN it opens a PR updating `ARG OPENCODE_VERSION` in `opencode/Dockerfile` and `codenomad/Dockerfile`

#### Scenario: CodeNomad minor release

- GIVEN `@neuralnomads/codenomad@0.17.0` is released
- WHEN Dependabot scans
- THEN it opens a PR updating `ARG CODENOMAD_VERSION` in `codenomad/Dockerfile`
- AND the PR requires manual review before merge

### Requirement: Update Schedule

The system MUST run Dependabot checks weekly on Mondays.

#### Scenario: Weekly scan

- GIVEN the schedule is set to `interval: weekly`
- WHEN Monday arrives
- THEN Dependabot scans all configured ecosystems
- AND opens PRs for any outdated dependencies

### Requirement: Auto-Merge for Patches

The system MUST auto-merge patch-level Dependabot PRs if CI passes.

#### Scenario: Patch PR passes CI

- GIVEN a patch-level Dependabot PR is opened
- WHEN all checks (build, validate, smoke) pass
- THEN the PR auto-merges
- AND the updated image is deployed via Dokploy webhook

#### Scenario: Patch PR fails CI

- GIVEN a patch-level Dependabot PR fails the build workflow
- WHEN CI completes with failures
- THEN auto-merge is blocked
- AND a maintainer receives a notification

### Requirement: Major/Minor PR Review

The system MUST require manual review for major and minor version bumps.

#### Scenario: Major version bump

- GIVEN a major version update PR is opened
- WHEN CI passes
- THEN the PR does NOT auto-merge
- AND it awaits explicit maintainer approval

### Requirement: Grouping Strategy

The system SHOULD group related npm updates across `opencode/Dockerfile` and `codenomad/Dockerfile` into a single PR.

#### Scenario: Related npm bumps

- GIVEN both `opencode-ai` and `@neuralnomads/codenomad` have patch updates
- WHEN Dependabot groups them
- THEN one PR updates both `ARG` values
- AND the PR description lists both packages

#### Scenario: Independent Docker bumps

- GIVEN `ubuntu:jammy` and `kasmweb/core-ubuntu-jammy` both have updates
- WHEN Dependabot scans
- THEN separate PRs are opened for each base image
- AND each PR is labeled independently
