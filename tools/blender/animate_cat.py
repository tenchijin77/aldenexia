# animate_cat.py — gives Oni (the user's rig in ~/NCT/Aldenexia-Lightfall/models/Oni/Oni Rigged.blend) her animations and
# exports a .glb the game plays (test 40: "it would be great to see Oni walking / running, her tail moving").
#   idle — breathing, a slow lazy tail sway, a look around (3 s loop)
#   walk — a cat's diagonal gait (front-right with back-left), paws lifting as they swing forward, a small bob, the tail
#          swaying in a travelling wave (1 s loop)
#   run  — a bounding gallop: front legs together, back legs together, the spine flexing, the tail streaming (0.5 s loop)
# The cat is first turned so her body points straight down -Y (the rig's spine leaned ~23 degrees off), so she walks
# where she faces in the game. Bones are the user's; rotations are keyed in each bone's own space about the body's side,
# up and forward axes, so the same code works whatever way each bone was drawn.
#   blender -b "Oni Rigged.blend" --python tools/blender/animate_cat.py -- <out.glb> [render_dir]
import bpy, sys, math, os
from mathutils import Vector, Quaternion, Matrix

argv = sys.argv[sys.argv.index("--") + 1:]
out = argv[0]
render_dir = argv[1] if len(argv) > 1 else ""
FPS = 24

arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
mesh = next(o for o in bpy.data.objects if o.type == 'MESH')
B = {b.name: b for b in arm.data.bones}

def head(n): return arm.matrix_world @ B[n].head_local
def tail(n): return arm.matrix_world @ B[n].tail_local

# ── straighten her: the body from the hips to the neck should point along -Y ──
hips = tail("Bone.001")          # mid-back / hips joint
neck = head("Bone.001")          # where the neck and front legs meet
fwd = (neck - hips); fwd.z = 0; fwd.normalize()
yaw = math.atan2(fwd.x, -fwd.y)  # how far she's turned from -Y
arm.matrix_world = Matrix.Rotation(-yaw, 4, 'Z') @ arm.matrix_world
bpy.context.view_layer.update()
print("TURNED by %.1f degrees" % math.degrees(yaw))

FWD = Vector((0, -1, 0))   # toward her head
UP = Vector((0, 0, 1))
SIDE = Vector((1, 0, 0))   # her left or right: legs swing about this

LEGS = {   # upper bone, lower bones (bend to lift the paw), phase in the walk, phase in the run
    "front_r": (["Arm.R"], ["Forearm.R", "Paw.R"], 0.0, 0.0),
    "front_l": (["Arm.L"], ["Forearm.L", "Paw.L"], 0.5, 0.08),
    "rear_l": (["rear thigh.l"], ["rear upper leg.l", "Bone.017", "rear leg.l"], 0.0, 0.5),
    "rear_r": (["rear thigh.r"], ["rear upper leg.r", "rear forearm.R", "Bone.023"], 0.5, 0.58),
}
TAIL = ["Bone.004", "Bone.008", "Bone.009", "Bone.010", "Bone.011", "Bone.012"]
ROOTS = [b.name for b in arm.data.bones if b.parent is None]   # the rig has several unparented roots: they move together


def local_axis(bone: str, world_axis: Vector) -> Vector:
    m = (arm.matrix_world.to_3x3() @ B[bone].matrix_local.to_3x3()).inverted()
    return (m @ world_axis).normalized()


def set_rot(bone: str, rots: list) -> None:
    """rots: [(world axis, degrees), ...] combined, keyed on the current frame."""
    pb = arm.pose.bones[bone]
    pb.rotation_mode = 'QUATERNION'
    q = Quaternion()
    for axis, deg in rots:
        q = Quaternion(local_axis(bone, axis), math.radians(deg)) @ q
    pb.rotation_quaternion = q
    pb.keyframe_insert("rotation_quaternion")


def set_loc(bone: str, world_offset: Vector) -> None:
    pb = arm.pose.bones[bone]
    m = (arm.matrix_world.to_3x3() @ B[bone].matrix_local.to_3x3()).inverted()
    pb.location = m @ world_offset
    pb.keyframe_insert("location")


def make(name: str, seconds: float, pose) -> None:
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    arm.animation_data_create()
    arm.animation_data.action = act
    frames = int(round(seconds * FPS))
    for f in range(frames + 1):
        bpy.context.scene.frame_set(f)
        for pb in arm.pose.bones:
            pb.rotation_mode = 'QUATERNION'
            pb.rotation_quaternion = Quaternion()
            pb.location = Vector()
        pose(f / frames)   # t: 0..1 over the loop
    for fc in act.fcurves if hasattr(act, "fcurves") else []:
        for kp in fc.keyframe_points:
            kp.interpolation = 'LINEAR'
    # keep it as an NLA strip so the exporter writes it as its own animation
    track = arm.animation_data.nla_tracks.new()
    track.name = name
    track.strips.new(name, 0, act)
    arm.animation_data.action = None
    print("ACTION", name, frames, "frames")


TAU = math.tau


def legs(t: float, swing: float, lift: float, phase_key: int) -> None:
    for leg, (uppers, lowers, walk_phase, run_phase) in LEGS.items():
        ph = t + (walk_phase if phase_key == 0 else run_phase)
        s = math.sin(TAU * ph)
        forward = leg.startswith("front")
        # the upper bone swings the leg fore and aft; the lower ones bend while it travels forward (the paw lifts)
        for u in uppers:
            set_rot(u, [(SIDE, swing * s)])
        bend = lift * max(0.0, math.cos(TAU * ph))   # bent through the forward swing, straight on the ground
        for i, lb in enumerate(lowers):
            sign = -1.0 if forward else 1.0          # elbows fold back, hocks fold forward
            set_rot(lb, [(SIDE, sign * bend * (1.0 if i == 0 else 0.5))])


def tail_wave(t: float, amp: float, speed: float, lag: float, lift: float = 0.0) -> None:
    for i, b in enumerate(TAIL):
        k = (i + 1) / len(TAIL)
        set_rot(b, [(FWD, amp * k * math.sin(TAU * speed * t - i * lag)), (SIDE, lift * k)])


def idle(t: float) -> None:
    breath = math.sin(TAU * t * 2)                      # two breaths a loop
    set_rot("Bone.001", [(SIDE, 1.5 * breath)])
    set_rot("Head", [(UP, 14 * math.sin(TAU * t)), (SIDE, 3 * math.sin(TAU * t * 2 + 1))])
    tail_wave(t, 16, 1, 0.5)


def walk(t: float) -> None:
    legs(t, 16, 30, 0)
    for r in ROOTS:
        set_loc(r, UP * (0.012 * math.sin(TAU * t * 2)))   # a small bob, twice a stride
    set_rot("Bone.001", [(UP, 3 * math.sin(TAU * t))])      # the body sways with the gait
    set_rot("Head", [(SIDE, 4 * math.sin(TAU * t * 2)), (UP, -3 * math.sin(TAU * t))])
    tail_wave(t, 20, 1, 0.7)


def run(t: float) -> None:
    legs(t, 24, 40, 1)
    flex = math.sin(TAU * t)
    for r in ROOTS:
        set_loc(r, UP * (0.02 * max(0.0, math.sin(TAU * t))))   # airborne between bounds
    set_rot("Bone.001", [(SIDE, 10 * flex)])                     # the spine bunches and stretches
    set_rot("Bone.002", [(SIDE, -8 * flex)])
    set_rot("Head", [(SIDE, -6 * flex)])
    tail_wave(t, 12, 2, 0.5, lift=-12)                          # streaming out behind, flicking


for n, secs, f in [("idle", 3.0, idle), ("walk", 1.0, walk), ("run", 0.5, run)]:
    make(n, secs, f)

for o in bpy.context.scene.objects:
    o.select_set(False)
arm.select_set(True)
mesh.select_set(True)
bpy.context.view_layer.objects.active = arm
os.makedirs(os.path.dirname(out), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', use_selection=True, export_animations=True,
		export_animation_mode='NLA_TRACKS', export_force_sampling=True, export_frame_range=False, export_skins=True)
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
    lo = Vector((1e9,) * 3); hi = Vector((-1e9,) * 3)
    for cc in mesh.bound_box:
        w = mesh.matrix_world @ Vector(cc); lo = Vector(map(min, lo, w)); hi = Vector(map(max, hi, w))
    c = (lo + hi) / 2
    cam.location = c + Vector((4.2, 0.0, 0.3))
    cam.rotation_euler = (c - cam.location).to_track_quat('-Z', 'Y').to_euler()
    for n in ["walk", "run"]:
        act = bpy.data.actions[n]
        for tr in arm.animation_data.nla_tracks:
            tr.mute = tr.name != n
        frames = int(act.frame_range[1])
        for i, f in enumerate([round(frames * k / 6) for k in range(6)]):
            sc.frame_set(f)
            sc.render.filepath = os.path.join(render_dir, "%s_%d.png" % (n, i))
            bpy.ops.render.render(write_still=True)
    print("RENDERED")
