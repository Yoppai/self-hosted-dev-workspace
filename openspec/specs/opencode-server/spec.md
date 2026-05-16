# Opencode Server Specification

## Purpose

Define the custom opencode server image and its runtime behavior for AI coding assistance.

## Requirements

### Requirement: Image Derivation

The system MUST build the opencode server image `FROM` the shared dev-base image.

#### Scenario: Layer reuse

- GIVEN the dev-base image exists
- WHEN the opencode image is built
- THEN it reuses base layers without reinstalling Node.js, Bun, or Git

### Requirement: Server Mode

The system MUST run opencode in server mode, exposing port `4096` internally.

#### Scenario: Server startup

- GIVEN the container starts
- WHEN the opencode process initializes
- THEN it binds to port `4096` inside the container
- AND it responds to HTTP health requests

#### Scenario: Internal auth

- GIVEN the server is running
- WHEN unauthenticated requests arrive
- THEN they are rejected or redirected to authentication

### Requirement: Configuration Persistence

The system MUST mount `opencode_config` and `workspace_projects` volumes so global config, skills, agents, MCP settings, and project files persist.

#### Scenario: Config survives restart

- GIVEN opencode skills have been installed
- WHEN the container restarts
- THEN the skills remain available without reinstallation

#### Scenario: Project access

- GIVEN a project exists in `workspace_projects`
- WHEN opencode opens the project folder
- THEN files are readable and writable

### Requirement: Environment-Driven Secrets

The system MUST accept AI provider credentials via environment variables injected by Dokploy, not from image or repository.

#### Scenario: API key injection

- GIVEN Dokploy sets `ANTHROPIC_API_KEY`
- WHEN opencode makes an LLM request
- THEN the key is available to the process
- AND it is not present in the built image
