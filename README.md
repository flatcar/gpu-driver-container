# NVIDIA Drivers and Flatcar Container Linux

[Flatcar Container Linux](https://kinvolk.io/flatcar-container-linux/) is a Linux distribution designed for container workloads. 
To provide better security, Flatcar is immutable and contains minimal tools to run container workloads. This repository contains code to be able to build and provision NVIDIA drivers for Flatcar Linux through the use of containers. The NVIDIA driver container takes care of building the NVIDIA kernel modules and optionally loading them for running CUDA workloads. Together with the [NVIDIA Container Toolkit](https://github.com/NVIDIA/nvidia-docker), also provisioned using a container, you can start running GPU accelerated containers on Flatcar Linux. 

## Prerequisites

The NVIDIA driver has a dependency on the following modules: `i2c_core` and `ipmi_msghandler`. For convenience, these modules can be 
configured to be loaded at reboot.

```bash
$ sudo modprobe -a i2c_core ipmi_msghandler \
    && echo -e "i2c_core\nipmi_msghandler" | sudo tee /etc/modules-load.d/driver.conf
```

If you're getting started with Flatcar on EC2, then Flatcar images for various regions can be found here:
https://kinvolk.io/docs/flatcar-container-linux/latest/installing/cloud/aws-ec2/

## Supported Drivers

The following NVIDIA datacenter drivers have been tested with this container on Flatcar (kernel 6.12+):
1. `580.159.04`
1. `595.71.05`

Other datacenter driver versions from the [NVIDIA driver downloads](https://www.nvidia.com/en-us/drivers/) are expected to work as
long as they support the running kernel.

Only the NVIDIA open GPU kernel modules are used, so NVIDIA datacenter GPUs based on Turing+ architecture (e.g. T4, A100, L40S,
H100) are supported; older GPUs such as P100 or V100 are not. On NVSwitch based 
systems (e.g. HGX/DGX A100, H100, H200) the driver container ships the NVIDIA Fabric Manager and NSCQ library and starts the 
Fabric Manager automatically when NVSwitch devices are detected (`/proc/driver/nvidia-nvswitch/devices`); this has been verified 
on HGX H100 8-GPU systems. Note that NVLink5+ systems (e.g. GB200 NVL) additionally require the NVLink Subnet Manager, which is 
not yet included.

## Getting Started

Setup the NVIDIA Container Toolkit using the [container-config](https://gitlab.com/nvidia/container-toolkit/container-config) project:
```bash
$ docker run --rm --privileged \
     -v "/etc/docker:/etc/docker" \
     -v "/run/nvidia:/run/nvidia" \
     -v "/run/docker.sock:/run/docker.sock" \
     -v "/opt/nvidia-runtime:/opt/nvidia-runtime" \
     -e "RUNTIME=docker" \
     -e "RUNTIME_ARGS=--socket /run/docker.sock" \
     -e "DOCKER_SOCKET=/run/docker.sock" \
     nvcr.io/nvidia/k8s/container-toolkit:1.4.7-ubuntu18.04 \
     "/opt/nvidia-runtime"
```
You should see an output as shown below:
```console
time="2021-04-06T06:54:23Z" level=info msg="Setting up runtime"
time="2021-04-06T06:54:23Z" level=info msg="Starting 'setup' for docker"
time="2021-04-06T06:54:23Z" level=info msg="Parsing arguments: [/opt/nvidia-runtime/toolkit]"
time="2021-04-06T06:54:23Z" level=info msg="Successfully parsed arguments"
time="2021-04-06T06:54:23Z" level=info msg="Loading config: /etc/docker/daemon.json"
time="2021-04-06T06:54:23Z" level=info msg="Config file does not exist, creating new one"
time="2021-04-06T06:54:23Z" level=info msg="Flushing config"
time="2021-04-06T06:54:23Z" level=info msg="Successfully flushed config"
time="2021-04-06T06:54:23Z" level=info msg="Sending SIGHUP signal to docker"
time="2021-04-06T06:54:23Z" level=info msg="Signal received, exiting early"
time="2021-04-06T06:54:23Z" level=info msg="Shutting Down"
```

Restart `docker` to ensure that `nvidia` is added as a custom runtime:
```bash
$ sudo systemctl restart docker
$ docker info | grep -i nvidia
 Runtimes: nvidia runc
 Default Runtime: nvidia
```

The `container-config` would have also created a `daemon.json` for Docker in `/etc/docker/daemon.json` with the `nvidia` runtime binaries being located in the directory specified (`/opt/nvidia-runtime` in our example).

## Building the Driver Images

The `Dockerfile` has two targets, both built with the Makefile:

- **generic** (`<driver>-flatcar0`): compiles the NVIDIA open kernel modules at runtime against the
  kernel build tree of the running Flatcar host. Works on any Flatcar release, startup takes a few minutes.
- **precompiled** (`<driver>-<kernel>-flatcar0`, e.g. `595-6.12.113-flatcar-flatcar0`): the modules are built
  at image build time inside the
  [Flatcar developer container](https://www.flatcar.org/docs/latest/devguide/kernel-modules/) of that release, i.e.
  with the exact compiler and kernel build tree Flatcar uses. The image contains no compiler or kernel sources and
  only starts on nodes running exactly that kernel build (`/proc/version`); on any other kernel it exits with an
  error.

`<driver>` is both the driver branch (e.g. `595`) and the full driver version (e.g. `595.71.05`). Every Flatcar
release ships a new kernel, so `<kernel>` identifies the Flatcar release, e.g. `6.12.113-flatcar` for 4757.2.2 and
`6.12.114-flatcar` for 4757.2.3 (see `Linux` in the [release notes](https://www.flatcar.org/releases)).

```bash
$ git clone https://github.com/flatcar/gpu-driver-container.git \
    && cd gpu-driver-container

# generic image
$ make build-595.71.05

# precompiled image for Flatcar 4757.2.2
$ FLATCAR_VERSION=4757.2.2 make build-precompiled-595.71.05
```

The precompiled build uses `ghcr.io/flatcar/flatcar-devcontainer:<VERSION_ID>` by default (`DEVCONTAINER_IMAGE`).
Flatcar publishes the developer container only as a disk image, so it is converted into a container image with
`import-devcontainer.sh`, which verifies the release signature against the Flatcar image signing key
(`flatcar-image-signing-key.asc`). In CI this is done by the `devcontainer` workflow. To build locally against a
locally imported developer container:

```bash
$ ./import-devcontainer.sh 4757.2.2
$ FLATCAR_VERSION=4757.2.2 DEVCONTAINER_IMAGE=flatcar-devcontainer:4757.2.2 PULL= \
    make build-precompiled-595.71.05
```

The driver container logs show which path is used:

```console
========== NVIDIA Software Installer ==========
Starting installation of NVIDIA driver version 595.71.05 for Linux kernel version 6.12.113-flatcar
Stopping NVIDIA persistence daemon...
Unloading NVIDIA driver kernel modules...
Unmounting NVIDIA driver rootfs...
Checking NVIDIA driver packages...
Found precompiled NVIDIA kernel modules for 6.12.113-flatcar
Loading kernel module dependencies on the host...
Installing precompiled NVIDIA driver kernel modules...
Installing NVIDIA GSP firmware into /lib/firmware/nvidia/595.71.05...
Mounting NVIDIA driver rootfs...
Loading NVIDIA driver kernel modules...
Starting NVIDIA persistence daemon...
Done, now waiting for signal
```

## Deploying the Driver with the GPU Operator

The images are deployed with the [NVIDIA GPU Operator](https://github.com/NVIDIA/gpu-operator) and Helm.

### Image tag convention

The GPU Operator composes the driver image reference as:

```
<driver.repository>/<driver.image>:<driver.version>-<osTag>                    # usePrecompiled=false
<driver.repository>/<driver.image>:<driver.version>-<kernel-version>-<osTag>   # usePrecompiled=true
```

`osTag` is `<ID><VERSION_ID>` of a GPU node, and the operator reads it from a single node for the whole cluster.
With Flatcar's per-release `VERSION_ID` this picks the wrong image while nodes run different Flatcar releases, e.g.
during updates ([NVIDIA/gpu-operator#1622](https://github.com/NVIDIA/gpu-operator/issues/1622)). Like
[Garden Linux](https://github.com/gardenlinux/gardenlinux-nvidia-installer), a Node Feature Discovery rule therefore
sets `VERSION_ID` to `0` on Flatcar nodes, which makes `osTag` the constant `flatcar0`. With `usePrecompiled=true`
the operator creates one driver DaemonSet per kernel version, so each node gets the image for its Flatcar release.

### Installation

```yaml
# values.yaml
driver:
  repository: ghcr.io/flatcar
  image: driver
  version: "595"
  usePrecompiled: true # false for the generic image
  imagePullPolicy: Always
toolkit:
  installDir: /opt/nvidia-runtime
node-feature-discovery:
  worker:
    config:
      sources:
        custom:
          - name: flatcar-version
            labelsTemplate: |
              {{ range .system.osrelease }}feature.node.kubernetes.io/system-os_release.VERSION_ID=0
              {{ end }}
            matchFeatures:
              - feature: system.osrelease
                matchExpressions:
                  ID: {op: In, value: ["flatcar"]}
```

```bash
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update

helm install gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator --create-namespace \
  --values values.yaml
```

Notes:

- `toolkit.installDir=/opt/nvidia-runtime` is **required on Flatcar**: the default
  install path `/usr/local/nvidia` is on a read-only filesystem and the container
  toolkit pods will fail with `CreateContainerError` otherwise.
- A precompiled image must exist for the kernel of every GPU node. Publish it before
  updating nodes to a new Flatcar release; otherwise the driver pod stays in
  `ImagePullBackOff` and has to be deleted once the image is available.
- If the image is in a private registry, create a pull secret in the `gpu-operator`
  namespace and add `--set driver.imagePullSecrets[0]=<secret-name>`.

### Verification

1. Wait for the driver pods and check that the precompiled package is used (no runtime
   compilation):

   ```bash
   kubectl -n gpu-operator logs -l app=nvidia-driver-daemonset | grep -E "precompiled NVIDIA"
   ```

   Expected output:

   ```
   Found precompiled NVIDIA kernel modules for 6.12.113-flatcar
   Installing precompiled NVIDIA driver kernel modules...
   ```

   If the driver pod instead exits with `This image contains NVIDIA kernel modules for: ...`,
   the node runs a different kernel build than the image was built for.

1. Confirm the driver is loaded:

   ```bash
   POD=$(kubectl -n gpu-operator get pods -l app=nvidia-driver-daemonset -o name | head -1)
   kubectl -n gpu-operator exec "$POD" -- nvidia-smi
   ```

1. On NVSwitch based systems (e.g. HGX H100 8-GPU), confirm the Fabric Manager started and the
   fabric is initialized:

   ```bash
   kubectl -n gpu-operator logs -l app=nvidia-driver-daemonset | grep "fabric manager"
   # Starting NVIDIA fabric manager daemon...

   kubectl -n gpu-operator exec "$POD" -- nvidia-smi -q | grep -A2 "^    Fabric"
   #     Fabric
   #         State  : Completed
   #         Status : Success
   ```

1. Confirm the whole stack converges — all pods `Running` and the CUDA validators
   `Completed`:

   ```bash
   kubectl -n gpu-operator get pods
   ```

### Reinstalling from scratch

If you delete the `gpu-operator` namespace without `helm uninstall`, cluster-scoped
leftovers block a fresh installation. Clean them up first:

```bash
kubectl delete clusterpolicy cluster-policy
kubectl delete clusterrole,clusterrolebinding gpu-operator \
  gpu-operator-node-feature-discovery gpu-operator-node-feature-discovery-gc
kubectl delete crd nodefeatures.nfd.k8s-sigs.io nodefeaturerules.nfd.k8s-sigs.io \
  nodefeaturegroups.nfd.k8s-sigs.io clusterpolicies.nvidia.com nvidiadrivers.nvidia.com
```

### Switching to a new driver image

To roll out a newly built image without reinstalling:

```bash
kubectl patch clusterpolicy cluster-policy --type merge \
  -p '{"spec":{"driver":{"version":"<driver>"}}}'
kubectl -n gpu-operator delete pods -l app=nvidia-driver-daemonset
```

When enabling the NFD rule on an existing installation, the operator keeps the driver
DaemonSets created for the previous `osTag` (e.g. `nvidia-driver-daemonset-<kernel>-flatcar4757.2.2`).
Delete them once the nodes carry `feature.node.kubernetes.io/system-os_release.VERSION_ID=0`.

## Sample CUDA Workloads

Now we can run some sample CUDA workloads. 

1. Run `nvidia-smi`
    ```bash
    $ docker run --runtime=nvidia nvidia/cuda:11.0-base nvidia-smi
    
    +-----------------------------------------------------------------------------+
    | NVIDIA-SMI 460.32.03    Driver Version: 460.32.03    CUDA Version: 11.2     |
    |-------------------------------+----------------------+----------------------+
    | GPU  Name        Persistence-M| Bus-Id        Disp.A | Volatile Uncorr. ECC |
    | Fan  Temp  Perf  Pwr:Usage/Cap|         Memory-Usage | GPU-Util  Compute M. |
    |                               |                      |               MIG M. |
    |===============================+======================+======================|
    |   0  Tesla T4            On   | 00000000:00:1E.0 Off |                    0 |
    | N/A   30C    P8     9W /  70W |      0MiB / 15109MiB |      0%      Default |
    |                               |                      |                  N/A |
    +-------------------------------+----------------------+----------------------+
    
    +-----------------------------------------------------------------------------+
    | Processes:                                                                  |
    |  GPU   GI   CI        PID   Type   Process name                  GPU Memory |
    |        ID   ID                                                   Usage      |
    |=============================================================================|
    |  No running processes found                                                 |
    +-----------------------------------------------------------------------------+        
    ```

1. Run a sample CUDA program:
    ```bash
    $ docker run --runtime=nvidia nvidia/samples:vectoradd-cuda11.2.1

    [Vector addition of 50000 elements]
    Copy input data from the host memory to the CUDA device
    CUDA kernel launch with 196 blocks of 256 threads
    Copy output data from the CUDA device to the host memory
    Test PASSED
    Done    
    ```

1. Generate a deterministic FP16 GEMM on the GPU using the Tensor Cores if available:
    ```bash
    $ docker run --runtime=nvidia \
        --cap-add SYS_ADMIN \
        nvidia/samples:dcgmproftester-2.0.10-cuda11.0-ubuntu18.04 \
        --no-dcgm-validation -t 1004 -d 30

    Skipping CreateDcgmGroups() since DCGM validation is disabled
    CU_DEVICE_ATTRIBUTE_MAX_THREADS_PER_MULTIPROCESSOR: 1024
    CU_DEVICE_ATTRIBUTE_MULTIPROCESSOR_COUNT: 40
    CU_DEVICE_ATTRIBUTE_MAX_SHARED_MEMORY_PER_MULTIPROCESSOR: 65536
    CU_DEVICE_ATTRIBUTE_COMPUTE_CAPABILITY_MAJOR: 7
    CU_DEVICE_ATTRIBUTE_COMPUTE_CAPABILITY_MINOR: 5
    CU_DEVICE_ATTRIBUTE_GLOBAL_MEMORY_BUS_WIDTH: 256
    CU_DEVICE_ATTRIBUTE_MEMORY_CLOCK_RATE: 5001000
    Max Memory bandwidth: 320064000000 bytes (320.06 GiB)
    CudaInit completed successfully.
    
    Skipping WatchFields() since DCGM validation is disabled
    TensorEngineActive: generated ???, dcgm 0.000 (26723.0 gflops)
    TensorEngineActive: generated ???, dcgm 0.000 (27450.3 gflops)
    TensorEngineActive: generated ???, dcgm 0.000 (27520.2 gflops)
    TensorEngineActive: generated ???, dcgm 0.000 (27386.5 gflops)
    TensorEngineActive: generated ???, dcgm 0.000 (27294.1 gflops)
    TensorEngineActive: generated ???, dcgm 0.000 (27304.2 gflops)
    TensorEngineActive: generated ???, dcgm 0.000 (27220.1 gflops)
    TensorEngineActive: generated ???, dcgm 0.000 (27193.2 gflops)
    TensorEngineActive: generated ???, dcgm 0.000 (27139.5 gflops)
    TensorEngineActive: generated ???, dcgm 0.000 (27125.2 gflops)
    TensorEngineActive: generated ???, dcgm 0.000 (26985.2 gflops)
    TensorEngineActive: generated ???, dcgm 0.000 (27282.3 gflops)
    TensorEngineActive: generated ???, dcgm 0.000 (27413.9 gflops)
    TensorEngineActive: generated ???, dcgm 0.000 (27366.0 gflops)
    TensorEngineActive: generated ???, dcgm 0.000 (27378.1 gflops)
    TensorEngineActive: generated ???, dcgm 0.000 (27244.6 gflops)    
        ```
