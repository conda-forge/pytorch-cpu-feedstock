Building pytorch packages locally
=================================
To build a conda pytorch package with GPU support you can use docker and the
`build-locally.py` script.

1. Install docker. Ensure that the following command succeeds:

```bash
docker run hello-world
```

2. Build a specific version with the command
```bash
python build-locally.py
```

3. Generally speaking, this package takes too long to compile on any of our CI
  resources. One should follow CFEP-03 to package this feedstock.

The following script may help build all cuda version sequentially:
```bash
#!/usr/env/bin bash

set -ex

docker system prune --force
configs=$(find .ci_support/ -type f -name 'linux_*' -printf "%p ")
# configs=$(find .ci_support/ -type f -name '*cuda_compiler_version[^nN]*' -printf "%p ")

# Assuming a powerful enough machine with many cores
# 10 seems to be a good point where things don't run out of RAM too much.
export CPU_COUNT=10

mkdir -p build_artifacts

for config_filename in $configs; do
    filename=$(basename ${config_filename})
    config=${filename%.*}
    if [ -f build_artifacts/conda-forge-build-done-${config} ]; then
        echo skipped $config
        continue
    fi

    python build-locally.py $config | tee build_artifacts/${config}-log.txt
    # docker images get quite big clean them up after each build to save your disk....
    docker system prune --force
done

zip build_artifacts/log_files.zip build_artifacts/*-log.txt
```


Checking dependency versions against upstream git
=================================================
For vendored dependencies, the easiest way to obtain dependency versions
is to run:

```console
$ git submodule update --init --recursive
$ git submodule status --recursive
 7e1e1fe3858c63c251c637ae41a20de425dde96f android/libs/fbjni (v0.1.0-12-g7e1e1fe)
 4dfe081cf6bcd15db339cf2680b9281b8451eeb3 third_party/FP16 (4dfe081)
 b408327ac2a15ec3e43352421954f5b1967701d1 third_party/FXdiv (b408327)
 c07e3a0400713d546e0dea2d5466dd22ea389c73 third_party/NNPACK (c07e3a0)
 e170594ac7cf1dac584da473d4ca9301087090c1 third_party/NVTX (v3.1.0)
 a6bfc237255a6bac1513f7c1ebde6d8aed6b5191 third_party/VulkanMemoryAllocator (v2.1.0-705-ga6bfc23)
...
```

Whenever possible, it will describe the used commit using a version tag.

For Python dependencies, the specific pins can be found
in `*.dist-info/METADATA` inside the wheel. For non-Python dependencies,
CI scripts can be inspected.

The following table summarizes versions used in 2.5.1 (`+` indicates
additional commits on top of the tag), and conda-forge matches as
of 2024-11-28:

| Package   | Upstream       | Recipe | Conda-forge | Source                              |
|-----------|----------------|--------|-------------|-------------------------------------|
| cuda      | 11.8/12.1/12.4 | 12.6   | 12.6        | `.ci/docker/build.sh`               |
| magma     | 2.6.1          |        | 2.8.0       | `.ci/docker/common/instal_magma.sh` |
| libabseil | indirect?      |        | 20240722.0  |                                     |
| libuv     |                |        | 1.49.2      | (not pinned)                        |
| mkl       | 2024.2.0       |        | 2024.2.2    | `.ci/docker/common/install_mkl.sh`  |
| nccl      | 2.21.5+        |        | 2.23.4.1    | `third_party/nccl/nccl`             |
| protobuf  | 3.7.0rc2+      |        | 5.28.2      | `third_party/protobuf`              |
| sleef     | 3.6+           |        | 3.7         | `third_party/sleef`                 |
| filelock  |                |        | 3.16.1      | (wheel metadata)                    |
| fsspec    |                |        | 2024.10.0   | (wheel metadata)                    |
| jinja2    |                |        | 3.1.4       | (wheel metadata)                    |
| networkx  |                |        | 3.4.2       | (wheel metadata)                    |
| numpy     | (2.0.2 for build) | *   | 2.1.3       | `.ci/pytorch/build.sh`              |
| pyyaml    | mixed pins     |        | 6.0.2       |                                     |
| requests  | mixed pins     |        | 2.32.3      |                                     |
| six       | 1.11.0         |        | 1.16.0      | `third_party/NNPACK/cmake/DownloadSix.cmake` |
| sympy     | ==1.13.1       | >=1.13.1, !=1.13.2 | 1.13.3 | (wheel metadata)             |
| typing-extensions | >=4.8.0 |       | 4.12.2      | (wheel metadata)                    |
| triton    | 3.1.0          | none   | 3.1.0       | (wheel metadata)                    |
