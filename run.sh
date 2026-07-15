#!/bin/bash

set -xeuo pipefail

: ${DRIVER_VERSION:="$(sed -n "s/^ARG DRIVER_VERSION=//p" Dockerfile)"}
. /etc/os-release

docker run -d --privileged --pid=host \
     -v /run/nvidia:/run/nvidia:shared \
     -v /var/log:/var/log \
     -v /dev/log:/dev/log \
     -v /etc/os-release:/host-etc/os-release \
     --name nvidia-driver \
     nvidia/nvidia-flatcar-${VERSION_ID}:${DRIVER_VERSION}
