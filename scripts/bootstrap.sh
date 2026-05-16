#!/usr/bin/env bash
# bootstrap.sh — Self-Hosted Workspace MVP
# ==========================================
# One-shot initialisation of shared Docker volumes.
# Run ONCE before deploying services so that directories
# exist with correct ownership (UID 1000).
#
# Usage:
#   sudo ./scripts/bootstrap.sh [--dry-run]
#
# Volume directories (must match docker-compose.yml):
#   workspace_projects  — repositories and working files
#   workspace_profile   — ~/.config, ~/.ssh, OAuth tokens
#   toolchains          — user-installed binaries
#
# Design rationale:
#   Docker named volumes are created empty. If the first
#   container to write runs as root, files end up owned by
#   root and subsequent UID-1000 containers can't write.
#   This script pre-creates the top-level hierarchy with
#   1000:1000 ownership so all services can share.

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────
# NOTE: UID and GID are readonly Bash variables. Use TARGET_UID/GID instead.
TARGET_UID=${WORKSPACE_UID:-1000}
TARGET_GID=${WORKSPACE_GID:-1000}
VOLUME_BASE="/var/lib/docker/volumes"

declare -A VOLUMES
VOLUMES[workspace_projects]="projects"
VOLUMES[workspace_profile]="profile"
VOLUMES[toolchains]="toolchains"

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# ── Functions ─────────────────────────────────────────────────────────────
info()  { printf "  \033[1;34m→\033[0m %s\n" "$*"; }
ok()    { printf "  \033[1;32m✓\033[0m %s\n" "$*"; }
warn()  { printf "  \033[1;33m!\033[0m %s\n" "$*" >&2; }
fail()  { printf "  \033[1;31m✗\033[0m %s\n" "$*" >&2; exit 1; }

init_volume() {
    local name="$1"
    local subdir="$2"
    local vol_path="${VOLUME_BASE}/${name}/_data"

    if $DRY_RUN; then
        info "[dry-run] Would create ${vol_path}/${subdir} with ${TARGET_UID}:${TARGET_GID}"
        return
    fi

    if [[ ! -d "$vol_path" ]]; then
        warn "Volume ${name} does not exist at ${vol_path}"
        warn "  → Create it first: docker volume create ${name}"
        warn "  → Or deploy the Compose stack once (volumes are auto-created)"
        # Attempt to auto-create
        docker volume create "$name" >/dev/null 2>&1 || true
        # Re-check
        if [[ ! -d "$vol_path" ]]; then
            fail "Cannot create volume ${name}. Is Docker running?"
        fi
    fi

    mkdir -p "${vol_path}/${subdir}"
    # Chown the volume root so services that mount the top-level path
    # can also create directories there (e.g. workspace_projects/_data/other).
    chown "${TARGET_UID}:${TARGET_GID}" "${vol_path}"
    chown -R "${TARGET_UID}:${TARGET_GID}" "${vol_path}/${subdir}"
    ok "${name}/${subdir} — ${TARGET_UID}:${TARGET_GID}"
}

# ── Main ──────────────────────────────────────────────────────────────────
echo ""
echo "  ╔══════════════════════════════════════════════════╗"
echo "  ║  Workspace Volume Bootstrap                      ║"
echo "  ║  UID: ${TARGET_UID}  GID: ${TARGET_GID}                        "
echo "  ╚══════════════════════════════════════════════════╝"
echo ""

require_command() {
    if ! command -v "$1" &>/dev/null; then
        fail "Required command not found: $1"
    fi
}

require_command docker

if [[ $EUID -ne 0 ]]; then
    warn "This script modifies Docker volume ownership (needs root)."
    warn "Re-run with sudo if you encounter permission errors."
    echo ""
fi

for name in "${!VOLUMES[@]}"; do
    init_volume "$name" "${VOLUMES[$name]}"
done

echo ""
if $DRY_RUN; then
    info "Dry-run complete. Run without --dry-run to apply."
else
    ok "Bootstrap complete. Volumes are ready for workspace services."
fi
echo ""
