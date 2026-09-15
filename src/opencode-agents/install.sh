#!/bin/sh
set -e

echo "Activating feature 'opencode-agents'"

# The 'install.sh' entrypoint script is always executed as the root user.
# Option values are passed in as environment variables named after the option id,
# converted to UPPERCASE (e.g. 'overwrite' -> $OVERWRITE, 'with_library' -> $WITH_LIBRARY).
echo "The effective dev container remoteUser is '$_REMOTE_USER'"
echo "The effective dev container containerUser is '$_CONTAINER_USER'"

OVERWRITE="${OVERWRITE:-false}"
WITH_LIBRARY="${WITH_LIBRARY:-true}"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/share/opencode-agents}"

FEATURE_PAYLOAD_DIR="/usr/local/share/llm-lab/opencode-agents-payload"
mkdir -p "$FEATURE_PAYLOAD_DIR"

echo "Opencode-agents config: OVERWRITE=$OVERWRITE WITH_LIBRARY=$WITH_LIBRARY INSTALL_DIR=$INSTALL_DIR"

# Unpack payload tarball → INSTALL_DIR
# The payload is a pre-built tarball containing the agentic setup.
# For now, we create the scaffold structure from the canonical source in this repo.

# Ship AGENTS.md and AGENTS_LIFECYCLE.md
mkdir -p "$INSTALL_DIR"

# Create .opencode/agent/ directory structure
if [ ! -d "$INSTALL_DIR/.opencode" ]; then
    mkdir -p "$INSTALL_DIR/.opencode/agent"
fi

# Template directory (shipped with the feature)
TPL_DIR="$(dirname "$0")/templates"

# Copy AGENTS.md
cp -f "$TPL_DIR/AGENTS.md" "$INSTALL_DIR/AGENTS.md"
cp -f "$TPL_DIR/AGENTS_LIFECYCLE.md" "$INSTALL_DIR/AGENTS_LIFECYCLE.md"

# Copy .opencode/agent/*.md files
mkdir -p "$INSTALL_DIR/.opencode/agent"
for f in "$TPL_DIR/.opencode/agent"/*.md; do
    [ -f "$f" ] && cp -f "$f" "$INSTALL_DIR/.opencode/agent/"
done

# Copy library books if WITH_LIBRARY is true
mkdir -p "$INSTALL_DIR/library"
cp -f "$TPL_DIR/library/EXTENSIONS.md" "$INSTALL_DIR/library/EXTENSIONS.md"
cp -f "$TPL_DIR/library/release-it.mini.md" "$INSTALL_DIR/library/release-it.mini.md"

if [ "$WITH_LIBRARY" = "true" ]; then
    mkdir -p "$INSTALL_DIR/library/skills"
    cp -f "$TPL_DIR/library/skills/"*.md "$INSTALL_DIR/library/skills/" 2>/dev/null || true

    mkdir -p "$INSTALL_DIR/library/ai-researcher"
    cp -f "$TPL_DIR/library/ai-researcher/"*.md "$INSTALL_DIR/library/ai-researcher/" 2>/dev/null || true
else
    echo "WITH_LIBRARY=false — skipping shipped library books (EXTENSIONS.md only)"
fi

# Copy scaffold.sh
cp -f "$TPL_DIR/scaffold.sh" "$INSTALL_DIR/scaffold.sh"
chmod 0755 "$INSTALL_DIR/scaffold.sh"

# Copy opencode.json.fragment
cp -f "$TPL_DIR/opencode.json.fragment" "$INSTALL_DIR/opencode.json.fragment"

# Install the opencode CLI itself (binary via the official installer).
if ! command -v curl >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
    apt-get install -y --no-install-recommends curl git >/dev/null 2>&1 ||
        echo "WARNING: curl/git unavailable — CLI install needs curl; agent workflows need git"
fi
if command -v opencode >/dev/null 2>&1; then
    echo "opencode CLI already installed: $(opencode --version 2>/dev/null || echo present)"
else
    echo "Installing opencode CLI (official installer)..."
    if curl -fsSL https://opencode.ai/install | bash; then
        echo "opencode CLI installed: $(opencode --version 2>/dev/null || echo present)"
    else
        echo "WARNING: opencode CLI install failed — run 'curl -fsSL https://opencode.ai/install | bash' manually"
    fi
fi

# Copy opencode binary to /usr/local/bin so EVERY user sees it
if [ -x "$HOME/.opencode/bin/opencode" ]; then
    cp -f "$HOME/.opencode/bin/opencode" /usr/local/bin/opencode
    chmod 0755 /usr/local/bin/opencode
    echo "opencode copied to /usr/local/bin/opencode (all users)"
fi

echo "Done! Opencode-agents feature activated."
echo "Scaffold scripts placed at $INSTALL_DIR/scaffold.sh"
echo "opencode.json.fragment placed at $INSTALL_DIR/opencode.json.fragment"
echo "Run scaffold.sh to copy payload into workspace."
