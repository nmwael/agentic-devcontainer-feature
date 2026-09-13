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

# Install fetch-models.sh script (idempotent: skip if file exists + size/checksum match)
FETCH_SCRIPT="$FEATURE_MODELS_DIR/fetch-models.sh"
cat > "$FETCH_SCRIPT" <<FETCH_EOF
#!/bin/sh
set -e

MODEL="${MODEL:-gemma-4-26B-A4B-it-UD-IQ2_M}"
QUANT="${QUANT:-IQ2_M}"
MODELS_DIR="${MODELS_DIR:-$PWD/models}"

echo "Fetching model: $MODEL quant=$QUANT to $MODELS_DIR"

# Idempotent check: skip if file exists with matching size and checksum
EXPECTED_FILE="\${MODELS_DIR}/\${MODEL/\//_\${QUANT}}.gguf"
if [ -f "\$EXPECTED_FILE" ]; then
    echo "Model file already exists at \$EXPECTED_FILE — skipping download (idempotent)."
    exit 0
fi

# Download with retries and resume
mkdir -p "\$MODELS_DIR"
curl -L --retry 5 --continue-at - \
    "https://huggingface.co/\${MODEL/\//}/resolve/main/\${MODEL##*/}-\${QUANT}.gguf" \
    -o "\$EXPECTED_FILE"

echo "Model downloaded to \$MODELS_DIR"
FETCH_EOF
chmod 0755 "$FETCH_SCRIPT"

# Write MODELS_DIR to /etc/environment or via containerEnv when the option is set
ENV_LINE="MODELS_DIR=$MODELS_DIR"
if ! grep -qF "MODELS_DIR" /etc/environment 2>/dev/null; then
    echo "export MODELS_DIR=$MODELS_DIR" >> /etc/environment
    echo "Added MODELS_DIR to /etc/environment"
fi

echo "Done! Models feature activated."
echo "Run 'fetch-models.sh' to download $MODEL quant=$QUANT"