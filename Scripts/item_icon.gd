# item_icon.gd — Shared helper for showing an item's icon (items.json "icon"
# field) in list rows: the vendor's buy/sell lists and the corpse loot window.
class_name ItemIcon

const DEFAULT_SIZE := 30
const COIN_ICON := "res://Assets/icons/items/coin.png"

static var _cache: Dictionary = {}  # res:// path -> Texture2D (or null if it failed to load)


static func texture(item_def: Dictionary) -> Texture2D:
	return _load(str(item_def.get("icon", "")))


static func coin_texture() -> Texture2D:
	return _load(COIN_ICON)


# A ready-to-add icon square. Always returned (empty if the item has no icon or
# the file is missing) so every row keeps the same column alignment.
static func make_rect(tex: Texture2D, size: int = DEFAULT_SIZE) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = tex
	rect.custom_minimum_size = Vector2(size, size)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


# Hover text for an item in a slot: name (x qty), slot/type, stats, description,
# burn time for lights, and value — the item counterpart of SpellInfo.tooltip().
const _COIN_ABBREV := {"copper": "cp", "silver": "sp", "gold": "gp", "platinum": "pp"}

static func tooltip(item: Dictionary) -> String:
	var lines: Array[String] = []
	var title := str(item.get("name", "Unknown Item"))
	var qty := int(item.get("quantity", 1)) if item.get("stackable", false) else 1
	if qty > 1:
		title += "  x%d" % qty
	lines.append(title)

	var meta: Array[String] = []
	var slot := str(item.get("slot", "none"))
	if slot != "none" and slot != "":
		meta.append(slot.capitalize())
	var type := str(item.get("type", ""))
	if type != "" and type != "misc":
		meta.append(type.capitalize())
	if not meta.is_empty():
		lines.append(" · ".join(meta))

	var stats: Array[String] = []
	if int(item.get("damage", 0)) > 0:
		stats.append("Damage %d / Delay %d" % [int(item.get("damage", 0)), int(item.get("delay", 0))])
	if int(item.get("armor_class", 0)) > 0:
		stats.append("AC %d" % int(item.get("armor_class", 0)))
	if float(item.get("weight", 0.0)) > 0.0:
		stats.append("Wt %s" % str(item.get("weight")))
	if not stats.is_empty():
		lines.append("   ".join(stats))

	var desc := str(item.get("description", ""))
	if desc != "":
		lines.append("")
		lines.append(SpellInfo.wrap_text(desc))

	var light: Variant = item.get("light_source", null)
	if light is Dictionary:
		var secs := float(item.get("burn_remaining", float(light.get("burn_minutes", 10.0)) * 60.0))
		var time_text := "%d:%02d" % [int(secs) / 60, int(secs) % 60]
		lines.append("")
		if item.get("lit", false):
			lines.append("Lit — %s left" % time_text)
		elif item.has("burn_remaining"):
			lines.append("Unlit — %s left" % time_text)
		else:
			lines.append("Burns for about %d minutes" % int(light.get("burn_minutes", 10.0)))

	var value := int(item.get("value", 0))
	if value > 0:
		lines.append("Value: %d %s" % [value, _COIN_ABBREV.get(str(item.get("currency_type", "copper")), "cp")])
	return "\n".join(lines)


static func _load(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if not _cache.has(path):
		_cache[path] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _cache[path]
