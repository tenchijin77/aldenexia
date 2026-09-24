# game_log.gd — Autoload signal bus for all in-game messages
extends Node

signal general_message(text: String)
# The same messages with a CATEGORY (say, tell, party, zone, npc, loot, xp, skill, quest, system): what the chat window's tabs filter on.
signal message_categorized(category: String, text: String)
# has_position/position let game_log_window.gd filter out combat noise from
# fights the player isn't near (e.g. a guard NPC's own battles clear across
# the zone) without every call site needing to know about that filtering —
# has_position false (the default, e.g. the player's own combat) always shows.
signal combat_message(text: String, has_position: bool, position: Vector3)
signal autoattack_changed(active: bool)


# `category` is optional: without it the line is classified from its wording (classify() below), so existing call sites need no change.
func log_general(text: String, category: String = "") -> void:
	emit_signal("general_message", text)
	emit_signal("message_categorized", category if category != "" else classify(text), text)


func log_combat(text: String, source_position: Variant = null) -> void:
	if source_position == null:
		emit_signal("combat_message", text, false, Vector3.ZERO)
	else:
		emit_signal("combat_message", text, true, source_position)


func set_autoattack(active: bool) -> void:
	emit_signal("autoattack_changed", active)


# Which category a general line belongs to, judged from its wording and colour (the chat channels have their own colours, see
# ChatChannels). Anything unrecognised is "system". Adjust the patterns here when a new kind of line should filter on its own.
func classify(text: String) -> String:
	# The four chat channels (chat_channels.gd wraps each line in its channel colour).
	if text.begins_with("[color=#ffe066]") and (text.contains(" says, ") or text.contains("You say")):
		return "say"
	if text.begins_with("[color=#cc88ff]") and (text.contains(" tells you") or text.contains("You tell ")):
		return "tell"
	if text.begins_with("[color=#88ccff]") and text.contains("[Party]"):
		return "party"
	if text.begins_with("[color=#ff9944]") and (text.contains(" shouts, ") or text.contains("You shout")):
		return "zone"
	# An NPC talking or emoting (guards, vendors, the harbour master, the merchant...).
	if (text.contains(" says, ") or text.contains(" shouts, ")) and text.contains("\"") or text.begins_with("[color=#ffd9a0]"):
		return "npc"
	if text.contains("experience points") or text.contains("You are now level") or text.contains("reached level"):
		return "xp"
	if text.contains("You've become better at"):
		return "skill"
	if text.contains("Quest started") or text.contains("Quest complete") or text.contains("— completed"):
		return "quest"
	if (text.begins_with("[color=#ffdd44]") or text.begins_with("[color=#cccccc]")) and text.contains(" — "):
		return "quest"   # a line of the /quests journal
	if text.contains("You receive ") or text.contains("automatically loot") or text.contains("You loot ") or text.contains("You search the corpse"):
		return "loot"
	return "system"
