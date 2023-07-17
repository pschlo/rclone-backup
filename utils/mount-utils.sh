


# ------ CONFIG -----

# all durations are seconds
IS_MOUNTED_TIMEOUT=3
WAIT_MOUNT_TIMEOUT=10
STOP_MOUNT_TIMEOUT=10




# ---- UTILS ----

log_err () { echo "ERROR: $1" >&2; }
log_warn () { echo "WARN: $1" >&2; }
log_info () { echo "$1"; }

SECONDS=1000
# current timestamp in milliseconds; see https://serverfault.com/a/151112
timestamp_ms () {
    echo $(($(date +%s%N)/1000000))
}

# $1: mount session ID (usually same as PID)
is_alive() {
    pgrep -g "$1" >/dev/null
}

# wait for a process group to terminate
# $1: process group ID
# $2: timeout in ms
# returns 1 if timeout, 0 if process group terminated
wait_group_termination () {
    local pid="$1"
    local timeout_ms="$2"
    local t0=$(timestamp_ms)
    is_timeout() { (($(timestamp_ms)-t0 >= timeout_ms)); }
    while is_alive $pid && ! is_timeout; do
        sleep 0.1
    done
    if is_alive $pid; then return 1; fi
    return 0
}

# $1: process group ID
kill_group () {
    pkill -TERM -g "$1" 2>/dev/null
    # ensure that stopped processes receive the signal
    pkill -CONT -g "$1" 2>/dev/null
}

# $1: mount path
is_mounted () {
    # in case of broken/stale mount, 'mountpoint' can freeze
    # note that timeout by default runs in a new background group and thus does NOT receive keyboard signals
    # we pass --foreground to run it in the current process group
    timeout --foreground "$IS_MOUNTED_TIMEOUT"s mountpoint -q "$1"
}


# $1: process group ID
# $2: mountpoint
# $3: timeout in seconds
# the main command is 'umount'.
# if that fails, we try again.
# if that fails, we kill the process group.
stop_mount () {
    local pid=$1
    local point="$2"
    local mount_str="${pid}@$(basename "$point")"

    if [[ ${3+x} ]]; then
        local timeout_secs="$3"
    else
        local timeout_secs="$STOP_MOUNT_TIMEOUT"
    fi
    # divide by three because we wait three times
    timeout_ms="$(( (timeout_secs*SECONDS) / 3 ))"

    # try umount
    log_info "unmounting $mount_str"
    umount "$point" 2>/dev/null && true
    wait_group_termination $pid $timeout_ms || {
        # umount failed, either because not yet mounted, or because it is still somehow active
        # the processes that accessed the mount should already be dead, since we executed it in the foreground, if at all
        # wait for mountpoint to become non-busy and try umount again
        log_warn "unmounting $mount_str failed, retrying"
        umount "$point" 2>/dev/null && true
        wait_group_termination $pid $timeout_ms || {
            # kill
            log_warn "unmounting $mount_str failed again, killing mount processes"
            kill_group "$pid" && true
            wait_group_termination $pid $timeout_ms || {
                # failed
                log_err "could not terminate mount processes $mount_str"
                return 1
            }
        }
    }
    log_info "successfully unmounted $mount_str"
    return 0
}

# $1: process group ID
# $2: mountpoint
# $3: timeout in seconds
wait_mount () {
    local pid=$1
    local point="$2"
    local mount_str="${pid}@$(basename "$point")"

    if [[ ${3+x} ]]; then
        local timeout_secs="$3"
    else
        local timeout_secs="$WAIT_MOUNT_TIMEOUT"
    fi

    local timeout_ms=$((timeout_secs*SECONDS))
    local t0=$(timestamp_ms)
    is_timeout() { (($(timestamp_ms)-t0 >= timeout_ms)); }

    while ! is_mounted "$point" && is_alive $pid && ! is_timeout; do
        sleep 0.1
    done
    # now either mounted, dead or timed out

    if ! is_alive $pid; then
        log_err "mount $mount_str stopped"
        return 1
    fi
    if is_mounted "$point"; then
        return 0
    fi
    # must be timeout
    log_err "mount $mount_str timed out"
    return 1

}