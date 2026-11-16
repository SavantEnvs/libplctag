# `match_numeric_segment()` signed integer overflow (src/libplctag/protocols/ab/cip.c)

`cip_encode_path()` -> `match_numeric_segment()` accumulates the decimal digits of a path segment
with `val = (val * 10) + digit` into an `int`. A path segment of 10+ digits (e.g. `3333333333`)
overflows it (undefined behaviour, caught by UBSan `signed-integer-overflow`). The value is range-checked
only afterwards (`val > 0x11`), so in practice the wrap is benign, but it is UB reachable from the
user-supplied `path=` tag attribute.

Reproduce: `/mayhem/fuzz_cip_path-standalone known-findings/signed_overflow.bin` on a build with
`RELAX_FLAGS=` (empty); the default build relaxes `-fno-sanitize=signed-integer-overflow` so this one
finding does not mask everything else the target can reach.

Fix: stop accumulating once `val > 0x11` (or use a wider type / `__builtin_mul_overflow`).

Scope of the relaxation: `RELAX_FLAGS` is applied to the whole library build (CMake gives no clean per-file
hook without editing upstream's `CMakeLists.txt`), so all four targets (`fuzz_attr`, `fuzz_tag_name`,
`fuzz_cip_path`, `fuzz_decoders`) run without `signed-integer-overflow` detection. ASan and every other UBSan
check stay halting.
