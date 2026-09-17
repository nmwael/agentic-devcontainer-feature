#!/bin/bash
# devcontainer features test — models "cloud-mode" scenario: CLOUD_MODE=true with
# no explicit MODELS writes a cloud-only stack.json (empty models, cloud:true,
# every role carrying a hosted opencode model id).
set -e

fail() { echo "FAIL: $*"; exit 1; }
ok() { echo "ok: $*"; }

STACK=/usr/local/share/llm-lab/stack.json
[ -f "$STACK" ] || fail "stack.json missing"

[ "$(jq -r '.cloud // false' "$STACK")" = "true" ] || fail "expected .cloud == true"
[ "$(jq -r '.cloud_provider // "opencode"' "$STACK")" = "opencode" ] || fail "expected cloud_provider == opencode"
[ "$(jq '.models | length' "$STACK")" -eq 0 ] || fail "expected empty models array in cloud mode"
[ "$(jq '.roles | length' "$STACK")" -ge 1 ] || fail "expected at least one role in cloud stack"
jq -e '.roles | to_entries | all(.value.model != null and (.value.model | type == "string") and (.value.model | length > 0))' "$STACK" >/dev/null 2>&1 \
    || fail "every cloud role must carry a non-empty hosted model id"
ok "cloud stack: cloud=true, 0 models, $(jq '.roles | length' "$STACK") role(s) -> hosted opencode ids"

echo "PASS: models cloud-mode"