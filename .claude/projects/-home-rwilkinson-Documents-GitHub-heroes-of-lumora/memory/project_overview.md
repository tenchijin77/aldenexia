---
name: project-overview
description: "Heroes of Lumora — what the game is, its current state, and key design decisions"
metadata: 
  node_type: memory
  type: project
  originSessionId: 7ab18f2e-6f8a-4e69-a254-4eedf47e49d1
---

Heroes of Lumora is a Godot 4 top-down wave survival game by solo developer Ross Wilkinson. It is his first game and is feature-complete / in polish phase. The world of Lumora is a prequel setting to a planned larger project called "Aldenexia: Lightfall."

**Genre / Loop:** Defend a village from monster waves. Save 50 villagers to trigger the final boss (Mh'Orzath). Buy upgrades (guards, magi, health, damage, speed) from a shop between waves.

**Heroes / Characters:**
- Player (Tenchijin) — the character you control
- Annadaeus — named companion, follows player
- Guard — buyable ranged ally (NodePool-based, multiple)
- Magi — buyable magic ally (NodePool-based, multiple)
- Priestess (healer) — healing aura NPC

**Enemies:** Goblin, Skeleton, Troll, Wraith, Beholder, Lich, Hezrou, Ogre, Ghost, Balrog, Mh'Orzath (final boss)

**Key scenes:** main.tscn (gameplay), game_over.tscn (high score entry + wall), game_over2.tscn (no high score), victory_scene.tscn (ending), main_menu.tscn, shop

**Current branch:** test-build

**Why:** Shipping as a complete game; polish and bug-fix phase. Mobile export is being worked on.
