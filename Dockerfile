ARG CUDA_VERSION=13.2.1
FROM nvidia/cuda:${CUDA_VERSION}-base-ubuntu24.04 AS build

ENV NVIDIA_VISIBLE_DEVICES=void

ARG TARGETARCH
ENV TARGETARCH=$TARGETARCH

SHELL ["/bin/bash", "-c"]

RUN echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections

RUN if [ "$TARGETARCH" = "amd64" ]; then \
        echo "deb [arch=amd64] http://archive.ubuntu.com/ubuntu/ jammy main universe" > /etc/apt/sources.list && \
        echo "deb [arch=amd64] http://archive.ubuntu.com/ubuntu/ jammy-updates main universe" >> /etc/apt/sources.list && \
        echo "deb [arch=amd64] http://archive.ubuntu.com/ubuntu/ jammy-security main universe" >> /etc/apt/sources.list && \
        usermod -o -u 0 -g 0 _apt ; \
    elif [ "$TARGETARCH" = "arm64" ]; then \
        echo "deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports jammy main universe" > /etc/apt/sources.list && \
        echo "deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports jammy-updates main universe" >> /etc/apt/sources.list && \
        echo "deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports jammy-security main universe" >> /etc/apt/sources.list && \
        usermod -o -u 0 -g 0 _apt ; \
    else \
        echo "TARGETARCH doesn't match a known arch target" ; \
        exit 1 ; \
    fi

RUN if [ "$TARGETARCH" = "amd64" ]; then dpkg --add-architecture i386 ; fi && \
    apt-get update && apt-get install -y --no-install-recommends \
        apt-transport-https \
        apt-utils \
        bc \
        binutils \
        build-essential \
        ca-certificates \
        curl \
        gcc-14 \
        gnupg2 \
        jq \
        kmod \
        libelf-dev \
        libssl-dev \
        patchelf \
        pahole \
        file \
        fdisk \
        software-properties-common && \
    rm -rf /var/lib/apt/lists/*

RUN curl -fsSL --retry 5 --retry-delay 5 --retry-all-errors -o /usr/local/bin/donkey https://github.com/3XX0/donkey/releases/download/v1.1.0/donkey && \
    curl -fsSL --retry 5 --retry-delay 5 --retry-all-errors -o /usr/local/bin/extract-vmlinux https://raw.githubusercontent.com/torvalds/linux/master/scripts/extract-vmlinux && \
    chmod +x /usr/local/bin/donkey /usr/local/bin/extract-vmlinux

ARG BASE_URL=https://us.download.nvidia.com/tesla
ARG DRIVER_VERSION=580.95.05
ENV DRIVER_VERSION=$DRIVER_VERSION
ENV DEBIAN_FRONTEND=noninteractive

# Install the userspace components and copy the kernel module sources.
RUN cd /tmp && \
    DRIVER_ARCH="$TARGETARCH" && DRIVER_ARCH=${DRIVER_ARCH/amd64/x86_64} && DRIVER_ARCH=${DRIVER_ARCH/arm64/aarch64} && \
    curl -fSsl --retry 5 --retry-delay 5 --retry-all-errors -O $BASE_URL/$DRIVER_VERSION/NVIDIA-Linux-$DRIVER_ARCH-$DRIVER_VERSION.run && \
    sh NVIDIA-Linux-${DRIVER_ARCH}-$DRIVER_VERSION.run -x && \
    cd NVIDIA-Linux-${DRIVER_ARCH}-$DRIVER_VERSION*/ && \
    ./nvidia-installer --silent \
                       --no-kernel-module \
                       --install-compat32-libs \
                       --no-nouveau-check \
                       --no-nvidia-modprobe \
                       --no-rpms \
                       --no-backup \
                       --no-check-for-alternate-installs \
                       --no-libglx-indirect \
                       --no-install-libglvnd \
                       --x-prefix=/tmp/null \
                       --x-module-path=/tmp/null \
                       --x-library-path=/tmp/null \
                       --x-sysconfig-path=/tmp/null && \
    mkdir -p /usr/src/nvidia-$DRIVER_VERSION && \
    mv LICENSE mkprecompiled kernel /usr/src/nvidia-$DRIVER_VERSION && \
    sed '9,${/^\(kernel\|LICENSE\)/!d}' .manifest > /usr/src/nvidia-$DRIVER_VERSION/.manifest && \
    rm -rf /tmp/*

# Install fabric manager and NSCQ for NVSwitch based systems (e.g. HGX/DGX A100, H100, H200).
# Newer CUDA base images ship the cuda-keyring package (repo list is a dpkg conffile —
# do NOT delete it, reinstalling the same version won't restore it). Older images ship
# a bare cuda.list without signed-by, which conflicts with cuda-keyring; only in that
# case remove it and install the keyring.
# NVIDIA publishes fabric manager and NSCQ in lockstep with each datacenter driver
# release (versions.mk only tracks such versions), so pin the exact driver version
# and fail fast if it is missing. Packages are branch-suffixed below branch 580.
RUN OS_ARCH=${TARGETARCH/amd64/x86_64} && OS_ARCH=${OS_ARCH/arm64/sbsa} && \
    if ! dpkg -s cuda-keyring > /dev/null 2>&1; then \
        rm -f /etc/apt/sources.list.d/cuda*.list && \
        curl -fsSL --retry 5 --retry-delay 5 --retry-all-errors -o /tmp/cuda-keyring.deb \
            https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/${OS_ARCH}/cuda-keyring_1.1-1_all.deb && \
        dpkg -i /tmp/cuda-keyring.deb && rm -f /tmp/cuda-keyring.deb ; \
    fi && \
    apt-get update && \
    DRIVER_BRANCH=${DRIVER_VERSION%%.*} && \
    if [ "$DRIVER_BRANCH" -ge 580 ]; then \
        FM_PKG=nvidia-fabricmanager NSCQ_PKG=libnvidia-nscq ; \
    else \
        FM_PKG=nvidia-fabricmanager-${DRIVER_BRANCH} NSCQ_PKG=libnvidia-nscq-${DRIVER_BRANCH} ; \
    fi && \
    apt-get install -y --no-install-recommends "${FM_PKG}=${DRIVER_VERSION}*" "${NSCQ_PKG}=${DRIVER_VERSION}*" && \
    apt-mark hold "${FM_PKG}" "${NSCQ_PKG}" && \
    rm -rf /var/lib/apt/lists/*

COPY nvidia-driver /usr/local/bin

WORKDIR /usr/src/nvidia-$DRIVER_VERSION

ARG PUBLIC_KEY=empty
COPY ${PUBLIC_KEY} kernel/pubkey.x509

# Add NGC DL license from the CUDA image
RUN mkdir /licenses && mv /NGC-DL-CONTAINER-LICENSE /licenses/NGC-DL-CONTAINER-LICENSE

ENV CC=gcc-14

# When FLATCAR_VERSION is set, build the kernel modules for that Flatcar release
# at image build time and pack them as a precompiled package, so no compilation
# happens at runtime. When unset, a generic image is built and the modules are
# compiled at runtime for the running kernel.
ARG FLATCAR_VERSION
ENV FLATCAR_VERSION=$FLATCAR_VERSION
RUN if [ -n "$FLATCAR_VERSION" ]; then \
        CREATE_PRECOMPILED_PACKAGE=true nvidia-driver update -f "$FLATCAR_VERSION" ; \
    fi

ENTRYPOINT ["nvidia-driver", "init"]
