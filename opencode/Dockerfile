# opencode/Dockerfile
# Self-Hosted Workspace MVP — Opencode Server Image
#
## Purpose
# Custom opencode server image built on dev-base.
# Runs opencode in server mode on port 4096 for AI coding assistance.
# Configuration persists via opencode_config and workspace_profiles volumes.
#
## Build (after dev-base:latest exists)
#   docker build --platform linux/arm64 -t opencode-server:latest ./opencode
#
## Runtime dependencies
#   - dev-base:latest (build dependency — build first)
#   - ANTHROPIC_API_KEY, OPENAI_API_KEY (Dokploy env vars)
#   - OPENCODE_SERVER_PASSWORD (Dokploy env var for internal auth)
FROM dev-base:latest

# ── Phase 1: Install opencode ──────────────────────────────────────────────
# Global npm install pins the opencode server CLI.
# ARG allows version pinning at build time (default: latest).
ARG OPENCODE_VERSION=1.15.1

# Switch to root for global package install (dev-base ends as USER workspace)
USER root
RUN npm install -g "opencode-ai@${OPENCODE_VERSION}" \
    && npm cache clean --force

# Return to workspace user for runtime
USER workspace
WORKDIR /home/workspace

# ── Phase 2: Runtime configuration ─────────────────────────────────────────
EXPOSE 4096

# opencode reads config from XDG_CONFIG_HOME or ~/.config/opencode
# The opencode_config volume mounts at this path.
ENV XDG_CONFIG_HOME=/home/workspace/.config

# ── PATH for shared toolchains ────────────────────────────────────────────
# The toolchains volume mounts at /home/workspace/.local.
# This PATH entry makes user-installed binaries discoverable at runtime.
ENV PATH="/home/workspace/.local/bin:${PATH}"

# ── Health check ──────────────────────────────────────────────────────────
# Verify opencode server responds on its HTTP port.
# When OPENCODE_SERVER_PASSWORD is set, /global/health requires HTTP Basic
# auth. The curl command reads OPENCODE_SERVER_USERNAME (default: opencode)
# and OPENCODE_SERVER_PASSWORD from the environment at runtime — no secrets
# are baked into the image layer.
# Requires curl (installed in dev-base).
HEALTHCHECK --interval=30s --timeout=10s --start-period=20s --retries=3 \
  CMD curl -sf -u "${OPENCODE_SERVER_USERNAME:-opencode}:${OPENCODE_SERVER_PASSWORD}" http://localhost:4096/global/health || exit 1

# ── Entrypoint ────────────────────────────────────────────────────────────
# Start opencode in server mode.
# OPENCODE_SERVER_PASSWORD is injected by Dokploy at runtime.
# The server binds to all interfaces inside the container so Traefik can
# route to it from the Dokploy network.
CMD ["opencode", "serve", "--port", "4096", "--hostname", "0.0.0.0"]
