#!/bin/bash

source ./serve-custom-mount.sh
./serve-mount.sh rclone mount "$SOURCE_PATH" MOUNTPOINT --read-only "$@"
