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
| cusparselt| 0.6.2.3+others |        | 0.6.3.2     | `.ci/docker/common/install_cuda.sh` |
| libcudss  | 0.3.0.9        |        | 0.4.0.2     | `.ci/docker/common/install_cudss.sh`|
| magma     | 2.6.1          |        | 2.8.0       | `.ci/docker/common/instal_magma.sh` |
| libabseil | indirect?      |        | 20240722.0  |                                     |
| libuv     |                |        | 1.49.2      | (not pinned)                        |
| mkl       | 2024.2.0       | <2024  | 2023.2.0    | `.ci/docker/common/install_mkl.sh`  |
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
| triton    | 3.1.0          | 3.1.0  | 3.1.0       | (wheel metadata)                    |


Maintenance notes
=================

Packages built by the recipe
----------------------------
The recipe currently builds three packages:

1. `libtorch` that installs the common libraries, executables and data files
   that are independent of selected Python version and are therefore shared
   by all Python versions.

2. `pytorch` that installs the library and other files for a specific Python
   version.

3. `pytorch-cpu` or `pytorch-gpu` backwards compatibility metapackage.

These packages can be built in the following variants:

- `cpu` variant that does not use CUDA, or `cuda` variant built using
  specific CUDA version.

- `mkl` variant that uses MKL to provide BLAS/LAPACK, as well as a set
  of additional functions, and `generic` variant that can use any BLAS/LAPACK
  provider (created by patching on OpenBLAS support upstream).

Some of the platforms support only a subset of these variants.

The recipe supports a `megabuild` mode that is currently used for Linux
configurations. In this mode, PyTorch is built for all Python versions
in a single run. As a result, the shared bits (`libtorch*`) are only built once.

As the `megabuild` mode imposes high disk space requirements on the CI builders,
and more importantly, cannot be built within the 6h time limit imposed by azure,
it is not used on other platforms currently. For this reason, there are separate
configurations for every Python version there.


The build process
-----------------
The upstream build system consists of a heavily customize `setup.py` script,
based on the setuptools build system that performs some preparations related
to building C++ code and then calls into CMake to build it (i.e. it's not
suitable to use CMake directly). The build process can be customized using
environment variables, some of them processed directly by the setup script,
others converted into `-D` options for CMake. When looking for available
options, `setup.py` and `tools/setup_helpers/cmake.py` are the two primary
files to look at.

Normally, the setup code only runs the `cmake` generate step if `CMakeCache.txt`
does not exist yet. Therefore, on subsequent calls environment variables do not
affect the CMake build. It is technically possible to force rerunning it via
appending `--cmake` option, but that usually causes the build system to consider
all targets out of date, and therefore rebuild everything from scratch. Instead,
we are editing `CMakeCache.txt` directly, therefore triggering the build step
to detect changes and regenerate.

To facilitate split package builds, we perform the build in the following steps:

1. For the top-level rule (`libtorch`), we perform the base environment setup
   and run `setup.py build` to build the libraries, collect the data files
   and install the common parts corresponding to the `libtorch` package.

   a. If `megabuild` is enabled, we build against a fixed Python version.
      Otherwise, we build using the final Python version.

2. For the `pytorch` package(s), we invoke `pip install` to build and install
   the complete package. Importantly, this reuses previously built targets,
   so only Python-related bits are rebuilt. In `megabuild` mode, we patch
   `CMakeCache.txt` to set the correct Python version.


Speeding up development builds
==============================
Building PyTorch can take significant time. This can be especially problematic
when working on the recipe, as that may require rebuilding it multiple times.
This section provides a few hints that can be used to speed this up, saving
both time and resources.


Using ccache
------------
PyTorch supports using `ccache` to copy C, C++ and CUDA compilation results
to a disk cache. In a subsequent build, if the source files match the cached
result, ccache can retrieve it immediately without having to call the compiler
again. With an up-to-date cache, the compilation step can be shortened
to a few minutes.

Furthermore, ccache can also speed up sequential builds of different package
variants. Since large parts of the shared code do not change between different
variants, ccache can reuse large parts of the previous cached compilations
and recompile only files that are actually different.

The simplest way of using ccache is to run `conda-build` directly
in an environment where ccache is installed. Start by installing ccache:

```
$ conda install ccache
```

Configure ccache by creating `~/.config/ccache/ccache.conf` file.
The recommended configuration follows:

```
compiler_check = none
compression = true
sloppiness = pch_defines,time_macros
hash_dir = false
base_dir = /var/tmp/conda-bld
max_size = 6G
```

This example uses `/var/tmp/conda-bld` as the top directory for all conda
builds. Replace it with the directory you are going to use. See `man ccache`
for more options.

Afterwards, run build by calling `conda-build` directly, e.g.:

```
$ conda build --no-build-id --croot /var/tmp/conda-bld -m .ci_support/linux_64_blas_implmklc_compiler_version13cuda_compilercuda-nvcccuda_compiler_version12.6cxx_compiler_version13.yaml --clobber-file .ci_support/linux_64_blas_implmklc_compiler_version13cuda_compilercuda-nvcccuda_compiler_version12.6cxx_compiler_version13.yaml .
```

Note that it is important to specify `--croot` as the same directory
as ccache's `base_dir`, and to use `--no-build-id` to avoid path variation.

PyTorch's CMake automatically detects and uses `ccache`.


Limiting CUDA targets
---------------------
Normally, CUDA-enabled versions of PyTorch are compiled for a wide range
of GPUs. This causes every CUDA compilation to take significant amounts
of time and space. For testing purposes, you may want to instead change
the list to a single GPU. For example, if you are using a sm75 GPU, you
can change `TORCH_CUDA_ARCH_LIST` in the build script to:

```
export TORCH_CUDA_ARCH_LIST="7.5"
```


Limiting Python targets (for megabuild)
---------------------------------------
While megabuild generally saves time by reusing the same base build for
multiple Python targets, building and testing for multiple versions of Python
can significantly slow up development builds. If you don't need to do that,
you can edit the generated `*.yaml` file in `.ci_support`, and remove
the entries for `python` versions you don't need. Note that Python versions
are zipped to `numpy` versions, so you'll have to remove them in pairs.
