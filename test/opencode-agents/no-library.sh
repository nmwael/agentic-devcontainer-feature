#!/bin/bash
# devcontainer features test — opencode-agents "no-library" scenario
# (WITH_LIBRARY=false): agents stay fully functional, books are skipped.
set -e

fail() { echo "FAIL: $*"; exit 1; }
ok() { echo "ok: $*"; }

[ -x /usr/local/bin/opencode ] || fail "opencode CLI missing"
D=/usr/local/share/opencode-agents
[ -f "$D/AGENTS.md" ] || fail "AGENTS.md missing even without library"
[ -f "$D/library/EXTENSIONS.md" ] || fail "library/EXTENSIONS.md must always ship"
ok "core scaffold present without library"

if [ -d "$D/library/ai-researcher" ]; then
    fail "WITH_LIBRARY=false but ai-researcher books were shipped"
fi
ok "no shipped library books (WITH_LIBRARY=false honored)"

echo "PASS: opencode-agents no-library"