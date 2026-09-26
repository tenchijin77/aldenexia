# The user's Mixamo animations (2026-09-26): shared onto every race by tools/add_shared_clips.gd, and used for emotes
# (/bow /kiss /cheer /clap /wave /dance), the tanks' taunts, Shield Bash, hit reactions on big blows, sneaking, walking backward, an Aetherfist's punches and kicks, dodging.
extends "res://tools/tests/test_base.gd"

const NEEDED := ["emote_bow", "emote_kiss", "emote_cheer", "emote_clap", "emote_wave", "emote_taunt", "dance_1", "dance_5",
		"sneak", "walk_back", "swim", "fish_cast", "pick_up", "hit_front", "dodge", "dodge_2", "punch", "punch_combo", "kick",
		"heavy_swing", "dual_combo"]


func run() -> void:
	# every race's pack has them
	var src := FileAccess.get_file_as_string("res://Scripts/player3d.gd")
	var re := RegEx.new()
	re.compile('"library":\\s*"(res://models/[^"]+_pack\\.res)"')
	var packs := 0
	for m in re.search_all(src):
		var lib := load(m.get_string(1)) as AnimationLibrary
		packs += 1
		var missing := NEEDED.filter(func(n): return not lib.has_animation(n))
		check(missing.is_empty(), "%s has the new clips%s" % [m.get_string(1).get_file(), "" if missing.is_empty() else " (missing %s)" % str(missing)])
		if lib.has_animation("dance_1"):
			eq(lib.get_animation("dance_1").loop_mode, Animation.LOOP_LINEAR, "%s: a dance loops" % m.get_string(1).get_file())
	check(packs >= 22, "all %d race packs" % packs)

	make_floor(100.0)
	var p = await make_player({"player_name": "Jaessa", "player_class": "Shadowblade"})
	var said: Array = []
	var listen := func(text: String) -> void: said.append(text)
	GameLog.general_message.connect(listen)
	check(p.emote("bow"), "/bow")
	await frames(3)
	eq(p.anim_state, "emote_bow", "the bow plays (and is what others see)")
	check(said.has("You bow."), "You bow.")
	await get_tree().create_timer(p.animation_player.get_animation("emote_bow").length + 0.3).timeout
	await frames(2)
	eq(p.anim_state, "idle", "and ends by itself")
	check(p.emote("dance", "3"), "/dance 3")
	await get_tree().create_timer(1.0).timeout
	eq(p.anim_state, "dance_3", "a dance keeps going")
	p.autorun_enabled = true
	for i in 10:
		await get_tree().physics_frame
	p.autorun_enabled = false
	await frames(2)
	check(not p.anim_state.begins_with("dance"), "until you move (%s)" % p.anim_state)
	for i in 20:
		await get_tree().physics_frame

	# someone else seeing it: their own machine prints the line (the clip is replicated; no message is sent)
	var other = await make_player({"player_name": "Leeia", "player_class": "Woodstalker"})
	said.clear()
	other.global_position = Vector3(3, 0, 0)
	var me: Node = TargetFrame.local_player()
	var waver: Node = other if me == p else p
	var waver_name: String = str(waver.player_name)
	waver._announce_seen_emote("emote_wave")
	check(said.has("%s waves." % waver_name), "a player nearby sees \"%s waves.\"" % waver_name)
	said.clear()
	waver.global_position = me.global_position + Vector3(40, 0, 0)
	waver._announce_seen_emote("dance_2")
	check(said.is_empty(), "not from 40 m away")
	other.queue_free()
	GameLog.general_message.disconnect(listen)

	# walking backward, sneaking
	p._moving_backward = true
	p.current_speed = 2.0
	p._update_animation()
	eq(p.anim_state, "walk_back", "walking backward has its own clip")
	p._moving_backward = false
	p.combat_node.apply_effect("stance_stealth", 60.0, {"stealthed": 1.0})
	p._update_animation()
	eq(p.anim_state, "sneak", "moving in Stealth: sneaking")
	p.combat_node.remove_effect("stance_stealth")
	p.current_speed = 0.0
	p.queue_free()
	await frames(2)

	# an Aetherfist bare-handed punches and kicks; a dodge sidesteps
	var monk = await make_player({"player_name": "Zfist", "player_class": "Aetherfist"})
	for i in 6:
		monk._trigger_attack_animation()
		check(Player3D.AETHERFIST_SWINGS.has(monk._current_attack_anim), "an Aetherfist's swing: %s" % monk._current_attack_anim)
	monk._tick_defense_skill("DODGE")
	eq(monk._current_cast_anim, "dodge_2", "an Aetherfist's dodge is the fancy one")
	# the tanks' taunts and Shield Bash have their own moves; there's no /beckon (the gesture is the taunt's)
	eq(Player3D.SKILL_CLIPS.get("taunt", ""), "emote_taunt", "Taunt: the taunting gesture")
	eq(Player3D.SKILL_CLIPS.get("defiant_roar", ""), "emote_taunt", "Defiant Roar too")
	eq(Player3D.SKILL_CLIPS.get("shield_bash", ""), "shield_kick", "Shield Bash: the sword-and-shield kick")
	check(not Player3D.EMOTES.has("beckon"), "no /beckon")
	# a big blow (15%+ of your health) makes you flinch; from behind, you stagger forward; a small one doesn't
	monk._cast_anim_timer = 0.0
	monk._current_cast_anim = ""
	monk.combat_node.current_hp = monk.combat_node.max_hp
	monk.take_damage(1)
	check(monk._cast_anim_timer <= 0.0, "a scratch: no reaction")
	monk.take_damage(int(ceil(monk.combat_node.max_hp * 0.2)))
	eq(monk._current_cast_anim, "hit_front", "a big hit: a flinch")
	monk._cast_anim_timer = 0.0
	var behind := Node3D.new()
	add_child(behind)
	behind.global_position = monk.global_position + monk.global_transform.basis.z * 2.0   # (the model faces -Z)
	monk.combat_node.current_hp = monk.combat_node.max_hp
	monk.take_damage(int(ceil(monk.combat_node.max_hp * 0.2)), behind)
	eq(monk._current_cast_anim, "hit_back", "from behind: staggered forward")
	behind.queue_free()
	monk._cast_anim_timer = 0.0
	# a flying kick is a flying kick
	eq(Player3D.SKILL_CLIPS.get("flying_kick", ""), "flying_kick", "Flying Kick has its own move")
	monk._cast_anim_timer = 0.0   # (the dodge above has played out)
	monk.play_task_clip("fish_cast", 2.0)
	monk._update_animation()
	eq(monk.anim_state, "fish_cast", "gathering at a fishing spot casts a line")
	monk.stop_task_clip()
	monk._update_animation()
	eq(monk.anim_state, "idle", "and stops when the gather ends")
	monk.queue_free()
	await frames(2)
	check(FileAccess.get_file_as_string("res://Scripts/gathering_node.gd").contains('const GATHER_CLIPS := {"fishing": "fish_cast", "forage": "pick_up"}'), "fishing and foraging have their clips")
