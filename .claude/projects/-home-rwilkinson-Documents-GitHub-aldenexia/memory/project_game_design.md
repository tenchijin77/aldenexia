---
name: project-game-design
description: "Core game design principles — EQ-style mechanics, class system, combat feel"
metadata: 
  node_type: memory
  type: project
  originSessionId: d6f652db-ff5d-490f-9513-2e10ddd5de2d
---

Aldenexia is an EverQuest-inspired 3D RPG built in Godot 4.

**Combat style:** EQ-style tab-target with auto-attack. No action combat. Player presses Tab to cycle targets, toggles auto-attack on/off.

**Regen:** 6-second tick (EQ-style), not per-frame. HP and mana regen on the tick. Stamina regens per second (movement resource).

**Con system:** Target name colored by level difference. Red (≥5 above) through grey (≥6 below, no XP). See [[project-ui-systems]] for exact thresholds.

**Grey mobs give no XP** — this must be enforced in the XP award logic when implemented.

**Classes (12+):** Blademaster, Aetherfist, Shadowblade, Voidknight, Lightsworn, Woodstalker, Troubadour, Spiritweaver, Gravecaller, Runecaster, Arcanist, Chaosborn. Full list in Data/character_options.json.

**Spellbook gating:** Players must find, train, purchase, or research spells before they appear in their spellbook. Data/player_spells.json holds all 477+ definitions; known_spells in save data holds what each character has learned. [[project-spellbook-design]]

**Vitals:** satiety (hunger) and thirst decay over time. Below 25 reduces regen. At 0 deals periodic damage (non-lethal — floors at 1 HP).

**Social monsters:** call_nearby_allies() when attacked. Allies within aggro_range of same faction join combat.

**Dual-wield and Aetherfist flurry** are class-specific multi-attack systems in CombatNode. [[project-combat-system]]
