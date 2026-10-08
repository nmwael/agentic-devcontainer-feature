#!/usr/bin/env bats
# Container-side assertions for the bifrost-gateway feature. The nvidia/cuda
# base images lack node/npm, so the feature must self-provision them, install
# @maximhq/bifrost, and write a launcher that points at the package's REAL
# entrypoint (bin.js - the old dist/index.js path never existed).

# Stub PIDs for the watchdog probe tests; teardown is the supported hook — an
# EXIT trap here would clobber bats' own trap and abort the run mid-file.
# (bats 1.10 has no `describe`, so the watchdog group is a flat banner like
# llama-server.bats.)
WATCHDOG_STUB_PIDS=""

teardown() {
    for stub_pid in $WATCHDOG_STUB_PIDS; do
        kill "$stub_pid" 2>/dev/null || true
    done
    WATCHDOG_STUB_PIDS=""
}

@test "node and npm are provisioned by the feature" {
    command -v node
    command -v npm
}

@test "@maximhq/bifrost installed into the feature dir" {
    [ -f /usr/local/share/llm-lab/bifrost/node_modules/@maximhq/bifrost/bin.js ]
}

@test "start-bifrost launcher installed and executable" {
    [ -x /usr/local/bin/start-bifrost ]
}

@test "launcher references the packaged entrypoint (bin.js), not dist/" {
    grep -q "node_modules/@maximhq/bifrost/bin.js" /usr/local/bin/start-bifrost
    if grep -q "dist/index.js" /usr/local/bin/start-bifrost; then
        echo "launcher still points at the nonexistent dist/index.js"
        return 1
    fi
}

@test "scaffolded config dir exists (workspace-agnostic)" {
    [ -d /usr/local/share/llm-lab/bifrost/config ]
}

@test "launcher is sh-clean" {
    dash -n /usr/local/bin/start-bifrost
}

@test "launcher passes the port as -port flag, not a positional argument" {
    # bifrost v2.2.x parses -port/-host as flags. A positional port is silently
    # ignored and the server falls back to 127.0.0.1:8080, making BIFROST_PORT
    # unreachable. Guard against regressing to the positional form.
    run grep -q '\-port "\$PORT_ENV"' /usr/local/bin/start-bifrost
    [ "$status" -eq 0 ]
    run grep -q '\-host "\$HOST_ENV"' /usr/local/bin/start-bifrost
    [ "$status" -eq 0 ]
    if grep -q 'bin.js" "\$PORT_ENV"' /usr/local/bin/start-bifrost; then
        echo "launcher still passes the port positionally; bifrost ignores it"
        return 1
    fi
}

@test "launcher syncs generated config to bifrost's expected app-dir path" {
    # write-bifrost-config.sh emits <BIFROST_DIR>/config/bifrost.json but bifrost
    # reads <app-dir>/config.json. Without the sync it logs "config file not
    # found ... initializing with default values" and serves zero providers.
    run grep -q 'APP_DIR' /usr/local/bin/start-bifrost
    [ "$status" -eq 0 ]
    run grep -q 'config.json' /usr/local/bin/start-bifrost
    [ "$status" -eq 0 ]
    run grep -q 'GENERATED_CONFIG' /usr/local/bin/start-bifrost
    [ "$status" -eq 0 ]
}

@test "launcher honours BIFROST_PORT end-to-end (binds the requested port)" {
    requested=18383
    BIFROST_PORT=$requested start-bifrost >/tmp/bifrost-port-test.log 2>&1 &
    launcher_pid=$!
    n=0
    while [ "$n" -lt 20 ]; do
        if PORT=$requested python3 -c 'import os,socket
s=socket.socket(); s.settimeout(2)
try:
    s.connect(("127.0.0.1", int(os.environ["PORT"]))); s.close(); raise SystemExit(0)
except SystemExit: raise
except Exception: raise SystemExit(1)'; then
            break
        fi
        n=$((n + 1))
        sleep 1
    done
    bound=no
    [ "$n" -lt 20 ] && bound=yes
    # Tear down before asserting. `wait` on a SIGTERM'd child exits 143, which
    # bats would otherwise report as a test failure.
    pkill -f "bifros[t]-http" 2>/dev/null
    kill "$launcher_pid" 2>/dev/null
    wait "$launcher_pid" 2>/dev/null || true
    [ "$bound" = yes ]
}

@test "write-bifrost-config.sh shipped, executable, sh-clean" {
    [ -f /usr/local/share/llm-lab/bifrost/write-bifrost-config.sh ]
    [ -x /usr/local/share/llm-lab/bifrost/write-bifrost-config.sh ]
    run dash -n /usr/local/share/llm-lab/bifrost/write-bifrost-config.sh
    [ "$status" -eq 0 ]
}

@test "scaffolded bifrost.json uses the v2 schema (multi-upstream shape)" {
    cfg=/usr/local/share/llm-lab/bifrost/config/bifrost.json
    [ -f "$cfg" ]
    python3 - <<'PY'
import json
with open('/usr/local/share/llm-lab/bifrost/config/bifrost.json') as f:
    c = json.load(f)
assert 'providers' in c
assert c.get('config_store', {}).get('enabled') is False, "config_store.enabled must be false"
p = next(iter(c['providers'].values()))
assert 'network_config' in p and 'base_url' in p['network_config']
assert 'custom_provider_config' in p and p['custom_provider_config'].get('base_provider_type') == 'openai'
assert isinstance(p['keys'], list)
PY
}

@test "write-bifrost-config.sh materializes one provider per upstream from a simulated stack.json" {
    stack=$(mktemp)
    out=$(mktemp --suffix=.json)
    python3 - <<'PY' >"$stack"
import json
print(json.dumps({
    "schema": 1, "models_dir": "/models", "bifrost_port": 8082,
    "opencode_port": 4096, "subagent_depth": 2,
    "models": [
        {"name": "gemma4-26b-a4b", "provider": "local-gemma4-26b",
         "hf": "gemma-4-26B-A4B-it-UD-IQ2_M", "quant": "IQ2_M",
         "port": 8089, "context": 65536, "parallel": 5},
        {"name": "gemma4-31b-a4b", "provider": "local-gemma4-31b",
         "hf": "gemma-4-31B-A4B-it-UD-IQ3_M", "quant": "IQ3_M",
         "port": 8090, "context": 32768, "parallel": 3}
    ],
    "roles": {}
}))
PY
    run /usr/local/share/llm-lab/bifrost/write-bifrost-config.sh "$stack" "$out"
    [ "$status" -eq 0 ]
    python3 - <<'PY' "$out"
import json, sys
with open(sys.argv[1]) as f:
    c = json.load(f)
providers = c['providers']
assert set(providers) == {'gemma4-26b-a4b', 'gemma4-31b-a4b'}
assert providers['gemma4-26b-a4b']['network_config']['base_url'].endswith(':8089')
assert providers['gemma4-31b-a4b']['network_config']['base_url'].endswith(':8090')
# model-id routing: keys[].models allowlists the provider's exact ids
# (name plus per-slot ids; bifrost matches allowlist entries exactly)
assert 'gemma4-26b-a4b' in providers['gemma4-26b-a4b']['keys'][0]['models']
assert 'gemma4-26b-a4b-s3' in providers['gemma4-26b-a4b']['keys'][0]['models']
assert not any(m.endswith('*') for m in providers['gemma4-26b-a4b']['keys'][0]['models'])
assert 'gemma4-31b-a4b' in providers['gemma4-31b-a4b']['keys'][0]['models']
assert 'gemma4-31b-a4b-s2' in providers['gemma4-31b-a4b']['keys'][0]['models']
assert not any(m.endswith('*') for m in providers['gemma4-31b-a4b']['keys'][0]['models'])
PY
    rm -f "$stack" "$out"
}

@test "second install stays functional (idempotent)" {
    run /bin/sh /tmp/feature/install.sh
    [ "$status" -eq 0 ]
    [ -x /usr/local/bin/start-bifrost ]
}

# --- bifrost-watchdog (feature >= 1.1.4) --------------------------------------
# Parity with llama-server.bats:52-229 — install shape, dash cleanliness,
# probe budget semantics, restart ledger, daemon guards, best-effort OOM.

@test "bifrost-watchdog installed and symlinked onto PATH" {
    [ -x /usr/local/share/llm-lab/bifrost/bifrost-watchdog.sh ]
    [ -L /usr/local/bin/bifrost-watchdog ]
    [ "$(readlink /usr/local/bin/bifrost-watchdog)" = "/usr/local/share/llm-lab/bifrost/bifrost-watchdog.sh" ]
    command -v bifrost-watchdog
}

@test "bifrost-watchdog passes dash -n" {
    run dash -n "$(command -v bifrost-watchdog)"
    [ "$status" -eq 0 ]
}

@test "bifrost-watchdog --probe: fast stub 0, over-budget stub 1, dead port 1" {
    work=$(mktemp -d)
    cat >"$work/stub.py" <<'PY'
import sys
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

mode, port = sys.argv[1], int(sys.argv[2])


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        # The watchdog probes plain GET / — the readiness signal auto-startup
        # polls. No completion semantics, no /slots equivalent.
        if mode == "slow":
            time.sleep(30)
        body = b'{"ok":true}'
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
    python3 "$work/stub.py" fast 18481 &
    WATCHDOG_STUB_PIDS="$WATCHDOG_STUB_PIDS $!"
    python3 "$work/stub.py" slow 18482 &
    WATCHDOG_STUB_PIDS="$WATCHDOG_STUB_PIDS $!"

    n=0
    until (exec 3<>/dev/tcp/127.0.0.1/18481) 2>/dev/null; do
        n=$((n + 1))
        [ "$n" -lt 20 ] || false
        sleep 0.5
    done
    n=0
    until (exec 3<>/dev/tcp/127.0.0.1/18482) 2>/dev/null; do
        n=$((n + 1))
        [ "$n" -lt 20 ] || false
        sleep 0.5
    done

    run bifrost-watchdog --probe 18481
    [ "$status" -eq 0 ]

    run env BIFROST_WATCHDOG_BUDGET=2 bifrost-watchdog --probe 18482
    [ "$status" -eq 1 ]

    run bifrost-watchdog --probe 18489
    [ "$status" -eq 1 ]
}

@test "bifrost-watchdog restart ledger: caps attempts, healthy probe re-arms" {
    work=$(mktemp -d)
    marker="$work/restarted"
    state="$work/state"

    # Three restart attempts on a dead port, each relaunch "succeeds".
    i=0
    while [ "$i" -lt 3 ]; do
        run env BIFROST_WATCHDOG_STATE="$state" BIFROST_WATCHDOG_CONFIRM_DELAY=0 \
            BIFROST_WATCHDOG_MAX_RESTARTS=3 \
            BIFROST_WATCHDOG_RESTART="echo restarted >> $marker" \
            bifrost-watchdog --once 18489
        [ "$status" -eq 0 ]
        i=$((i + 1))
    done
    [ "$(wc -l <"$marker")" -eq 3 ]
    [ "$(awk '$1 == "18489" { print $2 }' "$state")" -eq 3 ]

    # Fourth attempt gives up: the restart command must not run again.
    run env BIFROST_WATCHDOG_STATE="$state" BIFROST_WATCHDOG_CONFIRM_DELAY=0 \
        BIFROST_WATCHDOG_MAX_RESTARTS=3 \
        BIFROST_WATCHDOG_RESTART="echo restarted >> $marker" \
        bifrost-watchdog --once 18489
    [ "$status" -eq 0 ]
    printf '%s' "$output" | grep -q "giving up"
    [ "$(wc -l <"$marker")" -eq 3 ]

    # A healthy probe re-arms only the probed port's budget.
    printf '18483 3\n18489 3\n' >"$state"
    cat >"$work/stub.py" <<'PY'
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

port = int(sys.argv[1])


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        body = b'{"ok":true}'
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


HTTPServer(("127.0.0.1", port), Handler).serve_forever()
PY
    python3 "$work/stub.py" 18483 &
    WATCHDOG_STUB_PIDS="$WATCHDOG_STUB_PIDS $!"
    n=0
    until (exec 3<>/dev/tcp/127.0.0.1/18483) 2>/dev/null; do
        n=$((n + 1))
        [ "$n" -lt 20 ] || false
        sleep 0.5
    done

    run env BIFROST_WATCHDOG_STATE="$state" bifrost-watchdog --once 18483
    [ "$status" -eq 0 ]
    printf '%s' "$output" | grep -q "healthy (probe inside"
    [ -z "$(awk '$1 == "18483" { print $2 }' "$state")" ]
    [ "$(awk '$1 == "18489" { print $2 }' "$state")" -eq 3 ]
}

@test "bifrost-watchdog with no args enters daemon mode (auto-startup spawns it bare)" {
    # Missing manifest is NOT fatal for bifrost (unlike llama-watchdog's exit
    # 1): the daemon resolves a default port and keeps watching — so it must
    # still be running when timeout kills it (124). No BIFROST_WATCHDOG_RESTART
    # and no sibling auto-startup.sh in this image, so the restart path must
    # take the report-only branch — never kill anything it cannot relaunch.
    run env STACK_JSON=/nonexistent-stack.json BIFROST_PORT=18499 \
        BIFROST_WATCHDOG_CONFIRM_DELAY=1 timeout 10 bifrost-watchdog
    [ "$status" -eq 124 ]
    printf '%s' "$output" | grep -q "watching port 18499"
    printf '%s' "$output" | grep -q "reporting only, not killing"

    # Cloud/skip boxes: exit cleanly instead of restart-looping on nothing.
    cloud=$(mktemp)
    printf '{"cloud": true}\n' >"$cloud"
    run env STACK_JSON="$cloud" timeout 10 bifrost-watchdog
    [ "$status" -eq 0 ]
    printf '%s' "$output" | grep -q "cloud mode"
    rm -f "$cloud"
}

@test "launcher carries the best-effort oom_score_adj write (score never worse than 0)" {
    grep -q 'oom_score_adj' /usr/local/bin/start-bifrost

    # Live read: start the launcher, wait until it is serving (proof it got
    # past the pre-exec write), then check the score it carries. CI Docker
    # drops CAP_SYS_RESOURCE, so the write lands on 0 there and -100 on a
    # privileged box — assert the direction only, never -100 (1.1.4 risk 3).
    BIFROST_PORT=18384 start-bifrost >/tmp/bifrost-oom-test.log 2>&1 &
    launcher_pid=$!
    n=0
    while [ "$n" -lt 20 ]; do
        if PORT=18384 python3 -c 'import os,socket
s=socket.socket(); s.settimeout(2)
try:
    s.connect(("127.0.0.1", int(os.environ["PORT"]))); s.close(); raise SystemExit(0)
except SystemExit: raise
except Exception: raise SystemExit(1)'; then
            break
        fi
        kill -0 "$launcher_pid" 2>/dev/null || break
        n=$((n + 1))
        sleep 1
    done
    score=""
    if [ -r "/proc/$launcher_pid/oom_score_adj" ]; then
        score=$(cat "/proc/$launcher_pid/oom_score_adj")
    fi
    # Tear down before asserting. `wait` on a SIGTERM'd child exits 143, which
    # bats would otherwise report as a test failure.
    pkill -f "bifros[t]-http" 2>/dev/null
    kill "$launcher_pid" 2>/dev/null
    wait "$launcher_pid" 2>/dev/null || true
    if [ -z "$score" ]; then
        echo "launcher exited before /proc/$launcher_pid/oom_score_adj could be read"
        return 1
    fi
    [ "$score" -le 0 ]
}