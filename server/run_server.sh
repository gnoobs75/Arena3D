#!/bin/bash
echo "=== Arena Relay Server ==="
echo "Starting relay server on port 8765..."
echo

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Try common Godot locations
if command -v godot &> /dev/null; then
    godot --headless --path "$PROJECT_DIR" "res://server/relay_server.tscn"
elif [ -f "/c/Godot/Godot_v4.5.1-stable_mono_win64_console.exe" ]; then
    "/c/Godot/Godot_v4.5.1-stable_mono_win64_console.exe" --headless --path "$PROJECT_DIR" "res://server/relay_server.tscn"
else
    echo "ERROR: Godot not found. Please install Godot or set the path in this script."
    exit 1
fi
