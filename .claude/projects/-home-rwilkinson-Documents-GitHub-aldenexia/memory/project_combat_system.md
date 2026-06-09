---
name: project-combat-system
description: "CombatNode design — stats, combat resolution, how players and monsters are wired to it"
metadata: 
  node_type: memory
  type: project
  originSessionId: d6f652db-ff5d-490f-9513-2e10ddd5de2d
---

CombatNode (Scripts/combatnode.gd) owns all combat math. Both Player3D and Monster own one as a child node instantiated in _ready().

**7 base stats:** strength, constitution, dexterity, intelligence, wisdom, charisma, luck. This is the canonical stat list — agility was an old stat and is gone.

**Resources:** current_hp / max_hp, current_mana / max_mana, current_stamina / max_stamina

**Derived stats** (calculated via recalculate_derived_stats(), cached with dirty flag):
- AC = 10 + gear_ac + dex/2 + class_ac_bonus
- ATK = (weapon_skill×2) + str + dex/2 + gear_atk
- max_hp = 50 + (con×10) + gear_hp
- max_mana = 30 + (int+wis)×5 + gear_mana
- hp_regen per 6-sec tick = 1 + con/5
- mana_regen per 6-sec tick = 1 + wis/5

**Combat resolution order** (resolve_attack): miss → riposte (parry+riposte rolls) → parry → block → dodge → hit

**Monster CombatNode setup** (flat override approach — avoids formula mismatch):
- All base stats set to 0
- gear_ac = monsters.json armor_class - 10
- gear_hp = monsters.json health - 50
- gear_atk = 40 + level × 10 (gives ~40-60% hit rate vs typical player AC)
- weapon_damage = monsters.json damage

**Regen tick:** 6 seconds (EQ-style), not per-frame. Stamina regens per second.

**Why:** resolve_attack() modifies BOTH sides' current_hp directly (riposte hits attacker). Callers must sync health bars after any resolve_attack() call.

**How to apply:** After resolve_attack(), always check is_alive() on both sides and call sync_health_bar() on monsters. [[project-architecture]]
