extends TextureButton

var slot_type: String = ""      # "basic", "bag"
var slot_index: int = -1        # index in that container
var bag_slot: int = -1          # which basic slot this bag belongs to
var item_index: int = -1        # index inside bag_contents[bag_slot]
var item_data: Dictionary = {}  # actual item dictionary

func _ready():
	mouse_filter = Control.MOUSE_FILTER_PASS

#
# GODOT 4 DRAG START
#
func get_drag_data(position):
	if item_data == {}:
		return null

	var payload := {
		"item_data": item_data,
		"slot_type": slot_type,
		"slot_index": slot_index,
		"bag_slot": bag_slot,
		"item_index": item_index
	}

	var preview := TextureRect.new()
	if item_data.has("icon") and item_data.icon is String and FileAccess.file_exists(item_data.icon):
		preview.texture = load(item_data.icon)
	preview.custom_minimum_size = Vector2(48, 48)
	preview.modulate = Color(1, 1, 1, 0.85)

	set_drag_preview(preview)
	return payload

#
# GODOT 4 DROP VALIDATION
#
func can_drop_data(position, data):
	return typeof(data) == TYPE_DICTIONARY and data.has("item_data")

#
# GODOT 4 DROP HANDLING
#
func drop_data(position, data):
	Inventory.move_item_between_slots(self, data)
