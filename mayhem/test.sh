#!/usr/bin/env bash
# ArduinoJson/mayhem/test.sh — RUN the Catch/ctest suite built by mayhem/build.sh (normal flags).
# Behavioral anchor: Catch prints "N assertions in M test cases" when tests actually execute.
# A neutered exit(0) binary prints nothing — ctest alone would false-pass (§6.3).
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "$SRC"

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

[ -d "$SRC/build-tests" ] || { echo "missing build-tests — run mayhem/build.sh first" >&2; emit_ctrf "cmake-ctest" 0 1; exit 2; }

out="$(cd "$SRC/build-tests" && ctest -LE Fuzzing --output-on-failure 2>&1)"; rc=$?
echo "$out"

total=$(printf '%s\n' "$out" | sed -n 's/.* out of \([0-9][0-9]*\)$/\1/p' | tail -1)
failed=$(printf '%s\n' "$out" | sed -n 's/.*, \([0-9][0-9]*\) tests failed.*/\1/p' | tail -1)

if [ -z "${total:-}" ] || [ -z "${failed:-}" ]; then
  echo "could not parse ctest summary; exit code $rc" >&2
  emit_ctrf "cmake-ctest" 0 1
  exit $?
fi
: "${failed:=0}"
passed=$((total - failed))

# Sum Catch assertion counts from representative binaries (not just ctest exit status).
MIN_ASSERTIONS=500
assertions=0
for bin in \
  "$SRC/build-tests/extras/tests/JsonDocument/JsonDocumentTests" \
  "$SRC/build-tests/extras/tests/JsonDeserializer/JsonDeserializerTests" \
  "$SRC/build-tests/extras/tests/JsonSerializer/JsonSerializerTests"; do
  [ -x "$bin" ] || { echo "missing runner $bin" >&2; emit_ctrf "cmake-ctest" 0 1; exit 2; }
  bout="$("$bin" 2>&1)" || true
  echo "$bout" | tail -3
  a=$(printf '%s\n' "$bout" | sed -n 's/.*(\([0-9][0-9]*\) assertions in.*/\1/p' | tail -1)
  [ -n "$a" ] && assertions=$((assertions + a))
done

if [ "$failed" -gt 0 ] || [ "$passed" -lt 1 ] || [ "$assertions" -lt "$MIN_ASSERTIONS" ]; then
  echo "behavioral check failed: passed=$passed failed=$failed assertions=$assertions (need >=$MIN_ASSERTIONS)" >&2
  emit_ctrf "cmake-ctest" "$passed" "$failed"
  exit 1
fi

emit_ctrf "cmake-ctest" "$passed" "$failed"
