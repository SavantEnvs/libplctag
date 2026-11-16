#!/usr/bin/env bash
#
# mayhem/test.sh — RUN libplctag's own unit tests and simulator suite (built by mayhem/build.sh into build_tests/bin_dist).
# exit 0 = pass. EDIT per repo. PATCH-grade oracle: after an agent patches the source, the grader
# rebuilds (build.sh) then runs this. DELETE this file if the repo has no meaningful tests.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

BIN="$SRC/build_tests/bin_dist"
# binary:expected number of passing cases (from upstream's src/tests/*.c)
SUITES="test_init:2 test_platform_str:5 test_tag_name_bounds:6 test_eip_response_validation:3"

passed=0
failed=0
for entry in $SUITES; do
  name="${entry%%:*}"
  want="${entry##*:}"
  if [ ! -x "$BIN/$name" ]; then
    echo "FAIL: $BIN/$name is missing (mayhem/build.sh should have built it)" >&2
    failed=$((failed + want))
    continue
  fi
  out="$("$BIN/$name" 2>&1)"
  rc=$?
  echo "$out"
  got="$(printf '%s\n' "$out" | sed -n 's/^\[==========\] \([0-9][0-9]*\) test(s) passed\.$/\1/p' | tail -n1)"
  nfail="$(printf '%s\n' "$out" | grep -c '^\[  FAILED  \]' || true)"
  if [ "$rc" -eq 0 ] && [ "${got:-}" = "$want" ] && [ "$nfail" -eq 0 ]; then
    passed=$((passed + want))
  else
    echo "FAIL: $name rc=$rc passed-summary='${got:-none}' expected=$want" >&2
    failed=$((failed + want))
  fi
done

# 2) Upstream's simulator suite (what its CI runs in every job): tag_rw2, the examples and the test_*
#    clients against the in-tree ab_server/modbus_server on loopback (FUNCTIONAL, STRESS and TIMING
#    groups, incl. the --corrupt response-validation cases). Standard-library Python only; no network.
SIM_MIN=181   # tests in upstream's manifest at the time of integration; fewer results = the runner broke
SIM_LOGS="$(mktemp -d "${TMPDIR:-/tmp}/libplctag-sim.XXXXXX")"
sim_out="$(python3 "$SRC/src/tests/scripts/run_simulator_tests_parallel.py" "$BIN" "$SIM_LOGS" 2>&1)"
sim_rc=$?
echo "$sim_out"
# one result line per test: "<ts>   [section] test <id> (<group>): <name>... OK (12s)" / "... FAILURE (12s)"
sim_ok="$(printf '%s\n' "$sim_out" | grep -Ec '\] test [0-9]+ \([a-z]+\): .*\.\.\. OK \([0-9]+s\)' || true)"
sim_bad="$(printf '%s\n' "$sim_out" | grep -Ec '\] test [0-9]+ \([a-z]+\): .*\.\.\. FAILURE \([0-9]+s\)' || true)"
sim_total="$(printf '%s\n' "$sim_out" | sed -n 's/^.* - \([0-9][0-9]*\) tests\.$/\1/p' | tail -n1)"
if [ "$sim_rc" -ne 0 ] || [ "$sim_bad" -ne 0 ] || [ "${sim_total:-0}" -ne $((sim_ok + sim_bad)) ] \
   || [ "$sim_ok" -lt "$SIM_MIN" ]; then
  echo "FAIL: simulator suite rc=$sim_rc ok=$sim_ok failed=$sim_bad reported-total=${sim_total:-none} (need >= $SIM_MIN all OK); logs in $SIM_LOGS" >&2
  # tests that never reported (runner died, missing executables) count as failed
  missing=$(( SIM_MIN - sim_ok - sim_bad )); [ "$missing" -gt 0 ] || missing=0
  sim_bad=$(( sim_bad + missing ))
  [ "$sim_bad" -gt 0 ] || sim_bad=1
fi
passed=$((passed + sim_ok))
failed=$((failed + sim_bad))

emit_ctrf "libplctag-unit+simulator" "$passed" "$failed" 0
