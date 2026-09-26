# make_tail.gd — gives a character model a tail that can move (2026-09-26, the user: "can you please animate the
# lizardkins' tails in their animations?"). The lizardkin rigs have no tail bones: the tail is skinned to the hips, so it
# can only follow the hips about (and went through the floor when they sat). This finds the tail in the smoothed mesh
# (<scene>_smooth_mesh.res: everything well behind and below the hips), fits a chain of TAIL_BONES bones along its middle,
# and weights each tail vertex onto the two nearest bones (blending into the hips at the root, so there's no seam).
# Writes <scene>_tail_mesh.res: the mesh with the new weights, carrying as metadata the new Skin ("tail_skin": the
# FBX's binds plus the tail's) and the bones to add ("tail_bones": [name, parent, local rest]). TailRig (tail_rig.gd)
# adds the bones and swaps both in at runtime, and swings the tail. The FBX, the smoothed mesh and every animation stay
# as they are.
#   godot --headless --path . --script res://tools/make_tail.gd -- "res://models/Lizardkin Male/Lizardkin Male Breathing Idle.fbx"
extends SceneTree

const TAIL_BONES := 5
const BEHIND := 0.2        # a tail vertex is at least this far behind the hips joint (m)...
const BELOW := 0.1         # ...and no higher than this above it
const ROOT_BLEND := 0.6    # in bone lengths: the first stretch blends from the hips' own weights into the tail's


func _init() -> void:
	var scene_path: String = OS.get_cmdline_user_args()[0]
	var sc: Node3D = load(scene_path).instantiate()
	var sk := sc.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var mi := sc.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var smooth_path := scene_path.get_base_dir().path_join(scene_path.get_file().get_basename().to_snake_case() + "_smooth_mesh.res")
	var mesh: ArrayMesh = load(smooth_path)
	var skin: Skin = mi.skin
	var hips := sk.find_bone("Hips")
	var hips_bind := -1
	for b in skin.get_bind_count():
		if str(skin.get_bind_name(b)) == "Hips" or skin.get_bind_bone(b) == hips:
			hips_bind = b
	var hips_rest := sk.get_bone_global_rest(hips)
	var to_skel: Transform3D = hips_rest * skin.get_bind_pose(hips_bind)   # mesh space -> skeleton space (at rest)
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var per := bones.size() / verts.size()
	var h := hips_rest.origin

	# the tail: behind the hips (+Y is the back in these skeletons) and not above them
	var tail := PackedInt32Array()
	var skel_pos := PackedVector3Array()
	skel_pos.resize(verts.size())
	for i in verts.size():
		var p := to_skel * verts[i]
		skel_pos[i] = p
		if p.y > h.y + BEHIND and p.z < h.z + BELOW:
			tail.append(i)
	# fit the chain; then drop anything far from it (the male's heel claws sit behind the hips too) and fit again
	var fit := _fit(tail, skel_pos, h)
	var dists := []
	for i in tail:
		dists.append(_to_chain(skel_pos[i], fit["joints"]))
	var sorted_d := dists.duplicate()
	sorted_d.sort()
	var limit := maxf(0.12, 3.0 * float(sorted_d[sorted_d.size() / 2]))
	var kept := PackedInt32Array()
	for n in tail.size():
		if dists[n] <= limit:
			kept.append(tail[n])
	print("  dropped %d stray vertices (more than %.2f m from the tail's middle)" % [tail.size() - kept.size(), limit])
	tail = kept
	fit = _fit(tail, skel_pos, h)
	var root: Vector3 = fit["root"]
	var far: float = fit["far"]
	var joints: Array[Vector3] = fit["joints"]
	print("%s: %d tail vertices, %.2f m long; joints %s" % [scene_path.get_file(), tail.size(), far, str(joints.map(func(j): return j.snapped(Vector3.ONE * 0.01)))])

	# the bones: Tail1 on the hips at the root, each next one at the next joint; same axes as the hips (a turn about the
	# hips' own axes swings the tail)
	var names: Array[String] = []
	var bone_rows := []
	var globals: Array[Transform3D] = []
	for k in TAIL_BONES:
		var name := "Tail%d" % (k + 1)
		names.append(name)
		var g := Transform3D(hips_rest.basis, joints[k])
		globals.append(g)
		var parent_g: Transform3D = hips_rest if k == 0 else globals[k - 1]
		bone_rows.append([name, "Hips" if k == 0 else names[k - 1], parent_g.affine_inverse() * g])
	var new_skin := skin.duplicate() as Skin
	var first_bind := new_skin.get_bind_count()
	for k in TAIL_BONES:
		new_skin.add_named_bind(names[k], globals[k].affine_inverse() * to_skel)

	# the weights: two neighbouring tail bones by position along the tail, blended into the old weights at the root
	var bone_len := far / float(TAIL_BONES)
	for i in tail:
		var s := skel_pos[i].distance_to(root) / bone_len          # 0 at the root .. TAIL_BONES at the tip
		var a := clampi(int(floor(s - 0.5)), 0, TAIL_BONES - 1)   # bone a covers joint a .. a+1; blend at mid-bones
		var b := mini(a + 1, TAIL_BONES - 1)
		var f := clampf(s - 0.5 - float(a), 0.0, 1.0) if b != a else 0.0
		var tail_w := clampf(s / ROOT_BLEND, 0.0, 1.0)
		var infl := {}
		for j in per:
			var w := weights[i * per + j] * (1.0 - tail_w)
			if w > 0.0:
				infl[bones[i * per + j]] = float(infl.get(bones[i * per + j], 0.0)) + w
		infl[first_bind + a] = float(infl.get(first_bind + a, 0.0)) + tail_w * (1.0 - f)
		if f > 0.0:
			infl[first_bind + b] = float(infl.get(first_bind + b, 0.0)) + tail_w * f
		var ranked := infl.keys()
		ranked.sort_custom(func(x, y): return infl[x] > infl[y])
		var total := 0.0
		for j in mini(per, ranked.size()):
			total += infl[ranked[j]]
		for j in per:
			bones[i * per + j] = ranked[j] if j < ranked.size() else 0
			weights[i * per + j] = (infl[ranked[j]] / total) if j < ranked.size() else 0.0
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights

	var out := ArrayMesh.new()
	out.blend_shape_mode = mesh.blend_shape_mode
	for bs in mesh.get_blend_shape_count():
		out.add_blend_shape(mesh.get_blend_shape_name(bs))
	var flags := Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per == 8 else 0
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, mesh.surface_get_blend_shape_arrays(0), {}, flags)
	out.surface_set_material(0, mesh.surface_get_material(0))
	out.set_meta("tail_skin", new_skin)
	out.set_meta("tail_bones", bone_rows)
	var out_path := smooth_path.replace("_smooth_mesh.res", "_tail_mesh.res")
	var err := ResourceSaver.save(out, out_path, ResourceSaver.FLAG_COMPRESS)
	print("wrote %s (%s)" % [out_path, "ok" if err == OK else "FAILED %d" % err])
	sc.free()
	quit()


# The tail's root (its vertices nearest the hips), length, and TAIL_BONES + 1 joints: centroids of slices along it.
func _fit(tail: PackedInt32Array, skel_pos: PackedVector3Array, h: Vector3) -> Dictionary:
	var near := []
	for i in tail:
		near.append([skel_pos[i].distance_to(h), i])
	near.sort()
	var root := Vector3.ZERO
	var root_n := maxi(1, near.size() / 20)
	for n in root_n:
		root += skel_pos[near[n][1]]
	root /= float(root_n)
	var far := 0.0
	for i in tail:
		far = maxf(far, skel_pos[i].distance_to(root))
	var sums := []
	for k in TAIL_BONES + 1:
		sums.append([Vector3.ZERO, 0])
	for i in tail:
		var k := clampi(int(round(skel_pos[i].distance_to(root) / far * TAIL_BONES)), 0, TAIL_BONES)
		sums[k][0] += skel_pos[i]
		sums[k][1] += 1
	var joints: Array[Vector3] = []
	for k in TAIL_BONES + 1:
		joints.append(root if k == 0 else (sums[k][0] / float(maxi(1, sums[k][1]))))
	return {"root": root, "far": far, "joints": joints}


static func _to_chain(p: Vector3, joints: Array[Vector3]) -> float:
	var best := INF
	for k in joints.size() - 1:
		best = minf(best, p.distance_to(Geometry3D.get_closest_point_to_segment(p, joints[k], joints[k + 1])))
	return best
