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

[ -d "$D/.opencode/agents" ] || fail ".opencode/agents role dir missing"
ROLE_COUNT="$(find "$D/.opencode/agents" -name '*.md' | wc -l)"
[ "$ROLE_COUNT" -ge 1 ] || fail "no agent role definitions shipped"
ok "agent role definitions shipped: $ROLE_COUNT file(s)"

grep -q '^## Delegation JSON envelope$' "$D/AGENTS.md" || fail "AGENTS.md missing delegation JSON envelope contract"
grep -q '^## Orchestration Flow$' "$D/AGENTS.md" || fail "AGENTS.md missing orchestration flow contract"
grep -q 'Delegation JSON envelope' "$D/.opencode/agents/coder.md" || fail "coder.md missing JSON envelope pointer"
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
    ROLE_FILE="$D/.opencode/agents/$role.md"
    [ -f "$ROLE_FILE" ] || fail "role prompt missing: $ROLE_FILE"
    grep -q '^description:' "$ROLE_FILE" || fail "role prompt $role.md: no ^description: line"
    grep -q '^mode:' "$ROLE_FILE" || fail "role prompt $role.md: no ^mode: line"
    if grep -q '^model:' "$ROLE_FILE"; then
        fail "role prompt $role.md: must not pin ^model:"
    fi
done
ok "six self-contained role prompts ship description + mode, no model pin"

[ ! -f "$D/.opencode/agents/agent-roles.md" ] || fail "stale agent-roles.md must not ship"
ok "stale agent-roles.md absent"

if grep -rqE '3d-designer|ai-researcher' "$D"; then
    fail "removed role name (3d-designer|ai-researcher) still present under $D"
fi
ok "no trace of removed roles under $D"

echo "PASS: opencode-agents default scenario"

# --- regression: scaffold.sh guard + preserve (opencode-agents 1.5.1) -------------
# Guard: WORKSPACE=/ must be rejected (prevents /opencode.json pollution)
SCRATCH=$(mktemp -d)
WORKSPACE=/ /usr/local/share/opencode-agents/scaffold.sh >/dev/null 2>&1 && fail "scaffold.sh must reject WORKSPACE=/"
[ ! -f "/opencode.json" ] || fail "scaffold.sh must not write /opencode.json when WORKSPACE=/"
ok "scaffold.sh rejects WORKSPACE=/ (exit non-zero, no /opencode.json)"

# Preserve: existing non-empty config must not be clobbered without OVERWRITE=true
WORKSPACE="$SCRATCH" /usr/local/share/opencode-agents/scaffold.sh >/dev/null 2>&1
# Add a custom provider to the generated config (simulates user edit)
jq '.enabled_providers += ["custom"]' "$SCRATCH/opencode.json" >"$SCRATCH/opencode.json.tmp" && mv "$SCRATCH/opencode.json.tmp" "$SCRATCH/opencode.json"
CUSTOM_BEFORE=$(jq -r '.enabled_providers | join(",")' "$SCRATCH/opencode.json")
# Re-run scaffold (without OVERWRITE) — should preserve the custom provider
WORKSPACE="$SCRATCH" /usr/local/share/opencode-agents/scaffold.sh >/dev/null 2>&1
CUSTOM_AFTER=$(jq -r '.enabled_providers | join(",")' "$SCRATCH/opencode.json")
[ "$CUSTOM_BEFORE" = "$CUSTOM_AFTER" ] || fail "scaffold.sh clobbered existing config without OVERWRITE=true"
ok "scaffold.sh preserves existing config without OVERWRITE=true"

# OVERWRITE=true must regenerate
WORKSPACE="$SCRATCH" OVERWRITE=true /usr/local/share/opencode-agents/scaffold.sh >/dev/null 2>&1
CUSTOM_AFTER_OVERWRITE=$(jq -r '.enabled_providers | join(",")' "$SCRATCH/opencode.json")
[ "$CUSTOM_AFTER_OVERWRITE" != "$CUSTOM_BEFORE" ] || fail "OVERWRITE=true should regenerate config"
ok "OVERWRITE=true regenerates config"

# Cleanup
rm -rf "$SCRATCH"

echo "PASS: scaffold.sh guard + preserve regression"
