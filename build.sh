#!/bin/bash

set -xeuo pipefail

: ${DRIVER_VERSION:="$(sed -n "s/^ARG DRIVER_VERSION=//p" Dockerfile)"}

docker build --pull \
    --tag nvidia/nvidia-driver-flatcar:${DRIVER_VERSION} \
    --file Dockerfile .
docker tag nvidia/nvidia-driver-flatcar:${DRIVER_VERSION} nvidia/nvidia-driver-flatcar:latest
