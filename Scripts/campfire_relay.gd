# campfire_relay.gd — campfires players light from a Firewood Bundle (Woodworking; test 42: "let's also add in the
# craftable campfire so i can test it"). Right-click the bundle in your bags and press Light: a campfire burns where you
# stand for its tier's time, then goes out. It is a real campfire (campfire.tscn): you can cook at it, and lingering by it
# gives Warmth of the Campfire as the roadside fires do. Its warmth reaches AURA_RANGE, and everyone within it earns
# bonus experience from kills by tier (3 / 6 / 10%, the best fire only, fires don't stack).
# Not in town (within TOWN_RANGE of a vendor, guard, townsperson, crafting station or bank, or anywhere in the city), not
# in combat, and not within SPACING of another fire.
#
# Like world_items.gd (whose child this is, made on every peer so its path and RPCs match everywhere), the SERVER owns the
# list: a lit fire is sent to it, it shows it on every peer and puts it out when it burns down; a player who arrives later
# asks for the fires already burning. The XP bonus is worked out on the server too, where the kill's XP is shared
# (monster3d.gd), so the save checks (server_trust.gd) count it.
class_name CampfireRelay
extends Node

const TIERS := {
	"fir_firewood_bundle": {"xp": 0.03, "minutes": 10.0, "regen": 2},
	"ironwood_firewood_bundle": {"xp": 0.06, "minutes": 20.0, "regen": 4},
	"palm_firewood_bundle": {"xp": 0.10, "minutes": 30.0, "regen": 6},
}
const AURA_RANGE := 15.0
const SPACING := 20.0
const TOWN_RANGE := 40.0
const TOWN_GROUPS := ["npc_vendor", "npc_guard", "npc_talker", "crafting_station", "bank_window"]
const CITY_SCENES := ["res://Scenes/zones/lumora.tscn"]
const EXPIRY_CHECK_SECONDS := 5.0
const CAMPFIRE_SCENE := "res://Scenes/campfire.tscn"

var _fires := {}     # SERVER: id -> {"pos": Vector3, "item_id": String, "expires_ms": int, "lit_by": String}
var _nodes := {}     # every peer: id -> the campfire shown
var _next_id := 1
var _expiry_timer := 0.0
var _asked_for_snapshot := false


func _ready() -> void:
	multiplayer.server_disconnected.connect(func() -> void: _asked_for_snapshot = false)


func _process(delta: float) -> void:
	if _is_server():
		_expiry_timer -= delta
		if _expiry_timer <= 0.0:
			_expiry_timer = EXPIRY_CHECK_SECONDS
			var now := Time.get_ticks_msec()
			for id in _fires.keys():
				if now >= int(_fires[id]["expires_ms"]):
					_put_out_everywhere(id)
	elif not _asked_for_snapshot and is_instance_valid(TargetFrame.local_player()):
		_asked_for_snapshot = true
		_rpc_request_snapshot.rpc_id(1)


static func relay(tree: SceneTree) -> CampfireRelay:
	var items := tree.get_first_node_in_group("world_items") if tree else null
	return items.get_node_or_null("CampfireRelay") as CampfireRelay if items else null


# Why `player` can't light a fire where it stands ("" = it can).
static func refusal(player: Node3D) -> String:
	var tree := player.get_tree()
	var zone := tree.current_scene
	if zone and CITY_SCENES.has(zone.scene_file_path):
		return "You can't make camp inside the city."
	for group in TOWN_GROUPS:
		for n in tree.get_nodes_in_group(group):
			if n is Node3D and (n as Node3D).global_position.distance_to(player.global_position) <= TOWN_RANGE:
				return "You can't make camp in town."
	var cn = player.get("combat_node")
	var attacked_ms := int(player.get("last_attacked_msec")) if "last_attacked_msec" in player else -100000
	if (cn is CombatNode and cn.in_combat) or Time.get_ticks_msec() - attacked_ms < 10000:
		return "You can't make camp while you're fighting."
	for fire in tree.get_nodes_in_group("campfires"):
		if fire is Node3D and (fire as Node3D).global_position.distance_to(player.global_position) <= SPACING:
			return "There's already a fire burning nearby."
	return ""


# The best XP bonus from a burning player fire within AURA_RANGE of `pos` (the server's list; 0 if none).
static func xp_bonus_at(tree: SceneTree, pos: Vector3) -> float:
	var r := relay(tree)
	if r == null:
		return 0.0
	var best := 0.0
	for id in r._fires:
		var f: Dictionary = r._fires[id]
		if (f["pos"] as Vector3).distance_to(pos) <= AURA_RANGE:
			best = maxf(best, float(TIERS.get(f["item_id"], {}).get("xp", 0.0)))
	return best


# ── Called on the player's own machine (the bundle is already used up) ───────────────────────────────────────────────

func light(item_id: String, pos: Vector3, lit_by: String) -> void:
	if _is_server():
		_server_light(item_id, pos, lit_by, multiplayer.get_unique_id())
	else:
		_rpc_light.rpc_id(1, item_id, pos, lit_by)


# ── Server ──────────────────────────────────────────────────────────────────────────────────────────────────────────

func _is_server() -> bool:
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()


func _has_remote_peers() -> bool:
	return multiplayer.has_multiplayer_peer() and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer) \
			and not multiplayer.get_peers().is_empty()


func _server_light(item_id: String, pos: Vector3, lit_by: String, peer: int) -> void:
	if not TIERS.has(item_id):
		return
	for id in _fires:
		if (_fires[id]["pos"] as Vector3).distance_to(pos) <= SPACING:
			return   # two lit at once, a step apart: the first one burns
	var id := _next_id
	_next_id += 1
	var seconds := float(TIERS[item_id]["minutes"]) * 60.0
	_fires[id] = {"pos": pos, "item_id": item_id, "lit_by": lit_by, "expires_ms": Time.get_ticks_msec() + int(seconds * 1000.0)}
	if not Net.is_dedicated_server:
		_show(id, pos, int(TIERS[item_id]["regen"]))
	if _has_remote_peers():
		_rpc_show.rpc(id, pos, int(TIERS[item_id]["regen"]))
	var text := "[color=#ffaa55]%s lights a campfire.[/color]" % lit_by
	if peer == multiplayer.get_unique_id():
		GameLog.log_general("[color=#ffaa55]You light a campfire. It will burn for %d minutes.[/color]" % int(TIERS[item_id]["minutes"]))
	elif multiplayer.has_multiplayer_peer():
		_rpc_lit.rpc_id(peer, int(TIERS[item_id]["minutes"]))
	if Net.is_multiplayer_game and multiplayer.has_multiplayer_peer():
		Net.broadcast_combat_message(text, pos)


func _put_out_everywhere(id: int) -> void:
	_fires.erase(id)
	_hide(id)
	if _has_remote_peers():
		_rpc_hide.rpc(id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_light(item_id: String, pos: Vector3, lit_by: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var player := TargetFrame.peer_id_to_player_node(sender) as Node3D
	if is_instance_valid(player) and player.global_position.distance_to(pos) > 6.0:
		return   # a fire is lit where you stand
	_server_light(item_id, pos, lit_by, sender)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_snapshot() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	for id in _fires:
		_rpc_show.rpc_id(sender, id, _fires[id]["pos"], int(TIERS[_fires[id]["item_id"]]["regen"]))


# ── Every peer ──────────────────────────────────────────────────────────────────────────────────────────────────────

@rpc("authority", "call_remote", "reliable")
func _rpc_show(id: int, pos: Vector3, regen: int) -> void:
	_show(id, pos, regen)


@rpc("authority", "call_remote", "reliable")
func _rpc_hide(id: int) -> void:
	_hide(id)


@rpc("authority", "call_remote", "reliable")
func _rpc_lit(minutes: int) -> void:
	GameLog.log_general("[color=#ffaa55]You light a campfire. It will burn for %d minutes.[/color]" % minutes)


func _show(id: int, pos: Vector3, regen: int = 2) -> void:
	_hide(id)
	var zone := get_tree().current_scene
	if zone == null:
		return
	var fire: Node3D = (load(CAMPFIRE_SCENE) as PackedScene).instantiate()
	fire.name = "PlayerCampfire_%d" % id
	fire.display_name = "Your Campfire"
	fire.regen_bonus = regen   # a better bundle, a warmer fire
	zone.add_child(fire)
	fire.global_position = pos
	# its warmth reaches the whole camp, not just the few steps round a roadside fire
	var shape := fire.get_node_or_null("WarmthArea/CollisionShape3D") as CollisionShape3D
	if shape and shape.shape is SphereShape3D:
		var sphere := (shape.shape as SphereShape3D).duplicate() as SphereShape3D
		sphere.radius = AURA_RANGE
		shape.shape = sphere
	_nodes[id] = fire


func _hide(id: int) -> void:
	var node: Node = _nodes.get(id)
	_nodes.erase(id)
	if not is_instance_valid(node):
		return
	var me := TargetFrame.local_player() as Node3D
	if is_instance_valid(me) and me.global_position.distance_to((node as Node3D).global_position) <= AURA_RANGE:
		GameLog.log_general("The campfire burns down to embers.")
	node.queue_free()
