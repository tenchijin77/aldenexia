# global.gd (Autoload Singleton)
# Manages global game state, time system, and player data
extends Node

#region Signals
signal chat_state_changed(is_active)
signal time_changed(current_time: Dictionary)
signal day_changed(new_day: int)
signal month_changed(new_month: String)
#endregion

#region Chat System
var is_chat_active = false:
	set(value):
		is_chat_active = value
		emit_signal("chat_state_changed", is_chat_active)
#endregion

#region Character Data
var current_character_data: Dictionary = {}
var current_character_name: String = ""
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

# Time conversion (2x hybrid speed)
const REAL_SECONDS_PER_GAME_MINUTE = 30.0
const REAL_SECONDS_PER_GAME_HOUR = 1800.0
const REAL_SECONDS_PER_GAME_DAY = 43200.0

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
	load_xp_table()
	initialize_time_system()
	start_playtime_tracking()

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
	while game_time.hour >= 24:
		game_time.hour -= 24
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
	return game_time.hour >= 6 and game_time.hour < 18

func create_character_creation_timestamp() -> Dictionary:
	return {
		"real_time": Time.get_datetime_string_from_system(),
		"game_time": game_time.duplicate()
	}

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
