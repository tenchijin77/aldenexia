# combat_log_formatter.gd
# Builds randomized combat log messages in EQ style.
# All functions are static — call as CombatLogFormatter.player_attack(...)
# No autoload needed; class_name makes it globally available.
extends Node
class_name CombatLogFormatter

# ── Verb tables ───────────────────────────────────────────────────────────────

const SLASH_2ND  := ["slash", "cut into", "slice", "carve into", "hack at"]
const PIERCE_2ND := ["pierce", "stab", "thrust at", "drive your blade into", "skewer"]
const BLUNT_2ND  := ["smash", "crush", "slam into", "bludgeon", "pound"]
const GENERIC_2ND := ["strike", "hit", "land a blow on", "attack"]

const SLASH_3RD  := ["slashes", "cuts into", "slices", "carves into", "hacks at"]
const PIERCE_3RD := ["pierces", "stabs", "thrusts at", "drives a blade into", "skewers"]
const BLUNT_3RD  := ["smashes", "crushes", "slams into", "bludgeons", "pounds"]
const GENERIC_3RD := ["strikes", "hits", "lands a blow on", "batters"]

# ── Defensive phrase tables ───────────────────────────────────────────────────

# Used when the monster defends against the player's attack (%s = monster name)
const ENEMY_PARRY := [
	"%s parries your attack!",
	"%s deflects your strike!",
	"%s turns your blow aside!",
	"%s catches your attack on their blade!",
]
const ENEMY_BLOCK := [
	"%s blocks your attack with their shield!",
	"%s raises their guard, stopping your blow!",
	"%s absorbs your strike behind their shield!",
]
const ENEMY_DODGE := [
	"%s dodges your attack!",
	"%s sidesteps your strike!",
	"%s narrowly avoids your blow!",
	"%s evades your swing!",
]
const ENEMY_RIPOSTE := [
	"%s ripostes your attack and counterattacks for [b]%d[/b] damage!",
	"%s turns your strike aside and retaliates for [b]%d[/b] damage!",
	"%s exploits an opening and counters for [b]%d[/b] damage!",
	"%s deflects and instantly strikes back for [b]%d[/b] damage!",
]

# Used when the player defends against the monster's attack (%s = monster name)
const PLAYER_PARRY := [
	"You parry %s's attack!",
	"You deflect %s's strike!",
	"You turn aside %s's blow!",
	"You catch %s's attack on your blade!",
]
const PLAYER_BLOCK := [
	"You block %s's attack with your shield!",
	"You raise your shield, stopping %s's blow!",
	"You absorb %s's strike behind your guard!",
]
const PLAYER_DODGE := [
	"You dodge %s's attack!",
	"You sidestep %s's strike!",
	"You narrowly avoid %s's blow!",
	"You evade %s's swing!",
]
const PLAYER_RIPOSTE := [
	"You riposte %s's attack and counterattack for [b]%d[/b] damage!",
	"You turn %s's strike aside and retaliate for [b]%d[/b] damage!",
	"You exploit an opening in %s's attack and counter for [b]%d[/b] damage!",
]

# Maps item "skill" field → damage_type string
const SKILL_TO_DAMAGE_TYPE: Dictionary = {
	"1h slashing": "slashing", "1h_slashing": "slashing",
	"2h slashing": "slashing", "2h_slashing": "slashing",
	"1h piercing": "piercing", "1h_piercing": "piercing",
	"2h piercing": "piercing", "2h_piercing": "piercing",
	"1h blunt":    "blunt",    "1h_blunt":    "blunt",
	"2h blunt":    "blunt",    "2h_blunt":    "blunt",
	"hand_to_hand": "blunt",
	"archery":      "piercing",
	"throwing":     "piercing",
}

# ── Helpers ───────────────────────────────────────────────────────────────────

static func _pick(arr: Array) -> String:
	return arr[randi() % arr.size()]

static func _verb2(damage_type: String) -> String:
	match damage_type:
		"slashing": return _pick(SLASH_2ND)
		"piercing": return _pick(PIERCE_2ND)
		"blunt":    return _pick(BLUNT_2ND)
		_:          return _pick(GENERIC_2ND)

static func _verb3(damage_type: String) -> String:
	match damage_type:
		"slashing": return _pick(SLASH_3RD)
		"piercing": return _pick(PIERCE_3RD)
		"blunt":    return _pick(BLUNT_3RD)
		_:          return _pick(GENERIC_3RD)

static func damage_type_from_item(item: Dictionary) -> String:
	var s: String = item.get("skill", "").to_lower()
	return SKILL_TO_DAMAGE_TYPE.get(s, "generic")

# ── Player attacks monster ────────────────────────────────────────────────────

static func player_attack(result: Dictionary, target_desc: String, weapon_name: String, damage_type: String) -> String:
	var cap: String = target_desc.capitalize()
	match result.get("result", ""):
		"MISS":
			if weapon_name.is_empty():
				return "You miss %s!" % cap
			return "You swing at %s with %s, but miss!" % [cap, weapon_name]
		"PARRY":
			return _pick(ENEMY_PARRY) % cap
		"BLOCK":
			return _pick(ENEMY_BLOCK) % cap
		"DODGE":
			return _pick(ENEMY_DODGE) % cap
		"RIPOSTE":
			return _pick(ENEMY_RIPOSTE) % [cap, result.get("damage", 0)]
		"HIT":
			var verb: String = _verb2(damage_type)
			var crit: String = "[color=#ffaa00]Critical! [/color]" if result.get("is_crit", false) else ""
			if weapon_name.is_empty():
				return "%sYou %s %s for [b]%d[/b] damage!" % [crit, verb, cap, result.get("damage", 0)]
			return "%sYou %s %s with %s for [b]%d[/b] damage!" % [crit, verb, cap, weapon_name, result.get("damage", 0)]
	return ""

# ── Monster attacks player ────────────────────────────────────────────────────

static func monster_attack(result: Dictionary, monster_desc: String, damage_type: String) -> String:
	var cap: String = monster_desc.capitalize()
	match result.get("result", ""):
		"MISS":
			return "%s misses you!" % cap
		"PARRY":
			return _pick(PLAYER_PARRY) % monster_desc
		"BLOCK":
			return _pick(PLAYER_BLOCK) % monster_desc
		"DODGE":
			return _pick(PLAYER_DODGE) % monster_desc
		"RIPOSTE":
			return _pick(PLAYER_RIPOSTE) % [monster_desc, result.get("damage", 0)]
		"HIT":
			var verb: String = _verb3(damage_type)
			var crit: String = "[color=#ffaa00]Critical! [/color]" if result.get("is_crit", false) else ""
			return "%s%s %s you for [b]%d[/b] damage!" % [crit, cap, verb, result.get("damage", 0)]
	return ""

# ── Spell messages ────────────────────────────────────────────────────────────

static func spell_damage(caster: String, spell_name: String, target_desc: String, damage: int) -> String:
	var verb := "cast" if caster == "You" else "casts"
	return "%s %s [b]%s[/b] on %s for [b]%d[/b] damage!" % [
		caster, verb, spell_name.replace("_", " ").capitalize(), target_desc, damage
	]

static func spell_heal(caster: String, spell_name: String, target_desc: String, amount: int) -> String:
	var verb := "cast" if caster == "You" else "casts"
	return "%s %s [b]%s[/b] on %s, restoring [b]%d[/b] health!" % [
		caster, verb, spell_name.replace("_", " ").capitalize(), target_desc, amount
	]

static func spell_debuff(caster: String, spell_name: String, target_desc: String, stat: String, amount: int) -> String:
	var verb := "cast" if caster == "You" else "casts"
	return "%s %s [b]%s[/b] on %s, reducing its %s by %d!" % [
		caster, verb, spell_name.replace("_", " ").capitalize(), target_desc, stat, amount
	]

static func begin_cast(caster: String) -> String:
	if caster == "You":
		return "You begin casting a spell."
	return "%s begins casting a spell." % caster

static func death(killer: String, target_desc: String) -> String:
	return "[color=#ff4444]%s has slain %s![/color]" % [killer, target_desc.capitalize()]
