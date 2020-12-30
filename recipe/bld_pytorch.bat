@echo On

set TH_BINARY_BUILD=1
set PYTORCH_BUILD_VERSION=%PKG_VERSION%
set PYTORCH_BUILD_NUMBER=%PKG_BUILDNUM%

if "%cuda_compiler_version%" == "None" (
    set USE_CUDA=0
)

if "%cuda_compiler_version%" == "None" goto cuda_flags_end

set CUDA_BIN_PATH=%CUDA_PATH%\bin
set TORCH_CUDA_ARCH_LIST=3.5;5.0+PTX
if "%cuda_compiler_version%" == "9.2" set TORCH_CUDA_ARCH_LIST=%TORCH_CUDA_ARCH_LIST%;6.0;6.1;7.0
if "%cuda_compiler_version%" == "10.0" set TORCH_CUDA_ARCH_LIST=%TORCH_CUDA_ARCH_LIST%;6.0;6.1;7.0;7.5
if "%cuda_compiler_version%" == "10.1" set TORCH_CUDA_ARCH_LIST=%TORCH_CUDA_ARCH_LIST%;6.0;6.1;7.0;7.5
if "%cuda_compiler_version%" == "10.2" set TORCH_CUDA_ARCH_LIST=%TORCH_CUDA_ARCH_LIST%;6.0;6.1;7.0;7.5
if "%cuda_compiler_version%" == "11.0" set TORCH_CUDA_ARCH_LIST=%TORCH_CUDA_ARCH_LIST%;6.0;6.1;7.0;7.5;8.0
if "%cuda_compiler_version%" == "11.1" set TORCH_CUDA_ARCH_LIST=%TORCH_CUDA_ARCH_LIST%;6.0;6.1;7.0;7.5;8.0;8.6
set TORCH_NVCC_FLAGS=-Xfatbin -compress-all

REM these are set by nvcc activation and interferes with the build
unset CFLAGS
unset CXXFLAGS
unset CPPFLAGS

:cuda_flags_end

set CMAKE_INCLUDE_PATH=%LIBRARY_PREFIX%\include
set LIB=%LIBRARY_PREFIX%\lib;%LIB%

IF "%cuda_compiler_version%" == "None" goto cuda_end

set MAGMA_HOME=%LIBRARY_PREFIX%

set "PATH=%CUDA_BIN_PATH%;%PATH%"

set CUDNN_INCLUDE_DIR=%LIBRARY_PREFIX%\include

:cuda_end

set CMAKE_GENERATOR=Ninja
set "CMAKE_PREFIX_PATH=%LIBRARY_PREFIX%"
set "libuv_ROOT=%LIBRARY_PREFIX%"

%PYTHON% -m pip install . --no-deps -vv
if errorlevel 1 exit /b 1
