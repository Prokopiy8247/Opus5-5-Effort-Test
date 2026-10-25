#!/bin/bash
# Double-click this file to play. First launch downloads the Godot engine and prepares the game.
cd "$(dirname "$0")" || exit 1
PROJECT_DIR="$(pwd)"

GODOT_VERSION="4.7.2-stable"
CACHE_DIR="$HOME/Library/Application Support/OpusEffortTest/godot-$GODOT_VERSION"
GODOT_APP="$CACHE_DIR/Godot.app"
GODOT_BIN="$GODOT_APP/Contents/MacOS/Godot"
GODOT_URL="https://github.com/godotengine/godot-builds/releases/download/$GODOT_VERSION/Godot_v${GODOT_VERSION}_macos.universal.zip"

pause_and_exit() {
  echo
  read -n 1 -s -r -p "Press any key to close this window..."
  echo
  exit "${1:-1}"
}

echo "============================================================"
echo "  VALORIA: Open Road Festival"
echo "  Claude Opus 5.5 effort test: xhigh"
echo "============================================================"
echo

if [ ! -x "$GODOT_BIN" ]; then
  echo "[1/3] Downloading the Godot game engine, about 165 MB. This happens only once."
  mkdir -p "$CACHE_DIR" || pause_and_exit 1
  if ! curl -L --fail --progress-bar -o "$CACHE_DIR/godot.zip" "$GODOT_URL"; then
    echo
    echo "ERROR: could not download the Godot engine. Check your internet connection and try again."
    rm -f "$CACHE_DIR/godot.zip"
    pause_and_exit 1
  fi
  unzip -q -o "$CACHE_DIR/godot.zip" -d "$CACHE_DIR" || pause_and_exit 1
  rm -f "$CACHE_DIR/godot.zip"
  xattr -dr com.apple.quarantine "$GODOT_APP" 2>/dev/null
  chmod +x "$GODOT_BIN" 2>/dev/null
  if [ ! -x "$GODOT_BIN" ]; then
    echo "ERROR: Godot was not installed correctly. See README.md in the repository root."
    pause_and_exit 1
  fi
fi

if [ ! -f "$PROJECT_DIR/.godot/opus_import_done" ]; then
  echo "[2/3] First launch: preparing the game files. This can take 2-10 minutes. Please wait..."
  "$GODOT_BIN" --headless --path "$PROJECT_DIR" --import >/dev/null 2>&1
  [ -d "$PROJECT_DIR/.godot" ] && echo done > "$PROJECT_DIR/.godot/opus_import_done"
fi

echo "[3/3] Starting the game..."
"$GODOT_BIN" --path "$PROJECT_DIR"
STATUS=$?
if [ $STATUS -ne 0 ]; then
  echo
  echo "The game closed with an error. Please see README.md in the repository root."
  pause_and_exit $STATUS
fi
