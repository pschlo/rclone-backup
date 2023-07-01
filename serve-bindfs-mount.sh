#!/bin/bash

source ./serve-custom-mount.sh
./serve-mount.sh bindfs -f "$SOURCE_PATH" MOUNTPOINT "$@"
