# Maintaining and Releasing Driver Images

This guide is for maintainers who publish driver images for new Flatcar releases or new NVIDIA driver and CUDA
versions.

## Where versions are defined

| What | Where | Used by |
|---|---|---|
| NVIDIA driver versions (one per datacenter branch) | `DRIVER_VERSIONS` in `Makefile` | CI, `make build` |
| CUDA base image version | `CUDA_VERSION` in `Makefile` | CI, `make build` |
| Flatcar releases with precompiled images | `FLATCAR_VERSIONS` in `Makefile` | CI |
| Defaults for a plain `docker build` | `ARG CUDA_VERSION`, `ARG DRIVER_VERSION`, `ARG FLATCAR_VERSION` in `Dockerfile` | `build.sh`, manual builds |
| Tested drivers, examples | `README.md` | users |

The `Makefile` is the source of truth for CI. Keep the `Dockerfile` defaults and the README in sync with it.

## How CI builds images

- Every push builds dev images with a `dev-<sha8>-` tag prefix, e.g.
  `ghcr.io/flatcar/driver:dev-1266c695-595-6.12.113-flatcar-flatcar0`.
- A published GitHub Release builds the release tags without prefix.
- For each Flatcar release in `FLATCAR_VERSIONS`, the `devcontainer` workflow first imports the Flatcar developer
  container into `ghcr.io/flatcar/flatcar-devcontainer:<VERSION_ID>` (skipped if it already exists). Then one
  precompiled image is built per driver version and Flatcar release.
- One generic image is built per driver version.

Each image gets a tag for the driver branch and one for the full driver version:

| Image | Tags |
|---|---|
| precompiled | `595-6.12.113-flatcar-flatcar0`, `595.71.05-6.12.113-flatcar-flatcar0` |
| generic | `595-flatcar0`, `595.71.05-flatcar0` |

The kernel version in the tag (`6.12.113-flatcar`) is read from the Flatcar release
(`flatcar_production_image_kernel_config.txt`); every Flatcar release ships a new kernel.

## New Flatcar release

Nodes running a Flatcar release without a precompiled image cannot start the driver (`ImagePullBackOff`), so publish
the image **before** clusters update their nodes. New releases are listed at <https://www.flatcar.org/releases>
(JSON feed: `https://www.flatcar.org/releases-json/releases-<channel>.json`).

1. Add the new `VERSION_ID` to `FLATCAR_VERSIONS` in the `Makefile`. Remove releases that are no longer in use;
   their published images stay in the registry.
2. Push the change and check that the `image` workflow succeeds, including `devcontainer / import (<version>)` and
   `precompiled-flatcar (<driver>, <version>)`.
3. Test the dev image on a node with the new release (see [Testing](#testing)).
4. Publish the release tags, either by creating a GitHub Release, or without a release via **Actions → image → Run
   workflow** with `flatcar_versions` set to the new release and `release` checked.

## New NVIDIA driver version

Only NVIDIA **datacenter** drivers are supported, see <https://docs.nvidia.com/datacenter/tesla/>.

1. Check that the driver is published at
   `https://us.download.nvidia.com/tesla/<version>/NVIDIA-Linux-x86_64-<version>.run`.
2. Check that the CUDA repository for Ubuntu 24.04 has `nvidia-fabricmanager` and `libnvidia-nscq` in exactly
   this version. The build pins them and fails otherwise:
   ```bash
   docker run --rm nvidia/cuda:13.2.1-base-ubuntu24.04 \
     sh -c 'apt-get update -qq && apt-cache madison nvidia-fabricmanager libnvidia-nscq | grep <version>'
   ```
3. In `DRIVER_VERSIONS`, replace the previous version of the same branch (e.g. `595.71.05` → `595.x.y`). Add a new
   branch or remove a branch that reached end of life.
4. Update `ARG DRIVER_VERSION` in the `Dockerfile` if the newest branch changed, and the list of tested drivers in the
   `README.md`.
5. Push, test the dev images (see [Testing](#testing)), then publish a GitHub Release.

Clusters using the branch tag (`driver.version: "595"`) get the new version when the driver pods restart
(`imagePullPolicy: Always`). The driver DaemonSets use `OnDelete`, so restart them with
`kubectl -n gpu-operator delete pods -l app=nvidia-driver-daemonset` (this unloads the driver; drain GPU workloads
first).

Notes:

- NVIDIA ships parts of the open kernel modules as prebuilt objects. The build log therefore contains many objtool
  warnings `'naked' return found in MITIGATION_RETHUNK build`; these are expected
  ([NVIDIA/open-gpu-kernel-modules#1077](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1077)).
- With driver branch 615 and newer, check `dmesg` for `Unpatched return thunk in use` after loading the driver
  (reported upstream in the same issue).

## New CUDA version

`CUDA_VERSION` only selects the base image `nvidia/cuda:<CUDA_VERSION>-base-ubuntu24.04`. The driver libraries come
from the NVIDIA driver package, so the CUDA version does not limit which driver versions can be built.

1. Check that the tag exists on [Docker Hub](https://hub.docker.com/r/nvidia/cuda/tags?name=base-ubuntu24.04).
2. Update `CUDA_VERSION` in the `Makefile` and `ARG CUDA_VERSION` in the `Dockerfile`.
3. Push, test the dev images, then publish a GitHub Release.

## Testing

Test on a cluster with GPU nodes using the GPU Operator installation from the README, with
`driver.repository`/`driver.version` pointing to the dev images (e.g. `driver.version: dev-<sha8>-595`). Test both
`driver.usePrecompiled: true` and `false`.

- [ ] Driver pods are `Running`, the logs show `Found precompiled NVIDIA kernel modules for <kernel>` (precompiled)
      and contain no errors.
- [ ] `nvidia-cuda-validator` pods are `Completed`; nodes report the expected `nvidia.com/gpu` count.
- [ ] A CUDA sample passes (`nvcr.io/nvidia/k8s/cuda-sample:vectoradd-cuda12.5.0`, see README).
- [ ] On NVSwitch systems (e.g. HGX H100), `nvidia-smi -q` reports `Fabric` `State: Completed`, `Status: Success`.
- [ ] `dmesg` on the node contains no `return thunk` warnings and no GSP firmware errors.
- [ ] If possible, nodes with different Flatcar releases get one driver DaemonSet per kernel.
