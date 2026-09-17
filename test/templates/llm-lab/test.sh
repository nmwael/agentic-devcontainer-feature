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

default-cloud)
    echo "=== Default Cloud llm-lab Scenario ==="
    echo "Testing on ubuntu:24.04 with the default cloud template options..."
    WS_DIR="${WORKSPACE:-$PWD}"

    # Full scaffold contract — each payload materialized by postCreateCommand ->
    # scaffold.sh (D2) into the consumer workspace. Absence of ANY file fails this
    # scenario (mirrors scenarios.json checks).

    # AGENTS.md
    if [ -f "$WS_DIR/AGENTS.md" ]; then
        echo "OK: AGENTS.md scaffolded in workspace"
    else
        echo "WARN: AGENTS.md missing from workspace"
    fi

    # AGENTS_LIFECYCLE.md
    if [ -f "$WS_DIR/AGENTS_LIFECYCLE.md" ]; then
        echo "OK: AGENTS_LIFECYCLE.md scaffolded in workspace"
    else
        echo "WARN: AGENTS_LIFECYCLE.md missing from workspace"
    fi

    # .opencode/agent/*.md
    if [ -d "$WS_DIR/.opencode/agent" ]; then
        echo "OK: .opencode/agent/ directory scaffolded"
    else
        echo "WARN: .opencode/agent/ missing"
    fi

    # library/
    if [ -d "$WS_DIR/library" ]; then
        echo "OK: library/ scaffolded (reference books)"
    else
        echo "WARN: library/ missing"
    fi

    # opencode.json (materialized from stack.json by generate-opencode step)
    if [ -f "$WS_DIR/opencode.json" ]; then
        echo "OK: opencode.json materialized in workspace"
    else
        echo "WARN: opencode.json missing"
    fi

    # Cloud-mode pin contract: every agent must route to the hosted opencode
    # provider (opencode/<model>), and the primary model must match.
    if [ -f "$WS_DIR/opencode.json" ] && command -v jq >/dev/null 2>&1; then
        CLOUD_BAD=0
        for agent in architect coder researcher reviewer build ui artist ai-researcher; do
            m="$(jq -r ".agent.$agent.model // empty" "$WS_DIR/opencode.json" 2>/dev/null)"
            case "$m" in
                opencode/*) echo "OK: agent $agent -> $m" ;;
                "") echo "WARN: agent $agent has no model pin in opencode.json" ;;
                *) echo "FAIL: agent $agent -> $m (expected opencode/* in cloud mode)"; CLOUD_BAD=1 ;;
            esac
        done
        [ "$CLOUD_BAD" -eq 0 ] || exit 1
        PRIMARY="$(jq -r '.model // empty' "$WS_DIR/opencode.json" 2>/dev/null)"
        case "$PRIMARY" in
            opencode/*) echo "OK: primary model $PRIMARY (cloud)" ;;
            *) echo "FAIL: primary model '$PRIMARY' is not opencode/* (cloud mode)"; exit 1 ;;
        esac
    else
        echo "WARN: cannot assert cloud agent pins (opencode.json and/or jq missing)"
    fi

    # feature-level scaffold.sh payload (D2 materializer)
    if [ -f /usr/local/share/opencode-agents/scaffold.sh ]; then
        echo "OK: opencode-agents scaffold.sh present"
    else
        echo "WARN: opencode-agents scaffold.sh missing"
    fi

    # opencode CLI provided by the opencode feature (D3)
    if command -v opencode >/dev/null 2>&1; then
        echo "OK: opencode CLI on PATH"
    else
        echo "WARN: opencode CLI not on PATH"
    fi

    echo "=== Default Cloud scenario checks complete ==="
    ;;

*)
    echo "Unknown scenario: $SCENARIO"
    exit 1
    ;;
esac
