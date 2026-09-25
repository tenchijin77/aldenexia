#!/usr/bin/env bash
# run_tests.sh — runs the regression suite (tools/tests/) headless. Exit code 0 = all passed.
#   bash tools/run_tests.sh              every test
#   bash tools/run_tests.sh quests trust only test_quests.gd and test_trust.gd
cd "$(dirname "$0")/.." || exit 1
GODOT="${GODOT:-godot}"
"$GODOT" --headless --path . --import >/dev/null 2>&1   # new scripts/class names must be registered first
out=$("$GODOT" --headless --path . res://tools/tests/run_tests.tscn -- "$@" 2>&1)
status=$?
echo "$out" | grep -E "^TEST |^    - |SCRIPT ERROR|Parse Error"
if ! echo "$out" | grep -q "^TEST RESULT OK"; then
	[ $status -eq 0 ] && status=1
fi
exit $status
