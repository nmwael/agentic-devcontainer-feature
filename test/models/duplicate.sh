#!/bin/bash
# devcontainer features test — models duplicate/idempotency mode.
# Two installs with different option sets must both leave a consistent stack.
set -e

fail() { echo "FAIL: $*"; exit 1; }
ok() { echo "ok: $*"; }

[ -x /usr/local/share/llm-lab/models/fetch-models.sh ] || fail "fetch-models.sh missing after re-install"
ok "fetch-models.sh present after duplicate install"

STACK=/usr/local/share/llm-lab/stack.json
[ -f "$STACK" ] || fail "stack.json missing after re-install"
jq -e . "$STACK" >/dev/null 2>&1 || fail "stack.json invalid after re-install"
[ "$(jq '.models | length' "$STACK")" -ge 1 ] || fail "stack.json lost its models after re-install"
ok "stack.json intact after duplicate install ($(jq '.models | length' "$STACK") model(s))"

echo "PASS: models duplicate"