#!/bin/sh
# Bifrost gateway launcher honoring BIFROST_PORT / config
set -e
BIFROST_DIR="${BIFROST_DIR:-/usr/local/share/llm-lab/bifrost}"
PORT_ENV="${BIFROST_PORT:-${PORT:-8082}}"
export BIFROST_PORT="$PORT_ENV"
export LLAMA_PORT="${LLAMA_PORT:-8089}"

# bifrost v2.2.x takes the port as a -port FLAG, not a positional argument.
# Passing it positionally is silently ignored and the server falls back to its
# own default (127.0.0.1:8080), leaving BIFROST_PORT unreachable.
# -host must also be set explicitly, otherwise it binds to "localhost" only.
HOST_ENV="${BIFROST_HOST:-0.0.0.0}"

# bifrost reads its config from <app-dir>/config.json (default app-dir is
# /root/.config/bifrost), while write-bifrost-config.sh generates
# <BIFROST_DIR>/config/bifrost.json. Without this sync bifrost logs
# "config file not found ... initializing with default values" and comes up
# with zero providers, so every request fails with
# "could not auto resolve a provider".
GENERATED_CONFIG="$BIFROST_DIR/config/bifrost.json"
APP_DIR="${BIFROST_APP_DIR:-${HOME:-/root}/.config/bifrost}"
if [ -f "$GENERATED_CONFIG" ]; then
    mkdir -p "$APP_DIR"
    cp -f "$GENERATED_CONFIG" "$APP_DIR/config.json"
fi

# exec preserves the pid so this write lands on the node wrapper; the
# bifrost-http-0 child inherits the score at fork — one write covers both.
if ! printf '%s\n' "${BIFROST_OOM_SCORE_ADJ:--100}" >/proc/self/oom_score_adj 2>/dev/null; then
    echo "[start-bifrost] could not set oom_score_adj (needs CAP_SYS_RESOURCE) — continuing" >&2
fi

exec node "$BIFROST_DIR/node_modules/@maximhq/bifrost/bin.js" -port "$PORT_ENV" -host "$HOST_ENV"
