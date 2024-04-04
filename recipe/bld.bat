@echo On

set TH_BINARY_BUILD=1
set PYTORCH_BUILD_VERSION=%PKG_VERSION%
set PYTORCH_BUILD_NUMBER=%PKG_BUILDNUM%

if "%pytorch_variant%" == "gpu" (
    set build_with_cuda=1
    set desired_cuda=%CUDA_VERSION:~0,-1%.%CUDA_VERSION:~-1,1%
) else (
    set build_with_cuda=
    set USE_CUDA=0
)

if "%build_with_cuda%" == "" goto cuda_flags_end

set CUDA_PATH=C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v%desired_cuda%
set CUDA_BIN_PATH=%CUDA_PATH%\bin
set TORCH_CUDA_ARCH_LIST=3.5;5.0+PTX
if "%desired_cuda%" == "9.0" (
    set TORCH_CUDA_ARCH_LIST=3.5;5.0;6.0;7.0+PTX
    set CUDA_TOOLKIT_ROOT_DIR=%CUDA_HOME%
) else if "%desired_cuda%" == "9.2" (
    set TORCH_CUDA_ARCH_LIST=3.5;5.0;6.0;6.1;7.0+PTX
    set CUDA_TOOLKIT_ROOT_DIR=%CUDA_HOME%
) else if "%desired_cuda%" == "10.0" (
    set TORCH_CUDA_ARCH_LIST=3.5;5.0;6.0;6.1;7.0;7.5+PTX
    set CUDA_TOOLKIT_ROOT_DIR=%CUDA_HOME%
) else if "%desired_cuda%" == "11.0" (
    set TORCH_CUDA_ARCH_LIST=3.5;5.0;6.0;6.1;7.0;7.5;8.0+PTX
    set CUDA_TOOLKIT_ROOT_DIR=%CUDA_HOME%
) else if "%desired_cuda%" == "11.1" (
    set TORCH_CUDA_ARCH_LIST=3.5;5.0;6.0;6.1;7.0;7.5;8.0;8.6+PTX
    set CUDA_TOOLKIT_ROOT_DIR=%CUDA_HOME%
) else if "%desired_cuda%" == "11.2" (
    set TORCH_CUDA_ARCH_LIST=3.5;5.0;6.0;6.1;7.0;7.5;8.0;8.6+PTX
    set CUDA_TOOLKIT_ROOT_DIR=%CUDA_HOME%
) else if "%desired_cuda%" == "11.8" (
    set TORCH_CUDA_ARCH_LIST=3.5;5.0;6.0;6.1;7.0;7.5;8.0;8.6;8.9+PTX
    set CUDA_TOOLKIT_ROOT_DIR=%CUDA_HOME%
) else if "%desired_cuda%" == "12.0" (
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

:cuda_flags_end

set DISTUTILS_USE_SDK=1

set CMAKE_INCLUDE_PATH=%LIBRARY_PREFIX%\include
set LIB=%LIBRARY_PREFIX%\lib;%LIB%

IF "%build_with_cuda%" == "" goto cuda_end

set MAGMA_HOME=%LIBRARY_PREFIX%

set "PATH=%CUDA_BIN_PATH%;%PATH%"

set CUDNN_INCLUDE_DIR=%LIBRARY_PREFIX%\include

:cuda_end

set CMAKE_GENERATOR=Ninja
set "CMAKE_GENERATOR_TOOLSET="
set "CMAKE_GENERATOR_PLATFORM="
set "CMAKE_PREFIX_PATH=%LIBRARY_PREFIX%"
set "CMAKE_INCLUDE_PATH=%LIBRARY_INC%"
set "CMAKE_LIBRARY_PATH=%LIBRARY_LIB%"
set "libuv_ROOT=%LIBRARY_PREFIX%"
set "USE_SYSTEM_SLEEF=ON"
set "INSTALL_TEST=0"
set "BUILD_TEST=0"

@REM There are link errors because of conflicting symbols with caffe2_protos.lib
set "BUILD_CUSTOM_PROTOBUF=ON"

%PYTHON% setup.py install
if errorlevel 1 exit /b 1
