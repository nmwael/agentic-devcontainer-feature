#!/bin/bash
# devcontainer features test — bifrost-gateway duplicate/idempotency mode.
set -e

fail() { echo "FAIL: $*"; exit 1; }
ok() { echo "ok: $*"; }

[ -x /usr/local/bin/start-bifrost ] || fail "start-bifrost missing after re-install"
[ -f /usr/local/share/llm-lab/bifrost/config/bifrost.json ] || fail "bifrost config missing after re-install"
ok "start-bifrost + config intact after duplicate install"

echo "PASS: bifrost-gateway duplicate"