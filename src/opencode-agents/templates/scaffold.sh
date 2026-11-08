#!/bin/sh
set -e

echo "Opencode-agents scaffold: copying payload to workspace"

INSTALL_DIR="${INSTALL_DIR:-/usr/local/share/opencode-agents}"
OVERWRITE="${OVERWRITE:-false}"
WORKSPACE="${WORKSPACE:-$(pwd)}"
STACK_JSON="${STACK_JSON:-/usr/local/share/llm-lab/stack.json}"

# Guard: refuse to write to filesystem root (prevents /opencode.json pollution)
case "$WORKSPACE" in
    ""|/)
        echo "ERROR: WORKSPACE is empty or '/' — refusing to write outside a project directory." >&2
        echo "       Set WORKSPACE explicitly (e.g. WORKSPACE=$(pwd) scaffold.sh) or run from a project directory." >&2
        exit 1
        ;;
esac

# Materialize opencode.json — only when the target is absent/empty, or when the
# consumer explicitly asks to refresh with OVERWRITE=true. A non-empty existing
# config is consumer state (e.g. extra enabled_providers such as nvidia) and
# must never be silently clobbered by a re-run of scaffold.
if [ "$OVERWRITE" = "true" ] || [ ! -s "$WORKSPACE/opencode.json" ] ||
    [ "$(tr -d '[:space:]' <"$WORKSPACE/opencode.json" 2>/dev/null)" = "{}" ]; then
    if [ -f "$STACK_JSON" ] && command -v jq >/dev/null 2>&1; then
        if sh "$INSTALL_DIR/generate-opencode.sh" "$STACK_JSON" "$WORKSPACE/opencode.json" 2>/dev/null; then
            echo "opencode.json generated from stack.json ($STACK_JSON)"
        else
            echo "WARNING: generation from stack.json failed — falling back to shipped fragment"
            cp -f "$INSTALL_DIR/opencode.json.fragment" "$WORKSPACE/opencode.json"
        fi
    else
        cp -f "$INSTALL_DIR/opencode.json.fragment" "$WORKSPACE/opencode.json"
        echo "opencode.json generated from fragment (slot-pinned models)"
    fi
else
    echo "opencode.json present — leaving consumer config untouched (OVERWRITE=true to regenerate)"
fi

# Idempotent: skip if files already exist unless OVERWRITE
if [ "$OVERWRITE" = "true" ]; then
    echo "OVERWRITE=true — refreshing scaffold files (may overwrite existing workspace files)"
else
    # Check if scaffold already exists (skip if present unless consumer edited it)
    if [ -f "$WORKSPACE/AGENTS.md" ] && [ -f "$WORKSPACE/AGENTS_LIFECYCLE.md" ]; then
        echo "Scaffold already present (AGENTS.md + AGENTS_LIFECYCLE.md detected). Use OVERWRITE=true to refresh."
        exit 0
    fi
fi

# Copy AGENTS.md and AGENTS_LIFECYCLE.md to workspace (respecting OVERWRITE)
cp -f "$INSTALL_DIR/AGENTS.md" "$WORKSPACE/AGENTS.md"
cp -f "$INSTALL_DIR/AGENTS_LIFECYCLE.md" "$WORKSPACE/AGENTS_LIFECYCLE.md"

# Copy .opencode/agents/*.md files (opencode v2 uses the plural 'agents' dir)
mkdir -p "$WORKSPACE/.opencode/agents"
for f in "$INSTALL_DIR/.opencode/agents"/*.md; do
    [ -f "$f" ] && cp -f "$f" "$WORKSPACE/.opencode/agents/"
done

# Pre-1.3.0 scaffolds shipped one combined agent-roles.md. OVERWRITE refreshes
# never delete, so remove the stale straggler now that per-role files replace it.
rm -f "$WORKSPACE/.opencode/agents/agent-roles.md"

# opencode v2 only discovers .opencode/agents (plural); drop a stale legacy
# singular dir when the consumer opted into a refresh.
if [ "$OVERWRITE" = "true" ]; then
    rm -rf "$WORKSPACE/.opencode/agent"
fi

# Copy library/ books
mkdir -p "$WORKSPACE/library"
cp -rf "$INSTALL_DIR/library/." "$WORKSPACE/library/"

# Copy library/EXTENSIONS.md guide (always copy, consumer edits survive OVERWRITE)
cp -f "$INSTALL_DIR/library/EXTENSIONS.md" "$WORKSPACE/library/EXTENSIONS.md"

echo "Scaffold complete. AGENTS.md + AGENTS_LIFECYCLE.md copied to workspace."
