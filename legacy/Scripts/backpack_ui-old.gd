#backpack_ui.gd
extends CanvasLayer

var is_open := false

func _ready():
	update_slots()

	visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)  # Ensure mouse is usable

func _input(event):
	if event.is_action_pressed("toggle_backpack"):
		toggle_backpack()

func toggle_backpack():
	visible = !visible
	if visible:
		update_slots()


func update_slots():
	var item_keys = Inventory.inventory.keys()
	for i in range(min(item_keys.size(), 12)):
		var item_id = item_keys[i]
		var slot_name = "slot" + str(i)
		var slot_node = $backpack_panel/slot_grid.get_node(slot_name)
		if Inventory.item_data.has(item_id):
			slot_node.texture_normal = load(Inventory.item_data[item_id].get("icon", ""))
			slot_node.tooltip_text = Inventory.item_data[item_id]["name"]
