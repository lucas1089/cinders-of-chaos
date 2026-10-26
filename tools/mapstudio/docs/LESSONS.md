# Lessons learned

Rules this studio learned the hard way while building jungle and lava islands. Each one cost at least one
review round. Add yours when you learn them.

## Method

- **Measure the reference first.** Every time a rule was guessed, the person found it wrong. Every time it
  was measured on the reference map and the output was measured with the same tool, it held.
- **Review batches, not single maps.** One seed hides problems that the next seed shows. Eight varied seeds
  per round catch most rule bugs.
- **Fix the rule, not the spot.** A note on one tile ("square patch here") is a symptom of a rule that
  makes squares everywhere.
- **Re-check after the last reshape.** Every step that grows or moves shapes (a final roughening, a liquid
  cleanup) can undo earlier guarantees: a closed pass, a new 1-wide strip. Run passes, cleaning and access
  checks after the final shape step.
- **Budget every loop.** A shape cleaner that toggles one tile back and forth hangs a whole batch. Give
  every "repeat until stable" loop a change budget and an error past it, and run generation with time
  limits.
- **Keep ids out of code.** Each id in code had to be found and moved again when the next biome came. Kits
  hold ids; code holds rules.

## Shapes and borders

- **Nothing straight.** Straight edges and rectangles are the first thing a viewer notices. Roughen every
  outline, including patches inside roads and the walls of cut passes. Use round brushes, not square ones.
- **No 1-tile strips.** A strip of one ground one tile wide between two others gives broken border pieces.
  Settle thin strips into the higher layer.
- **Bare seams are bugs.** Two grounds whose pair has no border must never touch. Turn one side into a
  ground that borders both.
- **Grounds without a shore stay off the water.** A road or patch ground with no border onto water gets
  kept 1-2 tiles away from it.
- **Small islands of a ground** (under about 12 tiles, inside one other ground) read as noise. Dissolve
  them.
- **Different relief families must not touch.** Two cliff sets on one tile overlap badly. Keep them 4+
  tiles apart.

## Relief and access

- **Broad tops.** Hand-made mountain tops are broad plateaus, not concentric rings. Each level follows the
  one below only partly (about a third), plus its own noise.
- **Terraces 2 tiles wide** read right. Wider leaves bare steps; one tile stacks two cliffs into a dark
  mass unless the ring tile is left without ground.
- **Every ramp must be usable:** reachable approach, clear landing, plants kept off both. A stair on a top
  whose lower level has no stair is a dead end. Place ramps level by level, each from what is already
  reached.
- **Cut passes where ranges split the ground**, and seal tiny pockets into rock. Then run the reach check:
  98%+ of walkable ground reached.
- **Liquid shores may be walkable.** Where the land draws its border onto a liquid (lava style), tiles
  beside the liquid are walkable, and region and pass logic must know it.

## Water and crossings

- **The island must not touch the area edge.** Keep 5+ tiles of open sea around it.
- **Bridges sit on straight banks**, fully on flat ground or flat border, never on a diagonal corner, with
  room to walk on at both ends. One crossing per river is enough; twins look odd. Keep 20 tiles between
  crossings.
- **Borders continue under a bridge's lip.** Don't cut a bank border where a bridge starts.
- **Rivers are narrow and smooth.** Smooth the path, draw it at a fixed width, and keep it off other water
  so it doesn't merge into bays.

## Vegetation

- **Clump with measured densities**, denser near edges and sparser deep inside, with glades in big
  meadows.
- **Never row the same id.** No same id on 8-neighbouring tiles. Mix species.
- **Paths stay open.** Big blocking plants on roads only on the outer edge of wide roads. Routes on
  mountain tops get walkable plants only.
- **Empty spots need scatter.** Deep open ground gets sparse walkable decor (tufts, stones, flowers).

## Review page

- Coordinates on the review page are surface tiles. A spot on a raised top of level k is drawn k tiles
  up-left of the tile it belongs to. Reproduce a note before you fix it.
