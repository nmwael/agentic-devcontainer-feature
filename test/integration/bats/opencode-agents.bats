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

@test "second install is a no-op (idempotent)" {
    run /bin/sh /tmp/feature/install.sh
    [ "$status" -eq 0 ]
    command -v opencode
    [ -x /usr/local/share/opencode-agents/scaffold.sh ]
}