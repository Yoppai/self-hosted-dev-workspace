# kasmvnc/Dockerfile
# Self-Hosted Workspace MVP — KasmVNC Desktop Image
#
## Purpose
# Browser-accessible Linux desktop (via KasmVNC/noVNC) with dev tooling
# matching the dev-base image. UID 1000 for shared-volume compatibility.
#
## Why NOT derive from dev-base
# KasmVNC requires the VNC server, noVNC web proxy, window manager, and
# X11 infrastructure that kasmweb images provide. Building those from
# scratch on dev-base would be complex and fragile. Instead we overlay
# the same dev tools onto the official KasmVNC base.
#
## Build
#   docker build --platform linux/arm64 -t kasmvnc-workspace:latest ./kasmvnc
#
## Runtime dependencies
#   - KASMVNC_PASSWORD (Dokploy env var — required)
#   - workspace_projects, workspace_home, kasm_config volumes
FROM kasmweb/core-ubuntu-jammy:1.18.0

# ── Phase 0: Scrub upstream default passwords ────────────────────────────
# The kasmweb base image bakes VNC_PW=vncpassword and
# VNC_VIEW_ONLY_PW=vncviewonlypassword into its layers. Override both to
# empty so the derived image has no default password. The actual password
# is enforced at runtime via docker-compose environment (KASMVNC_PASSWORD).
ENV VNC_PW=
ENV VNC_VIEW_ONLY_PW=

# ── Phase 1: Install dev tools ─────────────────────────────────────────────
# Same toolchain as dev-base so the desktop has Git, Node.js, Bun, pnpm.
USER root
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
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# ── Phase 3: pnpm (via npm) ───────────────────────────────────────────────
RUN npm install -g pnpm

# ── Phase 4: Bun (official install script) ────────────────────────────────
ENV BUN_INSTALL=/usr/local
RUN curl -fsSL https://bun.sh/install | bash

# ── Phase 5: Verify tools installed correctly ──────────────────────────────
RUN git --version \
    && node --version \
    && npm --version \
    && pnpm --version \
    && bun --version

# ── Phase 6: Ensure non‑root UID 1000 ──────────────────────────────────────
# kasmweb images typically create user `kasm-user` with UID 1000.
# We confirm the UID and switch explicitly so volume ownership is consistent.
RUN id -u kasm-user 2>/dev/null | grep -q '^1000$' \
    || (echo "ERROR: expected kasm-user with UID 1000" && exit 1)

USER 1000:1000

# ── Phase 7: Runtime configuration ─────────────────────────────────────────
# Port 6901 = noVNC web UI (HTTPS). KasmVNC startup handles VNC + noVNC.
EXPOSE 6901

# PATH must include Bun's install dir and .local/bin for toolchains volume.
ENV PATH="/usr/local/bin:/home/kasm-user/.local/bin:${PATH}"

# ── Health check ──────────────────────────────────────────────────────────
# Verify KasmVNC is listening on port 6901 (TCP-level probe).
# We use `ss` instead of curl because KasmVNC blacklists 127.0.0.1 connections
# (localhost is rejected with "IP 127.0.0.1 is blacklisted, dropping").
# `ss` is available in the base Ubuntu image via iproute2.
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
  CMD ["bash", "-c", "ss -tlnp | grep -q ':6901' || exit 1"]

# NOTE: No CMD/ENTRYPOINT override — the kasmweb base image provides its own
# startup that initialises VNC, noVNC, and the desktop environment.
# VNC_PW is read from the environment (set in docker-compose.yml).
