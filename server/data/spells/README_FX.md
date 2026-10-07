# Custom spell effects (dark-fantasy set)

43 magic effects (ids 372..414) and 10 distance missiles (ids 116..125) taken from the Black Talon 10.98 dat/spr and
appended to our Tibia.dat/.spr. Names and ids: `effects_catalog.csv`; Lua: `server/data/lib/chaos_fx.lua`
(`Fx("fire_nova", CONST_ME_FIREAREA)`, `FxMissile("fire_bolt", CONST_ANI_FIRE)`). Previews: `client/tools/sprites/fx_sheets/`
(`picked_*.jpg` = the chosen ones). Pick list: `client/tools/sprites/fx_picks.csv`.

Server limit: magic effects are uint16 end to end in the Exodus source (`MagicEffectClasses : uint16_t`,
`ProtocolGame::sendMagicEffect` writes u16, `Combat` params `impactEffect` uint16_t, Lua `Position:sendMagicEffect`), so ids
above 255 work with the client feature `GameMagicEffectU16` (enabled in our 10.98 profile). No server patch needed.
Distance shots (`sendDistanceShoot`, `distanceEffect`) are uint8: max 255, our new ids stop at 125.

## Running both merges (local, in this order; the merged spr is ~500 MB and is not committed)

```
cd client/tools/sprites
# 1. outfits (Black Talon source A_dat.dat / A.spr, our originals Tibia.dat / Tibia.spr)
python3 -I merge_outfits.py --src-dat A_dat.dat --src-spr A.spr --ours-dat Tibia.dat --ours-spr Tibia.spr \
    --report report.csv --out-dir out/outfits
# 2. effects + missiles, chained on the outfit result -> ONE pair in out/final/
python3 -I merge_effects.py --src-dat A_dat.dat --src-spr A.spr \
    --ours-dat out/outfits/Tibia.dat --ours-spr out/outfits/Tibia.spr --out-dir out/final
```
Use `out/final/Tibia.dat` + `Tibia.spr` in the client. Without the outfit merge, pass the original Tibia.dat/.spr as
`--ours-*`; the effect ids are the same either way (372.. / 116..). Each script re-parses its result and checks the added
things pixel-identically against the source. `mapping.csv`, `effects_catalog.csv` and `chaos_fx.lua` are also written to
`out/final/` (they must equal the committed ones). The server never reads the dat; effect ids are only numbers.
The scripts never modify their input files.
