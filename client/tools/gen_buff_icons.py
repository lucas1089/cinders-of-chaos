#!/usr/bin/env python3
"""Procedural 32x32 icons for the buff bar (client module game_buffbar).

Run: python3 client/tools/gen_buff_icons.py [OUTDIR]
     default OUTDIR: client/overlay/data/images/game/buffs  ->  <name>.png, one per name of ICONS

One icon for every key of the registry (server/data/lib/chaos_buffs.lua): the icon of the entries that name their own
spell / condition art ("spell:..", "cond:..") is the fallback the client draws when that art is not in the sheet it
has, and the "buff:<name>" entries use it as their icon. The drawings are the spell icons' kit (gen_spell_icons.py:
colour themes, glyphs, the dark plate with a themed glow); the client puts a green / gold (buff) or red (debuff)
border around every icon, so the plate's own rim stays quiet. Our own procedural art. The names are checked against
the registry when it is found (a key or a "buff:" icon without a drawing, or a drawing nobody uses, stops the run).
Needs Pillow."""
import os, re, sys
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from gen_spell_icons import render  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(HERE))
DEFAULT_OUT = os.path.join(ROOT, 'client', 'overlay', 'data', 'images', 'game', 'buffs')
REGISTRY = os.path.join(ROOT, 'server', 'data', 'lib', 'chaos_buffs.lua')

ICONS = {  # name: (theme, glyph)
    # the world
    'world_xp': ('holy', 'arrowup'), 'world_loot': ('light', 'ring'), 'world_skill': ('arcane', 'nodes'),
    'victory': ('holy', 'banner'), 'golden_hour': ('light', 'burst'), 'chaos_storm': ('arcane', 'bolt'),
    'calendar_event': ('light', 'gate'), 'event': ('light', 'gate'), 'double_xp': ('light', 'arrowup'),
    # class buffs
    'blood_pact': ('blood', 'drop'), 'red_frenzy': ('blood', 'fang'), 'rally': ('holy', 'banner'),
    'barkskin': ('nature', 'shield'), 'divine_ward': ('holy', 'shield'), 'soul_aegis': ('arcane', 'ring'),
    'phantom_veil': ('shadow', 'ghost'), 'dash': ('light', 'dash'), 'iron_will': ('steel', 'shield'),
    'stealth': ('shadow', 'hood'), 'poison_blades': ('poison', 'daggers'), 'counter': ('steel', 'katana'),
    'bushido': ('steel', 'eye'), 'bloodrage': ('blood', 'greataxe'), 'bone_aura': ('bone', 'banner'),
    'bone_shield': ('bone', 'ribs'), 'focus': ('arcane', 'eye'), 'chi_ward': ('arcane', 'palm'),
    'mantra': ('steel', 'mountain'), 'roll': ('shadow', 'swirl'), 'breath': ('ember', 'flame'),
    'zealotry': ('holy', 'flame'), 'aegis_faith': ('holy', 'shield'),
    # counters and windows
    'trial_stacks': ('blood', 'arrowup'), 'chi': ('arcane', 'fist'), 'rage': ('blood', 'burst'), 'reprisal': ('steel', 'twin'),
    # engine buffs
    'haste': ('light', 'dash'), 'regen': ('nature', 'leaf'), 'fed': ('ember', 'dots'), 'manashield': ('arcane', 'shield'),
    'invisible': ('shadow', 'ghost'), 'light': ('light', 'burst'), 'spellbuff': ('arcane', 'arrowup'),
    # engine debuffs
    'poison': ('poison', 'drop'), 'burning': ('fire', 'flame'), 'energy': ('arcane', 'bolt'), 'bleeding': ('blood', 'drop'),
    'drowning': ('water', 'wave'), 'freezing': ('frost', 'crystal'), 'dazzled': ('holy', 'burst'), 'cursed': ('necrotic', 'skull'),
    'paralyze': ('steel', 'slam'), 'drunk': ('ember', 'swirl'), 'pacified': ('holy', 'ring'), 'muted': ('shadow', 'hood'),
    'infight': ('blood', 'sword'), 'skull_white': ('bone', 'skull'), 'skull_red': ('blood', 'skull'), 'skull_black': ('shadow', 'skull'),
}
# the theme 'fire' is named 'fire' in the kit
from gen_spell_icons import COL  # noqa: E402
assert all(t in COL for t, _g in ICONS.values()), 'unknown theme'


def registry_names():
    """keys and "buff:<name>" icons of the registry, or None when the registry is not found"""
    if not os.path.exists(REGISTRY):
        return None
    text = open(REGISTRY, encoding='utf-8').read()
    keys = set(re.findall(r'^(?:cond|source)\("(\w+)"', text, re.M))
    icons = set(re.findall(r'"buff:(\w+)"', text))
    return keys | icons


def check():
    names = registry_names()
    if names is None:
        return
    mine = set(ICONS)
    if names != mine:
        raise SystemExit('ICONS does not match chaos_buffs.lua: missing %s, unused %s' %
                         (sorted(names - mine), sorted(mine - names)))


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_OUT
    check()
    os.makedirs(out, exist_ok=True)
    for name, (theme, glyph) in sorted(ICONS.items()):
        render(theme, glyph).resize((32, 32), Image.LANCZOS).save(os.path.join(out, name + '.png'), optimize=True)
    print(len(ICONS), 'buff icons written to', out)


if __name__ == '__main__':
    main()
