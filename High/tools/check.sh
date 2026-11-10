#!/bin/bash
# Parses every project script headlessly and prints unique script errors (no rendering, no GPU load).
G="/w/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
cd "$(dirname "$0")/.."
timeout 240 "$G" --headless --path . --import > tools/_out/check.log 2>&1
grep -A1 -E "SCRIPT ERROR|^ERROR" tools/_out/check.log | grep -v "^--" | paste - - | sed 's/SCRIPT ERROR: //' | sort -u | head -${1:-60}
