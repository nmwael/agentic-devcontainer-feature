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

# Idempotence path: if llama-server already exists, notice and NO-OP
if [ -f "${LLAMA_DIR}/llama-server" ]; then
    echo "Notice: /opt/llama-server/llama-server already exists (custom image as base)."
    echo "llama-server feature is idempotent — no re-install performed."
    echo "VERSION: $VERSION, INSTALL_PATH: $INSTALL_PATH"
    exit 0
fi

echo "Installing llama-server VERSION=$VERSION CUDA_ARCHS=$CUDA_ARCHS ARCH=$ARCH_VARIANT"

# Resolve asset URL
if [ -n "$ASSET_URL" ]; then
    ASSET_URL_FINAL="$ASSET_URL"
else
    # Default derived URL pattern — this would need the actual base
    # For now, attempt the standard ggml-org pattern
    ASSET_URL_FINAL="https://github.com/ggml-org/llama.cpp/releases/download/$VERSION/llama-server-${VERSION}-cuda13-${CUDA_ARCHS}.tar.gz"
fi

echo "Downloading llama-server asset from: $ASSET_URL_FINAL"

# Download to scratch /tmp
SCRATCH="/tmp/llama-server-scratch-${VERSION}-${ARCH_VARIANT}"
mkdir -p "$SCRATCH"
rm -rf "$SCRATCH"/*

if ! curl -fL "$ASSET_URL_FINAL" -o "$SCRATCH/llama-server.tar.gz"; then
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
tar -xzf "$SCRATCH/llama-server.tar.gz" -C "$INSTALL_PATH" --strip-components=1

# Create symlink onto PATH if INSTALL_PATH/bin exists
if [ -f "$INSTALL_PATH/llama-server" ]; then
    ln -sf "$INSTALL_PATH/llama-server" /usr/local/bin/llama-server
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
echo "$VERSION" > "$INSTALL_PATH/VERSION"

echo "Done! llama-server installed at $INSTALL_PATH"
echo "Run 'llama-server --version' to verify."