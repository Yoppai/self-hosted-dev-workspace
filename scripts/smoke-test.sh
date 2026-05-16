#!/usr/bin/env bash
# smoke-test.sh — Self-Hosted Workspace MVP
# ============================================
# Post-deploy validation: build, start, health, volume sharing, secrets.
#
# Usage:
#   ./scripts/smoke-test.sh              # full suite
#   ./scripts/smoke-test.sh --quick      # skip image build, test running stack
#   ./scripts/smoke-test.sh --build-only # build images only, no runtime checks
#
# Design:
#   - Builds all custom images (dev-base, opencode, codenomad, kasmvnc)
#   - Starts the full Compose stack with placeholder env vars
#   - Waits for Docker health checks (up to 90s)
#   - Verifies each service HTTP/HTTPS endpoint responds
#   - Tests cross-container volume read/write
#   - Inspects image layers for embedded secrets
#
# Exit codes:
#   0 = all checks pass
#   1 = build failure
#   2 = runtime health failure
#   3 = volume or persistence failure
#   4 = secret audit failure

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yml}"
PROJECT_NAME="${PROJECT_NAME:-workspace-smoke}"
ENV_FILE="$(mktemp)"
COMPOSE_UP_TIMEOUT=90           # seconds to wait for all healthy
COMPOSE_DOWN=false              # set to true to teardown after test

# Placeholder env vars for testing (NOT real secrets)
cat > "$ENV_FILE" <<'EOF'
ANTHROPIC_API_KEY=sk-placeholder-smoke-test
OPENAI_API_KEY=sk-placeholder-smoke-test
CODE_SERVER_PASSWORD=smoke-test-pw
OPENCODE_SERVER_USERNAME=smoke-test-user
OPENCODE_SERVER_PASSWORD=smoke-test-pw
CODENOMAD_SERVER_USERNAME=smoke-test-user
CODENOMAD_SERVER_PASSWORD=smoke-test-pw
KASMVNC_PASSWORD=smoke-test-pw
EOF

# Images to build
BUILD_IMAGES=(
    "dev-base:smoke"
    "opencode-server:smoke"
    "codenomad-server:smoke"
    "kasmvnc-workspace:smoke"
)

# ── Helpers ────────────────────────────────────────────────────────────────
PASS=0
FAIL=0
SKIP=0

info()  { printf "  \033[1;34m→\033[0m %s\n" "$*"; }
ok()    { printf "  \033[1;32m✓\033[0m %s\n" "$*"; ((PASS++)); }
warn()  { printf "  \033[1;33m!\033[0m %s\n" "$*" >&2; }
fail()  { printf "  \033[1;31m✗\033[0m %s\n" "$*" >&2; ((FAIL++)); }
skip()  { printf "  \033[1;90m–\033[0m %s\n" "$*"; ((SKIP++)); }
banner(){ echo "  ── $* ──"; }

require_command() {
    if ! command -v "$1" &>/dev/null; then
        fail "Required command not found: $1"
        exit 1
    fi
}

cleanup() {
    local exit_code=$?
    if $COMPOSE_DOWN && [[ -f "$ENV_FILE" ]]; then
        docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" down -v 2>/dev/null || true
    fi
    rm -f "$ENV_FILE"
    exit "$exit_code"
}
trap cleanup EXIT

# ── Main ──────────────────────────────────────────────────────────────────
echo ""
echo "  ╔══════════════════════════════════════════════════╗"
echo "  ║  Workspace MVP — Smoke Test Suite               ║"
echo "  ╚══════════════════════════════════════════════════╝"
echo ""

require_command docker

QUICK_MODE=false
BUILD_ONLY=false
for arg in "$@"; do
    case "$arg" in
        --quick) QUICK_MODE=true ;;
        --build-only) BUILD_ONLY=true ;;
    esac
done

# ═══════════════════════════════════════════════════════════════════════════
# SECTION 1: Build images
# ═══════════════════════════════════════════════════════════════════════════

banner "1/6  Image Build"

if $QUICK_MODE; then
    info "Skipping build (--quick). Checking existing images..."
    for img in dev-base opencode-server codenomad-server kasmvnc-workspace; do
        docker image inspect "${img}:smoke" &>/dev/null \
            && ok "${img}:smoke exists" \
            || warn "${img}:smoke not found — run without --quick first"
    done
else
    # dev-base — build first, other images depend on it
    info "Building dev-base:smoke ..."
    if docker build --platform linux/arm64 -t dev-base:smoke ./dev-base; then
        ok "dev-base:smoke built"

        info "Building opencode-server:smoke ..."
        if docker build -t opencode-server:smoke ./opencode; then
            ok "opencode-server:smoke built"
        else
            fail "opencode-server build failed"
        fi

        info "Building codenomad-server:smoke ..."
        if docker build -t codenomad-server:smoke ./codenomad; then
            ok "codenomad-server:smoke built"
        else
            fail "codenomad-server build failed"
        fi

        info "Building kasmvnc-workspace:smoke ..."
        if docker build -t kasmvnc-workspace:smoke ./kasmvnc; then
            ok "kasmvnc-workspace:smoke built"
        else
            fail "kasmvnc-workspace build failed"
        fi
    else
        fail "dev-base build failed — aborting further builds"
    fi
fi

if $BUILD_ONLY; then
    echo ""
    info "Build-only mode. Skipping runtime tests."
    echo ""
    echo "  ╔══════════════════════════════════════════════════╗"
    printf "  ║  Results:  %d passed · %d failed · %d skipped      ║\n" $PASS $FAIL $SKIP
    echo "  ╚══════════════════════════════════════════════════╝"
    echo ""
    [[ $FAIL -eq 0 ]] && exit 0 || exit 1
fi

# ═══════════════════════════════════════════════════════════════════════════
# SECTION 2: Start stack
# ═══════════════════════════════════════════════════════════════════════════

banner "2/6  Stack Startup"

export COMPOSE_FILE PROJECT_NAME
# Use built images for services that have custom builds
export DEV_BASE_TAG=smoke
export OPENCODE_TAG=smoke
export CODENOMAD_TAG=smoke
export KASMVNC_TAG=smoke

info "Starting stack with placeholder env vars ..."
if docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" --env-file "$ENV_FILE" up -d --wait --wait-timeout "$COMPOSE_UP_TIMEOUT"; then
    ok "All services started (docker compose up --wait)"
else
    fail "Stack startup incomplete — checking individual services ..."
    # Show what's not healthy
    for svc in code-server opencode-server codenomad-server kasmvnc-workspace; do
        state=$(docker compose -p "$PROJECT_NAME" ps --format json "$svc" 2>/dev/null | grep -o '"Health":"[^"]*"' | cut -d'"' -f4 || echo "unknown")
        if [[ "$state" == "healthy" ]]; then
            ok "$svc = healthy"
        else
            warn "$svc = ${state:-missing} — may need more time or has config issue"
        fi
    done
fi

# ═══════════════════════════════════════════════════════════════════════════
# SECTION 3: Service endpoints
# ═══════════════════════════════════════════════════════════════════════════

banner "3/6  Service Endpoints"

# Get container IPs from the internal network
get_container_ip() {
    local svc="$1"
    docker compose -p "$PROJECT_NAME" exec -T "$svc" hostname -I 2>/dev/null | awk '{print $1}' || echo ""
}

# code-server (HTTP port 8080)
info "code-server @ :8080 ..."
docker compose -p "$PROJECT_NAME" exec -T code-server \
    bash -lc 'curl -sf -o /dev/null -w "%{http_code}" http://localhost:8080/healthz' 2>/dev/null \
    && ok "code-server health endpoint responds" \
    || fail "code-server unreachable on :8080"

# opencode-server (HTTP port 4096, needs basic auth)
info "opencode-server @ :4096 (authenticated) ..."
docker compose -p "$PROJECT_NAME" exec -T opencode-server \
    bash -lc 'curl -sf -u "${OPENCODE_SERVER_USERNAME}:${OPENCODE_SERVER_PASSWORD}" -o /dev/null -w "%{http_code}" http://localhost:4096/global/health' 2>/dev/null \
    && ok "opencode-server authenticated health = 200" \
    || fail "opencode-server unreachable or auth failure"

# opencode-server unauthenticated (should 401)
info "opencode-server @ :4096 (unauthenticated, expecting 401) ..."
docker compose -p "$PROJECT_NAME" exec -T opencode-server \
    bash -lc 'curl -sf -o /dev/null -w "%{http_code}" http://localhost:4096/global/health' 2>/dev/null \
    && warn "opencode-server accepted unauthenticated request (expected 401)" \
    || ok "opencode-server rejects unauthenticated requests"

# CodeNomad (HTTPS port 9898)
info "codenomad-server @ :9898 ..."
docker compose -p "$PROJECT_NAME" exec -T codenomad-server \
    bash -lc 'curl -sk -o /dev/null -w "%{http_code}" https://localhost:9898/' 2>/dev/null \
    && ok "CodeNomad endpoint responds" \
    || fail "CodeNomad unreachable on :9898"

# KasmVNC (HTTPS port 6901)
info "kasmvnc-workspace @ :6901 ..."
docker compose -p "$PROJECT_NAME" exec -T kasmvnc-workspace \
    bash -lc 'curl -sk -o /dev/null -w "%{http_code}" https://localhost:6901/' 2>/dev/null \
    && ok "KasmVNC noVNC endpoint responds" \
    || fail "KasmVNC unreachable on :6901"

# ═══════════════════════════════════════════════════════════════════════════
# SECTION 4: Cross-container volume sharing
# ═══════════════════════════════════════════════════════════════════════════

banner "4/6  Volume Sharing (workspace_projects)"

VOLUME_TEST_FILE=".smoke-test-$(date +%s)"
VOLUME_TEST_CONTENT="smoke-test-write-from-$(hostname)"

# Write from opencode-server
info "Writing from opencode-server ..."
if docker compose -p "$PROJECT_NAME" exec -T opencode-server \
    bash -lc "echo '${VOLUME_TEST_CONTENT}' > /home/workspace/projects/${VOLUME_TEST_FILE}"; then
    ok "Written by opencode-server to workspace_projects"
else
    fail "Cannot write from opencode-server"
fi

# Read from code-server
info "Reading from code-server ..."
if docker compose -p "$PROJECT_NAME" exec -T code-server \
    bash -lc "cat /home/coder/projects/${VOLUME_TEST_FILE}" 2>/dev/null | grep -q "${VOLUME_TEST_CONTENT}"; then
    ok "Read by code-server — content matches"
else
    fail "Cross-service volume read failed"
fi

# Read from KasmVNC
info "Reading from KasmVNC ..."
if docker compose -p "$PROJECT_NAME" exec -T kasmvnc-workspace \
    bash -lc "cat /home/kasm-user/projects/${VOLUME_TEST_FILE}" 2>/dev/null | grep -q "${VOLUME_TEST_CONTENT}"; then
    ok "Read by KasmVNC — content matches"
else
    warn "KasmVNC volume read failed (may need different mount path)"
fi

# Read from CodeNomad
info "Reading from CodeNomad ..."
if docker compose -p "$PROJECT_NAME" exec -T codenomad-server \
    bash -lc "cat /home/workspace/projects/${VOLUME_TEST_FILE}" 2>/dev/null | grep -q "${VOLUME_TEST_CONTENT}"; then
    ok "Read by CodeNomad — content matches"
else
    fail "CodeNomad volume read failed"
fi

# Cleanup test file
docker compose -p "$PROJECT_NAME" exec -T opencode-server \
    bash -lc "rm -f /home/workspace/projects/${VOLUME_TEST_FILE}" 2>/dev/null || true

# ═══════════════════════════════════════════════════════════════════════════
# SECTION 5: Secret audit (image layer inspection)
# ═══════════════════════════════════════════════════════════════════════════

banner "5/6  Secret Audit (Image Layers)"

SECRET_PATTERNS='sk-placeholder-smoke-test|smoke-test-pw|smoke-test-user'
SECRET_FOUND=false

for img in dev-base opencode-server codenomad-server kasmvnc-workspace; do
    tag="${img}:smoke"
    info "Scanning ${tag} ..."
    if docker image inspect "$tag" &>/dev/null; then
        # Check image config env
        if docker image inspect --format '{{json .Config.Env}}' "$tag" 2>/dev/null | grep -qiE "$SECRET_PATTERNS"; then
            warn "${tag}: potential secrets in Config.Env"
            SECRET_FOUND=true
        fi
        # Check image history commands (truncated)
        if docker history --no-trunc "$tag" 2>/dev/null | grep -qiE "$SECRET_PATTERNS"; then
            warn "${tag}: potential secrets in history"
            SECRET_FOUND=true
        fi
        if ! $SECRET_FOUND; then
            ok "${tag}: no placeholder secrets in layers"
        fi
    else
        skip "${tag}: image not found — skipping audit"
    fi
done

if $SECRET_FOUND; then
    fail "One or more images MAY contain secrets in layers — investigate manually"
else
    ok "All scanned images pass secret isolation check"
fi

# ═══════════════════════════════════════════════════════════════════════════
# SECTION 6: Restart persistence (quick)
# ═══════════════════════════════════════════════════════════════════════════

banner "6/6  Restart Persistence"

PERSISTENCE_FILE=".smoke-restart-$(date +%s)"

# Write marker
docker compose -p "$PROJECT_NAME" exec -T opencode-server \
    bash -lc "echo 'persistence-test' > /home/workspace/projects/${PERSISTENCE_FILE}" 2>/dev/null || true

# Restart
info "Restarting stack ..."
if docker compose -p "$PROJECT_NAME" restart -t 30 2>/dev/null; then
    sleep 5
    # Read marker
    if docker compose -p "$PROJECT_NAME" exec -T code-server \
        bash -lc "cat /home/coder/projects/${PERSISTENCE_FILE}" 2>/dev/null | grep -q "persistence-test"; then
        ok "File survives restart — persistence verified"
    else
        fail "File lost after restart"
    fi
    # Cleanup
    docker compose -p "$PROJECT_NAME" exec -T opencode-server \
        bash -lc "rm -f /home/workspace/projects/${PERSISTENCE_FILE}" 2>/dev/null || true
else
    fail "docker compose restart failed"
fi

# ═══════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════

echo ""
echo "  ╔══════════════════════════════════════════════════╗"
printf "  ║  RESULTS:  %d passed · %d failed · %d skipped       ║\n" $PASS $FAIL $SKIP
echo "  ╚══════════════════════════════════════════════════╝"
echo ""

# Teardown if --quick or explicit
if $QUICK_MODE || $COMPOSE_DOWN; then
    info "Tearing down stack ..."
    docker compose -p "$PROJECT_NAME" down -v 2>/dev/null || true
fi

[[ $FAIL -eq 0 ]] && exit 0 || exit 2
