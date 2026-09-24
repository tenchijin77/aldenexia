#!/usr/bin/env python3
# make_icon_variants.py — builds colour variants of item icons from one base picture, so one drawn icon (a bow, a ring,
# a potion vial) covers every tier of it. Each variant is written to Assets/icons/items/<item_id>.png, where
# tools/export_crafting.py (crafting items) and Data/items.json pick it up.
#
#   python3 tools/make_icon_variants.py            build every variant in VARIANTS
#   python3 tools/make_icon_variants.py --sheet F  also save a contact sheet of the results to F (for a quick look)
#
# How a variant is made: only the coloured part of the icon (its background glow and the object) is recoloured —
# the grey stone frame and dark outlines are left alone. A recipe is (hue in degrees or None to keep, saturation
# multiplier, brightness multiplier). Re-run after changing a base icon. To give an item hand-drawn art instead,
# delete its line below and save the art as its own <item_id>.png.

import colorsys
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ITEMS = os.path.join(ROOT, "Assets", "icons", "items")

# Named recipes: (hue degrees or None, saturation x, brightness x)
KEEP = (None, 1.0, 1.0)
TIN = (210, 0.12, 1.1)
COPPER = (18, 1.0, 0.95)
BRONZE = (34, 0.75, 0.85)
FIR = (40, 0.55, 1.0)
IRONWOOD = (22, 0.7, 0.6)
PALM = (46, 1.0, 1.1)
COOKED = (24, 0.75, 0.7)
RED, GREEN, BLUE, PURPLE, TEAL = (0, 1.0, 1.0), (115, 0.9, 0.9), (215, 1.0, 1.0), (275, 0.85, 1.0), (175, 0.9, 0.95)
AMBER, SILVER, GOLD, DARK_RED = (38, 1.0, 1.0), (220, 0.15, 1.15), (48, 0.9, 1.1), (355, 0.95, 0.65)

# item_id -> (base icon file, recipe)
VARIANTS = {
    # bows / staves (Woodworking)
    "fir_shortbow": ("bow.png", FIR), "ironwood_bow": ("bow.png", IRONWOOD), "palm_longbow": ("bow.png", PALM),
    "fir_staff": ("staff.png", FIR), "ironwood_staff": ("staff.png", IRONWOOD), "masters_staff": ("staff.png", GOLD),
    # quivers (Fletching / vendor)
    "quiver_of_rough_arrows": ("quiver.png", (None, 0.35, 0.85)), "case_of_rough_bolts": ("quiver.png", (210, 0.2, 0.8)),
    "quiver_of_fir_arrows": ("quiver.png", FIR), "quiver_of_ironwood_arrows": ("quiver.png", IRONWOOD),
    "quiver_of_broadhead_arrows": ("quiver.png", COPPER), "quiver_of_palm_arrows": ("quiver.png", PALM),
    "broadhead_arrowheads": ("arrowhead.png", COPPER),
    # jewelry (Jewelcrafting / Tinkering)
    "tin_ring": ("ruby_ring.png", TIN), "copper_ring": ("ruby_ring.png", COPPER), "bronze_ring": ("ruby_ring.png", KEEP),
    "simple_amulet": ("amulet.png", TIN), "copper_pendant": ("amulet.png", COPPER), "bronze_amulet": ("amulet.png", KEEP),
    "bronze_charm": ("fang_necklace.png", BRONZE),
    # tools and gadgets
    "miners_pick": ("pickaxe.png", KEEP), "copper_pickaxe": ("pickaxe.png", COPPER),
    "copper_lantern": ("lantern.png", COPPER),
    "explosive_device": ("bomb.png", KEEP), "smoke_grenade": ("bomb.png", (None, 0.15, 1.2)),
    # kits (one satchel, a colour per skill)
    "basic_alchemy_kit": ("tinkering_kit.png", TEAL), "basic_cooking_kit": ("tinkering_kit.png", RED),
    "basic_brewing_kit": ("tinkering_kit.png", AMBER), "basic_fletching_kit": ("tinkering_kit.png", GREEN),
    "basic_jewelcrafting_kit": ("tinkering_kit.png", PURPLE), "basic_leatherworking_kit": ("tinkering_kit.png", COPPER),
    "basic_tailoring_kit": ("tinkering_kit.png", (330, 0.8, 1.0)), "basic_woodworking_kit": ("tinkering_kit.png", IRONWOOD),
    # potions and poisons (Alchemy) — the vial with a different liquid
    "minor_healing_potion": ("crystal_vial.png", RED), "antidote_essence": ("crystal_vial.png", (90, 0.6, 0.9)),
    "stamina_elixir": ("crystal_vial.png", AMBER), "moonpetal_essence": ("crystal_vial.png", SILVER),
    "elixir_of_insight": ("crystal_vial.png", PURPLE), "viper_poison": ("crystal_vial.png", GREEN),
    "basic_poison": ("crystal_vial.png", (75, 0.8, 0.75)),
    # brews (Brewing): teas in the mug, combat brews in the goblet
    "desert_tea": ("cup.png", AMBER), "fortified_tonic": ("cup.png", (60, 0.7, 0.8)), "clarity_draught": ("cup.png", BLUE),
    "energy_brew": ("goblet.png", TEAL), "courage_draught": ("goblet.png", DARK_RED),
    "resistance_elixir": ("goblet.png", PURPLE), "starlight_cordial": ("goblet.png", SILVER),
    # cooked meats: the raw meat, browned
    "cooked_bat_meat": ("raw_bat_meat.png", COOKED), "cooked_rat_meat": ("raw_rat_meat.png", COOKED),
    "cooked_spider_meat": ("raw_spider_meat.png", COOKED), "cooked_snake_meat": ("raw_snake_meat.png", COOKED),
    "cooked_goblin_meat": ("raw_goblin_meat.png", COOKED), "cooked_human_meat": ("raw_human_meat.png", COOKED),
    "cooked_meat": ("raw_rat_meat.png", (30, 0.6, 0.65)),
    # firewood bundles: the logs as they are
    "fir_firewood_bundle": ("fir_log.png", KEEP), "ironwood_firewood_bundle": ("ironwood_log.png", KEEP),
    "palm_firewood_bundle": ("palm_log.png", KEEP),
    # bowstrings: the thread
    "bowstring": ("thread.png", KEEP), "silk_bowstring": ("thread.png", (270, 0.35, 1.1)),
    # torches (Woodworking)
    "pitch_torch": ("torch.png", (None, 0.8, 0.8)), "ironwood_torch": ("torch.png", IRONWOOD),
    "palm_resin_torch": ("torch.png", GOLD),
    # dishes (Cooking)
    "desert_thistle_salad": ("salad.png", KEEP), "sandroot_stew": ("stew.png", KEEP), "viper_kebab": ("kebab.png", KEEP),
    # crafted gear: the generic slot art, tinted per material
    "tin_dagger": ("dagger.png", TIN), "tin_shortsword": ("sword.png", TIN), "copper_sword": ("sword.png", COPPER),
    "bronze_longsword": ("sword.png", BRONZE), "copper_war_axe": ("axe.png", COPPER),
    "woodcutters_axe": ("axe.png", KEEP), "bronze_woodcutters_axe": ("axe.png", BRONZE),
    "bronze_lockpick_set": ("key.png", BRONZE), "copper_wrist_cuff": ("chain-bracers.png", COPPER),
    "copper_armor_plating": ("plate-breastplate.png", COPPER), "bronze_shield": ("shield.png", BRONZE),
    "tin_shield": ("shield.png", TIN),
    "leather_jerkin": ("leather-chestpiece.png", (None, 0.7, 1.15)), "leather_armor": ("leather-chestpiece.png", KEEP),
    "hardened_leather_armor": ("leather-chestpiece.png", (20, 0.8, 0.7)),
    "reinforced_leather_armor": ("leather-chestpiece.png", (190, 0.45, 0.75)),
    "leather_boots": ("leather-boots.png", KEEP), "leather_bracers": ("leather-bracers.png", KEEP),
    "simple_robe": ("cloth-chestpiece.png", (None, 0.3, 1.0)), "apprentice_robe": ("cloth-chestpiece.png", BLUE),
    "mages_robe": ("cloth-chestpiece.png", PURPLE), "archmages_robe": ("cloth-chestpiece.png", GOLD),
    # older game gear that shared generic art
    "ragged_leggings": ("cloth_pants.png", (None, 0.5, 0.8)),
    "ragged_hood": ("hood.png", (None, 0.4, 0.8)), "ragged_tunic": ("cloth-chestpiece.png", (35, 0.35, 0.75)),
    "cloth_cape": ("cloak.png", (None, 0.4, 1.0)), "ghostly_cloak": ("cloak.png", (195, 0.4, 1.15)),
    "weavemothers_silk_cloak": ("cloak.png", PURPLE),
    "cloth_slippers": ("cloth-shoes.png", KEEP), "torn_boots": ("cloth-shoes.png", (None, 0.3, 0.7)),
    "worn_sandals": ("cloth-shoes.png", (38, 0.45, 0.9)), "royal_sandals": ("cloth-shoes.png", GOLD),
    "goblin_hide_boots": ("leather-boots.png", GREEN),
    "bandit_captains_vest": ("leather-chestpiece.png", DARK_RED), "tarnished_warden_helm": ("plate-helm.png", (80, 0.3, 0.7)),
    "bone_shield": ("shield.png", (42, 0.25, 1.1)),
    "bandit_dagger": ("dagger.png", DARK_RED), "sharp_dagger": ("dagger.png", SILVER), "venomfang_dagger": ("dagger.png", GREEN),
    "rusty_sword": ("sword.png", (18, 0.8, 0.6)), "rusty_cleaver": ("axe.png", (18, 0.8, 0.6)),
    "notched_blade": ("sword.png", (None, 0.3, 0.75)), "brigand_cutlass": ("sword.png", DARK_RED),
    "wardens_grave_blade": ("sword.png", SILVER), "warlord_scimitar": ("sword.png", GOLD),
    "worn_hand_wraps": ("cloth-bracers.png", (None, 0.4, 0.85)), "combat_wraps": ("cloth-bracers.png", DARK_RED),
    "scavenged_ring": ("ruby_ring.png", (None, 0.3, 0.7)), "coinhand_signet": ("ruby_ring.png", GOLD),
    "ravager_earring": ("ruby_ring.png", DARK_RED),
    "tribal_charm": ("fang_necklace.png", GREEN), "chieftains_bone_charm": ("fang_necklace.png", KEEP),
    "small_bag": ("backpack.png", (None, 0.5, 0.85)), "traveler_pack": ("backpack.png", KEEP),
    "scroll_case": ("scroll.png", (25, 0.8, 0.75)),
    # older materials that match the new crafting art
    "raw_meat": ("raw_rat_meat.png", (5, 0.9, 0.95)),
    "leather_scrap": ("soft_leather.png", (None, 0.6, 0.85)), "light_leather": ("soft_leather.png", (40, 0.6, 1.1)),
    "heavy_leather": ("hardened_leather.png", (None, 0.8, 0.7)),
    "linen_cloth": ("woven_cloth.png", (None, 0.4, 1.1)), "rotting_cloth": ("woven_cloth.png", (70, 0.5, 0.6)),
    "rotten_linen": ("woven_cloth.png", (55, 0.4, 0.7)),
    "fur_pelt": ("raw_hide.png", (30, 0.5, 0.9)), "dog_pelt": ("raw_hide.png", (25, 0.4, 0.7)),
    "gnoll_pelt": ("raw_hide.png", (42, 0.7, 0.8)), "tough_hide": ("raw_hide.png", (80, 0.4, 0.7)),
    "snake_venom": ("crystal_vial.png", (95, 0.9, 0.8)), "toxic_residue": ("crystal_vial.png", (70, 0.9, 0.6)),
    "acidic_fluid": ("crystal_vial.png", (60, 1.0, 1.0)),
    "spring_water": ("crystal_vial.png", (200, 0.6, 1.1)), "water_flask": ("crystal_vial.png", (190, 0.9, 0.95)),
    "desert_root": ("sandroot.png", (20, 0.6, 0.8)), "shiny_pebble": ("uncut_gem.png", (None, 0.3, 1.1)),
    "spider_silk": ("thread.png", (None, 0.1, 1.2)), "blighted_spider_silk": ("thread.png", (100, 0.4, 0.7)),
    # armour sets (2026-09-24): the slot art of each armour type, tinted per set (shoulders/arms/waist are stand-ins)
    "copper_links": ("chain-bracers.png", COPPER),
    "night_eye_draught": ("crystal_vial.png", (250, 0.7, 0.75)),
    "copperlink_gloves": ("chainmail_gloves.png", COPPER),
    "copperlink_boots": ("chain-boots.png", COPPER),
    "copperlink_bracers": ("chain-bracers.png", COPPER),
    "copperlink_belt": ("chain-bracers.png", COPPER),
    "copperlink_coif": ("chain-helm.png", COPPER),
    "copperlink_sleeves": ("chain-bracers.png", COPPER),
    "copperlink_spaulders": ("chainmail-chestpiece.png", COPPER),
    "copperlink_leggings": ("chainmail_pants.png", COPPER),
    "copperlink_hauberk": ("chainmail-chestpiece.png", COPPER),
    "bronzeguard_gauntlets": ("plate_gauntlets.png", BRONZE),
    "bronzeguard_sabatons": ("plate-boots.png", BRONZE),
    "bronzeguard_vambraces": ("plate-bracers.png", BRONZE),
    "bronzeguard_girdle": ("plate-bracers.png", BRONZE),
    "bronzeguard_helm": ("plate-helm.png", BRONZE),
    "bronzeguard_rerebraces": ("plate-bracers.png", BRONZE),
    "bronzeguard_pauldrons": ("plate-breastplate.png", BRONZE),
    "bronzeguard_greaves": ("plate_legplates.png", BRONZE),
    "bronzeguard_breastplate": ("plate-breastplate.png", BRONZE),
    "dunehide_gloves": ("leather_gloves.png", (32, 0.7, 0.95)),
    "dunehide_boots": ("leather-boots.png", (32, 0.7, 0.95)),
    "dunehide_bracers": ("leather-bracers.png", (32, 0.7, 0.95)),
    "dunehide_belt": ("leather.png", (32, 0.7, 0.95)),
    "dunehide_cap": ("leather-helm.png", (32, 0.7, 0.95)),
    "dunehide_sleeves": ("leather-bracers.png", (32, 0.7, 0.95)),
    "dunehide_pauldrons": ("leather-chestpiece.png", (32, 0.7, 0.95)),
    "dunehide_leggings": ("leather_pants.png", (32, 0.7, 0.95)),
    "dunehide_jerkin": ("leather-chestpiece.png", (32, 0.7, 0.95)),
    "oasis_linen_gloves": ("cloth_gloves.png", (175, 0.5, 1.05)),
    "oasis_linen_slippers": ("cloth-shoes.png", (175, 0.5, 1.05)),
    "oasis_linen_wraps": ("cloth-bracers.png", (175, 0.5, 1.05)),
    "oasis_linen_sash": ("cloth.png", (175, 0.5, 1.05)),
    "oasis_linen_hood": ("hood.png", (175, 0.5, 1.05)),
    "oasis_linen_sleeves": ("cloth-bracers.png", (175, 0.5, 1.05)),
    "oasis_linen_mantle": ("cloth-chestpiece.png", (175, 0.5, 1.05)),
    "oasis_linen_trousers": ("cloth_pants.png", (175, 0.5, 1.05)),
    "oasis_linen_robe": ("cloth-chestpiece.png", (175, 0.5, 1.05)),
}

SAT_MASK = 0.18  # pixels less saturated than this (the stone frame, outlines, highlights) are left untouched


def recolour(img: Image.Image, recipe: tuple) -> Image.Image:
    hue, sat_mul, val_mul = recipe
    if recipe == KEEP:
        return img.copy()
    out = img.convert("RGBA")
    px = out.load()
    w, h = out.size
    target_h = None if hue is None else (hue % 360) / 360.0
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            hh, s, v = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
            if s < SAT_MASK or a == 0:
                continue
            # fade the effect in over the mask edge so outlines don't get a hard seam
            k = min(1.0, (s - SAT_MASK) / 0.12)
            nh = hh if target_h is None else target_h
            ns = min(1.0, s * sat_mul)
            nv = min(1.0, v * val_mul)
            nr, ng, nb = colorsys.hsv_to_rgb(nh, ns, nv)
            px[x, y] = (int(r + (nr * 255 - r) * k), int(g + (ng * 255 - g) * k), int(b + (nb * 255 - b) * k), a)
    return out


def main() -> None:
    sheet_path = sys.argv[sys.argv.index("--sheet") + 1] if "--sheet" in sys.argv else ""
    made = []
    missing = sorted({base for base, _ in VARIANTS.values() if not os.path.exists(os.path.join(ITEMS, base))})
    for item_id, (base, recipe) in VARIANTS.items():
        src = os.path.join(ITEMS, base)
        if not os.path.exists(src):
            continue
        out = recolour(Image.open(src), recipe)
        mode = Image.open(src).mode
        out = out.convert(mode) if mode in ("RGB", "RGBA") else out
        out.save(os.path.join(ITEMS, item_id + ".png"))
        made.append(item_id)
    print(f"Made {len(made)} icon variants.")
    if missing:
        print("Missing base icons (their variants were skipped):", ", ".join(missing))
    if sheet_path:
        cols, size = 10, 96
        rows = (len(made) + cols - 1) // cols
        sheet = Image.new("RGBA", (cols * size, rows * size), (50, 50, 50, 255))
        for i, item_id in enumerate(made):
            im = Image.open(os.path.join(ITEMS, item_id + ".png")).convert("RGBA").resize((size, size))
            sheet.alpha_composite(im, ((i % cols) * size, (i // cols) * size))
        sheet.save(sheet_path)


if __name__ == "__main__":
    main()
