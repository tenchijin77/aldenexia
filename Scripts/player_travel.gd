# player_travel.gd — caster travel, evacuation, gates and binding (design: ~/NCT/Aldenexia-Lightfall/Class teleportation Spell
# Notes.txt and Class mechanics.txt). A child node "Travel" of every player (player3d.gd _ready()), so its RPCs reach the
# same node on every peer: the caster's copy on each machine opens the portal there, and each machine moves only its OWN
# player (players are self-authoritative; the server never checks positions).
#
# Spells carry "travel" in Data/player_spells.json:
#   "bind"   Attune Spirit — your bind point becomes where you stand (once an hour, not in combat).
#   "gate"   every class's self-gate (Recall to Sanctuary, Call of Nature, ...) — you, to your bind point.
#   "ritual" group travel to an attuned Ley-Line Node (Data/ley_lines.json, ley_line_node.gd); you pick which when you cast.
#            Spectral Bridge ("bridge"): a bridge opens behind the rooted Arcanist for the whole channel; group members run
#            across it; the Arcanist is pulled through when it ends. Chaos Rift ("rift"): the same with a jagged hole and a
#            5-8 s cast; 5% Wild Surge on arrival. Root-Tunnel ("tunnel"): vines pull the group within 8 m under at the end;
#            everyone arrives with Nature's Ward.
#   "evac"   the group within 20 m to the zone's entrance: Spatial Redoubt (slow, safe), Wormhole (fast, dirty), Phase Snap
#            (1.5 s, d20 Chaos Tax: 1-5 caster loses 20% max mana, 6-10 Aether-Sickness, 11-15 teleport trash, 16-20 heal).
# "Group" = players in the caster's group (group_members); alone, it is just the caster.
extends Node
class_name PlayerTravel

const LEY_LINES_PATH := "res://Data/ley_lines.json"
const ZONE_KEY := "lumora_outskirts"   # one zone so far
const BIND_CHANGE_SECONDS := 3600.0
const TRASH := ["bent_spoon", "stranger_button", "half_a_letter", "warm_pebble"]
const ARRIVAL_SCATTER := 2.5           # metres: a group doesn't land on one spot

static var _zone_cache: Dictionary = {}

var player: Node                        # the Player3D this belongs to (the caster, on every peer)
var _destination: Dictionary = {}       # the ley-line picked for the ritual being cast
var _destination_for := ""
var _portal: Node3D = null              # this player's open portal/vines/sphere on THIS machine


func _ready() -> void:
	player = get_parent()


static func zone() -> Dictionary:
	if _zone_cache.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(LEY_LINES_PATH)) if FileAccess.file_exists(LEY_LINES_PATH) else null
		_zone_cache = parsed.get(ZONE_KEY, {}) if typeof(parsed) == TYPE_DICTIONARY else {}
	return _zone_cache


static func node_entry(id: String) -> Dictionary:
	for entry in zone().get("nodes", []):
		if str(entry.get("id", "")) == id:
			return entry
	return {}


# ── Casting hooks (called by player3d.gd on the caster's own machine) ──

# Before mana/cooldown are spent: false stops the cast. A ritual with no destination picked opens the chooser instead; picking
# one casts the spell again.
func pre_cast(spell_name: String, spell: Dictionary) -> bool:
	var kind := str(spell.get("travel", ""))
	var display := Player3D.spell_display_name(spell_name)
	if kind in ["gate", "ritual", "bind"] and player.combat_node.in_combat:
		GameLog.log_general("[color=#ff8866]You can't cast [b]%s[/b] in the middle of a fight.[/color]" % display)
		return false
	if kind == "bind":
		var since := Time.get_unix_time_from_system() - float(Global.player_data.get("bind_attuned_at", 0.0))
		if since < BIND_CHANGE_SECONDS:
			GameLog.log_general("[color=#ff8866]Your spirit is still settling from its last attunement. Try again in %d minutes.[/color]" % int(ceil((BIND_CHANGE_SECONDS - since) / 60.0)))
			return false
	if kind == "ritual" and (_destination.is_empty() or _destination_for != spell_name):
		var choices: Array = zone().get("nodes", []).filter(func(e): return LeyLineNode.is_attuned(str(e.get("id", ""))))
		if choices.is_empty():
			GameLog.log_general("[color=#ff8866]You aren't attuned to any ley-line yet. Find a ley-stone and right-click it to attune.[/color]")
			return false
		_open_chooser(spell_name, choices)
		return false
	return true


# The cast has begun (it has a cast time): open what the group can see — the bridge, the rift, the vines, the fold.
func on_cast_started(spell_name: String, spell: Dictionary, cast_time: float) -> void:
	var kind := str(spell.get("travel_kind", ""))
	if kind in ["gate", "bind", "snap"]:
		return
	var back: Vector3 = player.global_transform.basis.z
	back.y = 0.0
	back = back.normalized() if back.length() > 0.01 else Vector3.BACK
	var dest := Vector2.ZERO
	if not _destination.is_empty():
		var p: Array = _destination.get("position", [0, 0])
		dest = Vector2(float(p[0]), float(p[1]))
	var dest_name := str(_destination.get("name", ""))
	_open_portal(kind, player.global_position, back, dest, dest_name, cast_time + 0.5)
	_broadcast("travel_open_portal", [kind, player.global_position, back, dest, dest_name, cast_time + 0.5])


# The cast ended without finishing (moved, interrupted, died): close it for everyone.
func on_cast_stopped() -> void:
	_destination = {}
	_destination_for = ""
	if is_instance_valid(_portal):
		_close_portal()
		_broadcast("travel_close_portal", [])


# The cast finished.
func resolve(spell_name: String, spell: Dictionary) -> void:
	var kind := str(spell.get("travel_kind", ""))
	match str(spell.get("travel", "")):
		"bind":
			Global.player_data["bind_point"] = [player.global_position.x, player.global_position.y, player.global_position.z]
			Global.player_data["bind_attuned_at"] = Time.get_unix_time_from_system()
			Global.save_player_data_to_file()
			GameLog.log_general("[color=#ffdd44]Your spirit settles into this place. You will return here when you fall, and your gate spell brings you here.[/color]")
		"gate":
			var bind: Vector3 = player.get_bind_point()
			arrive("gate", Vector2(bind.x, bind.z), {"name": "your bind point", "exact_y": bind.y}, str(player.player_name))
		"ritual":
			var p: Array = _destination.get("position", [0, 0])
			var dest := Vector2(float(p[0]), float(p[1]))
			var extra := {"name": str(_destination.get("name", "the ley-line"))}
			if kind == "tunnel":
				var radius := float(spell.get("aoe_radius", 8.0))
				_broadcast("travel_pull", [kind, player.global_position, radius, dest, extra])
			if is_instance_valid(_portal):
				_close_portal()
				_broadcast("travel_close_portal", [])
			arrive(kind, dest, extra, str(player.player_name), true)
		"evac":
			var e: Array = zone().get("zone_entrance", [0, 0])
			var dest := Vector2(float(e[0]), float(e[1]))
			var extra := {"name": "the town gate"}
			if kind == "snap":
				var roll := randi_range(1, 20)
				extra["roll"] = roll
				GameLog.log_combat("[color=#cc88ff]The Chaos Tax: you roll [b]%d[/b].[/color]" % roll)
				if roll <= 5:
					var burn := int(player.combat_node.max_mana * 0.2)
					player.combat_node.current_mana = maxi(0, player.combat_node.current_mana - burn)
					GameLog.log_combat("[color=#ff8866]Aetheric Burn: the snap tears [b]%d[/b] extra mana out of you.[/color]" % burn)
			var radius := float(spell.get("aoe_radius", 20.0))
			_broadcast("travel_pull", [kind, player.global_position, radius, dest, extra])
			if is_instance_valid(_portal):
				_close_portal()
				_broadcast("travel_close_portal", [])
			arrive(kind, dest, extra, str(player.player_name), true)
	_destination = {}
	_destination_for = ""


# ── Arriving (always this machine's OWN player) ──
func arrive(kind: String, dest: Vector2, extra: Dictionary, caster_name: String, is_caster: bool = false) -> void:
	var scatter := Vector2.ZERO if kind in ["gate"] or is_caster else Vector2.from_angle(randf() * TAU) * randf_range(1.0, ARRIVAL_SCATTER)
	var spot := dest + scatter
	var pos := _ground_point(spot)
	if extra.has("exact_y"):
		pos.y = float(extra["exact_y"])
	var where := str(extra.get("name", "somewhere else"))
	_flash(kind, float(extra.get("roll", 20)))
	player.velocity = Vector3.ZERO
	player.global_position = pos
	player._fall_grace_until_ms = Time.get_ticks_msec() + Player3D.FALL_GRACE_MS
	if is_instance_valid(player.active_pet) and player.active_pet.has_method("recall_to_owner"):
		player.active_pet.recall_to_owner()
	var cn: CombatNode = player.combat_node
	match kind:
		"gate":
			GameLog.log_general("[color=#99ddcc]The world blurs, and you arrive at your bind point.[/color]")
		"bridge":
			if is_caster:
				GameLog.log_general("[color=#99ccff]The portal surges forward and swallows you. You step out at the %s.[/color]" % where)
			else:
				GameLog.log_general("[color=#99ccff]You run the length of %s's spectral bridge and step out at the %s.[/color]" % [caster_name, where])
		"rift":
			GameLog.log_general("[color=#cc88ff]You step through the rift and stumble out at the %s.[/color]" % where)
			if randf() < 0.05:
				if randf() < 0.5:
					cn.apply_effect("wild_surge", 30.0, {"move_speed_bonus": 0.2})
					GameLog.log_combat("[color=#cc88ff]Wild Surge! Leftover chaos quickens your step.[/color]")
				else:
					var leak := int(cn.max_mana * 0.1)
					cn.current_mana = maxi(0, cn.current_mana - leak)
					GameLog.log_combat("[color=#cc88ff]Wild Surge! The rift leaks away %d of your mana.[/color]" % leak)
		"tunnel":
			GameLog.log_general("[color=#88dd88]Vines coil around you and pull you down into the earth. You surface at the %s, the Green humming around you.[/color]" % where)
			cn.apply_effect("natures_ward", 120.0, {"hp_regen_bonus": 3})
			GameLog.log_combat("[color=#88dd88]You arrive with Nature's Ward.[/color]")
		"redoubt":
			GameLog.log_general("[color=#99ccff]Reality folds, neatly, and the town gate is simply here.[/color]")
		"wormhole":
			GameLog.log_general("[color=#b0a070]The earth swallows you and drags you through the dark. You're spat out at the town gate, covered in dirt.[/color]")
		"snap":
			GameLog.log_general("[color=#cc88ff]Reality cracks like a whip and spits you out at the town gate.[/color]")
			var roll := int(extra.get("roll", 20))
			if roll <= 5 and not is_caster:
				GameLog.log_combat("[color=#cc88ff]%s pays the Chaos Tax in mana.[/color]" % caster_name)
			elif roll >= 6 and roll <= 10:
				cn.apply_effect("aether_sickness", 20.0, {"move_speed_bonus": -0.3})
				GameLog.log_combat("[color=#ff8866]Aether-Sickness: the world swims, and your legs feel like lead.[/color]")
			elif roll >= 11 and roll <= 15:
				var trash: String = TRASH.pick_random()
				Inventory.add_item(trash, 1)
				GameLog.log_combat("[color=#cc88ff]The Void's Toll: there's something in your pack that wasn't there before — %s.[/color]" % Inventory.get_item_definition(trash).get("name", trash))
			elif roll >= 16:
				var healed := cn.heal(int(cn.max_hp * 0.1))
				GameLog.log_combat("[color=#66ff99]Lucky Break: a clean escape, and you feel %s.[/color]" % ("a little better" if healed > 0 else "fine"))


func _ground_point(xz: Vector2) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(Vector3(xz.x, 300.0, xz.y), Vector3(xz.x, -100.0, xz.y))
	query.exclude = [player.get_rid()]
	var hit := Global.ground_ray(player.get_world_3d().direct_space_state, query)
	return (hit["position"] + Vector3(0, 0.3, 0)) if not hit.is_empty() else Vector3(xz.x, 2.0, xz.y)


# A brief screen wash on arrival: blue-white for magic, earthy for the tunnels, violet flicker for Phase Snap.
func _flash(kind: String, roll: float) -> void:
	var colour := Color(0.75, 0.85, 1.0, 0.65)
	var seconds := 0.5
	match kind:
		"tunnel", "wormhole":
			colour = Color(0.25, 0.2, 0.1, 0.9)
			seconds = 0.9
		"rift", "snap":
			colour = Color(0.6, 0.3, 0.9, 0.7)
			seconds = 1.4 if kind == "snap" and roll >= 6 and roll <= 10 else 0.6
	var layer := CanvasLayer.new()
	layer.layer = 90
	var rect := ColorRect.new()
	rect.color = colour
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(rect)
	player.get_tree().root.add_child(layer)
	var tween := layer.create_tween()
	if kind in ["rift", "snap"]:
		for i in 3:  # the "glitch": a few hard flickers
			tween.tween_property(rect, "modulate:a", 0.15, seconds / 8.0)
			tween.tween_property(rect, "modulate:a", 1.0, seconds / 8.0)
	tween.tween_property(rect, "modulate:a", 0.0, seconds / 2.0)
	tween.tween_callback(layer.queue_free)


# ── The destination chooser ──
func _open_chooser(spell_name: String, choices: Array) -> void:
	var old := player.get_tree().root.get_node_or_null("TravelDestinations")
	if old:
		old.name = "TravelDestinationsOld"
		old.queue_free()
	var menu := PopupMenu.new()
	menu.name = "TravelDestinations"
	menu.add_separator("%s — where to?" % Player3D.spell_display_name(spell_name))
	for i in range(choices.size()):
		menu.add_item(str(choices[i].get("name", "?")), i)
	menu.id_pressed.connect(func(id: int):
		menu.queue_free()
		_destination = choices[id]
		_destination_for = spell_name
		player.cast_spell(spell_name))
	menu.popup_hide.connect(menu.queue_free)
	player.get_tree().root.add_child(menu)
	menu.popup(Rect2i(Vector2i(player.get_viewport().get_mouse_position()), Vector2i(220, 0)))


# ── Portals: shown on every machine; each machine sends only its own player through ──
func _open_portal(kind: String, origin: Vector3, back: Vector3, dest: Vector2, dest_name: String, seconds: float) -> void:
	if is_instance_valid(_portal):
		_portal.queue_free()
	_portal = TravelPortal.new()
	_portal.setup(kind, origin, back, dest, dest_name, seconds, player)
	player.get_tree().current_scene.add_child(_portal)


func _close_portal() -> void:
	if is_instance_valid(_portal):
		_portal.close()
	_portal = null


func _broadcast(method: String, args: Array) -> void:
	if not Net.is_multiplayer_game or not multiplayer.has_multiplayer_peer():
		return
	callv("rpc", [method] + args)


@rpc("any_peer", "call_remote", "reliable")
func travel_open_portal(kind: String, origin: Vector3, back: Vector3, dest: Vector2, dest_name: String, seconds: float) -> void:
	if multiplayer.get_remote_sender_id() != player.get_multiplayer_authority():
		return
	_open_portal(kind, origin, back, dest, dest_name, seconds)


@rpc("any_peer", "call_remote", "reliable")
func travel_close_portal() -> void:
	if multiplayer.get_remote_sender_id() != player.get_multiplayer_authority():
		return
	_close_portal()


# The caster pulls their group (Root-Tunnel, the evacuations): each machine checks whether ITS player is in the caster's
# group and close enough, and if so moves it.
@rpc("any_peer", "call_remote", "reliable")
func travel_pull(kind: String, center: Vector3, radius: float, dest: Vector2, extra: Dictionary) -> void:
	var caster_peer := player.get_multiplayer_authority()
	if multiplayer.get_remote_sender_id() != caster_peer:
		return
	var me := TargetFrame.local_player()
	if me == null or me == player or not (caster_peer in me.group_members) or me.global_position.distance_to(center) > radius:
		return
	me.get_node("Travel").arrive(kind, dest, extra, str(player.player_name))
