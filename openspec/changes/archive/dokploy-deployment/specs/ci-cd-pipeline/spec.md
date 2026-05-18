# Delta for CI/CD Pipeline

## ADDED Requirements

### Requirement: Dokploy Deploy Trigger

The system MUST send a webhook POST to Dokploy's Compose service webhook URL after images are successfully pushed to GHCR.

#### Scenario: Successful deploy notification

- GIVEN the `push-images` job completed successfully on `main`
- WHEN the `notify-dokploy` job runs
- THEN it POSTs to `secrets.DOKPLOY_WEBHOOK_URL`
- AND the payload includes repository, SHA, and ref
- AND the job returns success on HTTP 2xx

#### Scenario: Webhook URL not configured

- GIVEN `DOKPLOY_WEBHOOK_URL` is unset
- WHEN the `notify-dokploy` job runs
- THEN it logs a warning and exits cleanly
- AND the workflow does not fail

#### Scenario: Webhook failure

- GIVEN the webhook URL is configured but Dokploy returns 4xx or 5xx
- WHEN the POST executes
- THEN the job logs a non-fatal warning with the HTTP status
- AND the workflow continues (images are already in GHCR)

## MODIFIED Requirements

None.

## REMOVED Requirements

None.
