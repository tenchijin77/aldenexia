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
const COIN_SOUND: AudioStream = preload("res://Assets/yodguard-coin-collect-3-540190.mp3")

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
	play_sfx(COIN_SOUND)


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

var settings: Dictionary = {
	"music_volume": 1.0,   # linear 0..1, applied to the "Music" audio bus
	"sfx_volume": 1.0,     # linear 0..1, applied to the "SFX" audio bus
	"invert_look_y": false,  # flips vertical mouse input for both mouselook and head-turn (camera_controller.gd)
	"show_name_tags": true,  # floating Label3D above the player's and pet's heads (player3d.gd, pet_minion.gd)
}

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
var time_running: bool = true
var session_start_time: int = 0
var total_playtime_seconds: int = 0
#endregion

func _ready():
	_warm_up_audio()
	load_xp_table()
	load_character_options()
	initialize_time_system()
	start_playtime_tracking()
	load_settings()
	apply_audio_settings()

func _process(delta: float):
	if not time_running:
		return
	time_accumulator += delta
	if time_accumulator >= REAL_SECONDS_PER_GAME_MINUTE:
		time_accumulator -= REAL_SECONDS_PER_GAME_MINUTE
		advance_game_time(1)

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

func format_birthday(creation_data: Dictionary) -> String:
	if not creation_data.has("game_time"):
		return "Unknown"
	var gt = creation_data.game_time
	var real_time = creation_data.get("real_time", "")
	var formatted_real = "Unknown"
	if real_time.length() > 0:
		var parts = real_time.split("T")
		if parts.size() >= 2:
			var date_part = parts[0].split("-")
			var time_part = parts[1].split(":")
			if date_part.size() >= 3 and time_part.size() >= 2:
				formatted_real = "%s/%s/%s at %s:%s" % [date_part[1], date_part[2], date_part[0], time_part[0], time_part[1]]
	return "Day %d, %s, %s %d (%s)" % [gt.get("day", 1), DAYS_OF_WEEK[gt.get("day_of_week", 0)], MONTHS[gt.get("month", 0)], gt.get("year", START_YEAR), formatted_real]

func format_playtime(seconds: int) -> String:
	var hours = seconds / 3600
	var minutes = (seconds % 3600) / 60
	return "%dh %dm" % [hours, minutes] if hours > 0 else "%dm" % minutes

func get_total_playtime() -> int:
	var current = Time.get_ticks_msec()
	var session = (current - session_start_time) / 1000
	return total_playtime_seconds + int(session)

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
	total_playtime_seconds = data.get("playtime_seconds", 0)
	session_start_time = Time.get_ticks_msec()

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
	# Every save call site (many, across player3d.gd and pause_menu.gd) goes
	# through here, so capturing the live position right before writing —
	# rather than patching each call site — guarantees it's always current
	# and lets the player log back in exactly where they logged out. Distinct
	# from "bind_point" (player3d.gd), which is the death-respawn location and
	# only ever set once on first spawn.
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		var p: Node3D = players[0]
		player_data["last_position"] = [p.global_position.x, p.global_position.y, p.global_position.z]
	var file_path := "user://saves/%s_character_stats.json" % current_character_name.to_lower()
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(player_data, "\t"))
		file.close()
	else:
		push_error("❌ Failed to write save: " + file_path)
