#!/usr/bin/env bats
# Container-side assertions for the llama-server feature (installed twice at
# build time - these must hold on the SECOND install too).

# Stub PIDs for the watchdog probe test; teardown is the supported hook — an
# EXIT trap here would clobber bats' own trap and abort the run mid-file.
WATCHDOG_STUB_PIDS=""

teardown() {
    for stub_pid in $WATCHDOG_STUB_PIDS; do
        kill "$stub_pid" 2>/dev/null || true
    done
    WATCHDOG_STUB_PIDS=""
}

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
    # Modern llama.cpp split builds: llama-server is a thin wrapper (~18 KB at
    # b10360); the code lives in libllama.so* + libggml-*.so next to it.
    [ "$size" -gt 10000 ]
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
@test "llama-watchdog installed and symlinked onto PATH" {
    [ -x /opt/llama-server/llama-watchdog.sh ]
    [ -L /usr/local/bin/llama-watchdog ]
    [ "$(readlink /usr/local/bin/llama-watchdog)" = "/opt/llama-server/llama-watchdog.sh" ]
    command -v llama-watchdog
}

@test "llama-watchdog passes dash -n" {
    run dash -n "$(command -v llama-watchdog)"
    [ "$status" -eq 0 ]
}

@test "llama-watchdog --probe: fast server 0, over-budget server 1, dead port 1" {
    work=$(mktemp -d)
    cat >"$work/stub.py" <<'PY'
import json
import sys
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

mode, port = sys.argv[1], int(sys.argv[2])


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        self.rfile.read(length)
        if mode == "slow":
            time.sleep(30)
        body = json.dumps(
            {"choices": [{"message": {"content": "OK"}}],
             "usage": {"completion_tokens": 1}}
        ).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


class Server(HTTPServer):
    def handle_error(self, request, client_address):
        # The watchdog's budget timeout closes the socket mid-response; that
        # broken pipe is the point of the test, not a failure.
        pass


Server(("127.0.0.1", port), Handler).serve_forever()
PY
    python3 "$work/stub.py" fast 18089 &
    WATCHDOG_STUB_PIDS="$WATCHDOG_STUB_PIDS $!"
    python3 "$work/stub.py" slow 18090 &
    WATCHDOG_STUB_PIDS="$WATCHDOG_STUB_PIDS $!"

    n=0
    until (exec 3<>/dev/tcp/127.0.0.1/18089) 2>/dev/null; do
        n=$((n + 1))
        [ "$n" -lt 20 ] || false
        sleep 0.5
    done
    n=0
    until (exec 3<>/dev/tcp/127.0.0.1/18090) 2>/dev/null; do
        n=$((n + 1))
        [ "$n" -lt 20 ] || false
        sleep 0.5
    done

    run llama-watchdog --probe 18089
    [ "$status" -eq 0 ]

    run env WATCHDOG_BUDGET=2 llama-watchdog --probe 18090
    [ "$status" -eq 1 ]

    run llama-watchdog --probe 18099
    [ "$status" -eq 1 ]
}
