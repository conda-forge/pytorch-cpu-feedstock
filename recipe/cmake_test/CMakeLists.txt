project(cf_dummy LANGUAGES C CXX)
cmake_minimum_required(VERSION 3.12)

find_package(Torch CONFIG REQUIRED)
find_package(ATen CONFIG REQUIRED)

option(WITH_TORCH_PYTHON "Build with torch_python" OFF)

if(WITH_TORCH_PYTHON)
  if(WIN32)
    set(libtorch_base_path $ENV{PREFIX}/Lib/site-packages/torch)
  else()
    set(libtorch_base_path $ENV{PREFIX})
  endif()
  find_library(torch_python NAMES torch_python HINTS ${libtorch_base_path}/lib/ REQUIRED)

  find_package(Python3 REQUIRED COMPONENTS Interpreter Development)
  find_package(pybind11 CONFIG REQUIRED)

  add_executable(cmake_test main.cpp)

  target_include_directories(cmake_test PRIVATE
    ${ATEN_INCLUDE_DIR}
    ${TORCH_INCLUDE_DIRS}
    ${Python3_INCLUDE_DIRS}
  )

  target_link_libraries(cmake_test PRIVATE
    ${ATEN_LIBRARIES}
    ${TORCH_LIBRARIES}
    pybind11::pybind11
    Python3::Python
  )

  target_link_libraries(cmake_test PRIVATE
    ${torch_python}
  )

  set(MSVC_UTF8_FLAG)
  if(MSVC)
    # The source code is in utf-8 encoding
    set(MSVC_UTF8_FLAG "/utf-8")
  endif()

  target_compile_options(cmake_test PRIVATE
    ${TORCH_CXX_FLAGS}
    ${MSVC_UTF8_FLAG}
  )
endif()
