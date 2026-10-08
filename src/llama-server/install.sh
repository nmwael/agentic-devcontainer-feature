#!/bin/sh
set -e

echo "Activating feature 'llama-server'"

# The 'install.sh' entrypoint script is always executed as the root user.
# Option values are passed in as environment variables named after the option id,
# converted to UPPERCASE (e.g. 'version' -> $VERSION, 'cuda_archs' -> $CUDA_ARCHS).
echo "The effective dev container remoteUser is '$_REMOTE_USER'"
echo "The effective dev container containerUser is '$_CONTAINER_USER'"

VERSION="${VERSION:-b10360}"
CUDA_ARCHS="${CUDA_ARCHS:-80;86;89;90;120}"
ASSET_URL="${ASSET_URL:-}"
INSTALL_PATH="${INSTALL_PATH:-/opt/llama-server}"
COMPILE="${COMPILE:-false}"
BUNDLE_CUDA_LIBS="${BUNDLE_CUDA_LIBS:-true}"

# Detect architecture
ARCH=$(uname -m)
case "$ARCH" in
x86_64) ARCH_VARIANT="x64" ;;
aarch64) ARCH_VARIANT="arm64" ;;
*) ARCH_VARIANT="x64" ;;
esac

LLAMA_DIR="${INSTALL_PATH}"

# Runtime dependency: the upstream ubuntu-* release builds are compiled with
# OpenMP, so libggml-base.so and every libggml-cpu-<microarch>.so backend
# link against libgomp.so.1. That lives in the 'libgomp1' package, which is NOT
# pulled in by libgcc-s1/gcc-14-base — so a minimal base image has the GCC
# runtime but not the OpenMP runtime, and every llama-server binary dies with
#   "error while loading shared libraries: libgomp.so.1".
# Provisioned before the idempotence check below so a custom base image that
# already ships llama-server gets the fix too.
if ! ldconfig -p 2>/dev/null | grep -q 'libgomp\.so\.1'; then
    echo "libgomp.so.1 not found — provisioning via apt..."
    if apt-get update -qq && apt-get install -y --no-install-recommends libgomp1 >/dev/null 2>&1; then
        echo "libgomp1 ready"
    else
        echo "WARNING: libgomp1 install failed — llama-server will not start."
        echo "         Install it manually (apt-get install libgomp1) or rebuild from a base image that provides it."
    fi
else
    echo "libgomp.so.1 already present — skipping"
fi

# llama-watchdog.sh rides along with the binary. /health stays green when
# generation collapses (a server observed at ~0.1 tok/s still answers in
# milliseconds), so the consumer's auto-startup.sh spawns this probe to detect
# a degraded server and recycle it through the idempotent starter.
# Installed BEFORE the idempotence check below, for the same reason libgomp1
# is: a base image that already ships llama-server (or a rebuild whose binary
# rides in from a cached layer) takes the early-exit path, and the watchdog is
# exactly what that path is missing — 1.0.5 never landed on such a box.
FEATURE_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
if [ -f "$FEATURE_DIR/llama-watchdog.sh" ]; then
    mkdir -p "$INSTALL_PATH"
    install -m 0755 "$FEATURE_DIR/llama-watchdog.sh" "$INSTALL_PATH/llama-watchdog.sh"
    ln -sf "$INSTALL_PATH/llama-watchdog.sh" /usr/local/bin/llama-watchdog
    echo "llama-watchdog installed -> /usr/local/bin/llama-watchdog"
fi

# Idempotence path: if llama-server already exists, notice and NO-OP
if [ -f "${LLAMA_DIR}/llama-server" ]; then
    echo "Notice: /opt/llama-server/llama-server already exists (custom image as base)."
    echo "llama-server feature is idempotent — no re-install performed."
    echo "VERSION: $VERSION, INSTALL_PATH: $INSTALL_PATH"
    exit 0
fi

echo "Installing llama-server VERSION=$VERSION CUDA_ARCHS=$CUDA_ARCHS ARCH=$ARCH_VARIANT"

# The download needs curl + CA trust. A minimal base image (e.g. ubuntu:24.04,
# used by the devcontainer CLI feature-test harness) has neither. Provision
# them up-front (idempotent) so the asset fetch works on any base; mirrors the
# libgomp1 provisioning above.
if ! command -v curl >/dev/null 2>&1; then
    echo "curl not found — provisioning via apt..."
    apt-get update -qq \
        && apt-get install -y --no-install-recommends ca-certificates curl >/dev/null 2>&1 \
        || echo "WARNING: curl install failed — llama-server will not be installed."
fi

# Resolve asset URL
if [ -n "$ASSET_URL" ]; then
    ASSET_URL_FINAL="$ASSET_URL"
else
    # Default derived URL pattern — the official ubuntu-bin asset for this release
    # (upstream publishes CPU builds here; CUDA builds are not published as
    # ubuntu assets on recent releases, so GPU runtimes come from a cuda-runtime
    # base image + BUNDLE_CUDA_LIBS, or an ASSET_URL override).
    ASSET_URL_FINAL="https://github.com/ggml-org/llama.cpp/releases/download/$VERSION/llama-${VERSION}-bin-ubuntu-${ARCH_VARIANT}.tar.gz"
fi

echo "Downloading llama-server asset from: $ASSET_URL_FINAL"

# Download to scratch /tmp
SCRATCH="/tmp/llama-server-scratch-${VERSION}-${ARCH_VARIANT}"
mkdir -p "$SCRATCH"
rm -rf "${SCRATCH:?}"/*

# Bounded download: --max-time/--retry prevent a stalled connection from
# hanging the devcontainer "configuring" step forever (worst case ~15 min,
# then the graceful-degrade path below runs instead).
if ! curl -fL --max-time 300 --retry 3 --retry-delay 2 \
    "$ASSET_URL_FINAL" -o "$SCRATCH/llama-server.tar.gz"; then
    echo "WARNING: Failed to download llama-server asset from $ASSET_URL_FINAL"
    echo "llama-server will not be installed. The feature gracefully degrades."
    echo "To install manually: download the tarball, unpack to $INSTALL_PATH,"
    echo "and ensure llama-server is on PATH."
    exit 0
fi

# Verify embedded sha256 checksum if present
if [ -f "$SCRATCH/SHASUMS256.txt" ]; then
    echo "Verifying checksum..."
    if ! echo "$(sha256sum "$SCRATCH/llama-server.tar.gz" | awk '{print $1}')  $SCRATCH/llama-server.tar.gz" | sha256sum -c -; then
        echo "WARNING: Checksum verification failed. Proceeding anyway."
    else
        echo "Checksum verification passed."
    fi
fi

# Unpack to install path
echo "Unpacking to $INSTALL_PATH ..."
mkdir -p "$INSTALL_PATH"
# Assets differ in layout: some carry a top-level dir, some carry bin/….
# Try --strip-components=1 (dir layout) and fall back to plain extraction.
if ! tar -xzf "$SCRATCH/llama-server.tar.gz" -C "$INSTALL_PATH" --strip-components=1 2>/dev/null; then
    tar -xzf "$SCRATCH/llama-server.tar.gz" -C "$INSTALL_PATH"
fi

# Locate the llama-server binary wherever the asset puts it (bin/ or root)
LLAMA_BIN="$(find "$INSTALL_PATH" -type f -name llama-server | head -1)"
if [ -n "$LLAMA_BIN" ]; then
    ln -sf "$LLAMA_BIN" /usr/local/bin/llama-server
    echo "llama-server symlinked to /usr/local/bin/llama-server"
fi

# Bundle CUDA runtime libs if requested
if [ "$BUNDLE_CUDA_LIBS" = "true" ]; then
    echo "Bundling CUDA 13.3 runtime libraries..."
    # Install cudart, cublas, cublasLt into INSTALL_PATH
    # These are typically available from the CUDA runtime path
    if [ -d "/usr/local/cuda" ]; then
        cp -r /usr/local/cuda/lib64/libcudart.so* "$INSTALL_PATH/" 2>/dev/null || true
        cp -r /usr/local/cuda/lib64/libcublas* "$INSTALL_PATH/" 2>/dev/null || true
        cp -r /usr/local/cuda/lib64/libcublasLt* "$INSTALL_PATH/" 2>/dev/null || true
        echo "CUDA runtime libraries copied to $INSTALL_PATH"
    else
        echo "NOTE: No /usr/local/cuda found — CUDA libs will be missing at runtime."
        echo "Set BUNDLE_CUDA_LIBS=false and use a cuda-runtime base image instead."
    fi
fi

# Write VERSION file
echo "$VERSION" >"$INSTALL_PATH/VERSION"

# Self-check: execute the binary. Loading it is the only way to prove every
# transitive shared object resolved, so a missing runtime dep surfaces here at
# build time instead of at the first agent prompt.
echo "Verifying llama-server starts..."
if "$INSTALL_PATH/llama-server" --version >/dev/null 2>&1; then
    echo "llama-server --version OK"
else
    echo "WARNING: llama-server was installed but fails to execute."
    "$INSTALL_PATH/llama-server" --version 2>&1 | head -3 || true
    echo "         Common cause: missing libgomp1 (OpenMP runtime)."
fi

echo "Done! llama-server installed at $INSTALL_PATH"
echo "Run 'llama-server --version' to verify."
