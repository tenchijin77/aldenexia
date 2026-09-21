# skill_effects.gd — reads Data/skill_effects.json: what each skill in player_skills.json actually does (bonus per skill point).
# Missing file / missing entry = no bonus, so skills simply do nothing extra until listed. Read once per run.
# Like combat_balance.json this affects numbers computed on each player's own machine, so server and clients ship the same file.
class_name SkillEffects
extends RefCounted

const PATH := "res://Data/skill_effects.json"

static var _effects: Dictionary = {}
static var _loaded := false


# The per-point table for one stat: {skill_name: bonus_per_point}. Empty when the stat has no entry.
static func table(stat: String) -> Dictionary:
	if not _loaded:
		_load()
	return _effects.get(stat, {})


static func reload() -> void:
	_loaded = false


static func _load() -> void:
	_loaded = true
	_effects = {}
	if not FileAccess.file_exists(PATH):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("effects")) != TYPE_DICTIONARY:
		push_warning("skill_effects.json could not be read — skills add nothing beyond what is hard-coded.")
		return
	_effects = parsed["effects"]
