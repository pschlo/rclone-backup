#!/bin/bash

# POSITIONAL ARGUMENTS
#   1       rclone remote path, e.g. my_onedrive:foo/bar
#   2       program path
#   3..     program arguments


set -o errexit   # abort on nonzero exitstatus; also see https://stackoverflow.com/a/11231970
set -o nounset   # abort on unbound variable
set -o pipefail  # don't hide errors within pipes


# ---- UTILS ----

SECONDS=1000
# current timestamp in milliseconds; see https://serverfault.com/a/151112
timestamp_ms () {
    echo $(($(date +%s%N)/1000000))
}

is_alive() {
    [[ ${MOUNT_PID+1} ]] && ps -p $MOUNT_PID >/dev/null
}

is_mounted() {
    [[ ${MOUNT_PATH+1} ]] && mountpoint -q "$MOUNT_PATH"
}





# ---- PARSE ARGUMENTS ----

# (no longer) adapted from https://stackoverflow.com/a/14203146

KEYWORD_ARGS=()
while [[ (($# > 0)) && $1 != "--" ]]; do
    KEYWORD_ARGS+=("$1")
    shift
done

if (($# == 0)); then
    # missing -- delimiter
    # assume that no rclone args were passed
    set -- "${KEYWORD_ARGS[@]}"
    KEYWORD_ARGS=()
else
    # remove -- delimiter
    shift
fi

if (($# < 2)); then echo "ERROR: Expected at least 2 positional arguments, but $# where given"; exit 1; fi
SOURCE_PATH="$1"  # path on source, e.g. server
shift

# path to restic repository
PROGRAM_PATH="$1"
shift
if [[ $PROGRAM_PATH == ./* || $PROGRAM_PATH == ../* ]]; then
    # relative path; convert to absolute
    PROGRAM_PATH="$PWD"/"$PROGRAM_PATH"
fi







# ---- CLEANUP FUNCTIONS ----

# define function to be run at exit
cleanup () {
    echo ""
    echo ""
    set +o errexit
    # echo "cleaning up"
    stop_mount
    delete_mount_dir
    set -o errexit
}

stop_mount () {
    if ! is_alive; then return 0; fi

    if is_mounted; then
        umount "$MOUNT_PATH" 2>/dev/null
        if (($? > 0)); then
            echo "unmounting failed; killing mount process"
            # we could *wait* for processes to finish their business with the mount dir,
            # but this script assumes that a *single* process is accessing the mount.
            # Upon exit signal, bash first waits for the running command to finish and
            # then finishes itself. Thus, the process is dead already.

            # kill might fail if mount process failed in the meantime
            kill $MOUNT_PID 2>/dev/null
        fi
    else
        # not yet mounted
        # kill might fail if mount process failed in the meantime
        kill $MOUNT_PID 2>/dev/null
    fi

    echo "waiting for mount to stop"
    # wait for TIMEOUT_MS millisecods for the mount process to terminate
    TIMEOUT_MS=$((10*SECONDS))
    t0=$(timestamp_ms)
    is_timeout() { (($(timestamp_ms)-t0 >= TIMEOUT_MS)); }

    while is_alive && ! is_timeout; do sleep 0.1; done
    if is_alive; then echo "ERROR: Could not terminate mount process"; exit 1; fi
    echo "mount stopped"
    return 0
}

delete_mount_dir () {
    # when mount process was killed, rm might fail
    if [[ ${MOUNT_PATH+1} ]]; then
        rm -d "$MOUNT_PATH"
        if (($?>0)); then echo "ERROR: could not delete mount folder"; exit 1; fi
    fi
}

trap cleanup EXIT









# ---- MOUNTING ----

echo "mounting remote $SOURCE_PATH"

# create mount folder
MOUNT_PATH="$(mktemp -d)"

# launch fuse mount daemon

args=()
args+=("$SOURCE_PATH" "$MOUNT_PATH")
args+=("--read-only")
args+=("${KEYWORD_ARGS[@]}")

setsid rclone mount "${args[@]}" &
MOUNT_PID=$!

# wait until mount becomes available
# abort after TIMEOUT_MS milliseconds
TIMEOUT_MS=$((10*SECONDS))
t0=$(timestamp_ms)
is_timeout() { (($(timestamp_ms)-t0 >= TIMEOUT_MS)); }

while ! is_mounted && is_alive && ! is_timeout; do sleep 0.1; done
if ! is_alive; then echo "ERROR: rclone mount stopped"; exit 1; fi
if is_timeout && ! is_mounted; then echo "ERROR: rclone mount timed out"; exit 1; fi

# successfully mounted
# do not allow empty mount dir
# this happens e.g. when rclone mounts an invalid path
if [[ ! "$(ls -A "$MOUNT_PATH")" ]]; then
    # empty
    echo "ERROR: mount is empty"
    exit 1
fi
echo "mount successful"





# ---- RUNNING THE PROGRAM  ----
echo "running $PROGRAM_PATH"

(
    # process should be able to access the original working directory (where this script was executed in)
    export ORIGINAL_PWD="$PWD"
    # working directory for process is the mount folder
    cd "$MOUNT_PATH"
    $PROGRAM_PATH "$@"
)
