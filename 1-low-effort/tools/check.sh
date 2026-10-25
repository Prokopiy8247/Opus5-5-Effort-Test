#!/bin/sh
# Parse-checks every GDScript in the project; prints errors only.
G="W:/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
for f in $(find scripts -name "*.gd"); do
  "$G" --headless --path . --check-only --script "res://$f" 2>&1 | grep -E "SCRIPT ERROR|Parse Error|at: GDScript::reload" | grep -v "depended" | sed "s|^|$f: |" | head -6
done
