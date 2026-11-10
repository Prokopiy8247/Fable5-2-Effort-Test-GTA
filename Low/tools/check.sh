#!/bin/sh
# Headless parse/boot check with a hard time limit (GPU-free).
G="/w/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
timeout 120 "$G" --headless --path . --quit-after ${1:-3} 2>&1 | grep -E "ERROR|Parse Error|Compile Error|at: |\[boot\]|\[nav\]|\[test\]|WARNING" | grep -v "^$" | head -${2:-40}
