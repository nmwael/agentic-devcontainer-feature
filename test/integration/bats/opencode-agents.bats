#!/usr/bin/env bats
# Container-side assertions for the opencode-agents feature. The CLI must be on
# PATH for NON-interactive shells too (postStartCommand, crons, CI) - not just
# login shells where the official installer's rc-file edit applies.

@test "opencode CLI is on PATH for non-interactive shells (all users)" {
    command -v opencode
    # Must be a real file at /usr/local/bin, NOT a symlink into ~/ (0700,
    # untraversable by the remoteUser) — the 1.0.4 copy fix.
    [ -f /usr/local/bin/opencode ]
    [ ! -L /usr/local/bin/opencode ]
    [ -x /usr/local/bin/opencode ]
    size=$(stat -c %s /usr/local/bin/opencode)
    [ "$size" -gt 1000000 ]
}

@test "opencode CLI runs and reports a version" {
    run opencode --version
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

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
    grep -q '"local-gemma4-26b"' "$fresh/opencode.json"
    grep -q '"port": 4096' "$fresh/opencode.json"
    grep -q 'gemma4-26b-a4b-s0' "$fresh/opencode.json"
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
    out=$(mktemp --suffix=.json)
    python3 - <<'PY' >"$stack"
import json
print(json.dumps({
    "schema": 1,
    "models_dir": "/models",
    "bifrost_port": 8082,
    "opencode_port": 4096,
    "subagent_depth": 2,
    "models": [
        {"name": "gemma4-26b-a4b", "provider": "local-gemma4-26b",
         "hf": "gemma-4-26B-A4B-it-UD-IQ2_M", "quant": "IQ2_M",
         "port": 8089, "context": 65536, "parallel": 5}
    ],
    "roles": {
        "architect": {"model": "gemma4-26b-a4b", "slot": 0},
        "coder":     {"model": "gemma4-26b-a4b", "slot": 1},
        "researcher": {"model": "gemma4-26b-a4b", "slot": 2},
        "reviewer":  {"model": "gemma4-26b-a4b", "slot": 3},
        "build":     {"model": "gemma4-26b-a4b", "slot": 4},
        "ui":        {"model": "gemma4-26b-a4b", "slot": 4},
        "artist":    {"model": "gemma4-26b-a4b", "slot": 4},
        "ai-researcher": {"model": "gemma4-26b-a4b", "slot": 4}
    }
}))
PY
    run /usr/local/share/opencode-agents/generate-opencode.sh "$stack" "$out"
    [ "$status" -eq 0 ]
    python3 -m json.tool "$out" >/dev/null
    grep -q '"local-gemma4-26b"' "$out"
    grep -q '"port": 4096' "$out"
    grep -q 'gemma4-26b-a4b-s0' "$out"
    grep -q '"enabled_providers"' "$out"
    grep -q '"subagent_depth"' "$out"
    grep -q '"agent"' "$out"
    rm -f "$stack" "$out"
}

@test "generate-opencode.sh cloud mode routes every agent to opencode/* and omits local providers" {
    stack=$(mktemp)
    out=$(mktemp --suffix=.json)
    python3 - <<'PY' >"$stack"
import json
print(json.dumps({
    "schema": 1,
    "models_dir": "/models",
    "bifrost_port": 8082,
    "opencode_port": 4096,
    "subagent_depth": 2,
    "cloud": True,
    "cloud_provider": "opencode",
    "models": [],
    "roles": {
        "architect": {"model": "big-pickle", "slot": 0},
        "coder":     {"model": "big-pickle", "slot": 0},
        "researcher": {"model": "big-pickle", "slot": 0},
        "reviewer":  {"model": "big-pickle", "slot": 0},
        "build":     {"model": "big-pickle", "slot": 0},
        "ui":        {"model": "big-pickle", "slot": 0},
        "artist":    {"model": "big-pickle", "slot": 0},
        "ai-researcher": {"model": "big-pickle", "slot": 0}
    }
}))
PY
    run /usr/local/share/opencode-agents/generate-opencode.sh "$stack" "$out"
    [ "$status" -eq 0 ]
    python3 -m json.tool "$out" >/dev/null
    [ "$(jq -r '.model' "$out")" = "opencode/big-pickle" ]
    [ "$(jq -r '.small_model' "$out")" = "opencode/big-pickle" ]
    [ "$(jq '[.enabled_providers[]] | length' "$out")" -eq 1 ]
    [ "$(jq -r '.enabled_providers[0]' "$out")" = "opencode" ]
    [ "$(jq '.provider | has("local-gemma4-26b")' "$out")" = "false" ]
    jq -e '.agent | to_entries | all(.value.model | startswith("opencode/"))' "$out" >/dev/null
    rm -f "$stack" "$out"
}

@test "scaffold.sh generates from stack.json when present (fragment when absent)" {
    stack=$(mktemp)
    python3 -c "import json; json.dump({'bifrost_port':8082,'opencode_port':4096,'subagent_depth':2,'models':[{'name':'gemma4-26b-a4b','provider':'local-gemma4-26b','hf':'gemma-4-26B-A4B-it-UD-IQ2_M','quant':'IQ2_M','port':8089,'context':65536,'parallel':5}],'roles':{'build':{'model':'gemma4-26b-a4b','slot':4}}}, open('$stack','w'))"
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
    command -v opencode
    [ -x /usr/local/share/opencode-agents/scaffold.sh ]
}