#!/bin/bash


# ---- UTILS ----

log_err () { echo "ERROR: $1" >&2; }
log_warn () { echo "WARN: $1" >&2; }
log_info () { echo "$1"; }

SECONDS=1000
# current timestamp in milliseconds; see https://serverfault.com/a/151112
timestamp_ms () {
    echo $(($(date +%s%N)/1000000))
}

is_alive() {
    ps -p $MOUNT_PID >/dev/null
}

is_mounted() {
    mountpoint -q "$MOUNT_PATH"
}




stop_mount () {
    MOUNT_PID=$1
    MOUNT_PATH="$2"
    mount_str="${MOUNT_PID}@$(basename "$MOUNT_PATH")"

    if [[ ${3+x} ]]; then
        TIMEOUT_SECS="$3"
    else
        TIMEOUT_SECS=10
    fi

    if ! is_alive; then return 0; fi

    if is_mounted; then
        umount "$MOUNT_PATH" 2>/dev/null && true
        if (($? > 0)); then
            log_warn "unmounting $mount_str failed; killing mount process"
            # we could *wait* for processes to finish their business with the mount dir,
            # but this script assumes that a *single* process is accessing the mount.
            # Upon exit signal, bash first waits for the running command to finish and
            # then finishes itself. Thus, the process is dead already.

            # kill might fail if mount process died in the meantime
            kill $MOUNT_PID 2>/dev/null && true
        fi
    else
        # not yet mounted
        # kill might fail if mount process died in the meantime
        kill $MOUNT_PID 2>/dev/null && true
    fi

    log_info "waiting for mount $mount_str to stop"
    # wait for TIMEOUT_MS millisecods for the mount process to terminate
    TIMEOUT_MS=$((TIMEOUT_SECS*SECONDS))
    t0=$(timestamp_ms)
    is_timeout() { (($(timestamp_ms)-t0 >= TIMEOUT_MS)); }

    while is_alive && ! is_timeout; do sleep 0.1; done
    if is_alive; then log_err "could not terminate mount process $mount_str"; return 1; fi
    log_info "mount $mount_str stopped"
    return 0
}

wait_mount () {
    MOUNT_PID=$1
    MOUNT_PATH="$2"
    mount_str="${MOUNT_PID}@$(basename "$MOUNT_PATH")"

    if [[ ${3+x} ]]; then
        TIMEOUT_SECS="$3"
    else
        TIMEOUT_SECS=10
    fi

    TIMEOUT_MS=$((TIMEOUT_SECS*SECONDS))
    t0=$(timestamp_ms)
    is_timeout() { (($(timestamp_ms)-t0 >= TIMEOUT_MS)); }

    while ! is_mounted && is_alive && ! is_timeout; do sleep 0.1; done
    if ! is_alive; then log_err "mount $mount_str stopped"; return 1; fi
    if is_timeout && ! is_mounted; then log_err "mount $mount_str timed out"; return 1; fi
    return 0
}