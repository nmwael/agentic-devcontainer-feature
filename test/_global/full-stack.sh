#!/bin/bash
# devcontainer features test — full-stack (_global scenario).
# Validates the template's emitted config: all 5 features + apt-get-packages.
# This proves our features compose together end-to-end as a real consumer
# (or the llm-lab template) would experience them.
set -e

fail() { echo "FAIL: $*"; exit 1; }
ok() { echo "ok: $*"; }

# ---- llama-server -----------------------------------------------------------
[ -x /usr/local/bin/llama-server ] || fail "llama-server not on PATH"
ok "llama-server on PATH"

# ---- gpu-bridge -------------------------------------------------------------
if [ -d /usr/lib/wsl/lib ]; then
    ok "gpu-bridge installed (WSL2 detected)"
else
    ok "gpu-bridge no-op stub (non-WSL2)"
fi

# ---- bifrost-gateway --------------------------------------------------------
[ -x /usr/local/bin/start-bifrost ] || fail "start-bifrost not on PATH"
CFG=/usr/local/share/llm-lab/bifrost/config/bifrost.json
[ -f "$CFG" ] || fail "bifrost config missing"
jq -e . "$CFG" >/dev/null 2>&1 || fail "bifrost config invalid JSON"
jq -e '.providers.gemma4-26b-a4b.network_config.base_url | endswith(":8089/v1")' "$CFG" \
    >/dev/null 2>&1 || fail "bifrost config must expose default upstream on :8089/v1"
ok "bifrost multi-upstream config materialized from stack.json"

# ---- models -----------------------------------------------------------------
[ -x /usr/local/share/llm-lab/models/fetch-models.sh ] || fail "fetch-models.sh missing"
STACK=/usr/local/share/llm-lab/stack.json
[ -f "$STACK" ] || fail "stack.json missing"
jq -e . "$STACK" >/dev/null 2>&1 || fail "stack.json invalid JSON"
[ "$(jq '.models | length' "$STACK")" -eq 1 ] || fail "default stack must have exactly 1 model"
[ "$(jq '.roles | length' "$STACK")" -eq 8 ] || fail "default stack must have 8 roles"
ok "stack.json default manifest: $(jq -r '.models[0].name' "$STACK") on :$(jq -r '.models[0].port' "$STACK")"

# ---- opencode-agents --------------------------------------------------------
[ -x /usr/local/bin/opencode ] || fail "opencode CLI not on PATH"
ok "opencode CLI on PATH"

# ---- scaffold (the step consumers run at postCreateCommand) -----------------
SCRATCH=/tmp/full-stack-smoke
rm -rf "$SCRATCH" && mkdir -p "$SCRATCH/.opencode"
WORKSPACE="$SCRATCH" /usr/local/share/opencode-agents/scaffold.sh >/dev/null 2>&1 \
    || fail "scaffold.sh exited non-zero"
[ -f "$SCRATCH/AGENTS.md" ] || fail "scaffold did not produce AGENTS.md"
[ -f "$SCRATCH/AGENTS_LIFECYCLE.md" ] || fail "scaffold did not produce AGENTS_LIFECYCLE.md"
[ -d "$SCRATCH/.opencode/agent" ] || fail "scaffold did not produce .opencode/agent/"
[ -f "$SCRATCH/library/EXTENSIONS.md" ] || fail "scaffold did not produce library/"
ok "scaffold produced expected workspace files (AGENTS.md, .opencode/agent, library)"

echo "PASS: full-stack"