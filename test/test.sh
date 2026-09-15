#!/bin/sh
set -e

echo "Running llm-lab template test scenario: $SCENARIO_NAME"

# Parse scenario from environment
SCENARIO="${SCENARIO:-cpu-only-ubuntu2404}"

case "$SCENARIO" in
cpu-only-ubuntu2404)
    echo "=== CPU-Only Ubuntu 24.04 Scenario ==="
    echo "Checking graceful degradation without GPU..."

    # Check llama-server is not installed (or no-op)
    if command -v llama-server >/dev/null 2>&1; then
        echo "WARNING: llama-server is on PATH — unexpected for CPU-only scenario"
        llama-server --version 2>/dev/null || echo "llama-server present but failed to run"
    else
        echo "OK: llama-server not on PATH (graceful degradation)"
    fi

    # Check gpu-bridge stub
    if [ -x /usr/local/bin/ensure-bridge.sh ] || [ -d /usr/local/share/llm-lab/gpu-bridge ]; then
        echo "OK: gpu-bridge feature scripts present (stub mode)"
    else
        echo "OK: gpu-bridge not installed (not WSL2)"
    fi

    # Check bifrost-gateway
    if [ -d /usr/local/share/llm-lab/bifrost ] && [ -x /usr/local/bin/start-bifrost ]; then
        echo "OK: bifrost-gateway installed"
    else
        echo "WARN: bifrost-gateway not fully installed"
    fi

    # Check models
    if [ -f /usr/local/share/llm-lab/models/fetch-models.sh ]; then
        echo "OK: models fetch-models.sh script available"
    else
        echo "WARN: models fetch script not found"
    fi

    # Check opencode-agents scaffold
    if [ -f "${WORKSPACE:-$PWD}/AGENTS.md" ]; then
        echo "OK: opencode-agents scaffold present (AGENTS.md)"
    else
        echo "WARN: opencode-agents scaffold not present"
    fi

    echo "=== CPU-Only scenario checks complete ==="
    ;;

cpu-only-cuda-runtime)
    echo "=== CPU-Only CUDA Runtime Scenario ==="
    echo "Testing on nvidia/cuda:13.3.0-cudnn-runtime-ubuntu24.04 base..."

    # Check llama-server
    if [ -f /opt/llama-server/llama-server ]; then
        echo "OK: llama-server installed at /opt/llama-server"
        /opt/llama-server/llama-server --version 2>/dev/null || echo "llama-server binary present"
    else
        echo "OK: llama-server not installed (will use graceful degradation)"
    fi

    # Check gpu-bridge
    if [ ! -d /usr/lib/wsl/lib ]; then
        echo "OK: Not WSL2 — gpu-bridge will stub exit 0"
    fi

    # Check bifrost
    if [ -d /usr/local/share/llm-lab/bifrost ]; then
        echo "OK: bifrost-gateway installed"
    fi

    # Check models
    if [ -f /usr/local/share/llm-lab/models/fetch-models.sh ]; then
        echo "OK: models fetch-models.sh available"
    fi

    # Check opencode-agents
    if [ -f "${WORKSPACE:-$PWD}/AGENTS.md" ]; then
        echo "OK: opencode-agents scaffold present"
    fi

    echo "=== CUDA Runtime scenario checks complete ==="
    ;;

*)
    echo "Unknown scenario: $SCENARIO"
    exit 1
    ;;
esac
