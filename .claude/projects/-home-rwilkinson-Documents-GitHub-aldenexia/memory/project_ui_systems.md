---
name: project-ui-systems
description: "HUD and UI scene inventory — what exists, where it lives, how it connects"
metadata: 
  node_type: memory
  type: project
  originSessionId: d6f652db-ff5d-490f-9513-2e10ddd5de2d
---

**GameLog autoload** (Scripts/game_log.gd) — signal bus. Call GameLog.log_general(text) or GameLog.log_combat(text) from anywhere. UI listens via signals. No direct references between game code and UI.

**HUD scenes** (all spawned by Player3D._spawn_hud() at runtime, added to scene root, tagged with group "game_hud"):
- `Scenes/player_frame.tscn` (Scripts/player_frame.gd) — top-left, 220×130. Finds player via group "player". Shows name, HP (red), MP (blue), STA (yellow). Updates in _process().
- `Scenes/target_frame.tscn` (Scripts/target_frame.gd) — top-left beside player frame (offset 250). Con-colored name + level + HP bar. In group "target_frame". Updated via player3d._set_target_frame(node).
- `Scenes/game_log_window.tscn` (Scripts/game_log_window.gd) — bottom-left, 470×200. Two tabs: General (non-combat) and Combat. RichTextLabel with scroll_following=true. Max 200 lines before clear.

**HUD cleanup on scene exit** — all HUD nodes are tagged with group `"game_hud"` when spawned. `pause_menu._on_save_and_exit()` calls `get_tree().get_nodes_in_group("game_hud")` and queue_frees each before changing scene. Required because root-level nodes survive `change_scene_to_file()` — only the current scene node is freed.

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

**Action bar** (`Scenes/action_bar.tscn` / `Scripts/action_bar.gd`) — bottom-center, 12 slots (keys 1–9, 0, -, =). Built entirely in _ready(), no layout in .tscn. Polls `player.known_spells` and `player._spell_cooldowns` in _process(). Filled slots show gold border + spell name; cooldown slots darken with countdown timer. Spawned by _spawn_hud(). **Draggable** — click and hold anywhere on bar to reposition. Position saved to `ui_positions["action_bar"]` on drag release.

**Autoattack indicator** — flashing red ⬤ dot top-right of game_log_window panel. Driven by `GameLog.autoattack_changed(bool)` signal / `GameLog.set_autoattack(bool)`. Tween-animated fade in/out.

**Chat window** (`Scenes/game_log_window.tscn`) — has a 22px "Chat" drag bar at the top (added in code, pushes VBox down). Drag bar has MOUSE_FILTER_STOP so events don't reach the RichTextLabel. **Draggable**. Position saved to `ui_positions["chat"]` on drag release.

**Drag bar pattern** — RichTextLabel and VBoxContainer consume all mouse events before they reach their parent Panel. Solution: add a thin Label with `mouse_filter = MOUSE_FILTER_STOP` above the VBox and wire its `gui_input`. Also set HBoxContainer to `MOUSE_FILTER_PASS` when the panel itself must receive events bubbled from slot children.

**Right-click to equip** (`slot_button.gd`) — right-clicking an item with a valid equip slot calls `Inventory.equip_item()` directly. Non-equippable items still show the inspect popup.

**Window position persistence** — `Global.player_data["ui_positions"]` stores offset arrays per window key ("chat", "action_bar"). Saved to disk via `Global.save_player_data_to_file()` on drag release. Loaded in each window's `_ready()`.

**Pause menu** (`Scenes/pause_menu.tscn` / `Scripts/pause_menu.gd`) — Escape key opens a layer-20 modal. Three buttons: Save Game (writes file, logs confirmation, closes), Save and Exit (writes file, scene-changes to main_menu.tscn), Resume (closes). Escape also dismisses. Player3D owns `_pause_menu_instance` and `_toggle_pause_menu()`. Mouse released to VISIBLE when menu opens.

**Equipment → CombatNode live sync** — `Inventory.equipment_changed` signal connected to `player3d._on_equipment_changed()` in _ready(). Calls `_apply_equipment_from_inventory()` which reads `Inventory.equipped` (live paperdoll) and updates `combat_node.weapon_damage` + `gear_ac`. Also triggers `Global.save_player_data_to_file()` so equipment persists immediately.

**Save function** — `Global.save_player_data_to_file()` writes `player_data` dict to `user://saves/{name}_character_stats.json`. Called on equip, on window drag release, and from pause menu.

**Combat log format:**
- Monster hits player: `"A hooded bandit hits you for 12 damage!"` — pulls `description` from monsters.json
- Player hits monster: `"You hit/critically hit a hooded bandit with melee attack for X damage!"`
- Parry / block / dodge / riposte each have distinct messages

**Still to build:** spellbook UI. [[project-spellbook-design]]
