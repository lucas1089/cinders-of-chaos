#!/usr/bin/env python3
"""Icons of the passive tree's medium and large nodes, taken from the tree's own painted icon atlas.

Run: python3 -I client/tools/gen_keystone_icons.py client/overlay/data/images/passivetree/keystones.png
     python3 -I client/tools/gen_keystone_icons.py --check client/overlay/modules/game_passivetree/treedata/icons.lua
     python3 -I client/tools/gen_keystone_icons.py --lua      (prints the icons.lua entries of NOTABLES)

Every icon here is a cell of data/images/passivetree/skills.png, the atlas the small nodes use. Nothing is drawn and
nothing comes from outside the repository, so the medium and large nodes have the same painted look, light and palette
as the small ones.
 * KEYSTONES (keystone frame, nodes 369, 376, 383, 390, 621, 624 with their per-class variants, 631-664, and the build
   archetype keystones 77, 78, 81, 82, 106-109, 253, 262, 355, 362): one row of
   64x64 cells in keystones.png, in the order below (treedata/icons.lua: x = index * 64). Each cell is the atlas icon
   scaled up once here (Lanczos, a light unsharp mask), so the client does not stretch a 25 px clip to 60 px.
 * START (class section start nodes 625, 635, 645, 655): classstart_<line>.png, 150x150, written next to the sheet:
   the root start node's medallion (PSGroupBackground95.png) scaled down, the class icon set into its centre.
 * NOTABLES (notable and mastery frames: the 27 path notables, the class section notables, 619-623, the masteries
   665-668): no new image; treedata/icons.lua clips them from skills.png like the small nodes. --check verifies those
   clips and the keystone cells; --lua prints the entries.
Each icon is used once, and none of them is used by a small node. Deterministic. Needs Pillow."""
import os, re, sys
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
IMAGES = os.path.join(HERE, '..', 'overlay', 'data', 'images', 'passivetree')
ATLAS = os.path.join(IMAGES, 'skills.png')
MEDALLION = os.path.join(IMAGES, 'PSGroupBackground95.png')
CELL = 64
START_SIZE = 150

# The atlas is two grids of painted icons: block A (y < 270) has 36 columns of exact 27 px cells; block B (from y 270)
# has cells 990 / 37 px apart (37 columns in rows 0-10, 26 in rows 11-35). A cell is named A<row>.<col> or B<row>.<col>.
B_PITCH = 990 / 37


def cell(name):
    """(x, y, w, h) of an atlas cell: the full 27 px cell in block A, the inner 25 px in block B (no neighbour bleed)."""
    m = re.match(r'^([AB])(\d+)\.(\d+)$', name)
    block, row, col = m.group(1), int(m.group(2)), int(m.group(3))
    if block == 'A':
        assert row < 10 and col < 36, name
        return col * 27, row * 27, 27, 27
    assert row < 36 and col < (37 if row < 11 else 26), name
    return round(col * B_PITCH) + 1, round(270 + row * B_PITCH) + 1, 25, 25


KEYSTONES = [  # (icon key in treedata/icons.lua, atlas cell): the order fixes the cell in keystones.png
    ('ksWrath', 'B5.33'),              # 621 for a class without a keystone there: a red burst
    ('ksResolve', 'A2.20'),            # 624 likewise: a warding shield
    ('ksCleavingArc', 'B12.18'),       # Knight, Berserker: crossed axes
    ('ksBulwark', 'B7.26'),            # Knight, Juggernaut: a red tower shield
    ('ksRicochet', 'B2.12'),           # Paladin, Beastmaster: an arrow in flight
    ('ksDeadeye', 'B17.20'),           # Paladin, Deadeye: a red hunter's eye
    ('ksArcaneEcho', 'A4.19'),         # Sorcerer: an arcane spiral
    ('ksOverload', 'B20.25'),          # Sorcerer, Elemental Overload: three element orbs
    ('ksOvergrowth', 'B24.13'),        # Druid: a sprouting seedling
    ('ksThorns', 'B13.21'),            # Druid: a thorned branch
    ('ksSharedPhantasm', 'B10.30'),    # Illusionist: a marking violet eye
    ('ksInspiringIllusion', 'B19.18'), # Illusionist: a figure in a golden aura
    ('ksImmovable', 'B11.11'),         # Juggernaut: an iron helm
    ('ksUndyingRage', 'B1.12'),        # Berserker: a bleeding hand
    ('ksHuntersFocus', 'A5.23'),       # Deadeye: crosshairs on a target
    ('ksPackAlpha', 'B15.12'),         # Beastmaster: a beast
    ('ksLivingShadow', 'B28.15'),      # Ninja: a cloaked shadow
    ('ksWayOfTheBlade', 'B30.19'),     # Samurai: a raised blade
    ('ksHoardedSouls', 'B10.19'),      # Lich: a trapped soul
    ('ksBoneColossus', 'B21.1'),       # Bone Lord: a skull-faced colossus
    ('ksHundredHands', 'B3.14'),       # Shadowfist: a fist in a whirl of blows
    ('ksFlowingMercy', 'B4.24'),       # Iron Sage: a healer's aura
    ('ksDivineVerdict', 'B14.11'),     # Inquisitor: a holy judgement star
    ('ksBastion', 'A7.23'),            # Sentinel: a shield of light
    ('ksBlackbloodCreed', 'B24.12'),   # 383 Thief line: a poison flask
    ('ksGraveCovenant', 'B23.17'),     # 369 Necromancer line: a host of skulls
    ('ksScarredDiscipline', 'B13.24'), # 390 Monk line: a struck body
    ('ksPenitentWrath', 'A6.14'),      # 376 Templar line: twin holy blades
    # the build archetype keystones (2026-10, server archetypes_config.lua; docs/BUILDS.md)
    ('arPyreOath', 'B2.32'),           # 108 a figure wreathed in fire
    ('arSanguine', 'B4.4'),            # 81 a blood-red seal
    ('arThornbound', 'B3.34'),         # 77 a struck shield
    ('arOpenHand', 'B5.18'),           # 109 a clenched red fist
    ('arContagion', 'B2.34'),          # 107 a green venom drop
    ('arCascade', 'B2.25'),            # 78 bursting shards
    ('arStormstring', 'B4.10'),        # 82 a lightning-struck archer
    ('arWinterLattice', 'B5.8'),       # 355 a frost burst
    ('arEffigy', 'B3.10'),             # 262 a golden idol
    ('arCinderSigil', 'B2.35'),        # 106 a burning sigil ring
    ('arAetherEdge', 'B4.12'),         # 362 a blade of blue energy
    ('arReliquary', 'B0.24'),          # 253 a sacred relic
]

START = [  # (line, atlas cell): the start node of each class section
    ('thief', 'A1.12'), ('necromancer', 'B14.0'), ('monk', 'B22.1'), ('templar', 'A0.29'),
]

NOTABLES = [  # (icon key, node, atlas cell)
    # class sections: Thief
    ('ntLightFeet', 626, 'A5.12'), ('ntVenomCraft', 627, 'A9.15'), ('ntShadowBorn', 628, 'A7.4'),
    ('ntTwinFangs', 629, 'A3.16'), ('ntFleetShadow', 630, 'B2.29'), ('ntSteelDiscipline', 632, 'A0.17'),
    ('ntIronParry', 633, 'B6.18'),
    # Necromancer
    ('ntGraveLore', 636, 'B26.0'), ('ntBoneCraft', 637, 'B13.25'), ('ntDarkPact', 638, 'A5.30'),
    ('ntSpreadingBlight', 639, 'B23.20'), ('ntLingeringRot', 640, 'A7.9'), ('ntLegion', 642, 'B23.14'),
    ('ntBannerBearer', 643, 'B21.5'),
    # Monk
    ('ntIronFist', 646, 'A2.4'), ('ntCentered', 647, 'B31.7'), ('ntFlowingChi', 648, 'A3.25'),
    ('ntPreciseStrikes', 649, 'A2.32'), ('ntNerveStrike', 650, 'B3.21'), ('ntHealingHands', 652, 'A2.31'),
    ('ntDeepMantra', 653, 'B30.5'),
    # Templar
    ('ntHolyVigor', 656, 'B19.17'), ('ntShieldOfFaith', 657, 'A0.19'), ('ntRighteousArm', 658, 'A6.15'),
    ('ntSacredFire', 659, 'B14.9'), ('ntBurningZeal', 660, 'B26.20'), ('ntSteadfast', 662, 'A2.19'),
    ('ntSanctuary', 663, 'B7.24'),
    # the masteries of the class sections
    ('msShadowDiscipline', 665, 'A3.14'), ('msGraveMastery', 666, 'B23.16'), ('msInnerDiscipline', 667, 'B31.13'),
    ('msSacredOath', 668, 'B10.0'),
    # the notables next to the keystones 621 and 624
    ('ntGatheringFury', 619, 'A3.1'), ('ntEdgeOfRuin', 620, 'B33.20'), ('ntIronResolve', 622, 'A2.5'),
    ('ntUnbrokenWill', 623, 'B12.7'),
    # the path notables
    ('ntRedHarvest', 135, 'B2.13'), ('ntWitchfireGaze', 138, 'B17.19'), ('ntPyreLitany', 153, 'B1.2'),
    ('ntIronCommunion', 161, 'B7.25'), ('ntUndertow', 210, 'A4.2'), ('ntFrostbittenWill', 219, 'B1.34'),
    ('ntThunderbrand', 246, 'A8.28'), ('ntScarredHide', 260, 'A0.15'), ('ntCrimsonParry', 276, 'A6.3'),
    ('ntHeadsmansMark', 290, 'A1.29'), ('ntHawksMalice', 297, 'B11.21'), ('ntAshenBulwark', 319, 'B9.34'),
    ('ntRimeLitany', 335, 'A8.29'), ('ntMercyOfEmbers', 358, 'A0.7'), ('ntNightshadeDraught', 381, 'B24.10'),
    ('ntCinderVein', 393, 'A8.27'), ('ntMarrowgrinder', 412, 'B1.13'), ('ntStormboundNerves', 430, 'B9.8'),
    ('ntRotrootVenom', 449, 'A7.24'), ('ntGravecoldWhisper', 468, 'B14.1'), ('ntDrownedLungs', 487, 'A2.9'),
    ('ntHoarfrostMantle', 507, 'B23.25'), ('ntBloodwardCommunion', 526, 'B1.29'), ('ntLitanyOfAsh', 545, 'A6.16'),
    ('ntBloodthirstRite', 563, 'B29.0'), ('ntVoidglassFocus', 583, 'B2.4'), ('ntBlackTide', 603, 'B7.30'),
]


def all_cells():
    return [c for _, c in KEYSTONES] + [c for _, c in START] + [c for _, _, c in NOTABLES]


def crop(atlas, name):
    x, y, w, h = cell(name)
    return atlas.crop((x, y, x + w, y + h))


def upscale(icon, size):
    return icon.resize((size, size), Image.LANCZOS).filter(ImageFilter.UnsharpMask(radius=1.2, percent=60,
                                                                                     threshold=2))


def start_image(atlas, name):
    medal = Image.open(MEDALLION).convert('RGBA')
    mw, mh = medal.size  # 245 x 235, the inner disc centred at (122.5, 117.5), radius about 62
    k = START_SIZE / mw
    medal = medal.resize((START_SIZE, round(mh * k)), Image.LANCZOS)
    out = Image.new('RGBA', (START_SIZE, START_SIZE), (0, 0, 0, 0))
    top = (START_SIZE - medal.size[1]) // 2
    out.alpha_composite(medal, (0, top))
    r = 40
    cx, cy = START_SIZE / 2, top + 117.5 * k
    icon = upscale(crop(atlas, name), 2 * r)
    mask = Image.new('L', (8 * r, 8 * r), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, 8 * r - 1, 8 * r - 1), fill=255)
    icon.putalpha(mask.resize((2 * r, 2 * r), Image.LANCZOS))
    out.alpha_composite(icon, (round(cx - r), round(cy - r)))
    # a dark seam where the icon meets the medallion's ring
    ImageDraw.Draw(out).ellipse((cx - r, cy - r, cx + r, cy + r), outline=(40, 28, 16, 200), width=2)
    return out


def lua_entries():
    return ['\t\t%s = {x = %d, y = %d, w = %d, h = %d}, -- node %d, atlas cell %s' % ((key,) + cell(c) + (node, c))
            for key, node, c in NOTABLES]


def check(icons_lua):
    """icons.lua must clip every notable key as NOTABLES says and put every keystone at its cell of the sheet."""
    text = open(icons_lua, encoding='utf-8').read()
    errors = []
    for key, node, c in NOTABLES:
        m = re.search(r'\b%s = \{([^}]*)\}' % key, text)
        want = dict(zip('xywh', cell(c)))
        got = dict((k, int(v)) for k, v in re.findall(r'\b([xywh]) = (\d+)', m.group(1))) if m else None
        if got != want:
            errors.append('%s (node %d): icons.lua has %s, the atlas cell %s is %s' % (key, node, got, c, want))
    for i, (key, _) in enumerate(KEYSTONES):
        m = re.search(r'\b%s = \{([^}]*)\}' % key, text)
        if not m or 'x = %d,' % (i * CELL) not in m.group(1) or '/images/passivetree/keystones' not in m.group(1):
            errors.append('%s: not at x = %d of keystones.png in icons.lua' % (key, i * CELL))
    return errors


def main(argv):
    used = all_cells()
    dupes = sorted(set(c for c in used if used.count(c) > 1))
    assert not dupes, 'atlas cells used twice: %s' % dupes
    if argv[:1] == ['--lua']:
        print('\n'.join(lua_entries()))
        return 0
    if argv[:1] == ['--check']:
        errors = check(argv[1])
        for e in errors:
            print(e)
        print('%d keystone and %d notable icons checked, %d errors' % (len(KEYSTONES), len(NOTABLES), len(errors)))
        return 1 if errors else 0
    out = argv[0]
    atlas = Image.open(ATLAS).convert('RGBA')
    sheet = Image.new('RGBA', (CELL * len(KEYSTONES), CELL), (0, 0, 0, 0))
    for i, (_, c) in enumerate(KEYSTONES):
        sheet.alpha_composite(upscale(crop(atlas, c), CELL), (i * CELL, 0))
    sheet.save(out)
    print(len(KEYSTONES), 'keystone icons written to', out)
    folder = os.path.dirname(os.path.abspath(out))
    for line, c in START:
        start_image(atlas, c).save(os.path.join(folder, 'classstart_%s.png' % line))
    print(len(START), 'class start images written next to it')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
