# buff_bar.gd — Draggable HUD panel listing the player's active buffs/debuffs
# (stances included), EQ/WoW-style: each row shows a name, what it does, and
# time remaining. Reads directly off combat_node.active_effects (the generic
# effect system in combatnode.gd) rather than tracking its own list, so any
# future apply_effect() call — stance, spell buff/debuff, whatever — shows up
# here automatically with no extra wiring.
#
# Icons: each row has a bordered square on the left that shows the effect's
# spell icon (player_spells.json's "icon" field, via SpellInfo). Stances and
# environmental effects have no spell entry, so their square stays blank.
extends CanvasLayer
class_name BuffBar

const ICON_SIZE := 28
const POSITION_KEY := "buff_bar"
const RESIZE_MARGIN := 16.0
const MIN_WIDTH := 160.0
const MIN_HEIGHT := 100.0

var _player: Node = null
var _class_stances: Dictionary = {}
var _last_effect_names: Array = []
var _row_time_labels: Dictionary = {}  # effect_name -> Label
var _dragging := false
var _resizing := false

@onready var panel: Panel = $Panel
@onready var buff_list: VBoxContainer = $Panel/Margin/VBox/BuffList


func _ready() -> void:
	panel.gui_input.connect(_on_panel_gui_input)
	WindowPosition.load_full_into(POSITION_KEY, panel)
	var file := FileAccess.open("res://Data/class_stances.json", FileAccess.READ)
	if file:
		var data = JSON.parse_string(file.get_as_text())
		file.close()
		if typeof(data) == TYPE_DICTIONARY:
			_class_stances = data


func _process(_delta: float) -> void:
	if not is_instance_valid(_player):
		_player = TargetFrame.local_player()
		if not is_instance_valid(_player):
			return

	if not ("combat_node" in _player) or not (_player.combat_node is CombatNode):
		return

	var active_effects: Dictionary = _with_vitals(_with_weapon_poisons(_player.combat_node.active_effects))
	var effect_names: Array = active_effects.keys()
	effect_names.sort()

	if effect_names != _last_effect_names:
		_last_effect_names = effect_names.duplicate()
		_rebuild_rows(effect_names, active_effects)

	for effect_name in effect_names:
		var label: Label = _row_time_labels.get(effect_name)
		if label:
			label.text = _format_remaining(active_effects[effect_name].get("remaining", 0.0))


func _rebuild_rows(effect_names: Array, active_effects: Dictionary) -> void:
	for child in buff_list.get_children():
		child.queue_free()
	_row_time_labels.clear()

	for effect_name in effect_names:
		var display := _resolve_effect_display(effect_name)
		var remaining: float = active_effects[effect_name].get("remaining", 0.0)
		_build_row(effect_name, display.name, display.description, remaining, display.is_debuff, display.get("icon"))


func _build_row(effect_name: String, display_name: String, description: String, remaining: float, is_debuff: bool = false, icon: Texture2D = null) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	# Full description only on hover (was always shown inline, cluttering the
	# window per the user's feedback 2026-09-17) — needs MOUSE_FILTER_STOP,
	# since a Container's default filter (IGNORE) never receives the hover
	# events a tooltip needs.
	row.tooltip_text = SpellInfo.wrap_text(description)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	# Right-click cancels the effect, EQ-style — stances excluded since they
	# toggle through stance_bar.gd's own current-stance state, not a plain
	# active_effects entry; erasing just the buff-bar side of it here would
	# desync the two.
	if not effect_name.begins_with("stance_") and not effect_name.begins_with(WEAPON_POISON_PREFIX) and not VITAL_DEBUFFS.has(effect_name):
		row.gui_input.connect(func(event: InputEvent): _on_row_gui_input(event, effect_name))

	var icon_box := Panel.new()
	icon_box.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	var icon_style := StyleBoxFlat.new()
	# Debuffs/negative effects get a red-highlighted box so the player has an
	# immediate visual cue something harmful is active, separate from reading
	# each row's name/description.
	if is_debuff:
		icon_style.bg_color = Color(0.35, 0.08, 0.08)
		icon_style.border_color = Color(0.95, 0.25, 0.25)
		icon_style.set_border_width_all(2)
	else:
		icon_style.bg_color = Color(0.12, 0.12, 0.16)
		icon_style.border_color = Color(0.4, 0.4, 0.5)
		icon_style.set_border_width_all(1)
	icon_style.set_corner_radius_all(3)
	icon_box.add_theme_stylebox_override("panel", icon_style)
	# A Panel defaults to MOUSE_FILTER_STOP, which would swallow the hover
	# over the icon and stop the row's tooltip (and right-click cancel) from
	# firing there.
	icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if icon != null:
		var icon_rect := TextureRect.new()
		icon_rect.texture = icon   # (debuffs used to get a yellow border drawn round the icon; now the whole row is framed below)
		icon_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon_rect.offset_left   = 2
		icon_rect.offset_top    = 2
		icon_rect.offset_right  = -2
		icon_rect.offset_bottom = -2
		icon_rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_box.add_child(icon_rect)
	row.add_child(icon_box)

	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_theme_constant_override("separation", 0)
	row.add_child(text_col)

	var name_row := HBoxContainer.new()
	text_col.add_child(name_row)

	var name_label := Label.new()
	name_label.text = display_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", Color(0.95, 0.4, 0.4) if is_debuff else Color(0.95, 0.85, 0.55))
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_row.add_child(name_label)

	var time_label := Label.new()
	time_label.text = _format_remaining(remaining)
	time_label.add_theme_font_size_override("font_size", 10)
	time_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	name_row.add_child(time_label)
	_row_time_labels[effect_name] = time_label

	if not is_debuff:
		buff_list.add_child(row)
		return
	# A debuff: a yellow rectangle round the whole row (icon, name and time), so harmful effects stand out (test 34:
	# the old border round only the icon looked odd).
	var frame := PanelContainer.new()
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color(0.35, 0.08, 0.08, 0.25)
	frame_style.border_color = Color(0.95, 0.8, 0.2)
	frame_style.set_border_width_all(1)
	frame_style.set_corner_radius_all(3)
	frame_style.set_content_margin_all(2)
	frame.add_theme_stylebox_override("panel", frame_style)
	frame.mouse_filter = Control.MOUSE_FILTER_PASS
	frame.add_child(row)
	buff_list.add_child(frame)


# Cancelling only ever touches the LOCAL player's own combat_node — buff_bar.gd
# only ever displays TargetFrame.local_player()'s active_effects (see
# _process() above), so there's no remote target to relay to, unlike
# player3d.gd's cast-a-spell-on-someone-else relay helpers.
func _on_row_gui_input(event: InputEvent, effect_name: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if is_instance_valid(_player) and "combat_node" in _player and _player.combat_node is CombatNode:
			_player.combat_node.remove_effect(effect_name)
			GameLog.log_general("You cancel [b]%s[/b]." % Player3D.spell_display_name(effect_name))


func _format_remaining(remaining: float) -> String:
	if remaining == INF:
		return "∞"
	var seconds := maxi(0, int(remaining))
	return "%d:%02d" % [seconds / 60, seconds % 60]


# A poison coating a weapon isn't an active_effects entry — it's stored on the weapon item itself (slot_button.gd's
# _apply_weapon_poison() sets poison_bonus_damage + poison_name, and player3d.gd adds it to the weapon's damage). So it
# never showed up here and there was no way to tell a poisoned weapon from a clean one. Each poisoned equipped weapon now
# gets a synthetic row, keyed "weapon_poison:<slot>:<weapon>:<bonus>" (the key changes when the weapon or poison does, which
# is what makes the list rebuild). The time shown is the coating's poison_remaining (15 minutes of play from the moment it
# is applied). Not cancellable from here.
const WEAPON_POISON_PREFIX := "weapon_poison:"
const WEAPON_POISON_ICON := "res://Assets/icons/spells/aoepoison.png"  # the green skull

func _with_weapon_poisons(active_effects: Dictionary) -> Dictionary:
	var merged: Dictionary = active_effects
	for slot in ["primary", "secondary"]:
		var weapon: Variant = Inventory.equipped.get(slot, null)
		if weapon == null or typeof(weapon) != TYPE_DICTIONARY:
			continue
		var bonus: int = int(weapon.get("poison_bonus_damage", 0))
		if bonus <= 0:
			continue
		if merged == active_effects:
			merged = active_effects.duplicate()  # never write into the real effect dictionary
		merged["%s%s:%s:%d" % [WEAPON_POISON_PREFIX, slot, weapon.get("name", "weapon"), bonus]] = {"remaining": float(weapon.get("poison_remaining", Player3D.WEAPON_POISON_DEFAULT_SECONDS))}
	return merged


# Out of food / out of drink (satiety or thirst at 0): not real effects, just the player's state shown as debuffs — they
# appear the moment the vital hits 0 and vanish when you eat or drink. Can't be cancelled.
const VITAL_DEBUFFS := {
	"starving": {"name": "Starving", "item": "iron_rations", "vital": "satiety",
		"description": "You are out of food. Your health and stamina won't recover until you eat something."},
	"thirsty": {"name": "Thirsty", "item": "water_flask", "vital": "thirst",
		"description": "You are out of drink. Your mana won't recover until you drink something."},
}
const WARNING_TINT := Color(0.95, 0.15, 0.1)
const WARNING_OUTLINE := Color(1.0, 0.85, 0.15)
static var _warning_icons: Dictionary = {}


func _with_vitals(active_effects: Dictionary) -> Dictionary:
	var merged: Dictionary = active_effects
	for key in VITAL_DEBUFFS:
		var level = _player.get(VITAL_DEBUFFS[key]["vital"])
		if level != null and int(level) <= 0:
			if merged == active_effects:
				merged = active_effects.duplicate()  # never write into the real effect dictionary
			merged[key] = {"remaining": INF}
	return merged


# The item's own icon washed red, with a yellow border round it (Starving, Thirsty): a warning at a glance.
static func _warning_icon(item_id: String) -> Texture2D:
	return _outlined(ItemIcon.texture(Inventory.get_item_definition(item_id)), true, false)   # the row frame is the border now


# Every debuff's icon gets a yellow border (and, with `wash_red`, a red wash) so harmful effects stand out on the bar.
# Cached per source texture.
static func _outlined(base: Texture2D, wash_red: bool = false, border_on: bool = true) -> Texture2D:
	if base == null:
		return null
	var key := "%d|%s|%s" % [base.get_instance_id(), wash_red, border_on]
	if _warning_icons.has(key):
		return _warning_icons[key]
	var tex: Texture2D = base
	var img: Image = base.get_image()
	if img != null:
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		var w := img.get_width()
		var h := img.get_height()
		var border := maxi(2, int(round(mini(w, h) * 0.06)))
		for y in h:
			for x in w:
				if border_on and (x < border or y < border or x >= w - border or y >= h - border):
					img.set_pixel(x, y, WARNING_OUTLINE)
				elif wash_red:
					var c := img.get_pixel(x, y)
					var lum := c.get_luminance()
					var red := Color(WARNING_TINT.r * (0.35 + 0.9 * lum), WARNING_TINT.g * (0.3 + lum), WARNING_TINT.b * (0.3 + lum), c.a)
					img.set_pixel(x, y, c.lerp(red, 0.75))
		tex = ImageTexture.create_from_image(img)
	_warning_icons[key] = tex
	return tex


func _weapon_poison_display(effect_name: String) -> Dictionary:
	var parts := effect_name.substr(WEAPON_POISON_PREFIX.length()).split(":")
	var slot: String = parts[0] if parts.size() > 0 else "primary"
	var weapon: Variant = Inventory.equipped.get(slot, null)
	var weapon_name: String = str(weapon.get("name", "weapon")) if typeof(weapon) == TYPE_DICTIONARY else "weapon"
	var bonus: int = int(weapon.get("poison_bonus_damage", 0)) if typeof(weapon) == TYPE_DICTIONARY else 0
	var poison_name: String = str(weapon.get("poison_name", "Poison")) if typeof(weapon) == TYPE_DICTIONARY else "Poison"
	var description := "%s coats your %s: +%d damage on every hit, until it wears off." % [poison_name, weapon_name, bonus]
	if slot != "primary":
		description = "%s coats your %s, but only the weapon in your main hand deals damage, so this has no effect yet." % [poison_name, weapon_name]
	return {"name": "%s (%s)" % [poison_name, weapon_name], "description": description, "is_debuff": false, "icon": load(WEAPON_POISON_ICON) as Texture2D}


# Non-spell, non-stance effects (environmental buffs, etc.) that still want a
# real description on the buff bar instead of just a titled name.
const ENVIRONMENTAL_EFFECT_DESCRIPTIONS := {
	"campfire_warmth": "Resting by a campfire's warmth. +2 HP/Mana/Stamina regeneration.",
	"well_fed": "Well fed and hydrated. +2 HP/Mana/Stamina regeneration.",
	"kenjis_blessing": "Kenji's blessing. +2 HP/Mana/Stamina regeneration and +3 to hit.",
	"weak_poison": "A weak poison from a snake or spider bite: 5 damage every 6 seconds. It wears off after a minute, or a cure removes it.",
	"disease": "A disease from an undead creature's touch: 5 damage every 6 seconds. It wears off after a minute and a half, or a cure removes it.",
	"strong_poison": "A strong venom: heavy damage every few seconds until it wears off, or a cure removes it.",
	"weakening_venom": "A weakening venom: your blows land 15% softer and it burns a little, until it wears off or a cure removes it.",
	"sundered_armor": "Your armour has been battered loose: 4 less armour class until you set it right (it wears off).",
	"crippled": "Crippled: you move much more slowly until it wears off, or a cure removes it.",
	"blinded": "Blinded: sand or light in your eyes, 20 less to hit until it clears.",
	"dazed": "Dazed by a heavy blow: you can barely move for a moment.",
	"withering_touch": "A withering touch drains your life every few seconds until it fades, or a cure removes it.",
	"bleeding": "Bleeding: a deep wound that hurts every few seconds until it closes.",
	"grave_miasma": "The grave's miasma: you are weakened (10% softer blows) and sickened until it passes, or a cure removes it.",
	"lit_torch": "A burning torch lights the way. Rain will put it out, and it gives away a sneaking Shadowblade. Right-click to put it out.",
}
# Effects that borrow one of the spell icons (effect name -> icon path). There is no dedicated art for these yet, so they
# reuse the closest spell icon: a red flame for the campfire and the golden sunburst (the divine icon) for Kenji's blessing.
const ENVIRONMENTAL_EFFECT_SPELL_ICONS := {
	"campfire_warmth": "res://Assets/icons/spells/aoefire.png",
	"kenjis_blessing": "res://Assets/icons/spells/aoedivine.png",
	"weak_poison": "res://Assets/icons/spells/aoepoison.png",  # the green skull
	"disease": "res://Assets/icons/spells/targetnecromancy.png",
	"strong_poison": "res://Assets/icons/spells/grouppoison.png",
	"weakening_venom": "res://Assets/icons/spells/targetpoison.png",
	"sundered_armor": "res://Assets/icons/spells/aoephysical.png",
	"crippled": "res://Assets/icons/spells/targetroot.png",
	"blinded": "res://Assets/icons/spells/targetblind.png",
	"dazed": "res://Assets/icons/spells/targetstun.png",
	"withering_touch": "res://Assets/icons/spells/aoenecromancy.png",
	"bleeding": "res://Assets/icons/spells/aoephysical.png",
	"grave_miasma": "res://Assets/icons/spells/groupnecromancy.png",
}
# Environmental effects that are harmful (red box, yellow border).
const ENVIRONMENTAL_DEBUFFS := ["weak_poison", "disease", "strong_poison", "weakening_venom", "sundered_armor", "crippled", "blinded",
		"dazed", "withering_touch", "bleeding", "grave_miasma"]
# Effects that show an item's icon on the buff bar (effect name -> items.json id).
const ENVIRONMENTAL_EFFECT_ITEM_ICONS := {
	"lit_torch": "torch",
	"well_fed": "iron_rations",  # its icon is the generic food.png — swap for dedicated art when it exists
}

# Resolves an active_effects key to a display name + description + is_debuff
# flag by checking, in order: stance data (effect names are
# "stance_<stance_id>", never debuffs), the FULL spell table (_spell_by_name
# is loaded from every spell in player_spells.json, not just known ones — see
# player3d.gd _load_spell_cache() — so this also correctly flags a debuff an
# enemy/other source casts on the player, not just the player's own spells),
# then the environmental-effects table above, falling back to a titled
# version of the raw effect name if nothing matches.
func _resolve_effect_display(effect_name: String) -> Dictionary:
	if effect_name.begins_with(WEAPON_POISON_PREFIX):
		return _weapon_poison_display(effect_name)
	if VITAL_DEBUFFS.has(effect_name):
		var vital: Dictionary = VITAL_DEBUFFS[effect_name]
		return {"name": vital["name"], "description": vital["description"], "is_debuff": true, "icon": _warning_icon(vital["item"])}
	if effect_name.begins_with("stance_") or effect_name.begins_with("group_stance_"):
		var from_group := effect_name.begins_with("group_stance_")
		var stance_id := effect_name.trim_prefix("group_stance_").trim_prefix("stance_")
		for class_stances in _class_stances.values():
			if not (class_stances is Array):
				continue  # the file's "_comment"
			for stance in class_stances:
				if stance.get("stance_id", "") == stance_id:
					var shown: String = str(stance.get("name", stance_id)) + (" (from your group)" if from_group else "")
					return {"name": shown, "description": stance.get("description", ""), "is_debuff": false, "icon": SpellInfo.icon_texture(stance)}

	if "_spell_by_name" in _player:
		var spell: Dictionary = _player._spell_by_name.get(effect_name, {})
		if not spell.is_empty():
			# target, not spell_type/effect_type, decides red — those two
			# describe the spell's own mechanical shape/polarity (e.g. Aura of
			# the Shadow is effect_type "debuff" because it debuffs nearby
			# ENEMIES, and dozens of clearly-beneficial group buffs are
			# mis-tagged spell_type "detrimental" in the source data) rather
			# than whether landing on the PLAYER specifically is harmful. An
			# effect only ever ends up in the player's own active_effects
			# because they cast a self/group spell on themselves (never
			# harmful by construction) or a hostile "enemy"-target spell
			# resolved onto them (always harmful) — target says which.
			var is_debuff: bool = spell.get("target", "") == "enemy"
			return {"name": Player3D.spell_display_name(effect_name), "description": spell.get("description", ""), "is_debuff": is_debuff, "icon": SpellInfo.icon_texture(spell)}

	if ENVIRONMENTAL_EFFECT_DESCRIPTIONS.has(effect_name):
		var env_icon: Texture2D = null
		if ENVIRONMENTAL_EFFECT_ITEM_ICONS.has(effect_name):
			env_icon = ItemIcon.texture(Inventory.get_item_definition(ENVIRONMENTAL_EFFECT_ITEM_ICONS[effect_name]))
		elif ENVIRONMENTAL_EFFECT_SPELL_ICONS.has(effect_name):
			env_icon = load(ENVIRONMENTAL_EFFECT_SPELL_ICONS[effect_name]) as Texture2D
		return {"name": Player3D.spell_display_name(effect_name), "description": ENVIRONMENTAL_EFFECT_DESCRIPTIONS[effect_name], "is_debuff": ENVIRONMENTAL_DEBUFFS.has(effect_name), "icon": env_icon}

	return {"name": Player3D.spell_display_name(effect_name), "description": "", "is_debuff": false}


# ===== DRAGGABLE PANEL =====

func _on_panel_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var pos: Vector2 = event.position
			if pos.x > panel.size.x - RESIZE_MARGIN and pos.y > panel.size.y - RESIZE_MARGIN:
				_resizing = true
			else:
				_dragging = true
		else:
			if _dragging or _resizing:
				WindowPosition.save(POSITION_KEY, panel)
			_dragging = false
			_resizing = false
	elif event is InputEventMouseMotion and _resizing:
		panel.offset_right  = max(panel.offset_left + MIN_WIDTH, panel.offset_right + event.relative.x)
		panel.offset_bottom = max(panel.offset_top + MIN_HEIGHT, panel.offset_bottom + event.relative.y)
	elif event is InputEventMouseMotion and _dragging:
		panel.offset_left   += event.relative.x
		panel.offset_top    += event.relative.y
		panel.offset_right  += event.relative.x
		panel.offset_bottom += event.relative.y
