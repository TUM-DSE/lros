cmake_minimum_required(VERSION 3.25)
project(saxpy LANGUAGES C CXX CUDA)

find_package(CUDAToolkit REQUIRED COMPONENTS cudart cublas)

find_library(VACCEL vaccel)

add_library(saxpy SHARED saxpy.cu vaccel.c)
target_link_libraries(saxpy PUBLIC CUDA::cublas CUDA::cudart m ${VACCEL})
target_compile_features(saxpy PRIVATE cxx_std_14)
target_compile_options(saxpy PRIVATE $<$<COMPILE_LANGUAGE:CUDA>:
                                     --expt-relaxed-constexpr>)

install(TARGETS saxpy)
