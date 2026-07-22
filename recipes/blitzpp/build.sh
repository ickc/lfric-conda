#!/usr/bin/env bash
set -euxo pipefail

# Upstream ships both autotools and CMake; CMake is the maintained path and the
# one Spack uses. BUILD_TESTING also gates examples/benchmarks, which we skip.
cmake -G Ninja -S . -B build \
  ${CMAKE_ARGS} \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_INSTALL_LIBDIR=lib \
  -DBUILD_SHARED_LIBS=ON \
  -DBUILD_TESTING=OFF \
  -DBUILD_DOC=OFF

cmake --build build --parallel "${CPU_COUNT:-2}"
cmake --install build
