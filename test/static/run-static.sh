#!/usr/bin/env bash
# Static quality gate for the devcontainer feature collection.
#  1. shellcheck (warning severity) on every shipped shell script
#  2. dash -n syntax check (feature installers run under /bin/sh)
#  3. schema validation (devcontainer-feature.json / devcontainer-template.json)
# Runs on the CI runner - no Docker required.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

FEATURE_SCRIPTS=(
    src/*/install.sh
    src/templates/llm-lab/test/test.sh
)

CHECK_SCRIPTS=(
    "${FEATURE_SCRIPTS[@]}"
    scripts/*.sh
    test/static/run-static.sh
    test/integration/run.sh
    test/bats/helpers.bash
)

echo "==[1/3] shellcheck (warning severity) =="
shellcheck -x -S warning "${CHECK_SCRIPTS[@]}"
echo "  shellcheck: clean"

echo "==[2/3] dash -n syntax (installers run under /bin/sh) =="
for f in "${FEATURE_SCRIPTS[@]}"; do
    dash -n "$f"
    echo "  ok: $f"
done

echo "==[3/3] schema validation =="
python3 test/static/schema-check.py

echo "STATIC SUITE PASSED"