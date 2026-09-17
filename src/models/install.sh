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

# Default cloud role mapping: every agent routes to the hosted opencode provider
# (roles.model = hosted model id; slot is unused by the opencode generator).
DEFAULT_CLOUD_ROLES="{\"architect\":{\"model\":\"$CLOUD_MODEL\",\"slot\":0},\"coder\":{\"model\":\"$CLOUD_MODEL\",\"slot\":0},\"researcher\":{\"model\":\"$CLOUD_MODEL\",\"slot\":0},\"reviewer\":{\"model\":\"$CLOUD_MODEL\",\"slot\":0},\"build\":{\"model\":\"$CLOUD_MODEL\",\"slot\":0},\"ui\":{\"model\":\"$CLOUD_MODEL\",\"slot\":0},\"artist\":{\"model\":\"$CLOUD_MODEL\",\"slot\":0},\"ai-researcher\":{\"model\":\"$CLOUD_MODEL\",\"slot\":0}}"

# Consumer-friendly file overrides — real JSON files, zero shell quoting required.
# Precedence: option env var > $PWD/.devcontainer/llm-lab-{models,roles}.json > defaults.
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
    MODELS_DIR="$PWD/models"
    echo "MODELS_DIR not set — defaulting to $MODELS_DIR"
fi

FEATURE_MODELS_DIR="/usr/local/share/llm-lab/models"
STACK_FILE="/usr/local/share/llm-lab/stack.json"
SCRIPT_SRC="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"

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
        # Cloud integrity: >=1 role, every role carries a non-empty hosted model id.
        if ! jq -e -n --argjson r "$(printf '%s' "$ROLES" | jq -c .)" \
            '($r | length) > 0 and
             all($r[];
                 (.model | type) == "string" and (.model | length) > 0)' \
            >/dev/null 2>&1; then
            echo "WARNING: cloud ROLES entries must carry a non-empty 'model' (hosted opencode id) — using cloud default"
            ROLES="$DEFAULT_CLOUD_ROLES"
        fi
    else
        # Local integrity: >=1 model, every role references an existing model, slot < its parallel slot count.
        if ! jq -e -n --argjson m "$(printf '%s' "$MODELS" | jq -c .)" --argjson r "$(printf '%s' "$ROLES" | jq -c .)" \
            '($m | length) > 0 and
             all($r[];
                 .model as $rm |
                 (any($m[]; .name == $rm))
                 and ((first($m[] | select(.name == $rm))).parallel) > .slot)' \
            >/dev/null 2>&1; then
            echo "WARNING: MODELS/ROLES fail integrity (role must reference an existing model, slot < parallel) — using defaults"
            MODELS="$DEFAULT_MODELS"
            ROLES="$DEFAULT_ROLES"
        fi
    fi

    MODELS_NORM="$(printf '%s' "$MODELS" | jq -c .)"
    ROLES_NORM="$(printf '%s' "$ROLES" | jq -c .)"

    # Write the shared manifest — single source of truth for bifrost + opencode + auto-startup.
    if [ "$MODE" = "cloud" ]; then
        jq -n --argjson r "$ROLES_NORM" \
            --arg md "$MODELS_DIR" --arg bp "$BIFROST_PORT" --arg op "$OPENCODE_PORT" --arg sd "$SUBAGENT_DEPTH" \
            '{
                schema: 1,
                notation: "cloud mode: roles.model = hosted opencode provider model id (slots unused)",
                models_dir: $md,
                bifrost_port: ($bp | tonumber),
                opencode_port: ($op | tonumber),
                subagent_depth: ($sd | tonumber),
                cloud: true,
                cloud_provider: "opencode",
                models: [],
                roles: $r
            }' >"$STACK_FILE"
        echo "Cloud-only shared manifest written to $STACK_FILE (all agents -> hosted opencode provider)"
    else
        jq -n --argjson m "$MODELS_NORM" --argjson r "$ROLES_NORM" \
            --arg md "$MODELS_DIR" --arg bp "$BIFROST_PORT" --arg op "$OPENCODE_PORT" --arg sd "$SUBAGENT_DEPTH" \
            '{
                schema: 1,
                notation: "roles -> (model, slot); model id = provider/name[-s{slot}]",
                models_dir: $md,
                bifrost_port: ($bp | tonumber),
                opencode_port: ($op | tonumber),
                subagent_depth: ($sd | tonumber),
                cloud: false,
                cloud_provider: "opencode",
                models: $m,
                roles: $r
            }' >"$STACK_FILE"
        echo "Shared manifest written to $STACK_FILE"
    fi

    # Back-compat mirror: models.json reflects the FIRST model only (legacy fetch path).
    FIRST_HF="$(printf '%s' "$MODELS_NORM" | jq -r '.[0].hf // empty')"
    FIRST_QUANT="$(printf '%s' "$MODELS_NORM" | jq -r '.[0].quant // empty')"
    jq -n --arg m "$FIRST_HF" --arg q "$FIRST_QUANT" --arg d "$MODELS_DIR" \
        '{model: $m, quant: $q, models_dir: $d}' >"$FEATURE_MODELS_DIR/models.json"
else
    cp -f "$SCRIPT_SRC/templates/models.json" "$FEATURE_MODELS_DIR/models.json"
    echo "WARNING: jq unavailable — manifest not written; models.json keeps template defaults"
fi

# Install the static fetch-models.sh from the feature root (reads stack.json at runtime)
FETCH_SCRIPT="$FEATURE_MODELS_DIR/fetch-models.sh"
cp -f "$SCRIPT_SRC/fetch-models.sh" "$FETCH_SCRIPT"
chmod 0755 "$FETCH_SCRIPT"

# Write MODELS_DIR to /etc/environment or via containerEnv when the option is set
if ! grep -qF "MODELS_DIR" /etc/environment 2>/dev/null; then
    echo "export MODELS_DIR=$MODELS_DIR" >>/etc/environment
    echo "Added MODELS_DIR to /etc/environment"
fi

echo "Done! Models feature activated."
echo "Run 'fetch-models.sh' to download configured model(s) into $MODELS_DIR"