#!/bin/bash
# devcontainer features test — models (auto-generated, default options).
# Default model stack: single gemma4-26b-a4b model on :8089, 8 roles pinned
# to slots, shared stack.json manifest written, back-compat models.json mirror.
set -e

fail() { echo "FAIL: $*"; exit 1; }
ok() { echo "ok: $*"; }

[ -x /usr/local/share/llm-lab/models/fetch-models.sh ] || fail "fetch-models.sh missing"
ok "fetch-models.sh installed (executable)"

STACK=/usr/local/share/llm-lab/stack.json
[ -f "$STACK" ] || fail "stack.json manifest missing"
jq -e . "$STACK" >/dev/null 2>&1 || fail "stack.json is not valid JSON"
ok "stack.json manifest present + valid JSON"

[ "$(jq '.models | length' "$STACK")" -ge 1 ] || fail "stack.json declares no models"
[ "$(jq '.roles | length' "$STACK")" -ge 1 ] || fail "stack.json declares no roles"
ok "stack.json: $(jq '.models | length' "$STACK") model(s), $(jq '.roles | length' "$STACK") role(s)"

# Default manifest reproduces the single-model legacy stack exactly.
jq -e '.models[0].name == "gemma4-26b-a4b" and .models[0].port == 8089 and .models[0].context == 65536' "$STACK" \
    >/dev/null 2>&1 || fail "default model does not match single-model legacy stack"
ok "default model matches legacy stack (gemma4-26b-a4b :8089 ctx 65536)"

[ -f /usr/local/share/llm-lab/models/models.json ] || fail "models.json back-compat mirror missing"
ok "models.json back-compat mirror present"

grep -q "MODELS_DIR" /etc/environment || fail "MODELS_DIR not exported in /etc/environment"
ok "MODELS_DIR exported in /etc/environment"

echo "PASS: models"