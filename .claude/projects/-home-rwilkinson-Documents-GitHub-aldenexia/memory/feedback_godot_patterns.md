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

When Godot crashes on startup with "Could not parse global class X from res://Scripts/foo.gd", the fix is to delete the stale Godot cache files and let the engine rebuild them:
  - .godot/uid_cache.bin
  - .godot/global_script_class_cache.cfg

**Why:** The uid_cache.bin accumulates UIDs for scripts that have since been deleted or moved. Godot tries to resolve them on startup and fails.

**How to apply:** If a script was recently deleted/moved and Godot crashes with a class parse error, check uid_cache.bin with `strings` for stale paths, then delete both cache files. Godot rebuilds them automatically on next open.
