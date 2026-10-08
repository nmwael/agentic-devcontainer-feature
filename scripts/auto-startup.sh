#!/usr/bin/env bash
# postStartCommand: brought up on every container start.
# Launches the LLM stack — one llama-server per model in stack.json (defaults
# :8089), bifrost proxy (:8082), opencode serve (:4096) — plus Tailscale if the
# tooling is present. Idempotent: every step guards on "already running".
set -euo pipefail

# WSL2 GPU bridge: the CUDA loader symlinks live under /usr/lib/wsl/drivers,
# a per-container 9p mount that is NOT visible while `docker build` runs.
# Re-apply them on every start so llama-server finds the real libcuda.
# postStartCommand runs as the devcontainer user → sudo (NOPASSWD) here.
if [ -d /usr/lib/wsl/drivers ] && [ -d /usr/lib/wsl/lib ]; then
    echo "[auto-startup] re-linking WSL2 GPU bridge loader libs..."
    for lib in libcuda.so.1 libcuda_loader.so libnvidia-ml.so.1 libnvidia-ptxjitcompiler.so.1 libnvdxgdmal.so.1; do
        f=$(find /usr/lib/wsl/drivers -name "$lib" 2>/dev/null | head -1)
        # 2>/dev/null: sudo's "unable to send audit message" is cosmetic in
        # containers (no CAP_AUDIT_WRITE); the symlink is still created.
        [ -n "$f" ] && sudo ln -sfn "$f" "/usr/lib/wsl/lib/$lib" 2>/dev/null
    done
fi

# --- Tailscale (official feature: tailscaled + CLI), userspace networking ---
# The feature bakes the binaries; the daemon must be started per container
# boot (build-time runs don't persist). Root daemon + world socket dir so the
# vscode user's CLI can talk to it. Joins the tailnet automatically when
# TS_AUTHKEY is set (containerEnv) — "join the VPN" with zero manual steps.
if command -v tailscaled >/dev/null 2>&1 && ! pgrep -x tailscaled >/dev/null 2>&1; then
    echo "[auto-startup] starting tailscaled (userspace networking)"
    sudo mkdir -p /var/run/tailscale /var/lib/tailscale 2>/dev/null
    sudo chown "$(id -u):$(id -g)" /var/run/tailscale 2>/dev/null
    # shellcheck disable=SC2024 # redirect as vscode to /tmp is intended (sticky world-writable)
    sudo nohup tailscaled -tun userspace-networking \
        -state /var/lib/tailscale/tailscaled.state \
        -socket /var/run/tailscale/tailscaled.sock \
        >/tmp/tailscaled.log 2>&1 &
    sleep 2
fi
if command -v tailscale >/dev/null 2>&1; then
    if sudo timeout 5 tailscale status >/dev/null 2>&1; then
        echo "[auto-startup] tailscale already up"
    elif [ -n "${TS_AUTHKEY:-}" ]; then
        # Stable tailnet node name (override via TS_HOSTNAME env).
        # Container hostnames are random IDs by default; a fixed name makes
        # the box findable as llm-lab (tailscale ip -4 / tailscale status).
        TS_HOSTNAME="${TS_HOSTNAME:-llm-lab}"
        sudo tailscale up --authkey="$TS_AUTHKEY" --hostname="$TS_HOSTNAME" \
            --accept-routes --accept-dns --operator="$(id -un)" 2>/dev/null ||
            echo "[auto-startup] WARNING: tailscale up (authkey) failed"
    else
        echo "[auto-startup] TS_AUTHKEY unset — skipping tailscale up (run 'tailscale up' for interactive login)"
    fi
fi

# --- llama-server: one per model in stack.json (or single fallback) ---
MODELS_DIR="${MODELS_DIR:-$PWD/models}"
STACK_JSON="${STACK_JSON:-/usr/local/share/llm-lab/stack.json}"

# Cloud mode (stack.json.cloud=true) means no local backends at all: skip
# llama-server AND bifrost. Everything still runs (opencode serve, tailscale)
# and agents route to the hosted opencode provider.
CLOUD_STACK=false
if [ -f "$STACK_JSON" ] && command -v jq >/dev/null 2>&1; then
    CLOUD_STACK="$(jq -r '.cloud // false' "$STACK_JSON")"
fi

start_llama_server() {
    local model_file="$1" port="$2" ctx="$3" label="$4" alias="$5" parallel="$6"
    if [ -z "$model_file" ] || ! command -v llama-server >/dev/null 2>&1; then
        echo "[auto-startup] WARNING: no model file or llama-server missing for $label — skipping"
        return
    fi
    if curl -sf -o /dev/null --max-time 2 "http://127.0.0.1:$port/health"; then
        echo "[auto-startup] llama-server already up on :$port ($label)"
        return
    fi
    # --alias/--parallel keep the model id emitted by generate-opencode.jq (the
    # {name}[-s{slot}] family) in sync with the running server's advertised
    # model + slot count — see AGENTS.md (model id <-> --alias sync invariant).
    echo "[auto-startup] starting llama-server on :$port with $model_file ($label, alias=$alias, slots=$parallel)"
    nohup llama-server -m "$model_file" --host 0.0.0.0 --port "$port" \
        --ctx-size "$ctx" --alias "$alias" --parallel "$parallel" \
        >/tmp/llama-server-"$label".log 2>&1 &
    local i=0
    while [ $i -lt 15 ]; do
        curl -sf -o /dev/null --max-time 2 "http://127.0.0.1:$port/health" &&
            {
                echo "[auto-startup] llama-server ready on :$port ($label)"
                return
            }
        i=$((i + 1))
        sleep 2
    done
    echo "[auto-startup] WARNING: llama-server on :$port timed out after 30s ($label — see /tmp/llama-server-$label.log)"
}

if [ -n "${SKIP_LLAMA_START:-}" ]; then
    echo "[auto-startup] SKIP_LLAMA_START set — skipping llama-server"
elif [ "$CLOUD_STACK" = "true" ]; then
    echo "[auto-startup] cloud mode (stack.json.cloud=true) — skipping llama-server"
elif [ -f "$STACK_JSON" ] && command -v jq >/dev/null 2>&1; then
    model_count=$(jq '.models | length' "$STACK_JSON")
    echo "[auto-startup] stack.json present — starting $model_count llama-server(s)"
    i=0
    while [ $i -lt "$model_count" ]; do
        mname=$(jq -r ".models[$i].name" "$STACK_JSON")
        mhf=$(jq -r ".models[$i].hf" "$STACK_JSON")
        mquant=$(jq -r ".models[$i].quant" "$STACK_JSON")
        mport=$(jq -r ".models[$i].port" "$STACK_JSON")
        mctx=$(jq -r ".models[$i].context" "$STACK_JSON")
        mparallel=$(jq -r ".models[$i].parallel // 5" "$STACK_JSON")
        # Match .gguf by HF slug or model name substring
        mfile=""
        # fetch-models.sh names files <hf with "/" -> "_">_<quant>.gguf; mirror that
        # normalization so slash-containing HF slugs match on disk.
        mslug=$(printf '%s' "$mhf" | tr '/' '_')
        if ls "$MODELS_DIR"/*"$mslug"*"$mquant"*.gguf >/dev/null 2>&1; then
            mfile=$(ls "$MODELS_DIR"/*"$mslug"*"$mquant"*.gguf | head -1)
        elif ls "$MODELS_DIR"/*"$mname"*.gguf >/dev/null 2>&1; then
            mfile=$(ls "$MODELS_DIR"/*"$mname"*.gguf | head -1)
        fi
        start_llama_server "$mfile" "$mport" "$mctx" "$mname" "$mname" "$mparallel"
        i=$((i + 1))
    done
else
    # Legacy single-server fallback: MODELS_DIR/*.gguf → port 8089. Alias stays
    # in sync with the shipped fragment's model id family (gemma4-26b-a4b).
    SLOTS="${SLOTS:-5}"
    MODEL_FILE=""
    if ls "$MODELS_DIR"/*.gguf >/dev/null 2>&1; then
        MODEL_FILE="$(ls "$MODELS_DIR"/*.gguf | head -1)"
    fi
    start_llama_server "$MODEL_FILE" 8089 65536 "default" "${LEGACY_ALIAS:-gemma4-26b-a4b}" "$SLOTS"
fi

# --- bifrost proxy (launcher installed by the bifrost-gateway feature) ---
# Backgrounded + bounded poll: the first start downloads the ~120 MB Go binary,
# which must never block postStartCommand forever.
BIFROST_PORT="${BIFROST_PORT:-8082}"
if [ -f "$STACK_JSON" ] && command -v jq >/dev/null 2>&1; then
    BIFROST_PORT=$(jq -r '.bifrost_port // 8082' "$STACK_JSON")
fi
if [ "$CLOUD_STACK" = "true" ]; then
    echo "[auto-startup] cloud mode — skipping bifrost (no local upstreams)"
elif command -v start-bifrost >/dev/null 2>&1; then
    if curl -sf -o /dev/null --max-time 2 "http://127.0.0.1:$BIFROST_PORT/"; then
        echo "[auto-startup] bifrost already up on :$BIFROST_PORT"
    else
        echo "[auto-startup] starting bifrost on :$BIFROST_PORT (background)"
        if command -v pgrep >/dev/null 2>&1 && pgrep -f 'bifros[t].*bin.js' >/dev/null 2>&1; then
            echo "[auto-startup] a bifrost launcher is already running — waiting instead of double-spawning"
        else
            nohup start-bifrost >/tmp/bifrost.log 2>&1 &
        fi
        i=0
        while [ $i -lt 30 ]; do
            curl -sf -o /dev/null --max-time 2 "http://127.0.0.1:$BIFROST_PORT/" &&
                {
                    echo "[auto-startup] bifrost ready on :$BIFROST_PORT"
                    break
                }
            i=$((i + 1))
            sleep 2
        done
        if [ $i -ge 30 ]; then
            echo "[auto-startup] WARNING: bifrost not ready after 60s — continuing in background (see /tmp/bifrost.log)"
        fi
    fi
else
    echo "[auto-startup] bifrost launcher not installed — skipping"
fi

# --- opencode serve (opencode mobile / Tailscale remote control) ---
OPENCODE_PORT="${OPENCODE_PORT:-4096}"
if [ -f "$STACK_JSON" ] && command -v jq >/dev/null 2>&1; then
    OPENCODE_PORT=$(jq -r '.opencode_port // 4096' "$STACK_JSON")
fi
if command -v opencode >/dev/null 2>&1; then
    if curl -sf -o /dev/null --max-time 2 "http://127.0.0.1:$OPENCODE_PORT/"; then
        echo "[auto-startup] opencode serve already up on :$OPENCODE_PORT"
    else
        echo "[auto-startup] starting opencode serve on :$OPENCODE_PORT"
        nohup opencode serve --port "$OPENCODE_PORT" --hostname 0.0.0.0 >/tmp/opencode-serve.log 2>&1 &
        sleep 2
    fi
else
    echo "[auto-startup] opencode CLI not installed — skipping"
fi

# --- llama watchdog (/health stays green while generation collapses) ---------
# A server decoding at ~0.1 tok/s still answers /health in milliseconds, so
# every agent turn would silently burn opencode's provider timeout. The probe
# (installed by the llama-server feature) stops that: two slow/failed probes
# while idle recycle the server through this same idempotent starter.
SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
SCRIPT_PATH="$SCRIPT_DIR/auto-startup.sh"
WATCHDOG_BIN=""
if command -v llama-watchdog >/dev/null 2>&1; then
    WATCHDOG_BIN="$(command -v llama-watchdog)"
elif [ -f "$SCRIPT_DIR/llama-watchdog.sh" ]; then
    WATCHDOG_BIN="$SCRIPT_DIR/llama-watchdog.sh"
fi
if [ -z "$WATCHDOG_BIN" ]; then
    echo "[auto-startup] llama-watchdog not installed — skipping (feature llama-server >= 1.0.4)"
elif command -v pgrep >/dev/null 2>&1 && pgrep -f 'llama-watchdog(\.sh)?$' >/dev/null 2>&1; then
    echo "[auto-startup] llama watchdog already running"
else
    echo "[auto-startup] starting llama watchdog (interval=${WATCHDOG_INTERVAL:-120}s budget=${WATCHDOG_BUDGET:-30}s)"
    WATCHDOG_RESTART="bash $SCRIPT_PATH" nohup sh "$WATCHDOG_BIN" >>/tmp/llama-watchdog.log 2>&1 &
fi

BIFROST_WATCHDOG_BIN=$(command -v bifrost-watchdog 2>/dev/null || true)
if [ -z "$BIFROST_WATCHDOG_BIN" ] && [ -f "$SCRIPT_DIR/bifrost-watchdog.sh" ]; then
    BIFROST_WATCHDOG_BIN="$SCRIPT_DIR/bifrost-watchdog.sh"
fi
if [ -z "$BIFROST_WATCHDOG_BIN" ]; then
    echo "[auto-startup] bifrost-watchdog not installed — skipping (feature bifrost-gateway >= 1.1.4)"
elif command -v pgrep >/dev/null 2>&1 && pgrep -f 'bifrost-watchdog(\.sh)?$' >/dev/null 2>&1; then
    echo "[auto-startup] bifrost-watchdog already running"
else
    echo "[auto-startup] starting bifrost-watchdog (background)"
    BIFROST_WATCHDOG_RESTART="bash $SCRIPT_PATH" BIFROST_PORT="$BIFROST_PORT" nohup sh "$BIFROST_WATCHDOG_BIN" >>/tmp/bifrost-watchdog.log 2>&1 &
fi

echo "[auto-startup] done."
