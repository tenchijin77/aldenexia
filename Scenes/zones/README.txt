ZONES — how a zone scene is put together (2026-09-24)

zone_template.tscn   everything every zone needs: the root (multiplayer_player_spawner.gd: zone_id, zone_name,
					 spawn_position), Terrain3D (shares Lumora's texture list, zones/lumora_terrain/terrain_assets.res),
                     sun + sky + DayNightCycle + WeatherManager + wind, the pre-placed player (single-player), the
                     monster spawner, multiplayer spawners, GM relay, world items, server notices, crafting/gathering
                     spawner, NavigationRegion3D, and empty NPCs / Structures / Markers / ZoneLines folders.
<zone_id>.tscn       INHERITS the template (Scene > New Inherited Scene), so a change to the template reaches every
					 zone. Only what is the zone's own is set here: zone_id, zone_name, Terrain3D data_directory,
					 the navmesh file, and its own nodes (NPCs, buildings, markers, zone lines).

Zones so far: dustwind_plateaus.tscn, ashfall_dunes.tscn — each a flat 1 km square of Terrain3D (16 regions of 256 m,
centred on 0,0, height 0) in zones/<zone_id>_terrain/, ready to sculpt, with a baked navmesh.

The zone's data files are found by its zone_id (Scripts/zone_info.gd):
  Data/<zone_id>_spawns.json             monsters (none yet = no monsters; copy lumora_outskirts_spawns.json's layout)
  Data/crafting_placements.json[zone_id] stations and gathering nodes
  Data/ley_lines.json[zone_id]           travel sites ("class": Arcanist/Wildspeaker/Chaosborn) and "zone_entrance"
  Data/perception_spots.json[zone_id], Data/world_objects.json[zone_id]
  Scripts/global_background_music.gd SCENE_MUSIC   the zone's music

A NEW ZONE
 1. Scene > New Inherited Scene > Scenes/zones/zone_template.tscn; save as Scenes/zones/<zone_id>.tscn.
 2. On the root: zone_id, zone_name, spawn_position. On Terrain3D: data_directory = res://zones/<zone_id>_terrain
	(make the folder; add regions with Terrain3D's Region tool, or copy what tools made for Dustwind).
 3. NavigationRegion3D: a new NavigationMesh saved as Data/<zone_id>_navmesh.tres (copy dustwind_plateaus_navmesh.tres's
    settings and widen filter_baking_aabb to the terrain), then bake:
      godot --headless --path . --script res://tools/bake_lumora_navmesh.gd -- res://Scenes/zones/<zone_id>.tscn
    Re-bake whenever the terrain changes.
 4. Run tools/run_tests.sh — test_zones.gd checks every scene in this folder (id, terrain, navmesh baked, no stray mobs).
 5. Try its server side alone: godot --headless --path . -- --server --port=8990 --name=zztest --zone=<zone_id>
	("World check" line). Players can't walk into it until zoning is built.

NPCS
Drag an NPC scene (Scenes/talking_vendor.tscn for a talking shopkeeper, guard_npc.tscn, ...) into the zone's NPCs folder and
set it up in the Inspector (Npc Name, Title, Model Key such as "dwarf_male", Config Path, Shop Id). Every NPC shows its
real model and name in the editor (npc_editor_preview.gd), so move it wherever you like. Height needn't be exact:
vendors stand on the ground under them when the game starts (keep them within a few metres above it), guards fall to it.

AN UNDERGROUND ZONE (a dungeon; the first is warden_crypts.tscn, 2026-09-26)
Same template, but: DayNightCycle Outdoors off (no sun/sky/rain, fixed dim ambient, no Elf outdoor speed), Terrain3D
hidden with collision off (its flat background plane would z-fight the floor), DirectionalLight3D hidden, AmbientWind
autoplay off, a dark Environment. The rooms: a Node3D under Structures with Scripts/dungeon_builder.gd and a text map
(Data/<zone_id>_layout.txt: # rock, . floor, T torch, S stairs up, C sarcophagus; 3 m cells, rows run south). Edit the
text, reopen the scene, re-bake the navmesh (keep filter_baking_aabb below the ceiling). test_zones.gd checks it has no
terrain and a Structures/Dungeon instead.
