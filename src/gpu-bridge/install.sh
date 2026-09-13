#!/bin/sh
set -e

echo "Activating feature 'gpu-bridge'"

# The 'install.sh' entrypoint script is always executed as the root user.
# Option values are passed in as environment variables named after the option id,
# converted to UPPERCASE (e.g. 'wsl2_only' -> $WSL2_ONLY, 'env_rewrite' -> $ENV_REWRITE).
echo "The effective dev container remoteUser is '$_REMOTE_USER'"
echo "The effective dev container containerUser is '$_CONTAINER_USER'"

WSL2_ONLY="${WSL2_ONLY:-false}"
ENV_REWRITE="${ENV_REWRITE:-true}"

# Detect if running inside WSL2
IS_WSL2=false
if [ -f /proc/version ]; then
    if grep -qi "microsoft" /proc/version; then
        IS_WSL2=true
    fi
fi
# Also check for /usr/lib/wsl/lib which is WSL2-specific
if [ -d "/usr/lib/wsl/lib" ]; then
    IS_WSL2=true
fi

echo "WSL2 detection: $IS_WSL2"

if [ "$IS_WSL2" = "false" ]; then
    if [ "$WSL2_ONLY" = "true" ]; then
        echo "ERROR: gpu-bridge requires WSL2 but not running in WSL2. Exiting."
        exit 1
    else
        echo "Not running in WSL2 — gpu-bridge stub: exiting 0 (no-op)."
        exit 0
    fi
fi

echo "Running in WSL2 — installing GPU bridge..."

# Copy ensure-bridge.sh logic to the feature directory
FEATURE_DIR="/usr/local/share/llm-lab/gpu-bridge"
mkdir -p "$FEATURE_DIR"

# The ensure-bridge logic: idempotent symlink of driver loader libs
# /usr/lib/wsl/drivers/*/ → /usr/lib/wsl/lib for various CUDA libs
DRIVERS_DIR="/usr/lib/wsl/drivers"
LIB_WSL="/usr/lib/wsl/lib"

# Create the feature directory structure
mkdir -p "$FEATURE_DIR/drivers"

# Symlink CUDA loader libraries from WSL drivers to WSL lib
# These libs are needed for llama-server to work under WSL2
LIBS_TO_LINK=(
    "libcuda.so.1"
    "libcuda_loader.so"
    "libnvidia-ml.so.1"
    "libnvidia-ptxjitcompiler.so.1"
    "libnvdxgdmal.so.1"
)

for lib in "${LIBS_TO_LINK[@]}"; do
    # Find the actual file in WSL drivers
    if [ -d "$DRIVERS_DIR" ]; then
        DRIVER_FILE=$(find "$DRIVERS_DIR" -name "$lib" 2>/dev/null | head -1)
        if [ -n "$DRIVER_FILE" ] && [ -e "$LIB_WSL/$lib" ]; then
            # Symlink: driver lib -> WSL lib (idempotent, safe to re-run)
            ln -sfn "$DRIVER_FILE" "$LIB_WSL/$lib"
            echo "Linked $DRIVER_FILE -> $LIB_WSL/$lib"
        fi
    fi
done

# Apply /etc/environment LD_LIBRARY_PATH rewrite
if [ "$ENV_REWRITE" = "true" ]; then
    ENV_LINE="/usr/lib/wsl/lib:/opt/llama-server:/usr/local/cuda/compat:/usr/local/nvidia/lib:/usr/local/nvidia/lib64:/usr/local/cuda/lib64"
    if ! grep -qF "$_REMOTE_USER" /etc/environment 2>/dev/null; then
        # Append the LLAMA-specific path
        echo "LD_LIBRARY_PATH=$ENV_LINE" >> /etc/environment
        echo "Updated /etc/environment with LD_LIBRARY_PATH"
    fi
fi

# postStartCommand hook: re-symlinks and verify /dev/dxg
# This would be called via devcontainer postStartCommand, but we run it here for features
if [ -L "$LIB_WSL/libcuda_loader.so" ]; then
    echo "Verifying WSL GPU bridge components..."
    ls -la "$LIB_WSL/"*cuda* 2>/dev/null || echo "WARNING: Some CUDA loader libs not found in /usr/lib/wsl/lib"
fi

echo "Done! gpu-bridge feature activated."
echo "Run 'ensure-bridge.sh' or restart the container to apply changes."