# Most of this script is adapted from the pytorch/pythorch-cpu
# meta.yaml.template build.sh and bld.bat scripts
set TN_BINARY_BUILD=1
set PYTORCH_BINARY_BUILD=1
set NO_CUDA=1
set PYTORCH_BUILD_VERSION={{ PKG_VERSION }}
set PYTORCH_BUILD_NUMBER={{ PKG_BUILDNUM }}
set BUILD_CUSTOM_PROTOBUF=ON
# Use ninja as the build just won't finish on windows
set CMAKE_GENERATOR=Ninja
# I have no idea what this flag does, but they recommend turning it on
# when we don't find three of their headers.
# It seemed to be required on Appveyor, but not azure, strange???
# set GEN_TO_SOURCE=1                          # [win]
# Why are all warnings treated as errors???
# Disable this other 3rd party binary
set NO_MKLDNN=1
# set NO_TEST=1
# I couldn't find any documentation on this, but eventually they call
# a script tools/build_pytorch_libs.sh
# whcih passes EXTRA_CAFFE2_CMAKE_FLAGS at the end of the cmake command
# to all 3rd party libraries.
set EXTRA_CAFFE2_CMAKE_FLAGS="-DUSE_MPI=OFF -DUSE_NUMA=OFF -DUSE_NCCL=OFF -DATEN_NO_TEST=OFF"
# Why do I need to export these?
# How do we add /std:c++11 to windows CFLAGS
# There is an other weird python package called ninja
# which is their preferred method of building
# that said, it does nothing but call "ninja"
# - pip install ninja
%PYTHON% -m pip install . -vv
