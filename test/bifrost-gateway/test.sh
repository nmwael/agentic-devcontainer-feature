#!/bin/bash
# devcontainer features test — bifrost-gateway (auto-generated, default options).
# The feature is built in ISOLATION here (no models feature -> no stack.json),
# so write-bifrost-config.sh must fall back to the legacy single-upstream config
# on the default LLAMA_PORT (8089); bifrost appends the /v1 path itself.
set -e

fail() { echo "FAIL: $*"; exit 1; }
ok() { echo "ok: $*"; }

[ -x /usr/local/bin/start-bifrost ] || fail "start-bifrost launcher missing on PATH"
ok "start-bifrost launcher on PATH"

CFG=/usr/local/share/llm-lab/bifrost/config/bifrost.json
[ -f "$CFG" ] || fail "bifrost config missing at $CFG"
jq -e . "$CFG" >/dev/null 2>&1 || fail "bifrost config is not valid JSON"
ok "bifrost config present + valid JSON"

jq -e '.providers.llama.network_config.base_url | endswith(":8089")' "$CFG" >/dev/null 2>&1 \
    || fail "expected legacy single-upstream on :8089 (no stack.json present)"
ok "legacy fallback upstream resolves to http://127.0.0.1:8089"

[ -x /usr/local/share/llm-lab/bifrost/write-bifrost-config.sh ] || fail "write-bifrost-config.sh not installed"
ok "write-bifrost-config.sh installed"

command -v node >/dev/null 2>&1 || fail "node runtime missing (bifrost is a node app)"
ok "node runtime present: $(node --version 2>/dev/null)"

[ -s /usr/local/share/llm-lab/bifrost/version ] || fail "bifrost version stamp missing"
ok "bifrost version: $(cat /usr/local/share/llm-lab/bifrost/version)"

# --- watchdog shipped by the feature (>= 1.1.4) -------------------------------
# Parity with the llama watchdog checks (llama-server.bats:52-76): real file in
# the feature share dir, symlink on PATH, and POSIX-sh clean.
[ -x /usr/local/share/llm-lab/bifrost/bifrost-watchdog.sh ] \
    || fail "bifrost-watchdog.sh missing from the feature share dir"
[ -x /usr/local/bin/bifrost-watchdog ] || fail "bifrost-watchdog missing on PATH"
ok "bifrost-watchdog on PATH"
dash -n /usr/local/bin/bifrost-watchdog || fail "bifrost-watchdog is not dash-clean"
ok "bifrost-watchdog passes dash -n"

# Launcher contract: a best-effort oom_score_adj write must exist before
# `exec node` so the wrapper (and the bifrost-http-0 child via fork
# inheritance) is deprioritised under memory pressure. Positive grep only —
# whether the write succeeds is privilege-dependent (CI Docker drops
# CAP_SYS_RESOURCE), so the guarded write, not the result, is the contract.
grep -q 'oom_score_adj' /usr/local/bin/start-bifrost \
    || fail "start-bifrost does not set oom_score_adj before exec"
ok "start-bifrost carries the best-effort oom_score_adj write"

# Static: install.sh must install the watchdog BEFORE BOTH `exit 0` early-exits
# (nodejs/npm/jq provisioning failure, npm install failure) — any exit 0 before
# the install loses the watchdog on exactly the base images that need it
# (the 1.0.5/1.0.6 lesson). Repo-side only; the integration tier covers the
# installed artifacts.
INSTALL="${TEST_FEATURE_SRC:-/workspaces/agentic-devcontainer-feature/src}/bifrost-gateway/install.sh"
if [ -f "$INSTALL" ]; then
    grep -q 'bifrost-watchdog installed' "$INSTALL" \
        || fail "install.sh never installs bifrost-watchdog"
    wd_line=$(grep -n 'bifrost-watchdog installed' "$INSTALL" | head -1 | cut -d: -f1)
    grep -q 'nodejs/npm/jq install failed' "$INSTALL" \
        || fail "install.sh nodejs/npm/jq early-exit marker missing"
    exit1_line=$(grep -n 'nodejs/npm/jq install failed' "$INSTALL" | head -1 | cut -d: -f1)
    grep -q 'npm install failed for @maximhq/bifrost' "$INSTALL" \
        || fail "install.sh npm-install early-exit marker missing"
    exit2_line=$(grep -n 'npm install failed for @maximhq/bifrost' "$INSTALL" | head -1 | cut -d: -f1)
    [ "$wd_line" -lt "$exit1_line" ] \
        || fail "watchdog installs after the nodejs/npm/jq early-exit (line $wd_line vs $exit1_line)"
    [ "$wd_line" -lt "$exit2_line" ] \
        || fail "watchdog installs after the npm-install early-exit (line $wd_line vs $exit2_line)"
    ok "install.sh installs the watchdog before both early-exit paths ($wd_line < $exit1_line/$exit2_line)"
fi

# --- launcher must actually START on the configured port ------------------------
# Regression guard: the launcher used to pass the port positionally, which
# bifrost v2.2.x silently ignores, so the server bound its own default 8080 and
# PORT (8082) was never reachable. The process was alive, which is exactly why
# this was hard to spot. Verify the listener, not just the process.
PORT="${BIFROST_PORT:-8082}"
nohup start-bifrost >/tmp/bifrost-test.log 2>&1 &
launcher_pid=$!
n=0
while [ "$n" -lt 25 ]; do
    # Probe with python3, not `curl`/`ss`: the slim test image ships neither, and
    # a missing probe binary would silently fail the check and mask a real
    # regression (this test passed while bifrost was bound to the wrong port).
    if PORT="$PORT" python3 -c 'import os,socket
s=socket.socket(); s.settimeout(2)
try:
    s.connect(("127.0.0.1", int(os.environ["PORT"]))); s.close(); raise SystemExit(0)
except SystemExit: raise
except Exception: raise SystemExit(1)'; then break; fi
    kill -0 "$launcher_pid" 2>/dev/null || fail "start-bifrost exited early (see /tmp/bifrost-test.log)"
    n=$((n + 1))
    sleep 1
done
pkill -f "bifros[t]-http" 2>/dev/null || true
kill "$launcher_pid" 2>/dev/null || true
wait "$launcher_pid" 2>/dev/null || true
[ "$n" -lt 25 ] || fail "bifrost never listened on :$PORT (wrong port arg form?)"
ok "start-bifrost binds :$PORT"

# --- generated config must reach bifrost's app-dir ----------------------------
# Regression guard: write-bifrost-config.sh emits config/bifrost.json, but
# bifrost reads <app-dir>/config.json. Without the launcher's sync it starts
# with zero providers and every request fails to resolve a provider.
APP_DIR="${BIFROST_APP_DIR:-${HOME:-/root}/.config/bifrost}"
nohup start-bifrost >/tmp/bifrost-test2.log 2>&1 &
launcher_pid=$!
n=0
while [ "$n" -lt 25 ]; do
    [ -f "$APP_DIR/config.json" ] && break
    n=$((n + 1))
    sleep 1
done
pkill -f "bifros[t]-http" 2>/dev/null || true
kill "$launcher_pid" 2>/dev/null || true
wait "$launcher_pid" 2>/dev/null || true
[ -f "$APP_DIR/config.json" ] || fail "launcher did not sync config into $APP_DIR"
jq -e '.providers | length > 0' "$APP_DIR/config.json" >/dev/null 2>&1 \
    || fail "synced config has no providers — bifrost would serve nothing"
ok "config synced to $APP_DIR/config.json with providers"

echo "PASS: bifrost-gateway"