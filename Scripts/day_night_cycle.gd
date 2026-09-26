# day_night_cycle.gd
# Drives the outdoor zone's sun (DirectionalLight3D) and sky/ambient lighting.
# Phase/progress are derived directly from Global.game_time (single source of
# truth) rather than an independent timer, so the sky and the /time command
# always agree. Global runs at 1 real second = 1 game minute over a standard
# 24-hour day (6:00-21:00 day, 21:00-6:00 night) — 15 real minutes of day
# (the last in-game hour blending into dusk) and 9 of night. See Global.gd's
# HOURS_PER_DAY/DAY_START_HOUR/DAY_END_HOUR consts.
class_name DayNightCycle
extends Node

signal phase_changed(is_day: bool)

@export var sun_path: NodePath = ^"../DirectionalLight3D"
@export var world_environment_path: NodePath = ^"../WorldEnvironment"

@export_range(0.0, 0.49) var dawn_dusk_fraction: float = 0.0667  # portion of the day spent ramping in/out of full brightness at each end (~1 in-game hour out of the 15h day, e.g. dusk ~20:00-21:00)

@export_group("Sun (day)")
@export var sun_yaw_degrees: float = 35.0
@export var sun_min_altitude_degrees: float = -5.0
@export var sun_max_altitude_degrees: float = 80.0
@export var sun_edge_energy: float = 0.15   # light energy right at sunrise/sunset
@export var sun_peak_energy: float = 1.3    # light energy at noon
@export var sun_edge_color: Color = Color(1.0, 0.62, 0.38)  # warm dawn/dusk tint
@export var sun_noon_color: Color = Color(1.0, 0.98, 0.92)
## The sun crosses the sky: from sun_yaw - arc/2 at sunrise to sun_yaw + arc/2 at sunset (shadows turn through the day).
@export var sun_arc_degrees: float = 140.0

@export_group("Moon (night)")
@export var moon_rotation_degrees: Vector3 = Vector3(-55.0, 200.0, 0.0)
@export var moon_energy: float = 0.16  # was 0.04 (too dim to see by), then 0.25 (too bright per user 2026-09-17) — still a fraction of sun_peak_energy
@export var moon_color: Color = Color(0.55, 0.65, 0.95)
## The moon crosses the sky at night too (around moon_rotation_degrees' yaw), highest at midnight.
@export var moon_arc_degrees: float = 120.0
@export var moon_min_altitude_degrees: float = 12.0
## One cycle of the moon's phases, in real days: a new moon (the dark moon) every MOON_CYCLE_DAYS (the dark moon tally is
## fortnightly, Development page part 1).
const MOON_CYCLE_DAYS := 14.0
const SKY_SHADER := "res://Shaders/sky.gdshader"

@export_group("Sky / Ambient")
@export var day_sky_top_color: Color = Color(0.22986513, 0.3887299, 0.9202023)
@export var day_sky_horizon_color: Color = Color(0.62, 0.65, 0.71)
@export var night_sky_top_color: Color = Color(0.01, 0.015, 0.04)
@export var night_sky_horizon_color: Color = Color(0.03, 0.035, 0.07)
@export var day_ambient_energy: float = 1.0
@export var night_ambient_energy: float = 0.11  # was 0.05 (too dim), then 0.18 (too bright per user 2026-09-17) — same reasoning as moon_energy

@export_group("Weather (driven by weather_manager.gd)")
@export var overcast_light_scale: float = 0.55   # sun/moon + ambient energy multiplier at full rain
@export var overcast_sky_color: Color = Color(0.36, 0.39, 0.44)  # daytime sky colour under full rain

@export_group("Dark Sight (races with the trait — local viewer only)")
## Dark Sight / Improved Dark Sight: outdoors at night, dim light counts as bright light. Only this
## machine's own rendering is changed (each client runs its own day/night), so
## it only ever affects the viewer who actually has the trait. Set false on a
## lightless interior/dungeon scene — with nothing to amplify it does nothing
## ("Deep Darkness"). Zones without a DayNightCycle at all get no boost either.
@export var outdoors: bool = true
## These four are the FULL-strength (Improved Dark Sight) look; plain Dark Sight uses dark_sight_basic_strength of it.
@export var dark_sight_night_ambient_energy: float = 0.8
@export var dark_sight_moon_energy_multiplier: float = 3.0
@export var dark_sight_sky_top_color: Color = Color(0.20, 0.30, 0.55)
@export var dark_sight_sky_horizon_color: Color = Color(0.30, 0.35, 0.50)
@export_range(0.0, 1.0) var dark_sight_basic_strength: float = 0.5

enum Phase { DAY, NIGHT }
var dark_sight_strength: float = 0.0  # local player's race: 0 none, dark_sight_basic_strength = Dark Sight, 1 = Improved Dark Sight
var weather_dim: float = 0.0  # 0 = clear, 1 = full rain; set via set_weather_dim()

var phase: int = Phase.DAY
var progress: float = 0.0  # 0..1 through the current phase

var _sun: DirectionalLight3D
var _sky_material: ProceduralSkyMaterial
var _sky_shader: ShaderMaterial   # Shaders/sky.gdshader: sun, moon with its phases, stars, clouds (test 39)
var _environment: Environment


func _ready() -> void:
	add_to_group("day_night_cycle")
	_sun = get_node_or_null(sun_path)
	var world_env: WorldEnvironment = get_node_or_null(world_environment_path)
	if world_env:
		_environment = world_env.environment
		if _environment and _environment.sky:
			# A stripped dedicated-server export swaps materials for placeholders (nothing is drawn there anyway),
			# so only keep the sky material if it is the real thing.
			var sky_mat := _environment.sky.sky_material
			if sky_mat is ProceduralSkyMaterial:
				_sky_material = sky_mat
				if ResourceLoader.exists(SKY_SHADER) and DisplayServer.get_name() != "headless":
					# the zone's plain gradient becomes the full sky; the gradient's colours carry over
					_sky_shader = ShaderMaterial.new()
					_sky_shader.shader = load(SKY_SHADER)
					_environment.sky = _environment.sky.duplicate()   # the zone scenes share one Sky resource
					_environment.sky.sky_material = _sky_shader
					_environment.sky.process_mode = Sky.PROCESS_MODE_REALTIME   # the clouds drift and the stars twinkle
					_environment.sky.radiance_size = Sky.RADIANCE_SIZE_256
					_sky_shader.set_shader_parameter("ground_color", sky_mat.ground_bottom_color)
	Global.time_changed.connect(_on_global_time_changed)
	_refresh_dark_sight()
	_on_global_time_changed(Global.game_time)


# Reads the trait straight from the race data (character_options.json
# races.<race>.traits.improved_dark_sight / dark_sight) for the LOCAL player's race.
func _refresh_dark_sight() -> void:
	var race := str(Global.player_data.get("player_race", "")).to_lower().replace(" ", "_").replace("-", "_")
	var traits: Dictionary = Global.character_options.get("races", {}).get(race, {}).get("traits", {})
	if bool(traits.get("improved_dark_sight", false)):
		dark_sight_strength = 1.0
	elif bool(traits.get("dark_sight", false)):
		dark_sight_strength = dark_sight_basic_strength
	else:
		dark_sight_strength = 0.0
	# A Night-Eye Draught (Alchemy) gives plain Dark Sight while it lasts (its effect "night_eye").
	var player := TargetFrame.local_player()
	if is_instance_valid(player) and player.combat_node and player.combat_node.active_effects.has("night_eye"):
		dark_sight_strength = maxf(dark_sight_strength, dark_sight_basic_strength)


func _on_global_time_changed(_current_time: Dictionary) -> void:
	_refresh_dark_sight()
	var was_day := phase == Phase.DAY
	_recompute_phase_from_global_time()
	if was_day != (phase == Phase.DAY):
		emit_signal("phase_changed", phase == Phase.DAY)
	_apply_lighting()


func _recompute_phase_from_global_time() -> void:
	var minutes_now: float = Global.game_time.hour * 60.0 + Global.game_time.minute
	var day_start_min: float = Global.DAY_START_HOUR * 60.0
	var day_end_min: float = Global.DAY_END_HOUR * 60.0
	var day_len_min: float = day_end_min - day_start_min
	var night_len_min: float = Global.HOURS_PER_DAY * 60.0 - day_len_min

	if minutes_now >= day_start_min and minutes_now < day_end_min:
		phase = Phase.DAY
		progress = (minutes_now - day_start_min) / day_len_min
	else:
		phase = Phase.NIGHT
		var since_night_start: float = minutes_now - day_end_min
		if minutes_now < day_end_min:
			since_night_start = (Global.HOURS_PER_DAY * 60.0 - day_end_min) + minutes_now
		progress = since_night_start / night_len_min


func _apply_lighting() -> void:
	var daylight: float = _daylight_factor()

	var light_scale: float = lerpf(1.0, overcast_light_scale, weather_dim)
	# 0 in full daylight, up to the trait's strength in full night — and only for a viewer with the trait.
	var uv: float = (1.0 - daylight) * dark_sight_strength if outdoors else 0.0
	if _sky_material:
		var top_color: Color = night_sky_top_color.lerp(day_sky_top_color, daylight)
		var horizon_color: Color = night_sky_horizon_color.lerp(day_sky_horizon_color, daylight)
		if uv > 0.0:
			top_color = _brightened(top_color, dark_sight_sky_top_color * uv)
			horizon_color = _brightened(horizon_color, dark_sight_sky_horizon_color * uv)
		if weather_dim > 0.0:
			# Rain greys the sky toward overcast — darker at night so a rainy
			# night doesn't glow.
			var overcast: Color = overcast_sky_color * lerpf(0.15, 1.0, daylight)
			top_color = top_color.lerp(overcast, weather_dim * 0.85)
			horizon_color = horizon_color.lerp(overcast, weather_dim * 0.85)
		_sky_material.sky_top_color = top_color
		_sky_material.sky_horizon_color = horizon_color
		# ground_horizon_color was never touched, so it sat at its bright
		# default gray around the clock — invisible by day, but at night it
		# stayed lit while sky_horizon_color above it went dark, producing a
		# glowing seam right at the horizon. Mirroring it to the same color
		# keeps the sky/ground halves of the dome seamless at every hour.
		_sky_material.ground_horizon_color = horizon_color
		if _sky_shader:
			_feed_sky(top_color, horizon_color, daylight)
	if _environment:
		_environment.ambient_light_energy = maxf(lerp(night_ambient_energy, day_ambient_energy, daylight), dark_sight_night_ambient_energy * uv) * light_scale

	if _sun == null:
		return

	if phase == Phase.DAY:
		var sun_rotation := _sun_rotation(progress)
		# at the day's ends the light hands over to the moon where it is then (rising at dusk, setting at dawn)
		var moon_rotation := _moon_rotation(1.0 if progress < 0.5 else 0.0)
		var sun_color := sun_edge_color.lerp(sun_noon_color, daylight)
		var sun_energy: float = lerp(sun_edge_energy, sun_peak_energy, daylight)
		# Continuously crossfade with the moon's exact rotation/color/energy
		# right at the edges of the day phase (daylight 0..1) instead of a
		# hard switch the instant phase flips to/from NIGHT — at daylight=0
		# this evaluates to precisely the moon's values on both sides of the
		# boundary (NIGHT always renders pure moon values too), so there's no
		# discontinuous jump in light direction, color, or brightness.
		_sun.rotation_degrees = moon_rotation.lerp(sun_rotation, daylight)
		_sun.light_color = moon_color.lerp(sun_color, daylight)
		_sun.light_energy = lerp(moon_energy, sun_energy, daylight) * light_scale * lerpf(1.0, dark_sight_moon_energy_multiplier, uv)
	else:
		_sun.rotation_degrees = _moon_rotation(progress)
		# a thin moon lights the land less; the dark moon only a little (starlight)
		var moonlight: float = lerpf(0.45, 1.0, 1.0 - absf(moon_phase() * 2.0 - 1.0))
		_sun.light_energy = moon_energy * moonlight * light_scale * lerpf(1.0, dark_sight_moon_energy_multiplier, uv)
		_sun.light_color = moon_color


# Where the sun is `p` (0..1) through the day: rising at one side of sun_yaw, highest at noon, setting at the other.
func _sun_rotation(p: float) -> Vector3:
	var altitude: float = lerp(sun_min_altitude_degrees, sun_max_altitude_degrees, sin(p * PI))
	return Vector3(-altitude, sun_yaw_degrees + lerpf(-0.5, 0.5, p) * sun_arc_degrees, 0.0)


# Where the moon is `p` (0..1) through the night, the same way around moon_rotation_degrees.
func _moon_rotation(p: float) -> Vector3:
	var top: float = -moon_rotation_degrees.x
	var altitude: float = lerp(moon_min_altitude_degrees, top, sin(p * PI))
	return Vector3(-altitude, moon_rotation_degrees.y + lerpf(-0.5, 0.5, p) * moon_arc_degrees, 0.0)


# 0 = new moon (the dark moon), 0.5 = full. From the real clock, the same for every player.
static func moon_phase(unix_time: float = -1.0) -> float:
	var t := Time.get_unix_time_from_system() if unix_time < 0.0 else unix_time
	return fposmod(t / (MOON_CYCLE_DAYS * 86400.0), 1.0)


# The direction toward a light with these rotation degrees (a DirectionalLight3D shines along its -Z).
static func toward(rotation_deg: Vector3) -> Vector3:
	return Basis.from_euler(rotation_deg * (PI / 180.0)).z


func _feed_sky(top_color: Color, horizon_color: Color, daylight: float) -> void:
	var sun_rot: Vector3 = _sun_rotation(progress) if phase == Phase.DAY else _sun_rotation(0.0 if progress > 0.5 else 1.0)
	var moon_rot: Vector3 = _moon_rotation(progress) if phase == Phase.NIGHT else _moon_rotation(1.0 if progress < 0.5 else 0.0)
	var sun_dir := toward(sun_rot)
	_sky_shader.set_shader_parameter("top_color", top_color)
	_sky_shader.set_shader_parameter("horizon_color", horizon_color)
	_sky_shader.set_shader_parameter("sun_dir", sun_dir)
	_sky_shader.set_shader_parameter("sun_color", sun_edge_color.lerp(sun_noon_color, daylight))
	_sky_shader.set_shader_parameter("sun_visible", clampf(daylight * 3.0, 0.0, 1.0) * (1.0 - weather_dim * 0.8))
	_sky_shader.set_shader_parameter("sunset", clampf(1.0 - sun_dir.y * 4.0, 0.0, 1.0) * (1.0 if phase == Phase.DAY else 0.0) * (1.0 - weather_dim))
	_sky_shader.set_shader_parameter("moon_dir", toward(moon_rot))
	_sky_shader.set_shader_parameter("moon_visible", (1.0 - daylight) * (1.0 - weather_dim * 0.7))
	_sky_shader.set_shader_parameter("moon_phase", moon_phase())
	_sky_shader.set_shader_parameter("moon_color", Color(0.86, 0.88, 0.95))
	_sky_shader.set_shader_parameter("night", 1.0 - daylight)
	_sky_shader.set_shader_parameter("cloud_coverage", lerpf(0.32, 0.92, weather_dim))
	_sky_shader.set_shader_parameter("cloud_darkness", weather_dim)


# 0.0 at night, ramps up/down over dawn_dusk_fraction at each end of the day
# phase, 1.0 for the plateau in between. Night is always 0.0.
func _daylight_factor() -> float:
	if phase == Phase.NIGHT:
		return 0.0
	if dawn_dusk_fraction <= 0.0:
		return 1.0
	if progress < dawn_dusk_fraction:
		return smoothstep(0.0, 1.0, progress / dawn_dusk_fraction)
	if progress > 1.0 - dawn_dusk_fraction:
		return smoothstep(0.0, 1.0, (1.0 - progress) / dawn_dusk_fraction)
	return 1.0


# Per-channel "at least this bright" — lifts a dark sky colour toward a floor
# colour without ever dimming a colour that is already brighter.
func _brightened(base: Color, floor_color: Color) -> Color:
	return Color(maxf(base.r, floor_color.r), maxf(base.g, floor_color.g), maxf(base.b, floor_color.b), base.a)


func is_day() -> bool:
	return phase == Phase.DAY


# Public wrapper for the private ramp (used by weather_manager.gd to darken fog at night).
func get_daylight() -> float:
	return _daylight_factor()


# Called every frame while rain is fading in/out (weather_manager.gd); redraws
# the lighting immediately instead of waiting for the next game-minute tick.
func set_weather_dim(value: float) -> void:
	value = clampf(value, 0.0, 1.0)
	if is_equal_approx(value, weather_dim):
		return
	weather_dim = value
	_apply_lighting()


# Real seconds until the next phase flips (day->night or night->day), for
# UI/debug display (e.g. the /time chat command).
func seconds_until_next_phase() -> float:
	var day_len_min: float = Global.DAY_END_HOUR * 60.0 - Global.DAY_START_HOUR * 60.0
	var night_len_min: float = Global.HOURS_PER_DAY * 60.0 - day_len_min
	var phase_len_min: float = day_len_min if phase == Phase.DAY else night_len_min
	# 1 real second = 1 game minute (Global.REAL_SECONDS_PER_GAME_MINUTE), so
	# remaining game-minutes in this phase converts 1:1 to remaining real seconds.
	return (1.0 - progress) * phase_len_min * Global.REAL_SECONDS_PER_GAME_MINUTE
