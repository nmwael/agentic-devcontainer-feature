#!/bin/sh
set -e

echo "Activating feature 'models'"

# The 'install.sh' entrypoint script is always executed as the root user.
# Option values are passed in as environment variables named after the option id,
# converted to UPPERCASE (e.g. 'model' -> $MODEL, 'quant' -> $QUANT).
echo "The effective dev container remoteUser is '$_REMOTE_USER'"
echo "The effective dev container containerUser is '$_CONTAINER_USER'"

MODEL="${MODEL:-gemma-4-26B-A4B-it-UD-IQ2_M}"
QUANT="${QUANT:-IQ2_M}"
MODELS_DIR="${MODELS_DIR:-}"

# Derive MODELS_DIR if not set (default: $PWD/models → bind-mount friendly)
if [ -z "$MODELS_DIR" ]; then
    MODELS_DIR="$PWD/models"
    echo "MODELS_DIR not set — defaulting to $MODELS_DIR"
fi

FEATURE_MODELS_DIR="/usr/local/share/llm-lab/models"
mkdir -p "$FEATURE_MODELS_DIR"

echo "Model config: MODEL=$MODEL QUANT=$QUANT MODELS_DIR=$MODELS_DIR"

# jq provisioning guard — needed to materialize models.json (config-data templates are JSON)
if ! command -v jq >/dev/null 2>&1; then
    echo "jq not found — provisioning via apt..."
    if apt-get update -qq && apt-get install -y --no-install-recommends jq >/dev/null 2>&1; then
        echo "jq ready"
    else
        echo "WARNING: jq install failed — models config will keep template defaults"
    fi
fi

SCRIPT_SRC="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"

# Generate models.json from the JSON template via jq (values override template defaults)
CONFIG_FILE="$FEATURE_MODELS_DIR/models.json"
if command -v jq >/dev/null 2>&1; then
    jq --arg m "$MODEL" --arg q "$QUANT" --arg d "$MODELS_DIR" \
        '.model = $m | .quant = $q | .models_dir = $d' \
        "$SCRIPT_SRC/templates/models.json" >"$CONFIG_FILE"
else
    cp -f "$SCRIPT_SRC/templates/models.json" "$CONFIG_FILE"
    echo "WARNING: jq unavailable — models.json keeps template defaults"
fi

# Install the static fetch-models.sh from the feature root (reads models.json at runtime)
FETCH_SCRIPT="$FEATURE_MODELS_DIR/fetch-models.sh"
cp -f "$SCRIPT_SRC/fetch-models.sh" "$FETCH_SCRIPT"
chmod 0755 "$FETCH_SCRIPT"

# Write MODELS_DIR to /etc/environment or via containerEnv when the option is set
if ! grep -qF "MODELS_DIR" /etc/environment 2>/dev/null; then
    echo "export MODELS_DIR=$MODELS_DIR" >>/etc/environment
    echo "Added MODELS_DIR to /etc/environment"
fi

echo "Done! Models feature activated."
echo "Run 'fetch-models.sh' to download $MODEL quant=$QUANT"
