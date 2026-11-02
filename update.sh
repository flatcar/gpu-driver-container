#!/bin/bash

set -xeuo pipefail

: "${DRIVER_VERSION:="$(sed -n 's/^ARG DRIVER_VERSION=//p' Dockerfile)"}"
: "${IMAGE_NAME:=ghcr.io/flatcar/driver}"
: "${FLATCAR_VERSION:="$(. /etc/os-release; echo "${VERSION_ID}")"}"

docker rm -f nvidia-driver
docker run -it --privileged --pid=host \
    --entrypoint nvidia-driver \
    -v /run/nvidia:/run/nvidia:shared \
    -v /var/log:/var/log \
    -v /dev/log:/dev/log \
    --name nvidia-driver \
    "${IMAGE_NAME}:${DRIVER_VERSION}-flatcar" update -f "${FLATCAR_VERSION}"
