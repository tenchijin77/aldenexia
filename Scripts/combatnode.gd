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

	# Health (HP)
	var base_hp = 50  # Base for level 1
	var con_bonus = constitution * 10
	var hp_from_class = int(base_hp * class_hp_bonus) if class_hp_bonus > 0 else 0
	max_hp = base_hp + con_bonus + hp_from_class + gear_hp
	current_hp = min(current_hp, max_hp)
	_cached_stats["max_hp"] = max_hp

	# Mana (MP)
	var base_mana = 30  # Base for level 1
	var int_wis_bonus = (intelligence + wisdom) * 5
	var mana_from_class = int(base_mana * class_mana_bonus) if class_mana_bonus > 0 else 0
	max_mana = base_mana + int_wis_bonus + mana_from_class + gear_mana
	current_mana = min(current_mana, max_mana)
	_cached_stats["max_mana"] = max_mana

	# Stamina
	max_stamina = 100 + (constitution * 5)
	current_stamina = min(current_stamina, max_stamina)
	_cached_stats["max_stamina"] = max_stamina

	# Attack Rating (ATK)
	var atk = (weapon_skill * 2) + strength + int(dexterity / 2.0) + gear_atk
	_cached_stats["attack_rating"] = atk

	# Armor Class (AC)
	var ac = 10 + gear_ac + int(dexterity / 2.0) + class_ac_bonus
	if has_shield and shield_bonus_map.has(shield_type):
		ac += shield_bonus_map[shield_type]
	_cached_stats["armor_class"] = ac

	# Crit Chance
	var base_crit = 5
	var class_crit_bonus = _get_class_crit_bonus()
	var crit_chance = base_crit + int((dexterity + luck) / 2.0) + class_crit_bonus + gear_crit
	crit_chance = clamp(crit_chance, 0, 60)  # Hard cap at 60%
	_cached_stats["crit_chance"] = crit_chance

	# Crit Damage
	var crit_damage = 150 + int(luck * 0.5) + gear_crit_damage
	_cached_stats["crit_damage"] = crit_damage

	# Riposte Chance
	var riposte = class_riposte_base + int(dexterity * 0.2) + int(weapon_skill * 0.1) + gear_riposte
	riposte = clamp(riposte, 0, 100)
	_cached_stats["riposte_chance"] = riposte

	# Dodge Chance
	var dodge = class_dodge_base + int(dexterity * 0.5)
	dodge = clamp(dodge, 0, 50)  # Soft cap at 50%
	_cached_stats["dodge_chance"] = dodge

	# Parry Chance
	var parry = class_parry_base + int(dexterity * 0.3) + int(weapon_skill * 0.1)
	parry = clamp(parry, 0, 50)  # Soft cap at 50%
	_cached_stats["parry_chance"] = parry

	# Block Chance
	var block = 0
	if has_shield and shield_bonus_map.has(shield_type):
		block = shield_bonus_map[shield_type] + int(dexterity * 0.2)
	block = clamp(block, 0, 50)  # Soft cap at 50%
	_cached_stats["block_chance"] = block

	# Resistances (all types)
	var base_resist = int(constitution / 2.0) + int(wisdom / 2.0)
	_cached_stats["fire_resist"] = clamp(base_resist + gear_ac, 0, 200)
	_cached_stats["cold_resist"] = clamp(base_resist + gear_ac, 0, 200)
	_cached_stats["poison_resist"] = clamp(base_resist + gear_ac, 0, 200)
	_cached_stats["disease_resist"] = clamp(base_resist + gear_ac, 0, 200)
	_cached_stats["arcane_resist"] = clamp(base_resist + gear_ac, 0, 200)
	_cached_stats["divine_resist"] = clamp(base_resist + gear_ac, 0, 200)
	_cached_stats["psychic_resist"] = clamp(base_resist + gear_ac, 0, 200)
	_cached_stats["spirit_resist"] = clamp(int((constitution + wisdom) / 2.0) + gear_spirit_resist, 0, 200)

	# Health Regeneration (per 6-second tick)
	var hp_regen = 1 + int(constitution / 5.0)  # Base + CON scaling
	_cached_stats["hp_regen"] = hp_regen

	# Mana Regeneration (per 6-second tick)
	var mana_regen = 1 + int(wisdom / 5.0)  # Base + WIS scaling
	_cached_stats["mana_regen"] = mana_regen

	# Stamina Regeneration (per second)
	var stamina_regen = 10 + int(constitution / 5.0)
	_cached_stats["stamina_regen"] = stamina_regen

	# Spell Power (Arcane)
	var arcane_power = (intelligence * 2) + gear_spell_power
	_cached_stats["arcane_power"] = arcane_power

	# Spell Power (Divine/Nature)
	var divine_power = (wisdom * 2) + gear_healing_power
	_cached_stats["divine_power"] = divine_power

	# Concentration
	var concentration = class_concentration_base + int(wisdom / 2.0) + int(intelligence / 4.0) + gear_concentration
	concentration = clamp(concentration, 0, 95)  # Hard cap at 95%
	_cached_stats["concentration"] = concentration

	# Carry Weight
	var carry_weight = 100 + (strength * 2)
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
	return get_derived_stat("block_chance")

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

	# Apply crit
	if is_crit:
		var crit_dmg_mult = 1.0 + (get_crit_damage() / 100.0)
		raw_damage = int(raw_damage * crit_dmg_mult)

	# Apply level modifier
	raw_damage = int(raw_damage * (1.0 + (level_modifier / 100.0)))

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
	return max(1, final_damage)

func calculate_spell_damage(base_spell_damage: int, is_arcane: bool = true, target: CombatNode = null, is_crit: bool = false) -> int:
	"""Calculate spell damage with resist checks"""
	var spell_power = get_arcane_power() if is_arcane else get_divine_power()
	var damage = base_spell_damage + spell_power

	# Apply crit if applicable
	if is_crit:
		damage = int(damage * 1.75)  # 175% crit damage for spells

	# Subtract target resist if provided
	if target:
		var resist_type = "arcane_resist" if is_arcane else "divine_resist"
		var target_resist = target.get_resistance(resist_type)
		damage = int(damage * (1.0 - (target_resist / 100.0)))

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
	var level_modifier = (level - target.level) * 5
	level_modifier = clamp(level_modifier, -50, 50)

	var atk = get_atk()
	var target_ac = target.get_ac()
	var hit_chance = (atk - target_ac) + level_modifier + randi() % 21

	# Hard caps
	hit_chance = clamp(hit_chance, 5, 95)

	return hit_chance

func calculate_resist_chance(target: CombatNode, is_arcane: bool = true) -> int:
	"""Calculate spell resist chance"""
	var level_modifier = (target.level - level) * 10
	var my_power = get_arcane_power() if is_arcane else get_divine_power()
	var target_resist = target.get_resistance("arcane_resist" if is_arcane else "divine_resist")

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

	# 2. RIPOSTE CHECK (Defender)
	if target.roll_parry():
		if target.roll_riposte():
			var riposte_damage = target.calculate_melee_damage(self)
			var riposte_crit = target.roll_crit()
			if riposte_crit:
				riposte_damage = target.calculate_melee_damage(self, true)
			riposte_damage = apply_ac_mitigation(riposte_damage, self)
			current_hp -= riposte_damage
			return {
				"result": "RIPOSTE",
				"damage": riposte_damage,
				"message": "Your opponent ripostes for " + str(riposte_damage) + " damage!"
			}

	# 3. PARRY CHECK (Defender)
	if target.roll_parry():
		return {
			"result": "PARRY",
			"damage": 0,
			"message": "Your attack is parried!"
		}

	# 4. BLOCK CHECK (Defender)
	if target.roll_block():
		return {
			"result": "BLOCK",
			"damage": 0,
			"message": "Your attack is blocked!"
		}

	# 5. DODGE CHECK (Defender)
	if target.roll_dodge():
		return {
			"result": "DODGE",
			"damage": 0,
			"message": "Your attack is dodged!"
		}

	# 6. HIT - CALCULATE DAMAGE
	var is_crit = roll_crit()
	var damage = calculate_melee_damage(target, is_crit)
	damage = apply_ac_mitigation(damage, target)

	target.current_hp -= damage

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

	target.current_hp -= damage

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
		var double_chance = 40 + int(dexterity * 0.3) + (level - 10)
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
					var triple_chance = 15 + int(dexterity * 0.2) + int((level - 15) * 0.5)
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

	is_casting = false

	if concentration_roll <= adjusted_concentration:
		# SUCCESS - no mana loss
		return {
			"result": "CONCENTRATION_SUCCESS",
			"mana_lost": 0,
			"message": "You maintain concentration!"
		}

	# FAILURE - lose mana based on progress
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
	var threat = float(damage_dealt) + (float(healing_done) * 0.5)
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
