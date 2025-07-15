extends Node

signal chat_state_changed(is_active)

var is_chat_active = false:

	set(value):
		is_chat_active = value
		emit_signal("chat_state_changed", is_chat_active)
