#!/usr/bin/env python3
"""Pair 36: every effect of the purchased effect packs as magic effects and missiles of the client pair, and the
pack art in place of our own procedural effects (owner 2026-10-22: "Use as spells, level up e loot beams", "use
everything").

    python3 -I gen_pack36_fx.py build --src DIR [--src DIR ...]    # cut the strips, write the specs and tables
    python3 -I gen_pack36_fx.py build --src DIR ... --check        # rebuild in memory, compare with the repo and the disk
    python3 -I gen_pack36_fx.py build --check                      # CI, no packs: the committed tables agree
    python3 -I gen_pack36_fx.py inventory --src DIR ...            # every effect found, with its size (no writes)

The packs (docs/CREDITS.md; their files are never in git): each --src is a folder that holds the unzipped packs in
any sub folders. Two layouts are read:
  * `metadata.json` packs (one sheet per effect, all layers combined in the `all` sheet, `oblique/32` frames, the
    anchor tile is the tile the effect is sent to): the four families of the 500 tile-grid set (tile spells,
    fields, area skills, cones; the cone sheets are split over two archives, any --src may hold them), the 500
    effect set and the spellcraft set. 32 px art, used 1:1.
  * `catalog.json` packs (sheets/64px/<category>/<effect>/<variant>/<effect>_<variant>.json; the stages start, loop
    and end in order; the `full` sheet, else the layers merged as gen_pack27_fx.load merges them): spells and
    impacts, circles, auras and buffs, fields and traps, projectiles and the game feel set. Only their 64 px renders
    exist: each frame is halved (premultiplied 2 x 2 box mean, alpha cut with the 4x4 Bayer dither of
    gen_pack27_fx.clean_alpha) and placed by its halved pivot like gen_pack27_fx (feet point or tile centre).
  * the loot beam strips (`*_loot_beam_strip24.png`, 24 frames of 64 x 128): halved to 32 x 64, the bottom tile on
    the item's tile.

What is imported (art_import/pack36_<group>.csv, the specs of import_fx_art.py, chained in GROUPS order):
  replace  our procedural effects and missiles of gen_effects.py (fx_custom.csv) rebuilt AT THEIR IDS with the pack
           art that fits (REPLACE / REPLACE_MISSILE below), so every script, monster and engine hit keeps its id;
           import_fx_art.py --replace. The always-drawn combat set 415..423 and the reflect bubble 628 included.
  missiles every projectile of the projectile set no replacement took, then the 500 set's until MAX_MISSILE
           (missiles are uint8 on the wire: 189..MAX_MISSILE)
  tile, field, area, cone   the tile-grid set, every effect (a directional one: eight effects <name>_<dir>)
  mega, impact, circle, aura, trap, ui, beam   every other effect, one colour variant each (the first one no
           earlier pair imported), directional ones as eight effects. The spellcraft set is in the pair since the first
           import (chaos_vfx.lua: arcane_orbit, dawn_aegis, ...), so it only lends art to the replacements here.
An effect of a looping set (auras, fields, statuses) plays its frames once and its last FADE frames dissolve.
Names: a group prefix and the pack's id (`tile_cinder_burst`, `cone_bilious_belch_e`, `mega_alembic_orbit`, ...);
the Lua names (server/data/lib/chaos_pack36_fx_ids.lua) merge into ChaosVfx / ChaosVfxMissile like every pack.

Licence (the same author's terms for every set but the loot beams; docs/CREDITS.md): use in games, modified or not,
no attribution; no resale, redistribution or sharing of the assets, even modified; never machine-learning training
data. So nothing cut here is committed: art_import/pack36_fx/ is ignored by git; committed are only this script, the
specs (names, sizes, offsets, frame counts), pack36_fx.sums (sha256 of each strip's decoded pixels) and
pack36_fx_sources.csv (name, pack, source effect/variant). The script reads the packs' frames, alpha boxes and
metadata only to place them; it never samples a palette or a style.
Deterministic: no randomness; Pillow 12.3.0 and numpy 2.5.3 (the CI pins).
"""
import argparse
import csv
import glob
import hashlib
import io
import json
import os
import sys
from collections import namedtuple

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_pack27_fx as G  # noqa: E402

ART = os.path.join(HERE, 'art_import')
OUT = os.path.join(ART, 'pack36_fx')
SUMS = os.path.join(ART, 'pack36_fx.sums')
SOURCES = os.path.join(ART, 'pack36_fx_sources.csv')
GITIGNORE_TEXT = ('# strips cut from the purchased effect packs: not to be redistributed, never committed '
                  '(gen_pack36_fx.py)\n*\n!.gitignore\n')
GROUPS = ['replace', 'missiles', 'tile', 'field', 'area', 'cone', 'mega', 'impact', 'circle', 'aura',
          'trap', 'ui', 'beam']
SPEC = {g: os.path.join(ART, f'pack36_{g}.csv') for g in GROUPS}
FIRST_MISSILE = 189          # pair 35 has 188 missiles
MAX_MISSILE = 250            # uint8 on the wire; a few ids stay free
MAX_TILES = 9                # cones reach 7 tiles from the caster
MAX_MISSILE_TILES = 3
FADE = 3
JOBS = max(1, min(4, os.cpu_count() or 1))     # worker processes (the result does not depend on it)
DIRS8 = G.DIRS8              # sheet rows: E SE S SW W NW N NE
OUR_DIRS = G.OUR_DIRS
LICENCE = ('purchased; use in games, modified or not, credit not required; no resale, redistribution or sharing of '
           'the assets, even modified; never machine-learning training data; author: docs/CREDITS.md')
LICENCE_MEGA = LICENCE + '; never a style reference or AI input'
LICENCE_BEAMS = ('purchased; use in games, modified or recoloured; no resale or sharing of the raw files; never AI '
                 'training data; credit appreciated; studio: docs/CREDITS.md')
# pack key -> the docs/CREDITS.md entry it is credited under
PACK_NAME = {'grid_tile_spells': 'Grid Magic 500', 'grid_fields': 'Grid Magic 500', 'grid_area_skills': 'Grid Magic 500',
             'grid_cones': 'Grid Magic 500', 'mega': 'Mega VFX 500', 'spellcraft': 'Pixel Spellcraft VFX',
             'impacts': 'Magic VFX Spells & Impacts', 'circles': 'Magic VFX Spells & Impacts',
             'auras': 'Auras & Buffs', 'traps': 'Fields & Traps', 'projectiles': 'Projectiles', 'ui': 'UI Game Feel',
             'beams': 'MutterPixel Studio animated VFX'}
# group -> (pack keys, name prefix)
GROUP_PACKS = {'tile': (['grid_tile_spells'], 'tile_'), 'field': (['grid_fields'], 'gfield_'),
               'area': (['grid_area_skills'], 'area_'), 'cone': (['grid_cones'], 'cone_'),
               'mega': (['mega'], 'mega_'), 'impact': (['impacts'], 'w_'),
               'circle': (['circles'], 'w_'), 'aura': (['auras'], 'w_'), 'trap': (['traps'], 'w_'),
               'ui': (['ui'], 'w_'), 'beam': (['beams'], 'beam_')}
EARLIER_SOURCES = ['pack27_sources.csv', 'pack29_sources.csv']     # (effect, variant) already in the pair

# --------------------------------------------------------------------------------------------- in-place replacements
# our id -> (pack, effect id, variant or '', note). The procedural effects of gen_effects.py (fx_custom.csv) that a
# pack effect matches by element and shape: area effects (shown on every tile of an area) by a one-tile stamp of the
# tile-grid set, single ones by a burst, circle or status of the same theme.
REPLACE = {
    1: ('grid_tile_spells', 'hemorrhage', '', 'bleeding hit'),
    2: ('grid_tile_spells', 'water_splash', '', 'drown / water hit'),
    3: ('ui', 'fx_smoke_poof', 'ink', 'puff of smoke'),
    4: ('impacts', 'impact_block', 'steel', 'blocked hit'),
    5: ('grid_tile_spells', 'blast_ring', '', 'explosion area'),
    6: ('grid_tile_spells', 'cinder_burst', '', 'explosion hit'),
    7: ('grid_tile_spells', 'ember_rain', '', 'fire area'),
    8: ('grid_tile_spells', 'sanctified_ring', '', 'yellow rings'),
    9: ('grid_tile_spells', 'toxic_puff', '', 'green rings'),
    10: ('grid_tile_spells', 'crimson_rend', '', 'physical area hit'),
    11: ('ui', 'fx_teleport_in', 'arcane', 'teleport'),
    12: ('grid_tile_spells', 'spark_burst', '', 'energy hit'),
    13: ('grid_tile_spells', 'arcane_cross', '', 'blue magic'),
    14: ('grid_tile_spells', 'blood_bloom', '', 'red magic'),
    15: ('spellcraft', 'healing_bloom', '', 'green magic (healing)'),
    16: ('grid_tile_spells', 'napalm_splash', '', 'hit by fire'),
    17: ('grid_tile_spells', 'acid_splash', '', 'hit by poison'),
    18: ('grid_tile_spells', 'skull_burst', '', 'death area'),
    19: ('ui', 'fx_note_burst', 'lavender', 'green notes'),
    20: ('ui', 'fx_note_burst', 'sakura', 'red notes'),
    21: ('grid_tile_spells', 'venom_spikes', '', 'poison area'),
    22: ('ui', 'fx_note_burst', 'gold', 'yellow notes'),
    23: ('ui', 'fx_note_burst', 'lavender', 'purple notes'),
    24: ('ui', 'fx_note_burst', 'lavender', 'blue notes'),
    25: ('ui', 'fx_note_burst', 'gold', 'white notes'),
    26: ('grid_tile_spells', 'bubble_barrage', '', 'bubbles'),
    32: ('spellcraft', 'stunned', '', 'stun'),
    33: ('spellcraft', 'asleep', '', 'sleep'),
    35: ('grid_tile_spells', 'quake_crack', '', 'groundshaker'),
    37: ('grid_tile_spells', 'fire_pillar', '', 'fire attack'),
    38: ('grid_tile_spells', 'arc_strike', '', 'energy area'),
    39: ('grid_tile_spells', 'soul_drain', '', 'small clouds (death)'),
    40: ('grid_tile_spells', 'radiant_burst', '', 'holy damage'),
    41: ('grid_tile_spells', 'thunder_crash', '', 'big clouds (energy)'),
    42: ('grid_tile_spells', 'frost_shard_burst', '', 'ice area'),
    43: ('grid_tile_spells', 'blizzard_gust', '', 'ice tornado'),
    44: ('grid_tile_spells', 'ice_spike', '', 'ice attack'),
    45: ('grid_tile_spells', 'rock_shrapnel', '', 'stones'),
    46: ('grid_tile_spells', 'root_snare', '', 'small plants'),
    47: ('grid_tile_spells', 'snapjaw_trap', '', 'carniphila'),
    48: ('grid_tile_spells', 'void_rift', '', 'purple energy'),
    49: ('grid_tile_spells', 'tesla_spikes', '', 'yellow energy'),
    50: ('grid_tile_spells', 'holy_smite', '', 'holy area'),
    51: ('grid_tile_spells', 'thorn_eruption', '', 'big plants'),
    53: ('grid_tile_spells', 'ice_tomb_shatter', '', 'giant ice'),
    54: ('grid_tile_spells', 'geyser_burst', '', 'water splash'),
    158: ('grid_tile_spells', 'shadow_tendrils', '', 'black smoke'),
    167: ('grid_tile_spells', 'blood_rain', '', 'red smoke'),
    173: ('impacts', 'impact_critical_hit', 'gold', 'critical damage (no word: owner 2026-10-17, the animation, not the word)'),
    182: ('grid_tile_spells', 'stone_spikes', '', 'earth (182)'),
    183: ('grid_tile_spells', 'mud_splash', '', 'earth (183)'),
    185: ('spellcraft', 'regenerating', '', 'healing (185)'),
    187: ('grid_tile_spells', 'hex_bloom', '', 'bewitched'),
    200: ('grid_tile_spells', 'magma_geyser', '', 'fire (200)'),
    201: ('grid_tile_spells', 'divine_spears', '', 'holy (201)'),
    202: ('grid_tile_spells', 'frost_ring', '', 'frost (202)'),
    203: ('grid_tile_spells', 'bone_spikes', '', 'death (203)'),
    204: ('grid_tile_spells', 'plasma_pop', '', 'energy (204)'),
    205: ('grid_tile_spells', 'hail_strike', '', 'frost (205)'),
    213: ('grid_tile_spells', 'scorch_glyph', '', 'fire (213)'),
    215: ('grid_tile_spells', 'permafrost_stomp', '', 'frost (215)'),
    216: ('grid_tile_spells', 'flare_mine', '', 'fire (216)'),
    217: ('grid_tile_spells', 'ion_vortex', '', 'energy (217)'),
    218: ('grid_tile_spells', 'death_pentacle', '', 'death (218)'),
    219: ('grid_tile_spells', 'thunderball_bounce', '', 'energy (219)'),
    220: ('grid_tile_spells', 'grave_claw', '', 'death (220)'),
    221: ('grid_tile_spells', 'magma_bloom', '', 'fire (221)'),
    222: ('grid_tile_spells', 'hex_brand', '', 'death (222)'),
    223: ('grid_tile_spells', 'blood_geyser', '', 'blood (223)'),
    224: ('grid_tile_spells', 'judgement_seal', '', 'holy (224)'),
    225: ('grid_tile_spells', 'purging_flame', '', 'holy (225)'),
    226: ('grid_tile_spells', 'firebird_dive', '', 'fire (226)'),
    244: ('grid_tile_spells', 'rune_detonation', '', 'arcane (244)'),
    246: ('grid_tile_spells', 'emp_pulse', '', 'energy (246)'),
    248: ('grid_tile_spells', 'blast_ring', '', 'fire (248)'),
    262: ('grid_tile_spells', 'angel_feathers', '', 'holy (262)'),
    264: ('grid_tile_spells', 'halo_crush', '', 'holy (264)'),
    288: ('grid_tile_spells', 'mana_shatter', '', 'arcane (288)'),
    291: ('grid_tile_spells', 'arcane_impact', '', 'arcane (291)'),
    309: ('grid_tile_spells', 'glyph_cascade', '', 'arcane (309)'),
    312: ('grid_tile_spells', 'arcane_orbits', '', 'arcane (312)'),
    359: ('grid_tile_spells', 'shiver_mirror', '', 'frost (359)'),
    367: ('grid_tile_spells', 'crystal_spire', '', 'earth (367)'),
    372: ('grid_tile_spells', 'blast_ring', '', 'fire_nova'),
    373: ('grid_tile_spells', 'cinder_burst', '', 'fire_explosion'),
    374: ('grid_tile_spells', 'cyclone_spin', '', 'fire_tornado'),
    375: ('grid_tile_spells', 'napalm_splash', '', 'fire_burst'),
    376: ('grid_tile_spells', 'skyfall_comet', '', 'meteor_strike'),
    377: ('grid_tile_spells', 'magma_bloom', '', 'inferno_burst'),
    378: ('grid_tile_spells', 'scorch_glyph', '', 'fire_ring'),
    379: ('grid_tile_spells', 'frost_shard_burst', '', 'frost_burst'),
    380: ('grid_tile_spells', 'frost_ring', '', 'frost_nova'),
    381: ('grid_tile_spells', 'ice_spike', '', 'ice_spikes'),
    382: ('spellcraft', 'ice_shatter', '', 'ice_crystal'),
    383: ('grid_tile_spells', 'permafrost_stomp', '', 'frost_ripple'),
    384: ('grid_tile_spells', 'arc_strike', '', 'chain_lightning'),
    385: ('grid_tile_spells', 'ion_vortex', '', 'lightning_violet'),
    386: ('spellcraft', 'lightning_strike', '', 'lightning_strike'),
    387: ('grid_tile_spells', 'spark_burst', '', 'lightning_zap'),
    388: ('spellcraft', 'blood_pact', '', 'blood_rune'),
    389: ('grid_tile_spells', 'blood_spikes', '', 'blood_ring'),
    390: ('grid_tile_spells', 'hemorrhage', '', 'blood_splash'),
    391: ('grid_tile_spells', 'crimson_rend', '', 'blood_slash'),
    392: ('grid_tile_spells', 'blood_bloom', '', 'blood_nova'),
    393: ('grid_tile_spells', 'shade_needles', '', 'shadow_smoke'),
    394: ('grid_tile_spells', 'nightfall_veil', '', 'shadow_cloud'),
    395: ('grid_tile_spells', 'shadow_tendrils', '', 'shadow_ring'),
    396: ('spellcraft', 'void_maw', '', 'void_eye'),
    397: ('grid_tile_spells', 'skull_burst', '', 'necro_skull'),
    398: ('grid_tile_spells', 'eclipse_drop', '', 'shadow_flame'),
    399: ('spellcraft', 'plague_mist', '', 'poison_pentagram'),
    400: ('grid_tile_spells', 'bubbling_bog', '', 'poison_ring'),
    401: ('grid_tile_spells', 'blister_pustules', '', 'poison_flame'),
    402: ('grid_tile_spells', 'spore_burst', '', 'poison_burst'),
    403: ('grid_tile_spells', 'holy_smite', '', 'holy_smite'),
    404: ('spellcraft', 'holy_seal', '', 'holy_cross'),
    405: ('grid_tile_spells', 'judgement_pillar', '', 'holy_spiral'),
    406: ('grid_tile_spells', 'clockwork_sigil', '', 'arcane_circle'),
    407: ('grid_tile_spells', 'hex_bloom', '', 'arcane_aura'),
    408: ('grid_tile_spells', 'arcane_cross', '', 'arcane_burst'),
    409: ('ui', 'fx_portal', 'arcane', 'summon_portal'),
    410: ('grid_tile_spells', 'void_rift', '', 'summon_vortex'),
    411: ('spellcraft', 'healing_bloom', '', 'heal_hearts'),
    412: ('spellcraft', 'regenerating', '', 'heal_sparkle'),
    413: ('grid_tile_spells', 'tremor_quake', '', 'ground_slam'),
    414: ('grid_tile_spells', 'concussion_ring', '', 'shockwave'),
    415: ('impacts', 'impact_critical_hit', 'blood', 'crit_burst: critical hit (no word, as 173)'),
    416: ('ui', 'fx_smoke_poof', 'holy', 'dodge_whoosh: dodge, also Mistborne Step (no word)'),
    417: ('impacts', 'impact_parry', 'steel', 'reflect_aegis: reflect, also a shield buff fallback (no word)'),
    418: ('grid_tile_spells', 'cinder_burst', '', 'imbue_fire'),
    419: ('grid_tile_spells', 'frost_shard_burst', '', 'imbue_ice'),
    420: ('grid_tile_spells', 'spark_burst', '', 'imbue_energy'),
    421: ('grid_tile_spells', 'stone_spikes', '', 'imbue_earth'),
    422: ('grid_tile_spells', 'skull_burst', '', 'imbue_death'),
    423: ('grid_tile_spells', 'radiant_burst', '', 'imbue_holy'),
    424: ('beams', 'green_nature', '', 'loot_ray_unique'),
    425: ('beams', 'legendary', '', 'loot_ray_legendary'),
    426: ('beams', 'mythic', '', 'loot_ray_mythic'),
    427: ('beams', 'silver_metal', '', 'loot_ray_divine'),
    428: ('beams', 'rainbow_prismatic', '', 'loot_ray_cosmic'),
    628: ('impacts', 'impact_block', 'sapphire', 'reflect_bubble (628): the reflect flash (no word)'),
}
# our missile id -> (pack, effect id, variant or '', note)
REPLACE_MISSILE = {
    4: ('projectiles', 'proj_fireball', 'fire', 'fire'),
    5: ('projectiles', 'proj_lightning_bolt', 'storm', 'energy'),
    11: ('projectiles', 'proj_shadow_bolt', 'shadow', 'death'),
    12: ('projectiles', 'proj_boulder', 'earth', 'large rock'),
    13: ('projectiles', 'proj_frost_shard', 'crystal', 'snowball'),
    15: ('projectiles', 'proj_venom_glob', 'poison', 'poison'),
    25: ('projectiles', 'proj_throwing_axe', 'steel', 'whirlwind sword'),
    28: ('projectiles', 'proj_spear', 'holy', 'ethereal spear'),
    29: ('projectiles', 'proj_ice_lance', 'frost', 'ice'),
    30: ('projectiles', 'proj_stone_shard', 'earth', 'earth'),
    31: ('projectiles', 'proj_holy_spear', 'holy', 'holy'),
    32: ('projectiles', 'proj_soul_skull', 'necrotic', 'sudden death'),
    33: ('projectiles', 'proj_arrow', 'steel', 'flash arrow'),
    36: ('projectiles', 'proj_ball_lightning', 'storm', 'energy ball'),
    37: ('projectiles', 'proj_frost_shard', 'frost', 'small ice'),
    38: ('projectiles', 'proj_holy_orb', 'holy', 'small holy'),
    39: ('projectiles', 'proj_stone_shard', 'crystal', 'small earth'),
    41: ('projectiles', 'proj_fireball', 'hellfire', 'explosion'),
    56: ('projectiles', 'proj_ice_lance', 'crystal', 'frost (56)'),
    57: ('projectiles', 'proj_holy_orb', 'radiant', 'holy (57)'),
    60: ('projectiles', 'proj_water_bolt', 'water', 'water (60)'),
    84: ('projectiles', 'proj_arcane_missile', 'arcane', 'arcane (84)'),
    85: ('projectiles', 'proj_arcane_missile', 'lavender', 'arcane'),
    86: ('projectiles', 'proj_arcane_missile', 'void', 'arcane (86)'),
    104: ('projectiles', 'proj_energy_disc', 'arcane', 'arcane (104)'),
    116: ('projectiles', 'proj_fireball', 'spirit', 'fire_bolt'),
    117: ('projectiles', 'proj_flame_lance', 'fire', 'fire_streak'),
    118: ('projectiles', 'proj_ice_lance', 'frost', 'ice_shard'),
    119: ('projectiles', 'proj_void_orb', 'void', 'arcane_orb'),
    120: ('projectiles', 'proj_shadow_bolt', 'void', 'shadow_bolt'),
    121: ('projectiles', 'proj_holy_spear', 'radiant', 'holy_bolt'),
    122: ('projectiles', 'proj_blood_spike', 'blood', 'blood_spear'),
    123: ('projectiles', 'proj_lightning_bolt', 'thunder', 'lightning_orb'),
    124: ('projectiles', 'proj_poison_dart', 'poison', 'poison_dart'),
    125: ('projectiles', 'proj_soul_skull', 'hellfire', 'skull_orb'),
}

Src = namedtuple('Src', 'pack eid var meta root fmt')


# -------------------------------------------------------------------------------------------------------- the packs
def discover(srcs):
    """-> {pack key: [Src]} of every effect (all variants) found under the --src folders"""
    found = {}
    seen = set()
    for s in srcs:
        for p in sorted(glob.glob(os.path.join(s, '**', 'metadata.json'), recursive=True)):
            d = json.load(open(p))
            root = os.path.dirname(p)
            if 'family' in d:
                key = 'grid_' + d['family']
            elif 'topdown' in d.get('projections', []):
                key = 'spellcraft'
            else:
                key = 'mega'
            for e in d['effects']:
                if (key, e['id']) in seen:
                    continue
                if 'oblique/32' not in e['variants']:
                    continue
                seen.add((key, e['id']))
                found.setdefault(key, []).append(Src(key, e['id'], '', e, root, 'meta'))
        for p in sorted(glob.glob(os.path.join(s, '**', 'catalog.json'), recursive=True)):
            root = os.path.dirname(p)
            cats = {os.path.basename(c) for c in glob.glob(os.path.join(root, 'sheets', '64px', '*'))}
            for e in json.load(open(p)):
                key = catalog_pack(e['category'], cats)
                if key is None:
                    continue
                for v in e['variants']:
                    j = os.path.join(root, 'sheets', '64px', e['category'], e['id'], v, f"{e['id']}_{v}.json")
                    if not os.path.exists(j) or (key, e['id'], v) in seen:
                        continue
                    seen.add((key, e['id'], v))
                    found.setdefault(key, []).append(Src(key, e['id'], v, e, j, 'catalog'))
        for p in sorted(glob.glob(os.path.join(s, '**', '*_loot_beam_strip24.png'), recursive=True)):
            eid = os.path.basename(p)[:-len('_loot_beam_strip24.png')]
            if ('beams', eid) not in seen:
                seen.add(('beams', eid))
                found.setdefault('beams', []).append(Src('beams', eid, '', {}, p, 'beam'))
    return found


def catalog_pack(cat, cats):
    if cat == 'projectiles':
        return 'projectiles'
    if cat in ('fields', 'environment'):
        return 'traps'
    if cat in ('auras', 'status'):
        return 'auras'
    if cat == 'impacts':
        return 'impacts' if 'impacts' in cats else None
    if cat == 'circles':
        return 'circles' if 'circles' in cats else None
    if cat in ('fx', 'markers', 'text'):
        return 'ui'
    return None


def halve(fr):
    """64 px art -> 32 px: premultiplied 2 x 2 box mean, then the alpha made clean (0 / 255, Bayer dither)"""
    a = fr.astype(np.float64) / 255.0
    h, w = a.shape[0] // 2 * 2, a.shape[1] // 2 * 2
    a = a[:h, :w]
    al = a[:, :, 3:4]
    pm = np.concatenate([a[:, :, :3] * al, al], 2)
    m = (pm[0::2, 0::2] + pm[1::2, 0::2] + pm[0::2, 1::2] + pm[1::2, 1::2]) / 4.0
    am = m[:, :, 3:4]
    rgb = np.where(am > 0, m[:, :, :3] / np.maximum(am, 1e-9), 0)
    out = np.clip(np.round(np.concatenate([rgb, am], 2) * 255), 0, 255).astype(np.uint8)
    return G.clean_alpha(out)


def locate(src, rel):
    """a sheet of a metadata pack: beside its metadata.json, else in a sibling archive of the same family"""
    p = os.path.join(src.root, rel)
    if os.path.exists(p):
        return p
    fam = os.path.basename(src.root)
    for q in sorted(glob.glob(os.path.join(os.path.dirname(os.path.dirname(src.root)), '*', fam, rel))):
        return q
    raise SystemExit(f'{src.pack}/{src.eid}: sheet {rel} not found')


def load(src):
    """-> (rows {row: [frames]}, anchor px, point px, ms, loop, directional)"""
    if src.fmt == 'meta':
        e = src.meta
        v = e['variants']['oblique/32']
        img = np.asarray(Image.open(locate(src, v['files']['all'])).convert('RGBA'))
        fw, fh = v['frame_w'], v['frame_h']
        nrow = v['rows']
        assert img.shape[0] == fh * nrow and img.shape[1] % fw == 0, (src.eid, img.shape)
        rows = {r: [G.clean_alpha(img[r * fh:(r + 1) * fh, i * fw:(i + 1) * fw])
                    for i in range(img.shape[1] // fw)] for r in range(nrow)}
        ax, ay = v['anchor_tile']
        directional = bool(e.get('directions')) and nrow == 8
        return rows, (ax * 32, ay * 32), (0, 0), int(round(1000 / e['fps'])), bool(e.get('loop')), directional
    if src.fmt == 'beam':
        img = np.asarray(Image.open(src.root).convert('RGBA'))
        fw = img.shape[1] // 24
        frames = [halve(img[:, i * fw:(i + 1) * fw]) for i in range(24)]
        h = frames[0].shape[0]
        return {0: frames}, (0, h - 32), (0, 0), 70, True, False
    d = json.load(open(src.root))
    base = os.path.dirname(src.root)
    assert d['tile_size'] == 64, src.root
    fw, fh = d['frame_width'], d['frame_height']
    sheets = d['sheets']
    staged = isinstance(next(iter(sheets.values())), dict)
    parts = [sheets[k] for k in ('start', 'loop', 'end') if k in sheets] if staged else [sheets]
    nrow = len(d.get('directions') or []) or 1
    rows = {r: [] for r in range(nrow)}
    for p in parts:
        if 'full' in p and os.path.exists(os.path.join(base, p['full'])):
            layers = ['full']
        else:
            layers = [ln for ln in d['layers'] if ln in p]
        merged = None
        for ln in layers:
            a = np.asarray(Image.open(os.path.join(base, p[ln])).convert('RGBA'))
            if merged is None:
                merged = np.zeros_like(a)
            merged = G.over(merged, a, G.BACK_ALPHA if (ln == 'back' and 'front' in layers) else 1.0)
        assert merged.shape[0] == fh * nrow and merged.shape[1] % fw == 0, (src.root, merged.shape)
        for r in range(nrow):
            for i in range(merged.shape[1] // fw):
                rows[r].append(halve(merged[r * fh:(r + 1) * fh, i * fw:(i + 1) * fw]))
    piv = (int(round(d['pivot'][0] / 2)), int(round(d['pivot'][1] / 2)))
    ax, ay = d['anchor_tile']
    if src.meta.get('category') == 'projectiles':
        point = G.MISSILE_CENTRE
    elif piv == (ax * 32 + 16, ay * 32 + 16):
        point = G.TILE_CENTRE
    else:
        point = G.FEET
    return rows, piv, point, int(round(1000 / d['fps'])), bool(d.get('loop')), nrow == 8


# ---------------------------------------------------------------------------------------------------------- cutting
def trim(frames):
    frames = [f for f in frames]
    while frames and not frames[-1][:, :, 3].any():
        frames.pop()
    while frames and not frames[0][:, :, 3].any():
        frames.pop(0)
    return [f for f in frames if f[:, :, 3].any()]       # an empty frame inside a flicker is dropped


def effect_strip(name, frames, anchor, point, loop, max_tiles=MAX_TILES):
    frames = trim(frames)
    assert frames, (name, 'no art')
    if loop and len(frames) > FADE + 2:
        for j in range(FADE):
            k = len(frames) - FADE + j
            frames[k] = G.dissolve(frames[k], (FADE - j) / (FADE + 1))
        frames = trim(frames)
    left, top, right, bottom = G.bbox_tiles(frames, anchor, point)
    w, h = left + 1 + right, top + 1 + bottom
    if w > max_tiles or h > max_tiles:
        return None
    n = len(frames) + 1
    strip = np.zeros((h * 32, w * 32 * n, 4), np.uint8)
    for i, f in enumerate(frames):
        strip[:, i * w * 32:(i + 1) * w * 32] = G.place(f, anchor, point, left, top, w, h, name)
    return strip, w, h, n, right, bottom


def missile_strip(name, rows, anchor, point):
    pats = {}
    for pat, d in G.MISSILE_DIR.items():
        pats[pat] = trim(rows[DIRS8.index(d)])
    n = min(len(v) for v in pats.values())
    pats = {k: v[:n] for k, v in pats.items()}
    left, top, right, bottom = G.bbox_tiles([f for v in pats.values() for f in v], anchor, point)
    w, h = left + 1 + right, top + 1 + bottom
    if w > MAX_MISSILE_TILES or h > MAX_MISSILE_TILES or n == 0:
        return None
    W, H = w * 32, h * 32
    strip = np.zeros((3 * H, 3 * W * n, 4), np.uint8)
    for (x, y), fr in pats.items():
        for f, img in enumerate(fr):
            x0 = (x * n + f) * W
            strip[y * H:(y + 1) * H, x0:x0 + W] = G.place(img, anchor, point, left, top, w, h, name)
    return strip, w, h, n, right, bottom


REPLACE_MAX_TILES = 4         # an effect rebuilt at our id: at most 4 x 4 tiles
REPLACE_MAX_MISSILE_TILES = 2
# the send offset of a replaced id: the scripts and the engine send these ids at their own tile + this offset (the
# Lua tables that list one with an offset: chaos_pack_fx_ids.lua reflect_bubble); every other replaced id is sent at
# the target tile itself (ChaosFx ids, engine CONST_ME_* / CONST_ANI_*), so its art keeps the bottom-right tile there
REPLACE_OFFSET = {628: (1, 1)}


def anchored(frames, anchor, point, dx, dy, max_tiles, name):
    """frames placed with a FIXED send offset (dx, dy): the art is shifted left / up when it reaches past the
    bottom-right tile (a whole-strip shift, so it stays together), and cut only past max_tiles.
    -> (frames on the canvas, w, h, share of art pixels cut)"""
    ox, oy = point[0] - anchor[0], point[1] - anchor[1]
    x0 = y0 = 10 ** 6
    x1 = y1 = -10 ** 6
    for fr in frames:
        ys, xs = np.nonzero(fr[:, :, 3] > 0)
        x0, x1 = min(x0, xs.min() + ox), max(x1, xs.max() + 1 + ox)
        y0, y1 = min(y0, ys.min() + oy), max(y1, ys.max() + 1 + oy)
    sx = min(0, (dx + 1) * 32 - x1)
    sy = min(0, (dy + 1) * 32 - y1)
    t = lambda v: int(-(-max(0, v) // 32))
    left = min(t(-(x0 + sx)), max_tiles - 1 - dx)
    top = min(t(-(y0 + sy)), max_tiles - 1 - dy)
    w, h = left + 1 + dx, top + 1 + dy
    out, cut, tot = [], 0, 0
    for f in frames:
        fh, fw = f.shape[:2]
        px, py = left * 32 + ox + sx, top * 32 + oy + sy
        cv = np.zeros((h * 32 + 2 * fh, w * 32 + 2 * fw, 4), np.uint8)
        cv[fh + py:fh + py + fh, fw + px:fw + px + fw] = f
        tile = cv[fh:fh + h * 32, fw:fw + w * 32].copy()
        a, b = int((f[:, :, 3] > 0).sum()), int((tile[:, :, 3] > 0).sum())
        tot += a
        cut += a - b
        out.append(tile)
    keep = [i for i, f in enumerate(out) if f[:, :, 3].any()]
    assert keep, (name, 'all art cut')
    return out[keep[0]:keep[-1] + 1], w, h, cut / max(1, tot)


def replaced_effect(name, frames, anchor, point, loop, oid):
    frames = trim(frames)
    assert frames, (name, 'no art')
    if loop and len(frames) > FADE + 2:
        for j in range(FADE):
            k = len(frames) - FADE + j
            frames[k] = G.dissolve(frames[k], (FADE - j) / (FADE + 1))
        frames = trim(frames)
    dx, dy = REPLACE_OFFSET.get(oid, (0, 0))
    placed, w, h, cut = anchored(frames, anchor, point, dx, dy, REPLACE_MAX_TILES, name)
    placed = [f for f in placed if f[:, :, 3].any()]
    n = len(placed) + 1
    strip = np.zeros((h * 32, w * 32 * n, 4), np.uint8)
    for i, f in enumerate(placed):
        strip[:, i * w * 32:(i + 1) * w * 32] = f
    return strip, w, h, n, dx, dy, cut


def replaced_missile(name, rows, anchor, point):
    pats = {pat: trim(rows[DIRS8.index(d)]) for pat, d in G.MISSILE_DIR.items()}
    n = min(len(v) for v in pats.values())
    allf = [f for v in pats.values() for f in v[:n]]
    placed, w, h, cut = anchored(allf, anchor, point, 0, 0, REPLACE_MAX_MISSILE_TILES, name)
    assert len(placed) == len(allf), (name, 'a missile frame cut away')
    W, H = w * 32, h * 32
    strip = np.zeros((3 * H, 3 * W * n, 4), np.uint8)
    for k, (x, y) in enumerate(pats):
        for f in range(n):
            x0 = (x * n + f) * W
            strip[y * H:(y + 1) * H, x0:x0 + W] = placed[k * n + f]
    return strip, w, h, n, 0, 0, cut


# -------------------------------------------------------------------------------------------------------- the picks
Pick = namedtuple('Pick', 'group kind name src note replace')


def earlier_used():
    used = set()
    for f in EARLIER_SOURCES:
        p = os.path.join(ART, f)
        if os.path.exists(p):
            for r in csv.DictReader(open(p, newline='')):
                sid, _, var = r['source'].partition('/')
                used.add((sid, var.partition('@')[0]))
    return used


def find_src(found, pack, eid, var):
    hits = [s for s in found.get(pack, []) if s.eid == eid and (not var or s.var == var)]
    if not hits:
        raise SystemExit(f'{pack}/{eid}/{var}: not in the packs')
    return hits[0]


def default_variant(found, pack, used):
    """one Src per effect id of a catalog pack: the first variant no earlier pair imported (else the first)"""
    by = {}
    for s in found.get(pack, []):
        by.setdefault(s.eid, []).append(s)
    out = []
    for eid, lst in by.items():
        free = [s for s in lst if (s.eid, s.var) not in used]
        out.append((free or lst)[0])
    return out


def ident(s):
    return ''.join(c if c.isalnum() else '_' for c in s.lower()).strip('_')


def picks(found):
    used = earlier_used()
    out = []
    taken_missile = set()
    for oid, (pack, eid, var, note) in sorted(REPLACE.items()):
        out.append(Pick('replace', 'effect', f'rep_e{oid}', find_src(found, pack, eid, var), note, oid))
    for oid, (pack, eid, var, note) in sorted(REPLACE_MISSILE.items()):
        s = find_src(found, pack, eid, var)
        taken_missile.add((s.pack, s.eid))
        out.append(Pick('replace', 'missile', f'rep_m{oid}', s, note, oid))
    # missiles: the projectile set, the spellcraft set, then the 500 set, until MAX_MISSILE
    cands = [s for s in default_variant(found, 'projectiles', used)]
    cands += [s for s in found.get('mega', []) if s.meta['category'] == 'projectiles' and (s.eid, '') not in used]
    free = MAX_MISSILE - FIRST_MISSILE + 1
    for s in cands:
        if free <= 0:
            break
        if (s.pack, s.eid) in taken_missile and s.pack == 'projectiles':
            continue
        pre = {'projectiles': '', 'mega': 'mega_'}[s.pack]
        out.append(Pick('missiles', 'missile', ident(pre + s.eid), s, s.meta.get('title') or s.meta.get('name'), None))
        free -= 1
    for g in GROUPS[2:]:
        packs, pre = GROUP_PACKS[g]
        for pack in packs:
            srcs = default_variant(found, pack, used) if pack in ('impacts', 'circles', 'auras', 'traps', 'ui') \
                else found.get(pack, [])
            for s in srcs:
                if s.meta.get('category') == 'projectiles':
                    continue
                if s.pack == 'mega' and (s.eid, '') in used:
                    continue
                title = s.meta.get('title') or s.meta.get('name') or s.eid
                out.append(Pick(g, 'effect', ident(pre + s.eid), s, title, None))
    return out


CUT = {}                     # replaced name -> share of its art pixels cut by the fixed offset (printed by build)


def convert(p):
    """-> [(spec row, strip)] (a directional effect gives eight), [] when it does not fit"""
    rows, anchor, point, ms, loop, directional = load(p.src)
    src = f'{p.src.eid}/{p.src.var}' if p.src.var else p.src.eid
    res = []
    if p.group == 'replace':
        if p.kind == 'missile':
            if len(rows) != 8:
                rows = {r: rows[0] for r in range(8)}
            strip, w, h, n, dx, dy, cut = replaced_missile(p.name, rows, anchor, point)
        else:
            row = DIRS8.index('s') if directional else 0
            strip, w, h, n, dx, dy, cut = replaced_effect(p.name, rows[row], anchor, point, loop, p.replace)
        CUT[p.name] = cut
        res.append((dict(kind=p.kind, name=p.name, file=f'pack36_fx/{p.name}.png', w=w, h=h, phases=n, ms=ms,
                         dx=dx, dy=dy, note=f'{p.note} (from {src})'), strip))
        return res
    if p.kind == 'missile':
        if len(rows) != 8:
            rows = {r: rows[0] for r in range(8)}
        cut = missile_strip(p.name, rows, anchor, point)
        if cut:
            strip, w, h, n, dx, dy = cut
            res.append((dict(kind='missile', name=p.name, file=f'pack36_fx/{p.name}.png', w=w, h=h, phases=n,
                             ms=ms, dx=dx, dy=dy, note=f'{p.note} (from {src})'), strip))
        return res
    if directional and p.group != 'replace':
        for d in OUR_DIRS:
            cut = effect_strip(f'{p.name}_{d}', rows[DIRS8.index(d)], anchor, point, loop)
            if cut is None:
                return []
            strip, w, h, n, dx, dy = cut
            res.append((dict(kind='effect', name=f'{p.name}_{d}', file=f'pack36_fx/{p.name}_{d}.png', w=w, h=h,
                             phases=n, ms=ms, dx=dx, dy=dy, note=f'{p.note}, towards {d} (from {src})'), strip))
        return res
    row = DIRS8.index('s') if directional else 0
    cut = effect_strip(p.name, rows[row], anchor, point, loop)
    if cut:
        strip, w, h, n, dx, dy = cut
        res.append((dict(kind='effect', name=p.name, file=f'pack36_fx/{p.name}.png', w=w, h=h, phases=n, ms=ms,
                         dx=dx, dy=dy, note=f'{p.note} (from {src})'), strip))
    return res


FIELDS = G.FIELDS
FIELDS_REPLACE = ['replace'] + G.FIELDS


def spec_text(group, rows):
    buf = io.StringIO()
    fields = FIELDS_REPLACE if group == 'replace' else FIELDS
    wr = csv.DictWriter(buf, fieldnames=fields, lineterminator='\n')
    wr.writeheader()
    wr.writerows(rows)
    return buf.getvalue()


def sources_text(entries):
    buf = io.StringIO()
    wr = csv.writer(buf, lineterminator='\n')
    wr.writerow(['name', 'kind', 'pack', 'source', 'licence'])
    for p, row in entries:
        src = f'{p.src.eid}/{p.src.var}' if p.src.var else p.src.eid
        wr.writerow([row['name'], row['kind'], PACK_NAME[p.src.pack], src,
                     LICENCE_BEAMS if p.src.pack == 'beams' else LICENCE_MEGA if p.src.pack == 'mega' else LICENCE])
    return buf.getvalue()


def existing_names():
    """every ChaosVfx / ChaosVfxMissile name of the committed Lua tables (a new name must not shadow one)"""
    names = set()
    lib = os.path.join(HERE, '..', '..', '..', 'server', 'data', 'lib')
    for p in sorted(glob.glob(os.path.join(lib, 'chaos_*.lua'))):
        if os.path.basename(p) == 'chaos_pack36_fx_ids.lua':
            continue
        for line in open(p, encoding='utf-8', errors='replace'):
            for pre in ('ChaosVfx.', 'ChaosVfxMissile.'):
                if line.startswith(pre):
                    names.add((pre, line[len(pre):].split(' ')[0]))
    return names


def tiles_in(strip):
    """non-empty 32 x 32 tiles of a strip (about the sprites it adds to the pair)"""
    h, w = strip.shape[0] // 32, strip.shape[1] // 32
    al = strip[:, :, 3].reshape(h, 32, w, 32).any(axis=(1, 3))
    return int(al.sum())


def work(args):
    """one pick in a worker process -> ([(row, digest, tiles)], cut share or None); the strips are saved here"""
    p, save = args
    res = []
    for row, strip in convert(p):
        if save:
            Image.fromarray(strip).save(os.path.join(ART, row['file']), optimize=False)
        res.append((row, G.digest(strip), tiles_in(strip)))
    return res, CUT.get(p.name)


def build(srcs, check, only=None):
    """cut every pick (each strip written as soon as it is made: the whole set does not fit in memory)"""
    found = discover(srcs)
    allp = picks(found)
    if only:
        allp = [p for p in allp if p.group in only]
    taken = existing_names()
    rows = {g: [] for g in GROUPS}
    sums = {}
    entries = []
    skipped = []
    ntiles = {g: 0 for g in GROUPS}
    old_sums = {}
    if check and os.path.exists(SUMS):
        old_sums = {l.split('  ', 1)[1].strip(): l.split('  ', 1)[0] for l in open(SUMS)}
    bad_art = []
    if not check:
        os.makedirs(OUT, exist_ok=True)
        open(os.path.join(OUT, '.gitignore'), 'w').write(GITIGNORE_TEXT)
    import multiprocessing
    with multiprocessing.get_context('fork').Pool(JOBS) as pool:
        done = list(pool.imap(work, [(p, not check) for p in allp], chunksize=4))
    for i, (p, (out, cut)) in enumerate(zip(allp, done)):
        if cut is not None:
            CUT[p.name] = cut
        if not out:
            skipped.append(p)
            continue
        for row, digest, nt in out:
            pre = 'ChaosVfxMissile.' if row['kind'] == 'missile' else 'ChaosVfx.'
            assert p.group == 'replace' or (pre, row['name']) not in taken, (row['name'], 'name taken')
            if p.group == 'replace':
                row = dict(replace=p.replace, **row)
            rows[p.group].append(row)
            sums[row['file']] = digest
            ntiles[p.group] += nt
            entries.append((p, row))
            if check and old_sums.get(row['file']) != digest:
                bad_art.append(row['file'])
    names = [(r['kind'], r['name']) for g in GROUPS for r in rows[g]]
    assert len(set(names)) == len(names), 'duplicate name'
    nm = sum(1 for g in GROUPS[1:] for r in rows[g] if r['kind'] == 'missile')
    assert FIRST_MISSILE + nm - 1 <= 255, 'missiles are uint8'
    texts = {SPEC[g]: spec_text(g, rows[g]) for g in GROUPS}
    texts[SOURCES] = sources_text(entries)
    texts[SUMS] = ''.join(f'{sums[r["file"]]}  {r["file"]}\n' for g in GROUPS for r in rows[g])
    if check:
        bad = [p for p, t in texts.items() if not os.path.exists(p) or open(p, newline='').read() != t]
        for p in bad:
            print('differs:', os.path.relpath(p, HERE))
        for f in bad_art:
            print('strip differs:', f)
        return 1 if bad or bad_art else 0
    if not only:
        for p, t in texts.items():
            open(p, 'w', newline='').write(t)
    for p in skipped:
        print(f'skipped (larger than {MAX_TILES} tiles, {MAX_MISSILE_TILES} for a missile): {p.group} {p.name}')
    for n, c in sorted(CUT.items()):
        if c > 0.02:
            print(f'replace {n}: {c:.0%} of the art cut (fixed send offset, {REPLACE_MAX_TILES} tiles)')
    for g in GROUPS:
        ne = sum(1 for r in rows[g] if r['kind'] == 'effect')
        nmi = sum(1 for r in rows[g] if r['kind'] == 'missile')
        print(f'{g}: {ne} effects, {nmi} missiles, {ntiles[g]} tiles')
    print(f'{len(sums)} strips, {sum(ntiles.values())} tiles (sprites before dedup), {len(skipped)} skipped')
    return 0


def check_without_art():
    """CI: the specs, the sources and the sums name the same things; names unique and free; offsets inside"""
    errs = []
    names = []
    files = []
    for g in GROUPS:
        if not os.path.exists(SPEC[g]):
            errs.append(f'missing {os.path.basename(SPEC[g])}')
            continue
        for r in csv.DictReader(open(SPEC[g], newline='')):
            names.append((r['kind'], r['name']))
            files.append(r['file'])
            w, h, dx, dy = int(r['w']), int(r['h']), int(r['dx']), int(r['dy'])
            if not (0 <= dx < w and 0 <= dy < h):
                errs.append(f"{r['name']}: offset outside")
            if g == 'replace' and not r['replace'].isdigit():
                errs.append(f"{r['name']}: no target id")
            if g != 'replace' and r['kind'] == 'missile' and (w > 3 or h > 3):
                errs.append(f"{r['name']}: missile too big")
    if len(set(names)) != len(names):
        errs.append('duplicate name')
    taken = existing_names()
    for kind, n in names:
        pre = 'ChaosVfxMissile.' if kind == 'missile' else 'ChaosVfx.'
        if not n.startswith('rep_') and (pre, n) in taken:
            errs.append(f'{n}: name already used in another Lua table')
    srcs = [r['name'] for r in csv.DictReader(open(SOURCES, newline=''))] if os.path.exists(SOURCES) else []
    if sorted(srcs) != sorted(n for _, n in names):
        errs.append('pack36_fx_sources.csv does not list the spec names')
    sums = [l.split('  ', 1)[1].strip() for l in open(SUMS)] if os.path.exists(SUMS) else []
    if sums != files:
        errs.append('pack36_fx.sums does not list the spec files in order')
    have = [f for f in files if os.path.exists(os.path.join(ART, f))]
    if have:
        want = {l.split('  ', 1)[1].strip(): l.split('  ', 1)[0] for l in open(SUMS)}
        for f in have:
            a = np.asarray(Image.open(os.path.join(ART, f)).convert('RGBA'))
            if G.digest(a) != want[f]:
                errs.append(f'{f}: differs from its sum')
    nm = sum(1 for (k, n) in names if k == 'missile' and not n.startswith('rep_'))
    if FIRST_MISSILE + nm - 1 > 255:
        errs.append('too many missiles (uint8)')
    for e in errs:
        print(e)
    print(f'pack36 fx: {len(names)} things, {len(have)} strips on disk checked, '
          f"{'OK' if not errs else f'{len(errs)} problem(s)'}")
    return 1 if errs else 0


def inventory(srcs):
    found = discover(srcs)
    for k in sorted(found):
        ids = {s.eid for s in found[k]}
        print(f'{k}: {len(ids)} effects, {len(found[k])} with their colour variants ({PACK_NAME.get(k)})')
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('cmd', choices=['build', 'inventory'])
    ap.add_argument('--src', action='append', default=[])
    ap.add_argument('--check', action='store_true')
    ap.add_argument('--only', default='', help='comma separated groups (a trial; specs not written)')
    a = ap.parse_args()
    if a.cmd == 'inventory':
        return inventory(a.src)
    if not a.src:
        if not a.check:
            sys.exit('build needs --src (or --check alone)')
        return check_without_art()
    return build(a.src, a.check, [g for g in a.only.split(',') if g])


if __name__ == '__main__':
    sys.exit(main())
