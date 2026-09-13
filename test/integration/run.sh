#!/usr/bin/env bash
# Container integration suite: for each feature, build an ubuntu:24.04
# container, install the feature TWICE (idempotency contract), and run the
# per-feature bats suite against the installed artifacts.
#
# Requires: docker (GH Actions ubuntu-latest provides it).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: docker required for integration tests" >&2
    exit 1
fi

FEATURES=(llama-server gpu-bridge bifrost-gateway models opencode-agents)
LOG_DIR="$(mktemp -d /tmp/feature-integration-XXXXXX)"
echo "Integration log dir: $LOG_DIR"

failures=0
for feature in "${FEATURES[@]}"; do
    echo "==> $feature"
    ctx="$LOG_DIR/$feature"
    mkdir -p "$ctx"
    cp -r "src/$feature" "$ctx/feature"
    cp "test/integration/bats/$feature.bats" "$ctx/test.bats"
    cp "test/integration/Dockerfile.ci" "$ctx/Dockerfile"
    python3 test/integration/options2env.py "src/$feature/devcontainer-feature.json" > "$ctx/options.env"

    if docker build -q -t "ci-feature-$feature" "$ctx" >"$LOG_DIR/$feature.build.log" 2>&1; then
        if docker run --rm "ci-feature-$feature" >"$LOG_DIR/$feature.run.log" 2>&1; then
            echo "  PASS"
        else
            echo "  FAIL (bats):"
            tail -30 "$LOG_DIR/$feature.run.log"
            failures=$((failures + 1))
        fi
    else
        echo "  FAIL (build):"
        tail -30 "$LOG_DIR/$feature.build.log"
        failures=$((failures + 1))
    fi
done

if [ "$failures" -gt 0 ]; then
    echo "INTEGRATION SUITE FAILED: $failures/${#FEATURES[@]} feature(s)"
    exit 1
fi

echo "INTEGRATION SUITE PASSED (${#FEATURES[@]} features)"
echo "Logs retained at: $LOG_DIR"