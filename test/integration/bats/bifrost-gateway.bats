#!/usr/bin/env bats
# Container-side assertions for the bifrost-gateway feature. The nvidia/cuda
# base images lack node/npm, so the feature must self-provision them, install
# @maximhq/bifrost, and write a launcher that points at the package's REAL
# entrypoint (bin.js - the old dist/index.js path never existed).

@test "node and npm are provisioned by the feature" {
    command -v node
    command -v npm
}

@test "@maximhq/bifrost installed into the feature dir" {
    [ -f /usr/local/share/llm-lab/bifrost/node_modules/@maximhq/bifrost/bin.js ]
}

@test "start-bifrost launcher installed and executable" {
    [ -x /usr/local/bin/start-bifrost ]
}

@test "launcher references the packaged entrypoint (bin.js), not dist/" {
    grep -q "node_modules/@maximhq/bifrost/bin.js" /usr/local/bin/start-bifrost
    if grep -q "dist/index.js" /usr/local/bin/start-bifrost; then
        echo "launcher still points at the nonexistent dist/index.js"
        return 1
    fi
}

@test "scaffolded config dir exists (workspace-agnostic)" {
    [ -d /usr/local/share/llm-lab/bifrost/config ]
}

@test "launcher is sh-clean" {
    dash -n /usr/local/bin/start-bifrost
}

@test "write-bifrost-config.sh shipped, executable, sh-clean" {
    [ -f /usr/local/share/llm-lab/bifrost/write-bifrost-config.sh ]
    [ -x /usr/local/share/llm-lab/bifrost/write-bifrost-config.sh ]
    run dash -n /usr/local/share/llm-lab/bifrost/write-bifrost-config.sh
    [ "$status" -eq 0 ]
}

@test "scaffolded bifrost.json uses the v2 schema (multi-upstream shape)" {
    cfg=/usr/local/share/llm-lab/bifrost/config/bifrost.json
    [ -f "$cfg" ]
    python3 - <<'PY'
import json
with open('/usr/local/share/llm-lab/bifrost/config/bifrost.json') as f:
    c = json.load(f)
assert 'providers' in c
assert c.get('config_store', {}).get('enabled') is False, "config_store.enabled must be false"
p = next(iter(c['providers'].values()))
assert 'network_config' in p and 'base_url' in p['network_config']
assert 'custom_provider_config' in p and p['custom_provider_config'].get('base_provider_type') == 'openai'
assert isinstance(p['keys'], list)
PY
}

@test "write-bifrost-config.sh materializes one provider per upstream from a simulated stack.json" {
    stack=$(mktemp)
    out=$(mktemp --suffix=.json)
    python3 - <<'PY' >"$stack"
import json
print(json.dumps({
    "schema": 1, "models_dir": "/models", "bifrost_port": 8082,
    "opencode_port": 4096, "subagent_depth": 2,
    "models": [
        {"name": "gemma4-26b-a4b", "provider": "local-gemma4-26b",
         "hf": "gemma-4-26B-A4B-it-UD-IQ2_M", "quant": "IQ2_M",
         "port": 8089, "context": 65536, "parallel": 5},
        {"name": "gemma4-31b-a4b", "provider": "local-gemma4-31b",
         "hf": "gemma-4-31B-A4B-it-UD-IQ3_M", "quant": "IQ3_M",
         "port": 8090, "context": 32768, "parallel": 3}
    ],
    "roles": {}
}))
PY
    run /usr/local/share/llm-lab/bifrost/write-bifrost-config.sh "$stack" "$out"
    [ "$status" -eq 0 ]
    python3 - <<'PY' "$out"
import json, sys
with open(sys.argv[1]) as f:
    c = json.load(f)
providers = c['providers']
assert set(providers) == {'gemma4-26b-a4b', 'gemma4-31b-a4b'}
assert providers['gemma4-26b-a4b']['network_config']['base_url'].endswith(':8089')
assert providers['gemma4-31b-a4b']['network_config']['base_url'].endswith(':8090')
# model-id routing: keys[].models allowlists the provider's slug with a wildcard
assert 'gemma4-26b-a4b*' in providers['gemma4-26b-a4b']['keys'][0]['models']
PY
    rm -f "$stack" "$out"
}

@test "second install stays functional (idempotent)" {
    run /bin/sh /tmp/feature/install.sh
    [ "$status" -eq 0 ]
    [ -x /usr/local/bin/start-bifrost ]
}