---
name: project-spellbook-design
description: Spellbook UI design rules — spells must be learned before appearing
metadata: 
  node_type: memory
  type: project
  originSessionId: d6f652db-ff5d-490f-9513-2e10ddd5de2d
---

Spellbook shows only spells the player has learned — not all spells from player_spells.json.

Spells are acquired via: finding (loot/world), training (trainer NPC), purchasing (vendor), or researching.

**Why:** Player progression should gate spell access; showing all spells upfront removes discovery and economy.

**How to apply:** player_spells.json is the master definition list. A separate per-character "known_spells" array (saved to character data) tracks what the player has learned. Spellbook UI filters against known_spells, not the full JSON.
