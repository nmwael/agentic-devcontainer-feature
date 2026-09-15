#!/usr/bin/env bats
# Container-side assertions for the models feature. Install time must NEVER
# download model weights (9-16 GB) - it only scaffolds the on-demand fetch
# script. A quick default sanity check builds on that.

@test "fetch-models.sh scaffolded into the feature dir" {
    [ -f /usr/local/share/llm-lab/models/fetch-models.sh ]
    [ -x /usr/local/share/llm-lab/models/fetch-models.sh ]
}

@test "fetch-models.sh is sh-clean" {
    dash -n /usr/local/share/llm-lab/models/fetch-models.sh
}

@test "default model name/quant embedded in the fetch script" {
    grep -q "gemma-4-26B-A4B-it-UD-IQ2_M" /usr/local/share/llm-lab/models/fetch-models.sh
    grep -q 'QUANT=' /usr/local/share/llm-lab/models/fetch-models.sh
}

@test "MODELS_DIR exported to /etc/environment" {
    grep -q "MODELS_DIR" /etc/environment
}

@test "stack.json manifest written with schema and defaults" {
    [ -f /usr/local/share/llm-lab/stack.json ]
    python3 - <<'PY'
import json
with open('/usr/local/share/llm-lab/stack.json') as f:
    s = json.load(f)
assert s['schema'] == 1
assert isinstance(s['models'], list) and len(s['models']) >= 1
assert isinstance(s['roles'], dict)
assert s['bifrost_port'] == 8082
assert s['opencode_port'] == 4096
m0 = s['models'][0]
assert m0['name'] == 'gemma4-26b-a4b'
assert m0['provider'] == 'local-gemma4-26b'
assert m0['port'] == 8089
# every role maps onto an existing model with slot < its parallel count
by_name = {m['name']: m for m in s['models']}
for role, r in s['roles'].items():
    assert r['model'] in by_name, f"role {role} references unknown model {r['model']}"
    assert r['slot'] < by_name[r['model']]['parallel'], f"role {role} slot OOB"
PY
}

@test "models.json backward-compat mirror written" {
    [ -f /usr/local/share/llm-lab/models/models.json ]
    python3 -c "import json; d=json.load(open('/usr/local/share/llm-lab/models/models.json')); assert d['model'] == 'gemma-4-26B-A4B-it-UD-IQ2_M'"
}

@test "no model weights were downloaded at install time" {
    [ ! -d /workspaces/ci/models ] || [ -z "$(ls -A /workspaces/ci/models 2>/dev/null)" ]
}

@test "second install is a no-op (idempotent)" {
    run /bin/sh /tmp/feature/install.sh
    [ "$status" -eq 0 ]
    [ -x /usr/local/share/llm-lab/models/fetch-models.sh ]
}