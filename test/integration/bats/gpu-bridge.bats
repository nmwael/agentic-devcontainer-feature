#!/usr/bin/env bats
# Container-side assertions for the gpu-bridge feature. CI containers are NOT
# WSL2, so the feature must stub out cleanly (exit 0) - including on re-runs.

@test "non-WSL2 install exits 0 (stub no-op, not an error)" {
    run /bin/sh /tmp/feature/install.sh
    [ "$status" -eq 0 ]
}

@test "stub reports the WSL2 skip explicitly" {
    run /bin/sh /tmp/feature/install.sh
    [[ "$output" == *"Not running in WSL2"* ]]
}

@test "default WSL2_ONLY=false means stub, WSL2_ONLY=true means hard fail" {
    run env WSL2_ONLY=true /bin/sh /tmp/feature/install.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *"requires WSL2"* ]]
}

@test "no WSL2 artifacts are created outside WSL2" {
    [ ! -d /usr/lib/wsl/lib ]
    [ ! -d /usr/lib/wsl/drivers ]
}