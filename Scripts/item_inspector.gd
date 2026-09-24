# item_inspector.gd — The item properties popup for the SHOP (right-click a row in the For Sale or Your Items list). Shows what
# the item is and does, who can use it, and — for anything that can be worn or wielded — a comparison with whatever you have
# equipped in that slot, so you can tell whether a purchase is an upgrade BEFORE you spend the coin.
# (The bag's own inspect popup lives in slot_button.gd and carries the Equip/Use buttons; this one is read-only.)
class_name ItemInspector
extends RefCounted

const LAYER_NAME := "ItemInspectLayer"  # the same name the bag popup uses, so opening one replaces the other and Escape closes it
const GOOD := Color(0.45, 0.9, 0.5)
const BAD := Color(0.95, 0.45, 0.4)
const NEUTRAL := Color(0.8, 0.8, 0.8)


static func open(item_def: Dictionary, at_position: Vector2, tree: SceneTree) -> void:
	var root := tree.root
	var existing := root.get_node_or_null(LAYER_NAME)
	if existing:
		existing.name = LAYER_NAME + "_closing"  # it is only freed at the end of the frame: keep its name from renaming the new popup
		existing.queue_free()

	var layer := CanvasLayer.new()
	layer.name = LAYER_NAME
	layer.layer = 16

	# A PanelContainer, so the popup grows to fit however many lines the item has (a plain Panel would stay a fixed size).
	var popup := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.06, 0.98)
	style.border_color = Color(0.45, 0.38, 0.25)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(10)
	popup.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	popup.add_child(vbox)

	fill(vbox, item_def)

	vbox.add_child(HSeparator.new())
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(func() -> void: layer.queue_free())
	vbox.add_child(close_btn)

	popup.custom_minimum_size = Vector2(310, 60)
	layer.add_child(popup)
	root.add_child(layer)
	# Beside the click, then kept fully on screen once its real size is known (a frame later).
	popup.position = at_position + Vector2(14, 10)
	await tree.process_frame
	if is_instance_valid(popup):
		var vp := popup.get_viewport_rect().size
		popup.position = Vector2(clampf(popup.position.x, 4.0, maxf(vp.x - popup.size.x - 4.0, 4.0)), clampf(popup.position.y, 4.0, maxf(vp.y - popup.size.y - 4.0, 4.0)))


# Everything the popup says about an item: name, kind, stats, who can use it, what it does (for a spell scroll: what the spell does), lore, and
# how it compares with what you wear. Shared by the shop's popup (open() above) and the inventory / backpack popup (slot_button.gd).
static func fill(vbox: VBoxContainer, item_def: Dictionary, with_comparison: bool = true) -> void:
	_line(vbox, str(item_def.get("name", "Unknown Item")), Color(1.0, 0.85, 0.4), 14)
	_line(vbox, _kind_line(item_def), Color(0.62, 0.62, 0.66), 11)
	for stat_line in _stat_lines(item_def):
		_line(vbox, stat_line, Color(0.7, 0.85, 1.0), 12)
	var usable := _usability_line(item_def)
	if not usable.is_empty():
		_line(vbox, usable[0], usable[1], 11)
	var set_id := ArmorTypes.set_of(item_def)
	if not set_id.is_empty() and ArmorTypes.sets().has(set_id):
		var set_def: Dictionary = ArmorTypes.sets()[set_id]
		_line(vbox, "%s set (%d / %d worn). Full set: %s" % [set_def.get("name", set_id), int(ArmorTypes.worn_counts().get(set_id, 0)), int(set_def.get("pieces", 9)), ArmorTypes.bonus_text(set_id)], Color(0.95, 0.85, 0.45), 11)
	if str(item_def.get("description", "")) != "":
		_line(vbox, str(item_def["description"]), Color(0.82, 0.82, 0.82), 11)
	var kind := known_kind(item_def)
	if kind == "recipe" or kind == "language":
		_line(vbox, "✔ You already know this %s." % kind, Color(0.45, 0.85, 0.5), 11)
	var spell_block := _spell_lines(item_def)
	if not spell_block.is_empty():
		vbox.add_child(HSeparator.new())
		for entry in spell_block:
			_line(vbox, entry[0], entry[1], int(entry[2]) if entry.size() > 2 else 11)
	if str(item_def.get("lore", "")) != "":
		_line(vbox, str(item_def["lore"]), Color(0.65, 0.65, 0.55), 10)

	if with_comparison:
		var comparison := _comparison(item_def)
		if not comparison.is_empty():
			vbox.add_child(HSeparator.new())
			for entry in comparison:
				_line(vbox, entry[0], entry[1], int(entry[2]) if entry.size() > 2 else 11)


# True for a scroll whose lesson the local player already has — a spell scroll for a known spell, a recipe scroll for a known
# recipe (player3d.gd known_recipes), a language primer for a language already started (Languages.learn_basics() refuses it).
# The shop and the inventory mark those so you do not buy or carry a scroll you cannot use.
static func teaches_known(def: Dictionary) -> bool:
	return known_kind(def) != ""


# What an already-known scroll teaches: "spell", "recipe" or "language"; "" if it teaches nothing you know.
static func known_kind(def: Dictionary) -> String:
	var player := TargetFrame.local_player()
	var spell_name := str(def.get("teaches_spell", ""))
	if spell_name != "":
		return "spell" if is_instance_valid(player) and "known_spells" in player and spell_name in player.known_spells else ""
	var recipe_id := str(def.get("teaches_recipe", ""))
	if recipe_id != "":
		# Only non-innate recipes have scrolls, so the learned list is the whole answer.
		return "recipe" if is_instance_valid(player) and "known_recipes" in player and recipe_id in player.known_recipes else ""
	var language := str(def.get("teaches_language", ""))
	if language != "":
		return "language" if Languages.skill(language) >= 1.0 else ""
	return ""


# What a spell scroll teaches: the spell's name, the level YOUR class needs, its description and its numbers, and whether you already
# know it. [] for anything that is not a scroll. Songs (the Troubadour's spells) are spells too.
static func _spell_lines(def: Dictionary) -> Array:
	var spell_name := str(def.get("teaches_spell", ""))
	if spell_name.is_empty():
		return []
	var player := TargetFrame.local_player()
	var info: Dictionary = {}
	if is_instance_valid(player) and "_spell_by_name" in player:
		info = player._spell_by_name.get(spell_name, {})
	if info.is_empty():
		return [["Teaches: %s" % _nice(spell_name), Color(0.8, 0.75, 1.0), 12]]
	var lines: Array = []
	var my_class := str(player.get("player_class")) if is_instance_valid(player) else ""
	var levels: Dictionary = info.get("class_level_requirements", {})
	var required := SpellInfo.required_level(info, my_class) if levels.has(my_class) else (int(levels.values().min()) if not levels.is_empty() else int(info.get("level", 1)))
	var my_level := int(player.combat_node.level) if is_instance_valid(player) and "combat_node" in player and player.combat_node else 1
	var can_cast := levels.has(my_class) and my_level >= required
	var known: Array = player.get("known_spells") if is_instance_valid(player) and "known_spells" in player else []
	var header := "%s: %s" % ["Song" if my_class == "Troubadour" else "Spell", Player3D.spell_display_name(spell_name)]
	lines.append([header, Color(0.8, 0.75, 1.0), 13])
	var school := str(info.get("spell_school", ""))
	lines.append(["Level %d%s" % [required, ("   ·   " + _nice(school)) if school != "" else ""], Color(0.55, 0.85, 0.55) if can_cast else Color(0.9, 0.4, 0.4), 11])
	if str(info.get("description", "")) != "":
		lines.append([str(info["description"]), Color(0.86, 0.86, 0.92), 11])
	var facts: Array = []
	if float(info.get("mana_cost", 0.0)) > 0.0:
		facts.append("%d mana" % int(info["mana_cost"]))
	if float(info.get("casting_time", 0.0)) > 0.0:
		facts.append("cast %.1f s" % float(info["casting_time"]))
	if float(info.get("recast_time", 0.0)) > 0.0:
		facts.append("recast %.0f s" % float(info["recast_time"]))
	var reach := Player3D.spell_range_m(info)
	if reach > 0.0 and str(info.get("target", "")) not in ["self", "pbaoe"]:
		facts.append("range %d m" % int(reach))
	if str(info.get("target", "")) != "":
		facts.append("target: %s" % _nice(str(info["target"])))
	if float(info.get("damage", 0)) > 0.0:
		facts.append("damage %d" % int(info["damage"]))
	if not facts.is_empty():
		lines.append(["  ·  ".join(facts), Color(0.45, 0.65, 1.0), 11])
	if spell_name in known:
		lines.append(["You already know this.", Color(0.7, 0.7, 0.75), 11])
	return lines


static func _line(parent: Control, text: String, color: Color, font_size: int) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(290, 0)
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)


static func _nice(text: String) -> String:
	return text.replace("_", " ").capitalize()


# "Weapon - Primary hand - Slashing weapons", "Armor - Back", "Scroll", ...
static func _kind_line(def: Dictionary) -> String:
	var parts: Array = [_nice(str(def.get("type", "item")))]
	var slot := str(def.get("slot", "none"))
	if slot != "none" and slot != "":
		parts.append(_nice(slot))
	var skill := str(def.get("skill", "none"))
	if skill != "none" and skill != "" and (def.get("damage", 0) > 0 or def.get("type", "") == "weapon"):
		parts.append(_nice(skill))
	return " - ".join(parts)


static func _stat_lines(def: Dictionary) -> Array:
	var lines: Array = []
	if float(def.get("damage", 0)) > 0.0:
		lines.append("Damage %d    Delay %d    Ratio %.2f" % [int(def["damage"]), int(def.get("delay", 0)), float(def.get("ratio", 0))])
	if int(def.get("armor_class", 0)) > 0:
		lines.append("Armor Class %d" % int(def["armor_class"]))
	var mods: Dictionary = def.get("stat_modifiers", {}) if typeof(def.get("stat_modifiers")) == TYPE_DICTIONARY else {}
	if not mods.is_empty():
		var parts: Array = []
		for key in mods:
			parts.append("%+d %s" % [int(mods[key]), _nice(str(key))])
		lines.append(", ".join(parts))
	var foot: Array = []
	if float(def.get("weight", 0)) > 0.0:
		foot.append("Weight %.1f" % float(def["weight"]))
	if int(def.get("value", 0)) > 0:
		foot.append("Value %d %s" % [int(def["value"]), _coin_short(str(def.get("currency_type", "copper")))])
	if not foot.is_empty():
		lines.append("    ".join(foot))
	return lines


static func _coin_short(currency: String) -> String:
	match currency:
		"silver": return "sp"
		"gold": return "gp"
		"platinum": return "pp"
	return "cp"


# Can YOUR class and race use it? [text, color] or [] if it is open to everyone. Armour also says its type and whether
# your class can wear it (ArmorTypes).
static func _usability_line(def: Dictionary) -> Array:
	var player := TargetFrame.local_player()
	if not str(def.get("armor_type", "")).is_empty():
		var my_class_name := str(player.get("player_class")) if is_instance_valid(player) else ""
		if not ArmorTypes.can_wear(def, my_class_name):
			return [ArmorTypes.refusal(def, my_class_name), BAD]
		if str(def.get("armor_type")) != "cloth":
			return ["%s. You can wear it." % ArmorTypes.label(def), GOOD]
	var classes: Array = def.get("class", ["all"])
	var races: Array = def.get("race", ["all"])
	var restricted := not ("all" in classes) or not ("all" in races)
	if not restricted:
		return []
	var my_class := str(player.get("player_class")).to_lower() if is_instance_valid(player) else ""
	var my_race := str(player.get("player_race")).to_lower() if is_instance_valid(player) else ""
	var class_ok := "all" in classes or my_class in classes.map(func(c): return str(c).to_lower())
	var race_ok := "all" in races or my_race in races.map(func(r): return str(r).to_lower())
	var who: Array = []
	if not ("all" in classes):
		who.append(", ".join(classes.map(func(c): return _nice(str(c)))))
	if not ("all" in races):
		who.append(", ".join(races.map(func(r): return _nice(str(r)))))
	if class_ok and race_ok:
		return ["Usable by: %s (that includes you)" % "; ".join(who), GOOD]
	return ["Usable by: %s. You cannot use this." % "; ".join(who), BAD]


# ── Comparison with what is equipped in the same slot(s) ──
static func _equip_slots_for(def: Dictionary) -> Array:
	var slot := str(def.get("slot", ""))
	var mapped: String = Inventory.ITEM_SLOT_MAP.get(slot, "")
	if mapped == "":
		return []
	match mapped:
		"ear1": return ["ear1", "ear2"]
		"wrist1": return ["wrist1", "wrist2"]
		"finger1": return ["finger1", "finger2"]
		"trinket1": return ["trinket1", "trinket2"]
	return [mapped]


# Lines of [text, color, size?] — empty when the item is not wearable/wieldable.
static func _comparison(def: Dictionary) -> Array:
	var slots := _equip_slots_for(def)
	if slots.is_empty():
		return []
	var out: Array = []
	var any_equipped := false
	for slot in slots:
		var worn: Variant = Inventory.equipped.get(slot, null)
		if typeof(worn) != TYPE_DICTIONARY or (worn as Dictionary).is_empty():
			continue
		any_equipped = true
		out.append(["Compared with your %s (%s):" % [worn.get("name", "?"), _nice(slot)], Color(1.0, 0.85, 0.4), 12])
		out.append_array(_diff_lines(def, worn))
	if not any_equipped:
		out.append(["Nothing equipped in that slot: this would be your first.", GOOD, 11])
	return out


static func _diff_lines(new_def: Dictionary, old: Dictionary) -> Array:
	var out: Array = []
	var score := 0.0
	var new_is_weapon := float(new_def.get("damage", 0)) > 0.0
	if new_is_weapon or float(old.get("damage", 0)) > 0.0:
		var dn := float(new_def.get("damage", 0)); var do := float(old.get("damage", 0))
		out.append(_delta("Damage", do, dn, true))
		out.append(_delta("Delay", float(old.get("delay", 0)), float(new_def.get("delay", 0)), false))
		var rn := float(new_def.get("ratio", 0)); var ro := float(old.get("ratio", 0))
		out.append(_delta("Ratio (damage per delay)", ro, rn, true, 2))
		score += (rn - ro) * 10.0 if (rn > 0.0 or ro > 0.0) else (dn - do)
	var an := float(new_def.get("armor_class", 0)); var ao := float(old.get("armor_class", 0))
	if an > 0.0 or ao > 0.0:
		out.append(_delta("Armor Class", ao, an, true))
		score += an - ao
	var new_mods: Dictionary = new_def.get("stat_modifiers", {}) if typeof(new_def.get("stat_modifiers")) == TYPE_DICTIONARY else {}
	var old_mods: Dictionary = old.get("stat_modifiers", {}) if typeof(old.get("stat_modifiers")) == TYPE_DICTIONARY else {}
	var keys: Array = new_mods.keys()
	for k in old_mods:
		if not keys.has(k):
			keys.append(k)
	for key in keys:
		var nv := float(new_mods.get(key, 0)); var ov := float(old_mods.get(key, 0))
		if nv != ov:
			out.append(_delta(_nice(str(key)), ov, nv, true))
			score += nv - ov
	var verdict: Array
	var usable := _usability_line(new_def)
	if not usable.is_empty() and usable[1] == BAD:
		verdict = ["You cannot use this, so it is no upgrade for you.", BAD, 12]
	elif score > 0.01:
		verdict = ["Verdict: an UPGRADE over your %s." % old.get("name", "current item"), GOOD, 12]
	elif score < -0.01:
		verdict = ["Verdict: WORSE than your %s." % old.get("name", "current item"), BAD, 12]
	else:
		verdict = ["Verdict: about the same as your %s." % old.get("name", "current item"), NEUTRAL, 12]
	out.append(verdict)
	return out


# "Damage  6 -> 18  (+12)" in green when better, red when worse (for Delay, lower is better).
static func _delta(label: String, old_value: float, new_value: float, higher_is_better: bool, decimals: int = 0) -> Array:
	var change := new_value - old_value
	var fmt := "%%.%df" % decimals
	var text := ("%s   " + fmt + " -> " + fmt) % [label, old_value, new_value]
	if absf(change) < 0.0001:
		return [text + "   (same)", NEUTRAL, 11]
	var better := (change > 0.0) == higher_is_better
	return [text + ("   (" + ("%+." + str(decimals) + "f") + ")") % change, GOOD if better else BAD, 11]
