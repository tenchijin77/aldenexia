# test_base.gd — what every regression test (tools/tests/test_*.gd) extends. A test overrides run() (it may await) and
# calls check() / eq(); the runner (run_tests.gd) collects the results. Helpers build a real player from a save dict.
extends Node

var passes := 0
var failures: Array = []


func run() -> void:
	pass


func check(ok: bool, what: String) -> void:
	if ok:
		passes += 1
	else:
		failures.append(what)


func eq(got: Variant, want: Variant, what: String) -> void:
	check(got == want, "%s: got %s, expected %s" % [what, str(got), str(want)])


func frames(n: int = 3) -> void:
	for i in n:
		await get_tree().process_frame


# A real Player3D (res://Scenes/player3d.tscn) built from a minimal save; extra keys override the defaults.
func make_player(extra: Dictionary = {}) -> Node:
	var data := {"player_class": "Blademaster", "player_race": "human", "player_name": "Ztest", "player_level": 5,
		"known_spells": [], "quests": {}, "languages": {"common": 100.0}, "bind_point": [5, 1, 5]}
	data.merge(extra, true)
	Global.player_data = data
	Inventory.reset_for_new_character()
	var p = load("res://Scenes/player3d.tscn").instantiate()
	add_child(p)
	await frames(5)
	p.combat_node.level = int(data["player_level"])
	return p


# A flat floor to stand on (tests with movement or ground rays).
func make_floor(size: float = 200.0) -> void:
	var b := StaticBody3D.new()
	var c := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = Vector3(size, 1, size)
	c.shape = s
	b.add_child(c)
	add_child(b)
	b.position = Vector3(0, -0.5, 0)
