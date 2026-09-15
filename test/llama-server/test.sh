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

echo "PASS: llama-server"