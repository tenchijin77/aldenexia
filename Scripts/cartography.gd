# cartography.gd — the Cartography skill and your maps (the Game Systems notes, section 6; test 39: "you start with no
# map, just like in life. You need to earn the money for the skill (scroll) and items needed to use it").
#
#   * Learn the skill from a Scroll of Cartography, and carry Blank Parchment and a Charcoal Stick (bought once, kept).
#     Then, as you walk, the land around you (REVEAL_RADIUS) is drawn onto your map of that zone: fog of war, per
#     character, per zone, saved with the character (Global.player_data "maps": a bit per cell of a GRID x GRID square).
#   * Charting new ground raises the skill (0-100; Woodstalkers learn it fastest, Shadowblades and Troubadours next).
#     The skill decides what your map shows (DETAIL): terrain only; then landmark names and zone borders; then camps,
#     resource nodes, people and contour lines; then patrol routes, rare spawns and hidden places.
#   * A compass in your bags adds "you are here". Your own notes (right-click the map) stay where you put them.
#   * M opens it (map_window.gd).
# A child of every Player3D; only the local player's copy does anything.
class_name Cartography
extends Node

const SKILL := "cartography"
const SKILL_CAP := 100
const GRID := 128                  # cells across the zone's map square
const REVEAL_RADIUS := 45.0        # metres of land you chart around you
const TICK := 1.0
const SAVE_EVERY := 20.0
const PARCHMENT := "blank_parchment"
const CHARCOAL := "charcoal_stick"
const COMPASS := "compass"
const CLASS_GAIN := {"Woodstalker": 1.10, "Shadowblade": 1.05, "Troubadour": 1.05}
const DETAIL := {"landmarks": 21, "camps": 51, "secrets": 76}   # the skill each layer needs

var _player: Node = null
var _timer := 0.0
var _save_timer := 0.0
var _dirty := false
var _zone := ""
var _bits := PackedByteArray()
var _frame := {}


func _ready() -> void:
	_player = get_parent()


func _process(delta: float) -> void:
	if not (is_instance_valid(_player) and _player.is_multiplayer_authority()) or Net.is_dedicated_server:
		return
	_timer += delta
	_save_timer += delta
	if _timer < TICK:
		return
	_timer = 0.0
	if not can_chart():
		return
	_load_zone()
	var p: Vector3 = (_player as Node3D).global_position
	var fresh := reveal(_bits, _frame, Vector2(p.x, p.z), REVEAL_RADIUS)
	if fresh > 0:
		_dirty = true
		_try_skill_up(minf(fresh, 6.0) / 6.0)
	if _dirty and _save_timer >= SAVE_EVERY:
		save()


# ── What you need ──
static func knows_skill() -> bool:
	var levels = Global.player_data.get("skill_levels", {})
	return typeof(levels) == TYPE_DICTIONARY and levels.has(SKILL)


static func has_kit() -> bool:
	return ItemHelper.count(PARCHMENT) > 0 and ItemHelper.count(CHARCOAL) > 0


static func can_chart() -> bool:
	return knows_skill() and has_kit()


static func skill() -> int:
	var levels = Global.player_data.get("skill_levels", {})
	return int(levels.get(SKILL, 0)) if typeof(levels) == TYPE_DICTIONARY else 0


# Why you can't open a map, or "" if you can.
static func why_not() -> String:
	if not knows_skill():
		return "You don't know how to draw a map. A Cartographer can teach you (Lumora's Cartographer sells the scroll)."
	if not has_kit():
		return "You need Blank Parchment and a Charcoal Stick in your bags to keep a map."
	return ""


# ── The map square for a zone ──
# center / half (metres) in world XZ; north and east unit vectors (Data/compass.json: the Outskirts' north is +X).
static func frame_for(zone_root: Node, zone_id: String) -> Dictionary:
	var north := Vector2(0, -1)
	var cfg = JSON.parse_string(FileAccess.get_file_as_string("res://Data/compass.json")) if FileAccess.file_exists("res://Data/compass.json") else {}
	if typeof(cfg) == TYPE_DICTIONARY:
		# compass.json is keyed by the zone scene's file name (as compass_hud.gd reads it), or the zone id
		var scene_key := str(zone_root.scene_file_path).get_file().get_basename() if zone_root != null else ""
		var zones: Dictionary = cfg.get("zones", {})
		var entry = zones.get(scene_key, zones.get(zone_id, cfg.get("default", {"north": [0, -1]})))
		var n: Array = entry.get("north", [0, -1])
		north = Vector2(float(n[0]), float(n[1])).normalized()
	var east := Vector2(-north.y, north.x)
	var lo := Vector2(-512, -512)
	var hi := Vector2(512, 512)
	var terrain: Node = zone_root.get_node_or_null("Terrain3D") if zone_root != null else null
	if terrain != null and terrain.get("data") != null:
		var size: float = float(terrain.get("region_size")) * float(terrain.get("vertex_spacing"))
		var locs: Array = terrain.data.get_region_locations()
		if not locs.is_empty():
			lo = Vector2(INF, INF)
			hi = Vector2(-INF, -INF)
			for l in locs:
				lo = Vector2(minf(lo.x, l.x * size), minf(lo.y, l.y * size))
				hi = Vector2(maxf(hi.x, (l.x + 1) * size), maxf(hi.y, (l.y + 1) * size))
	# only the playable part (zone_boundary.gd's limits: the Outskirts' north wall at x 118)
	var edge: Node = zone_root.get_node_or_null("ZoneBoundary") if zone_root != null else null
	if edge != null:
		lo = Vector2(maxf(lo.x, float(edge.get("limit_min_x"))), maxf(lo.y, float(edge.get("limit_min_z"))))
		hi = Vector2(minf(hi.x, float(edge.get("limit_max_x"))), minf(hi.y, float(edge.get("limit_max_z"))))
	var center := (lo + hi) * 0.5
	var half := maxf(hi.x - lo.x, hi.y - lo.y) * 0.5
	return {"center": center, "half": half, "north": north, "east": east}


# World XZ -> map 0..1 (u east, v south: north is up) and back.
static func to_map(f: Dictionary, p: Vector2) -> Vector2:
	var d: Vector2 = p - f["center"]
	return Vector2((d.dot(f["east"]) / f["half"] + 1.0) * 0.5, (-d.dot(f["north"]) / f["half"] + 1.0) * 0.5)


static func to_world(f: Dictionary, uv: Vector2) -> Vector2:
	return f["center"] + f["east"] * ((uv.x * 2.0 - 1.0) * f["half"]) - f["north"] * ((uv.y * 2.0 - 1.0) * f["half"])


# ── Fog of war: one bit per cell ──
static func empty_bits() -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(GRID * GRID / 8)
	return b


static func is_revealed(bits: PackedByteArray, cx: int, cy: int) -> bool:
	if cx < 0 or cy < 0 or cx >= GRID or cy >= GRID or bits.is_empty():
		return false
	var i := cy * GRID + cx
	return (bits[i >> 3] >> (i & 7)) & 1 == 1


# Charts the cells within `radius` metres of world point `p`. Returns how many were new.
static func reveal(bits: PackedByteArray, f: Dictionary, p: Vector2, radius: float) -> int:
	var uv := to_map(f, p)
	var cell_m: float = f["half"] * 2.0 / GRID
	var r := int(ceil(radius / cell_m))
	var cx := int(uv.x * GRID)
	var cy := int(uv.y * GRID)
	var fresh := 0
	for y in range(cy - r, cy + r + 1):
		for x in range(cx - r, cx + r + 1):
			if x < 0 or y < 0 or x >= GRID or y >= GRID:
				continue
			if Vector2(x - cx, y - cy).length() * cell_m > radius:
				continue
			var i := y * GRID + x
			if (bits[i >> 3] >> (i & 7)) & 1 == 0:
				bits[i >> 3] |= 1 << (i & 7)
				fresh += 1
	return fresh


static func bits_for(zone_id: String) -> PackedByteArray:
	var maps = Global.player_data.get("maps", {})
	if typeof(maps) == TYPE_DICTIONARY and maps.has(zone_id):
		var b := Marshalls.base64_to_raw(str(maps[zone_id]))
		if b.size() == GRID * GRID / 8:
			return b
	return empty_bits()


func _load_zone() -> void:
	var id := ZoneInfo.current_id()
	if id == _zone and not _bits.is_empty():
		return
	if _dirty:
		save()
	_zone = id
	_bits = bits_for(id)
	_frame = frame_for(get_tree().current_scene, id)


func save() -> void:
	if _zone.is_empty() or _bits.is_empty():
		return
	if typeof(Global.player_data.get("maps")) != TYPE_DICTIONARY:
		Global.player_data["maps"] = {}
	Global.player_data["maps"][_zone] = Marshalls.raw_to_base64(_bits)
	_dirty = false
	_save_timer = 0.0
	Global.save_player_data_to_file()


# The map window reads the live copy (so what you just walked is on it).
func current_bits() -> PackedByteArray:
	_load_zone()
	return _bits


func current_frame() -> Dictionary:
	_load_zone()
	return _frame


# ── The skill ──
# Charting new ground (or adding a note) is the only way it rises; `amount` 0..1 scales the chance.
func _try_skill_up(amount: float) -> void:
	var cur := skill()
	if cur >= SKILL_CAP:
		return
	var chance: float = 0.15 * (1.0 - float(cur) / SKILL_CAP) * amount * float(CLASS_GAIN.get(str(_player.get("player_class")), 1.0))
	chance *= float(_player.get("race_skill_gain_mult")) if _player.get("race_skill_gain_mult") != null else 1.0
	if randf() < chance:
		raise_skill()


func raise_skill() -> void:
	var levels: Dictionary = _player.skill_levels
	levels[SKILL] = mini(int(levels.get(SKILL, 0)) + 1, SKILL_CAP)
	Global.player_data["skill_levels"] = levels
	GameLog.log_general("You've become better at [b]Cartography[/b]! (%d)" % levels[SKILL])
	var n := int(levels[SKILL])
	for layer in DETAIL:
		if n == int(DETAIL[layer]):
			GameLog.log_general("[color=#e8d8a8]Your maps grow more detailed: %s.[/color]" % {"landmarks": "place names, roads between zones", "camps": "camps, people, resources and the lie of the land", "secrets": "patrols, rare creatures and hidden places"}[layer])


# ── Your notes ──
static func notes_for(zone_id: String) -> Array:
	var all = Global.player_data.get("map_notes", {})
	return all.get(zone_id, []) if typeof(all) == TYPE_DICTIONARY else []


func add_note(world: Vector2, text: String) -> void:
	var zone := ZoneInfo.current_id()
	if typeof(Global.player_data.get("map_notes")) != TYPE_DICTIONARY:
		Global.player_data["map_notes"] = {}
	var list: Array = Global.player_data["map_notes"].get(zone, [])
	list.append([snappedf(world.x, 0.1), snappedf(world.y, 0.1), text.strip_edges().substr(0, 60)])
	Global.player_data["map_notes"][zone] = list
	_try_skill_up(1.0)
	Global.save_player_data_to_file()


func remove_note(index: int) -> void:
	var zone := ZoneInfo.current_id()
	var list: Array = notes_for(zone)
	if index >= 0 and index < list.size():
		list.remove_at(index)
		Global.player_data["map_notes"][zone] = list
		Global.save_player_data_to_file()
