#!/usr/bin/env bash
# Runs the headless test scenes in tests/ and summarises them.
#
#   GODOT=/path/to/godot tools/run_tests.sh               # every *_test.gd
#   GODOT=/path/to/godot tools/run_tests.sh climb_test ...  # just these
#
# Each test prints PASS/FAIL lines and exits non-zero on a failure; logs go
# to $TEST_LOGS (default: a temporary folder). Exits 1 if any test failed.
set -u
cd "$(dirname "$0")/.."

GODOT="${GODOT:-godot}"
if ! command -v "$GODOT" >/dev/null 2>&1; then
	echo "Godot not found: set GODOT to the Godot 4.6 executable." >&2
	exit 2
fi
LOGS="${TEST_LOGS:-$(mktemp -d)}"
mkdir -p "$LOGS"
TIMEOUT="${TEST_TIMEOUT:-600}"

if [ $# -gt 0 ]; then
	tests=("$@")
else
	tests=()
	for f in tests/*_test.gd; do tests+=("$(basename "$f" .gd)"); done
fi

# The project must have been imported once (class names, resources).
if [ ! -d .godot ]; then
	echo "Importing the project (first run)..."
	"$GODOT" --headless --path . --import >"$LOGS/import.log" 2>&1
fi

failed=()
for t in "${tests[@]}"; do
	log="$LOGS/$t.log"
	timeout "$TIMEOUT" "$GODOT" --headless --path . --fixed-fps 60 --script "res://tests/$t.gd" >"$log" 2>&1
	code=$?
	passes=$(grep -c ' PASS ' "$log")
	fails=$(grep -c ' FAIL ' "$log")
	errors=$(grep -c 'SCRIPT ERROR' "$log")
	if [ $code -ne 0 ] || [ "$fails" -gt 0 ] || [ "$errors" -gt 0 ]; then
		failed+=("$t")
		status="FAILED"
		[ $code -eq 124 ] && status="TIMED OUT"
	else
		status="ok"
	fi
	printf '%-26s %-9s %3d passed, %d failed\n' "$t" "$status" "$passes" "$fails"
done

echo
if [ ${#failed[@]} -eq 0 ]; then
	echo "All ${#tests[@]} test files passed. Logs: $LOGS"
else
	echo "${#failed[@]} of ${#tests[@]} failed: ${failed[*]}  (logs: $LOGS)"
	exit 1
fi
