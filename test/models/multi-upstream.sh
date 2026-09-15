#!/bin/bash
# devcontainer features test — models "multi-upstream" scenario: 2 models on
# distinct ports, 3 roles bound to valid slots. stack.json must reflect both.
set -e

fail() { echo "FAIL: $*"; exit 1; }
ok() { echo "ok: $*"; }

STACK=/usr/local/share/llm-lab/stack.json
[ -f "$STACK" ] || fail "stack.json missing"

[ "$(jq '.models | length' "$STACK")" -eq 2 ] || fail "expected 2 models, got $(jq '.models | length' "$STACK")"
[ "$(jq '.roles | length' "$STACK")" -eq 3 ] || fail "expected 3 roles, got $(jq '.roles | length' "$STACK")"
ok "2 models + 3 roles materialized in stack.json"

jq -e '.roles.architect.model == "e5-26b" and .roles.architect.slot == 0' "$STACK" >/dev/null 2>&1 \
    || fail "architect role miswired"
jq -e '.models | map(.port) | unique | length == 2' "$STACK" >/dev/null 2>&1 \
    || fail "model ports are not distinct (18081/18082 required)"
ok "role wiring + distinct ports verified"

echo "PASS: models multi-upstream"