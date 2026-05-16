# KasmVNC Workspace Specification

## Purpose

Define the custom KasmVNC desktop image and its runtime constraints for browser-based remote GUI access.

## Requirements

### Requirement: Image Derivation

The system SHOULD derive the KasmVNC image from the shared dev-base image, or document why a separate base is required.

#### Scenario: Tool overlay

- GIVEN the dev-base image provides Git, Node.js, Bun, and pnpm
- WHEN the KasmVNC image is built
- THEN the same tools are available inside the desktop session

### Requirement: Browser-Accessible Desktop

The system MUST expose a KasmVNC session reachable via HTTPS through the browser.

#### Scenario: Desktop login

- GIVEN the container is running
- WHEN a user opens the configured subdomain in a browser
- THEN the KasmVNC login page loads
- AND after valid credentials the desktop is interactive

### Requirement: Workspace Volume Access

The system MUST mount `workspace_projects` inside the desktop environment so GUI tools can browse and edit shared files.

#### Scenario: File manager access

- GIVEN files exist in `workspace_projects`
- WHEN the user opens the file manager inside KasmVNC
- THEN the workspace folder is visible and writable

### Requirement: Resource Limits

The system MUST limit the KasmVNC container to `4 GB` RAM to prevent host resource exhaustion.

#### Scenario: Memory enforcement

- GIVEN the container memory limit is set to `4 GB`
- WHEN desktop processes allocate memory
- THEN the container is throttled or OOM-killed instead of the host

### Requirement: UID Consistency

The system MUST run the KasmVNC session as UID `1000` so files created in the desktop match ownership of other services.

#### Scenario: Cross-service file creation

- GIVEN a file is created from KasmVNC
- WHEN `code-server` reads the same file
- THEN no permission errors occur

### Requirement: Internal Authentication

The system MUST enforce KasmVNC password authentication independently of Cloudflare Access.

#### Scenario: Defense in depth

- GIVEN a user passes Cloudflare Access
- WHEN they reach the KasmVNC endpoint
- THEN they must authenticate with the VNC password
