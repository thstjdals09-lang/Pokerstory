#!/usr/bin/env bash
# Runs the unit tests and the end-to-end first-play scenarios headlessly.
# Usage: tools/run_tests.sh [unit|e2e|all]   (default: all)
# Set GODOT to the Godot 4.7.2 console executable if it is not at the default location.
set -u
GODOT="${GODOT:-/c/Users/a/tools/godot/Godot_v4.7.2-stable_win64_console.exe}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GAME="$ROOT/game"
MODE="${1:-all}"
status=0

"$GODOT" --headless --path "$GAME" --import >/dev/null 2>&1

if [ "$MODE" = "unit" ] || [ "$MODE" = "all" ]; then
  echo "== unit tests =="
  "$GODOT" --headless --path "$GAME" -s res://tests/run_tests.gd || status=1
fi

if [ "$MODE" = "e2e" ] || [ "$MODE" = "all" ]; then
  for scenario in path_a path_b path_c path_d1 path_d2 broke migrate reject cc04 story cc05 cc06; do
    save="user://e2e_$(echo "$scenario" | sed 's/[0-9]$//').json"
    echo "== e2e: $scenario =="
    "$GODOT" --headless --path "$GAME" -- --e2e="$scenario" --save-path="$save" || status=1
  done
fi

exit $status
