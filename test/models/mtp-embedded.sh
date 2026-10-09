#!/bin/bash
# devcontainer features test — models "mtp-embedded" scenario: a profile that
# embeds MTP speculative decoding (spec_type draft-mtp with parallel 1) must be
# materialized into stack.json with both fields preserved.
set -e

fail() { echo "FAIL: $*"; exit 1; }
ok() { echo "ok: $*"; }

STACK=/usr/local/share/llm-lab/stack.json
[ -f "$STACK" ] || fail "stack.json missing"

[ "$(jq '.models | length' "$STACK")" -eq 1 ] || fail "expected the single MTP model"
[ "$(jq -r '.models[0].name' "$STACK")" = "mtp-model" ] \
    || fail "expected model mtp-model, got $(jq -r '.models[0].name' "$STACK")"
[ "$(jq -r '.models[0].spec_type' "$STACK")" = "draft-mtp" ] || fail "spec_type draft-mtp not preserved"
[ "$(jq -r '.models[0].spec_draft_n_max' "$STACK")" = "4" ] || fail "spec_draft_n_max 4 not preserved"
[ "$(jq -r '.models[0].parallel' "$STACK")" = "1" ] || fail "MTP requires parallel == 1"
ok "mtp model materialized with spec_type=draft-mtp, spec_draft_n_max=4, parallel=1"

echo "PASS: models mtp-embedded"
