#!/usr/bin/env bats
# Container-side assertions for the llama-server feature (installed twice at
# build time - these must hold on the SECOND install too).

@test "llama-server binary installed (assets differ in layout: root or bin/)" {
    [ -x /opt/llama-server/llama-server ] || [ -x /opt/llama-server/bin/llama-server ]
}

@test "llama-server binary is a real asset (thin wrapper + runtime libs)" {
    if [ -f /opt/llama-server/llama-server ]; then
        dir=/opt/llama-server
        size=$(stat -c %s /opt/llama-server/llama-server)
    else
        dir=/opt/llama-server/bin
        size=$(stat -c %s /opt/llama-server/bin/llama-server)
    fi
    # Modern llama.cpp split builds: llama-server is a thin wrapper; the code
    # lives in libllama.so* + libggml-*.so next to it.
    [ "$size" -gt 100000 ]
    find "$dir" -maxdepth 1 -name 'libllama.so*' | grep -q .
    find "$dir" -maxdepth 1 -name 'libggml-*.so' | grep -q .
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