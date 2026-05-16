# Volume Persistence Specification

## Purpose

Define the shared and private volume strategy that lets services share project data and persist configuration without state collisions.

## Requirements

### Requirement: Named Volume Set

The system MUST create the following named volumes:

| Volume | Shared by | Purpose |
|---|---|---|
| `workspace_projects` | All dev services | Repositories and working files |
| `workspace_profile` | Services needing shared identity | `~/.config`, `~/.gentle-ai`, `~/.agents`, `~/.local`, `~/.ssh` |
| `workspace_home` | CLI-oriented and desktop services | Persistent home directory for interactive sessions |
| `opencode_config` | `opencode`, CodeNomad | Global opencode config, skills, agents, MCP |
| `codenomad_config` | CodeNomad | Sessions, chat history, instances |
| `code_server_config` | `code-server` | VS Code settings and extensions |
| `kasm_config` | KasmVNC | VNC settings and desktop state |
| `package_caches` | Build/CLI containers | Optional npm/pnpm/bun caches |
| `toolchains` | Compatible CLI services | User-installed toolchains in versionable paths |

#### Scenario: Volume creation on deploy

- GIVEN the Compose service is first deployed
- WHEN Dokploy provisions resources
- THEN all named volumes are created automatically

### Requirement: UID/GID Standardization

The system MUST standardize all containers that write to shared volumes to run as UID `1000` and GID `1000`.

#### Scenario: Shared write access

- GIVEN `code-server` creates a file in `workspace_projects`
- WHEN `opencode` writes to the same directory
- THEN both operations succeed without `chown` fixes

#### Scenario: UID mismatch prevention

- GIVEN a container attempts to run as a different UID
- WHEN it mounts a shared volume
- THEN the deployment configuration is rejected or corrected

### Requirement: Separation of Concerns

The system MUST NOT mix project data and tool configuration in a single undifferentiated volume.

#### Scenario: Isolated config corruption

- GIVEN a tool configuration volume becomes corrupted
- WHEN only that volume is recreated
- THEN project files in `workspace_projects` remain intact

### Requirement: Persistence Across Redeploy

The system MUST ensure that redeploying the Compose service does not destroy or recreate named volumes containing user data.

#### Scenario: Redeploy safety

- GIVEN the service is redeployed via Dokploy
- WHEN the deployment completes
- THEN project files, extensions, skills, and settings remain available

### Requirement: Shared PATH for Toolchains

The system MUST declare a consistent `PATH` across containers that mount `workspace_profile` and `toolchains` so user-installed binaries are discoverable.

#### Scenario: Custom CLI usage

- GIVEN a user installs a tool to `~/.local/bin`
- WHEN they open a terminal in any compatible service
- THEN the tool is executable without absolute path
