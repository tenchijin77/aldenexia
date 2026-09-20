# tradeskill_slot.gd — one of the 4 ingredient slots in tradeskill_window.gd.
# Accepts a drag-and-drop item the same way slot_button.gd's real inventory
# slots do (same drag payload shape: item_data/slot_type/slot_index/bag_slot/
# item_index), but immediately removes the dropped item from the player's
# actual inventory via Inventory.consume_amount() rather than just moving a
# reference — this is a staging slot, not a real inventory slot. Right-click
# returns the held item straight back to the bag (Inventory.add_item()).
#
# Icon uses texture_normal (TextureButton's own built-in property), same as
# backpack_ui.gd's slots — an earlier version drew the icon manually in
# _draw() via draw_texture_rect(), which never actually rendered; this is the
# one pattern already proven working elsewhere in this codebase. tooltip_text
# is a free built-in Control hover tooltip, so the item name-on-hover the
# user asked for needs no custom popup code.
extends TextureButton
class_name TradeskillSlot

var held_item_id: String = ""
var held_quantity: int = 0

signal contents_changed


func _ready() -> void:
	custom_minimum_size = Vector2(48, 48)
	ignore_texture_size = true
	stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	mouse_filter = Control.MOUSE_FILTER_STOP


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.15, 0.15, 0.15, 0.9))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.5, 0.5, 0.5, 1.0), false, 1.0)
	if held_quantity > 1:
		draw_string(ThemeDB.fallback_font, Vector2(4, size.y - 4), str(held_quantity),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)


func is_empty() -> bool:
	return held_item_id.is_empty()


func clear() -> void:
	held_item_id = ""
	held_quantity = 0
	texture_normal = null
	tooltip_text = ""
	queue_redraw()


# Removes `amount` from the held stack (used when a recipe only consumes
# part of what's staged) — clears the slot entirely if that empties it.
func remove_quantity(amount: int) -> void:
	held_quantity -= amount
	if held_quantity <= 0:
		clear()
	else:
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT \
			and event.pressed and not is_empty():
		Inventory.add_item(held_item_id, held_quantity)
		clear()
		contents_changed.emit()


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY or not data.has("item_data"):
		return false
	if not is_empty():
		return false
	# Loot-window drags use a different payload shape (item_id/loot_drop) —
	# not meaningful to drag straight from a corpse into a crafting slot.
	return data.get("slot_type", "") in ["basic", "bag"]


# Takes the WHOLE dragged stack (per the user's request: drag in 4 raw meat,
# cook all 4 at once) rather than always exactly 1 — Inventory has no
# split-stack UI to drag a partial amount anyway, so "the whole stack" is the
# only sensible amount a single drag can represent.
func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var item_data: Dictionary = data.get("item_data", {})
	var item_id: String = item_data.get("item_id", "")
	if item_id.is_empty():
		return
	var quantity: int = int(item_data.get("quantity", 1)) if item_data.get("stackable", false) else 1
	Inventory.consume_amount(
		data.get("slot_type", ""), data.get("slot_index", -1),
		data.get("bag_slot", -1), data.get("item_index", -1), quantity
	)
	held_item_id = item_id
	held_quantity = quantity
	tooltip_text = item_data.get("name", item_id)
	texture_normal = ItemIcon.texture(item_data)
	queue_redraw()
	contents_changed.emit()
