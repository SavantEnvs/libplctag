#!/usr/bin/env bash
#
# mayhem/build.sh — build libplctag's fuzz harnesses (sanitized, DWARF 3) and its unit-test suite.
# Runs inside the commit image as `mayhem` in /mayhem; re-runnable and network-free.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
# upstream match_numeric_segment() (cip.c) accumulates digits into an int and range-checks afterwards; the overflow is benign and floods the target. Applies library-wide (all four targets), see fuzz_cip_path/known-findings/README.md
: "${RELAX_FLAGS=-fno-sanitize=signed-integer-overflow}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${SRC:=/mayhem}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

HARNESSES="fuzz_attr fuzz_tag_name fuzz_cip_path fuzz_decoders"

# 1) The test suite first, with the project's NORMAL flags (Debug config, no sanitizers), in its own tree:
#    the unit tests plus everything upstream's simulator runner needs (examples, ab_server, modbus_server).
#    CMake takes the compiler from $CC/$CXX (exported above); never -DCMAKE_C_COMPILER (it wipes the cache on a re-run).
cmake -S . -B build_tests -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Debug \
      -DCMAKE_C_FLAGS="$COVERAGE_FLAGS" \
      -DBUILD_EXAMPLES=1 -DBUILD_TESTS=1 -DUSE_MEM_SANITIZERS=0 -DUSE_SERVER_MEM_SANITIZERS=0
cmake --build build_tests -j"$MAYHEM_JOBS"

# 2) The library itself with the fuzz flags (static archive; harnesses link its internal symbols).
cmake -S . -B build_fuzz -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=MinSizeRel \
      -DCMAKE_C_FLAGS="$SANITIZER_FLAGS -fsanitize=fuzzer-no-link $RELAX_FLAGS $DEBUG_FLAGS" \
      -DBUILD_EXAMPLES=0 -DBUILD_TESTS=0 -DUSE_MEM_SANITIZERS=0 -DUSE_SERVER_MEM_SANITIZERS=0
cmake --build build_fuzz -j"$MAYHEM_JOBS" --target plctag_static
LIB="$SRC/build_fuzz/bin_dist/libplctag_static.a"

INC="-I$SRC/src -I$SRC/src/libplctag -I$SRC/src/platform/posix"
DEFS="-D__USE_POSIX=1 -D_XOPEN_SOURCE=700 -D_POSIX_C_SOURCE=200809L -DPLCTAG_COMPILE_DEBUG_LEVEL=3 -DLIBPLCTAG_STATIC=1"

# 3) LeakSanitizer off, at build time (leaks are not what this fleet fuzzes for).
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.c" -o /tmp/lsan_off.o

# 4) Each harness twice: libFuzzer binary and a run-once standalone reproducer.
for h in $HARNESSES; do
    $CC $SANITIZER_FLAGS $DEBUG_FLAGS $DEFS $INC $LIB_FUZZING_ENGINE \
        "$SRC/mayhem/harnesses/$h.c" /tmp/lsan_off.o "$LIB" -lpthread -lm -o "$SRC/$h"
    $CC $SANITIZER_FLAGS $DEBUG_FLAGS $DEFS $INC "$STANDALONE_FUZZ_MAIN" \
        "$SRC/mayhem/harnesses/$h.c" /tmp/lsan_off.o "$LIB" -lpthread -lm -o "$SRC/$h-standalone"
done
