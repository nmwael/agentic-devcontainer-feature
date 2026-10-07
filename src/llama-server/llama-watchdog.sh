#!/bin/sh
# llama-watchdog.sh — liveness + throughput guard for llama-server.
#
# /health answers in milliseconds even when generation has collapsed. A server
# observed at ~0.1 tok/s (degraded GPU state) still looks healthy, so every
# agent turn just runs into opencode's 5-minute provider timeout instead of
# failing fast — the run looks like a hang, not a broken server. This probe
# closes that gap: a 32-token completion must come back inside WATCHDOG_BUDGET
# seconds, otherwise (after one confirming retry, and only while no slot is
# processing) the server is stopped and the consumer's idempotent
# auto-startup.sh relaunches it.
#
# Modes:
#   (none)                daemon: probe every model in STACK_JSON, loop forever
#   --probe PORT [MODEL]  one probe; exit 0 healthy, 1 degraded/unreachable
#   --once  PORT [MODEL]  one full cycle (probe + confirm + restart if needed)
#
# Environment:
#   STACK_JSON             manifest enumerated in daemon mode
#                          (default /usr/local/share/llm-lab/stack.json)
#   WATCHDOG_INTERVAL      seconds between daemon cycles   (default 120)
#   WATCHDOG_BUDGET        probe timeout, seconds          (default 30)
#   WATCHDOG_CONFIRM_DELAY seconds between probe and retry (default 5)
#   WATCHDOG_RESTART       command relaunching the stack; default is
#                          auto-startup.sh next to this script. When no
#                          restart command can be resolved the watchdog only
#                          reports — it never kills a server it cannot bring
#                          back.
set -u

INTERVAL="${WATCHDOG_INTERVAL:-120}"
BUDGET="${WATCHDOG_BUDGET:-30}"
CONFIRM_DELAY="${WATCHDOG_CONFIRM_DELAY:-5}"
STACK_JSON="${STACK_JSON:-/usr/local/share/llm-lab/stack.json}"
PROBE_MODEL="${WATCHDOG_PROBE_MODEL:-watchdog}"
PROBE_CONTENT='Reply with exactly the word OK. This prompt exists only to measure generation speed.'
PROBE_TOKENS=32
LOG_FILE="${WATCHDOG_LOG:-/tmp/llama-watchdog.log}"

log() {
    printf '[llama-watchdog] %s\n' "$*"
}

usage() {
    cat <<'EOF'
usage: llama-watchdog.sh [--probe PORT [MODEL] | --once PORT [MODEL]]

  (no args)          daemon: probe every model in STACK_JSON every
                     WATCHDOG_INTERVAL seconds, restart after two failures
  --probe PORT [...] one probe; exit 0 healthy, 1 degraded or unreachable
  --once  PORT [...] one cycle (probe, confirm, restart if degraded)

env: STACK_JSON, WATCHDOG_INTERVAL, WATCHDOG_BUDGET,
     WATCHDOG_CONFIRM_DELAY, WATCHDOG_RESTART, WATCHDOG_LOG
EOF
}

probe_ok() {
    probe_p=$1
    probe_m=$2
    probe_body=$(printf '{"model":"%s","messages":[{"role":"user","content":"%s"}],"max_tokens":%s}' \
        "$probe_m" "$PROBE_CONTENT" "$PROBE_TOKENS")
    curl -sf -o /dev/null --max-time "$BUDGET" \
        -H 'Content-Type: application/json' \
        -d "$probe_body" \
        -X POST "http://127.0.0.1:${probe_p}/v1/chat/completions" >/dev/null 2>&1
}

# True only when /slots positively reports an in-flight request. A busy server
# is not degraded — probing it would queue behind the running generation and
# look like a timeout, which is exactly the false positive we must not restart on.
slot_busy() {
    busy_body=$(curl -s --max-time 3 "http://127.0.0.1:${1}/slots" 2>/dev/null) || return 1
    printf '%s' "$busy_body" | grep -Eq '"is_processing"[[:space:]]*:[[:space:]]*true'
}

llama_pid_for_port() {
    for pid_dir in /proc/[0-9]*; do
        [ -r "$pid_dir/cmdline" ] || continue
        pid_cmd=$(tr '\0' ' ' <"$pid_dir/cmdline" 2>/dev/null) || continue
        case " $pid_cmd " in
        *llama-server*" --port $1 "*)
            printf '%s\n' "${pid_dir#/proc/}"
            return 0
            ;;
        esac
    done
    return 1
}

stop_pid() {
    stop_target=$1
    kill "$stop_target" 2>/dev/null || true
    stop_i=0
    while kill -0 "$stop_target" 2>/dev/null; do
        stop_i=$((stop_i + 1))
        if [ "$stop_i" -gt 15 ]; then
            kill -9 "$stop_target" 2>/dev/null || true
            break
        fi
        sleep 1
    done
}

resolve_restart() {
    if [ -n "${WATCHDOG_RESTART:-}" ]; then
        printf '%s\n' "$WATCHDOG_RESTART"
        return 0
    fi
    restart_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" 2>/dev/null && pwd) || restart_dir=""
    if [ -n "$restart_dir" ] && [ -f "$restart_dir/auto-startup.sh" ]; then
        printf 'bash %s\n' "$restart_dir/auto-startup.sh"
        return 0
    fi
    return 1
}

restart_server() {
    restart_port=$1
    restart_name=$2
    if ! restart_cmd=$(resolve_restart); then
        log "WARNING: ${restart_name} :${restart_port} needs a restart but no WATCHDOG_RESTART or sibling auto-startup.sh was found — reporting only, not killing"
        return 1
    fi
    restart_pid=$(llama_pid_for_port "$restart_port" || true)
    if [ -n "$restart_pid" ]; then
        log "stopping ${restart_name} on :${restart_port} (pid ${restart_pid})"
        stop_pid "$restart_pid"
    else
        log "${restart_name} :${restart_port} has no llama-server process — relaunching"
    fi
    log "relaunching via: ${restart_cmd}"
    if sh -c "$restart_cmd"; then
        log "${restart_name} relaunch requested on :${restart_port}"
        return 0
    fi
    log "WARNING: restart command failed for ${restart_name} (see ${LOG_FILE})"
    return 1
}

cycle_one() {
    cycle_port=$1
    cycle_name=$2
    cycle_model=$3

    if ! curl -sf -o /dev/null --max-time 3 "http://127.0.0.1:${cycle_port}/health" 2>/dev/null; then
        log "${cycle_name} :${cycle_port} /health DOWN — confirming in ${CONFIRM_DELAY}s"
        sleep "$CONFIRM_DELAY"
        if ! curl -sf -o /dev/null --max-time 3 "http://127.0.0.1:${cycle_port}/health" 2>/dev/null; then
            log "${cycle_name} :${cycle_port} still DOWN — restarting"
            restart_server "$cycle_port" "$cycle_name"
            return 0
        fi
    fi

    if slot_busy "$cycle_port"; then
        log "${cycle_name} :${cycle_port} busy — skipping probe"
        return 0
    fi

    if probe_ok "$cycle_port" "$cycle_model"; then
        log "${cycle_name} :${cycle_port} healthy (probe inside ${BUDGET}s)"
        return 0
    fi

    log "${cycle_name} :${cycle_port} probe missed the ${BUDGET}s budget — confirming in ${CONFIRM_DELAY}s"
    sleep "$CONFIRM_DELAY"
    if slot_busy "$cycle_port"; then
        log "${cycle_name} :${cycle_port} became busy — skipping restart"
        return 0
    fi
    if probe_ok "$cycle_port" "$cycle_model"; then
        log "${cycle_name} :${cycle_port} healthy on retry"
        return 0
    fi

    log "${cycle_name} :${cycle_port} DEGRADED (two probes over ${BUDGET}s) — restarting"
    restart_server "$cycle_port" "$cycle_name"
}

MODE=daemon
case "${1:-}" in
--probe)
    MODE=probe
    shift
    ;;
--once)
    MODE=once
    shift
    ;;
'' | -h | --help)
    usage
    exit 0
    ;;
*)
    usage >&2
    exit 2
    ;;
esac

case "$MODE" in
probe)
    if [ "$#" -lt 1 ]; then
        echo "llama-watchdog: --probe needs a port" >&2
        exit 2
    fi
    if probe_ok "$1" "${2:-$PROBE_MODEL}"; then
        log ":$1 probe healthy (inside ${BUDGET}s)"
        exit 0
    fi
    log ":$1 probe DEGRADED (budget ${BUDGET}s)"
    exit 1
    ;;
once)
    if [ "$#" -lt 1 ]; then
        echo "llama-watchdog: --once needs a port" >&2
        exit 2
    fi
    cycle_one "$1" "${2:-$1}" "${2:-$PROBE_MODEL}"
    exit 0
    ;;
esac

if ! command -v jq >/dev/null 2>&1; then
    log "jq not found — cannot enumerate ${STACK_JSON} (use --probe/--once)"
    exit 1
fi
if [ ! -f "$STACK_JSON" ]; then
    log "no manifest at ${STACK_JSON} — nothing to watch"
    exit 1
fi

log "watching ${STACK_JSON} every ${INTERVAL}s (budget ${BUDGET}s, confirm delay ${CONFIRM_DELAY}s)"
while :; do
    model_total=$(jq '.models | length' "$STACK_JSON" 2>/dev/null) || model_total=0
    case "$model_total" in
    '' | *[!0-9]*) model_total=0 ;;
    esac
    idx=0
    while [ "$idx" -lt "$model_total" ]; do
        m_name=$(jq -r ".models[$idx].name" "$STACK_JSON")
        m_port=$(jq -r ".models[$idx].port" "$STACK_JSON")
        cycle_one "$m_port" "$m_name" "$m_name"
        idx=$((idx + 1))
    done
    sleep "$INTERVAL"
done
