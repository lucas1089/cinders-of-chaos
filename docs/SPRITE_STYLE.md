# Sprite style guide

How a new sprite of ours should look, for anyone (agent or person) drawing 32 x 32 sprites for the client.
Every number here was measured with `client/tools/sprites/style_check.py report` (run it again to refresh them).
The checker `style_check.py check` tests a sprite against these rules.

## Reference art

Only art we may use as a reference:

- **The owner's seven gear set sheets**, `client/tools/sprites/art_import/gear_sets/<set>.png`. The owner made them
  for us (`gen_gear_sets_art.py`, docs/CREDITS.md "Owner art"). Each is an 8 x 8 grid of 32 px item icons of one
  theme. They are the main reference: the themes and their palettes come from them.
- **The owner art of pair 26**, `art_import/owner_art/` (monster looks, wings, cacti, a floor seal;
  `gen_owner_art.py`). Used for the outfit frames, the anchors and the light of creatures.
- **Our own generated art**: the generator scripts of `client/tools/sprites/` and their outputs in git
  (`gen_effects.py` and `fx_custom.csv`, `gen_class_fx.py`, `gen_big_fx.py`, `gen_necro_fx.py`, `gen_theme_art.py`).
  Used for the effect frame counts.

Purchased packs and the other Drive sets are **not** a reference. The licence audit of 2026-10-15 found one licence
file in the Drive folder, and it forbids use as AI training material (the effects gigapack of docs/CREDITS.md, so also
its author's other packs); the other packs have no licence text there, so none is allowed until the owner confirms
its terms. Imported pack art in the pairs stays as it is. Do not trace, recolour or sample any other game's or
server's sprites.

## Grid, size and anchors

- One sprite is **32 x 32 px**. A thing is w x h tiles of 32 px (items 1 x 1; creatures and wings 2 x 2 to 4 x 4,
  that is 64 to 128 px; effects 1 x 1 to 9 x 9).
- **Draw at 1:1.** One art pixel is one screen pixel. Never upscale a 16 px or 32 px drawing to fill a bigger thing:
  the checker refuses art drawn in 2 x 2 blocks.
- A sheet is a grid of whole cells. The image width and height are multiples of the cell (32, or 64 for 2 x 2
  things). Nothing crosses a cell edge.
- **Items fill the tile.** The owner's items use the whole cell: the art box is about 30 x 30 (median 28-30 wide,
  30-31 high), with a margin of 1 px (0 to 2) on each side. Do not draw a small icon in the middle of the cell.
- **Things are anchored bottom right.** The client draws a thing's bottom-right 32 x 32 cell on its own tile and the
  other cells up and to the left. A creature stands at the bottom right of its frame: in the owner's 2 x 2 monsters
  the art ends 0-1 px from the right and bottom edges (the behemoth 3 px).
- **Displacement** moves a whole thing up and left by that many pixels (dat flag `displacement:x:y`):
  - player looks: 2 x 2 tiles, displacement 8, 8 (the stock player place; client/MANIFEST.md "New class look art");
  - the owner's monsters: 2 x 2 or 4 x 4 tiles, no displacement;
  - wings: 3 x 3 tiles, none (two owner wings use -6, -12);
  - auras: centre of the art on the feet point (14, 20) (client/MANIFEST.md "Raid boss and faction looks");
  - effects: the send offset `dx, dy` = (w - 1) / 2 tiles, so a 3 x 3 effect has 1, 1 and is centred on the target.
- An outfit cannot draw past the right or bottom edge of its frame. Weapons and strides that would cross it are held
  up or shortened (`class_art.py edges`). `compose_outfit.py` lowers the displacement when a layer reaches past it.

## View and light

- **Oblique top-down view.** We look down from the front and above. A figure leans up and left with its
  height (`gen_outfit_anchors.py`). Items are shown as if lying on the ground, seen from above and in front.
- **The light comes from the top, a little left.** The checker measures the rim light: the mean luma of the body
  pixels next to its left edge minus its right edge, and next to its top edge minus its bottom edge.
  - The gear sheets: from 74 to 100 degrees, mean **94 degrees** (90 is straight above, 180 is from the left).
    The top rim is about 17 luma brighter than the bottom rim; left and right are almost equal.
  - The owner's 2 x 2 monsters: 104 to 133 degrees, from the top left.
  - So: light the top and top-left faces, shade the bottom and bottom-right. Cast no shadow on the ground.
- Light sources inside the art (embers, runes, frost glow, eyes) may light from below locally. That is allowed; the
  checker only refuses a sprite lit clearly from the opposite side.

## Outline

- **One pixel, near-black, all round.** On the gear sheets 98% of the rim pixels (opaque pixels next to
  transparency) have a luma under 24; the mean outline luma is 4.6. Only 12% of the second ring is that dark,
  so the outline is one pixel thick.
- **Not pure black: tinted toward the theme.** The most used outline colours:

| theme | outline colours |
|---|---|
| cinderwrought | `#070102` `#050000` `#040202` |
| wyrmscale | `#020202` `#030100` `#010301` |
| rimewraith | `#010507` `#010206` `#020203` |
| azurevigil | `#020101` `#020205` `#040404` |
| bloodmoon | `#050000` `#050102` `#060303` |
| gildcrown | `#050101` `#070000` `#050303` |
| blightfang | `#010201` `#010102` `#030303` |

- **Selective outline only for light.** Glowing parts (flames, embers, frost light) may drop the outline where they
  shine: the lowest owner cell still has 39% of its rim dark. The checker wants at least 30%.
- **Inner lines** are dark too: 6-21% of the inside pixels are under luma 24 (plate seams, straps, gem settings).
- Two owner ice monsters (golem_ice, dragon_ice) use a dark blue outline instead. Do not copy that for items.

## Palettes and shading

- **Each theme is one fixed palette.** Every sheet uses 56 to 87 colours, and each row of a sheet uses only colours
  of the other seven rows (held-out distance 0). New art of a theme uses exactly that palette:
  `style_check.py snap IN.png OUT.png --theme NAME` moves every pixel to the nearest theme colour.
- The full palettes, sorted dark to light and grouped by hue family, are in
  `client/tools/sprites/style_palettes.json` (`themes.<name>.palette` and `.ramps`).
- The themes' palettes are far apart: the other sheets' cells sit at a mean CIE76 distance of 9 to 24 (median) from a
  theme's palette. The checker allows a mean of 4.5 and 10% far pixels (distance over 12).

| theme | words | colours | light (deg) | ramps (family: colours, darkest .. lightest) |
|---|---|---|---|---|
| cinderwrought | fire and ember | 71 | 99 | red 20 `#3c130e`..`#c42e04`; orange 24 `#5c3f34`..`#dabd89`; yellow 4 `#fdb51d`..`#f2e39a`; grey 8 |
| wyrmscale | green dragon | 56 | 94 | green 11 `#0a2607`..`#b0f978`; red 8 `#36171d`..`#954f3e`; orange 6; grey 12 |
| rimewraith | teal frost, spectral | 71 | 93 | teal 31 `#0d2a32`..`#8bfffa`; grey 20 `#0b1f28`..`#f6f8f8`; violet 5 `#503f60`..`#c384ed` |
| azurevigil | blue and gold paladin | 87 | 92 | blue 21 `#082e4c`..`#73b3ce`; orange 14 `#3b2b14`..`#ddab78`; yellow 9 `#3d3319`..`#fcedbd`; violet 7; grey 15 |
| bloodmoon | crimson, blood | 77 | 74 | red 25 `#381216`..`#b85d4a`; orange 19 `#623721`..`#ffe1b5`; grey 8; blue 4; violet 4 |
| gildcrown | gold | 79 | 98 | orange 45 `#291506`..`#e9b44c`; yellow 13 `#c69f4e`..`#fefbbd`; grey 5; red 3 |
| blightfang | dark green, venom | 67 | 100 | grey 37 `#1a1818`..`#f6f9f7`; green 9 `#335e44`..`#b0ffc2`; orange 5 `#895813`..`#f4be5c` |

Each theme also has 11 to 15 near-black colours (luma under 24): the outlines and the deepest shadows.

The most used colours of each main ramp, dark to light (use them as the shading steps of a material):

- cinderwrought: metal `#3c130e #470e10 #540d0d #5c150f #531b11 #5f1e0d`; fire `#803412 #d44512 #cb5622 #e35c18
  #f16902 #f5941c`; flame tips `#fdb51d #fedf31 #f9dc58 #f2e39a`
- wyrmscale: scales `#0a2607 #103d1a #174b1c #2c7834 #36913b #508e43`; leather `#36171d #4b1512 #461c0f #601300
  #68200e #932822`
- rimewraith: frost `#183e42 #234a4f #315059 #335a5e #519091 #5e9c95`; steel `#0b1f28 #131e2b #192734 #232a3a
  #34454b #41505b`; spirit `#503f60 #615474 #745b89 #a55acc #c384ed`
- azurevigil: blue `#193040 #183c58 #1d445e #1d537c #215e86 #59b0d6`; gold `#584121 #815824 #9f7024 #b27a22 #be8a2a
  #d6a23d`, highlights `#c7a651 #e1b345 #debb6e #f0cc6a #f3e9b1`
- bloodmoon: crimson `#4f0e16 #3d1913 #3f1b1f #4f1716 #681824 #a93132`; brass `#955b31 #a56d3f #c17f41 #d2975b
  #e5b45c`
- gildcrown: gold `#311503 #532e06 #5e2f08 #65360b #68440c #7f4d11`; bright gold `#e8b12f #f8c23f #f5c859 #fad242
  #f7d857 #f9e967`
- blightfang: iron `#1f2225 #262a2d #2f2d2e #333839 #424748 #535958`; venom `#335e44 #0c9842 #4c7f5c #82a683 #67cc74
  #9dd2a3`

Shading rules from the sheets:

- **Many small steps, not three flat bands.** A 32 px item uses 19 to 61 colours (median 33 to 53 per sheet). The
  checker wants 11 to 68.
- **Fine texture inside a fixed palette.** In the owners' art 42% of the body pixels share their colour with none of
  their four neighbours: metal grain, scales and cloth weave are drawn pixel by pixel. That is texture with a
  direction (along a blade, across a scale), not random speckle. The checker refuses more than 87%.
- **Hue shifts with value**: the dark steps of a ramp lean warm or toward the theme's shadow hue; the light steps
  lean toward yellow or white (see the ramps above).

## Dithering, anti-aliasing and transparency

- **No ordered dithering.** Checkerboard 2 x 2 blocks are 0.0 to 0.8% of the pixels of a piece.
- **Anti-aliasing only inside the outline**, with the palette's in-between colours. Never against the background.
- **Alpha is 0 or 255.** The seven sheets have no semi-transparent pixel. A background is fully transparent, or one
  exact key colour (`#ff00ff`, the spr colour key) with no near-key fringe.
- Soft alpha is for effects and glows only (`alpha=soft` in `big_fx.csv` and `status_fx.csv`; five owner feather
  wings have 23% soft pixels). Nothing below alpha 12 (`gen_owner_art.ALPHA_MIN`). Check these with `--soft`.
- No lone pixels, no two-pixel specks, no pinholes. The owners' cells have at most 1 lone pixel, 1 speck and 6
  one-pixel holes (the links of a chain).

## Item silhouettes per slot

Measured on the 448 gear pieces (`report`, "Item silhouettes per kind"). Box = the art's bounding box in the cell.

| kind | box w x h (median) | fill of the box | shape (by eye, cinderwrought sheet) |
|---|---|---|---|
| helmet | 26 x 29 | 0.62 | front view, visor or face opening dark; horns and crests reach the cell edge |
| armor | 30 x 30 | 0.68 | front view, shoulders at the top corners, flat bottom hem |
| legs | 26 x 30 | 0.71 | two legs side by side, waistband at the top |
| boots | 28 x 28 | 0.66 | a pair, one in front of the other, toes to the left |
| shield | 24 x 30 | 0.75 | upright, a boss or emblem in the centre |
| spellbook | 26 x 30 | 0.90 | a closed book, cover toward the viewer, slightly turned |
| sword, axe, club, wand, rod | 30 x 30 to 31 x 31 | 0.25 to 0.36 | corner to corner on a diagonal (both diagonals occur) |
| bow | 31 x 31 | 0.24 | the arc on a diagonal, the string drawn |
| crossbow | 30 x 30 | 0.42 | the stock on a diagonal, the bow across it |
| amulet | 26 x 30 | 0.40 | chain loop at the top, pendant below the centre |
| ring | 25 x 28 | 0.67 | big, seen from above at an angle, the stone on top |

Weapons use the whole diagonal of the tile; armour and jewellery are centred and upright.

## Creatures, outfits and wings

The layout `import_art_things.py` reads (its docstring is the reference; `compose_outfit.py` writes the same):

- **Directions:** 4, in the order north, east, south, west (columns of the sheet).
- **Frame groups:** idle and walking. The sheet has one row per group and phase, the idle phases first.
  - Our player looks: idle 2 phases (a 1 px breath, 600 ms) and walking 4 (`--layout 2+4`), or the stock 1 + 8.
  - The owner's 2 x 2 monsters: idle 1, walking 8 (golems, brute, dragon, yeti, behemoth) or 3 (drakes), 100 ms a
    phase. The 4 x 4 lions: idle 1, walking 3.
  - Wings: one group, animated always, 9, 8 or 5 phases of 110 to 140 ms.
- **Layers:** a player look has 2: the art and the colour mask (template). The mask paints the parts the player
  colours in pure `#ffff00` head, `#ff0000` body, `#00ff00` legs, `#0000ff` feet; nothing else (`check_pair.py`
  warns at more than 16 other colours). Monsters and wings have 1 layer.
- **Addons:** pattern y, up to 3 (base and 2 addons). An addon pattern holds only the pixels that change when the
  addon is worn; the client draws it over pattern 0.
- **Mounts:** pattern z, up to 2 (on foot, riding).
- **Column order of a sheet:** ((z * addons + y) * layers + layer) * 4 + direction.
- The 64 px owner monsters use 16 to 37 colours a frame and a dark rim (84-98% under luma 24) like the items; the
  two ice looks have a dark blue rim instead. The 4 x 4 lions are painted with thousands of colours; do not copy that for new pixel art.

## Effects and missiles

Frame counts of our generated effects (`report`, last section):

| source | things | size | frames (min / median / max) | ms a frame (median) |
|---|---|---|---|---|
| `fx_custom.csv` effects | 140 | 1 x 1 (117), 2 x 2 (23) | 5 / 9 / 14 | 70 |
| `fx_custom.csv` missiles | 35 | 1 x 1 | 2 / 4 / 4 | 80 |
| `class_fx.csv` | 35 | 3 x 3 (33), 1 x 1 (2) | 6 / 8 / 8 | 90 |
| `necro_fx.csv` | 7 | 2 x 2 (6), 1 x 1 (1) | 6 / 8 / 8 | 90 |
| `big_fx.csv` | 21 | 5 x 5, 7 x 7, 9 x 9 | 10 / 12 / 13 | 70 |

- An effect plays once. Small effects take 6 to 10 frames (median 8 to 9), the large 5 x 5 to 9 x 9 ones 10 to 13.
- A missile loops while it flies and has 3 x 3 direction patterns (x west / centre / east, y north / centre / south).
- An effect strip is the frames left to right, each w * 32 x h * 32 (`import_fx_art.py`).

## Checklist before import

1. The art is ours: drawn here, generated by our scripts, or the owner's own. No pack art until the audit allows it.
   Every third-party source that ships goes into docs/CREDITS.md.
2. 1:1 pixels, a whole number of 32 px cells, nothing across a cell edge, anchored bottom right.
3. Items fill the cell (box about 30 x 30, 1 px margin).
4. A one-pixel near-black outline in the theme's outline colours; glowing parts may drop it.
5. Lit from the top, a little left; shade the bottom right.
6. Colours snapped to one theme (`style_check.py snap`); 11 to 68 colours a 32 px cell.
7. Alpha 0 or 255 (effects: `--soft`), no lone pixels, specks or pinholes.
8. Creatures: 4 directions, idle and walk groups, the mask in the four pure template colours.
9. `style_check.py check` passes:

```
/tmp/fxenv/bin/python -I client/tools/sprites/style_check.py check NEW.png --theme cinderwrought
/tmp/fxenv/bin/python -I client/tools/sprites/style_check.py check SHEET.png --theme gildcrown --cell 32
/tmp/fxenv/bin/python -I client/tools/sprites/style_check.py check FX.png --palette PAL.png --soft --cell 96
```

   It prints PASS or FAIL per image and one line per failed cell and reason; it exits 1 on any failure. `--verbose`
   also prints the light warnings of passing cells.

## Importing

- Put the art in `client/tools/sprites/art_import/` through a generator script (`gen_<name>_art.py` with a `build`
  and a `build --check` mode, like `gen_gear_sets_art.py` or `gen_owner_art.py`) that writes the atlas and the things
  file (`<name>.csv`, columns of `import_art_things.py`). Wire `build --check` into `.github/workflows/ci.yml`.
- Append to a copy of the live pair:

```
cd client/tools/sprites
python3 -I import_art_things.py --ours-dat P/Tibia.dat --ours-spr P/Tibia.spr --out-dir NEW \
    --things art_import/<name>.csv --first-item N --expect-items N-1 [--first-outfit M]
```

  Effects and missiles go through `import_fx_art.py` (a spec like `art_import/class_fx.csv`).
- Check the new pair, append-only against the old one:

```
python3 -I client/tools/sprites/check_pair.py NEW/Tibia.dat NEW/Tibia.spr --old P/Tibia.dat P/Tibia.spr --new-only
```

- Record the pair's md5s in client/MANIFEST.md and add a section for the new things.

## Thresholds

`client/tools/sprites/style_palettes.json` holds the palettes, the thresholds and the owners' measured ranges.
`style_check.py build-palettes` makes it from the seven sheets: every owner cell passes its own theme with a margin.
CI runs `build-palettes --check` and `style_check_test.py`. Do not edit the JSON by hand; when the owner sends new
sheets, add them to `THEMES` in `style_check.py` and rebuild.
