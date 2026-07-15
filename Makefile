DOCKER ?= docker

# DRIVER_VERSIONS contains the latest version of each active datacenter branch.
DRIVER_VERSIONS ?= 580.167.08 595.71.05
CUDA_VERSION ?= 13.2.1

REGISTRY ?= ghcr.io/flatcar
IMAGE_NAME ?= $(REGISTRY)/driver

# VERSION optionally prefixes the image tag (e.g. VERSION=dev-abc12345 for dev builds).
# Release tags follow the GPU Operator scheme:
#   generic:     <driver-version>-flatcar
#   precompiled: <driver-version>-flatcar<flatcar-version>
VERSION ?=
TAG_PREFIX = $(if $(VERSION),$(VERSION)-)

PLATFORM ?= linux/amd64
PUSH_ON_BUILD ?= false
DOCKER_BUILD_OPTIONS ?= --output=type=image,push=$(PUSH_ON_BUILD)

BUILD_TARGETS := $(patsubst %,build-%,$(DRIVER_VERSIONS))
PRECOMPILED_TARGETS := $(patsubst %,build-precompiled-%,$(DRIVER_VERSIONS))

.PHONY: build build-precompiled $(BUILD_TARGETS) $(PRECOMPILED_TARGETS)

# Generic images: kernel modules are compiled at runtime for the running kernel.
build: $(BUILD_TARGETS)

$(BUILD_TARGETS): build-%:
	$(DOCKER) buildx build --pull \
		$(DOCKER_BUILD_OPTIONS) \
		--platform=$(PLATFORM) \
		--tag $(IMAGE_NAME):$(TAG_PREFIX)$*-flatcar \
		--build-arg DRIVER_VERSION="$*" \
		--build-arg CUDA_VERSION="$(CUDA_VERSION)" \
		$(CURDIR)

# Precompiled images: kernel modules for a specific Flatcar release are built and
# packed at image build time. Requires FLATCAR_VERSION (a Flatcar VERSION_ID).
build-precompiled: $(PRECOMPILED_TARGETS)

$(PRECOMPILED_TARGETS): build-precompiled-%:
	@test -n "$(FLATCAR_VERSION)" || { echo "FLATCAR_VERSION must be set (e.g. FLATCAR_VERSION=4593.2.0)"; exit 1; }
	$(DOCKER) buildx build --pull \
		$(DOCKER_BUILD_OPTIONS) \
		--platform=$(PLATFORM) \
		--tag $(IMAGE_NAME):$(TAG_PREFIX)$*-flatcar$(FLATCAR_VERSION) \
		--build-arg DRIVER_VERSION="$*" \
		--build-arg CUDA_VERSION="$(CUDA_VERSION)" \
		--build-arg FLATCAR_VERSION="$(FLATCAR_VERSION)" \
		$(CURDIR)
