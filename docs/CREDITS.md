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

Game design, world, server systems, client interface, website and original art: the Cinders of Chaos team. The game's
files may not be extracted, decrypted or reused elsewhere: some art is licensed for this game only (Terms of Use).

- **Owner art**
  - Author: the Cinders of Chaos owner (own or commissioned art)
  - Used for: monster looks, wings, decoration and equipment sets
  - Source: the equipment set sheets are the owner's own art, made for us
- **Login artwork**
  - Author: the Cinders of Chaos team
  - Used for: the login screen
- **Owner-supplied outfits**
  - Source: supplied by the owner, source pack unnamed
  - Used for: the moon outfits and the costumes (plush bears, crawling hands, fry box)

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
reference; its effects are only imported into the game. The owner confirmed (2026-10-15) that the other WsT packs
here (spell, aura, tile and Meadow Monsters packs) have no such clause. The WsT monster packs bought later do: they
are never used for machine-learning training, and neither are the four WsT packs bought in October 2026 (wings, head
accessories, capes and cloaks, the Hollow Harvest Kit), which may not be shared even modified. The MutterPixel Studio packs (bought 2026-10-16 and later) and the
Pocket Cozy Pixels packs may be modified and recoloured, are never used as AI training data or a style reference, and
ask for credit (appreciated, not required). Listed here as thanks.

- **Magic VFX Spells & Impacts**
  - Author: WsT
  - Licence: purchased; credit not required
  - Used for: spell effects; since pair 36 every impact and circle (one colour each) and our procedural hits redrawn with them
- **Auras & Buffs**
  - Author: WsT
  - Licence: purchased; credit not required
  - Used for: auras and buff effects; since pair 36 all 84 auras and states
- **UI Game Feel**
  - Author: WsT
  - Licence: purchased; credit not required
  - Used for: level up, loot beams and other game feel effects; since pair 36 the level-up effect, the critical, dodge and block pop-ups and the rest of the set
- **Projectiles**
  - Author: WsT
  - Licence: purchased; credit not required; no resale, redistribution or sharing of the assets, even modified; never machine-learning training data
  - Used for: missiles; since pair 36 our procedural and the stock element missiles redrawn with them; since pair 41 (Projectiles 32px, the pack's native 32 px renders) the same missiles redrawn from those and three more appended; since pair 42 six more arrows and spears redrawn in place and fifteen more variants in free missile slots
- **Fields & Traps**
  - Author: WsT
  - Licence: purchased; credit not required
  - Used for: field and trap effects (all 31 since pair 36)
- **Mega VFX 500**
  - Author: WsT
  - Licence: purchased; credit not required
  - Used for: Mystic line spell effects and missiles; since pair 36 every effect (directional ones in eight directions) and the missiles that fit
- **Pixel Spellcraft VFX**
  - Author: WsT
  - Licence: purchased; credit not required
  - Used for: the first animated spell effects, auras and missiles; since pair 36 also some of our procedural effects redrawn
- **Grid Magic 500**
  - Author: WsT
  - Licence: purchased; credit appreciated, not required; no resale, redistribution or sharing of the assets, even modified (they ship only inside the compiled game); never machine-learning training data
  - Used for: since pair 36 (2026-10-22) all its tile spells, fields, area skills and cones (directional ones in eight directions), and our procedural area and hit effects redrawn with its tile spells
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
- **MutterPixel Studio animated VFX**
  - Author: MutterPixel Studio
  - Licence: purchased; use in games, modified or recoloured; no resale or sharing of the files; never AI training data
  - Credit: Art by MutterPixel Studio
  - Used for: condition auras, element blasts, missiles, level-up and boss fireworks, hit splashes, the loot beams (pair 36)
  - Source: Pixel Loot Beams - Animated VFX, Pixel Status Effects - Animated VFX Pack, Pixel Projectiles - Animated VFX, Pixel Fireworks - Animated VFX, Pixel Blood VFX - Animated VFX, Pixel Explosions - Animated VFX
- **MutterPixel Studio pixel art packs**
  - Author: MutterPixel Studio
  - Licence: purchased; use in games incl. commercial, modified or recoloured; no resale or sharing of the raw files (they ship only inside the compiled game); never AI or NFT training data or a style reference
  - Credit: Art by MutterPixel Studio
  - Used for: monsters, tiles, buildings, decoration, portals, magic effects
  - Source: Frozen Ruins, Classic Horror Monsters, Trick-or-Treaters, Autumn Graveyard Builder, RPG Magic Shops, Big RPG Portal Gates, Survivor Base, Zombie City, Gothic Buildings, Animated Cult NPCs, Lava Islands, Animated Goblins, Wasteland City Buildings, Castle Throne Room, Dwarven Mountain, Fantasy Wall Decorations, Roman Battle Arenas, Medieval Castle Builder Kit, Ruined Medieval Buildings, Animated Volcano Pack, Pirate Ships Pack, Fantasy Portal Gates, Pixel Icebergs, Cozy Halloween Market, RPG Castle Buildings, Haunted Ghosts, Ghost Town Builder, Zombie Outbreak Response, Desert Campsite, Haunted Manor Builder Kit, Dark Worship Interior, Animated War Beasts 1, Goblin Camp, Wasteland Town Buildings, Mushroom Buildings, Wizard Buildings, Roman Vineyards & Wineries, Orchard Trees Pack, Medieval War Machines, Colossal Ruined Towers, Ancient Pyramid Pack, Desert World Builder Kit, Magic Forest Ancient Ruins & Mystic Flora, Demon Creatures, Magic Effects, Summoning Circles, Haunted Graveyard Builder Kit, Castle Dungeon, Mineshaft Builder Kit, Ruined Village Builder Kit, Ancient & Mysterious Landmarks, Animated Skeleton NPC Pack, Vermin Pro Expansion, Giant Squid Boss, Animated Trees, Medieval War Camp, RPG Guard Buildings, Desert Village Buildings, Roman Temples & Shrines, RPG Weapons, Castle Royal Bedroom, Survivor Characters, Zombie Civilians, Dinosaur Fossil Dig Site, Roman City Builder
- **Pocket Cozy Pixels packs**
  - Author: BloomPixle / Pocket Cozy Pixels
  - Licence: purchased; commercial use and edits allowed; no resale or free sharing of the raw files (they ship only inside the compiled game); no AI image generator or NFT training
  - Credit: Art by Pocket Cozy Pixels
  - Used for: bushes, water tiles, village decoration
  - Source: Cozy Farmhouse Bathroom, Boats & Docks Pack, Forest Bushes & Berry Shrubs, Fishing Village Pack, Forest Builder Packs, Forgotten Forest Ruins, Cozy World Animated Sewer Builder Kit
- **WsT monster packs**
  - Author: WsT
  - Licence: purchased; modified or not, no attribution needed; no resale or sharing of the raw files; never machine-learning training data or a style reference
  - Used for: monsters
- **WsT Magic VFX / monster packs**
  - Author: WsT
  - Licence: purchased; credit appreciated, not required; no resale, redistribution or sharing of the assets, even modified (they ship only inside the compiled game); never machine-learning training data
  - Credit: WsT Magic VFX / monster packs (by WsT)
  - Used for: 51 hunting monsters and the new looks of 17 more (2026-10-22); the spell, level-up and game feel effects of pair 36 (the packs listed above)
- **WsT Wings Pack**
  - Author: WsT
  - Licence: purchased; personal and commercial use, modified or not; no attribution needed (credit appreciated); no resale, redistribution or sharing of the assets, even modified; never machine-learning training data
  - Used for: wings cosmetics (planned)
- **WsT Head Accessories Pack**
  - Author: WsT
  - Licence: purchased; personal and commercial use, modified or not; no attribution needed (credit appreciated); no resale, redistribution or sharing of the assets, even modified; never machine-learning training data
  - Used for: head accessory cosmetics (planned)
- **WsT Capes & Cloaks Pack**
  - Author: WsT
  - Licence: purchased; personal and commercial use, modified or not; no attribution needed (credit appreciated); no resale, redistribution or sharing of the assets, even modified; never machine-learning training data
  - Used for: cape cosmetics (planned)
- **WsT Hollow Harvest Kit**
  - Author: WsT
  - Licence: purchased; personal and commercial use, modified or not; no attribution needed (credit appreciated); no resale, redistribution or sharing of the assets, even modified; never machine-learning training data
  - Used for: harvest farmland and catacomb tiles, decoration, event props and monsters (planned)
- **Dark Fantasy RPG UI Kit Full Pack**
  - Author: ZSS Game Lab (itch.io)
  - Licence: purchased; personal and commercial use, resized, recoloured and modified; no resale, redistribution or repackaging of the files as standalone assets (credit appreciated); made with AI-assisted workflows and refined by hand
  - Used for: the liquid orb rings, the character plate, the action bar slots, window, panel, button, tab, text field, tooltip and minimap frames (cropped, resized and recoloured by client/tools/import_hud_kit.py; the original files are not in the repository)
- **A freely shared potion-throwing pack**
  - Licence: shared freely by its maker; no licence text
  - Used for: throwable potion flasks, projectiles and bursts

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
  - Used for: ring and necklace looks
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

## Sounds {pt-BR: Sons}

Game sounds (game_chaossound, O238): short picks from four packs, cut, set to mono and levelled by
`client/tools/gen_sfx.py`. All four are Creative Commons Zero 1.0 (the licence text in each pack's own download reads
"License: (Creative Commons Zero, CC0)"): no credit is required, and we credit the author anyway.

- **Impact Sounds**
  - Author: Kenney (www.kenney.nl)
  - Licence: Creative Commons Zero 1.0 (CC0)
  - Used for: hits, critical hits, kills, damage taken, blocks, ice, holy and earth spell sounds, the level up and unique drop sounds
  - Source: https://kenney.nl/assets/impact-sounds
- **RPG Audio**
  - Author: Kenney (www.kenney.nl)
  - Licence: Creative Commons Zero 1.0 (CC0)
  - Used for: dodges, physical spell sounds and the rare drop coins
  - Source: https://kenney.nl/assets/rpg-audio
- **Interface Sounds**
  - Author: Kenney (www.kenney.nl)
  - Licence: Creative Commons Zero 1.0 (CC0)
  - Used for: healing, goal and window sounds
  - Source: https://kenney.nl/assets/interface-sounds
- **Sci-fi Sounds**
  - Author: Kenney (www.kenney.nl)
  - Licence: Creative Commons Zero 1.0 (CC0)
  - Used for: fire, energy and death spell sounds
  - Source: https://kenney.nl/assets/sci-fi-sounds

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
- **JSch (mwiede fork)**
  - Author: Michael Wiedenbauer and the JSch contributors
  - Licence: BSD-3-Clause style
  - Used for: the ssh connection of the Cinders Admin phone app
  - Source: https://github.com/mwiede/jsch
- **Material Components for Android**
  - Author: Google and the Material Components contributors
  - Licence: Apache-2.0
  - Used for: the screens of the Cinders Admin phone app (cards, buttons, navigation, dialogs)
  - Source: https://github.com/material-components/material-components-android
- **AndroidX libraries and the Kotlin standard library**
  - Author: the Android Open Source Project; JetBrains and the Kotlin contributors
  - Licence: Apache-2.0
  - Used for: AppCompat, SwipeRefreshLayout and the other support libraries the Cinders Admin phone app ships with
  - Source: https://developer.android.com/jetpack/androidx and https://github.com/JetBrains/kotlin
- **Anthropic Python SDK and the Claude API**
  - Author: Anthropic
  - Licence: MIT (the SDK); the API is a paid service under Anthropic's terms
  - Used for: Ember, the Help channel assistant (installed on the server by the owner, not shipped in the packages)
  - Source: https://github.com/anthropics/anthropic-sdk-python

- **serde_json, serde_core, itoa, memchr, zmij (Rust crates) and the Rust standard library**
  - Author: David Tolnay, Erick Tryzelaar and the serde contributors; Andrew Gallant; the Rust Project contributors
  - Licence: MIT or Apache-2.0 (memchr: Unlicense or MIT; zmij: MIT)
  - Used for: the Rust login-screen services (server/services/clientservices-rs), built on the server by the owner when switched on, not shipped in the packages
  - Source: https://github.com/serde-rs/json and https://github.com/BurntSushi/memchr and https://www.rust-lang.org/

- **Helper module**
  - Author: R!ck, ZLukSrT#8740, Christianlb, worthdavi
  - Licence: unknown; the owner supplied the file, no licence text came with it
  - Used for: the helper window, healing and potion rows, spell rotation slots and presets (adapted to this game)

## Tools {pt-BR: Ferramentas}

- **PixelLab**
  - Licence: paid subscription
  - Used for: painting the themed item sets
- **NexaMap Editor**
  - Author: Mateuzkl, Skyyzyy and SoyFabi
  - Licence: freeware end-user licence in the source's LICENSE.rtf: free to use; copies may be passed on only unmodified, with that licence text and without a fee. Not part of our downloads: the owner downloads it from its source
  - Source: https://github.com/Mateuzkl/NexaMap-Editor
  - Used for: editing the game map (the Windows package sets its client and server folders)

<!-- credits:end -->

## Internal: licence tracing (not shown)

Sources the art tools record in their `*sources.csv` files. `check_credits.py` checks each one is named in this file.

- **donor B library**, **donor D library**, **donor F library**, **donor G library**, **donor H library**,
  **donor I library**, **donor J library**, **third donor sprite set**: older sprite libraries of monster, class and
  mount looks. Per look tracing: `client/tools/sprites/monster_looks/sources.csv`,
  `client/tools/outfit_art/class_looks_sources.csv`. Their authors and licences are not recorded yet, so they are
  not shown in the game or on the website.
- **set29 status**, **set29 projectile**, **set29 firework**, **set29 blood**, **set29 explosion**: the internal
  labels of the five MutterPixel Studio packs above, in the order of its Source line (status effects, projectiles,
  fireworks, blood, explosions). `client/tools/sprites/art_import/pack29_vfx_sources.csv` names each pick's pack by
  its label, so the pack names stay in this file (tools/ci/check_names.py).
- **set30 mutter**: the MutterPixel Studio pixel art packs above (tiles, builder kits, buildings, decoration, monsters,
  NPCs, portals, magic effects; the pack titles are the Source line of that entry).
- **set30 pocket**: the Pocket Cozy Pixels packs above (Cozy Farmhouse Bathroom, Boats & Docks Pack, Forest Bushes &
  Berry Shrubs, Fishing Village Pack, Forest Builder Packs, Forgotten Forest Ruins, Cozy World Animated Sewer Builder Kit).
- **set30 monsters**: the three WsT monster packs (75 creatures).
- **set30 potions**: the freely shared potion-throwing pack.
  `client/tools/sprites/art_import/pack30_*_sources.csv` name each pick's pack by these four labels; the vendor and
  pack names stay in this file (tools/ci/check_names.py).
- **set36 spellcraft**, **set36 beams**: the Pixel Spellcraft VFX pack and the MutterPixel Studio animated VFX
  (loot beams) above. `client/tools/sprites/art_import/pack36_fx_sources.csv` names those picks by these labels, so
  the pack names stay in this file (tools/ci/check_names.py).
- **set33 wings**, **set33 heads**, **set33 capes**, **set33 kit**: the four WsT packs of 2026-10-21 above, in this
  order: WsT Wings Pack, WsT Head Accessories Pack, WsT Capes & Cloaks Pack, WsT Hollow Harvest Kit (planned pair 33,
  `client/tools/sprites/gen_pack33.py`). Import-only: no machine-learning use, no style reference, never shared.
- **set37 outfits**: the owner-supplied outfits above (pair 37, `client/tools/sprites/gen_pack37_looks.py`): object
  builder .obd files on the owner's Drive (folders "random" and "obd+"), supplied by the owner, source pack unnamed.
  `client/tools/sprites/art_import/pack37_looks_sources.csv` names each look's file and md5. Import-only: the sheets
  are never committed; the art ships only inside the pair (and the website's outfit images, tier donor).
- **set35 icons**: the free Raven Fantasy Icons set above (its 32 x 32 full sheet). Pair 35 ring and necklace looks,
  `client/tools/sprites/gen_jewelry_art.py`; `art_import/jewelry_sources.csv` names each pick by this label.
- **sfx impact**, **sfx rpg**, **sfx interface**, **sfx scifi**: the internal labels of the four sound packs above
  (Impact Sounds, RPG Audio, Interface Sounds, Sci-fi Sounds). `client/tools/sfx_sources.csv` names each sound's pack by
  these labels and records the pick, the cut, the peak level and the sha256 of the file in
  `client/overlay/modules/game_chaossound/sounds/` (`client/tools/gen_sfx.py --check`).
