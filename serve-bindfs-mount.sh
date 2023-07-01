#!/bin/bash

SCRIPT_PATH="$(realpath "$0")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

source "$SCRIPT_DIR"/serve-custom-mount.sh
"$SCRIPT_DIR"/serve-mount.sh bindfs -f "$SOURCE_PATH" MOUNTPOINT "$@"
