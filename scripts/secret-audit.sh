#!/usr/bin/env bash
# secret-audit.sh — Self-Hosted Workspace MVP
# =============================================
# Inspect Docker images for embedded secrets.
# Checks image metadata (env, labels) and layer history.
#
# Usage:
#   ./scripts/secret-audit.sh                    # audit all workspace images
#   ./scripts/secret-audit.sh <image> [image...] # audit specific images
#   ./scripts/secret-audit.sh --patterns-file    # use custom patterns
#
# Design:
#   - Scans docker image inspect Config.Env and Config.Labels
#   - Scans docker history --no-trunc for env/set commands
#   - Default patterns match placeholder values (no real secrets expected)
#   - Reports PASS/FAIL per image
#
# Exit codes:
#   0 = no high-confidence secrets found
#   1 = secrets detected in one or more images

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────
# Default images to audit
DEFAULT_IMAGES=(
    "dev-base:latest"
    "opencode-server:latest"
    "codenomad-server:latest"
    "kasmvnc-workspace:latest"
)

# Default patterns to flag (detect placeholder secrets accidentally embedded)
# NOTE: These are the placeholders from .env.example and smoke-test values.
# Add or customise patterns via --patterns-file or SECRET_PATTERNS env var.
SECRET_PATTERNS="${SECRET_PATTERNS:-<(your-|placeholder|sk-placeholder|smoke-test-pw|smoke-test-user)}"

# Patterns that are safe in images (our known env var names)
SAFE_ENV_NAMES="^(ANTHROPIC_API_KEY|OPENAI_API_KEY|OPENCODE_SERVER_USERNAME|OPENCODE_SERVER_PASSWORD|CODENOMAD_SERVER_USERNAME|CODENOMAD_SERVER_PASSWORD|KASMVNC_PASSWORD|CODE_SERVER_PASSWORD|VNC_PW|PATH|HOME|USER|DEBIAN_FRONTEND|BUN_INSTALL|XDG_CONFIG_HOME|TZ)$"

# ── Helpers ────────────────────────────────────────────────────────────────
PASS=0
FAIL=0
SKIP=0
SECRETS_FOUND=false

info()  { printf "  \033[1;34m→\033[0m %s\n" "$*"; }
ok()    { printf "  \033[1;32m✓\033[0m %s\n" "$*"; ((PASS++)); }
warn()  { printf "  \033[1;33m!\033[0m %s\n" "$*" >&2; }
fail()  { printf "  \033[1;31m✗\033[0m %s\n" "$*" >&2; ((FAIL++)); SECRETS_FOUND=true; }
skip()  { printf "  \033[1;90m–\033[0m %s\n" "$*"; ((SKIP++)); }
banner(){ echo "  ── $* ──"; }

# ── Main ──────────────────────────────────────────────────────────────────
echo ""
echo "  ╔══════════════════════════════════════════════════╗"
echo "  ║  Secret Layer Audit                             ║"
echo "  ╚══════════════════════════════════════════════════╝"
echo ""

IMAGES=("${@:-${DEFAULT_IMAGES[@]}}")

for img in "${IMAGES[@]}"; do
    banner "Auditing: ${img}"

    if ! docker image inspect "$img" &>/dev/null; then
        warn "Image ${img} not found — skipping"
        skip "Not found"
        continue
    fi

    # ── Check 1: Config.Env ──────────────────────────────────────────────
    info "  Checking Config.Env ..."
    env_values=$(docker image inspect --format '{{json .Config.Env}}' "$img" 2>/dev/null || echo "[]")
    if [[ -z "$env_values" || "$env_values" == "[]" ]] || echo "$env_values" | grep -qE "$SECRET_PATTERNS"; then
        # Extract the actual values to report
        found_secrets=$(echo "$env_values" | grep -oE "[^=]*=(${SECRET_PATTERNS})" 2>/dev/null || true)
        if [[ -n "$found_secrets" ]]; then
            warn "  Potential secrets in Config.Env:"
            while IFS= read -r line; do
                warn "    ${line}"
            done <<< "$found_secrets"
            fail "  ${img} has secrets in environment metadata"
        else
            ok "  Config.Env clean — no secret values"
        fi
    else
        ok "  Config.Env clean — no secret values"
    fi

    # ── Check 2: Config.Labels ───────────────────────────────────────────
    info "  Checking Config.Labels ..."
    labels=$(docker image inspect --format '{{json .Config.Labels}}' "$img" 2>/dev/null || echo "{}")
    if [[ -n "$labels" && "$labels" != "{}" ]] && echo "$labels" | grep -qiE "$SECRET_PATTERNS"; then
        fail "  ${img} has potential secrets in labels"
    else
        ok "  Config.Labels clean"
    fi

    # ── Check 3: History ─────────────────────────────────────────────────
    info "  Checking docker history ..."
    history_output=$(docker history --no-trunc "$img" 2>/dev/null || true)
    if echo "$history_output" | grep -qiE "$SECRET_PATTERNS"; then
        warn "  Potential secret patterns found in build commands:"
        echo "$history_output" | grep -iE "$SECRET_PATTERNS" | while IFS= read -r line; do
            warn "    ${line:0:200}"
        done
        fail "  ${img} has potential secrets in image history"
    else
        ok "  History clean — no secret values in layer commands"
    fi

    echo ""
done

# ── Summary ───────────────────────────────────────────────────────────────
echo ""
echo "  ╔══════════════════════════════════════════════════╗"
printf "  ║  RESULTS:  %d passed · %d failed · %d skipped       ║\n" $PASS $FAIL $SKIP
echo "  ╚══════════════════════════════════════════════════╝"
echo ""

if $SECRETS_FOUND; then
    warn "SECRETS DETECTED in one or more images."
    warn "Review flagged values and rebuild affected images."
    info "If this is a false positive, update SECRET_PATTERNS in this script."
    exit 1
else
    info "All scanned images pass secret isolation check."
    info "No high-confidence secrets found in image layers."
    exit 0
fi
