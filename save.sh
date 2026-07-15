#!/bin/bash

set -xeuo pipefail

: ${DRIVER_VERSION:="$(sed -n "s/^ARG DRIVER_VERSION=//p" Dockerfile)"}
. /etc/os-release

docker commit \
    --change='ENTRYPOINT ["nvidia-driver", "init"]' \
    nvidia-driver nvidia/nvidia-flatcar-${VERSION_ID}:${DRIVER_VERSION}
