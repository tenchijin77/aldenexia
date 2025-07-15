extends Node

@onready var elira_label: Label = %npc_elira/dialogue_label

var dialogue_queue: Array[String] = [
	"Welcome, traveler... Lumora has waited a long time.",
	"The moon no longer rises. We need your help.",
	"Take this key. Find answers beneath Town Hall."
]

var current_index: int = 0

func _ready() -> void:
	elira_label.visible = false

func start_dialogue() -> void:
	elira_label.visible = true
	elira_label.text = dialogue_queue[current_index]

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") and elira_label.visible:
		current_index += 1
		if current_index < dialogue_queue.size():
			elira_label.text = dialogue_queue[current_index]
		else:
			elira_label.visible = false
			current_index = 0
