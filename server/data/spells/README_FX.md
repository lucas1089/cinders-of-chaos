# Spell effects (dark-fantasy set, our own art)

Every spell effect and spell projectile is drawn by `client/tools/sprites/gen_effects.py`: noise fields, particles and
polygons quantised to small palette ramps (deep reds and embers, violet shadow, sickly greens, cold blues) with crisp
alpha. No sprite from any client is copied, traced or recoloured. The spec table is
`client/tools/sprites/fx_custom.csv` (category, id, name, mode, use, theme, style, palette, size, frames, ms, opts, note).

Area spells put the same effect on every tile of a 7x7..13x13 area, so the art is built not to turn into a tinted carpet:
- `use=area` (104 effects, everything an area spell or a hit can show): 1x1, drawn off-centre as separate crisp shapes and
  particles, no halo or haze layer, and 3x3 pattern variants (the client picks one by tile position, `x % 3`, `y % 3`), so
  neighbouring tiles differ. At least 65 % of the pixels of every 32x32 frame stay fully transparent (enforced; the run
  prints per-effect stats and writes `fx_alpha_stats.csv`). Rings are broken into irregular arcs.
- `use=single` (31: teleport, notes, stun, self buffs, portals, skull, eye, rune circles...): one picture, may be 2x2
  and may use full centred rings; still no haze.
- Every effect bursts and dissipates: grows, peaks, fades, last frame (nearly) empty, 400..900 ms in total.
- Effects carry no light flag (dozens of lit tiles tinted the whole screen); glowing missiles have a small light (2).

- **replace**: 83 stock magic effects and 25 stock missiles are redrawn at the same id, so stock spell scripts work
  unchanged. The list covers every `CONST_ME_*` / `CONST_ANI_*` or numeric id used by the scripts registered in the base
  server's `spells.xml` (runes, instant spells, monster spells; the chaos spells use their own ids), the hit effects the
  engine shows when damage lands (`Game::combatGetTypeInfo` and the block effects in `game.cpp`, life/mana drain and the
  critical hit in `combat.cpp`), and the extra area effects monster XML attacks name (shimmers, notes, plants, energy,
  smoke). Weapon ammunition missiles are left alone unless a spell script uses them (large rock, snowball and flash arrow
  are used by monster spells, so they are redrawn in a shape that still reads as the thrown object).
- **append**: our 52 effects (ids 372..423) and 10 missiles (ids 116..125), same names and ids as before. 415..423 are
  the combat feedback set shown by `server/data/scripts/chaos/combat_fx.lua` (see "Combat feedback" below).
  Names and ids: `effects_catalog.csv` (generated from `fx_custom.csv`); Lua: `server/data/lib/chaos_fx.lua`
  (`Fx("fire_nova", CONST_ME_FIREAREA)`, `FxMissile("fire_bolt", CONST_ANI_FIRE)`).

Overview of all 170 pictures: `client/tools/sprites/fx_sheets/custom_overview.jpg`. `--preview DIR` writes full
filmstrips (every frame, all nine missile directions, 2x) and `tiled_*.png`: each effect on a 7x7 area over a grey-brown
ground at two frames, as the client draws it, to catch carpet patterns before they reach the client.

Server limit: magic effects are uint16 end to end in the base server source (`MagicEffectClasses : uint16_t`,
`ProtocolGame::sendMagicEffect` writes u16, `Combat` params `impactEffect` uint16_t, Lua `Position:sendMagicEffect`), so ids
above 255 work with the client feature `GameMagicEffectU16` (enabled in our 10.98 profile). No server patch needed.
Distance shots (`sendDistanceShoot`, `distanceEffect`) are uint8: max 255, our new ids stop at 125.

## Building the client pair (local, in this order; the spr is ~500 MB and is not committed)

```
cd client/tools/sprites
# 1. outfits (donor client source A_dat.dat / A.spr, our originals Tibia.dat / Tibia.spr)
python3 -I merge_outfits.py --src-dat A_dat.dat --src-spr A.spr --ours-dat Tibia.dat --ours-spr Tibia.spr \
    --report report.csv --out-dir out/outfits
# 2. effects + missiles (procedural), chained on the outfit result -> ONE pair in out/final/
python3 -I gen_effects.py --ours-dat out/outfits/Tibia.dat --ours-spr out/outfits/Tibia.spr --out-dir out/final \
    [--preview out/fx_preview] [--overview fx_sheets/custom_overview.jpg]
```
Use `out/final/Tibia.dat` + `Tibia.spr` in the client. Without the outfit merge, pass the original Tibia.dat/.spr as
`--ours-*`; the effect ids are the same either way (372.. / 116..). An earlier output that has fewer appended effects (for example the 414-effect pair
made before 415..423 existed) is also valid input: the missing ids are appended. Running `gen_effects.py` again on its own output is
fine (the ids are rebuilt in place and every sprite is reused, so the pair comes out identical). The script appends its
sprites to the spr, rebuilds only the listed dat entries, then verifies: the output dat is re-parsed, every written
frame and missile direction is rendered back from the output spr and compared pixel-exact with the generated picture,
and all other dat entries plus 3000 sampled old sprites are checked unchanged (about 35 s in total).

`chaos_fx.lua` and `effects_catalog.csv` are also written to `out/final/` (they must equal the committed ones). To update
the committed files after editing `fx_custom.csv`, add `--lua-out ../../../server/data/lib/chaos_fx.lua --catalog-out
../../../server/data/spells/effects_catalog.csv`; `--lua-out` refuses to write if a chaos name or id would change. The
server never reads the dat; effect ids are only numbers. The scripts never modify their input files.

To change a picture, edit its row in `fx_custom.csv` (use, style, palette, size 1 = 32 px or 2 = 64 px (single only), frames, ms per frame,
style options such as `rings=2;ry=0.6`) and rerun. Styles: burst, nova, flame, shards, sparks, cloud, skull, rays, pillar,
splash, slash, impact, eruption, thorns, sparkle, rings, circle, swirl, tornado, aura, bubbles, notes, stun, hearts,
meteor; missiles: orb, bolt, shard, arrow, dart, rock, spin. Palettes are listed at the top of `gen_effects.py`.

## Combat feedback (ids 415..423)

Drawn by the styles `critstar`, `whoosh`, `aegis` and `imbue` in `gen_effects.py`; sent only by `combat_fx.lua`.

| id | name | use | look |
|---|---|---|---|
| 415 | crit_burst | single 2x2 | critical hit: eight sharp blades (four long, four short) snap open around a white-hot core, then retract; a few sparks (palette `crit`) |
| 416 | dodge_whoosh | single 2x2 | dodge: three tapered speed streaks sweep across the creature, a crescent afterimage edge, dust at the feet (palette `wraith`) |
| 417 | reflect_aegis | single 2x2 | reflect: a heater-shield outline flashes, a glint crosses it, three short arcs bounce outward (palette `aegis`) |
| 418..423 | imbue_fire / _ice / _energy / _earth / _death / _holy | area 1x1, 3x3 variants | elemental weapon hit: a thin crescent edge trail in the element colour plus embers / glints / micro arcs / spores / dark wisps / motes; at least 91 % of every frame transparent, because it shows on every auto attack |

To rebuild the client pair with them, run the two commands above (the dat must come from this `fx_custom.csv`); the
server needs the updated `server/data/lib/chaos_fx.lua` (committed) loaded before `combat_fx.lua` (the script
`dofile`s it when `ChaosFx` is missing). Without the new pair the client ignores the ids 415..423 ("invalid effect id"
in its log) and only the text labels and the engine's own hit effects show.
