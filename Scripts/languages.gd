# languages.gd — spoken languages (Data/languages.json). Every character is fluent in some languages and learning others
# (Global.player_data["languages"]: id -> skill 0-100). Speech in a language you only partly know shows up partly
# scrambled — the same word always scrambles the same way, in that language's own sound — and short everyday words come
# through first. Dialects ("related") partly understand each other. Skill grows slowly by hearing a language (players, NPCs,
# monsters) and by speaking it where someone who knows it can hear; intelligence and wisdom speed it up; no level cap.
# A low-skill speaker mispronounces: even fluent listeners see some of their words garbled.
#
# Player chat carries its language inside the message text (encode()/decode(); Net's chat RPCs are unchanged), so this is
# all client-side: the sender picks and pronounces, each listener scrambles for themself (ChatChannels.*_other()).
class_name Languages

const MARK := "\u001e"          # message = MARK + language id + MARK + text
const PRACTICE_COOLDOWN_MS := 4000  # one practice roll per language this often (no leveling by spam)

static var _data: Dictionary = {}
static var _last_practice: Dictionary = {}  # language id -> msec


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://Data/languages.json"))
		_data = parsed if typeof(parsed) == TYPE_DICTIONARY else {"languages": {"common": {"name": "Common", "syllables": ["la"]}}}
	return _data


static func exists(id: String) -> bool:
	return data()["languages"].has(id)


static func display(id: String) -> String:
	return str(data()["languages"].get(id, {}).get("name", id.capitalize()))


static func ids() -> Array:
	return data()["languages"].keys()


# Finds a language by id or display name, loosely ("khuzdul", "Kry'thuun", "old thallian", "cant").
static func find(name: String) -> String:
	var wanted := name.strip_edges().to_lower().replace("'", "").replace(" ", "_")
	for id in ids():
		var shown := display(id).to_lower().replace("'", "").replace(" ", "_")
		if id == wanted or shown == wanted or shown.begins_with(wanted):
			return id
	return ""


# ── The local character's skills ──
static func skills() -> Dictionary:
	if typeof(Global.player_data.get("languages")) != TYPE_DICTIONARY:
		Global.player_data["languages"] = {}
	return Global.player_data["languages"]


static func skill(id: String) -> float:
	return float(skills().get(id, 0.0))


# A new (or pre-languages) character gets its race's starting languages.
static func ensure_started(race: String) -> void:
	var mine := skills()
	if not mine.is_empty():
		return
	var start: Dictionary = data().get("race_start", {}).get(race, {"common": 100})
	for id in start:
		mine[id] = float(start[id])


# How much of `id` the local character understands: its own skill, or a related dialect's skill x the relation.
static func understanding(id: String) -> float:
	var best := skill(id)
	var related: Dictionary = data()["languages"].get(id, {}).get("related", {})
	for other in related:
		best = maxf(best, skill(str(other)) * float(related[other]))
	return clampf(best, 0.0, 100.0)


# Languages the local character can speak (any skill at all), best first.
static func speakable() -> Array:
	var list: Array = skills().keys().filter(func(id): return exists(str(id)) and skill(str(id)) >= 1.0)
	list.sort_custom(func(a, b): return skill(str(a)) > skill(str(b)))
	return list


# The language plain chat goes out in: the one picked in the chat window, else Common if you speak it well, else your best.
static func speaking() -> String:
	var picked := str(Global.player_data.get("speaking_language", ""))
	if exists(picked) and skill(picked) >= 1.0:
		return picked
	if skill("common") >= 50.0:
		return "common"
	var list := speakable()
	return str(list[0]) if not list.is_empty() else "common"


static func set_speaking(id: String) -> void:
	Global.player_data["speaking_language"] = id
	_refresh_open_book()


# An open abilities book lists your languages (which one you speak, their skill): rebuild it when either changes.
static func _refresh_open_book() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var player := TargetFrame.local_player()
	if tree == null or not is_instance_valid(player):
		return
	for node in tree.root.get_children():
		if node is AbilitiesBook:
			node.set_player(player)


# ", in Khuzdul" — added after "says"/"shouts"/"tells you" for anything but Common.
static func tag(id: String) -> String:
	return "" if id == "common" or id.is_empty() else ", in %s" % display(id)


# ── Chat wire format ──
static func encode(id: String, text: String) -> String:
	return MARK + id + MARK + text


static func decode(message: String) -> Array:
	if message.begins_with(MARK):
		var end := message.find(MARK, 1)
		if end > 0:
			var id := message.substr(1, end - 1)
			return [id if exists(id) else "common", message.substr(end + 1)]
	return ["common", message]


# ── Scrambling ──
# Word "difficulty" 0-99, fixed per word; short words are easy, so they're understood (and pronounced) first.
static func _difficulty(core: String) -> float:
	var d := float(absi(core.to_lower().hash()) % 100)
	if core.length() <= 3:
		d *= 0.35
	elif core.length() <= 5:
		d *= 0.7
	return d


static func _gibberish(core: String, id: String) -> String:
	var syllables: Array = data()["languages"].get(id, {}).get("syllables", ["la"])
	var rng := RandomNumberGenerator.new()
	rng.seed = (core.to_lower() + "|" + id).hash()
	var word := ""
	var target := maxi(2, core.length())
	while word.length() < target:
		word += str(syllables[rng.randi() % syllables.size()])
	if word.length() > target + 3:
		word = word.substr(0, target + 2)
	if core.substr(0, 1) != core.substr(0, 1).to_lower():
		word = word.substr(0, 1).to_upper() + word.substr(1)
	return word


static var _word_re: RegEx = null

# Replaces every word whose difficulty is `threshold` or more with its gibberish. {keywords} (NPC conversation links) and
# markup stay as they are, so they keep working.
static func _garble(text: String, id: String, threshold: float) -> String:
	if threshold >= 100.0:
		return text
	if _word_re == null:
		_word_re = RegEx.new()
		_word_re.compile("^([^\\p{L}\\p{N}]*)([\\p{L}\\p{N}'-]+)([^\\p{L}\\p{N}]*)$")
	var out: Array = []
	for token in text.split(" "):
		if token.contains("{") or token.contains("}") or token.contains("[") or token.contains("]"):
			out.append(token)
			continue
		var m := _word_re.search(token)
		if m == null or _difficulty(m.get_string(2)) < threshold:
			out.append(token)
			continue
		out.append(m.get_string(1) + _gibberish(m.get_string(2), id) + m.get_string(3))
	return " ".join(out)


# What the local character hears of `text` in language `id` (and a chance to learn from it).
static func hear(id: String, text: String) -> String:
	if id.is_empty() or not exists(id):
		return text
	practice(id)
	return _garble(text, id, understanding(id))


# What the local character actually SAYS when speaking `id`: words beyond their skill come out mispronounced.
static func pronounce(id: String, text: String) -> String:
	var margin := float(data().get("learning", {}).get("mispronounce_margin", 25))
	return _garble(text, id, skill(id) + margin)


# ── Learning ──
static func practice(id: String) -> void:
	var s := skill(id)
	if s < 1.0 or s >= 100.0:
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_practice.get(id, -PRACTICE_COOLDOWN_MS)) < PRACTICE_COOLDOWN_MS:
		return
	_last_practice[id] = now
	var learning: Dictionary = data().get("learning", {})
	var mind := 20.0
	var p: Node = TargetFrame.local_player()
	if is_instance_valid(p) and p.get("combat_node") != null:
		mind = float(p.combat_node.intelligence + p.combat_node.wisdom)
	var chance := float(learning.get("base_chance", 0.08)) * (1.0 - s / 100.0) * maxf(0.25, 1.0 + (mind - 20.0) / float(learning.get("stat_divisor", 40.0)))
	if randf() < chance:
		skills()[id] = minf(100.0, floorf(s) + 1.0)
		GameLog.log_general("[color=#ffff66]You've become better at %s! (%d)[/color]" % [display(id), int(skills()[id])])
		_refresh_open_book()


# A scroll of a language's basics: starts it at 1 point.
static func learn_basics(id: String) -> bool:
	if not exists(id):
		return false
	if skill(id) >= 1.0:
		GameLog.log_general("You already know some %s." % display(id))
		return false
	skills()[id] = 1.0
	GameLog.log_general("[color=#ffdd44]You learn the basics of %s. Listen to it spoken, and speak it, to learn more.[/color]" % display(id))
	return true


# ── Monsters and NPCs ──
# A monster's language: "language" in monsters.json, else its category's default (humanoids Common, undead Old Thallian);
# animals and the like speak none ("").
static func of_monster(monster_name: String, category: String) -> String:
	var monsters = JSON.parse_string(FileAccess.get_file_as_string("res://Data/monsters.json")) if not _monster_langs_loaded else null
	if not _monster_langs_loaded:
		_monster_langs_loaded = true
		if typeof(monsters) == TYPE_DICTIONARY:
			for key in monsters:
				if typeof(monsters[key]) == TYPE_DICTIONARY and monsters[key].has("language"):
					_monster_langs[key] = str(monsters[key]["language"])
	if _monster_langs.has(monster_name):
		return _monster_langs[monster_name]
	return str(data().get("monster_category_default", {}).get(category, ""))

static var _monster_langs: Dictionary = {}
static var _monster_langs_loaded := false


# ── NPCs ──
# Does this NPC speak (and so understand) language `id`? Its "language" plus any "extra_languages".
static func npc_speaks(npc: Node, id: String) -> bool:
	var main = npc.get("language")
	if main == null:
		return id == "common"
	if str(main) == id:
		return true
	var extra = npc.get("extra_languages")
	return extra is Array and (extra as Array).has(id)


# The language an NPC talks in: the one you last addressed it in (if it speaks it), else its own. Kept on this machine.
static func voice_of(npc: Node) -> String:
	var addressed := str(npc.get_meta("answer_language", ""))
	if not addressed.is_empty() and npc_speaks(npc, addressed):
		return addressed
	return str(npc.get("language")) if npc.get("language") != null else "common"


# Speech built on one machine and shown on others (gate-raid shouts): the line is embedded with its language, and each
# player's machine turns it into what they hear (localize) — TAG_SLOT becomes ", in Goblish" or nothing.
const TAG_SLOT := "\u001f"

static func embed(id: String, line: String) -> String:
	return MARK + id + MARK + line + MARK


static func localize(text: String) -> String:
	var i := text.find(MARK)
	var j := text.find(MARK, i + 1) if i >= 0 else -1
	var k := text.find(MARK, j + 1) if j >= 0 else -1
	if k < 0:
		return text.replace(TAG_SLOT, "")
	var spoken := npc_line(text.substr(i + 1, j - i - 1), text.substr(j + 1, k - j - 1))
	return text.substr(0, i).replace(TAG_SLOT, spoken[0]) + spoken[1] + text.substr(k + 1)


# One line of NPC or monster speech as the local player hears it: `"<name> says, in Khuzdul, \"...\""` pieces. Returns
# [tag, text] — the caller keeps its own colour and verb.
static func npc_line(id: String, line: String) -> Array:
	if id.is_empty() or id == "common" and understanding("common") >= 100.0:
		return ["", line]
	return [tag(id), hear(id, line)]
