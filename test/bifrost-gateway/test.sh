#!/bin/bash
# devcontainer features test — bifrost-gateway (auto-generated, default options).
# The feature is built in ISOLATION here (no models feature -> no stack.json),
# so write-bifrost-config.sh must fall back to the legacy single-upstream config
# on the default LLAMA_PORT (8089), ending in /v1 (llama-server OpenAI endpoint).
set -e

fail() { echo "FAIL: $*"; exit 1; }
ok() { echo "ok: $*"; }

[ -x /usr/local/bin/start-bifrost ] || fail "start-bifrost launcher missing on PATH"
ok "start-bifrost launcher on PATH"

CFG=/usr/local/share/llm-lab/bifrost/config/bifrost.json
[ -f "$CFG" ] || fail "bifrost config missing at $CFG"
jq -e . "$CFG" >/dev/null 2>&1 || fail "bifrost config is not valid JSON"
ok "bifrost config present + valid JSON"

jq -e '.providers.llama.network_config.base_url | endswith(":8089/v1")' "$CFG" >/dev/null 2>&1 \
    || fail "expected legacy single-upstream on :8089/v1 (no stack.json present)"
ok "legacy fallback upstream resolves to http://127.0.0.1:8089/v1"

[ -x /usr/local/share/llm-lab/bifrost/write-bifrost-config.sh ] || fail "write-bifrost-config.sh not installed"
ok "write-bifrost-config.sh installed"

command -v node >/dev/null 2>&1 || fail "node runtime missing (bifrost is a node app)"
ok "node runtime present: $(node --version 2>/dev/null)"

[ -s /usr/local/share/llm-lab/bifrost/version ] || fail "bifrost version stamp missing"
ok "bifrost version: $(cat /usr/local/share/llm-lab/bifrost/version)"

echo "PASS: bifrost-gateway"