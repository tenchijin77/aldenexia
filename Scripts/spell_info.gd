# spell_info.gd — Shared helpers for showing a spell's icon + hover tooltip.
# Used by action_bar.gd, abilities_book.gd (K) and buff_bar.gd so all three
# read the same "icon" / "description" fields off player_spells.json entries
# (icons are assigned by tools/assign_spell_icons.py; spells with no matching
# icon file simply have no "icon" field and fall back to their text label).
class_name SpellInfo

const TOOLTIP_WRAP_CHARS := 46

static var _icon_cache: Dictionary = {}  # res:// path -> Texture2D (or null if it failed to load)


# Returns the spell's icon texture, or null when the entry has no icon field
# or the file can't be loaded.
static func icon_texture(info: Dictionary) -> Texture2D:
	var path: String = info.get("icon", "")
	if path.is_empty():
		return null
	if not _icon_cache.has(path):
		_icon_cache[path] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _icon_cache[path]


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
