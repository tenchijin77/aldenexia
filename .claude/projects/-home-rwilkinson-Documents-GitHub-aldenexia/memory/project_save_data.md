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

**known_spells:** Array of spell **name strings** (e.g. `["power_strike", "battle_shout"]`). Spellbook only shows spells in this list — players must find/train/purchase/research spells before they appear. Master definitions live in Data/player_spells.json. Action bar slots 1–12 map to known_spells[0–11].

**equipment dict:** All slots empty strings at character creation — players equip manually from inventory. `apply_equipment()` still runs at load for legacy saves that stored item_id strings here. New saves rely on `inventory_data["equipped"]` (the live paperdoll) instead.

**inventory_data:** Full Inventory autoload state — `basic_inventory` (12 slots), `bag_contents` (dict of bag-slot-index → item arrays), `bank_storage`, `equipped` (paperdoll). Saved/restored via `Inventory.save_inventory_data()` / `load_inventory_data()`. After load, `_apply_equipment_from_inventory()` re-derives CombatNode stats from the paperdoll.

**Starting inventory layout (new characters):**
- `basic_inventory[0]` = small_bag (4 slots) containing: faded_note, iron_rations×20, water_flask×20, torch×5
- `basic_inventory[1–5]` = class armor (ragged_hood, ragged_tunic, ragged_leggings, torn_boots, cloth_cape)
- `basic_inventory[1]` prepended with weapon for melee/ranger classes (rusty_sword or dagger)
- All `equipped` slots empty — player must manually drag gear to paperdoll

**ui_positions dict:** Stored in player_data under `"ui_positions"`. Keys: `"chat"`, `"action_bar"`. Values: `[offset_left, offset_top, offset_right, offset_bottom]`. Written on drag release, read on window _ready().

**Save trigger points:** `Global.save_player_data_to_file()` is called on equip (via equipment_changed signal), on window drag release, and from pause menu Save Game / Save and Exit buttons.

**Dev fallback:** When `Global.player_data` is empty (direct scene launch from editor), player3d.gd builds Inventory directly (same layout as new characters), then sets hardcoded Blademaster player_data including the inventory_data snapshot. `res://Data/character_stats.json` archived to `archive-2d/Data/`.

**Why:** The old "derived" section in saves was removed — CombatNode calculates at load. Old saves still load; load_character_data() ignores unknown keys.
