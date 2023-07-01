#!/bin/bash

# POSITIONAL ARGUMENTS
#   1..--       mount command with MOUNTPOINT instead of actual mountpoint
#   --..     program path and arguments

# EXIT CODES
#   In general, the exit code of the program is returned.
#   However, the following exit codes can also be returned under other circumstances:
#       126     cannot execute program
#       127     program was not found
#       128     invalid exit argument
#       255     error occurred or received exit signal

# see also https://tldp.org/LDP/abs/html/exitcodes.html



set -o errexit   # abort on nonzero exitstatus; also see https://stackoverflow.com/a/11231970
set -o nounset   # abort on unbound variable
set -o pipefail  # don't hide errors within pipes
set -o errtrace
source "./mount-utils.sh"
ORIGINAL_PWD="$PWD"
MOUNTPOINT_PLACEHOLDER="MOUNTPOINT"



# ---- UTILS ----


is_temp_mount() {
    [[ ! ${CUSTOM_MOUNTPOINT+1} ]];
}


# by default, the script should not terminate from signals
for ((i=0; i<100; i++)); do
    trap : $i 2>/dev/null && true
done
# terminate from these signals
for signal in TERM INT QUIT KILL HUP PIPE; do
    trap "exit 255" $signal
done



# ---- PARSE ARGUMENTS ----

# (no longer) adapted from https://stackoverflow.com/a/14203146

MOUNT_CMD=()
while [[ (($# > 0)) && $1 != "--" ]]; do
    case "$1" in
        "--mountpoint")
            if [[ ! ${2+1} ]]; then echo "ERROR: must specify mountpoint"; exit 255; fi
            CUSTOM_MOUNTPOINT="$2"
            shift
            shift
            ;;
        "--allow-empty")
            ALLOW_EMPTY="true"
            shift
            ;;
        *)
            MOUNT_CMD+=("$1")
            shift
            ;;
    esac
done

if ((${#MOUNT_CMD[@]} == 0)); then echo "ERROR: missing mount command"; exit 255; fi

if (($# == 0)); then echo "ERROR: missing -- delimiter"; exit 255; fi
# remove -- delimiter
shift

if (($# == 0)); then echo "ERROR: missing program path"; exit 255; fi

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
# NOTE: if interrupt signal is received during cleanup, signal handler is called again, but does not call exit handler

exit_handler () {
    retval=$1

    # define handler for when cleanup fails
    # note that it is not possible trap EXIT inside of exit handler
    err_handler () {
        echo "ERROR: cleanup failed" >&2 && true
        exit 255
    }
    trap err_handler ERR

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
    cleanup
    exit $retval
}


cleanup () {
    if [[ ${MOUNT_PID+1} ]]; then
        stop_mount $MOUNT_PID "$MOUNTPOINT"
        delete_mount_dir
    fi
}

delete_mount_dir () {
    # when mount could not be unmounted, rm might fail
    if is_temp_mount; then
        rm -d "$MOUNTPOINT"
        if (($?>0)); then echo "ERROR: could not delete temporary mount folder"; return 1; fi
    fi
    return 0
}


# must always exit with 0 to not overwrite exit code of left pipe part
# $1: file descriptor
fd_wrapper () {
    # ignore all signals
    for ((i=0; i<100; i++)); do
        trap : $i 2>/dev/null && true
    done
    # redirect stdin to file descriptor
    # nothing happens if file descriptor is invalid
    while IFS= read -r line; do
        echo "FOO $1  $line" >&$1 2>/dev/null && true
    done
    exit 0
}



# if stdout or stderr are not connected anymore at some point in this script,
# then SIGPIPE is received, which leads to the script exiting with 255.
# however, the exit handler contains 'echo' calls, which would fail
# we thus connect stdout and stderr of the exit handler to a safety wrapper

safe_exit_handler () {
    retval=$?
    cd "$ORIGINAL_PWD"

    # we want to keep stdout and stderr separate AND we want to keep the order
    # however, if stdout and stderr are written to separate processes, then race condition can happen and the order is not preserved
    # thus: if stdout and stderr point to same thing, use only one safety wrapper
    # otherwise order does not matter and we can use two wrappers
    if [[ "$(readlink /proc/$$/fd/1)" == "$(readlink /proc/$$/fd/2)" ]]; then
        # stdout and stderr are the same, merge them
        # pipe exits with exit code of exit_handler because we set pipefail and fd_wrapper exits with 0
        exit_handler $retval 2>&1 | fd_wrapper 1
    else
        # stdout and stderr are different, keep them separate
        exit_handler $retval 1> >(fd_wrapper 1) 2> >(fd_wrapper 2)
    fi

    # obsolete, but keep for safety
    exit 255
}

trap safe_exit_handler EXIT









# ---- MOUNTING ----

if is_temp_mount; then
    echo "mounting in temporary folder"
else
    echo "mounting in $CUSTOM_MOUNTPOINT"
fi

# create mount folder
if is_temp_mount; then
    MOUNTPOINT="$(mktemp -d)"
else
    if [[ ! -d $CUSTOM_MOUNTPOINT ]]; then
        echo "ERROR: mountpoint does not exist"
        exit 255
    fi
    MOUNTPOINT="$CUSTOM_MOUNTPOINT"
fi

# replace mount point placeholder with actual mount point
is_set="false"
for i in "${!MOUNT_CMD[@]}"; do
   if [[ "${MOUNT_CMD[$i]}" == "$MOUNTPOINT_PLACEHOLDER" ]]; then
       MOUNT_CMD[$i]="$MOUNTPOINT"
       is_set="true"
   fi
done
if [[ $is_set == "false" ]]; then echo "ERROR: command does not contain $MOUNTPOINT_PLACEHOLDER placeholder"; exit 255; fi

# launch mount command as daemon, but keep stdout connected to current terminal
setsid "${MOUNT_CMD[@]}" &
MOUNT_PID=$!

# wait until mount becomes available
wait_mount $MOUNT_PID "$MOUNTPOINT"

# successfully mounted
# do not allow empty mount dir
# this happens e.g. when rclone mounts an invalid path
if [[ ! ${ALLOW_EMPTY+1} && ! "$(ls -A "$MOUNTPOINT")" ]]; then
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
cd "$MOUNTPOINT"
IS_LAUNCHED=1
"$PROGRAM_PATH" "$@" && true
# if both this script and the program receive a signal, then once the program terminates, the script signal handler is called
# it thus does not matter what the program does or what it returns
# if only the program receives a signal, then either a) the program handles it and exits, which is just like a normal exit,
# or b) it notifies its parent (i.e. this script) about it, which then calls its script handler
exit $?
