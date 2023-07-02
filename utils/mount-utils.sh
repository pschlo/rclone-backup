

# ---- UTILS ----

log_err () { echo "ERROR: $1" >&2; }
log_warn () { echo "WARN: $1" >&2; }
log_info () { echo "$1"; }

SECONDS=1000
# current timestamp in milliseconds; see https://serverfault.com/a/151112
timestamp_ms () {
    echo $(($(date +%s%N)/1000000))
}

# $1: mount PID
is_alive() {
    ps -p "$1" >/dev/null
}

# $1: mount path
is_mounted() {
    mountpoint -q "$1"
}




stop_mount () {
    local PID=$1
    local POINT="$2"
    local mount_str="${PID}@$(basename "$POINT")"

    if [[ ${3+x} ]]; then
        local TIMEOUT_SECS="$3"
    else
        local TIMEOUT_SECS=10
    fi

    if ! is_alive $PID; then return 0; fi

    if is_mounted $POINT; then
        umount "$POINT" 2>/dev/null && true
        if (($? > 0)); then
            log_warn "unmounting $mount_str failed; killing mount process"
            # we could *wait* for processes to finish their business with the mount dir,
            # but this script assumes that a *single* process is accessing the mount.
            # Upon exit signal, bash first waits for the running command to finish and
            # then finishes itself. Thus, the process is dead already.

            # kill might fail if mount process died in the meantime
            kill $PID 2>/dev/null && true
        fi
    else
        # not yet mounted
        # kill might fail if mount process died in the meantime
        kill $PID 2>/dev/null && true
    fi

    log_info "waiting for mount $mount_str to stop"
    # wait for TIMEOUT_MS millisecods for the mount process to terminate
    local TIMEOUT_MS=$((TIMEOUT_SECS*SECONDS))
    local t0=$(timestamp_ms)
    is_timeout() { (($(timestamp_ms)-t0 >= TIMEOUT_MS)); }

    while is_alive $PID && ! is_timeout; do
        sleep 0.1
    done
    if is_alive $PID; then
        log_err "could not terminate mount process $mount_str"
        return 1
    fi
    log_info "mount $mount_str stopped"
    return 0
}

wait_mount () {
    local PID=$1
    local POINT="$2"
    local mount_str="${PID}@$(basename "$POINT")"

    if [[ ${3+x} ]]; then
        local TIMEOUT_SECS="$3"
    else
        local TIMEOUT_SECS=10
    fi

    local TIMEOUT_MS=$((TIMEOUT_SECS*SECONDS))
    local t0=$(timestamp_ms)
    is_timeout() { (($(timestamp_ms)-t0 >= TIMEOUT_MS)); }

    while ! is_mounted $POINT && is_alive $PID && ! is_timeout; do
        sleep 0.1
    done
    if ! is_alive $PID; then
        log_err "mount $mount_str stopped"
        return 1
    fi
    if is_timeout && ! is_mounted $POINT; then
        log_err "mount $mount_str timed out"
        return 1
    fi
    return 0
}