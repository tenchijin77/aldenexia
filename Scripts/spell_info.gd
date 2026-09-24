# spell_info.gd — Shared helpers for showing a spell's icon + hover tooltip.
# Used by action_bar.gd, abilities_book.gd (K) and buff_bar.gd so all three
# read the same "icon" / "description" fields off player_spells.json entries
# (icons are assigned by tools/assign_spell_icons.py; spells with no matching
# icon file simply have no "icon" field and fall back to their text label).
class_name SpellInfo

const TOOLTIP_WRAP_CHARS := 46

static var _icon_cache: Dictionary = {}  # res:// path (+ tint) -> Texture2D (or null if it failed to load)
static var _spells: Dictionary = {}      # spell_name -> player_spells.json entry
static var _counts_as: Dictionary = {}   # spell_name -> [itself + every spell it upgrades, all the way down]

# Upgrades ("upgrades": [base, ...] in player_spells.json — Improved Flurry replaces Flurry of Blows when learned) show the
# base spell's icon with a tint: gold for improved/greater/enhanced, violet for master.
const UPGRADE_TINT := Color(1.0, 0.8, 0.3)
const MASTER_TINT := Color(0.8, 0.5, 1.0)
const TINT_STRENGTH := 0.45


# Returns the spell's icon texture, or null when the entry has no icon field
# or the file can't be loaded.
static func icon_texture(info: Dictionary) -> Texture2D:
	var path: String = info.get("icon", "")
	if path.is_empty():
		return null
	var tint := Color.WHITE
	if info.has("upgrades"):
		tint = MASTER_TINT if str(info.get("spell_name", "")).begins_with("master_") else UPGRADE_TINT
	var key := path if tint == Color.WHITE else "%s|%s" % [path, tint.to_html()]
	if not _icon_cache.has(key):
		var tex: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
		_icon_cache[key] = _tinted(tex, tint) if tex != null and tint != Color.WHITE else tex
	return _icon_cache[key]


static func _tinted(tex: Texture2D, tint: Color) -> Texture2D:
	var img := tex.get_image()
	if img == null:
		return tex
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var shaded := Color(c.r * tint.r, c.g * tint.g, c.b * tint.b, c.a)
			img.set_pixel(x, y, c.lerp(shaded, TINT_STRENGTH).lerp(Color(tint, c.a), TINT_STRENGTH * 0.3))
	return ImageTexture.create_from_image(img)


static func spell(spell_name: String) -> Dictionary:
	if _spells.is_empty():
		var data = JSON.parse_string(FileAccess.get_file_as_string("res://Data/player_spells.json"))
		if typeof(data) == TYPE_ARRAY:
			for entry in data:
				_spells[str(entry.get("spell_name", ""))] = entry
	return _spells.get(spell_name, {})


# The spell plus every spell it upgrades (recursively): Master Ki Strike counts as Improved Ki Strike too. Passive checks and
# spell-specific code go through this, so an upgrade keeps working wherever its base did.
static func counts_as(spell_name: String) -> Array:
	if _counts_as.has(spell_name):
		return _counts_as[spell_name]
	var names: Array = [spell_name]
	var i := 0
	while i < names.size() and i < 16:
		for base in spell(str(names[i])).get("upgrades", []):
			if not names.has(base):
				names.append(base)
		i += 1
	_counts_as[spell_name] = names
	return names


# The original spell at the bottom of an upgrade chain ("master_ki_strike" -> "improved_ki_strike"'s base, or itself).
static func root_name(spell_name: String) -> String:
	var chain := counts_as(spell_name)
	var root := spell_name
	for name in chain:
		if spell(name).get("upgrades", []).is_empty():
			root = name
			break
	return root


# The level a class needs to cast this spell: the per-class entry, not the flat "level" field (the same spell can need a different
# level for different classes; player3d.gd's cast gate uses the same rule).
static func required_level(info: Dictionary, player_class: String) -> int:
	return int(info.get("class_level_requirements", {}).get(player_class, info.get("level", 1)))


# Godot's built-in tooltip never wraps, so long descriptions would render as
# one very wide line — break them on word boundaries ourselves.
static func wrap_text(text: String, width: int = TOOLTIP_WRAP_CHARS) -> String:
	var lines: Array[String] = []
	var current := ""
	for word in text.split(" ", false):
		if current.is_empty():
			current = word
		elif current.length() + 1 + word.length() <= width:
			current += " " + word
		else:
			lines.append(current)
			current = word
	if not current.is_empty():
		lines.append(current)
	return "\n".join(lines)


# Full tooltip: name, description straight from the file, then cost/recast
# when the spell has one (same "25 mp · 10s recast" line the K book shows).
static func tooltip(spell_name: String, info: Dictionary) -> String:
	var parts: Array[String] = [Player3D.spell_display_name(spell_name)]
	var desc: String = info.get("description", "")
	if not desc.is_empty():
		parts.append(wrap_text(desc))
	var cost: float = info.get("mana_cost", 0.0)
	if cost > 0.0:
		parts.append("%d mp  ·  %.0fs recast" % [int(cost), info.get("recast_time", 0.0)])
	return "\n\n".join(parts)
