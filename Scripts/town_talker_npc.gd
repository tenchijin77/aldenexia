# town_talker_npc.gd — a townsperson who talks but sells nothing (the Lumora stand-ins, 2026-09-26: Commander Halvar at
# the Citadel, the town crier...). Right-click or hail: a greeting; they chat on their own (ambient lines) and answer
# keywords, all from their config (the talking_vendor_npc.gd shape).
extends "res://Scripts/talking_vendor_npc.gd"

const USE_RANGE := 8.0


func open_interaction(player: Node) -> void:
	_greet(player)


func respond_to_hail() -> void:
	_greet(TargetFrame.local_player())


func can_trade() -> bool:
	return false


func _greet(player: Node) -> void:
	if not is_instance_valid(player) or not player.is_multiplayer_authority():
		return
	if (player as Node3D).global_position.distance_to(global_position) > USE_RANGE:
		GameLog.log_general("You need to be closer to %s." % npc_name)
		return
	_face_player()
	say_local(_pick("greeting"))
