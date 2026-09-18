# wildspeaker_pet.gd — Wildspeaker's level-1 pet, "Spirit of the Woods",
# granted via the "summon_spirit_of_the_woods" starting spell. Extends
# PetMinion the same way phantasmal_echo_pet.gd does, and its ranged-attack
# structure is deliberately modeled on that pet closely (same
# holds-at-range/casts-rather-than-melees shape) since the spec is nearly
# identical: ranged damage + a periodic support cast on the neediest ally.
# The one real mechanical difference is the heal is a heal-over-time (via
# CombatNode's generic tick_heal effect — see combatnode.gd's apply_effect())
# rather than an instant heal, and routed through owner_player._buff_target()
# so it actually lands when the healed ally is a REMOTE player (see
# player3d.gd's _buff_target()/_heal_target() — a direct combat_node.heal()
# call here would only update the caster's own local, replicated copy).
#
# Visual is a placeholder per the user's explicit request (2026-09-17) — no
# Meshy/Mixamo model built for this pet yet. Swap _setup_visual() for a real
# model once art exists; nothing else here depends on it.
extends PetMinion
class_name WildspeakerPet

const RANGED_ATTACK_RANGE := 14.0
const RANGED_ATTACK_COOLDOWN := 3.0

const HOT_INTERVAL := 30.0
const HOT_DURATION := 15.0
const HOT_PER_SECOND := 5

var _hot_timer: float = 0.0


func setup(p_owner: Node, preset_name: String = "") -> void:
	super.setup(p_owner, preset_name)
	attack_cooldown = RANGED_ATTACK_COOLDOWN


func _pet_title() -> String:
	return "spirit of the woods"


func _pick_random_name() -> String:
	var picked := super._pick_random_name()
	return "Spirit of %s" % picked if picked != "Skeleton Warrior" else "Spirit of the Woods"


# Simple translucent glow (a soft green sphere) instead of a real character
# mesh — matches how Phantasmal Echo originally looked before it got a real
# model (see phantasmal_echo_pet.gd's own doc comment).
func _setup_visual() -> void:
	var body := MeshInstance3D.new()
	body.name = "Character"
	var sphere := SphereMesh.new()
	sphere.radius = 0.4
	sphere.height = 0.8
	body.mesh = sphere
	body.position = Vector3(0, 1.0, 0)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.9, 0.4, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.9, 0.4)
	mat.emission_energy_multiplier = 1.5
	body.material_override = mat
	add_child(body)

	var glow := OmniLight3D.new()
	glow.light_color = Color(0.5, 1.0, 0.5)
	glow.light_energy = 0.6
	glow.omni_range = 3.0
	glow.position = Vector3(0, 1.0, 0)
	add_child(glow)


func _load_skeleton_stats() -> Dictionary:
	return {"damage": 10, "armor_class": 6}


# Holds at range and casts rather than closing into melee — see
# pet_minion.gd's _process_attack() for the melee version this overrides.
func _process_attack(delta: float) -> void:
	if not is_instance_valid(attack_target) or not _target_alive(attack_target):
		attack_target = null
		command = _pre_attack_command
		return

	var distance := global_position.distance_to(attack_target.global_position)
	if distance > RANGED_ATTACK_RANGE:
		_move_toward(attack_target.global_position, RANGED_ATTACK_RANGE * 0.8, delta)
		return

	_apply_gravity(delta)
	velocity.x = 0.0
	velocity.z = 0.0
	look_at(attack_target.global_position, Vector3.UP)

	if can_attack:
		_perform_attack()


# Reuses the existing spectral bolt projectile as a placeholder visual for
# the ranged attack (a nature-themed one doesn't exist yet) — same "physical
# school spell" damage math as phantasmal_echo_pet.gd's version.
func _perform_attack() -> void:
	can_attack = false
	attack_timer = attack_cooldown
	_play_attack_animation()

	if not (attack_target.get("combat_node") is CombatNode):
		return

	var target_cn: CombatNode = attack_target.combat_node
	var dmg: int = combat_node.apply_ac_mitigation(combat_node.weapon_damage, target_cn)
	dmg = max(1, dmg)

	var bolt: Node3D = load("res://Scenes/spectral_bolt.tscn").instantiate()
	get_tree().current_scene.add_child(bolt)
	bolt.global_position = global_position + Vector3(0, 1.1, 0)
	bolt.target = attack_target
	bolt.damage = dmg
	bolt.source_pet = self


func _resolve_bolt_impact(target: Node, dmg: int) -> void:
	if not _target_alive(target) or not (target.get("combat_node") is CombatNode):
		return

	var target_cn: CombatNode = target.combat_node
	target.apply_damage(dmg, "physical")

	var target_is_networked_monster: bool = target is Monster and not target.is_multiplayer_authority()
	if target_is_networked_monster and dmg > 0 and is_instance_valid(owner_player):
		target.apply_networked_damage.rpc_id(1, dmg, owner_player.get_multiplayer_authority())

	if target.has_method("add_threat"):
		target.add_threat(self, combat_node.generate_threat(dmg))

	var target_desc: String = target.get("monster_description")
	if target_desc == "":
		target_desc = target.get_monster_name()
	GameLog.log_combat("%s's thorned volley strikes %s for [b]%d[/b] damage!" % [pet_name, target_desc, dmg])

	if not target_cn.is_alive():
		GameLog.log_combat(CombatLogFormatter.death(pet_name, target_desc))
		if not target_is_networked_monster and target.has_method("die"):
			target.die()
		if attack_target == target:
			attack_target = null
			command = _pre_attack_command


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not is_multiplayer_authority():
		return
	if not is_instance_valid(owner_player):
		return
	_hot_timer += delta
	if _hot_timer < HOT_INTERVAL:
		return
	_hot_timer = 0.0
	_cast_hot_on_most_damaged_ally()


# "Most damaged" = furthest below full health, same candidate pool
# (owner + resolvable group members) phantasmal_echo_pet.gd's instant-heal
# uses — this casts a real heal-over-time via the shared CombatNode tick_heal
# engine instead, and always relays through owner_player._buff_target() so it
# actually lands on a remote ally's own authoritative combat_node rather than
# just the caster's local replicated view of it.
func _cast_hot_on_most_damaged_ally() -> void:
	var candidates: Array = [owner_player]
	if "group_members" in owner_player and owner_player.has_method("_peer_id_to_player_node"):
		for peer_id in owner_player.group_members:
			var member: Node = owner_player._peer_id_to_player_node(peer_id)
			if is_instance_valid(member) and member != owner_player:
				candidates.append(member)

	var most_damaged: Node = null
	var lowest_pct: float = 1.0
	for candidate in candidates:
		var cn = candidate.get("combat_node")
		if not (cn is CombatNode) or not cn.is_alive() or cn.current_hp >= cn.max_hp:
			continue
		var pct: float = float(cn.current_hp) / float(cn.max_hp)
		if pct < lowest_pct:
			lowest_pct = pct
			most_damaged = candidate

	if most_damaged == null:
		return

	var target_cn = most_damaged.get("combat_node")
	if not (target_cn is CombatNode) or not owner_player.has_method("_buff_target"):
		return

	owner_player._buff_target(most_damaged, target_cn, "spirit_of_the_woods_regrowth", HOT_DURATION, {}, 0, 1.0, HOT_PER_SECOND)
	_spawn_regrowth_pulse()
	var who: String = "you" if most_damaged == owner_player else TargetFrame.display_name(most_damaged)
	GameLog.log_combat("[color=#88ff88]%s calls upon nature to mend %s.[/color]" % [pet_name, who])


func _spawn_regrowth_pulse() -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.3
	torus.outer_radius = 0.5
	ring.mesh = torus
	ring.rotation_degrees = Vector3(90, 0, 0)
	ring.position = Vector3(0, 0.15, 0)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 1.0, 0.4, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(0.5, 1.0, 0.4)
	mat.emission_energy_multiplier = 2.0
	ring.material_override = mat
	add_child(ring)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(3.0, 3.0, 3.0), 0.7).set_trans(Tween.TRANS_SINE)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.7)
	tween.chain().tween_callback(ring.queue_free)
