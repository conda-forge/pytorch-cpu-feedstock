@echo On

set TH_BINARY_BUILD=1
set PYTORCH_BUILD_VERSION=%PKG_VERSION%
set PYTORCH_BUILD_NUMBER=%PKG_BUILDNUM%

if "%cuda_compiler_version%" != "None" (
    set build_with_cuda=1
    set desired_cuda=%CUDA_VERSION:~0,-1%.%CUDA_VERSION:~-1,1%
    set USE_CUDA=1
) else (
    set build_with_cuda=
    set USE_CUDA=0
)

if "%build_with_cuda%" == "" goto cuda_flags_end

set CUDA_PATH=C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v%desired_cuda%
set CUDA_BIN_PATH=%CUDA_PATH%\bin
set TORCH_CUDA_ARCH_LIST=3.7+PTX
if "%desired_cuda%" == "9.0" set TORCH_CUDA_ARCH_LIST=%TORCH_CUDA_ARCH_LIST%;7.0
if "%desired_cuda%" == "9.2" set TORCH_CUDA_ARCH_LIST=%TORCH_CUDA_ARCH_LIST%;7.0
if "%desired_cuda%" == "10.0" set TORCH_CUDA_ARCH_LIST=%TORCH_CUDA_ARCH_LIST%;7.0;7.5
if "%desired_cuda%" == "10.1" set TORCH_CUDA_ARCH_LIST=%TORCH_CUDA_ARCH_LIST%;7.0;7.5
if "%desired_cuda%" == "10.2" set TORCH_CUDA_ARCH_LIST=%TORCH_CUDA_ARCH_LIST%;7.0;7.5
if "%desired_cuda%" == "11.0" set TORCH_CUDA_ARCH_LIST=%TORCH_CUDA_ARCH_LIST%;7.0;7.5;8.0
if "%desired_cuda%" == "11.1" set TORCH_CUDA_ARCH_LIST=%TORCH_CUDA_ARCH_LIST%;7.0;7.5;8.0;8.6
if "%desired_cuda%" == "11.2" set TORCH_CUDA_ARCH_LIST=%TORCH_CUDA_ARCH_LIST%;7.0;7.5;8.0;8.6
set TORCH_NVCC_FLAGS=-Xfatbin -compress-all

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
set "CMAKE_GENERATOR_PLATFORM="
set "CMAKE_PREFIX_PATH=%LIBRARY_PREFIX%"
set "libuv_ROOT=%LIBRARY_PREFIX%"
set "USE_SYSTEM_SLEEF=OFF"

set "MAX_JOBS=%CPU_COUNT%"

%PYTHON% -m pip install . --no-deps -vv
if errorlevel 1 exit /b 1
