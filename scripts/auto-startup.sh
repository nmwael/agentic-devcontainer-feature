#!/usr/bin/env bash
# postStartCommand: brought up on every container start.
# Launches the LLM stack — llama-server :8089, bifrost proxy :8082,
# opencode serve :4096 — plus Tailscale if the tooling is present.
# Idempotent: every step guards on "already running".
set -euo pipefail

# WSL2 GPU bridge: the CUDA loader symlinks live under /usr/lib/wsl/drivers,
# a per-container 9p mount that is NOT visible while `docker build` runs.
# Re-apply them on every start so llama-server finds the real libcuda.
# postStartCommand runs as the devcontainer user → sudo (NOPASSWD) here.
if [ -d /usr/lib/wsl/drivers ] && [ -d /usr/lib/wsl/lib ]; then
    echo "[auto-startup] re-linking WSL2 GPU bridge loader libs..."
    for lib in libcuda.so.1 libcuda_loader.so libnvidia-ml.so.1 libnvidia-ptxjitcompiler.so.1 libnvdxgdmal.so.1; do
        f=$(find /usr/lib/wsl/drivers -name "$lib" 2>/dev/null | head -1)
        [ -n "$f" ] && sudo ln -sfn "$f" "/usr/lib/wsl/lib/$lib"
    done
fi

# --- Tailscale (userspace networking), only if the tooling is present ---
if command -v tailscaled >/dev/null 2>&1 && ! pgrep -x tailscaled >/dev/null 2>&1; then
    sudo mkdir -p /var/run/tailscale && sudo chown "$(id -u):$(id -g)" /var/run/tailscale
    tailscaled -tun userspace-networking -state /tmp/tailscaled.state -socket /var/run/tailscale/tailscaled.sock &
    sleep 2
fi
if command -v tailscale >/dev/null 2>&1; then
    if timeout 5 tailscale status >/dev/null 2>&1; then
        echo "[auto-startup] tailscale already up"
    elif [ -n "${TS_AUTHKEY:-}" ]; then
        sudo tailscale up --authkey="$TS_AUTHKEY" --accept-routes --accept-dns --operator="$(id -un)" 2>/dev/null \
            || echo "[auto-startup] WARNING: tailscale up (authkey) failed"
    else
        echo "[auto-startup] TS_AUTHKEY unset — skipping tailscale up (run 'tailscale up' for interactive login)"
    fi
fi

# --- llama-server :8089 ---
MODELS_DIR="${MODELS_DIR:-$PWD/models}"
MODEL_FILE=""
if ls "$MODELS_DIR"/*.gguf >/dev/null 2>&1; then
    MODEL_FILE="$(ls "$MODELS_DIR"/*.gguf | head -1)"
fi

if [ -n "${SKIP_LLAMA_START:-}" ]; then
    echo "[auto-startup] SKIP_LLAMA_START set — skipping llama-server"
elif [ -n "$MODEL_FILE" ] && command -v llama-server >/dev/null 2>&1; then
    if curl -sf -o /dev/null --max-time 2 http://127.0.0.1:8089/health; then
        echo "[auto-startup] llama-server already up on :8089"
    else
        echo "[auto-startup] starting llama-server with $MODEL_FILE"
        nohup llama-server -m "$MODEL_FILE" --host 0.0.0.0 --port 8089 >/tmp/llama-server.log 2>&1 &
        i=0
        while [ $i -lt 15 ]; do
            curl -sf -o /dev/null --max-time 2 http://127.0.0.1:8089/health \
                && { echo "[auto-startup] llama-server ready on :8089"; break; }
            i=$((i + 1)); sleep 2
        done
        if [ $i -eq 15 ]; then
            echo "[auto-startup] WARNING: llama-server health check timed out (see /tmp/llama-server.log)"
        fi
    fi
else
    echo "[auto-startup] WARNING: no .gguf model in $MODELS_DIR or llama-server missing — skipping model server"
fi

# --- bifrost proxy :8082 -> :8089 (launcher installed by the bifrost-gateway feature) ---
if command -v start-bifrost >/dev/null 2>&1; then
    echo "[auto-startup] starting bifrost on :8082"
    start-bifrost || echo "[auto-startup] WARNING: start-bifrost exited non-zero"
else
    echo "[auto-startup] bifrost launcher not installed — skipping"
fi

# --- opencode serve :4096 (opencode mobile / Tailscale remote control) ---
if command -v opencode >/dev/null 2>&1; then
    if curl -sf -o /dev/null --max-time 2 http://127.0.0.1:4096/; then
        echo "[auto-startup] opencode serve already up on :4096"
    else
        echo "[auto-startup] starting opencode serve on :4096"
        nohup opencode serve --port 4096 --hostname 0.0.0.0 >/tmp/opencode-serve.log 2>&1 &
        sleep 2
    fi
else
    echo "[auto-startup] opencode CLI not installed — skipping"
fi

echo "[auto-startup] done."