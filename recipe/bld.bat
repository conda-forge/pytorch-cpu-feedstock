@echo On
setlocal enabledelayedexpansion

@REM remove pyproject.toml to avoid installing deps from pip
if EXIST pyproject.toml (
  DEL pyproject.toml
  if %ERRORLEVEL% neq 0 exit 1
)

set PYTORCH_BUILD_VERSION=%PKG_VERSION%
@REM Always pass 0 to avoid appending ".post" to version string.
@REM https://github.com/conda-forge/pytorch-cpu-feedstock/issues/315
set PYTORCH_BUILD_NUMBER=0

@REM Setup BLAS
if "%blas_impl%" == "generic" (
    @REM Fake openblas
    SET BLAS=OpenBLAS
    SET OpenBLAS_HOME=%LIBRARY_PREFIX%
) else (
    SET BLAS=MKL
)

@REM TODO(baszalmstra): Figure out if we need these flags
SET "USE_NUMA=0"
SET "USE_ITT=0"

if "%PKG_NAME%" == "pytorch" (
  set "PIP_ACTION=install"
  @REM We build libtorch for a specific python version.
  @REM This ensures its only build once. However, when that version changes
  @REM we need to make sure to update that here.
  @REM Get the full python version string
  for /f "tokens=2" %%a in ('python --version 2^>^&1') do set PY_VERSION_FULL=%%a

  @REM Replace Python312 or python312 with ie Python311 or python311
  sed "s/\([Pp]ython\)312/\1%CONDA_PY%/g" build/CMakeCache.txt.orig > build/CMakeCache.txt
  if %ERRORLEVEL% neq 0 exit 1

  @REM Replace version string v3.12.8() with ie v3.11.11()
  sed -i.bak -E "s/v3\.12\.[0-9]+/v%PY_VERSION_FULL%/g" build/CMakeCache.txt
  if %ERRORLEVEL% neq 0 exit 1

  @REM Replace interpreter properties Python;3;12;8;64 with ie Python;3;11;11;64
  sed -i.bak -E "s/Python;3;12;[0-9]+;64/Python;%PY_VERSION_FULL:.=;%;64/g" build/CMakeCache.txt
  if %ERRORLEVEL% neq 0 exit 1

  @REM Replace cp312-win_amd64 with ie cp311-win_amd64
  sed -i.bak "s/cp312/cp%CONDA_PY%/g" build/CMakeCache.txt
  if %ERRORLEVEL% neq 0 exit 1

  sed -i.bak "s#numpy\\\\core\\\\include#numpy\\\\_core\\\\include#g" build/CMakeCache.txt
  if %ERRORLEVEL% neq 0 exit 1

) else (
  @REM For the main script we just build a wheel for so that the C++/CUDA
  @REM parts are built. Then they are reused in each python version.
  set "PIP_ACTION=wheel"
)

if not "%cuda_compiler_version%" == "None" (
    set USE_CUDA=1

    @REM set CUDA_PATH=C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v%desired_cuda%
    @REM set CUDA_BIN_PATH=%CUDA_PATH%\bin

    set TORCH_CUDA_ARCH_LIST=5.0;6.0;6.1;7.0;7.5;8.0;8.6;8.9;9.0+PTX

    set TORCH_NVCC_FLAGS=-Xfatbin -compress-all

    set USE_STATIC_CUDNN=0
    set MAGMA_HOME=%PREFIX%

    @REM NCCL is not available on windows
    set USE_NCCL=0
    set USE_STATIC_NCCL=0

    set MAGMA_HOME=%LIBRARY_PREFIX%

    set "PATH=%CUDA_BIN_PATH%;%PATH%"

    set CUDNN_INCLUDE_DIR=%LIBRARY_PREFIX%\include

) else (
    set USE_CUDA=0
    @REM On windows, env vars are case-insensitive and setup.py
    @REM passes all env vars starting with CUDA_*, CMAKE_* to
    @REM to cmake
    set "cuda_compiler_version="
    set "cuda_compiler="
    set "CUDA_VERSION="

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
@REM This is so that CMake finds the environment's Python, not another one
set Python_EXECUTABLE=%PYTHON%
set Python3_EXECUTABLE=%PYTHON%

set "INSTALL_TEST=0"
set "BUILD_TEST=0"

set "libuv_ROOT=%LIBRARY_PREFIX%"
set "USE_SYSTEM_SLEEF=ON"

@REM uncomment to debug cmake build
@REM set "CMAKE_VERBOSE_MAKEFILE=1"

set "BUILD_CUSTOM_PROTOBUF=OFF"
set "USE_LITE_PROTO=ON"

@REM TODO(baszalmstra): There are linker errors because of mixing Intel OpenMP (iomp) and Microsoft OpenMP (vcomp)
set "USE_OPENMP=OFF"

@REM The activation script for cuda-nvcc doesnt add the CUDA_CFLAGS on windows.
@REM Therefor we do this manually here. See:
@REM https://github.com/conda-forge/cuda-nvcc-feedstock/issues/47
echo "CUDA_CFLAGS=%CUDA_CFLAGS%"
set "CUDA_CFLAGS=-I%PREFIX%/Library/include -I%BUILD_PREFIX%/Library/include"
set "CFLAGS=%CFLAGS% %CUDA_CFLAGS%"
set "CPPFLAGS=%CPPFLAGS% %CUDA_CFLAGS%"
set "CXXFLAGS=%CXXFLAGS% %CUDA_CFLAGS%"
echo "CUDA_CFLAGS=%CUDA_CFLAGS%"
echo "CXXFLAGS=%CXXFLAGS%"

@REM Configure sccache
set "CMAKE_C_COMPILER_LAUNCHER=sccache"
set "CMAKE_CXX_COMPILER_LAUNCHER=sccache"
set "CMAKE_CUDA_COMPILER_LAUNCHER=sccache"

sccache --stop-server
sccache --start-server
if %ERRORLEVEL% neq 0 exit 1
sccache --zero-stats
if %ERRORLEVEL% neq 0 exit 1

@REM Clear the build from any remaining artifacts. We use sccache to avoid recompiling similar code.
if EXIST build (
    cmake --build build --target clean
    if %ERRORLEVEL% neq 0 exit 1
)

%PYTHON% -m pip %PIP_ACTION% . --no-build-isolation --no-deps -vvv --no-clean
if %ERRORLEVEL% neq 0 exit 1

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
    if not exist "%SRC_DIR%\dist" mkdir %SRC_DIR%\dist
    pushd %SRC_DIR%\dist
    for /f %%f in ('dir /b /S ..\torch-*.whl') do (
        wheel unpack %%f
        if %ERRORLEVEL% neq 0 exit 1
    )

    @REM Navigate into the unpacked wheel; naming pattern of the folder is documented:
    @REM https://github.com/pypa/wheel/blob/0.45.1/src/wheel/cli/unpack.py#L11-L12
    pushd torch-%PKG_VERSION%
    if %ERRORLEVEL% neq 0 exit 1

    @REM Do not package `fmt.lib` (and its metadata); delete it before the move into
    @REM %LIBRARY_BIN% because it may exist in host before installation already
    del torch\lib\fmt.lib torch\lib\pkgconfig\fmt.pc
    if %ERRORLEVEL% neq 0 exit 1
    @REM also delete rest of fmt metadata
    rmdir /s /q torch\lib\cmake\fmt

    @REM Move the binaries into the packages site-package directory
    @REM the only content of torch\bin, {asmjit,fbgemm}.dll, also exists in torch\lib
    robocopy /NP /NFL /NDL /NJH /E torch\lib\ %LIBRARY_BIN%\ torch*.dll c10.dll shm.dll asmjit.dll fbgemm.dll
    robocopy /NP /NFL /NDL /NJH /E torch\lib\ %LIBRARY_LIB%\ torch*.lib c10.lib shm.lib asmjit.lib fbgemm.lib
    if not "%cuda_compiler_version%" == "None" (
        robocopy /NP /NFL /NDL /NJH /E torch\lib\ %LIBRARY_BIN%\ c10_cuda.dll caffe2_nvrtc.dll
        robocopy /NP /NFL /NDL /NJH /E torch\lib\ %LIBRARY_LIB%\ c10_cuda.lib caffe2_nvrtc.lib
    )
    robocopy /NP /NFL /NDL /NJH /E torch\share\ %LIBRARY_PREFIX%\share
    for %%f in (ATen caffe2 torch c10) do (
        robocopy /NP /NFL /NDL /NJH /E torch\include\%%f %LIBRARY_INC%\%%f\
    )

    @REM Remove the python binary file, that is placed in the site-packages
    @REM directory by the specific python specific pytorch package.
    del %LIBRARY_BIN%\torch_python.* %LIBRARY_LIB%\torch_python.* %LIBRARY_LIB%\_C.lib
    if %ERRORLEVEL% neq 0 exit 1

    popd
    popd

    @REM Keep the original backed up to sed later
    copy build\CMakeCache.txt build\CMakeCache.txt.orig
    if %ERRORLEVEL% neq 0 exit 1
) else if "%PKG_NAME%" == "pytorch" (
    @REM Move libtorch_python and remove the other directories afterwards.
    robocopy /NP /NFL /NDL /NJH /E %SP_DIR%\torch\lib\ %LIBRARY_BIN%\ torch_python.dll
    robocopy /NP /NFL /NDL /NJH /E %SP_DIR%\torch\lib\ %LIBRARY_LIB%\ torch_python.lib
    robocopy /NP /NFL /NDL /NJH /E %SP_DIR%\torch\lib\ %LIBRARY_LIB%\ _C.lib
    rmdir /s /q %SP_DIR%\torch\lib
    rmdir /s /q %SP_DIR%\torch\bin
    rmdir /s /q %SP_DIR%\torch\share
    for %%f in (ATen caffe2 torch c10) do (
        rmdir /s /q %SP_DIR%\torch\include\%%f
    )

    @REM Copy libtorch_python.lib back -- that's much easier than the for loop
    @REM needed to remove everything else.
    robocopy /NP /NFL /NDL /NJH /E %LIBRARY_LIB%\ torch\lib\ torch_python.lib
    robocopy /NP /NFL /NDL /NJH /E %LIBRARY_LIB%\ torch\lib\ _C.lib
)

@REM Show the sccache stats.
sccache --show-stats
