# fix_held_model.py — tidies the user's single-mesh held models (2026-09-26 drop: axes, maces, hammers, clubs, wand,
# crossbow, torch, lantern, pick, fishing pole, woodcutter's axe, quiver, quarterstaff, chest) to the same convention as
# tools/blender/fix_props.py, for models that come as ONE mesh ("geometry_") instead of named parts:
#   HELD (onehand, twohand, staff, wand, torch, crossbow, pole)  the grip at the origin, the head / business end toward +Y
#        (Godot), the wide side of the head along X, flat faces toward +/-Z. The head end is found from the model itself:
#        the end whose cross-section is widest. The grip sits GRIP of the way from the butt (a hand's width up a one-handed
#        haft, lower on two-handers, the middle of a staff).
#   lantern  hangs from its handle: the origin at the top of the handle, the body below.
#   back     a quiver worn on the back: the origin at its middle, the opening up (+Y).
#   prop     a world object lying on its back (the generator's height along Blender -Y): stood up, base on the origin.
# Every material came fully metallic (wood rendered near black): only grey, unsaturated materials stay metal. Loose bits
# floating well away from the body (the maces' flanges came spread a metre around the head) are dropped.
#   blender -b --python tools/blender/fix_held_model.py -- <kind> "<in.glb>" "<out.glb>" [length_m] [drop] [render.png]
import bpy, bmesh, sys, os, colorsys
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:]
kind, src, dst = argv[0], argv[1], argv[2]
length = float(argv[3]) if len(argv) > 3 and argv[3].replace(".", "", 1).isdigit() else 0.0
render_out = next((a for a in argv[3:] if a.endswith(".png")), "")
GRIP = {"onehand": 0.14, "twohand": 0.30, "staff": 0.45, "wand": 0.25, "torch": 0.25, "crossbow": 0.35, "pole": 0.12}

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
for o in meshes:
	mw = o.matrix_world.copy()
	o.parent = None
	o.matrix_world = mw
for o in list(bpy.context.scene.objects):
	if o.type != "MESH":
		bpy.data.objects.remove(o)
bpy.ops.object.select_all(action="DESELECT")
for o in meshes:
	o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
if len(meshes) > 1:
	bpy.ops.object.join()
obj = bpy.context.view_layer.objects.active
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
me = obj.data

# ── drop loose bits floating off the handle's line (opt-in: "drop"; the maces' flanges came a metre out) ──
# These models are built of many separate primitive pieces, so a piece being separate means nothing: only a piece whose
# centre is far off the line of the handle (the longest piece) is dropped.
if "drop" in argv[3:]:
	bm = bmesh.new()
	bm.from_mesh(me)
	bm.verts.ensure_lookup_table()
	islands = []
	seen = set()
	for v in bm.verts:
		if v.index in seen:
			continue
		stack = [v]
		isl = []
		seen.add(v.index)
		while stack:
			x = stack.pop()
			isl.append(x)
			for e in x.link_edges:
				o = e.other_vert(x)
				if o.index not in seen:
					seen.add(o.index)
					stack.append(o)
		islands.append(isl)
	def box(vs):
		lo = Vector((min(v.co.x for v in vs), min(v.co.y for v in vs), min(v.co.z for v in vs)))
		hi = Vector((max(v.co.x for v in vs), max(v.co.y for v in vs), max(v.co.z for v in vs)))
		return lo, hi
	shaft = max(islands, key=lambda i: max(box(i)[1] - box(i)[0]))
	slo, shi = box(shaft)
	ssize = shi - slo
	sax = max(range(3), key=lambda k: ssize[k])
	centre = (slo + shi) / 2
	radius = max(ssize[k] for k in range(3) if k != sax) / 2
	limit = radius * 3.0 + 0.1
	dropped = 0
	for isl in islands:
		lo, hi = box(isl)
		c = (lo + hi) / 2
		off = c - centre
		off[sax] = 0.0
		# ...or floating past either end of the handle with a gap (a head sits against its end; these hung 10+ cm away)
		gap = max(lo[sax] - shi[sax], slo[sax] - hi[sax])
		if off.length > limit or gap > 0.08:
			bmesh.ops.delete(bm, geom=list(set(isl)), context="VERTS")
			dropped += 1
	bm.to_mesh(me)
	bm.free()
	print("DROPPED", dropped, "piece(s) off the handle's line (> %.2f m) or floating past its ends" % limit)

verts = [v.co.copy() for v in me.vertices]
lo = Vector((min(p.x for p in verts), min(p.y for p in verts), min(p.z for p in verts)))
hi = Vector((max(p.x for p in verts), max(p.y for p in verts), max(p.z for p in verts)))
size = hi - lo
axis = max(range(3), key=lambda i: size[i])                # the long axis


def slice_width(a0: float, a1: float) -> float:
	ps = [p for p in verts if a0 <= p[axis] <= a1]
	if not ps:
		return 0.0
	others = [i for i in range(3) if i != axis]
	return max(max(p[i] for p in ps) - min(p[i] for p in ps) for i in others)


if kind in GRIP:
	n = 10
	span = size[axis]
	widths = [slice_width(lo[axis] + span * k / n, lo[axis] + span * (k + 1) / n) for k in range(n)]
	head_at_high = sum(widths[n // 2:]) >= sum(widths[:n // 2]) if kind != "pole" else widths[0] > widths[-1]
	if kind == "pole":
		head_at_high = not (widths[0] > widths[-1])   # a rod: the thick butt is the grip end, the tip the "head"
	butt = lo[axis] if head_at_high else hi[axis]
	up = Vector((0, 0, 0))
	up[axis] = 1.0 if head_at_high else -1.0
	grip = (lo + hi) / 2
	grip[axis] = butt + up[axis] * span * GRIP[kind]
	# the widest side of the head end, to lie along X
	head_ps = [p for p in verts if (p[axis] - butt) * up[axis] > span * 0.75]
	others = [i for i in range(3) if i != axis]
	wide = max(others, key=lambda i: (max(p[i] for p in head_ps) - min(p[i] for p in head_ps)) if head_ps else 0)
	X = Vector((0, 0, 0)); X[wide] = 1.0
	Z = up.copy()                                          # Blender Z = Godot +Y
	Y = Z.cross(X)
	rot = Matrix((X, Y, Z))                                # rows: new axes in old coordinates
	obj.data.transform(Matrix.Translation(-grip))
	obj.data.transform(rot.to_4x4())
elif kind == "lantern":
	top = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, 0))
	# the generator's height is along -Y: the handle is the end at Y = max (top)
	obj.data.transform(Matrix.Translation(-Vector(((lo.x + hi.x) / 2, hi.y, (lo.z + hi.z) / 2))))
	obj.data.transform(Matrix.Rotation(-1.5708, 4, "X"))   # -Y down -> -Z down
	vs = [v.co for v in me.vertices]
	obj.data.transform(Matrix.Translation(Vector((0, 0, -max(v.z for v in vs)))))   # the handle's top at the origin: the body hangs below
elif kind == "back":
	obj.data.transform(Matrix.Translation(-(lo + hi) / 2))
	obj.data.transform(Matrix.Rotation(-1.5708, 4, "X"))
elif kind == "prop":
	obj.data.transform(Matrix.Translation(-Vector(((lo.x + hi.x) / 2, hi.y, (lo.z + hi.z) / 2))))
	obj.data.transform(Matrix.Rotation(-1.5708, 4, "X"))
	vs = [v.co for v in me.vertices]
	obj.data.transform(Matrix.Translation(Vector((0, 0, -min(v.z for v in vs)))))

if length > 0.0:
	vs = [v.co for v in me.vertices]
	cur = max(max(v[i] for v in vs) - min(v[i] for v in vs) for i in range(3))
	obj.data.transform(Matrix.Scale(length / cur, 4))

# ── materials: only grey stays metal ──
for m in me.materials:
	if m is None or not m.use_nodes:
		continue
	bsdf = m.node_tree.nodes.get("Principled BSDF")
	if bsdf is None:
		continue
	col = bsdf.inputs["Base Color"].default_value
	h, s, v = colorsys.rgb_to_hsv(col[0], col[1], col[2])
	metal = s < 0.18 and 0.15 < v < 0.95
	bsdf.inputs["Metallic"].default_value = 0.85 if metal else 0.0
	bsdf.inputs["Roughness"].default_value = 0.35 if metal else 0.8

vs = [v.co for v in me.vertices]
print("DONE", os.path.basename(dst), "size", tuple(round(max(v[i] for v in vs) - min(v[i] for v in vs), 2) for i in range(3)),
		"z", round(min(v.z for v in vs), 2), round(max(v.z for v in vs), 2))
os.makedirs(os.path.dirname(os.path.abspath(dst)), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", use_selection=False)

if render_out:
	sc = bpy.context.scene
	sc.render.engine = "BLENDER_WORKBENCH"
	sc.render.resolution_x = sc.render.resolution_y = 260
	sc.display.shading.color_type = "MATERIAL"
	cam = bpy.data.objects.new("c", bpy.data.cameras.new("c"))
	sc.collection.objects.link(cam)
	sc.camera = cam
	vs = [v.co for v in me.vertices]
	lo2 = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
	hi2 = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
	c = (lo2 + hi2) / 2
	r = max(hi2 - lo2)
	cam.location = c + Vector((0, -r * 2.2, r * 0.3))   # from the front (Blender -Y = Godot +Z)
	cam.rotation_euler = (c - cam.location).to_track_quat("-Z", "Y").to_euler()
	# a marker at the origin (the grip)
	bpy.ops.mesh.primitive_uv_sphere_add(radius=r * 0.03, location=(0, 0, 0))
	sc.render.filepath = render_out
	bpy.ops.render.render(write_still=True)
