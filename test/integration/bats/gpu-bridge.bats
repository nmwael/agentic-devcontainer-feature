#!/usr/bin/env bats
# Container-side assertions for the gpu-bridge feature.
# FORCE_NONWSL=true forces the non-WSL2 code path regardless of host, so these
# assertions are deterministic even when CI itself runs under WSL2.

@test "non-WSL2 install exits 0 (stub no-op, not an error)" {
    run env FORCE_NONWSL=true /bin/sh /tmp/feature/install.sh
    [ "$status" -eq 0 ]
}

@test "stub reports the WSL2 skip explicitly" {
    run env FORCE_NONWSL=true /bin/sh /tmp/feature/install.sh
    echo "$output" | grep -qi "not running in wsl2"
}

@test "WSL2_ONLY=true hard-fails outside WSL2" {
    run env FORCE_NONWSL=true WSL2_ONLY=true /bin/sh /tmp/feature/install.sh
    [ "$status" -eq 1 ]
    echo "$output" | grep -qi "requires wsl2"
}

@test "no WSL2 artifacts are created outside WSL2" {
    run env FORCE_NONWSL=true /bin/sh /tmp/feature/install.sh
    [ ! -d /usr/lib/wsl/lib ]
    [ ! -d /usr/lib/wsl/drivers ]
}
