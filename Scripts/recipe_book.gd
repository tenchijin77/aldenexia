# recipe_book.gd — the recipe book (L, player3d.gd toggle_recipe_book()). Every tradeskill recipe the character knows
# (innate ones plus those learned from recipe scrolls — player3d.gd knows_recipe()), from Data/tradeskill_recipes.json,
# like the abilities book does for spells: the finished item's icon, its ingredients (icon + quantity), the skill and level
# it needs, and where it can be made. Filter by skill or search by name. The skill line is green when you can make it,
# red when your skill is too low, and grey once it is trivial (no more skill-ups). Each recipe also shows how many times
# you have made it (player3d.gd record_craft(): the first success "discovers" it); "Discovered only" narrows the book to
# the things you have actually made, as a reference. Refreshes when a recipe is learned or made.
extends GameWindow
class_name RecipeBook

const POSITION_KEY := "recipe_book"
const RECIPES_PATH := "res://Data/tradeskill_recipes.json"
const ICON_SIZE := 36
const SMALL_ICON := 18
const STATION_NAMES := {"campfire": "Campfire", "tailors_bench": "Tailor's Bench"}

var _player: Node = null
var _recipes: Dictionary = {}
var _groups: Dictionary = {}
var _skill_filter: OptionButton
var _search: LineEdit
var _discovered_only: CheckBox
var _count: Label
var _list: VBoxContainer
var _skills: Array = []
var _known_signature := ""
var _refresh := 0.0


func _ready() -> void:
	build_frame("Recipe Book", POSITION_KEY, Vector2(560, 520), Vector2(420, 300))
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(RECIPES_PATH))
	if typeof(parsed) == TYPE_DICTIONARY:
		_recipes = parsed.get("recipes", {})
		_groups = parsed.get("ingredient_groups", {})
	var filters := HBoxContainer.new()
	body.add_child(filters)
	_skill_filter = OptionButton.new()
	_skill_filter.item_selected.connect(func(_i: int): _rebuild())
	filters.add_child(_skill_filter)
	_search = LineEdit.new()
	_search.placeholder_text = "Search recipes..."
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_t: String): _rebuild())
	filters.add_child(_search)
	_discovered_only = CheckBox.new()
	_discovered_only.text = "Discovered only"
	_discovered_only.tooltip_text = "Only recipes you have made at least once."
	_discovered_only.toggled.connect(func(_on: bool): _rebuild())
	filters.add_child(_discovered_only)
	_count = header("")
	body.add_child(_count)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)


func set_player(p: Node) -> void:
	_player = p
	_rebuild_skills()
	_rebuild()


func _process(delta: float) -> void:
	_refresh -= delta
	if _refresh > 0.0:
		return
	_refresh = 1.0
	if is_instance_valid(_player) and _signature() != _known_signature:
		_rebuild_skills()
		_rebuild()


func _signature() -> String:
	return JSON.stringify([_player.known_recipes, Global.player_data.get("crafted_recipes", {})])


func _crafted(id: String) -> int:
	return int(Global.player_data.get("crafted_recipes", {}).get(id, 0))


func _known() -> Array:
	var out: Array = []
	if not is_instance_valid(_player):
		return out
	for id in _recipes:
		if _player.knows_recipe(id, _recipes[id]):
			out.append(id)
	return out


# The skill dropdown: "All skills" plus every skill the character knows a recipe for.
func _rebuild_skills() -> void:
	_known_signature = _signature()
	var keep := _skill_filter.get_item_text(_skill_filter.selected) if _skill_filter.selected >= 0 else "All skills"
	_skills = []
	for id in _known():
		var skill := str(_recipes[id].get("skill", ""))
		if not _skills.has(skill):
			_skills.append(skill)
	_skills.sort()
	_skill_filter.clear()
	_skill_filter.add_item("All skills")
	for skill in _skills:
		_skill_filter.add_item(skill.capitalize())
	for i in _skill_filter.item_count:
		if _skill_filter.get_item_text(i) == keep:
			_skill_filter.select(i)


func _rebuild() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	if not is_instance_valid(_player):
		return
	var skill_pick := "" if _skill_filter.selected <= 0 else str(_skills[_skill_filter.selected - 1])
	var search := _search.text.strip_edges().to_lower()
	var ids := _known().filter(func(id):
		var r: Dictionary = _recipes[id]
		return (skill_pick.is_empty() or r.get("skill", "") == skill_pick) and (search.is_empty() or search in str(r.get("name", "")).to_lower()) \
			and (not _discovered_only.button_pressed or _crafted(id) > 0))
	ids.sort_custom(func(a, b):
		var ra: Dictionary = _recipes[a]; var rb: Dictionary = _recipes[b]
		if ra.get("skill", "") != rb.get("skill", ""):
			return str(ra.get("skill", "")) < str(rb.get("skill", ""))
		if int(ra.get("min_skill", 0)) != int(rb.get("min_skill", 0)):
			return int(ra.get("min_skill", 0)) < int(rb.get("min_skill", 0))
		return str(ra.get("name", "")) < str(rb.get("name", "")))
	var discovered := _known().filter(func(id): return _crafted(id) > 0).size()
	_count.text = "%d recipe%s shown%s  •  %d of %d known recipes discovered" % [ids.size(), "" if ids.size() == 1 else "s", "" if search.is_empty() and skill_pick.is_empty() and not _discovered_only.button_pressed else " (filtered)", discovered, _known().size()]
	var last_skill := ""
	for id in ids:
		var skill := str(_recipes[id].get("skill", ""))
		if skill != last_skill and skill_pick.is_empty():
			var h := header(skill.capitalize())
			h.add_theme_font_size_override("font_size", 14)
			h.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
			_list.add_child(h)
			last_skill = skill
		_list.add_child(_row(id, _recipes[id]))


func _row(id: String, r: Dictionary) -> Control:
	var out_def := Inventory.get_item_definition(str(r.get("output", "")))
	var row := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.12, 0.1, 0.9)
	style.set_border_width_all(1)
	style.border_color = Color(0.3, 0.27, 0.2)
	style.set_content_margin_all(5)
	row.add_theme_stylebox_override("panel", style)
	row.tooltip_text = str(out_def.get("description", ""))
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	row.add_child(hbox)
	hbox.add_child(ItemIcon.make_rect(ItemIcon.texture(out_def), ICON_SIZE))
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	hbox.add_child(col)

	var name_line := RichTextLabel.new()
	name_line.bbcode_enabled = true
	name_line.fit_content = true
	name_line.scroll_active = false
	name_line.autowrap_mode = TextServer.AUTOWRAP_OFF
	var skill_name := str(r.get("skill", ""))
	var have := int(_player.skill_levels.get(skill_name, 0))
	var need := int(r.get("min_skill", 0))
	var colour := "#ff7766" if have < need else ("#9a9a9a" if have >= int(r.get("max_level", 9999)) else "#88dd88")
	var makes := int(r.get("yield", 1))
	var made := _crafted(id)
	var made_text := ("   [color=#ffd966]✦ crafted %d×[/color]" % made) if made > 0 else "   [color=#777777]not yet discovered[/color]"
	name_line.text = "[b]%s[/b]%s   [color=%s]%s %d[/color]%s" % [r.get("name", ""), (" [color=#aaaaaa](makes %d)[/color]" % makes) if makes > 1 else "", colour, skill_name.capitalize(), need, made_text]
	col.add_child(name_line)

	var ingredients := HFlowContainer.new()
	ingredients.add_theme_constant_override("h_separation", 10)
	var ing: Dictionary = r.get("ingredients", {})
	for key in ing:
		var piece := HBoxContainer.new()
		piece.add_theme_constant_override("separation", 3)
		var shown_id := str(key)
		var label_name := ""
		if _groups.has(key):
			shown_id = "cooked_meat"
			label_name = str(key).trim_suffix("_any").replace("_", " ").capitalize().insert(0, "Any ")
		var def := Inventory.get_item_definition(shown_id)
		if label_name.is_empty():
			label_name = str(def.get("name", key))
		piece.add_child(ItemIcon.make_rect(ItemIcon.texture(def), SMALL_ICON))
		var l := Label.new()
		l.text = "%d %s" % [int(ing[key]), label_name]
		l.add_theme_font_size_override("font_size", 12)
		piece.add_child(l)
		ingredients.add_child(piece)
	col.add_child(ingredients)

	var where := Label.new()
	where.text = "Made at: " + _stations_text(r.get("stations", []))
	where.add_theme_font_size_override("font_size", 11)
	where.add_theme_color_override("font_color", Color(0.62, 0.6, 0.55))
	col.add_child(where)
	return row


func _stations_text(stations: Array) -> String:
	var names: Array = []
	for s in stations:
		var sid := str(s)
		names.append(STATION_NAMES.get(sid, sid.trim_prefix("basic_").replace("_", " ").capitalize()))
	if names.size() <= 1:
		return "".join(names)
	return ", ".join(names.slice(0, names.size() - 1)) + " or " + names[-1]
