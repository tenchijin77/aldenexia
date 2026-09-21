# compass_hud.gd — A heading strip at the top of the screen showing the way the CHARACTER is facing (N, NE, E ... and degrees).
# Shown only while you carry a Compass item (bags or equipped), and only if you have not switched it off with N (or /compass).
# Drag it anywhere and drag its lower-right corner to resize it, like the other windows (position and size are saved per
# character; /resetui puts it back). "North" per zone comes from Data/compass.json (the direction of north on the zone map, [x, z] in world coordinates); the
# compass is a HUD element like the buff bar, spawned with the rest of the HUD.
extends CanvasLayer
class_name CompassHud

const ITEM_ID := "compass"
const CONFIG_PATH := "res://Data/compass.json"
const SETTING_KEY := "compass_visible"
const STRIP_WIDTH := 460.0
const STRIP_HEIGHT := 40.0
const VISIBLE_DEGREES := 140.0    # how much of the horizon the strip shows
const POSITION_KEY := "compass"
const RESIZE_MARGIN := 16.0
const MIN_SIZE := Vector2(180.0, 24.0)
const MAX_SIZE := Vector2(1400.0, 160.0)

var _strip: CompassStrip
var _config: Dictionary = {}
var _north := Vector2(0, -1)      # [x, z] of north in this zone
var _zone := ""
var _has_item := false
var _item_check_timer := 0.0
var _player: Node3D = null
var _dragging := false
var _resizing := false


func _ready() -> void:
	layer = 5
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH)) if FileAccess.file_exists(CONFIG_PATH) else null
	_config = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	_strip = CompassStrip.new()
	_strip.custom_minimum_size = MIN_SIZE
	_strip.size = Vector2(STRIP_WIDTH, STRIP_HEIGHT)
	_strip.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_strip.offset_left = -STRIP_WIDTH * 0.5
	_strip.offset_right = STRIP_WIDTH * 0.5
	_strip.offset_top = 10.0
	_strip.offset_bottom = 10.0 + STRIP_HEIGHT
	_strip.mouse_filter = Control.MOUSE_FILTER_STOP
	_strip.tooltip_text = "Drag to move. Drag the lower-right corner to resize."
	_strip.gui_input.connect(_on_strip_gui_input)
	_strip.mouse_entered.connect(func() -> void: _strip.hovered = true; _strip.queue_redraw())
	_strip.mouse_exited.connect(func() -> void: _strip.hovered = false; _strip.queue_redraw())
	add_child(_strip)
	WindowPosition.load_full_into(POSITION_KEY, _strip)  # a saved position/size from a previous session
	_strip.visible = false
	_refresh_zone()


# Drag anywhere to move; the lower-right corner resizes. Saved on release.
func _on_strip_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var pos: Vector2 = event.position
			_resizing = pos.x > _strip.size.x - RESIZE_MARGIN and pos.y > _strip.size.y - RESIZE_MARGIN
			_dragging = not _resizing
		else:
			if _dragging or _resizing:
				WindowPosition.save(POSITION_KEY, _strip)
			_dragging = false
			_resizing = false
	elif event is InputEventMouseMotion and _resizing:
		var width := clampf(_strip.size.x + event.relative.x, MIN_SIZE.x, MAX_SIZE.x)
		var height := clampf(_strip.size.y + event.relative.y, MIN_SIZE.y, MAX_SIZE.y)
		_strip.offset_right = _strip.offset_left + width
		_strip.offset_bottom = _strip.offset_top + height
		_strip.queue_redraw()
	elif event is InputEventMouseMotion and _dragging:
		_strip.offset_left += event.relative.x
		_strip.offset_right += event.relative.x
		_strip.offset_top += event.relative.y
		_strip.offset_bottom += event.relative.y


# Which way is north in the zone we are in now.
func _refresh_zone() -> void:
	var scene := get_tree().current_scene
	_zone = scene.scene_file_path.get_file().get_basename() if scene != null else ""
	var entry: Dictionary = _config.get("zones", {}).get(_zone, _config.get("default", {"north": [0, -1]}))
	var n: Array = entry.get("north", [0, -1])
	_north = Vector2(float(n[0]), float(n[1])).normalized()


# Degrees clockwise from north, 0..360, for a world-space forward vector.
func bearing_of(forward: Vector3) -> float:
	var f := Vector2(forward.x, forward.z)
	if f.length() < 0.001:
		return 0.0
	var east := Vector2(-_north.y, _north.x)
	return fposmod(rad_to_deg(atan2(f.dot(east), f.dot(_north))), 360.0)


static func cardinal_name(bearing: float) -> String:
	const NAMES := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	return NAMES[int(round(bearing / 45.0)) % 8]


func is_switched_on() -> bool:
	return bool(Global.settings.get(SETTING_KEY, true))


# N key or /compass. Returns a message for the log.
func toggle() -> String:
	if not _has_item:
		return "You have no compass."
	Global.settings[SETTING_KEY] = not is_switched_on()
	Global.save_settings()
	return "Compass shown." if is_switched_on() else "Compass hidden."


static func player_has_compass() -> bool:
	if ItemHelper.count(ITEM_ID) > 0:
		return true
	for item in Inventory.equipped.values():
		if typeof(item) == TYPE_DICTIONARY and str(item.get("item_id", "")) == ITEM_ID:
			return true
	return false


func _process(delta: float) -> void:
	if not is_instance_valid(_player):
		_player = TargetFrame.local_player()
		if not is_instance_valid(_player):
			_strip.visible = false
			return
	_item_check_timer -= delta
	if _item_check_timer <= 0.0:
		_item_check_timer = 0.5
		_has_item = player_has_compass()
		var scene_zone := get_tree().current_scene.scene_file_path.get_file().get_basename() if get_tree().current_scene else ""
		if scene_zone != _zone:
			_refresh_zone()
	_strip.visible = _has_item and is_switched_on()
	if _strip.visible:
		_strip.bearing = bearing_of(-_player.global_transform.basis.z)
		_strip.queue_redraw()


# The strip itself: a scrolling row of ticks and letters with a marker in the middle and the heading underneath. Everything
# scales with the height, so a bigger compass is a bigger picture.
class CompassStrip extends Control:
	var bearing := 0.0
	var hovered := false

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var k := h / CompassHud.STRIP_HEIGHT
		draw_rect(Rect2(0, 0, w, h), Color(0.06, 0.05, 0.04, 0.72))
		draw_rect(Rect2(0, 0, w, h), Color(0.55, 0.45, 0.28, 0.9), false, maxf(1.0, 1.5 * k))
		var font := ThemeDB.fallback_font
		var half := CompassHud.VISIBLE_DEGREES * 0.5
		var start := int(floor((bearing - half) / 5.0)) * 5
		for deg in range(start, start + int(CompassHud.VISIBLE_DEGREES) + 10, 5):
			var delta := deg - bearing
			if abs(delta) > half:
				continue
			var x := w * 0.5 + (delta / half) * (w * 0.5 - 6.0 * k)
			var norm := posmod(deg, 360)
			var major := norm % 45 == 0
			var mid := norm % 15 == 0
			var tick := (12.0 if major else (8.0 if mid else 4.0)) * k
			var fade := clampf(1.0 - abs(delta) / half * 0.55, 0.35, 1.0)
			draw_line(Vector2(x, h - 13.0 * k), Vector2(x, h - 13.0 * k - tick), Color(0.9, 0.82, 0.6, fade), maxf(1.0, (1.5 if major else 1.0) * k))
			if major:
				var label := CompassHud.cardinal_name(float(norm))
				var is_north := label == "N"
				var fs := int(round((17 if label.length() == 1 else 12) * k))
				var col := Color(0.95, 0.3, 0.25, fade) if is_north else Color(0.98, 0.9, 0.62, fade)
				var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				draw_string(font, Vector2(x - tw * 0.5, 16.0 * k), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		# centre marker + the heading in degrees
		draw_colored_polygon(PackedVector2Array([Vector2(w * 0.5 - 5 * k, 0), Vector2(w * 0.5 + 5 * k, 0), Vector2(w * 0.5, 7 * k)]), Color(1.0, 0.85, 0.35))
		var text := "%s  %d°" % [CompassHud.cardinal_name(bearing), int(round(bearing)) % 360]
		var hs := int(round(11 * k))
		var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, hs)
		draw_string(font, Vector2(w * 0.5 - ts.x * 0.5, h - 2.0 * k), text, HORIZONTAL_ALIGNMENT_LEFT, -1, hs, Color(0.85, 0.78, 0.6))
		# a faint grip in the lower-right corner while the mouse is over it, so the resize handle can be found
		if hovered:
			for i in 3:
				var o := 4.0 + i * 4.0
				draw_line(Vector2(w - o, h - 3.0), Vector2(w - 3.0, h - o), Color(0.85, 0.75, 0.5, 0.8), 1.5)
