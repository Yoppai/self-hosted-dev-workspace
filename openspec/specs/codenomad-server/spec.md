# CodeNomad Server Specification

## Purpose

Define the custom CodeNomad server image with opencode CLI integration and session persistence.

## Requirements

### Requirement: Image Derivation

The system MUST build the CodeNomad image `FROM` the shared dev-base image.

#### Scenario: Layer reuse

- GIVEN the dev-base image exists
- WHEN the CodeNomad image is built
- THEN it reuses base layers and adds only CodeNomad-specific dependencies

### Requirement: Opencode CLI in PATH

The system MUST ensure the `opencode` binary is discoverable in the container `PATH`.

#### Scenario: CLI invocation

- GIVEN a running CodeNomad container
- WHEN CodeNomad executes an opencode subprocess
- THEN the binary resolves without an absolute path

#### Scenario: Version coupling

- GIVEN pinned versions for both CodeNomad and opencode
- WHEN either version is bumped
- THEN the integration is tested together before deploy

### Requirement: Session Persistence

The system MUST mount `codenomad_config` and `workspace_projects` so chat history, instances, and sessions survive restarts.

#### Scenario: Session resume

- GIVEN an active CodeNomad chat session exists
- WHEN the container restarts
- THEN the session list is restored on next login

#### Scenario: Workspace file access

- GIVEN files exist in `workspace_projects`
- WHEN CodeNomad opens or edits them
- THEN changes are written and visible to other services

### Requirement: Port Exposure

The system MUST expose ports `9898` (HTTPS) and `9899` (HTTP) internally for CodeNomad traffic.

#### Scenario: Routing via Traefik

- GIVEN Traefik routes to the CodeNomad container
- WHEN HTTPS traffic arrives at the configured subdomain
- THEN CodeNomad serves the cockpit UI securely

### Requirement: Internal Authentication

The system MUST require CodeNomad's own user/password login even after Cloudflare Access.

#### Scenario: Defense in depth

- GIVEN a user passes Cloudflare Access
- WHEN they reach the CodeNomad subdomain
- THEN they must authenticate with CodeNomad credentials
