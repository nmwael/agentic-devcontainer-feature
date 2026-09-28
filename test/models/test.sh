#!/bin/bash
# devcontainer features test — models (auto-generated, default options).
# Default model stack: single gemma4-26b-a4b model on :8089, 8 roles pinned
# to slots, shared stack.json manifest written, back-compat models.json mirror.
set -e

fail() { echo "FAIL: $*"; exit 1; }
ok() { echo "ok: $*"; }

[ -x /usr/local/share/llm-lab/models/fetch-models.sh ] || fail "fetch-models.sh missing"
ok "fetch-models.sh installed (executable)"

STACK=/usr/local/share/llm-lab/stack.json
[ -f "$STACK" ] || fail "stack.json manifest missing"
jq -e . "$STACK" >/dev/null 2>&1 || fail "stack.json is not valid JSON"
ok "stack.json manifest present + valid JSON"

[ "$(jq '.models | length' "$STACK")" -ge 1 ] || fail "stack.json declares no models"
[ "$(jq '.roles | length' "$STACK")" -ge 1 ] || fail "stack.json declares no roles"
ok "stack.json: $(jq '.models | length' "$STACK") model(s), $(jq '.roles | length' "$STACK") role(s)"

# Default manifest reproduces the single-model legacy stack exactly.
jq -e '.models[0].name == "gemma4-26b-a4b" and .models[0].port == 8089 and .models[0].context == 65536' "$STACK" \
    >/dev/null 2>&1 || fail "default model does not match single-model legacy stack"
ok "default model matches legacy stack (gemma4-26b-a4b :8089 ctx 65536)"

[ -f /usr/local/share/llm-lab/models/models.json ] || fail "models.json back-compat mirror missing"
ok "models.json back-compat mirror present"

grep -q "MODELS_DIR" /etc/environment || fail "MODELS_DIR not exported in /etc/environment"
ok "MODELS_DIR exported in /etc/environment"

# Per-model `url` support (1.3.0): exact repo/filename.gguf, since real repos
# disagree on the -QUANT vs .QUANT separator and cannot be derived from hf+quant.
FETCH=/usr/local/share/llm-lab/models/fetch-models.sh
grep -q 'https://huggingface.co/\${url}' "$FETCH" || fail "fetch-models.sh does not honour the per-model url field"
ok "fetch-models.sh honours the per-model url field"

# The legacy hf-derived path must remain byte-identical for configs without url.
grep -q 'resolve/main/\${MODEL_BASE}-\${quant}\.gguf' "$FETCH" \
    || fail "legacy hf-derived download path regressed"
ok "legacy hf-derived download path preserved (no url)"

# Downloaded names must stay discoverable by the auto-startup.sh glob
# *<hf with / -> _>*<quant>*.gguf, otherwise the server silently skips the model.
grep -q "tr '/' '_'" "$FETCH" || fail "fetch-models.sh no longer normalises slashes for the filename"
ok "filename normalises hf slashes (auto-startup.sh glob stays matchable)"

dash -n "$FETCH" 2>/dev/null || sh -n "$FETCH" || fail "fetch-models.sh is not POSIX-sh clean"
ok "fetch-models.sh is POSIX-sh clean"

# A 4xx/5xx body must not be persisted: the idempotency check would otherwise
# treat the error page as a finished model and never retry.
grep -q -- '--fail' "$FETCH" || fail "curl is not --fail; HTTP error pages get saved as .gguf"
grep -q '!= "GGUF"' "$FETCH" || fail "fetched files are not validated as GGUF"
ok "rejects non-GGUF downloads and cleans up on failure"

echo "PASS: models"