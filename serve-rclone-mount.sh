#!/bin/bash

# POSITIONAL ARGUMENTS
#   1       rclone remote path, e.g. my_onedrive:foo/bar
#   2       program path
#   3..     program arguments

# EXIT CODES
#   In general, the exit code of the program is returned.
#   However, the following exit codes can also be returned under other circumstances:
#       126     cannot execute program
#       127     program was not found
#       128     invalid exit argument
#       255     program was not executed or exit signal has been received

# see also https://tldp.org/LDP/abs/html/exitcodes.html



set -o errexit   # abort on nonzero exitstatus; also see https://stackoverflow.com/a/11231970
set -o nounset   # abort on unbound variable
set -o pipefail  # don't hide errors within pipes
source "./mount-utils.sh"
ORIGINAL_PWD="$PWD"



# ---- UTILS ----

is_temp_mount() {
    [[ ! ${CUSTOM_MOUNTPOINT+1} ]];
}


# by default, the script should not terminate from signals
for ((i=0; i<40; i++)); do
    trap : $i
done
# terminate from these signals
for signal in TERM INT QUIT KILL HUP PIPE; do
    trap "exit 255" $signal
done



# ---- PARSE ARGUMENTS ----

# (no longer) adapted from https://stackoverflow.com/a/14203146

RCLONE_ARGS=()
while [[ (($# > 0)) && $1 != "--" ]]; do
    case "$1" in
        "--mountpoint")
            if [[ ! ${2+1} ]]; then echo "ERROR: must specify mountpoint"; exit 255; fi
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

if (($# < 2)); then echo "ERROR: Expected at least 2 positional arguments, but $# where given"; exit 255; fi
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
# retval is either set by an 'exit' statement, or is 255 because a signal handler was called.
exit_handler () {
    retval=$?
    # disable exit on failure
    set +o errexit
    echo ""

    if [[ ${IS_LAUNCHED+1} ]]; then
        if ((retval==255)); then
            # either the program exited with code 255 or a signal handler was called
            echo "WARN: program either finished with code 255 or has been aborted"
        else
            # program exited
            # exit code will be either program exit code or special exit code like 126, 127 or 128
            echo "program has finished with code $retval"
        fi
    else
        # program was not launched
        if ((retval==0)); then
            # this means that exit 0 was called before the program was started, which should NOT happen
            echo "ERROR: program was not launched"
        elif ((retval==255)); then
            echo "ERROR: program was not launched: received exit signal"
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
        if [[ ${MOUNT_PID+1} ]]; then
            stop_mount $MOUNT_PID "$MOUNT_PATH" &&
            delete_mount_dir
        fi
    } || { err; return 1; }
    return 0
}



delete_mount_dir () {
    # when mount could not be unmounted, rm might fail
    if is_temp_mount; then
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
        echo "ERROR: mountpoint does not exist"
        exit 255
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
wait_mount $MOUNT_PID "$MOUNT_PATH"

# successfully mounted
# do not allow empty mount dir
# this happens e.g. when rclone mounts an invalid path
if [[ ! "$(ls -A "$MOUNT_PATH")" ]]; then
    # empty
    echo "ERROR: mount is empty"
    exit 255
fi
echo "mount successful"





# ---- RUNNING THE PROGRAM  ----
echo "launching $PROGRAM_PATH"
echo ""

# process should be able to access the original working directory (where this script was executed in)
export ORIGINAL_PWD
# working directory for process is the mount folder
cd "$MOUNT_PATH"
IS_LAUNCHED=1
"$PROGRAM_PATH" "$@" && true
# if both this script and the program receive a signal, then once the program terminates, the script signal handler is called
# it thus does not matter what the program does or what it returns
# if only the program receives a signal, then either a) the program handles it and exits, which is just like a normal exit,
# or b) it notifies its parent (i.e. this script) about it, which then calls its script handler
exit $?
