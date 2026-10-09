#!/bin/sh
# stack-lib.sh — shared manifest helpers for the models feature.
#
# Sourced by install.sh (build time) and resolve-stack.sh (runtime). Keeping the
# validation and manifest writers in one place guarantees the runtime resolver
# produces byte-identical output to the build-time install for the same inputs.
#
# This file is sourced, never executed. No shebang-executed side effects.

STACK_SCHEMA=1
LLM_LAB_DIR="${LLM_LAB_DIR:-/usr/local/share/llm-lab}"
STACK_FILE="${STACK_FILE:-$LLM_LAB_DIR/stack.json}"
FEATURE_MODELS_DIR="${FEATURE_MODELS_DIR:-$LLM_LAB_DIR/models}"

# llm_validate_local MODELS_JSON ROLES_JSON
# Local integrity: >=1 model, every role references an existing model, and the
# role's slot is strictly below that model's parallel capacity.
llm_validate_local() {
    printf '%s' "$1" | jq -e '
        (type == "array") and (length > 0) and
        all(.[];
            (.name | type) == "string" and (.name | length) > 0 and
            (.port | type) == "number" and
            ((.parallel // 1) | type) == "number"
        )
        and all(.[];
            (.spec_type // "") as $st |
            ($st == "" or $st == "draft-mtp")
            and (($st != "draft-mtp") or ((.parallel // 1) == 1))
            and ((.spec_draft_n_max // 0) == 0
                 or (($st == "draft-mtp") and ((.spec_draft_n_max | type) == "number")
                     and (.spec_draft_n_max == (.spec_draft_n_max | floor))
                     and (.spec_draft_n_max >= 1 and .spec_draft_n_max <= 8)))
        )
    ' >/dev/null 2>&1 || return 1
    printf '%s' "$2" | jq -e '
        (type == "object") and (length > 0) and
        all(to_entries[];
            (.value | type) == "object" and
            (.value.model | type) == "string" and (.value.model | length) > 0 and
            ((.value.slot // 0) | type) == "number"
        )
    ' >/dev/null 2>&1 || return 1
    jq -e -n --argjson m "$1" --argjson r "$2" '
        all($r | to_entries[]; .value as $rv |
            (any($m[]; .name == $rv.model))
            and ((first($m[] | select(.name == $rv.model)).parallel // 1) > $rv.slot)
        )
    ' >/dev/null 2>&1
}

# llm_validate_cloud ROLES_JSON
# Cloud integrity: >=1 role, every role carries a non-empty hosted model id.
llm_validate_cloud() {
    printf '%s' "$1" | jq -e '
        (type == "object") and (length > 0) and
        all(to_entries[];
            (.value | type) == "object" and
            (.value.model | type) == "string" and (.value.model | length) > 0
        )
    ' >/dev/null 2>&1
}

# llm_write_stack MODE MODELS_JSON ROLES_JSON MODELS_DIR BIFROST_PORT OPENCODE_PORT SUBAGENT_DEPTH
# Materialises the shared manifest. MODE is "cloud" or "local".
llm_write_stack() {
    _mode="$1"; _m="$2"; _r="$3"; _md="$4"; _bp="$5"; _op="$6"; _sd="$7"
    mkdir -p "$(dirname "$STACK_FILE")"
    if [ "$_mode" = "cloud" ]; then
        jq -n --argjson r "$_r" \
            --arg md "$_md" --arg bp "$_bp" --arg op "$_op" --arg sd "$_sd" \
            --argjson schema "$STACK_SCHEMA" \
            '{
                schema: $schema,
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
    else
        jq -n --argjson m "$_m" --argjson r "$_r" \
            --arg md "$_md" --arg bp "$_bp" --arg op "$_op" --arg sd "$_sd" \
            --argjson schema "$STACK_SCHEMA" \
            '{
                schema: $schema,
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
    fi
}

# llm_write_models_json MODELS_JSON MODELS_DIR
# Back-compat mirror: models.json reflects the FIRST model only (legacy fetch path).
llm_write_models_json() {
    _m="$1"; _md="$2"
    mkdir -p "$FEATURE_MODELS_DIR"
    _hf="$(printf '%s' "$_m" | jq -r '.[0].hf // empty' 2>/dev/null || true)"
    _q="$(printf '%s' "$_m" | jq -r '.[0].quant // empty' 2>/dev/null || true)"
    jq -n --arg m "$_hf" --arg q "$_q" --arg d "$_md" \
        '{model: $m, quant: $q, models_dir: $d}' >"$FEATURE_MODELS_DIR/models.json"
}

# llm_refresh_bifrost LLAMA_PORT_FALLBACK TEMPLATE_DIR
# bifrost bakes its routing at build time, so a runtime stack change must
# re-materialise it. write-bifrost-config.sh is installed by the bifrost
# feature as a re-runnable utility, so this is a no-op when absent.
llm_refresh_bifrost() {
    _fallback="${1:-8089}"
    _tpl="${2:-}"
    _bin="$LLM_LAB_DIR/bifrost/write-bifrost-config.sh"
    [ -x "$_bin" ] || { echo "bifrost not installed — skipping config refresh"; return 0; }
    if [ -n "$_tpl" ] && [ -f "$_tpl/bifrost.json" ]; then
        "$_bin" "$STACK_FILE" "$LLM_LAB_DIR/bifrost/config/bifrost.json" "$_fallback" "$_tpl/bifrost.json" \
            || echo "WARNING: bifrost config refresh failed (routing may be stale)"
    else
        "$_bin" "$STACK_FILE" "$LLM_LAB_DIR/bifrost/config/bifrost.json" "$_fallback" \
            || echo "WARNING: bifrost config refresh failed (routing may be stale)"
    fi
}

# llm_persist_models_dir MODELS_DIR
# Replaces any previously persisted MODELS_DIR so later shells do not inherit a
# stale build-time value (e.g. the CLI's /tmp/dev-container-features/... path).
llm_persist_models_dir() {
    [ -n "$1" ] || return 0
    _cur=""
    [ -f /etc/environment ] && _cur="$(grep -m1 '^export MODELS_DIR=' /etc/environment 2>/dev/null || true)"
    [ "$_cur" = "export MODELS_DIR=$1" ] && return 0
    if [ -n "$_cur" ]; then
        sed -i "s|^export MODELS_DIR=.*|export MODELS_DIR=$1|" /etc/environment
    else
        echo "export MODELS_DIR=$1" >>/etc/environment
    fi
}
