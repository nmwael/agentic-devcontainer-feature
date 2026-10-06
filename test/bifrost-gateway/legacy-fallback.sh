#!/bin/bash
# devcontainer features test — bifrost-gateway "legacy-fallback" scenario.
# No models feature present (no stack.json): the config generator must fall back
# to a single upstream on the configured LLAMA_PORT (8091 here); bifrost appends
# the /v1 path itself.
set -e

fail() { echo "FAIL: $*"; exit 1; }
ok() { echo "ok: $*"; }

CFG=/usr/local/share/llm-lab/bifrost/config/bifrost.json
[ -f "$CFG" ] || fail "bifrost config missing"
jq -e '.providers.llama.network_config.base_url | endswith(":8091")' "$CFG" >/dev/null 2>&1 \
    || fail "expected single-upstream config on LLAMA_PORT :8091"
ok "legacy fallback honors LLAMA_PORT=8091 (no /v1 in base_url)"

jq -e '.providers.llama.keys[0].models == ["*"]' "$CFG" >/dev/null 2>&1 \
    || fail "expected legacy fallback models allowlist to stay [\"*\"] (single provider)"
ok "legacy fallback keeps the [\"*\"] catch-all allowlist"

echo "PASS: bifrost-gateway legacy-fallback"