project(cf_dummy LANGUAGES C CXX)
cmake_minimum_required(VERSION 3.12)
find_package(Python3 REQUIRED COMPONENTS Interpreter Development)
find_package(pybind11 CONFIG REQUIRED)
find_package(Torch CONFIG REQUIRED)
find_package(ATen CONFIG REQUIRED)
if(WIN32)
  set(libtorch_base_path $ENV{PREFIX}/Lib/site-packages/torch)
else()
  set(libtorch_base_path $ENV{PREFIX})
endif()
find_library(torch_python NAMES torch_python HINTS ${libtorch_base_path}/lib/ REQUIRED)
set(target_name cmake_test)
add_executable(${target_name} main.cpp)
target_include_directories(${target_name} PRIVATE
  ${ATEN_INCLUDE_DIR}
  ${TORCH_INCLUDE_DIRS}
  ${Python3_INCLUDE_DIRS}
)
target_link_libraries(${target_name} PRIVATE
  ${ATEN_LIBRARIES}
  ${TORCH_LIBRARIES}
  ${torch_python}
  pybind11::pybind11
  Python3::Python
)
target_compile_options(${target_name} PRIVATE
  ${TORCH_CXX_FLAGS}
)
