# magistrate_npc.gd — the Magistrate at the Lumora courthouse (crime.gd). Hail or right-click them: they take a bounty
# (the whole of it), and for someone whose record is clear they sell back the standing their crimes cost ("making
# amends": Crime.AMENDS_COPPER_PER_POINT a point). Only that standing: the rest is earned out in the world. A talking NPC
# like the Soul Binder (lines and keyword topics from Data/magistrate.json).
extends "res://Scripts/talking_vendor_npc.gd"

const USE_RANGE := 6.0


func open_interaction(player: Node) -> void:
	_offer(player)


func respond_to_hail() -> void:
	_offer(TargetFrame.local_player())


func can_trade() -> bool:
	return false


func _offer(player: Node) -> void:
	if not is_instance_valid(player) or not player.is_multiplayer_authority():
		return
	if (player as Node3D).global_position.distance_to(global_position) > USE_RANGE:
		GameLog.log_general("You need to be closer to %s." % npc_name)
		return
	_face_player()
	var popup: Node = load("res://Scenes/group_invite_popup.tscn").instantiate()
	var owed := Crime.bounty()
	if owed > 0:
		get_tree().root.add_child(popup)
		popup.ask("\"Your bounty in %s stands at %s. Settle it, and the guards will leave you be.\"" % [Crime.REGION, Crime.coins(owed)],
				"Pay %s" % Crime.coins(owed), "Not now", func(yes: bool): _pay(player, yes))
		return
	var cost := Crime.amends_cost()
	if cost > 0:
		var lost := Crime.standing_lost()
		var names := []
		for f in lost:
			names.append("%s (%d)" % [f, int(lost[f])])
		get_tree().root.add_child(popup)
		popup.ask("\"Your record is clear, but the city remembers.\"\nMake amends with %s for %s?" % [", ".join(names), Crime.coins(cost)],
				"Make amends", "Not now", func(yes: bool): _amends(player, yes))
		return
	popup.free()
	say_local(_pick("greeting"))


func _pay(player: Node, yes: bool) -> void:
	if not yes or not is_instance_valid(player):
		return
	if Crime.pay(player):
		say_local("Paid in full. Stay out of trouble.")
	else:
		say_local("That purse won't cover it. Come back when it will.")


func _amends(player: Node, yes: bool) -> void:
	if not yes or not is_instance_valid(player):
		return
	if Crime.make_amends(player):
		say_local("So recorded. The Wardens will hear you've made it right.")
	else:
		say_local("Amends cost coin. Come back when you have it.")
