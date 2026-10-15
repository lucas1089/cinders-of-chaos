#!/usr/bin/env python3
"""Pair 27 trial: own effects and missiles for the nine pack farming spells, buff and game feel effects, cut from the
owner's oblique effect sets.

    python3 -I gen_pack27_fx.py build --src DIR [--src DIR ...]   # -> art_import/pack27_fx/<name>.png
                                                                  #    + art_import/pack27_fx.csv + pack27_fx.sums
                                                                  #    + art_import/pack27_sources.csv
    python3 -I gen_pack27_fx.py build --src DIR ... --check       # rebuild in memory, compare with spec, sums, strips
    python3 -I gen_pack27_fx.py build --check                     # without the sets (CI): spec and sums match PICKS;
                                                                  #    strips on disk match the sums
    python3 -I gen_pack27_fx.py preview --out DIR                 # every strip 3x on a ground with the tile grid + GIFs

The sources: the owner's oblique effect sets of 2026-10-15 (Google Drive "ots"): projectiles, fields and traps, game
feel effects, spells and impacts, auras and buffs (status loops), 32 px tiles. Each --src is a folder that holds
unzipped sets (or the loose files fetched from the unpacked Drive folder: a variant's .json and its `full` sheet); an
effect variant is found at `sheets/32px/<category>/<effect>/<variant>/<effect>_<variant>.json` in any of them (frame
size, pivot, anchor tile, layers, stages, sheets; 8-way sheets have one row per direction, E SE S SW W NW N NE).
When a variant's layer sheets are missing, its flattened `full` sheet is used instead.

Conversion (like gen_pack_fx.py):
  * layers merged: `back` at 60 % opacity under `front` (import_vfx.py BACK_ALPHA), `ground` under `air`;
    staged effects (start / loop / end) are their stages in order;
  * frames a..b of that, every `step`-th; alpha made clean (0 / 255; soft pixels become an ordered 4x4 dither);
    effects: empty frames at the end are dropped and one empty last frame is added (they play once);
  * placed like import_vfx.py: a unit-centred effect's pivot (the set's feet point, a quarter tile right/down of the
    tile centre) goes on our feet point (14, 20); a tile-centred one's pivot (the tile centre) on (16, 16);
    a missile's pivot (its frame centre) on (13, 13); cut to whole tiles, sent at target + (dx, dy);
  * missiles: the 3 x 3 direction patterns of the client (import_vfx.MISSILE_DIR), each a block of the frames;
    directional effects (`dirs`): one effect per direction, named <name>_<dir> (VfxDir).

The sets' licence allows use in unlimited commercial projects (games included), modified or not, without
attribution; it forbids reselling, redistributing, sublicensing or sharing the assets themselves (alone or in
another pack, template or generator, even modified) and machine-learning training. Shipping the converted frames
inside the game client is use in a game. So neither the sets nor these strips are committed: art_import/pack27_fx/
is ignored by git; art_import/pack27_fx.sums holds the sha256 of every strip's decoded RGBA pixels.
Deterministic: no randomness; Pillow 12.3.0 and numpy 2.5.3 (the CI pins).

Not in any published pair. Trial: appended to things_custom26 with import_fx_art.py (client/MANIFEST.md
"Pack farming spell effects (pair 27 trial)"); server side server/data/lib/chaos_pack27_fx.lua behind the switch
ChaosPack27Fx.PAIR27_FX (off).
"""
import argparse
import csv
import glob
import hashlib
import io
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, 'art_import')
OUT = os.path.join(ART, 'pack27_fx')
SPEC = os.path.join(ART, 'pack27_fx.csv')
SUMS = os.path.join(ART, 'pack27_fx.sums')
SOURCES = os.path.join(ART, 'pack27_sources.csv')     # every pick's art pack, for docs/CREDITS.md (check_credits.py)
# source effect prefix -> the pack it comes from, by its entry name in docs/CREDITS.md
# the licence line of every pack used (all four: the same author's standard terms; author in docs/CREDITS.md)
LICENCE = ('purchased; commercial use in games, credit not required; no resale or redistribution of the files; '
           'no machine-learning use; author: docs/CREDITS.md')
PACK_OF = [('impact_', 'Magic VFX Spells & Impacts'), ('circle_', 'Magic VFX Spells & Impacts'),
           ('status_', 'Auras & Buffs'), ('aura_', 'Auras & Buffs'), ('fx_', 'UI Game Feel'),
           ('proj_', 'Projectiles'), ('field_', 'Fields & Traps'), ('env_', 'Fields & Traps')]
FEET = (14, 20)               # import_vfx.PLACE['feet']
TILE_CENTRE = (16, 16)
MISSILE_CENTRE = (13, 13)     # import_vfx.PLACE['centre']
BACK_ALPHA = 0.6
MAX_TILES = 7
DIRS8 = ['e', 'se', 's', 'sw', 'w', 'nw', 'n', 'ne']
MISSILE_DIR = {(0, 0): 'nw', (1, 0): 'n', (2, 0): 'ne', (0, 1): 'w', (1, 1): 's', (2, 1): 'e',
               (0, 2): 'sw', (1, 2): 's', (2, 2): 'se'}
OUR_DIRS = ['n', 'ne', 'e', 'se', 's', 'sw', 'w', 'nw']       # suffix order of the directional effects

# kind, name, source effect, variant, first and last frame of the merged stages, step, ms per frame, note
# (spec order = id order; a 'dirs' row writes 8 effects <name>_<dir>; a 'loop' row is an effect cut from a looping
# status or marker: its last FADE frames dissolve, an ordered dither like gen_pack_fx.py)
PICKS = [
    # the nine pack farming spells
    ('effect', 'palm_quake', 'impact_shockwave', 'earth', 0, 15, 1, 62,
     'Palm Shockwave: a ground-slam ring tears across the floor, dust and pebbles thrown out'),
    ('effect', 'flurry_petals', 'impact_blade_dance', 'sakura', 0, 13, 1, 62,
     'Blade Flurry: three silk-ribbon slashes whirl round the caster, petals scatter'),
    ('dirs', 'iaido_dash', 'fx_charge_dash', 'steel', 0, 11, 1, 70,
     'Iaido Sweep: steel crescents and speed lines rush towards the cut'),
    ('effect', 'ricochet_burst', 'impact_shadow_burst', 'void', 0, 13, 1, 62,
     'Shadow Ricochet: a shadow knot opens, violet tendrils lash out and recoil'),
    ('effect', 'chain_sparks', 'impact_punch', 'steel', 0, 13, 1, 62,
     'Iron Chain: a steel burst and star lines where each link strikes'),
    ('effect', 'sanctified_seal', 'impact_holy_nova', 'holy', 0, 15, 1, 70,
     'Sanctified Ground: motes gather and burst into a sun-crowned ring across the floor'),
    ('dirs', 'shieldwave_bash', 'impact_shield_bash', 'holy', 0, 13, 1, 62,
     'Shield Wave: a golden shield-shaped shock bursts forward'),
    ('effect', 'shrapnel_burst', 'impact_corpse_explosion', 'necrotic', 0, 13, 1, 62,
     'Bone Shrapnel: a necrotic blast of bone shards and gore'),
    # buff bar states (sent on the player when the state starts) and a spell's own buff
    ('loop', 'buff_rested', 'status_regeneration', 'nature', 0, 15, 1, 83,
     'rested: green crosses rise, a soft pulse ring on the floor'),
    ('loop', 'buff_returning', 'status_blessed', 'holy', 0, 15, 1, 83,
     'returning player: a golden halo, white feathers drift down'),
    ('loop', 'buff_catchup', 'status_haste', 'gold', 0, 15, 1, 83,
     'catch-up: a golden whirl of wind and speed lines'),
    ('loop', 'buff_low_stamina', 'status_exhausted', 'steel', 0, 15, 1, 83,
     'low stamina: sweat, steam puffs and a drooping swirl'),
    ('loop', 'hunter_focus', 'status_eagle_eye', 'gold', 0, 15, 1, 83,
     "Hunter's Instinct: a hawk crest and a turning crosshair over the head"),
    # game feel: level up (the frames before the set's baked words), loot beams by rarity, Ember Cache, Candlemarks
    ('loop', 'levelup_rise', 'fx_level_up', 'gold', 0, 7, 1, 67,
     'level up: a golden ring and a rising star beam, no words (the frames before the lettering)'),
    ('loop', 'loot_beam_gold', 'fx_loot_beacon', 'gold', 0, 15, 1, 83, 'loot beam: legendary and exotic drops (gold)'),
    ('loop', 'loot_beam_steel', 'fx_loot_beacon', 'steel', 0, 15, 1, 83, 'loot beam: divine drops (white steel)'),
    ('loop', 'loot_beam_amethyst', 'fx_loot_beacon', 'amethyst', 0, 15, 1, 83, 'loot beam: cosmic drops (violet)'),
    ('loop', 'loot_beam_emerald', 'fx_loot_beacon', 'emerald', 0, 15, 1, 83, 'loot beam: unique drops (emerald)'),
    ('effect', 'embercache_coins', 'fx_coin_burst', 'gold', 0, 15, 1, 67, 'Ember Cache reward: a burst of gold coins'),
    ('loop', 'candlemark_glow', 'fx_treasure_glow', 'gold', 0, 15, 1, 83, 'Candlemarks earned: a treasure glow and sparkles'),
    # spell impacts of the classes (the spell's own effect name is swapped, see chaos_pack27_fx.lua)
    ('effect', 'nova_frost', 'impact_frost_nova', 'frost', 0, 15, 1, 62,
     'Rime Bloom: a frost ring glazes the floor, a crown of ice spikes erupts and shatters'),
    ('effect', 'meteor_fall', 'impact_meteor', 'fire', 0, 19, 1, 62,
     'Falling Pyre: a blazing meteor crashes down, fireball, debris and a cooling crater'),
    ('effect', 'storm_chain', 'impact_chain_lightning', 'storm', 0, 15, 1, 62,
     'Forked Storm: a bolt cracks down and leaps across the floor in jagged arcs'),
    ('effect', 'smite_radiant', 'impact_holy_smite', 'radiant', 0, 13, 1, 62,
     'Radiant Smite: a pillar of light slams down, a burst ring and drifting feathers'),
    ('effect', 'judgment_holy', 'impact_divine_judgment', 'holy', 0, 15, 1, 62,
     'Judgement: a sword of light plunges down with a cross-shaped shock ring'),
    ('effect', 'nova_radiant', 'impact_holy_nova', 'radiant', 0, 15, 1, 62,
     'Purging Nova: motes gather and burst into a sun-crowned ring'),
    ('effect', 'mend_holy', 'impact_mass_heal', 'holy', 0, 15, 1, 62,
     'Vow of Mending: a radiant cross blooms over a ring of holy light'),
    ('effect', 'gyre_steel', 'impact_whirlwind', 'steel', 0, 15, 1, 62,
     'Reaping Gyre: a ring of blade smears sweeps twice around the feet'),
    ('effect', 'berserk_blood', 'impact_berserk', 'blood', 0, 15, 1, 62,
     'Bloodrage and Red Frenzy: a furious red spin, rage flares and a dust ring'),
    ('effect', 'slam_earth', 'impact_ground_slam', 'earth', 0, 15, 1, 62,
     'Earthbreaker: a radial shockwave, rock chunks and a rolling dust wall'),
    ('effect', 'terra_strike', 'impact_ultimate_terra_strike', 'earth', 0, 15, 1, 62,
     'Colossus Fall: the ground caves in, two rings of rock spikes erupt and crumble'),
    ('dirs', 'cleave_blood', 'impact_cleave', 'blood', 0, 13, 1, 62,
     'Skyfall and Vaulting Cleave: a wide cleaving arc in front of the warrior'),
    ('effect', 'backstab_shadow', 'impact_backstab', 'shadow', 0, 13, 1, 62,
     'Shadow Step: a shadow afterimage strikes from behind, a crimson X'),
    ('effect', 'parry_steel', 'impact_parry', 'steel', 0, 13, 1, 62,
     'Counter Stance: two blade gleams cross, a white-hot star and sparks'),
    ('effect', 'venom_flurry', 'impact_venom_flurry', 'poison', 0, 13, 1, 62,
     'Poison Blades: three dagger slashes fling green venom'),
    ('effect', 'drain_blood', 'impact_blood_drain', 'necrotic', 0, 13, 1, 62,
     'Life Siphon: ribbons of blood torn from the target'),
    ('dirs', 'claws_shadow', 'impact_shadow_claws', 'shadow', 0, 13, 1, 62,
     'Shadowfist Flurry: three rakes of living shadow, turned from the caster'),
    ('effect', 'punch_fire', 'impact_punch', 'fire', 0, 13, 1, 62, 'Ashen Fist: a fiery comic punch burst'),
    ('effect', 'hammer_steel', 'impact_hammer_hit', 'steel', 0, 13, 1, 62, 'Iron Palm: a heavy steel impact'),
    ('effect', 'healing_burst', 'impact_healing_burst', 'spirit', 0, 13, 1, 62,
     'Kindled Breath: a radiant plus-sign blooms, leaves and sparkles spiral up'),
    # circles: spell rifts and seals, the Town Portal pad, the boss danger telegraph
    ('loop', 'rift_void', 'circle_void_rift', 'void@start', 0, 11, 1, 83,
     'Tear in the Weave: a vortex tears open in the ground'),
    ('loop', 'summon_necro', 'circle_summoning', 'necrotic@start', 0, 11, 1, 83,
     'Raise Dead: a pentagram blazes inside a double circle'),
    ('loop', 'portal_pad', 'circle_teleport_pad', 'arcane@loop', 0, 23, 1, 83,
     'Town Portal channel: a spinning rune circle with columns of light'),
    ('loop', 'boss_telegraph', 'circle_telegraph', 'blood@loop', 0, 23, 1, 83,
     'boss telegraph (round, 5 x 5): a pulsing blood-red rim, the fill closes in'),
    ('loop', 'portal_in', 'fx_teleport_in', 'arcane', 0, 15, 1, 67, 'Town Portal opens: an arcane arrival flash'),
    ('loop', 'portal_out', 'fx_teleport_out', 'arcane', 0, 15, 1, 67, 'Town Portal closes: an arcane departure flash'),
    # buff and debuff states (one shot of the status loop when the state starts)
    ('loop', 'vigil_wrath', 'status_might', 'fire', 0, 15, 1, 83, 'Vigil of Wrath on: blazing chevrons stream up'),
    ('loop', 'vigil_iron', 'status_fortified', 'sapphire', 0, 15, 1, 83,
     'Vigil of Iron on: a shield emblem and orbiting hex plates'),
    ('loop', 'vigil_haste', 'status_haste', 'wind', 0, 15, 1, 83, 'Vigil of Haste on: a whirl of wind and speed lines'),
    ('loop', 'vigil_clarity', 'aura_chrono_rings', 'arcane', 0, 23, 1, 83, 'Vigil of Clarity on: turning clock-dial rings'),
    ('loop', 'ward_shield', 'status_shielded', 'arcane@loop', 0, 15, 1, 83, 'Soulward: a hex-grid barrier dome'),
    ('loop', 'aegis_radiant', 'status_divine_shield', 'radiant', 0, 15, 1, 83, 'Aegis of Faith: a golden dome of light'),
    ('loop', 'veil_stealth', 'status_stealth', 'shadow', 0, 15, 1, 83, 'Shadow Veil: the thief fades into shadow'),
    ('loop', 'zeal_oath', 'aura_crusader_oath', 'radiant', 0, 23, 1, 83, 'Zealotry: six holy swords ring the caster'),
    ('loop', 'bellow_cry', 'status_battle_cry', 'gold', 0, 15, 1, 83, 'Iron Bellow: shockwave rings burst from the head'),
    ('loop', 'curse_mark', 'status_cursed', 'necrotic', 0, 15, 1, 83, 'Withering Curse: a skull sigil and shadow tendrils'),
    ('loop', 'stun_stars', 'status_stunned', 'gold', 0, 15, 1, 83, 'stunned: little stars wheel round the head'),
    ('missile', 'fan_knife', 'proj_throwing_knife', 'steel', 0, 7, 1, 83, 'Fan of Knives: a steel throwing knife'),
    ('missile', 'ricochet_bolt', 'proj_shadow_bolt', 'void', 0, 7, 1, 83, 'Shadow Ricochet: a violet shadow bolt'),
    ('missile', 'chain_disc', 'proj_energy_disc', 'gold', 0, 7, 1, 83, 'Iron Chain: a ring of golden chi'),
    ('missile', 'shrapnel_shards', 'proj_bone_shards', 'bone', 0, 7, 1, 83, 'Bone Shrapnel: three bone shards'),
    ('missile', 'shuriken_steel', 'proj_shuriken', 'steel', 0, 7, 1, 83, 'Shuriken Toss and Barrage: a spinning steel star'),
    ('missile', 'soul_skull', 'proj_soul_skull', 'necrotic', 0, 7, 1, 83, 'necromancer skull orb: a green-lit skull'),
    ('missile', 'holy_orb', 'proj_holy_orb', 'radiant', 0, 7, 1, 83, 'Radiant Smite: a holy orb'),
]

FADE = 3


def dissolve(fr, keep):
    """keep a Bayer-ordered share `keep` (0..1) of the art: a pixel-art fade out (gen_pack_fx.py)"""
    h, w = fr.shape[:2]
    thr = np.tile(BAYER, (h // 4 + 1, w // 4 + 1))[:h, :w]
    out = fr.copy()
    out[thr >= keep] = 0
    return out


BAYER = (np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) + 0.5) / 16.0


def clean_alpha(fr):
    """RGBA -> RGBA with alpha 0 / 255: opaque stays, soft pixels kept where alpha beats a 4x4 Bayer threshold"""
    a = fr[:, :, 3].astype(np.float64) / 255.0
    h, w = a.shape
    thr = np.tile(BAYER, (h // 4 + 1, w // 4 + 1))[:h, :w]
    keep = (a >= 1.0) | ((a > 0) & (a > thr))
    out = fr.copy()
    out[:, :, 3] = np.where(keep, 255, 0).astype(np.uint8)
    out[~keep] = 0
    return out


def over(dst, src, alpha=1.0):
    """straight-alpha 'over' in float, -> uint8 RGBA"""
    d = dst.astype(np.float64) / 255.0
    s = src.astype(np.float64) / 255.0
    sa = s[:, :, 3:4] * alpha
    da = d[:, :, 3:4]
    oa = sa + da * (1 - sa)
    rgb = np.where(oa > 0, (s[:, :, :3] * sa + d[:, :, :3] * da * (1 - sa)) / np.maximum(oa, 1e-9), 0)
    return np.clip(np.round(np.concatenate([rgb, oa], 2) * 255), 0, 255).astype(np.uint8)


def find(srcs, eid, var):
    hits = []
    for s in srcs:
        hits += glob.glob(os.path.join(s, '**', 'sheets', '32px', '*', eid, var, f'{eid}_{var}.json'), recursive=True)
    if not hits:
        sys.exit(f'{eid}/{var}: not found under {srcs}')
    return sorted(hits)[0]


def load(srcs, eid, var):
    """-> (meta, {row: [frames]}) of the merged layers, stages in order; `var` may name one stage of a staged effect
    as <variant>@<stage> (start, loop or end)"""
    var, _, stage = var.partition('@')
    path = find(srcs, eid, var)
    d = json.load(open(path))
    base = os.path.dirname(path)
    fw, fh = d['frame_width'], d['frame_height']
    assert d['tile_size'] == 32, path
    sheets = d['sheets']
    staged = isinstance(sheets.get('loop'), dict)
    assert staged or not stage, (path, 'not a staged effect')
    parts = [sheets[k] for k in ((stage,) if stage else ('start', 'loop', 'end')) if k in sheets] \
        if staged else [sheets]
    assert parts, (path, stage)
    layers = d['layers']
    rows = len(d.get('directions') or []) or 1
    out = {r: [] for r in range(rows)}
    for p in parts:
        merged = None
        if not all(os.path.exists(os.path.join(base, p[ln])) for ln in layers):
            layers = ['full']                   # only the flattened sheet was fetched (loose Drive files)
        for ln in layers:
            a = np.asarray(Image.open(os.path.join(base, p[ln])).convert('RGBA'))
            if merged is None:
                merged = np.zeros_like(a)
            merged = over(merged, a, BACK_ALPHA if (ln == 'back' and 'front' in layers) else 1.0)
        assert merged.shape[0] == fh * rows and merged.shape[1] % fw == 0, (path, merged.shape)
        for r in range(rows):
            for i in range(merged.shape[1] // fw):
                out[r].append(merged[r * fh:(r + 1) * fh, i * fw:(i + 1) * fw].copy())
    return d, out


def bbox_tiles(frames, anchor, point):
    x0 = y0 = 10 ** 6
    x1 = y1 = -10 ** 6
    for fr in frames:
        al = fr[:, :, 3] > 0
        if not al.any():
            continue
        ys, xs = np.nonzero(al)
        ox, oy = point[0] - anchor[0], point[1] - anchor[1]
        x0, x1 = min(x0, xs.min() + ox), max(x1, xs.max() + 1 + ox)
        y0, y1 = min(y0, ys.min() + oy), max(y1, ys.max() + 1 + oy)
    t = lambda v: int(-(-max(0, v) // 32))
    return t(-x0), t(-y0), t(x1 - 32), t(y1 - 32)


def place(f, anchor, point, left, top, w, h, name):
    fh, fw = f.shape[:2]
    px, py = left * 32 + point[0] - anchor[0], top * 32 + point[1] - anchor[1]
    cv = np.zeros((h * 32 + 2 * fh, w * 32 + 2 * fw, 4), np.uint8)       # padded: art outside is cut, checked
    cv[fh + py:fh + py + fh, fw + px:fw + px + fw] = f
    tile = cv[fh:fh + h * 32, fw:fw + w * 32]
    assert (tile[:, :, 3] > 0).sum() == (f[:, :, 3] > 0).sum(), (name, 'art clipped')
    return tile


def pivot_point(meta, kind):
    """(the set's pivot in frame pixels, our point on the target tile)"""
    piv = (int(round(meta['pivot'][0])), int(round(meta['pivot'][1])))
    if kind == 'missile':
        return piv, MISSILE_CENTRE
    ax, ay = meta['anchor_tile']
    if piv == (ax * 32 + 16, ay * 32 + 16):
        return piv, TILE_CENTRE                                         # tile-centred (fields, circles)
    assert piv == (ax * 32 + 24, ay * 32 + 24), (meta['id'], piv)       # unit-centred: the feet point
    return piv, FEET


def select(frames, a, b, step):
    assert 0 <= a <= b < len(frames), (a, b, len(frames))
    return [clean_alpha(f) for f in frames[a:b + 1:step]]


def effect_strip(name, frames, anchor, point):
    while frames and not frames[-1][:, :, 3].any():
        frames = frames[:-1]
    while frames and not frames[0][:, :, 3].any():
        frames = frames[1:]
    assert frames and all(f[:, :, 3].any() for f in frames), (name, 'empty frame inside')
    left, top, right, bottom = bbox_tiles(frames, anchor, point)
    w, h = left + 1 + right, top + 1 + bottom
    assert w <= MAX_TILES and h <= MAX_TILES, (name, w, h)
    n = len(frames) + 1
    strip = np.zeros((h * 32, w * 32 * n, 4), np.uint8)
    for i, f in enumerate(frames):
        strip[:, i * w * 32:(i + 1) * w * 32] = place(f, anchor, point, left, top, w, h, name)
    return strip, w, h, n, right, bottom


def convert(srcs, pick):
    kind, name, sid, var, a, b, step, ms, note = pick
    meta, rows = load(srcs, sid, var)
    src = f'{sid}/{var} {a}-{b}' + (f' step {step}' if step > 1 else '')
    out = []
    if kind in ('effect', 'loop'):
        anchor, point = pivot_point(meta, 'effect')
        fr = select(rows[0], a, b, step)
        if kind == 'loop':                     # a loop cut to a one-shot: the last FADE frames dissolve
            for j in range(FADE):
                fr[len(fr) - FADE + j] = dissolve(fr[len(fr) - FADE + j], (FADE - j) / (FADE + 1))
        strip, w, h, n, dx, dy = effect_strip(name, fr, anchor, point)
        out.append((dict(kind='effect', name=name, file=f'pack27_fx/{name}.png', w=w, h=h, phases=n, ms=ms,
                         dx=dx, dy=dy, note=f'{note} (from {src})'), strip))
    elif kind == 'dirs':
        assert len(rows) == 8, name
        anchor, point = pivot_point(meta, 'effect')
        for d in OUR_DIRS:
            fr = select(rows[DIRS8.index(d)], a, b, step)
            strip, w, h, n, dx, dy = effect_strip(f'{name}_{d}', fr, anchor, point)
            out.append((dict(kind='effect', name=f'{name}_{d}', file=f'pack27_fx/{name}_{d}.png', w=w, h=h,
                             phases=n, ms=ms, dx=dx, dy=dy, note=f'{note}, towards {d} (from {src})'), strip))
    else:
        assert len(rows) == 8, name
        anchor, point = pivot_point(meta, 'missile')
        pats = {pat: select(rows[DIRS8.index(d)], a, b, step) for pat, d in MISSILE_DIR.items()}
        n = len(pats[(0, 0)])
        left, top, right, bottom = bbox_tiles([f for v in pats.values() for f in v], anchor, point)
        w, h = left + 1 + right, top + 1 + bottom
        assert w <= 3 and h <= 3, (name, w, h)
        W, H = w * 32, h * 32
        strip = np.zeros((3 * H, 3 * W * n, 4), np.uint8)
        for (x, y), fr in pats.items():
            for f, img in enumerate(fr):
                assert img[:, :, 3].any(), (name, 'empty missile frame')
                x0 = (x * n + f) * W
                strip[y * H:(y + 1) * H, x0:x0 + W] = place(img, anchor, point, left, top, w, h, name)
        out.append((dict(kind='missile', name=name, file=f'pack27_fx/{name}.png', w=w, h=h, phases=n, ms=ms,
                         dx=right, dy=bottom, note=f'{note} (from {src})'), strip))
    return out


def check_strip(row, strip):
    W, H, n = row['w'] * 32, row['h'] * 32, row['phases']
    if row['kind'] == 'missile':
        want = (3 * H, 3 * W * n)
    else:
        want = (H, W * n)
    if strip.shape[:2] != want:
        return [f"{row['name']}: size {strip.shape[:2]} != {want}"]
    errs = []
    al = strip[:, :, 3]
    if not np.isin(al, (0, 255)).all():
        errs.append(f"{row['name']}: alpha not 0 / 255")
    if row['kind'] == 'effect':
        for f in range(n):
            has = al[:, f * W:(f + 1) * W].any()
            if f < n - 1 and not has:
                errs.append(f"{row['name']}: frame {f} empty")
            if f == n - 1 and has:
                errs.append(f"{row['name']}: last frame not empty")
    if not (0 <= row['dx'] < row['w'] and 0 <= row['dy'] < row['h']):
        errs.append(f"{row['name']}: offset outside")
    return errs


def digest(strip):
    return hashlib.sha256(np.ascontiguousarray(strip).tobytes() + repr(strip.shape).encode()).hexdigest()


FIELDS = ['kind', 'name', 'file', 'w', 'h', 'phases', 'ms', 'dx', 'dy', 'note']


def spec_text(rows):
    buf = io.StringIO()
    wr = csv.DictWriter(buf, fieldnames=FIELDS, lineterminator='\n')
    wr.writeheader()
    wr.writerows(rows)
    return buf.getvalue()


def sums_text(rows, strips):
    return ''.join(f"{digest(s)}  {r['file']}\n" for r, s in zip(rows, strips))


def pack_of(sid):
    for prefix, pack in PACK_OF:
        if sid.startswith(prefix):
            return pack
    sys.exit(f'{sid}: no pack for this source effect (PACK_OF)')


def sources_text():
    """one row per pick: our name, its kind, the art pack (a docs/CREDITS.md entry), the source effect/variant and the
    licence line (the author is named only in docs/CREDITS.md: tools/ci/check_names.py)"""
    buf = io.StringIO()
    wr = csv.writer(buf, lineterminator='\n')
    wr.writerow(['name', 'kind', 'pack', 'source', 'licence'])
    for kind, name, sid, var, a, b, step, ms, note in PICKS:
        wr.writerow([name, kind, pack_of(sid), f'{sid}/{var}', LICENCE])
    return buf.getvalue()


def read(path):
    return open(path, newline='').read() if os.path.exists(path) else None


def expected_names():
    """[(kind, name, source text, ms, note)] the spec must list, in order, from PICKS"""
    out = []
    for kind, name, sid, var, a, b, step, ms, note in PICKS:
        src = f'{sid}/{var} {a}-{b}' + (f' step {step}' if step > 1 else '')
        if kind == 'dirs':
            out += [('effect', f'{name}_{d}', ms, f'{note}, towards {d} (from {src})') for d in OUR_DIRS]
        elif kind == 'loop':
            out.append(('effect', name, ms, f'{note} (from {src})'))
        else:
            out.append((kind, name, ms, f'{note} (from {src})'))
    return out


def check_without_art():
    ok = True
    spec, sums = read(SPEC), read(SUMS)
    if spec is None or sums is None:
        print('missing', SPEC if spec is None else SUMS)
        return False
    rows = list(csv.DictReader(io.StringIO(spec)))
    if read(SOURCES) != sources_text():
        print(SOURCES, 'differs from PICKS (run build)')
        ok = False
    want = expected_names()
    if [(r['kind'], r['name']) for r in rows] != [(k, n) for k, n, _, _ in want]:
        print('spec names differ from PICKS')
        ok = False
    for r, (kind, name, ms, note) in zip(rows, want):
        exp = dict(file=f'pack27_fx/{name}.png', ms=str(ms), note=note)
        for k, v in exp.items():
            if r[k] != v:
                print(f'{name}: {k} = {r[k]!r}, PICKS says {v!r}')
                ok = False
        for k in ('w', 'h', 'dx', 'dy', 'phases', 'ms'):
            r[k] = int(r[k])
        lim = 3 if kind == 'missile' else MAX_TILES
        if not (1 <= r['w'] <= lim and 1 <= r['h'] <= lim and 0 <= r['dx'] < r['w'] and 0 <= r['dy'] < r['h']):
            print(f'{name}: bad size or offset')
            ok = False
    sum_of = dict(reversed(line.split('  ', 1)) for line in sums.splitlines())
    if sorted(sum_of) != sorted(r['file'] for r in rows):
        print('sums do not list exactly the spec files')
        ok = False
    found = 0
    for r in rows:
        p = os.path.join(ART, r['file'])
        if os.path.exists(p):
            found += 1
            s = np.asarray(Image.open(p).convert('RGBA'))
            errs = check_strip(r, s)
            if digest(s) != sum_of.get(r['file']):
                errs.append(f"{r['name']}: strip differs from pack27_fx.sums")
            for e in errs:
                print(e)
            ok = ok and not errs
    print(f'pack27 fx check (no art sets): {len(rows)} specs, {found} strips on disk checked:',
          'OK' if ok else 'FAILED')
    return ok


def build(srcs, check):
    if not srcs:
        if not check:
            sys.exit('build needs --src (the art sets); without it only --check runs')
        return check_without_art()
    rows, strips, errs = [], [], []
    for p in PICKS:
        for r, s in convert(srcs, p):
            errs += check_strip(r, s)
            rows.append(r)
            strips.append(s)
    for e in errs:
        print(e)
    if errs:
        return False
    spec, sums = spec_text(rows), sums_text(rows, strips)
    if check:
        ok = read(SPEC) == spec and read(SUMS) == sums and read(SOURCES) == sources_text()
        if not ok:
            print('spec, sums or sources differ from a rebuild')
        for r, s in zip(rows, strips):
            p = os.path.join(ART, r['file'])
            if os.path.exists(p) and not np.array_equal(np.asarray(Image.open(p).convert('RGBA')), s):
                print(r['name'], 'strip differs from a rebuild')
                ok = False
        print('pack27 fx check:', 'OK' if ok else 'FAILED')
        return ok
    os.makedirs(OUT, exist_ok=True)
    for r, s in zip(rows, strips):
        Image.fromarray(s).save(os.path.join(ART, r['file']), optimize=True)
    open(SPEC, 'w', newline='').write(spec)
    open(SUMS, 'w', newline='').write(sums)
    open(SOURCES, 'w', newline='').write(sources_text())
    for r in rows:
        print(f"{r['kind']} {r['name']}: {r['w']}x{r['h']}, offset {r['dx']},{r['dy']}, {r['phases']} x {r['ms']} ms")
    return True


def ground(W, H):
    bg = Image.new('RGBA', (W, H), (52, 46, 40, 255))
    d = ImageDraw.Draw(bg)
    for x in range(0, W, 32):
        d.line([(x, 0), (x, H)], fill=(66, 60, 52, 255))
    for y in range(0, H, 32):
        d.line([(0, y), (W, y)], fill=(66, 60, 52, 255))
    return bg, d


def preview(out):
    os.makedirs(out, exist_ok=True)
    rows = list(csv.DictReader(open(SPEC, newline='')))
    S = 3
    for r in rows:
        w, h, n = int(r['w']), int(r['h']), int(r['phases'])
        s = Image.open(os.path.join(ART, r['file'])).convert('RGBA')
        W, H = w * 32, h * 32
        frames = []
        for f in range(n):
            if r['kind'] == 'missile':                  # the east pattern (2, 1)
                art = s.crop(((2 * n + f) * W, H, (2 * n + f + 1) * W, 2 * H))
            else:
                art = s.crop((f * W, 0, (f + 1) * W, H))
            bg, d = ground(W, H)
            tx, ty = (w - 1 - int(r['dx'])) * 32, (h - 1 - int(r['dy'])) * 32
            d.rectangle([tx, ty, tx + 31, ty + 31], outline=(150, 120, 60, 255))     # the target tile
            bg.alpha_composite(art)
            frames.append(bg.resize((W * S, H * S), Image.NEAREST))
        sheet = Image.new('RGBA', (len(frames) * (W * S + 4), H * S), (20, 18, 22, 255))
        for i, f in enumerate(frames):
            sheet.paste(f, (i * (W * S + 4), 0))
        sheet.convert('RGB').save(os.path.join(out, r['name'] + '_frames.png'))
        g = [f.convert('RGB') for f in frames]
        g[0].save(os.path.join(out, r['name'] + '.gif'), save_all=True, append_images=g[1:],
                  duration=int(r['ms']), loop=0)
    print('preview:', out)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    b = sub.add_parser('build')
    b.add_argument('--src', action='append', default=[])
    b.add_argument('--check', action='store_true')
    p = sub.add_parser('preview')
    p.add_argument('--out', required=True)
    a = ap.parse_args()
    if a.cmd == 'build':
        sys.exit(0 if build(a.src, a.check) else 1)
    preview(a.out)


if __name__ == '__main__':
    main()
