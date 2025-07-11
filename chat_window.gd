extends Control

@onready var chat_output = $VBoxContainer/ChatOutput
@onready var chat_input = $VBoxContainer/ChatInput
@onready var http_request = $HTTPRequest
@onready var player = get_tree().get_nodes_in_group("player")[0]

var is_chat_active = false
var current_faction = ""
var current_npc_name = ""
var api_key = "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"  # Your updated OpenAI API key
var game_context = """
Game: Aldenexia: The Sword of Light, a 2D RPG inspired by Ultima and EverQuest.
World: Aldenexia, a medieval fantasy realm with kingdoms, forests, and ruins.
Lore: Aldenexia was forged by gods; the Void threatens it. The player seeks the Sword of Light.
Factions:
- Order of Light: Noble knights, protect Aldenexia, tied to the Sword of Light.
- Shadow Guild: Secretive rogues, seek the Void’s power.
- Villagers of Lumora: Neutral townsfolk, wary of conflict.
Controls: Move with WASD/arrow keys. H to hail NPCs. E to interact. I for inventory.
NPC Role: A villager in Lumora, speaks in a medieval tone unless hostile.
Faction Standing Effects:
- Positive (>100): Friendly, helpful, may offer quests.
- Neutral (0 to 100): Indifferent, basic responses.
- Negative (<0): Curt or hostile, may refuse to help.
"""

func _ready():
	if not chat_output or not chat_input or not http_request:
		print("Error: Chat window nodes not found!")
		return
	chat_output.text = "[color=green][Welcome to Aldenexia][/color]\n"
	chat_input.visible = false
	http_request.request_completed.connect(_on_request_completed)
	connect_to_npc()

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
	if not is_chat_active:
		is_chat_active = true
		chat_input.visible = true
		var standing = player.get_faction_standing(faction)
		var tone = "friendly"
		if standing < 0:
			tone = "hostile"
		elif standing <= 100:
			tone = "neutral"
		chat_output.append_text("[color=yellow]You say, 'Hail, %s'[/color]\n" % npc_name)
		chat_output.append_text("[color=cyan]%s says, 'Hail, adventurer! %s asks thy purpose. (Type and press Enter)'[/color]\n" % [npc_name, tone.capitalize()])
		chat_input.grab_focus()
	else:
		_reset_chat()

func _input(event):
	if is_chat_active and event.is_action_pressed("ui_accept"):
		var message = chat_input.text.strip_edges()
		if message != "":
			chat_output.append_text("[color=yellow]You say, '%s'[/color]\n" % message)
			_handle_player_message(message)
		chat_input.text = ""

func _handle_player_message(message):
	var standing = player.get_faction_standing(current_faction) # Use current_faction here
	chat_output.append_text("[color=cyan]%s says, 'Let me think...'[/color]\n" % current_npc_name)
	_send_to_openai(message, standing)

func _send_to_openai(message, standing):
	var headers = ["Content-Type: application/json", "Authorization: Bearer " + api_key]
	var context_with_standing = game_context + "\nPlayer's standing with %s: %d\nNPC Name: %s" % [current_faction, standing, current_npc_name]
	var body = JSON.stringify({
		"model": "gpt-3.5-turbo",
		"messages": [
			{"role": "system", "content": context_with_standing},
			{"role": "user", "content": message}
		],
		"max_tokens": 150,
		"temperature": 0.7
	})
	var error = http_request.request("https://api.openai.com/v1/chat/completions", headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		chat_output.append_text("[color=red]%s says, 'Alas, something went wrong!'[/color]\n" % current_npc_name)

func _on_request_completed(result, response_code, headers, body):
	if response_code == 200:
		var json = JSON.parse_string(body.get_string_from_utf8())
		var response = json["choices"][0]["message"]["content"]
		chat_output.append_text("[color=cyan]%s says, '%s'[/color]\n" % [current_npc_name, response])
	else:
		chat_output.append_text("[color=red]%s says, 'Alas, my wisdom fails me.'[/color]\n" % current_npc_name)

func _reset_chat():
	is_chat_active = false
	chat_input.visible = false
	chat_output.append_text("[color=green]Conversation ended.[/color]\n")
