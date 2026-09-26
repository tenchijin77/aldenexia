# On-demand zones (2026-09-26): only the always-on zones run all the time; the login server (the hub) starts any other
# zone when a player needs it and a zone started that way stops itself once empty. The end-to-end run (a world started
# with tools/run_world.sh, a headless client crossing into Dustwind, logging out, the zone stopping, logging back in
# through the login server) was checked by hand; these keep the pieces in place.
extends "res://tools/tests/test_base.gd"


func run() -> void:
	check(ZoneInfo.always_on(ZoneInfo.DEFAULT_ID), "the starting zone (the login server) is always on")
	check(not ZoneInfo.always_on("dustwind_plateaus"), "Dustwind runs on demand")
	check(FileAccess.get_file_as_string("res://Scripts/net.gd").contains('"always" if ZoneInfo.always_on(id) else "ondemand"'), "--list-zones says which")
	var rw := FileAccess.get_file_as_string("res://tools/run_world.sh")
	check(rw.contains("export ALDENEXIA_ZONE_LAUNCH") and rw.contains("--on-demand") and rw.contains("--all-zones"), "run_world.sh hands the hub the launch command (and --all-zones keeps the old way)")

	var link = load("res://Scripts/world_link.gd").new()
	link.as_hub = true
	add_child(link)
	await frames(1)
	check(link.zone_running(ZoneInfo.DEFAULT_ID), "its own zone is running")
	check(not link.zone_running("dustwind_plateaus"), "a zone that hasn't linked up isn't")
	link._peers.append({"tcp": StreamPeerTCP.new(), "buf": "", "zone": "dustwind_plateaus"})
	check(link.zone_running("dustwind_plateaus"), "once it says hello, it is")
	link._closing["dustwind_plateaus"] = true
	check(not link.zone_running("dustwind_plateaus"), "not while it's shutting down (nobody is sent to a closing zone)")
	link._peers.clear()
	link._closing.clear()

	# no launch command (a server started by hand): the answer comes at once, "no"
	var had_env := OS.get_environment("ALDENEXIA_ZONE_LAUNCH")
	OS.unset_environment("ALDENEXIA_ZONE_LAUNCH")
	var got := []
	link.ensure_zone("dustwind_plateaus", func(ok: bool) -> void: got.append(ok))
	eq(got, [false], "without a launch command a sleeping zone can't be started: the player is told at once")
	got.clear()
	link.ensure_zone(ZoneInfo.DEFAULT_ID, func(ok: bool) -> void: got.append(ok))
	eq(got, [true], "the zone you're in is always fine")
	got.clear()
	link.ensure_zone("no_such_zone", func(ok: bool) -> void: got.append(ok))
	eq(got, [false], "a zone that doesn't exist: no")
	got.clear()
	# a waiter joins an in-progress start; the zone's hello answers everyone
	link._waking["ashfall_dunes"] = {"since": Time.get_ticks_msec(), "launched": true, "waiters": []}
	link.ensure_zone("ashfall_dunes", func(ok: bool) -> void: got.append(ok))
	link.ensure_zone("ashfall_dunes", func(ok: bool) -> void: got.append(ok))
	eq(got, [], "two players waiting while it starts")
	link._zone_came_up("ashfall_dunes")
	eq(got, [true, true], "both told when it's up")
	if not had_env.is_empty():
		OS.set_environment("ALDENEXIA_ZONE_LAUNCH", had_env)

	# the whole world's players, for the character list, deletes and the Join screen's count
	link._world = {"dustwind_plateaus": [{"name": "Maedianie"}], "lumora": [{"name": "Zozuur"}]}
	var everyone: Array = link.online_everywhere()
	check(everyone.has("maedianie") and everyone.has("zozuur"), "online in other zones counts as online")
	eq(link.world_player_count(), 2, "the world's player count")
	check(FileAccess.get_file_as_string("res://Scripts/account_relay.gd").contains("func _is_online("), "the character list and delete check use it")

	# the client: a zone line waits for the zone; a dead zone port falls back to the login server
	var ns := FileAccess.get_file_as_string("res://Scripts/net.gd")
	check(ns.contains("link.request_zone(target)") and ns.contains("func _travel_now("), "crossing a zone line waits for the zone to be up")
	check(ns.contains("_tried_login_server = true"), "a zone that doesn't answer: log in through the login server")
	check(ns.contains("link.ensure_zone(zone, func(ok: bool) -> void: _send_redirect("), "the login server wakes a character's zone before sending them")
	link.queue_free()
	await frames(1)
