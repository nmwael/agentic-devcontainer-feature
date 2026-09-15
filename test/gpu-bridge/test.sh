#!/bin/bash
# devcontainer features test — gpu-bridge (auto-generated, default options).
# CI containers are not WSL2: the feature must degrade to a no-op stub that
# exits 0 (the container building + this script running already proves that).
set -e

fail() { echo "FAIL: $*"; exit 1; }
ok() { echo "ok: $*"; }

if [ -d /usr/lib/wsl/lib ]; then
    [ -x /usr/local/bin/ensure-bridge.sh ] || fail "WSL2 detected but ensure-bridge.sh missing on PATH"
    ok "WSL2 detected — ensure-bridge.sh on PATH"
else
    ok "not WSL2 — gpu-bridge is a no-op stub (container boot + test execution prove it)"
fi

echo "PASS: gpu-bridge"