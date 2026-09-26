# animate_sitting_cat.py — brings Kenji to life (test 40: "and the same for Kenji"). His model is sculpted SITTING, his tail
# curled round his front paws, so he can't walk; instead he gets shape keys and an idle loop:
#   tail_left / tail_right — the curled tail sweeps side to side, the tip most, lifting a little off the ground
#   look_left / look_right — his head turns, pivoting at the neck
#   breathe                — the chest swells
# found from the mesh itself: the tail is the low geometry with no body above it; the head is everything above the neck.
# The idle (6 s) mixes them: tail flicks at odd moments, a look around, steady breathing. Exported as a .glb with the
# shape-key animation (Godot plays it as blend shapes).
#   blender -b --python tools/blender/animate_sitting_cat.py -- <in.fbx> <out.glb> [render_dir]
import bpy, sys, math, os
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:]
src, out = argv[0], argv[1]
render_dir = argv[2] if len(argv) > 2 else ""
FPS = 24

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=src)
obj = next(o for o in bpy.context.scene.objects if o.type == 'MESH')
bpy.context.view_layer.objects.active = obj
obj.select_set(True)
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
me = obj.data
V = [v.co.copy() for v in me.vertices]
zs = [p.z for p in V]
zmin, zmax = min(zs), max(zs)
H = zmax - zmin

# the tail: it lies low along his left side (-X), from behind him round to his front paws (found by slicing the model:
# the bottom quarter of his height, outside x TAIL_X). Soft edges, so the fur where it meets the body doesn't tear.
mid = [p for p in V if zmin + 0.12 * H <= p.z <= zmin + 0.45 * H]
cx = sum(p.x for p in mid) / len(mid)
cy = sum(p.y for p in mid) / len(mid)
# Where it curls round in front of his paws (y below TAIL_FRONT_Y) the boundary swings out to the right along a diagonal,
# and only the flat bottom layer counts there, so the tip comes along (test 42: "the middle moves, but the end of the
# tail is not attached and stays in place") without dragging his front legs.
TAIL_X = -0.28
TAIL_TOP = zmin + 0.36 * H
TAIL_FRONT_Y = -0.1
TAIL_FRONT_TOP = zmin + 0.16 * H
def tail_w(p):
    front = max(0.0, TAIL_FRONT_Y - p.y)
    edge = min(TAIL_X + front * 1.5, 0.1)
    wx = max(0.0, min(1.0, (edge - p.x) / 0.08))
    top = TAIL_TOP if p.x < TAIL_X else TAIL_FRONT_TOP
    wz = max(0.0, min(1.0, (top - p.z) / (0.06 * H)))
    return wx * wz
tail = [i for i, p in enumerate(V) if tail_w(p) > 0.0]
ys = [V[i].y for i in tail]
y_base, y_tip = max(ys), min(ys)           # it leaves the body behind him and ends at the front
base = Vector((sum(V[i].x for i in tail) / len(tail), y_base, zmin))
ang = {i: 0.0 for i in tail}
def along(i):
    return (y_base - V[i].y) / max(y_base - y_tip, 1e-6)
print("TAIL verts", len(tail), "of", len(V), "from y", round(y_base, 2), "to", round(y_tip, 2))

# the head: above the neck, pivoting at the neck
neck_z = zmin + 0.62 * H
head_top = [p for p in V if p.z > neck_z + 0.05 * H]
hx = sum(p.x for p in head_top) / len(head_top)
hy = sum(p.y for p in head_top) / len(head_top)
pivot = Vector((hx, hy, neck_z))
def head_weight(p):
    return max(0.0, min(1.0, (p.z - (neck_z - 0.06 * H)) / (0.14 * H)))

obj.shape_key_add(name="Basis")
def key(name, fn):
    k = obj.shape_key_add(name=name, from_mix=False)
    for i, p in enumerate(V):
        k.data[i].co = fn(i, p)
    return k

def tail_sweep(deg):
    def fn(i, p):
        if i not in ang:
            return p
        s = along(i)
        w = tail_w(p)
        r = Matrix.Rotation(math.radians(deg * s * s * w), 3, 'Z')
        pivot_here = Vector((base.x, base.y, p.z))
        return pivot_here + r @ (p - pivot_here) + Vector((0, 0, 0.05 * H * s * s * w))
    return fn

def look(deg):
    def fn(i, p):
        w = head_weight(p)
        if w <= 0.0:
            return p
        r = Matrix.Rotation(math.radians(deg * w), 3, 'Z')
        return pivot + r @ (p - pivot)
    return fn

def breathe(i, p):
    if not (zmin + 0.2 * H < p.z < neck_z):
        return p
    k = math.sin(math.pi * (p.z - (zmin + 0.2 * H)) / (neck_z - zmin - 0.2 * H))
    d = Vector((p.x - cx, p.y - cy, 0))
    return p + d * 0.025 * k

keys = {
    "tail_left": key("tail_left", tail_sweep(30)),
    "tail_right": key("tail_right", tail_sweep(-18)),
    "look_left": key("look_left", look(35)),
    "look_right": key("look_right", look(-35)),
    "breathe": key("breathe", breathe),
}

# the idle: [(second, value)] per key, over a 6 s loop
LOOP = 6.0
TRACKS = {
    "tail_left":  [(0, 0), (0.4, 0.9), (0.8, 0), (2.6, 0), (2.9, 0.5), (3.2, 0), (6, 0)],
    "tail_right": [(0, 0), (0.8, 0), (1.2, 0.8), (1.6, 0), (4.4, 0), (4.7, 1.0), (5.1, 0.2), (5.4, 0), (6, 0)],
    "look_left":  [(0, 0), (1.5, 0), (2.2, 1.0), (3.2, 1.0), (3.8, 0), (6, 0)],
    "look_right": [(0, 0), (4.0, 0), (4.5, 0.7), (5.4, 0.7), (6, 0)],
    "breathe":    [(0, 0), (1, 1), (2, 0), (3, 1), (4, 0), (5, 1), (6, 0)],
}
act = bpy.data.actions.new("idle")
act.use_fake_user = True
sk = me.shape_keys
sk.animation_data_create()
sk.animation_data.action = act
for name, pts in TRACKS.items():
    kb = sk.key_blocks[name]
    for sec, val in pts:
        kb.value = val
        kb.keyframe_insert("value", frame=int(round(sec * FPS)))
track = sk.animation_data.nla_tracks.new()
track.name = "idle"
track.strips.new("idle", 0, act)
sk.animation_data.action = None
bpy.context.scene.frame_end = int(LOOP * FPS)

os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', use_selection=True, export_animations=True,
		export_animation_mode='NLA_TRACKS', export_morph=True, export_morph_animation=True, export_force_sampling=True)
print("EXPORTED", out)

if render_dir:
    os.makedirs(render_dir, exist_ok=True)
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_WORKBENCH'
    sc.render.resolution_x = sc.render.resolution_y = 300
    sc.display.shading.light = 'STUDIO'
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    c = Vector((cx, cy, zmin + 0.45 * H))
    cam.location = c + Vector((1.2, -2.6, 1.6))
    cam.rotation_euler = (c - cam.location).to_track_quat('-Z', 'Y').to_euler()
    for tr in sk.animation_data.nla_tracks:
        tr.mute = True   # else the idle drives the keys and every picture shows its first frame
    top = bpy.data.objects.new("top", bpy.data.cameras.new("top"))
    sc.collection.objects.link(top)
    top.location = Vector((cx, cy, zmin + 3.2))
    top.rotation_euler = (0, 0, 0)
    for name in keys:
        for kb in sk.key_blocks:
            kb.value = 0.0
        sk.key_blocks[name].value = 1.0
        for camname, c_obj in (("", cam), ("_top", top)):
            sc.camera = c_obj
            sc.render.filepath = os.path.join(render_dir, name + camname + ".png")
            bpy.ops.render.render(write_still=True)
        sc.camera = cam
    for kb in sk.key_blocks:
        kb.value = 0.0
    sc.render.filepath = os.path.join(render_dir, "_rest.png")
    bpy.ops.render.render(write_still=True)
    print("RENDERED")
