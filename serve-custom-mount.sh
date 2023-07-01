#!/bin/bash


if (($# < 2)); then echo "ERROR: Expected at least 2 positional arguments, but $# where given"; exit 255; fi
SOURCE_PATH="$1"  # path on source, e.g. server
shift

found="false"
for i in "$@"; do [[ "$i" == "--" ]] && found="true"; done
if [[ $found == "false" ]]; then set -- "--" "$@"; fi