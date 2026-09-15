#!/bin/bash
# devcontainer features test — gpu-bridge duplicate/idempotency mode.
# The feature has been installed TWICE (randomized + default option sets). It
# must not conflict; on a non-WSL2 runner the second install is a no-op stub.
set -e

fail() { echo "FAIL: $*"; exit 1; }
ok() { echo "ok: $*"; }

if [ -d /usr/lib/wsl/lib ]; then
    [ -x /usr/local/bin/ensure-bridge.sh ] || fail "ensure-bridge.sh missing after re-install"
    ok "ensure-bridge.sh present after duplicate install (WSL2)"
else
    ok "not WSL2 — duplicate install was a no-op stub"
fi

echo "PASS: gpu-bridge duplicate"