# quests.gd — The small, data-driven quest piece (Data/quests.json). Static, no autoload (patches can't add autoloads): the
# state lives in the character's own save (Global.player_data["quests"]), so it persists per character, on the server too.
# State per quest: not present = never started, "active" (with hand-in progress), "complete".
# Optional per quest: "auto_start": true (picking up or handing in the item starts it), "requires_quest": id (a chain: that quest must be complete).
# v1 supports one objective type, "hand_in": bring N of an item to the quest giver — by dragging the items onto the NPC (the
# EverQuest-style Give window) — which is what "Release the Hollowed" needs. More types (kill counts, reach a spot) come later.
class_name Quests
extends RefCounted

const DATA_PATH := "res://Data/quests.json"
const SAVE_KEY := "quests"

static var _data: Dictionary = {}
static var _loaded := false


static func definition(id: String) -> Dictionary:
	if not _loaded:
		_loaded = true
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH)) if FileAccess.file_exists(DATA_PATH) else null
		_data = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	return _data.get(id, {})


# "none" (never started), "active" or "complete".
static func state(id: String) -> String:
	return str(_entry(id).get("state", "none"))


static func progress(id: String) -> int:
	return int(_entry(id).get("progress", 0))


static func needed(id: String) -> int:
	return int(definition(id).get("objective", {}).get("count", 0))


static func start(id: String) -> bool:
	if definition(id).is_empty() or state(id) != "none":
		return false
	_quests()[id] = {"state": "active", "progress": 0, "started": Time.get_unix_time_from_system()}
	Global.save_player_data_to_file()
	GameLog.log_general("[color=#ffdd44][b]Quest started:[/b] %s[/color] [color=#aaaaaa](added to your journal — press J)[/color]" % definition(id).get("name", id))
	Sfx.play("quest_received")
	GameLog.log_general("[color=#cccccc]%s[/color]" % definition(id).get("summary", ""))
	return true


# One line per active quest, for /quests and the Give window.
static func journal_lines() -> Array:
	var lines: Array = []
	for id in _quests():
		var def := definition(id)
		match state(id):
			"active":
				lines.append("[color=#ffdd44]%s[/color] — %s (%d / %d)" % [def.get("name", id), def.get("short", def.get("summary", "")), progress(id), needed(id)])
			"complete":
				lines.append("[color=#88cc88]%s — completed[/color]" % def.get("name", id))
	return lines


static func progress_summary(giver: String) -> String:
	for id in _quests():
		var def := definition(id)
		if state(id) == "active" and def.get("giver", "") == giver:
			return "%s: %d / %d" % [def.get("name", id), progress(id), needed(id)]
	return ""


# A hand-in through the Give window. Returns {result, given, need, taken, text} where result is
#   "wrong_item" | "not_started" | "already_done" | "progress" | "complete" (quest_id is set when a quest is involved).
static func try_hand_in(giver: String, item_id: String, player: Node) -> Dictionary:
	var involved := ""
	for id in _all_ids():
		var def := definition(id)
		if def.get("giver", "") == giver and def.get("objective", {}).get("item", "") == item_id:
			involved = id
			break
	if involved == "":
		return {"result": "wrong_item"}
	var def := definition(involved)
	var texts: Dictionary = def.get("texts", {})
	# A later step of a chain: the earlier quest has to be complete first.
	var prerequisite: String = str(def.get("requires_quest", ""))
	if not prerequisite.is_empty() and state(prerequisite) != "complete" and state(involved) == "none":
		return {"result": "not_started", "quest_id": involved, "text": texts.get("not_started", "")}
	# "auto_start": bringing the item is answer enough (you found it before you were asked), so it starts the quest itself.
	if state(involved) == "none" and bool(def.get("auto_start", false)):
		start(involved)
	match state(involved):
		"none":
			return {"result": "not_started", "quest_id": involved, "text": texts.get("not_started", "")}
		"complete":
			return {"result": "already_done", "quest_id": involved, "text": texts.get("already_done", "")}
	var need := needed(involved)
	var have := ItemHelper.count(item_id)
	var taken := mini(have, maxi(need - progress(involved), 0))
	if taken <= 0:
		return {"result": "wrong_item", "quest_id": involved}
	ItemHelper.consume(item_id, taken)
	var item_name: String = str(Inventory.get_item_definition(item_id).get("name", item_id))
	GameLog.log_general("You give %s %d %s." % [giver, taken, item_name + ("s" if taken != 1 else "")])
	_entry(involved)["progress"] = progress(involved) + taken
	if progress(involved) < need:
		Global.save_player_data_to_file()
		return {"result": "progress", "quest_id": involved, "given": progress(involved), "need": need, "taken": taken,
				"text": str(texts.get("progress", "")).replace("{given}", str(progress(involved))).replace("{need}", str(need)).replace("{left}", str(need - progress(involved)))}
	_entry(involved)["state"] = "complete"
	_entry(involved)["completed"] = Time.get_unix_time_from_system()
	_give_rewards(def.get("rewards", {}), player)
	GameLog.log_general("[color=#ffdd44][b]Quest complete:[/b] %s[/color]" % def.get("name", involved))
	Sfx.play("quest_complete")
	for next_id in _all_ids():  # the next step of a chain, if you already carry its item
		if str(definition(next_id).get("requires_quest", "")) == involved:
			var next_item := str(definition(next_id).get("objective", {}).get("item", ""))
			if not next_item.is_empty() and ItemHelper.count(next_item) > 0:
				on_item_gained(next_item)
	return {"result": "complete", "quest_id": involved, "given": need, "need": need, "taken": taken, "text": str(texts.get("complete", ""))}


# Picking up a quest's hand-in item starts an "auto_start" quest (inventory_autoload.gd add_item()), so it is in the journal
# as soon as you have the thing — not only once you hand it in (a one-item hand-in would start and finish in the same
# moment and never show as pending). A later step of a chain waits until the earlier quest is complete.
static func on_item_gained(item_id: String) -> void:
	for id in _all_ids():
		var def := definition(id)
		if state(id) != "none" or not bool(def.get("auto_start", false)) or def.get("objective", {}).get("item", "") != item_id:
			continue
		var prerequisite := str(def.get("requires_quest", ""))
		if not prerequisite.is_empty() and state(prerequisite) != "complete":
			continue
		start(id)


# Whether a quest has been started (or finished) — for world objects that only react the first time.
static func is_started(id: String) -> bool:
	return state(id) != "none"


static func _give_rewards(rewards: Dictionary, player: Node) -> void:
	for field in rewards.get("coin", {}):
		Global.grant_currency(field, int(rewards["coin"][field]))
		GameLog.log_general("[color=#ffdd88]You receive %d %s.[/color]" % [int(rewards["coin"][field]), field])
	for entry in rewards.get("items", []):
		Inventory.add_item(str(entry.get("id", "")), int(entry.get("qty", 1)))
	if int(rewards.get("xp", 0)) > 0 and is_instance_valid(player) and player.has_method("grant_xp"):
		player.grant_xp(int(rewards["xp"]))
	Global.save_player_data_to_file()


static func _all_ids() -> Array:
	definition("")  # makes sure the file is loaded
	return _data.keys().filter(func(k): return typeof(_data[k]) == TYPE_DICTIONARY)


static func _quests() -> Dictionary:
	if not Global.player_data.has(SAVE_KEY) or typeof(Global.player_data[SAVE_KEY]) != TYPE_DICTIONARY:
		Global.player_data[SAVE_KEY] = {}
	return Global.player_data[SAVE_KEY]


static func _entry(id: String) -> Dictionary:
	var q := _quests()
	return q[id] if q.has(id) and typeof(q[id]) == TYPE_DICTIONARY else {}


# Every quest the character has been given, for the journal (quest_journal.gd): [{id, def, state, progress, needed,
# started, completed}]. "started"/"completed" are unix times (0 for quests started before they were recorded).
static func journal_entries() -> Array:
	var out: Array = []
	for id in _quests():
		var entry := _entry(id)
		var def := definition(id)
		if def.is_empty():
			continue
		out.append({"id": id, "def": def, "state": state(id), "progress": progress(id), "needed": needed(id),
				"started": float(entry.get("started", 0.0)), "completed": float(entry.get("completed", 0.0))})
	return out
