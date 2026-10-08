#!/bin/sh
# bifrost-watchdog.sh — liveness guard for the bifrost gateway.
#
# GET / answers in milliseconds even when the gateway is wedged or dead, so
# a broken gateway presents as slow agent requests rather than a clear
# outage. This probe closes that gap: a plain GET / must come back inside
# BIFROST_WATCHDOG_BUDGET seconds, otherwise (after one confirming retry) the
# gateway processes are stopped and the consumer's idempotent
# auto-startup.sh relaunches them.
#
# Modes:
#   (none)          daemon: probe the resolved port every cycle, restart
#                   after two failures
#   --probe PORT    one probe; exit 0 healthy, 1 degraded/unreachable
#   --once  PORT    one full cycle (probe + confirm + restart if needed)
#
# Environment:
#   STACK_JSON                     manifest consulted in daemon mode for
#                                  .cloud and .bifrost_port
#                                  (default /usr/local/share/llm-lab/stack.json)
#   BIFROST_WATCHDOG_INTERVAL      seconds between daemon cycles   (default 120)
#   BIFROST_WATCHDOG_BUDGET        probe timeout, seconds          (default 5)
#   BIFROST_WATCHDOG_CONFIRM_DELAY seconds between probe and retry (default 5)
#   BIFROST_WATCHDOG_MAX_RESTARTS  restart attempts per port before giving up
#                                  until a healthy probe resets the count
#                                  (default 3)
#   BIFROST_WATCHDOG_STATE         restart-attempt ledger file
#                                  (default /tmp/bifrost-watchdog.state)
#   BIFROST_WATCHDOG_LOG           log file named in failure messages
#                                  (default /tmp/bifrost-watchdog.log)
#   BIFROST_WATCHDOG_RESTART       command relaunching the stack; default is
#                                  auto-startup.sh next to this script. When no
#                                  restart command can be resolved the watchdog
#                                  only reports — it never kills a gateway it
#                                  cannot bring back.
#   BIFROST_PORT                   gateway port probed in daemon mode when set
#                                  (default: manifest .bifrost_port, else 8082)
set -u

INTERVAL="${BIFROST_WATCHDOG_INTERVAL:-120}"
BUDGET="${BIFROST_WATCHDOG_BUDGET:-5}"
CONFIRM_DELAY="${BIFROST_WATCHDOG_CONFIRM_DELAY:-5}"
MAX_RESTARTS="${BIFROST_WATCHDOG_MAX_RESTARTS:-3}"
STACK_JSON="${STACK_JSON:-/usr/local/share/llm-lab/stack.json}"
STATE_FILE="${BIFROST_WATCHDOG_STATE:-/tmp/bifrost-watchdog.state}"
LOG_FILE="${BIFROST_WATCHDOG_LOG:-/tmp/bifrost-watchdog.log}"

log() {
    printf '[bifrost-watchdog] %s\n' "$*"
}

usage() {
    cat <<'EOF'
usage: bifrost-watchdog.sh [--probe PORT | --once PORT]

  (no args)       daemon: probe http://127.0.0.1:<port>/ every
                  BIFROST_WATCHDOG_INTERVAL seconds, restart after two failures
  --probe PORT    one probe; exit 0 healthy, 1 degraded or unreachable
  --once  PORT    one cycle (probe, confirm, restart if degraded)

env: STACK_JSON, BIFROST_WATCHDOG_INTERVAL, BIFROST_WATCHDOG_BUDGET,
     BIFROST_WATCHDOG_CONFIRM_DELAY, BIFROST_WATCHDOG_MAX_RESTARTS,
     BIFROST_WATCHDOG_RESTART, BIFROST_WATCHDOG_LOG, BIFROST_PORT
EOF
}

# Plain GET / — the same readiness signal auto-startup.sh polls. No completion
# probe (needs a live upstream → false-positive restarts on a no-weights box)
# and no /slots equivalent.
probe_ok() {
    curl -sf -o /dev/null --max-time "$BUDGET" "http://127.0.0.1:${1}/" >/dev/null 2>&1
}

# Launcher pids: cmdline must contain BOTH bin.js and the port, so the match
# covers the positional form (bin.js 8082) and the flag form
# (bin.js -port 8082 -host 0.0.0.0) while excluding other ports.
bifrost_parent_pids() {
    pid_port=$1
    for pid_dir in /proc/[0-9]*; do
        [ -r "$pid_dir/cmdline" ] || continue
        pid_cmd=$(tr '\0' ' ' <"$pid_dir/cmdline" 2>/dev/null) || continue
        case " $pid_cmd " in
        *bin.js*)
            case " $pid_cmd " in
            *" $pid_port "*)
                printf '%s\n' "${pid_dir#/proc/}"
                ;;
            esac
            ;;
        esac
    done
    return 0
}

# bifrost-http-0 child pids; bracket trick keeps the pattern out of our own
# cmdline (repo convention, test/bifrost-gateway/test.sh).
bifrost_child_pids() {
    for pid_dir in /proc/[0-9]*; do
        [ -r "$pid_dir/cmdline" ] || continue
        pid_cmd=$(tr '\0' ' ' <"$pid_dir/cmdline" 2>/dev/null) || continue
        case " $pid_cmd " in
        *bifros[t]-http*)
            printf '%s\n' "${pid_dir#/proc/}"
            ;;
        esac
    done
    return 0
}

# True when something still holds a LISTEN socket on the port — a wedged
# listener would make auto-startup's curl guard fail and relaunch EADDRINUSE.
port_listening() {
    pl_hex=$(printf '%04X' "$1")
    for pl_file in /proc/net/tcp /proc/net/tcp6; do
        [ -r "$pl_file" ] || continue
        if awk -v h="$pl_hex" 'FNR > 1 && $4 == "0A" && $2 ~ (":" h "$") { found = 1 } END { exit !found }' "$pl_file" 2>/dev/null; then
            return 0
        fi
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

# Per-port restart ledger: give up after MAX_RESTARTS attempts so a box that
# cannot bring its stack up is reported about once, not relaunched forever.
# A healthy probe clears the port's count.
restart_attempts_get() {
    [ -f "$STATE_FILE" ] || {
        printf '0'
        return 0
    }
    awk -v p="$1" '$1 == p { c = $2 } END { print c + 0 }' "$STATE_FILE"
}

restart_attempts_bump() {
    bump_port=$1
    bump_now=$(restart_attempts_get "$bump_port")
    bump_now=$((bump_now + 1))
    if [ -f "$STATE_FILE" ]; then
        awk -v p="$bump_port" '$1 != p { print $1, $2 }' "$STATE_FILE" >"${STATE_FILE}.tmp"
    else
        : >"${STATE_FILE}.tmp"
    fi
    printf '%s %s\n' "$bump_port" "$bump_now" >>"${STATE_FILE}.tmp"
    mv "${STATE_FILE}.tmp" "$STATE_FILE"
}

restart_attempts_reset() {
    [ -f "$STATE_FILE" ] || return 0
    awk -v p="$1" '$1 != p { print $1, $2 }' "$STATE_FILE" >"${STATE_FILE}.tmp"
    mv "${STATE_FILE}.tmp" "$STATE_FILE"
}

resolve_restart() {
    if [ -n "${BIFROST_WATCHDOG_RESTART:-}" ]; then
        printf '%s\n' "$BIFROST_WATCHDOG_RESTART"
        return 0
    fi
    restart_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" 2>/dev/null && pwd) || restart_dir=""
    if [ -n "$restart_dir" ] && [ -f "$restart_dir/auto-startup.sh" ]; then
        printf 'bash %s\n' "$restart_dir/auto-startup.sh"
        return 0
    fi
    return 1
}

restart_bifrost() {
    restart_port=$1
    restart_attempts=$(restart_attempts_get "$restart_port")
    if [ "$restart_attempts" -ge "$MAX_RESTARTS" ]; then
        log "bifrost :${restart_port} already restarted ${restart_attempts}x without a healthy probe — giving up (ledger ${STATE_FILE}; a healthy probe or a fresh ${0##*/} run re-arms it)"
        return 1
    fi
    if ! restart_cmd=$(resolve_restart); then
        log "WARNING: bifrost :${restart_port} needs a restart but no BIFROST_WATCHDOG_RESTART or sibling auto-startup.sh was found — reporting only, not killing"
        return 1
    fi
    # Stop-before-start: a wedged listener would make auto-startup's curl
    # guard fail → relaunch EADDRINUSE. Kill the bin.js launcher for this
    # port, then the bifrost-http child only when a launcher matched for this
    # port or the port is still occupied afterwards.
    restart_parents=$(bifrost_parent_pids "$restart_port")
    restart_stop_children=false
    if [ -n "$restart_parents" ]; then
        restart_stop_children=true
        for restart_pid in $restart_parents; do
            log "stopping bifrost launcher on :${restart_port} (pid ${restart_pid})"
            stop_pid "$restart_pid"
        done
    elif port_listening "$restart_port"; then
        log "bifrost :${restart_port} has no bin.js launcher but the port is still occupied — clearing listener"
        restart_stop_children=true
    else
        log "bifrost :${restart_port} has no bifrost process — relaunching"
    fi
    if [ "$restart_stop_children" = true ]; then
        restart_children=$(bifrost_child_pids "$restart_port")
        for restart_pid in $restart_children; do
            log "stopping bifrost-http child on :${restart_port} (pid ${restart_pid})"
            stop_pid "$restart_pid"
        done
    fi
    log "relaunching via: ${restart_cmd}"
    if sh -c "$restart_cmd"; then
        restart_attempts_bump "$restart_port"
        log "bifrost relaunch requested on :${restart_port} (attempt $((restart_attempts + 1))/${MAX_RESTARTS})"
        return 0
    fi
    log "WARNING: restart command failed for bifrost (see ${LOG_FILE})"
    return 1
}

cycle() {
    cycle_port=$1

    if ! probe_ok "$cycle_port"; then
        log "bifrost :${cycle_port} DOWN — confirming in ${CONFIRM_DELAY}s"
        sleep "$CONFIRM_DELAY"
        if ! probe_ok "$cycle_port"; then
            log "bifrost :${cycle_port} still DOWN — restarting"
            restart_bifrost "$cycle_port"
            return 0
        fi
        restart_attempts_reset "$cycle_port"
        log "bifrost :${cycle_port} healthy on retry"
        return 0
    fi

    restart_attempts_reset "$cycle_port"
    log "bifrost :${cycle_port} healthy (probe inside ${BUDGET}s)"
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
-h | --help)
    usage
    exit 0
    ;;
'')
    # no args: fall through to daemon mode (MODE already set above)
    ;;
*)
    usage >&2
    exit 2
    ;;
esac

case "$MODE" in
probe)
    if [ "$#" -lt 1 ]; then
        echo "bifrost-watchdog: --probe needs a port" >&2
        exit 2
    fi
    if probe_ok "$1"; then
        log ":$1 probe healthy (inside ${BUDGET}s)"
        exit 0
    fi
    log ":$1 probe DEGRADED (budget ${BUDGET}s)"
    exit 1
    ;;
once)
    if [ "$#" -lt 1 ]; then
        echo "bifrost-watchdog: --once needs a port" >&2
        exit 2
    fi
    cycle "$1"
    exit 0
    ;;
esac

if [ -f "$STACK_JSON" ] && command -v jq >/dev/null 2>&1 &&
    [ "$(jq -r '.cloud // false' "$STACK_JSON" 2>/dev/null)" = "true" ]; then
    log "cloud mode — no local bifrost to watch, exiting"
    exit 0
fi
if ! command -v start-bifrost >/dev/null 2>&1; then
    log "start-bifrost not installed — nothing to watch, exiting"
    exit 0
fi

# Port resolution mirrors auto-startup.sh: env when set, else manifest
# .bifrost_port when manifest + jq are available, else 8082. A missing
# manifest is NOT fatal — bifrost legitimately runs without stack.json.
daemon_port="${BIFROST_PORT:-}"
if [ -z "$daemon_port" ]; then
    if [ -f "$STACK_JSON" ] && command -v jq >/dev/null 2>&1; then
        daemon_port=$(jq -r '.bifrost_port // empty' "$STACK_JSON" 2>/dev/null) || daemon_port=""
    fi
    [ -n "$daemon_port" ] || daemon_port=8082
fi

log "watching port ${daemon_port} every ${INTERVAL}s (budget ${BUDGET}s, confirm delay ${CONFIRM_DELAY}s)"
while :; do
    cycle "$daemon_port"
    sleep "$INTERVAL"
done
