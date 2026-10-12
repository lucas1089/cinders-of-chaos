---
name: creature
description: Creates a new CREATURE (monster, beast, enemy, mob) in pixel art in Tibia's oblique perspective — the SHAPE modelled in Python (signed distances), PixelLab only REPAINTING that shape (Edit images Pro, 3 variants, silhouette review), and the animation (idle + walking) made by dressing the posed shape in the painting, never repainting frame by frame. Delivers ONE sheet with a column per direction (north, east, south, west), the idle on top and the walking below. Use when the user asks for a creature, monster, beast, enemy or mob, a new version of one, its animation, or runs /creature.
argument-hint: "[name and idea of the creature]"
---

# A new creature

Request: **$ARGUMENTS**

The way (it is what holds the perspective — PixelLab alone does not):

1. **the SHAPE in Python**, one file per creature (`creatures/<name>.py`, copied from `creatures/_template.py`):
   parts made of signed distances, seen through the Tibia projection, lit from the top-left, read off ramps of tones
   per material, with a dark outline;
2. **PixelLab only REPAINTS** that shape (Edit images Pro), in 3 variants, and the silhouette of each is reviewed;
3. **the animation dresses the posed shape in the painting**: each frame puts the parts in a rigid pose and each pixel
   takes the colour of the same point of the same part in the standing painting. What only moves comes out IDENTICAL,
   just shifted; nothing "boils".

The kit: `kit/tibia_view.py` (the projection, the primitives), `kit/creature_kit.py` (shape, painting, PixelLab),
`kit/creature_anim.py` (pose, reprojection, sheet, GIF), `kit/pixellab.py` (the API).

## What to ask (only what the request did not say; everything else has a default)

| | default |
|---|---|
| **the name** (it names the files) | what the user called it, ASCII, with `_` (`zombie_seagull`) |
| **the idea** | suggest a twist that escapes the ordinary (the tortoise gets spikes, the seagull turns zombie, the frog turns pirate) |
| **the size** | a 64 frame and a creature of ~40 px; "bigger" = a 96 frame and ~60 px |
| **how it walks** | forward; SIDEWAYS only what walks sideways (a crab); flying/hovering is a variant of the walking |
| **the directions** | the 4 of the sheet come from TWO painted views (north and south): east and west are south and north mirrored on the diagonal |

A reference image from the user (concept art) is the best input: read it and turn it into parts.

## The steps

1. **The file.** Copy `creatures/_template.py` to `creatures/<name>.py`. Replace the example (the beetle): `NAME`,
   `FRAME`, `K`, `WALKS`, the parts in `parts()`, `RAMPS`, `OUTLINE`, the `Shape` classes (`mottle`, `gloss`, `glow`,
   `painter`), `WHAT` and `DESIGN` (what PixelLab will hear), the poses and `check_signs`. The docstring at the top
   holds the request in the user's words and the date.
2. **The shape**: `python creatures/<name>.py shape`. It prints the size of each view and writes into `out/<name>/`:
   `<name>_python.png` (north | south), `_python_x5.png` and `_python_4dir_x3.png`. OPEN the previews (read the image)
   and fix the SHAPE until it reads well in all four views — PixelLab copies its defects (table below). Tune `K` to the
   size asked.
3. **The motion on the shape**: `python creatures/<name>.py preview` animates the shape itself
   (`<name>_shape_idle8_walking8.png` and the GIFs). Judge the rhythm and the poses HERE, before spending PixelLab.
4. **PixelLab**: `python creatures/<name>.py edit 3` (3 variants). Before the first round, tell the user it costs
   generations and check the balance
   (`python -c "import sys; sys.path.insert(0,'kit'); import pixellab; print(pixellab.balance())"`) before and after.
   The command prints the review: how much of each variant's silhouette overlaps the shape's (1.00 = the same). Under
   ~0.90 PixelLab REDREW it; also check that north and south stayed CONSISTENT with each other. Show the candidates to
   the user (`out/<name>/edit_compare.png`) with your recommendation; they choose.
5. **The chosen one**: `python creatures/<name>.py pick out/<name>/edit/edit_vN.png` → `<name>_pixellab.png`.
6. **The sheet**: `python creatures/<name>.py animate` → `<name>_idle8_walking8.png` (4 columns × 16 rows),
   `<name>_idle8_x4.gif`, `<name>_walking8_x4.gif`, `<name>_idle8_walking8_frames_x2.png`. It prints how many pixels
   the 1st idle frame differs from the painting (0 to a few). Check the frames ENLARGED: a loose limb, a floating foot,
   a stray pixel, a shell that boils.
7. **Record it**: in `NOTES.md` at the studio root, one section per creature (the request, the shape, the variants and
   the choice, the poses, every mistake that cost a round). That is how the studio learns.

## The sheet (not negotiable)

| | |
|---|---|
| **columns** | one per direction of MOVEMENT: 1 north, 2 east (to the right), 3 south, 4 west (to the left) |
| **rows** | the frames going down: the IDLE on top and the WALKING below, on the SAME sheet |
| **name** | `<creature>_idle<N>_walking<N>.png` (a 1-frame idle = `idle1`). A new variant gets a new name (`_hovering_`, `walking16`): NEVER overwrite an approved sheet |
| **sideways** | a creature that walks sideways (a crab): `WALKS = "sideways"`, always the right flank leading |

## The rules of the shape (each one cost a rejection or a round)

| | |
|---|---|
| **art from SCRATCH** | a commercial game's sprite (Tibia's or any other) is a ruler for SIZE, fit and parts; none of its pixels go into the art |
| **the perspective** | a point at height h is drawn h/1.5 up and h/1.5 to the left; the ground seen from above, never squashed; you see the top and the south and east faces. A 1-tile creature stands at (39.5, 40) of a 64 frame; in a bigger frame, in the bottom-right tile ((71.5, 72) in a 96) and it grows up and to the left |
| **NO Create from scratch** | PixelLab creating from nothing, even with a reference, goes back to the symmetric frontal RPG view and fills the tile. Always shape + Edit |
| **PixelLab copies the defect** | a shell that is a whole ellipsoid comes out a BALL (use only the top half, with an edge); a leg with a high knee becomes a parallel STROKE (lower it, thicken it, fan the legs out). Fix the shape before spending |
| **upright parts come out dark** | spike, thin leg, rib: their visible faces (south and east) turn away from the light and become dark holes. Put the material in `painter` (the light a pixel artist paints by, in screen terms) |
| **≥ 2 px thick** | a thinner part becomes just outline; a cone's tip radius ≥ 0.5 px |
| **test the SIGN** | a wing with the tilt swapped became an EAR; a leg that should go forward went back. Every new rotation gets an `assert` in `check_signs` |
| **south shrinks** | going south (down the screen) cancels height (up-left): a head too far forward DROPS below the body in the front view. An upright creature: the head almost above the chest. North and west read longer, south and east more compact: that is the projection |
| **a HUMANOID FACE looks DOWN** | two eyes and a mouth on a level head read as "looking up the diagonal". The WHOLE head (hat, eyes, mouth) nods ~22° down about the top of the neck (the template's `nodded()`); a HAT tilts back ~40° relative to it, or the brim covers the face; and `DESIGN` tells PixelLab "head bowed slightly forward and DOWN: the face looks down toward the viewer, never up" |
| **biped: chibi proportions** | short legs and trunk, a BIG head, the face on the FRONT of the head (where the south view sees it) |
| **plain min between parts** | `np.minimum` between parts (`smin` only inside one part): the animation moves the parts apart |
| **what sits under a BRIM vanishes** | the view comes from above and the south: whatever is under a brim (a hammerhead, a hat, a snout) must stick out in front of it ~1 unit per 1.5 of height |
| **a plate in PROFILE** | a blade, fin or flat wing facing northeast/southwest comes out edge-on. Put the plate in the plane of the front-right diagonal (flat in north and south) |
| **a weapon: by the HANDLE, the blade HANGING** | the hand at the END of the haft, the haft forward almost level, the blade at the tip hanging STRAIGHT down (the only direction north and south both see wide) |
| **a thin weapon comes out JAGGED** | PixelLab draws a 2 px blade in a crooked staircase: redraw the weapon in clean pixel art over the chosen painting (~5 px, outline, light edge, dark spine), starting BELOW the hand |
| **quality** | compare at 1× and enlarged; texture with volume, never flat; show only what is really good |
| **the approved is not "improved"** | what the user approved comes back pixel for pixel; an automatic cleanup that eats a spike's tip is a regression |

## The rules of the animation

| | |
|---|---|
| **the body by WHOLE pixels** | `ca.lifted(px, forward)`: 1 px of height = 1.5 along the diagonal. The body comes out identical, only shifted |
| **limbs about their hinge** | `ca.turn(axis, degrees, hinge, then=body)`; groups: body, head (base of the neck), jaw (inside the head: `ca.compose`), each limb |
| **the WEAPON arm does not swing** | turning a limb resamples what it holds and the weapon "boils": the armed arm moves WHOLE with the body (whole pixels); only the other one swings |
| **a short step** | a chest or shell hides the top of the leg: a long step leaves the foot LOOSE. ~14° instead of 24° |
| **`exact` + `THIN`** | PixelLab's painting goes past the shape (loose feathers): in `exact` mode the fringe moves with the nearest part; thin legs it drew off their place go in `THIN` |
| **per-view poses** | if the painting put a part somewhere else in one view (a tail painted where the shape has the sword), pass `{view: poses}` to `make_sheet` and give that view its own poses |
| **the walk** | quadruped: diagonal pairs; insect/crab: alternating tripod; biped: alternating legs, the body rises where they cross, the head leads mid-step |
| **an idle with charm** | snapping pincers, a scream with a twitch, pawing the ground; eyes STILL. A rest pause at the start (~400 ms) |
| **fly/hop** | a variant of the walking: rise by whole pixels with the wings beating, or little steps + a short flight that lands (`walking16`) |
| **DO NOT animate the FACE** | PixelLab keeps the silhouette, not where the eyes and the mouth are. A tongue, a blink, an opening mouth came out ugly and were rejected. The idle animates what is RIGID and in the same place on the shape and the painting (limb, weapon, wing, pincer, the whole body), or it is just the standing frame (`idle1`) |
| **a shape part over the WRONG place of the painting** | moving a part moves the PAINTED pixels that fall on it: if the shape's throat falls on the painting's scarf, the CLOTHES jump. Only animate a part whose place is the same on the shape and the painting |

## What to say when delivering

- the sheet (the path), the size of each view, the GIFs;
- the variant chosen and why, and how much the balance dropped;
- what you did not see (the GIF playing: you see the frames) and the numbers to tune (height, angle, ms).
