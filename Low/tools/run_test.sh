#!/bin/sh
# usage: tools/run_test.sh <plan> [headless|window] [timeout_s]
# Runs scripted autotests with a hard OS-level time limit and a 30 fps cap (see autotest.gd).
G="/w/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
MODE=${2:-headless}
T=${3:-240}
if [ "$MODE" = "headless" ]; then
  timeout $T "$G" --headless --path . -- --autotest=$1 2>&1 | grep -vE "^\s*$|Godot Engine|material_get_instance|dummy/storage" | head -${4:-70}
else
  timeout $T "$G" --path . --resolution 1280x720 --position 40,40 -- --autotest=$1 2>&1 | grep -vE "^\s*$|Godot Engine|Vulkan|Using Device" | head -${4:-70}
fi
