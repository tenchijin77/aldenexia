# inventory.gd
extends Control

var inventory: Dictionary = {}        # Tracks item quantities
var item_data: Dictionary = {}        # Definitions loaded from items.json

var equipped := {
	"weapon": null,
	"armor": null,
	"accessory": null
}

func _ready():
	load_item_data()
	load_backpack()

func load_item_data():
	var file = FileAccess.open("res://Data/items.json", FileAccess.READ)
	if file:
		var text = file.get_as_text()
		var parsed = JSON.parse_string(text)
		if typeof(parsed) == TYPE_DICTIONARY:
			item_data = parsed
		else:
			push_error("items.json parsing failed or returned non-dictionary")

func add_item(item_id: String, amount: int = 1):
	if inventory.has(item_id):
		inventory[item_id] += amount
	else:
		inventory[item_id] = amount
	update_ui()

func equip_item(item_id: String, slot: String):
	if item_data.has(item_id):
		var item = item_data[item_id]
		if item.has("type") and item["type"] == slot:
			equipped[slot] = item_id
			inventory.erase(item_id)
			update_ui()

func unequip_item(slot: String):
	if equipped[slot]:
		add_item(equipped[slot])
		equipped[slot] = null
		update_ui()

func update_ui():
	# Loop through inventory and update item slots
	for item_id in inventory.keys():
		if not item_data.has(item_id):
			print("⚠️ Missing item definition for:", item_id)
			continue  # Skip updating UI for undefined items

		var icon_path = item_data[item_id].get("icon", "")
		var quantity = inventory[item_id]
		# TODO: Update inventory slot UI with icon_path and quantity

	# Loop through equipped slots
	for slot in equipped.keys():
		var item_id = equipped[slot]
		if item_id and item_data.has(item_id):
			var equip_icon = item_data[item_id].get("icon", "")
			# TODO: Update equipment UI panel with equip_icon for slot

func load_backpack():
	var file = FileAccess.open("res://Data/backpack.json", FileAccess.READ)
	if file:
		var json_data = JSON.parse_string(file.get_as_text())
		if json_data and json_data.has("items"):
			for entry in json_data["items"]:
				if entry.has("id") and entry.has("quantity"):
					add_item(entry["id"], entry["quantity"])
		if json_data.has("equipped"):
			for slot in equipped.keys():
				if json_data["equipped"].has(slot):
					equipped[slot] = json_data["equipped"][slot]
		file.close()

func save_backpack():
	var file = FileAccess.open("res://Data/backpack.json", FileAccess.WRITE)
	if file:
		var item_array = []
		for item_id in inventory.keys():
			item_array.append({ "id": item_id, "quantity": inventory[item_id] })
		var json_output = {
			"items": item_array,
			"equipped": equipped
		}
		file.store_string(JSON.stringify(json_output, "\t"))
		file.close()
