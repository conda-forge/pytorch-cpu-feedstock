#!/bin/bash

echo "=== Building ${PKG_NAME} (py: ${PY_VER}) ==="

set -ex

echo "####################################################################"
echo "Building PyTorch using BLAS implementation: $blas_impl              "
echo "####################################################################"

# This is used to detect if it's in the process of building pytorch
export IN_PYTORCH_BUILD=1

# https://github.com/conda-forge/pytorch-cpu-feedstock/issues/243
# https://github.com/pytorch/pytorch/blob/v2.3.1/setup.py#L341
export PACKAGE_TYPE=conda

# remove pyproject.toml to avoid installing deps from pip
rm -rf pyproject.toml

# uncomment to debug cmake build
# export CMAKE_VERBOSE_MAKEFILE=1

export USE_CUFILE=0
export USE_NUMA=0
export USE_ITT=0

#################### ADJUST COMPILER AND LINKER FLAGS #####################
# Pytorch's build system doesn't like us setting the c++ standard and will
# issue a warning:
# https://github.com/pytorch/pytorch/blob/3beb7006dd5a415dfa236081ad5d55ae38346324/CMakeLists.txt#L41
export CXXFLAGS="$(echo $CXXFLAGS | sed 's/-std=c++[0-9][0-9]//g')"
# The below three lines expose symbols that would otherwise be hidden or
# optimised away. They were here before, so removing them would potentially
# break users' programs
export CFLAGS="$(echo $CFLAGS | sed 's/-fvisibility-inlines-hidden//g')"
export CXXFLAGS="$(echo $CXXFLAGS | sed 's/-fvisibility-inlines-hidden//g')"
export LDFLAGS="$(echo $LDFLAGS | sed 's/-Wl,--as-needed//g')"
# The default conda LDFLAGs include -Wl,-dead_strip_dylibs, which removes all the
# MKL sequential, core, etc. libraries, resulting in a "Symbol not found: _mkl_blas_caxpy"
# error on osx-64.
export LDFLAGS="$(echo $LDFLAGS | sed 's/-Wl,-dead_strip_dylibs//g')"
export LDFLAGS_LD="$(echo $LDFLAGS_LD | sed 's/-dead_strip_dylibs//g')"
if [[ "$c_compiler" == "clang" ]]; then
    export CXXFLAGS="$CXXFLAGS -Wno-deprecated-declarations -Wno-unknown-warning-option -Wno-error=unused-command-line-argument -Wno-error=vla-cxx-extension"
    export CFLAGS="$CFLAGS -Wno-deprecated-declarations -Wno-unknown-warning-option -Wno-error=unused-command-line-argument -Wno-error=vla-cxx-extension"
else
    export CXXFLAGS="$CXXFLAGS -Wno-deprecated-declarations -Wno-error=maybe-uninitialized"
    export CFLAGS="$CFLAGS -Wno-deprecated-declarations -Wno-error=maybe-uninitialized"
fi

# This is not correctly found for linux-aarch64 since pytorch 2.0.0 for some reason
export _GLIBCXX_USE_CXX11_ABI=1

if [[ "$target_platform" == "osx-64" ]]; then
  export CXXFLAGS="$CXXFLAGS -DTARGET_OS_OSX=1"
  export CFLAGS="$CFLAGS -DTARGET_OS_OSX=1"
fi

# Dynamic libraries need to be lazily loaded so that torch
# can be imported on system without a GPU
LDFLAGS="${LDFLAGS//-Wl,-z,now/-Wl,-z,lazy}"

################ CONFIGURE CMAKE FOR CONDA ENVIRONMENT ###################
export CMAKE_GENERATOR=Ninja
export CMAKE_LIBRARY_PATH=$PREFIX/lib:$PREFIX/include:$CMAKE_LIBRARY_PATH
export CMAKE_PREFIX_PATH=$PREFIX
export CMAKE_BUILD_TYPE=Release

for ARG in $CMAKE_ARGS; do
  if [[ "$ARG" == "-DCMAKE_"* ]]; then
    cmake_arg=$(echo $ARG | cut -d= -f1)
    cmake_arg=$(echo $cmake_arg| cut -dD -f2-)
    cmake_val=$(echo $ARG | cut -d= -f2-)
    printf -v $cmake_arg "$cmake_val"
    export ${cmake_arg}
  fi
done
CMAKE_FIND_ROOT_PATH+=";$SRC_DIR"
unset CMAKE_INSTALL_PREFIX
export TH_BINARY_BUILD=1
# Use our build version and number for inserting into binaries
export PYTORCH_BUILD_VERSION=$PKG_VERSION
# Always pass 0 to avoid appending ".post" to version string.
# https://github.com/conda-forge/pytorch-cpu-feedstock/issues/315
export PYTORCH_BUILD_NUMBER=0

export INSTALL_TEST=0
export BUILD_TEST=0

export USE_SYSTEM_SLEEF=1
# use our protobuf
export BUILD_CUSTOM_PROTOBUF=OFF
rm -rf $PREFIX/bin/protoc

# prevent six from being downloaded
> third_party/NNPACK/cmake/DownloadSix.cmake

if [[ "${target_platform}" != "${build_platform}" ]]; then
    # It helps cross compiled builds without emulation support to complete
    # Use BUILD PREFIX protoc instead of the one that is from the host platform
    sed -i.bak \
        "s,IMPORTED_LOCATION_RELEASE .*/bin/protoc,IMPORTED_LOCATION_RELEASE \"${BUILD_PREFIX}/bin/protoc," \
        ${PREFIX}/lib/cmake/protobuf/protobuf-targets-release.cmake
fi

# I don't know where this folder comes from, but it's interfering with the build in osx-64
rm -rf $PREFIX/git

if [[ "$CONDA_BUILD_CROSS_COMPILATION" == 1 ]]; then
    export COMPILER_WORKS_EXITCODE=0
    export COMPILER_WORKS_EXITCODE__TRYRUN_OUTPUT=""
fi

if [[ "${CI}" == "github_actions" ]]; then
    # h-vetinari/hmaarrfk -- May 2024
    # reduce parallelism to avoid getting OOM-killed on
    # cirun-openstack-gpu-2xlarge, which has 32GB RAM, 8 CPUs
    export MAX_JOBS=4
else
    export MAX_JOBS=${CPU_COUNT}
fi

if [[ "$blas_impl" == "generic" ]]; then
    # Fake openblas
    export BLAS=OpenBLAS
    export OpenBLAS_HOME=${PREFIX}
else
    export BLAS=MKL
fi

if [[ "$PKG_NAME" == "pytorch" ]]; then
  # Trick Cmake into thinking python hasn't changed
  sed "s/3\.12/$PY_VER/g" build/CMakeCache.txt.orig > build/CMakeCache.txt
  sed -i.bak "s/3;12/${PY_VER%.*};${PY_VER#*.}/g" build/CMakeCache.txt
  sed -i.bak "s/cpython-312/cpython-${PY_VER%.*}${PY_VER#*.}/g" build/CMakeCache.txt
fi

# MacOS build is simple, and will not be for CUDA
if [[ "$OSTYPE" == "darwin"* ]]; then
    # Produce macOS builds with torch.distributed support.
    # This is enabled by default on Linux, but disabled by default on macOS,
    # because it requires an non-bundled compile-time dependency (libuv
    # through gloo). This dependency is made available through meta.yaml, so
    # we can override the default and set USE_DISTRIBUTED=1.
    export USE_DISTRIBUTED=1

    if [[ "$target_platform" == "osx-arm64" ]]; then
        # MKLDNN did not support on Apple M1 at the time support Apple M1
        # was added. Revisit later
        export USE_MKLDNN=0
    fi
elif [[ ${cuda_compiler_version} != "None" ]]; then
    if [[ "$target_platform" == "linux-aarch64" ]]; then
        # https://github.com/pytorch/pytorch/pull/121975
        # https://github.com/conda-forge/pytorch-cpu-feedstock/issues/264
        export USE_PRIORITIZED_TEXT_FOR_LD=1
    fi
    # Even though cudnn is used for CUDA builds, it's good to enable
    # for MKLDNN for CUDA builds when CUDA builds are used on a machine
    # with no NVIDIA GPUs.
    export USE_MKLDNN=1
    export USE_CUDA=1
    export USE_CUFILE=1
    # PyTorch has multiple different bits of logic finding CUDA, override
    # all of them.
    export CUDAToolkit_BIN_DIR=${BUILD_PREFIX}/bin
    export CUDAToolkit_ROOT_DIR=${PREFIX}
    if [[ "${target_platform}" != "${build_platform}" ]]; then
        export CUDA_TOOLKIT_ROOT=${PREFIX}
    fi
    # for CUPTI
    export CUDA_TOOLKIT_ROOT_DIR=${PREFIX}
    case ${target_platform} in
        linux-64)
            export CUDAToolkit_TARGET_DIR=${PREFIX}/targets/x86_64-linux
            ;;
        linux-aarch64)
            export CUDAToolkit_TARGET_DIR=${PREFIX}/targets/sbsa-linux
            ;;
        *)
            echo "unknown CUDA arch, edit build.sh"
            exit 1
    esac
    # Warning from pytorch v1.12.1: In the future we will require one to
    # explicitly pass TORCH_CUDA_ARCH_LIST to cmake instead of implicitly
    # setting it as an env variable.
    #
    # See:
    # https://pytorch.org/docs/stable/cpp_extension.html (Compute capabilities)
    # https://github.com/pytorch/pytorch/blob/main/.ci/manywheel/build_cuda.sh
    case ${cuda_compiler_version} in
        12.6)
            export TORCH_CUDA_ARCH_LIST="5.0;6.0;6.1;7.0;7.5;8.0;8.6;8.9;9.0+PTX"
            ;;
        *)
            echo "No CUDA architecture list exists for CUDA v${cuda_compiler_version}. See build.sh for information on adding one."
            exit 1
    esac
    export TORCH_NVCC_FLAGS="-Xfatbin -compress-all"
    export NCCL_ROOT_DIR=$PREFIX
    export NCCL_INCLUDE_DIR=$PREFIX/include
    export USE_SYSTEM_NCCL=1
    export USE_SYSTEM_NVTX=1
    export USE_STATIC_NCCL=0
    export USE_STATIC_CUDNN=0
    export MAGMA_HOME="${PREFIX}"
    export USE_MAGMA=1
else
    if [[ "$target_platform" != *-64 ]]; then
      # Breakpad seems to not work on aarch64 or ppc64le
      # https://github.com/pytorch/pytorch/issues/67083
      export USE_BREAKPAD=0
    fi
    # MKLDNN is an Apache-2.0 licensed library for DNNs and is used
    # for CPU builds. Not to be confused with MKL.
    export USE_MKLDNN=1
    export USE_CUDA=0
fi

echo '${CXX}'=${CXX}
echo '${PREFIX}'=${PREFIX}

case ${PKG_NAME} in
  libtorch)
    # Call setup.py directly to avoid spending time on unnecessarily
    # packing and unpacking the wheel.
    $PREFIX/bin/python setup.py build

    mv build/lib.*/torch/bin/* ${PREFIX}/bin/
    mv build/lib.*/torch/lib/* ${PREFIX}/lib/
    mv build/lib.*/torch/share/* ${PREFIX}/share/
    mv build/lib.*/torch/include/{ATen,caffe2,tensorpipe,torch,c10} ${PREFIX}/include/
    rm ${PREFIX}/lib/libtorch_python.*

    # Keep the original backed up to sed later
    cp build/CMakeCache.txt build/CMakeCache.txt.orig
    ;;
  pytorch)
    $PREFIX/bin/python -m pip install . --no-deps -vvv --no-clean \
        | sed "s,${CXX},\$\{CXX\},g" \
        | sed "s,${PREFIX},\$\{PREFIX\},g"
    # Keep this in ${PREFIX}/lib so that the library can be found by
    # TorchConfig.cmake.
    # With upstream non-split build, `libtorch_python.so`
    # and TorchConfig.cmake are both in ${SP_DIR}/torch/lib and therefore
    # this is not needed.
    #
    # NB: we are using cp rather than mv, so that the loop below symlinks it
    # back.
    cp ${SP_DIR}/torch/lib/libtorch_python${SHLIB_EXT} ${PREFIX}/lib

    pushd $SP_DIR/torch
    # Make symlinks for libraries and headers from libtorch into $SP_DIR/torch
    # Also remove the vendorered libraries they seem to include
    # https://github.com/conda-forge/pytorch-cpu-feedstock/issues/243
    # https://github.com/pytorch/pytorch/blob/v2.3.1/setup.py#L341
    for f in bin/* lib/* share/* include/*; do
      if [[ -e "$PREFIX/$f" ]]; then
        rm -rf $f
        ln -sf $PREFIX/$f $PWD/$f
      fi
    done
    popd
    ;;
  *)
    echo "Unknown package name, edit build.sh"
    exit 1
esac
