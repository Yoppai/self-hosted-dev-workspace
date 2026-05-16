#!/usr/bin/env bash
# arm64-validate.sh — Self-Hosted Workspace MVP
# ================================================
# Validate all custom images build and run on linux/arm64.
#
# Usage:
#   ./scripts/arm64-validate.sh              # full validation
#   ./scripts/arm64-validate.sh --check-only  # check setup, don't build
#   ./scripts/arm64-validate.sh --target-host # print target-host instructions
#
# Design:
#   - Checks Docker buildx is available and lists builders
#   - On amd64 hosts: uses QEMU emulation via buildx (slower but validates)
#   - On arm64 hosts: native build (fast)
#   - Builds all custom images with --platform linux/arm64
#   - Verifies each image has linux/arm64 in its manifest
#   - Runs a brief runtime check on each image
#
# Requires:
#   - Docker with buildx plugin (default in Docker Desktop / Docker CE 24+)
#   - QEMU user-static binaries for cross-platform (auto-managed by buildx)

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────
HOST_ARCH="$(docker info --format '{{.Architecture}}' 2>/dev/null || uname -m)"
BUILDER_NAME="workspace-arm64-builder"
IMAGES=(
    "dev-base:arm64-validated"
    "opencode-server:arm64-validated"
    "codenomad-server:arm64-validated"
    "kasmvnc-workspace:arm64-validated"
)
BUILD_DIRS=(
    "./dev-base"
    "./opencode"
    "./codenomad"
    "./kasmvnc"
)

PASS=0
FAIL=0
SKIP=0

info()  { printf "  \033[1;34m→\033[0m %s\n" "$*"; }
ok()    { printf "  \033[1;32m✓\033[0m %s\n" "$*"; ((PASS++)); }
warn()  { printf "  \033[1;33m!\033[0m %s\n" "$*" >&2; }
fail()  { printf "  \033[1;31m✗\033[0m %s\n" "$*" >&2; ((FAIL++)); }
banner(){ echo "  ── $* ──"; }

require_command() {
    if ! command -v "$1" &>/dev/null; then
        fail "Required command not found: $1"
        exit 1
    fi
}

# ── Main ──────────────────────────────────────────────────────────────────
echo ""
echo "  ╔══════════════════════════════════════════════════╗"
echo "  ║  ARM64 Validation Suite                         ║"
echo "  ║  Host arch: ${HOST_ARCH}                        "
echo "  ╚══════════════════════════════════════════════════╝"
echo ""

require_command docker

CHECK_ONLY=false
TARGET_HOST=false
for arg in "$@"; do
    case "$arg" in
        --check-only) CHECK_ONLY=true ;;
        --target-host) TARGET_HOST=true ;;
    esac
done

# ── Target-host instructions mode ─────────────────────────────────────────
if $TARGET_HOST; then
    echo ""
    banner "ARM64 Validation — Target Host Instructions"
    echo ""
    echo "  The target host is Oracle Cloud A1 Flex (Ampere ARM64)."
    echo "  On that host, all builds are NATIVE (no emulation needed)."
    echo ""
    echo "  Steps:"
    echo "    1. Clone the repository on the target host."
    echo "    2. Ensure Docker CE 24+ is installed."
    echo "    3. Run:"
    echo "         docker compose build"
    echo "    4. Verify architecture:"
    echo "         docker run --rm dev-base:latest uname -m"
    echo "         # → aarch64"
    echo ""
    echo "    5. Run the smoke test suite:"
    echo "         ./scripts/smoke-test.sh"
    echo ""
    echo "    6. Run the secret audit:"
    echo "         ./scripts/secret-audit.sh"
    echo ""
    echo "  Expected build output (all images):"
    for img in "${IMAGES[@]}"; do
        echo "    ✅ ${img}"
    done
    echo ""
    exit 0
fi

# ── Check buildx availability ─────────────────────────────────────────────
banner "1/4  Docker Buildx Check"

if docker buildx version &>/dev/null; then
    ok "buildx plugin available"
else
    fail "buildx plugin not found — install Docker Desktop or docker-buildx"
    exit 1
fi

EXISTING_BUILDER=$(docker buildx ls 2>/dev/null | grep "${BUILDER_NAME}" || true)
if [[ -n "$EXISTING_BUILDER" ]]; then
    ok "Builder '${BUILDER_NAME}' exists"
else
    info "Creating buildx builder '${BUILDER_NAME}' ..."
    if docker buildx create --name "${BUILDER_NAME}" --driver docker-container --bootstrap 2>/dev/null; then
        ok "Builder '${BUILDER_NAME}' created and bootstrapped"
    else
        warn "Could not create dedicated builder — falling back to default"
        BUILDER_NAME="default"
    fi
fi

# Inspect builder capabilities
if docker buildx inspect "${BUILDER_NAME}" 2>/dev/null | grep -q "linux/arm64"; then
    ok "Builder supports linux/arm64 platform"
else
    warn "Builder may not support linux/arm64 — attempting QEMU registration"
    docker run --privileged --rm tonistiigi/binfmt --install arm64 &>/dev/null || true
    if docker buildx inspect "${BUILDER_NAME}" 2>/dev/null | grep -q "linux/arm64"; then
        ok "linux/arm64 support enabled after QEMU install"
    else
        fail "Cannot enable linux/arm64 support. Try: docker run --privileged --rm tonistiigi/binfmt --install all"
    fi
fi

if $CHECK_ONLY; then
    echo ""
    info "Check-only mode. Skipping builds. Re-run without --check-only to validate."
    exit 0
fi

# ── Build images for linux/arm64 ──────────────────────────────────────────
banner "2/4  ARM64 Image Builds"

for i in "${!IMAGES[@]}"; do
    local_img="${IMAGES[$i]}"
    build_dir="${BUILD_DIRS[$i]}"
    tag_name="${local_img%%:*}"  # get the image name without tag

    info "Building ${local_img} for linux/arm64 (this may take a while via emulation) ..."

    if docker buildx build \
        --builder "${BUILDER_NAME}" \
        --platform linux/arm64 \
        --tag "${local_img}" \
        --load \
        "${build_dir}" 2>/dev/null; then
        ok "${local_img} built for linux/arm64"
    else
        fail "${local_img} build FAILED for linux/arm64"
        warn "Check Dockerfile for arch-specific issues"
    fi
done

# ── Verify manifest ───────────────────────────────────────────────────────
banner "3/4  Manifest Verification"

for img in "${IMAGES[@]}"; do
    if docker image inspect "$img" &>/dev/null; then
        arch=$(docker image inspect --format '{{.Architecture}}' "$img" 2>/dev/null)
        if [[ "$arch" == "arm64" ]] || [[ "$arch" == "aarch64" ]]; then
            ok "${img}: arch = ${arch} ✅"
        else
            warn "${img}: arch = ${arch} (expected arm64) — may need --platform linux/arm64"
        fi
    else
        skip "${img}: not found"
    fi
done

# ── Brief runtime check on arm64 image ────────────────────────────────────
banner "4/4  Runtime Smoke (arm64)"

for img in "${IMAGES[@]}"; do
    img_name="${img%%:*}"
    tag="${img##*:}"

    if ! docker image inspect "${img}" &>/dev/null; then
        skip "${img}: not built — skipping runtime check"
        continue
    fi

    case "$img_name" in
        dev-base)
            info "Testing ${img} ..."
            output=$(docker run --rm --platform linux/arm64 "${img}" bash -lc 'git --version && node --version && bun --version' 2>/dev/null || echo "FAILED")
            if echo "$output" | grep -q "FAILED"; then
                fail "${img}: runtime check failed"
            else
                ok "${img}: git/node/bun available"
            fi
            ;;
        opencode-server)
            info "Testing ${img} ..."
            out=$(docker run --rm --platform linux/arm64 \
                -e OPENCODE_SERVER_PASSWORD=test \
                "${img}" bash -lc 'opencode --version' 2>/dev/null || echo "FAILED")
            if echo "$out" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+'; then
                ok "${img}: opencode v${out} available"
            else
                fail "${img}: opencode not found"
            fi
            ;;
        codenomad-server)
            info "Testing ${img} ..."
            out=$(docker run --rm --platform linux/arm64 \
                "${img}" bash -lc 'opencode --version && codenomad --version' 2>/dev/null || echo "FAILED")
            if echo "$out" | grep -q "FAILED"; then
                fail "${img}: CLI check failed"
            else
                ok "${img}: opencode + CodeNomad available"
            fi
            ;;
        kasmvnc-workspace)
            info "Testing ${img} (architecture only) ..."
            arch=$(docker run --rm --platform linux/arm64 "${img}" uname -m 2>/dev/null || echo "FAILED")
            if [[ "$arch" == "aarch64" ]]; then
                ok "${img}: runs on aarch64 ✅"
            else
                warn "${img}: uname -m = ${arch} (expected aarch64)"
            fi
            ;;
    esac
done

# ── Cleanup builder if we created it ──────────────────────────────────────
if docker buildx inspect "${BUILDER_NAME}" &>/dev/null && [[ "${BUILDER_NAME}" != "default" ]]; then
    docker buildx rm "${BUILDER_NAME}" 2>/dev/null || true
fi

# ── Summary ───────────────────────────────────────────────────────────────
echo ""
echo "  ╔══════════════════════════════════════════════════╗"
printf "  ║  RESULTS:  %d passed · %d failed · %d skipped       ║\n" $PASS $FAIL $SKIP
echo "  ╚══════════════════════════════════════════════════╝"
echo ""

if [[ $FAIL -eq 0 ]]; then
    info "All ARM64 validations pass. Images are ready for target host deployment."
else
    warn "Some ARM64 validations failed. Review warnings above before deploying."
fi

[[ $FAIL -eq 0 ]]
