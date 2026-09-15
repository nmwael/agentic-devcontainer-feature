#!/bin/sh
# write-bifrost-config.sh — materialize a bifrost v2 config file from the shared
# stack.json manifest (written by the models feature), one provider per llama-server
# upstream. Model-id routing: each provider's keys[].models allowlist is "{name}*",
# so a request for "gemma4-26b-a4b-s0" is routed to the 26B upstream on its port.
#
# Usage: write-bifrost-config.sh [stack.json] [output.json] [llama_port_fallback]
# Requires: jq. Without jq it falls back to copying the shipped legacy template.
set -e

STACK_FILE="${1:-/usr/local/share/llm-lab/stack.json}"
OUT_FILE="${2:-/usr/local/share/llm-lab/bifrost/config/bifrost.json}"
LLAMA_PORT="${3:-${LLAMA_PORT:-8089}}"
LEGACY_TEMPLATE="${4:-}"

mkdir -p "$(dirname "$OUT_FILE")"

if command -v jq >/dev/null 2>&1; then
    if [ -f "$STACK_FILE" ] && jq -e . "$STACK_FILE" >/dev/null 2>&1; then
        # One provider per model upstream; keys[].models routes "{name}*" model ids here.
        jq -n --slurpfile s "$STACK_FILE" \
            '{ "$schema": "https://www.getbifrost.ai/schema",
               providers: (
                   reduce $s[0].models[] as $m ({};
                       .[$m.name] = {
                           keys:    [ { name: "local", value: "no-key", models: [($m.name + "*")], weight: 1.0 } ],
                           network_config: { base_url: ("http://127.0.0.1:" + ($m.port | tostring) + "/v1") },
                           custom_provider_config: { base_provider_type: "openai" }
                       }
                   )
               ),
               config_store: { enabled: false } }' >"$OUT_FILE"
        echo "bifrost.json materialized from stack.json (multi-upstream)"
    else
        # No manifest: single legacy upstream fallback (llama-server on LLAMA_PORT).
        jq -n --arg port "$LLAMA_PORT" \
            '{ "$schema": "https://www.getbifrost.ai/schema",
               providers: {
                   llama: {
                       keys:    [ { name: "local", value: "no-key", models: ["*"], weight: 1.0 } ],
                       network_config: { base_url: ("http://127.0.0.1:" + $port + "/v1") },
                       custom_provider_config: { base_provider_type: "openai" }
                   }
               },
               config_store: { enabled: false } }' >"$OUT_FILE"
        echo "bifrost.json materialized for single upstream on port $LLAMA_PORT (no stack.json)"
    fi
else
    if [ -n "$LEGACY_TEMPLATE" ] && [ -f "$LEGACY_TEMPLATE" ]; then
        cp -f "$LEGACY_TEMPLATE" "$OUT_FILE"
        echo "WARNING: jq unavailable — bifrost.json keeps template defaults (port 8089)"
    else
        echo "WARNING: jq unavailable and no legacy template provided — leaving $OUT_FILE absent"
    fi
fi