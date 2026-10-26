# Mapping concepts

What an OT map is made of, and the rules this studio learned for making one look hand-made. The
numbers come from studying one hand-made reference map. Treat them as starting points and re-measure
them on yours.

## Tiles, floors and stacks

- A map is a grid of tiles on floors `z = 0..15`. Floor 7 is the surface, 0-6 are above it, and 8-15 are
  underground.
- The client draws each floor above the one you stand on shifted one tile up-left. So a walkable top on
  floor 6 at (x, y) shows on screen at (x-1, y-1). Keep this in mind when you read coordinates on a
  render: review notes use surface coordinates.
- A tile holds a stack of items, bottom first: one **ground**, then **borders**, then **bottom** items
  (walls, tree bases), then common items, then **top** items (roofs, canopies). The item flags in the
  `.dat` decide each item's place (`kind_of` in `tools/common.py`).
- Walkability comes from flags. A tile is walkable when it has a ground and no item flagged
  `not_walkable`. Borders and rims never block; shore and cliff pieces usually do.

## Ground families

A **family** is the set of ground items a mapper lays mixed as one ground: grass and its variants. Tools
name a family `G<lead>`, where the lead is its most used member. Variants are picked at random per tile.
Two grounds that look alike but are never mixed are two families. `tools/build_families.py` builds the
table; check it on renders.

## 12-piece sets (borders, shores, cliffs, rims)

Where a region meets other ground, a set of 12 pieces draws the edge:

- `edge_n`, `edge_e`, `edge_s`, `edge_w`: the region is on that one side.
- `inner_nw`, `inner_ne`, `inner_sw`, `inner_se`: the region is on two adjacent sides (a concave corner of
  the outside).
- `outer_nw`, `outer_ne`, `outer_sw`, `outer_se`: the region is only on that diagonal (a convex corner of
  the region).

**Pieces sit on the tile outside the region and are named toward the region.** Map editors and games
don't all name them the same way, so always confirm a new set with `tools/name_set.py` (it names each
piece from where the reference map puts it) before it goes into a kit.

Borders, water shores, mountain cliffs (pieces around the foot of raised ground) and top rims (pieces on
the edge tiles of a raised top, toward the drop) all follow the same 12-piece logic.

## The layer table: who draws onto whom

Grounds have a rank. Where two grounds meet, **the higher one draws its own border set onto the lower
neighbour's tile**. For example, with sand < gravel < rock soil < grass < water, grass draws its grass
border onto sand tiles. Some rules that follow:

- A higher ground may use a different set per lower ground (`"border": {"sand": "...", "lava": "..."}`).
- Some pairs draw nothing. Those two grounds must never touch: the seam would be bare. The generator turns
  one side into a ground that borders both (`bare seams` in the run summary must be 0).
- Water is usually the highest layer: its shore pieces lie on the land tiles. Lava-like liquids are often
  the lowest: the land draws its border onto the liquid tiles. The kit's layer order decides which, and
  the generator follows it.

`tools/seam_audit.py --pair A,B` shows what the reference map draws on each side of an A|B seam.

## Drawable shapes

A 12-piece set can't draw every shape. If a tile outside the region has region on opposite sides (a
1-wide gap or spit), or on a side and the far diagonal, its pieces would face opposite ways and look
broken. The **pinch rule** (`lib.pinched`) finds such tiles. `lib.clean` makes a shape drawable by
letting those tiles join the region. After every step that changes a shape, clean it again. The run
summary counts `odd tiles per set`. On a hand-made map it is 0 for shores, cliffs and grounds, and a few
percent for rims.

## Natural outlines

Hand-made outlines are staircases. Measured on the reference map, about a third of a border's pieces each
are edge, inner and outer pieces, and almost no edge piece runs 4+ tiles in a straight line
(`tools/outline_study.py`). Straight runs and rectangles read as artificial at once.
`lib.break_runs` and `lib.roughen` put a 1-tile bump or notch into every straight run longer than 3. They
run on every outline: coast, lakes, rivers, mountain levels, sand patches, roads and patches inside roads.

## Raised ground (mountains and hills)

A raised area of level k is built as a column:

- **Fill**: the mountain fill item on every floor from 7 up to the top's floor.
- **Top**: a walkable ground on floor `7 - k`, with **rim** pieces on its edge tiles, named toward the drop.
- **Cliff**: the cliff set on the tiles around the foot of each level, named toward the mountain. Where a
  higher level stands, its cliff pieces sit on the lower level's top.
- **Terraces**: each level stands 2 tiles inside the one below (measured: most terraces are 1-2 tiles
  wide). Where a level stands only 1 tile in, the hand-made map often leaves the ring tile without ground or
  rim, holding only the upper cliff, so two cliffs read as one tall face.
- Different relief families (grey rock against earth hills) must not touch: their cliffs overlap. Keep
  them 4+ tiles apart.

## Ramps and stairs

A ramp sits on the tile right outside a level, named for the side the level is on. Its lower half is
one tile further out. It carries a `floorchange` attribute in `items.xml`. For a ramp to be usable:

- It sits on a straight stretch of edge (no corner pieces beside it).
- The approach tiles below it are walkable ground reachable from the main ground, and don't touch the cliff.
- The landing above it and the next tile inward are clear top ground.
- Keep plants off a 3x3 around the approach and the landing.

Where a terrace is too narrow for that, seat the ramp in a small notch cut into the level's edge, the way
hand-made maps set stairs into cliffs.

## Access: every walkable tile must be reachable

Players must be able to walk everywhere that looks walkable. `gen/access.py` walks the finished map from
the main ground through every usable ramp and reports what's reached. Rules that keep it high:

- **Passes**: where mountain ranges split the ground, a 5-wide valley is cut along the cheapest path
  through the relief (round brush, walls roughened).
- **Sealed pockets**: small ground pockets shut in by relief and water become rock.
- **Crossings**: rivers and liquid channels get bridges (straight banks, landing room at both ends) or
  fords. Crossings are chosen so that every ground region joins the main one.
- **Routes on tops**: every ramp arriving on a top is joined to every ramp leaving it by a corridor kept
  free of blocking plants.
- **Re-check after the last reshape.** Every later step that grows relief or changes water can close a
  way again. Run passes and checks after the final shape step, not only in the middle.

Targets for a finished map: every ramp usable, 98%+ of walkable ground reached, tops without any ramp kept
as scenery on purpose.

## Liquids

- Water bodies: an island in open sea (keep 5+ tiles of sea at the area edge, so land never touches the
  border), lakes, rivers drawn as a smoothed path with a fixed width, and banks with their own plants.
- Liquids with variants by depth (shallow to deep water, crust to molten lava) use bands: the variant mix
  depends on the distance to land (`tools/bands.py` measures it). Far from land, the deepest variant
  dominates.

## Vegetation and decor

- **Per-ground rates**: how many of each plant per tile, learned per family (`tools/family_items.py`).
- **Clumping**: plants cluster. Local density in a 5x5 window is measured as quantiles per distance-to-edge
  band (`tools/clump_study.py`), and the generator maps a noise field through those quantiles
  (`lib.place_clumped`).
- **Edge density**: plants are denser near other grounds (about 2x the mean 1-3 tiles from an edge, 0.2x
  deep inside), which gives belts along roads, shores and cliffs and open meadows between
  (`tools/edge_density.py`). Break up big empty meadows with sparse walkable scatter.
- **No rows**: never put the same item id on 8-neighbouring tiles. Mix species.
- **Paths stay open**: blocking plants never close a corridor. Canopies may overhang roads and water,
  but bases never sit on water, shore or cliff tiles.

## Ground mosaic

Hand-made maps mix 3-5 grounds per biome: main ground, roads (3-5 wide, winding), patches, worn rims
along roads, rock or gravel aprons at cliff feet, and other grounds on mountain tops. Each gets its share
and widths from the reference map (`tools/ground_context.py`, `tools/top_ground_study.py`), and every seam
is bordered by the layer table.
