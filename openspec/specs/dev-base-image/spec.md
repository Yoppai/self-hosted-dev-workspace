# Dev Base Image Specification

## Purpose

Provide a shared ARM64 base image containing common development tooling used by all workspace services.

## Requirements

### Requirement: Target Platform

The system MUST produce an image that builds and runs on `linux/arm64`.

#### Scenario: Build on ARM64

- GIVEN a Docker builder with ARM64 support
- WHEN the base image is built
- THEN the build completes without architecture-specific errors

#### Scenario: Derived images inherit platform

- GIVEN a service image that `FROM` the base image
- WHEN it is built for `linux/arm64`
- THEN the build succeeds without reinstalling base toolchains

### Requirement: Base Tooling

The system MUST include Git, Node.js (LTS), Bun, pnpm, and common shells (bash, zsh).

#### Scenario: Tool availability

- GIVEN a container running from the base image
- WHEN the user invokes `git`, `node`, `bun`, or `pnpm`
- THEN each command returns its version and is available in `PATH`

#### Scenario: Shell selection

- GIVEN an interactive session in the container
- WHEN the user runs `bash` or `zsh`
- THEN both shells start successfully

### Requirement: Non-Root User

The system MUST create a non-root user with UID `1000` and GID `1000`.

#### Scenario: User ownership

- GIVEN a fresh container from the base image
- WHEN files are created under the non-root user
- THEN they are owned by `1000:1000`

#### Scenario: Volume write access

- GIVEN a named volume mounted into the container
- WHEN the non-root user writes to the mount
- THEN the write succeeds without runtime `chown` fixes

### Requirement: No Secrets in Image

The system MUST NOT embed API keys, passwords, or tokens in the base image layers.

#### Scenario: Image inspection

- GIVEN the built image layers
- WHEN scanning for common secret patterns
- THEN no matches are found
