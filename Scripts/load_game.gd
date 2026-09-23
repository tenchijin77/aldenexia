# load_game.gd — character-select popup opened from the main menu's "Load
# Game" button. Used to sit at a hardcoded absolute pixel position left over
# from an older main-menu layout, landing oddly off to the side once the
# menu itself was redesigned around a centered button column — now a
# properly centered, styled modal like the rest of this project's windows.
extends CanvasLayer

@onready var panel: Panel = $Panel
@onready var character_list: ItemList = $Panel/Margin/VBoxContainer/character_list
@onready var load_button: Button = $Panel/Margin/VBoxContainer/load_button

var delete_button: Button


func _ready() -> void:
	panel.add_theme_stylebox_override("panel", Global.window_bg_style())
	# Delete sits right under Load. Built here rather than in the scene, next to the button it pairs with.
	delete_button = Button.new()
	delete_button.text = "Delete Character"
	delete_button.custom_minimum_size = load_button.custom_minimum_size
	delete_button.pressed.connect(_on_delete_button_pressed)
	load_button.get_parent().add_child(delete_button)
	load_button.get_parent().move_child(delete_button, load_button.get_index() + 1)
	character_list.item_selected.connect(func(_i: int) -> void: _refresh_buttons())
	load_save_files()


func _on_close_button_pressed() -> void:
	queue_free()


# Loads available save files into the list
func load_save_files() -> void:
	character_list.clear()

	# Globalize the user://saves/ path to ensure it handles spaces and special characters correctly
	var save_dir_path = ProjectSettings.globalize_path("user://saves/")
	var dir = DirAccess.open(save_dir_path)

	if not dir:
		push_error("❌ Failed to open save directory: %s" % save_dir_path)
		load_button.disabled = true
		return

	dir.list_dir_begin()
	var file_name = dir.get_next()
	var found_any_saves := false
	while file_name != "":
		if file_name in [".", ".."]:
			file_name = dir.get_next()
			continue
		if file_name.ends_with("_character_stats.json"):
			found_any_saves = true
			var stem: String = file_name.replace("_character_stats.json", "")
			character_list.add_item(stem.capitalize())
			character_list.set_item_metadata(character_list.item_count - 1, stem)
		file_name = dir.get_next()
	dir.list_dir_end()

	load_button.disabled = not found_any_saves
	_refresh_buttons()


func _refresh_buttons() -> void:
	delete_button.disabled = character_list.get_selected_items().is_empty()


# Delete asks for the character's name to be typed exactly (see delete_character_dialog.gd) before
# it removes the save file, then refreshes the list.
func _on_delete_button_pressed() -> void:
	var selected_items := character_list.get_selected_items()
	if selected_items.is_empty():
		return
	var stem: String = character_list.get_item_metadata(selected_items[0])
	var dialog := DeleteCharacterDialog.open(self, Global.local_character_display_name(stem), "this computer")
	dialog.confirmed.connect(func(_password: String) -> void:
		Global.delete_local_character(stem)
		dialog.close()
		load_save_files()
	)


func _on_load_button_pressed() -> void:
	var selected_items = character_list.get_selected_items()
	if selected_items.is_empty():
		return

	var selected_character_name_raw = character_list.get_item_text(selected_items[0]).to_lower()
	var file_path = ProjectSettings.globalize_path("user://saves/%s_character_stats.json" % selected_character_name_raw)

	if not FileAccess.file_exists(file_path):
		push_error("❌ Save file not found: %s" % file_path)
		return

	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("❌ Failed to open file for reading: %s" % file_path)
		return

	var file_content = file.get_as_text()
	file.close()
	var character_data = JSON.parse_string(file_content)

	if typeof(character_data) != TYPE_DICTIONARY:
		push_error("❌ Failed to parse character data from JSON for: %s" % selected_character_name_raw)
		return

	Global.set_player_data(character_data)
	get_tree().change_scene_to_file(Global.START_ZONE_PATH)
