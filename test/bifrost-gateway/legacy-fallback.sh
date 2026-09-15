#!/bin/bash
# devcontainer features test — bifrost-gateway "legacy-fallback" scenario.
# No models feature present (no stack.json): the config generator must fall back
# to a single upstream on the configured LLAMA_PORT (8091 here), ending in /v1.
set -e

fail() { echo "FAIL: $*"; exit 1; }
ok() { echo "ok: $*"; }

CFG=/usr/local/share/llm-lab/bifrost/config/bifrost.json
[ -f "$CFG" ] || fail "bifrost config missing"
jq -e '.providers.llama.network_config.base_url | endswith(":8091/v1")' "$CFG" >/dev/null 2>&1 \
    || fail "expected single-upstream config on LLAMA_PORT :8091/v1"
ok "legacy fallback honors LLAMA_PORT=8091 (/v1 endpoint)"

echo "PASS: bifrost-gateway legacy-fallback"