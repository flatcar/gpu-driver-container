#!/bin/bash

set -xeuo pipefail

: "${DRIVER_VERSION:="$(sed -n 's/^ARG DRIVER_VERSION=//p' Dockerfile)"}"
: "${IMAGE_NAME:=ghcr.io/flatcar/driver}"
. /etc/os-release

docker commit \
    --change='ENTRYPOINT ["nvidia-driver", "init"]' \
    nvidia-driver "${IMAGE_NAME}:${DRIVER_VERSION}-flatcar${VERSION_ID}"
docker rm nvidia-driver
