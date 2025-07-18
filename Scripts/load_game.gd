# load_game.gd
extends Control

@onready var character_list: ItemList = $VBoxContainer/character_list
@onready var load_button: Button = $VBoxContainer/load_button

func _ready():
	print("DEBUG: Load game menu opened") # Confirm menu is active
	load_save_files()

# Loads available save files into the list
func load_save_files():
	character_list.clear()
	
	# Globalize the user://saves/ path to ensure it handles spaces and special characters correctly
	var save_dir_path = ProjectSettings.globalize_path("user://saves/")
	print("DEBUG: Attempting to open directory: ", save_dir_path) # Confirms resolved path

	var dir = DirAccess.open(save_dir_path)

	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		var found_any_saves = false
		while file_name != "":
			# --- CRUCIAL DEBUG LINE TO SEE WHAT FILES ARE FOUND ---
			print("DEBUG: Found file in save directory: ", file_name) 
			# -----------------------------------------------------

			# Ignore system files like "." and ".."
			if file_name == "." or file_name == "..":
				file_name = dir.get_next()
				continue

			if file_name.ends_with("_character_stats.json"):
				found_any_saves = true
				# Capitalize for display, but use original (lowercase) for path construction
				var display_name = file_name.replace("_character_stats.json", "").capitalize()
				character_list.add_item(display_name)
				print("DEBUG: Added character to list: ", display_name) # Confirm character added
			file_name = dir.get_next()
		dir.list_dir_end()
		
		if not found_any_saves:
			print("DEBUG: No character save files found matching '_character_stats.json' in: ", save_dir_path)
			load_button.disabled = true
		else:
			load_button.disabled = false # Enable if saves are found
	else:
		push_error("❌ Failed to open save directory: %s. Check permissions or path." % save_dir_path)
		load_button.disabled = true # Disable button if directory can't be opened

# Called when Load button is pressed
func _on_load_button_pressed():
	var selected_items = character_list.get_selected_items()
	if selected_items.size() > 0:
		var selected_character_name_raw = character_list.get_item_text(selected_items[0]).to_lower()
		var file_name = "%s_character_stats.json" % selected_character_name_raw
		
		# Globalize the file path when opening the specific save file
		var file_path = ProjectSettings.globalize_path("user://saves/" + file_name)
		print("DEBUG: Attempting to load character from file: ", file_path)

		if FileAccess.file_exists(file_path):
			var file = FileAccess.open(file_path, FileAccess.READ)
			if file:
				var file_content = file.get_as_text()
				file.close()
				var character_data = JSON.parse_string(file_content)

				if typeof(character_data) == TYPE_DICTIONARY:
					# Store the parsed character data in the global singleton
					Global.current_character_data = character_data
					
					# Change scene to the game world
					get_tree().change_scene_to_file("res://Scenes/lumora_outskirts.tscn")
					print("✅ Character '%s' data stored in Global. Scene changing to Lumora Outskirts." % selected_character_name_raw)
				else:
					push_error("❌ Failed to parse character data from JSON for: %s. Data is not a dictionary. Content: %s" % [selected_character_name_raw, file_content.left(100) + "..."])
			else:
				push_error("❌ Failed to open file for reading: %s" % file_path)
		else:
			push_error("❌ Save file not found: %s" % file_path)
	else:
		print("DEBUG: No character selected for loading.")
