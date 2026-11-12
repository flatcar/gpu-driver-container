DOCKER ?= docker

# DRIVER_VERSIONS contains the latest version of each active datacenter branch.
DRIVER_VERSIONS ?= 580.167.08 595.71.05
CUDA_VERSION ?= 13.2.1

REGISTRY ?= ghcr.io/flatcar
IMAGE_NAME ?= $(REGISTRY)/driver

# VERSION optionally prefixes the image tag (e.g. VERSION=dev-abc12345 for dev builds).
# Tags follow the GPU Operator scheme, each for the driver branch and the full driver version:
#   generic:     <driver>-<OS_TAG>               (driver.usePrecompiled=false)
#   precompiled: <driver>-<kernel>-<OS_TAG>      (driver.usePrecompiled=true)
VERSION ?=
TAG_PREFIX = $(if $(VERSION),$(VERSION)-)
# Constant OS tag; requires the NFD rule from the README that sets VERSION_ID=0 on Flatcar nodes.
OS_TAG ?= flatcar0
BOARD ?= amd64-usr
branch = $(firstword $(subst ., ,$(1)))

PLATFORM ?= linux/amd64
PUSH_ON_BUILD ?= false
DOCKER_BUILD_OPTIONS ?= --output=type=image,push=$(PUSH_ON_BUILD)
# Links the image to its repository on ghcr.io.
SOURCE_URL ?= https://github.com/flatcar/gpu-driver-container
# Set PULL= to build against a locally imported developer container.
PULL ?= --pull

# Flatcar developer container with the matching kernel toolchain (see import-devcontainer.sh).
DEVCONTAINER_IMAGE ?= $(REGISTRY)/flatcar-devcontainer:$(FLATCAR_VERSION)

BUILD_TARGETS := $(patsubst %,build-%,$(DRIVER_VERSIONS))
PRECOMPILED_TARGETS := $(patsubst %,build-precompiled-%,$(DRIVER_VERSIONS))

.PHONY: build build-precompiled $(BUILD_TARGETS) $(PRECOMPILED_TARGETS)

# Generic images: kernel modules are compiled at runtime for the running kernel.
build: $(BUILD_TARGETS)

$(BUILD_TARGETS): build-%:
	$(DOCKER) buildx build $(PULL) \
		$(DOCKER_BUILD_OPTIONS) \
		--platform=$(PLATFORM) \
		--target generic \
		--tag $(IMAGE_NAME):$(TAG_PREFIX)$(call branch,$*)-$(OS_TAG) \
		--tag $(IMAGE_NAME):$(TAG_PREFIX)$*-$(OS_TAG) \
		--label org.opencontainers.image.source="$(SOURCE_URL)" \
		--build-arg DRIVER_VERSION="$*" \
		--build-arg CUDA_VERSION="$(CUDA_VERSION)" \
		$(CURDIR)

# Precompiled images: kernel modules for a specific Flatcar release are built at image
# build time in the Flatcar developer container. Requires FLATCAR_VERSION (a Flatcar VERSION_ID).
build-precompiled: $(PRECOMPILED_TARGETS)

$(PRECOMPILED_TARGETS): build-precompiled-%:
	@test -n "$(FLATCAR_VERSION)" || { echo "FLATCAR_VERSION must be set (e.g. FLATCAR_VERSION=4757.2.2)"; exit 1; }
	case "$(FLATCAR_VERSION)" in *.2.*) channel=stable ;; *.1.*) channel=beta ;; *) channel=alpha ;; esac && \
	kernel=$$(curl -fsSL --retry 3 "https://$${channel}.release.flatcar-linux.net/$(BOARD)/$(FLATCAR_VERSION)/flatcar_production_image_kernel_config.txt" | \
		sed -n 's/^# Linux\/[^ ]* \([^ ]*\) Kernel Configuration$$/\1/p') && \
	test -n "$${kernel}" && \
	$(DOCKER) buildx build $(PULL) \
		$(DOCKER_BUILD_OPTIONS) \
		--platform=$(PLATFORM) \
		--target precompiled \
		--tag $(IMAGE_NAME):$(TAG_PREFIX)$(call branch,$*)-$${kernel}-$(OS_TAG) \
		--tag $(IMAGE_NAME):$(TAG_PREFIX)$*-$${kernel}-$(OS_TAG) \
		--label org.opencontainers.image.source="$(SOURCE_URL)" \
		--build-arg DRIVER_VERSION="$*" \
		--build-arg CUDA_VERSION="$(CUDA_VERSION)" \
		--build-arg FLATCAR_VERSION="$(FLATCAR_VERSION)" \
		--build-arg KERNEL_VERSION="$${kernel}" \
		--build-arg DEVCONTAINER_IMAGE="$(DEVCONTAINER_IMAGE)" \
		$(CURDIR)
