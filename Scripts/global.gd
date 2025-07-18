# global.gd
extends Node

signal chat_state_changed(is_active)

var is_chat_active = false:
	set(value):
		is_chat_active = value
		emit_signal("chat_state_changed", is_chat_active)
		
# CRITICAL FIX: Ensure current_character_data is explicitly typed as a Dictionary
var current_character_data: Dictionary = {} 
var current_character_name: String = ""

# Optional: Add a helper function to clear data after use
func clear_current_character_data():
	current_character_data = {}
