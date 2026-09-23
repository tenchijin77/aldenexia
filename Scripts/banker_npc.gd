# banker_npc.gd — the Lumora banker: a talking NPC (talking_vendor_npc.gd — greetings, ambient lines, keyword topics from
# Data/banker.json) whose right-click or hail opens your bank (bank_window.gd) instead of a shop. The bank itself is
# Inventory.bank_storage, saved with the character.
extends "res://Scripts/talking_vendor_npc.gd"

const BANK_WINDOW := preload("res://Scripts/bank_window.gd")
const USE_RANGE := 6.0


# Right-click (player3d.gd _open_shop() calls this instead of opening a shop).
func open_interaction(player: Node) -> void:
	_open_bank(player)


func respond_to_hail() -> void:
	_open_bank(TargetFrame.local_player())


func can_trade() -> bool:
	return false  # no shop: "bank" topics open the bank through the hail action


func _open_bank(player: Node) -> void:
	if not is_instance_valid(player) or not player.is_multiplayer_authority():
		return
	if (player as Node3D).global_position.distance_to(global_position) > USE_RANGE:
		GameLog.log_general("You need to be closer to %s." % npc_name)
		return
	_face_player()
	say_local(_pick("greeting"))
	for existing in get_tree().root.get_children():
		if existing.get_script() == BANK_WINDOW:
			existing.queue_free()
	var window = BANK_WINDOW.new()
	get_tree().root.add_child(window)
	window.set_banker(self)
