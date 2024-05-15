@echo On
setlocal enabledelayedexpansion

REM remove pyproject.toml to avoid installing deps from pip
DEL pyproject.toml

set TH_BINARY_BUILD=1
set PYTORCH_BUILD_VERSION=%PKG_VERSION%
set PYTORCH_BUILD_NUMBER=%PKG_BUILDNUM%

REM I don't know where this folder comes from, but it's interfering with the build in osx-64
RD /S /Q %PREFIX%\git

@REM Setup BLAS
if "%blas_impl%" == "generic" (
    REM Fake openblas
    SET BLAS=OpenBLAS

    sed -i.bak "s#FIND_LIBRARY.*#set(OpenBLAS_LIB %PREFIX:\=/%/Library/lib/lapack.lib %PREFIX:\=/%/Library/lib/cblas.lib %PREFIX:\=/%/Library/lib/blas.lib)#g" cmake/Modules/FindOpenBLAS.cmake
) else (
    SET BLAS=MKL
)

@REM TODO(baszalmstra): Figure out if we need these flags
SET "USE_NUMA=0"
SET "USE_ITT=0"

@REM KINETO seems to require CUPTI and will look quite hard for it.
@REM CUPTI seems to cause trouble when users install a version of
@REM cudatoolkit different than the one specified at compile time.
@REM https://github.com/conda-forge/pytorch-cpu-feedstock/issues/135
set "USE_KINETO=OFF"

if "%PKG_NAME%" == "pytorch" (
  set "PIP_ACTION=install"
  @REM We build libtorch for a specific python version. 
  @REM This ensures its only build once. However, when that version changes 
  @REM we need to make sure to update that here.
  sed "s/3.12/%PY_VER%/g" build/CMakeCache.txt.orig > build/CMakeCache.txt
  sed -i "s/312/%CONDA_PY%/g" build/CMakeCache.txt
) else (
  @REM For the main script we just build a wheel for so that the C++/CUDA
  @REM parts are built. Then they are reused in each python version.
  set "PIP_ACTION=wheel"

  @REM Disable building python specific code
  set "BUILD_PYTON=0"
)

if not "%cuda_compiler_version%" == "None" (
    set USE_CUDA=1

    REM set CUDA_PATH=C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v%desired_cuda%
    REM set CUDA_BIN_PATH=%CUDA_PATH%\bin

    set TORCH_CUDA_ARCH_LIST=3.5;5.0+PTX
    if "%cuda_compiler_version:~0,3%" == "9.0" (
        set TORCH_CUDA_ARCH_LIST=3.5;5.0;6.0;7.0+PTX
        set CUDA_TOOLKIT_ROOT_DIR=%CUDA_HOME%
    ) else if "%cuda_compiler_version:~0,3%" == "9.2" (
        set TORCH_CUDA_ARCH_LIST=3.5;5.0;6.0;6.1;7.0+PTX
        set CUDA_TOOLKIT_ROOT_DIR=%CUDA_HOME%
    ) else if "%cuda_compiler_version:~0,3%" == "10." (
        set TORCH_CUDA_ARCH_LIST=3.5;5.0;6.0;6.1;7.0;7.5+PTX
        set CUDA_TOOLKIT_ROOT_DIR=%CUDA_HOME%
    ) else if "%cuda_compiler_version:~0,4%" == "11.0" (
        set TORCH_CUDA_ARCH_LIST=3.5;5.0;6.0;6.1;7.0;7.5;8.0+PTX
        set CUDA_TOOLKIT_ROOT_DIR=%CUDA_HOME%
    ) else if "%cuda_compiler_version%" == "11.1" (
        set TORCH_CUDA_ARCH_LIST=3.5;5.0;6.0;6.1;7.0;7.5;8.0;8.6+PTX
        set CUDA_TOOLKIT_ROOT_DIR=%CUDA_HOME%
    ) else if "%cuda_compiler_version%" == "11.2" (
        set TORCH_CUDA_ARCH_LIST=3.5;5.0;6.0;6.1;7.0;7.5;8.0;8.6+PTX
        set CUDA_TOOLKIT_ROOT_DIR=%CUDA_HOME%
    ) else if "%cuda_compiler_version%" == "11.8" (
        set TORCH_CUDA_ARCH_LIST=3.5;5.0;6.0;6.1;7.0;7.5;8.0;8.6;8.9+PTX
        set CUDA_TOOLKIT_ROOT_DIR=%CUDA_HOME%
    ) else if "%cuda_compiler_version%" == "12.0" (
        set TORCH_CUDA_ARCH_LIST=5.0;6.0;6.1;7.0;7.5;8.0;8.6;8.9;9.0+PTX
        set CUDA_TOOLKIT_ROOT_DIR=%PREFIX%
    ) else (
        echo "unsupported cuda version. edit build_pytorch.bat"
        exit /b 1
    )

    set TORCH_NVCC_FLAGS=-Xfatbin -compress-all

    REM set USE_SYSTEM_NCCL=1
    set USE_STATIC_NCCL=0
    set USE_STATIC_CUDNN=0
    set MAGMA_HOME=%PREFIX%

    REM NCCL is not available on windows
    set USE_NCCL=0

    set MAGMA_HOME=%LIBRARY_PREFIX%

    set "PATH=%CUDA_BIN_PATH%;%PATH%"

    set CUDNN_INCLUDE_DIR=%LIBRARY_PREFIX%\include

) else (
    set USE_CUDA=0
    
    @REM MKLDNN is an Apache-2.0 licensed library for DNNs and is used
    @REM for CPU builds. Not to be confused with MKL.
    set "USE_MKLDNN=1"
)

set DISTUTILS_USE_SDK=1

set CMAKE_INCLUDE_PATH=%LIBRARY_PREFIX%\include
set LIB=%LIBRARY_PREFIX%\lib;%LIB%

@REM CMake configuration
set CMAKE_GENERATOR=Ninja
set "CMAKE_GENERATOR_TOOLSET="
set "CMAKE_GENERATOR_PLATFORM="
set "CMAKE_PREFIX_PATH=%LIBRARY_PREFIX%"
set "CMAKE_INCLUDE_PATH=%LIBRARY_INC%"
set "CMAKE_LIBRARY_PATH=%LIBRARY_LIB%"
set "CMAKE_BUILD_TYPE=Release"

set "INSTALL_TEST=0"
set "BUILD_TEST=0"

set "libuv_ROOT=%LIBRARY_PREFIX%"
set "USE_SYSTEM_SLEEF=ON"

@REM Only for debugging
@REM set "CMAKE_C_COMPILER_LAUNCHER=sccache"
@REM set "CMAKE_CXX_COMPILER_LAUNCHER=sccache"
@REM set "CMAKE_CUDA_COMPILER_LAUNCHER=sccache"
@REM uncomment to debug cmake build
@REM set "CMAKE_VERBOSE_MAKEFILE=1"

@REM TODO(baszalmstra): There are link errors because of conflicting symbols with caffe2_protos.lib
set "BUILD_CUSTOM_PROTOBUF=ON"

@REM TODO(baszalmstra): There are linker errors because of mixing Intel OpenMP (iomp) and Microsoft OpenMP (vcomp)
set "USE_OPENMP=0"

%PYTHON% -m pip %PIP_ACTION% . --no-deps -vvv --no-clean
if errorlevel 1 exit /b 1

@REM Here we split the build into two parts.
@REM 
@REM Both the packages libtorch and pytorch use this same build script.
@REM - The output of the libtorch package should just contain the binaries that are 
@REM   not related to Python.
@REM - The output of the pytorch package contains everything except for the 
@REM   non-python specific binaries.
@REM
@REM This ensures that a user can quickly switch between python versions without the
@REM need to redownload all the large CUDA binaries.

if "%PKG_NAME%" == "libtorch" (
    @REM Extract the compiled wheel into a temporary directory
    if not exist "%SRC_DIR%/dist" mkdir %SRC_DIR%/dist
    pushd %SRC_DIR%/dist
    for %%f in (../torch-*.whl) do (
        wheel unpack %%f
    )

    @REM Navigate into the unpacked wheel
    pushd torch-*

    @REM Move the binaries into the packages site-package directory
    robocopy /NP /E torch\bin %SP_DIR%\torch\bin\
    robocopy /NP /E torch\lib %SP_DIR%\torch\lib\
    robocopy /NP /E torch\share %SP_DIR%\torch\share\
    for %%f in (ATen caffe2 torch c10) do (
        robocopy /NP /E torch\include\%%f %SP_DIR%\torch\include\%%f\
    )

    @REM Remove the python binary file, that is placed in the site-packages 
    @REM directory by the specific python specific pytorch package.
    del %SP_DIR%\torch\lib\torch_python.*
    
    popd
    popd

    @REM Keep the original backed up to sed later
    copy build\CMakeCache.txt build\CMakeCache.txt.orig
)