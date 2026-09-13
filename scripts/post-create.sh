#!/usr/bin/env bash
# postCreateCommand: runs once after the container is built.
# The devcontainer features already installed llama-server, bifrost,
# opencode CLI, models and the agent scaffold payload — this verifies the
# box and scaffolds the agent config into the workspace.
set -euo pipefail

echo "[post-create] agentic-devcontainer-feature self-consumption container"

# Locale (python + some toolchains want a real UTF-8 locale).
# postCreateCommand runs as the devcontainer user (vscode), so privileged
# steps go through sudo (NOPASSWD from the Dockerfile).
if ! locale -a 2>/dev/null | grep -qi "en_US.UTF-8"; then
    echo "[post-create] generating en_US.UTF-8 locale..."
    # stderr suppressed: sudo emits a cosmetic "unable to send audit message"
    # warning in containers (no CAP_AUDIT_WRITE); the command still succeeds.
    if ! echo "en_US.UTF-8 UTF-8" | sudo tee -a /etc/locale.gen >/dev/null 2>&1 \
        || ! sudo locale-gen >/dev/null 2>&1; then
        echo "[post-create] WARNING: locale-gen failed (sudo locale-gen manually)"
    fi
fi

# Component status
for bin in git llama-server opencode; do
    if command -v "$bin" >/dev/null 2>&1; then
        echo "[post-create] $bin: ready ($(command -v "$bin"))"
    else
        echo "[post-create] $bin: NOT on PATH"
    fi
done
if command -v start-bifrost >/dev/null 2>&1; then
    echo "[post-create] bifrost: ready (start-bifrost launcher)"
else
    echo "[post-create] bifrost: NOT installed"
fi

# Model present?
MODELS_DIR="${MODELS_DIR:-$PWD/models}"
if ls "$MODELS_DIR"/*.gguf >/dev/null 2>&1; then
    echo "[post-create] models: found in $MODELS_DIR ($(ls "$MODELS_DIR"/*.gguf | wc -l) .gguf)"
else
    echo "[post-create] models: none in $MODELS_DIR yet — set MODEL/QUANT options or drop a .gguf in models/"
fi

# Scaffold the agent payload into the workspace (AGENTS.md, library, .opencode/agent)
SCAFFOLD="/usr/local/share/opencode-agents/scaffold.sh"
if [ -x "$SCAFFOLD" ]; then
    echo "[post-create] scaffolding agent payload into workspace..."
    "$SCAFFOLD" || echo "[post-create] WARNING: scaffold.sh reported an issue (see output above)"
else
    echo "[post-create] scaffold.sh not found at $SCAFFOLD"
fi

echo "[post-create] done. Stack starts on container start (llama-server :8089, bifrost :8082, opencode serve :4096)."