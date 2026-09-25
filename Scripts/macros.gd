# macros.gd — EverQuest-style social macros: a named button of up to five chat lines, run top to bottom from the action bar
# (or its hotkey), e.g.
#     /party Rooting %t — don't break it!
#     /cast Entangling Roots
# Each character has CHARACTER_SLOTS macros of its own (saved with the character, "macros") and shares SHARED_SLOTS with
# every character on its account ("shared_macros": a dedicated server keeps them in the account file — net.gd lifts them
# out of each save — and a game with no server keeps them in user://shared_macros.json).
# A macro is {"name", "icon" (a spell's key, whose icon it shows; "" = the first /cast line's spell), "lines": [5 strings]}.
# An action bar slot holds {"type": "macro", "name": "c3"} (character macro 3) or "s3" (shared macro 3).
# In a line: %t = your target's name, %T = target's name, level and health, %s = your own name.
# Lines run at once, except /pause <seconds>; a /cast that fails (no mana, recharging, out of range...) stops the macro,
# so the group is never told about a spell that didn't go off. Running lines go through the chat box
# (GameLogWindow.run_macro_line()), so every chat command works in a macro.
class_name Macros
extends RefCounted

const CHARACTER_SLOTS := 24
const SHARED_SLOTS := 24
const MAX_LINES := 5
const MAX_LINE_LENGTH := 120
const MAX_NAME_LENGTH := 16
const MAX_PAUSE := 10.0
const SHARED_FILE := "user://shared_macros.json"


static func empty_macro() -> Dictionary:
	return {"name": "", "icon": "", "lines": ["", "", "", "", ""]}


static func is_empty_macro(m: Dictionary) -> bool:
	if not str(m.get("name", "")).strip_edges().is_empty():
		return false
	for line in m.get("lines", []):
		if not str(line).strip_edges().is_empty():
			return false
	return true


# A list as the save holds it, cleaned up: exactly `count` macros, names and lines cut to size. Used on load, before
# saving, and by the server on every uploaded save (a save can say anything).
static func sanitize(list: Variant, count: int) -> Array:
	var out: Array = []
	var src: Array = list if typeof(list) == TYPE_ARRAY else []
	for i in count:
		var m: Dictionary = src[i] if i < src.size() and typeof(src[i]) == TYPE_DICTIONARY else {}
		var lines: Array = []
		var src_lines: Array = m.get("lines", []) if typeof(m.get("lines")) == TYPE_ARRAY else []
		for j in MAX_LINES:
			lines.append(str(src_lines[j]).replace("\n", " ").left(MAX_LINE_LENGTH) if j < src_lines.size() else "")
		out.append({"name": str(m.get("name", "")).replace("\n", " ").strip_edges().left(MAX_NAME_LENGTH),
				"icon": str(m.get("icon", "")).left(64), "lines": lines})
	return out


static func character_list() -> Array:
	return sanitize(Global.player_data.get("macros", []), CHARACTER_SLOTS)


static func shared_list() -> Array:
	if Net.remote_character_mode:
		return sanitize(Global.player_data.get("shared_macros", []), SHARED_SLOTS)
	var data: Variant = null
	if FileAccess.file_exists(SHARED_FILE):
		data = JSON.parse_string(FileAccess.get_file_as_string(SHARED_FILE))
	return sanitize(data, SHARED_SLOTS)


# ref: "c<index>" or "s<index>".
static func get_macro(ref: String) -> Dictionary:
	var idx := int(ref.substr(1)) if ref.length() > 1 and ref.substr(1).is_valid_int() else -1
	var list := character_list() if ref.begins_with("c") else (shared_list() if ref.begins_with("s") else [])
	return list[idx] if idx >= 0 and idx < list.size() else {}


static func set_macro(ref: String, macro: Dictionary) -> void:
	var idx := int(ref.substr(1)) if ref.length() > 1 and ref.substr(1).is_valid_int() else -1
	if ref.begins_with("c"):
		var list := character_list()
		if idx < 0 or idx >= list.size():
			return
		list[idx] = sanitize([macro], 1)[0]
		Global.player_data["macros"] = list
		Global.save_player_data_to_file()
	elif ref.begins_with("s"):
		var list := shared_list()
		if idx < 0 or idx >= list.size():
			return
		list[idx] = sanitize([macro], 1)[0]
		if Net.remote_character_mode:
			Global.player_data["shared_macros"] = list   # uploaded with the character; the server files it under the account
			Global.save_player_data_to_file()
		else:
			var f := FileAccess.open(SHARED_FILE, FileAccess.WRITE)
			if f:
				f.store_string(JSON.stringify(list, "\t"))
				f.close()


# The spell key a macro shows: its chosen icon, else the spell of its first /cast line ("" = none).
static func icon_spell(macro: Dictionary, player: Node) -> String:
	var chosen := str(macro.get("icon", ""))
	if not chosen.is_empty():
		return chosen
	for line in macro.get("lines", []):
		var text := str(line).strip_edges()
		if text.to_lower().begins_with("/cast "):
			var key := resolve_spell(text.substr(6), player, false)
			if not key.is_empty():
				return key
	return ""


static func label(macro: Dictionary) -> String:
	var n := str(macro.get("name", "")).strip_edges()
	return n if not n.is_empty() else "Macro"


# A spell the player knows, from what was typed after /cast: its key, its shown name (any case), or the start of either
# when only one known spell matches. "" when nothing (or more than one) matches — `say` logs why.
static func resolve_spell(typed: String, player: Node, say: bool = true) -> String:
	var want := typed.strip_edges().to_lower()
	if want.is_empty() or not is_instance_valid(player):
		return ""
	var known: Array = player.get("known_spells") if "known_spells" in player else []
	var prefix_hits: Array = []
	for key in known:
		var shown := Player3D.spell_display_name(str(key)).to_lower()
		if want == shown or want == str(key).to_lower():
			return str(key)
		if shown.begins_with(want) or str(key).to_lower().begins_with(want):
			prefix_hits.append(str(key))
	if prefix_hits.size() == 1:
		return prefix_hits[0]
	if say:
		if prefix_hits.is_empty():
			GameLog.log_general("[color=red]You don't know a spell called '%s'.[/color]" % typed.strip_edges())
		else:
			GameLog.log_general("[color=red]'%s' could be %s.[/color]" % [typed.strip_edges(),
					", ".join(prefix_hits.map(func(k): return Player3D.spell_display_name(str(k))))])
	return ""


# %t / %T / %s filled in. With no target, %t and %T become "nothing" (as in EverQuest's "%t" with no target).
static func substitute(line: String, player: Node) -> String:
	if not line.contains("%"):
		return line
	var target: Node = player.get("current_target") if is_instance_valid(player) and "current_target" in player else null
	var t_name := "nothing"
	var t_long := "nothing"
	if is_instance_valid(target):
		t_name = TargetFrame.display_name(target)
		t_long = t_name
		var cn = target.get("combat_node") if "combat_node" in target else null
		if cn != null:
			var pct := int(round(100.0 * float(cn.current_hp) / maxf(1.0, float(cn.max_hp))))
			t_long = "%s (level %d, %d%% health)" % [t_name, int(cn.level), pct]
	var me := str(player.get("player_name")) if is_instance_valid(player) and "player_name" in player else ""
	return line.replace("%T", t_long).replace("%t", t_name).replace("%s", me)


# Seconds for /pause (EverQuest's /pause took tenths; here it is seconds, 0.1 to MAX_PAUSE). -1 = not a number.
static func pause_seconds(arg: String) -> float:
	var text := arg.strip_edges().split(",")[0].strip_edges()   # "/pause 3, /cast x" (EQ style) — only the number counts
	if not text.is_valid_float():
		return -1.0
	return clampf(float(text), 0.1, MAX_PAUSE)
