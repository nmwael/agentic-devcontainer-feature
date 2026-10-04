#!/bin/bash
# devcontainer features test — opencode-agents duplicate/idempotency mode.
# (The opencode CLI is a separate feature; not asserted here.)
set -e

fail() { echo "FAIL: $*"; exit 1; }
ok() { echo "ok: $*"; }

D=/usr/local/share/opencode-agents
[ -f "$D/AGENTS.md" ] || fail "AGENTS.md missing after re-install"
[ -x "$D/scaffold.sh" ] || fail "scaffold.sh not executable after re-install"
[ -f "$D/generate-opencode.sh" ] || fail "generate-opencode.sh missing after re-install"
ok "scaffold intact after duplicate install"

echo "PASS: opencode-agents duplicate"
