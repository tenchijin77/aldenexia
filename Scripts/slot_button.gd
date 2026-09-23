#slot_button.gd - creates the drag and drop bag slots
extends TextureButton

var slot_type: String = ""
var slot_name: String = ""
var slot_index: int = -1
var bag_slot: int = -1
var item_index: int = -1
var item_data: Dictionary = {}
## Dim slot name drawn inside an EMPTY tile (the equipment paperdoll sets this).
var placeholder: String = ""

const TILE_BG_EMPTY := Color(0.085, 0.085, 0.115, 0.96)
const TILE_BG_FILLED := Color(0.12, 0.11, 0.09, 0.96)
const FRAME_EMPTY := Color(0.27, 0.27, 0.34)
const FRAME_FILLED := Color(0.62, 0.52, 0.30)
const FRAME_HOVER := Color(0.95, 0.80, 0.42)
const FRAME_LIT := Color(1.0, 0.62, 0.22)  # a lit light source glows warm
const PLACEHOLDER_COLOR := Color(0.42, 0.42, 0.52)

var _hovered := false
var _bg: Control     # tile background + placeholder, drawn BEHIND the icon
var _frame: Control  # border, drawn ON TOP of the icon
var _bg_style := StyleBoxFlat.new()
var _frame_style := StyleBoxFlat.new()

func _ready():
	custom_minimum_size = Vector2(48, 48)
	ignore_texture_size = true
	stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	mouse_filter = Control.MOUSE_FILTER_STOP

	_bg_style.set_corner_radius_all(5)
	_frame_style.set_corner_radius_all(5)
	_frame_style.draw_center = false
	_frame_style.set_border_width_all(1)

	# This node's own _draw() runs AFTER the button paints its icon, so anything
	# drawn there would cover the item. The tile background therefore lives in a
	# child with show_behind_parent (painted under the icon), and the border in a
	# normal child (painted over it).
	_bg = Control.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.show_behind_parent = true
	_bg.draw.connect(_draw_bg)
	add_child(_bg)
	_frame = Control.new()
	_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.draw.connect(_draw_frame)
	add_child(_frame)
	mouse_entered.connect(func(): _hovered = true; _frame.queue_redraw())
	mouse_exited.connect(func(): _hovered = false; _frame.queue_redraw())
	queue_redraw()

func _draw():
	# Just a redraw trigger: callers queue_redraw() this node whenever the item
	# changes, and the visible parts are the two child layers.
	if is_instance_valid(_bg):
		_bg.queue_redraw()
	if is_instance_valid(_frame):
		_frame.queue_redraw()

func _draw_bg():
	_bg_style.bg_color = TILE_BG_EMPTY if item_data.is_empty() else TILE_BG_FILLED
	_bg.draw_style_box(_bg_style, Rect2(Vector2.ZERO, size))
	if item_data.is_empty() and placeholder != "":
		var font := ThemeDB.fallback_font
		var text_size := font.get_string_size(placeholder, HORIZONTAL_ALIGNMENT_CENTER, size.x - 4.0, 9)
		_bg.draw_string(font, Vector2((size.x - text_size.x) / 2.0, size.y / 2.0 + 3.0), placeholder,
				HORIZONTAL_ALIGNMENT_LEFT, size.x - 4.0, 9, PLACEHOLDER_COLOR)

func _draw_frame():
	var color := FRAME_EMPTY
	var width := 1
	if not item_data.is_empty():
		color = FRAME_LIT if item_data.get("lit", false) else FRAME_FILLED
		width = 2 if item_data.get("lit", false) else 1
	if _hovered:
		color = FRAME_HOVER
		width = 2
	_frame_style.border_color = color
	_frame_style.set_border_width_all(width)
	_frame.draw_style_box(_frame_style, Rect2(Vector2.ZERO, size))

	# A spell scroll for a spell you already know: green badge (disc with a tick) in the top-right corner
	if ItemInspector.teaches_known_spell(item_data):
		var centre := Vector2(size.x - 10.0, 10.0)
		_frame.draw_circle(centre, 7.5, Color(0, 0, 0, 0.85))
		_frame.draw_circle(centre, 6.0, Color(0.20, 0.62, 0.28))
		_frame.draw_polyline(PackedVector2Array([centre + Vector2(-3.2, 0.2), centre + Vector2(-0.8, 2.6), centre + Vector2(3.4, -2.6)]), Color(1, 1, 1), 1.8, true)

	# Stack count in the bottom-right corner
	if item_data.get("stackable", false) and int(item_data.get("quantity", 1)) > 1:
		var text := str(int(item_data.get("quantity", 1)))
		var font := ThemeDB.fallback_font
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
		var pos := Vector2(size.x - text_size.x - 4.0, size.y - 4.0)
		_frame.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 3, Color(0, 0, 0, 0.9))
		_frame.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT \
			and event.pressed and not item_data.is_empty():
		_show_inspect_popup()


func _learn_from_scroll() -> void:
	var spell_name: String = item_data.get("teaches_spell", "")
	if spell_name.is_empty():
		return

	var player := TargetFrame.local_player()
	if not is_instance_valid(player):
		return
	# Everything below that needs the scene tree goes through the PLAYER, not this button: removing the scroll makes the inventory
	# windows rebuild their slots, and the character sheet takes this very button out of the tree at once, so get_tree() on it
	# returns null afterwards ("Parameter data.tree is null" — the crash when learning Taunt from the character sheet's bags).
	var tree := player.get_tree()

	var known: Array = player.get("known_spells") if "known_spells" in player else []
	if spell_name in known:
		GameLog.log_general("You already know [b]%s[/b]." % spell_name.replace("_", " ").capitalize())
		return

	# Learn the spell
	known.append(spell_name)
	player.known_spells = known
	Global.player_data["known_spells"] = known

	# Remove the scroll from inventory
	if slot_type == "basic":
		Inventory.remove_from_basic_inventory(slot_index)
	elif slot_type == "bag":
		Inventory.remove_from_bag(bag_slot, item_index)

	Global.save_player_data_to_file()

	GameLog.log_general("[color=#ffdd44]You have learned [b]%s[/b]![/color]" % spell_name.replace("_", " ").capitalize())

	# Refresh the abilities book if it's open
	for node in tree.root.get_children():
		if node is AbilitiesBook:
			node.set_player(player)
			break

# Learns the tradeskill recipe a recipe scroll teaches (Data/crafting_items.json "teaches_recipe") and uses the scroll up.
# Anyone can learn any recipe; the recipe's min skill is checked when you try to craft it.
func _learn_recipe_from_scroll() -> void:
	var recipe_id: String = str(item_data.get("teaches_recipe", ""))
	var player := TargetFrame.local_player()
	if recipe_id.is_empty() or not is_instance_valid(player) or not player.has_method("learn_recipe"):
		return
	var recipe_name: String = str(item_data.get("name", recipe_id)).trim_prefix("Recipe: ")
	if not player.learn_recipe(recipe_id):
		GameLog.log_general("You already know how to make [b]%s[/b]." % recipe_name)
		return
	if slot_type == "basic":
		Inventory.remove_from_basic_inventory(slot_index)
	elif slot_type == "bag":
		Inventory.remove_from_bag(bag_slot, item_index)
	GameLog.log_general("[color=#ffdd44]You have learned how to make [b]%s[/b]![/color]" % recipe_name)


func _consume_item() -> void:
	var player := TargetFrame.local_player()
	if not is_instance_valid(player):
		return
	if not player.has_method("consume_food_or_drink"):
		return
	player.consume_food_or_drink(item_data)
	Inventory.consume_one(slot_type, slot_index, bag_slot, item_index)


# Bandages (Cloth/Coarse Bandage) previously had a "heal_amount"-less "effect"
# flavor-text field only, with no Use button anywhere — a fully inert item.
# Self-use only; bandaging a DOWNED ALLY goes through a separate right-click-
# in-the-3D-world flow (player3d.gd's _try_bandage()), not this inventory
# popup, since there's no "target" concept here.
func _use_bandage() -> void:
	var player := TargetFrame.local_player()
	if not is_instance_valid(player) or not ("combat_node" in player):
		return
	var healed: int = player.combat_node.heal(int(item_data.get("heal_amount", 0)))
	if healed > 0:
		GameLog.log_general("[color=#88ffaa]You bandage your wounds, healing [b]%d[/b].[/color]" % healed)
	else:
		GameLog.log_general("You are already at full health.")
	Inventory.consume_one(slot_type, slot_index, bag_slot, item_index)


func _show_inspect_popup() -> void:
	var tree := get_tree()
	var root = tree.root
	var existing = root.get_node_or_null("ItemInspectLayer")
	if existing:
		existing.name = "ItemInspectLayer_closing"  # freed only at the end of the frame: its name must not rename the new popup
		existing.queue_free()

	var layer := CanvasLayer.new()
	layer.name = "ItemInspectLayer"
	layer.layer = 15

	# A PanelContainer, so the popup grows to fit however many lines the item has (a plain Panel stays a fixed size).
	var popup := PanelContainer.new()
	popup.custom_minimum_size = Vector2(310, 60)

	var bg := StyleBoxFlat.new()
	bg.bg_color     = Color(0.08, 0.07, 0.06, 0.97)
	bg.border_color = Color(0.45, 0.38, 0.25)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(4)
	bg.set_content_margin_all(10)
	popup.add_theme_stylebox_override("panel", bg)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)

	# The same details the shop shows (kind, stats, who can use it, what it does; for a spell scroll what the spell does), and how it compares
	# with what you wear.
	ItemInspector.fill(vbox, item_data)

	# Separator
	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Action buttons row
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 6)
	vbox.add_child(btn_row)

	# Equip button (equippable items only)
	var equip_slot: String = Inventory.ITEM_SLOT_MAP.get(item_data.get("slot", ""), "")
	if not equip_slot.is_empty() and slot_type != "pet_equipment" and slot_type != "equipment":
		var equip_btn := Button.new()
		equip_btn.text = "Equip"
		equip_btn.pressed.connect(func():
			layer.queue_free()
			Inventory.equip_item(item_data, slot_type, slot_index, bag_slot, item_index)
		)
		btn_row.add_child(equip_btn)

	var player := TargetFrame.local_player()

	# Light a torch straight from a bag (equips one into the Light slot and lights it)
	if slot_type in ["basic", "bag"] and item_data.has("light_source") and player and player.has_method("light_from_bag"):
		var light_btn := Button.new()
		light_btn.text = "Light"
		light_btn.pressed.connect(func():
			layer.queue_free()
			player.light_from_bag(item_data, slot_type, slot_index, bag_slot, item_index)
		)
		btn_row.add_child(light_btn)

	# Equipped gear: Unequip (and Light / Snuff Out for the Light slot)
	if slot_type == "equipment" and player:
		if slot_name == "light" and player.has_method("light_equipped_light"):
			var lit_now: bool = bool(item_data.get("lit", false))
			var toggle_btn := Button.new()
			toggle_btn.text = "Snuff Out" if lit_now else "Light"
			toggle_btn.pressed.connect(func():
				layer.queue_free()
				if lit_now:
					player.snuff_equipped_light("You put out your %s." % str(item_data.get("name", "light")).to_lower())
				else:
					player.light_equipped_light()
			)
			btn_row.add_child(toggle_btn)
		var take_off_btn := Button.new()
		take_off_btn.text = "Unequip"
		take_off_btn.pressed.connect(func():
			layer.queue_free()
			Inventory.unequip_item(slot_name)
		)
		btn_row.add_child(take_off_btn)

	# Equip to Pet button (weapon/armor items only, and only while a pet is out)
	if player and slot_type != "pet_equipment" and player.has_method("pet_can_equip_slot") \
			and player.pet_can_equip_slot(equip_slot) and is_instance_valid(player.get("active_pet")):
		var pet_equip_btn := Button.new()
		pet_equip_btn.text = "Equip to Pet"
		pet_equip_btn.pressed.connect(func():
			layer.queue_free()
			player.equip_to_pet(item_data, slot_type, slot_index, bag_slot, item_index)
		)
		btn_row.add_child(pet_equip_btn)

	# Unequip button (pet gear window slots only)
	if slot_type == "pet_equipment" and player:
		var unequip_btn := Button.new()
		unequip_btn.text = "Unequip"
		unequip_btn.pressed.connect(func():
			layer.queue_free()
			player.unequip_from_pet(slot_name)
		)
		btn_row.add_child(unequip_btn)

	# Learn button (spell scrolls and tradeskill recipe scrolls)
	if item_data.get("type") == "scroll" and item_data.has("teaches_recipe"):
		var learn_recipe_btn := Button.new()
		learn_recipe_btn.text = "Learn"
		learn_recipe_btn.pressed.connect(func():
			layer.queue_free()
			_learn_recipe_from_scroll()
		)
		btn_row.add_child(learn_recipe_btn)
	if item_data.get("type") == "scroll" and item_data.has("teaches_spell"):
		var learn_btn := Button.new()
		learn_btn.text = "Learn"
		learn_btn.pressed.connect(func():
			layer.queue_free()
			_learn_from_scroll()
		)
		btn_row.add_child(learn_btn)

	# Eat/Drink button (food/drink items only — see consume_food_or_drink())
	if item_data.get("type") in ["food", "drink"]:
		var consume_btn := Button.new()
		consume_btn.text = "Eat" if item_data.get("type") == "food" else "Drink"
		consume_btn.pressed.connect(func():
			layer.queue_free()
			_consume_item()
		)
		btn_row.add_child(consume_btn)

	# Drink button (crafted potions and elixirs — player3d.gd's use_potion())
	if item_data.get("type") == "potion":
		var drink_btn := Button.new()
		drink_btn.text = "Drink"
		drink_btn.pressed.connect(func():
			layer.queue_free()
			var p := TargetFrame.local_player()
			if is_instance_valid(p) and p.has_method("use_potion") and p.use_potion(item_data):
				Inventory.consume_one(slot_type, slot_index, bag_slot, item_index)
		)
		btn_row.add_child(drink_btn)

	# Use button (bandage-style consumables with a heal_amount — see
	# _use_bandage(); food/drink already have their own Eat/Drink button above)
	if item_data.get("type") == "consumable" and int(item_data.get("heal_amount", 0)) > 0:
		var use_btn := Button.new()
		use_btn.text = "Use"
		use_btn.pressed.connect(func():
			layer.queue_free()
			_use_bandage()
		)
		btn_row.add_child(use_btn)

	# Open button (tradeskill stations, e.g. Basic Alchemy Kit — see
	# tradeskill_window.gd for the shared crafting window)
	if item_data.has("tradeskill_station"):
		var open_btn := Button.new()
		open_btn.text = "Open"
		open_btn.pressed.connect(func():
			layer.queue_free()
			var p := TargetFrame.local_player()
			if is_instance_valid(p) and p.has_method("_open_tradeskill_window"):
				p._open_tradeskill_window(item_data["tradeskill_station"], item_data.get("name", "Tool"), "Mix")
		)
		btn_row.add_child(open_btn)

	# Apply to Weapon button (weapon poisons, e.g. Basic Poison)
	if item_data.has("weapon_poison_bonus_damage"):
		var poison_btn := Button.new()
		poison_btn.text = "Apply to Weapon"
		poison_btn.pressed.connect(func():
			layer.queue_free()
			_show_weapon_choice_popup()
		)
		btn_row.add_child(poison_btn)

	# Drop (at your feet, in a pouch) and Destroy, for anything in your bags or character-sheet slots
	if slot_type in ["basic", "bag"]:
		var item_row := HBoxContainer.new()
		item_row.add_theme_constant_override("separation", 6)
		vbox.add_child(item_row)
		var drop_btn := Button.new()
		drop_btn.text = "Drop"
		drop_btn.tooltip_text = "Put it on the ground in a pouch (anyone can pick it up; it vanishes after 15 minutes).\nYou can also drag it out of the window onto the ground."
		drop_btn.pressed.connect(func():
			layer.queue_free()
			_drop_on_ground(item_data))
		item_row.add_child(drop_btn)
		var destroy_btn := Button.new()
		destroy_btn.text = "Destroy"
		destroy_btn.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))
		destroy_btn.pressed.connect(func():
			layer.queue_free()
			_confirm_destroy())
		item_row.add_child(destroy_btn)

	# In the bank an item can only be looked at (take it out to use, equip or eat it) — or withdrawn.
	var bank_open := not get_tree().get_nodes_in_group("bank_window").is_empty()
	if slot_type in ["bank", "bank_bag"]:
		for action in btn_row.get_children():
			action.queue_free()
		if bank_open:
			var withdraw_btn := Button.new()
			withdraw_btn.text = "Withdraw"
			withdraw_btn.tooltip_text = "Take it out of the bank into your bags."
			withdraw_btn.pressed.connect(func():
				layer.queue_free()
				Inventory.quick_bank_move(slot_type, slot_index, bag_slot, item_index))
			btn_row.add_child(withdraw_btn)
	elif slot_type in ["basic", "bag"] and bank_open:
		var deposit_btn := Button.new()
		deposit_btn.text = "Deposit"
		deposit_btn.tooltip_text = "Put it in the bank (a bag goes in with everything in it)."
		deposit_btn.pressed.connect(func():
			layer.queue_free()
			Inventory.quick_bank_move(slot_type, slot_index, bag_slot, item_index))
		btn_row.add_child(deposit_btn)

	# Close button
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(func(): layer.queue_free())
	btn_row.add_child(close_btn)

	popup.add_child(vbox)
	popup.position = get_global_mouse_position() + Vector2(10, 10)
	layer.add_child(popup)
	root.add_child(layer)
	# Kept fully on screen once its real size is known (a frame later): a spell scroll's popup is tall.
	await tree.process_frame
	if is_instance_valid(popup):
		var vp := popup.get_viewport_rect().size
		popup.position = Vector2(clampf(popup.position.x, 4.0, maxf(vp.x - popup.size.x - 4.0, 4.0)), clampf(popup.position.y, 4.0, maxf(vp.y - popup.size.y - 4.0, 4.0)))

# Small popup listing whichever weapon slot(s) (primary/secondary) currently
# have a weapon equipped, so the player picks which one gets poisoned when
# dual-wielding — rather than silently guessing "primary".
func _show_weapon_choice_popup() -> void:
	var weapon_slots: Array = ["primary", "secondary"].filter(func(slot_key):
		var equipped: Variant = Inventory.equipped.get(slot_key, null)
		return equipped != null and typeof(equipped) == TYPE_DICTIONARY and equipped.get("type", "") == "weapon"
	)
	if weapon_slots.is_empty():
		GameLog.log_general("[color=#ff8866]You have no weapon equipped to apply this to.[/color]")
		return

	var root = get_tree().root
	var existing = root.get_node_or_null("WeaponChoiceLayer")
	if existing:
		existing.queue_free()

	var layer := CanvasLayer.new()
	layer.name = "WeaponChoiceLayer"
	layer.layer = 15

	var popup := Panel.new()
	popup.custom_minimum_size = Vector2(220, 30 + 30 * weapon_slots.size())
	var bg := StyleBoxFlat.new()
	bg.bg_color     = Color(0.08, 0.07, 0.06, 0.97)
	bg.border_color = Color(0.45, 0.38, 0.25)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(4)
	popup.add_theme_stylebox_override("panel", bg)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	vbox.add_theme_constant_override("separation", 4)

	var title := Label.new()
	title.text = "Apply to which weapon?"
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	vbox.add_child(title)

	for slot_key in weapon_slots:
		var weapon: Dictionary = Inventory.equipped[slot_key]
		var btn := Button.new()
		btn.text = weapon.get("name", slot_key.capitalize())
		btn.pressed.connect(func():
			layer.queue_free()
			_apply_weapon_poison(slot_key)
		)
		vbox.add_child(btn)

	popup.add_child(vbox)
	popup.position = get_global_mouse_position() + Vector2(10, 10)
	layer.add_child(popup)
	root.add_child(layer)


func _apply_weapon_poison(equip_slot: String) -> void:
	var bonus: int = int(item_data.get("weapon_poison_bonus_damage", 0))
	var weapon: Dictionary = Inventory.equipped.get(equip_slot, {})
	if weapon.is_empty():
		return
	weapon["poison_bonus_damage"] = bonus
	weapon["poison_name"] = str(item_data.get("name", "Poison"))  # shown on the status window (buff_bar.gd)
	# Seconds of play left on the coating (ticks down while the weapon is equipped — see Player3D._tick_weapon_poison());
	# applying it again refreshes the time, like re-casting a buff.
	weapon["poison_remaining"] = float(item_data.get("weapon_poison_duration", Player3D.WEAPON_POISON_DEFAULT_SECONDS))
	Inventory.equipped[equip_slot] = weapon

	var player := TargetFrame.local_player()
	if is_instance_valid(player) and player.has_method("_apply_equipment_from_inventory"):
		player._apply_equipment_from_inventory()

	Inventory.consume_one(slot_type, slot_index, bag_slot, item_index)
	GameLog.log_general("[color=#88ffaa]You coat %s with poison (+%d damage for %d minutes).[/color]" % [weapon.get("name", "your weapon"), bonus, int(round(float(weapon["poison_remaining"]) / 60.0))])


# What was picked up by the drag in progress (item_data itself can be refreshed before the drag ends).
var _dragged_item: Dictionary = {}


# Dropping an item on an NPC in the 3D world (EverQuest-style: drag a rat tail onto Kenji). Godot only delivers drops
# to Controls, so when a drag from a bag slot ends with no UI accepting it AND the cursor is over the world (not
# over another window), the item is offered to whatever NPC is under the cursor.
func _notification(what: int) -> void:
	if what != NOTIFICATION_DRAG_END or _dragged_item.is_empty():
		return
	var item := _dragged_item
	_dragged_item = {}
	if slot_type != "basic" and slot_type != "bag":
		return
	var vp := get_viewport()
	if vp == null or vp.gui_is_drag_successful() or vp.gui_get_hovered_control() != null:
		return
	_offer_item_to_world(item, vp.get_mouse_position())


# Released over the world: an NPC under the cursor is offered it; otherwise it is dropped on the ground as a pouch.
func _offer_item_to_world(item: Dictionary, screen_pos: Vector2) -> void:
	var player := TargetFrame.local_player()
	if not is_instance_valid(player):
		return
	if player.has_method("try_offer_item_to_npc_at") and player.try_offer_item_to_npc_at(screen_pos, item):
		return
	_drop_on_ground(item)


# Takes this slot's item (the whole stack) out of the bags and puts it at the player's feet in a pouch (world_items.gd).
func _drop_on_ground(item: Dictionary) -> void:
	var player := TargetFrame.local_player() as Node3D
	var world_items := get_tree().get_first_node_in_group("world_items")
	if not is_instance_valid(player) or world_items == null:
		return
	var taken := Inventory.take_from_slot(slot_type, slot_index, bag_slot, item_index, str(item.get("item_id", "")))
	if taken.is_empty():
		return
	var forward := -player.global_transform.basis.z
	world_items.drop(taken, player.global_position + Vector3(forward.x, 0.0, forward.z).normalized() * 0.8, str(player.get("player_name")))
	GameLog.log_general("You drop %s on the ground." % _stack_name(taken))
	Global.save_player_data_to_file()


# Right-click menu > Destroy: asks first, then the item is gone for good.
func _confirm_destroy() -> void:
	var item := item_data.duplicate(true)
	var dialog := ConfirmationDialog.new()
	dialog.title = "Destroy item"
	dialog.dialog_text = "Destroy %s? This can't be undone." % _stack_name(item)
	dialog.ok_button_text = "Destroy"
	var layer := CanvasLayer.new()
	layer.layer = 20
	get_tree().root.add_child(layer)
	layer.add_child(dialog)
	dialog.confirmed.connect(func():
		var taken := Inventory.take_from_slot(slot_type, slot_index, bag_slot, item_index, str(item.get("item_id", "")))
		if not taken.is_empty():
			GameLog.log_general("[color=#ff8866]You destroy %s.[/color]" % _stack_name(taken))
			Global.save_player_data_to_file()
		layer.queue_free())
	dialog.canceled.connect(layer.queue_free)
	dialog.popup_centered()


static func _stack_name(item: Dictionary) -> String:
	var qty := int(item.get("quantity", 1)) if item.get("stackable", false) else 1
	return ("%d %s" % [qty, str(item.get("name", "item"))]) if qty > 1 else str(item.get("name", "the item"))


func _get_drag_data(at_position: Vector2) -> Variant:
	if item_data.is_empty():
		return null
	_dragged_item = item_data.duplicate(true)
	var payload := {
		"item_data": item_data,
		"slot_type": slot_type,
		"slot_name": slot_name,
		"slot_index": slot_index,
		"bag_slot": bag_slot,
		"item_index": item_index
	}
	var preview := TextureRect.new()
	preview.texture = ItemIcon.texture(item_data)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.custom_minimum_size = Vector2(48, 48)
	preview.modulate = Color(1, 1, 1, 0.85)
	set_drag_preview(preview)
	return payload

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	if data.get("slot_type") == "loot":
		return not data.get("item_id", "").is_empty()
	if slot_type == "equipment":
		var item: Dictionary = data.get("item_data", {})
		var target: String = Inventory.ITEM_SLOT_MAP.get(item.get("slot", "none"), "")
		return target == slot_name
	return data.has("item_data")

func _drop_data(at_position: Vector2, data: Variant) -> void:
	if data.get("slot_type") == "loot":
		var item_id: String = data.get("item_id", "")
		if item_id.is_empty():
			return
		var qty: int = data.get("loot_drop", {}).get("quantity", 1)
		if Inventory.add_item(item_id, qty):
			var window = data.get("loot_window")
			if is_instance_valid(window):
				window.consume_loot(data.get("loot_drop"))
		else:
			GameLog.log_general("[color=#ff8866]Your inventory is full.[/color]")
	elif slot_type == "equipment":
		Inventory.equip_item(
			data.get("item_data", {}),
			data.get("slot_type", ""),
			data.get("slot_index", -1),
			data.get("bag_slot", -1),
			data.get("item_index", -1)
		)
	elif data.get("slot_type") == "equipment":
		Inventory.unequip_item(data.get("slot_name", ""))
	else:
		Inventory.move_item_between_slots(self, data)
