# run_tests.gd — the regression suite runner. Runs every tools/tests/test_*.gd (or the ones named after --) headless:
#   godot --headless --path . res://tools/tests/run_tests.tscn            (all)
#   godot --headless --path . res://tools/tests/run_tests.tscn -- quests  (only test_quests.gd)
# or simply: bash tools/run_tests.sh. Prints PASS/FAIL per test and exits 1 if anything failed (update.sh refuses to deploy).
extends Node3D

const DIR := "res://tools/tests/"


func _ready() -> void:
	await get_tree().process_frame
	var only: Array = Array(OS.get_cmdline_user_args())
	var files: Array = []
	for f in DirAccess.get_files_at(DIR):
		if f.begins_with("test_") and f.ends_with(".gd") and f != "test_base.gd":
			if only.is_empty() or only.has(f.trim_prefix("test_").trim_suffix(".gd")):
				files.append(f)
	files.sort()
	var total_pass := 0
	var failed: Array = []
	for f in files:
		var script: GDScript = load(DIR + f)
		if script == null or not script.can_instantiate():
			failed.append("%s: does not compile" % f)
			print("TEST FAIL %s (does not compile)" % f)
			continue
		var t: Node = script.new()
		t.name = f.trim_suffix(".gd")
		add_child(t)
		await t.run()
		total_pass += t.passes
		if t.failures.is_empty():
			print("TEST PASS %-24s %d checks" % [f, t.passes])
		else:
			print("TEST FAIL %-24s %d passed, %d failed" % [f, t.passes, t.failures.size()])
			for why in t.failures:
				print("    - " + str(why))
				failed.append("%s: %s" % [f, why])
		t.queue_free()
		Global.player_data = {}
		Inventory.reset_for_new_character()
		for i in 3:
			await get_tree().process_frame
	print("TEST RESULT %s: %d checks passed, %d failed, %d files" % ["OK" if failed.is_empty() else "FAILED", total_pass, failed.size(), files.size()])
	get_tree().quit(0 if failed.is_empty() else 1)
