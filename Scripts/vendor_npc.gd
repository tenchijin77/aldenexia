# vendor_npc.gd — Stationary general-goods vendor. Player3D's right-click
# handler (_try_open_shop_or_loot()) opens shop_window.tscn against whichever
# VendorNPC is nearest when a vendor's within SHOP_RANGE, in preference to the
# usual loot-corpse behavior. Reuses the player's own Mixamo model/idle
# animation for its visual, same as monster3d.gd's humanoid mobs — no combat,
# no navigation, just stands in place with a name label like guard_npc.gd.
extends CharacterBody3D
class_name VendorNPC

@export var npc_name: String = "Vendor"
@export var shop_id: String = "lumora_general_goods"  # key into Data/vendor_shop.json
@export var shop_data_path: String = "res://Data/vendor_shop.json"

@onready var name_label: Label3D = $NameLabel
@onready var animation_player: AnimationPlayer = $Character/AnimationPlayer

var _shop_data: Dictionary = {}


func _ready() -> void:
	add_to_group("npc_vendor")
	if name_label:
		name_label.text = npc_name
	_load_shop_data()
	_setup_animation()


func _load_shop_data() -> void:
	var file := FileAccess.open(shop_data_path, FileAccess.READ)
	if not file:
		return
	var result = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(result) == TYPE_DICTIONARY:
		_shop_data = result.get(shop_id, {})


func get_vendor_display_name() -> String:
	return _shop_data.get("vendor_name", npc_name)


# Returns [{item_id, item_def, price}] for everything this vendor stocks,
# skipping any item_id from the JSON that has no items.json definition.
func get_shop_stock() -> Array:
	var stock: Array = []
	var multiplier: float = _shop_data.get("buy_price_multiplier", 1.0)
	for item_id in _shop_data.get("stock", []):
		var item_def: Dictionary = Inventory.get_item_definition(item_id)
		if item_def.is_empty():
			continue
		var price := int(round(Global.item_value_in_copper(item_def) * multiplier))
		stock.append({"item_id": item_id, "item_def": item_def, "price": maxi(price, 1)})
	return stock


# What this vendor will pay the player for one unit of a given item def.
func get_sell_price(item_def: Dictionary) -> int:
	var multiplier: float = _shop_data.get("sell_price_multiplier", 0.5)
	return maxi(int(round(Global.item_value_in_copper(item_def) * multiplier)), 1)


func _setup_animation() -> void:
	if not animation_player:
		return
	var lib := load("res://models/player/player_animations.res") as AnimationLibrary
	if not lib:
		return
	if animation_player.has_animation_library(""):
		animation_player.remove_animation_library("")
	animation_player.add_animation_library("", lib)
	if animation_player.has_animation("idle"):
		animation_player.play("idle")
