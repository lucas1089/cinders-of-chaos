# Studio notes

One section per creature, item set or floor: the request (in the words of whoever asked, with the date), what was
chosen and why, and every mistake that cost a round. A new rule that holds for everything also goes into the skill.

## Setup (2026-10-09)

Set up from `PIXEL-ART-STUDIO.md` section 4 into `client/tools/art_studio/`; the section 6 files were extracted byte
for byte from the guide. The no-token test passed (beetle: 23x25 / 23x23 / 23x24 / 25x23 px, "idle frame 1 vs the
painting: 4 px differ" north and south) and was deleted. No PixelLab token yet: nothing was generated or spent.
`out/` is gitignored. Added: the `/pixelart` skill (prompts for the website, grimdark by default) and a Cinders of Chaos
note in the item-sheet base instructions.

## Floors: cracked_obsidian, ash_stone, blood_moss + border blood_moss -> ash_stone (2026-10-09)

Request: "dark-fantasy floors that fit our dark tiles: cracked obsidian, ash-covered stone, blood-moss; with variation
and one border set". 256 px blocks (4x4 tiles of 64), shared helpers in `floors/_floorlib.py` (periodic Voronoi,
stepped ramps). Compared with `client/tools/sprites/dark_tiles/masters/` in `out/floors/compare_dark_tiles.png`.

- `seam_score` reads 1.1-1.3 on Voronoi floors with NO seam: interior columns score the same (1.2-1.36). The number
  is noise there; judge the 3x3 preview.
- ash_stone: small running-bond slabs read as a brick WALL; bigger slabs (courses 26-40, widths 34-64) read as floor.
  A course joint ON the wrap gave seam 1.89: the whole block is rolled (9, 5) so the wrap falls inside stones.
- ash_stone: speckle-dithered ash edges looked dirty; whole drifts with a lit top-left rim and a 1 px shadow down-right
  read as ash. The first ash ramp was too bright for our set: darkened.
- blood_moss: 2-3 px cushions read as red beads/berries; 8 px cells with fibre noise and a desaturated wine ramp read
  as moss.
- the border: bare soil in the moss tile met the stone in a straight line. Soil gaps now stay inside a tile (cushions
  whole within 9 px of every tile edge), so the edge is always cushions.
- Python bug: `hs[-2] += hs.pop()` adds to the wrong element (the index is resolved before the pop).

## Creature: ghoul (shape + preview only, 2026-10-09)

Request: "one small creature shape + idle/walk preview, e.g. a bone-golem-like or ghoul creature". 64 frame, K 1.15,
~31x25 px. First version: too dark a skin ramp (it read as a black blob) and arms spread so wide it sprawled; then
the head lowered and pushed forward (a hunch) to shorten the diagonal lean of a tall biped. The walk: alternating legs
16 degrees, arms against them; the idle: a breath (1 px) and a claw twitch, face still. Not repainted (no token).

## Items: Monk fist weapons + Necromancer bone effect pieces (2026-10-10)

Request: "a small set of fist weapons for the Monk, 5 tiers up to level ~500+, plus a legendary; 32x32, oblique, top-left
light, dark outline, grimdark (charred iron, embers, ash, bone)" and "the bone_spear / bone_burst / bone_aura effects".
Prompts: `prompts/items/fist-weapons.md` (the 32x32 VARIANT for ONE item per call), `bone-spear.md` (32), `bone-shards.md`
and `bone-skulls.md` (16). Balance 2000 -> 1920 generations: 8 calls, 10 generations each (Create image Pro bills a call,
not an image: at 32 px one call gives 64 candidates, at 16 px also 64).

- One item per call at 32 px beats a sheet: 64 candidates of the right size, ~26x27 px each, nothing to cut apart.
- The legendary did not need its own call: one ossuary gauntlet candidate had a skull on the knuckles; its eye sockets
  were recoloured to embers in `gen_fistfx_art.py` (9 pixels).
- PixelLab painted every spear diagonally, as asked; the straight directions come from RotSprite (Scale2x x3, nearest
  rotation, nearest sampling back) and need a smaller scale (0.6 against 0.78) or they cross the tile.
- The 16 px skulls come without a hard outline; at 0.72 scale over the violet ring they still read at 1x.
- Picks are in `client/tools/sprites/art_import/fistfx_src/` (unchanged PNGs); `out/items/fistfx/` holds every candidate
  (ignored by git).

