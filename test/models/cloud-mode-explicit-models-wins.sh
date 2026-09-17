#!/bin/bash
# devcontainer features test — models "cloud-mode-explicit-models-wins" scenario:
# CLOUD_MODE=true is ignored when explicit MODELS are supplied; the local
# slot-pinned stack is written instead.
set -e

fail() { echo "FAIL: $*"; exit 1; }
ok() { echo "ok: $*"; }

STACK=/usr/local/share/llm-lab/stack.json
[ -f "$STACK" ] || fail "stack.json missing"

[ "$(jq -r '.cloud // false' "$STACK")" = "false" ] || fail "expected .cloud == false when MODELS supplied alongside CLOUD_MODE"
[ "$(jq '.models | length' "$STACK")" -eq 1 ] || fail "expected the single explicit model"
[ "$(jq -r '.models[0].name' "$STACK")" = "e5-26b" ] || fail "expected explicit model e5-26b"
[ "$(jq -r '.roles.architect.model' "$STACK")" = "e5-26b" ] || fail "architect must pin to explicit local model"
ok "explicit MODELS won over CLOUD_MODE (stack.cloud=false, models=[e5-26b])"

echo "PASS: models cloud-mode-explicit-models-wins"