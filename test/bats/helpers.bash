#!/usr/bin/env bash
# Shared helpers for the runner-side bats metadata suite.
# Sources from test/bats/, so repo root is always two levels up.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Used by metadata.bats, which sources this file (shellcheck can't see the consumer).
# shellcheck disable=SC2034
FEATURES=(llama-server gpu-bridge bifrost-gateway models opencode-agents)

# Read a JSON field out of a feature's devcontainer-feature.json.
feature_json_field() {
    local feature="$1" field="$2"
    python3 -c '
import json, sys
data = json.load(open(sys.argv[1]))
print(data.get(sys.argv[2], ""))
' "$REPO_ROOT/src/$feature/devcontainer-feature.json" "$field"
}

# Feature versions must be semver X.Y.Z (the GHCR publish step relies on this).
is_semver() {
    [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}
