---
name: architecture
description: "Key technical details — scripts, physics layers, global state, patterns used"
metadata: 
  node_type: memory
  type: project
  originSessionId: 7ab18f2e-6f8a-4e69-a254-4eedf47e49d1
---

**Global autoload (`global.gd`):** Tracks score, wave, coins, villagers saved/lost, time survived, high scores (JSON at user://saves/high_scores.json), killer_name (for epitaphs), game_active flag, boss_fight_active. `generate_epitaph(killer: String)` is a static function — killer is the script basename of the attacker (e.g. "goblin", "mh_orzath", "victory").

**Physics layers (bitmask values):**
- Layer 5 (value 16): wall tiles and boundary walls — player collides with this
- Player collision_mask = 538 (layers 2, 4, 5, 10)
- Do NOT use layer 1 for walls — player mask excludes it

**Tile system:** TileMapLayer nodes (grass, roads, town, walls), 32×32 px tiles. Map bounds computed at runtime via `get_used_rect()` in main.gd `_ready()`.

**Damage system:** `take_damage(damage: int, source: Node)` — source is the projectile or monster. Projectiles carry `shooter: Node` pointing back to the monster that fired them. `_identify_killer(source)` in player.gd extracts the script basename for epitaph tracking.

**High scores:** Stored as Array[Dictionary] with keys: score, initials, wave, coins, time_survived, saved_villagers, lost_villagers, epitaph. Epitaph is the death phrase (without initials); display prepends initials at render time.

**Monster base:** All enemies extend monsters.gd. `_cast()` fires projectiles (sets `projectile.shooter = self`). Melee collision passes `self` to `take_damage`. Final boss (mh_orzath.gd) extends monsters.gd.

**Game over flow:**
- Player dies → `Global.killer_name` set → game_over.tscn (high score) or game_over2.tscn
- Boss dies → `_on_boss_died()` in global.gd → victory_scene.tscn
- Victory → "The Wall of Heroes" button → game_over.tscn (no Global.reset() yet)
- game_over.tscn Restart button → Global.reset() → main.tscn
- Guard against simultaneous player+boss death: `_handle_game_over()` returns early if `Global.game_active` is already false

**Touch controls:** touch_controls.tscn (CanvasLayer with two Control nodes). touch_joystick.gd extends Control, uses `_input()` with `InputEventScreenTouch`/`InputEventScreenDrag`, drives `Input.action_press()` with analog strength. Shown only on touchscreen devices via `OS.has_feature("touchscreen")` in ui.gd `_toggle_touch_controls()`. Joystick positions: left (165,500), right (990,500), radius 100.

**Magi health bar:** Created programmatically in `_create_health_bar()`. Must use `offset_left/top/right/bottom` (not `size`/`position`) to match the 19×2px scene-based bars of guard/tenchijin/annadaeus — otherwise Godot theme minimum size overrides the programmatic size.

**Healing aura (priestess):** Shader-based pulse. Key params in priestess.tscn: `shader_parameter/pulse_speed = 3.5`, `shader_parameter/max_alpha = 0.45`, `scale = Vector2(0.9, 0.9)`.

**Mh'Orzath boss:** Event Horizon (range 500, pull_strength 1000, damage 160, cooldown 15s) — pulls targets toward boss then damages. Nihil Storm (range 600, damage 200, cooldown 20s) — pure AoE damage + camera shake.
