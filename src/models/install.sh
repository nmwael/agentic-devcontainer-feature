#!/bin/sh
set -e

echo "Activating feature 'models'"

# The 'install.sh' entrypoint script is always executed as the root user.
# Option values are passed in as environment variables named after the option id,
# converted to UPPERCASE (e.g. 'models' -> $MODELS, 'roles' -> $ROLES).
echo "The effective dev container remoteUser is '$_REMOTE_USER'"
echo "The effective dev container containerUser is '$_CONTAINER_USER'"

# Built-in defaults reproduce the historical single-model stack exactly:
# one 26B backend on :8089 (5 shared slots), 8 roles pinned to slots s0..s4.
DEFAULT_MODELS='[{"name":"gemma4-26b-a4b","provider":"local-gemma4-26b","hf":"gemma-4-26B-A4B-it-UD-IQ2_M","quant":"IQ2_M","port":8089,"context":65536,"parallel":5}]'
DEFAULT_ROLES='{"architect":{"model":"gemma4-26b-a4b","slot":0},"coder":{"model":"gemma4-26b-a4b","slot":1},"researcher":{"model":"gemma4-26b-a4b","slot":2},"reviewer":{"model":"gemma4-26b-a4b","slot":3},"build":{"model":"gemma4-26b-a4b","slot":4},"ui":{"model":"gemma4-26b-a4b","slot":4},"artist":{"model":"gemma4-26b-a4b","slot":4},"ai-researcher":{"model":"gemma4-26b-a4b","slot":4}}'

MODELS="${MODELS:-}"
ROLES="${ROLES:-}"
CLOUD_MODE="${CLOUD_MODE:-false}"
CLOUD_MODEL="${CLOUD_MODEL:-big-pickle}"
MODELS_DIR="${MODELS_DIR:-}"
BIFROST_PORT="${BIFROST_PORT:-8082}"
OPENCODE_PORT="${OPENCODE_PORT:-4096}"
SUBAGENT_DEPTH="${SUBAGENT_DEPTH:-2}"

SCRIPT_SRC="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
LLM_LAB_DIR="${LLM_LAB_DIR:-/usr/local/share/llm-lab}"
STACK_FILE="${STACK_FILE:-$LLM_LAB_DIR/stack.json}"
FEATURE_MODELS_DIR="${FEATURE_MODELS_DIR:-$LLM_LAB_DIR/models}"

# Remember whether MODELS/ROLES arrived as explicit feature options. resolve-stack.sh
# reads this to avoid clobbering an explicit-option consumer with a stray profile file.
BUILD_MODELS_OPTION="${MODELS}"
BUILD_ROLES_OPTION="${ROLES}"

# Shared manifest writers/validators, also used at runtime by resolve-stack.sh.
# shellcheck source=/dev/null
. "$SCRIPT_SRC/stack-lib.sh"

# Default cloud role mapping: every agent routes to the hosted opencode provider
# (roles.model = hosted model id; slot is unused by the opencode generator).
DEFAULT_CLOUD_ROLES="{\"architect\":{\"model\":\"$CLOUD_MODEL\",\"slot\":0},\"coder\":{\"model\":\"$CLOUD_MODEL\",\"slot\":0},\"researcher\":{\"model\":\"$CLOUD_MODEL\",\"slot\":0},\"reviewer\":{\"model\":\"$CLOUD_MODEL\",\"slot\":0},\"build\":{\"model\":\"$CLOUD_MODEL\",\"slot\":0},\"ui\":{\"model\":\"$CLOUD_MODEL\",\"slot\":0},\"artist\":{\"model\":\"$CLOUD_MODEL\",\"slot\":0},\"ai-researcher\":{\"model\":\"$CLOUD_MODEL\",\"slot\":0}}"

# NOTE: $PWD here is NOT the workspace. The devcontainer CLI extracts an OCI
# feature to /tmp/dev-container-features/<id>_<n> and runs install.sh with that
# as the working directory, and the workspace bind-mount does not exist yet at
# build time. So $PWD/.devcontainer/llm-lab-*.json can never match. Profile
# files are resolved at runtime by resolve-stack.sh (postCreateCommand), where
# the workspace is mounted. Explicit options remain the build-time input.
if [ -z "$MODELS" ] && [ -f "$PWD/.devcontainer/llm-lab-models.json" ]; then
    MODELS="$(cat "$PWD/.devcontainer/llm-lab-models.json")"
    echo "MODELS loaded from $PWD/.devcontainer/llm-lab-models.json"
fi
if [ -z "$ROLES" ] && [ -f "$PWD/.devcontainer/llm-lab-roles.json" ]; then
    ROLES="$(cat "$PWD/.devcontainer/llm-lab-roles.json")"
    echo "ROLES loaded from $PWD/.devcontainer/llm-lab-roles.json"
fi

CLOUD_ON=false
if [ "$(printf '%s' "$CLOUD_MODE" | tr '[:upper:]' '[:lower:]')" = "true" ] || [ "$CLOUD_MODE" = "1" ]; then
    CLOUD_ON=true
fi

# Mode selection. Explicit MODELS (option or llm-lab-models.json) ALWAYS builds
# the local slot-pinned stack and wins over CLOUD_MODE ("if models are supplied,
# use those instead"). Cloud mode = CLOUD_MODE=true with no explicit models; ROLES
# (option or llm-lab-roles.json) then supplies per-role hosted model ids.
MODE=local
if [ -z "$MODELS" ] && [ "$CLOUD_ON" = "true" ]; then
    MODE=cloud
    MODELS='[]'
    echo "CLOUD_MODE=true with no explicit MODELS — writing cloud-only stack (all agents -> hosted opencode provider, default model $CLOUD_MODEL)"
fi
if [ -z "$MODELS" ]; then
    MODELS="$DEFAULT_MODELS"
fi
if [ -z "$ROLES" ]; then
    if [ "$MODE" = "cloud" ]; then
        ROLES="$DEFAULT_CLOUD_ROLES"
    else
        ROLES="$DEFAULT_ROLES"
    fi
fi

# jq provisioning — needed to materialize stack.json (the shared multi-model manifest).
# Installs are POSIX sh (dash on Ubuntu/Debian); jq is NOT guaranteed in base images.
if ! command -v jq >/dev/null 2>&1; then
    echo "jq not found — provisioning via apt..."
    if apt-get update -qq && apt-get install -y --no-install-recommends jq >/dev/null 2>&1; then
        echo "jq ready"
    else
        echo "WARNING: jq install failed — models config keeps template defaults"
    fi
fi

if [ -z "$MODELS_DIR" ]; then
    # $PWD is the CLI's temp feature-extraction dir (/tmp/dev-container-features/<id>_<n>),
    # never the workspace, so defaulting to "$PWD/models" baked a path that cannot exist.
    # Leave it empty: resolve-stack.sh sets it to $WORKSPACE/models at runtime, and
    # fetch-models.sh already falls back through stack.json -> models.json -> $PWD/models.
    MODELS_DIR=""
    echo "MODELS_DIR not set — deferring to runtime resolution (resolve-stack.sh)"
fi

mkdir -p "$FEATURE_MODELS_DIR" "$(dirname "$STACK_FILE")"

if command -v jq >/dev/null 2>&1; then
    # Validate MODELS/ROLES are parseable JSON -> else fall back to built-in defaults.
    if ! printf '%s' "$MODELS" | jq -e . >/dev/null 2>&1; then
        echo "WARNING: invalid MODELS JSON — using default single-model stack"
        MODELS="$DEFAULT_MODELS"
        MODE=local
    fi
    if ! printf '%s' "$ROLES" | jq -e . >/dev/null 2>&1; then
        echo "WARNING: invalid ROLES JSON — using default role mapping"
        if [ "$MODE" = "cloud" ]; then ROLES="$DEFAULT_CLOUD_ROLES"; else ROLES="$DEFAULT_ROLES"; fi
    fi

    if [ "$MODE" = "cloud" ]; then
        if ! llm_validate_cloud "$ROLES"; then
            echo "WARNING: cloud ROLES entries must carry a non-empty 'model' (hosted opencode id) — using cloud default"
            ROLES="$DEFAULT_CLOUD_ROLES"
        fi
    else
        if ! llm_validate_local "$MODELS" "$ROLES"; then
            echo "WARNING: MODELS/ROLES fail integrity (role must reference an existing model, slot < parallel) — using defaults"
            MODELS="$DEFAULT_MODELS"
            ROLES="$DEFAULT_ROLES"
        fi
    fi

    MODELS_NORM="$(printf '%s' "$MODELS" | jq -c .)"
    ROLES_NORM="$(printf '%s' "$ROLES" | jq -c .)"

    # Write the shared manifest — single source of truth for bifrost + opencode + auto-startup.
    llm_write_stack "$MODE" "$MODELS_NORM" "$ROLES_NORM" "$MODELS_DIR" \
        "$BIFROST_PORT" "$OPENCODE_PORT" "$SUBAGENT_DEPTH"

    if [ "$MODE" = "cloud" ]; then
        echo "Cloud-only shared manifest written to $STACK_FILE (all agents -> hosted opencode provider)"
    else
        echo "Shared manifest written to $STACK_FILE"
        # Back-compat mirror: models.json reflects the FIRST model only (legacy fetch path).
        llm_write_models_json "$MODELS_NORM" "$MODELS_DIR"
    fi

    # Record build-time inputs so resolve-stack.sh can honour explicit feature options
    # and reuse the ports/depth selected here at runtime.
    LLAMA_PORT="${LLAMA_PORT:-8089}"
    cat >"$LLM_LAB_DIR/.build-state" <<EOF
BUILD_MODELS='$BUILD_MODELS_OPTION'
BUILD_ROLES='$BUILD_ROLES_OPTION'
BUILD_MODE='$MODE'
BUILD_MODELS_DIR='$MODELS_DIR'
BUILD_BIFROST_PORT='$BIFROST_PORT'
BUILD_OPENCODE_PORT='$OPENCODE_PORT'
BUILD_SUBAGENT_DEPTH='$SUBAGENT_DEPTH'
BUILD_LLAMA_PORT='$LLAMA_PORT'
EOF
else
    cp -f "$SCRIPT_SRC/templates/models.json" "$FEATURE_MODELS_DIR/models.json"
    echo "WARNING: jq unavailable — manifest not written; models.json keeps template defaults"
fi

# Install the static fetch-models.sh from the feature root (reads stack.json at runtime)
FETCH_SCRIPT="$FEATURE_MODELS_DIR/fetch-models.sh"
cp -f "$SCRIPT_SRC/fetch-models.sh" "$FETCH_SCRIPT"
chmod 0755 "$FETCH_SCRIPT"

# Install the runtime resolver (sourced shared lib travels with it).
cp -f "$SCRIPT_SRC/stack-lib.sh" "$FEATURE_MODELS_DIR/stack-lib.sh"
cp -f "$SCRIPT_SRC/resolve-stack.sh" "$FEATURE_MODELS_DIR/resolve-stack.sh"
chmod 0755 "$FEATURE_MODELS_DIR/resolve-stack.sh"

# Persist MODELS_DIR only when explicitly configured. Writing the (now empty)
# build-time default would leave an empty/stale export in /etc/environment that
# shadows the runtime value for every later shell; resolve-stack.sh sets it once
# the workspace is mounted.
if [ -n "$MODELS_DIR" ]; then
    if ! grep -qF "export MODELS_DIR=" /etc/environment 2>/dev/null; then
        echo "export MODELS_DIR=$MODELS_DIR" >>/etc/environment
        echo "Added MODELS_DIR to /etc/environment"
    fi
fi

echo "Done! Models feature activated."
if [ -n "$MODELS_DIR" ]; then
    echo "Run 'fetch-models.sh' to download configured model(s) into $MODELS_DIR"
else
    echo "MODELS_DIR resolved at runtime — run 'fetch-models.sh' after the workspace is mounted"
fi