#!/bin/bash


if (($# < 2)); then echo "ERROR: Expected at least 2 positional arguments, but $# where given"; exit 255; fi
SOURCE_PATH="$1"  # path on source, e.g. server
shift

# check if -- is contained in args
found="false"
for i in "$@"; do
    if [[ "$i" == "--" ]]; then
        found="true"
        break
    fi
done

# add -- if not contained
if [[ $found == "false" ]]; then
    set -- "--" "$@"
fi