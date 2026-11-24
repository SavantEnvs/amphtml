#!/usr/bin/env bash
#
# mayhem/test.sh — RUN this repo's OWN functional test suite (already built by mayhem/build.sh).
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

# Upstream's own gtest suites (validator/cpp/**/*_test.cc), built by mayhem/build.sh with normal
# flags. validator_test is the golden-output suite: it validates every validator/testdata and
# extensions/*/*/test/*.html document and diffs the result against the checked-in .out file.
BIN="$SRC/mayhem/build/test/bin"
TESTS="tokenizer_test parser_test strings_test renderer_test url_test allocator_test atomutil_test
casetable_test doctype_test entity_test fileutil_test htmldataset_test node_test utf8_test
json_test types_test parse-css_test amp4ads-parse-css_test
validators_json_test validators_ipaddress_test validators_supported_media_query_test
parse-srcset_test parse-layout_test parse-viewport_test utf8-util_test parse-layout-sizes_test
error-formatter_test keyframes-parse-css_test type-identifier_test validator_test"
# validator_test globs testdata/*/*.html and external/amphtml-extensions/*/*/test/*.html (bazel
# runfiles layout) relative to its cwd: recreate that layout in a scratch dir.
RUN="$(mktemp -d "${TMPDIR:-/tmp}/amphtml-test.XXXXXX")"
trap 'rm -rf "$RUN"' EXIT
mkdir -p "$RUN/external"
ln -s "$SRC/validator/testdata" "$RUN/testdata"
ln -s "$SRC/extensions" "$RUN/external/amphtml-extensions"
# htmldataset_test globs testdata/tree-construction/*.dat and cpp/htmlparser/testdata/go/*.dat
# (htmlparser/testconstants.h): its own dir, since testdata/ above is validator/testdata.
HRUN="$RUN/htmldataset"
mkdir -p "$HRUN"
ln -s "$SRC/validator/cpp/htmlparser/testdata" "$HRUN/testdata"
ln -s "$SRC/validator/cpp" "$HRUN/cpp"

passed=0; failed=0
for t in $TESTS; do
  if [ ! -x "$BIN/$t" ]; then echo "missing test binary $BIN/$t (build.sh bug)" >&2; failed=$((failed+1)); continue; fi
  d="$RUN"; [ "$t" = htmldataset_test ] && d="$HRUN"
  out="$( (cd "$d" && "$BIN/$t") 2>&1)"; rc=$?
  p="$(printf '%s\n' "$out" | sed -n 's/^\[  PASSED  \] \([0-9]*\) test.*/\1/p' | tail -1)"
  f="$(printf '%s\n' "$out" | sed -n 's/^\[  FAILED  \] \([0-9]*\) test.*/\1/p' | tail -1)"
  p="${p:-0}"; f="${f:-0}"
  # A suite that ran no test, or exited non-zero without reporting a failure, counts as one failure.
  if [ "$p" -eq 0 ] && [ "$f" -eq 0 ]; then f=1; fi
  if [ "$rc" -ne 0 ] && [ "$f" -eq 0 ]; then f=1; fi
  echo "$t: passed=$p failed=$f (exit $rc)"
  [ "$f" -eq 0 ] || printf '%s\n' "$out" | grep -E '^\[  FAILED  \]|Failure' | head -20
  passed=$((passed+p)); failed=$((failed+f))
done
emit_ctrf "gtest" "$passed" "$failed" 0
