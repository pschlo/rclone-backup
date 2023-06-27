#!/bin/bash

# POSITIONAL ARGUMENTS
#   1       rclone remote path, e.g. my_onedrive:foo/bar
#   2       program path
#   3..     program arguments

# EXIT CODES
# 0..87        program was executed and exited with resp. code
# 126          program/script cannot execute
# 127          program/script not found
# 129..165     program/script terminated due to signal
# 166..253     an error occurred during cleanup, but the program was lauched and exited with <exitcode>-166.
# 254          an error ocurred before the program could be launched. Cleanup may or may not have been successful.

# for special bash exit codes between 126 and 165, see https://tldp.org/LDP/abs/html/exitcodes.html

set -o errexit   # abort on nonzero exitstatus; also see https://stackoverflow.com/a/11231970
set -o nounset   # abort on unbound variable
set -o pipefail  # don't hide errors within pipes
ORIGINAL_PWD="$PWD"


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

is_temp_mount() {
    [[ ! ${CUSTOM_MOUNTPOINT+1} ]];
}






# ---- PARSE ARGUMENTS ----

# (no longer) adapted from https://stackoverflow.com/a/14203146

RCLONE_ARGS=()
while [[ (($# > 0)) && $1 != "--" ]]; do
    case "$1" in
        "--mountpoint")
            if [[ ! ${2+1} ]]; then echo "ERROR: must specify mountpoint"; exit 1; fi
            CUSTOM_MOUNTPOINT="$(realpath "$2")"
            shift
            shift
            ;;
        *)
            RCLONE_ARGS+=("$1")
            shift
            ;;
    esac
done

if (($# == 0)); then
    # missing -- delimiter
    # assume that no rclone args were passed
    set -- "${RCLONE_ARGS[@]}"
    RCLONE_ARGS=()
else
    # remove -- delimiter
    shift
fi

if (($# < 2)); then echo "ERROR: Expected at least 2 positional arguments, but $# where given"; exit 1; fi
SOURCE_PATH="$1"  # path on source, e.g. server
shift

# path to program
PROGRAM_PATH="$1"
shift
if [[ $PROGRAM_PATH == ./* || $PROGRAM_PATH == ../* ]]; then
    # relative path; convert to absolute
    PROGRAM_PATH="$PWD"/"$PROGRAM_PATH"
fi







# ---- CLEANUP FUNCTIONS ----

# define function to be run at exit
# if the script does not exit during cleanup, then the exit code from before cleanup was called is returned
# if the script exits during cleanup, then that is returned instead
# thus: do NOT exit during cleanup
cleanup () {
    retval=$?
    # disable exit on failure
    set +o errexit
    echo ""
    echo ""

    cleanup_err () {
        echo "ERROR: cleanup failed"
        if [[ ${IS_LAUNCHED+1} ]]; then
            if ((retval>87)); then
                echo "WARN: exit code $retval is too large, truncating to 87"
                retval=87
            fi
            exit $((retval+166))
        else
            exit 254
        fi
    }

    if [[ ${IS_LAUNCHED+1} ]]; then
        echo "program finished"
    else
        if ((retval==0)); then
            # this means that exit 0 was called before the program was started, which should NOT happen
            echo "program was not executed"
        else
            echo "ERROR: An error occurred before the program could be launched"
        fi
    fi

    # echo "cleaning up"
    cd "$ORIGINAL_PWD" || cleanup_err
    stop_mount || cleanup_err
    delete_mount_dir || cleanup_err

    if [[ ${IS_LAUNCHED+1} ]]; then
        if ((retval>87)); then
            echo "WARN: exit code $retval is too large, truncating to 87"
            retval=87
        fi
        exit $retval
    else
        exit 254
    fi
}

stop_mount () {
    if ! is_alive; then return 0; fi

    if is_mounted; then
        umount "$MOUNT_PATH" 2>/dev/null
        if (($? > 0)); then
            echo "WARN: unmounting failed; killing mount process"
            # we could *wait* for processes to finish their business with the mount dir,
            # but this script assumes that a *single* process is accessing the mount.
            # Upon exit signal, bash first waits for the running command to finish and
            # then finishes itself. Thus, the process is dead already.

            # kill might fail if mount process died in the meantime
            kill $MOUNT_PID 2>/dev/null
        fi
    else
        # not yet mounted
        # kill might fail if mount process died in the meantime
        kill $MOUNT_PID 2>/dev/null
    fi

    echo "waiting for mount to stop"
    # wait for TIMEOUT_MS millisecods for the mount process to terminate
    TIMEOUT_MS=$((10*SECONDS))
    t0=$(timestamp_ms)
    is_timeout() { (($(timestamp_ms)-t0 >= TIMEOUT_MS)); }

    while is_alive && ! is_timeout; do sleep 0.1; done
    if is_alive; then echo "ERROR: Could not terminate mount process"; return 1; fi
    echo "mount stopped"
    return 0
}

delete_mount_dir () {
    # when mount could not be unmounted, rm might fail
    if [[ ${MOUNT_PATH+1} ]] && is_temp_mount; then
        rm -d "$MOUNT_PATH"
        if (($?>0)); then echo "ERROR: could not delete temporary mount folder"; return 1; fi
    fi
    return 0
}

trap cleanup EXIT









# ---- MOUNTING ----

if is_temp_mount; then
    echo "mounting remote $SOURCE_PATH in temporary folder"
else
    echo "mounting remote $SOURCE_PATH in $CUSTOM_MOUNTPOINT"
fi

# create mount folder
if is_temp_mount; then
    MOUNT_PATH="$(mktemp -d)"
else
    if [[ ! -d $CUSTOM_MOUNTPOINT ]]; then
        echo "ERROR: mountpoint does not exit"
        exit 1
    fi
    MOUNT_PATH="$CUSTOM_MOUNTPOINT"  
fi

# launch fuse mount daemon

args=()
args+=("$SOURCE_PATH" "$MOUNT_PATH")
args+=("--read-only")
args+=("${RCLONE_ARGS[@]}")

# launch as daemon, but keep stdout connected to current terminal
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

# process should be able to access the original working directory (where this script was executed in)
export ORIGINAL_PWD
# working directory for process is the mount folder
cd "$MOUNT_PATH"
IS_LAUNCHED=1
"$PROGRAM_PATH" "$@" && true
# exit with return code of executed program
exit $?
