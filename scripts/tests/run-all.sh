#!/usr/bin/env bash
# Runs every scripts/tests/test-*.sh (bash) and scripts/tests/test_*.py
# (Python) test and reports one line per test. Exit 1 if any test fails.
# Run from anywhere inside the repo.
set -u
ROOT="$(git rev-parse --show-toplevel)"
fail=0
for t in "$ROOT"/scripts/tests/test-*.sh; do
  [ -e "$t" ] || continue
  name="$(basename "$t")"
  if out="$(bash "$t" 2>&1)"; then
    echo "PASS $name"
  else
    echo "FAIL $name"
    echo "$out" | sed 's/^/    /'
    fail=1
  fi
done
for t in "$ROOT"/scripts/tests/test_*.py; do
  [ -e "$t" ] || continue
  name="$(basename "$t")"
  if out="$(python3 "$t" 2>&1)"; then
    echo "PASS $name"
  else
    echo "FAIL $name"
    echo "$out" | sed 's/^/    /'
    fail=1
  fi
done
echo "NOTE: this run did not cover scripts/tests/debrief-push-bench.sh (slow, builds throwaway repositories); run it by name after touching scripts/debrief-push.sh or scripts/debrief-verify.sh."
exit $fail
