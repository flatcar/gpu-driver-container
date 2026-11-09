ARG CUDA_VERSION=13.2.1
ARG DRIVER_VERSION=595.71.05
# Only used by the precompiled target, see import-devcontainer.sh.
ARG FLATCAR_VERSION=4757.2.2
ARG DEVCONTAINER_IMAGE=ghcr.io/flatcar/flatcar-devcontainer:${FLATCAR_VERSION}

FROM nvidia/cuda:${CUDA_VERSION}-base-ubuntu24.04 AS base

ENV NVIDIA_VISIBLE_DEVICES=void

ARG TARGETARCH
ENV TARGETARCH=$TARGETARCH

SHELL ["/bin/bash", "-c"]

RUN echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections

RUN if [ "$TARGETARCH" = "amd64" ]; then \
        echo "deb [arch=amd64] http://archive.ubuntu.com/ubuntu/ noble main universe" > /etc/apt/sources.list && \
        echo "deb [arch=amd64] http://archive.ubuntu.com/ubuntu/ noble-updates main universe" >> /etc/apt/sources.list && \
        echo "deb [arch=amd64] http://archive.ubuntu.com/ubuntu/ noble-security main universe" >> /etc/apt/sources.list && \
        usermod -o -u 0 -g 0 _apt ; \
    elif [ "$TARGETARCH" = "arm64" ]; then \
        echo "deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports noble main universe" > /etc/apt/sources.list && \
        echo "deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports noble-updates main universe" >> /etc/apt/sources.list && \
        echo "deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports noble-security main universe" >> /etc/apt/sources.list && \
        usermod -o -u 0 -g 0 _apt ; \
    else \
        echo "TARGETARCH doesn't match a known arch target" ; \
        exit 1 ; \
    fi

RUN if [ "$TARGETARCH" = "amd64" ]; then dpkg --add-architecture i386 ; fi && \
    apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        kmod && \
    rm -rf /var/lib/apt/lists/*

ARG DRIVER_VERSION
ENV DRIVER_VERSION=$DRIVER_VERSION
ENV DEBIAN_FRONTEND=noninteractive

FROM base AS source

ARG BASE_URL=https://us.download.nvidia.com/tesla

RUN cd /tmp && \
    DRIVER_ARCH="$TARGETARCH" && DRIVER_ARCH=${DRIVER_ARCH/amd64/x86_64} && DRIVER_ARCH=${DRIVER_ARCH/arm64/aarch64} && \
    curl -fSsl --retry 5 --retry-delay 5 --retry-all-errors -O $BASE_URL/$DRIVER_VERSION/NVIDIA-Linux-$DRIVER_ARCH-$DRIVER_VERSION.run && \
    sh NVIDIA-Linux-${DRIVER_ARCH}-$DRIVER_VERSION.run -x && \
    mv NVIDIA-Linux-${DRIVER_ARCH}-$DRIVER_VERSION /src && \
    rm -f NVIDIA-Linux-${DRIVER_ARCH}-$DRIVER_VERSION.run

FROM base AS runtime

# Install the userspace components and keep the open kernel module sources and GSP firmware.
RUN --mount=type=bind,from=source,source=/src,target=/tmp/nvidia,rw \
    cd /tmp/nvidia && \
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
    mv LICENSE kernel-open firmware /usr/src/nvidia-$DRIVER_VERSION && \
    sed '9,${/^\(kernel-open\|firmware\|LICENSE\)/!d}' .manifest > /usr/src/nvidia-$DRIVER_VERSION/.manifest && \
    find /tmp -mindepth 1 -maxdepth 1 ! -name nvidia -exec rm -rf {} +

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

# Add NGC DL license from the CUDA image
RUN mkdir /licenses && mv /NGC-DL-CONTAINER-LICENSE /licenses/NGC-DL-CONTAINER-LICENSE

ENTRYPOINT ["nvidia-driver", "init"]

# Build the kernel modules with the toolchain and kernel build tree of the target Flatcar release.
FROM ${DEVCONTAINER_IMAGE} AS modules

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

ARG FLATCAR_VERSION

COPY --from=source /src/kernel-open /tmp/kernel-open

RUN . /usr/share/flatcar/release && \
    if [ "${FLATCAR_RELEASE_VERSION}" != "${FLATCAR_VERSION}" ]; then \
        echo "Developer container is ${FLATCAR_RELEASE_VERSION}, expected ${FLATCAR_VERSION}" >&2; exit 1; \
    fi && \
    KERNEL_VERSION=$(ls /usr/lib/modules) && \
    KERNEL_BUILD=/usr/lib/modules/${KERNEL_VERSION}/build && \
    cd /tmp/kernel-open && \
    make -s -j"$(nproc)" CC=x86_64-cros-linux-gnu-gcc SYSSRC="${KERNEL_BUILD}" modules > /dev/null && \
    mkdir -p "/out/${KERNEL_VERSION}" && \
    cp nvidia.ko nvidia-modeset.ko nvidia-uvm.ko nvidia-peermem.ko "/out/${KERNEL_VERSION}/" && \
    case "${FLATCAR_VERSION}" in *.2.*) channel=stable ;; *.1.*) channel=beta ;; *) channel=alpha ;; esac && \
    curl -fsSL --retry 3 -o /tmp/vmlinuz \
        "https://${channel}.release.flatcar-linux.net/${FLATCAR_RELEASE_BOARD}/${FLATCAR_VERSION}/flatcar_production_image.vmlinuz" && \
    # Only the real banner carries a build number ("#1 SMP"); it must equal /proc/version on the host.
    { "${KERNEL_BUILD}/scripts/extract-vmlinux" /tmp/vmlinuz | strings | \
        grep -m1 -E "^Linux version ${KERNEL_VERSION} .*#[0-9]+ SMP " > "/out/${KERNEL_VERSION}/proc-version" || true; } && \
    test -s "/out/${KERNEL_VERSION}/proc-version" && \
    cat "/out/${KERNEL_VERSION}/proc-version"

# Kernel modules for one Flatcar release, no compiler or kernel sources.
FROM runtime AS precompiled

COPY --from=modules /out /usr/src/nvidia-${DRIVER_VERSION}/precompiled

# Compiles the kernel modules at runtime for the running Flatcar kernel.
FROM runtime AS generic

RUN apt-get update && apt-get install -y --no-install-recommends \
        bc \
        binutils \
        build-essential \
        gcc-14 \
        libelf-dev \
        libssl-dev \
        patchelf \
        pahole && \
    rm -rf /var/lib/apt/lists/*

ENV CC=gcc-14
