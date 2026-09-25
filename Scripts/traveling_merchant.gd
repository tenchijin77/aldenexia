# traveling_merchant.gd — Sahren of the Deep Wells, the Djhanid traveling merchant. Not a permanent fixture: he walks a loop
# through Solgrave's zones on a timetable (merchant_schedule.gd), and traveling_merchant_spawner.gd brings him into a zone
# when his loop reaches it. In a zone he WALKS (a real navmesh path, at a walking pace) from stop to stop (route: the
# Outskirts' docks and gate; Dustwind's Stone Circles, Nomad Camp and Destroyed Caravan), trades at each for a while, then
# walks out of the zone and is gone. Hail him on the road and he stops for a chat and a sale (CHATTING), then walks on.
# His stock is a shop in Data/vendor_shop.json (shop_id), his timings and lines are in Data/traveling_merchant.json.
#
# Built on VendorNPC to reuse its plumbing (targeting, hail range, shop stock/prices). Multiplayer: the SERVER walks him
# and keeps the schedule; every other peer just mirrors what is replicated (position, rotation, stage, anim_state — see the
# scene's MultiplayerSynchronizer) and plays the matching animation. All timings use real-world time, not game time.
extends VendorNPC
class_name TravelingMerchant


enum Stage { ROAD, AT_STOP, LEAVING, CHATTING }

const CONFIG_PATH := "res://Data/traveling_merchant.json"
const INTERACT_RANGE := 8.0
const HEAR_RANGE := 14.0          # he calls out his wares, so he carries farther than a guard's mutter
const CORNER_ARRIVAL := 1.5
const ARRIVAL := 1.0              # how close counts as "reached" a stop
const GRAVITY := 20.0
const HOP_HEIGHT := 1.4           # a ledge up to about this high he hops onto (the dock's deck is 1 m up and the navmesh does not join it to the shore)
const WALKABLE_NORMAL_Y := 0.6   # a surface this upright or flatter (slopes up to ~53°) is ground to walk up, not an obstacle
const STALL_SECONDS := 20.0       # no progress toward the stop for this long -> repath / skip a corner
const TRAVEL_SLACK := 2.5         # a leg may take this many times its expected time before he is simply placed at the stop
const LEAVING_SECONDS := 4.0      # after the farewell, before he is gone
const HAWK_MIN_SECONDS := 60.0   # ambient talk while he trades: one line every 1-2 minutes
const HAWK_MAX_SECONDS := 120.0
const EMOTE_COLOR := "#ffd9a0"

## Replicated to every peer (see the scene's MultiplayerSynchronizer).
var stage: int = Stage.ROAD
var anim_state: String = "idle"

var route: Array = []              # set by the spawner: [{pos: Vector3, name: String, stay: seconds}] (server side walks; clients never do)
var route_exit := Vector3.ZERO     # where he walks out of the zone
var route_index := 0               # the stop he is heading for or standing at (== route.size(): heading for the exit)
var start_stay_left := -1.0        # spawned at a stop mid-stay (a zone's server started while he was there): seconds left

var _config: Dictionary = {}
var _lines: Dictionary = {}
var _model_key := "halfling_male"
var _walk_speed := 3.5
var _pause_seconds := 60.0        # how long he waits on the road for a customer
var _chat_until_msec := 0
var _warn_before := 30.0

var _path: PackedVector3Array = PackedVector3Array()
var _path_i := 0
var _dest := Vector3.ZERO
var _travelling := false
var _leg_deadline_msec := 0
var _off_mesh := false             # the navmesh path ends short of his stop (the dock): he finishes the leg in a straight line
var _shore_point := Vector3.INF    # where he left the navmesh for the dock: the next leg starts by walking back there
var _to_shore := false
var _best_dist := INF
var _stall := 0.0
var _leave_at_msec := 0            # when the current stay ends
var _warned := false
var _next_hawk_msec := 0
var _leaving_until_msec := 0
var _shown_anim := ""
var _conversation: NPCConversation = null
var _token_noticed := false        # he reacts to a Ceramic Water-Token once per visit (per player, on their own machine)


func _ready() -> void:
	if extra_languages.is_empty():
		extra_languages = ["djhanid"]  # Sahren trades in Common and his own Djhanid
	_load_config()
	snap_on_ready = false   # he walks his route (traveling_merchant_spawner.gd places him)
	super._ready()
	add_to_group("traveling_merchant")
	add_to_group("npc_talker")  # hears what nearby players say (keyword conversation, npc_conversation.gd)
	_conversation = NPCConversation.new(self, _config.get("topics", []))
	_next_hawk_msec = Time.get_ticks_msec() + int(randf_range(HAWK_MIN_SECONDS, HAWK_MAX_SECONDS) * 1000.0)
	if _is_server_side():
		if start_stay_left >= 0.0 and route_index < route.size():
			_arrive()   # a zone's server started while he was trading here: he is standing at the stop already
			_leave_at_msec = Time.get_ticks_msec() + int(start_stay_left * 1000.0)
		else:
			_begin_leg()


func _load_config() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH)) if FileAccess.file_exists(CONFIG_PATH) else null
	_config = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	npc_name = str(_config.get("name", "Traveling Merchant"))
	shop_id = str(_config.get("shop_id", "traveling_merchant"))
	_model_key = str(_config.get("model", _model_key))
	_walk_speed = float(_config.get("walk_speed", _walk_speed))
	_pause_seconds = float(_config.get("roadside_pause_seconds", _pause_seconds))
	_warn_before = float(_config.get("warn_before_leaving_seconds", _warn_before))
	_lines = _config.get("lines", {}) if typeof(_config.get("lines")) == TYPE_DICTIONARY else {}


# ── VendorNPC hooks ──
func _build_character_model() -> void:
	animation_player = NPCRaceModel.build(self, _model_key)


func _setup_animation() -> void:
	pass  # NPCRaceModel.build() already loaded the library and started idle


func get_vendor_display_name() -> String:
	return npc_name


# He is a traveler, not a fixture: nothing kills him and he never "respawns".
func die() -> void:
	pass


# True while he is standing with his wares out: at a stop, or stopped on the road for a customer.
func can_trade() -> bool:
	return stage == Stage.AT_STOP or stage == Stage.CHATTING


func respond_to_hail() -> void:
	if stage == Stage.ROAD:
		request_pause()   # on the road: he stops for you
		say_local(_pick("roadside"))
		return
	_face_player()
	if _notice_token():
		return
	say_local(_line_for_stage("hail"))


# A player hailed or clicked him while he walked: ask the server to stop him (it owns his walking).
func request_pause() -> void:
	if _is_server_side():
		_pause_on_road()
	else:
		_rpc_request_pause.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_pause() -> void:
	if not _is_server_side():
		return
	_pause_on_road()
	var customer := TargetFrame.peer_id_to_player_node(multiplayer.get_remote_sender_id()) as Node3D
	if customer != null and stage == Stage.CHATTING:   # turn to whoever stopped him (his rotation replicates)
		var target := customer.global_position
		target.y = global_position.y
		if target.distance_to(global_position) > 0.01:
			look_at(target, Vector3.UP)


# SERVER: stop for a customer (or keep waiting a little longer if he already has).
func _pause_on_road() -> void:
	if stage == Stage.ROAD:
		stage = Stage.CHATTING
		_travelling = false
		velocity.x = 0.0
		velocity.z = 0.0
	if stage == Stage.CHATTING:
		_chat_until_msec = Time.get_ticks_msec() + int(_pause_seconds * 1000.0)


# SERVER: his time in this zone is up (the timetable moved on): he packs up where he is.
func pack_up() -> void:
	if stage == Stage.LEAVING:
		return
	stage = Stage.LEAVING
	_travelling = false
	_leaving_until_msec = Time.get_ticks_msec() + int(LEAVING_SECONDS * 1000.0)
	say_to_all(_pick("farewell"))


# Called by Player3D when his shop opens: if you carry a Ceramic Water-Token he reacts to THAT first; otherwise a sales line.
func greet_player(_player_name: String) -> void:
	_face_player()
	if _notice_token():
		return
	say_local(_pick("sales"))


# A Djhanid water-token, far from any Djhanid: he goes still and asks where it came from. Once per visit.
func _notice_token() -> bool:
	if _token_noticed or not can_trade() or KenjiNPC.count_item(str(_config.get("token_item", "ceramic_water_token"))) <= 0:
		return false
	_token_noticed = true
	var emote := _pick("token_surprise_emote").replace("{name}", npc_name.split(" ")[0])
	if not emote.is_empty():
		GameLog.log_general("[color=%s]%s[/color]" % [EMOTE_COLOR, emote])
	say_local(_pick("token_surprise"))
	return true


func open_interaction(player: Node) -> void:
	if not is_instance_valid(player) or global_position.distance_to(player.global_position) > INTERACT_RANGE:
		GameLog.log_general("You are too far away to trade with %s." % npc_name)
		return
	if stage == Stage.ROAD:
		request_pause()   # he stops on the road to sell to you
		say_local(_pick("roadside"))
		player.open_shop_window(self)
		return
	_face_player()
	if not can_trade():
		say_local(_pick("hail_leaving"))
		return
	if stage == Stage.CHATTING:
		request_pause()   # still here: wait a little longer
	player.open_shop_window(self)


# ── Speech ──
func _pick(category: String) -> String:
	var lines: Array = _lines.get(category, [])
	return "" if lines.is_empty() else str(lines[randi() % lines.size()])


func _line_for_stage(_kind: String) -> String:
	match stage:
		Stage.AT_STOP, Stage.CHATTING: return _pick("greeting")
		Stage.LEAVING: return _pick("hail_leaving")
		_: return _pick("roadside")


# Said only to the local player, and only when close enough to hear. {word} marks a clickable keyword.
func say_local(line: String) -> void:
	if line.is_empty():
		return
	var player := TargetFrame.local_player()
	if not is_instance_valid(player) or global_position.distance_to(player.global_position) > HEAR_RANGE:
		return
	var spoken := Languages.npc_line(Languages.voice_of(self), line)
	GameLog.log_general("[color=#cccc88]%s says%s, \"%s\"[/color]" % [npc_name, spoken[0], NPCConversation.format(spoken[1])])


# ── Conversation (npc_conversation.gd) ──
func speak(line: String) -> void:
	say_local(line)


func face_player() -> void:
	_face_player()


func dynamic_lines(name: String) -> Array:
	var pool = _lines.get(name, [])
	return pool if typeof(pool) == TYPE_ARRAY else []


func can_answer(player: Node, text: String) -> bool:
	return _conversation != null and _conversation.can_answer(player, text)


# Something the local player said nearby. He only talks while standing still.
func hear_say(player: Node, text: String) -> void:
	if _conversation == null:
		return
	if stage == Stage.ROAD and not _conversation.find_topic(text).is_empty() \
			and global_position.distance_to(player.global_position) <= NPCConversation.TALK_RANGE:
		request_pause()   # talk to him on the road and he stops to answer
	elif not can_trade():
		if not _conversation.find_topic(text).is_empty() and global_position.distance_to(player.global_position) <= NPCConversation.TALK_RANGE:
			say_local(_pick("hail_leaving"))
		return
	_conversation.hear(player, text)


# ── Quest hand-in (EverQuest style: drag items from the bags onto him -> the Give window) ──
func receive_item_drop(item: Dictionary, player: Node) -> void:
	if stage == Stage.ROAD:
		request_pause()
	elif not can_trade():
		_face_player()
		say_local(_pick("hail_leaving"))
		return
	var existing := get_tree().root.get_node_or_null("GiveWindow")
	if existing:
		existing.queue_free()
	var win := GiveWindow.new()
	win.name = "GiveWindow"
	get_tree().root.add_child(win)
	win.setup(self, player)
	if win.has_method("offer_item"):
		win.offer_item(item)


# Called by the Give window: true closes it (finished), false leaves it open.
func try_give(item_id: String, player: Node) -> bool:
	var result := Quests.try_hand_in(get_vendor_display_name(), item_id, player)
	var text: String = str(result.get("text", ""))
	match str(result.get("result", "")):
		"wrong_item":
			GameLog.log_general("[color=%s]%s[/color]" % [EMOTE_COLOR, _pick("wrong_item")])
			return false
		"have_enough":
			GameLog.log_general("[color=%s]Sahren shakes his head. \"I have enough of those, friend.\"[/color]" % EMOTE_COLOR)
			return false
		"complete", "already_done":
			if not text.is_empty():
				GameLog.log_general("[color=%s]%s[/color]" % [EMOTE_COLOR, text])
			return true
		_:
			if not text.is_empty():
				GameLog.log_general("[color=%s]%s[/color]" % [EMOTE_COLOR, text])
			return false


func progress_summary() -> String:
	return Quests.progress_summary(get_vendor_display_name())


# An unprompted line decided on the server that everyone nearby should hear.
func say_to_all(line: String) -> void:
	say_local(line)
	if Net.is_multiplayer_game and multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_rpc_say.rpc(line)


@rpc("authority", "call_remote", "reliable")
func _rpc_say(line: String) -> void:
	say_local(line)


func _face_player() -> void:
	var player: Node3D = TargetFrame.local_player()
	if not is_instance_valid(player) or _travelling:
		return
	var target := player.global_position
	target.y = global_position.y
	if target.distance_to(global_position) > 0.01:
		look_at(target, Vector3.UP)


# ── Who is in charge ──
func _is_puppet() -> bool:
	return Net.is_multiplayer_game and multiplayer.has_multiplayer_peer() and not is_multiplayer_authority()


func _is_server_side() -> bool:
	return not _is_puppet()


# ── Main loop ──
func _physics_process(delta: float) -> void:
	if _is_puppet():
		_show_anim(anim_state)
		return
	_apply_gravity(delta)
	var now := Time.get_ticks_msec()
	match stage:
		Stage.ROAD:
			_walk(delta, now)
		Stage.AT_STOP:
			velocity.x = 0.0
			velocity.z = 0.0
			_tick_stay(now)
		Stage.CHATTING:
			velocity.x = 0.0
			velocity.z = 0.0
			if now >= _chat_until_msec:
				say_to_all(_pick("resume"))
				_begin_leg()   # back on the road to the same stop
		Stage.LEAVING:
			velocity.x = 0.0
			velocity.z = 0.0
			if now >= _leaving_until_msec:
				queue_free()  # the spawner's node replicates the removal to every peer
				return
	move_and_slide()
	anim_state = "walk" if _travelling and Vector2(velocity.x, velocity.z).length() > 0.1 else "idle"
	_show_anim(anim_state)


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0


func _show_anim(clip: String) -> void:
	if clip == _shown_anim or animation_player == null:
		return
	if animation_player.has_animation(clip):
		_shown_anim = clip
		animation_player.play(clip)


# ── The route ──
# Walk to route[route_index] (or the exit once the stops are done).
func _begin_leg() -> void:
	stage = Stage.ROAD
	var stop: Dictionary = route[route_index] if route_index < route.size() else {}
	_dest = stop.get("pos", route_exit) if not stop.is_empty() else route_exit
	_dest.y = floor_y_at(_dest, _dest.y)
	_travelling = true
	_off_mesh = false
	_to_shore = _shore_point != Vector3.INF   # leaving the dock: off its deck first, the navmesh there is an island of its own
	_path = PackedVector3Array()
	_path_i = 0
	_best_dist = INF
	_stall = 0.0
	var expected := _flat(global_position, _dest) / maxf(_walk_speed, 0.5)
	_leg_deadline_msec = Time.get_ticks_msec() + int((expected * TRAVEL_SLACK + 60.0) * 1000.0)


func _walk(delta: float, now: int) -> void:
	var to_dest := _flat(global_position, _dest)
	if to_dest <= ARRIVAL or now >= _leg_deadline_msec:
		if now >= _leg_deadline_msec and to_dest > ARRIVAL:
			push_warning("%s could not reach his stop in time — placing him there." % npc_name)
			global_position = Vector3(_dest.x, _dest.y, _dest.z)
		_arrive()
		return
	if _to_shore:
		if _flat(global_position, _shore_point) < CORNER_ARRIVAL:
			_to_shore = false
			_shore_point = Vector3.INF
			_best_dist = INF
			_path = PackedVector3Array()
		else:
			_walk_straight(_shore_point)
			return
	# Progress watchdog: he must never be able to stand still forever on a scheduled route.
	if to_dest < _best_dist - 0.5:
		_best_dist = to_dest
		_stall = 0.0
	else:
		_stall += delta
		if _stall >= STALL_SECONDS:
			_stall = 0.0
			_path = PackedVector3Array()  # repath from wherever he is now
	if _path.is_empty():
		_recompute_path()
		if _path.is_empty():
			velocity.x = 0.0
			velocity.z = 0.0
			return
	while _path_i < _path.size() - 1 and _flat(global_position, _path[_path_i]) < CORNER_ARRIVAL:
		_path_i += 1
	var next: Vector3 = _path[_path_i]
	if _path_i >= _path.size() - 1 and _flat(global_position, next) < CORNER_ARRIVAL * 2.0 and _flat(next, _dest) > CORNER_ARRIVAL * 2.0:
		_off_mesh = true  # the navmesh ends here but his stop is further on (the dock's deck): walk the rest straight
		_shore_point = global_position
	if _off_mesh:
		_walk_straight(_dest)
		return
	var flat_dir := Vector3(next.x - global_position.x, 0.0, next.z - global_position.z)
	if flat_dir.length() < 0.1:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var dir := _steer(flat_dir.normalized())
	look_at(global_position + dir, Vector3.UP)
	velocity.x = dir.x * _walk_speed
	velocity.z = dir.z * _walk_speed


# The last stretch when the navmesh does not reach the stop: straight at it, hopping onto a ledge that is in the way.
func _walk_straight(target: Vector3) -> void:
	var dir := Vector3(target.x - global_position.x, 0.0, target.z - global_position.z).normalized()
	look_at(global_position + dir, Vector3.UP)
	velocity.x = dir.x * _walk_speed
	velocity.z = dir.z * _walk_speed
	if is_on_floor():
		var space := get_world_3d().direct_space_state
		var knee := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 0.4, 0), global_position + Vector3(0, 0.4, 0) + dir * 1.0)
		knee.exclude = [get_rid()]
		var high := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, HOP_HEIGHT + 0.3, 0), global_position + Vector3(0, HOP_HEIGHT + 0.3, 0) + dir * 1.0)
		high.exclude = [get_rid()]
		if space.intersect_ray(knee) and not space.intersect_ray(high):
			velocity.y = sqrt(2.0 * GRAVITY * HOP_HEIGHT)


func _recompute_path() -> void:
	_path = PackedVector3Array()
	_path_i = 0
	if not is_inside_tree():
		return
	var query := NavigationPathQueryParameters3D.new()
	query.map = get_world_3d().navigation_map
	query.start_position = global_position
	query.target_position = _dest
	var result := NavigationPathQueryResult3D.new()
	NavigationServer3D.query_path(query, result)
	_path = result.path
	if _path.size() > 1:
		_path_i = 1  # path[0] is just where he already is


# A short ray ahead: if something solid is in the way, sidestep to the first clear heading. A walkable slope (a hillside
# rising ahead) is not "in the way" — he walks up it; only a wall-steep surface counts.
func _steer(direction: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var origin := global_position + Vector3(0, 0.9, 0)
	for angle in [0.0, 30.0, -30.0, 60.0, -60.0, 90.0, -90.0]:
		var candidate := direction.rotated(Vector3.UP, deg_to_rad(angle))
		var query := PhysicsRayQueryParameters3D.create(origin, origin + candidate * 1.5)
		query.exclude = [self]
		var hit := space.intersect_ray(query)
		if hit.is_empty() or hit["normal"].y >= WALKABLE_NORMAL_Y:
			return candidate
	return direction


func _arrive() -> void:
	_travelling = false
	velocity.x = 0.0
	velocity.z = 0.0
	_warned = false
	if route_index >= route.size():   # reached the way out of the zone
		stage = Stage.LEAVING
		_leaving_until_msec = Time.get_ticks_msec() + int(LEAVING_SECONDS * 1000.0)
		return
	stage = Stage.AT_STOP
	_leave_at_msec = Time.get_ticks_msec() + int(float(route[route_index].get("stay", 300.0)) * 1000.0)
	_next_hawk_msec = Time.get_ticks_msec() + int(randf_range(HAWK_MIN_SECONDS * 0.3, HAWK_MAX_SECONDS * 0.5) * 1000.0)


func _tick_stay(now: int) -> void:
	if not _warned and now >= _leave_at_msec - int(_warn_before * 1000.0):
		_warned = true
		say_to_all(_pick("warn"))
	if now >= _next_hawk_msec:
		_next_hawk_msec = now + int(randf_range(HAWK_MIN_SECONDS, HAWK_MAX_SECONDS) * 1000.0)
		say_to_all(_ambient_line())
	if now < _leave_at_msec:
		return
	route_index += 1
	if route_index >= route.size():
		say_to_all(_pick("farewell"))   # the last stop: he packs up and walks out of the zone
	_begin_leg()


# Ambient chatter while he trades; at night there is a chance it is one of his secret lines instead.
func _ambient_line() -> String:
	var cycles := get_tree().get_nodes_in_group("day_night_cycle")
	var night: bool = not cycles.is_empty() and cycles[0].has_method("is_day") and not cycles[0].is_day()
	if night and randf() < float(_config.get("ambient_secret_chance_at_night", 0.2)):
		return _pick("secret")
	return _pick("ambient")


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
