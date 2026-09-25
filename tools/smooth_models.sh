#!/usr/bin/env bash
# smooth_models.sh — rebuilds every character model's mesh smooth (2026-09-25; see tools/blender/smooth_character.py and
# tools/make_smooth_models.gd). The FBX files are never changed: each gets a <scene>_smooth_mesh.res next to it, which
# the game uses instead of the FBX's faceted mesh (MeshSmoothing.use_rebuilt_mesh). Delete a .res to go back.
#   bash tools/smooth_models.sh                       every model in Player3D.CHARACTER_MODELS
#   bash tools/smooth_models.sh "models/Elf Male/Elf Male Breathing Idle.fbx"   just that one
cd "$(dirname "$0")/.." || exit 1
BLENDER="${BLENDER:-blender}"
GODOT="${GODOT:-godot}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
if [ $# -gt 0 ]; then
	scenes=("$@")
else
	mapfile -t scenes < <(grep -o '"scene": *"res://models/[^"]*Breathing Idle.fbx"' Scripts/player3d.gd | sed 's/.*"res:\/\/\(.*\)"/\1/')
fi
# Body shaping for the women (tools/blender/shape_body.py: bust, waist, hips), user 2026-09-25: "keep them busty and
# beautiful". Chosen from side-by-side renders of the half-elf female; lighter on the big and scaly races.
declare -A SHAPE=(
	["Human Female"]="0.4,0.07,0.05" ["Half-Elf Female"]="0.4,0.07,0.05" ["Elf Female"]="0.4,0.07,0.05"
	["Dark Elf Female"]="0.4,0.07,0.05" ["Half-Orc Female"]="0.4,0.06,0.05" ["Dwarf Female"]="0.4,0.05,0.05"
	["Halfling Female"]="0.4,0.05,0.05" ["Gnome Female"]="0.35,0.05,0.04" ["Troll Female"]="0.3,0.05,0.04"
	["Ogre Female"]="0.3,0.04,0.04" ["Lizardkin Female"]="0.2,0.04,0.03"
)
RENDERS="${RENDERS:-}"   # set to a folder to also save check renders of each model
status=0
for scene in "${scenes[@]}"; do
	scene="${scene#res://}"
	glb="$WORK/$(basename "$scene" .fbx).glb"
	echo "== $scene"
	folder="$(basename "$(dirname "$scene")")"
	extra=()
	[ -n "${SHAPE[$folder]:-}" ] && extra+=("shape=${SHAPE[$folder]}")
	if [ -n "$RENDERS" ]; then
		tex="$(ls "$(dirname "$scene")"/*_texture_0.png 2>/dev/null | head -1)"
		extra=(0 "$RENDERS/$folder" "$tex" "${extra[@]}")
	fi
	"$BLENDER" -b --python tools/blender/smooth_character.py -- "$scene" "$glb" "${extra[@]}" 2>&1 | grep -E "SMOOTHED|SHAPE|Error" | grep -v OCIO
	if [ ! -f "$glb" ]; then echo "   Blender failed"; status=1; continue; fi
	"$GODOT" --headless --path . --script res://tools/make_smooth_models.gd -- "res://$scene" "$glb" 2>&1 | grep -E "triangles|^ERROR: [a-zA-Z]|can't|doesn't|isn't|no skinned" || status=1
done
exit $status
