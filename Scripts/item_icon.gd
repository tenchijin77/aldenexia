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


static func _load(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if not _cache.has(path):
		_cache[path] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _cache[path]
