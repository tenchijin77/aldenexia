# temple_healer_npc.gd — the healer at Lumora's Temple of the Dawn (the development page's Lumora plan: "the temple heals
# and cures; no resurrections"). Hail or right-click: for HEAL_COST she restores your health and mana and lifts every
# ailment a cure spell would (poisons, disease, curses, fear...). Lines from her config (talking_vendor_npc.gd shape).
extends "res://Scripts/talking_vendor_npc.gd"

const USE_RANGE := 6.0
const HEAL_COST := 5   # copper


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
	popup.ask("Be healed and cured of your ailments? (%s)\nThe temple cannot bring back the dead." % Crime.coins(HEAL_COST),
			"Heal me", "Not now", func(yes: bool): _heal(player, yes))


func _heal(player: Node, yes: bool) -> void:
	if not yes or not is_instance_valid(player):
		return
	if not Global.can_afford(HEAL_COST):
		say_local("A few coppers for the temple's oils. Come back when you have them.")
		return
	Global.spend_currency_copper(HEAL_COST)
	heal_fully(player)
	say_local("The Dawn's light on you. Go gently.")


# Full health and mana, every curable ailment gone. Static-free so the tests can call it.
func heal_fully(player: Node) -> int:
	var cn = player.get("combat_node")
	if not (cn is CombatNode):
		return 0
	cn.current_hp = cn.max_hp
	if "current_mana" in cn and "max_mana" in cn:
		cn.current_mana = cn.max_mana
	var cured := 0
	if player.has_method("_find_debuff_to_cure"):
		for i in 30:
			var e: String = player._find_debuff_to_cure(cn)
			if e.is_empty():
				break
			cn.remove_effect(e)
			cured += 1
	GameLog.log_general("[color=#ffee99]Warm light washes over you. You are healed%s.[/color]" % (" and cured" if cured > 0 else ""))
	return cured
