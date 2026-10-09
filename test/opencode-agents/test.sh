#!/bin/bash
# devcontainer features test — opencode-agents (auto-generated, default options).
# WITH_LIBRARY=true by default: full agentic payload + library books.
set -e

fail() { echo "FAIL: $*"; exit 1; }
ok() { echo "ok: $*"; }

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

grep -q '^## Delegation JSON envelope$' "$D/AGENTS.md" || fail "AGENTS.md missing delegation JSON envelope contract"
grep -q '^## Orchestration Flow$' "$D/AGENTS.md" || fail "AGENTS.md missing orchestration flow contract"
grep -q 'Delegation JSON envelope' "$D/.opencode/agent/coder.md" || fail "coder.md missing JSON envelope pointer"
ok "delegation JSON envelope contract shipped"

[ -f "$D/library/EXTENSIONS.md" ] || fail "library/EXTENSIONS.md missing"
[ -f "$D/library/release-it.mini.md" ] || fail "library/release-it.mini.md missing"
[ -d "$D/library/skills" ] || fail "WITH_LIBRARY=true: library/skills dir missing"
SKILL_COUNT="$(find "$D/library/skills" -name '*.md' | wc -l)"
[ "$SKILL_COUNT" -ge 1 ] || fail "WITH_LIBRARY=true: library/skills has no .md files"
ok "library present (WITH_LIBRARY=true): skills=$SKILL_COUNT"

[ ! -d "$D/library/ai-researcher" ] || fail "per-role ai-researcher books must not ship"
ok "no per-role library book dirs shipped"

for role in architect coder researcher reviewer ui artist; do
    ROLE_FILE="$D/.opencode/agent/$role.md"
    [ -f "$ROLE_FILE" ] || fail "role prompt missing: $ROLE_FILE"
    grep -q '^description:' "$ROLE_FILE" || fail "role prompt $role.md: no ^description: line"
    grep -q '^mode:' "$ROLE_FILE" || fail "role prompt $role.md: no ^mode: line"
    if grep -q '^model:' "$ROLE_FILE"; then
        fail "role prompt $role.md: must not pin ^model:"
    fi
done
ok "six self-contained role prompts ship description + mode, no model pin"

[ ! -f "$D/.opencode/agent/agent-roles.md" ] || fail "stale agent-roles.md must not ship"
ok "stale agent-roles.md absent"

if grep -rqE '3d-designer|ai-researcher' "$D"; then
    fail "removed role name (3d-designer|ai-researcher) still present under $D"
fi
ok "no trace of removed roles under $D"

echo "PASS: opencode-agents default scenario"
