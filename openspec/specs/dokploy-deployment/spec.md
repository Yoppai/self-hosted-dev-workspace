# Dokploy Deployment Specification

## Purpose

Configure Dokploy to receive CI-built images from GHCR, deploy the workspace Compose stack, and trigger redeploys automatically via GitHub Actions webhooks.

## Requirements

### Requirement: Compose Service Configuration

The system MUST create a Dokploy Compose service using Raw YAML source containing `docker-compose.prod.yml`.

#### Scenario: Service creation

- GIVEN `docker-compose.prod.yml` is valid and references GHCR images
- WHEN an administrator pastes it into Dokploy's Raw Compose source field
- THEN Dokploy parses all four services, networks, and volumes
- AND the service status shows "Ready to deploy"

#### Scenario: Invalid YAML rejected

- GIVEN the YAML contains a syntax error
- WHEN it is submitted to Dokploy
- THEN Dokploy rejects it before any deployment starts
- AND no containers are created or started

### Requirement: GHCR Registry Authentication

The system MUST register GHCR in Dokploy with a token having `read:packages` scope.

#### Scenario: Successful test pull

- GIVEN a valid GHCR personal access token is saved in Dokploy Registry settings
- WHEN the administrator runs the registry test-pull action
- THEN Dokploy authenticates to `ghcr.io` and pulls `ghcr.io/yoppai/self-hosted-dev-workspace/opencode-server:latest`
- AND the test returns success

#### Scenario: Expired token

- GIVEN the registered token has expired or been revoked
- WHEN a redeploy attempts to pull images
- THEN the pull fails with an authentication error
- AND Dokploy surfaces the error in the deployment log

### Requirement: Environment and Secrets Management

The system MUST inject all required environment variables into the Compose service via Dokploy's Environment tab.

#### Scenario: All variables present

- GIVEN eight environment variables are defined in the Environment tab (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `CODE_SERVER_PASSWORD`, `OPENCODE_SERVER_USERNAME`, `OPENCODE_SERVER_PASSWORD`, `CODENOMAD_SERVER_USERNAME`, `CODENOMAD_SERVER_PASSWORD`, `KASMVNC_PASSWORD`)
- WHEN the Compose service deploys
- THEN every `${VAR:?err}` placeholder in `docker-compose.prod.yml` resolves
- AND no container exits due to missing required variables

#### Scenario: Missing required variable

- GIVEN one required variable is absent from the Environment tab
- WHEN Docker Compose attempts to start the affected service
- THEN the service fails immediately with a variable-not-set error
- AND dependent services do not start

### Requirement: Webhook Deployment Trigger

The system MUST accept a webhook POST from GitHub Actions to trigger a full service redeploy.

#### Scenario: Valid webhook triggers redeploy

- GIVEN the `notify-dokploy` CI job POSTs to the Dokploy Compose webhook URL
- WHEN the payload contains a valid trigger signal
- THEN Dokploy initiates a redeploy within 60 seconds
- AND the deployment log shows new image pulls

#### Scenario: Invalid webhook rejected

- GIVEN a POST arrives with an incorrect secret or malformed payload
- WHEN Dokploy validates the request
- THEN it returns a 4xx error
- AND no redeploy is initiated

### Requirement: Volume Bootstrap

The system MUST have three external volumes (`workspace_projects`, `workspace_profile`, `toolchains`) pre-created with UID 1000 ownership before the first deploy.

#### Scenario: Volumes ready before deploy

- GIVEN `scripts/bootstrap.sh` has been executed on the VPS
- WHEN the first Dokploy deploy runs
- THEN all `external: true` volumes exist
- AND containers mount them without permission errors

#### Scenario: Missing external volume

- GIVEN an external volume was not pre-created
- WHEN Dokploy deploys the stack
- THEN Docker Compose fails with a "volume not found" error
- AND the deployment halts

### Requirement: Domain and Traefik Routing

The system MUST route public HTTPS domains to containers using Traefik labels declared in `docker-compose.prod.yml`.

#### Scenario: Domain reaches service

- GIVEN a request to `https://code.workspace.yoppai.dev`
- WHEN Traefik processes it via the `code-server` router label
- THEN the request is forwarded to the `code-server` container on port 8080
- AND the TLS certificate is provisioned by `letsencrypt`

#### Scenario: Router label conflict

- GIVEN two services declare the same `Host()` rule
- WHEN Traefik loads the dynamic configuration
- THEN only one router is active
- AND the conflicting service logs a routing warning

### Requirement: Deployment Verification

The system MUST verify all four services report healthy after a redeploy completes.

#### Scenario: All services healthy

- GIVEN a redeploy has finished
- WHEN health checks run for `code-server`, `opencode-server`, `codenomad-server`, and `kasmvnc-workspace`
- THEN every service returns a passing health status within its `start_period`
- AND Dokploy marks the deployment as successful

#### Scenario: Service unhealthy after deploy

- GIVEN one service fails its health check after redeploy
- WHEN the `start_period` and `retries` elapse
- THEN Dokploy marks the container as unhealthy
- AND the deployment status reflects the failure

### Requirement: Rollback and Recovery

The system MUST support manual rollback by stopping the Compose service and reverting image tags.

#### Scenario: Manual rollback

- GIVEN a deployed service is running broken images tagged `latest`
- WHEN an administrator stops the service and reverts to a known-good `sha-{7}` tag
- THEN Dokploy restarts containers with the previous image
- AND `workspace_projects` data remains intact

#### Scenario: Failed deploy recovery

- GIVEN a deploy fails mid-pull due to network interruption
- WHEN the administrator re-triggers the webhook or clicks Redeploy
- THEN Dokploy resumes from the current state
- AND previously pulled layers are reused
