# day_night_cycle.gd
# Drives the outdoor zone's sun (DirectionalLight3D) and sky/ambient lighting.
# Phase/progress are derived directly from Global.game_time (single source of
# truth) rather than an independent timer, so the sky and the /time command
# always agree. Global runs at 1 real second = 1 game minute over a standard
# 24-hour day (6:00-21:00 day, 21:00-6:00 night) — 15 real minutes of day
# (the last in-game hour blending into dusk) and 9 of night. See Global.gd's
# HOURS_PER_DAY/DAY_START_HOUR/DAY_END_HOUR consts.
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

@export_group("Moon (night)")
@export var moon_rotation_degrees: Vector3 = Vector3(-55.0, 200.0, 0.0)
@export var moon_energy: float = 0.04
@export var moon_color: Color = Color(0.55, 0.65, 0.95)

@export_group("Sky / Ambient")
@export var day_sky_top_color: Color = Color(0.22986513, 0.3887299, 0.9202023)
@export var day_sky_horizon_color: Color = Color(0.62, 0.65, 0.71)
@export var night_sky_top_color: Color = Color(0.01, 0.015, 0.04)
@export var night_sky_horizon_color: Color = Color(0.03, 0.035, 0.07)
@export var day_ambient_energy: float = 1.0
@export var night_ambient_energy: float = 0.05

enum Phase { DAY, NIGHT }

var phase: int = Phase.DAY
var progress: float = 0.0  # 0..1 through the current phase

var _sun: DirectionalLight3D
var _sky_material: ProceduralSkyMaterial
var _environment: Environment


func _ready() -> void:
	add_to_group("day_night_cycle")
	_sun = get_node_or_null(sun_path)
	var world_env: WorldEnvironment = get_node_or_null(world_environment_path)
	if world_env:
		_environment = world_env.environment
		if _environment and _environment.sky:
			_sky_material = _environment.sky.sky_material
	Global.time_changed.connect(_on_global_time_changed)
	_on_global_time_changed(Global.game_time)


func _on_global_time_changed(_current_time: Dictionary) -> void:
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

	if _sky_material:
		_sky_material.sky_top_color = night_sky_top_color.lerp(day_sky_top_color, daylight)
		_sky_material.sky_horizon_color = night_sky_horizon_color.lerp(day_sky_horizon_color, daylight)
	if _environment:
		_environment.ambient_light_energy = lerp(night_ambient_energy, day_ambient_energy, daylight)

	if _sun == null:
		return

	if phase == Phase.DAY:
		var altitude: float = lerp(sun_min_altitude_degrees, sun_max_altitude_degrees, sin(progress * PI))
		_sun.rotation_degrees = Vector3(-altitude, sun_yaw_degrees, 0.0)
		_sun.light_energy = lerp(sun_edge_energy, sun_peak_energy, daylight)
		_sun.light_color = sun_edge_color.lerp(sun_noon_color, daylight)
	else:
		_sun.rotation_degrees = moon_rotation_degrees
		_sun.light_energy = moon_energy
		_sun.light_color = moon_color


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


func is_day() -> bool:
	return phase == Phase.DAY


# Real seconds until the next phase flips (day->night or night->day), for
# UI/debug display (e.g. the /time chat command).
func seconds_until_next_phase() -> float:
	var day_len_min: float = Global.DAY_END_HOUR * 60.0 - Global.DAY_START_HOUR * 60.0
	var night_len_min: float = Global.HOURS_PER_DAY * 60.0 - day_len_min
	var phase_len_min: float = day_len_min if phase == Phase.DAY else night_len_min
	# 1 real second = 1 game minute (Global.REAL_SECONDS_PER_GAME_MINUTE), so
	# remaining game-minutes in this phase converts 1:1 to remaining real seconds.
	return (1.0 - progress) * phase_len_min * Global.REAL_SECONDS_PER_GAME_MINUTE
