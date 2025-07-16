# lumora_outskirts.gd
extends Node2D

var character_sheet
var player_name = "Unknown Hero"  # default fallback

@onready var player = get_tree().get_nodes_in_group("player").front()  # adjust if needed

func _ready():
	# Load character stats from file
	var file = FileAccess.open("res://Data/character_stats.json", FileAccess.READ)
	if file:
		var data = JSON.parse_string(file.get_as_text())
		file.close()
		player_name = data.get("player_name", "Unknown Hero")

	# Instantiate and add character sheet
	character_sheet = preload("res://Scenes/character_sheet.tscn").instantiate()
	add_child(character_sheet)

	# Show intro bubble
	show_intro_bubble(player_name + " has entered the Lumora Outskirts...")

func show_intro_bubble(text: String):
	# Create background panel
	var panel = Panel.new()
	panel.modulate.a = 0  # Start fully transparent
	panel.size = Vector2(200, 30)  # Adjust to fit your text

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
	if player:
		var offset = Vector2(-panel.size.x / 2, -60)  # slightly above the player
		panel.position = player.global_position + offset
	else:
		panel.position = Vector2(200, 80)  # fallback if player not found

	add_child(panel)

	# Animate with tween
	var tween = create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 1.0)
	tween.chain().tween_interval(2.0)
	tween.chain().tween_property(panel, "modulate:a", 0.0, 1.0)
	tween.chain().tween_callback(panel.queue_free)
