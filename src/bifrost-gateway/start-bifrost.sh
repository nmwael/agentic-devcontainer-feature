#!/bin/sh
# Bifrost gateway launcher honoring BIFROST_PORT / config
set -e
BIFROST_DIR="${BIFROST_DIR:-/usr/local/share/llm-lab/bifrost}"
PORT_ENV="${BIFROST_PORT:-${PORT:-8082}}"
export BIFROST_PORT="$PORT_ENV"
export LLAMA_PORT="${LLAMA_PORT:-8089}"
exec node "$BIFROST_DIR/node_modules/@maximhq/bifrost/bin.js" "$PORT_ENV"
