extends Node
class_name CombatNode

# --- Core Stats ---
var level: int = 1
var proficiency_bonus: int = 2
var strength_mod: int = 0
var dexterity_mod: int = 0
var constitution_mod: int = 0
var intelligence_mod: int = 0
var wisdom_mod: int = 0
var charisma_mod: int = 0
var armor_class: int = 10
var spellcasting_ability: String = "intelligence"  # or "wisdom", "charisma"

# --- Initialization ---
func _ready():
    randomize()
    proficiency_bonus = get_proficiency_bonus(level)

func get_proficiency_bonus(level):
    if level < 5: return 2
    elif level < 9: return 3
    elif level < 13: return 4
    elif level < 17: return 5
    else: return 6

# --- Dice Rolling ---
func roll_d20():
    return randi() % 20 + 1

func roll_d20_with_advantage():
    return max(roll_d20(), roll_d20())

func roll_d20_with_disadvantage():
    return min(roll_d20(), roll_d20())

func roll_dice(num: int, sides: int) -> int:
    var total = 0
    for i in num:
        total += randi() % sides + 1
    return total

# --- Attack Rolls ---
func roll_attack(use_strength: bool, advantage: bool = false, disadvantage: bool = false):
    var base_roll = roll_d20()
    if advantage and disadvantage:
        pass  # Cancel out
    elif advantage:
        base_roll = roll_d20_with_advantage()
    elif disadvantage:
        base_roll = roll_d20_with_disadvantage()

    var ability_mod = use_strength ? strength_mod : dexterity_mod
    var total_roll = base_roll + ability_mod + proficiency_bonus

    return {
        "roll": base_roll,
        "total": total_roll,
        "is_critical": base_roll == 20,
        "is_fail": base_roll == 1
    }

func check_hit(attack_total: int, target_ac: int) -> bool:
    return attack_total >= target_ac

# --- Damage Calculation ---
func calculate_damage(base_damage: int, is_critical: bool) -> int:
    if is_critical:
        match randi() % 3:
            0: print("You land a critical blow on the enemy!")
            1: print("You stagger your opponent with a massive strike!")
            2: print("Your critical hit sends your target into a panic!")
        return base_damage * 2
    return base_damage

# --- Critical Fail Flavor ---
func handle_critical_fail():
    match randi() % 3:
        0: print("You swing your weapon wildly and miss!")
        1: print("You stumble and trip over your own feet!")
        2: print("You flail wildly and accidentally hit an ally!")

# --- Spellcasting ---
func get_spellcasting_mod():
    match spellcasting_ability:
        "intelligence": return intelligence_mod
        "wisdom": return wisdom_mod
        "charisma": return charisma_mod
        _: return 0

func roll_spell_attack(advantage: bool = false, disadvantage: bool = false):
    var base_roll = roll_d20()
    if advantage and disadvantage:
        pass
    elif advantage:
        base_roll = roll_d20_with_advantage()
    elif disadvantage:
        base_roll = roll_d20_with_disadvantage()

    var spell_mod = get_spellcasting_mod()
    var total = base_roll + spell_mod + proficiency_bonus

    return {
        "roll": base_roll,
        "total": total,
        "is_critical": base_roll == 20,
        "is_fail": base_roll == 1
    }

func get_spell_save_dc():
    return 8 + proficiency_bonus + get_spellcasting_mod()

# --- Saving Throws ---
func roll_saving_throw(ability: String, dc: int, advantage: bool = false, disadvantage: bool = false) -> Dictionary:
    var mod = match ability:
        "strength": strength_mod
        "dexterity": dexterity_mod
        "constitution": constitution_mod
        "intelligence": intelligence_mod
        "wisdom": wisdom_mod
        "charisma": charisma_mod
        _: 0

    var roll = roll_d20()
    if advantage and disadvantage:
        pass
    elif advantage:
        roll = roll_d20_with_advantage()
    elif disadvantage:
        roll = roll_d20_with_disadvantage()

    var total = roll + mod
    var success = total >= dc

    return {
        "roll": roll,
        "total": total,
        "success": success,
        "is_critical": roll == 20,
        "is_fail": roll == 1
    }
