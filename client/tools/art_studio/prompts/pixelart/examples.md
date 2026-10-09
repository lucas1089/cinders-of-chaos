# /pixelart examples (Project Chaos)

Ready to paste into the PixelLab website (pixellab.ai): nothing here calls the API or needs a token. Set the canvas to
the size at the start of each prompt. Each one is under 400 characters (the website cuts longer prompts at the end).
Not generated yet: record what comes back in `NOTES.md`.

## 1. The crafting orbs (a set of 6, 32x32)

The orbs of the crafting bench (`server/data/lib/chaos_crafting.lua`), in the bench's order: Awakening (silver
mist), Gilding (molten gold), Grafting (white star), Unmaking (black void), Erasure (rust sand), Upheaval (crimson
swirl). 399 characters.

```text
32x32 pixel art set of 6 crafting orbs: silver mist, molten gold, white star, black void, rust sand, crimson swirl, 45 degree oblique top-down perspective in classic Tibia style showing top surface and front face simultaneously, richly rendered pixel art with volumetric shading and strong top-left directional lighting, same form, grimdark, Tibia-style item sprites, bold 1 pixel near-black outline
```

To redo one orb alone (T1):

```text
32x32 pixel art item: crafting orb, [ITS CORE, e.g. a crimson chaos swirl] inside dark glass in a tarnished iron cage, 45 degree oblique top-down perspective in classic Tibia style showing top surface and front face simultaneously, richly rendered pixel art with volumetric shading and strong top-left directional lighting, grimdark, Tibia-style item sprite, bold 1 pixel near-black outline
```

## 2. A support rune (32x32)

A spell support rune (`server/data/lib/chaos_supports.lua`: runes that sit in a spell's support sockets). 394
characters.

```text
32x32 pixel art item: support rune, cracked obsidian rune stone, carved socket sigil glowing violet, 45 degree oblique top-down perspective in classic Tibia style showing top surface and front face simultaneously, richly rendered pixel art with volumetric shading and strong top-left directional lighting, chipped edges, gritty grimdark, Tibia-style item sprite, bold 1 pixel near-black outline
```

## 3. The rift key (64x64 master)

The key that opens a rift (`server/data/scripts/chaos/rift_config.lua`, "Rift Key (Tier N)"). 64x64 for the master;
the 32 px client sprite is a reduction or a second prompt at 32 with the 32 px outline. 399 characters.

```text
64x64 pixel art item: rift key, jagged black iron key, bone bow, violet rift crack glowing along the blade, 45 degree oblique top-down perspective in classic Tibia style showing top surface and front face simultaneously, richly rendered pixel art with volumetric shading and strong top-left directional lighting, rust, gritty grimdark, Tibia-style item sprite, bold dark outline tinted to its colors
```
