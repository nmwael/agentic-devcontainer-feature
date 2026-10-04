#!/bin/sh
# resolve-stack.sh — runtime profile resolution for the models feature.
#
# WHY THIS EXISTS
#   Features install at BUILD time, when the workspace bind-mount does not exist
#   yet and the devcontainer CLI passes no workspace path (the only build args
#   are _DEV_CONTAINERS_BASE_IMAGE / _DEV_CONTAINERS_IMAGE_USER). install.sh's
#   `$PWD/.devcontainer/llm-lab-models.json` lookup therefore can never match an
#   OCI-published feature: the CLI extracts features to
#   /tmp/dev-container-features/<id>_<n> and runs install.sh there, so $PWD is a
#   temp dir and $PWD/models baked into stack.json is garbage.
#
#   This script runs from the feature's postCreateCommand, where the workspace
#   IS mounted and the CLI executes hooks with cwd = the workspace folder. It
#   re-reads the profile files and rewrites the shared manifest, then re-runs the
#   bifrost config materialiser so routing matches the new stack.
#
# PRECEDENCE (mirrors install.sh)
#   explicit MODELS/ROLES feature options (recorded at build time)
#     > $PWD/.devcontainer/llm-lab-{models,roles}.json
#     > built-in defaults written at build time
#
# Usage: resolve-stack.sh [workspace_dir]   (defaults to $PWD)
set -e

SELF_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
LLM_LAB_DIR="${LLM_LAB_DIR:-/usr/local/share/llm-lab}"
STACK_FILE="${STACK_FILE:-$LLM_LAB_DIR/stack.json}"
FEATURE_MODELS_DIR="${FEATURE_MODELS_DIR:-$LLM_LAB_DIR/models}"

# Reuse install.sh's writers/validators so both paths cannot drift.
# shellcheck source=/dev/null
. "$SELF_DIR/stack-lib.sh"

WORKSPACE="${1:-$PWD}"
MODELS_JSON_FILE="$WORKSPACE/.devcontainer/llm-lab-models.json"
ROLES_JSON_FILE="$WORKSPACE/.devcontainer/llm-lab-roles.json"
BUILD_STATE="$LLM_LAB_DIR/.build-state"

echo "[resolve-stack] workspace: $WORKSPACE"

# jq is required to rewrite the manifest.
if ! command -v jq >/dev/null 2>&1; then
    echo "[resolve-stack] jq unavailable — leaving build-time stack.json untouched"
    exit 0
fi

if [ ! -f "$MODELS_JSON_FILE" ] && [ ! -f "$ROLES_JSON_FILE" ]; then
    echo "[resolve-stack] no profile files in $WORKSPACE/.devcontainer — nothing to resolve"
    exit 0
fi

# Build-time options win. install.sh records them so an explicit MODELS/ROLES
# consumer is never silently overridden by a stray workspace profile file.
BUILD_MODELS=""
BUILD_ROLES=""
BUILD_MODE="local"
# shellcheck disable=SC2034  # populated by .build-state; kept for completeness/sourced reuse
BUILD_MODELS_DIR=""
BUILD_BIFROST_PORT="8082"
BUILD_OPENCODE_PORT="4096"
BUILD_SUBAGENT_DEPTH="2"
BUILD_LLAMA_PORT="8089"
if [ -f "$BUILD_STATE" ]; then
    # shellcheck source=/dev/null
    . "$BUILD_STATE"
fi

if [ -n "$BUILD_MODELS" ]; then
    echo "[resolve-stack] MODELS/ROLES were set as feature options — keeping build-time stack"
    exit 0
fi

MODELS=""
ROLES=""
[ -f "$MODELS_JSON_FILE" ] && MODELS="$(cat "$MODELS_JSON_FILE")"
[ -f "$ROLES_JSON_FILE" ] && ROLES="$(cat "$ROLES_JSON_FILE")"

if [ -z "$MODELS" ] && [ -z "$ROLES" ]; then
    echo "[resolve-stack] profile files present but empty — keeping build-time stack"
    exit 0
fi

# Parse-or-warn, then fall back to the build-time values (not the built-in
# defaults) so a malformed profile cannot silently downgrade a working box.
if [ -n "$MODELS" ] && ! printf '%s' "$MODELS" | jq -e . >/dev/null 2>&1; then
    echo "[resolve-stack] WARNING: $MODELS_JSON_FILE is not valid JSON — ignoring it"
    MODELS=""
fi
if [ -n "$ROLES" ] && ! printf '%s' "$ROLES" | jq -e . >/dev/null 2>&1; then
    echo "[resolve-stack] WARNING: $ROLES_JSON_FILE is not valid JSON — ignoring it"
    ROLES=""
fi

if [ -z "$MODELS" ] && [ -z "$ROLES" ]; then
    echo "[resolve-stack] no usable profile data — keeping build-time stack"
    exit 0
fi

# A profile supplying models always means the local slot-pinned stack, matching
# install.sh's rule that explicit models win over CLOUD_MODE.
MODE=local
if [ -z "$MODELS" ] && [ "$BUILD_MODE" = "cloud" ]; then
    MODE=cloud
    MODELS='[]'
fi

[ -z "$MODELS" ] && MODELS="$BUILD_MODELS"
[ -z "$ROLES" ] && ROLES="$BUILD_ROLES"

if [ "$MODE" = "cloud" ]; then
    if ! llm_validate_cloud "$ROLES"; then
        echo "[resolve-stack] WARNING: cloud ROLES invalid — keeping build-time stack"
        exit 0
    fi
else
    if ! llm_validate_local "$MODELS" "$ROLES"; then
        echo "[resolve-stack] WARNING: profile fails integrity (role must reference an existing model, slot < parallel) — keeping build-time stack"
        exit 0
    fi
fi

# The workspace is the models home: this is the whole point of the fix. Only an
# explicit MODELS_DIR option may override it.
MODELS_DIR="${MODELS_DIR:-$WORKSPACE/models}"
mkdir -p "$MODELS_DIR"

MODELS_NORM="$(printf '%s' "$MODELS" | jq -c .)"
ROLES_NORM="$(printf '%s' "$ROLES" | jq -c .)"

BIFROST_PORT="${BIFROST_PORT:-$BUILD_BIFROST_PORT}"
OPENCODE_PORT="${OPENCODE_PORT:-$BUILD_OPENCODE_PORT}"
SUBAGENT_DEPTH="${SUBAGENT_DEPTH:-$BUILD_SUBAGENT_DEPTH}"

llm_write_stack "$MODE" "$MODELS_NORM" "$ROLES_NORM" "$MODELS_DIR" \
    "$BIFROST_PORT" "$OPENCODE_PORT" "$SUBAGENT_DEPTH"

if [ "$MODE" = "cloud" ]; then
    echo "[resolve-stack] cloud stack written to $STACK_FILE"
else
    llm_write_models_json "$MODELS_NORM" "$MODELS_DIR"
    echo "[resolve-stack] resolved $(printf '%s' "$MODELS_NORM" | jq 'length') model(s) into $STACK_FILE"
    echo "[resolve-stack] models_dir: $MODELS_DIR"
fi

llm_persist_models_dir "$MODELS_DIR"
llm_refresh_bifrost "$BUILD_LLAMA_PORT"

echo "[resolve-stack] done"
