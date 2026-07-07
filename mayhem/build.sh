#!/usr/bin/env bash
# ArduinoJson/mayhem/build.sh — sanitized json_fuzzer harness + standalone reproducer, plus the
# project's Catch/ctest suite (normal flags) for mayhem/test.sh.
#
# ArduinoJson is header-only: the fuzzed library code is compiled into the harness TU with
# $SANITIZER_FLAGS so ASan/UBSan see deserialize/serialize paths, not just the driver.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

HARNESS="$SRC/extras/fuzzing/json_fuzzer.cpp"
CXXFLAGS="-I$SRC/src -DARDUINOJSON_DEBUG=1 -std=c++11"

# 1) libFuzzer target (Mayhem)
# shellcheck disable=SC2086
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS $CXXFLAGS \
  "$HARNESS" $LIB_FUZZING_ENGINE \
  -o /mayhem/json_fuzzer

# 2) Standalone reproducer (C driver keeps extern "C" linkage for the harness)
# shellcheck disable=SC2086
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o /tmp/standalone_main.o
# shellcheck disable=SC2086
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS $CXXFLAGS \
  "$HARNESS" /tmp/standalone_main.o \
  -o /mayhem/json_fuzzer-standalone

# 3) Functional test suite — normal flags, gcc so extras/fuzzing/ is skipped (Clang-only)
cmake -S "$SRC" -B "$SRC/build-tests" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++ \
  -DCMAKE_C_FLAGS="$COVERAGE_FLAGS" \
  -DCMAKE_CXX_FLAGS="$COVERAGE_FLAGS" >/dev/null
cmake --build "$SRC/build-tests" -j"$MAYHEM_JOBS"
