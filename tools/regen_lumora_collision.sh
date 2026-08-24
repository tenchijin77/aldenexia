#!/usr/bin/env bash
# Run this after every Blender re-export of zones/LumoraOutskirts.glb.
# Regenerates collision in Scenes/lumora_outskirts3d.tscn, then does a
# headless run of the scene to catch the degenerate-transform gotcha
# (a 0-scale axis on some Blender object silently corrupts physics —
# see game_flow.txt, "3D LEVEL COLLISION PIPELINE").
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== Regenerating collision from LumoraOutskirts.glb =="
godot --headless --path . --script res://tools/regen_lumora_collision.gd

echo
echo "== Sanity-checking scene physics =="
log="$(mktemp)"
godot --headless --path . res://Scenes/lumora_outskirts3d.tscn --quit-after 60 > "$log" 2>&1 || true

if grep -qE "det == 0|cannot be normalized" "$log"; then
	echo "!! Degenerate transform detected — a Blender object likely has a 0 scale on some axis."
	echo "!! (Blender Z-up maps to Godot Y-up, so check the object's Z-scale field.)"
	grep -E "det == 0|cannot be normalized" -B2 "$log"
	rm -f "$log"
	exit 1
fi

echo "OK — no degenerate transforms detected."
rm -f "$log"
