# Windows keep their contents inside their border, whatever text they show.
extends "res://tools/tests/test_base.gd"


func run() -> void:
	# Join a Server during an update (test 34.5): long server names and status lines pushed every field past the right edge.
	var menu = load("res://Scenes/join_server_menu.tscn").instantiate()
	add_child(menu)
	await frames(3)
	menu.server_select.set_item_text(0, "test-us-west-lan   (update needed)")
	menu.server_status_label.text = "Can't reach the server, and a different build is published (9ad0be2). Try updating. " \
			+ "Update needed — this server runs v0.4.5 (8748b53)."
	menu.update_btn.visible = true
	menu.update_bar.visible = true
	menu.status_label.text = "Downloading update... 20.8 / 144.9 MB"
	await frames(4)
	var panel: Rect2 = menu.panel.get_global_rect()
	var worst := 0.0
	for node in menu.panel.find_children("*", "Control", true, false):
		if node.is_visible_in_tree() and node.size.x > 0.0:
			worst = maxf(worst, node.get_global_rect().end.x - panel.end.x)
	check(worst <= 0.5, "nothing sticks out past the Join window's right edge (by %.0f px)" % worst)
	menu.queue_free()
	# The window checks the servers as it opens: close that connection, or the next test's player isn't "ours".
	Net._menu_request = {}
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()   # Godot's normal offline state (null would make our id 0)
	await frames(2)
