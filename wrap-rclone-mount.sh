#!/bin/bash

# POSITIONAL ARGUMENTS
#   1: rclone remote path, e.g. my_onedrive:foo/bar
#   2: program path

# OPTIONAL ARGUMENTS
#   --config    rclone config path. Default is default rclone config.

# ENVIRONMENT VARIABLES
#   RCLONE_CONFIG


set -o errexit   # abort on nonzero exitstatus; also see https://stackoverflow.com/a/11231970
set -o nounset   # abort on unbound variable
set -o pipefail  # don't hide errors within pipes


# ---- UTILS ----

SECONDS=1000
# current timestamp in milliseconds; see https://serverfault.com/a/151112
timestamp_ms () {
    echo $(($(date +%s%N)/1000000))
}







# ---- PARSE ARGUMENTS ----

# adapted from https://stackoverflow.com/a/14203146

POSITIONAL_ARGS=()
is_pos_args="false"

while (($# > 0)); do
    # we have already seen a positional arg
    # everything following will also be parsed as positional arg
    if [[ $is_pos_args == "true" ]]; then
        POSITIONAL_ARGS+=("$1") # save positional arg
        shift # past argument
        continue
    fi
    # we have not yet seen a positional arg
    case "$1" in
        -c|--config)
            RCLONE_CONF="$2"
            shift # past argument
            shift # past value
            ;;
        -*|--*)
            echo "ERROR: Unknown option $1"
            exit 1
            ;;
        *)
            # found positional arg
            is_pos_args="true"
            ;;
    esac
done

# parse positional arguments

set -- "${POSITIONAL_ARGS[@]}" # restore positional parameters
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
    set +o errexit
    echo "cleaning up"
    if [[ ${MOUNT_PID+1} ]]; then unmount; fi
    # when mount process was killed, rm might fail
    if [[ ${MOUNT_PATH+1} ]]; then
        rm -d "$MOUNT_PATH"
        if (($?>0)); then echo "ERROR: could not delete mount folder"; exit 1; fi
    fi

    set -o errexit
}


# requires MOUNT_PID to be set
unmount () {
    is_alive() { ps -p $MOUNT_PID >/dev/null; }
    is_mounted() { mountpoint -q "$MOUNT_PATH"; }

    if is_mounted; then
        umount "$MOUNT_PATH" 2>/dev/null
        if (($? > 0)); then
            echo "unmounting failed"
            echo "killing mount process"
            kill $MOUNT_PID
        fi
    else
        # not mounted, either because not YET mounted or because of failure
        is_alive && kill $MOUNT_PID
    fi

    # wait for TIMEOUT_MS millisecods for the mount process to terminate
    TIMEOUT_MS=10000
    t0=$(timestamp_ms)
    is_timeout() { (($(timestamp_ms)-t0 >= TIMEOUT_MS)); }

    while is_alive && ! is_timeout; do sleep 0.1; done
    if is_alive; then echo "ERROR: Could not terminate mount process"; exit 1; fi
    return 0
}

trap cleanup EXIT

# create mount folder
MOUNT_PATH="$(mktemp -d)"








# ---- MOUNTING ----

echo "mounting remote $SOURCE_PATH"

# launch fuse mount daemon

args=()
if [[ ${RCLONE_CONF+1} ]]; then
    args+=("--config" "$RCLONE_CONF")
fi
args+=("--read-only" "$SOURCE_PATH" "$MOUNT_PATH")

setsid rclone mount "${args[@]}" &
MOUNT_PID=$!

# wait until mount becomes available
# abort after TIMEOUT_MS milliseconds
TIMEOUT_MS=$((10*SECONDS))
t0=$(timestamp_ms)
is_alive() { ps -p $MOUNT_PID >/dev/null; }
is_mounted() { mountpoint -q "$MOUNT_PATH"; }
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
