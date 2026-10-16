# Credits

The single list of every third-party source in Cinders of Chaos: engine, website, fonts, art packs and tools.
The game shows it in the Credits window (login screen CREDITS button, System > Credits in game). The website shows it
at `page.php?plugin=chaos&p=credits` (footer link "Créditos / Credits").

Both are generated from this file. After an edit run:

```
python3 -I client/tools/gen_credits.py     # -> client_chaos_credits/credits_data.lua, website credits_data.json
python3 -I tools/ci/check_credits.py       # every pack of the art *sources.csv files is listed here
```

Format, read by `client/tools/gen_credits.py`:

- Only the part between the `credits:begin` and `credits:end` markers is shown. The part after it is internal.
- `## English heading {pt-BR: Título em português}`: one section. The client shows the heading through `tr()`,
  so `client_chaos_locale/pt_br.lua` holds the same pair. `check_credits.py` checks it.
- `- **Name**`: one entry. Its indented lines are `Author:`, `Licence:`, `Credit:` (a line the licence asks us to
  show, shown word for word), `Used for:` and `Source:`. Each is optional.
- A plain paragraph under a heading is shown as the section's note.

Licence notes below are copied from the repository's own records: client/MANIFEST.md, client/BASE.md,
client/fonts-src/*/README.md, website/README.md.

<!-- credits:begin -->

## Cinders of Chaos {pt-BR: Cinders of Chaos}

Game design, world, server systems, client interface, website and original art: the Cinders of Chaos team.

- **Owner art**
  - Author: the Cinders of Chaos owner (own or commissioned art)
  - Used for: monster looks, wings, decoration and equipment sets
  - Source: the equipment set sheets are the owner's own art, made for us
- **Login artwork**
  - Author: the Cinders of Chaos team
  - Used for: the login screen

## Art with required credit {pt-BR: Arte com crédito obrigatório}

- **Will's Pixel Explosions**
  - Author: Will Tice / unTied Games
  - Licence: purchased; the licence asks for credit
  - Credit: Will's Pixel Explosions - Will Tice / unTied Games
- **Super Pixel Effects Gigapack**
  - Author: Will Tice / unTied Games
  - Licence: purchased; the licence asks for credit
  - Credit: Super Pixel Effects Gigapack - Will Tice / unTied Games

## Art packs {pt-BR: Pacotes de arte}

Purchased packs. Their licence: use in personal and commercial games, modified or not; no attribution needed; the
assets themselves are never resold or shared. Mega VFX 500 is never used to train machine learning or as a style
reference; its effects are only imported into the game. The owner confirmed (2026-10-15) that the other packs here
have no such clause. Listed here as thanks.

- **Magic VFX Spells & Impacts**
  - Author: WsT
  - Licence: purchased; credit not required
  - Used for: spell effects
- **Auras & Buffs**
  - Author: WsT
  - Licence: purchased; credit not required
  - Used for: auras and buff effects
- **UI Game Feel**
  - Author: WsT
  - Licence: purchased; credit not required
  - Used for: level up, loot beams and other game feel effects
- **Projectiles**
  - Author: WsT
  - Licence: purchased; credit not required
  - Used for: missiles
- **Fields & Traps**
  - Author: WsT
  - Licence: purchased; credit not required
  - Used for: field and trap effects
- **Mega VFX 500**
  - Author: WsT
  - Licence: purchased; credit not required
  - Used for: Mystic line spell effects and missiles
- **Pixel Spellcraft VFX**
  - Author: WsT
  - Licence: purchased; credit not required
- **Anime Ki Auras**
  - Author: WsT
  - Licence: purchased; credit not required
- **Meadow Monsters Vol. 1**
  - Author: WsT
  - Licence: purchased; credit not required
  - Used for: monsters
- **WsT tile kits**
  - Author: WsT
  - Licence: purchased; credit not required
  - Used for: grounds, borders and map objects

## Free assets {pt-BR: Recursos gratuitos}

Free effect, icon and font packs. Their files name no author.

- **FX Pack 1-4**
  - Author: free asset pack
  - Licence: free to use
- **64x64 Explo and Power**
  - Author: free asset pack
  - Licence: free to use
- **500 Bullet 24x24**
  - Author: free asset pack
  - Licence: free to use
- **48x48 Shader Slash**
  - Author: free asset pack
  - Licence: free to use
- **32x32 Shades Effect**
  - Author: free asset pack
  - Licence: free to use
- **Shader Cylinder 64x96**
  - Author: free asset pack
  - Licence: free to use
- **Free Part 1-36**
  - Author: free asset pack
  - Licence: free to use
- **Raven Fantasy Icons**
  - Author: free asset pack
  - Licence: free to use
- **Future Millennium font**
  - Author: free asset pack
  - Licence: free to use
- **Gem set**
  - Author: free asset pack
  - Licence: free to use
  - Used for: gem looks in five tiers
- **Text effects set**
  - Author: free asset pack
  - Licence: free to use
  - Used for: status words over creatures

## Fonts {pt-BR: Fontes}

SIL Open Font License 1.1. The licence texts ship with the client in `data/fonts/chaos/`. The bitmap fonts made from
them are named by role, so they carry no Reserved Font Name.

- **Cinzel**
  - Author: Copyright 2020 The Cinzel Project Authors
  - Licence: SIL Open Font License 1.1
  - Used for: window titles, the login splash and captions
  - Source: https://github.com/NDISCOVER/Cinzel
- **Alegreya SC**
  - Author: Copyright 2011 The Alegreya Project Authors, Huerta Tipográfica
  - Licence: SIL Open Font License 1.1
  - Used for: Codex titles and headings
  - Source: https://github.com/huertatipografica/Alegreya
- **Alegreya Sans**
  - Author: Copyright 2013 The Alegreya Sans Project Authors, Huerta Tipográfica
  - Licence: SIL Open Font License 1.1
  - Used for: text over the game picture
  - Source: https://github.com/huertatipografica/Alegreya-Sans
- **IM Fell English**
  - Author: Copyright (c) 2010, Igino Marini
  - Licence: SIL Open Font License 1.1
  - Used for: NPC dialogue
  - Source: https://github.com/librefonts/imfellenglish
- **PT Sans**
  - Author: Copyright (c) 2010, ParaType Ltd., with Reserved Font Names "PT Sans" and "ParaType"
  - Licence: SIL Open Font License 1.1
  - Used for: the small interface fonts with the pt-BR letters
  - Source: https://www.paratype.com/public

## Engine and libraries {pt-BR: Motor e bibliotecas}

- **Server engine (TFS 1.4.2 fork)**
  - Author: The Forgotten Server contributors
  - Licence: GPL-2.0, the base tree's LICENSE file
- **Client engine (OTClient family)**
  - Author: the OTClient contributors
  - Licence: open source, the base tree's LICENSE file ships with the client
- **xBRZ 1.8**
  - Author: Zenju
  - Licence: GPL-3.0
  - Used for: HD sprite upscaling in the client
  - Source: https://sourceforge.net/projects/xbrz/
- **json.lua**
  - Author: rxi
  - Licence: MIT
  - Used for: JSON in the server scripts
- **ZnoteX**
  - Author: Open Games Community
  - Licence: open source; its own credits page is on the website (credits.php)
  - Used for: the account website
  - Source: https://github.com/Open-Games-Community/ZnoteX
- **Znote AAC**
  - Author: Znote and contributors
  - Licence: open source
  - Used for: the base of ZnoteX
  - Source: https://github.com/Znote/ZnoteAAC
- **Void layout**
  - Author: Alex (opengamescommunity.com)
  - Used for: the website layout, re-coloured for Cinders of Chaos
- **PHPMailer**
  - Author: the PHPMailer contributors
  - Licence: LGPL-2.1
  - Used for: website mail
  - Source: https://github.com/PHPMailer/PHPMailer

## Tools {pt-BR: Ferramentas}

- **PixelLab**
  - Licence: paid subscription
  - Used for: painting the themed item sets

<!-- credits:end -->

## Internal: licence tracing (not shown)

Sources the art tools record in their `*sources.csv` files. `check_credits.py` checks each one is named in this file.

- **donor B library**, **donor D library**, **donor F library**, **donor G library**, **donor H library**,
  **donor I library**, **donor J library**, **third donor sprite set**: older sprite libraries of monster, class and
  mount looks. Per look tracing: `client/tools/sprites/monster_looks/sources.csv`,
  `client/tools/outfit_art/class_looks_sources.csv`. Their authors and licences are not recorded yet, so they are
  not shown in the game or on the website.
