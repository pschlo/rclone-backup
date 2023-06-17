#!/bin/bash

export RESTIC_REPOSITORY="$1"

restic backup "."