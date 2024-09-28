cmake_minimum_required(VERSION 3.15)
project(MyCProject C)
find_package(Python3 REQUIRED COMPONENTS Interpreter Development NumPy)
set(CMAKE_C_STANDARD 99)
include_directories(${Python3_INCLUDE_DIRS})
include_directories(${Python3_NumPy_INCLUDE_DIRS})

add_executable(my_executable main.c)

target_link_libraries(my_executable Python3::Python)
