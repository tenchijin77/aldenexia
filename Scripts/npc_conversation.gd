# npc_conversation.gd — EverQuest-style keyword conversations. An NPC's JSON has a "topics" list; each topic has keywords and
# lines. When the local player SAYS something near the NPC (typed with /say, or a highlighted word clicked in the chat), the
# first topic whose keyword appears in what was said, and whose conditions hold, is answered. Words the NPC wants you to pick up
# are written {like this} in its lines and shown highlighted and clickable in the chat.
#
# A topic:
#   "id"        a name (also what tests look for)
#   "keywords"  words/phrases that trigger it (whole words, case-insensitive; multi-word phrases work)
#   "lines"     one of these is said (picked at random)      -or-
#   "sequence"  all of these are said in order, a moment apart -or-
#   "category"  lines come from the NPC's own line pool of that name (e.g. "secret")  -or-
#   "dynamic"   lines come from the NPC's dynamic_lines(name)
#   "requires"  {"quest": id, "quest_state": "none|active|complete", "has_item": id, "no_item": id, "night": true|false}
#   "then"      {"start_quest": id, "open_shop": true, "hail": true} — done after the lines
# Order matters: the first matching topic whose requirements hold wins, so put the more specific topics first.
# Replies are private to the speaking player (each client's own NPC node answers its own player).
class_name NPCConversation
extends RefCounted

const TALK_RANGE := 9.0
const LINE_DELAY := 2.4
const KEYWORD_COLOR := "#ffe08a"

var _npc: Node3D
var _topics: Array = []
var _busy := false


func _init(npc: Node3D, topics: Array) -> void:
	_npc = npc
	_topics = topics


# {word} -> a clickable, highlighted word. Clicking says the word (see GameLogWindow._on_meta_clicked).
static func format(line: String) -> String:
	var out := line
	var regex := RegEx.create_from_string("\\{([^}]+)\\}")
	for m in regex.search_all(line):
		var word := m.get_string(1)
		out = out.replace(m.get_string(0), "[url=kw:%s][color=%s]%s[/color][/url]" % [word, KEYWORD_COLOR, word])
	return out


# The line without the {} markers, for logs and tests.
static func plain(line: String) -> String:
	return line.replace("{", "").replace("}", "")


# " lower case words " — punctuation becomes spaces, apostrophes stay, so phrases match on word boundaries.
static func normalise(text: String) -> String:
	var lowered := text.to_lower()
	var out := ""
	for ch in lowered:
		out += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "'" else " "
	return " " + " ".join(out.split(" ", false)) + " "


func find_topic(text: String) -> Dictionary:
	var heard := normalise(text)
	for topic in _topics:
		if not _conditions_met(topic.get("requires", {})):
			continue
		for keyword in topic.get("keywords", []):
			if heard.contains(normalise(str(keyword))):
				return topic
	return {}


func hear(player: Node3D, text: String) -> void:
	if _busy or not is_instance_valid(_npc) or not is_instance_valid(player):
		return
	if player.global_position.distance_to(_npc.global_position) > TALK_RANGE:
		return
	var topic := find_topic(text)
	if not topic.is_empty():
		await run_topic(player, topic)


func run_topic(player: Node3D, topic: Dictionary) -> void:
	_busy = true
	if _npc.has_method("face_player"):
		_npc.face_player()
	var lines: Array = []
	if topic.has("sequence"):
		lines = topic["sequence"]
	elif topic.has("lines"):
		lines = [topic["lines"][randi() % topic["lines"].size()]] if not topic["lines"].is_empty() else []
	elif topic.has("category") or topic.has("dynamic"):
		var pool: Array = _npc.dynamic_lines(str(topic.get("dynamic", topic.get("category", "")))) if _npc.has_method("dynamic_lines") else []
		lines = [pool[randi() % pool.size()]] if not pool.is_empty() else []
	for i in lines.size():
		if not is_instance_valid(_npc):
			_busy = false
			return
		if i > 0:
			await _npc.get_tree().create_timer(LINE_DELAY).timeout
		if is_instance_valid(_npc):
			_npc.speak(str(lines[i]))
	_busy = false
	if not is_instance_valid(_npc):
		return
	var then: Dictionary = topic.get("then", {})
	if then.has("start_quest"):
		Quests.start(str(then["start_quest"]))
	if then.get("open_shop", false) and player.has_method("open_shop_window") and _npc.has_method("can_trade") and _npc.can_trade():
		player.open_shop_window(_npc)
	if then.get("hail", false) and _npc.has_method("respond_to_hail"):
		_npc.respond_to_hail()


func _conditions_met(req: Dictionary) -> bool:
	if req.is_empty():
		return true
	if req.has("quest") and Quests.state(str(req["quest"])) != str(req.get("quest_state", "active")):
		return false
	if req.has("has_item") and ItemHelper.count(str(req["has_item"])) <= 0:
		return false
	if req.has("no_item") and ItemHelper.count(str(req["no_item"])) > 0:
		return false
	if req.has("night") and is_night(_npc.get_tree()) != bool(req["night"]):
		return false
	return true


static func is_night(tree: SceneTree) -> bool:
	var cycles := tree.get_nodes_in_group("day_night_cycle")
	return not cycles.is_empty() and cycles[0].has_method("is_day") and not cycles[0].is_day()
