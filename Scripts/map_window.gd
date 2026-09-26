# map_window.gd — your map of the zone you're in (M; Cartography, cartography.gd). Drawn on parchment from the zone's own
# terrain (shaded hills, the sea where the land ends), and only where YOU have charted; the rest is blank parchment.
# What it shows grows with your Cartography skill (Cartography.DETAIL): place names and zone borders at 21; camps,
# people, resource nodes and contour lines at 51; patrol routes, rare creatures and hidden places at 76. A compass in
# your bags adds "you are here". Right-click the map to write a note there; right-click a note to rub it out.
class_name MapWindow
extends CanvasLayer

const SIZE := 560                  # the map on screen (px)
const IMAGE := 384                 # the map picture's resolution
const PARCHMENT := Color(0.93, 0.87, 0.72)
const INK := Color(0.30, 0.20, 0.11)
const FADED_INK := Color(0.45, 0.33, 0.20, 0.85)
const SEA := Color(0.66, 0.74, 0.76)
const CONTOUR_M := 4.0

static var _terrain_cache := {}    # zone id -> Image (heights drawn once per zone per session)

var _cart: Cartography
var _frame := {}
var _zone := ""
var _canvas: Control
var _map_rect: TextureRect
var _labels: Array = []            # [uv, text, kind] drawn over the map
var _note_edit: LineEdit = null
var _note_uv := Vector2.ZERO


static func open_for(player: Node) -> void:
	for n in player.get_tree().root.get_children():
		if n is MapWindow:
			n.queue_free()
			return   # M again closes it
	var why := Cartography.why_not()
	if not why.is_empty():
		GameLog.log_general("[color=#cccccc]%s[/color]" % why)
		return
	var w := MapWindow.new()
	w._cart = player.get_node_or_null("Cartography")
	player.get_tree().root.add_child(w)


const POSITION_KEY := "map_window"
const TITLE_H := 28.0
const HINT_H := 30.0
const MARGIN := 10.0
const RESIZE_MARGIN := 16.0
const MIN_SIZE := Vector2(320, 360)

var _panel: Panel
var _title: Label
var _note_button: Button
var _placing_note := false
var _dragging := false
var _resizing := false
var _side := float(SIZE)
var _view_pos := Vector2.ZERO      # the top-left of what's in view, 0..1 of the whole map
var _view_size := 1.0              # how much of the map is in view (1 = all of it; the wheel zooms in to MIN_VIEW)
var _panning := false
const MIN_VIEW := 0.08


# Map 0..1 -> a point on the canvas, and back, through the current zoom and pan.
func _to_screen(uv: Vector2) -> Vector2:
	return (uv - _view_pos) / _view_size * _side


func _to_uv(screen: Vector2) -> Vector2:
	return _view_pos + screen / _side * _view_size


func _clamp_view() -> void:
	_view_size = clampf(_view_size, MIN_VIEW, 1.0)
	_view_pos = Vector2(clampf(_view_pos.x, 0.0, 1.0 - _view_size), clampf(_view_pos.y, 0.0, 1.0 - _view_size))


func _ready() -> void:
	layer = 12
	_zone = ZoneInfo.current_id()
	_frame = _cart.current_frame() if _cart else Cartography.frame_for(get_tree().current_scene, _zone)
	# a window: drag it by the title bar, resize it from the bottom-right corner (remembered, like the other windows)
	_panel = Panel.new()
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.16, 0.11, 0.07, 0.96)
	bg.border_color = Color(0.55, 0.42, 0.24)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(4)
	_panel.add_theme_stylebox_override("panel", bg)
	var vp := get_viewport().get_visible_rect().size
	var w := SIZE + MARGIN * 2
	var h := SIZE + TITLE_H + HINT_H + MARGIN
	_panel.offset_left = (vp.x - w) / 2.0
	_panel.offset_top = (vp.y - h) / 2.0
	_panel.offset_right = _panel.offset_left + w
	_panel.offset_bottom = _panel.offset_top + h
	WindowPosition.load_full_into(POSITION_KEY, _panel)
	_panel.gui_input.connect(_on_panel_input)
	_panel.resized.connect(_layout)
	_panel.draw.connect(func():   # the resize grip, bottom-right
		var c := _panel.size
		_panel.draw_colored_polygon(PackedVector2Array([c - Vector2(3, 14), c - Vector2(3, 3), c - Vector2(14, 3)]), Color(0.55, 0.42, 0.24)))
	add_child(_panel)
	_title = Label.new()
	_title.text = "%s — Cartography %d" % [ZoneInfo.name_for(_zone), Cartography.skill()]
	_title.add_theme_color_override("font_color", Color(0.93, 0.85, 0.62))
	_title.position = Vector2(MARGIN, 5)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_title)
	var close := Button.new()
	close.text = "X"
	close.flat = true
	close.pressed.connect(queue_free)
	close.name = "Close"
	_panel.add_child(close)
	_map_rect = TextureRect.new()   # holds the picture; the canvas draws the part in view (zoom and pan)
	_map_rect.visible = false
	_map_rect.texture = ImageTexture.create_from_image(compose(_zone, _frame, _bits(), Cartography.skill(), get_tree().current_scene))
	_panel.add_child(_map_rect)
	_canvas = Control.new()
	_canvas.clip_contents = true
	_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR   # smooth when zoomed in
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.draw.connect(_draw_overlay)
	_canvas.gui_input.connect(_on_map_input)
	_panel.add_child(_canvas)
	_note_button = Button.new()
	_note_button.text = "Add note"
	_note_button.toggle_mode = true
	_note_button.tooltip_text = "Then click the map where the note goes. (Right-click works too; right-click a note to rub it out.)"
	_note_button.toggled.connect(func(on: bool): _placing_note = on)
	_panel.add_child(_note_button)
	var hint := Label.new()
	hint.name = "Hint"
	hint.text = "Wheel: zoom · drag: move · right-click: note (on a note: rub it out) · M: close"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.75, 0.68, 0.5))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(hint)
	_labels = features(get_tree().current_scene, _zone, _frame, Cartography.skill())
	_layout()


# Fits the map (kept square) and the controls to the window's current size.
func _layout() -> void:
	if not is_instance_valid(_panel) or not is_instance_valid(_map_rect):
		return
	var avail := _panel.size - Vector2(MARGIN * 2, TITLE_H + HINT_H + MARGIN)
	_side = maxf(64.0, minf(avail.x, avail.y))
	var origin := Vector2(MARGIN + (avail.x - _side) / 2.0, TITLE_H)
	_canvas.position = origin
	_canvas.size = Vector2(_side, _side)
	_panel.get_node("Close").position = Vector2(_panel.size.x - 34, 2)
	_note_button.position = Vector2(MARGIN, _panel.size.y - HINT_H + 2)
	_panel.get_node("Hint").position = Vector2(MARGIN + 90, _panel.size.y - HINT_H + 7)
	_panel.queue_redraw()


func _on_panel_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if event.position.x > _panel.size.x - RESIZE_MARGIN and event.position.y > _panel.size.y - RESIZE_MARGIN:
				_resizing = true
			elif event.position.y < TITLE_H:
				_dragging = true
		else:
			if _dragging or _resizing:
				WindowPosition.save(POSITION_KEY, _panel)
			_dragging = false
			_resizing = false
	elif event is InputEventMouseMotion:
		if _dragging:
			_panel.offset_left += event.relative.x
			_panel.offset_top += event.relative.y
			_panel.offset_right += event.relative.x
			_panel.offset_bottom += event.relative.y
		elif _resizing:
			_panel.offset_right = maxf(_panel.offset_left + MIN_SIZE.x, _panel.offset_right + event.relative.x)
			_panel.offset_bottom = maxf(_panel.offset_top + MIN_SIZE.y, _panel.offset_bottom + event.relative.y)


func _bits() -> PackedByteArray:
	return _cart.current_bits() if _cart else Cartography.bits_for(_zone)


func _process(_delta: float) -> void:
	if is_instance_valid(_canvas):
		_canvas.queue_redraw()


# ── The picture ──
# The zone's terrain on parchment (shading, and contours from skill 51), the sea where there is no land, and blank
# parchment wherever this character hasn't charted.
static func compose(zone_id: String, f: Dictionary, bits: PackedByteArray, skill_level: int, zone_root: Node) -> Image:
	var base: Image = _terrain_image(zone_id, f, zone_root, skill_level >= int(Cartography.DETAIL["camps"]))
	var img := Image.create(IMAGE, IMAGE, false, Image.FORMAT_RGBA8)
	for y in IMAGE:
		for x in IMAGE:
			var cx := int(float(x) / IMAGE * Cartography.GRID)
			var cy := int(float(y) / IMAGE * Cartography.GRID)
			var n := 0.93 + 0.07 * _grain(x, y)
			if Cartography.is_revealed(bits, cx, cy):
				img.set_pixel(x, y, base.get_pixel(x, y))
			else:
				img.set_pixel(x, y, Color(PARCHMENT.r * n, PARCHMENT.g * n, PARCHMENT.b * n))
	return img


static func _grain(x: int, y: int) -> float:
	return fposmod(sin(float(x) * 12.9898 + float(y) * 78.233) * 43758.5453, 1.0)


static func _terrain_image(zone_id: String, f: Dictionary, zone_root: Node, contours: bool) -> Image:
	var key := "%s:%s" % [zone_id, contours]
	if _terrain_cache.has(key):
		return _terrain_cache[key]
	var img := Image.create(IMAGE, IMAGE, false, Image.FORMAT_RGBA8)
	var terrain: Node = zone_root.get_node_or_null("Terrain3D") if zone_root != null else null
	var data = terrain.get("data") if terrain != null else null
	var heights := PackedFloat32Array()
	heights.resize(IMAGE * IMAGE)
	for y in IMAGE:
		for x in IMAGE:
			var w := Cartography.to_world(f, Vector2((x + 0.5) / IMAGE, (y + 0.5) / IMAGE))
			heights[y * IMAGE + x] = data.get_height(Vector3(w.x, 0, w.y)) if data != null else 0.0
	for y in IMAGE:
		for x in IMAGE:
			var h := heights[y * IMAGE + x]
			var n := 0.94 + 0.06 * _grain(x, y)
			if is_nan(h):
				img.set_pixel(x, y, Color(PARCHMENT.r * n * 0.97, PARCHMENT.g * n * 0.95, PARCHMENT.b * n * 0.9))   # off the edge of the land
				continue
			var hx := heights[y * IMAGE + mini(x + 1, IMAGE - 1)]
			var hy := heights[mini(y + 1, IMAGE - 1) * IMAGE + x]
			hx = h if is_nan(hx) else hx
			hy = h if is_nan(hy) else hy
			var shade := clampf(0.5 + (h - hx) * 0.18 + (h - hy) * 0.18, 0.0, 1.0)   # hills lit from the north-west
			var c := PARCHMENT.darkened(0.25 * (1.0 - shade)).lightened(0.12 * maxf(shade - 0.5, 0.0))
			if contours and (floor(h / CONTOUR_M) != floor(hx / CONTOUR_M) or floor(h / CONTOUR_M) != floor(hy / CONTOUR_M)):
				c = c.lerp(INK, 0.35)
			img.set_pixel(x, y, Color(c.r * n, c.g * n, c.b * n))
	# walls, buildings and camps in ink
	var ink := _structure_mask(zone_root, f)
	for i in ink.size():
		if ink[i] != 0:
			var px := i % IMAGE
			var py := i / IMAGE
			img.set_pixel(px, py, img.get_pixel(px, py).lerp(INK, 0.85))
	_terrain_cache[key] = img
	return img


# Where the zone's structures stand, one byte per map pixel. Big models (walls, gates: bigger than BIG_M) are traced from
# their steep faces, so a wall is a line, as on an EverQuest map; small ones (tents, stalls, props) are drawn as the
# outline of their footprint. Characters, monsters, NPCs, the terrain, water and sky are left out.
const BIG_M := 30.0
const SKIP_UNDER := ["Terrain3D", "monster_spawner", "RemotePlayers", "CharacterBody3D", "NPCs", "Guards", "Merchants", "WorldEnvironment", "water", "Torches", "Campfires"]

static func _structure_mask(zone_root: Node, f: Dictionary) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(IMAGE * IMAGE)
	if zone_root == null:
		return mask
	for node in zone_root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree() or _skipped(zone_root, mi):
			continue
		var aabb := mi.global_transform * mi.get_aabb()
		if maxf(aabb.size.x, aabb.size.z) > BIG_M and mi.mesh.get_faces().size() < 150000:
			var faces := mi.mesh.get_faces()
			var xf := mi.global_transform
			for i in range(0, faces.size(), 3):
				var a := xf * faces[i]
				var b := xf * faces[i + 1]
				var c := xf * faces[i + 2]
				if absf((b - a).cross(c - a).normalized().y) > 0.5:
					continue   # floors and roofs: only the walls are drawn
				_plot_line(mask, f, Vector2(a.x, a.z), Vector2(b.x, b.z))
				_plot_line(mask, f, Vector2(b.x, b.z), Vector2(c.x, c.z))
		else:
			var corners: Array = []
			for k in 8:
				var p := aabb.get_endpoint(k)
				corners.append(Vector2(p.x, p.z))
			var lo := Vector2(INF, INF)
			var hi := Vector2(-INF, -INF)
			for p in corners:
				lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
				hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
			if hi.x - lo.x < 0.5 and hi.y - lo.y < 0.5:
				continue   # a pebble
			_plot_line(mask, f, lo, Vector2(hi.x, lo.y))
			_plot_line(mask, f, Vector2(hi.x, lo.y), hi)
			_plot_line(mask, f, hi, Vector2(lo.x, hi.y))
			_plot_line(mask, f, Vector2(lo.x, hi.y), lo)
	return mask


static func _skipped(zone_root: Node, n: Node) -> bool:
	var p := n
	while p != null and p != zone_root:
		if SKIP_UNDER.has(str(p.name)) or p is CharacterBody3D or p.is_in_group("held_gear"):
			return true
		p = p.get_parent()
	return false


static func _plot_line(mask: PackedByteArray, f: Dictionary, a: Vector2, b: Vector2) -> void:
	var pa := Cartography.to_map(f, a) * IMAGE
	var pb := Cartography.to_map(f, b) * IMAGE
	var steps := int(maxf(absf(pb.x - pa.x), absf(pb.y - pa.y))) + 1
	if steps > 4 * IMAGE:
		return
	for i in steps + 1:
		var p := pa.lerp(pb, float(i) / steps)
		var x := int(p.x)
		var y := int(p.y)
		if x >= 0 and y >= 0 and x < IMAGE and y < IMAGE:
			mask[y * IMAGE + x] = 1


# ── What the map shows, by skill ──
# [uv, text, kind]: "place", "border", "camp", "person", "resource", "patrol" (text = the next point's uv), "rare", "secret".
static func features(zone_root: Node, zone_id: String, f: Dictionary, skill_level: int) -> Array:
	var out: Array = []
	if zone_root == null:
		return out
	if skill_level >= int(Cartography.DETAIL["landmarks"]):
		for group_name in ["Markers", "Terrain Art"]:
			var g := zone_root.get_node_or_null(group_name)
			if g == null:
				continue
			for n in g.get_children():
				var label := str(n.name)
				if label.contains("_") or label.contains("Tent") or label.contains("Banner") or label.contains("Foundation") \
						or label.contains("(reserved)") or label.contains("Patrol") or label.right(1).is_valid_int():
					continue   # arrival markers (lumora_zone), patrol points (OniPatrol3) and camp dressing
				out.append([Cartography.to_map(f, Vector2(n.global_position.x, n.global_position.z)), label, "place"])
		for line in zone_root.get_tree().get_nodes_in_group("zone_line") if zone_root.is_inside_tree() else zone_root.find_children("*", "Area3D", true, false):
			if not zone_root.is_ancestor_of(line) or str(line.get("target_zone")).is_empty():
				continue
			out.append([Cartography.to_map(f, Vector2(line.global_position.x, line.global_position.z)), "To " + ZoneInfo.name_for(str(line.get("target_zone"))), "border"])
	if skill_level >= int(Cartography.DETAIL["camps"]):
		var npcs := zone_root.get_node_or_null("NPCs")
		if npcs != null:
			for n in npcs.get_children():
				var who := str(n.get("npc_name")) if n.get("npc_name") != null else str(n.name)
				out.append([Cartography.to_map(f, Vector2(n.global_position.x, n.global_position.z)), who, "person"])
		for s in _spawns(zone_id):
			var p: Array = s.get("position", [0, 0, 0])
			var rare: bool = float(s.get("spawn_chance", 1.0)) <= 0.25
			if rare and skill_level < int(Cartography.DETAIL["secrets"]):
				continue
			out.append([Cartography.to_map(f, Vector2(float(p[0]), float(p[2]))), str(s.get("mob_type", "")).replace("_", " ").capitalize(), "rare" if rare else "camp"])
		var placements = JSON.parse_string(FileAccess.get_file_as_string("res://Data/crafting_placements.json"))
		if typeof(placements) == TYPE_DICTIONARY:
			for c in placements.get(zone_id, {}).get("nodes", []):
				var cp: Array = c.get("center", [0, 0])
				out.append([Cartography.to_map(f, Vector2(float(cp[0]), float(cp[1]))), str(c.get("node", "")).replace("_", " ").capitalize(), "resource"])
	if skill_level >= int(Cartography.DETAIL["secrets"]):
		var guards := zone_root.get_node_or_null("Guards")
		if guards != null:
			for g in guards.get_children():
				var wps = g.get("patrol_waypoints")
				if not (wps is Array) or wps.is_empty():
					continue
				var pts: Array = []
				for wp in wps:
					var m: Node = g.get_node_or_null(wp)
					if m is Node3D:
						pts.append(Cartography.to_map(f, Vector2(m.global_position.x, m.global_position.z)))
				for i in pts.size():
					out.append([pts[i], pts[(i + 1) % pts.size()], "patrol"])
		var spots = JSON.parse_string(FileAccess.get_file_as_string("res://Data/perception_spots.json"))
		if typeof(spots) == TYPE_DICTIONARY and spots.get(zone_id) is Array:
			for s in spots[zone_id]:
				var sp: Array = s.get("position", [0, 0])
				out.append([Cartography.to_map(f, Vector2(float(sp[0]), float(sp[1]))), "?", "secret"])
	return out


static func _spawns(zone_id: String) -> Array:
	var path := "res://Data/%s_spawns.json" % zone_id
	if not FileAccess.file_exists(path):
		return []
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(d) == TYPE_DICTIONARY:
		return d.get("spawns", [])
	return d if d is Array else []


# ── Drawing the overlay ──
func _draw_overlay() -> void:
	var tex: Texture2D = _map_rect.texture if is_instance_valid(_map_rect) else null
	if tex != null:
		_canvas.draw_texture_rect_region(tex, Rect2(Vector2.ZERO, Vector2(_side, _side)), Rect2(_view_pos * IMAGE, Vector2.ONE * _view_size * IMAGE))
	var bits := _bits()
	var font := ThemeDB.fallback_font
	var drawn_names := {}
	for feat in _labels:
		var uv: Vector2 = feat[0]
		if not Cartography.is_revealed(bits, int(uv.x * Cartography.GRID), int(uv.y * Cartography.GRID)):
			continue
		var p := _to_screen(uv)
		match str(feat[2]):
			"place":
				_canvas.draw_circle(p, 3.0, INK)
				_canvas.draw_string(font, p + Vector2(5, 4), str(feat[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, INK)
			"border":
				_canvas.draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), Color(0.55, 0.12, 0.08), false, 2.0)
				_canvas.draw_string(font, p + Vector2(7, 4), str(feat[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.55, 0.12, 0.08))
			"person":
				_canvas.draw_circle(p, 2.5, Color(0.15, 0.35, 0.55))
			"camp":
				var key := "%d:%d" % [int(p.x / 14), int(p.y / 14)]   # one mark per camp, not per spawn point
				if drawn_names.has(key):
					continue
				drawn_names[key] = true
				_draw_skull(p, Color(0.45, 0.12, 0.08))
			"rare":
				_draw_skull(p, Color(0.75, 0.05, 0.05))
				_canvas.draw_string(font, p + Vector2(6, 4), str(feat[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.75, 0.05, 0.05))
			"resource":
				_canvas.draw_circle(p, 2.5, Color(0.2, 0.45, 0.15))
			"patrol":
				_canvas.draw_dashed_line(p, _to_screen(feat[1] as Vector2), Color(0.15, 0.3, 0.6, 0.8), 1.5, 5.0)
			"secret":
				_canvas.draw_string(font, p + Vector2(-3, 4), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.45, 0.1, 0.5))
	var notes: Array = Cartography.notes_for(_zone)
	for n in notes:
		var p := _to_screen(Cartography.to_map(_frame, Vector2(float(n[0]), float(n[1]))))
		_canvas.draw_string(font, p + Vector2(-4, 5), "★", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.35, 0.05))
		_canvas.draw_string(font, p + Vector2(8, 4), str(n[2]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.45, 0.25, 0.05))
	# you are here: only with a compass (it tells you which way you face, too)
	var me := TargetFrame.local_player()
	if is_instance_valid(me) and ItemHelper.count(Cartography.COMPASS) > 0:
		var p := _to_screen(Cartography.to_map(_frame, Vector2(me.global_position.x, me.global_position.z)))
		var fwd3: Vector3 = -me.global_transform.basis.z
		var fwd := Vector2(fwd3.x, fwd3.z)
		var dir := Vector2(fwd.dot(_frame["east"]), -fwd.dot(_frame["north"])).normalized()
		var side := Vector2(-dir.y, dir.x)
		_canvas.draw_colored_polygon(PackedVector2Array([p + dir * 9, p - dir * 5 + side * 5, p - dir * 2, p - dir * 5 - side * 5]), Color(0.7, 0.1, 0.05))


func _draw_skull(p: Vector2, c: Color) -> void:
	_canvas.draw_circle(p, 4.0, c)
	_canvas.draw_circle(p + Vector2(-1.5, -0.5), 1.0, PARCHMENT)
	_canvas.draw_circle(p + Vector2(1.5, -0.5), 1.0, PARCHMENT)


# ── Notes ──
func _on_map_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var at := _to_uv(event.position)   # zoom around the cursor
		_view_size *= 0.8 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.25
		_clamp_view()
		_view_pos = at - event.position / _side * _view_size
		_clamp_view()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not _placing_note:
		_panning = event.pressed
		return
	if event is InputEventMouseMotion and _panning:
		_view_pos -= event.relative / _side * _view_size
		_clamp_view()
		return
	if not (event is InputEventMouseButton and event.pressed):
		return
	var placing: bool = event.button_index == MOUSE_BUTTON_LEFT and _placing_note
	if not (event.button_index == MOUSE_BUTTON_RIGHT or placing):
		return
	var uv: Vector2 = _to_uv(event.position)
	if event.button_index == MOUSE_BUTTON_RIGHT:
		var notes: Array = Cartography.notes_for(_zone)
		for i in notes.size():
			var p := _to_screen(Cartography.to_map(_frame, Vector2(float(notes[i][0]), float(notes[i][1]))))
			if p.distance_to(event.position) < 8.0:
				if _cart:
					_cart.remove_note(i)
				return
	_placing_note = false
	_note_button.button_pressed = false
	_note_uv = uv
	if is_instance_valid(_note_edit):
		_note_edit.queue_free()
	_note_edit = LineEdit.new()
	_note_edit.placeholder_text = "Write a note, then Enter"
	_note_edit.max_length = 60
	_note_edit.position = event.position + Vector2(8, -12)
	_note_edit.custom_minimum_size = Vector2(200, 0)
	_canvas.add_child(_note_edit)
	_note_edit.grab_focus()
	_note_edit.text_submitted.connect(func(text: String):
		if not text.strip_edges().is_empty() and _cart:
			_cart.add_note(Cartography.to_world(_frame, _note_uv), text)
		_note_edit.queue_free())
