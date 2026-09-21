# combat_balance.gd — reads Data/combat_balance.json, the one place the combat numbers are tuned.
# Every value has a NEUTRAL fallback below (= how combat behaved before the file existed), so a missing file or a
# missing/invalid key simply means "unchanged". The file is read once per run; edit it and restart.
# NOTE for a dedicated server: hit chance and spell/melee damage of PLAYERS are computed on each player's own machine,
# monster HP/damage on the server, so server and clients must ship the same file (they do: it is in the export).
class_name CombatBalance
extends RefCounted

const PATH := "res://Data/combat_balance.json"

const NEUTRAL := {
	"player_hit_bonus": 0.0,
	"monster_hit_bonus": 0.0,
	"hit_level_diff_per_level": 5.0,
	"hit_min": 5.0,
	"hit_max": 95.0,
	"player_melee_damage_mult": 1.0,
	"monster_melee_damage_mult": 1.0,
	"player_spell_damage_mult": 1.0,
	"monster_hp_mult": 1.0,
	"monster_hp_per_level": 0.0,
	"monster_damage_per_level": 0.0,
	"monster_scale_min": 0.5,
	"monster_scale_max": 3.0,
	"skill_cap_per_level": 0.0,  # 0 = no level cap on skills (the old behaviour: everything trains up to skill_max)
}

static var _values: Dictionary = {}
static var _loaded := false


static func num(key: String) -> float:
	if not _loaded:
		_load()
	return float(_values.get(key, NEUTRAL.get(key, 0.0)))


static func reload() -> void:
	_loaded = false


static func _load() -> void:
	_loaded = true
	_values = NEUTRAL.duplicate()
	if not FileAccess.file_exists(PATH):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("combat_balance.json could not be read — using the neutral defaults.")
		return
	for key in NEUTRAL:
		var v = parsed.get(key)
		if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
			_values[key] = float(v)


# "player", "monster" or "" (guards, pets, anything else) for the node that owns a CombatNode.
static func role_of(combat_node: Node) -> String:
	var owner_node := combat_node.get_parent()
	if owner_node == null:
		return ""
	if owner_node.is_in_group("player"):
		return "player"
	if owner_node.is_in_group("monsters"):
		return "monster"
	return ""
