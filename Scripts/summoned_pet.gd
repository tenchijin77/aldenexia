# summoned_pet.gd — every summon that has no pet of its own yet: the Voidknight's wraiths and shade, the Gravecaller's ghoul and
# abominations, the Lightmender's Spiritual Weapon, the Woodstalker's and Wildspeaker's animal companions. A PetMinion (same
# AI, commands, pet frame and replication) that wears a borrowed MONSTER model, tinted and scaled — TEMPORARY stand-ins until
# real art exists (see KINDS; the list of missing models is in change_log.txt).
#
# What a summon gives is data on its spell (Data/player_spells.json): "pet_kind" (a KINDS key), "pet_hp_pct" (share of the
# caster's health), "pet_duration" (seconds; 0 = until destroyed), and optional "pet_damage_mult" / "pet_crit_bonus".
# player3d.gd's _summon_from_spell() passes them in the spawn data, so every peer builds the same pet.
extends PetMinion
class_name SummonedPet

# model: a key of Monster.MOB_MODELS (rigged humanoids) or Monster.CRITTER_MODELS (static critters); tint multiplies its texture.
const KINDS := {
	"ghoul":            {"title": "ghoul",            "model": "mummy",  "scale": 1.0,  "tint": Color(0.62, 0.78, 0.55)},
	"abomination":      {"title": "abomination",      "model": "bandit", "scale": 1.35, "tint": Color(0.55, 0.68, 0.5)},
	"wraith":           {"title": "wraith",           "model": "ghost",  "scale": 1.05, "tint": Color(0.6, 0.45, 0.85)},
	"shade":            {"title": "shade",            "model": "ghost",  "scale": 1.0,  "tint": Color(0.28, 0.24, 0.34)},
	"spiritual_weapon": {"title": "spiritual weapon", "model": "ghost",  "scale": 0.9,  "tint": Color(1.0, 0.88, 0.45)},
	"wolf":             {"title": "wolf",             "model": "rat",    "scale": 1.5,  "tint": Color(0.78, 0.74, 0.68)},
	"hawk":             {"title": "hawk",             "model": "bat",    "scale": 1.0,  "tint": Color(0.85, 0.62, 0.4)},
	"bear":             {"title": "bear",             "model": "rat",    "scale": 2.2,  "tint": Color(0.5, 0.36, 0.26)},
	"panther":          {"title": "panther",          "model": "rat",    "scale": 1.7,  "tint": Color(0.24, 0.24, 0.27)},
}
# Summons that aren't living creatures: their pet gear's stats count, but nothing shows in their hands (test 42, the user:
# the Spiritual Weapon "will not have equipped weapons showing, as it is not a living pet per se").
const HOLDS_NO_GEAR := ["spiritual_weapon"]
const ANIMAL_NAMES := ["Ash", "Briar", "Dusk", "Ember", "Flint", "Grey", "Juniper", "Kestrel", "Moss", "Rook", "Sable", "Thorn"]
# Same per-model ground offsets monster3d.gd uses (their pivots sit above the lowest geometry).
const CRITTER_GROUND_OFFSET := {"rat": 0.4, "bat": 0.9, "snake": 0.22, "spider": 0.38}

var kind := "wolf"
var duration := 0.0
var damage_mult := 1.0
var crit_bonus := 0.0


# Called by player3d.gd's _build_pet() before setup(), with the spawn data.
func configure(data: Dictionary) -> void:
	kind = str(data.get("kind", "wolf")) if KINDS.has(str(data.get("kind", ""))) else "wolf"
	hp_percent_of_caster = float(data.get("hp_pct", 0.4))
	duration = float(data.get("duration", 0.0))
	damage_mult = float(data.get("damage_mult", 1.0))
	crit_bonus = float(data.get("crit_bonus", 0.0))


func _ready() -> void:
	super._ready()
	if crit_bonus > 0.0 and combat_node:
		combat_node.apply_effect("summon_crit", 1e9, {"crit_bonus": crit_bonus})
	# A timed summon fades on its owner's machine; the spawner then removes it everywhere.
	if duration > 0.0 and is_multiplayer_authority():
		get_tree().create_timer(duration).timeout.connect(_expire)


func _expire() -> void:
	if not is_instance_valid(self) or is_queued_for_deletion():
		return
	GameLog.log_general("[color=#888888]%s fades away.[/color]" % pet_name)
	dismissed.emit()
	queue_free()


func is_timed() -> bool:
	return duration > 0.0


func _pet_title() -> String:
	return str(KINDS[kind]["title"])


func _pick_random_name() -> String:
	if kind in ["wolf", "hawk", "bear", "panther"]:
		return ANIMAL_NAMES[randi() % ANIMAL_NAMES.size()]
	if kind == "spiritual_weapon":
		return "Spiritual Weapon"
	return super._pick_random_name()


func _recalculate_stats() -> void:
	super._recalculate_stats()
	if combat_node and damage_mult != 1.0:
		combat_node.weapon_damage = int(round(combat_node.weapon_damage * damage_mult))
		combat_node._stats_dirty = true
		combat_node.recalculate_derived_stats()


func _setup_visual() -> void:
	var info: Dictionary = KINDS.get(kind, KINDS["wolf"])
	var model := str(info["model"])
	var model_scale := float(info["scale"])
	var tint: Color = info["tint"]
	if Monster.CRITTER_MODELS.has(model):
		_build_critter(Monster.CRITTER_MODELS[model], model, model_scale, tint)
	else:
		_build_humanoid(Monster.MOB_MODELS.get(model, Monster.DEFAULT_HUMANOID_MOB_MODEL), model_scale, tint)
	if has_node("NameLabel"):
		$NameLabel.position.y = 2.4 * maxf(model_scale, 0.6) if not Monster.CRITTER_MODELS.has(model) else 1.4 * model_scale
		$TitleLabel.position.y = $NameLabel.position.y - 0.3


func _build_humanoid(model_info: Dictionary, model_scale: float, tint: Color) -> void:
	var scene := load(str(model_info["scene"])) as PackedScene
	if scene == null:
		return
	var character: Node3D = scene.instantiate()
	character.name = "Character"
	character.transform = Transform3D.IDENTITY.rotated(Vector3.UP, PI)
	character.scale = Vector3.ONE * model_scale
	add_child(character)
	animation_player = character.get_node_or_null("AnimationPlayer")
	var lib := load(str(model_info["library"])) as AnimationLibrary
	if lib and animation_player:
		for looping_clip in ["idle", "walk", "run"]:
			if lib.has_animation(looping_clip) and lib.get_animation(looping_clip).loop_mode == Animation.LOOP_NONE:
				lib.get_animation(looping_clip).loop_mode = Animation.LOOP_LINEAR
		if animation_player.has_animation_library(""):
			animation_player.remove_animation_library("")
		animation_player.add_animation_library("", lib)
	if model_info.has("texture_override"):
		var tex := load(str(model_info["texture_override"])) as Texture2D
		if tex:
			var mat := StandardMaterial3D.new()
			mat.albedo_texture = tex
			mat.albedo_color = model_info.get("tint", Color.WHITE) * tint
			_apply_material_recursive(character, mat)
	if not held_gear.is_empty():
		HeldGear.apply(character, held_gear)   # a humanoid summon wields its pet gear too (test 41)


func _build_critter(model_info: Dictionary, model: String, model_scale: float, tint: Color) -> void:
	var scene := load(str(model_info["scene"])) as PackedScene
	if scene == null:
		return
	var character: Node3D = scene.instantiate()
	character.name = "Character"
	character.transform = Transform3D.IDENTITY.rotated(Vector3.UP, PI)
	character.position.y += float(CRITTER_GROUND_OFFSET.get(model, 0.0)) * model_scale
	character.scale = Vector3.ONE * model_scale
	add_child(character)
	var albedo := load(str(model_info.get("albedo", ""))) as Texture2D if str(model_info.get("albedo", "")) != "" else null
	var motion: Dictionary = Monster.CRITTER_MOTION.get(model, {})
	if albedo and not motion.is_empty() and ResourceLoader.exists(Monster.CRITTER_SHADER):
		_apply_critter_motion(character, model_info, albedo, motion, tint)
	elif albedo:
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = albedo
		mat.albedo_color = tint
		_apply_material_recursive(character, mat)


# Animal pets built on the critter meshes move like the critters do (Shaders/critter_motion.gdshader, the same set-up as
# monster3d.gd: test 42's outstanding "summoned animal pets don't use critter motion"): a wolf's legs paddle and its tail
# swishes as it runs, a hawk beats its wings, and it lunges when it bites.
var _critter_meshes: Array = []
var _critter_time := 0.0
var _critter_speed := 0.0
var _critter_last := Vector3.INF
var _critter_attack := 0.0


func _apply_critter_motion(node: Node, model_info: Dictionary, albedo: Texture2D, motion: Dictionary, tint: Color) -> void:
	_critter_meshes.clear()
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var box := m.get_aabb()
		var mat := ShaderMaterial.new()
		mat.shader = load(Monster.CRITTER_SHADER)
		mat.set_shader_parameter("mode", int(motion["mode"]))
		mat.set_shader_parameter("body_axis", int(motion["axis"]))
		mat.set_shader_parameter("tail_sign", float(motion["tail"]))
		mat.set_shader_parameter("box_center", box.get_center())
		mat.set_shader_parameter("box_half", box.size * 0.5)
		mat.set_shader_parameter("tint", tint)
		mat.set_shader_parameter("albedo_tex", albedo)
		for key in ["normal", "roughness", "metallic"]:
			var path := str(model_info.get(key, ""))
			var tex := load(path) as Texture2D if not path.is_empty() else null
			if tex:
				mat.set_shader_parameter(key + "_tex", tex)
				if key != "roughness":
					mat.set_shader_parameter("use_" + key, true)
		for i in m.mesh.get_surface_count():
			m.set_surface_override_material(i, mat)
		m.extra_cull_margin = maxf(box.size.x, maxf(box.size.y, box.size.z)) * 0.6
		_critter_meshes.append(m)
	_critter_time = randf() * 10.0


func _process(delta: float) -> void:
	if _critter_meshes.is_empty() or Net.is_dedicated_server:
		return
	var p := global_position
	var step := 0.0 if _critter_last == Vector3.INF else Vector2(p.x - _critter_last.x, p.z - _critter_last.z).length() / maxf(delta, 0.001)
	_critter_last = p
	_critter_speed = lerpf(_critter_speed, minf(step, 12.0), 0.15)
	var mv := clampf(_critter_speed / 3.0, 0.0, 1.5)
	_critter_time += delta * (0.5 + 1.2 * mv)
	_critter_attack = maxf(0.0, _critter_attack - delta / 0.35)
	for m in _critter_meshes:
		if is_instance_valid(m):
			m.set_instance_shader_parameter("anim_time", _critter_time)
			m.set_instance_shader_parameter("move", mv)
			m.set_instance_shader_parameter("attack", sin(_critter_attack * PI) if _critter_attack > 0.0 else 0.0)


# Critters have no animations, and a borrowed library may lack the swing clips: then the swing is just the hit.
func _play_attack_animation() -> void:
	if not _critter_meshes.is_empty():
		_critter_attack = 1.0   # the critter lunge (on the owner's screen; others see it run and paddle)
	if not animation_player:
		return
	var clips: Array = ATTACK_ANIMS.filter(func(c): return animation_player.has_animation(c))
	if clips.is_empty():
		return
	var anim_name: String = clips[randi() % clips.size()]
	anim_state = anim_name
	animation_player.play(anim_name, 0.1)
	_attack_anim_timer = animation_player.get_animation(anim_name).length
