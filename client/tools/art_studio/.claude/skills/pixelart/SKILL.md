---
name: pixelart
description: Writes a ready-to-paste PixelLab PROMPT (no API call, no token, no balance spent) for an item, a coherent item set, a creature concept or a map object in Tibia's 45 degree oblique perspective (top surface + front face), top-left light, dark outline, grimdark by default (Project Chaos is dark fantasy). The user pastes it into the PixelLab website themselves. Use when the user asks for "a prompt", "a PixelLab prompt", wants to generate art on the website by hand, or runs /pixelart.
argument-hint: "[what to draw; size 32/64/96/128; how many; theme]"
---

# A PixelLab prompt, by hand

Request: **$ARGUMENTS**

This skill makes TEXT only: a prompt the user copies into the PixelLab website (pixellab.ai) and generates there with
their own account. It calls nothing and spends nothing. For the same art through the API, with cutting and boards,
use `/item-sheet` (items) or `/creature` (a game creature); for a ground, `/floor` (pure Python).

## The five pillars (say them all, or PixelLab falls back to its flat default)

1. **The perspective**: Tibia's 45 degree oblique top-down view shows the TOP and the FRONT face at once. It is NOT 30
   degree isometric (three faces). Forgetting this is the number one mistake.
2. **Volume**: a real object with mass, not a sticker.
3. **One strong light**: from the top-left; lit top-left edges, deep shadow lower-right.
4. **A readable silhouette**: a dark outline, a contour that reads at real size.
5. **Personality**: wear, cracks, engravings, a glow: what sets it apart from the generic one.

## The vocabulary

**Always** (the core, near the START of the prompt):

- `45 degree oblique top-down perspective in classic Tibia style`
- `showing top surface and front face simultaneously`
- `richly rendered pixel art with volumetric shading`
- `strong top-left directional lighting`

**Good additions**: `deep dimensional shadows`, `bright specular highlights`, `rim lighting`, `high contrast`,
`sculpted form`, `carved details`, `ornate sculpted details with personality`, `weathered cracked surfaces`,
`faded engravings`, `tarnished metal`, `chipped enamel`, `hairline cracks revealing inner glow`, `characterful
design`, `angled top-down view at 45 degrees` (an alternative to the primary perspective line).

**The setting**: `gritty grimdark dark fantasy` by default (Project Chaos: obsidian, ash, bone, rust, dried blood,
crimson and violet glows, cold grave light). Change it only when the user names another theme.

**The style reference** (at least ONE, near the END): `Tibia-style item sprite`, `Tibia-style map object`,
`classic MMORPG item icon`. Never name any other game.

**The outline** (at the END, or PixelLab forgets it):
- 64 px and up: `bold dark outline tinted toward the item's own colors` (the tested /item-sheet rule: not pure black)
- 32 px: `bold 1 pixel near-black outline` (the classic 32 px item)

## Poison words (NEVER in the prompt)

`flat icon`, `icon set`, `clean`, `simple`, `minimal`, `2D` on its own, `consistent silhouette scale`, `vector style`,
`cartoon` (unless asked), `isometric 3/4 view` or `true isometric` on their own (they give the 30 degree three-face
view), `chunky` (it gives blocky staircase pixels: the tested /item-sheet base avoids `blocky chunky pixels`).

**No ground shadow.** The game draws every sprite over a floor: a baked `drop shadow`, a ground patch or a base
platform under the item looks wrong in the client. If the website adds one anyway, end the prompt with
`no ground, no cast shadow`. (The tested /item-sheet base prompt avoids shadows under items for the same reason.)

## Step 1: what to make

Ask only what the request did not say:

0. **The size, ALWAYS** (do not assume). Our 10.98 client draws 32x32; 64x64 is the master size (the HD look).
   On the website: 16-42 px tends to come out as a sheet of several frames; 64-128 px one detailed frame; 171-512 px a
   high-resolution single frame. Put the size at the start of the prompt (`32x32 pixel art item ...`) and tell the
   user to set the PixelLab canvas to the same size.
1. **What it is** (item, set, creature, map object), and **how many**.
2. **Theme** (default grimdark), **unique details** (materials, colours, glow), and for a set **the axis of
   variation** (colour, material, ornament, tier).

## Step 2: the template

| what | template |
|---|---|
| one item | T1 |
| a coherent set (3+) | T2 (and offer T1 per item, to redo one alone) |
| a creature | T3, as CONCEPT ART only: the website drawing a creature from nothing goes back to the frontal RPG view (see /creature's rules). For a game creature with 4 directions and a walk, use `/creature` |
| a map object (altar, forge, chest, statue, fountain) | T4 |

**T1, one item**

```text
[SIZE] pixel art item: [item and form] [thematic detail], 45 degree oblique top-down perspective in classic Tibia style showing top surface and front face simultaneously, richly rendered pixel art with volumetric shading and strong top-left directional lighting, [materials and textures], [glow or accent], weathered cracked surfaces, gritty grimdark dark fantasy, Tibia-style item sprite, [OUTLINE]
```

**T2, a set**

```text
[SIZE] pixel art set of [N] [category], each a different [theme] ([each in 2-4 words]), 45 degree oblique top-down perspective in classic Tibia style showing top surface and front face simultaneously, richly rendered pixel art with volumetric shading, strong top-left directional lighting, deep shadows and bright specular highlights, same base form, [what varies], gritty grimdark, Tibia-style item sprites, [OUTLINE]
```

**T3, a creature (concept)**

```text
[SIZE] pixel art creature: [creature] [size and posture], 45 degree oblique top-down perspective in classic Tibia style, richly rendered pixel art with volumetric shading and strong top-left directional lighting, [anatomy details], [palette], [pose with personality], menacing readable silhouette, gritty grimdark dark fantasy, Tibia-style creature sprite, [OUTLINE]
```

**T4, a map object**

```text
[NxN tiles, SIZE] pixel art map object: [object and main features], 45 degree oblique top-down perspective in classic Tibia style showing top surface and front face simultaneously, richly rendered pixel art with volumetric shading and strong top-left directional lighting, [structure and texture], [fire, smoke or glow], weathered surfaces, ornate sculpted details, gritty grimdark [biome], Tibia-style map object, [OUTLINE]
```

## Step 3: write it

- Fill the template; concrete details beat adjectives ("tarnished gold filigree with chipped enamel" > "old").
- **Under 400 characters** when possible (the website cuts the end): the perspective and the light at the start, the
  style reference and the outline at the end; cut item details before cutting those. Count the characters.
- English, ASCII, one line.

## Step 4: deliver

The prompt in a ```text block, its length in characters, the canvas size to set, and for a set the T1 version with
placeholders to redo one item. Say plainly that nothing was generated and nothing was spent.

## Step 5: when it comes back wrong

- **Too flat**: add `rendered as a 3D sculpted object in pixel art`, `extreme contrast lighting with deep black
  shadows`, `clear angled perspective showing depth`.
- **No personality**: add `unique characterful design`, engravings, runes, gems, wear, cracks, broken parts.
- **Three faces (isometric)**: repeat `showing top surface and front face simultaneously` and remove any `isometric`.
- **A shadow or ground under it**: end with `no ground, no cast shadow`.

Record what worked (the prompt, the size, what was wrong) in `NOTES.md`; a word that keeps failing joins the poison
list here.
