#combatnode.gd - Complete EQ-Style Combat System
extends Node
class_name CombatNode

# ================================================================================
# ⭐ CORE STATS (7 Base Stats)
# ================================================================================

var strength: int = 10           # Melee damage, carry weight, intimidation
var constitution: int = 10       # HP, stamina, poison/disease resist
var dexterity: int = 10          # Dodge, parry, ranged accuracy, crit, initiative
var intelligence: int = 10       # Arcane spells, mana, spell crit, crafting
var wisdom: int = 10             # Healing, mana regen, divine spells, concentration
var charisma: int = 10           # NPC reactions, faction, bard magic, pet control
var luck: int = 10               # Crit chance, crit damage, loot, lucky rolls

# ================================================================================
# ⭐ CHARACTER INFO
# ================================================================================

var character_name: String = "Player"
var level: int = 1
var character_class: String = "Blademaster"  # Blademaster, Aetherfist, etc.
var current_hp: int = 50
var max_hp: int = 50
var current_mana: int = 30
var max_mana: int = 30
var current_stamina: int = 100
var max_stamina: int = 100

# ================================================================================
# ⭐ EQUIPMENT & GEAR STATS (Additive Bonuses)
# ================================================================================

var gear_atk: int = 0            # Weapon ATK bonus
var gear_ac: int = 0             # Armor AC bonus
var gear_crit: int = 0           # Crit chance bonus
var gear_crit_damage: int = 0    # Crit damage bonus
var gear_riposte: int = 0        # Riposte chance bonus
var gear_spell_power: int = 0    # Arcane spell damage bonus
var gear_healing_power: int = 0  # Divine spell damage bonus
var gear_concentration: int = 0  # Concentration bonus
var gear_spirit_resist: int = 0  # Spirit resist bonus
var gear_hp: int = 0             # HP bonus
var gear_mana: int = 0           # Mana bonus

# ================================================================================
# ⭐ WEAPON STATS
# ================================================================================

var weapon_skill: int = 0        # 0-252 (EQ-style)
## The player's skill levels (name -> points), shared by reference with player3d.gd. Empty for monsters, guards and pets,
## which is what keeps them out of Data/skill_effects.json — see skill_bonus().
var skills: Dictionary = {}
## Set by monster3d.gd from the level it rolled (see monster_damage_per_level in Data/combat_balance.json). 1.0 for everyone else.
var balance_damage_scale: float = 1.0
var weapon_damage: int = 0       # Base weapon damage
var weapon_speed: float = 2.0    # Attack speed in seconds (base 2.0-3.0)
var weapon_type: String = "melee"  # melee, ranged, unarmed, staff
var is_two_handed: bool = false
var is_dual_wield: bool = false

# Offhand weapon (for dual-wield)
var offhand_weapon_damage: int = 0
var offhand_weapon_skill: int = 0

# ================================================================================
# ⭐ SHIELD STATS
# ================================================================================

var has_shield: bool = false
var shield_type: String = ""  # buckler, round_shield, kite_shield, tower_shield

var shield_bonus_map = {
	"buckler": 10,
	"round_shield": 15,
	"kite_shield": 20,
	"tower_shield": 25
}

# ================================================================================
# ⭐ CLASS-SPECIFIC BONUSES
# ================================================================================

var class_hp_bonus: float = 0.0      # Percentage bonus (0.1 = 10%)
var class_mana_bonus: float = 0.0
var class_ac_bonus: int = 0
var class_dodge_base: int = 3
var class_parry_base: int = 5
var class_riposte_base: int = 0
var class_concentration_base: int = 0

# ================================================================================
# ⭐ RACIAL BONUSES (set by player3d.gd's apply_racial_modifiers(); character_options.json
# is the source of truth for the numbers — this is the "core combat stats" subset only.
# Skill-specific bonuses, faction standing offsets, and environmental/conditional traits
# (daylight, cold, swamp, "outdoors") aren't wired up yet — see
# [[project_racial_traits]] in Claude's memory for the full list and what's deferred.
# ================================================================================

var race_hp_mult: float = 0.0             # Percentage (0.1 = +10% max HP)
var race_mana_mult: float = 0.0
var race_melee_damage_mult: float = 0.0
var race_spell_damage_mult: float = 0.0
var race_physical_resist: float = 0.0     # Flat percentage reduction on incoming physical damage
var race_dodge_bonus: int = 0             # Flat points added to dodge_chance
var race_parry_bonus: int = 0
var race_crit_bonus: int = 0
var race_movement_speed_mult: float = 0.0 # Applied directly in player3d.gd's handle_movement()
var race_all_stats_mult: float = 0.0      # Applied to effective base stats in recalculate_derived_stats()
var race_negative_effect_resist: float = 0.0  # Chance [0-1] to shrug off an incoming debuff/CC entirely
var race_immune_to_root: bool = false
var race_immune_to_blind: bool = false

# Flat point bonuses/penalties added to the matching resist stat in
# recalculate_derived_stats() — sourced from Data/racial_stats.json's
# authored per-race "resistances" data, which existed but was never actually
# read anywhere before 2026-09-19 (see game_flow.txt's "Spell
# Classification" section). Only 5 of the 10 finalized damage types have
# racial data authored so far; the other 5 (lightning/lightning/disease/
# poison/disease/divine/spirit) default to 0 for every race until that data exists.
var race_fire_resist: int = 0
var race_cold_resist: int = 0
var race_acid_resist: int = 0
var race_magic_resist: int = 0
var race_psychic_resist: int = 0

# Sum of what the player's skills add to `stat`, from Data/skill_effects.json ("skill: bonus per point").
# `category` is the skill the current spell/ability belongs to (stands in for "@category"). 0.0 for anything without skills.
func skill_bonus(stat: String, category: String = "") -> float:
	if skills.is_empty():
		return 0.0
	var total := 0.0
	var table := SkillEffects.table(stat)
	for skill_name in table:
		var points := 0
		match skill_name:
			"@weapon": points = weapon_skill
			"@category": points = int(skills.get(category, 0)) if not category.is_empty() else 0
			_: points = int(skills.get(skill_name, 0))
		total += points * float(table[skill_name])
	return total

func rolls_resist_negative_effect() -> bool:
	return race_negative_effect_resist > 0.0 and randf() < race_negative_effect_resist

# ================================================================================
# ⭐ SPELL CASTING
# ================================================================================

var spellcasting_ability: String = "intelligence"  # intelligence, wisdom, charisma
var is_casting: bool = false
var current_cast_time: float = 0.0
var total_cast_time: float = 0.0

# ================================================================================
# ⭐ COMBAT STATE
# ================================================================================

var in_combat: bool = false
var last_combat_time: float = 0.0

# "Recently engaged" clock (added 2026-09-19) — stamped whenever this node deals
# or takes hostile damage (see resolve_attack/generate_threat/take_damage).
# Drives the combat music (global_background_music.gd). Deliberately NOT built
# on `in_combat` above, which nothing ever sets — flipping that on would also
# change decay_threat()'s behavior.
var last_engaged_msec: int = -1000000

func mark_engaged() -> void:
	last_engaged_msec = Time.get_ticks_msec()

func seconds_since_engaged() -> float:
	return (Time.get_ticks_msec() - last_engaged_msec) / 1000.0
var threat_value: float = 0.0

# ================================================================================
# ⭐ DERIVED STAT CACHE (Recalculate when stats change)
# ================================================================================

var _cached_stats = {}
var _stats_dirty: bool = true

# ================================================================================
# ⭐ INITIALIZATION
# ================================================================================

func _ready():
	randomize()
	recalculate_derived_stats()

# ================================================================================
# ⭐ BUFF / DEBUFF EFFECTS (generic timed modifiers, shared by player + monsters)
# ================================================================================

var active_effects: Dictionary = {}  # name -> {remaining, modifiers, tick_dmg, tick_heal, tick_interval, tick_accum}

func apply_effect(effect_name: String, duration: float, modifiers: Dictionary, tick_dmg: int = 0, tick_interval: float = 1.0, tick_heal: int = 0) -> void:
	"""Apply (or refresh) a named timed effect with a dict of additive modifiers.
	tick_dmg/tick_heal are mutually-exclusive per-tick amounts (DoT/HoT) — heal
	goes through heal() so it respects max_hp, unlike take_damage()."""
	active_effects[effect_name] = {
		"remaining": duration,
		"modifiers": modifiers,
		"tick_dmg": tick_dmg,
		"tick_heal": tick_heal,
		"tick_interval": tick_interval,
		"tick_accum": 0.0,
	}

func remove_effect(effect_name: String) -> void:
	active_effects.erase(effect_name)

func has_effect(effect_name: String) -> bool:
	return active_effects.has(effect_name)

func get_modifier(key: String) -> float:
	"""Sum a named modifier (e.g. 'damage_mult', 'hit_chance') across all active effects."""
	var total: float = 0.0
	for effect in active_effects.values():
		total += effect["modifiers"].get(key, 0.0)
	return total


# ── Invisibility / stealth ──────────────────────────────────────────────────
# "invisible" and "see_invisible" are modifier keys on ordinary timed effects
# (player3d.gd's "invisibility" spell cast, deathly_visage's see-invisible
# grant) rather than dedicated fields — reuses the existing effect/expiry
# system instead of a parallel one. "stealthed" is the same shape, wired up
# here for TargetFrame's nameplate formatting even though no skill sets it
# yet (no rogue stealth mechanic exists in this codebase to hook into).
func is_currently_invisible() -> bool:
	return get_modifier("invisible") > 0.0

func has_see_invisible() -> bool:
	return get_modifier("see_invisible") > 0.0

func is_stealthed() -> bool:
	return get_modifier("stealthed") > 0.0

# Called from resolve_attack() below (melee) and player3d.gd's
# _resolve_spell_cast() (spell damage) — attacking of any kind reveals you,
# same rule for players and monsters alike.
func break_invisibility() -> void:
	if active_effects.has("invisibility"):
		remove_effect("invisibility")

func has_passive(spell_name: String) -> bool:
	"""Check whether this CombatNode's owner (player/pet) knows a non-cast passive spell."""
	var owner_node: Node = get_parent()
	if owner_node and "known_spells" in owner_node:
		return spell_name in owner_node.known_spells
	return false

# Reduces incoming damage against any active effect carrying an
# "absorb_remaining" pool (e.g. Shadow Ward) — consumes the pool as it soaks
# damage, and lets the effect's own duration/removal handle final cleanup
# once the pool hits zero. Not part of the generic modifiers dict because it
# needs to be consumed (drained), not just summed like get_modifier().
func absorb_incoming_damage(amount: int) -> int:
	for effect in active_effects.values():
		if amount <= 0:
			break
		if effect.get("absorb_remaining", 0) > 0:
			var absorbed: int = mini(amount, effect["absorb_remaining"])
			effect["absorb_remaining"] -= absorbed
			amount -= absorbed
	return amount

# Voidknight's Death's Echo — "killing an enemy boosts next attack damage by
# 10%." Callers invoke this right where they already confirm a kill (player3d.gd's
# melee/autoattack/spell-cast kill blocks). Converts the standing buff into a
# short damage_mult proc rather than something callers have to remember to
# clear after one hit — simpler than tracking "next attack only" exactly.
func notify_kill() -> void:
	if has_effect("deaths_echo"):
		remove_effect("deaths_echo")
		apply_effect("deaths_echo_proc", 20.0, {"damage_mult": 0.10})

func _process(delta: float) -> void:
	if active_effects.is_empty():
		return
	var expired: Array = []
	for effect_name in active_effects:
		var effect: Dictionary = active_effects[effect_name]
		if effect["tick_dmg"] > 0 or effect.get("tick_heal", 0) > 0:
			effect["tick_accum"] += delta
			if effect["tick_accum"] >= effect["tick_interval"]:
				effect["tick_accum"] -= effect["tick_interval"]
				if effect["tick_dmg"] > 0:
					take_damage(effect["tick_dmg"])
				if effect.get("tick_heal", 0) > 0:
					heal(effect["tick_heal"])
		if effect["remaining"] != INF:
			effect["remaining"] -= delta
			if effect["remaining"] <= 0.0:
				expired.append(effect_name)
	for effect_name in expired:
		active_effects.erase(effect_name)

# ================================================================================
# ⭐ STAT MODIFICATION (Marks cache as dirty)
# ================================================================================

func set_base_stat(stat_name: String, value: int):
	"""Set a base stat and invalidate cache"""
	match stat_name:
		"strength": strength = value
		"constitution": constitution = value
		"dexterity": dexterity = value
		"intelligence": intelligence = value
		"wisdom": wisdom = value
		"charisma": charisma = value
		"luck": luck = value
		"level": level = value
	_stats_dirty = true

func set_weapon_stats(dmg: int, skill: int, speed: float, two_handed: bool = false, dual_wield: bool = false):
	"""Set weapon stats"""
	weapon_damage = dmg
	weapon_skill = skill
	weapon_speed = speed
	is_two_handed = two_handed
	is_dual_wield = dual_wield
	_stats_dirty = true

func set_offhand_weapon_stats(dmg: int, skill: int):
	"""Set off-hand weapon stats (dual-wield)"""
	offhand_weapon_damage = dmg
	offhand_weapon_skill = skill
	_stats_dirty = true

func set_shield(shield_type_name: String):
	"""Equip a shield"""
	has_shield = true
	shield_type = shield_type_name
	_stats_dirty = true

func remove_shield():
	"""Unequip shield"""
	has_shield = false
	shield_type = ""
	_stats_dirty = true

# ================================================================================
# ⭐ DERIVED STAT CALCULATION
# ================================================================================

func recalculate_derived_stats():
	"""Recalculate all derived stats from base stats"""
	if not _stats_dirty:
		return

	_cached_stats.clear()

	# Effective base stats — race_all_stats_mult (e.g. Half-Elf's +5%) scales
	# every base stat's CONTRIBUTION to derived stats below, without mutating
	# the stored base stat itself (keeps saved character data clean).
	var str_eff: float  = strength     * (1.0 + race_all_stats_mult)
	var con_eff: float  = constitution * (1.0 + race_all_stats_mult)
	var dex_eff: float  = dexterity    * (1.0 + race_all_stats_mult)
	var int_eff: float  = intelligence * (1.0 + race_all_stats_mult)
	var wis_eff: float  = wisdom       * (1.0 + race_all_stats_mult)
	var luck_eff: float = luck         * (1.0 + race_all_stats_mult)

	# Health (HP)
	var base_hp = 50  # Base for level 1
	var con_bonus = int(con_eff * 10)
	var hp_from_class = int(base_hp * class_hp_bonus) if class_hp_bonus > 0 else 0
	var hp_from_race = int(base_hp * race_hp_mult)
	max_hp = base_hp + con_bonus + hp_from_class + hp_from_race + gear_hp
	current_hp = min(current_hp, max_hp)
	_cached_stats["max_hp"] = max_hp

	# Mana (MP)
	var base_mana = 30  # Base for level 1
	var int_wis_bonus = int((int_eff + wis_eff) * 5)
	var mana_from_class = int(base_mana * class_mana_bonus) if class_mana_bonus > 0 else 0
	var mana_from_race = int(base_mana * race_mana_mult)
	max_mana = base_mana + int_wis_bonus + mana_from_class + mana_from_race + gear_mana
	current_mana = min(current_mana, max_mana)
	_cached_stats["max_mana"] = max_mana

	# Stamina
	max_stamina = 100 + int(con_eff * 5)
	current_stamina = min(current_stamina, max_stamina)
	_cached_stats["max_stamina"] = max_stamina

	# Attack Rating (ATK)
	var atk = (weapon_skill * 2) + int(str_eff) + int(dex_eff / 2.0) + gear_atk + int(skill_bonus("attack_rating"))
	_cached_stats["attack_rating"] = atk

	# Armor Class (AC)
	var ac = 10 + gear_ac + int(dex_eff / 2.0) + class_ac_bonus
	if has_shield and shield_bonus_map.has(shield_type):
		ac += shield_bonus_map[shield_type]
	_cached_stats["armor_class"] = ac

	# Crit Chance
	var base_crit = 5
	var class_crit_bonus = _get_class_crit_bonus()
	var crit_chance = base_crit + int((dex_eff + luck_eff) / 2.0) + class_crit_bonus + gear_crit + race_crit_bonus + int(skill_bonus("crit_chance"))
	crit_chance = clamp(crit_chance, 0, 60)  # Hard cap at 60%
	_cached_stats["crit_chance"] = crit_chance

	# Crit Damage
	var crit_damage = 150 + int(luck_eff * 0.5) + gear_crit_damage
	_cached_stats["crit_damage"] = crit_damage

	# Riposte Chance
	var riposte = class_riposte_base + int(dex_eff * 0.2) + int(weapon_skill * 0.1) + gear_riposte + int(skill_bonus("riposte_chance"))
	riposte = clamp(riposte, 0, 100)
	_cached_stats["riposte_chance"] = riposte

	# Dodge Chance
	var dodge = class_dodge_base + int(dex_eff * 0.5) + race_dodge_bonus + int(skill_bonus("dodge_chance"))
	dodge = clamp(dodge, 0, 50)  # Soft cap at 50%
	_cached_stats["dodge_chance"] = dodge

	# Parry Chance
	var parry = class_parry_base + int(dex_eff * 0.3) + int(weapon_skill * 0.1) + race_parry_bonus + int(skill_bonus("parry_chance"))
	parry = clamp(parry, 0, 50)  # Soft cap at 50%
	_cached_stats["parry_chance"] = parry

	# Block Chance
	var block = 0
	if has_shield and shield_bonus_map.has(shield_type):
		block = shield_bonus_map[shield_type] + int(dex_eff * 0.2) + int(skill_bonus("block_chance"))
	block = clamp(block, 0, 50)  # Soft cap at 50%
	_cached_stats["block_chance"] = block

	# Resistances — the 10 finalized spell_school damage types (see
	# game_flow.txt's "Spell Classification" section, 2026-09-19). All still
	# share the same base formula for now (no per-type balancing pass yet,
	# this is the infrastructure/plumbing step) except spirit, which keeps
	# its existing dedicated gear_spirit_resist bonus.
	var base_resist = int(con_eff / 2.0) + int(wis_eff / 2.0)
	_cached_stats["fire_resist"] = clamp(base_resist + gear_ac + race_fire_resist, 0, 200)
	_cached_stats["cold_resist"] = clamp(base_resist + gear_ac + race_cold_resist, 0, 200)
	_cached_stats["acid_resist"] = clamp(base_resist + gear_ac + race_acid_resist, 0, 200)
	_cached_stats["lightning_resist"] = clamp(base_resist + gear_ac, 0, 200)
	_cached_stats["poison_resist"] = clamp(base_resist + gear_ac, 0, 200)
	_cached_stats["disease_resist"] = clamp(base_resist + gear_ac, 0, 200)
	_cached_stats["magic_resist"] = clamp(base_resist + gear_ac + race_magic_resist, 0, 200)
	_cached_stats["divine_resist"] = clamp(base_resist + gear_ac, 0, 200)
	_cached_stats["psychic_resist"] = clamp(base_resist + gear_ac + race_psychic_resist, 0, 200)
	_cached_stats["spirit_resist"] = clamp(int((con_eff + wis_eff) / 2.0) + gear_spirit_resist, 0, 200)

	# Health Regeneration (per 6-second tick). Sitting multiplier applied in player3d.
	var hp_regen = 2 + int(con_eff / 3.0)
	_cached_stats["hp_regen"] = hp_regen

	# Mana Regeneration (per 6-second tick). Sitting multiplier applied in player3d.
	var mana_regen = 2 + int(wis_eff / 3.0) + int(skill_bonus("mana_regen"))
	_cached_stats["mana_regen"] = mana_regen

	# Stamina Regeneration (per second)
	var stamina_regen = 10 + int(con_eff / 5.0)
	_cached_stats["stamina_regen"] = stamina_regen

	# Spell Power (Arcane)
	var arcane_power = int(int_eff * 2) + gear_spell_power
	_cached_stats["arcane_power"] = arcane_power

	# Spell Power (Divine/Nature)
	var divine_power = int(wis_eff * 2) + gear_healing_power
	_cached_stats["divine_power"] = divine_power

	# Concentration
	var concentration = class_concentration_base + int(wis_eff / 2.0) + int(int_eff / 4.0) + gear_concentration + int(skill_bonus("concentration"))
	concentration = clamp(concentration, 0, 95)  # Hard cap at 95%
	_cached_stats["concentration"] = concentration

	# Carry Weight
	var carry_weight = 100 + int(str_eff * 2)
	_cached_stats["carry_weight"] = carry_weight

	_stats_dirty = false

# ================================================================================
# ⭐ CLASS-SPECIFIC BONUSES
# ================================================================================

func set_class(new_class: String):
	"""Set character class and apply class-specific bonuses"""
	character_class = new_class

	match new_class:
		"Blademaster":
			class_hp_bonus = 0.15
			class_ac_bonus = 2
			class_dodge_base = 3
			class_parry_base = 15
			class_riposte_base = 5
			class_concentration_base = 0

		"Aetherfist":
			class_hp_bonus = 0.10
			class_ac_bonus = 0
			class_dodge_base = 7
			class_parry_base = 12
			class_riposte_base = 4
			class_concentration_base = 0

		"Shadowblade":
			class_hp_bonus = 0.08
			class_ac_bonus = 1
			class_dodge_base = 10
			class_parry_base = 10
			class_riposte_base = 3
			class_concentration_base = 0

		"Voidknight":
			class_hp_bonus = 0.20
			class_ac_bonus = 5
			class_dodge_base = 3
			class_parry_base = 8
			class_riposte_base = 2
			class_concentration_base = 0

		"Lightsworn":
			class_hp_bonus = 0.12
			class_ac_bonus = 3
			class_dodge_base = 3
			class_parry_base = 8
			class_riposte_base = 2
			class_concentration_base = 12

		"Woodstalker":
			class_hp_bonus = 0.10
			class_ac_bonus = 1
			class_dodge_base = 8
			class_parry_base = 3
			class_riposte_base = 3
			class_concentration_base = 0

		"Troubadour":
			class_hp_bonus = 0.08
			class_ac_bonus = 0
			class_dodge_base = 5
			class_parry_base = 1
			class_riposte_base = 1
			class_concentration_base = 10

		"Spiritweaver":
			class_hp_bonus = 0.08
			class_ac_bonus = 0
			class_dodge_base = 3
			class_parry_base = 0
			class_riposte_base = 0
			class_concentration_base = 18

		"Gravecaller":
			class_hp_bonus = 0.08
			class_ac_bonus = 0
			class_dodge_base = 3
			class_parry_base = 0
			class_riposte_base = 0
			class_concentration_base = 12

		"Runecaster":
			class_hp_bonus = 0.06
			class_ac_bonus = 0
			class_dodge_base = 3
			class_parry_base = 0
			class_riposte_base = 0
			class_concentration_base = 15

		"Arcanist":
			class_hp_bonus = 0.06
			class_ac_bonus = 0
			class_dodge_base = 3
			class_parry_base = 0
			class_riposte_base = 0
			class_concentration_base = 15

		"Chaosborn":
			class_hp_bonus = 0.10
			class_ac_bonus = 1
			class_dodge_base = 4
			class_parry_base = 2
			class_riposte_base = 0
			class_concentration_base = 10

	_stats_dirty = true

func _get_class_crit_bonus() -> int:
	"""Get class-specific crit bonus"""
	match character_class:
		"Shadowblade": return 5
		"Blademaster": return 3
		"Woodstalker": return 2
		_: return 0

# ================================================================================
# ⭐ STAT GETTERS (Access derived stats)
# ================================================================================

func get_derived_stat(stat_name: String):
	"""Get a derived stat (recalculates if dirty)"""
	recalculate_derived_stats()
	return _cached_stats.get(stat_name, 0)

func get_atk() -> int:
	return get_derived_stat("attack_rating")

func get_ac() -> int:
	return get_derived_stat("armor_class")

func get_crit_chance() -> int:
	return get_derived_stat("crit_chance")

func get_crit_damage() -> int:
	return get_derived_stat("crit_damage")

func get_dodge_chance() -> int:
	return get_derived_stat("dodge_chance")

func get_parry_chance() -> int:
	return get_derived_stat("parry_chance")

func get_block_chance() -> int:
	var passive_bonus := 10 if has_passive("improved_block") else 0
	return get_derived_stat("block_chance") + int(get_modifier("block_chance")) + passive_bonus

func get_riposte_chance() -> int:
	return get_derived_stat("riposte_chance")

func get_resistance(resist_type: String) -> int:
	return get_derived_stat(resist_type + "_resist")

func get_arcane_power() -> int:
	return get_derived_stat("arcane_power")

func get_divine_power() -> int:
	return get_derived_stat("divine_power")

func get_concentration() -> int:
	return get_derived_stat("concentration")

# ================================================================================
# ⭐ DAMAGE CALCULATION
# ================================================================================

func calculate_melee_damage(target: CombatNode = null, is_crit: bool = false) -> int:
	"""Calculate melee damage with modifiers"""
	var level_modifier = 0
	if target:
		level_modifier = (level - target.level) * 5
		level_modifier = clamp(level_modifier, -50, 50)

	var raw_damage = weapon_damage + int(strength / 2.0)

	# Apply two-handed bonus
	if is_two_handed:
		raw_damage = int(raw_damage * 1.15)  # +15%

	# Racial melee damage bonus/penalty (e.g. Ogre +20%, Gnome -15%)
	if race_melee_damage_mult != 0.0:
		raw_damage = int(raw_damage * (1.0 + race_melee_damage_mult))

	# Skills: weapon mastery / offense / the wielded weapon's own skill (Data/skill_effects.json)
	raw_damage = int(raw_damage * (1.0 + skill_bonus("melee_damage_pct") / 100.0))

	# Apply crit
	if is_crit:
		var crit_dmg_mult = 1.0 + (get_crit_damage() / 100.0)
		raw_damage = int(raw_damage * crit_dmg_mult)

	# Apply level modifier
	raw_damage = int(raw_damage * (1.0 + (level_modifier / 100.0)))

	# Apply active buff/debuff damage modifiers (e.g. blood_ritual)
	raw_damage = int(raw_damage * (1.0 + get_modifier("damage_mult")))

	# Tunable melee damage (Data/combat_balance.json): players, and monsters (+ their per-level scaling)
	match CombatBalance.role_of(self):
		"player": raw_damage = int(raw_damage * CombatBalance.num("player_melee_damage_mult"))
		"monster": raw_damage = int(raw_damage * CombatBalance.num("monster_melee_damage_mult") * balance_damage_scale)

	return max(1, raw_damage)

func calculate_offhand_damage(target: CombatNode = null, is_crit: bool = false) -> int:
	"""Calculate off-hand damage (50% of main hand)"""
	var damage = calculate_melee_damage(target, is_crit)
	damage = int(damage * 0.5)  # Off-hand is 50% damage
	return damage

func apply_ac_mitigation(raw_damage: int, target: CombatNode) -> int:
	"""Apply AC-based damage reduction"""
	var target_ac = target.get_ac()
	var damage_reduction = target_ac / float(target_ac + 100 + (target.level * 10))
	var final_damage = int(raw_damage * (1.0 - damage_reduction))
	# Racial physical damage resistance (e.g. Dwarf/Ogre +5%) — a flat extra
	# reduction on top of AC mitigation, not folded into the AC formula itself.
	if target.race_physical_resist > 0.0:
		final_damage = int(final_damage * (1.0 - target.race_physical_resist))
	return max(1, final_damage)

func calculate_spell_damage(base_spell_damage: int, resist_type: String = "magic", target: CombatNode = null, is_crit: bool = false, skill_category: String = "") -> int:
	"""Calculate spell damage with resist checks. resist_type is one of the
	10 finalized spell_school damage types (see game_flow.txt's "Spell
	Classification" section, 2026-09-19) — physical/fire/cold/acid/
	lightning/poison/disease/magic/divine/psychic/spirit. Power source is
	divine for "divine"-school spells (Lightsworn/Lightmender), arcane for
	everything else — this used to be a bare is_arcane bool covering only
	two resist pools (arcane/divine); every other school silently fell into
	whichever one the caller picked, since there was no way to express a
	third option. Replaced 2026-09-19 so damage is actually resisted by the
	specific type it deals, not just lumped into arcane or divine."""
	var use_divine_power := resist_type == "divine"
	var spell_power = get_divine_power() if use_divine_power else get_arcane_power()
	var damage = base_spell_damage + spell_power

	# Apply crit if applicable
	if is_crit:
		damage = int(damage * 1.75)  # 175% crit damage for spells

	# Subtract target resist if provided. get_resistance() appends "_resist"
	# itself (see its definition) — this used to pass the already-suffixed
	# name ("arcane_resist"/"divine_resist"), producing a lookup for
	# "arcane_resist_resist" that never matched anything, so spell damage has
	# never actually been resisted by ANY target, player or monster. Found
	# during the 2026-09-14 monster balance pass.
	if target:
		var target_resist := target.get_resistance(resist_type) + int(target.get_modifier("magic_resist_bonus"))
		damage = int(damage * (1.0 - (target_resist / 100.0)))

	damage = int(damage * (1.0 + get_modifier("damage_mult")))

	# Skills: general spell casting + the spell's own school (Data/skill_effects.json)
	damage = int(damage * (1.0 + skill_bonus("spell_potency_pct", skill_category) / 100.0))

	# Racial spell damage bonus/penalty (e.g. Elf +5%, Half-Orc -5%)
	if race_spell_damage_mult != 0.0:
		damage = int(damage * (1.0 + race_spell_damage_mult))

	# Tunable spell damage for players (Data/combat_balance.json)
	if CombatBalance.role_of(self) == "player":
		damage = int(damage * CombatBalance.num("player_spell_damage_mult"))

	return max(1, damage)

func calculate_healing(base_heal: int, is_crit: bool = false) -> int:
	"""Calculate healing output"""
	var divine_power = get_divine_power()
	var heal_amount = base_heal + divine_power

	# Apply crit
	if is_crit:
		heal_amount = int(heal_amount * 1.5)  # 150% heal crit

	return heal_amount

# ================================================================================
# ⭐ HIT CHANCE CALCULATIONS
# ================================================================================

func calculate_hit_chance(target: CombatNode) -> int:
	"""Calculate hit chance vs target AC"""
	var level_modifier = (level - target.level) * CombatBalance.num("hit_level_diff_per_level")
	level_modifier = clamp(level_modifier, -50, 50)

	var atk = get_atk()
	var target_ac = target.get_ac()
	var hit_chance = (atk - target_ac) + int(level_modifier) + randi() % 21

	# Active buff/debuff accuracy modifiers (e.g. shadow_aura applied to an attacking monster)
	hit_chance += int(get_modifier("hit_chance"))

	# Tunable accuracy for players / monsters (Data/combat_balance.json)
	match CombatBalance.role_of(self):
		"player": hit_chance += int(CombatBalance.num("player_hit_bonus"))
		"monster": hit_chance += int(CombatBalance.num("monster_hit_bonus"))

	# Hard caps
	hit_chance = clampi(hit_chance, int(CombatBalance.num("hit_min")), int(CombatBalance.num("hit_max")))

	return hit_chance

func calculate_resist_chance(target: CombatNode, resist_type: String = "magic") -> int:
	"""Calculate spell resist chance"""
	var level_modifier = (target.level - level) * 10
	var my_power = get_divine_power() if resist_type == "divine" else get_arcane_power()
	var target_resist = target.get_resistance(resist_type)

	var resist_chance = int((target_resist - my_power + level_modifier) / 2.0)
	resist_chance = clamp(resist_chance, 0, 200)

	return resist_chance

# ================================================================================
# ⭐ ATTACK ROLLS
# ================================================================================

func roll_attack(target: CombatNode, advantage: bool = false, disadvantage: bool = false) -> Dictionary:
	"""Roll to hit with advantage/disadvantage"""
	var hit_chance = calculate_hit_chance(target)
	var roll = randi() % 100 + 1
	var is_hit = roll <= hit_chance
	var is_crit = roll >= 95 and is_hit
	var is_miss = roll <= 5

	return {
		"roll": roll,
		"hit_chance": hit_chance,
		"is_hit": is_hit,
		"is_crit": is_crit,
		"is_miss": is_miss
	}

func roll_crit(crit_chance: int = -1) -> bool:
	"""Roll for critical hit"""
	if crit_chance == -1:
		crit_chance = get_crit_chance()

	var roll = randi() % 100 + 1
	return roll <= crit_chance

func roll_dodge() -> bool:
	"""Roll to dodge"""
	var dodge_chance = get_dodge_chance()
	var roll = randi() % 100 + 1
	return roll <= dodge_chance

func roll_parry() -> bool:
	"""Roll to parry"""
	var parry_chance = get_parry_chance()
	var roll = randi() % 100 + 1
	return roll <= parry_chance

func roll_block() -> bool:
	"""Roll to block (requires shield)"""
	if not has_shield:
		return false
	var block_chance = get_block_chance()
	var roll = randi() % 100 + 1
	return roll <= block_chance

func roll_riposte() -> bool:
	"""Roll to riposte (requires successful parry first)"""
	var riposte_chance = get_riposte_chance()
	var roll = randi() % 100 + 1
	return roll <= riposte_chance

# ================================================================================
# ⭐ COMBAT RESOLUTION (Main Attack Sequence)
# ================================================================================

# True if this CombatNode's owner is positioned in target's rear hemisphere
# (dot product of target's forward vector and the direction to the attacker
# is negative) — i.e. the attack is coming from behind the target, which
# resolve_attack() uses to bypass all four defensive rolls. Missing node refs
# (an owner not in the 3D scene, e.g. a pure test CombatNode) or an
# attacker standing exactly on top of the target default to "in front" —
# not being able to prove the attack is a backstab means it isn't one.
func is_attacked_from_behind(target: CombatNode) -> bool:
	var attacker_node: Node3D = get_parent() as Node3D
	var defender_node: Node3D = target.get_parent() as Node3D
	if not attacker_node or not defender_node:
		return false
	var to_attacker: Vector3 = attacker_node.global_position - defender_node.global_position
	to_attacker.y = 0.0
	if to_attacker.length() < 0.01:
		return false
	var defender_forward: Vector3 = -defender_node.global_transform.basis.z
	defender_forward.y = 0.0
	if defender_forward.length() < 0.01:
		return false
	return defender_forward.normalized().dot(to_attacker.normalized()) < 0.0


func resolve_attack(target: CombatNode) -> Dictionary:
	"""
	Main attack sequence:
	1. Miss check
	2. Riposte check (defender)
	3. Parry check (defender)
	4. Block check (defender)
	5. Dodge check (defender)
	6. Hit - calculate damage
	"""
	break_invisibility()
	mark_engaged()
	if target:
		target.mark_engaged()

	# 1. MISS CHECK
	var attack_roll = roll_attack(target)
	if attack_roll["is_miss"]:
		return {
			"result": "MISS",
			"damage": 0,
			"message": "Your attack misses!"
		}

	if not attack_roll["is_hit"]:
		return {
			"result": "MISS",
			"damage": 0,
			"message": "Your attack misses!"
		}

	# Positional combat: block/parry/dodge/riposte all require the defender to
	# actually be facing their attacker — you can't parry a blade you never
	# saw coming. Attacking from behind (a rogue backstab, a flanking pet)
	# skips straight to the hit roll, bypassing all four defensive checks.
	var from_behind := is_attacked_from_behind(target)

	# 2. RIPOSTE CHECK (Defender)
	if not from_behind and target.roll_parry():
		if target.roll_riposte():
			var riposte_damage = target.calculate_melee_damage(self)
			var riposte_crit = target.roll_crit()
			if riposte_crit:
				riposte_damage = target.calculate_melee_damage(self, true)
			riposte_damage += int(target.get_modifier("riposte_bonus_damage"))
			riposte_damage = apply_ac_mitigation(riposte_damage, self)
			riposte_damage = absorb_incoming_damage(riposte_damage)
			current_hp -= riposte_damage
			return {
				"result": "RIPOSTE",
				"damage": riposte_damage,
				"message": "Your opponent ripostes for " + str(riposte_damage) + " damage!"
			}

	# 3. PARRY CHECK (Defender)
	if not from_behind and target.roll_parry():
		return {
			"result": "PARRY",
			"damage": 0,
			"message": "Your attack is parried!"
		}

	# 4. BLOCK CHECK (Defender)
	if not from_behind and target.roll_block():
		var stagger_chance: float = target.get_modifier("stagger_chance")
		if target.has_passive("improved_block"):
			stagger_chance += 0.05
		if stagger_chance > 0.0 and randf() < stagger_chance:
			var attacker_node: Node = get_parent()
			if attacker_node and "attack_timer" in attacker_node and "attack_cooldown" in attacker_node:
				attacker_node.can_attack = false
				attacker_node.attack_timer = attacker_node.attack_cooldown * 1.5
			return {
				"result": "BLOCK",
				"damage": 0,
				"message": "Your attack is blocked, and you are staggered!"
			}
		return {
			"result": "BLOCK",
			"damage": 0,
			"message": "Your attack is blocked!"
		}

	# 5. DODGE CHECK (Defender)
	if not from_behind and target.roll_dodge():
		return {
			"result": "DODGE",
			"damage": 0,
			"message": "Your attack is dodged!"
		}

	# 6. HIT - CALCULATE DAMAGE
	var is_crit = roll_crit()
	var damage = calculate_melee_damage(target, is_crit)
	damage = apply_ac_mitigation(damage, target)
	# Generic flat "% less damage taken" modifier — e.g. Spiritweaver's Earth
	# Totem — distinct from absorb (a depletable shield) and damage_drain_pct
	# (heal-back): this just reduces the hit outright.
	damage = int(damage * (1.0 - target.get_modifier("damage_taken_mult")))
	damage = target.absorb_incoming_damage(damage)

	target.current_hp -= damage

	# Blood Aegis — "converts 20% incoming damage to health drain," i.e. the
	# defender heals for a cut of the damage they just took rather than the
	# damage itself being reduced.
	var drain_pct: float = target.get_modifier("damage_drain_pct")
	if drain_pct > 0.0 and damage > 0:
		target.heal(int(damage * drain_pct))

	var crit_message = " [CRITICAL]" if is_crit else ""
	return {
		"result": "HIT",
		"damage": damage,
		"is_crit": is_crit,
		"message": "You hit for " + str(damage) + " damage!" + crit_message
	}

# ================================================================================
# ⭐ DUAL-WIELD ATTACK SEQUENCE
# ================================================================================

func resolve_dual_wield_attack(target: CombatNode) -> Dictionary:
	"""Execute both main-hand and off-hand attacks"""
	var main_hand = resolve_attack(target)

	# Off-hand has -10% hit chance
	var offhand_hit_chance = calculate_hit_chance(target) - 10
	var roll = randi() % 100 + 1

	if roll > offhand_hit_chance:
		return {
			"result": "DUAL_WIELD",
			"main_hand": main_hand,
			"off_hand": {
				"result": "MISS",
				"damage": 0,
				"message": "Off-hand attack misses!"
			},
			"total_damage": main_hand["damage"]
		}

	# Off-hand hits - go through defensive checks
	var off_hand_result = _resolve_offhand_hit(target)

	return {
		"result": "DUAL_WIELD",
		"main_hand": main_hand,
		"off_hand": off_hand_result,
		"total_damage": main_hand.get("damage", 0) + off_hand_result.get("damage", 0)
	}

func _resolve_offhand_hit(target: CombatNode) -> Dictionary:
	"""Resolve off-hand hit after successful initial roll"""
	# Parry/block/dodge still apply
	if target.roll_parry():
		return {"result": "PARRY", "damage": 0, "message": "Off-hand attack parried!"}
	if target.roll_block():
		return {"result": "BLOCK", "damage": 0, "message": "Off-hand attack blocked!"}
	if target.roll_dodge():
		return {"result": "DODGE", "damage": 0, "message": "Off-hand attack dodged!"}

	# Calculate off-hand damage
	var is_crit = roll_crit()
	var damage = calculate_offhand_damage(target, is_crit)
	damage = apply_ac_mitigation(damage, target)
	damage = int(damage * (1.0 - target.get_modifier("damage_taken_mult")))
	damage = target.absorb_incoming_damage(damage)

	target.current_hp -= damage

	var offhand_drain_pct: float = target.get_modifier("damage_drain_pct")
	if offhand_drain_pct > 0.0 and damage > 0:
		target.heal(int(damage * offhand_drain_pct))

	var crit_message = " [CRITICAL]" if is_crit else ""
	return {
		"result": "HIT",
		"damage": damage,
		"is_crit": is_crit,
		"message": "Off-hand hits for " + str(damage) + " damage!" + crit_message
	}

# ================================================================================
# ⭐ AETHERFIST MULTI-ATTACK SYSTEM
# ================================================================================

func resolve_aetherfist_attack(target: CombatNode) -> Dictionary:
	"""
	Aetherfist flurry of fists:
	1. Main-hand attack
	2. Double Attack check
	3. Triple Attack check (if double succeeds)
	"""

	var main_attack = resolve_attack(target)
	if main_attack["result"] != "HIT":
		return main_attack

	var total_damage = main_attack["damage"]
	var attack_count = 1
	var result_text = "Main-hand: " + str(main_attack["damage"]) + " damage"

	# DOUBLE ATTACK CHECK (Level 10+)
	if level >= 10:
		var double_chance = 40 + int(dexterity * 0.3) + (level - 10) + int(skill_bonus("double_attack_chance"))
		double_chance = clamp(double_chance, 0, 100)

		var roll = randi() % 100 + 1
		if roll <= double_chance:
			var second_attack = resolve_attack(target)
			if second_attack["result"] == "HIT":
				total_damage += second_attack["damage"]
				attack_count += 1
				result_text += "\nDouble attack: " + str(second_attack["damage"]) + " damage"

				# TRIPLE ATTACK CHECK (Level 15+)
				if level >= 15:
					var triple_chance = 15 + int(dexterity * 0.2) + int((level - 15) * 0.5) + int(skill_bonus("triple_attack_chance"))
					triple_chance = clamp(triple_chance, 0, 100)

					var triple_roll = randi() % 100 + 1
					if triple_roll <= triple_chance:
						var third_attack = resolve_attack(target)
						if third_attack["result"] == "HIT":
							total_damage += third_attack["damage"]
							attack_count += 1
							var crit_tag = " [CRITICAL]" if third_attack.get("is_crit", false) else ""
							result_text += "\nTriple attack: " + str(third_attack["damage"]) + " damage" + crit_tag

	return {
		"result": "AETHERFIST_FLURRY",
		"attack_count": attack_count,
		"total_damage": total_damage,
		"message": result_text
	}

# ================================================================================
# ⭐ SPELL CASTING & INTERRUPTS
# ================================================================================

func start_spell_cast(cast_time: float):
	"""Begin casting a spell"""
	is_casting = true
	total_cast_time = cast_time
	current_cast_time = 0.0

func interrupt_spell(target: CombatNode, mana_cost: int) -> Dictionary:
	"""Interrupt a spell being cast"""
	if not is_casting:
		return {"result": "NOT_CASTING", "mana_lost": 0}

	# Calculate cast progress
	var cast_progress = (current_cast_time / total_cast_time) * 100

	# Concentration check
	var concentration = get_concentration()
	var concentration_roll = randi() % 100 + 1

	# Boost concentration by cast progress
	var adjusted_concentration = concentration + int(cast_progress / 2.0)
	adjusted_concentration = clamp(adjusted_concentration, 0, 95)

	if concentration_roll <= adjusted_concentration:
		# SUCCESS - cast continues uninterrupted, no mana loss
		return {
			"result": "CONCENTRATION_SUCCESS",
			"mana_lost": 0,
			"message": "You maintain concentration!"
		}

	# FAILURE - cast is disrupted, lose mana based on progress
	is_casting = false
	var mana_lost = 0
	var message = ""

	if cast_progress < 25:
		mana_lost = mana_cost
		message = "Your spell is disrupted!"
	elif cast_progress < 50:
		mana_lost = int(mana_cost * 0.75)
		message = "Your spell partially fizzles!"
	elif cast_progress < 75:
		mana_lost = int(mana_cost * 0.5)
		message = "You salvage some mana!"
	else:
		mana_lost = int(mana_cost * 0.25)
		message = "You nearly completed the spell!"

	current_mana = max(0, current_mana - mana_lost)

	return {
		"result": "CONCENTRATION_FAILURE",
		"mana_lost": mana_lost,
		"message": message
	}

# ================================================================================
# ⭐ THREAT SYSTEM
# ================================================================================

func generate_threat(damage_dealt: int, healing_done: int = 0) -> float:
	"""Calculate threat generated by actions"""
	if damage_dealt > 0:
		mark_engaged()
	var threat = float(damage_dealt) + (float(healing_done) * 0.5)
	threat *= (1.0 + get_modifier("threat_mult"))
	threat_value += threat
	return threat

func decay_threat(delta: float = 1.0):
	"""Decay threat over time out of combat"""
	if not in_combat:
		threat_value *= (1.0 - (0.01 * delta))  # 1% decay per second

func reset_threat():
	"""Reset threat on death or combat end"""
	threat_value = 0.0

# ================================================================================
# ⭐ HEALTH & RESOURCE MANAGEMENT
# ================================================================================

func take_damage(amount: int) -> int:
	"""Take damage and return actual damage taken"""
	if amount > 0:
		mark_engaged()
	var damage_taken = min(amount, current_hp)
	current_hp -= damage_taken
	return damage_taken

func heal(amount: int) -> int:
	"""Heal and return actual healing done"""
	var healing_done = min(amount, max_hp - current_hp)
	current_hp += healing_done
	return healing_done

func spend_mana(amount: int) -> bool:
	"""Spend mana, return true if successful"""
	if current_mana >= amount:
		current_mana -= amount
		return true
	return false

func spend_stamina(amount: int) -> bool:
	"""Spend stamina, return true if successful"""
	if current_stamina >= amount:
		current_stamina -= amount
		return true
	return false

func is_alive() -> bool:
	"""Check if character is alive"""
	return current_hp > 0

# ================================================================================
# ⭐ UTILITY FUNCTIONS
# ================================================================================

func get_health_percent() -> float:
	"""Get health as percentage (0.0 to 1.0)"""
	return float(current_hp) / float(max_hp)

func get_mana_percent() -> float:
	"""Get mana as percentage (0.0 to 1.0)"""
	return float(current_mana) / float(max_mana)

func get_stamina_percent() -> float:
	"""Get stamina as percentage (0.0 to 1.0)"""
	return float(current_stamina) / float(max_stamina)

func print_stats():
	"""Debug print all stats"""
	print("=== CHARACTER STATS ===")
	print("Name: ", character_name)
	print("Level: ", level)
	print("Class: ", character_class)
	print("\n=== CORE STATS ===")
	print("STR: ", strength, " | DEX: ", dexterity, " | CON: ", constitution)
	print("INT: ", intelligence, " | WIS: ", wisdom, " | CHA: ", charisma)
	print("LCK: ", luck)
	print("\n=== RESOURCES ===")
	print("HP: ", current_hp, "/", max_hp)
	print("Mana: ", current_mana, "/", max_mana)
	print("Stamina: ", current_stamina, "/", max_stamina)
	print("\n=== OFFENSIVE ===")
	print("ATK: ", get_atk(), " | Weapon Skill: ", weapon_skill)
	print("Crit Chance: ", get_crit_chance(), "% | Crit Damage: ", get_crit_damage(), "%")
	print("Riposte: ", get_riposte_chance(), "%")
	print("\n=== DEFENSIVE ===")
	print("AC: ", get_ac())
	print("Dodge: ", get_dodge_chance(), "% | Parry: ", get_parry_chance(), "% | Block: ", get_block_chance(), "%")
	print("Spirit Resist: ", get_resistance("spirit_resist"))
	print("\n=== SPELLCASTING ===")
	print("Arcane Power: ", get_arcane_power())
	print("Divine Power: ", get_divine_power())
	print("Concentration: ", get_concentration(), "%")
