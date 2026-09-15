#!/bin/sh
# generate-opencode.sh — materialize opencode.json from the shared stack.json
# manifest using the bundled generate-opencode.jq program.
# Usage: generate-opencode.sh [stack.json] [output.json]
set -e

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
STACK="${1:-/usr/local/share/llm-lab/stack.json}"
OUT="${2:-/dev/stdout}"

if [ ! -f "$STACK" ]; then
    echo "WARNING: stack.json not found at $STACK" >&2
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "WARNING: jq unavailable — cannot generate opencode.json" >&2
    exit 1
fi

jq -f "$SCRIPT_DIR/generate-opencode.jq" "$STACK" >"$OUT"
echo "opencode.json generated from $STACK"