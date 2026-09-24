#!/usr/bin/env python3
# make_manual.py — builds PLAYER_MANUAL.html (project root) from tools/manual_template.html and the game's own data, so
# the manual's spell lists, recipes, monsters, races and levels always match the build.
#
#   python3 tools/make_manual.py
#
# The words live in tools/manual_template.html: edit them there. Everything in a {{MARKER}} is generated here from
# Data/*.json, Scripts/character_creation.gd (starting spells) and TESTER_GUIDE.html (the full controls list, so it is
# kept in one place). Re-run after changing any of them.

import html
import json
import os
import re
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "Data")


def load(name):
    with open(os.path.join(DATA, name)) as f:
        text = f.read()
    return json.loads(re.sub(r",(\s*[}\]])", r"\1", text))  # a few hand-edited files have trailing commas


def e(text):
    return html.escape(str(text), quote=True)


def nice(ident):
    return " ".join(w.capitalize() for w in str(ident).replace("_", " ").split())


ITEMS = load("items.json")
SPELLS = load("player_spells.json")
OPTIONS = load("character_options.json")
RACIAL = load("racial_stats.json")
RESTRICT = load("class_restrictions.json")
STANCES = load("class_stances.json")
XP = load("xp_table.json")
VENDORS = load("vendor_shop.json")
RECIPES = load("tradeskill_recipes.json")["recipes"]
NODES = load("gathering_nodes.json")["nodes"]
LANGS = load("languages.json")
SKILLS = load("player_skills.json")
EFFECTS = load("skill_effects.json")["effects"]
BALANCE = load("combat_balance.json")
MONSTERS = load("monsters.json")
SPAWNS = load("lumora_outskirts_spawns.json")["spawns"]
QUESTS = load("quests.json")
BUILD = load("build_info.json")

MAX_LEVEL = int(XP.get("max_level", 20))
SKILL_CAP = int(BALANCE.get("skill_cap_per_level", 4)) if isinstance(BALANCE, dict) else 4


def item_name(item_id):
    d = ITEMS.get(item_id)
    return d["name"] if isinstance(d, dict) else nice(item_id)


# Spell display names: Player3D.SPELL_DISPLAY_NAMES, else the id capitalised (Player3D.spell_display_name()).
def _display_names():
    src = open(os.path.join(ROOT, "Scripts", "player3d.gd")).read()
    block = re.search(r"const SPELL_DISPLAY_NAMES := \{(.*?)\n\}", src, re.S).group(1)
    return dict(re.findall(r'"(\w+)":\s*"([^"]+)"', block))


DISPLAY = _display_names()


def spell_name(sid):
    return DISPLAY.get(sid, " ".join(w.capitalize() for w in sid.split("_")))


def _starting_spells():
    src = open(os.path.join(ROOT, "Scripts", "character_creation.gd")).read()
    block = re.search(r"const STARTING_SPELLS := \{(.*?)\n\}", src, re.S).group(1)
    return {c: re.findall(r'"(\w+)"', rest) for c, rest in re.findall(r'"(\w+)":\s*\[([^\]]*)\]', block)}


STARTING = _starting_spells()

# Who sells what: item id -> [vendor names]
SOLD_BY = defaultdict(list)
for shop in VENDORS.values():
    if isinstance(shop, dict):
        for item_id in shop.get("stock", []):
            if isinstance(item_id, str):
                SOLD_BY[item_id].append(shop["vendor_name"])
SPELL_SCROLL = {d["teaches_spell"]: i for i, d in ITEMS.items() if isinstance(d, dict) and d.get("teaches_spell")}


def short_vendor(name):
    return {"Archivist Ilsabet Thornmere": "Ilsabet", "Xalvyr Tenn": "Xalvyr", "Aldric the Provisioner": "Aldric",
            "Lira Solarpetal": "Lira", "Tobble Cogfarrow": "Tobble", "Sahren of the Deep Wells": "Sahren",
            "Harbour Master Tobias Sandcrest": "Tobias"}.get(name, name)


def price(item_id):
    d = ITEMS.get(item_id, {})
    return f"{d.get('value', 0)} {({'copper': 'cp', 'silver': 'sp', 'gold': 'gp'}).get(d.get('currency_type', 'copper'), 'cp')}"


def table(headers, rows, num_cols=()):
    head = "".join(f'<th{" class=\"num\"" if i in num_cols else ""}>{h}</th>' for i, h in enumerate(headers))
    return f'<div class="tablewrap"><table class="data"><thead><tr>{head}</tr></thead><tbody>{"".join(rows)}</tbody></table></div>'


# ── Languages ──
def languages():
    names = {k: v["name"] if isinstance(v, dict) else v for k, v in LANGS["languages"].items()}
    primers = defaultdict(list)
    for i, d in ITEMS.items():
        if isinstance(d, dict) and d.get("teaches_language"):
            primers[d["teaches_language"]] += [short_vendor(v) for v in SOLD_BY.get(i, [])]
    speakers = defaultdict(list)
    race_names = {k: v["name"] for k, v in OPTIONS["races"].items()}
    for race, start in LANGS["race_start"].items():
        for lang, pts in start.items():
            speakers[lang].append(f"{race_names.get(race, nice(race))} {pts}" if pts < 100 else race_names.get(race, nice(race)))
    rows = []
    for lid, name in names.items():
        spoken = ", ".join(speakers.get(lid, [])) or '<span class="muted">no race starts with it</span>'
        sold = ", ".join(sorted(set(primers.get(lid, [])))) or '<span class="muted">—</span>'
        rows.append(f'<tr><td class="name">{e(name)}</td><td>{spoken}</td><td>{sold}</td></tr>')
    return ('<p class="muted">Races that start with a language know it fully unless a number (out of 100) is shown.</p>'
            + table(["Language", "Starting speakers", "Primer sold by"], rows))


def xp_table():
    levels = [(int(k), v) for k, v in XP.items() if k.isdigit()]
    rows, prev = [], 0
    for lvl, total in sorted(levels):
        rows.append(f'<tr><td class="lvl">{lvl}</td><td class="num">{total:,}</td><td class="num">{total - prev:,}</td></tr>')
        prev = total
    half = (len(rows) + 1) // 2
    return ('<div class="facts">' + table(["Level", "Total XP", "From previous"], rows[:half], (1, 2))
            + table(["Level", "Total XP", "From previous"], rows[half:], (1, 2)) + "</div>")


# ── Races ──
# Traits the game does not use yet (mirrors Player3D.RACIAL_TRAITS_NOT_YET_USED); every other trait is live.
TRAITS_NOT_YET = {"research_skill_bonus", "intimidation_skill_bonus", "swamp_movement_speed_bonus", "swamp_survival_skill_bonus",
                  "swamp_perception_skill_bonus", "fear_resistance_save_bonus", "immune_to_knockback"}
SKILL_NAMES = {"mining_skill_bonus": "Prospecting", "engineering_skill_bonus": "Tinkering", "foraging_skill_bonus": "Forage",
               "hide_skill_bonus": "Stealth (hide)", "sneak_skill_bonus": "Stealth (sneak)", "pick_lock_skill_bonus": "Lockpicking"}
STAT_ORDER = [("strength", "STR"), ("constitution", "CON"), ("dexterity", "DEX"), ("intelligence", "INT"),
              ("wisdom", "WIS"), ("charisma", "CHA"), ("luck", "LCK")]


def trait_text(key, val):
    if key == "dark_sight":
        return "Dark sight: dim light at night counts as brighter"
    if key == "improved_dark_sight":
        return "Improved dark sight: dim light at night counts as bright light"
    if key == "torch_burn_bonus":
        return f"Torches burn {int(val * 100)}% longer"
    if key == "amphibious":
        return "Breathes underwater"
    if key in SKILL_NAMES:
        return f"{SKILL_NAMES[key]} +{val} (counts when used)"
    if key.endswith("_skill_bonus"):
        return f"{nice(key[:-len('_skill_bonus')])} +{val} (counts when used)"
    if key == "experience_gain_all_skills":
        return f"Skills improve {int(val * 100)}% faster"
    if key == "combat_skill_experience_gain_bonus":
        return f"Combat skills improve {int(val * 100)}% faster"
    if key in ("faction_bonus_all", "faction_standing_bonus_all"):
        return f"+{val} standing with every faction"
    if key == "movement_speed_outdoors_bonus":
        return f"{int(val * 100)}% faster outdoors"
    if key == "in_combat_health_regeneration":
        return "Regenerates health during combat"
    if key == "unarmed_bite_damage":
        return "Bites for an extra 1d6 when fighting bare-handed"
    if key == "negative_effect_resistance_chance":
        return f"{int(val * 100)}% chance to shrug off a harmful effect"
    label = nice(key).replace("Bonus", "").strip()
    if isinstance(val, bool):
        return label
    if isinstance(val, float) and val < 1:
        return f"{label} +{round(val * 100, 1):g}%"
    if isinstance(val, dict):
        return f"{label} {val.get('dice', '')}"
    return f"{label} +{val}"


# What the drawback notes above do in numbers (Player3D.apply_racial_traits() / apply_racial_modifiers()).
PENALTY_NUMBERS = {
    "elf": ["In numbers: 10% less health."],
    "dwarf": ["In numbers: 10% slower, 10% less mana."],
    "gnome": ["In numbers: 15% less melee damage, −5 standing with every faction."],
    "halfling": ["In numbers: 10% less health, 5% less melee damage."],
    "half_elf": ["In numbers: skills improve 5% slower."],
    "ogre": ["In numbers: 15% slower, −10 dodge, 20% less mana."],
    "troll": ["In numbers: −10 dodge and parry, −10 standing with every faction."],
    "dark_elf": ["In numbers: health and mana regenerate half as fast by day, −10 standing with every faction."],
    "half_orc": ["In numbers: 10% less mana, 5% less spell damage, −5 standing with every faction."],
    "lizardkin": ["In numbers: −5 accuracy at night; cold resistance −10."],
}


def racial_key(race_id):
    return {"half_elf": "half-elf", "half_orc": "half-orc", "dark_elf": "dark_elf"}.get(race_id, race_id)


def races():
    out = []
    lang_names = {k: v["name"] if isinstance(v, dict) else v for k, v in LANGS["languages"].items()}
    for rid, r in OPTIONS["races"].items():
        stats = RACIAL.get(racial_key(rid)) or RACIAL.get(rid) or RACIAL.get(rid.replace("_", "-")) or {}
        base = stats.get("base_stats", {})
        stat_html = "".join(f'<div><span>{ab}</span><b>{base.get(k, "–")}</b></div>' for k, ab in STAT_ORDER)
        res = stats.get("resistances", {})
        res_txt = ", ".join(f"{nice(k)} {'+' if v > 0 else ''}{v}" for k, v in res.items() if v) or "none"
        classes = [c for c, allowed in RESTRICT.items() if r["name"] in allowed]
        langs = ", ".join(f"{lang_names.get(l, nice(l))}{'' if p >= 100 else f' ({p})'}"
                          for l, p in LANGS["race_start"].get(rid, {}).items())
        traits = r.get("traits", {})
        live = [trait_text(k, v) for k, v in traits.items() if k not in TRAITS_NOT_YET]
        planned = [trait_text(k, v) for k, v in traits.items() if k in TRAITS_NOT_YET]
        pen = r.get("penalties", {}).get("notes", []) + PENALTY_NUMBERS.get(rid, [])
        out.append(f'''<details class="panel" id="race-{rid}">
  <summary><span class="title">{e(r["name"])}</span><span class="sub">{e(nice(r.get("alignment", "")))} · {len(classes)} classes</span></summary>
  <div class="body">
    <p>{e(r["description"])}</p>
    <p class="muted">{e(r.get("lore", ""))}</p>
    <div class="stats" aria-label="Starting statistics">{stat_html}</div>
    <div class="statline"><span><b>Resistances</b> {e(res_txt)}</span><span><b>Languages</b> {e(langs)}</span></div>
    <div class="statline"><span><b>Classes</b> {e(", ".join(classes))}</span></div>
    <div class="facts">
      <div><h4>Traits</h4><ul class="plain">{"".join(f"<li>{e(t)}</li>" for t in live) or '<li class="muted">None in the game yet</li>'}
      {"".join(f'<li>{e(t)} <span class="tag soon">planned</span></li>' for t in planned)}</ul></div>
      <div><h4>Drawbacks</h4><ul class="plain">{"".join(f"<li>{e(p)}</li>" for p in pen) or "<li>None</li>"}</ul></div>
    </div>
  </div>
</details>''')
    return "\n".join(out)


# ── Classes and their spells ──
ROLE_CLASS = {"Tank": "", "Healer": "healer", "Melee DPS": "dps", "Hybrid DPS": "dps", "Caster DPS": "dps"}
STAT_ABBR = {"strength": "Strength", "constitution": "Constitution", "dexterity": "Dexterity", "intelligence": "Intelligence",
             "wisdom": "Wisdom", "charisma": "Charisma", "luck": "Luck"}
START_WEAPON = {"Blademaster": "Rusty Sword", "Voidknight": "Rusty Sword", "Lightsworn": "Rusty Sword",
                "Shadowblade": "Dagger", "Woodstalker": "Dagger", "Aetherfist": "Worn Hand Wraps"}


def class_spells(cname):
    rows = []
    for s in SPELLS:
        lvl = s["class_level_requirements"].get(cname)
        if lvl is not None:
            rows.append((int(lvl), s))
    rows.sort(key=lambda t: (t[0], spell_name(t[1]["spell_name"])))
    return rows


def spell_row(lvl, s, cname):
    sid = s["spell_name"]
    tags = ""
    if sid in STARTING.get(cname, []):
        tags += '<span class="tag start">starting</span>'
    if s.get("passive"):
        tags += '<span class="tag passive">passive</span>'
    if s.get("upgrades"):
        tags += f'<span class="tag passive">replaces {e(", ".join(spell_name(u) for u in s["upgrades"]))}</span>'
    mana = f'{int(s["mana_cost"])}' if s.get("mana_cost") else "—"
    cast = "instant" if not s.get("casting_time") else f'{s["casting_time"]:g} s'
    recast = f'{s["recast_time"]:g} s' if s.get("recast_time") else "—"
    rng = "self" if str(s.get("range")) == "0m" else str(s.get("range", "")).replace("m", " m")
    if sid in STARTING.get(cname, []):
        where = "known"
    else:
        where = ", ".join(short_vendor(v) for v in SOLD_BY.get(SPELL_SCROLL.get(sid, ""), [])) or '<span class="muted">not sold yet</span>'
    return (f'<tr><td class="lvl">{lvl}</td><td><span class="name">{e(spell_name(sid))}</span>{tags}'
            f'<div class="desc">{e(s.get("description", ""))}</div></td>'
            f'<td class="num">{mana}</td><td class="num">{cast}</td><td class="num">{recast}</td><td class="num">{rng}</td><td>{where}</td></tr>')


def stances_for(cname):
    st = STANCES.get(cname)
    if not st:
        return ""
    lst = st if isinstance(st, list) else st.get("stances", list(st.values()))
    items = []
    for s in lst:
        if isinstance(s, dict) and s.get("name"):
            lvl = s.get("level", s.get("min_level"))
            items.append(f'<li><b>{e(s["name"])}</b>{f" (level {lvl})" if lvl and lvl > 1 else ""}: {e(s.get("description", ""))}</li>')
    return f'<h4>Stances</h4><ul class="plain">{"".join(items)}</ul>' if items else ""


def class_cards():
    out = []
    for cid, c in OPTIONS["classes"].items():
        pri = c["stat_priorities"]
        out.append(f'''<div class="card">
  <div class="top"><h3>{e(c["name"])}</h3><span class="role {ROLE_CLASS.get(c["role"], "")}">{e(c["role"])}</span></div>
  <p>{e(c["description"])}</p>
  <div class="meta"><b>{e(STAT_ABBR.get(pri["primary"], nice(pri["primary"])))}</b> · {e([t for t in c.get("armor_types", ["cloth"]) if t != "shield"][-1].capitalize())} armour{" + shield" if "shield" in c.get("armor_types", []) else ""} · {e(c.get("difficulty", ""))} · like a {e(c.get("base_class", ""))}</div>
  <a href="#class-{cid}">Spells and details</a>
</div>''')
    return "\n".join(out)


def class_details():
    out = []
    for cid, c in OPTIONS["classes"].items():
        name = c["name"]
        pri = c["stat_priorities"]
        spells = class_spells(name)
        start = ", ".join(spell_name(s) for s in STARTING.get(name, []))
        rows = [spell_row(l, s, name) for l, s in spells]
        out.append(f'''<details class="panel" id="class-{cid}">
  <summary><span class="title">{e(name)}</span><span class="sub">{e(c["role"])} · {len(spells)} spells</span></summary>
  <div class="body">
    <p>{e(c["description"])}</p>
    <div class="statline">
      <span><b>Stats</b> {e(STAT_ABBR[pri["primary"]])}, then {e(STAT_ABBR.get(pri["secondary"], ""))}, then {e(STAT_ABBR.get(pri["tertiary"], ""))}</span>
      <span><b>Difficulty</b> {e(c.get("difficulty", ""))}</span>
      <span><b>Also called</b> {e(", ".join(c.get("alternate_names", [])))}</span>
    </div>
    <div class="statline"><span><b>Races</b> {e(", ".join(RESTRICT.get(name, [])))}</span></div>
    <div class="statline"><span><b>Armour</b> {e(", ".join(c.get("armor_types", ["cloth"])))}</span></div>
    <div class="statline"><span><b>Starts with</b> {e(start)}{e(", " + START_WEAPON[name]) if name in START_WEAPON else ""}</span></div>
    {stances_for(name)}
    <h4>Spells</h4>
    {table(["Lvl", "Spell", "Mana", "Cast", "Recast", "Range", "Scroll from"], rows, (2, 3, 4, 5))}
  </div>
</details>''')
    return "\n".join(out)


# ── Skills ──
EFFECT_LABEL = {
    "attack_rating": "Accuracy (attack rating)", "melee_damage_pct": "Melee damage", "crit_chance": "Critical hit chance",
    "dodge_chance": "Dodge chance", "parry_chance": "Parry chance", "riposte_chance": "Riposte chance",
    "block_chance": "Block chance (with a shield)", "spell_potency_pct": "Spell damage and healing",
    "ability_damage_pct": "Physical ability damage", "concentration": "Keeping a spell when hit while casting",
    "stamina_regen": "Stamina regeneration", "stamina_drain_pct": "Less stamina used running",
    "bandage_heal_pct": "Bandage healing", "double_attack_chance": "Double attack chance",
    "triple_attack_chance": "Triple attack chance", "mana_regen": "Mana regeneration",
}


def skill_label(key):
    if key == "@weapon":
        return "the weapon you're using"
    if key == "@category":
        return "the spell's own school"
    return nice(key)


def skill_effects():
    rows = []
    for eff, parts in EFFECTS.items():
        by = ", ".join(skill_label(k) for k in parts)
        rows.append(f'<tr><td class="name">{e(EFFECT_LABEL.get(eff, nice(eff)))}</td><td>{e(by)}</td></tr>')
    return ('<p>What your skills do for you:</p>' + table(["Improves", "Raised by"], rows))


def skill_lists():
    titles = {"physical": ("Combat and physical skills", "Weapons, defence, movement and roguish arts."),
              "magic": ("Magic skills", "The schools of magic and the arts of casting."),
              "crafting": ("Crafting and gathering skills", "See Crafting and gathering for how they work.")}
    out = []
    for cat, (title, sub) in titles.items():
        skills = SKILLS.get(cat, {})
        rows = [f'<tr><td class="name">{e(nice(k))}</td><td>{e(v)}</td></tr>' for k, v in skills.items()]
        out.append(f'''<details class="panel"><summary><span class="title">{title}</span><span class="sub">{len(skills)} skills · {e(sub)}</span></summary>
  <div class="body">{table(["Skill", "What it does"], rows)}</div></details>''')
    return "\n".join(out)


# ── Crafting ──
STATION_NAMES = {"campfire": "Campfire", "oven": "Oven", "forge": "Forge", "alchemy_station": "Alchemy Station",
                 "brewing_vat": "Brewing Vat", "tinkering_bench": "Tinkering Bench", "fletching_station": "Fletching Station",
                 "jewelcrafting_station": "Jewelcrafting Station", "tannery": "Tannery", "tailors_bench": "Tailor's Bench",
                 "woodworking_station": "Woodworking Station"}


def station_name(sid):
    if sid in STATION_NAMES:
        return STATION_NAMES[sid]
    if sid.startswith("basic_") and sid.endswith("_kit"):
        return "Kit"
    return nice(sid)


def gathering():
    rows = []
    for n in sorted(NODES.values(), key=lambda n: (n["skill"], n["min_skill"])):
        tool = {"prospecting": "Miner's Pick", "woodworking": "Woodcutter's Axe"}.get(n["tool"], "—")
        bonus = n.get("bonus") or {}
        extra = f' <span class="desc">(sometimes {e(item_name(bonus["item"]))})</span>' if bonus.get("item") else ""
        rows.append(f'<tr><td class="name">{e(n["name"])}</td><td>{e(nice(n["skill"]))}</td><td class="num">{n["min_skill"]}</td>'
                    f'<td>{e(item_name(n["item"]))}{extra}</td><td>{e(tool)}</td><td>{e(n.get("location", ""))}</td></tr>')
    return table(["Node", "Skill", "Min", "Gives", "Tool", "Where"], rows, (2,))


# Recipe scrolls given as quest rewards: scroll id -> quest name.
QUEST_REWARD = {it.get("id", ""): q.get("name", "") for q in QUESTS.values() if isinstance(q, dict)
                for it in (q.get("rewards", {}).get("items", []) + q.get("repeat_rewards", {}).get("items", []))}


def recipes():
    by = defaultdict(list)
    for rid, r in RECIPES.items():
        by[r["skill"]].append((rid, r))
    out = []
    for skill in ["cooking", "alchemy", "brewing", "tinkering", "blacksmithing", "woodworking", "fletching",
                  "jewelcrafting", "leatherworking", "tailoring"]:
        lst = sorted(by.get(skill, []), key=lambda t: (t[1]["min_skill"], t[1]["name"]))
        rows = []
        for rid, r in lst:
            ing = ", ".join(f'{q} {e("Any Cooked Meat" if i == "cooked_meat_any" else item_name(i))}' for i, q in r["ingredients"].items())
            where = " / ".join(dict.fromkeys(station_name(s) for s in r["stations"]))
            if r.get("innate"):
                learn = '<span class="tag start">innate</span>'
            else:
                sold = ", ".join(short_vendor(v) for v in SOLD_BY.get(r.get("scroll", ""), []))
                learn = f'{price(r["scroll"])} · {e(sold)}' if sold else (f'quest: {e(QUEST_REWARD.get(r.get("scroll", ""), ""))}' if QUEST_REWARD.get(r.get("scroll", "")) else '<span class="muted">quest or drop</span>')
            soon = ' <span class="tag soon">effect coming</span>' if r.get("status") == "Needs engine" else ""
            made = f' <span class="desc">×{r["yield"]}</span>' if r["yield"] > 1 else ""
            rows.append(f'<tr><td class="num">{r["min_skill"]}</td><td><span class="name">{e(r["name"])}</span>{made}{soon}'
                        f'<div class="desc">{e(ITEMS.get(r["output"], {}).get("description", ""))}</div></td>'
                        f'<td>{ing}</td><td>{e(where)}</td><td>{learn}</td></tr>')
        innate = sum(1 for _, r in lst if r.get("innate"))
        out.append(f'''<details class="panel" id="craft-{skill}"><summary><span class="title">{nice(skill)}</span><span class="sub">{len(lst)} recipes · {innate} known from the start</span></summary>
  <div class="body">{table(["Skill", "Makes", "Ingredients", "Where", "Learn"], rows, (0,))}</div></details>''')
    return "\n".join(out)


# ── Lumora Outskirts ──
AREAS = [
    ("The Sand Dunes by the gate", ["dunes_start", "dunes_far"], "The gentle starting ground right outside Lumora's gate. Rats, sand vipers, dusk bats, dune scarabs and a few slimes."),
    ("The roads", ["road_south", "road_west", "nw_approach", "far_west", "southwest", "south_a", "south_b", "south_c"], "The roads between the landmarks. Mixed wildlife, the odd skeleton, and shimmering mirage phantoms in the heat."),
    ("The Wagon Crash", ["wagon_crash", "wagon_crash_named"], "A Lumoran trading wagon, wrecked on the south road. Brigands pick over it, led by Dessik Coinhand."),
    ("The bandit camps", ["bandit_camp_1", "bandit_camp_2", "bandit_camp_1_named"], "Two camps of sand brigands. Rask Ironjaw runs the larger one."),
    ("The goblin camps", ["goblin_camp_1", "goblin_camp_2", "goblin_camp_3", "goblin_camp_1_named"], "Three camps of desert goblins, with warriors and scouts. Grukka Bonechewer leads the biggest."),
    ("The Mausoleum, graveyard and crypts", ["mausoleum", "graveyard", "small_crypt_1", "small_crypt_2", "mausoleum_named"], "An old burial ground where the dead don't rest: fallen scout skeletons, a sand mummy, a tormented spirit, and Sergeant Halvek, a Warden who never came home."),
    ("The Spider Den", ["spider_den", "spider_den_named"], "A den far to the west, gone wrong. Blighted spiders and spiderling swarms guard Weavemother Vhessa. Take friends."),
    ("The deep dunes", ["deep_dunes_south"], "Far to the south, where the Hollowed wander: Djhanid exiles driven mad by the sun. They appear rarely."),
]


def places():
    rows = []
    zone_mobs = defaultdict(set)
    for s in SPAWNS:
        zone_mobs[s["spawn_zone"]].add(s["mob_type"])
    for title, zones, text in AREAS:
        mobs = sorted({MONSTERS[m]["description"] for z in zones for m in zone_mobs.get(z, set()) if m in MONSTERS},
                      key=str.lower)
        lv = [(s.get("min_level"), s.get("max_level")) for s in SPAWNS if s["spawn_zone"] in zones]
        lows = [MONSTERS[s["mob_type"]]["level"] if s["spawn_zone"].endswith("named") else (s.get("min_level") or 1) for s in SPAWNS if s["spawn_zone"] in zones]
        highs = [MONSTERS[s["mob_type"]]["level"] if s["spawn_zone"].endswith("named") else (s.get("max_level") or 1) for s in SPAWNS if s["spawn_zone"] in zones]
        levels = f"{min(lows)}–{max(highs)}" if lows else ""
        rows.append(f'<tr><td class="name">{e(title)}</td><td class="num">{levels}</td><td>{e(text)}</td></tr>')
    return table(["Place", "Levels", "What's there"], rows, (1,))


NPCS = [
    ("Guard Reyna", "Oasis Warden", "Keeps the town gate. Hail her: she has work for newcomers (a wrecked wagon on the south road) and wants to hear about a Warden who isn't resting."),
    ("Private Corwin", "Oasis Warden", "Worried about the spiders in the western den. Hail him and ask. His questions lead somewhere darker."),
    ("Sergeant Bryn", "Oasis Warden", "Patrols the town. Try /follow Sergeant Bryn to walk his rounds."),
    ("Guard Halric", "Oasis Warden", "One of the gate guards. The guards all answer questions: hail them and click the words you want to know about."),
    ("Aldric the Provisioner", "General goods", "Food, water, bags, torches, a compass, gathering tools, crafting kits, basic ammunition, and the Woodworking, Cooking, Fletching, Leatherworking and Tailoring recipe scrolls, including the Oasis Linen and Dunehide armour patterns. Short of fur for his packs."),
    ("Borgrim Emberforge", "Dwarf smith, by the forge", "Every Blacksmithing pattern he'll teach an outsider, including the Copperlink mail and Bronzeguard plate sets, and a Miner's Pick. Blunt, proud of good work, rude about bad work."),
    ("Lira Solarpetal", "Apothecary", "Alchemy and brewing: kits, crystal vials, and the Alchemy and Brewing recipe scrolls. Always short of rarer reagents."),
    ("Tobble Cogfarrow", "Gnome tinkerer", "The Tinkering and Jewelcrafting kits and recipes, the Large Crafting Bag, and the compass (the one thing he considers finished)."),
    ("Archivist Ilsabet Thornmere", "Scribe of the Oasis Wardens", "Spell scrolls for the light and neutral classes, and language primers. Precise, formal, and will correct your spelling."),
    ("Xalvyr Tenn", "Vol'kyne copyist, Sandveil Bazaar", "Spell scrolls for the dark classes, and language primers. Tolerated in Lumora only under Zyra Sandveil's protection. “Coin acknowledges no gods.”"),
    ("Oswin Coinwright", "Banker", "Right-click him to open your bank."),
    ("Harbour Master Tobias Sandcrest", "Sandcrest Landing", "Runs the docks and sells passage north to Thallia's Bastion. The ferry isn't running yet."),
    ("Sahren of the Deep Wells", "Travelling Djhanid merchant", "Walks the roads between the landmarks, so you'll have to find him. Sells rare goods and the Djhanid primer, and asks for help releasing the Hollowed. Speak to him in Djhanid and he answers in kind."),
    ("Kenji", "The gate cat", "Sits by the town gate. Bring him 10 rat tails (you can give them a few at a time) for 40 experience and Kenji's Blessing: better regeneration and accuracy for 15 minutes. He never tires of rat tails."),
    ("Oni", "The hunting cat", "Patrols the town and hunts rats. /pet her if she lets you."),
]


def npcs():
    return "\n".join(f'<div class="card"><div class="top"><h3>{e(n)}</h3></div><div class="role">{e(r)}</div><p>{e(t)}</p></div>'
                     for n, r, t in NPCS)


def quests():
    rows = []
    for q in QUESTS.values():
        if not isinstance(q, dict):
            continue
        rw = q.get("rewards", {})
        coin = ", ".join(f"{v} {k}" for k, v in rw.get("coin", {}).items())
        reward = " + ".join(x for x in [f'{rw["xp"]} XP' if rw.get("xp") else "", coin] if x)
        after = f' <span class="desc">(after {e(QUESTS[q["requires_quest"]]["name"])})</span>' if q.get("requires_quest") else ""
        rows.append(f'<tr><td class="name">{e(q["name"])}{after}</td><td>{e(q.get("giver", ""))}</td><td>{e(q.get("short", ""))}</td><td>{e(reward)}</td></tr>')
    return table(["Quest", "From", "What to do", "Reward"], rows)


BEHAVIOUR = {"passive": "Leaves you alone unless you get very close", "skitter": "Attacks when you come near",
             "aggressive": "Attacks on sight", "neutral": "Attacks if you come close"}


def bestiary():
    lv = defaultdict(list)
    for s in SPAWNS:
        if not s["spawn_zone"].endswith("named"):
            lv[s["mob_type"]] += [s.get("min_level") or MONSTERS[s["mob_type"]]["level"], s.get("max_level") or MONSTERS[s["mob_type"]]["level"]]
    seen, rows = [], []
    for s in SPAWNS:
        m = s["mob_type"]
        if m in seen:
            continue
        seen.append(m)
    def key(m):
        named = any(s["spawn_zone"].endswith("named") and s["mob_type"] == m for s in SPAWNS)
        return (named, MONSTERS[m]["level"], MONSTERS[m]["description"].lower())
    for m in sorted(seen, key=key):
        d = MONSTERS[m]
        named = any(s["spawn_zone"].endswith("named") and s["mob_type"] == m for s in SPAWNS)
        levels = str(d["level"]) if named or not lv[m] else (f"{min(lv[m])}–{max(lv[m])}" if min(lv[m]) != max(lv[m]) else str(min(lv[m])))
        name = d["description"][0].upper() + d["description"][1:]
        tag = ' <span class="tag named">named</span>' if named else ""
        notes = []
        if d.get("is_social"):
            notes.append("calls nearby friends")
        eff = d.get("on_hit_effect")
        if isinstance(eff, dict) and eff.get("name"):
            notes.append(f'may inflict {e(eff["name"])}')
        cat = nice(d.get("category", ""))
        rows.append(f'<tr><td class="num">{levels}</td><td><span class="name">{e(name)}</span>{tag}</td><td>{e(cat)}</td>'
                    f'<td class="num">{d["health"]}</td><td>{e(BEHAVIOUR.get(d.get("behavior_type"), ""))}{"; " + "; ".join(notes) if notes else ""}</td></tr>')
    return table(["Level", "Creature", "Kind", "Health", "Behaviour"], rows, (0, 3))


# ── Controls: lifted from the tester guide so the list lives in one place ──
def controls():
    src = open(os.path.join(ROOT, "TESTER_GUIDE.html")).read()
    m = re.search(r'<details class="allkeys">.*?<p class="fine">.*?</p>(.*?)</details>', src, re.S)
    return m.group(1).strip() if m else "<p>See Esc → Controls &amp; Commands in the game.</p>"


def main():
    with open(os.path.join(ROOT, "tools", "manual_template.html")) as f:
        page = f.read()
    page = re.sub(r"\A<!--.*?-->\s*", "", page, flags=re.S)
    fill = {
        "VERSION": BUILD.get("build", "?"), "DATE": BUILD.get("date", ""), "MAX_LEVEL": str(MAX_LEVEL),
        "SKILL_CAP": str(SKILL_CAP), "SKILL_CAP_5": str(SKILL_CAP * 5),
        "LANGUAGES": languages(), "XP_TABLE": xp_table(), "RACES": races(),
        "CLASS_CARDS": class_cards(), "CLASS_DETAILS": class_details(),
        "SKILL_EFFECTS": skill_effects(), "SKILL_LISTS": skill_lists(),
        "GATHERING": gathering(), "RECIPES": recipes(),
        "PLACES": places(), "NPCS": npcs(), "QUESTS": quests(), "BESTIARY": bestiary(), "CONTROLS": controls(),
    }
    for k, v in fill.items():
        page = page.replace("{{" + k + "}}", v)
    left = re.findall(r"\{\{\w+\}\}", page)
    if left:
        raise SystemExit(f"unfilled markers: {left}")
    out = os.path.join(ROOT, "PLAYER_MANUAL.html")
    with open(out, "w") as f:
        f.write(page)
    print(f"Wrote {out} ({len(page) // 1024} KB): {sum(len(class_spells(c['name'])) for c in OPTIONS['classes'].values())} "
          f"class spell rows, {len(RECIPES)} recipes, build {fill['VERSION']}.")


if __name__ == "__main__":
    main()
