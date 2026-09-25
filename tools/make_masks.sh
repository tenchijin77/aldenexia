#!/usr/bin/env bash
# make_masks.sh — builds every character model's appearance mask (skin / hair / eyes: tools/blender/make_masks.py),
# written next to the FBX as <scene>_mask.png. Re-run for a new or re-exported model.
#   bash tools/make_masks.sh [preview_folder]     (preview_folder: also save a recoloured check render of each)
cd "$(dirname "$0")/.." || exit 1
BLENDER="${BLENDER:-blender}"
PREVIEW="${1:-}"
python3 - <<'PY' > "${TMPDIR:-/tmp}/aldenexia_models.txt"
import re
t = open("Scripts/player3d.gd").read()
for a, b in re.findall(r'"scene":\s*"res://(models/[^"]+Breathing Idle\.fbx)"[^}]*?"texture_override":\s*"res://([^"]+)"', t, re.S):
    print(a + "|" + b)
PY
status=0
while IFS='|' read -r scene tex; do
	[ -z "$scene" ] && continue
	folder="$(basename "$(dirname "$scene")")"
	base="$(basename "$scene" .fbx | tr 'A-Z -' 'a-z__')"
	out="$(dirname "$scene")/${base}_mask.png"
	args=("$scene" "$tex" "$out")
	[ -n "$PREVIEW" ] && args+=("$PREVIEW/$folder.png")
	echo "== $folder"
	"$BLENDER" -b --python tools/blender/make_masks.py -- "${args[@]}" 2>&1 | grep -E "MASKS|Error" | grep -v OCIO || status=1
done < "${TMPDIR:-/tmp}/aldenexia_models.txt"
exit $status
