# global.gd (Autoload Singleton)
extends Node

signal chat_state_changed(is_active)

var is_chat_active = false:
	set(value):
		is_chat_active = value
		emit_signal("chat_state_changed", is_chat_active)
		
# CRITICAL FIX: Ensure current_character_data is explicitly typed as a Dictionary
var current_character_data: Dictionary = {} 
var current_character_name: String = ""
var xp_table: Dictionary = {}
var max_player_level: int = 0



# Optional: Add a helper function to clear data after use
func clear_current_character_data():
	current_character_data = {}
	
func _ready():
	load_xp_table()
	print("DEBUG: Global script ready. XP table loaded.")

func load_xp_table():
	var file: FileAccess = FileAccess.open("res://Data/xp_table.json", FileAccess.READ)
	if file:
		var content: String = file.get_as_text()
		var data: Variant = JSON.parse_string(content)
		file.close()

		if typeof(data) == TYPE_DICTIONARY:
			xp_table = data
			max_player_level = xp_table.get("max_level", 20) # Default to 20 if not specified
			print("✅ Global: XP table loaded successfully.")
		else:
			push_error("❌ Global: Failed to parse xp_table.json or content is not a Dictionary.")
	else:
		push_error("❌ Global: Failed to open xp_table.json at res://Data/.")
