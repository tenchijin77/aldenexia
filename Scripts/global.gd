# global.gd (Autoload Singleton)
# Manages global game state, time system, and player data
extends Node

#region Signals
signal chat_state_changed(is_active)
signal time_changed(current_time: Dictionary)
signal day_changed(new_day: int)
signal month_changed(new_month: String)
signal currency_changed
#endregion

#region SFX (one-shot, non-positional — UI/feedback sounds, not 3D-positioned combat SFX)
const COIN_SOUND: AudioStream = preload("res://Assets/sounds/ui/coins.mp3")

# Spawns a short-lived AudioStreamPlayer on the "SFX" bus (respects the
# Options menu's SFX volume slider) and frees itself when done — a fresh
# player per call rather than one shared/reused player, so looting several
# coin drops in quick succession layers the sound instead of each new play
# cutting the previous one off.
func play_sfx(stream: AudioStream, volume_db: float = 0.0) -> void:
	if not stream:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = "SFX"
	player.volume_db = volume_db
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)

func play_coin_sound() -> void:
	Sfx.play("coins")  # balanced volume (Data/sounds.json)


# Investigated 2026-09-14: reported "title music takes 5-10s to start on the
# loading screen, seems to have started after we added the audio buses."
# Traced the actual GDScript path — Global._ready() -> GlobalBackgroundMusic
# autoplay/_check_and_play_music() -> main_menu._ready() — and it resolves
# in ~1.4s from process launch in testing, nowhere near 5-10s, and
# default_bus_layout.tres has zero effects on any bus (just Master/Music/SFX
# routing), so the bus graph itself isn't doing anything slow either. The
# far more likely cause: PulseAudio/PipeWire (and some Windows/macOS audio
# backends similarly) auto-suspend an idle output device after a few
# seconds of silence, then take a noticeable moment to wake it back up the
# next time something actually plays — and the very first sound this game
# ever plays is the title music itself, right as the loading screen appears,
# so that wake-up latency shows up as exactly this "music takes a few
# seconds to start" symptom. It likely only coincides with the bus work
# timing-wise rather than being caused by it.
# This can't be fixed from inside the audio graph, but it CAN be hidden: a
# near-silent one-shot played here, as early as possible (Global is the
# first autoload), forces the OS audio device to wake up during the
# engine's own boot/window-creation time — which is already happening
# regardless — instead of at the moment the title music tries to play,
# so any such wake-up delay is absorbed before the player ever notices it.
func _warm_up_audio() -> void:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 44100
	var silence := PackedByteArray()
	silence.resize(256)  # a few ms of silence — just enough to open the device
	stream.data = silence
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = -80.0
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)
#endregion

#region Chat System
var is_chat_active = false:
	set(value):
		is_chat_active = value
		emit_signal("chat_state_changed", is_chat_active)
#endregion

#region Mouse mode
# Single source of truth for whether mouselook (F12, camera_controller.gd) is
# toggled on. UI windows (backpack, character sheet, pause menu, loot window)
# always force the mouse visible while they're open, then call
# restore_mouse_mode() on close instead of hardcoding a mode — that way
# closing a window resumes mouselook if it was on, instead of silently
# cancelling it (or, worse, capturing/hiding the mouse when it wasn't).
var mouselook_enabled: bool = false

func restore_mouse_mode() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if mouselook_enabled else Input.MOUSE_MODE_VISIBLE)
#endregion

#region Settings (system-wide — NOT part of player_data, so they survive
# independently of which character is loaded/saved, and are available even
# from the main menu before any character is loaded)
const SETTINGS_PATH := "user://settings.json"
# The zone new and loaded characters start in (character creation, load game, joining a server). Since 2026-09-22 this is the
# Terrain3D rebuild of Lumora Outskirts; the old flat zone is archived as Scenes/lumora_outskirts3d_flat.tscn. The file name
# matters: Data/compass.json and the zone announcement (world_announcer.gd) key off it.
const START_ZONE_PATH := "res://Scenes/lumora_outskirts3d.tscn"

var settings: Dictionary = {
	"music_volume": 1.0,   # linear 0..1, applied to the "Music" audio bus
	"sfx_volume": 1.0,     # linear 0..1, applied to the "SFX" audio bus
	"invert_look_y": false,  # flips vertical mouse input for both mouselook and head-turn (camera_controller.gd)
	"show_name_tags": true,  # floating Label3D above the player's and pet's heads (player3d.gd, pet_minion.gd)
	"ui_bg_alpha": 0.92,   # 0..1, shared alpha for every HUD window's background — see window_bg_style()
}

# Single shared StyleBoxFlat used for every HUD window's outer panel
# background (character sheet, backpack, target/player/pet frames, tracking
# window, cast bar, group frame, pause menu, etc.) instead of each script
# building its own near-identical-but-not-quite copy. Every window calls
# window_bg_style() once in _ready() and gets back THE SAME resource
# instance, so adjusting ui_bg_alpha (the Options-panel transparency slider)
# updates every open window live with no signals/listeners needed — mutating
# a shared Resource's property is visible to every Control referencing it.
var _window_bg_style: StyleBoxFlat = null

func window_bg_style() -> StyleBoxFlat:
	if _window_bg_style == null:
		_window_bg_style = StyleBoxFlat.new()
		_window_bg_style.bg_color = Color(0.08, 0.07, 0.06, settings.get("ui_bg_alpha", 0.92))
		_window_bg_style.border_color = Color(0.45, 0.38, 0.25)
		_window_bg_style.set_border_width_all(2)
		_window_bg_style.set_corner_radius_all(5)
	return _window_bg_style

# Same look as window_bg_style() but (nearly) opaque — for modal screens drawn over the main menu, where
# a translucent panel lets the menu buttons behind it show through the text.
func opaque_window_bg_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = window_bg_style().duplicate()
	style.bg_color.a = 0.98
	return style

func set_ui_bg_alpha(alpha: float) -> void:
	settings["ui_bg_alpha"] = alpha
	window_bg_style().bg_color.a = alpha

func load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if not file:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) == TYPE_DICTIONARY:
		for key in parsed:
			settings[key] = parsed[key]


func save_settings() -> void:
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(settings, "\t"))
		file.close()


func apply_audio_settings() -> void:
	var music_bus := AudioServer.get_bus_index("Music")
	if music_bus >= 0:
		AudioServer.set_bus_volume_db(music_bus, linear_to_db(settings.get("music_volume", 1.0)))
	var sfx_bus := AudioServer.get_bus_index("SFX")
	if sfx_bus >= 0:
		AudioServer.set_bus_volume_db(sfx_bus, linear_to_db(settings.get("sfx_volume", 1.0)))
#endregion

#region Character Data
var current_character_data: Dictionary = {}
var current_character_name: String = ""
var character_options: Dictionary = {}
var player_data: Dictionary = {}  # Active player data (matches current_character_data)

# Set by multiplayer_menu.gd's "Create New Character" button before sending
# the player to character_creation.tscn — the multiplayer menu is an overlay
# added as a child of main_menu.tscn (see main_menu.gd::_on_multiplayer_pressed),
# not its own scene, so change_scene_to_file() to character creation destroys
# it; this flag tells main_menu.gd to reopen it (with a freshly repopulated
# character dropdown) once the player lands back on the main menu, and tells
# character_creation.gd's Back/Begin buttons to return there instead of
# launching straight into a single-player game.
var return_to_multiplayer_menu: bool = false
## Same idea for the Join a Server screen (join_server_menu.gd): set when a server join fails or drops, or
## when its "Create New Character" shortcut sends the player to character creation and back.
var return_to_join_server_menu: bool = false
## Set by the Join a Server screen while character_creation.tscn is creating a character ON A SERVER:
## {"address", "port", "password"}. Empty in every other flow. Creation then hands the new character to
## Net.begin_join_server() instead of writing user://saves.
var server_creation: Dictionary = {}
#endregion

#region XP System
var xp_table: Dictionary = {}
var max_player_level: int = 20
#endregion

#region Calendar Constants
const MONTHS = [
	"Luminar", "Verdalis", "Pyrosol", "Zepheral", "Aquenox",
	"Obscurion", "Solsticea", "Thornmere", "Glacivorne", "Starvane"
]

const DAYS_OF_WEEK = [
	"Mornis", "Ferros", "Eldra", "Solyn", "Umbra", "Nexar"
]

const DAYS_PER_MONTH = 36
const DAYS_PER_YEAR = 360
const MONTHS_PER_YEAR = 10
const DAYS_PER_WEEK = 6

# Standard 24-hour day: day is 6:00-21:00 (14h core daylight + the last hour
# ramps into dusk), night is 21:00-6:00 (9h). At exactly 1 real second = 1
# game minute that's 15 real minutes of day (incl. dusk) and 9 of night —
# close to the original 15/10 target without an unconventional day length.
# day_night_cycle.gd's dawn_dusk_fraction handles the dawn/dusk visual blend
# inside the last/first ~1 in-game hour of the day phase.
const HOURS_PER_DAY = 24
const DAY_START_HOUR = 6   # sunrise
const DAY_END_HOUR = 21    # sunset (dusk blend runs ~20:00-21:00)

# Time conversion: 1 real second = 1 game minute
const REAL_SECONDS_PER_GAME_MINUTE = 1.0
const REAL_SECONDS_PER_GAME_HOUR = 60.0
const REAL_SECONDS_PER_GAME_DAY = HOURS_PER_DAY * REAL_SECONDS_PER_GAME_HOUR

const START_YEAR = 300
const START_MONTH = 0
const START_DAY = 6
const START_HOUR = 12
const START_MINUTE = 0
#endregion

#region Game Time
var game_time: Dictionary = {
	"year": START_YEAR,
	"month": START_MONTH,
	"day": START_DAY,
	"hour": START_HOUR,
	"minute": START_MINUTE,
	"day_of_week": 0
}

var time_accumulator: float = 0.0
const TIME_SYNC_INTERVAL := 10.0  # real seconds between the server's clock pushes in multiplayer
var _time_sync_elapsed := 0.0
var time_running: bool = true
var session_start_time: int = 0
var total_playtime_seconds: int = 0
#endregion

func _ready():
	Sfx.install(get_tree())  # every Button clicks (sfx.gd)
	_ensure_input_actions()
	_warm_up_audio()
	load_xp_table()
	load_character_options()
	initialize_time_system()
	start_playtime_tracking()
	load_settings()
	apply_audio_settings()

# Saves are otherwise event-driven (a kill, an item moved...), so nothing banked the play time or your position if a
# session ended any other way — a dropped connection, closing the window, a crash. /played then only ever showed the
# current session. While a character is in the world it is now saved once a minute, and when the window is closed.
const AUTOSAVE_INTERVAL := 60.0
var _autosave_elapsed := 0.0


func _process(delta: float):
	_autosave_elapsed += delta
	if _autosave_elapsed >= AUTOSAVE_INTERVAL:
		_autosave_elapsed = 0.0
		if not player_data.is_empty() and is_instance_valid(TargetFrame.local_player()):
			save_player_data_to_file()
	if not time_running:
		return
	time_accumulator += delta
	if time_accumulator >= REAL_SECONDS_PER_GAME_MINUTE:
		time_accumulator -= REAL_SECONDS_PER_GAME_MINUTE
		advance_game_time(1)
	# In a multiplayer game the host/server is the world clock — every peer keeps
	# ticking locally between pushes, so this only nudges away accumulated drift.
	if Net.is_multiplayer_game and multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_time_sync_elapsed += delta
		if _time_sync_elapsed >= TIME_SYNC_INTERVAL:
			_time_sync_elapsed = 0.0
			for pid in multiplayer.get_peers():
				send_time_to(pid)


# Server -> one peer (a joiner right after the version check, or the periodic push).
# Without this each machine started its own clock at 12:00, so a joiner could see
# night while the host saw day, and the two drifted apart from then on.
# A dedicated server keeps the world clock across restarts (user://server_state_<name>.json). Saved every
# few minutes and on graceful shutdown by net.gd; loaded at start-up so the sun doesn't jump back to noon.
func save_world_state(server_name: String) -> void:
	var file := FileAccess.open("user://server_state_%s.json" % server_name, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"game_time": game_time, "time_accumulator": time_accumulator}, "\t"))
		file.close()


func load_world_state(server_name: String) -> void:
	var path := "user://server_state_%s.json" % server_name
	if not FileAccess.file_exists(path):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY or typeof(data.get("game_time")) != TYPE_DICTIONARY:
		return
	for key in game_time.keys():
		if data["game_time"].has(key):
			game_time[key] = int(data["game_time"][key])
	time_accumulator = float(data.get("time_accumulator", 0.0))
	initialize_time_system()
	Net._slog("Restored the world clock: day %d, %02d:%02d." % [game_time.day, game_time.hour, game_time.minute])


func _notification(what: int) -> void:
	# Closing the game window: bank the play time and position. (For a server character Net.disconnect_game() then
	# flushes the upload; whichever of the two runs first, the other still does the right thing.)
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not player_data.is_empty() and is_instance_valid(TargetFrame.local_player()):
		save_player_data_to_file()


func send_time_to(peer_id: int) -> void:
	_rpc_sync_game_time.rpc_id(peer_id, game_time.duplicate(), time_accumulator)


@rpc("authority", "call_remote", "reliable")
func _rpc_sync_game_time(server_time: Dictionary, server_accumulator: float) -> void:
	game_time = server_time
	time_accumulator = server_accumulator
	emit_signal("time_changed", game_time.duplicate())

func load_xp_table():
	var file = FileAccess.open("res://Data/xp_table.json", FileAccess.READ)
	if file:
		var data = JSON.parse_string(file.get_as_text())
		file.close()
		if typeof(data) == TYPE_DICTIONARY:
			xp_table = data
			max_player_level = xp_table.get("max_level", 20)
			
func load_character_options():
	var path = "res://Data/character_options.json"
	if not FileAccess.file_exists(path):
		push_error("❌ character_options.json not found at: " + path)
		return

	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("❌ Failed to open character_options.json")
		return

	var parsed = JSON.parse_string(file.get_as_text())
	file.close()

	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("❌ Failed to parse character_options.json")
		return

	character_options = parsed


func initialize_time_system():
	var total_days = (game_time.month * DAYS_PER_MONTH) + game_time.day - 1
	game_time.day_of_week = total_days % DAYS_PER_WEEK

# Called when the local character actually enters the world (player3d.gd), so menu and
# loading time isn't counted — /played measures time spent in game.
func start_playtime_tracking():
	session_start_time = Time.get_ticks_msec()

func advance_game_time(minutes: int = 1):
	game_time.minute += minutes
	while game_time.minute >= 60:
		game_time.minute -= 60
		game_time.hour += 1
	while game_time.hour >= HOURS_PER_DAY:
		game_time.hour -= HOURS_PER_DAY
		game_time.day += 1
		game_time.day_of_week = (game_time.day_of_week + 1) % DAYS_PER_WEEK
	while game_time.day > DAYS_PER_MONTH:
		game_time.day -= DAYS_PER_MONTH
		game_time.month += 1
	while game_time.month >= MONTHS_PER_YEAR:
		game_time.month -= MONTHS_PER_YEAR
		game_time.year += 1
	emit_signal("time_changed", game_time.duplicate())

func format_time_24h() -> String:
	return "%02d:%02d" % [game_time.hour, game_time.minute]

func format_short_date() -> String:
	return "%s, %s %d" % [DAYS_OF_WEEK[game_time.day_of_week], MONTHS[game_time.month], game_time.day]

func format_full_date() -> String:
	return "Day %d, %s, %s %d - %s" % [game_time.day, DAYS_OF_WEEK[game_time.day_of_week], MONTHS[game_time.month], game_time.year, format_time_24h()]

# In-world birth date and clock time, e.g. "Day 6, Nexar, Luminar 300 at 12:19" — "Unknown" for a
# character created before creation timestamps existed.
func format_birthday_ingame(creation_data: Dictionary) -> String:
	if not creation_data.has("game_time"):
		return "Unknown"
	var gt: Dictionary = creation_data.game_time
	# JSON hands numbers back as floats, and arrays can't be indexed by a float — cast first.
	var dow: int = clampi(int(gt.get("day_of_week", 0)), 0, DAYS_OF_WEEK.size() - 1)
	var month: int = clampi(int(gt.get("month", 0)), 0, MONTHS.size() - 1)
	return "Day %d, %s, %s %d at %02d:%02d" % [int(gt.get("day", 1)), DAYS_OF_WEEK[dow], MONTHS[month],
			int(gt.get("year", START_YEAR)), int(gt.get("hour", 0)), int(gt.get("minute", 0))]


# Real-world creation date and time, e.g. "08/25/2026 at 6:30 PM" (12-hour, like /time's real clock).
func format_birthday_real(creation_data: Dictionary) -> String:
	var real_time: String = str(creation_data.get("real_time", ""))
	var parts := real_time.split("T")
	if parts.size() < 2:
		return "Unknown"
	var date_part := parts[0].split("-")
	var time_part := parts[1].split(":")
	if date_part.size() < 3 or time_part.size() < 2:
		return "Unknown"
	var hour24: int = int(time_part[0])
	var hour12: int = hour24 % 12
	if hour12 == 0:
		hour12 = 12
	return "%s/%s/%s at %d:%s %s" % [date_part[1], date_part[2], date_part[0], hour12, time_part[1], "AM" if hour24 < 12 else "PM"]


func format_birthday(creation_data: Dictionary) -> String:
	if not creation_data.has("game_time"):
		return "Unknown"
	return "%s (%s)" % [format_birthday_ingame(creation_data), format_birthday_real(creation_data)]


# "3 days ago" / "today" for a character's real-world creation time (both clocks read as local time).
func format_real_age(creation_data: Dictionary) -> String:
	var real_time: String = str(creation_data.get("real_time", ""))
	if real_time.is_empty():
		return ""
	var created: int = int(Time.get_unix_time_from_datetime_string(real_time))
	var now_local: int = int(Time.get_unix_time_from_datetime_dict(Time.get_datetime_dict_from_system(false)))
	var days: int = maxi(0, now_local - created) / 86400
	if days <= 0:
		return "today"
	return "1 day ago" if days == 1 else "%d days ago" % days


func format_playtime(seconds: int) -> String:
	var days: int = seconds / 86400
	var hours: int = (seconds % 86400) / 3600
	var minutes: int = (seconds % 3600) / 60
	if days > 0:
		return "%dd %dh %dm" % [days, hours, minutes]
	if hours > 0:
		return "%dh %dm" % [hours, minutes]
	if minutes > 0:
		return "%dm" % minutes
	return "less than a minute"


# Total for this character: everything banked in the save plus the current session.
func get_total_playtime() -> int:
	return total_playtime_seconds + get_session_playtime()


func get_session_playtime() -> int:
	return int((Time.get_ticks_msec() - session_start_time) / 1000)

func is_daytime() -> bool:
	return game_time.hour >= DAY_START_HOUR and game_time.hour < DAY_END_HOUR

func create_character_creation_timestamp() -> Dictionary:
	return {
		"real_time": Time.get_datetime_string_from_system(),
		"game_time": game_time.duplicate()
	}

func grant_currency(field: String, amount: int) -> void:
	player_data[field] = player_data.get(field, 0) + amount
	currency_changed.emit()

# ── Denomination-aware currency helpers (vendor buy/sell) ──────────────────
# Currency is stored as 4 independent counters (copper/silver/gold/platinum).
# These treat that as one pool of copper-equivalent wealth — spending/adding
# collapses to a single total and re-mints it back into denominations greedily
# from platinum down, rather than requiring exact change in a specific coin.
const COPPER_PER_SILVER := 10
const COPPER_PER_GOLD := 100
const COPPER_PER_PLATINUM := 1000

func get_total_copper() -> int:
	return player_data.get("copper", 0) \
		+ player_data.get("silver", 0) * COPPER_PER_SILVER \
		+ player_data.get("gold", 0) * COPPER_PER_GOLD \
		+ player_data.get("platinum", 0) * COPPER_PER_PLATINUM

func _set_total_copper(total: int) -> void:
	total = maxi(total, 0)
	player_data["platinum"] = total / COPPER_PER_PLATINUM
	total %= COPPER_PER_PLATINUM
	player_data["gold"] = total / COPPER_PER_GOLD
	total %= COPPER_PER_GOLD
	player_data["silver"] = total / COPPER_PER_SILVER
	total %= COPPER_PER_SILVER
	player_data["copper"] = total
	currency_changed.emit()

func can_afford(copper_cost: int) -> bool:
	return get_total_copper() >= copper_cost

func spend_currency_copper(copper_cost: int) -> bool:
	var total := get_total_copper()
	if total < copper_cost:
		return false
	_set_total_copper(total - copper_cost)
	save_player_data_to_file()
	return true

func add_currency_copper(copper_amount: int) -> void:
	_set_total_copper(get_total_copper() + copper_amount)
	save_player_data_to_file()

# An item's "value" is denominated in whatever "currency_type" it declares
# (almost always copper; a handful of higher-tier trophy items are authored
# in silver to keep their value numbers small/readable) — this normalizes
# either to a flat copper amount for pricing.
func item_value_in_copper(item_def: Dictionary) -> int:
	var value: int = item_def.get("value", 0)
	match item_def.get("currency_type", "copper"):
		"silver":   return value * COPPER_PER_SILVER
		"gold":     return value * COPPER_PER_GOLD
		"platinum": return value * COPPER_PER_PLATINUM
		_:          return value

# ── Loot preferences (advanced-loot style "always loot/ignore/sell this item") ──
# Keyed by item_id, one of "loot" / "ignore" / "sell", or unset for "always ask"
# (i.e. show it in the loot window). Set from corpse_loot_window.gd's checkboxes,
# read back in monster3d.gd's die() to auto-resolve future drops of that item.
func get_loot_preference(item_id: String) -> String:
	return player_data.get("loot_preferences", {}).get(item_id, "")

func set_loot_preference(item_id: String, preference: String) -> void:
	var prefs: Dictionary = player_data.get("loot_preferences", {})
	prefs[item_id] = preference
	player_data["loot_preferences"] = prefs
	save_player_data_to_file()

func set_player_data(data: Dictionary):
	player_data = data
	current_character_data = data
	current_character_name = data.get("player_name", "Unknown")
	total_playtime_seconds = int(data.get("playtime_seconds", 0))
	session_start_time = Time.get_ticks_msec()

# The name a saved character is shown with (the player_name inside the file, as typed at creation), for
# confirmation prompts. `stem` is the lowercase file stem, e.g. "zozuur".
func local_character_display_name(stem: String) -> String:
	var path := "user://saves/%s_character_stats.json" % stem
	if FileAccess.file_exists(path):
		var data = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(data) == TYPE_DICTIONARY and str(data.get("player_name", "")) != "":
			return str(data["player_name"])
	return stem.capitalize()


# Permanently removes a local character's save. The UI (delete_character_dialog.gd) makes the player
# type the name first; nothing else keeps per-character files, so this is all a delete needs.
func delete_local_character(stem: String) -> bool:
	var path := "user://saves/%s_character_stats.json" % stem
	if not FileAccess.file_exists(path):
		return false
	if current_character_name.to_lower() == stem:
		clear_current_character_data()
	return DirAccess.remove_absolute(path) == OK


func clear_current_character_data():
	current_character_data = {}
	player_data = {}
	current_character_name = ""

	# Loads a character save file from user://saves/
func load_player_data_from_file(character_name: String) -> Dictionary:
	var file_path = "user://saves/%s_character_stats.json" % character_name.to_lower()

	if not FileAccess.file_exists(file_path):
		push_error("❌ Save file not found: " + file_path)
		return {}

	var file := FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("❌ Could not open save file: " + file_path)
		return {}

	var parsed = JSON.parse_string(file.get_as_text())
	file.close()

	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("❌ Failed to parse JSON in: " + file_path)
		return {}
	set_player_data(parsed)
	return parsed


func save_player_data_to_file() -> void:
	if player_data.is_empty() or current_character_name.is_empty():
		return
	# A character that lives on a dedicated server is uploaded there (batched, see Net) instead.
	if Net.remote_character_mode:
		Net.request_remote_save()
		return
	var file_path := "user://saves/%s_character_stats.json" % current_character_name.to_lower()
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		file.store_string(serialize_player_data())
		file.close()
	else:
		push_error("❌ Failed to write save: " + file_path)


# The character as save-file JSON, with the live fields brought up to date first. Both the
# local save above and Net's server upload write exactly this.
func serialize_player_data() -> String:
	if player_data.is_empty():
		return ""
	# Every save call site (many, across player3d.gd and pause_menu.gd) goes
	# through here, so capturing the live position right before writing —
	# rather than patching each call site — guarantees it's always current
	# and lets the player log back in exactly where they logged out. Distinct
	# from "bind_point" (player3d.gd), which is the death-respawn location and
	# only ever set once on first spawn.
	var p: Node3D = TargetFrame.local_player()
	if is_instance_valid(p):
		player_data["last_position"] = [p.global_position.x, p.global_position.y, p.global_position.z]
		player_data["last_zone"] = WorldAnnouncer.zone_display_name()  # shown on the server's character list
	# Bank the running total into the save. Before this the total only reached the character
	# sheet's display, so every save kept "playtime_seconds": 0 no matter how long you played.
	player_data["playtime_seconds"] = get_total_playtime()
	return JSON.stringify(player_data, "\t")


# Key bindings added after the base build. The input map lives in project.godot, which an update PATCH can't change (see
# patch_loader.gd), so a key added to project.godot later only exists in the editor and in fresh full builds — J and L did
# nothing for patched players (test 19). Adding them here at startup makes them work everywhere; an action already in the
# input map (a full build, or the player's own rebinding) is left alone.
const GROUND_PROBE_RADIUS := 0.05
const RUNTIME_ACTIONS := {
	"toggle_quest_journal": KEY_J,
	"toggle_recipe_book": KEY_L,
	"loot_all": KEY_G,   # loot every corpse within 10 m (player3d.gd loot_all_nearby())
}

func _ensure_input_actions() -> void:
	for action in RUNTIME_ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var key := InputEventKey.new()
		key.physical_keycode = RUNTIME_ACTIONS[action]
		InputMap.action_add_event(action, key)


# intersect_ray() for rays dropped straight down (or up) onto the ground. Godot's built-in physics can miss a
# HeightMapShape — every Terrain3D region is one — with a perfectly vertical ray, so a straight-down ray over the
# terrain sometimes reports nothing even though the ground is there (bodies still stand on it fine). When the ray finds
# nothing, a tiny sphere is swept along the same line instead, which never misses; the result has the same keys the
# callers use ("position", "normal", "collider", "rid"). Used by everything that looks for the ground under a point.
func ground_ray(space: PhysicsDirectSpaceState3D, query: PhysicsRayQueryParameters3D) -> Dictionary:
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		return hit
	var sphere := SphereShape3D.new()
	sphere.radius = GROUND_PROBE_RADIUS
	var sweep := PhysicsShapeQueryParameters3D.new()
	sweep.shape = sphere
	sweep.transform = Transform3D(Basis(), query.from)
	sweep.motion = query.to - query.from
	sweep.collision_mask = query.collision_mask
	sweep.exclude = query.exclude
	sweep.collide_with_areas = query.collide_with_areas
	sweep.collide_with_bodies = query.collide_with_bodies
	var fractions := space.cast_motion(sweep)
	if fractions.size() < 2 or fractions[1] >= 1.0:
		return {}
	sweep.transform.origin = query.from + sweep.motion * fractions[1]
	var rest := space.get_rest_info(sweep)
	if rest.is_empty():
		return {}
	return {"position": rest["point"], "normal": rest["normal"], "collider": instance_from_id(rest["collider_id"]),
		"collider_id": rest["collider_id"], "rid": rest["rid"], "shape": rest["shape"]}
