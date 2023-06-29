#!/bin/bash

# POSITIONAL ARGUMENTS
#   1       rclone remote path, e.g. my_onedrive:foo/bar
#   2       program path
#   3..     program arguments

# EXIT CODES
# 0..125    program was executed and exited with resp. code
# 126       cannot execute program
# 127       program was not found
# 128       invalid exit argument
# 128+n     received signal n
# 255       the program was not executed, likely because an error occurred before

# see https://tldp.org/LDP/abs/html/exitcodes.html
# NOTE: for exit codes greater than 125, you CANNOT tell whether the program returned this code of if the special condition was met

set -o errexit   # abort on nonzero exitstatus; also see https://stackoverflow.com/a/11231970
set -o nounset   # abort on unbound variable
set -o pipefail  # don't hide errors within pipes
ORIGINAL_PWD="$PWD"


# for signal in SIGTERM SIGINT SIGQUIT SIGKILL SIGHUP; do
#     trap "signal_handler $signal" $signal
# done

# $1: signal name
# signal_handler () {
#     set +o errexit
#     signal=$1
#     echo "interrupted by $signal"
#     cleanup
#     trap - $signal      # restore default handler to avoid infinite loop
#     trap - EXIT
#     kill -s $signal $$  # report to parent that we have been interrupted
# }



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

# NOTE: retval is the exit code of the last command that *exited*.
# This means that if the program is running and SIGINT is received and the program does *not* exit e.g. by trapping SIGINT,
# then retval is the exit code of the command *before* the program

# NOTE: if a signal was received by the script, then after the exit handler finishes, the exit code is silently overridden with the specific signal code

exit_handler () {
    retval=$?
    # disable exit on failure
    set +o errexit
    echo ""
    echo ""
    # filter out exits that happened before the program was launched
    if [[ ${IS_LAUNCHED+1} ]]; then
        if ((retval==255)); then
            # either the program exited with code 255, or the program did not exit and the 255 is from the previous command
            # if program did not exit, a signal was received and exit code will be overridden with special signal code
            echo "WARN: program either finished with code 255 or has been aborted"
        else
            # program exited
            # exit code will be program exit code, or special exit code like 126, 127 or 128
            echo "program has finished with code $retval"
        fi
    else
        # program was not launched
        if ((retval==0)); then
            # this means that exit 0 was called before the program was started, which should NOT happen
            echo "ERROR: program was not launched"
        else
            echo "ERROR: program was not launched: an error occurred"
        fi
        retval=255
    fi
    # retval is now either the exit code of the program, a special exit code, or 255.
    cleanup || retval=255
    exit $retval
}


cleanup () {
    err () { echo "ERROR: cleanup failed"; }
    # echo "cleaning up"
    {
        cd "$ORIGINAL_PWD" &&
        stop_mount &&
        delete_mount_dir
    } || { err; return 1; }
    return 0
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

trap exit_handler EXIT









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
echo "launching $PROGRAM_PATH"

# process should be able to access the original working directory (where this script was executed in)
export ORIGINAL_PWD
# working directory for process is the mount folder
cd "$MOUNT_PATH"
IS_LAUNCHED=1
# execute dummy command with exit code 255 so that the exit handler can detect if the program exited or was aborted
( exit 255 ) && true
"$PROGRAM_PATH" "$@" && true
# if the program receives a signal and notifies its parent, i.e. this script (e.g. by not trapping the signal), then the exit handler is called immediately.
# Otherwise, the script proceeds to the next line and exits with the resp. exit code
# this is simply how the default bash signal handler works, which we implicitly use in this script by not trapping the signals
exit $?
