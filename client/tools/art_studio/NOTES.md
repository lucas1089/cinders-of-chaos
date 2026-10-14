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


## Class outfits, phase 1: the Warrior line (2026-10-10)

Request: custom outfits for every class, male and female, "following the vibe of the game"; phase 1 is the Warrior
line only. Code: `client/tools/outfit_art/` (rig, body, gear, palette, warrior_line, build, repaint, importer). The
shape is the art (no repaint yet): every frame is the posed shape rendered again, so the colour template follows it.

- The stock player layout (look 131): 2x2 tiles, displacement 8,8, idle 1 phase, walk 8 phases at 300 ms, 2 layers,
  3 addon patterns, 2 mount patterns. Copied exactly; addons empty.
- A level or bowed face disappears from above (only a band at the bottom of the head showed). Heads tilt BACK 10
  degrees and the hairline sits high, so the face shows in the south and east views.
- Tinted materials must be bright greys (the client multiplies): the first ramps (34..236) read muddy once tinted.
- Thick horns read as one pale blob over the head; thin horns and a skull cap with ember eye sockets read as a skull.
- Females read as males at 1x until the hair framed the face (side locks) and fell down the back; the Juggernaut
  woman gets an open-faced helm.
- `top` (where rays start) must clear the raised riding pose, or the head renders from inside (a dark disc).
- PixelLab repaint (`repaint.py edit`): written, not run (the session's permission check refused the paid call).

## Rift bestiary trial: ashen thrall, bone hound, crypt wraith, ossuary knight (2026-10-10, not used)

Request: "Rift monsters must be exclusive and custom". Started as new art (`creatures/rift_bestiary.py`: one file and
shared builders for many creatures). Then the owner ruled that donated sprites come first. Every rift look found a donor
creature (client/MANIFEST.md "Monster looks pair"), so none of these four was imported. The paintings stay in
`out/rift/`.
- Bipeds drawn with the kit's 45 degree lean read as lying down. `rift_bestiary.py` shears the body upright (UPRIGHT 0.8,
  local patch of `Facing.to_body` / `rest_pixel`). The projection is then no longer symmetric about the diagonal, so all
  four views are rendered and painted (one Edit call over a 4-view canvas) instead of transposing south to east.
- Cost: one Edit images (Pro) call over a 256x64 or 384x96 canvas = 10 generations. Six calls in all, balance 1905 -> 1835
  (other sessions spent in parallel too).
- PixelLab kept the silhouette only sometimes (thrall v1: overlap 1.00). Mostly it repainted bigger and better
  (hound, wraith: overlap 0.12-0.55; the knight came out a dull blob). `fit` registers each painted view on the shape by
  a whole-pixel shift and prints the scale for K. A painting that fills its cell needs a bigger animation frame
  (`anim_frame` 96: the cells are padded, nothing is scaled). Painted pieces cross cell borders (a tail in the next
  cell), so pieces are given to the cell holding most of their pixels.
- The 96 frame animation of the hound did not finish in 10 minutes (ray marching at 4x supersampling over 16 frames x 4
  views); use ss 2 for big frames.

## Class outfits, phase 2: new class looks without donor art (2026-10-12)

Request: new art for the Lich and Inquisitor women, a matched Necromancer pair, and alternative Thief, Ninja and
Templar looks, each with 2 addons that carry the class. Code: `client/tools/outfit_art/class_art_line.py` (designs on
the Warrior-line rig) and `class_art.py` (sheets in the `import_art_things.py` layout, previews). No PixelLab token, so
no repaint: the shape is the art, as in phase 1.
- The client cuts anything past a 2x2 outfit's right or bottom edge. In the east view the figure's right side faces
  the bottom edge, in the north view the right edge: a weapon held low on the right (a hanging mace, a sword pointing
  forward, a staff to the ground) crossed it by up to 49 px. Weapons are now held up, staffs held mid-shaft, and the
  walk stride is 7 degrees (24 crossed by 11 px). `class_art.py edges` checks all poses before a build.
- Dark tinted cloth under a dark default colour reads as one black blob; the previews use per-class colours
  (`class_art_line.COLOURS`) and the client's default colours side by side.
- A hood hides the hair, so a hooded woman reads as a man: the Necromancer woman gets ash-grey locks outside the hood.
- An addon in the player's head colour on a head-coloured cowl disappears (the Ninja's headband): identity pieces that
  must always show (headband, scarf) are untinted crimson.
