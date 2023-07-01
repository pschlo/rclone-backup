#!/bin/bash

SCRIPT_PATH="$(realpath "$0")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

source "$SCRIPT_DIR"/serve-custom-mount.sh
"$SCRIPT_DIR"/serve-mount.sh rclone mount "$SOURCE_PATH" MOUNTPOINT --read-only "$@"
