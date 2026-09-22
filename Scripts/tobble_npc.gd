# tobble_npc.gd — Tobble Cogfarrow, gnome tinkerer of Lumora. Built on VendorNPC, same shape as harbour_master.gd: right-click
# (or hail) opens his shop, which for now sells one thing he's actually willing to stand behind (a compass) — he doesn't teach
# the Tinkering skill yet, because no tradeskill recipes exist for it, and his own personality (always refining, never quite
# satisfied) is the in-fiction reason why rather than a silent gap. He also talks on his own, same ambient-chatter pattern
# Tobias uses at the harbour. All his lines: Data/tobble.json.
# Multiplayer: he is a static scene node on every peer; the SERVER decides the ambient line and relays it (each peer applies
# its own hearing range), same as the harbour master's and the guards' banter.
extends VendorNPC
class_name TobbleTinkerer

const CONFIG_PATH := "res://Data/tobble.json"
const HEAR_RANGE := 12.0

@export var model_key: String = "gnome_male"

var _config: Dictionary = {}
var _next_ambient_msec := 0
var _conversation: NPCConversation = null


func _ready() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH)) if FileAccess.file_exists(CONFIG_PATH) else null
	_config = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	super._ready()
	add_to_group("npc_talker")  # hears what nearby players say (keyword conversation, npc_conversation.gd)
	_conversation = NPCConversation.new(self, _config.get("topics", []))
	if _is_decider():
		_schedule_ambient()


# ── VendorNPC hooks ──
func _build_character_model() -> void:
	animation_player = NPCRaceModel.build(self, model_key)


func _setup_animation() -> void:
	pass  # NPCRaceModel.build() already loaded the library and started idle


# Said when his shop opens (right-click or hail): a greeting, then an honest word about the state of his bench — the compass
# is the one thing on it that's actually finished.
func greet_player(_player_name: String) -> void:
	_face_player()
	say_local(_pick("greeting"))
	say_local(_pick("shop_intro"))


func respond_to_hail() -> void:
	_face_player()
	greet_player("")


# ── Ambient talk (server decides, everyone hears within range) ──
func _process(_delta: float) -> void:
	if not _is_decider() or Time.get_ticks_msec() < _next_ambient_msec:
		return
	_schedule_ambient()
	var night_chance := float(_config.get("ambient_secret_chance_at_night", 0.2))
	var line := _pick("secret") if (_is_night() and randf() < night_chance) else _pick("ambient")
	if not line.is_empty():
		say_to_all(line)


func _is_decider() -> bool:
	return not Net.is_multiplayer_game or not multiplayer.has_multiplayer_peer() or multiplayer.is_server()


func _schedule_ambient() -> void:
	var minutes: Array = _config.get("ambient_minutes", [3, 6])
	_next_ambient_msec = Time.get_ticks_msec() + int(randf_range(float(minutes[0]), float(minutes[1])) * 60000.0)


func _is_night() -> bool:
	var cycles := get_tree().get_nodes_in_group("day_night_cycle")
	return not cycles.is_empty() and cycles[0].has_method("is_day") and not cycles[0].is_day()


# ── Lines ──
func _pick(category: String) -> String:
	var lines = _config.get(category, [])
	return "" if typeof(lines) != TYPE_ARRAY or lines.is_empty() else str(lines[randi() % lines.size()])


func say_local(line: String) -> void:
	if line.is_empty():
		return
	var player := TargetFrame.local_player()
	if not is_instance_valid(player) or global_position.distance_to(player.global_position) > HEAR_RANGE:
		return
	GameLog.log_general("[color=#88ccaa]%s says, \"%s\"[/color]" % [get_vendor_display_name(), NPCConversation.format(line)])


# ── Conversation (npc_conversation.gd) ──
func speak(line: String) -> void:
	say_local(line)


func face_player() -> void:
	_face_player()


func can_trade() -> bool:
	return true


func can_answer(player: Node, text: String) -> bool:
	return _conversation != null and _conversation.can_answer(player, text)


func hear_say(player: Node, text: String) -> void:
	if _conversation != null:
		_conversation.hear(player, text)


func dynamic_lines(name: String) -> Array:
	var lines = _config.get(name, [])
	return lines if typeof(lines) == TYPE_ARRAY else []


func say_to_all(line: String) -> void:
	say_local(line)
	if Net.is_multiplayer_game and multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_rpc_say.rpc(line)


@rpc("authority", "call_remote", "reliable")
func _rpc_say(line: String) -> void:
	say_local(line)


func _face_player() -> void:
	var player: Node3D = TargetFrame.local_player()
	if not is_instance_valid(player):
		return
	var target := player.global_position
	target.y = global_position.y
	if target.distance_to(global_position) > 0.01:
		look_at(target, Vector3.UP)
