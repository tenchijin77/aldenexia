# quests.gd — The small, data-driven quest piece (Data/quests.json). Static, no autoload (patches can't add autoloads): the
# state lives in the character's own save (Global.player_data["quests"]), so it persists per character, on the server too.
# State per quest: not present = never started, "active" (with hand-in progress), "complete".
# Optional per quest: "auto_start": true (picking up or handing in the item starts it), "requires_quest": id (a chain: that quest must be complete),
# "repeatable": true (a finished quest takes a new hand-in and starts over; the first completion pays "rewards", every later
# one "repeat_rewards" — the goblin bounty).
# One objective type, "hand_in": bring items to the quest giver by dragging them onto the NPC (the EverQuest-style Give
# window). Either one item — {"type": "hand_in", "item": id, "count": n} — or several different ones —
# {"type": "hand_in", "items": {id: n, id2: n2}} — handed in in any order, a few at a time. Progress is kept per item in
# the save ("given": {id: n}; "progress" is their total). Or "find": {"type": "find", "item": id} — the quest is done the
# moment that item reaches your bags (The Guildmaster's Note). More types (kill counts, reach a spot) come later.
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


# Total items handed in so far / needed, over every item the quest asks for.
static func progress(id: String) -> int:
	var total := 0
	for item_id in given(id):
		total += int(given(id)[item_id])
	return total


static func needed(id: String) -> int:
	var total := 0
	for item_id in requirements(id):
		total += int(requirements(id)[item_id])
	return total


# What a hand-in quest asks for: {item_id: count} (one entry for the single-item form).
static func requirements(id: String) -> Dictionary:
	var objective: Dictionary = definition(id).get("objective", {})
	if str(objective.get("type", "")) != "hand_in":
		return {}
	if typeof(objective.get("items")) == TYPE_DICTIONARY:
		var out := {}
		for item_id in objective["items"]:
			out[str(item_id)] = int(objective["items"][item_id])
		return out
	if str(objective.get("item", "")) != "":
		return {str(objective["item"]): int(objective.get("count", 1))}
	return {}


# How many of each item have been handed in: {item_id: n}. Saves from before multi-item quests only have "progress" (one
# number), which belongs to the quest's single item.
static func given(id: String) -> Dictionary:
	var entry := _entry(id)
	if typeof(entry.get("given")) == TYPE_DICTIONARY:
		return entry["given"]
	var reqs := requirements(id)
	if reqs.size() == 1 and int(entry.get("progress", 0)) > 0:
		return {reqs.keys()[0]: int(entry["progress"])}
	return {}


static func asks_for(id: String, item_id: String) -> bool:
	return requirements(id).has(item_id)


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
				lines.append("[color=#ffdd44]%s[/color] — %s (%s)" % [def.get("name", id), def.get("short", def.get("summary", "")), item_progress_text(id)])
			"complete":
				lines.append("[color=#88cc88]%s — completed[/color]" % def.get("name", id))
	return lines


static func progress_summary(giver: String) -> String:
	for id in _quests():
		var def := definition(id)
		if state(id) == "active" and def.get("giver", "") == giver:
			return "%s: %s" % [def.get("name", id), item_progress_text(id)]
	return ""


# "3 / 6" for a single-item quest; "Lock of Hair 1/1, Small Tin Cup 0/1" when it asks for several items.
static func item_progress_text(id: String) -> String:
	var reqs := requirements(id)
	if reqs.size() <= 1:
		return "%d / %d" % [progress(id), needed(id)]
	var parts: Array = []
	for item_id in reqs:
		parts.append("%s %d/%d" % [Inventory.get_item_definition(item_id).get("name", item_id), int(given(id).get(item_id, 0)), int(reqs[item_id])])
	return ", ".join(parts)


# A hand-in through the Give window. Returns {result, given, need, taken, text} where result is
#   "wrong_item" | "not_started" | "already_done" | "progress" | "complete" (quest_id is set when a quest is involved).
static func try_hand_in(giver: String, item_id: String, player: Node) -> Dictionary:
	var involved := ""
	for id in _all_ids():
		if definition(id).get("giver", "") == giver and asks_for(id, item_id):
			involved = id
			if state(id) == "active":
				break   # an active quest wins over another (finished or chained) one that wants the same item
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
	# A repeatable quest that is done starts over with this hand-in.
	if state(involved) == "complete" and bool(def.get("repeatable", false)):
		var times := int(_entry(involved).get("times", 1))
		_quests()[involved] = {"state": "active", "progress": 0, "given": {}, "times": times, "started": Time.get_unix_time_from_system()}
	match state(involved):
		"none":
			return {"result": "not_started", "quest_id": involved, "text": texts.get("not_started", "")}
		"complete":
			return {"result": "already_done", "quest_id": involved, "text": texts.get("already_done", "")}
	var need := needed(involved)
	var item_need := int(requirements(involved).get(item_id, 0))
	var done_of_item := int(given(involved).get(item_id, 0))
	var have := ItemHelper.count(item_id)
	var taken := mini(have, maxi(item_need - done_of_item, 0))
	var item_name: String = str(Inventory.get_item_definition(item_id).get("name", item_id))
	if taken <= 0:
		if done_of_item >= item_need:
			return {"result": "have_enough", "quest_id": involved, "item_name": item_name}
		return {"result": "wrong_item", "quest_id": involved}
	ItemHelper.consume(item_id, taken)
	GameLog.log_general("You give %s %d %s." % [giver, taken, item_name + ("s" if taken != 1 else "")])
	var per_item: Dictionary = given(involved).duplicate()
	per_item[item_id] = done_of_item + taken
	_entry(involved)["given"] = per_item
	_entry(involved)["progress"] = progress(involved)
	if progress(involved) < need:
		Global.save_player_data_to_file()
		return {"result": "progress", "quest_id": involved, "given": progress(involved), "need": need, "taken": taken,
				"text": str(texts.get("progress", "")).replace("{given}", str(progress(involved))).replace("{need}", str(need)).replace("{left}", str(need - progress(involved)))}
	_entry(involved)["state"] = "complete"
	_entry(involved)["completed"] = Time.get_unix_time_from_system()
	var times := int(_entry(involved).get("times", 0))
	_entry(involved)["times"] = times + 1
	_give_rewards(def.get("repeat_rewards", def.get("rewards", {})) if times > 0 else def.get("rewards", {}), player)
	GameLog.log_general("[color=#ffdd44][b]Quest complete:[/b] %s[/color]" % def.get("name", involved))
	Sfx.play("quest_complete")
	for next_id in _all_ids():  # the next step of a chain, if you already carry its item
		if str(definition(next_id).get("requires_quest", "")) == involved:
			for next_item in requirements(next_id):
				if ItemHelper.count(next_item) > 0:
					on_item_gained(next_item)
					break
	return {"result": "complete", "quest_id": involved, "given": need, "need": need, "taken": taken, "text": str(texts.get("complete", ""))}


# Picking up a quest's hand-in item starts an "auto_start" quest (inventory_autoload.gd add_item()), so it is in the journal
# as soon as you have the thing — not only once you hand it in (a one-item hand-in would start and finish in the same
# moment and never show as pending). A later step of a chain waits until the earlier quest is complete.
static func on_item_gained(item_id: String) -> void:
	for id in _all_ids():
		var def := definition(id)
		var objective: Dictionary = def.get("objective", {})
		if str(objective.get("type", "")) == "find" and str(objective.get("item", "")) == item_id and state(id) != "complete":
			if state(id) == "none":
				start(id)
			_entry(id)["state"] = "complete"
			_entry(id)["completed"] = Time.get_unix_time_from_system()
			var text := str(def.get("texts", {}).get("complete", ""))
			if not text.is_empty():
				GameLog.log_general("[color=#e8dcc0]%s[/color]" % text)
			_give_rewards(def.get("rewards", {}), TargetFrame.local_player())
			GameLog.log_general("[color=#ffdd44][b]Quest complete:[/b] %s[/color]" % def.get("name", id))
			Sfx.play("quest_complete")
			continue
		if state(id) != "none" or not bool(def.get("auto_start", false)) or not asks_for(id, item_id):
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
				"requirements": requirements(id), "given": given(id),
				"started": float(entry.get("started", 0.0)), "completed": float(entry.get("completed", 0.0))})
	return out
