# lumora_outskirts.gd
extends Node2D

var character_sheet
# Removed 'player_name' variable, as the player node itself will now manage its name.

@onready var player: CharacterBody2D = null

func _ready():
	await get_tree().process_frame # Wait one frame to ensure all nodes are added

	var players = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		push_error("❌ No player node found in 'player' group. Make sure your Player scene is added to this scene and in the 'player' group.")
		return

	player = players.front()

	# --- CRITICAL FIX START ---
	# Now using Global.current_character_data as per your global.gd script
	if Global.current_character_data and typeof(Global.current_character_data) == TYPE_DICTIONARY:
		print("DEBUG: Global.current_character_data found. Passing it to player.load_character_data().")
		player.load_character_data(Global.current_character_data)
	else:
		push_error("❌ Global.current_character_data is missing or invalid. Player might not be initialized correctly.")
		# Fallback if character_data isn't set, e.g., if you run this scene directly
		# You might want to load a default character here or return to main menu
		if Global.current_character_name != "":
			print("Attempting to load missing data from file as fallback...")
			var file_path = "user://saves/" + Global.current_character_name + "_character_stats.json"
			if FileAccess.file_exists(file_path):
				var file = FileAccess.open(file_path, FileAccess.READ)
				if file:
					var data = JSON.parse_string(file.get_as_text())
					file.close()
					player.load_character_data(data)
					print("✅ Fallback data loaded for: ", Global.current_character_name)
				else:
					push_error("❌ Fallback: Failed to open character save file: " + file_path)
			else:
				push_error("❌ Fallback: Save file not found: " + file_path + " for character: " + Global.current_character_name)
		else:
			print("WARNING: No character selected (Global.current_character_name is empty) and Global.current_character_data is missing. Player will use default setup.")

	# --- CRITICAL FIX END ---

	# Instantiate and add character sheet
	# This part is handled by player.gd's toggle_character_sheet function.
	# var character_sheet_instance = preload("res://Scenes/character_sheet.tscn").instantiate()
	# add_child(character_sheet_instance)


	# Show intro bubble
	# Ensure player is valid before accessing its properties
	if is_instance_valid(player):
		show_intro_bubble(player.player_name + " has entered the Lumora Outskirts...")
	else:
		# Fallback if player somehow isn't valid, though the checks above should prevent this
		show_intro_bubble("An adventurer has entered the Lumora Outskirts...")


func show_intro_bubble(text: String):
	# Create background panel
	var panel = Panel.new()
	panel.modulate.a = 0 # Start fully transparent
	panel.size = Vector2(200, 30) # Adjust to fit your text

	# Create the label
	var label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 10)
	label.set("theme_override_colors/font_color", Color.WHITE)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label.anchors_preset = Control.PRESET_FULL_RECT

	panel.add_child(label)

	# Position it above the player
	if is_instance_valid(player): # Added is_instance_valid check
		var offset = Vector2(-panel.size.x / 2, -60) # slightly above the player
		panel.position = player.global_position + offset
	else:
		panel.position = Vector2(200, 80) # fallback if player not found

	add_child(panel)

	# Animate with tween
	var tween = create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 1.0)
	tween.chain().tween_interval(2.0)
	tween.chain().tween_property(panel, "modulate:a", 0.0, 1.0)
	tween.chain().tween_callback(panel.queue_free)
