# merchant_schedule.gd — Sahren's timetable (Data/traveling_merchant.json "journey"). He walks one loop through the zones
# of Solgrave — the Outskirts, Dustwind Plateaus, and Ashfall Dunes once it is built — and is only ever in ONE of them.
# Every zone's server works out from the shared clock where he is right now, so they agree without talking to each other
# (they all run on the same machine). A little randomness: each loop starts up to drift_minutes early or late, and his
# stays vary by stay_jitter — seeded by the loop's number, so every server rolls the same numbers.
# Pure functions of the time (unix seconds): the spawner uses them to bring him in, guards to say where he is.
class_name MerchantSchedule
extends RefCounted

const CONFIG_PATH := "res://Data/traveling_merchant.json"
static var _journey: Dictionary = {}


static func journey() -> Dictionary:
	if _journey.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH)) if FileAccess.file_exists(CONFIG_PATH) else null
		_journey = parsed.get("journey", {}) if typeof(parsed) == TYPE_DICTIONARY else {}
	return _journey


# The legs that are on: enabled and in a zone that exists (Ashfall's waits until it is built).
static func legs() -> Array:
	var out: Array = []
	for leg in journey().get("legs", []):
		if bool(leg.get("enabled", true)) and ZoneInfo.exists(str(leg.get("zone", ""))):
			out.append(leg)
	return out


static func _v(xz: Variant) -> Vector3:
	var a: Array = xz if typeof(xz) == TYPE_ARRAY else [0, 0]
	return Vector3(float(a[0]), 0.0, float(a[1]))


# The same "random" number on every server for a given loop and slot: 0..1.
static func _roll(cycle: int, slot: int) -> float:
	var h := hash("%d:%d" % [cycle, slot])
	return float(absi(h) % 100000) / 100000.0


# A leg as a timeline: [{kind: "walk"|"stay", from, to, seconds, name}], with the loop's rolls applied.
static func timeline(leg: Dictionary, cycle: int) -> Array:
	var speed := float(journey().get("walk_speed", 3.5)) / float(journey().get("walk_factor", 1.25))
	var jitter := float(journey().get("stay_jitter", 0.2))
	var out: Array = []
	var here := _v(leg.get("enter"))
	var stops: Array = leg.get("stops", [])
	for i in stops.size():
		var stop: Dictionary = stops[i]
		var there := _v(stop.get("at"))
		out.append({"kind": "walk", "from": here, "to": there, "seconds": here.distance_to(there) / speed, "name": str(stop.get("name", ""))})
		var stay := float(stop.get("stay_seconds", 300)) * (1.0 + jitter * (_roll(cycle, 10 + i) * 2.0 - 1.0))
		out.append({"kind": "stay", "from": there, "to": there, "seconds": stay, "name": str(stop.get("name", ""))})
		here = there
	var exit := _v(leg.get("exit"))
	out.append({"kind": "walk", "from": here, "to": exit, "seconds": here.distance_to(exit) / speed, "name": str(leg.get("exit_name", "the road"))})
	return out


static func leg_seconds(leg: Dictionary, cycle: int) -> float:
	var total := 0.0
	for step in timeline(leg, cycle):
		total += float(step["seconds"])
	return total


# When a leg of a loop starts (unix seconds).
static func leg_start(leg: Dictionary, cycle: int) -> float:
	var cycle_len := float(journey().get("cycle_minutes", 90)) * 60.0
	var drift := float(journey().get("drift_minutes", 8)) * 60.0 * (_roll(cycle, 1) * 2.0 - 1.0)
	return cycle * cycle_len + drift + float(leg.get("start_minute", 0)) * 60.0


# Where Sahren is at time `t`: {zone, leg, cycle, step (index), steps, elapsed (seconds into the step), position (Vector3,
# y 0), stop_name, stop_at, doing ("walking"|"trading"), seconds_left_in_step}; {} while he is between zones.
static func where(t: float) -> Dictionary:
	var cycle_len := float(journey().get("cycle_minutes", 90)) * 60.0
	if cycle_len <= 0.0:
		return {}
	var base := int(floor(t / cycle_len))
	for cycle in [base - 1, base, base + 1]:   # drift can push a loop's leg across the boundary
		for leg in legs():
			var start := leg_start(leg, cycle)
			var steps := timeline(leg, cycle)
			var into := t - start
			if into < 0.0 or into > leg_seconds(leg, cycle):
				continue
			for i in steps.size():
				var step: Dictionary = steps[i]
				if into <= float(step["seconds"]) or i == steps.size() - 1:
					var f := clampf(into / maxf(float(step["seconds"]), 0.001), 0.0, 1.0)
					return {"zone": str(leg.get("zone")), "leg": leg, "cycle": cycle, "step": i, "steps": steps, "elapsed": into,
							"position": (step["from"] as Vector3).lerp(step["to"], f), "stop_name": step["name"], "stop_at": step["to"],
							"doing": "trading" if step["kind"] == "stay" else "walking",
							"seconds_left_in_step": float(step["seconds"]) - into}
				into -= float(step["seconds"])
	return {}


# The next time (after `t`) he walks into `zone`, as unix seconds (INF if he never does).
static func next_arrival(zone: String, t: float) -> float:
	var cycle_len := float(journey().get("cycle_minutes", 90)) * 60.0
	var base := int(floor(t / cycle_len))
	var best := INF
	for cycle in [base, base + 1, base + 2]:
		for leg in legs():
			if str(leg.get("zone")) == zone:
				var start := leg_start(leg, cycle)
				if start > t:
					best = minf(best, start)
	return best


# What a guard says when asked about him (templates in Data/guard_topics.json "merchant_lines"): {key, stop, x, z, minutes, zone}.
static func report(zone: String, t: float) -> Dictionary:
	var w := where(t)
	if w.is_empty() or str(w["zone"]) != zone:
		var back := next_arrival(zone, t)
		return {"key": "elsewhere" if not w.is_empty() else "away", "zone": ZoneInfo.name_for(str(w.get("zone", ""))),
				"minutes": maxi(1, int(ceil((back - t) / 60.0))) if back < INF else 0}
	var at: Vector3 = w["stop_at"]
	var key := "trading" if w["doing"] == "trading" else ("leaving" if int(w["step"]) == (w["steps"] as Array).size() - 1 else "coming")
	return {"key": key, "stop": str(w["stop_name"]), "x": int(round(at.x)), "z": int(round(at.z)),
			"minutes": maxi(1, int(ceil(float(w["seconds_left_in_step"]) / 60.0))), "zone": ZoneInfo.name_for(zone)}
