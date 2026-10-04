#!/bin/bash
# Runtime profile resolution — regression tests for the build/runtime split.
#
# Bug this guards against: features install at BUILD time with $PWD set to the
# devcontainer CLI's temp extraction dir (/tmp/dev-container-features/<id>_<n>),
# not the workspace. The old install.sh read profile files from "$PWD/.devcontainer"
# (never present) and defaulted MODELS_DIR to "$PWD/models", baking an unreachable
# temp path into stack.json and /etc/environment.
#
# These tests drive install.sh and resolve-stack.sh the way the CLI does, with a
# hermetic LLM_LAB_DIR so they never touch the real /usr/local/share/llm-lab.
set -euo pipefail

# Where the feature installs its runtime pieces inside the image.
INSTALLED="${INSTALLED_FEATURE_DIR:-/usr/local/share/llm-lab/models}"
[ -f "$INSTALLED/resolve-stack.sh" ] || { echo "FAIL: no resolve-stack.sh under $INSTALLED"; exit 1; }

# The RESOLVER half needs only what the feature installs into the image.
# The BUILD half additionally needs install.sh + templates/, which are NOT installed.
# So the build cases run only when the feature source is reachable (CI checkout / local
# dev); in the container-only harness we still exercise the full resolver behaviour.
SRC=""
for cand in "${FEATURE_DIR:-}" "$(dirname "$0")/../../src/models"; do
    [ -n "$cand" ] || continue
    if [ -f "$cand/install.sh" ]; then SRC="$(CDPATH='' cd -- "$cand" && pwd)"; break; fi
done
HAVE_SRC=0
[ -n "$SRC" ] && HAVE_SRC=1

TEST_TMP="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP"' EXIT

WORK="$TEST_TMP/llmlab"
WS="$TEST_TMP/ws"
BUILD_CWD="$TEST_TMP/dev-container-features/models_3"

export LLM_LAB_DIR="$WORK"
export STACK_FILE="$WORK/stack.json"
export FEATURE_MODELS_DIR="$WORK/models"
unset MODELS ROLES CLOUD_MODE CLOUD_MODEL MODELS_DIR BIFROST_PORT OPENCODE_PORT SUBAGENT_DEPTH || true

fail() { echo "FAIL: $*"; exit 1; }
ok() { echo "ok: $*"; }

build() { # build [env assignments...]
    rm -rf "$WORK"; mkdir -p "$WORK" "$BUILD_CWD"
    mkdir -p "$WS/.devcontainer"
    if [ "$HAVE_SRC" = "1" ]; then
        if [ "$#" -eq 0 ]; then
            ( cd "$BUILD_CWD" && sh "$SRC/install.sh" >/dev/null 2>&1 )
        else
            ( cd "$BUILD_CWD" && env "$@" sh "$SRC/install.sh" >/dev/null 2>&1 )
        fi
        return 0
    fi
    # Container-only harness: install.sh is not in the image, so synthesise the
    # build-time state install.sh would have produced (default gemma stack, plus the
    # .build-state marker). BUILD_* flags describe the variant being simulated.
    _kind="${BUILD_SIM:-default}"
    _m='[{"name":"gemma4-26b-a4b","provider":"local-gemma4-26b","hf":"gemma-4-26B-A4B-it-UD-IQ2_M","quant":"IQ2_M","port":8089,"context":65536,"parallel":5}]'    _r='{"architect":{"model":"gemma4-26b-a4b","slot":0},"coder":{"model":"gemma4-26b-a4b","slot":1},"researcher":{"model":"gemma4-26b-a4b","slot":2},"reviewer":{"model":"gemma4-26b-a4b","slot":3},"build":{"model":"gemma4-26b-a4b","slot":4},"ui":{"model":"gemma4-26b-a4b","slot":4},"artist":{"model":"gemma4-26b-a4b","slot":4},"ai-researcher":{"model":"gemma4-26b-a4b","slot":4}}'
    _mo=""; _mode=local; _cloud=false
    case "$_kind" in
        cloud) _cloud=true; _mode=cloud ;;
        opt)
            _mo='[{"name":"opt-only","provider":"p","hf":"org/o","quant":"Q4_K_M","port":8089,"context":8192,"parallel":2}]'
            ;;
    esac
    _r_arg="$_r"
    [ -n "$_mo" ] && _r_arg='{"coder":{"model":"opt-only","slot":0}}'
    if [ "$_cloud" = true ]; then
        jq -n --argjson r "$_r_arg" '{schema:1,models_dir:"",bifrost_port:8082,opencode_port:4096,subagent_depth:2,cloud:true,cloud_provider:"opencode",models:[],roles:$r}' >"$STACK_FILE"
    elif [ -n "$_mo" ]; then
        jq -n --argjson m "$_mo" --argjson r "$_r_arg" '{schema:1,models_dir:"",bifrost_port:8082,opencode_port:4096,subagent_depth:2,cloud:false,cloud_provider:"opencode",models:$m,roles:$r}' >"$STACK_FILE"
    else
        jq -n --argjson m "$_m" --argjson r "$_r_arg" '{schema:1,models_dir:"",bifrost_port:8082,opencode_port:4096,subagent_depth:2,cloud:false,cloud_provider:"opencode",models:$m,roles:$r}' >"$STACK_FILE"
    fi
    mkdir -p "$FEATURE_MODELS_DIR"
    printf "BUILD_MODELS='%s'\nBUILD_ROLES='%s'\nBUILD_MODE='%s'\nBUILD_MODELS_DIR=''\nBUILD_BIFROST_PORT='8082'\nBUILD_OPENCODE_PORT='4096'\nBUILD_SUBAGENT_DEPTH='2'\nBUILD_LLAMA_PORT='8089'\n" \
        "$_mo" "" "$_mode" >"$LLM_LAB_DIR/.build-state"
}
resolve() { # resolve [workspace]
    ( cd "${1:-$WS}" && sh "$INSTALLED/resolve-stack.sh" >/dev/null 2>&1 )
}
resolve_with_models_dir() { # resolve_with_models_dir <dir> [workspace]
    _d="$1"
    ( cd "${2:-$WS}" && MODELS_DIR="$_d" sh "$INSTALLED/resolve-stack.sh" >/dev/null 2>&1 )
}
stack_get() { jq -r "$1" "$STACK_FILE"; }

# The build must never bake a temp/CLI-extraction path into models_dir.
build
D="$(stack_get '.models_dir')"
case "$D" in
    ""|/tmp/*|*/dev-container-features/*) ok "build-time models_dir not a temp path ('$D')" ;;
    *) fail "build-time models_dir leaked an unreachable path: $D" ;;
esac

# /etc/environment must not gain an empty MODELS_DIR export that would shadow
# the runtime value for every later shell.
if [ -f /etc/environment ] && grep -q '^export MODELS_DIR=$' /etc/environment 2>/dev/null; then
    fail "empty MODELS_DIR persisted to /etc/environment"
fi
ok "no empty MODELS_DIR persisted"

# Profile files are only visible at runtime, which is where they must be honoured.
cat >"$WS/.devcontainer/llm-lab-models.json" <<'JSON'
[{"name":"t-model-a","provider":"local-a","hf":"org/a","quant":"Q4_K_M","port":8089,"context":16384,"parallel":1},
 {"name":"t-model-b","provider":"local-b","hf":"org/b","quant":"Q4_K_M","port":8090,"context":8192,"parallel":1}]
JSON
cat >"$WS/.devcontainer/llm-lab-roles.json" <<'JSON'
{"coder":{"model":"t-model-b","slot":0},"architect":{"model":"t-model-a","slot":0}}
JSON
resolve
[ "$(stack_get '[.models[].name] | join(",")')" = "t-model-a,t-model-b" ] \
    || fail "runtime resolver did not apply profile models"
ok "runtime resolver applies profile models"

[ "$(stack_get '.models_dir')" = "$WS/models" ] \
    || fail "models_dir should default to <workspace>/models, got $(stack_get '.models_dir')"
ok "models_dir defaults to <workspace>/models"

[ "$(stack_get '.roles | length')" = "2" ] || fail "roles not applied"
[ "$(stack_get '.cloud')" = "false" ] || fail "profile stack must be local (cloud=false)"
ok "roles + cloud flag correct"

# Idempotent: repeated container starts must not drift the manifest.
A="$(jq -Sc . "$STACK_FILE")"; resolve; B="$(jq -Sc . "$STACK_FILE")"
[ "$A" = "$B" ] || fail "resolver is not idempotent"
ok "resolver is idempotent"

# Explicit MODELS option must win over a stray workspace profile file.
BUILD_SIM=opt build 'MODELS=[{"name":"opt-only","provider":"p","hf":"org/o","quant":"Q4_K_M","port":8089,"context":8192,"parallel":2}]' \
      'ROLES={"coder":{"model":"opt-only","slot":0}}'
resolve
[ "$(stack_get '[.models[].name] | join(",")')" = "opt-only" ] \
    || fail "explicit MODELS option was clobbered by profile files"
ok "explicit MODELS option takes precedence"

# No profile files -> the build-time stack must survive untouched.
build
mkdir -p "$TEST_TMP/empty/.devcontainer"
resolve "$TEST_TMP/empty"
[ "$(stack_get '.models[0].name')" = "gemma4-26b-a4b" ] \
    || fail "resolver must not rewrite the stack when no profile files exist"
ok "no profile files leaves build-time stack intact"

# A cloud-only box (no profile files) must stay cloud.
BUILD_SIM=cloud build 'CLOUD_MODE=true'
resolve "$TEST_TMP/empty"
[ "$(stack_get '.cloud')" = "true" ] || fail "cloud box flipped to local"
[ "$(stack_get '.models | length')" = "0" ] || fail "cloud box gained local models"
ok "cloud-only box preserved"

# Malformed profile JSON must not corrupt a working stack.
build
echo '{ not json at all' >"$WS/.devcontainer/llm-lab-models.json"
resolve
[ "$(stack_get '.models[0].name')" = "gemma4-26b-a4b" ] \
    || fail "malformed profile JSON corrupted the stack"
ok "malformed profile JSON is rejected safely"

# A role pointing past its model's parallel capacity must be rejected — this is
# the common profile mistake (8 roles onto a parallel:1 model).
build
cat >"$WS/.devcontainer/llm-lab-models.json" <<'JSON'
[{"name":"solo","provider":"p","hf":"org/s","quant":"Q4_K_M","port":8089,"context":8192,"parallel":1}]
JSON
cat >"$WS/.devcontainer/llm-lab-roles.json" <<'JSON'
{"coder":{"model":"solo","slot":4}}
JSON
resolve
[ "$(stack_get '.models[0].name')" = "gemma4-26b-a4b" ] \
    || fail "slot >= parallel must fail integrity"
ok "slot >= parallel rejected"

# A role referencing an unknown model must be rejected.
cat >"$WS/.devcontainer/llm-lab-roles.json" <<'JSON'
{"coder":{"model":"does-not-exist","slot":0}}
JSON
resolve
[ "$(stack_get '.models[0].name')" = "gemma4-26b-a4b" ] \
    || fail "unknown role model must fail integrity"
ok "unknown role model rejected"

# An explicit MODELS_DIR option must override <workspace>/models.
# Restore a valid profile first: build() wipes $WS, so write the profile in.
build
cat >"$WS/.devcontainer/llm-lab-models.json" <<'JSON'
[{"name":"t-model-a","provider":"local-a","hf":"org/a","quant":"Q4_K_M","port":8089,"context":16384,"parallel":1}]
JSON
cat >"$WS/.devcontainer/llm-lab-roles.json" <<'JSON'
{"coder":{"model":"t-model-a","slot":0}}
JSON
resolve_with_models_dir "$TEST_TMP/custom-weights"
[ "$(stack_get '.models_dir')" = "$TEST_TMP/custom-weights" ] \
    || fail "MODELS_DIR option must win"
ok "MODELS_DIR option honoured"

# Both scripts must be POSIX-sh clean and ship from the feature root.
sh -n "$INSTALLED/resolve-stack.sh" || fail "resolve-stack.sh not sh-clean"
sh -n "$INSTALLED/stack-lib.sh" || fail "stack-lib.sh not sh-clean"
ok "resolver + shared lib are POSIX-sh clean"

echo "PASS: models runtime resolution"
