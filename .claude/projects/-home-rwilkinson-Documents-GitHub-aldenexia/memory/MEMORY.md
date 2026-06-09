# Aldenexia Project Memory

## Architecture & Systems
- [Core Architecture](project_architecture.md) — Godot 4 3D RPG; active scripts are player3d.gd + monster3d.gd; mob.gd / player.gd are deprecated 2D versions kept for compatibility
- [Combat System](project_combat_system.md) — CombatNode is the single stat/combat source of truth; flat override pattern for monsters; resolve_attack() modifies both sides' HP
- [Save Data Schema](project_save_data.md) — canonical save fields; derived stats (hp, mana, AC) NOT saved — CombatNode recalculates at load; known_spells gates spellbook

## Game Design
- [Game Design](project_game_design.md) — EQ-style tab-target; 6-second regen tick; con system; grey mobs no XP; spellbook gating; social monsters
- [Spellbook Design](project_spellbook_design.md) — spells must be found/trained/purchased/researched before appearing in spellbook

## UI Systems
- [UI Systems](project_ui_systems.md) — GameLog autoload pattern; player_frame / target_frame / game_log_window HUD scenes; con color table; action bar + spellbook still to build

## Feedback & Patterns
- [Godot Patterns](feedback_godot_patterns.md) — always use monster3d.gd not mob.gd; GameLog not print() for combat; StyleBoxFlat colors set in _ready() not tscn
