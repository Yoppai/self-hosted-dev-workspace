# dev-base/Dockerfile
# Self-Hosted Workspace MVP — Shared ARM64 Base Image
#
## Purpose
# Single base image with common tooling for all workspace services.
# All containers FROM this image inherit Node.js, Bun, pnpm, Git,
# and run as UID 1000 for shared-volume compatibility.
#
## Build
#   docker build --platform linux/arm64 -t dev-base:latest ./dev-base
#
## Platform
# NOTE: Do NOT hardcode --platform in FROM. Pass --platform linux/arm64
# at build time so the same Dockerfile works for multi-arch builders and
# avoids the FromPlatformFlagConstDisallowed warning.
FROM ubuntu:jammy

ARG TARGETARCH

# ── Phase 1: System dependencies ──────────────────────────────────────────
# Keep apt layers stable; install only what every service needs.
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    gnupg \
    lsb-release \
    sudo \
    tzdata \
    unzip \
    zsh \
    && rm -rf /var/lib/apt/lists/*

# ── Phase 2: Node.js LTS (NodeSource) ─────────────────────────────────────
# Official NodeSource repo for Jammy; provides node + npm.
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# ── Phase 3: pnpm (via npm) ───────────────────────────────────────────────
RUN npm install -g pnpm

# ── Phase 4: Bun (official install script) ────────────────────────────────
# BUN_INSTALL=/usr/local puts the binary in /usr/local/bin.
ENV BUN_INSTALL=/usr/local
RUN curl -fsSL https://bun.sh/install | bash

# ── Phase 5: Non-root user (UID 1000) ─────────────────────────────────────
# All workspace services share UID 1000 to avoid chown on volumes.
RUN groupadd --gid 1000 workspace \
    && useradd --uid 1000 --gid workspace --shell /bin/bash --create-home workspace \
    && echo "workspace ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/workspace

USER workspace
WORKDIR /home/workspace

# ── Phase 6: Ensure .local/bin is on PATH ─────────────────────────────────
# Service images need /home/workspace/.local/bin (mounted from the toolchains
# volume) for user-installed binaries. Setting this in dev-base guarantees
# consistency across all derived images without each one remembering to add it.
ENV PATH="/home/workspace/.local/bin:${PATH}"

# ── Health check: verify all tools are on PATH ────────────────────────────
RUN git --version \
    && node --version \
    && npm --version \
    && pnpm --version \
    && bun --version

# Default command: keep alive for Compose health checks
CMD ["sleep", "infinity"]
