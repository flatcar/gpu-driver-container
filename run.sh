#!/bin/bash

set -xeuo pipefail

: "${DRIVER_VERSION:="$(sed -n 's/^ARG DRIVER_VERSION=//p' Dockerfile)"}"
: "${IMAGE_NAME:=ghcr.io/flatcar/driver}"
. /etc/os-release

# Remove a stopped update container left over from update.sh; fails if it is still running.
if docker container inspect nvidia-driver > /dev/null 2>&1; then
    docker rm nvidia-driver
fi
docker run -d --privileged --pid=host \
     -v /run/nvidia:/run/nvidia:shared \
     -v /var/log:/var/log \
     -v /dev/log:/dev/log \
     -v /etc/os-release:/host-etc/os-release \
     --name nvidia-driver \
     "${IMAGE_NAME}:${DRIVER_VERSION}-flatcar${VERSION_ID}"
