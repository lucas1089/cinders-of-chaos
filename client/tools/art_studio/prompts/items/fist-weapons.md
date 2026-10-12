# Fist weapons (Monk line), 32x32, one item per call

Request (2026-10-10): "a small set of fist weapons for the Monk, 5 tiers from early game to level ~500+, plus a
legendary; 32x32 item sprites, 10.98 style, oblique perspective, top-left light, dark outline, grimdark palette:
charred iron, embers, ash, bone".

One call per item at 32x32 (Create image Pro returns 64 candidates of one item at this size, so the cut needs no
sheet layout). The prompt is the 32x32 VARIANT of `.claude/skills/item-sheet/base-prompt.md` for a single item:
`{ITEM}` is replaced by each line of the list below. Size rule and STYLE as in the variant; 1 or 2 details per item.

```text
High-quality 32x32 pixel art item sprite: a single grimdark dark fantasy {ITEM}, shown alone on a transparent background, lying at a slight diagonal. SIZE RULE: the item is drawn BIG and fills the 32x32 square almost edge to edge in width AND in height, with at most 1 pixel of margin, like classic Tibia inventory items.

STYLE: authentic Tibia item sprite style, a painterly pre-rendered look, as if a small detailed painting was shrunk down to 32x32, in the classic Tibia 45 degree oblique top-down perspective showing the top surface and the front face. Almost every pixel is a slightly different shade: soft smooth gradients with fine per-pixel color noise over every surface, hundreds of colors per item, no flat color areas, no posterized bands, no clean cel-shaded clusters. Vivid saturated colors, high contrast, strong light from the top-left with soft glowing highlights and deep shadows. Forms are shaped by light and color, with very few dark inner lines. Bold 1 pixel near-black outline around the whole silhouette.

Avoid: hands, fingers, arms, human figure, flat colors, limited palette, clean cel-shaded pixel clusters, modern indie pixel art style, thick dark inner lines, pillow shading, blurry edges, micro-detail that turns into noise, photorealism, 3D render look, vector art, flat mobile-game icons, text, letters, numbers, ground, floor, base platforms, cast shadows or drop shadows, small items, empty space around the item, two items, extra items.
```

## Items (name in game -> {ITEM})

| key | name in game | {ITEM} |
|---|---|---|
| fist_t1 | charred hand wraps | pair of fist wraps made of soot-blackened linen strips wound in a thick loop, frayed burnt ends, two small iron rivets |
| fist_t2 | ashbound cestus | leather cestus fist guard, dark brown leather straps with ash-grey iron studs across the knuckles |
| fist_t3 | ember knuckles | heavy charred iron knuckle-duster with four rings, glowing orange ember cracks along the knuckles |
| fist_t4 | ossuary gauntlet | blackened iron fist gauntlet with yellowed bone plates riveted over the knuckles |
| fist_t5 | cinderforged talons | clawed gauntlet of charred dark iron with three curved iron talons and molten orange seams |
| fist_pyre | pyre saint's grasp (unique: Grasp of the Pyre Saint) | ornate blackened iron gauntlet with a small bone skull on the back of the hand and burning ember-red eye sockets, gold-tinged edges |
