# soul_binder_npc.gd — a town's Soul Binder (test 39, the Game Systems notes' "NPC Soul Binders"): anyone, caster or not,
# can have their spirit bound here for SOUL_BIND_COST. Hail or right-click them and say yes. A talking NPC like the banker
# (talking_vendor_npc.gd: greetings, ambient lines and keyword topics from Data/soul_binder.json). Binding follows the same
# once-an-hour rule as the casters' Attune Spirit (PlayerTravel.bind_spirit()).
extends "res://Scripts/talking_vendor_npc.gd"

const USE_RANGE := 6.0
const SOUL_BIND_COST := Global.COPPER_PER_SILVER   # 1 silver (the notes)


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
	say_local(_pick("greeting"))
	var popup: Node = load("res://Scenes/group_invite_popup.tscn").instantiate()
	get_tree().root.add_child(popup)
	popup.ask("Bind your spirit here, at the Dawnspire? (1 silver)\nYou will return here when you fall.", "Bind", "Not now",
			func(yes: bool): _bind(player, yes))


func _bind(player: Node, yes: bool) -> void:
	if not yes or not is_instance_valid(player):
		return
	if PlayerTravel.bind_wait_minutes() > 0:
		say_local("Your spirit hasn't settled from its last binding. Come back in %d minutes." % PlayerTravel.bind_wait_minutes())
		return
	if not Global.can_afford(SOUL_BIND_COST):
		say_local("A silver for the binding. The candles don't light themselves.")
		return
	Global.spend_currency_copper(SOUL_BIND_COST)
	PlayerTravel.bind_spirit((player as Node3D).global_position, "[color=#ffdd44]A clear image of this place is flashed in your mind. You feel a strong affinity to this area.[/color]")
