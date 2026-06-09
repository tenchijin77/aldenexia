# game_log.gd — Autoload signal bus for all in-game messages
extends Node

signal general_message(text: String)
signal combat_message(text: String)
signal autoattack_changed(active: bool)


func log_general(text: String) -> void:
	emit_signal("general_message", text)


func log_combat(text: String) -> void:
	emit_signal("combat_message", text)


func set_autoattack(active: bool) -> void:
	emit_signal("autoattack_changed", active)
