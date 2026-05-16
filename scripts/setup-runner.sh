#!/usr/bin/env bash
# setup-runner.sh — Self-Hosted Workspace MVP
# ============================================
# One-time GitHub Actions self-hosted runner registration for ARM64 VPS.
# Installs the runner, configures it as a systemd service with auto-restart,
# and registers it with the repository.
#
# Usage:
#   export GITHUB_PAT="ghp_..."
#   sudo ./scripts/setup-runner.sh
#
# Prerequisites:
#   - GitHub Personal Access Token with `repo` and `admin:org` scopes
#   - The GITHUB_PAT environment variable must be set
#   - Run as root (sudo)
#   - curl and jq installed
#
# Design:
#   - Idempotent: safe to re-run if the runner already exists
#   - Detects ARM64 architecture and downloads the matching runner binary
#   - Configures the runner as a systemd service with restart: always
#   - Runner runs as a dedicated `gh-runner` user (created if missing)
#
# Exit codes:
#   0 = runner registered and service started
#   1 = missing prerequisites
#   2 = configuration or registration failure

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────
REPO_URL="https://github.com/Yoppai/self-hosted-dev-workspace"
RUNNER_USER="gh-runner"
RUNNER_DIR="/opt/actions-runner"
SERVICE_NAME="actions.runner.Yoppai-self-hosted-dev-workspace"

GITHUB_PAT="${GITHUB_PAT:-}"

# ── Helpers ────────────────────────────────────────────────────────────────
info()  { printf "  \033[1;34m→\033[0m %s\n" "$*"; }
ok()    { printf "  \033[1;32m✓\033[0m %s\n" "$*"; }
warn()  { printf "  \033[1;33m!\033[0m %s\n" "$*" >&2; }
fail()  { printf "  \033[1;31m✗\033[0m %s\n" "$*" >&2; exit "${2:-1}"; }

require_command() {
    if ! command -v "$1" &>/dev/null; then
        fail "Required command not found: $1"
    fi
}

# ── Prerequisite checks ────────────────────────────────────────────────────
echo ""
echo "  ╔══════════════════════════════════════════════════╗"
echo "  ║  GitHub Actions Self-Hosted Runner Setup        ║"
echo "  ╚══════════════════════════════════════════════════╝"
echo ""

if [[ $EUID -ne 0 ]]; then
    fail "This script must be run as root (sudo)." 1
fi

if [[ -z "$GITHUB_PAT" ]]; then
    fail "GITHUB_PAT environment variable is not set." 1
fi

require_command curl
require_command jq

HOST_ARCH="$(uname -m)"
info "Host architecture: ${HOST_ARCH}"

# ── Determine runner package URL ──────────────────────────────────────────
case "$HOST_ARCH" in
    aarch64|arm64)
        RUNNER_PKG="actions-runner-linux-arm64-2.322.0.tar.gz"
        RUNNER_URL="https://github.com/actions/runner/releases/download/v2.322.0/${RUNNER_PKG}"
        ;;
    x86_64|amd64)
        RUNNER_PKG="actions-runner-linux-x64-2.322.0.tar.gz"
        RUNNER_URL="https://github.com/actions/runner/releases/download/v2.322.0/${RUNNER_PKG}"
        ;;
    *)
        fail "Unsupported architecture: ${HOST_ARCH}"
        ;;
esac

# ── Create runner user (idempotent) ────────────────────────────────────────
if id "$RUNNER_USER" &>/dev/null; then
    info "User '${RUNNER_USER}' already exists — skipping creation"
else
    info "Creating user '${RUNNER_USER}' ..."
    useradd --create-home --shell /bin/bash --system "$RUNNER_USER"
    ok "User '${RUNNER_USER}' created"
fi

# ── Install runner binary (idempotent) ─────────────────────────────────────
if [[ -f "${RUNNER_DIR}/run.sh" ]]; then
    info "Runner binary already installed at ${RUNNER_DIR} — skipping download"
else
    info "Creating runner directory ${RUNNER_DIR} ..."
    mkdir -p "$RUNNER_DIR"

    info "Downloading runner package from GitHub ..."
    curl -sL "$RUNNER_URL" -o "/tmp/${RUNNER_PKG}"

    info "Extracting to ${RUNNER_DIR} ..."
    tar xzf "/tmp/${RUNNER_PKG}" -C "$RUNNER_DIR"
    rm -f "/tmp/${RUNNER_PKG}"

    ok "Runner binary installed to ${RUNNER_DIR}"
fi

# ── Get runner registration token ──────────────────────────────────────────
info "Fetching runner registration token from GitHub API ..."

REG_TOKEN_RESPONSE=$(curl -s -X POST \
    -H "Authorization: Bearer ${GITHUB_PAT}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/Yoppai/self-hosted-dev-workspace/actions/runners/registration-token" 2>/dev/null)

REG_TOKEN=$(echo "$REG_TOKEN_RESPONSE" | jq -r '.token // empty')

if [[ -z "$REG_TOKEN" ]]; then
    ERROR_MSG=$(echo "$REG_TOKEN_RESPONSE" | jq -r '.message // "Unknown error"')
    fail "Failed to get registration token: ${ERROR_MSG}" 2
fi

ok "Registration token obtained"

# ── Register the runner (idempotent — skip if already registered) ────────
if [[ -f "${RUNNER_DIR}/.runner" ]]; then
    info "Runner already registered — skipping registration"
    info "To re-register, remove ${RUNNER_DIR}/.runner and re-run this script"
else
    info "Registering runner with repository ..."

    # Run registration as the runner user
    sudo -u "$RUNNER_USER" "$RUNNER_DIR/config.sh" \
        --url "$REPO_URL" \
        --token "$REG_TOKEN" \
        --name "$(hostname)-arm64-runner" \
        --labels "arm64,self-hosted,dev-workspace" \
        --work "_work" \
        --replace \
        --unattended \
        --disableupdate

    ok "Runner registered as '$(hostname)-arm64-runner'"
fi

# ── Install and start systemd service ──────────────────────────────────────
info "Checking systemd service '${SERVICE_NAME}' ..."

if systemctl is-enabled "$SERVICE_NAME" &>/dev/null; then
    info "Systemd service already enabled — restarting ..."
    systemctl restart "$SERVICE_NAME"
else
    info "Installing and starting systemd service ..."

    cd "$RUNNER_DIR"
    sudo -u "$RUNNER_USER" ./svc.sh install "$RUNNER_USER"
    ./svc.sh start
    cd /opt

    ok "Systemd service installed and started"
fi

# ── Verify service status ─────────────────────────────────────────────────
sleep 2
if systemctl is-active "$SERVICE_NAME" &>/dev/null; then
    ok "Runner service is active (running)"
else
    warn "Runner service is not active — check: systemctl status ${SERVICE_NAME}"
    fail "Service failed to start" 2
fi

# ── Summary ────────────────────────────────────────────────────────────────
echo ""
echo "  ╔══════════════════════════════════════════════════╗"
echo "  ║  Runner Setup Complete                          ║"
echo "  ╚══════════════════════════════════════════════════╝"
echo ""
info "Runner directory: ${RUNNER_DIR}"
info "Runner user:      ${RUNNER_USER}"
info "Repository:       ${REPO_URL}"
info "Labels:           arm64, self-hosted, dev-workspace"
echo ""
info "The runner will auto-start on boot (systemd)."
info "To check status:  sudo systemctl status ${SERVICE_NAME}"
info "To view logs:     sudo journalctl -u ${SERVICE_NAME} -f"
echo ""
