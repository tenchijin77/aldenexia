# weather_manager.gd — Random, infrequent rain for an outdoor zone.
#
# Lives in the zone scene next to DayNightCycle. The HOST (or single-player)
# decides when it rains — a random quiet spell (min/max_clear_seconds) followed
# by a random shower (min/max_rain_seconds) — and syncs each change to every
# peer over an RPC; peers joining mid-shower are told silently. Visuals are all
# driven by one smoothed `intensity` (0..1) so rain fades in and out instead of
# popping: a falling-rain particle box that follows the local player, haze
# (fog), dimmer/greyer sky + light (via DayNightCycle.set_weather_dim()), and a
# looping rain sound. All timings/text are @exports — edit them on the scene.
extends Node
class_name WeatherManager

signal rain_changed(raining: bool)

@export_group("Schedule (real-time seconds)")
@export var min_clear_seconds: float = 600.0
@export var max_clear_seconds: float = 1500.0
@export var min_rain_seconds: float = 120.0
@export var max_rain_seconds: float = 300.0
@export var fade_in_seconds: float = 12.0
@export var fade_out_seconds: float = 18.0

@export_group("Look")
@export var rain_amount: int = 3500
@export var fog_density_at_full: float = 0.006
@export var fog_color: Color = Color(0.5, 0.55, 0.62)
## Rain-loop volume (dB) at full intensity, on the SFX bus.
@export var rain_volume_db: float = -6.0
## How much quieter the rain sounds while you stand under a roof (dB).
@export var sheltered_volume_drop_db: float = 9.0

@export_group("Chat text")
@export var rain_start_text: String = "It begins to rain..."
## Chat message when the rain stops (leave empty for none).
@export var rain_stop_text: String = "The clear sky begins to break from behind the clouds..."

@export_group("Nodes / assets")
@export var day_night_path: NodePath = ^"../DayNightCycle"
@export var world_environment_path: NodePath = ^"../WorldEnvironment"
@export var rain_sound: AudioStream = preload("res://Assets/sounds/ambient/rain_loop.mp3")

const RAIN_TILT_MIN := 0.12      # slant of the rain: horizontal speed / fall speed, rolled per rain
const RAIN_TILT_MAX := 0.55
const RAIN_MEAN_SPEED := 23.0    # initial speed of a drop (Data: pm.initial_velocity 20..26)
const RAIN_MEAN_FALL := 28.0     # about its average downward speed over its fall (initial + gravity), for the streak's angle
const RAIN_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 rain_color : source_color = vec4(0.78, 0.86, 1.0, 0.5);
uniform vec3 fall_dir = vec3(0.0, -1.0, 0.0);
uniform sampler2D cover_tex : filter_nearest, repeat_disable;
uniform vec2 grid_origin = vec2(0.0);
uniform float grid_span = 40.0;

varying vec3 wpos;

void vertex() {
	// Long axis along the fall direction, turned to face the camera around that axis.
	vec3 axis = -normalize(fall_dir);
	vec3 centre = MODEL_MATRIX[3].xyz;
	vec3 to_cam = normalize(INV_VIEW_MATRIX[3].xyz - centre);
	vec3 side = cross(axis, to_cam);
	side = length(side) < 0.001 ? INV_VIEW_MATRIX[0].xyz : normalize(side);
	vec3 face = cross(side, axis);
	mat4 m = mat4(vec4(side, 0.0), vec4(axis, 0.0), vec4(face, 0.0), vec4(centre, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * m;
	wpos = (m * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = (wpos.xz - grid_origin) / grid_span;
	if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) {
		float roof = texture(cover_tex, uv).r;
		if (wpos.y < roof) {
			discard;
		}
	}
	ALBEDO = rain_color.rgb;
	ALPHA = rain_color.a;
}
"""

var raining: bool = false
var intensity: float = 0.0

var _time_to_next_change: float = 0.0
var _day_night: Node = null
var _environment: Environment = null
var _orig_fog_enabled: bool = false
var _orig_fog_density: float = 0.01
var _orig_fog_color: Color = Color.WHITE
var _rain: GPUParticles3D = null
var _rain_material: ShaderMaterial = null
var _cover := RainCover.new()
var _wind_seed := 0
var _wind_horizontal := Vector2.ZERO   # horizontal fall speed (m/s, x/z): the wind of this rain, rolled each time rain starts
var _sound: AudioStreamPlayer = null
var _sheltered := false
var _shelter_timer := 0.0
var _shelter_drop_db := 0.0   # smoothed


func _ready() -> void:
	add_to_group("weather_manager")
	_day_night = get_node_or_null(day_night_path)
	var world_env := get_node_or_null(world_environment_path) as WorldEnvironment
	if world_env and world_env.environment:
		_environment = world_env.environment
		_orig_fog_enabled = _environment.fog_enabled
		_orig_fog_density = _environment.fog_density
		_orig_fog_color = _environment.fog_light_color
	_build_rain_particles()
	_build_sound()
	_time_to_next_change = randf_range(min_clear_seconds, max_clear_seconds)
	if Net.is_multiplayer_game and multiplayer.is_server():
		Net.player_connected.connect(_on_peer_connected)


# ── Control ────────────────────────────────────────────────────────────────
# Host / single-player only. Applies locally with the chat message and tells
# every other peer. Also used by the /weather test command.
func set_weather(on: bool) -> void:
	if not is_multiplayer_authority():
		return
	var seed := randi()   # the wind of this rain: every peer derives the same direction and slant from it
	_apply_raining(on, true, seed)
	_time_to_next_change = randf_range(min_rain_seconds, max_rain_seconds) if on \
			else randf_range(min_clear_seconds, max_clear_seconds)
	if Net.is_multiplayer_game and multiplayer.has_multiplayer_peer():
		_rpc_set_raining.rpc(on, true, seed)


@rpc("authority", "call_remote", "reliable")
func _rpc_set_raining(on: bool, announce: bool, wind_seed: int) -> void:
	_apply_raining(on, announce, wind_seed)


func _on_peer_connected(peer_id: int) -> void:
	if raining:
		_rpc_set_raining.rpc_id(peer_id, true, false, _wind_seed)  # silent — they just arrived


func _apply_raining(on: bool, announce: bool, wind_seed: int = 0) -> void:
	if on == raining:
		return
	raining = on
	if on:
		_roll_wind(wind_seed)
	if announce:
		var text := rain_start_text if on else rain_stop_text
		if not text.is_empty():
			GameLog.log_general("[color=#9fc5e8]%s[/color]" % text)
	rain_changed.emit(on)


# A new wind for every rain: a random compass direction and a random slant (RAIN_TILT_MIN..MAX = horizontal / vertical speed).
func _roll_wind(wind_seed: int) -> void:
	_wind_seed = wind_seed
	var rng := RandomNumberGenerator.new()
	rng.seed = wind_seed
	var angle := rng.randf() * TAU
	var tilt := rng.randf_range(RAIN_TILT_MIN, RAIN_TILT_MAX)
	var fall_speed := RAIN_MEAN_SPEED * 1.0
	_wind_horizontal = Vector2(sin(angle), cos(angle)) * tilt * fall_speed
	if _rain == null:
		return
	var direction := Vector3(_wind_horizontal.x, -fall_speed, _wind_horizontal.y).normalized()
	(_rain.process_material as ParticleProcessMaterial).direction = direction
	_rain_material.set_shader_parameter("fall_dir", Vector3(_wind_horizontal.x, -RAIN_MEAN_FALL, _wind_horizontal.y).normalized())


# ── Per-frame ──────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if is_multiplayer_authority():
		_time_to_next_change -= delta
		if _time_to_next_change <= 0.0:
			set_weather(not raining)

	var target := 1.0 if raining else 0.0
	if intensity != target:
		var fade := fade_in_seconds if raining else fade_out_seconds
		intensity = move_toward(intensity, target, delta / maxf(fade, 0.1))
	_apply_visuals()


func _apply_visuals() -> void:
	var active := intensity > 0.01
	if _day_night and _day_night.has_method("set_weather_dim"):
		_day_night.set_weather_dim(intensity)

	if _environment:
		_environment.fog_enabled = active or _orig_fog_enabled
		if active:
			var daylight: float = _day_night.get_daylight() if _day_night and _day_night.has_method("get_daylight") else 1.0
			_environment.fog_light_color = fog_color * lerpf(0.12, 1.0, daylight)
			_environment.fog_density = fog_density_at_full * intensity
		else:
			_environment.fog_density = _orig_fog_density
			_environment.fog_light_color = _orig_fog_color

	if _rain:
		_rain.emitting = active
		_rain.amount_ratio = clampf(intensity, 0.05, 1.0)
		var p := TargetFrame.local_player()
		if is_instance_valid(p):
			# Wind carries the drops sideways during their fall: start the box upwind so they land around the player.
			_rain.global_position = p.global_position + Vector3(-_wind_horizontal.x, 0.0, -_wind_horizontal.y) * 0.45 + Vector3(0, 13, 0)
			if active:
				_cover.update(p.get_world_3d().direct_space_state, p.global_position)
				_rain_material.set_shader_parameter("grid_origin", _cover.origin)
			_shelter_timer -= get_process_delta_time()
			if active and _shelter_timer <= 0.0:
				_shelter_timer = 0.3
				_sheltered = _is_under_cover(p)

	if _sound:
		if active:
			if not _sound.playing:
				_sound.play()
			_shelter_drop_db = move_toward(_shelter_drop_db, sheltered_volume_drop_db if _sheltered else 0.0, 30.0 * get_process_delta_time())
			_sound.volume_db = rain_volume_db + linear_to_db(maxf(intensity, 0.001)) - _shelter_drop_db
		elif _sound.playing:
			_sound.stop()


# True when something solid is overhead within 30 m (a roof, an arch, a ledge): the rain sound is muffled there.
func _is_under_cover(player: Node3D) -> bool:
	var space := player.get_world_3d().direct_space_state
	var from := player.global_position + Vector3(0, 1.7, 0)
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, 30, 0))
	query.exclude = [player]
	return not space.intersect_ray(query).is_empty()


# ── Construction ───────────────────────────────────────────────────────────
func _build_rain_particles() -> void:
	_rain = GPUParticles3D.new()
	_rain.name = "Rain"
	_rain.amount = rain_amount
	_rain.lifetime = 0.9
	_rain.emitting = false
	_rain.local_coords = false  # drops stay where they fell as the player moves
	_rain.visibility_aabb = AABB(Vector3(-25, -30, -25), Vector3(50, 40, 50))
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(16, 0.1, 16)
	pm.direction = Vector3(0.08, -1, 0.04)
	pm.spread = 2.0
	pm.initial_velocity_min = 20.0
	pm.initial_velocity_max = 26.0
	pm.gravity = Vector3(0, -12, 0)
	_rain.process_material = pm

	# The streak: a thin quad drawn by RAIN_SHADER, which (1) turns it along the way it is falling (the wind slants it), and
	# (2) hides the part of it that is below a roof, an arch or a wall: RainCover keeps a small height map of what is overhead
	# (physics rays, cached: the level does not move), so it does not rain indoors and rain everywhere else is untouched.
	var streak := QuadMesh.new()
	streak.size = Vector2(0.012, 0.55)
	var shader := Shader.new()
	shader.code = RAIN_SHADER
	_rain_material = ShaderMaterial.new()
	_rain_material.shader = shader
	_rain_material.set_shader_parameter("cover_tex", _cover.texture)
	_rain_material.set_shader_parameter("grid_span", RainCover.N * RainCover.CELL)
	streak.material = _rain_material
	_rain.draw_pass_1 = streak
	add_child(_rain)


func _build_sound() -> void:
	if rain_sound == null:
		return
	if rain_sound is AudioStreamMP3:
		(rain_sound as AudioStreamMP3).loop = true  # import setting is off
	_sound = AudioStreamPlayer.new()
	_sound.name = "RainLoop"
	_sound.stream = rain_sound
	_sound.bus = &"SFX"
	_sound.volume_db = -80.0
	add_child(_sound)


# What is overhead, as a small height map around the player: for every 1.25 m cell, the height of the highest solid surface if it is
# at least 1.8 m above the lowest one in that column (a roof, an arch, a wall, a ledge), else "none". Found with vertical physics rays
# against the level's static collision (creatures are skipped) and CACHED per world cell, since the level does not move: each cell is probed
# once, a few hundred per frame at most, so it costs nothing after the first moments. The rain shader reads it to hide drops below it.
class RainCover extends RefCounted:
	const CELL := 1.25
	const N := 32
	const NONE := -1000.0
	const MIN_HEIGHT := 1.8
	const PER_UPDATE := 250

	var origin := Vector2.ZERO          # world x/z of the texture's corner
	var texture: ImageTexture
	var _image: Image
	var _cache: Dictionary = {}         # Vector2i cell -> covering height (or NONE)
	var _last_key := Vector2i(1 << 30, 1 << 30)
	var _pending := 0                   # cells in the window that are still unknown

	func _init() -> void:
		_image = Image.create(N, N, false, Image.FORMAT_RF)
		_image.fill(Color(NONE, 0.0, 0.0, 1.0))
		texture = ImageTexture.create_from_image(_image)

	func update(space: PhysicsDirectSpaceState3D, centre: Vector3) -> void:
		var cx := int(floor(centre.x / CELL)) - N / 2
		var cz := int(floor(centre.z / CELL)) - N / 2
		var key := Vector2i(cx, cz)
		if key == _last_key and _pending == 0:
			return
		_last_key = key
		origin = Vector2(cx * CELL, cz * CELL)
		var budget := PER_UPDATE
		_pending = 0
		for iz in N:
			for ix in N:
				var cell := Vector2i(cx + ix, cz + iz)
				var value: float = NONE
				if _cache.has(cell):
					value = _cache[cell]
				elif budget > 0:
					value = _probe(space, (cell.x + 0.5) * CELL, (cell.y + 0.5) * CELL, centre.y)
					_cache[cell] = value
					budget -= 1
				else:
					_pending += 1
				_image.set_pixel(ix, iz, Color(value, 0.0, 0.0, 1.0))
		texture.update(_image)

	func _probe(space: PhysicsDirectSpaceState3D, x: float, z: float, ref_y: float) -> float:
		var surfaces: Array[float] = []
		var y := ref_y + 45.0
		var bottom := ref_y - 45.0
		for i in 8:
			var hit := Global.ground_ray(space, PhysicsRayQueryParameters3D.create(Vector3(x, y, z), Vector3(x, bottom, z)))
			if hit.is_empty():
				break
			y = hit.position.y - 0.02
			if hit.collider is StaticBody3D:
				surfaces.append(hit.position.y)
		if surfaces.size() >= 2 and surfaces[0] - surfaces[surfaces.size() - 1] >= MIN_HEIGHT:
			return surfaces[0]
		return NONE
