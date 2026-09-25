# smooth_character.py — rebuilds a Meshy character's mesh so it reads as smooth, not faceted (2026-09-25). The Meshy
# exports are ~10k triangles with hard edges on most of them and flat custom normals: the texture is fine, the geometry
# is what looks "low poly" (a nose of four triangles). This clears the custom normals and sharp edges, shades smooth,
# adds one level of Catmull-Clark subdivision (rounds the shapes; skin weights are interpolated): ~10k -> ~60k triangles,
# with distance LODs added in Godot (decimating here smeared the lips; pass target_tris to try it anyway). Writes a .glb of the mesh + armature (no animation): tools/make_smooth_models.gd
# turns it into the game's <model>_smooth_mesh.res, which is swapped in for the FBX's mesh at runtime (the FBX's own
# skeleton, skin and animations stay exactly as they are).
#   blender -b --python tools/blender/smooth_character.py -- "<in.fbx>" "<out.glb>" [target_tris] [render_dir] [texture.png]
#       [shape=bust,waist,hips]   (optional: reshape the body first, tools/blender/shape_body.py; e.g. shape=0.35,0.06,0.04)
# (render_dir: also renders the result, face and full body, with the texture, to check it)
import bpy, sys, os, math
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
shape_arg = next((a for a in argv if a.startswith("shape=")), "")
argv = [a for a in argv if not a.startswith("shape=")]
src, out = argv[0], argv[1]
TARGET_TRIS = int(argv[2]) if len(argv) > 2 else 0   # 0 = keep every triangle (decimating smeared the lips); LODs come from Godot
render_dir = argv[3] if len(argv) > 3 else ""
texture = argv[4] if len(argv) > 4 else ""

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=src)
meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
female = "female" in os.path.basename(src).lower()
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shape_body
slider_shapes = [] if "noshapes" in sys.argv else (shape_body.FEMALE_SHAPES if female else shape_body.MALE_SHAPES)


def subdivide(o):
    sub = o.modifiers.new("smooth_subdiv", 'SUBSURF')
    sub.levels = 1; sub.render_levels = 1; sub.uv_smooth = 'PRESERVE_BOUNDARIES'; sub.boundary_smooth = 'PRESERVE_CORNERS'
    with bpy.context.temp_override(object=o, active_object=o):
        bpy.ops.object.modifier_move_to_index(modifier="smooth_subdiv", index=0)
        bpy.ops.object.modifier_apply(modifier="smooth_subdiv")


for o in meshes:
    bpy.context.view_layer.objects.active = o
    with bpy.context.temp_override(object=o, active_object=o):
        if o.data.has_custom_normals:
            bpy.ops.mesh.customdata_custom_splitnormals_clear()
    for e in o.data.edges:
        e.use_edge_sharp = False
    for p in o.data.polygons:
        p.use_smooth = True
    before = sum(len(p.vertices) - 2 for p in o.data.polygons)
    # merge vertices split for no reason (Meshy splits along its hard edges) — UV seams stay (different UVs are kept)
    bpy.ops.object.select_all(action='DESELECT'); o.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.remove_doubles(threshold=0.00001)
    bpy.ops.object.mode_set(mode='OBJECT')
    if shape_arg:
        b, w, h = [float(x) for x in shape_arg[6:].split(",")]
        shape_body.shape(o, bust=b, waist=w, hips=h, log=lambda s: print("SHAPE", s))
    # each slider shape: a copy of the (shaped) mesh, deformed at full strength and subdivided the same way; the base's
    # subdivided vertices and the copy's line up one for one, so the difference is the blend shape
    copies = {}
    for kind in slider_shapes:
        c = o.copy(); c.data = o.data.copy(); bpy.context.scene.collection.objects.link(c)
        c.modifiers.clear()
        shape_body.morph(c, kind)
        subdivide(c)
        copies[kind] = c
    subdivide(o)
    mid = sum(len(p.vertices) - 2 for p in o.data.polygons)
    if TARGET_TRIS and mid > TARGET_TRIS:
        dec = o.modifiers.new("trim", 'DECIMATE')
        dec.decimate_type = 'COLLAPSE'; dec.ratio = TARGET_TRIS / mid; dec.use_collapse_triangulate = True
        with bpy.context.temp_override(object=o, active_object=o):
            bpy.ops.object.modifier_move_to_index(modifier="trim", index=0)
            bpy.ops.object.modifier_apply(modifier="trim")
        copies = {}   # decimating breaks the one-for-one match: no slider shapes
    for p in o.data.polygons:
        p.use_smooth = True
    if copies:
        o.shape_key_add(name="Basis", from_mix=False)
        for kind, c in copies.items():
            if len(c.data.vertices) != len(o.data.vertices):
                print("SHAPEKEY skipped", kind, "(vertex count differs)")
                continue
            k = o.shape_key_add(name=kind, from_mix=False)
            for i, v in enumerate(c.data.vertices):
                k.data[i].co = v.co
        for c in copies.values():
            bpy.data.objects.remove(c)
        print("SHAPEKEYS", [k.name for k in o.data.shape_keys.key_blocks][1:])
    after = sum(len(p.vertices) - 2 for p in o.data.polygons)
    print("SMOOTHED %s: %d -> %d (subdivided) -> %d triangles" % (o.name, before, mid, after))

os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', use_selection=True, export_animations=False,
                          export_skins=True, export_morph=True, export_morph_normal=True, export_apply=False,
                          export_materials='NONE', export_yup=True)
print("WROTE", out)

if render_dir:
    os.makedirs(render_dir, exist_ok=True)
    if texture:
        mat = bpy.data.materials.new("tex"); mat.use_nodes = True
        tn = mat.node_tree.nodes.new("ShaderNodeTexImage"); tn.image = bpy.data.images.load(texture)
        mat.node_tree.links.new(tn.outputs[0], mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"])
        mat.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.6
        for o in meshes:
            for i in range(len(o.data.materials)):
                o.data.materials[i] = mat
    scene = bpy.context.scene
    scene.render.resolution_x = 700; scene.render.resolution_y = 700
    scene.view_settings.view_transform = 'Standard'
    w = bpy.data.worlds.new("w"); scene.world = w; w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[1].default_value = 0.5
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); scene.collection.objects.link(cam); scene.camera = cam
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", 'SUN')); scene.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(55), 0, math.radians(25)); sun.data.energy = 3.0
    pts = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    h = hi.z - lo.z
    # front face, full body front, and the torso from the side and three-quarters (the camera circles the model)
    for name, zf, d, turn in [("face", 0.92, 0.33, 0), ("body", 0.5, 1.5, 0), ("side", 0.62, 0.75, 90), ("three_quarter", 0.62, 0.75, 40)]:
        t = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z + h * zf))
        a = math.radians(turn)
        cam.location = t + Vector((h * d * math.sin(a), -h * d * math.cos(a), 0))
        cam.rotation_euler = (math.radians(90), 0, a)
        scene.render.filepath = os.path.join(render_dir, "after_" + name + ".png")
        bpy.ops.render.render(write_still=True)
