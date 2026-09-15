#!/usr/bin/env bash
# Static quality gate for the devcontainer feature collection.
#  1. shellcheck (warning severity) on every shipped shell script
#  2. dash -n syntax check (feature installers run under /bin/sh)
#  3. schema validation (devcontainer-feature.json / devcontainer-template.json)
#  4. template JSON validation (jq) on config templates
# Runs on the CI runner - no Docker required.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

FEATURE_SCRIPTS=(
    src/*/install.sh
    src/*/templates/*.sh
    src/models/fetch-models.sh
    src/bifrost-gateway/start-bifrost.sh
    src/gpu-bridge/ensure-bridge.sh
    src/templates/llm-lab/test/test.sh
)

CHECK_SCRIPTS=(
    "${FEATURE_SCRIPTS[@]}"
    scripts/*.sh
    test/static/run-static.sh
    test/integration/run.sh
    test/bats/helpers.bash
)

echo "==[1/4] shellcheck (warning severity) =="
shellcheck -x -S warning "${CHECK_SCRIPTS[@]}"
echo "  shellcheck: clean"

echo "==[2/4] dash -n syntax (installers run under /bin/sh) =="
for f in "${FEATURE_SCRIPTS[@]}"; do
    dash -n "$f"
    echo "  ok: $f"
done

echo "==[3/4] schema validation =="
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

echo "==[5/5] auto-startup llama-server flags =="
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

echo "STATIC SUITE PASSED"
