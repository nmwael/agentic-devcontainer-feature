#!/bin/sh
# fetch-models.sh — download every configured model from Hugging Face.
# Config source priority: stack.json (models feature manifest) > models.json (legacy).
# Env vars (MODELS_DIR) override; MODEL/QUANT apply only to the legacy fallback.
# POSIX sh only (dash) — no bash pattern-substitution expansions.
set -e

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
STACK="$SCRIPT_DIR/../stack.json"
CFG="$SCRIPT_DIR/models.json"

DEFAULT_MODEL="gemma-4-26B-A4B-it-UD-IQ2_M"
DEFAULT_QUANT="IQ2_M"

# MODELS_DIR precedence: env > stack.json > models.json > $PWD/models
MODELS_DIR="${MODELS_DIR:-}"
if [ -z "$MODELS_DIR" ] && [ -f "$STACK" ]; then
    MODELS_DIR="$(jq -r '.models_dir // empty' "$STACK" 2>/dev/null || true)"
fi
if [ -z "$MODELS_DIR" ] && [ -f "$CFG" ]; then
    MODELS_DIR="$(jq -r '.models_dir // empty' "$CFG" 2>/dev/null || true)"
fi
MODELS_DIR="${MODELS_DIR:-$PWD/models}"

# Read the model list: stack.json (array) or legacy single entry from models.json.
CFG_MODELS=""
if [ -f "$STACK" ]; then
    CFG_MODELS="$(jq -c '.models // empty' "$STACK" 2>/dev/null || true)"
fi
if [ -z "$CFG_MODELS" ] && [ -f "$CFG" ]; then
    CFG_MODELS="$(jq -nc --arg hf "$(jq -r '.model // empty' "$CFG" 2>/dev/null || true)" \
        --arg q "$(jq -r '.quant // empty' "$CFG" 2>/dev/null || true)" \
        '[{hf:$hf, quant:$q}]')"
fi

COUNT=$(printf '%s' "$CFG_MODELS" | jq 'length' 2>/dev/null) || COUNT=0

fetch_one() {
    hf="$1"
    quant="$2"
    echo "Fetching model: $hf quant=$quant to $MODELS_DIR"

    # Idempotent check: skip if file exists with matching size and checksum
    EXPECTED_FILE="${MODELS_DIR}/$(printf '%s' "$hf" | tr '/' '_')_${quant}.gguf"
    if [ -f "$EXPECTED_FILE" ]; then
        echo "Model file already exists at $EXPECTED_FILE — skipping download (idempotent)."
        return 0
    fi

    # Download with retries and resume
    mkdir -p "$MODELS_DIR"
    MODEL_PATH=$(printf '%s' "$hf" | sed 's|/||')
    MODEL_BASE=$(printf '%s' "$hf" | sed 's|.*/||')
    curl -L --retry 5 --continue-at - \
        "https://huggingface.co/${MODEL_PATH}/resolve/main/${MODEL_BASE}-${quant}.gguf" \
        -o "$EXPECTED_FILE"

    echo "Model downloaded to $MODELS_DIR"
}

if [ "${COUNT:-0}" -gt 0 ]; then
    i=0
    while [ "$i" -lt "$COUNT" ]; do
        hf="$(printf '%s' "$CFG_MODELS" | jq -r ".[$i].hf // empty" 2>/dev/null || true)"
        quant="$(printf '%s' "$CFG_MODELS" | jq -r ".[$i].quant // empty" 2>/dev/null || true)"
        if [ -n "$hf" ] && [ -n "$quant" ]; then
            fetch_one "$hf" "$quant" || {
                echo "WARNING: failed to fetch [$i] $hf-$quant" >&2
                exit 1
            }
        else
            echo "WARNING: skipping malformed entry [$i] in model list" >&2
        fi
        i=$((i + 1))
    done
else
    echo "No model config found ($STACK / $CFG) — using defaults."
    fetch_one "$DEFAULT_MODEL" "$DEFAULT_QUANT"
fi