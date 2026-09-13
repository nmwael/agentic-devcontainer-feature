#!/usr/bin/env bats
# Container-side assertions for the opencode-agents feature. The CLI must be on
# PATH for NON-interactive shells too (postStartCommand, crons, CI) - not just
# login shells where the official installer's rc-file edit applies.

@test "opencode CLI is on PATH for non-interactive shells" {
    command -v opencode
    [ -x /usr/local/bin/opencode ]
    [ "$(readlink /usr/local/bin/opencode)" = "/root/.opencode/bin/opencode" ]
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

@test "payload scaffold deployed into the workspace by install" {
    [ -f /workspaces/ci/AGENTS.md ]
    [ -f /workspaces/ci/AGENTS_LIFECYCLE.md ]
    [ -d /workspaces/ci/library ]
    [ -d /workspaces/ci/.opencode/agent ]
}

@test "second install is a no-op (idempotent)" {
    run /bin/sh /tmp/feature/install.sh
    [ "$status" -eq 0 ]
    command -v opencode
    [ -f /workspaces/ci/AGENTS.md ]
}