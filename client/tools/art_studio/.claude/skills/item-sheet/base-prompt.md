# PixelLab — the item sheet base

It came from an approved sheet of 15 pieces of equipment: the right texture and shading. Changing the style of EVERY
future sheet means editing the PIXELLAB BASE PROMPT block below.

## INSTRUCTIONS FOR THE AI (they do not go into the prompt)

- Create image has **no negative field**: everything negative goes in the `Avoid:` line at the end.
- **A long, detailed prompt is welcome** in this mode (up to 2000 characters through the API).
- **Two layouts:** LIST (different items, one per cell: `{LAYOUT_LIST}`) and VARIATIONS (up to 6 items, one ROW per
  item, the columns are the versions: `{LAYOUT_ROWS}`, and the items become `Row 1:`, `Row 2:`…).
- **How to put each kind in the cell:** body clothing `laid flat` (or it comes with a body inside; at 32: `short wide …
  robe laid flat in a square shape, sleeves spread out sideways`); hood and hat `shown empty`; boots `pair of …`; book
  `closed thick book`; wand, staff, long weapon `lying diagonally`.
- **Tiers (`{TIERS}`)** only when the sheet mixes common and rare. Without tiers, delete the whole paragraph.
- **Cinders of Chaos (added; the BASE PROMPT block below is unchanged and stays the tested one):** the default theme is
  grimdark dark fantasy, so `{THEME}` is e.g. `grimdark dark fantasy crafting` and `{TEXTURES}` may take the wear
  words of the `/pixelart` skill (`weathered cracked surfaces, faded engravings, tarnished metal, chipped enamel,
  hairline cracks revealing inner glow`). Never put its poison words in a sheet prompt (`flat icon`, `icon set`,
  `clean`, `simple`, `minimal`, `vector style`, `cartoon`, a bare `isometric`), never name another game, and keep this
  base's rules where the two differ: NO drop shadow (it is in the Avoid line), the outline tinted toward the item's
  colours at 64 (near-black at 32), and no `chunky`.

## PIXELLAB BASE PROMPT

```text
High-quality 64x64 pixel art item sprite sheet: {LAYOUT}

STYLE: richly rendered pixel art in the classic Tibia 45 degree oblique top-down perspective, showing the top surface and the front face at the same time. Strong light from the top-left. Every material uses a wide 10 to 12 tone color ramp with hue shifting: warm bright highlights, rich mid tones, cool deep shadows. Smooth tonal blending inside each material, soft reflected light on the lower-right edges, deep self-shadows inside folds, cavities and under overlapping parts. Fine material texture: {TEXTURES}. Thin dark outline around each item, tinted toward the item's own color.

{TIERS}

ITEMS:
{ITEMS}

Avoid: flat colors, limited palette, posterized or banded shading, blocky chunky pixels, jagged staircase edges, low detail, blurry or smudged areas, noisy random pixels, photorealism, 3D render look, vector art, flat mobile-game icons, text, letters, labels, numbers, ground, floor, grass, base platforms, cast shadows or drop shadows under the items, {EXTRA_AVOID}extra items not in the list.
```

### The blocks

`{LAYOUT_LIST}` (N = how many items):

```text
a clean grid of separate {THEME} items on a transparent background, one item centered in each cell, each item filling most of its cell, nothing overlapping. Exactly these N items, in this order, and nothing else.
```

`{LAYOUT_ROWS}`:

```text
each ROW is one item and the COLUMNS are design variations of that same item, on a transparent background, one item centered per cell, nothing overlapping. Exactly N rows, and nothing else.
```

`{TEXTURES}` — only the materials on the sheet, for example: `velvet sheen, leather grain and creases, wool fibers,
stitched seams, linen weave, worn brass and gold with small scratches, gems with inner light and a bright specular dot`.

`{TIERS}` (an example; adapt it to the game):

```text
TWO TIERS that must read at a glance: COMMON items are humble and worn, made of undyed wool, brown leather, rough linen and moss-green cloth, with patches and frayed edges, and they have NO gems. RARE items are midnight-blue velvet with gold embroidery and exactly one glowing violet gem.
```

`{EXTRA_AVOID}` — empty, or comma-separated terms ending in `, ` (e.g. `gems on common items, `).

## The 32x32 VARIANT

- `64x64` becomes `32x32` at the start, and the layout says `one item centered in each 32x32 cell`.
- **The ITEM FILLS THE CELL.** In Tibia a 32 item takes almost the whole tile. Right after `nothing overlapping.`:

  ```text
  SIZE RULE: every item is drawn BIG but lives ENTIRELY inside ONE square 32x32 cell: it fills the square almost edge to edge in width AND in height, with at most 1 pixel of margin, like classic Tibia inventory items, and no pixel ever crosses into the next cell. No item is taller than one cell or spans two cells. Long items are reshaped to fit the square: robes, capes and coats are drawn short and wide with the sleeves spread out to the sides; wands and staffs lie diagonally from corner to corner.
  ```

  And the Avoid line gains `small items, empty space around the items, wide margins inside the cells, items crossing the cell borders, items taller than one cell, long elongated robes, `.
  The rule is SQUARE ("width AND height"), not "longest side": with "longest side" it stretched the robes over two cells.
- The whole STYLE paragraph is replaced by this one. The classic 32 item is PAINTED AND SHRUNK, not clean pixel art
  (measured: ~0.6 distinct colours per pixel, soft gradients with fine noise, a 1 px near-black outline, FEW dark lines
  inside):

  ```text
  STYLE: authentic Tibia item sprite style, a painterly pre-rendered look, as if a small detailed painting was shrunk down to 32x32, in the classic Tibia 45 degree oblique top-down perspective showing the top surface and the front face. Almost every pixel is a slightly different shade: soft smooth gradients with fine per-pixel color noise over every surface, hundreds of colors per item, no flat color areas, no posterized bands, no clean cel-shaded clusters. Vivid saturated colors, high contrast, strong light from the top-left with soft glowing highlights and deep shadows. Forms are shaped by light and color, with very few dark inner lines. Bold 1 pixel near-black outline around the whole silhouette.
  ```

- **1 or 2 details per item**, not 2 to 4: a tiny rune or a seam vanishes at 32.
- **Do not lengthen the STYLE** to ask for a stronger outline: a long outline paragraph made the sheet lose its order,
  gain items that were not asked for and shrink the items. A stronger outline is done afterwards, on the PNG.
- The Avoid line swaps `blocky chunky pixels, jagged staircase edges` for `clean cel-shaded pixel clusters, limited palette, modern indie pixel art style, thick dark inner lines, pillow shading, blurry edges, micro-detail that turns into noise`.
