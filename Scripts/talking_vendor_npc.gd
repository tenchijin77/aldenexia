# talking_vendor_npc.gd — a vendor who talks: right-click or hail opens their shop with a greeting, they chat on their own
# to anyone nearby (ambient lines, a rarer "secret" line at night), and they answer keywords said near them. Everything
# they say lives in a JSON file (config_path) in the same shape as Data/tobble.json: greeting / shop_intro / ambient /
# secret / topics. Which model, name, title and shop are set on the node (Scenes/talking_vendor.tscn instances).
# Used by the Lumora scribes (Data/scribe_ilsabet.json, Data/scribe_xalvyr.json); Tobble and the harbour master are older
# one-off versions of the same thing.
# Multiplayer: a static scene node on every peer; the SERVER decides the ambient line and relays it (each peer applies
# its own hearing range), same as Tobble's and the guards' banter.
extends VendorNPC
class_name TalkingVendorNPC


const HEAR_RANGE := 12.0

@export var config_path: String = ""
@export var model_key: String = "human_male"
@export var title: String = ""  # shown under the name on the nameplate, e.g. "Archivist of the Oasis Wardens"

var _config: Dictionary = {}
var _next_ambient_msec := 0
var _conversation: NPCConversation = null


func _ready() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(config_path)) if FileAccess.file_exists(config_path) else null
	_config = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	super._ready()
	if not title.is_empty():
		name_label.text = "%s\n<%s>" % [npc_name, title]
	add_to_group("npc_talker")  # hears what nearby players say (keyword conversation, npc_conversation.gd)
	_conversation = NPCConversation.new(self, _config.get("topics", []))
	if _is_decider():
		_schedule_ambient()


# ── VendorNPC hooks ──
func _build_character_model() -> void:
	# A vendor with a model of its own (Vendor Model Key "male"/"female": Aldric's and Lira's Meshy models) keeps it;
	# everyone else is dressed as a person of their race (Model Key).
	if VENDOR_MODELS.has(vendor_model_key):
		super._build_character_model()
		return
	animation_player = NPCRaceModel.build(self, model_key)


func _setup_animation() -> void:
	if VENDOR_MODELS.has(vendor_model_key):
		super._setup_animation()   # a vendor model's own animation library
	# otherwise NPCRaceModel.build() already loaded the library and started idle


# Said when the shop opens (right-click or hail).
func greet_player(_player_name: String) -> void:
	_face_player()
	say_local(_pick("greeting"))
	say_local(_pick("shop_intro"))


func respond_to_hail() -> void:
	_face_player()
	# Someone with work for you says so (hail_hooks in the NPC's JSON; npc_conversation.gd hook_line()).
	var hook := _conversation.hook_line(_config.get("hail_hooks", [])) if _conversation != null else ""
	if not hook.is_empty():
		say_local(hook)
		return
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
	var spoken := Languages.npc_line(Languages.voice_of(self), line)
	GameLog.log_general("[color=#88ccaa]%s says%s, \"%s\"[/color]" % [get_vendor_display_name(), spoken[0], NPCConversation.format(spoken[1])])


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


func dynamic_lines(line_set: String) -> Array:
	var lines = _config.get(line_set, [])
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
