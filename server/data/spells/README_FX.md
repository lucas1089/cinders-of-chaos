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

## Animated pack effects (effects 429..558, missiles 126..136, auras)

Hand-drawn animated effects from three art sets the project owns, appended after the procedural ids by
`client/tools/sprites/import_vfx.py` (spec table `client/tools/sprites/vfx_import.csv`; catalogue with sizes and send
offsets: `vfx_catalog.csv`; Lua names: `server/data/lib/chaos_vfx.lua`, written by the tool):

- 130 magic effects: 95 oblique spell effects (13 auras, 10 ground circles, 12 bursts, 8 impacts, 10 status loops, 2
  melee, and 40 directional melee hits: 5 hits x 8 directions named `<hit>_n` .. `<hit>_nw`), 20 tinted energy effects
  (power-up bursts, dome blasts, small hits, fist hits, a holy flash, light / shadow teleport pillars, chi charge,
  rising stones, an energy sphere) and 15 pixel bursts (`px<sheet>_<colour>`). Frame timing as drawn (83 ms, 50 ms, or
  the bursts' 50..100 ms); effects play once.
- 11 missiles (8 directions each, missile patterns 3x3): arcane bolt, fireball, wind arrow, holy spear, ice lance,
  lightning orb, shadow orb, venom glob, two energy blasts and a razor disc.
- 19 auras (outfit things 1511..1529 on the current pair; auras.xml ids 6..24, `server/data/XML/chaos_auras.csv`,
  installed by `server/tools/install_auras.py`, step `auras` of install_all.py; sold in the store's Auras category).

**Send offset.** The client draws a thing with its bottom-right tile on the map tile, so art bigger than a tile that
reaches right of / below the target cannot be centred there. Each pack effect is built so that its bottom-right tile is
the target tile + (dx, dy) (0..3 tiles, per effect in `vfx_catalog.csv`) and must be sent there: always use
`Vfx(pos, name)`, `VfxDir(pos, base, direction)` and `VfxShoot(fromPos, toPos, name)` from chaos_vfx.lua (spells:
`ChaosSpell.vfx`, `vfxDir`, `vfxOr`, `vshoot` in `_common.lua`; `vfxOr` / `vshoot` fall back to the chaos effect when
chaos_vfx.lua is missing). Sending the raw id with `sendMagicEffect` puts it one or more tiles up-left. A side effect: an
effect whose offset tile is outside the player's view near the bottom/right edge of the screen is not shown.

**Ids and limits.** Magic effects are u16 on the wire (GameMagicEffectU16, see above); the client reads the effect
count from the dat, so 558 is fine and far from 65535. Missiles are u8 (`sendDistanceShoot`): 136 of 255 used.
Aura look types are u16 (GameLooktypeU16); auras.xml ids are u8 (1..255) and the store marks ownership in a storage
per 31 auras (base server `Player::addAura`).

**Client features.** The auras are 2..3 tiles wide and reach into the tiles right of / below the creature. With the
per-tile painter order those tiles' ground was drawn over them (cut edges); `GameMapDrawGroundFirst` (base patch
0006, 10.98 profile) draws every ground first, so the auras show whole. Effects need no feature: their offset anchor
keeps them over tiles that are drawn earlier.

**Wired into the spells** (one pack effect at the cast point or impact; the per-tile area effects stay the procedural
ones): Rime Bloom frost_nova; Witchfire Bolt fireball missile + fireball_hit; Forked Storm lightning_orb missile +
lightning_hit; Crimson Covenant blood_pact; Falling Pyre infernal_seal at the mark, meteor_strike timed to land with the
damage; Frozen Crypt ice_lance + frost_glyph; Doomtide dome_blast_fire / storm_ring / fire_explosion per wave;
Blightswarm toxic_burst; Purifying Wellspring healing_bloom; Ironbark Hide stone_ward; Briar Prison earth_spikes;
Moonfang Pack / Wild Bond teleport_in; Verdant Sanctuary grove_glyph; Primordial Squall earth_spikes / frost_nova;
Dawnpiercer holy_spear + holy_hit; Skewering Line thrust (by facing); Blessed Earth / Consecration holy_seal;
Lightward / Aegis of Faith dawn_aegis; Final Verdict / Judgement holy_spear + holy_smite; Reaping Gyre / Whirling Heel /
Blade Flurry whirlwind (the Flurry: ninja_vanish / samurai_parry as class effects); Iaido Sweep heavy_cleave (towards
the target, on the first tile of the cut); Palm Shockwave aura_burst_gold on the target; Shadow Ricochet shadow_bolt
jumps + void_eye; Iron Chain lightning_orb links + stone_rise; Bone Shrapnel bone_spear + bone_spear burst; Sanctified
Ground holy_seal; Shield Wave dome_blast_holy in front; Fan of Knives razor_disc (the stock throwing knife without the
pack); Earthbreaker earth_spikes; Red Frenzy / Bloodrage aura_burst_red; Iron Bellow / Banner Call / Bushido Focus /
Zealotry aura_burst_gold; Vaulting Cleave / Skyfall Cleave heavy_cleave and Iaijutsu sword_slash and Feral Command
claw_rake (towards the target); Colossus Fall earth_spikes + blunt_smash; Hall of Mirrors arcane_sigil; Umbral Stride /
Shadow Step / Shadow Veil shade_vanish / shade_appear; Flickerdash blink_vanish / blink_appear; Shattered Psyche
arcane_bolt (the Necromancer's cursed went: see "Mystic line effects"); Wraithshroud shadow_shroud; Nightburst void_maw;
Tear in the Weave void_rift; Lucid Reverie starfall_crown; Mirror Mend regenerating; Soulward / Counter Stance / Chi Ward shield_bubble; Hunter's Instinct gale_ring;
Poison Blades poisoned; Smoke Bomb stunned; Raise Dead necro_seal; Withering Curse shadow_orb + cursed; Corpse
Explosion px448_green + px633_indigo; Soul Rot toxic_burst (each tick px633_green); the rest of the Necromancer line:
see "Necromancer line effects" below;
Ashen Fist / Iron Palm punch_hit_gold; Sundering Palm punch_hit_red; Pressure Points / Shadowfist Flurry
punch_hit_violet; Kindled Breath chi_charge; Mistborne Step gale_hit; Mantra of Stone stone_rise; Radiant Smite
px652_white; Vow of Mending / Lay on Hands healing_bloom; Purging Nova dome_blast_holy; Rebuke solar_flash.

**Building** (after every other step that appends to the pair; the ids depend on the counts of the input pair):
```
python3 -I import_vfx.py --ours-dat IN/Tibia.dat --ours-spr IN/Tibia.spr --out-dir out/vfx \
    --src-spells <oblique effect set> --src-ki <tintable energy set> --src-fx <pixel burst set> \
    --expect-first-effect 429 --expect-first-missile 126 --expect-first-outfit 1511 \
    --lua-out ../../../server/data/lib/chaos_vfx.lua --catalog-out ../../../server/data/spells/vfx_catalog.csv \
    --auras-out ../../../server/data/XML/chaos_auras.csv [--preview DIR]
```
The art sets are not in the repository. A pair with more outfits before this step moves the aura look types: pass the
new `--expect-first-outfit` and keep the regenerated `chaos_auras.csv` (the auras.xml ids 6..24 stay the same). The tool
verifies its output like `import_outfits.py` (re-parse, every new frame / pattern / layer pixel-exact, all old entries
byte-identical, 3000 sampled old sprites) and is deterministic.

**More uses (switch `ChaosPackFx.PACK_FX`, on since 2026-10-13 (pair 24 at 407ad9b6)):** item powers, snares, rift modifiers, world bosses and
the reflect send these effects and seven short cuts of the status loops (reflect_bubble, tick_*; effects 628-634 of
things_custom24, built by
`client/tools/sprites/gen_pack_fx.py`). Which use sends which: server/README.md "Pack effects for procs and bosses";
the cuts and the set's licence: client/MANIFEST.md "Pack effect cuts".

## Bone effects (effects 583..585, missile 153; our own art)

The Necromancer line's own effects, appended after everything above by `client/tools/sprites/import_fx_art.py` (spec
`client/tools/sprites/art_import/fx_art.csv`, frame strips in `art_import/bone_fx/` built by `gen_fistfx_art.py` from
PixelLab paintings of a bone spear, bone shards and skulls; the pieces are moved, flipped and turned per frame, never
repainted). Lua names: `server/data/lib/chaos_vfx_art.lua` (written by the tool; merged into `ChaosVfx` /
`ChaosVfxMissile`, loaded by `_common.lua`), catalogue `vfx_art_catalog.csv`.

| id | name | size, offset | frames | use |
|---|---|---|---|---|
| 583 | bone_spear | 3x3, +1,+1 | 7 x 70 ms | fallback of Bone Spear's impact (replaced by necro_spear_hit) |
| 584 | bone_burst | 3x3, +1,+1 | 9 x 80 ms | fallback of Bone Offering's burst and Corpse Explosion (replaced by bonelord_offering / px448_green): eight shards thrown out, a broken ring, dust |
| 585 | bone_aura | 3x3, +1,+1 | 14 x 90 ms | fallback of Banner of Bones (each minion) and Bone Offering (the caster) (replaced by bonelord_rally / bonelord_ward): three skulls and four shards rise and circle once |
| missile 153 | bone_spear | 1x1, 3x3 directions | 2 x 100 ms | Bone Spear's flight (`ChaosSpell.vshoot`) |

Like the pack effects they must be sent with `Vfx` / `VfxShoot` (the spells use `vfxOr` / `vshoot`, which fall back to the
stock effect when `chaos_vfx_art.lua` is missing). Build order and md5s: client/MANIFEST.md "Fist weapons and bone effects".

## Necromancer line effects (effects 586..592; style sample art)

The line's effects follow the owner-approved style sample (oblique view, light from the top-left, ash and bone with
sickly green and violet soul light, a dark outline). **Donor art first:** before drawing anything, the effects already
in the pair (this file, `vfx_catalog.csv`, `effects_catalog.csv`) and the unconverted libraries (the donor libraries'
effect sheets, the raw VFX packs of the `sprite-libraries` branch, the pixel burst set) were surveyed for each spell. Pair
effects fit the Lich (curses, rot, drain) and Raise Dead; the libraries' bone-coloured effects are dust and smoke puffs
(no bones) in a flat, unoutlined style, and the raw packs are flat top-down pastel art, so the bone effects of the Bone
Lord and the bone spear's impact are new. Choice per spell (pair ids on things_custom12):

| spell | effects sent (first one known wins, then the older one, then the stock fallback) | source |
|---|---|---|
| Bone Spear | missile bone_spear 153 (kept); impact **necro_spear_hit 586**, then bone_spear 583 | our art (gen_necro_fx.py) |
| Raise Dead | skull_orb missile 125, necro_seal 447 (kept) | pair: pack and procedural |
| Withering Curse | shadow_orb 132, cursed 475, rot ticks stock 39 (all kept) | pair |
| Soul Rot | skull_orb 125, toxic_burst 463 (was px633_green), each tick px633_green 556 (was the stock cloud) | pair: pack |
| Life Siphon | skull_orb 125 (was blood_spear), **lich_soul_drain 587** (was px448_crimson), heal: heal_sparkle 412 (was red) | the style sample itself; pair |
| Corpse Explosion | px448_green 552 (was bone_burst), px633_indigo 555 | pair: pixel bursts |
| Bone Golem | **bonelord_golem_rise 588**, then necro_seal | our art |
| Banner of Bones | caster **bonelord_banner 589**, then necro_seal; each minion **bonelord_rally 590**, then bone_aura | our art |
| Bone Offering | the skeleton **bonelord_offering 591**, then bone_burst + px633_indigo; the caster **bonelord_ward 592**, then bone_aura | our art |

| id | name | size, offset | frames | look |
|---|---|---|---|---|
| 586 | necro_spear_hit | 2x2, 0,0 | 7 x 70 ms | a violet snap, six bone splinters thrown out and falling |
| 587 | lich_soul_drain | 2x2, 0,0 | 8 x 100 ms | the style sample: a rune circle, souls spiral up into an orb, a ghost skull |
| 588 | bonelord_golem_rise | 2x2, 0,0 | 8 x 90 ms | the ground cracks, a crown of bone spikes, a ribcage and a skull with green eyes, they sink |
| 589 | bonelord_banner | 2x2, 0,0 | 8 x 90 ms | a violet ring, six bone shards circle up into a crown, a green flare, they rain back |
| 590 | bonelord_rally | 1x1, 0,0 | 6 x 90 ms | three shards spiral up a minion, a green spark |
| 591 | bonelord_offering | 2x2, 0,0 | 8 x 85 ms | a skeleton bursts: ribs, long bones and the skull in a ring of ash, scattered |
| 592 | bonelord_ward | 2x2, 0,0 | 8 x 90 ms | six rib plates grow over the caster, a violet rim, they crumble |

The 2x2 effects have the target as their bottom-right tile (offset 0,0). Art: `client/tools/sprites/gen_necro_fx.py`
(shapes in Python, one PixelLab "Edit images (Pro)" repaint of the whole sheet, moved back onto the shapes; sources in
`art_import/necro_fx_src/`, strips in `art_import/necro_fx/`, spec `art_import/necro_fx.csv`), imported by
`import_fx_art.py --merge` (the Lua names and catalogue rows are added to `chaos_vfx_art.lua` / `vfx_art_catalog.csv`).
The spells send them through `NecroSpell.fx` (`_necro.lua`): a server without these Lua names sends the older effect or
the stock one. Build commands and md5s: client/MANIFEST.md "Necromancer line effects". Test: `server/tests/necro_fx_test.lua`.

## Class signature effects (effects 593..627; our own procedural art)

Each class line's signature spells get an effect of their own, so the lines read differently in combat (they shared
aura_burst_gold, shield_bubble, healing_bloom, dawn_aegis, earth_spikes, whirlwind, shade_vanish, teleport_in, cursed
and toxic_burst, and the Ranger used the Templar's holy art). A palette and shape per line: Warrior iron, rock and
ember; Ranger amber, leaf and wind; Mystic prism and rose (the Elementalist three elements); Thief smoke, ink and
sakura; Necromancer void and soul green; Monk chi, violet and jade; Templar gold. Drawn by
`client/tools/sprites/gen_class_fx.py` (spec `art_import/class_fx.csv`, strips `art_import/class_fx/`), appended by
`import_fx_art.py` (ids in `server/data/lib/chaos_class_fx_ids.lua`, catalogue `class_fx_catalog.csv`). Which spell of
which class sends which, and the pair switch `ChaosClassFx.PAIR22_FX` (on since 2026-10-12, things_custom22 live):
server/README.md "Class signature effects". Build and md5s: client/MANIFEST.md "Class signature effects".

| id | name | size, offset | frames | look |
|---|---|---|---|---|
| 593 | warrior_quake | 3x3, 1,1 | 8 x 85 ms | warrior: the ground splits in ember cracks, slabs of rock thrown up (Earthbreaker, Colossus Fall) |
| 594 | warrior_gyre | 3x3, 1,1 | 8 x 70 ms | warrior: two steel crescents sweep a full circle at blade height (Reaping Gyre) |
| 595 | warrior_bellow | 3x3, 1,1 | 8 x 80 ms | warrior: an iron war cry; chevrons and broken rings rush outward (Iron Bellow) |
| 596 | juggernaut_bulwark | 3x3, 1,1 | 8 x 90 ms | juggernaut: an iron tower shield slams down before the caster and cracks the ground (Iron Bellow) |
| 597 | berserker_rage | 3x3, 1,1 | 8 x 80 ms | berserker: blood flames tear up around the caster, droplets spray and fall (Red Frenzy, Bloodrage) |
| 598 | berserker_cleave | 3x3, 1,1 | 7 x 70 ms | berserker: a huge crimson crescent falls overhead and splits the ground (Skyfall Cleave) |
| 599 | ranger_pierce | 3x3, 1,1 | 7 x 70 ms | ranger: a fletched arrow strikes and splits; feathers and amber splinters burst (Dawnpiercer) |
| 600 | ranger_arrowfall | 1x1, 0,0 | 6 x 80 ms | ranger: two arrows drop steeply and stick in the ground, a puff of dust (Hail of Dawn, each tile) |
| 601 | ranger_thornseal | 3x3, 1,1 | 8 x 90 ms | ranger: a ring of thorned vines grows from the earth, amber motes rise (Blessed Earth) |
| 602 | ranger_canopy | 3x3, 1,1 | 8 x 90 ms | ranger: leaves whirl up into a canopy around the caster, a gust of wind (Lightward) |
| 603 | deadeye_mark | 3x3, 1,1 | 7 x 70 ms | deadeye: a reticle closes on the target, then a piercing flash and cracks (Final Verdict) |
| 604 | beast_spirit | 3x3, 1,1 | 8 x 90 ms | beastmaster: claw rakes tear the ground, paw prints and spirit wisps of amber and green (Wild Bond) |
| 605 | mystic_mend | 3x3, 1,1 | 8 x 90 ms | mystic: prismatic petals spiral up and open, rose and cyan motes (Purifying Wellspring, Mirror Mend) |
| 606 | elementalist_glyph | 3x3, 1,1 | 8 x 90 ms | elementalist: a rune circle in three arcs of fire, frost and storm turns and flares (Falling Pyre) |
| 607 | illusion_mirror | 3x3, 1,1 | 8 x 90 ms | illusionist: four mirror panes rise around the target, a glint crosses them, they shatter (Hall of Mirrors) |
| 608 | illusion_shatter | 3x3, 1,1 | 7 x 70 ms | illusionist: a figure breaks into glass shards of cyan and rose (Umbral Stride) |
| 609 | thief_vanish | 3x3, 1,1 | 7 x 80 ms | thief: low smoke billows from the feet, two dagger glints spin out (Shadow Veil, Shadow Mend) |
| 610 | ninja_vanish | 3x3, 1,1 | 7 x 70 ms | ninja: an ink slash crosses the spot, ink drops and leaves whirl (Shadow Step) |
| 611 | ninja_smoke | 1x1, 0,0 | 6 x 90 ms | ninja: a smoke bomb tile; grey puffs and a red spark (Smoke Bomb, each tile) |
| 612 | samurai_focus | 3x3, 1,1 | 8 x 90 ms | samurai: a blade gleam rises before the caster, crimson petals circle it (Bushido Focus) |
| 613 | samurai_parry | 3x3, 1,1 | 7 x 70 ms | samurai: crossed blades flash, sparks and a crescent of steel (Counter Stance) |
| 614 | necro_curse | 3x3, 1,1 | 8 x 90 ms | necromancer: a violet brand of runes closes on the target, a green skull mark sinks in (Withering Curse) |
| 615 | lich_rot | 3x3, 1,1 | 8 x 90 ms | lich: rot bubbles swell and burst on the target, green skull wisps rise (Soul Rot) |
| 616 | monk_heel | 3x3, 1,1 | 7 x 70 ms | monk: a ring of chi sweeps at kick height, ember footfalls flare (Whirling Heel) |
| 617 | shadowfist_mark | 3x3, 1,1 | 7 x 80 ms | shadowfist: five violet pressure points light up on the target, joined, then pulse (Pressure Points) |
| 618 | ironsage_ward | 3x3, 1,1 | 8 x 90 ms | iron sage: jade hexagon plates close into a dome over the target and crumble (Chi Ward) |
| 619 | templar_mend | 3x3, 1,1 | 8 x 90 ms | templar: a cross of gold light descends, feathers drift down (Vow of Mending, Lay on Hands) |
| 620 | inquisitor_zeal | 3x3, 1,1 | 8 x 80 ms | inquisitor: white-gold holy flames rise in a ring, sparks climb, a brand circle (Zealotry) |
| 621 | sentinel_aegis | 3x3, 1,1 | 8 x 90 ms | sentinel: three radiant wall panes rise around the caster under a dome of light (Aegis of Faith) |
| 622 | snare_jaws | 3x3, 1,1 | 6 x 70 ms | snare: iron jaws snap shut on the tile, sparks and dust (Snare Trap, triggered) |
| 623 | snare_blast | 3x3, 1,1 | 7 x 70 ms | snare: a mine bursts; ember shards, iron fragments and smoke (Seeker Mine, Detonate Mines) |
| 624 | vigil_wrath | 3x3, 1,1 | 8 x 90 ms | vigil: a red war banner with a sword rises from the ground (Vigil of Wrath) |
| 625 | vigil_iron | 3x3, 1,1 | 8 x 90 ms | vigil: a steel banner with a shield rises from the ground (Vigil of Iron) |
| 626 | vigil_haste | 3x3, 1,1 | 8 x 90 ms | vigil: a green banner with a wing rises from the ground (Vigil of Haste) |
| 627 | vigil_clarity | 3x3, 1,1 | 8 x 90 ms | vigil: a blue banner with an eye rises from the ground (Vigil of Clarity) |

## Large spell effects (things_custom24, effects 635-655; our own procedural art, soft alpha)

21 big glowing effects, 5x5 to 9x9 tiles, 10-13 frames, each sent at its centre tile: boss telegraph circles (5, 7,
9), shockwave rings (fire, frost, lightning, holy, blood), novas (fire 9x9, frost, poison, holy, void, arcane), pillars
of light (holy, arcane), a meteor, a lightning burst, a holy sanctum, a void rift and a blood geyser. Drawn by
`client/tools/sprites/gen_big_fx.py` (spec `art_import/big_fx.csv`; the element ramps of `item_forge_data/style.json`);
their alpha stays soft, unlike the pixel-art sets above. In things_custom24 (effects 635-655); the ids are in
`server/data/lib/chaos_big_fx_ids.lua`. Which spell, boss and use sends which, and the switch `ChaosBigFx.BIG_FX`
(on since 2026-10-13 (pair 24 at 407ad9b6)): server/README.md "Large spell effects". Sizes and build: client/MANIFEST.md "Large spell effects".

## Pack farming spell effects (pair 27, effects 674-758, missiles 154-160; switch on)

The nine pack farming spells get effects and missiles of their own. 34 more spells of the Mystic, Templar, Warrior,
Thief, Necromancer and Monk lines get new impacts, circles and status looks (frost nova, meteor, chain lightning, holy
smite, divine judgement, whirlwind, berserk, backstab, parry, blood drain, shadow claws and more). Also: the four vigils,
the Iron Palm stun, the buff bar, level up (no words in the art), loot beams, reward effects, the Town Portal and the
boss danger circle. Cut from the owner's oblique effect sets of 2026-10-15 by `client/tools/sprites/gen_pack27_fx.py`
(spec `art_import/pack27_fx.csv`, packs per pick in `art_import/pack27_sources.csv`), appended by `import_fx_art.py`
(ids in `server/data/lib/chaos_pack27_fx_ids.lua`, catalogue `pack27_fx_catalog.csv`). Effects only: no damage, area
or timing changes. In the published pairs since pair 27 (windows-assets 51a26d26, 2026-10-15; pair 28 keeps them); the
switch `ChaosPack27Fx.PAIR27_FX` is on since then: server/README.md "Pack farming spell effects", client/MANIFEST.md
"Pack farming spell effects (pair 27 trial)".

## Mystic line effects (2026-10-16, Tier A: pair 28 only, no new sprites)

Owner: "I found the effects of the Mystic spells very poor." Audit: 1x1 tile carpets on 37-137 tiles, impacts sent
at the cast (before the missile lands), tiny class effects in place of bigger pack ones, the swap order hiding the
better art, names ChaosFx has only through aliases (`poison_cloud`, `aura_ring`), the Necromancer's `cursed` reused. Helpers:
`server/data/lib/chaos_mystic_fx.lua` (`ChaosMysticFx`); rules: server/README.md "Mystic line effects".

| spell | sends now |
|---|---|
| Rime Bloom | pair 27 nova_frost + big_shock_frost_7 (250 ms), ice_shatter on each slowed foe; no tile effects |
| Witchfire Bolt | pack fireball; fire_explosion when it lands |
| Forked Storm | lightning orb; on arrival storm_chain (first target), lightning_strike (each jump); no chain_lightning tile |
| Crimson Covenant | px197_crimson, then blood_pact (300 ms) |
| Falling Pyre | as before + big_shock_fire_7 at the landing; no tile effects |
| Frozen Crypt | ice lance; nova_frost on landing and on pulses 2-6 (no tiles then), frost_glyph / frost_bastion in turn |
| Doomtide | the three big waves + four ring bursts each (fire_explosion, lightning_strike, meteor_fall); no tiles |
| Blightswarm | toxic_burst + big_nova_poison_7; no tiles (procedural poison_burst without it) |
| Briar Prison | poison_burst tiles (asked as poison_cloud, an alias) + earth_spikes |
| Primordial Squall | the big waves + four ring bursts each (earth_spikes, nova_frost); poison_burst cast and tiles |
| Purifying Wellspring | caster healing_bloom; each healed ally mystic_mend (class swap of heal_sparkle) |
| Hall of Mirrors | caster arcane_orbit; each clone illusion_mirror (class swap of arcane_sigil) |
| Umbral Stride | shadow_orb missile, shadow_eruption where it leaves, illusion_shatter, shadow_hit on arrival |
| Shattered Psyche | arcane_bolt; on arrival px03_arcane, arcane_hit (+150 ms), tick_curse (+400 ms) |
| Wraithshroud | shadow_shroud alone |
| Nightburst | void_maw (the gather), big_nova_void_7 + four shadow_eruption at the burst; no tiles |
| Tear in the Weave | big_rift_void_7 under the pair 27 rift_void; each implosion big_nova_arcane_7 + px195_arcane; no tiles |
| Mirror Mend | ki_blast_blue to the ally, regenerating on arrival; arcane_bolt on to the mirror, mystic_mend + arcane_hit |
| Lucid Reverie | starfall_crown; tick_regen on every member each pulse |
| Bewitching Hex (base) | arcane_bolt, arcane_hit on arrival, tick_curse on each of the four ticks (`patch_mystic_stock_fx.py`) |
| Arcane Ripple (base) | its wave + arcane_hit at the mouth and px674_arcane on each monster in the cone |

Without an effect in the pair (switch off, older pair) each site sends what it sent before. Tier B: the next section
(pair 29, switch off until the pair is live).

## Mystic line effects, Tier B (pair 29, effects 759-779, missiles 161-169; switch `ChaosPack29Fx.PAIR29`, off)

Owner-approved 2026-10-16. Cut from the owner's oblique effect sets by `client/tools/sprites/gen_pack29_fx.py` (spec
`art_import/pack29_fx.csv`, pack per pick in `art_import/pack29_sources.csv`), appended to pair 28 by
`import_fx_art.py` (ids `server/data/lib/chaos_pack29_fx_ids.lua`, catalogue `pack29_fx_catalog.csv`). Swaps:
server/data/lib/chaos_pack29_fx.lua; rules: server/README.md "Mystic line effects, Tier B (pair 29)". With the switch
off every spell sends its Tier A effects (the table above).

| spell | pair 29 sends (instead of) |
|---|---|
| Witchfire Bolt | missile witchfire_lance (fireball) |
| Forked Storm | missile storm_bolt (lightning orb); storm_shock on each jump (lightning_strike) |
| Crimson Covenant | covenant_bloodlust (blood_pact) |
| Falling Pyre | missile pyre_comet (fireball); pyre_rune, the burning mark (infernal_seal / the Elementalist glyph) |
| Frozen Crypt | missile crypt_lance (ice_lance); crypt_ice_strike on landing and pulses (nova_frost) |
| Doomtide | wave 2 doom_tornado (storm ring), wave 3 doom_skyfall (fire ring); the ring bursts stay |
| Ironbark Hide | ironbark_skin (stone_ward) |
| Briar Prison | briar_rooted (earth_spikes) |
| Primordial Squall | waves 1 and 3 squall_spore_cloud (venom nova) |
| Hall of Mirrors | caster mirror_ring (arcane_orbit); each clone mirror_glass_nova (illusion_mirror) |
| Umbral Stride | missile umbral_raven (shadow orb); umbral_step where it leaves (shadow_eruption) and arrives (illusion_shatter) |
| Shattered Psyche | missile psyche_prism (arcane_bolt); psyche_fracture on arrival (px03_arcane) |
| Wraithshroud | wraith_veil (shadow_shroud) |
| Nightburst | night_eyelid, the gather (void_maw); night_cataclysm, the burst (big_nova_void_7) |
| Tear in the Weave | weave_crush on each implosion (big_nova_arcane_7); missile weave_marble from each pulled foe (new) |
| Mirror Mend | missile mend_shards to the ally and the mirror (ki_blast_blue, arcane_bolt); mend_chime on the mirror (arcane_hit) |
| Lucid Reverie | reverie_release on the caster (starfall_crown); reverie_pop on every member each pulse (tick_regen) |
| Bewitching Hex (base) | missile hex_missile (arcane_bolt); hex_curse on each of the four ticks (tick_curse) |

Not changed: Rime Bloom, Blightswarm, Purifying Wellspring, Moonfang Pack, Verdant Sanctuary, Arcane Ripple and the
three stock fans (Tier A stays). Not fetched, for a later pass: the ultimate frost pillars, wrath of nature, the
mirror shatter step, dream bubbles, the void rift loop and end stages, the sonic blast of Arcane Ripple.

## Condition auras, blasts, missiles and fireworks (pair 29, effects 780-829, missiles 170-185; switch `ChaosPack29Fx.PAIR29`, off)

Cut from the five effect packs of 2026-10-16 by `client/tools/sprites/gen_pack29_vfx.py` (spec
`art_import/pack29_vfx.csv`, pack per pick in `art_import/pack29_vfx_sources.csv`), appended to pair 29 after the
Archmage by `import_fx_art.py` (ids `server/data/lib/chaos_pack29_vfx_ids.lua`, catalogue `pack29_vfx_catalog.csv`).
What sends each one: server/data/lib/chaos_pack29_vfx.lua; rules: server/README.md "Condition auras, blasts and
fireworks (pair 29)". With the switch off nothing changes.

| what | pair 29 sends (instead of) |
|---|---|
| damage condition ticks (engine) | cond_burning, cond_poison, cond_shocked, cond_bleeding, cond_frozen, cond_cursed (the stock hit sparks) |
| physical hit on a blood / fire creature (engine) | hit_blood / hit_blood_spray (the red splash effect) |
| direct fire, ice, energy, earth, death, arcane hit (engine) | blast_fire1, blast_ice, blast_energy, blast_poison, blast_dark, blast_arcane |
| stock and procedural element missiles (engine) | bolt_fire, bolt_lightning, bolt_plasma, bolt_dark, bolt_soul, bolt_ice, bolt_crystal, bolt_thorn, bolt_poison, bolt_holy, bolt_meteor, bolt_arcane, bolt_shadow |
| spell hits during a cast (ChaosSpell.fx / vfx) | fireball_hit, ice_shatter, lightning_hit, shadow_hit, arcane_hit, venom_splash, holy_hit, frost_burst, poison_burst, ground_slam, arcane_burst, lightning_zap, fire_burst, inferno_burst, fire_nova, fire_ring as blasts |
| slows, stuns, chill, shock, words, boss phases, player scan | the condition auras, held while the state lasts |
| level-up / achievement / boss reward | fw_grand / fw_star / fw_rainbow (nothing / the yellow firework) |
| boss death | blast_boss, blast_massive (nothing) |

## Ground effects (under the creatures; base patch 0055)

The client draws the floor shapes and the effects that would hide a creature under the creatures:
`client/overlay/modules/game_groundfx` registers the ids of `groundfx_data.lua` with `g_map.setGroundEffect`. The list
is data: `client/tools/sprites/ground_fx.csv` (name, layer, reason), resolved to ids through the catalogues here by
`client/tools/sprites/gen_ground_fx.py`, which also enforces the rules: procedural circles / novas / rings (not the
engine's hits), every large effect, floor shapes by name, and every effect that covers the creature on its tile at 35 %
or more for 500 ms (measured on the pair into `ground_fx_cover.csv`) are ground. Short hits, projectiles and the
status words stay above. Rebuild after a new pair: `gen_ground_fx.py measure --dat D --spr S`, then `build`.
