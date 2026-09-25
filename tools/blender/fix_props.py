# fix_props.py — tidies a held weapon/shield or a travel-site model for the game (2026-09-25). The user's first weapon and
# travel-site models came in with every material fully metallic (wood, leather and stone rendered near black) and each in
# its own layout. This gives them one convention, so hand attachment (the animation pack's held-gear step) is one rule:
#   WEAPONS  (Godot axes)  the grip at the origin, the blade / head / top pointing +Y, the edge along X, flat faces +/-Z.
#   SHIELDS                the handle (the middle of the back face) at the origin, the face toward +Z, the top +Y.
#   BOW                    the grip at the origin, the limbs along Y; its arrow is written separately (the ammunition
#                          and the projectile): origin at the middle of the shaft, the head toward -Z (Godot's forward).
#   SITES                  standing on the origin (the lowest point of the main piece a little below it, to sit in the
#                          ground), centred on the main piece.
# Metal parts (blade, guard, pommel, axe head, boss, rib, arrowhead, a grey shield face) become metal; wood, leather,
# string, feathers, stone and painted faces don't. Travel sites glow a little from their own texture. Parts are joined into
# one mesh; textures are embedded in the .glb (Godot extracts them on import); weapon textures are cut to 512 px.
#   blender -b --python tools/blender/fix_props.py -- <kind> "<in.glb>" "<out.glb>" [arrow_out.glb] [render.png]
#   kind: sword (swords, daggers), axe, staff, bow, shield, site, prop
#   prop: a scenery piece exported lying on its back (its height along Blender -Y, as the user's generator writes them):
#         stood up, centred, its base on the origin.
import bpy, sys, os, math
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:]
kind, src, dst = argv[0], argv[1], argv[2]
extra = argv[3:]
arrow_out = next((a for a in extra if a.endswith(".glb")), "")
render_out = next((a for a in extra if a.endswith(".png")), "")

METAL = ("blade", "guard", "pommel", "head", "boss", "rib", "arrowhead")
GLOW = {"spire": 0.6, "rift_shard": 1.0, "splinter": 1.0, "center_stone": 0.6}

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
for o in bpy.context.scene.objects:   # bake every transform into the vertices; drop the empty root
	o.select_set(o.type == "MESH")
bpy.context.view_layer.objects.active = meshes[0]
for o in meshes:
	mw = o.matrix_world.copy()
	o.parent = None
	o.matrix_world = mw
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for o in list(bpy.context.scene.objects):
	if o.type != "MESH":
		bpy.data.objects.remove(o)


def part_role(name: str) -> str:
	return name.rstrip("0123456789").split(".")[0]


def bounds(objs):
	lo = Vector((1e9,) * 3)
	hi = Vector((-1e9,) * 3)
	for o in objs:
		for v in o.data.vertices:
			w = o.matrix_world @ v.co
			lo = Vector(map(min, lo, w))
			hi = Vector(map(max, hi, w))
	return lo, hi


def by_role(role):
	return [o for o in meshes if part_role(o.name) == role]


def image_of(mat):
	for n in mat.node_tree.nodes:
		if n.type == "TEX_IMAGE" and n.image:
			return n, n.image
	return None, None


def greyish(img) -> bool:   # a low-saturation texture (bare steel) vs a painted or wooden one
	px = list(img.pixels[:])
	step = max(4, (len(px) // 4 // 4000) * 4)
	sat = 0.0
	n = 0
	for i in range(0, len(px) - 3, step):
		r, g, b = px[i], px[i + 1], px[i + 2]
		sat += max(r, g, b) - min(r, g, b)
		n += 1
	return sat / max(n, 1) < 0.08


# ── materials ──
done = set()
for o in meshes:
	role = part_role(o.name)
	for mat in o.data.materials:
		if mat is None or mat.name in done:
			continue
		done.add(mat.name)
		bsdf = mat.node_tree.nodes.get("Principled BSDF")
		if bsdf is None:
			continue
		tex_node, img = image_of(mat)
		metal = role in METAL or (role == "shield" and img is not None and greyish(img))
		bsdf.inputs["Metallic"].default_value = 0.85 if metal else 0.0
		bsdf.inputs["Roughness"].default_value = 0.4 if metal else 0.75
		if role in GLOW and tex_node is not None:
			mat.node_tree.links.new(tex_node.outputs["Color"], bsdf.inputs["Emission Color"])
			bsdf.inputs["Emission Strength"].default_value = GLOW[role]
		if img is not None and kind != "site" and img.size[0] > 512:
			img.scale(512, 512)


# ── orientation (Blender axes: +Z up = Godot +Y; -Y = Godot +Z; +Y = Godot -Z) ──
def rotation_to(up: Vector, front: Vector) -> Matrix:
	# a rotation taking `up` to +Z and `front` to -Y
	up = up.normalized()
	front = (front - up * front.dot(up)).normalized()
	side = front.cross(up)
	src = Matrix((side, front, up)).transposed()      # columns: the model's side, front, up
	dst = Matrix(((1, 0, 0), (0, -1, 0), (0, 0, 1))).transposed()
	return (dst @ src.inverted()).to_4x4()


def apply(mat4: Matrix, objs):
	for o in objs:
		o.data.transform(mat4)
		o.data.update()


lo, hi = bounds(meshes)
size = hi - lo
long_axis = max(range(3), key=lambda i: size[i])
thin_axis = min(range(3), key=lambda i: size[i])
axis = [Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))]


def centre(objs):
	a, b = bounds(objs)
	return (a + b) / 2


arrow_parts = [o for o in meshes if part_role(o.name) in ("arrowshaft", "arrowhead", "fletching")]
if kind in ("sword", "axe", "staff", "bow"):
	body = [o for o in meshes if o not in arrow_parts]
	grip_parts = by_role("grip") or by_role("haft") or body
	L = axis[long_axis]
	blo, bhi = bounds(body)
	if kind == "sword":
		tip = centre(by_role("blade"))
	elif kind == "axe":
		tip = centre(by_role("head"))
	elif kind == "staff":
		tip = centre(by_role("knot"))
	else:
		tip = bhi
	g = centre(grip_parts)
	up = L if (tip - g).dot(L) >= 0 else -L
	rot = rotation_to(up, axis[thin_axis])
	# the grip point, before rotating
	if kind == "axe":   # a hand's width up from the butt of the haft
		hlo, hhi = bounds(grip_parts)
		butt = hlo if up.dot(hhi - hlo) >= 0 else hhi
		along = (hhi - hlo).dot(up) * (1 if up.dot(hhi - hlo) >= 0 else -1)
		g = centre(grip_parts) + up * ((butt - centre(grip_parts)).dot(up) + abs(along) * 0.18)
	elif kind == "staff":   # a little below the middle
		a, b = bounds(body)
		g = (a + b) / 2 - up * (abs((b - a).dot(up)) * 0.05)
	apply(Matrix.Translation(-g), meshes)
	apply(rot, meshes)
elif kind == "shield":
	plate = by_role("shield")
	front_parts = by_role("boss") or by_role("rib")
	N = axis[thin_axis]
	plo, phi = bounds(plate)
	pc = (plo + phi) / 2
	front = N if (centre(front_parts) - pc).dot(N) >= 0 else -N
	# up: along the plate's long direction (or the model's +Y if round); a kite shield's wide end is the top
	cand = [i for i in range(3) if i != thin_axis]
	U = axis[max(cand, key=lambda i: (phi - plo)[i])]
	if abs((phi - plo)[cand[0]] - (phi - plo)[cand[1]]) < 0.02:
		U = axis[1] if thin_axis != 1 else axis[2]
	verts = [o.matrix_world @ v.co for o in plate for v in o.data.vertices]
	ext = [v.dot(U) for v in verts]
	span = max(ext) - min(ext)
	top_w = [v for v in verts if v.dot(U) > max(ext) - span * 0.12]
	bot_w = [v for v in verts if v.dot(U) < min(ext) + span * 0.12]
	W = axis[3 - thin_axis - (0 if U == axis[0] else 1 if U == axis[1] else 2)]
	width = lambda vs: (max(v.dot(W) for v in vs) - min(v.dot(W) for v in vs)) if vs else 0.0
	up = U if width(top_w) >= width(bot_w) else -U
	back = pc - front * ((phi - plo).dot(N) / 2 if front == N else (phi - plo).dot(N) / 2)
	back = pc - front * abs((phi - plo).dot(N)) / 2
	apply(Matrix.Translation(-back), meshes)
	apply(rotation_to(up, front), meshes)
elif kind == "prop":
	apply(Matrix.Rotation(math.radians(-90), 4, "X"), meshes)   # -Y (the generator's up) -> +Z
	a, b = bounds(meshes)
	apply(Matrix.Translation(-Vector(((a.x + b.x) / 2, (a.y + b.y) / 2, a.z))), meshes)
elif kind == "site":
	main = by_role("spire") or by_role("rift_shard") or by_role("center_stone") or meshes
	a, b = bounds(main)
	base = Vector(((a.x + b.x) / 2, (a.y + b.y) / 2, a.z + 0.05))
	if by_role("center_stone"):   # the ring of blocks is centred on the whole model
		a2, b2 = bounds(meshes)
		base = Vector(((a2.x + b2.x) / 2, (a2.y + b2.y) / 2, min(a.z, a2.z) + 0.05))
	apply(Matrix.Translation(-base), meshes)


def join(objs, name):
	bpy.ops.object.select_all(action="DESELECT")
	for o in objs:
		o.select_set(True)
	bpy.context.view_layer.objects.active = objs[0]
	if len(objs) > 1:
		bpy.ops.object.join()
	objs[0].name = name
	objs[0].data.name = name
	return objs[0]


def export(path, objs):
	bpy.ops.object.select_all(action="DESELECT")
	for o in objs:
		o.select_set(True)
	os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
	bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
			export_apply=True, export_image_format="AUTO")


name = os.path.splitext(os.path.basename(dst))[0]
arrow_obj = None
if arrow_parts and arrow_out:
	arrow_obj = join(arrow_parts, "arrow")
	meshes = [o for o in meshes if o not in arrow_parts]
main_obj = join(meshes, name)
export(dst, [main_obj])
print("FIXED", dst, "tris", sum(len(p.vertices) - 2 for p in main_obj.data.polygons), "bounds", [tuple(round(x, 3) for x in v) for v in bounds([main_obj])])

if arrow_obj is not None:
	# the arrow on its own: the middle of the shaft at the origin, head toward Blender +Y (Godot -Z, forward)
	a, b = bounds([arrow_obj])
	c = (a + b) / 2
	hd = None
	for p in arrow_obj.data.polygons:
		pass
	head_c = c
	# the arrowhead is the metal material's vertices
	metal_idx = [i for i, m in enumerate(arrow_obj.data.materials) if m and m.node_tree.nodes.get("Principled BSDF").inputs["Metallic"].default_value > 0.5]
	hv = [arrow_obj.matrix_world @ arrow_obj.data.vertices[v].co for p in arrow_obj.data.polygons if p.material_index in metal_idx for v in p.vertices]
	if hv:
		head_c = sum(hv, Vector()) / len(hv)
	size = b - a
	la = max(range(3), key=lambda i: size[i])
	L = axis[la]
	fwd = L if (head_c - c).dot(L) >= 0 else -L
	other = axis[min(range(3), key=lambda i: size[i] if i != la else 1e9)]
	apply(Matrix.Translation(-c), [arrow_obj])
	# forward -> +Y (Godot -Z); pick an up that is not the arrow's axis
	up_hint = axis[2] if la != 2 else axis[0]
	m = rotation_to(up_hint, -fwd)   # rotation_to sends `front` to -Y, so send -fwd there (fwd -> +Y)
	apply(m, [arrow_obj])
	bpy.ops.object.select_all(action="DESELECT")
	arrow_obj.select_set(True)
	main_obj.hide_set(True)
	export(arrow_out, [arrow_obj])
	main_obj.hide_set(False)
	print("FIXED", arrow_out, "bounds", [tuple(round(x, 3) for x in v) for v in bounds([arrow_obj])])

if render_out:
	# a check picture: front and side, with the origin marked by the axes (red X, green Godot-up = Blender Z)
	sc = bpy.context.scene
	sc.render.engine = "BLENDER_EEVEE"
	sc.render.resolution_x, sc.render.resolution_y = 500, 500
	w = bpy.data.worlds.new("w")
	sc.world = w
	w.use_nodes = True
	w.node_tree.nodes["Background"].inputs[0].default_value = (0.5, 0.5, 0.55, 1)
	for i in range(2):
		L = bpy.data.objects.new("sun%d" % i, bpy.data.lights.new("sun%d" % i, "SUN"))
		L.data.energy = 3.0
		L.rotation_euler = (math.radians(50), 0, math.radians(30 + 180 * i))
		sc.collection.objects.link(L)
	objs = [main_obj] + ([arrow_obj] if arrow_obj else [])
	a, b = bounds(objs)
	a = Vector(map(min, a, Vector((0, 0, 0))))
	b = Vector(map(max, b, Vector((0, 0, 0))))
	r = max((b - a).length / 2, 0.3)
	ctr = (a + b) / 2
	bpy.ops.mesh.primitive_uv_sphere_add(radius=r * 0.04, location=(0, 0, 0))
	dot = bpy.context.active_object
	dm = bpy.data.materials.new("origin")
	dm.use_nodes = True
	dm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (1, 0.1, 0.1, 1)
	dm.node_tree.nodes["Principled BSDF"].inputs["Emission Color"].default_value = (1, 0.1, 0.1, 1)
	dm.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = 3
	dot.data.materials.append(dm)
	cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
	sc.collection.objects.link(cam)
	sc.camera = cam
	cam.location = ctr + Vector((0.35, -1, 0.25)).normalized() * r * 3.4   # from the front (Godot +Z), a little right
	cam.rotation_euler = (ctr - cam.location).to_track_quat("-Z", "Y").to_euler()
	sc.render.filepath = render_out
	bpy.ops.render.render(write_still=True)
