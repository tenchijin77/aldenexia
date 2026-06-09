---
name: project-save-data
description: "Character save file schema — what's stored, where, and what CombatNode calculates at runtime"
metadata: 
  node_type: memory
  type: project
  originSessionId: d6f652db-ff5d-490f-9513-2e10ddd5de2d
---

Save files live at `user://saves/<character_name>_character_stats.json`.

**Canonical save schema (post-refactor):**
```json
{
  "player_name": "string",
  "player_class": "string",
  "player_race": "string",
  "player_level": 1,
  "stats": {
    "strength": 10, "constitution": 10, "dexterity": 10,
    "intelligence": 10, "wisdom": 10, "charisma": 10, "luck": 10
  },
  "known_spells": [],
  "current_hp": -1,
  "current_mana": -1,
  "current_stamina": 100,
  "satiety": 100,
  "thirst": 100,
  "xp": 0, "xp_next_level": 100,
  "copper": 0, "silver": 0, "gold": 0, "platinum": 0,
  "resistances": { "acid": 0, "cold": 0, "fire": 0, "magic": 0, "psychic": 0 },
  "equipment": { ... },
  "inventory_data": { ... }
}
```

**NOT saved** (CombatNode calculates at load time from base stats): max_hp, max_mana, max_stamina, armor_class, crit_chance, spell_power, max_weight.

**current_hp convention:** -1 means "default to max" (new character). Actual current HP stored as positive int for in-progress saves.

**known_spells:** Array of spell IDs (ints). Spellbook only shows spells in this list — players must find/train/purchase/research spells before they appear. Master definitions live in Data/player_spells.json.

**Why:** The old "derived" section in saves (health, mana, crit_chance, spell_power, max_weight) was removed — CombatNode owns those calculations now. Old saves with derived sections still load; load_character_data() ignores unknown keys.
