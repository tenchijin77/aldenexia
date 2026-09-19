# phantasmal_echo_pet.gd — Spiritweaver's level-1 pet, summoned by the
# "phantasmal_echo" spell. Extends PetMinion (Voidknight's Morthan's Call)
# rather than duplicating its follow/guard/nav/animation plumbing — that
# machinery (NavigationServer3D pathing, obstacle steering, stuck-recovery,
# Follow/Guard/Assist/Sit commands, pet_frame.gd's UI, the `is PetMinion`
# click-target check in player3d.gd) is all generic to "a pet that follows and
# fights," and only the actual combat behavior differs here: this pet never
# closes to melee, strikes at range instead, and periodically heals the
# neediest ally rather than only ever dealing damage.
#
# Visual is a placeholder (no Meshy/Mixamo model built for this pet yet — see
# reference_character_model_pipeline in memory) — a simple translucent glow
# instead of a real character mesh. Swap _setup_visual() for a real model once
# one exists; nothing else here depends on it.
extends PetMinion
class_name PhantasmalEchoPet

# Deliberately not melee's ATTACK_RANGE (2.5) — a caster/healer pet, this one
# holds at range and lobs spectral bolts rather than closing distance.
const RANGED_ATTACK_RANGE := 14.0
const RANGED_ATTACK_COOLDOWN := 3.0

const HEAL_INTERVAL := 20.0
const HEAL_AMOUNT := 10

var _heal_timer: float = 0.0


func setup(p_owner: Node, preset_name: String = "") -> void:
	super.setup(p_owner, preset_name)
	attack_cooldown = RANGED_ATTACK_COOLDOWN


func _pet_title() -> String:
	return "phantasmal echo"


# A Spiritweaver's Phantasmal Echo is a benevolent spirit ally, not an
# undead thrall bound to an evil master — per user request (2026-09-17), it
# shouldn't share pet_minion.gd's Voidknight-flavored "dark lord"/"master"
# lines. Overrides every _phrase_*() hook the base class calls from its
# cmd_*() state logic (unchanged, only the words differ here).
func _phrase_attack(target_desc: String) -> String:
	return "I answer the call — %s shall fall." % target_desc

func _phrase_follow() -> String:
	return "I drift beside you."

func _phrase_sit() -> String:
	return "I rest here a while..."

func _phrase_guard() -> String:
	return "I shall watch over this place."

func _phrase_assist() -> String:
	return "Your battle is my battle."

func _phrase_dismiss() -> String:
	return "Until you call upon me again..."


func _pick_random_name() -> String:
	# Same names.json pool as pet_minion.gd's skeletons reads from — no
	# dedicated "spirit name" list exists yet, and re-rolling from the shared
	# pool beats hardcoding a single name.
	var picked := super._pick_random_name()
	return "Echo of %s" % picked if picked != "Skeleton Warrior" else "Phantasmal Echo"


# Real Mixamo-rigged model as of 2026-09-18 ("Version 2" — replaces the
# original static-mesh placeholder described in this file's header comment;
# models/Spirit Pet/ is this pet's own dedicated folder, distinct from
# models/Wildspeaker Pet/ which wildspeaker_pet.gd uses). Same pipeline as
# every humanoid character/pet model in this codebase — see
# [[reference_character_model_pipeline]]. Measures the same standard 1.7m
# baseline every correctly-exported model does, no scale correction needed.
func _setup_visual() -> void:
	var character_scene := load("res://models/Spirit Pet/phantasmal echo pet idle.fbx")
	if not character_scene:
		return
	var character: Node3D = character_scene.instantiate()
	character.name = "Character"
	character.transform = Transform3D.IDENTITY.rotated(Vector3.UP, PI)
	add_child(character)

	animation_player = character.get_node_or_null("AnimationPlayer")
	var lib := load("res://models/Spirit Pet/spirit_pet_animations.res") as AnimationLibrary
	if lib and animation_player:
		if animation_player.has_animation_library(""):
			animation_player.remove_animation_library("")
		animation_player.add_animation_library("", lib)

	_apply_texture_override(character, "res://models/Spirit Pet/Meshy_AI_spirit_elder_rig_biped_texture_0.png")

	var glow := OmniLight3D.new()
	glow.light_color = Color(0.6, 0.5, 1.0)
	glow.light_energy = 0.4
	glow.omni_range = 2.5
	glow.position = Vector3(0, 1.0, 0)
	add_child(glow)


func _load_skeleton_stats() -> Dictionary:
	# Squishier and less physically threatening than the melee skeleton pet —
	# this one's value is ranged damage + healing, not soaking hits.
	return {"damage": 10, "armor_class": 6}


# Holds at RANGED_ATTACK_RANGE and casts rather than closing into melee and
# flanking — see pet_minion.gd's _process_attack() for the melee version this
# overrides.
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


# A reliable spectral bolt, not a weapon swing — same "physical school spell"
# math cast_spell() already uses for e.g. Spirit Strike (base damage + AC
# mitigation, no miss/parry/dodge/riposte roll), rather than resolve_attack()'s
# melee avoidance table, since this is meant to read as magic damage landing
# at range, not a sword connecting. Damage is computed now (against the
# target's AC at the moment of casting) but applied on impact, once the
# spectral_bolt.gd projectile actually reaches the target — see
# _resolve_bolt_impact() below.
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


# Called by spectral_bolt.gd once the projectile actually reaches its target.
# Re-checks the target is still alive (it can die to something else mid-
# flight) rather than trusting the state captured at launch in _perform_attack().
func _resolve_bolt_impact(target: Node, dmg: int) -> void:
	if not _target_alive(target) or not (target.get("combat_node") is CombatNode):
		return

	var target_cn: CombatNode = target.combat_node
	target.apply_damage(dmg, "magic")

	# Multiplayer relay — same reasoning as pet_minion.gd's melee version and
	# player3d.gd's own damage relays. Credits the owner, not the pet itself.
	var target_is_networked_monster: bool = target is Monster and not target.is_multiplayer_authority()
	if target_is_networked_monster and dmg > 0 and is_instance_valid(owner_player):
		target.apply_networked_damage.rpc_id(1, dmg, owner_player.get_multiplayer_authority())

	if target.has_method("add_threat"):
		target.add_threat(self, combat_node.generate_threat(dmg))

	var target_desc: String = target.get("monster_description")
	if target_desc == "":
		target_desc = target.get_monster_name()
	GameLog.log_combat("%s's spectral bolt strikes %s for [b]%d[/b] damage!" % [pet_name, target_desc, dmg])

	if not target_cn.is_alive():
		GameLog.log_combat(CombatLogFormatter.death(pet_name, target_desc))
		if not target_is_networked_monster and target.has_method("die"):
			target.die()
		if attack_target == target:
			attack_target = null
			command = _pre_attack_command


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	# super's own authority check already returned early for non-authoritative
	# peers, but that doesn't stop this override's own code from continuing —
	# has to be checked again here so a replicated puppet doesn't also decide
	# to heal on its own.
	if not is_multiplayer_authority():
		return
	if not is_instance_valid(owner_player):
		return
	_heal_timer += delta
	if _heal_timer < HEAL_INTERVAL:
		return
	_heal_timer = 0.0
	_heal_lowest_ally()


# "Lowest member in the group" per the spec this pet was built to — with no
# real party heal-target UI yet, this scans the owner plus whichever group
# members resolve to a local Node (same _peer_id_to_player_node() the F1-F6
# group-target keys already use) and picks whoever is both alive and furthest
# below full health. Solo, that's just "heal the owner when hurt," which is
# also exactly what testing this on one character needs.
func _heal_lowest_ally() -> void:
	var candidates: Array = [owner_player]
	if "group_members" in owner_player and owner_player.has_method("_peer_id_to_player_node"):
		for peer_id in owner_player.group_members:
			var member: Node = owner_player._peer_id_to_player_node(peer_id)
			if is_instance_valid(member) and member != owner_player:
				candidates.append(member)

	var lowest: Node = null
	var lowest_pct: float = 1.0
	for candidate in candidates:
		var cn = candidate.get("combat_node")
		if not (cn is CombatNode) or not cn.is_alive() or cn.current_hp >= cn.max_hp:
			continue
		var pct: float = float(cn.current_hp) / float(cn.max_hp)
		if pct < lowest_pct:
			lowest_pct = pct
			lowest = candidate

	if lowest == null:
		return

	var target_cn: CombatNode = lowest.combat_node
	var healed: int = target_cn.heal(HEAL_AMOUNT)
	if healed <= 0:
		return
	_spawn_heal_pulse()
	var who: String = "you" if lowest == owner_player else TargetFrame.display_name(lowest)
	GameLog.log_combat("[color=#66ff99]%s channels healing energy into %s, restoring [b]%d[/b] health.[/color]" % [pet_name, who, healed])


# A brief green ring pulse around the Echo itself when it casts the heal —
# not around whoever gets healed, since that could be a group member the pet
# isn't standing next to. Placeholder-visual-friendly: built in code like
# _setup_visual(), so it doesn't depend on the real model having any
# particular bone/attachment point once one exists.
func _spawn_heal_pulse() -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.3
	torus.outer_radius = 0.5
	ring.mesh = torus
	ring.rotation_degrees = Vector3(90, 0, 0)
	ring.position = Vector3(0, 0.15, 0)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 1.0, 0.5, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(0.3, 1.0, 0.5)
	mat.emission_energy_multiplier = 2.0
	ring.material_override = mat
	add_child(ring)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(3.0, 3.0, 3.0), 0.7).set_trans(Tween.TRANS_SINE)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.7)
	tween.chain().tween_callback(ring.queue_free)
