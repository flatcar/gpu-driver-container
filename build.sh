#!/bin/bash

set -xeuo pipefail

: "${DRIVER_VERSION:="$(sed -n 's/^ARG DRIVER_VERSION=//p' Dockerfile)"}"
: "${IMAGE_NAME:=ghcr.io/flatcar/driver}"

docker build --pull \
    --build-arg DRIVER_VERSION="${DRIVER_VERSION}" \
    --tag "${IMAGE_NAME}:${DRIVER_VERSION}-flatcar" \
    --file Dockerfile .
