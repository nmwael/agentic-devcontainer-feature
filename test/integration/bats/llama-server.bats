#!/usr/bin/env bats
# Container-side assertions for the llama-server feature (installed twice at
# build time - these must hold on the SECOND install too).

@test "llama-server binary installed (assets differ in layout: root or bin/)" {
    [ -x /opt/llama-server/llama-server ] || [ -x /opt/llama-server/bin/llama-server ]
}

@test "llama-server binary is a real asset (not an empty degrade)" {
    if [ -f /opt/llama-server/llama-server ]; then
        size=$(stat -c %s /opt/llama-server/llama-server)
    else
        size=$(stat -c %s /opt/llama-server/bin/llama-server)
    fi
    [ "$size" -gt 1000000 ]
}

@test "llama-server symlinked onto PATH" {
    [ -L /usr/local/bin/llama-server ]
    command -v llama-server
    [ "$(readlink /usr/local/bin/llama-server)" = "/opt/llama-server/llama-server" ] || \
        [ "$(readlink /usr/local/bin/llama-server)" = "/opt/llama-server/bin/llama-server" ]
}

@test "VERSION marker written" {
    [ -f /opt/llama-server/VERSION ]
    grep -q "b10360" /opt/llama-server/VERSION
}

@test "second install is a no-op (idempotent)" {
    run /bin/sh /tmp/feature/install.sh
    [ "$status" -eq 0 ]
    [ -x /opt/llama-server/llama-server ] || [ -x /opt/llama-server/bin/llama-server ]
}