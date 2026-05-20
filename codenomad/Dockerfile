# codenomad/Dockerfile
# Self-Hosted Workspace MVP — CodeNomad Server Image
#
## Purpose
# Custom CodeNomad server image built on dev-base.
# Provides a web cockpit for AI coding with opencode CLI integration.
# Session state persists via codenomad_config volume.
#
## Build (after dev-base:latest exists)
#   docker build --platform linux/arm64 -t codenomad-server:latest ./codenomad
#
## Runtime dependencies
#   - dev-base:latest (build dependency — build first)
#   - ANTHROPIC_API_KEY, OPENAI_API_KEY (Dokploy env vars)
#   - CODENOMAD_SERVER_USERNAME, CODENOMAD_SERVER_PASSWORD (Dokploy env vars for auth)
FROM dev-base:latest

# ── Phase 1: Install dependencies ──────────────────────────────────────────
# CodeNomad needs the opencode CLI in PATH (npm global puts it in /usr/local/bin).
# Both are pinned via ARG for version coupling (tested together before deploy).
ARG OPENCODE_VERSION=1.15.5
ARG CODENOMAD_VERSION=0.16.0

# Switch to root for global package install (dev-base ends as USER workspace)
USER root
RUN npm install -g "opencode-ai@${OPENCODE_VERSION}" "@neuralnomads/codenomad@${CODENOMAD_VERSION}" \
    && npm cache clean --force

# Return to workspace user for runtime
USER workspace
WORKDIR /home/workspace

# ── Phase 2: Verify CLI availability ──────────────────────────────────────
# Ensure opencode is on PATH per spec requirement.
RUN opencode --version && codenomad --version

# ── Phase 3: Runtime configuration ────────────────────────────────────────
EXPOSE 9898 9899

ENV XDG_CONFIG_HOME=/home/workspace/.config

# ── PATH for shared toolchains ────────────────────────────────────────────
# The toolchains volume mounts at /home/workspace/.local.
# This PATH entry makes user-installed binaries discoverable at runtime.
ENV PATH="/home/workspace/.local/bin:${PATH}"

# ── Health check ──────────────────────────────────────────────────────────
# Verify CodeNomad responds on its HTTPS port (9898).
# Traefik routes to CodeNomad HTTPS directly; health check uses curl -sk.
HEALTHCHECK --interval=30s --timeout=10s --start-period=20s --retries=3 \
  CMD curl -sk -o /dev/null -w '%{http_code}' https://localhost:9898/ | grep -qE '^[23]' || exit 1

# ── Entrypoint ────────────────────────────────────────────────────────────
# Start CodeNomad server on HTTPS port 9898.
# Traefik routes directly to CodeNomad HTTPS, with TLS termination at edge.
# CODENOMAD_SERVER_USERNAME and CODENOMAD_SERVER_PASSWORD env vars handle auth.
CMD ["codenomad", "server", "--https-port", "9898", "--host", "0.0.0.0"]
