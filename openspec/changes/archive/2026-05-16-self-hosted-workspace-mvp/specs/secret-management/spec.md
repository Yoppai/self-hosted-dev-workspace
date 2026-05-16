# Secret Management Specification

## Purpose

Define how secrets are injected, stored, and excluded from images and repository history.

## Requirements

### Requirement: No Secrets in Images

The system MUST NOT embed API keys, passwords, tokens, or certificates in any Docker image layer.

#### Scenario: Layer audit

- GIVEN a built image is inspected with `docker history`
- WHEN checking for secret patterns
- THEN no credentials are found in environment variables, labels, or layer commands

#### Scenario: Build-arg isolation

- GIVEN secrets are needed at build time
- WHEN the image is built
- THEN Docker BuildKit secret mounts or runtime injection are used
- AND secrets do not appear in the final image layers

### Requirement: No Secrets in Repository

The system MUST NOT commit secrets to version control.

#### Scenario: Repository scan

- GIVEN the repository is scanned for secrets
- WHEN checking `.env` files, config, and scripts
- THEN only placeholders or example values are present

### Requirement: Dokploy Environment Variables

The system MUST source service secrets from Dokploy environment variables at runtime.

#### Scenario: Runtime injection

- GIVEN Dokploy defines `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `OPENCODE_SERVER_PASSWORD`, and `CODENOMAD_SERVER_PASSWORD`
- WHEN containers start
- THEN the variables are available inside the container process

#### Scenario: Variable rotation

- GIVEN an API key is rotated in Dokploy
- WHEN the service restarts
- THEN the new value is used without code changes

### Requirement: Placeholder Template

The system MUST provide `.env.example` containing only placeholder values and comments, never real credentials.

#### Scenario: Onboarding clarity

- GIVEN a new clone of the repository
- WHEN `.env.example` is copied to `.env`
- THEN the user sees descriptive placeholders for every required secret
- AND no default secret values are present

### Requirement: Fail on Missing Secrets

The system SHOULD fail fast during startup if a required secret environment variable is missing.

#### Scenario: Missing API key

- GIVEN `ANTHROPIC_API_KEY` is not set
- WHEN the opencode container starts
- THEN it logs a clear error and exits with a non-zero code

### Requirement: Profile-Based Interactive Credentials

The system MAY store interactive OAuth tokens or Git credential helpers inside `workspace_profile` for containers that need them.

#### Scenario: Git HTTPS with token

- GIVEN a Git credential helper is configured
- WHEN the user clones over HTTPS
- THEN the token is cached in `workspace_profile`
- AND it is not written to the repository directory
