---
name: project-ui-systems
description: "HUD and UI scene inventory — what exists, where it lives, how it connects"
metadata: 
  node_type: memory
  type: project
  originSessionId: d6f652db-ff5d-490f-9513-2e10ddd5de2d
---

**GameLog autoload** (Scripts/game_log.gd) — signal bus. Call GameLog.log_general(text) or GameLog.log_combat(text) from anywhere. UI listens via signals. No direct references between game code and UI.

**HUD scenes** (all spawned by Player3D._spawn_hud() at runtime, added to scene root):
- `Scenes/player_frame.tscn` (Scripts/player_frame.gd) — top-left, 220×130. Finds player via group "player". Shows name, HP (red), MP (blue), STA (yellow). Updates in _process().
- `Scenes/target_frame.tscn` (Scripts/target_frame.gd) — top-left beside player frame (offset 250). Con-colored name + level + HP bar. In group "target_frame". Updated via player3d._set_target_frame(node).
- `Scenes/game_log_window.tscn` (Scripts/game_log_window.gd) — bottom-left, 470×200. Two tabs: General (non-combat) and Combat. RichTextLabel with scroll_following=true. Max 200 lines before clear.

**Con system colors** (target level - player level):
- Red: diff ≥ 5 (very dangerous)
- Orange: diff = 4
- Yellow: diff 2–3
- White: diff -1 to +1 (even)
- Blue: diff -2 to -3
- Green: diff -4 to -5
- Grey: diff ≤ -6 (trivial, no XP)

**Existing UI** (pre-dates this session):
- `Scenes/ui_bar.tscn` — bottom-right currency/HP/mana/XP labels (legacy, 2D scene)
- `Scenes/character_sheet.tscn` — full stat sheet, opened via toggle_character_sheet()
- `Scenes/backpack_ui.tscn` — inventory grid
- `Scenes/corpse_loot_window.tscn` — looting interface

**Action bar** (`Scenes/action_bar.tscn` / `Scripts/action_bar.gd`) — bottom-center, 12 slots (keys 1–9, 0, -, =). Built entirely in _ready(), no layout in .tscn. Polls `player.known_spells` and `player._spell_cooldowns` in _process(). Filled slots show gold border + spell name; cooldown slots darken with countdown timer. Spawned by _spawn_hud().

**Autoattack indicator** — flashing red ⬤ dot top-right of game_log_window panel. Driven by `GameLog.autoattack_changed(bool)` signal / `GameLog.set_autoattack(bool)`. Tween-animated fade in/out.

**Combat log format:**
- Monster hits player: `"A hooded bandit hits you for 12 damage!"` — pulls `description` from monsters.json
- Player hits monster: `"You hit/critically hit a hooded bandit with melee attack for X damage!"`
- Parry / block / dodge / riposte each have distinct messages

**Still to build:** spellbook UI. [[project-spellbook-design]]
