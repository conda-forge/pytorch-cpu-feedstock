export CFLAGS="-D__STDC_LIMIT_MACROS=1 -D__STDC_CONSTANT_MACROS=1 -D__STDC_FORMAT_MACROS=1 $CFLAGS"
export CXXFLAGS="-D__STDC_LIMIT_MACROS=1 -D__STDC_CONSTANT_MACROS=1 -D__STDC_FORMAT_MACROS=1 $CXXFLAGS"

# Most of this script is adapted from the pytorch/pythorch-cpu
# During verion 1.1. Maybe it is time to update it?
# meta.yaml.template build.sh and bld.bat scripts
export TN_BINARY_BUILD=1
export PYTORCH_BINARY_BUILD=1
export NO_CUDA=1
export PYTORCH_BUILD_VERSION=$PKG_VERSION
export PYTORCH_BUILD_NUMBER=$PKG_BUILDNUM
export BUILD_CUSTOM_PROTOBUF=ON
export CMAKE_GENERATOR=Ninja
# Why are all warnings treated as errors???
export CXXFLAGS="-Wno-error=unused-result $CXXFLAGS"
export CFLAGS="-Wno-error=unused-result $CFLAGS"
# Disable this other 3rd party binary
export NO_MKLDNN=1
export NO_TEST=1
# I couldn't find any documentation on this, but eventually they call
# a script tools/build_pytorch_libs.sh
# whcih passes EXTRA_CAFFE2_CMAKE_FLAGS at the end of the cmake command
# to all 3rd party libraries.
export EXTRA_CAFFE2_CMAKE_FLAGS="-DUSE_MPI=OFF -DUSE_NUMA=OFF -DUSE_NCCL=OFF -DATEN_NO_TEST=OFF"
# Why do I need to export these?
#
# The CMake for onnx reports:
# therefore, it clearly has a bug somewhere
# --   Protobuf compiler     : /home/mark2/miniconda3/envs/compile/bin/protoc
# --   Protobuf includes     : /usr/include
# --   Protobuf libraries    : /home/mark2/miniconda3/envs/compile/lib/libprotobuf.so;-lpthread
# export CXXFLAGS="-I{{ PREFIX }}/include/ $CXXFLAGS"  # [unix]
# export CFLAGS="-I{{ PREFIX }}/include/ $CFLAGS"  # [unix]
# How do we add /std:c++11 to windows CFLAGS
# There is an other weird python package called ninja
# which is their preferred method of building
# that said, it does nothing but call "ninja"
$PYTHON -m pip install . -vv
