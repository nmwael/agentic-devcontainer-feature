#!/bin/bash
# devcontainer features test — opencode-agents (auto-generated, default options).
# WITH_LIBRARY=true by default: full agentic payload + library books + opencode CLI.
set -e

fail() { echo "FAIL: $*"; exit 1; }
ok() { echo "ok: $*"; }

[ -x /usr/local/bin/opencode ] || fail "opencode CLI not on PATH"
ok "opencode CLI on PATH: $(opencode --version 2>/dev/null || echo present)"

D=/usr/local/share/opencode-agents
[ -f "$D/AGENTS.md" ] || fail "AGENTS.md not shipped"
[ -f "$D/AGENTS_LIFECYCLE.md" ] || fail "AGENTS_LIFECYCLE.md not shipped"
[ -f "$D/scaffold.sh" ] || fail "scaffold.sh not shipped"
[ -x "$D/scaffold.sh" ] || fail "scaffold.sh not executable"
[ -f "$D/generate-opencode.sh" ] || fail "generate-opencode.sh not shipped"
[ -f "$D/generate-opencode.jq" ] || fail "generate-opencode.jq not shipped"
[ -f "$D/opencode.json.fragment" ] || fail "opencode.json.fragment not shipped"
ok "core scaffolds shipped to $D"

[ -d "$D/.opencode/agent" ] || fail ".opencode/agent role dir missing"
ROLE_COUNT="$(find "$D/.opencode/agent" -name '*.md' | wc -l)"
[ "$ROLE_COUNT" -ge 1 ] || fail "no agent role definitions shipped"
ok "agent role definitions shipped: $ROLE_COUNT file(s)"

[ -f "$D/library/EXTENSIONS.md" ] || fail "library/EXTENSIONS.md missing"
[ -f "$D/library/release-it.mini.md" ] || fail "library/release-it.mini.md missing"
[ -d "$D/library/ai-researcher" ] || fail "WITH_LIBRARY=true: ai-researcher book dir missing"
BOOK_COUNT="$(find "$D/library/ai-researcher" -name '*.md' | wc -l)"
[ "$BOOK_COUNT" -ge 1 ] || fail "no ai-researcher reference books shipped"
ok "library shipped: ai-researcher $BOOK_COUNT book(s) + shared mini-books"

echo "PASS: opencode-agents"