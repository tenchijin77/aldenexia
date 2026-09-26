#!/usr/bin/env python3
# place_lumora_standins.py — puts the Lumora stand-ins in the zones (2026-09-26; the user: "i'll make some models, but
# please put some stand-ins for now"). Run after tools/make_lumora_standins.gd (which builds the buildings and writes
# Data/lumora_standins_placement.json). It:
#   - adds each building to its zone scene (under a "StandIns" node: move them freely in the editor);
#   - adds the people who work there (names from Data/lumora.json): the 14 class trainers in their halls, each selling
#     their class's scrolls (a shop "trainer_<class>" in Data/vendor_shop.json), the innkeeper, the Commander at the
#     Citadel, the temple healer, the town crier, the barkeep at Ralph's Last Round; and a notice board;
#   - writes each one's lines to Data/npcs/<id>.json (only if that file doesn't exist yet: edit them freely).
# Safe to run again: anything already placed (by node name) is left alone.
import json, os, re, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
os.chdir(ROOT)
placement = json.load(open("Data/lumora_standins_placement.json"))
items = json.load(open("Data/items.json"))
spells = json.load(open("Data/player_spells.json"))
spell_list = spells if isinstance(spells, list) else list(spells.values())
spell_by_name = {s.get("spell_name"): s for s in spell_list}

# ── who works where ────────────────────────────────────────────────────────────────────────────────────────────────
# [node id, name, title, model, building, spot, kind, class or shop]   kind: trainer / shop / talker / healer
TRAINER_LINES = {
    "blademaster": ("Steel answers steel.", "Keep your guard up and your feet under you."),
    "lightsworn": ("The Light asks for a shield arm as much as a prayer.", "Stand between the weak and the dark. That's the whole oath."),
    "aetherfist": ("Breathe. Strike. Breathe again.", "The body is the weapon. Everything else is decoration."),
    "woodstalker": ("The desert has tracks if you know how to read them.", "An arrow you don't have to fire is the best one."),
    "arcanist": ("Magic is a discipline, not a gift.", "Read first. Cast second. Apologise rarely."),
    "runecaster": ("Every rune is a promise the world must keep.", "Minds are the easiest locks to open."),
    "chaosborn": ("Order is a rumour. Power is not.", "Wild magic answers to whoever asks loudest."),
    "lightmender": ("The Dawn heals through willing hands.", "Mend the living. Grieve the dead. Know which is which."),
    "spiritweaver": ("The spirits are always talking. Few listen.", "Every totem is a conversation with the land."),
    "wildspeaker": ("The oasis breathes, if you're quiet enough to hear it.", "Root and thorn both have their seasons."),
    "voidknight": ("Fear is a tool. Learn to hold it by the handle.", "The void takes. So do we."),
    "gravecaller": ("The dead are patient teachers.", "Bones remember what flesh forgets."),
    "shadowblade": ("You didn't see me. Keep it that way.", "Coin buys lessons. Loose lips buy graves."),
    "troubadour": ("A song carries further than a sword.", "Every tavern is a stage, if you're brave."),
}
NPCS = [
    # the Sunlit Rest
    ["InnkeeperDalla", "Innkeeper Dalla Brightwell", "The Sunlit Rest", "human_female", "sunlit_rest", 0, "shop", "lumora_inn"],
    ["TrainerJorren", "Minstrel Jorren Brightsong", "Troubadour Trainer", "half_elf_male", "sunlit_rest", 1, "trainer", "troubadour"],
    # the Citadel
    ["CommanderHalvar", "Commander Halvar Sunshield", "Oasis Wardens", "human_male", "oasisheart_citadel", 0, "talker", ""],
    ["InstructorJalen", "Instructor Jalen of the First Spear", "Rookie Trainer", "human_male", "oasisheart_citadel", 1, "talker", ""],
    # the Hall of Arms (fighters)
    ["TrainerRhoran", "Captain Rhoran Steelmark", "Blademaster Trainer", "human_male", "hall_of_arms", 0, "trainer", "blademaster"],
    ["TrainerAravelle", "Sister Aravelle", "Lightsworn Trainer", "human_female", "hall_of_arms", 1, "trainer", "lightsworn"],
    ["TrainerJinhai", "Master Jinhai of the Sun Monastery", "Aetherfist Trainer", "human_male", "hall_of_arms", 2, "trainer", "aetherfist"],
    ["TrainerThalen", "Ranger Thalen Quickwind", "Woodstalker Trainer", "elf_male", "hall_of_arms", 3, "trainer", "woodstalker"],
    # the Lycaeum Annex (mages)
    ["TrainerArcturus", "Magelord Arcturus Vael", "Arcanist Trainer", "human_male", "lycaeum_annex", 0, "trainer", "arcanist"],
    ["TrainerSelvar", "Enchanter Selvar Runeveil", "Runecaster Trainer", "elf_male", "lycaeum_annex", 1, "trainer", "runecaster"],
    ["TrainerLyssandra", "Sorcerer Lyssandra Stormweave", "Chaosborn Trainer", "human_female", "lycaeum_annex", 2, "trainer", "chaosborn"],
    # the Temple of the Dawn (priests)
    ["HealerSolenne", "High Priestess Solenne", "Temple of the Dawn", "human_female", "temple_of_the_dawn", 0, "healer", ""],
    ["TrainerLiora", "Priestess Liora Dawnwell", "Lightmender Trainer", "human_female", "temple_of_the_dawn", 1, "trainer", "lightmender"],
    ["TrainerThamun", "Elder Thamun Windseer", "Spiritweaver Trainer", "human_male", "temple_of_the_dawn", 2, "trainer", "spiritweaver"],
    ["TrainerFaela", "Druidess Faela Greenroot", "Wildspeaker Trainer", "elf_female", "temple_of_the_dawn", 3, "trainer", "wildspeaker"],
    # Old Town (the dark guilds)
    ["TrainerKaelus", "Kaelus Darkbrand", "Voidknight Trainer", "human_male", "old_town_lodge", 0, "trainer", "voidknight"],
    ["TrainerValthrix", "Necromancer Valthrix the Pale", "Gravecaller Trainer", "dark_elf_male", "old_town_lodge", 1, "trainer", "gravecaller"],
    # the Cisterns (the thieves' den)
    ["TrainerKessira", "Shade Operative Kessira", "Shadowblade Trainer", "dark_elf_female", "cisterns_entrance", 0, "trainer", "shadowblade"],
    # Ralph's Last Round (the Outskirts gate)
    ["BarkeepWenna", "Wenna Tuller", "Ralph's Last Round", "human_female", "ralphs_last_round", 0, "shop", "outskirts_tavern"],
]
TALKER_LINES = {
    "CommanderHalvar": {
        "greeting": ["The Wardens hold this city. Keep the peace inside the walls and you'll have no quarrel with us.",
                     "Dustwalkers on the roads again. If you've a blade and a spine, the Citadel could use both."],
        "ambient": ["Double the watch on the south gate tonight.", "The oasis is the heart of Lumora. The Citadel is its fist."],
    },
    "InstructorJalen": {
        "greeting": ["New to the sands? Learn to fight at the Hall of Arms, learn to live in the Outskirts.",
                     "Your trainer's in the guild hall for your calling. The Hall of Arms, the Lycaeum, the Temple, or Old Town, if that's your sort."],
        "ambient": ["Feet apart. Shield up. Again.", "The desert doesn't grade on effort."],
    },
    "TownCrier": {
        "greeting": ["Hear ye! News from the gate, the bazaar and the Citadel!"],
        "ambient": ["Hear ye! The Sunlit Rest has rooms and a hot meal for weary travellers!",
                    "Hear ye! Dustwalker raids on the south road: travel in company!",
                    "Hear ye! Fines are paid at the courthouse, not argued in the street!",
                    "Hear ye! The Temple of the Dawn tends the sick and the wounded!",
                    "Hear ye! Caravans from Kordova expected at the Caravanserai before the dark moon!"],
        "ambient_minutes": [1, 3],
    },
}


def config_for(npc):
    nid, name, title, model, building, spot, kind, what = npc
    if kind == "trainer":
        a, b = TRAINER_LINES[what]
        return {"greeting": [a, "Here to learn? I keep what a %s needs, when you're ready for it." % what.capitalize()],
                "shop_intro": ["Here's what I can teach you."], "ambient": [a, b], "secret": [],
                "topics": [{"id": "hail", "keywords": ["hail", "hello", "greetings", "hey"], "then": {"hail": True}},
                           {"id": "train", "keywords": ["train", "learn", "scroll", "scrolls", "spell", "spells", "teach"],
                            "lines": ["Let's see what you're ready for."], "then": {"hail": True}}]}
    if kind == "healer":
        return {"greeting": ["The Dawn's light for the sick and the hurt. Come, sit.", "Wounded? Poisoned? The temple can help. The dead, it cannot."],
                "shop_intro": [], "ambient": ["The temple mends what it can.", "Aurethiel keeps no one waiting who asks in earnest."], "secret": [],
                "topics": [{"id": "hail", "keywords": ["hail", "hello", "greetings", "hey"], "then": {"hail": True}},
                           {"id": "heal", "keywords": ["heal", "healing", "cure", "poison", "disease", "curse", "sick"],
                            "lines": ["Of course. Be still."], "then": {"hail": True}}]}
    if nid == "InnkeeperDalla":
        return {"greeting": ["Welcome to the Sunlit Rest! Hot food, cold water, soft beds.", "Sit anywhere. The stew's fresh."],
                "shop_intro": ["Here's the board."], "ambient": ["Mind the step, the new boards squeak.", "Jorren plays most nights, if you like a song with supper."],
                "secret": ["Some nights a woman in a traveller's cloak sits by the window and never orders. The coins on the table are always old."],
                "topics": [{"id": "hail", "keywords": ["hail", "hello", "greetings", "hey"], "then": {"hail": True}},
                           {"id": "food", "keywords": ["food", "drink", "room", "stew", "eat"], "lines": ["Right away."], "then": {"hail": True}}]}
    if nid == "BarkeepWenna":
        return {"greeting": ["Welcome to Ralph's Last Round. Mind the tankard on the end of the bar: nobody touches Ralph's.",
                             "What'll it be? Water's cheap, the tea's better."],
                "shop_intro": ["Here's what we pour."], "ambient": ["Ralph always said the last round's on the house. Ralph's not paying anymore.",
                                                                    "Bards play here when they pass through. Best sound in the Outskirts."],
                "secret": ["The tankard? Ralph Tuller poured it the night he rode out to the south road. We leave it where he left it."],
                "topics": [{"id": "hail", "keywords": ["hail", "hello", "greetings", "hey"], "then": {"hail": True}},
                           {"id": "ralph", "keywords": ["ralph", "tankard"], "lines": ["My husband. He rode out one night and didn't come back. The tankard waits for him."]},
                           {"id": "drink", "keywords": ["drink", "food", "tea", "water"], "lines": ["Coming up."], "then": {"hail": True}}]}
    t = TALKER_LINES[nid]
    return {"greeting": t["greeting"], "shop_intro": [], "ambient": t["ambient"], "secret": [],
            "ambient_minutes": t.get("ambient_minutes", [5, 9]),
            "topics": [{"id": "hail", "keywords": ["hail", "hello", "greetings", "hey"], "then": {"hail": True}}]}


# ── shops ──
def scroll_level(item_id, cls):
    sp = spell_by_name.get(items[item_id].get("teaches_spell"), {})
    return int(sp.get("class_level_requirements", {}).get(cls.capitalize(), sp.get("level", 99)))


shops = json.load(open("Data/vendor_shop.json"))
for npc in NPCS:
    if npc[6] != "trainer":
        continue
    cls = npc[7]
    stock = [k for k, it in items.items() if isinstance(it, dict) and it.get("type") == "scroll" and it.get("teaches_spell")
             and cls in it.get("class", [])]
    stock.sort(key=lambda k: (scroll_level(k, cls), k))
    shops["trainer_" + cls] = {"_comment": "%s's scrolls, taught at their guild hall in Lumora (tools/place_lumora_standins.py; the scribes sell them too)." % npc[1],
                               "vendor_name": npc[1], "buy_price_multiplier": 1.0, "sell_price_multiplier": 0.5, "stock": stock}
shops["lumora_inn"] = {"_comment": "The Sunlit Rest's board (tools/place_lumora_standins.py). Basics only: cooks sell the good food.",
                       "vendor_name": "Innkeeper Dalla Brightwell", "buy_price_multiplier": 1.0, "sell_price_multiplier": 0.5,
                       "stock": ["trail_rations", "iron_rations", "spring_water", "water_flask", "desert_tea", "cooked_meat"]}
shops["outskirts_tavern"] = {"_comment": "Ralph's Last Round at the Outskirts gate (tools/place_lumora_standins.py).",
                             "vendor_name": "Wenna Tuller", "buy_price_multiplier": 1.0, "sell_price_multiplier": 0.5,
                             "stock": ["trail_rations", "spring_water", "water_flask", "desert_tea"]}
open("Data/vendor_shop.json", "w").write(json.dumps(shops, indent=2, ensure_ascii=False) + "\n")

# ── lines ──
os.makedirs("Data/npcs", exist_ok=True)
for npc in NPCS + [["TownCrier", "", "", "", "", 0, "talker", ""]]:
    path = "Data/npcs/%s.json" % npc[0].lower()
    if os.path.exists(path):
        continue
    cfg = {"_comment": "What %s says (talking_vendor_npc.gd shape: greeting, shop_intro, ambient, secret (night), topics). Written by tools/place_lumora_standins.py once; edit freely." % (npc[1] or npc[0])}
    cfg["ambient_minutes"] = [5, 9]
    cfg["ambient_secret_chance_at_night"] = 0.2
    cfg.update(config_for(npc))
    open(path, "w").write(json.dumps(cfg, indent=1, ensure_ascii=False) + "\n")


# ── the scenes ──
def add_ext(s, typ, path, rid):
    if 'id="%s"' % rid in s:
        return s
    last = [m.end() for m in re.finditer(r'^\[ext_resource [^\n]*\]\n', s, re.M)][-1]
    s = s[:last] + '[ext_resource type="%s" path="%s" id="%s"]\n' % (typ, path, rid) + s[last:]
    m = re.search(r'load_steps=(\d+)', s)
    if m:
        s = s.replace(m.group(0), "load_steps=%d" % (int(m.group(1)) + 1), 1)
    return s


SCRIPTS = {"trainer": None, "shop": None, "talker": ("res://Scripts/town_talker_npc.gd", "town_talker_scr"),
           "healer": ("res://Scripts/temple_healer_npc.gd", "temple_healer_scr")}
for zone, scene_path in [("lumora", "Scenes/zones/lumora.tscn"), ("lumora_outskirts", "Scenes/lumora_outskirts3d.tscn")]:
    s = open(scene_path).read()
    added = []
    if '[node name="StandIns"' not in s:
        s += '\n[node name="StandIns" type="Node3D" parent="."]\n'
    for bid, b in placement.items():
        if b["zone"] != zone:
            continue
        rid = "standin_%s" % bid
        s = add_ext(s, "PackedScene", b["scene"], rid)
        node = bid.title().replace("_", "")
        if '[node name="%s" parent="StandIns"' % node not in s:
            s += '\n[node name="%s" parent="StandIns" instance=ExtResource("%s")]\ntransform = %s\n' % (node, rid, b["transform"])
            added.append(node)
    for npc in NPCS:
        nid, name, title, model, building, spot, kind, what = npc
        if placement[building]["zone"] != zone or '[node name="%s"' % nid in s:
            continue
        script_line = ""
        if SCRIPTS[kind]:
            s = add_ext(s, "Script", SCRIPTS[kind][0], SCRIPTS[kind][1])
            script_line = 'script = ExtResource("%s")\n' % SCRIPTS[kind][1]
        shop = "trainer_" + what if kind == "trainer" else (what if kind == "shop" else "")
        s += ('\n[node name="%s" parent="NPCs" instance=ExtResource("talking_vendor_scn")]\ntransform = %s\n%sconfig_path = "res://Data/npcs/%s.json"\n'
              'model_key = "%s"\ntitle = "%s"\nnpc_name = "%s"\n') % (nid, placement[building]["spots"][spot], script_line, nid.lower(), model, title, name)
        if shop:
            s += 'shop_id = "%s"\n' % shop
        added.append(nid)
    if zone == "lumora":
        # the town crier by the Paladin's Vigil, the notice board in Citadel Plaza, the Magistrate at the courthouse door
        if '[node name="TownCrier"' not in s:
            s = add_ext(s, "Script", "res://Scripts/town_talker_npc.gd", "town_talker_scr")
            s += ('\n[node name="TownCrier" parent="NPCs" instance=ExtResource("talking_vendor_scn")]\n'
                  'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 5, 0, 262)\nscript = ExtResource("town_talker_scr")\n'
                  'config_path = "res://Data/npcs/towncrier.json"\nmodel_key = "human_male"\ntitle = "Town Crier"\nnpc_name = "Crier Pell"\n')
            added.append("TownCrier")
        if '[node name="NoticeBoard"' not in s:
            s = add_ext(s, "Script", "res://Scripts/world_note.gd", "world_note_scr")
            s += ('\n[node name="NoticeBoard" type="Node3D" parent="StandIns"]\ntransform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 8, 1.2, 292)\n'
                  'script = ExtResource("world_note_scr")\ntitle = "Notice Board"\n'
                  'note_text = "NOTICES, by order of the Oasis Wardens:\\n- Dustwalker raiders on the south road. Travel in company.\\n'
                  '- Fines for crimes within the walls are paid at the courthouse (Magistrate Corvane).\\n'
                  '- The Temple of the Dawn heals the sick and wounded. It does not raise the dead.\\n'
                  '- Guild halls: the Hall of Arms, the Lycaeum Annex, the Temple of the Dawn. Others know where to find theirs.\\n'
                  '- Rooms and meals at the Sunlit Rest."\nlabel_text = "Notice Board"\nlabel_height = 1.0\n')
            added.append("NoticeBoard")
        court = placement["courthouse"]["spots"][0]
        s = re.sub(r'(\[node name="Magistrate" parent="NPCs"[^\n]*\]\ntransform = )Transform3D\([^)]*\)', lambda m: m.group(1) + court, s)
    open(scene_path, "w").write(s)
    print(zone, "added:", ", ".join(added) if added else "nothing new")
