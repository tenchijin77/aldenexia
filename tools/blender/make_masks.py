# make_masks.py — finds where a Meshy character's texture is SKIN, HAIR and EYES, for the appearance sliders
# (2026-09-25). Meshy bakes everything into one texture and one mesh, so the regions are found on the model itself:
#   1. seeds: the hair at the crown (top of the head), the skin at the nose, the eyes either side of the nose bridge;
#   2. a flood fill over the mesh's faces from each seed, taking in neighbouring faces whose texture colour stays close
#      to the seed's colour (so the hair stops where the shirt begins, even if a brown corset elsewhere is hair-coloured);
#   3. inside the faces found, every texel is weighed by how close its colour is to the region's colour: soft edges.
# Writes <out>.png: red = skin, green = hair, blue = eyes (1024 px, same UVs as the texture). The game's appearance
# shader recolours each region (Scripts/appearance.gd). A model without hair (lizardkin) gets no hair mask.
#   blender -b --python tools/blender/make_masks.py -- "<model.fbx>" "<texture.png>" "<out.png>" [preview.png] [nohair]
import bpy, bmesh, sys, os, math
import numpy as np
from mathutils import Vector
from collections import deque

argv = sys.argv[sys.argv.index("--") + 1:]
src, tex_path, out_path = argv[0], argv[1], argv[2]
preview = argv[3] if len(argv) > 3 and argv[3].endswith(".png") else ""
nohair = "nohair" in argv
# per-model tuning (tools/blender/mask_config.json, keyed by the model folder name): thresholds, extra seeds, no hair
import json
_cfg_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mask_config.json")
CFG = json.load(open(_cfg_path)).get(os.path.basename(os.path.dirname(src)), {}) if os.path.exists(_cfg_path) else {}
nohair = nohair or CFG.get("nohair", False)
SKIN_T = CFG.get("skin_threshold", 12.0)
HAIR_T = CFG.get("hair_threshold", 15.0)
SIZE = 1024

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=src)
obj = next(o for o in bpy.data.objects if o.type == 'MESH')
mw = obj.matrix_world
img = bpy.data.images.load(tex_path)
W, Hh = img.size
px = np.empty(W * Hh * 4, dtype=np.float32)
img.pixels.foreach_get(px)
px = px.reshape(Hh, W, 4)[:, :, :3]       # row 0 = bottom (Blender), values sRGB 0..1


def to_lab(rgb):
    rgb = np.asarray(rgb, dtype=np.float32)
    lin = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)
    m = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]], dtype=np.float32)
    xyz = lin @ m.T / np.array([0.9505, 1.0, 1.089], dtype=np.float32)
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])], axis=-1)


def light_weight(ref, base):
    """How much lightness counts: little for a colourful region (red hair's highlights and shadows are still red hair),
    fully for a nearly grey one (black hair vs a white shirt differ ONLY in lightness)."""
    chroma = math.hypot(float(ref[1]), float(ref[2]))
    return base + (1.0 - base) * max(0.0, min(1.0, (22.0 - chroma) / 14.0))


def dist(lab, ref, lw):   # colour distance; lightness counts for less (shading, highlights)
    d = lab - ref
    return np.sqrt((d[..., 0] * lw) ** 2 + d[..., 1] ** 2 + d[..., 2] ** 2)


bm = bmesh.new()
bm.from_mesh(obj.data)
bm.faces.ensure_lookup_table()
# the UV map the texture is drawn with (some exports carry two, and the one active for editing isn't it)
render_uv = next((l.name for l in obj.data.uv_layers if l.active_render), None)
uv = bm.loops.layers.uv.get(render_uv) if render_uv else bm.loops.layers.uv.active
print("UV maps", [l.name for l in obj.data.uv_layers], "using", render_uv)
face_uv = [[l[uv].uv.copy() for l in f.loops] for f in bm.faces]
face_pos = [mw @ f.calc_center_median() for f in bm.faces]
zs = [(mw @ v.co).z for v in bm.verts]
z0, H = min(zs), max(zs) - min(zs)


def sample(u, v):
    x = min(W - 1, max(0, int(u % 1.0 * W)))
    y = min(Hh - 1, max(0, int(v % 1.0 * Hh)))
    return px[y, x]


face_lab = []
for uvs in face_uv:
    c = sum(uvs, Vector((0, 0))) / len(uvs)
    cols = [sample(c.x, c.y)] + [sample(*(c * 0.5 + p * 0.5)) for p in uvs]
    face_lab.append(np.median(to_lab(np.array(cols)), axis=0))
face_lab = np.array(face_lab)


def nearest_face(pred):
    best, bi = None, -1
    for i, p in enumerate(face_pos):
        k = pred(p)
        if k is not None and (best is None or k < best):
            best, bi = k, i
    return bi


def flood(seed, ref, thresh, lw, allow=lambda p: True, rival=None):
    """Grows from `seed` over faces within `thresh` of `ref`. With a `rival` colour a face joins only if it is closer to
    `ref` than to the rival (dark brown hair and tan skin can both be "near" each other once lightness counts for little;
    this makes each face go to the one it's really nearer)."""
    got = {seed}
    q = deque([seed])
    while q:
        f = bm.faces[q.popleft()]
        for e in f.edges:
            for g in e.link_faces:
                if g.index not in got and allow(face_pos[g.index]) and dist(face_lab[g.index], ref, lw) < thresh \
                        and (not rival or all(dist(face_lab[g.index], ref, 1.0) < dist(face_lab[g.index], r, 1.0) for r in rival)):
                    got.add(g.index)
                    q.append(g.index)
    return got


def ref_around(seed, rings=2):
    ring = {seed}
    for _ in range(rings):
        ring |= {g.index for i in list(ring) for e in bm.faces[i].edges for g in e.link_faces}
    return np.median(face_lab[list(ring)], axis=0)


# seeds, placed from the head bone (a dwarf's or gnome's head is a bigger share of its height than an elf's)
arm = next((o for o in bpy.data.objects if o.type == 'ARMATURE'), None)
head_b = arm.data.bones.get("Head") if arm else None
head_z = (arm.matrix_world @ head_b.head_local).z if head_b else z0 + 0.85 * H
top = z0 + H
hh = top - head_z                                       # neck-top to crown
# the nose tip: the most forward point of the head's lower half; the cheeks sit either side of it, a little lower (the
# eyes, brows and lashes above them are dark and would spoil the skin colour)
nose = nearest_face(lambda p: p.y if abs(p.x) < 0.08 * hh and head_z < p.z < head_z + 0.55 * hh else None)
nz0 = face_pos[nose].z
cheek_z = nz0 - CFG.get("cheek_below_nose", 0.04) * hh
# candidate skin spots: the nose, the inner cheeks, the middle of the forehead, the chin. Hair framing a narrow face or a
# fringe can cover some of them, so they vote: the biggest group of matching colours is the skin.
cands = [nose] if CFG.get("skin_seed") != "forehead" else []
for s in ((1, -1) if CFG.get("skin_seed") != "forehead" else ()):
    for dx in (0.08, 0.12, 0.16, 0.22):
        f = nearest_face(lambda p, s=s, dx=dx: p.y if abs(p.z - cheek_z) < 0.05 * hh and abs(s * p.x - dx * hh) < 0.03 * hh else None)
        if f >= 0:
            cands.append(f)
for dz in ((0.22, -0.2) if CFG.get("skin_seed") != "forehead" else (0.2, 0.26, 0.32)):
    f = nearest_face(lambda p, dz=dz: p.y if abs(p.x) < 0.05 * hh and abs(p.z - (nz0 + dz * hh)) < 0.04 * hh else None)
    if f >= 0:
        cands.append(f)
cand_labs = np.array([ref_around(c, 1) for c in cands])
votes = [sum(1 for m in cand_labs if dist(m, l, 1.0) < 10.0) for l in cand_labs]
best = int(np.argmax(votes))
cheeks = [c for c, lab in zip(cands, cand_labs) if dist(lab, cand_labs[best], 1.0) < 10.0]
skin_ref = np.median(np.array([cand_labs[i] for i, c in enumerate(cands) if c in cheeks]), axis=0)
back = nearest_face(lambda p: -p.y if abs(p.x) < 0.2 * hh and abs(p.z - (head_z + 0.6 * hh)) < 0.1 * hh else None)
crown = nearest_face(lambda p: -(p.z) if abs(p.x) < 0.05 * H else None)
print("SEEDS nose z %.3f, %d of %d skin spots agree, skin %s" % (nz0, len(cheeks), len(cands), np.round(skin_ref, 1).tolist()))
skin_lw = light_weight(skin_ref, 0.35)
refs = {"skin": skin_ref}
hair_ref = None
if not nohair:
    # the back of the head is the surest hair (a crown can wear goggles or a hood); a bald head there is skin-coloured
    seed = back if CFG.get("hair_seed", "back") == "back" else crown
    hair_ref = ref_around(seed, 1)
    if dist(hair_ref, skin_ref, 1.0) <= 8.0:
        hair_ref = None
# the clothes' colours, as rivals for the skin: a sleeve (top of the upper arm), the waist and a thigh, front. A white
# blouse is almost the colour of pale skin; with these a face goes to whichever it's really nearer. Bare arms or legs
# match the skin and are left out.
cloth = []
for pred in () if CFG.get("no_cloth_rivals") else (lambda p: -p.z if 0.16 * H < p.x < 0.24 * H else None,
             lambda p: p.y if abs(p.x) < 0.03 * H and abs(p.z - z0 - 0.6 * H) < 0.02 * H else None,
             lambda p: p.y if 0.03 * H < p.x < 0.08 * H and abs(p.z - z0 - 0.4 * H) < 0.02 * H else None):
    f = nearest_face(pred)
    if f >= 0:
        lab = ref_around(f, 1)
        if dist(lab, skin_ref, 1.0) > 6.0:
            cloth.append(lab)
skin_rivals = cloth + ([hair_ref] if hair_ref is not None else [])
# a model whose sleeves are the very colour of its skin: skin only within this far of the middle (share of height)
skin_allow = (lambda p: abs(p.x) < CFG["skin_max_x"] * H) if "skin_max_x" in CFG else (lambda p: True)
regions = {"skin": set()}
for s0 in cheeks:
    regions["skin"] |= flood(s0, skin_ref, SKIN_T, skin_lw, rival=skin_rivals, allow=skin_allow)
# more skin seeds where sleeves cut the skin off from the face: the fingertips and the tops of the upper arms; each is
# used only if its colour is really the face's skin colour
extra = [nearest_face(lambda p, s=s: -s * p.x) for s in (1, -1)]
for s in (1, -1):
    extra.append(nearest_face(lambda p, s=s: -p.z if 0.2 * H < s * p.x < 0.3 * H else None))
for seed0 in extra:
    if seed0 >= 0 and seed0 not in regions["skin"] and dist(ref_around(seed0, 1), skin_ref, skin_lw) < 10.0:
        regions["skin"] |= flood(seed0, skin_ref, SKIN_T, skin_lw, rival=skin_rivals, allow=skin_allow)
if hair_ref is not None:
    regions["hair"] = flood(seed, hair_ref, HAIR_T, light_weight(hair_ref, 0.25), allow=lambda p: p.z - z0 > 0.3 * H, rival=[skin_ref])
    refs["hair"] = hair_ref
# eyes: faces around each eye (either side of the nose bridge, a little above the nose) that are NOT skin
eyes = set()
nz = face_pos[nose].z
for side in (1, -1):
    for i, p in enumerate(face_pos):
        if 0.08 * hh < side * p.x < 0.3 * hh and nz + 0.04 * hh < p.z < nz + 0.25 * hh and p.y < face_pos[nose].y + 0.25 * hh:
            if i not in regions["skin"]:
                eyes.add(i)
regions["eyes"] = eyes
print("MASKS", {k: len(v) for k, v in regions.items()}, "cloth rivals", len(cloth), "skin ref", np.round(skin_ref, 1), "hair ref", np.round(refs.get("hair", [0, 0, 0]), 1))

# rasterise each region's faces into the mask, texel by texel, weighed by colour
mask = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
small = px[:: max(1, Hh // SIZE), :: max(1, W // SIZE)][:SIZE, :SIZE]
small_lab = to_lab(small)
chan = {"skin": 0, "hair": 1, "eyes": 2}
soft = {"skin": (SKIN_T * 0.8, SKIN_T * 1.5, 0.35), "hair": (HAIR_T * 0.9, HAIR_T * 1.6, 0.25)}
for name, faces in regions.items():
    c = chan[name]
    for fi in faces:
        tri = face_uv[fi]
        pts = np.array([[t.x % 1.0 * SIZE, t.y % 1.0 * SIZE] for t in tri])
        x0, y0 = np.floor(pts.min(0)).astype(int)
        x1, y1 = np.ceil(pts.max(0)).astype(int)
        x0, y0 = max(0, x0 - 1), max(0, y0 - 1)
        x1, y1 = min(SIZE - 1, x1 + 1), min(SIZE - 1, y1 + 1)
        if x1 < x0 or y1 < y0:
            continue
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        inside = np.zeros_like(gx, dtype=bool)
        for k in range(1, len(pts) - 1):   # fan-triangulate the face
            a, b, cc = pts[0], pts[k], pts[k + 1]
            d = (b[1] - cc[1]) * (a[0] - cc[0]) + (cc[0] - b[0]) * (a[1] - cc[1])
            if abs(d) < 1e-9:
                continue
            l1 = ((b[1] - cc[1]) * (gx - cc[0]) + (cc[0] - b[0]) * (gy - cc[1])) / d
            l2 = ((cc[1] - a[1]) * (gx - cc[0]) + (a[0] - cc[0]) * (gy - cc[1])) / d
            inside |= (l1 >= -0.02) & (l2 >= -0.02) & (1 - l1 - l2 >= -0.02)
        if name == "eyes":
            # the iris: a mid-tone that isn't skin, right beside the white of the eye (lids, brows and liner aren't next
            # to the white; lashes and the pupil are too dark). The white: bright and colourless.
            pad = 6
            ya, yb, xa, xb = max(0, y0 - pad), min(SIZE, y1 + 1 + pad), max(0, x0 - pad), min(SIZE, x1 + 1 + pad)
            big = small_lab[ya:yb, xa:xb]
            white = (big[..., 0] > 76) & (np.hypot(big[..., 1], big[..., 2]) < 10) & (dist(big, skin_ref, 1.0) > 8)
            near = np.zeros_like(white)
            for dy in range(-pad, pad + 1, 2):
                for dx in range(-pad, pad + 1, 2):
                    near |= np.roll(np.roll(white, dy, 0), dx, 1)
            near = near[y0 - ya:y0 - ya + (y1 - y0 + 1), x0 - xa:x0 - xa + (x1 - x0 + 1)]
            lab = small_lab[y0:y1 + 1, x0:x1 + 1]
            not_hair = dist(lab, refs["hair"], 0.6) > 14 if "hair" in refs else np.ones(lab.shape[:2], bool)   # brows
            w = ((lab[..., 0] > 22) & (lab[..., 0] < 66) & (dist(lab, skin_ref, 0.6) > 16) & near & not_hair).astype(np.float32)
        else:
            lo, hi, lw = soft[name]
            lw = light_weight(refs[name], lw)
            lab = small_lab[y0:y1 + 1, x0:x1 + 1]
            dd = dist(lab, refs[name], lw)
            w = np.clip((hi - dd) / (hi - lo), 0.0, 1.0)
            others = skin_rivals if name == "skin" else [skin_ref]
            for other in others:
                w = w * (dist(lab, refs[name], 1.0) < dist(lab, other, 1.0))
        region = mask[y0:y1 + 1, x0:x1 + 1, c]
        np.maximum(region, np.where(inside, w, 0.0), out=region)
# hair wins over skin where both claim a texel (hairline)
mask[..., 0] *= 1.0 - mask[..., 1]

# each region's own colour (sRGB, the average of the texels it covers): the shader recolours relative to it
refs_srgb = {}
for name, c in chan.items():
    m = mask[..., c]
    if m.sum() > 1.0:
        refs_srgb[name] = [round(float((small[..., k] * m).sum() / m.sum()), 4) for k in range(3)]
json.dump({"_comment": "make_masks.py: each region's original colour (sRGB 0-1); the mask is " + os.path.basename(out_path),
           "skin": refs_srgb.get("skin"), "hair": refs_srgb.get("hair"), "eyes": refs_srgb.get("eyes")},
          open(out_path[:-4] + ".json", "w"), indent=1)
out = bpy.data.images.new("mask", SIZE, SIZE, alpha=False)
out.pixels.foreach_set(np.concatenate([mask, np.ones((SIZE, SIZE, 1), np.float32)], axis=2).ravel())
out.filepath_raw = out_path
out.file_format = 'PNG'
out.save()
print("WROTE", out_path)

if preview:
    # the texture recoloured: skin -> green, hair -> blue, eyes -> red (to check the masks by eye)
    full = np.repeat(np.repeat(mask, max(1, Hh // SIZE), 0), max(1, W // SIZE), 1)[:Hh, :W]
    lum = px.mean(axis=2, keepdims=True)
    rec = px.copy()
    for c, col in [(0, (0.2, 0.9, 0.2)), (1, (0.2, 0.4, 1.0)), (2, (1.0, 0.1, 0.1))]:
        m = full[..., c:c + 1]
        rec = rec * (1 - m) + (lum * 1.6 * np.array(col, np.float32)) * m
    pimg = bpy.data.images.new("prev", W, Hh, alpha=False)
    pimg.pixels.foreach_set(np.concatenate([np.clip(rec, 0, 1), np.ones((Hh, W, 1), np.float32)], axis=2).ravel())
    mat = bpy.data.materials.new("p"); mat.use_nodes = True
    tn = mat.node_tree.nodes.new("ShaderNodeTexImage"); tn.image = pimg
    mat.node_tree.links.new(tn.outputs[0], mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"])
    for i in range(len(obj.data.materials)):
        obj.data.materials[i] = mat
    scene = bpy.context.scene
    scene.render.resolution_x = 500; scene.render.resolution_y = 700
    scene.view_settings.view_transform = 'Standard'
    wd = bpy.data.worlds.new("w"); scene.world = wd; wd.use_nodes = True; wd.node_tree.nodes["Background"].inputs[1].default_value = 2.0
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); scene.collection.objects.link(cam); scene.camera = cam
    cam.data.type = 'ORTHO'; cam.data.ortho_scale = 0.55 * H
    cam.location = Vector((0, -3, z0 + 0.78 * H)); cam.rotation_euler = (math.radians(90), 0, 0)
    scene.render.filepath = preview
    bpy.ops.render.render(write_still=True)
