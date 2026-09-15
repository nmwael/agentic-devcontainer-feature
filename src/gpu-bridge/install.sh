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

# Copy ensure-bridge.sh from the feature root and run it
FEATURE_DIR="/usr/local/share/llm-lab/gpu-bridge"
mkdir -p "$FEATURE_DIR"
SCRIPT_SRC="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
cp -f "$SCRIPT_SRC/ensure-bridge.sh" "$FEATURE_DIR/ensure-bridge.sh"
chmod 0755 "$FEATURE_DIR/ensure-bridge.sh"
"$FEATURE_DIR/ensure-bridge.sh"
ln -sf "$FEATURE_DIR/ensure-bridge.sh" /usr/local/bin/ensure-bridge.sh

# Apply /etc/environment LD_LIBRARY_PATH rewrite
if [ "$ENV_REWRITE" = "true" ]; then
    ENV_LINE="/usr/lib/wsl/lib:/opt/llama-server:/usr/local/cuda/compat:/usr/local/nvidia/lib:/usr/local/nvidia/lib64:/usr/local/cuda/lib64"
    if ! grep -qF "$_REMOTE_USER" /etc/environment 2>/dev/null; then
        # Append the LLAMA-specific path
        echo "LD_LIBRARY_PATH=$ENV_LINE" >>/etc/environment
        echo "Updated /etc/environment with LD_LIBRARY_PATH"
    fi
fi

echo "Done! gpu-bridge feature activated."
echo "Run 'ensure-bridge.sh' (installed at /usr/local/bin/ensure-bridge.sh) or restart the container to apply changes."
