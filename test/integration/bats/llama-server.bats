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

@test "watchdog installs even when the binary pre-exists (early-exit path)" {
    # Simulate a base image whose llama-server rode in from a cached layer but
    # that never got the watchdog (the 1.0.5 bug): remove the watchdog, then
    # re-run install.sh — the idempotence early-exit must not skip the install.
    rm -f /opt/llama-server/llama-watchdog.sh /usr/local/bin/llama-watchdog
    run /bin/sh /tmp/feature/install.sh
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "no re-install performed"
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

@test "llama-watchdog restart ledger: caps attempts, healthy probe re-arms" {
    work=$(mktemp -d)
    marker="$work/restarted"
    state="$work/state"

    # Three restart attempts on a dead port, each relaunch "succeeds".
    i=0
    while [ "$i" -lt 3 ]; do
        run env WATCHDOG_STATE="$state" WATCHDOG_CONFIRM_DELAY=0 WATCHDOG_MAX_RESTARTS=3 \
            WATCHDOG_RESTART="echo restarted >> $marker" llama-watchdog --once 18099 dead
        [ "$status" -eq 0 ]
        i=$((i + 1))
    done
    [ "$(wc -l <"$marker")" -eq 3 ]
    [ "$(awk '$1 == "18099" { print $2 }' "$state")" -eq 3 ]

    # Fourth attempt gives up: the restart command must not run again.
    run env WATCHDOG_STATE="$state" WATCHDOG_CONFIRM_DELAY=0 WATCHDOG_MAX_RESTARTS=3 \
        WATCHDOG_RESTART="echo restarted >> $marker" llama-watchdog --once 18099 dead
    [ "$status" -eq 0 ]
    printf '%s' "$output" | grep -q "giving up"
    [ "$(wc -l <"$marker")" -eq 3 ]

    # A healthy probe re-arms only the probed port's budget.
    printf '18089 3\n18099 3\n' >"$state"
    cat >"$work/stub.py" <<'PY'
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

port = int(sys.argv[1])


class Handler(BaseHTTPRequestHandler):
    def _ok(self, body):
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        # /health must answer 200 or the cycle never reaches the probe.
        self._ok(b'{"status":"ok"}')

    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length") or 0))
        self._ok(json.dumps({"choices": [{"message": {"content": "OK"}}]}).encode())

    def log_message(self, *args):
        pass


HTTPServer(("127.0.0.1", port), Handler).serve_forever()
PY
    python3 "$work/stub.py" 18089 &
    WATCHDOG_STUB_PIDS="$WATCHDOG_STUB_PIDS $!"
    n=0
    until (exec 3<>/dev/tcp/127.0.0.1/18089) 2>/dev/null; do
        n=$((n + 1))
        [ "$n" -lt 20 ] || false
        sleep 0.5
    done

    run env WATCHDOG_STATE="$state" llama-watchdog --once 18089 stub
    [ "$status" -eq 0 ]
    printf '%s' "$output" | grep -q "healthy (probe inside"
    [ -z "$(awk '$1 == "18089" { print $2 }' "$state")" ]
    [ "$(awk '$1 == "18099" { print $2 }' "$state")" -eq 3 ]
}

@test "llama-watchdog with no args enters daemon mode (auto-startup spawns it bare)" {
    # Daemon path, before any probe: the bare invocation must not stop at
    # --help (exit 0 + usage), so it has to reach the manifest guards and
    # exit 1 — or, on a box with jq, keep looping until timeout (124).
    run env STACK_JSON=/nonexistent-stack.json timeout 10 llama-watchdog
    [ "$status" -eq 1 ]
    printf '%s' "$output" | grep -Eq "jq not found|no manifest at"

    # Cloud/skip boxes: exit cleanly instead of restart-looping on nothing.
    run env SKIP_LLAMA_START=1 timeout 10 llama-watchdog
    [ "$status" -eq 0 ]
    printf '%s' "$output" | grep -q "SKIP_LLAMA_START is set"
}
