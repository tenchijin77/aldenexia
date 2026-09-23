var level: int
var proficiency_bonus: int
var strength: int
var dexterity: int
var agility: int
var wisdom: int
var intelligence: int
var charisma: int
var armor_class: int
var spellcasting_ability = "wisdom" # could be dynamic

#check proficiency bonus based on level
func get_proficiency_bonus(level):
  if level < 5: return 2
  elif level < 9: return 3
  elif level < 13: return 4
  elif level < 17: return 5
  else: return 6

#weapon attack
func roll_attack(str_mod, prof_bonus):
  var roll = randi() % 20 + 1 # d20 roll
  return roll + str_mod+ prof_bonus

#check to hit roll
func check_hit(attack_roll, target_ac):
  return attack_roll >= target_ac

#spell attack
func get_spell_attack(modifier, prof_bonus):
  return randi() % 20 + 1 + modifier + prof_bonus

#spell save DC
func get_spell_save_dc(modifier, prof_bonus):
  return 8 + modifier + prof_bonus

#attacking target roll_attack
func attack_target(attacker, target):
  var roll = attacker.roll_attack(attacker.strength, attacker.proficiency_bonus)
  return attacker.check_hit(roll, target.armor_class)
