---
name: floor
description: Paints a FLOOR (map ground — grass, dirt, stone, marble, planks, sand) in PYTHON as ONE periodic block of the world cut into 64 px tiles, with variation by an X/Y pattern and borders as transitions. Use when the user asks for a ground, floor, lawn, dirt, paving, boards, a ground tileset, the borders of a floor, or runs /floor.
argument-hint: "[the floor and what it should have]"
---

# A floor in Python

Request: **$ARGUMENTS**

The helper is `kit/tiles.py` (periodic block, noise that wraps around, cutting, preview, seam measure). Each floor's
script lives in `floors/<name>.py` and writes into `out/floors/<name>/`.

## The rules that are not negotiable (each one cost a rejection)

| | |
|---|---|
| **a floor is PYTHON, not PixelLab** | PixelLab flattens grass into a plain green, invents bushes, and with `no_background` on it ERASES the ground (takes it for background). At most it refines pieces with an outline (border stones), never the middle that repeats |
| **a BLOCK OF THE WORLD** | paint one periodic block (256 px = 4×4 tiles; 512 = 8×8) and each tile is its window at the world position (`x % P`, `y % P`). Every variant of a family uses the SAME block: there is no seam between them. Filters, blur and noise with `mode="wrap"` (`tiles.wrap_blur`, `tiles.wrap_noise`) |
| **variation by the X/Y pattern** | 4×4 at least; 8×8 when it repeats a lot. The game engine picks the tile by position |
| **64 px pixel art** | paint straight at 64 px (a crisp 1 px grass blade) or 8× bigger and shrink by the mean. No smooth gradients: stepped shading, dithering only inside one surface |
| **light from the top-left** | relief (stone, plank) with the top-left edge light and the bottom-right one dark; the cast shadow goes down-right and does NOT wrap around (no `np.roll` on the shadow) |
| **the change must SHOW** | judge at real size, tiled 3×3 (`tiles.tiled`), not on an enlarged preview |
| **do not invent dirt** | stains and broken slabs were rejected. Damage only when asked, and LIGHT |
| **no BLACK outline** | a stone's outline is a dark tone of its OWN material |

## The borders (one floor passing into another)

| | |
|---|---|
| **a transition, not a frame** | a border of another texture glued onto the floor was rejected. The border is the passage: the outside material only at the edge (~7 px), the FLOOR at the same world pixel from there inward, and the stones between them stay or go WHOLE |
| **4 shapes** | tile (x, y) uses shape `(x + 3y) % 4`: straight, set back, advancing with loose tufts, wavy; the shape changes only away from the tile's edge, or the neighbour does not fit |
| **dithering becomes a LINE** | thinning by a Bayer pattern leaves a regular band parallel to the border. Thin by WHOLE pieces, with a hash of the place |

## Step by step

1. Ask what is missing: the material, the tone (a reference or colours), the block size (4×4 or 8×8), whether there
   are borders.
2. Write `floors/<name>.py`: the `P×P` RGBA block in numpy; the colour ramp with `tibia_view.ramp` (cold shadow, warm
   light); the pieces (stones, planks, tufts) painted by position with `tibia_view.hash01` (an integer hash, never a
   sine hash: it comes out in BLOCKS).
3. Save `block.png`, the tiles (`tiles.cut` → `tile_<col>_<row>.png`) and `preview.png` (`tiles.tiled(block, 3)`).
4. Measure `tiles.seam_score(block)` (1 or less = no seam) and OPEN the preview: seam, repeated line, a square that
   stands out, tone.
5. Deliver: the preview, the seam number, and the list of tiles.
