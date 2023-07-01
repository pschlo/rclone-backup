#!/bin/bash

SCRIPT_PATH="$(realpath "$0")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"


# get options
OPTIONS=()
while [[ (($# > 0)) && $1 != "--" ]]; do
    OPTIONS+=("$1")
    shift
done

# remove -- delimiter
if (($# == 0)); then
    # delimiter missing; restore arguments
    set -- "${OPTIONS[@]}"
    OPTIONS=()
else
    shift
fi

# get source
if (($# == 0)); then echo "ERROR: missing source"; exit 1; fi
SOURCE="$1"
shift

# get program code
if (($# == 0)); then echo "ERROR: missing program command"; exit 1; fi
PROGRAM_CMD=("$@")


serve_mount () {
    "$SCRIPT_DIR"/serve-mount "${OPTIONS[@]}" "$@" -- "${PROGRAM_CMD[@]}"
}
