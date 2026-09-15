#!/bin/bash
# devcontainer features test — opencode-agents duplicate/idempotency mode.
set -e

fail() { echo "FAIL: $*"; exit 1; }
ok() { echo "ok: $*"; }

[ -x /usr/local/bin/opencode ] || fail "opencode CLI missing after re-install"
[ -f /usr/local/share/opencode-agents/AGENTS.md ] || fail "AGENTS.md missing after re-install"
ok "opencode CLI + scaffold intact after duplicate install"

echo "PASS: opencode-agents duplicate"