---
name: item-sheet
description: Makes an ITEM SHEET in pixel art (64x64 by default, or 32x32 in Tibia's painterly style) — builds the PixelLab prompt with the approved texture and oblique perspective, generates the sheet through the API (Create image Pro), cuts one PNG per item and builds a board to judge them. Use when the user asks for items, inventory icons, weapons, armour, potions, equipment, loot, "an item sheet", or runs /item-sheet.
argument-hint: "<items or theme; 'variations' for several versions of each; '32' for the classic size>"
---

# Item sheet

Items requested: **$ARGUMENTS**

If it came empty, ask which items (or the theme) before anything else. This is the item's ICON (what lies on the
ground and in the inventory); a piece worn on a character's body is a different sprite.

## 1. Build the prompt

Read ALL of `.claude/skills/item-sheet/base-prompt.md`: the **PIXELLAB BASE PROMPT** block is the real prompt, and the
`{...}` blocks under it are the pieces you fit in.

- **Size:** 64 by default. If the request says **32**, apply the whole 32x32 VARIANT section, including the rule that
  the item FILLS the tile.
- **Layout:** LIST by default. VARIATIONS if the request says "variations", "versions", "options of each", or if it is
  a single item.
- **Up to ~16 items per sheet.** Above that, split into sheets and say why.
- Each item in **English**: a short name, the main material with its colour, and 2 to 4 CONCRETE details (stitching,
  patch, buckle, rune, gem, crack). "Very detailed old metal" says nothing; "tarnished iron edges with small dents"
  does.
- The style, the perspective and the Avoid line are **never summarised or cut**: they are what made the sheet good.
- No `{...}` may be left. The final prompt must fit in **2000 characters** (the API's limit): cut item details, never
  the STYLE.

Save it to `prompts/items/<slug>.md` (kebab-case, ASCII): the prompt in a ```text block and, below it, the list of
items (the name shown in the game → the item on the sheet), so whoever cuts it knows what each cell is.

## 2. Generate

Show the prompt to the user and tell them it will spend generations. Then:

```
python kit/items.py gen prompts/items/<slug>.md <slug> 256
```

256×256 = a sheet of 4×4 cells of 64 (for 32 px: 128×128 with up to 16 items, or 256×256 with more). The command
prints the balance before and after and writes `out/items/<slug>/sheet_<k>.png`.

## 3. Cut and judge

```
python kit/items.py split out/items/<slug>/sheet_1.png <slug> 64
```

One PNG per item (`item_<row>_<col>.png`, alpha cut to 0/255) and `board.png` (each item at 1× and 4× on grass). OPEN
the board and check: an item that was not asked for, an item cut in half, two items stuck into one (the cut finds each
item as an opaque blob: if PixelLab made two touch, separate them by hand), an item too small for its cell (at 32 it
must fill the cell).

What came out wrong goes back into the prompt: the **Avoid** line gains the word for the problem that appeared (e.g.
`open books`, `human figure`), not a preventive list.

## 4. Deliver

The board, the list "name → file", how much the balance dropped, and what would call for another round.
