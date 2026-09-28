#!/bin/bash
# devcontainer features test — llama-server (auto-generated, default options).
# The container this runs in was built with the llama-server feature installed;
# fail hard if the runtime isn't usable.
set -e

fail() { echo "FAIL: $*"; exit 1; }
ok() { echo "ok: $*"; }

[ -x /opt/llama-server/llama-server ] || fail "llama-server binary missing at /opt/llama-server"
ok "llama-server binary installed at /opt/llama-server"

[ -x /usr/local/bin/llama-server ] || fail "llama-server missing on PATH (/usr/local/bin/llama-server)"
ok "llama-server available on PATH"

/opt/llama-server/llama-server --version >/dev/null 2>&1 || fail "llama-server --version did not exit 0"
ok "llama-server --version runs"

[ -f /opt/llama-server/VERSION ] || fail "llama-server VERSION file missing"
ok "llama-server VERSION: $(cat /opt/llama-server/VERSION)"

# The upstream ubuntu-* release builds are OpenMP-linked, so libgomp.so.1 must
# resolve or nothing runs. Check it explicitly so the failure names the cause
# instead of surfacing as a bare "error while loading shared libraries".
ldconfig -p 2>/dev/null | grep -q 'libgomp\.so\.1' \
    || fail "libgomp.so.1 not resolvable — llama-server cannot start (apt-get install libgomp1)"
ok "libgomp.so.1 (OpenMP runtime) resolvable"

# Static: install.sh must provision the runtime dep, and must do so BEFORE the
# idempotence early-exit so a custom base image that already ships llama-server
# is fixed too.
INSTALL="${TEST_FEATURE_SRC:-/workspaces/agentic-devcontainer-feature/src}/llama-server/install.sh"
if [ -f "$INSTALL" ]; then
    grep -q 'libgomp1' "$INSTALL" || fail "install.sh does not provision libgomp1"
    gomp_line=$(grep -n 'libgomp1' "$INSTALL" | head -1 | cut -d: -f1)
    idem_line=$(grep -n 'already exists (custom image as base)' "$INSTALL" | head -1 | cut -d: -f1)
    if [ -n "$idem_line" ] && [ "$gomp_line" -gt "$idem_line" ]; then
        fail "libgomp1 is provisioned after the idempotence early-exit; custom base images stay broken"
    fi
    ok "install.sh provisions libgomp1 before the idempotence check"
fi

echo "PASS: llama-server"