#!/bin/sh
set -e

echo "Opencode-agents scaffold: copying payload to workspace"

INSTALL_DIR="${INSTALL_DIR:-/usr/local/share/opencode-agents}"
OVERWRITE="${OVERWRITE:-false}"
WORKSPACE="${WORKSPACE:-$(pwd)}"

# Materialize opencode.json from the shipped fragment — before the guard so
# existing workspaces get a usable config too. Only fills when absent, empty,
# or "{}" (a default init); a real consumer config is NEVER touched.
if [ ! -s "$WORKSPACE/opencode.json" ] || \
   [ "$(tr -d '[:space:]' < "$WORKSPACE/opencode.json" 2>/dev/null)" = "{}" ]; then
    cp -f "$INSTALL_DIR/opencode.json.fragment" "$WORKSPACE/opencode.json"
    echo "opencode.json generated from fragment (slot-pinned models)"
else
    echo "opencode.json present — leaving consumer config untouched"
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

# Copy .opencode/agent/*.md files
mkdir -p "$WORKSPACE/.opencode/agent"
for f in "$INSTALL_DIR/.opencode/agent"/*.md; do
    [ -f "$f" ] && cp -f "$f" "$WORKSPACE/.opencode/agent/"
done

# Copy library/ books
mkdir -p "$WORKSPACE/library"
cp -rf "$INSTALL_DIR/library/" "$WORKSPACE/library/"

# Copy library/EXTENSIONS.md guide (always copy, consumer edits survive OVERWRITE)
cp -f "$INSTALL_DIR/library/EXTENSIONS.md" "$WORKSPACE/library/EXTENSIONS.md"

echo "Scaffold complete. AGENTS.md + AGENTS_LIFECYCLE.md copied to workspace."
