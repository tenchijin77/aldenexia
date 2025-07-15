extends Control

@onready var chat_output = $VBoxContainer/ScrollContainer/ChatOutput
@onready var chat_input = $VBoxContainer/ChatInput
@onready var player = get_tree().get_nodes_in_group("player")[0]

var current_faction = ""
var current_npc_name = ""
var dialogue_data = {}

func get_is_chat_active():
	return Global.is_chat_active

func _ready():
	if not chat_output or not chat_input:
		print("Error: Chat window nodes not found! chat_output: ", chat_output, " chat_input: ", chat_input)
		return

	print("Chat window initialized: chat_output=", chat_output.name, " chat_input=", chat_input.name)

	chat_output.text = "[color=green][Welcome to Aldenexia][/color]\n"
	chat_input.visible = false
	chat_output.add_theme_font_size_override("normal_font_size", 16)

	# Connect signals
	chat_input.text_submitted.connect(_on_chat_input_text_submitted)
	Global.connect("chat_state_changed", Callable(self, "_on_chat_state_changed"))

	load_dialogue_data()
	connect_to_npc()

func _on_chat_state_changed(is_active):
	chat_input.visible = is_active
	chat_output.visible = is_active
	if is_active:
		chat_input.grab_focus()
	else:
		chat_output.append_text("[color=green]Conversation ended.[/color]\n")

func load_dialogue_data():
	var file = FileAccess.open("res://Data/dialogue.json", FileAccess.READ)
	if file:
		var json_text = file.get_as_text()
		print("JSON text loaded from res://Data/dialogue.json: ", json_text)
		var json = JSON.new()
		var error = json.parse(json_text)
		if error == OK:
			dialogue_data = json.data
			print("Dialogue data loaded: ", dialogue_data)
		else:
			print("Error parsing dialogue.json: ", json.get_error_message(), " at line ", json.get_error_line())
		file.close()
	else:
		print("Error: Could not open res://Data/dialogue.json! Check the file path.")

func connect_to_npc():
	var npcs = get_tree().get_nodes_in_group("npc")
	if npcs.size() > 0:
		npcs[0].hailed.connect(_on_npc_hailed)
		print("Connected to NPC: ", npcs[0].name)
	else:
		print("Warning: No NPC found in 'npc' group. Check scene or group assignment.")

func _on_npc_hailed(faction, npc_name):
	current_faction = faction
	current_npc_name = npc_name

	if not Global.is_chat_active:
		Global.is_chat_active = true

		var standing = player.get_faction_standing(faction)
		var tone = "friendly"
		if standing < 0:
			tone = "hostile"
		elif standing <= 100:
			tone = "neutral"

		chat_output.append_text("[color=yellow]Hail, %s![/color]\n" % npc_name)
		chat_output.append_text("[color=cyan]%s says, 'Hail, adventurer! %s asks thy purpose. (Type and press Enter)'[/color]\n" % [npc_name, tone.capitalize()])
		chat_input.grab_focus()
	else:
		_reset_chat()

func _on_chat_input_text_submitted(message: String):
	message = message.strip_edges()
	if message != "":
		chat_output.append_text("[color=yellow]You say, '%s'[/color]\n" % message)
		_handle_player_message(message)
	chat_input.text = ""

func _handle_player_message(message):
	var standing = player.get_faction_standing(current_faction)
	var tone = "friendly"
	if standing < 0:
		tone = "hostile"
	elif standing <= 100:
		tone = "neutral"

	var response = "I understand thee not, adventurer."

	if dialogue_data.has("factions"):
		for faction in dialogue_data["factions"]:
			if faction["name"] == current_faction:
				for dialogue in faction["dialogue"][tone]:
					for keyword in dialogue["keywords"]:
						if keyword.to_lower() in message.to_lower():
							response = dialogue["response"]
							break
					if response != "I understand thee not, adventurer.":
						break

				# Check for farewell
				if "bye" in message.to_lower() or "farewell" in message.to_lower():
					response = "Fare thee well, adventurer! May thy path be safe."
					_reset_chat()
					break
				break
	else:
		print("Error: dialogue_data missing 'factions'. Data: ", dialogue_data)

	chat_output.append_text("[color=cyan]%s says, '%s'[/color]\n" % [current_npc_name, response])

func _reset_chat():
	Global.is_chat_active = false
	chat_input.text = ""

func _input(event):
	if Global.is_chat_active:
		if event.is_action_pressed("ui_up"):
			var scroll_container = chat_output.get_parent()
			if scroll_container is ScrollContainer:
				scroll_container.scroll_vertical -= 20
		elif event.is_action_pressed("ui_down"):
			var scroll_container = chat_output.get_parent()
			if scroll_container is ScrollContainer:
				scroll_container.scroll_vertical += 20
