---
name: project-architecture
description: "Core technical architecture of Aldenexia — engine, key scripts, class hierarchy"
metadata: 
  node_type: memory
  type: project
  originSessionId: d6f652db-ff5d-490f-9513-2e10ddd5de2d
---

Godot 4.x 3D RPG. Primary game loop is 3D (lumora_outskirts3d.tscn). A 2D scene (main.tscn / player.tscn) exists but is secondary.

**Engine:** Godot 4, GDScript. No C# or GDNative.

**Key autoloads:** Global (global.gd), Inventory (inventory_autoload.gd), GameLog (game_log.gd)

**Combat system:** CombatNode (Scripts/combatnode.gd, class_name CombatNode) is the single source of truth for all stats and combat math. Every combatant owns one as a child node.

**Player scripts:**
- `player3d.gd` (class_name Player3D, extends CharacterBody3D) — active 3D player
- `player.gd` (extends CharacterBody2D) — 2D player, still referenced by player.tscn / main.tscn

**Monster scripts:**
- `monster3d.gd` (class_name Monster, extends CharacterBody3D) — active 3D base class for all enemies
- `mob.gd` (class_name Mob, extends CharacterBody2D) — deprecated 2D base, kept because mob_spawner.tscn references it

**Why:** All 2D monster scripts (bandit.gd, rat.gd, etc.) extend Mob, but the active game uses Monster (3D).

**How to apply:** Always update monster3d.gd and player3d.gd for active game features. mob.gd and player.gd only need to stay compilable.
