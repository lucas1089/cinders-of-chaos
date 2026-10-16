#!/usr/bin/env python3
"""List icons of the Cosmetics window's effects (client/MANIFEST.md "Cosmetics effect previews").

    python3 -I gen_cosmetic_fx_icons.py --pair DIR            # Tibia.dat / Tibia.spr in DIR -> the icons
    python3 -I gen_cosmetic_fx_icons.py --pair DIR --check    # the icons on disk match the pair

Every effect a spell skin or a kill effect plays (server cosmetics_config.lua through cosmetics_core.lua C.playRows,
the ids of server/data/lib/chaos_*fx*.lua) gets a 32 x 32 picture: the frame of the effect with the most opaque
pixels, cropped to its pixels' bounding box and fitted (whole-number zoom when it is small, a smooth shrink when it is
large), centred. A missile is drawn flying south-east (the pattern the server's preview shows). Names are
`<type>_<name>.png` (fx_, vfx_, missile_, vmissile_), the `n` of a play step; game_cosmetics shows the row's main
effect with it and falls back to the sprites themselves when a picture is missing. Output:
client/overlay/modules/game_cosmetics/images/fx/. The pair is not in git, so CI does not run this; rerun it when the
pair or the cosmetics change.
"""
import argparse
import io
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, '..', '..', '..'))
OUT = os.path.join(REPO, 'client', 'overlay', 'modules', 'game_cosmetics', 'images', 'fx')
SIZE = 32

LUA_DUMP = r'''
for _, f in ipairs({"chaos_fx", "chaos_vfx", "chaos_vfx_art", "chaos_big_fx_ids", "chaos_class_fx_ids",
    "chaos_pack_fx_ids", "chaos_pack27_fx_ids", "chaos_pack29_fx_ids", "chaos_status_fx_ids"}) do
  pcall(dofile, "data/lib/" .. f .. ".lua")
end
dofile("data/scripts/chaos/cosmetics_core.lua")
local cfg = dofile("data/scripts/chaos/cosmetics_config.lua")
local K = ChaosCosmeticsCore
local function lookup(k, n)
  if k == "fx" then return ChaosFx and ChaosFx[n]
  elseif k == "vfx" then return ChaosVfx and ChaosVfx[n]
  elseif k == "missile" then return ChaosFxMissile and ChaosFxMissile[n]
  else return ChaosVfxMissile and ChaosVfxMissile[n] end
end
local seen = {}
for _, c in ipairs(cfg.cosmetics) do
  for _, r in ipairs(K.playRows(c, lookup)) do
    for _, side in ipairs({"a", "b"}) do
      local s = r[side]
      if s and not seen[s.n] then
        seen[s.n] = true
        print(s.n .. " " .. s.id .. " " .. (s.m and 1 or 0))
      end
    end
  end
end
'''


def specs():
    """[(name, id, missile)] of every play step's effects, from the server config"""
    out = subprocess.run(['luajit', '-e', LUA_DUMP], cwd=os.path.join(REPO, 'server'), capture_output=True,
                         text=True, check=True).stdout
    rows = []
    for line in out.splitlines():
        n, i, m = line.split()
        rows.append((n, int(i), m == '1'))
    return sorted(rows)


def fit(img, size=SIZE):
    """crop an RGBA image to its opaque pixels and fit it into size x size, centred; None when empty"""
    from PIL import Image
    bb = img.getchannel('A').getbbox()
    if not bb:
        return None
    crop = img.crop(bb)
    w, h = crop.size
    if w <= size and h <= size:
        z = max(1, min(size // w, size // h))
        crop = crop.resize((w * z, h * z), Image.NEAREST)
    else:
        s = min(size / w, size / h)
        crop = crop.resize((max(1, round(w * s)), max(1, round(h * s))), Image.LANCZOS)
    out = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    out.alpha_composite(crop, ((size - crop.size[0]) // 2, (size - crop.size[1]) // 2))
    return out


def frame(t, spr, phase, px=0, py=0):
    """one frame of a thing (all tiles, layer 0), w*32 x h*32, as the client draws it"""
    from PIL import Image
    from datspr import sprite_index
    canvas = Image.new('RGBA', (t.w * 32, t.h * 32), (0, 0, 0, 0))
    for hh in range(t.h):
        for ww in range(t.w):
            sid = t.sprites[sprite_index(t, px % t.px, py % t.py, 0, 0, phase, ww, hh)]
            a = spr.sprite(sid)
            if a is not None:
                canvas.alpha_composite(Image.fromarray(a, 'RGBA'), ((t.w - 1 - ww) * 32, (t.h - 1 - hh) * 32))
    return canvas


def best_frame(t, spr, px=0, py=0):
    """the frame with the most opaque pixels"""
    import numpy as np
    best, best_n = None, -1
    for ph in range(t.phases):
        im = frame(t, spr, ph, px, py)
        n = int((np.asarray(im)[:, :, 3] > 40).sum())
        if n > best_n:
            best, best_n = im, n
    return best


def thing_of(dat, tid, missile):
    lst = dat.missiles if missile else dat.effects
    return lst[tid - 1] if 1 <= tid <= len(lst) else None


def build(pair, check=False):
    sys.path.insert(0, HERE)
    from datspr import Dat, Spr
    dat = Dat(os.path.join(pair, 'Tibia.dat'))
    spr = Spr(os.path.join(pair, 'Tibia.spr'))
    os.makedirs(OUT, exist_ok=True)
    bad = 0
    names = set()
    for n, tid, missile in specs():
        t = thing_of(dat, tid, missile)
        if t is None:
            print(f'{n}: id {tid} is not in the pair'); bad += 1
            continue
        im = fit(best_frame(t, spr, 2 if missile else 0, 2 if missile else 0))
        if im is None:
            print(f'{n}: empty'); bad += 1
            continue
        names.add(n + '.png')
        path = os.path.join(OUT, n + '.png')
        buf = io.BytesIO()
        im.save(buf, 'PNG', optimize=True)
        data = buf.getvalue()
        if check:
            from PIL import Image, ImageChops
            if not os.path.exists(path) or ImageChops.difference(Image.open(path).convert('RGBA'), im).getbbox():
                print(f'{n}: out of date'); bad += 1
        else:
            with open(path, 'wb') as f:
                f.write(data)
    stale = sorted(set(f for f in os.listdir(OUT) if f.endswith('.png')) - names)
    for f in stale:
        if check:
            print(f'{f}: no effect uses it'); bad += 1
        else:
            os.remove(os.path.join(OUT, f))
    print(f'cosmetic fx icons: {len(names)} {"checked" if check else "written"}, {bad} problem(s)')
    return bad


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--pair', required=True, help='folder with Tibia.dat and Tibia.spr')
    ap.add_argument('--check', action='store_true')
    a = ap.parse_args()
    sys.exit(1 if build(a.pair, a.check) else 0)


if __name__ == '__main__':
    main()
