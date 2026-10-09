#!/bin/bash
# devcontainer features test — models "mtp-rejected" scenario: draft-mtp with
# parallel > 1 fails validation, so install.sh must fall back to the built-in
# default stack rather than emitting an invalid MTP manifest.
set -e

fail() { echo "FAIL: $*"; exit 1; }
ok() { echo "ok: $*"; }

STACK=/usr/local/share/llm-lab/stack.json
[ -f "$STACK" ] || fail "stack.json missing"

[ "$(jq -r '.models[0].name' "$STACK")" = "gemma4-26b-a4b" ] \
    || fail "invalid MTP profile did not fall back to default (got $(jq -r '.models[0].name' "$STACK"))"
[ "$(jq -r '.models[0].spec_type // "null"' "$STACK")" = "null" ] \
    || fail "rejected profile leaked spec_type into stack.json"
ok "parallel>1 draft-mtp rejected; default stack retained (no spec_type)"

echo "PASS: models mtp-rejected"
