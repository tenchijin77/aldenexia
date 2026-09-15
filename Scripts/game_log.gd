# game_log.gd — Autoload signal bus for all in-game messages
extends Node

signal general_message(text: String)
# has_position/position let game_log_window.gd filter out combat noise from
# fights the player isn't near (e.g. a guard NPC's own battles clear across
# the zone) without every call site needing to know about that filtering —
# has_position false (the default, e.g. the player's own combat) always shows.
signal combat_message(text: String, has_position: bool, position: Vector3)
signal autoattack_changed(active: bool)


func log_general(text: String) -> void:
	emit_signal("general_message", text)


func log_combat(text: String, source_position: Variant = null) -> void:
	if source_position == null:
		emit_signal("combat_message", text, false, Vector3.ZERO)
	else:
		emit_signal("combat_message", text, true, source_position)


func set_autoattack(active: bool) -> void:
	emit_signal("autoattack_changed", active)
