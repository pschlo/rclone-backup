#!/bin/bash

# this is a convenience script that creates a simple backup of a remote path

# PARAMETERS
#   1: rclone remote path
#   2: restic repository path

if (($# != 2)); then echo "ERROR: Expected 2 positional arguments, but $# where given"; exit 1; fi

./wrap-rclone-mount.sh "$1" restic -r "$2" backup "."
