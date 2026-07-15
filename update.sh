#!/bin/bash

set -x

FLATCAR=3815.2.0
docker rm -f nvidia-driver
docker run -it --privileged --pid=host \
    --entrypoint nvidia-driver \
    -v /run/nvidia:/run/nvidia:shared \
    -v /var/log:/var/log \
    -v /dev/log:/dev/log \
    --name nvidia-driver \
    nvidia/nvidia-driver-flatcar:latest update -f ${FLATCAR}
