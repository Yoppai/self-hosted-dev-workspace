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

The system MUST be deployable as a Dokploy Compose service and support automatic redeployment via webhook after CI image push.
(Previously: Manual Dokploy UI deploy only, no webhook or auto-redeploy)

#### Scenario: Deploy via Dokploy UI

- GIVEN the repository is linked to Dokploy
- WHEN the Compose service is deployed
- THEN Dokploy detects the Compose file and creates all resources
- AND service health is reported in the Dokploy dashboard

#### Scenario: Deploy via CI webhook

- GIVEN the CI workflow pushed new images to GHCR
- WHEN the webhook triggers
- THEN Dokploy redeploys the service automatically
- AND the new image is pulled and started

#### Scenario: Webhook URL missing

- GIVEN the `DOKPLOY_DEPLOY_WEBHOOK_URL` secret is not configured
- WHEN the CI workflow reaches the deploy step
- THEN the step is skipped
- AND the workflow succeeds with a warning annotation

### Requirement: Dokploy Webhook Deployment Trigger

The system MUST call the Dokploy deploy webhook after successfully pushing images to GHCR.

#### Scenario: Successful push triggers deploy

- GIVEN all images were pushed to GHCR with `latest` tags
- WHEN the workflow POSTs to `DOKPLOY_DEPLOY_WEBHOOK_URL`
- THEN Dokploy redeploys the Compose stack
- AND new images are pulled within 60 seconds

#### Scenario: Webhook failure is non-fatal

- GIVEN the Dokploy webhook URL is unreachable
- WHEN the POST request fails with HTTP 5xx
- THEN the CI workflow still succeeds
- AND a warning annotation is added to the workflow run

### Requirement: Compose Image References

The system SHOULD add `image:` references pointing to GHCR for CI-built services while keeping `build:` for local development.

#### Scenario: Dokploy deploy from GHCR

- GIVEN Dokploy receives a deploy webhook after GHCR push
- WHEN it reconciles the Compose file
- THEN it uses the `image:` reference to pull from GHCR
- AND ignores the `build:` section

#### Scenario: Local development build

- GIVEN a developer runs `docker compose build` locally
- WHEN the `image:` tag does not exist locally or in GHCR
- THEN Docker falls back to the `build:` context
- AND the image builds from local sources

#### Scenario: Rollback on deployment failure

- GIVEN Dokploy fails to pull a new image (e.g., GHCR auth error)
- WHEN the deployment health check fails
- THEN Dokploy keeps the previous running containers
- AND the failure is logged in the Dokploy dashboard
