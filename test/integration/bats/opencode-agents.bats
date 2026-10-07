#!/usr/bin/env bats
# Container-side assertions for the opencode-agents feature.

@test "agent scaffold installed at INSTALL_DIR" {
    [ -f /usr/local/share/opencode-agents/AGENTS.md ]
    [ -f /usr/local/share/opencode-agents/AGENTS_LIFECYCLE.md ]
    [ -x /usr/local/share/opencode-agents/scaffold.sh ]
    [ -d /usr/local/share/opencode-agents/.opencode/agent ]
    [ -d /usr/local/share/opencode-agents/library ]
}

@test "scaffold.sh deploys the payload into the workspace when run" {
    run /usr/local/share/opencode-agents/scaffold.sh
    [ "$status" -eq 0 ]
    [ -f /workspaces/ci/AGENTS.md ]
    [ -f /workspaces/ci/AGENTS_LIFECYCLE.md ]
    [ -d /workspaces/ci/library ]
    [ -d /workspaces/ci/.opencode/agent ]
}

@test "scaffold.sh generates opencode.json from the shipped fragment (fresh workspace)" {
    fresh=$(mktemp -d)
    run env WORKSPACE="$fresh" /usr/local/share/opencode-agents/scaffold.sh
    [ "$status" -eq 0 ]
    [ -s "$fresh/opencode.json" ]
    python3 -m json.tool "$fresh/opencode.json" >/dev/null
    grep -q '"provider"' "$fresh/opencode.json"
    grep -q '"subagent_depth"' "$fresh/opencode.json"
    grep -q '"enabled_providers"' "$fresh/opencode.json"
    grep -q '"port": 4096' "$fresh/opencode.json"
    rm -rf "$fresh"
}

@test "scaffold.sh fills an empty opencode.json but keeps a real consumer config" {
    work=$(mktemp -d)
    : > "$work/opencode.json"
    run env WORKSPACE="$work" /usr/local/share/opencode-agents/scaffold.sh
    [ "$status" -eq 0 ]
    [ -s "$work/opencode.json" ]
    python3 -m json.tool "$work/opencode.json" >/dev/null
    grep -q '"provider"' "$work/opencode.json"
    grep -q '"subagent_depth"' "$work/opencode.json"
    printf '{"custom":true}\n' > "$work/opencode.json"
    run env WORKSPACE="$work" /usr/local/share/opencode-agents/scaffold.sh
    grep -q '"custom":true' "$work/opencode.json"
    run grep -q '"provider"' "$work/opencode.json"
    [ "$status" -ne 0 ]
    rm -rf "$work"
}

@test "stack.json -> opencode.json generator shipped and executable" {
    [ -f /usr/local/share/opencode-agents/generate-opencode.jq ]
    [ -x /usr/local/share/opencode-agents/generate-opencode.sh ]
    run dash -n /usr/local/share/opencode-agents/generate-opencode.sh
    [ "$status" -eq 0 ]
}

@test "generate-opencode.sh materializes opencode.json from a simulated stack.json" {
    stack=$(mktemp)
    cat >"$stack" <<'J'
{"schema":1,"models_dir":"/tmp/m","bifrost_port":8082,"opencode_port":4096,"subagent_depth":2,"cloud":false,"cloud_provider":"opencode","models":[{"name":"gemma4-26b-a4b","provider":"local-gemma4-26b","hf":"x","quant":"Q2","port":8089,"context":65536,"parallel":5}],"roles":{"architect":{"model":"gemma4-26b-a4b","slot":0},"build":{"model":"gemma4-26b-a4b","slot":4}}}
J
    out=$(mktemp -d)
    run /usr/local/share/opencode-agents/generate-opencode.sh "$stack" "$out/opencode.json"
    [ "$status" -eq 0 ]
    [ -s "$out/opencode.json" ]
    python3 -m json.tool "$out/opencode.json" >/dev/null
    grep -q '"local-gemma4-26b"' "$out/opencode.json"
    rm -rf "$out" "$stack"
}

@test "generate-opencode.sh cloud mode routes every agent to opencode/* and omits local providers" {
    stack=$(mktemp)
    cat >"$stack" <<'J'
{"schema":1,"models_dir":"/tmp/m","bifrost_port":8082,"opencode_port":4096,"subagent_depth":2,"cloud":true,"cloud_provider":"opencode","models":[],"roles":{"architect":{"model":"big-pickle","slot":0},"coder":{"model":"ling-3.1-flash-free","slot":0}}}
J
    out=$(mktemp -d)
    run /usr/local/share/opencode-agents/generate-opencode.sh "$stack" "$out/opencode.json"
    [ "$status" -eq 0 ]
    grep -q '"opencode/big-pickle"' "$out/opencode.json"
    grep -q '"opencode/ling-3.1-flash-free"' "$out/opencode.json"
    run grep -q '"local-gemma4-26b"' "$out/opencode.json"
    [ "$status" -ne 0 ]
    rm -rf "$out" "$stack"
}

@test "scaffold.sh generates from stack.json when present (fragment when absent)" {
    stack=$(mktemp)
    cat >"$stack" <<'J'
{"schema":1,"models_dir":"/tmp/m","bifrost_port":8082,"opencode_port":4096,"subagent_depth":2,"cloud":false,"cloud_provider":"opencode","models":[{"name":"gemma4-26b-a4b","provider":"local-gemma4-26b","hf":"x","quant":"Q2","port":8089,"context":65536,"parallel":5}],"roles":{"architect":{"model":"gemma4-26b-a4b","slot":0},"build":{"model":"gemma4-26b-a4b","slot":4}}}
J
    fresh=$(mktemp -d)
    run env WORKSPACE="$fresh" STACK_JSON="$stack" /usr/local/share/opencode-agents/scaffold.sh
    [ "$status" -eq 0 ]
    [ -s "$fresh/opencode.json" ]
    grep -q '"local-gemma4-26b"' "$fresh/opencode.json"
    rm -rf "$fresh" "$stack"
}

@test "second install is a no-op (idempotent)" {
    run /bin/sh /tmp/feature/install.sh
    [ "$status" -eq 0 ]
    [ -x /usr/local/share/opencode-agents/scaffold.sh ]
}

@test "generate-opencode.sh defaults limit.output to 8192, never limit.context" {
    stack=$(mktemp)
    cat >"$stack" <<'J'
{"schema":1,"models_dir":"/tmp/m","bifrost_port":8082,"opencode_port":4096,"subagent_depth":2,"cloud":false,"cloud_provider":"opencode","models":[{"name":"gemma4-26b-a4b","provider":"local-gemma4-26b","hf":"x","quant":"Q2","port":8089,"context":65536,"parallel":2}],"roles":{"architect":{"model":"gemma4-26b-a4b","slot":0}}}
J
    out=$(mktemp -d)
    run /usr/local/share/opencode-agents/generate-opencode.sh "$stack" "$out/opencode.json"
    [ "$status" -eq 0 ]
    jq -e '[.provider[] | .models[]? | .limit.output] | all(. == 8192)' "$out/opencode.json" >/dev/null || {
        echo "limit.output must default to 8192 (context was 65536):"
        jq -c '.provider[] | .models[]? | .limit' "$out/opencode.json"
        return 1
    }
    jq -e '[.provider[] | .models[]? | (.limit.output == .limit.context)] | any | not' "$out/opencode.json" >/dev/null || {
        echo "limit.output == limit.context collapses opencode's compaction threshold to 0 (compact-every-turn loop)"
        return 1
    }
    rm -rf "$out" "$stack"
}

@test "generate-opencode.sh honours an explicit per-model output" {
    stack=$(mktemp)
    cat >"$stack" <<'J'
{"schema":1,"models_dir":"/tmp/m","bifrost_port":8082,"opencode_port":4096,"subagent_depth":2,"cloud":false,"cloud_provider":"opencode","models":[{"name":"qwen3-8b","provider":"local-qwen3-8b","hf":"x","quant":"Q4","port":8089,"context":40960,"output":4096,"parallel":1}],"roles":{"build":{"model":"qwen3-8b","slot":0}}}
J
    out=$(mktemp -d)
    run /usr/local/share/opencode-agents/generate-opencode.sh "$stack" "$out/opencode.json"
    [ "$status" -eq 0 ]
    jq -e '.provider["local-qwen3-8b"].models["qwen3-8b"].limit.output == 4096' "$out/opencode.json" >/dev/null || {
        echo "explicit profile output=4096 must reach limit.output:"
        jq -c '.provider["local-qwen3-8b"].models' "$out/opencode.json"
        return 1
    }
    jq -e '.provider["local-qwen3-8b"].models["qwen3-8b-s0"].limit.output == 4096' "$out/opencode.json" >/dev/null || {
        echo "slot id must carry the same explicit output"
        return 1
    }
    rm -rf "$out" "$stack"
}
