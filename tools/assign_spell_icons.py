#!/usr/bin/env python3
"""Match Assets/icons/spells/*.png to every spell in Data/player_spells.json.

Prefix (which icon family) comes from the spell's `target` field:
  self            -> self*
  enemy           -> target*
  group           -> group*   (player group if beneficial, enemies around the
                              target if detrimental)
  pbaoe/cone/line -> aoe*     (radiates from the caster)
  chain           -> group*
Exceptions: a beneficial "group" spell whose description explicitly names a
single ally and no party/allies wording is cast on one ally today -> target*;
beneficial spells mis-tagged target=enemy are really self buffs -> self*.

Usage:  python3 tools/assign_spell_icons.py           (dry run: prints a report)
        python3 tools/assign_spell_icons.py --write   (rewrites the "icon" field
                                                       on every spell; idempotent)
Re-run after adding icon files or changing a spell's target/effect_type.

Kind (which picture) comes from effect_type / description; damage kinds come
from spell_school.  Anything with no matching icon file gets no icon field.
"""
import json, os, re, sys, collections

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPELLS = f"{ROOT}/Data/player_spells.json"
ICON_DIR = f"{ROOT}/Assets/icons/spells"
RES = "res://Assets/icons/spells/"

have = {f[:-4] for f in os.listdir(ICON_DIR) if f.endswith(".png")}

SCHOOL_KIND = {"fire": "fire", "cold": "ice", "lightning": "lightning",
               "poison": "poison", "disease": "poison", "divine": "divine",
               "magic": "arcane", "psychic": "arcane", "spirit": "necromancy"}
CC_KIND = {"stun": "stun", "root": "root", "snare": "root", "fear": "fear",
           "silence": "silence", "blind": "blind", "confuse": "stun",
           "mesmerize": "stun", "charm": "arcane"}
BENEFICIAL_EFFECTS = {"heal", "hot", "buff", "absorb", "cure", "light"}
SINGLE_ALLY = re.compile(r"\b(1 ally|one ally|an ally|ally|self/ally)\b", re.I)
MULTI_ALLY = re.compile(r"\b(allies|party|group|everyone|nearby)\b", re.I)
# Spells tagged enemy/group with no effect_type whose text is plainly a buff
# ("+10% attack...", "Gains...", "Absorbs 150 damage...", "Transforms into...").
BUFF_START = re.compile(r"^(\+\d|gains\b|grants\b|absorbs\b|regenerates\b|transforms into\b|converts\b|"
                        r"companions gain|creates (a |\d+ )?(decoy|illusion)|.{0,40}\bgrants\b)", re.I)
HOSTILE_WORDS = re.compile(r"\b(deals?|enemy|enemies|target)\b", re.I)
UPGRADE = re.compile(r"^(improved|enhanced|greater|master)_(.+)$")
WARD = re.compile(r"absorb|shield|barrier|\bward\b|aegis", re.I)


def classify(s):
    """Return (icon_stem_or_None, note)."""
    tgt, eff, st = s["target"], s.get("effect_type"), s["spell_type"]
    school, desc, name = s["spell_school"], s["description"], s["spell_name"]
    dmg_words = bool(re.search(r"\bdeals?\b", desc, re.I))

    if st == "teleport":
        return "teleport", ""
    if re.search(r"resurrect|revival", name):
        return "resurrect", ""
    if "totem" in name:
        return "totemsummon", ""
    if st == "summon" or eff == "summon":
        return "petsummon", ""

    # ---- decide beneficial vs hostile -----------------------------------
    hostile_target = tgt in ("enemy", "pbaoe", "cone", "line", "chain", "corpse")
    beneficial = False
    if eff in BENEFICIAL_EFFECTS:
        beneficial = True
    elif eff is None and st in ("beneficial", "self-beneficial", "reactive"):
        beneficial = True
    if (not beneficial and eff is None and tgt in ("enemy", "group")
            and BUFF_START.search(desc) and not HOSTILE_WORDS.search(desc)):
        beneficial = True
    # life-drain style: enemy target, effect "heal", but really an attack
    if tgt == "enemy" and eff == "heal" and st == "detrimental":
        beneficial = False
    if tgt in ("pbaoe", "cone", "line", "chain") and eff == "heal" and st in ("targeted_directional", "chain"):
        beneficial = True
    if tgt == "enemy" and eff == "heal" and st == "beneficial" and dmg_words:
        beneficial = False  # harmony_blade: deals damage, heals self

    note = ""
    # ---- dispel-typed, non-heal -------------------------------------------
    if st == "dispel" and eff in (None, "cure") and school != "physical":
        kind = "dispel"
    elif beneficial:
        if eff == "hot":
            kind = "hot"
        elif eff == "heal":
            kind = "heal"
        elif eff == "absorb" or WARD.search(desc) or re.search(r"ward|shield|barrier|aegis", name):
            kind = "ward"
        else:
            kind = "buff"
    else:
        # hostile
        if eff in CC_KIND and not (dmg_words and school != "physical"):
            kind = CC_KIND[eff]
        elif school in SCHOOL_KIND and (s["damage"] > 0 or eff == "dot" or dmg_words):
            kind = SCHOOL_KIND[school]
        elif school in SCHOOL_KIND:
            kind = SCHOOL_KIND[school]   # untyped debuffs -> school flavour
            note = "debuff->school"
        else:
            return None, "physical/no icon"

    # ---- prefix -----------------------------------------------------------
    if tgt == "self":
        prefix = "self"
    elif beneficial:
        if tgt == "enemy":
            prefix = "self"; note = "mistagged enemy->self"
        elif tgt == "corpse":
            prefix = "self"
        elif tgt == "group":
            single = SINGLE_ALLY.search(desc) and not MULTI_ALLY.search(desc)
            prefix = "target" if single else "group"
            if single:
                note = "single-ally"
        else:                                  # pbaoe/cone/chain heals & buffs
            prefix = "group"
    else:
        if tgt in ("pbaoe", "cone", "line"):
            prefix = "aoe" if kind in ("fire", "ice", "lightning", "poison", "divine",
                                       "arcane", "necromancy") else "group"
            if prefix == "group":
                note = "aoe-cc->group"
        elif tgt in ("group", "chain"):
            prefix = "group"
        else:                                   # enemy / corpse
            prefix = "aoe" if tgt == "corpse" else "target"

    # self* only exists for buff/heal/ward
    if prefix == "self" and kind not in ("buff", "heal", "ward"):
        kind = "heal" if kind == "hot" else "buff"
        note = (note + " self-kind-fallback").strip()

    stem = f"{prefix}{kind}"
    if kind in ("teleport",):
        stem = kind
    if stem not in have:
        return None, f"missing:{stem}"
    return stem, note


def resolve_all(data):
    """classify() every spell, then let improved_/enhanced_/greater_/master_
    upgrades share their base spell's icon (or lack of one) when the base
    exists in the file."""
    names = {s["spell_name"]: s for s in data}
    own = {s["spell_name"]: classify(s) for s in data}
    final = {}
    for n, (stem, note) in own.items():
        m = UPGRADE.match(n)
        if m and m.group(2) in names:
            base = m.group(2)
            bstem = own[base][0]
            # chase chains like master_improved_x
            mm = UPGRADE.match(base)
            while mm and mm.group(2) in names:
                base = mm.group(2); bstem = own[base][0]; mm = UPGRADE.match(base)
            final[n] = (bstem, f"inherits:{base}")
        else:
            final[n] = (stem, note)
    return final


def main(write: bool):
    raw = open(SPELLS).read()
    data = json.loads(raw)
    by_icon = collections.defaultdict(list)
    none = []
    notes = collections.Counter()
    final = resolve_all(data)
    for s in data:
        stem, note = final[s["spell_name"]]
        if note:
            notes[note.split(":")[0]] += 1
        if stem is None:
            none.append((s["spell_name"], s["target"], s.get("effect_type"), s["spell_school"], note))
        else:
            by_icon[stem].append(s["spell_name"])
        s["_stem"] = stem
        s["_note"] = note

    if not write:
        print(f"icons used: {len(by_icon)} / {len(have)}; spells with icon: {sum(map(len, by_icon.values()))}; without: {len(none)}")
        print("unused icon files:", sorted(have - set(by_icon)))
        print("notes:", dict(notes))
        for k, v in sorted(by_icon.items(), key=lambda kv: -len(kv[1])):
            print(f"  {k:18}{len(v):4}  e.g. {', '.join(v[:4])}")
        why = collections.Counter(n[4] for n in none)
        print("\nno icon:", dict(why))
        return data

    out = []
    for s in data:
        stem = s.pop("_stem"); s.pop("_note")
        new = {}
        for k, v in s.items():
            if k == "icon":
                continue
            new[k] = v
            if k == "spell_name" and stem:
                new["icon"] = RES + stem + ".png"
        out.append(new)
    text = json.dumps(out, indent=4, ensure_ascii=False)
    if raw.endswith("\n"):
        text += "\n"
    open(SPELLS, "w").write(text)
    print("wrote", SPELLS)


if __name__ == "__main__":
    main(write="--write" in sys.argv)
