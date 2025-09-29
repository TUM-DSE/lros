cmake_minimum_required(VERSION 3.25)
project(plugins LANGUAGES C CXX CUDA)

find_package(CUDAToolkit REQUIRED COMPONENTS cudart cublas)

find_library(VACCEL vaccel)

# Add librknnrt here
#add_library(rknn SHARED rknn.c)
#target_link_libraries(rknn PUBLIC m ${VACCEL})
#target_compile_features(rknn PRIVATE cxx_std_14)

add_library(cuda SHARED cuda.cu)
target_link_libraries(cuda PUBLIC CUDA::cublas CUDA::cudart m ${VACCEL})
target_compile_features(cuda PRIVATE cxx_std_14)
target_compile_options(cuda PRIVATE $<$<COMPILE_LANGUAGE:CUDA>:
                                     --expt-relaxed-constexpr>)

install(TARGETS cuda)
