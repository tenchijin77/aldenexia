# Sahren's journey (merchant_schedule.gd, traveling_merchant_spawner.gd, traveling_merchant.gd): one timetable every zone
# agrees on, brought in mid-visit where he should be, stops on the road when hailed, guards know where he is.
extends "res://tools/tests/test_base.gd"


func run() -> void:
	var base := 1790000000.0
	# The loop: Outskirts, Dustwind, Ashfall; never two zones at once (one answer per moment)
	var zones_seen: Array = []
	var order: Array = []
	var t := base
	while t < base + 3 * 5400:
		var w := MerchantSchedule.where(t)
		var z := "" if w.is_empty() else str(w["zone"])
		if not z.is_empty() and (order.is_empty() or order[-1] != z):
			order.append(z)
		if not z.is_empty() and not zones_seen.has(z):
			zones_seen.append(z)
		t += 30.0
	check(zones_seen.has("lumora_outskirts") and zones_seen.has("dustwind_plateaus"), "he visits the Outskirts and Dustwind: %s" % str(zones_seen))
	check(zones_seen.has("ashfall_dunes"), "and Ashfall")
	var legs := MerchantSchedule.legs()
	var overlap := false
	for cycle in range(19000, 19400):   # every loop's last leg ends before the next loop's first begins, whatever the drift
		var last: Dictionary = legs[-1]
		overlap = overlap or MerchantSchedule.leg_start(last, cycle) + MerchantSchedule.leg_seconds(last, cycle) >= MerchantSchedule.leg_start(legs[0], cycle + 1)
		for i in range(1, legs.size()):
			overlap = overlap or MerchantSchedule.leg_start(legs[i - 1], cycle) + MerchantSchedule.leg_seconds(legs[i - 1], cycle) >= MerchantSchedule.leg_start(legs[i], cycle)
	check(not overlap, "no leg runs into the next (400 loops)")
	var alternates := true
	for i in range(1, order.size()):
		alternates = alternates and order[i] != order[i - 1]
	check(order.size() >= 5 and alternates, "Outskirts, Dustwind, Outskirts... in turn: %s" % str(order.slice(0, 6)))
	eq(MerchantSchedule.where(base + 1234.0), MerchantSchedule.where(base + 1234.0), "the same answer every time (every server agrees)")
	var starts: Array = []
	for cycle in range(20, 26):
		starts.append(fmod(MerchantSchedule.leg_start(MerchantSchedule.legs()[0], cycle), 5400.0))
	check(starts.any(func(s): return absf(s - starts[0]) > 30.0), "the loop drifts a little from one to the next")
	var drifts: Array = []
	for cycle in range(100, 140):
		drifts.append(MerchantSchedule.leg_start(MerchantSchedule.legs()[0], cycle) - cycle * 5400.0)
	var drift_max := float(MerchantSchedule.journey().get("drift_minutes", 8)) * 60.0
	check(drifts.max() - drifts.min() > drift_max, "and really scatters across +/- drift_minutes (spread %d s)" % int(drifts.max() - drifts.min()))

	# A moment when he's trading at the docks, and one when he's walking in Dustwind
	var at_docks := -1.0
	var dustwind_road := -1.0
	t = base
	while t < base + 2 * 5400 and (at_docks < 0.0 or dustwind_road < 0.0):
		var w := MerchantSchedule.where(t)
		if not w.is_empty():
			if at_docks < 0.0 and w["zone"] == "lumora_outskirts" and w["doing"] == "trading" and str(w["stop_name"]).contains("docks") and float(w["seconds_left_in_step"]) > 120.0:
				at_docks = t
			if dustwind_road < 0.0 and w["zone"] == "dustwind_plateaus" and w["doing"] == "walking" and int(w["step"]) == 2:
				dustwind_road = t
		t += 20.0
	check(at_docks > 0.0 and dustwind_road > 0.0, "found both moments")

	# Guards: where he is, with coordinates, in plain words
	var r := MerchantSchedule.report("lumora_outskirts", at_docks)
	eq(r["key"], "trading", "the guard's report while he trades at the docks")
	check(str(r["stop"]).contains("docks") and int(r["x"]) == -757 and int(r["z"]) == -1018, "names the stop and where it is")
	eq(MerchantSchedule.report("lumora_outskirts", dustwind_road)["key"], "elsewhere", "while he's in Dustwind: elsewhere")
	check(int(MerchantSchedule.report("lumora_outskirts", dustwind_road)["minutes"]) > 0, "and when he'll be back")

	var lines: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://Data/guard_topics.json"))["merchant_lines"]
	for key in ["coming", "trading", "leaving", "elsewhere", "away"]:
		check(lines.has(key) and not lines[key].is_empty(), "guards have lines for '%s'" % key)

	# A zone's marker for where he comes in and the timetable's [x, z] for it stay together (the guards' timings use the latter)
	for leg in MerchantSchedule.journey().get("legs", []):
		if str(leg.get("enter_marker", "")).is_empty() or not ZoneInfo.exists(str(leg.get("zone", ""))):
			continue
		var scene: Node = load(ZoneInfo.scene_for(str(leg["zone"]))).instantiate()
		var marker := scene.get_node_or_null(str(leg["enter_marker"])) as Node3D
		check(marker != null, "%s has the marker %s" % [leg["zone"], leg["enter_marker"]])
		if marker != null:
			var at: Array = leg["enter"]
			var gap := Vector2(marker.position.x - float(at[0]), marker.position.z - float(at[1])).length()
			check(gap < 50.0, "%s: the '%s' marker and traveling_merchant.json's enter [x, z] are %.0f m apart (keep them within 50)" % [leg["zone"], leg["enter_marker"], gap])
		scene.free()

	# A zone's server started in the middle of his visit: he is brought in where he should be
	var zone = load("res://Scenes/zones/dustwind_plateaus.tscn").instantiate()
	add_child(zone)
	await frames(4)
	var sp = zone.get_node("TravelingMerchantSpawner")
	sp.clock_override = dustwind_road
	sp._check = 99.0
	sp._process(0.1)
	await frames(3)
	var sahren = sp.get_node("Merchants").get_child(0) if sp.get_node("Merchants").get_child_count() > 0 else null
	check(sahren != null, "Dustwind's server brings him in mid-visit")
	if sahren != null:
		eq(sahren.stage, TravelingMerchant.Stage.ROAD, "on the road")
		eq(sahren.route.size(), 3, "Stone Circles, Nomad Camp, Destroyed Caravan")
		eq(sahren.route_index, 1, "heading for the Nomad Camp (the step he should be on)")
		var expected: Vector3 = MerchantSchedule.where(dustwind_road)["position"]
		check(Vector2(sahren.global_position.x - expected.x, sahren.global_position.z - expected.z).length() < 15.0, "partway along the road, where the timetable has him")
		# hailed on the road: he stops, trades, then walks on
		sahren.request_pause()
		eq(sahren.stage, TravelingMerchant.Stage.CHATTING, "hail him on the road: he stops")
		check(sahren.can_trade(), "and will trade")
		sahren._chat_until_msec = 0
		await get_tree().physics_frame
		await get_tree().physics_frame
		eq(sahren.stage, TravelingMerchant.Stage.ROAD, "then walks on")
		eq(sahren.route_index, 1, "to the same stop")
		# only once per visit: after he leaves, not brought back this loop
		sahren.pack_up()
		sahren._leaving_until_msec = 0
		await frames(4)
		sp._check = 99.0
		sp._process(0.1)
		await frames(2)
		eq(sp.get_node("Merchants").get_child_count(), 0, "not brought back again in the same loop")
	zone.queue_free()
	await frames(2)

	# He arrives mid-stay: standing at the stop with the rest of his stay left
	var outskirts = load("res://Scenes/zones/dustwind_plateaus.tscn").instantiate()
	add_child(outskirts)
	await frames(4)
	var sp2 = outskirts.get_node("TravelingMerchantSpawner")
	var w2 := MerchantSchedule.where(at_docks)
	w2["zone"] = "dustwind_plateaus"   # (reuse this zone's spawner for the Outskirts' docks moment)
	sp2.start_visit(w2)
	await frames(3)
	var trader = sp2.get_node("Merchants").get_child(0)
	eq(trader.stage, TravelingMerchant.Stage.AT_STOP, "at his stop")
	check(trader.can_trade(), "trading")
	outskirts.queue_free()
