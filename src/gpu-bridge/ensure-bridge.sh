#!/bin/sh
# Re-runnable WSL2 GPU bridge: idempotent symlink of CUDA loader libs + verification.
# /usr/lib/wsl/drivers/*/ → /usr/lib/wsl/lib for various CUDA libs.
set -e

DRIVERS_DIR="/usr/lib/wsl/drivers"
LIB_WSL="/usr/lib/wsl/lib"

# POSIX-sh only — devcontainer features run under /bin/sh (dash on Ubuntu/Debian),
# so no bash arrays. Iterate a whitespace list instead.
LIBS_TO_LINK="libcuda.so.1 libcuda_loader.so libnvidia-ml.so.1 libnvidia-ptxjitcompiler.so.1 libnvdxgdmal.so.1"

for lib in $LIBS_TO_LINK; do
    if [ -d "$DRIVERS_DIR" ]; then
        DRIVER_FILE=$(find "$DRIVERS_DIR" -name "$lib" 2>/dev/null | head -1)
        if [ -n "$DRIVER_FILE" ] && [ -e "$LIB_WSL/$lib" ]; then
            # Symlink: driver lib -> WSL lib (idempotent, safe to re-run)
            ln -sfn "$DRIVER_FILE" "$LIB_WSL/$lib"
            echo "Linked $DRIVER_FILE -> $LIB_WSL/$lib"
        fi
    fi
done

# Verify bridge components
if [ -L "$LIB_WSL/libcuda_loader.so" ]; then
    echo "Verifying WSL GPU bridge components..."
    ls -la "$LIB_WSL/"*cuda* 2>/dev/null || echo "WARNING: Some CUDA loader libs not found in /usr/lib/wsl/lib"
fi

# /dev/dxg check (WSL2 GPU passthrough device)
if [ -e /dev/dxg ]; then
    echo "OK: /dev/dxg present"
else
    echo "WARNING: /dev/dxg not found — GPU passthrough device missing"
fi
