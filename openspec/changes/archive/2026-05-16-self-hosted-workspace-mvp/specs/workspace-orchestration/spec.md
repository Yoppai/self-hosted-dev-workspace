# Workspace Orchestration Specification

## Purpose

Define the Docker Compose service topology, internal networking, and Traefik HTTPS routing for all workspace applications.

## Requirements

### Requirement: Compose Service Definition

The system MUST define a single Docker Compose service containing `code-server`, `opencode`, CodeNomad, and KasmVNC containers.

#### Scenario: Full stack deploy

- GIVEN the Compose file is valid
- WHEN `docker compose up` runs on the target host
- THEN all four containers start in dependency order
- AND the internal network is created automatically

#### Scenario: ARM64 compatibility

- GIVEN the host platform is `linux/arm64`
- WHEN images are built or pulled
- THEN every image MUST have an ARM64 variant or build successfully via `docker compose build`

### Requirement: Internal Networking

The system MUST use Docker internal networks for inter-service communication. No service port SHALL be bound directly to the host public interface.

#### Scenario: Service-to-service resolution

- GIVEN all containers are on the same internal network
- WHEN one container resolves another by service name
- THEN DNS resolution succeeds within the Docker network

#### Scenario: No direct port exposure

- GIVEN the Compose file is inspected
- WHEN checking `ports` directives
- THEN no public-facing port bindings exist for any workspace service
- AND Traefik is the sole public ingress point

### Requirement: Traefik HTTPS Routing

The system MUST configure Traefik labels for each public application, routing unique subdomains to the correct internal container port with HTTPS termination.

#### Scenario: Routing correctness

- GIVEN Traefik is enabled in Dokploy
- WHEN a request arrives at a configured subdomain
- THEN Traefik routes it to the correct container and port
- AND the connection uses TLS 1.2 or higher

#### Scenario: Subdomain isolation

- GIVEN two different workspace subdomains
- WHEN requests are sent to each
- THEN traffic is routed to distinct containers without collision

### Requirement: Dokploy Integration

The system MUST be deployable as a Dokploy Compose service without manual host-level configuration.

#### Scenario: Deploy via Dokploy UI

- GIVEN the repository is linked to Dokploy
- WHEN the Compose service is deployed
- THEN Dokploy detects the Compose file and creates all resources
- AND service health is reported in the Dokploy dashboard
