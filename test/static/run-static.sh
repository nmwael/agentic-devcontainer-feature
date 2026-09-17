#!/usr/bin/env bash
# Static quality gate for the devcontainer feature collection.
#  1. shellcheck (warning severity) on every shipped shell script
#  2. dash -n syntax check (feature installers run under /bin/sh)
#  3. schema validation (devcontainer-feature.json / devcontainer-template.json)
#  4. template JSON validation (jq) on config templates
#  5. hadolint Dockerfile lint (fail-on {DL3003,DL3008}; DL4006 report-only)
# Runs on the CI runner - Docker not required (hadolint runs via the binary
# or the hadolint/hadolint image when either is available; else SKIP, never fails).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

FEATURE_SCRIPTS=(
    src/*/install.sh
    src/*/templates/*.sh
    src/models/fetch-models.sh
    src/bifrost-gateway/start-bifrost.sh
    src/gpu-bridge/ensure-bridge.sh
    test/templates/llm-lab/test.sh
)

CHECK_SCRIPTS=(
    "${FEATURE_SCRIPTS[@]}"
    scripts/*.sh
    test/static/run-static.sh
    test/integration/run.sh
    test/bats/helpers.bash
    test/*/*.sh
    test/_global/*.sh
)

echo "==[1/7] shellcheck (warning severity) =="
shellcheck -x -S warning "${CHECK_SCRIPTS[@]}"
echo "  shellcheck: clean"

echo "==[2/7] dash -n syntax (installers run under /bin/sh) =="
for f in "${FEATURE_SCRIPTS[@]}"; do
    dash -n "$f"
    echo "  ok: $f"
done

echo "==[3/7] schema validation =="
python3 test/static/schema-check.py

echo "==[4/4] template JSON validation (jq) =="
TEMPLATE_JSONS=(src/*/templates/*.json)
COUNT=0
for f in "${TEMPLATE_JSONS[@]}"; do
    [ -f "$f" ] || continue
    if ! jq -e . "$f" >/dev/null; then
        echo "  FAIL: $f"
        exit 1
    fi
    echo "  ok: $f"
    COUNT=$((COUNT + 1))
done
echo "  ${COUNT} template JSON file(s) valid"

echo "==[5/7] hadolint Dockerfile lint =="
# Dockerfile correctness gate: fail-on {DL3003,DL3008}; DL4006 report-only.
# Runs when a hadolint binary or the hadolint/hadolint image is available;
# else SKIP (exit 0, never fails the suite).
HADOLINT_TARGETS=(
    src/templates/llm-lab/.devcontainer/Dockerfile
    .devcontainer/Dockerfile
    test/integration/Dockerfile.ci
)
HADOLINT_RULES="DL3003,DL3008"
hadolint_available=false
if command -v hadolint >/dev/null 2>&1; then
    hadolint_available=true
elif command -v docker >/dev/null 2>&1; then
    hadolint_available=true
fi
if [ "$hadolint_available" = "true" ]; then
    for dockerfile in "${HADOLINT_TARGETS[@]}"; do
        [ -f "$dockerfile" ] || continue
        if command -v hadolint >/dev/null 2>&1; then
            output=$(hadolint --no-color --fail-on "$HADOLINT_RULES" "$dockerfile" 2>&1) || true
        else
            output=$(docker run --rm -i hadolint/hadolint:latest-alpine hadolint --no-color --fail-on "$HADOLINT_RULES" - < "$dockerfile" 2>&1) || true
        fi
        fatal=$(printf '%s\n' "$output" | grep -cE "DL3003|DL3008" || true)
        dl4006=$(printf '%s\n' "$output" | grep -c "DL4006" || true)
        if [ "$fatal" -gt 0 ]; then
            echo "  FAIL: $dockerfile (${HADOLINT_RULES})"
            printf '%s\n' "$output"
            exit 1
        fi
        if [ "$dl4006" -gt 0 ]; then
            echo "  report-only: $dockerfile DL4006 (add SHELL [\"/bin/bash\",\"-o\",\"pipefail\",\"-c\"] to silence)"
        fi
        echo "  ok: $dockerfile"
    done
else
    echo "  SKIP: hadolint unavailable (no hadolint binary, no docker) — soft gate, never fails"
fi

echo "==[6/7] auto-startup llama-server flags =="
# Model-id sync contract: llama-server MUST receive --alias/--parallel matching
# the opencode provider models generated from stack.json, or bifrost routing
# 404s (see AGENTS.md conventions).
if ! grep -q -- '--alias' scripts/auto-startup.sh ||
    ! grep -q -- '--parallel' scripts/auto-startup.sh ||
    ! grep -q -- '--ctx-size' scripts/auto-startup.sh; then
    echo "  FAIL: scripts/auto-startup.sh must pass --alias/--parallel/--ctx-size to llama-server"
    exit 1
fi
echo "  ok: auto-startup.sh passes --alias/--parallel/--ctx-size"

echo "==[7/7] devcontainer-CLI test mirror contract =="
# `devcontainer features test` requires test/<feature>/test.sh for every feature
# in src/, and a matching <scenario>.sh for every key in each scenarios.json.
FEATURES=(llama-server gpu-bridge bifrost-gateway models opencode-agents)
ok=true
for feature in "${FEATURES[@]}"; do
    [ -f "test/$feature/test.sh" ] || { echo "  FAIL: missing test/$feature/test.sh"; ok=false; }
    if [ -f "test/$feature/scenarios.json" ]; then
        for scenario in $(jq -r 'keys[]' "test/$feature/scenarios.json"); do
            [ -f "test/$feature/$scenario.sh" ] || {
                echo "  FAIL: missing test/$feature/$scenario.sh (scenario '$scenario')"
                ok=false
            }
        done
    fi
done
[ -f "test/_global/scenarios.json" ] || { echo "  FAIL: missing test/_global/scenarios.json"; ok=false; }
for scenario in $(jq -r 'keys[]' test/_global/scenarios.json); do
    [ -f "test/_global/$scenario.sh" ] || { echo "  FAIL: missing test/_global/$scenario.sh"; ok=false; }
done
if [ "$ok" = "true" ]; then
    echo "  ok: all features mirrored; every scenario key has a matching script"
else
    exit 1
fi

echo "STATIC SUITE PASSED"
