---
name: feedback-godot-patterns
description: "Confirmed patterns and anti-patterns for this project's GDScript / Godot 4 code"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: d6f652db-ff5d-490f-9513-2e10ddd5de2d
---

Always check which script is the ACTIVE base class before making changes. mob.gd is deprecated; monster3d.gd (class_name Monster) is the real monster base. player3d.gd is the real player.

**Why:** Early in development, 2D versions (mob.gd, player.gd) were the active ones. Game moved to 3D. Spending time on mob.gd changes wasted effort.

**How to apply:** When asked to change monster behavior, default to monster3d.gd. When asked to change player behavior, default to player3d.gd. Only touch mob.gd / player.gd if explicitly asked about 2D scenes.

---

Use the GameLog autoload for any in-game message that should appear in the UI log, not print(). GameLog.log_combat() for combat events, GameLog.log_general() for everything else.

**Why:** print() only goes to console. Players need to see combat results in the UI.

**How to apply:** Any string that was previously a print() in combat code should be GameLog.log_combat(). System/world messages go to GameLog.log_general().

---

ProgressBar fill colors must be set via add_theme_stylebox_override("fill", StyleBoxFlat) in _ready() — not in tscn files (too complex to write by hand).

**Why:** Writing inline StyleBoxFlat resources in tscn format is error-prone and verbose.

---

Root-level nodes (added via `get_tree().root.add_child()`) survive `SceneTree.change_scene_to_file()` — only the current scene is freed. Always tag root-level HUD/overlay nodes with a group (e.g. "game_hud") and explicitly queue_free them before changing scene.

**Why:** The pause menu overlay and all HUD windows persisted into the main menu because they were root children, not scene children.

**How to apply:** Any CanvasLayer or UI node added directly to root should be in a named group. Scene exit code must free that group before `change_scene_to_file()`.

---

After an `await` in a node method (e.g. a despawn timer), always guard with `if not is_inside_tree(): return` before taking any action. If the node was freed by another path while the timer was running, the continuation will still fire.

**Why:** monster3d.die() had a 60s auto-despawn await. When the player fully looted the monster, `_on_fully_looted()` called queue_free() first. The 60s timer then resumed on a freed node.

**How to apply:** Every `await get_tree().create_timer(...)` in a node should be followed by `if not is_inside_tree(): return`.

---

When a popup window needs to mutate the caller's data (e.g. a loot window depleting a monster's loot array), pass the array by reference — do NOT call `.duplicate()`. Add a signal (e.g. `all_looted`) that fires when the array is empty, and let the caller connect to it for cleanup/despawn.

**Why:** corpse_loot_window called `loot.duplicate(true)`, so the monster's pending_loot was never depleted. Monster stayed lootable forever.

---

When Godot crashes on startup with "Could not parse global class X from res://Scripts/foo.gd", the fix is to delete the stale Godot cache files and let the engine rebuild them:
  - .godot/uid_cache.bin
  - .godot/global_script_class_cache.cfg

**Why:** The uid_cache.bin accumulates UIDs for scripts that have since been deleted or moved. Godot tries to resolve them on startup and fails.

**How to apply:** If a script was recently deleted/moved and Godot crashes with a class parse error, check uid_cache.bin with `strings` for stale paths, then delete both cache files. Godot rebuilds them automatically on next open.
