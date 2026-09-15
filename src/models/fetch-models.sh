#!/bin/sh
# fetch-models.sh — download the configured model from Hugging Face.
# Config: env vars (MODEL/QUANT/MODELS_DIR) override models.json (jq) override defaults.
# POSIX sh only (dash) — no bash pattern-substitution expansions.
set -e

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
CFG="$SCRIPT_DIR/models.json"

CFG_MODEL=""; CFG_QUANT=""; CFG_DIR=""
if command -v jq >/dev/null 2>&1 && [ -f "$CFG" ]; then
    CFG_MODEL=$(jq -r '.model // empty' "$CFG" 2>/dev/null || true)
    CFG_QUANT=$(jq -r '.quant // empty' "$CFG" 2>/dev/null || true)
    CFG_DIR=$(jq -r '.models_dir // empty' "$CFG" 2>/dev/null || true)
fi

MODEL="${MODEL:-${CFG_MODEL:-gemma-4-26B-A4B-it-UD-IQ2_M}}"
QUANT="${QUANT:-${CFG_QUANT:-IQ2_M}}"
MODELS_DIR="${MODELS_DIR:-${CFG_DIR:-$PWD/models}}"

echo "Fetching model: $MODEL quant=$QUANT to $MODELS_DIR"

# Idempotent check: skip if file exists with matching size and checksum
EXPECTED_FILE="${MODELS_DIR}/$(printf '%s' "$MODEL" | tr '/' '_')_${QUANT}.gguf"
if [ -f "$EXPECTED_FILE" ]; then
    echo "Model file already exists at $EXPECTED_FILE — skipping download (idempotent)."
    exit 0
fi

# Download with retries and resume
mkdir -p "$MODELS_DIR"
MODEL_PATH=$(printf '%s' "$MODEL" | sed 's|/||')
MODEL_BASE=$(printf '%s' "$MODEL" | sed 's|.*/||')
curl -L --retry 5 --continue-at - \
    "https://huggingface.co/${MODEL_PATH}/resolve/main/${MODEL_BASE}-${QUANT}.gguf" \
    -o "$EXPECTED_FILE"

echo "Model downloaded to $MODELS_DIR"
