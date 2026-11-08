# Unity prototype client (O405)

A test of the game in Unity. It logs in to the real server, draws the map from the real sprites, shows creatures with
their outfit colours and walks. Its UI: login, the character list, names and health bars, a health and mana panel
and a chat window (Enter talks, the x hides it). F12 shows the debug line and the protocol log.
The map shows exactly the 15 x 11 tiles around the player, centred; the rest of the screen stays dark.
Text and windows grow with the window height (720 px is scale 1).
Game windows are `GameWindow` classes (`ChaosApp.Windows.cs`), one file each, listed in `ChaosApp.MakeWindows`.
- Equipment (Ctrl+E): the 10 slots as a paper doll, cap and soul. Right-click uses an item (a bag opens).
- Containers (Ctrl+O): all open bags stacked, 4 slots per row. Opens by itself. Right-click uses. Drag a slot onto
  an equipment slot or another bag slot to move it. ^ goes up one bag, x closes.
- Skills (Ctrl+K): level and experience bar, magic level, the 7 skills, stamina, speed, cap.
- Windows live in `Assets/Chaos/Unity/Windows/`. `ItemSlots.cs` is the shared slot and drag code.
They are movable, open from the toolbar left of Log out or with Ctrl + their key, and hide the creature names under them.
The splash screen and the login header show our logo (`docs/brand`, copied in by `ChaosBuild`).
A Personal license keeps the engine's "Made with" line under our logo; the setting turns it off on a license that allows it.
Windows so far (files in `Assets/Chaos/Unity/Windows/`):
- Battle (Ctrl+B): creatures on your floor in view, nearest first. Left-click attacks (again stops), right-click follows. The target has a red row and a red frame on the map.
- Minimap (Ctrl+M): the remembered minimap round you (2 px per tile), floor up/down and zoom buttons. `MinimapMemory` (`Core/Minimap.cs`) keeps explored ground per floor.
- Hotkeys: 12 slots, F1 to F12, open at the bottom. Click a slot to type what it says; Enter or ok saves, per character in PlayerPrefs. The keys work while the bar is open and the chat line is not focused.
  Right-click a slot to pick a spell for it in the spellbook. A slot that holds the words of a spell counts its cooldown down.
- Spells (Ctrl+P): the server's spell list (opcode 219) with the filters of the main client (learned, available soon, my vocation, all, runes; all, attack, support; search).
  Left-click casts (says the words), right-click selects and shows F1 to F12 buttons that put the spell on a hotkey slot. Cooldowns come from 0xA4 and 0xA5.
- Right-click on a creature on the map attacks it (`ChaosApp.Combat.cs`).
It does not replace the client in `client/`.

## Layout

- `Client/` is the Unity project (2022.3 LTS).
  - `Assets/Chaos/Core/` holds pure C# with no Unity types. The same files build in Unity and in `Core.Tests`.
    - `ByteIO.cs`: byte reader and writer, latin-1 strings.
    - `Crypto.cs`: XTEA, raw RSA, adler32.
    - `Things.cs`: the dat (10.98 flags plus our custom flags) and spr readers (extended, transparency).
    - `Outfits.cs`: outfit colours, the colour mask.
    - `ClientGuard.cs`: the client guard answer (HMAC-SHA256) and the hello.
    - `Identity.cs`: who the client says it is (OS word, markers, capabilities) and the 0x43 feature list.
    - `ExtOpcodes.cs`: extended opcodes (0x32): JSON reader and writer, chunk join, dispatcher by opcode.
    - `Spells.cs`: the spell list (opcode 219), filters, cooldowns, cast by words. `Loc.cs`: UI texts in English and pt-BR.
    - `World.cs`: tiles, stacks, creatures.
    - `Protocol.cs`: framing, login packets, the TCP connection, the login answer.
    - `NpcTrade.cs`: NPC shop and talk model, the shop packets.
    - `Game.cs`: `GameParser` reads the server's messages into a `World`. `GameSession` adds login, guard, pings and walking.
  - `Assets/Chaos/Unity/` holds the app.
    - `ChaosApp.cs` builds everything from code at start.
    - `MapView.cs` is one dynamic mesh per frame, drawn in the stock order.
    - `SpriteAtlas.cs` is a 4096x4096 atlas of 32 px cells.
    - `Hd2dView.cs`, `Hd2dShot.cs`, `Hd2dPost.cs`: the HD-2D view (see below). Core: `Hd2d.cs`, `Hd2dDemo.cs`.
    - `FrontLiveFx.cs`: live combat effects over the front-art view (see "Front-art effects"). Core: `FrontFx.cs`, `FrontFxIds.cs` (generated), `FrontFxArt.cs`, `FrontFxDirector.cs`.
    - `Hd2dRuins3d.cs`, `Hd2dChars3d.cs`: 3D models for the map and the creatures. Core: `Hd2dRuins.cs`, `Hd2dTerrain.cs`, `Hd2dWorld3d.cs`, `Hd2dChars.cs`, `PixelText.cs` (the label font of the line-up shot).
  - `Assets/Chaos/Editor/ChaosBuild.cs` is the batch build.
- `tools/` holds Python tools: `hd2d_preview.py` (offline HD-2D pictures) and `fetch_3d_assets.py` (the KayKit characters, see "3D characters"), each with a test.
- `Core.Tests/` is a .NET 8 console project. It compiles `Core/` and runs the checks.
- `Client.Check/` compiles the Unity scripts (`Core/` and `Unity/`) against the engine's reference assemblies from NuGet,
  so a C# error shows on every PR without a Unity license: `cd unity/Client.Check && dotnet build`.

## HD-2D view (O432)

A visual proof: the same pixel-art sprites in a 3D scene, with real lights, shadows and a tilted camera. F9 switches between
the classic flat view and HD-2D (F10 adds the 3D world, see below); the choice is saved in PlayerPrefs (`chaos.hd2d`). F9 is also hotkey slot 9: while the hotkey bar
is open and the chat line has no focus, use Ctrl+F9. The UI windows are the same in both views.

- `Core/Hd2d.cs` (pure C#, tested in `Core.Tests/Hd2dTests.cs`) lays out a tile stack from the dat flags. The rule is in the file comment:
  ground and ground borders are flat quads on the floor; fluids, splashes, lying items, walkable on-bottom items and large walkable
  decorations (carpets) lie flat as decals; blocking on-bottom items (walls) and blocking items (pillars, statues) stand as upright
  billboards at the tile's back edge; other items, on-top items and creatures stand in the tile's middle.
- A sprite of W x H cells keeps its footprint: anchored on its own tile's east edge, extending west (the way a 64 px item is drawn up and
  left in the classic view) and up. Upright heights are stretched by 1 / cos(pitch) so a sprite keeps its height on screen. Displacement
  and elevation of the dat are applied.
- The game art draws height going up and to the left. Every upright thing, creatures included, is straightened row by row:
  `Hd2d.Lean` measures, on the thing's first idle frame (an outfit facing south), where the middle of its art sits at each
  height, and each upright cell is drawn in `Hd2d.Strips` strips moved east so that middle sits over the base (never leaning
  back, at most `MaxSlant` tiles per tile up). A pillar, a torch on its pole (the flame stays over it) and a figure all stand
  up. Profiles are measured once per type (`Hd2dView.LeanOf`). The synthetic demo art is drawn straight and is never moved
  (`Hd2dView.StraightArt`). Without a profile (tests) `Hd2d.ShearFor` shears 2 x 2 walls and pillars one tile per cell.
  The preview (`hd2d_preview.py lean_of`) applies the same profile.
- Lights come from things with the dat light attribute (level = range in tiles, colour = the 8-bit 6 x 6 x 6 index, 0 means white) and from
  creatures with a light. The nearest 8 become Unity point lights (4 on mobile); the nearest 2 cast soft shadows (none on mobile). A wall light
  hangs 0.4 tile in front of its wall.
- The camera looks at the player's tile from the south at pitch 40 degrees and a 25 degree field of view, at the smallest distance that keeps the
  whole 15 x 11 tile rectangle in the frame at the window's aspect. Walking is smooth.
- `Unity/Hd2dView.cs` builds two dynamic meshes over the sprite atlas (floor quads, and billboards that cast shadows) every frame, sets
  the lights and a warm dusk ambient (brighter with the server's world light). `Resources/Hd2dSprite.shader` is a lit alpha-cutout shader
  (bright texels like flames are emissive). Bloom, depth of field and fog: `Unity/Hd2dPost.cs`. Built-in render pipeline.
- Grounding: `Hd2d.ContactShadows` (a soft blob under every upright piece: creatures darkest, then objects, then walls; width from the footprint)
  and `Hd2d.WallAo` (a gradient strip on the floor along the foot of every wall-like billboard) are Core maths with tests. `Unity/Hd2dGround.cs`
  builds them as one flat mesh just above the floor, drawn by `Resources/Hd2dBlob.shader` (alpha blended, procedural radial / linear alpha).
  `Hd2dView.Build` calls `ground.Build(pieces)` once per build, so `Refresh()` (the screenshot mode) draws them too.
- Sprite light: `Hd2dSprite.shader` gives upright sprites volume: a fake normal from the alpha edge and luminance gradient of the 32 x 32 cell
  (neighbour texels clamped inside the cell), a warm rim per light, and a darker foot by world height. Floor quads stay flat. Not compiled here.
- Quality: on mobile, or with PlayerPrefs `chaos.hd2d.low` = 1, shadows and depth of field are off and fewer lights are used.

Screenshot mode: `ChaosUnity -chaosHd2dShot OUT_DIR` skips the login, builds the offline demo room (`Core/Hd2dDemo.cs`), renders it once
classic and once HD-2D at 1200 x 880 and writes `classic.png` and `hd2d.png`, then quits. It needs no server. The art is synthetic
placeholder sprites drawn by code, unless the real pair is found (`-chaosPair DIR`, CHAOS_PAIR_DIR or `things/` beside the executable)
and holds the temple tileset (pair 60); the pair is private and is not baked into the build. In the manual build with target
StandaloneLinux64 the workflow runs it under xvfb with Mesa software OpenGL and uploads the artifact `hd2d-shots` (a failure of that step
does not fail the build; the step log says why).

3D architecture test (Ruins3d): an experiment to see whether free 3D assets make the HD-2D view look better. Unity only; the game
client (OTClient family) does not use it and nothing here changes the server or the sprite pair.
- What: real low-poly architecture with the game's pixel sprites standing in it (3D diorama, pixel characters, depth of field, warm
  lights). Models: the CC0 Modular Ruins Pack by Quaternius (OBJ + MTL, no textures), 36 pieces in `Assets/Chaos/Resources/Ruins3d/`
  with the pack's `License.txt` (credited in `docs/CREDITS.md`). The repo commits no `.meta`: Unity makes them on import.
  `Resources.Load<GameObject>("Ruins3d/Wall")` works in the player; `ChaosBuild.cs` does not exclude them.
- Mapping (`Core/Hd2dRuins.cs`, tested in `Core.Tests/RuinsTests.cs`): from the HD-2D layout, ground becomes a floor piece per tile
  (Floor_Standard, Floor_Squares, a few Floor_Diamond); a ground border is dropped; a blocking on-bottom upright thing (the wall) becomes
  one Wall segment per cell of width and one course per cell of height, turned to face the open side (south, east, west, north);
  a blocking upright thing that is not on-bottom (pillar) becomes a column; a light source becomes a Torch on the wall of its tile,
  else candles on a short column. Decals (carpet), loose items and creatures stay sprites. A few props (barrel, crate, pots, chest,
  skull, bookcase) stand on free tiles in front of a wall. The Hd2dView light list is unchanged. One tile is one unit (pack scale 0.5).
  Dressing (all by tile hash, same layout same room): a wall run of 6+ tiles is 3 courses high, its top course is sometimes
  Wall_Broken / Wall_Hole / Wall_Half / Window_Bars, its middle two tiles are an arch (Wall_ArchRound or Wall_ArchGothic, the gothic one
  holds Doors_GothicArch), Flag_Wall banners and Support_Tall beams stand on some faces; a stag and a fox statue on plinths at the wall
  ends, a dead tree and a broken column in the far corners; up to `MaxProps` (22) barrels, crates, chest, pots (whole and broken), skulls,
  candles, rubble and wall bookcases along the room. No prop on a tile that holds an item, a creature or the carpet, nor within one tile of
  the carpet or a creature. The Overgrown (bright moss) variants are not shipped.
- Look: `Unity/Hd2dRuins3d.cs` copies the pack's materials per role and restyles them (`Hd2dRuins.Restyle(name, r, g, b, role)`, after a gamma
  lift): walls, columns and beams x 0.42 with a blue-grey tint and contrast x 1.18, floor x 0.55 with a warm brown dirt tint, stone props and
  statues x 0.5, wood and metal dark and dull, banners dull red, bark dark brown, flames warm and emissive. Walls get a faint fixed cold
  self-light (the first render lost the back wall: stone this dark vanished into the background). No soot gradient: the Standard shader reads
  no vertex colours. Standard shader, the view's point lights and ambient, shadows on.
- See it: the `hd2d-shots` artifact of `unity-prototype.yml` (Linux target) holds `hd2d_3d.png` next to `hd2d.png` and `classic.png`.
  Same room, same camera, same post effects. If the models are not in the build the step skips `hd2d_3d.png` and says so in the log.
- Unsure until seen: which side of the pack's walls is the nicer face, and the colour balance (the restyle lifts the pack's linear
  colours with a gamma first). Both are one-line changes in `Hd2dRuins.cs`.

3D characters (Chars3d, KayKit): see the section "3D characters" below. `hd2d_3d.png` and `hd2d_3d_close.png` show them.

3D world (World3d, Unity-only): the real game maps drawn with 3D models instead of sprites. Unity only, like Ruins3d; the game client
(OTClient family) does not use it and nothing here changes the server or the sprite pair. It reuses the Ruins3d plan and adds a role set
that works from the pixels of the sprites, because a real map has no demo tileset to know by id.
- Switch: F10 in the game, saved in PlayerPrefs `chaos.world3d`. It is active only together with HD-2D (F9): the object `World3d` is a
  child of the HD-2D view. F10 is hotkey slot 10: with the hotkey bar open use Ctrl+F10. Off: the sprites come back at once. If the
  models are not in the build, F10 says so in the chat and the map stays sprites. It attaches `Hd2dRuins3d` (WorldMode, Live) and
  `Hd2dChars3d` (Live) to the live `Hd2dView`.
- Classification (`Core/Hd2dTerrain.cs`, tested in `Core.Tests/World3dTests.cs`): every sprite is read from the atlas as raw RGBA and measured:
  mean colour of the opaque pixels (hue, saturation, value), spread of the luma, opaque share, grain (planks have lines, dirt is noise),
  share of green, grey and brown pixels. Ground, in this order: value under 0.14 Dark; bright orange-red (R 0.7, sat 0.7, value 0.7; when the
  dat animates or lights it 0.55 / 0.6 / 0.55) Lava; blue to cyan (hue 170 to 255, sat 0.4, animated 0.25) Water; bright grey-white Snow;
  grey (sat under 0.17) Stone; green (hue 65 to 165) Grass; pale yellow-brown Sand; brown with lines Wood, else Dirt; mostly clear Unknown.
  The class is cached by item id (`SpriteClassifier`); water reads all its phases (up to 8).
- Mapping (`Core/Hd2dWorld3d.cs`):

  | Sprite | 3D |
  |---|---|
  | ground Stone, Wood | the ruins floor piece |
  | ground Grass, Dirt, Sand, Snow, Dark | a thin tile, tinted from the sprite's mean colour (less saturated, x 0.6 to 0.7), plus on Grass about 15% of the tiles a Grass, Grass_Short, Plant or Rock, on Dirt a Rock (tile hash, never on a tile with anything) |
  | ground Water | a dark blue glossy plane 0.16 below the floor, a little tinted by the sprite |
  | ground Lava | an emissive orange plane 0.12 below the floor |
  | ground Unknown, ground border | sprite stays; border dropped |
  | blocking, not on-bottom, green, 2 cells high or more | a tree (CommonTree 1 to 3, PineTree 1 to 3), height 0.9 + 0.85 per cell |
  | blocking, 2 x 2 or larger, brown, not green | a dead tree (CommonTree_Dead 3 to 5) |
  | blocking, green, one cell high; or not blocking, green, small | Bush_1, Bush_2, BushBerries_1, BushBerries_2 |
  | blocking, grey, 1 x 1, no light | Rock_1 to Rock_7, Rock_Moss_1 to 3 |
  | wall, pillar, torch | as Ruins3d (a green on-bottom blocker, a hedge, stays a sprite; a big grey blocker stays a column) |
  | items, decals, doors, stairs, signs, creatures | sprite billboards, as before (creatures are the 3D characters when their models exist) |

  Carried items (pickupable, container, stackable) are never nature. Nature roles need the nature models; without them the pieces stay
  sprites (not columns). Willow is not used: the pack's willows are modelled off centre.
- Look: the palette of a map survives (tile colour is the sprite's mean, darkened `Hd2dTerrain.TileStyle`). Leaves, berries and trunks go
  through `Hd2dRuins.Restyle` (muted green, dark bark); rocks use the stone style. Terrain materials are shared per class and colour at
  5 bits a channel and drawn instanced; models are lit by the view's lights and ambient and cast shadows, tiles only receive them.
- Models: the CC0 Ultimate Nature Pack by Quaternius (OBJ + MTL, no textures), 28 pieces in `Assets/Chaos/Resources/Nature3d/` with the
  pack's `License.txt`, credited in `docs/CREDITS.md`. The Autumn, Snow, cactus and palm variants are not shipped. No `.meta` is committed.
- Live rebuild, without churn (`Unity/Hd2dRuins3d.cs`): the scene changes as the player walks. `LateUpdate` computes `Hd2dWorld3d.ViewHash`:
  a hash of the centre and, over the 18 x 14 window, each tile's position and item ids (creatures are not read; `Pos` is `IEquatable`, so
  the lookups do not box). It allocates nothing (tested: 0 bytes in 2000 calls). Only when it changes is the plan rebuilt, so a still
  player, a passing monster or an animated phase costs one hash (about 0.03 ms). Walking one tile moves the window and rebuilds. A rebuild
  keeps a pool of instances per (model, role): instances are reused and stay active when still needed, only the surplus is deactivated,
  nothing is destroyed or created once the pool has grown to the view's need. Materials are restyled once, when an instance is created. The plan
  itself takes about 0.5 ms on a 18 x 14 view (Core.Tests prints it), the placing is the transform writes of about 300 pieces.
  The sprite meshes of `Hd2dView` are still rebuilt every frame as before; `Skip` only drops the replaced pieces from them.
- Screenshot: `Hd2dShot` writes `hd2d_3d_outdoor.png` after the other files, from the real pair when found (the pair needs no temple
  tileset): `Hd2dDemo.Outdoor(dat, sprite)` scans the dat and picks the ids from the pixels (the plainest one-phase Grass and Dirt ground,
  the water with most phases, the greenest tall blocking thing as tree, a grey 1 x 1 lump as rock, a green small thing as bush), then lays
  out a meadow with a winding path, a pond, trees round it, rocks, bushes, the hero and a wanderer. Synthetic art: skipped with a log line.
  Like the other shots it renders by hand (`Refresh`, `Build`, `cam.Render()`), no frame waits.
- Limits: the current floor only (no upper floors yet); no sprite pieces of other floors; ground borders (shore, grass edges) are dropped, so a
  map's soft transitions between ground types are hard tile edges; the water has no animation or shore; sprite-based classes can miss
  (a grey-brown dirt that reads Stone, a stylised or recoloured ground); big grey statues and pillars stay columns; houses of a real map
  show the Ruins3d walls and, in the open, their props only on stone or wood floors; creatures are not part of the plan, so ruins props
  ignore them; a tree's footprint is its anchor cell and the crown overhangs tiles that may hold things; not run in a Unity editor or
  player in the session that wrote it (see the Limits below).
- Unsure until seen: the tree and rock sizes (scaled from the OBJ bounds), the tile tint (it ignores the lighting the sprite art already has),
  that the Standard shader draws the generated box and planes as intended, the cost of the pool reuse on a real map, and which grass the
  pick chooses on the real pair.

Limits, said plainly:
- The sprites are drawn for an oblique view. Upright walls look right only with this fixed camera: there is no camera rotation.
- Only the player's floor is drawn (no floors above or below).
- The classic UI windows are not ported to anything 3D; they draw over the scene as before.
- Lights and shadows are an approximation (shadows from billboards, no baked light). A creature's light is its dat or server light level.
- Not run in a Unity editor or player in the session that wrote it: the code compiles in `Client.Check` and the layout is tested, the look is
  unchecked until the first screenshot run.

## 3D characters

3D characters: every class and every monster of the HD-2D view as a 3D model, the monsters dark (skeletons, undead). Unity only, like Ruins3d.
- Models, in this order: `Resources/KayKit` (the CC0 KayKit Adventurers and Skeletons packs by Kay Lousberg: Knight, Barbarian, Mage, Rogue,
  RogueHooded, Skeleton_Warrior, Skeleton_Mage, Skeleton_Rogue, Skeleton_Minion, rigged, about 90 takes each), then `Resources/Chars3d` (the CC0
  RPG Character Pack by Quaternius: Warrior, Cleric, Wizard, committed, the fallback), then the creature sprites. Both packs are in `docs/CREDITS.md`.
  No `.meta` is committed: `Editor/Chars3dImport.cs` sets Generic rig and animations on import (the weapon FBX files keep no animation).
- Fetch step: the KayKit files are not in the repository (every character FBX is about 20 MB). `python3 -I unity/tools/fetch_3d_assets.py`
  shallow-fetches the two upstream repositories with git at pinned commits (their FBX folders are export-ignore, so a GitHub zip lacks them) (Adventurers `672074b7`, Skeletons `15b62b9b`), extracts only the
  used files (9 character FBX, 4 textures, 6 skeleton weapons, 2 licence texts, 22 files, about 190 MB) into `Assets/Chaos/Resources/KayKit/`
  (ignored by the Client folder's ignore file) and checks each against its sha256 in the script. `--check` verifies what is there, `--force`
  downloads again, `--zip PACK=PATH` uses a local archive. `unity-prototype.yml` runs it before the Unity build; a wrong hash fails the build.
  `python3 -I unity/tools/fetch_3d_assets_test.py` tests the pure parts on a fake archive (CI: `ci.yml`).
- `Unity/Hd2dChars3d.cs`: `Attach(view)` sets `Hd2dView.SkipCreature` (sprites hidden; labels, lights and shadows stay), `Build()` places the
  characters, which cast and receive shadows; materials are copies. Without any model the sprites stay and the log says so.
- Mapping (`Core/Hd2dChars.cs`, tested in `Core.Tests/CharsTests.cs`): `SpecFor(creature, isPlayer, playerVocation)` gives a `CharSpec` (model,
  fallback model, items, colour multiplier, brightness, size). Who gets what:
  - the local player: its class, from the vocation id of the login (`World.PlayerVocation`, set in `ChaosApp.Enter`); the Warrior when unknown;
  - another player: the protocol does not send the class, so the look type picks one of the 21 classes (stable). A creature with
    `Creature.Vocation` set (the offline cast) is that class;
  - a monster or summon: by name, below; an NPC: a plain adventurer without a weapon.
- Classes (the vocation ids of `server/data/XML/chaos_vocations*.xml`, `docs/CLASSES.md`; the test checks that the 21 ids match). The colour
  is a multiplier on the model's colour before the dark restyle (x 0.75 and a little grey; holy classes x 0.95):

  | id | Class | Model | Items | Colour |
  |---|---|---|---|---|
  | 4 | Warrior | Knight | sword, round shield | plain |
  | 8 | Juggernaut | Knight | sword, spiked shield | steel blue |
  | 14 | Berserker | Barbarian | two-handed axe | blood red |
  | 3 | Ranger | RogueHooded | two-handed crossbow | forest green |
  | 7 | Deadeye | Rogue | two-handed crossbow | slate blue |
  | 15 | Beastmaster | Rogue | one-handed crossbow | earth brown |
  | 1 | Mystic | Mage | staff | plain |
  | 5 | Elementalist | Mage | staff | fire orange |
  | 10 | Illusionist | Mage | wand, spellbook | violet |
  | 11 | Thief | Rogue | two knives | plain |
  | 12 | Ninja | RogueHooded | two knives | near black |
  | 13 | Samurai | Knight | sword, no shield | crimson |
  | 20 | Necromancer | Mage | wand, spellbook | sickly green |
  | 21 | Lich | Skeleton_Mage | skeleton staff | pale violet |
  | 22 | Bone Lord | Skeleton_Warrior | skeleton axe, large shield | plain |
  | 17 | Monk | Barbarian | bare hands | amber |
  | 18 | Shadowfist | Barbarian | bare hands | dark violet |
  | 19 | Iron Sage | Mage | staff | gold |
  | 23 | Templar | Knight | sword, badge shield | warm gold, light |
  | 24 | Inquisitor | Knight | two-handed sword | white, light |
  | 25 | Sentinel | Knight | sword, rectangular shield | blue steel, light |

  Melee heavy: Knight and Barbarian; casters: Mage; ranged and stealth: Rogue and RogueHooded; holy: Knight in a light tint; the two skeleton
  classes of the Necromancer line are skeletons.
- Monsters (`Hd2dChars.MonsterSpec(name, lookType)`, first match wins; stems match inside the lower-case name for undead, at the start of a word
  otherwise). Every name gets a model, the default is the Skeleton_Minion:
  1. Undead (skeleton, bone, skull, lich, undead, zombie, ghoul, ghost, wraith, necro, mummy, death, grave, crypt, vampire, risen, revenant,
     marrow, barrow, shade, reaper, thrall and more), by role: casters and liches (mage, lich, priest, seer, caller, cultist...) Skeleton_Mage with
     the staff; ethereal ones and archers (wraith, ghost, shade, banshee, count, archer, stalker) Skeleton_Rogue, ghosts with empty hands,
     archers with the crossbow; fighters (warrior, knight, golem, colossus, reaver, lancer, lord, king, warden) Skeleton_Warrior with blade and
     small shield (large shield for knights and guards, axe for golems and colossi); the rest Skeleton_Minion.
  2. Goblins and small folk: Skeleton_Minion, green.
  3. Humans and bandits, an adventurer with a darker tint (x 0.65 and x 0.85): casters (mage, witch, cultist, priest, seer...) Mage; rogues (bandit,
     thief, archer, pirate, assassin...) Rogue, hooded for assassins and shadows; brutes (barbarian, brute, warlord, butcher...) Barbarian;
     knights (knight, guard, captain, mercenary, royal, lord, `man`...) Knight.
  4. Beasts and the rest, a skeleton with empty hands by build: odd and magical shapes (elemental, wisp, slime, fungus, construct...) Skeleton_Mage;
     fast hunters (wolf, hound, spider, snake, wing...) Skeleton_Rogue; heavy brutes (bear, boar, troll, dragon, behemoth...) Skeleton_Warrior;
     anything else Skeleton_Minion.
  A colour family by word tints the body, never the glowing eyes: fire, ice, poison and rot, blood, void and shadow, gold, storm and tide, stone.
- Size: `Hd2dChars.SizeFor(creature, spriteW, spriteH)` from the outfit's sprite size in the dat (1 x 1: 1.0, 2 x 2: 1.3, 3 x 3: 1.5, more: 1.6)
  times 1.15 for a big word in the name (lord, king, dragon, colossus...) or 0.85 for a small one (whelp, imp, little...), between 0.85 and 1.6.
  Players and NPCs are 1. Base height 1.7 tiles, the Skeleton_Minion 0.9 of it.
- Items: an adventurer's FBX carries every weapon and shield as a node of the rig (`Hd2dChars.WeaponNodes`); the code hides all but the spec's
  items. A skeleton's weapons are separate FBX files, attached to the hand bone found by name (`Hd2dChars.HandBone`: `handslot.r` or
  `handslot.l`, never an IK helper), shields and offhand blades on the left.
- Look: a skeleton's "Glow" material (the eyes) is bright yellow and emissive (`_EmissionColor` x 1.6), never dimmed or tinted, no shadow.
  Everything else keeps the dark restyle times the spec's colour. Textures are bound by code (`KayKit/knight_texture`, ...).
- Pose without a frame: the idle clip is found by name in `Resources.LoadAll<AnimationClip>` (`Idle`, else `Idle_Combat`; `2H_Melee_Idle` for a
  two-handed grip, `Unarmed_Idle` for bare hands) and sampled by hand with `clip.SampleAnimation(model, t)` (t differs per creature); the Animator
  is then switched off. No idle clip: bind pose. `Live = true` resamples every frame.
- See it: `hd2d_3d_cast.png` in the `hd2d-shots` artifact is the line-up on the temple floor: one class per group in front (Juggernaut, Deadeye,
  Elementalist, Ninja, Lich, Shadowfist, Inquisitor) and the four dark skeletons behind (Risen Skeleton, Warrior, Mage, Archer), lit by the torches
  (two more are added at the row ends), names drawn from the 5 x 7 pixel font of `Core/PixelText.cs` (the screenshot is read from a render
  texture, so the game's own labels are not in it), the camera fitted to the cast. `hd2d_3d.png`, `hd2d_3d_close.png` and `hd2d_3d_outdoor.png` stay.
- Monster share per model over all 701 names (280 custom monsters of `server/data/monster/monsters` and 421 base names of
  `base_monster_names.csv`; the test prints the table): Skeleton_Minion 52.8 %, Skeleton_Rogue 10.0 %, Skeleton_Mage 9.3 %, Skeleton_Warrior 9.1 %,
  Knight 8.1 %, Barbarian 4.0 %, Mage 3.4 %, Rogue 2.6 %, RogueHooded 0.7 %.
- Not run in a Unity editor or player in the session that wrote it: the code compiles in `Client.Check` and the mapping is tested. Unsure until
  seen: the clip names after the FBX import (the files hold `Idle`, `Idle_Combat`, `2H_Melee_Idle`, `Unarmed_Idle`), the weapons' fit on the hand
  slots (identity, scale cancelled), the models' facing (`Hd2dChars.ModelYaw`), the look of the chibi proportions at 1.7 tiles, the camera fit of
  the line-up and the label positions.

## Front-art scene

A test of another look. Our 2D art is drawn at a slant, which looks wrong in 3D. This recipe: a blocky 3D diorama with crisp pixel
textures, and small FRONT-FACING pixel sprites standing upright as billboards. Night, a crypt courtyard and a ruined temple, torches
and ember glow, lit and shadowed, a tilt-shift miniature. No server, no sprite pair: everything is made in code or committed.
The ideas follow the MIT-licensed Luminati engine (docs/CREDITS.md); the code is ours.

- Open: F11 in the game (also on the login screen, own camera, F11 again closes), mouse wheel zooms from the wide view to the four
  characters. CI: the HD-2D screenshot run (`-chaosHd2dShot DIR`) also writes `front_art.png` (wide) and `front_art_close.png`
  (knight and mage facing skeleton and ghoul across a brazier) into the `hd2d-shots` artifact. Log lines start with `chaos front art:`.
  A failure of this scene alone is logged as an error and does not stop the run.
- `Core/FrontArtTex.cs` (tested): textures of 64 x 64 texels = 4 x 4 units (16 texels per unit, point filtered, tileable) for flagstone,
  cobble, dirt, mossy dirt, dead grass, brick, wood and coal, plus a pixel flame. Hue-shifted ramps (cool violet shadows, warm lights),
  four hue leans per stone or plank, bevels, chips, cracks, moss, pebbles, blades. A height map per texture gives the normal map.
- `Core/FrontArt.cs` (tested): the layout (a 20 x 16 slab, height levels of 0.5 units, a ragged 3 to 3.5 unit temple wall with a gate,
  two steps, a low wall ring with broken tiles, four pillars, graveyard, dead tree, sarcophagus, crates, rubble, five braziers, two wall
  torches, two cold lights), the mesher (a top quad per tile, sides only where the neighbour is lower, vertex ambient occlusion, one
  bucket per texture so a player merges one mesh per material) and `FrontArtFacing`: the facing against the camera yaw picks one of the
  8 pictures (the "south" picture looks at the viewer). `FrontArtCamera`: FOV 28, pitch 33, 32 units away (close view 11).
- `Unity/FrontArtScene.cs`: turns it into objects. Sprites are `Resources/FrontArt/{knight,mage,skeleton,ghoul}/<direction>.png`
  (48 x 48, 33 to 60 colours, PixelLab), with a normal map `<direction>_n.png` (PixelLab, OpenGL convention) and an emission mask
  `<direction>_e.png` (`unity/tools/gen_front_art_emission.py`: cyan eyes and gems, the staff flame near its densest cluster of
  near-white cores, lone embers; `--check` in CI). A sprite is an upright quad of 1.5 x 1.5 units (32 texels a unit) that turns with
  the camera yaw only, a blob under the feet (`Hd2dBlob`), a quad facing the sun drawn in the shadow pass only, and two ground
  silhouettes (`FrontArtCast`, multiplied into the frame, lifted 0.04): one stretched away from the nearest flame (0.95 strength,
  fading with distance), one away from the moon (0.55). Weaker silhouettes vanish on the night floor.
- Pack monsters (`Layout.Extras`, 14 of them: demons, a vampire, a werewolf, a headless rider, ghosts, cultists, a lizard mystic, a
  goblin shaman, a rat king, an armoured skeleton) come from purchased packs (`docs/CREDITS.md`, tracing alias
  "set30 mutter"). Their licence lets them ship inside the built game but not as files on their own, and this repository is public, so they
  are committed encrypted: `unity/art/front_art_packs.enc` (AES-256, the key is the repository secret `CHAOS_ART_KEY`).
  `unity/tools/front_art_packs.py build PACKS_DIR OUT` takes every idle and walk frame of each figure (64 x 64 canvases cut by
  one box around all of them, so the figure never jumps, also when it starts walking; feet on the bottom row) into `idle.png` and
  `walk.png` (frames side by side, facing right) and `idle_w.png` / `walk_w.png` (each frame mirrored, for the three west
  headings), each with a dome normal map `_n` and an emission mask `_e` per frame (glow modes per figure: the rule, every warm
  pixel for the fire demon, no cyan for the frost demon). The scene plays idle at 8 frames a second and walk at 10 (`PackFps`,
  `WalkFps`, each figure 3 frames apart) by the material's texture scale and offset, which the sprite, its shadow caster and the
  ground silhouettes (`FrontArtCast` reads `_MainTex_ST`) all follow. 12 of them patrol (`FaActor.Walks`, `FrontArtWalk` in
  Core): stand at home facing the scene, walk to `WalkX, WalkZ` at 0.75 units a second, stand there looking back, walk home;
  a start shift per figure. Their contact blobs move with them. Core tests: every patrol on flat open ground clear of graves,
  pillars and crates, figures 0.7 apart at every tenth of a second over a minute. Attack spells (`Layout.Spells`, `FaSpell`,
  `FrontArtSpells` in Core): the horde, the ghost king and the cultists cast at the knight and the mage, the mage answers at the
  fire demon. A walker casts while it stands at home: it turns to the target and plays its pack attack strip (`attack.png`; the
  ghosts have none and stay idle), the missile leaves at 0.45 s, flies at 5.5 units a second in a small arc following the
  target, and the impact plays on the target for a second; a point light in the spell's colour travels with the missile and
  flashes on the hit. Art: `front_art_packs.py fx PROJ_DIR OUT` writes `fx_<name>/missile.png` (the projectile
  pack's sheet: 8 direction rows E, SE, S, SW, W, NW, N, NE, 8 frames of 64; the row follows the missile's heading on screen)
  and `fx_<name>/impact.png` (a burst drawn in the missile's own colours: flash, ring, sparks; 12 frames of 128), sealed into the same `.enc`. Shader `FrontArtSpell` (premultiplied,
  brightened for the bloom). Core tests: casters stand while casting, the missile leaves the caster and lands on the target,
  before the next cast, never in the ground. Melee (`FaMelee`, `FrontArtMelee` in Core): the skeleton runs at the knight and the knight cuts back, the
  ghoul and the vampire run at the mage, the ghost knight at the knight. An attacker runs at 3.2 units a second to 0.95 from its
  target (a lunge: a 0.3 step), swings (the pack attack strip; the four lean in), a slash drawn in Core (`FrontArtSlash`, a
  crescent in the attack's colour with a white edge) and a flash light land 0.4 s in, it holds, then runs home. The target is
  pushed back and flashes red (`_Hit` of `FrontArtSprite`). Core tests: home inside the period, swing and slash at the blow,
  the target flinches, the slash within reach, every figure 0.5 apart. `Hd2dShot` adds `front_art_melee_000..299.png` (60 a second). `Hd2dShot` adds `front_art_anim_00..39.png`, the east horde over five seconds. `seal OUT ENC` encrypts,
  `open ENC Resources/FrontArt` is the step of `unity-prototype.yml` before the build. The opened `pk_*` folders are ignored by git;
  without them (no secret) the scene leaves the extras out. 40 texels a unit (1.6 units; the 32-texel skeleton 1.0). To change the
  figures: download the packs from the owner's Drive, run build and seal with the key, commit the new `.enc`.
  `Editor/FrontArtImport.cs` keeps the pictures (and the `fx_*` spell art) uncompressed, point filtered, without mips; normal and emission maps linear.
- Shaders (built-in pipeline, in `Resources/`, so a player build includes them): `FrontArtBlock` (world mapped uv from the mesh, the
  relief from the normal map per face axis, vertex colour as tint and occlusion, lambert with the moon's shadows and point lights,
  `_Emit` for coal) and `FrontArtSprite` (cutout sampled at mip 0, bent normal between the direction to the camera and up, wrap
  diffuse, small warm fill, the normal map at 0.85, point lights scaled and rolled off, `_EmitTex` x 2.2 added as light). Both add the trilight ambient by hand as emission. Flames use `Hd2dGlow` (additive, HDR colours so they
  bloom), halos and embers `Hd2dParticles`.
- Light and post: one moon (soft shadows, 2048, one cascade), a cool trilight ambient, warm flickering point lights (`Hd2d.Flicker`),
  exponential squared fog into a dark far ground, then `Hd2dPost` tuned in `FrontArtScene.Tune`: a thin sharp band (wide view
  focusHalf 0.13, feather 0.30, close 0.20 / 0.26), exposure 1.0, bloom threshold 1.0 and intensity 0.9, vignette 0.5, grain 0.035.
- Look at it without the engine: `CHAOS_FA_DUMP=DIR dotnet run -c Release` in `Core.Tests` writes the texture sheet and a CPU preview
  of both views (`front_art_preview.png`, `front_art_preview_close.png`: no shadows, no post, only for the layout and the camera).
- Not run in a Unity editor or player in the session that wrote it: it compiles in `Client.Check` and the data is tested. Unsure until
  seen: the two shaders (they only compile in CI: the ambient as emission, the base-pass-only emission, the shadow bias 0.03 and
  normal bias 0.45), the sun-facing proxy bias, the exposure and the tilt-shift values, the strength of the flame halos
  (`Hd2dParticles` clamps their size), the number of point lights (nine, eight forced to pixel).

## Front-art live view (F8)

The front-art look (previous section) on the real map: the live server world around the player as a blocky diorama with pixel textures,
the things standing on it as upright front-facing sprites of the real art, moon, flickering point lights, tilt-shift, bloom, fog, embers.
Creatures and effects are not drawn by this view: `FrontLiveCreatures` and `FrontLiveFx` (written apart) join it.

- Switch: F8 in the game, saved in PlayerPrefs `chaos.frontlive`. It takes over from the classic and HD-2D views (F9 stays saved but hidden);
  F8 is hotkey slot 8: with the hotkey bar open use Ctrl+F8. Mouse wheel zooms (not over a window). The camera follows the player's drawn
  position with a short smoothing: FOV 28, pitch 33, at the distance where the classic 15 x 11 tiles fit the screen times the zoom.
  The sharp band of the tilt-shift is thicker than the scene's (0.26, `FrontLiveView.FocusHalf`) so the map stays readable.
- `Core/FrontLive.cs` (pure C#, tested in `Core.Tests/FrontLiveTests.cs`): `FrontLive.Build(world, anchor, classifier, options, lean)` gives a
  `FrontLiveLayout`: a `FrontArtLayout` grid (heights, textures, tints, voids, boxes for props), upright and flat sprite pieces, lights.
  `FrontLive.ViewHash` is the rebuild key (centre, item ids of the 20 x 16 window and of the floors below; creatures not read; no allocation).
- Window: the tiles the client keeps, 8 left, 9 right, 6 up, 7 down of the player and one more round it, 20 x 16. A tile the server did not send
  is a void: no top, the neighbours' sides fall away (the cut edge of the slab). World units: one tile is one unit, +x east, +z north, tile
  (x, y) is x - Anchor.X, Anchor.Y - y. The anchor is the first centre and moves only after 192 tiles. Textures are mapped by world position and
  the variety of a tile comes from a hash of its tile position, so a tile keeps its look when the window moves.
- Ground, by the pixels of its sprite (`Hd2dTerrain.Classify`): Stone is Flagstone (one in six Cobble), Wood Wood, Grass Grass, Dirt Dirt (one in
  eight MossDirt), Sand Sand, Snow Snow, Water Water and Lava Lava (both one level, 0.5 units, lower; the lava glows, the water drifts), Unknown
  Dirt, Dark a hole. The sprite's mean colour leans through as a vertex tint (a third of the way from grey). A ground the dat marks not walkable
  and that reads Stone or Dirt is a cliff of 4 levels. Five new block kinds in `FrontArtTex` (Grass, Sand, Snow, Water, Lava; 64 x 64, hue-shifted
  ramps, tileable, `FrontArtTex.Emit` and `ReliefStrength` per kind).
- Walls: an on-bottom blocking item raises its tile to a block. A sprite that fills 70 percent of the cell or more is a full wall (5 levels, 2.5 units),
  45 percent a low wall (3 levels), less a fence (2 levels), a green one (40 percent green pixels) a hedge of grass (2 levels). The side texture from
  the colour: grey Flagstone, red-brown Brick, brown with lines Wood, pale yellow-brown Cobble.
- Items: ground borders are dropped (hard tile edges). Decals, and loose one-cell things that fill their tile (stairs, a hatch, a rug), lie flat on the
  block top. A grey blocking 1 x 1 thing is three rock boxes, a tall or wide grey one a pillar of four boxes (base, shaft, capital, band), a brown blocking
  thing of two cells or more a wooden box and its lid (big furniture). Everything else, light sources and trees included, is an upright sprite of
  the real art in the plane through the middle of its tile (cells going west and up, straightened by the measured lean profile as the HD-2D view does).
  Items stand on the top of their block (on the water at -0.5), lifted by their elevation.
- Lights: every item or ground with a dat light level becomes a `FaLight` at its tile, range `level * 0.85 + 2` (3 to 8), intensity 0.6 to 1.6, Flame
  for warm colours (flicker, embers, shadow). At most 96 per layout; the view lights the nearest 8 (4 on phones) each frame, the player's own light first,
  and the two nearest flames cast soft shadows. The world light level lifts the moon and the ambient from the night look toward day.
- Floors below: a tile without ground on the player's floor shows the floor below at the cell one tile south-east (what the stock client draws), 3 units
  lower and darker (x 0.55 per floor), ground and walls only, two floors at most; with nothing below it is a void.
- Rebuild, without churn: `FrontLiveView.Refresh` hashes the window and rebuilds only when it changes (a step, an item). The 13 terrain meshes, 13 prop
  meshes and the two sprite meshes are refilled in place. A layout with animated sprites refreshes the sprite meshes five times a second.
  Core.Tests prints the numbers (mixed window: build about 0.4 ms, meshing about 3 ms, 835 block quads, 41 sprite quads on the test map; limits in the
  test: 25 ms each, 6000 block quads, 1200 sprite quads).
- Contract for the creature and effect components (reflection in `FrontLiveView.Init`: `Chaos.Client.FrontLiveCreatures`, `Chaos.Client.FrontLiveFx`):
  `Cam`, `World`, `Atlas`, `Vector3 TileToWorld(x, y, z)` (middle of the tile at its ground height; a tile on a floor below is drawn shifted),
  `float GroundY(x, y, z)`, `DrawnTile(creature)` and `DrawnPoint(creature)` (smooth walking position), `event Action<float> Ticked` (every frame after
  the world update, clock in seconds), `Labels` (a `List<Hd2dView.Label>` the creatures fill: ChaosApp draws names, health bars, the attack frame and
  right-click attacks from it while the view is on), `AddFrameLight(FaLight)` (a light for one frame), `Layout`. Terrain materials sit in render queue 1990
  and the ground silhouette shader (`FrontArtCast`, 1995) draws after them, as in the front-art scene.
- CI: `-chaosHd2dShot DIR` also writes `front_live.png` (wide, 1.7 times the classic fit) and `front_live_close.png` (0.6) from the outdoor world of the real
  pair (the meadow, pond and trees of `hd2d_3d_outdoor.png`), else the temple room. The player is not drawn (no creatures here). Log lines start with
  `chaos front live:`. A failure of this shot alone is logged as an error and does not stop the run.
- Not done: stairs and ramps (the dat does not say which item changes the floor: they stay sprites or flat sprites), doors as doors (a closed door is a wall
  block, an open one a flat sprite), a hand-modelled tree, floors above, animated water beyond the texture drift, creature lights beyond the player's.
- Not run in a Unity editor or player in the session that wrote it: it compiles in `Client.Check` and the layout is tested. Unsure until seen: the
  look of the ground tints on real maps, whether the heuristic wall heights (cell fill) fit the real walls, fences and doors, the cost of the sprite
  meshes with many animated items, the sharp band at 0.26, the shadow of the upright sprites through the cutout, the pick of grey and brown things for boxes.

## Front-art creatures

The live game's creatures (players, monsters, NPCs, summons) in the front-art look: upright front-facing pixel billboards, lit by
`Resources/FrontArtSprite.shader`, with a contact blob, the two ground silhouettes, a shadow caster, a name and a health bar.
`Unity/FrontLiveCreatures.cs` is added to the `FrontLiveView` object by reflection; it reads `Cam`, `TileToWorld`, `GroundY` and
`World` from the view and moves on its `Ticked` event. Objects are pooled (one set per creature on screen). Log lines start with
`chaos front creatures:`.

- Looks (`Core/FrontLooks.cs`, tests `Core.Tests/FrontLooksTests.cs`):
  - Monsters and summons go by name to one of the 14 pack figures (`pk_<folder>`): goblins, rats, flyers, headless riders, vampires,
    cultists and casters (red for fire and blood, dark for the rest), ghosts (king for a crowned one), skeletons and bone, wolves and
    other furred beasts, lizards and snakes, the ice family, the fire family and brutes. Plain ghouls use the committed `ghoul`
    pictures. First rule that matches wins; the order is in `ForMonster`. Over the server's 701 monster names (280 custom, 421 base)
    about half get a figure; humans, bosses with invented names, plants and slimes stay their outfit.
  - Players go by class (`Hd2dChars.Classes`, 21 vocations): knight, barbarian, holy and melee classes are the `knight` pictures, casters
    the `mage`, the Lich and the Bone Lord the `skeleton`, each in the class tint softened (0.75 to 1.25, shader `_Tint`). The five
    ranged and stealth classes (Ranger, Deadeye, Beastmaster, Thief, Ninja) have no picture yet and are drawn as their outfit; a new
    hero set needs a folder and one row in `FrontLooks.HeroOfModel`. The local player is its class from the login; another player,
    whose class the protocol does not tell, is the knight or the mage by the outfit's look type.
  - Everything else (NPCs, no rule, art missing) is the creature's own outfit: `FrontOutfit.Compose` builds the classic art (base
    layer coloured by the mask layer, addons, all cells of a 2 x 2 or bigger sprite) into one picture standing on the tile, 1 cell = 1
    unit, same shader and lighting. It is not straightened (no `Hd2d.Lean`). Pictures are cached by type, direction, phase and colours.
  - Fallback chain when art is missing (the pack art exists only in CI after opening `front_art_packs.enc`): pack figure, then the
    committed `skeleton` or `ghoul` pictures (`FrontLook.Alt`), then the outfit. Nothing is ever left out.
- State (`Core/FrontLiveAnim.cs`): `FrontCreatureState.Update(t, creature, foe)` on its own clock, so it needs no game clock.
  - Movement: a step is told by `Creature.WalkStart` changing; the picture goes from where it is (the step's origin when far) to the
    tile over `WalkMs`. Jumps snap. Walk clip while stepping, hop for pictures without a walk strip.
  - Facing: the server's direction (`FrontLooks.Face`, x east, z north); the heroes pick one of 8 pictures with `FrontArtFacing`, the
    pack strips face right and the three west headings use the `_w` mirror, outfits pick the dat direction.
  - Attack: a creature with a foe next to it (`FrontTargets.Foe`: a monster fights players and own summons, a player or summon fights
    monsters; the local player's picked target first, `FrontLiveCreatures.LocalTarget`) that is not mid-step swings every 2 s for
    0.75 s, turned to the foe: the attack strip, or for heroes a lean of 0.12 tile. `Strike(t)` forces a swing.
  - Flinch: when `HealthPercent` drops it is pushed 0.16 tile away from the foe (backwards without one) over 0.3 s and flashes red
    (`_Hit` of the shader).
- Name and health bar (`FrontLabel`, `PixelText` font): outlined name in a pale tint of the health colour (green, yellow, orange,
  red), a 26 x 3 texel bar under it; NPCs have the name only. One texture per creature, redrawn when name or health change.
- `Unity/FrontArtSprites.cs` holds what `FrontArtScene` and the live creatures share: shader lookup, point filtering, strip frames, the
  quad, the ground silhouettes (`ApplyCast`) and `FrontArtSet`, the loader of a figure folder (8 pictures or idle, walk and attack strips
  with `_n` and `_e` maps). Silhouettes and shadows take the nearest point light and the first directional light of the scene.
- What the server and parser do not tell yet (needed for exact attack animation): who attacks whom and damage effects. `Game.cs` reads
  the magic effect (0x83) and the animated text (0x84) and drops them; with a hook for them `FrontCreatureState.Strike` swings the
  creatures next to the effect. Until then attacks are the adjacent-foe rule above, a good guess for melee and wrong for ranged.
- Needs from the host: `FrontLiveCreatures.SpriteSource` (`SpriteAtlas.Raw`; found by reflection on a member `Atlas` of the view when
  unset) for outfit art, and `LocalTarget` (`Game.AttackTarget`) for the local fights. Without a source, outfit creatures are not drawn.
- Not seen in a Unity editor or player in the session that wrote it: it compiles in `Client.Check` and the logic is tested. Unsure until
  seen: label size and position at both zoom levels, the pack figure scale next to a 1 x 1 outfit, outfit pictures with the oblique lean
  of the art, the `_Tint` strength.

## Front-art effects

Live combat in the front-art look (track C of the front-art game): what the server sends in a fight, drawn over `FrontLiveView`.
Not run in a Unity editor or player in the session that wrote it: it compiles in `Client.Check` and the logic is tested.
- Parser (`Core/Game.cs`, `GameParser`): the magic effect 0x83 (position, 16 bit id), the distance shot 0x85 (from, to, 8 bit id), the animated
  text 0x84, the creature square 0x86 and the damage, heal and experience messages 0xB4 modes 23 to 29 (up to two values with their text colours,
  and the sentence) become `FxEvent`s on `World.Fx` (`FxFeed`). Off until a consumer sets `World.Fx.Enabled`, capped at 512, oldest first.
  The Unity client does not ask for the typed impact layout (client base patch 0100), so a message ends at its text.
- Ids to elements: `Core/FrontFxIds.cs` is generated by `unity/tools/gen_front_fx_ids.py` (`--check` in the `core` job) from the server's
  `server/data/lib/*.lua` (ChaosFx, ChaosVfx, ChaosVfxMissile, the pair 50 and 51 tables) and `server/data/spells/effects_catalog.csv`, plus the
  stock ids of the base server. One letter per id by the keywords of its name and comment (fire, ice, energy, arcane, death, holy, physical,
  blood, shadow, poison, earth, water, heal, neutral, and X for pictures that are not combat: loot rays, teleports, puffs). Rerun it when a
  server fx id file changes. An id the table does not know is neutral. `FrontFx.ElementOfTextColor` maps the damage text colours the same way.
- `Core/FrontFx.cs` (tested): the palette of each element (hot core, body, rim), the missile art of each element (the 8 sheets of the projectile
  pack: fireball, frost, arcane, skull_necrotic, skull_spirit, blood, shadow, holy; energy, poison, earth and water use one tinted), number text
  (12.3K, 1.2M), the melee rule and the timing. Melee: a physical (red) hit with no missile at its tile draws a slash from the creature next to the
  target that swings: the one the sentence names ("due to an attack by a rat"), our own hit when we stand next to the target, else the hostile
  neighbour that faces it. A bite of fire or a spell has its own effect and no slash.
- `Core/FrontFxArt.cs` (tested): impacts are drawn in code, a port of `impact_strip` of `front_art_packs.py` (flash, ring, sparks, 12 frames of 64
  texels), a heal is a thin ring and rising sparkles; a comet stands in for a missile when the sheets `fx_*` are not there (CI after the packs are
  opened); the number picture is the pixel font (`PixelText`) with an outline. No art file is needed.
- `Core/FrontFxDirector.cs` (tested): events to live items on a clock. A missile flies 16 tiles a second (0.12 to 0.7 s) in a small arc; an effect
  or number at its end within 0.35 s of the launch waits for the landing, so the hit shows when the missile arrives. A burst is 0.5 s, a number
  rises 1.2 tiles in 1.1 s (pop to 1.5 times, full for 60 percent, then fades; received numbers 1.25 times, those of others 0.8), a slash 0.3 s,
  a light flash 0.3 s. The two values of a hit are two numbers, numbers on one tile stack. When more than 8 bursts start together (an area spell) the
  rest are smaller and have no light. Pools: 24 missiles, 48 bursts, 32 numbers, 8 slashes.
- `Unity/FrontLiveFx.cs`: a component that `FrontLiveView` adds. It reads `Cam`, `World`, `TileToWorld(x, y, z)`, `GroundY(x, y, z)` and `Ticked`,
  switches `World.Fx` on and draws the director's items in pooled camera-facing quads (shader `FrontArtSpell`, premultiplied; it got a `_Tint`
  property: colour multiplier, alpha = opacity; one material per picture, frame and tint by a `MaterialPropertyBlock`) and at most 6 point lights.
  A tile's size is the distance between two neighbouring tiles' world points, so the sizes follow the view. Only the player's floor is drawn.
- Not done: the target's flinch and red flash (`_Hit`) and the attacker's swing pose belong to the creature quads of `FrontLiveView`; the events and
  the slash are there for them (`FrontFxDirector.Slashes`). Unsure until seen: the heights over the tile (0.5 tiles for effects, 0.9 plus the rise for
  numbers, taken from `GroundY`), the sizes (a burst 1.7 tiles, a missile 1.2), the light range and intensity next to the scene's own lights, the
  missile frame rate (14), and effect ids that scripts send as a bare number: those not in the Lua files are neutral white bursts.

## Party, character select, character plate

- Party (`Core/Party.cs`, `Unity/Windows/PartyFramesWindow.cs`, `Unity/ChaosApp.Party.cs`): the base packets 0xA3 invite, 0xA4 join, 0xA5 revoke, 0xA6 pass leadership, 0xA7 leave, 0xA8 shared experience, and the Chaos party frames on extended opcode 235 (`open`, `close`, `kick`, `lead`, `invite` out, `state` in). The window (Ctrl+G) opens when the character joins a party. Left click on a frame follows the member, right click opens the menu. Right-click on a player on the map opens a menu with attack, follow and the party entries by the shield (`PartyMenu.For`); a monster is still attacked at once. The server's line "X has invited you to join ..." opens an Accept and Decline box; accepting joins by the leader's creature, who must be in view.
- Character select (`Core/CharSelect.cs`, `Unity/ChaosApp.CharSelect.cs`): cards from the login answer with the outfit drawn small, arrows, Home, End, Page keys and Enter, the last character is selected first. Characters are created on the website, not by an opcode: the "Create character" button opens `https://<login host without play.>/createcharacter.php`.
- Character plate (`Core/Plate.cs`, `Unity/ChaosApp.Plate.cs`): outfit portrait, name, level, health and mana bars (right-click for percent, kept per character) and the experience line with the percent to the next level, all from 0xA0. The main client's plate uses no extended opcode.
- `ChaosApp.DrawOutfit(rect, outfit)` draws a standing outfit in a GUI rectangle; `ChaosApp.ShowMenu(at, items)` is a small popup menu any window can use.

## HUD: toasts, buffs, bars, anti-bot, options (O433 phase 3, track H)

- Models in `Core/Hud.cs` (one `HudState` per session, `session.Hud`), tests `Core.Tests/HudTests.cs`, pt-BR texts in `Core/HudStrings.cs` (merged into `LocStrings.PtBr`).
- Toasts (opcode 79, flat `{action, message}`): `ToastCenter`, 21 types with the main client's colours and times, three shown, queue of 12, Accept and Decline on 151 and 152 (plain text), danger line for hunt warnings.
- Under the plate: energy shield (224, text `es:cur:max`), Monk chi (247, text `chi:chi:max:decay`), buff squares (234, `sync` then `full` and `diff`). No icon art: initials on a colour.
- Monster bar (125): `query {cid}` on every new target, `info` gives tier, role, level and modifiers, `mech` is the boss cast bar. Cast bars (231) over the caster, click on your own cancels.
- Anti-bot (211): modal check with the item pictures and a countdown, report dialog (`OpenReport(name)`; "Report Player" is in the player right-click menu).
- Options window (Ctrl+L): language (PlayerPrefs `chaos.lang`, hello on 157), keep attacking while moving (186), right-click equips (188), buff bar, the display scale the server reports (157). The two options and the language go out once after the login (`HudState.Hello`).
- Not done: icon art for buffs and toasts, frame art for the monster bar, the Town Portal bar, in-world tier labels, monster scaling by tier, catacomb Start protection zone check.

## Tests

```
cd unity/Core.Tests && dotnet run -c Release
```

The checks cover:
- crypto vectors shared with `server/tools/loadtest.py`;
- the dat and spr readers on synthetic files;
- the login answer, map descriptions with skip counters, moves, the east strip, turns, items, pings;
- a whole game login against a fake server on localhost. It uses its own RSA key, real XTEA and the guard handshake.
  It runs twice: identity Extended, and identity Chaos with the markers, a feature list, extended outfits, item attributes and an
  extended opcode round trip whose answer comes in parts;
- `ExtTests.cs`: JSON (parse, write, 22 broken texts, depth), the extended opcode wire bytes, chunks (split and join like the server and the
  main client, stray parts, a UTF-8 character cut by a part), the identity bytes, the Chaos parts of the parser (0x43, outfits, item attributes,
  0x4B floors, 0xA4 and 0xA5), the spell model and the pt-BR texts (every `Loc.T` key in `Unity/` has an entry);
- the front-art live view (`FrontLiveTests.cs`): the new block textures, ground and wall classes to blocks, heights, items as sprites or boxes,
  lights, floors below and voids, the world mapping and anchors, the rebuild hash, size and time bounds;
- the front-art creatures (`FrontLooksTests.cs`): the name rules over every monster name of the server, the 21 classes, the outfit composer, the label, the state machine (steps, facing, swings, flinch);
- NPC talk and trade (`NpcTests.cs`): byte-level 0x7A, 0x7B, 0x7C in and the buy, sell, look, close and NPC speech packets out, lists, search, quantity bounds (money, capacity, stock, 100), totals, currency (opcode 113), {keywords}, the talk log and its channel rule, NPC speech in the parser;
- the front-art live effects (`FrontFxTests.cs`): byte-level packets of 0x83, 0x84, 0x85, 0x86 and 0xB4, every effect and missile id of the server's Lua files has an element, palettes and missile arts, number text, the melee rule, timing and the director's rules;
- the 3D character mapping (`CharsTests.cs`): the 21 classes against the vocation files, the monster rules over every monster name of the server
  (it prints the share per model), size, hand bones, idle clips, the label font and the line-up. The fetch script: `python3 -I unity/tools/fetch_3d_assets_test.py`.

On the real pair: `dotnet run -c Release -- probe DAT SPR OUTDIR [outfit ids...]` draws outfits.png and items.png.

Against a server: `dotnet run -c Release -- live PAIR_DIR HOST ACCOUNT PASSWORD [CHARACTER] [RSA_MODULUS_FILE]`.
It logs in, enters, takes four steps and prints the opcodes it read. The guard key is read from `CHAOS_CLIENT_KEY`
(64 hex digits). Without it the dev key is used, which the live server refuses in mode "enforce".

## NPC talk and trade

- `NpcTalkWindow` opens when an NPC speaks to us (talk type 10 or 11 of 0xAA, with or without a position: `NpcTalkState.HasPosition`).
  Quick words hi, trade, bye, yes, no, a chip per `{keyword}` of the last line, a line to type. Hi and any line outside a conversation go on the
  default channel; once the NPC is focused on us words go as talk type 12 (the NPC channel), because the stock NPC library takes keywords of
  a focused player only from there. The NPC channel is a client tab in the main client, so Unity keeps the log itself.
- `NpcTradeWindow` opens on 0x7A (npc name, u16 count, items with id, sub type, name, weight, buy, sell) and 0x7B (u64 money, goods). Buy and Sell tabs,
  search, amount slider bounded by money, capacity (unless ignored), stock and 100, total, OK. Closing it sends 0x7C. Right-click on a row looks (0x79).
  Requests: buy 0x7A (id, sub type, u8 amount, ignore capacity, in backpacks), sell 0x7B (id, sub type, u8 amount, ignore equipped).
  An NPC that trades for another currency says so on opcode 113 first (`NpcTradeState.ReceiveCurrency`).
- Not done: buy in backpacks, the speech bubble over the NPC, walking up to an NPC on a click, NPC modal windows. Not tried on a live server.

## Running it

1. Open `unity/Client` in Unity 2022.3 LTS and press Play.
2. Put `Tibia.dat` and `Tibia.spr` of the current pair in a folder. The login screen asks for that folder.
   It defaults to `things/` beside the executable.
3. Server keys at run time:
   - `CHAOS_RSA_PUBLIC` is the server's RSA modulus in decimal. Without it the build uses the one baked in, or the open key.
   - `CHAOS_CLIENT_KEY` is the guard key.
   - Both are environment variables.

Keys: arrows, WASD, numpad. A held mouse button or finger walks towards the pointer.

## Build in GitHub Actions

`.github/workflows/unity-prototype.yml`:
- The job `core` runs the tests on every pull request that touches `unity/`.
- The job `build` is manual: Actions > Unity prototype > Run workflow. Pick a target: Windows, Linux or Android.
  - It needs three repository secrets: `UNITY_LICENSE` (the text of the `.ulf` file), `UNITY_EMAIL` and `UNITY_PASSWORD`.
    Without them it skips with a warning.
  - The license file: activate Unity Personal once on a PC with Unity Hub. Copy the `.ulf` file into the secret.
    - Windows: `C:\ProgramData\Unity\Unity_lic.ulf`.
  - `CHAOS_RSA_PUBLIC` (secret) is baked in. It is public data. Without it the build can not log in to the live server.
  - The guard key is **not** baked in by default. This repository is public.
    - The input `embed_client_key` puts `CHAOS_CLIENT_KEY` into the build. Use it only for a build you keep to yourself.
    - Otherwise set `CHAOS_CLIENT_KEY` on the PC that runs it, or test against a server with the guard in mode "log".

The artifact `chaos-unity-<target>` is kept 7 days.

## Protocol notes

- The game login says who we are in two places (full audit in "Both clients"): the OS word and the marker bytes after the random byte.
  Identity Extended (default): OS 21 and `u16 0`. The server sends no feature list, plain outfits (no wings, aura or shader), one 0x64 map, no item attributes, never compresses.
  An adler32 of 0, which would mean a compressed packet, is refused.
  Identity Chaos: OS 21 and the markers of the main client (`ClientIdentity.WriteMarkers`). The server then sends 0x43 (feature list), outfits with
  `u16 wings, u16 aura, string shader`, the floors of a change of level as 0x4B messages before 0xBE and 0xBF, item attributes (feature 126),
  16-bit spell ids in 0xA4 (feature 152). `GameParser` reads all of that when `Identity.Markers` is set. Item attributes follow the feature, not the identity.
- Every extended opcode reaches `GameSession.Ext` (`ExtOpcodes`). The guard challenge on 189 is answered inside the session. Modules register with
  `Ext.On(opcode, handler)` for JSON `{action, data}` (chunks joined) or `Ext.OnText(opcode, handler)` for plain text, and send with `Ext.Send(opcode, action, data)`.
  The text is UTF-8 on the wire; `ByteReader.Str` reads it as latin-1, so `ExtOpcodes.FromWire` and `ToWire` convert. A request over 16384 bytes is refused (the server drops it).
- The step time follows `server/tools/cast_relay.py` `step_ms` (src-patch 0018).
- An opcode the parser does not know stops that packet. The next packets go on. `live` lists what it read.

## Both clients

Players can use the main client (`client/`) or Unity on the same server. What the server tests, read from `server/src-patches` on 2026-11-07:

| Where | Test | Effect |
|---|---|---|
| both logins (0021) | u32 version word is the tag 0x4343 in the high half and the build in the low half, build allowed | else the official-client message (mode enforce) |
| game login (0021, 0015, base `login`) | OS word below 10 | no extended opcodes, the guard refuses it |
| game login | marker `"OTCv8"` + version after the random byte | `sendFeatures` (0x43), wings / aura / shader in outfits, floors as 0x4B |
| game login (0003) | then `"OTCv8TierByte"` and `"A"` | chaosClient: feature 126, item attributes after every item, packet compression when `packetCompression` is on (0069, 0073) |
| game login (0051, 0079) | then u32, `"C"` and a capability byte | bit 7 typed impact numbers (155), bit 6 16-bit spell ids (152, needs `chaosWideSpellIds`) |
| guard (0021) | challenge 189, hello 190 | `ClientGuard.cs`, unchanged. The real key comes from `CHAOS_CLIENT_KEY` at build time, never embedded by default. |
| extended opcodes (0075) | string over 16384 bytes | dropped on the server |
| Lua | `Player:sendExtendedOpcode` and the opcode dispatch | no check of the OS beyond the engine's, so Unity gets every module's messages |

What Unity announces: OS 21, version word `0x4343 << 16 | build`, markers `u16 0` (Extended, default) or the full marker block (Chaos).
OS 21 was always an extended opcode client, so the earlier note that Unity gets no extended opcodes was wrong: it got them and ignored all but the guard.
No server change was needed.

Choosing the identity: the setting `chaos.identity` (PlayerPrefs) or the environment variable `CHAOS_UNITY_IDENTITY` takes `extended` or `chaos`.
Chaos is parsed and tested on a fake server only. Before it becomes the default:
1. log in with `CHAOS_UNITY_IDENTITY=chaos` and read the log line `Server features: ...`. The full list is in the base engine, not in this repo.
   A feature that changes a wire width the parser does not know (an effect id of 16 bits, for example) must be handled by the effect parser of track B through `GameParser.Features`.
2. walk through a staircase and a hole (0x4B floors), open a bag with a rarity item, see a creature with wings or a shader.
3. keep `packetCompression` off until Unity has an inflater (it throws on a compressed packet).
4. leave capability bit 7 off until the 0xB4 parser reads the three extra fields (percent, type, creature id). `ClientIdentity.Capabilities` holds the bits.

UI text: the English text is the key, `Loc.T("text", args)` looks it up in `LocStrings.PtBr` (`Core/Loc.cs`). Arguments are `{0}`. The language is `chaos.lang` or the system language.
A test fails when a `Loc.T` key in `Unity/` has no pt-BR entry. Server texts come in the player's language from the server (opcode 157 `hello` with `lang`).
Window titles of the older windows are not translated yet.

Parity: `docs/UNITY_PARITY.md` has the module table (169 rows), the missing base opcodes and the migration plan.

## HD-2D post-processing (O432)

`Assets/Chaos/Unity/Hd2dPost.cs`: `Hd2dPost.Attach(camera, lowQuality)` turns the look on, `Detach(camera)` restores the camera,
fog, ambient light and shadow quality. `Hd2dPost.SpriteMaterial(atlas)` is the lit cutout material for billboards (point filter, mip 0, casts shadows).
- Effects, in shader order: tilt-shift depth of field (middle 48% of the height sharp, `focusHalf` 0.24, `focusFeather` 0.26; a light
  half-size blur and a heavy quarter-size blur blend by the distance from the band, so the top and bottom read as a miniature), bloom (`bloomThreshold` 0.8, `bloomIntensity` 0.95),
  light shafts, ACES tonemap with `exposure`, grade (lifted blacks, split toning, midtone saturation, contrast), vignette tinted toward
  the shadow colour, light film grain (`grain` 0.025, steps 24 times a second). Exponential fog is set by `Attach`.
- Tonemap: the camera is HDR on desktop, so flames and bloom are added before the curve and roll off instead of clipping. `Core/Hd2dGrade.cs`
  holds the same curve for the unit tests (`Hd2dGrade.Aces`); keep it in step with `Aces` in the shader.
- Grade fields on `Hd2dEffect` (defaults): `exposure` 1.0, `shadowTint` (0.78, 0.86, 1.16), `highlightTint` (1.14, 1.0, 0.80),
  `splitStrength` 0.75, `lift` (0.020, 0.018, 0.045), `tint` (1.02, 0.99, 0.95), `saturation` 1.04, `midSaturation` 0.22, `contrast` 1.05,
  `vignette` 0.38, `grain` 0.025.
- Light shafts: a radial blur of the bright pass toward up to 2 screen points, 20 samples each at quarter size, warm and subtle.
  Fields: `shaftIntensity` 0.55, `shaftDecay` 0.93, `shaftDensity` 0.9. There are none until the view says where the lights are. Once per
  frame, after the camera has moved: `Hd2dEffect.SetLightsWorld(cam, positions, colours)` (world positions, light colours; it keeps the 2 best
  by brightness over distance, drops lights behind the camera and fades those leaving the frame). `fx.SetShaftSources(list of ShaftSource)`
  takes screen uv points directly; null or an empty list turns the shafts off.
- `lowQuality` (phones): keeps bloom, tonemap (`exposure` 1.3 because the LDR image tops out at 1), grade and fog; drops depth of field,
  shafts, grain, HDR and soft shadows.
- Pipeline: the built-in one with our own image effect (`Hd2dEffect.OnRenderImage`), post shader in `Assets/Chaos/Shaders/`; the sprite shader `Chaos/Hd2dSprite` is the view's `Resources/Hd2dSprite.shader` (one shader of that name).
  URP was not taken: its assemblies are not on NuGet, so `Client.Check` could not compile it and nothing in CI would check the URP asset
  that an editor script makes. `ChaosBuild` adds the shaders to Always Included Shaders.
- Life (`Hd2dParticles.cs`, shader `Resources/Hd2dGlow.shader`, additive, vertex colour times a radial texture made in code): 60 dust motes
  around the focus, 12 embers rising from each flame light (max 8 lights), a soft halo on every light. Own CPU quads in one dynamic mesh,
  fixed seed, no frame needed: `Prewarm(s)` then `BuildMesh()` (the screenshot mode does both). `lowQuality` halves the counts.
  `Hd2dView.Particles` is fed the same light list as `SetLights`.
- Flicker: `Hd2d.Flicker(t, seed)` (Core, layered sines, 0.88..1.12) scales warm lights (`Hd2d.IsFlame`) and the halo, plus a small position jitter.
- Not checked without a Unity license: the shader text (`Client.Check` compiles the C# only). Look at it once in the editor.

## HD-2D preview (O432)

`unity/tools/hd2d_preview.py` draws the offline picture of the HD-2D look. It needs numpy and Pillow, not Unity.
- Run: `python3 -I unity/tools/hd2d_preview.py DAT SPR OUT_DIR [--scale N]`. It reads the real pair in place and writes
  `classic.png`, `hd2d.png` and `side_by_side.png`. The pictures are not committed.
- The scene is one temple room of 15 x 11 tiles (client ids 44511-44549) with three outfits.
- The classification, light and footprint rules are small functions at the top of the script (`classify`,
  `light_of`, `colour_from_index`, `billboard_rect`, `floor_rect`). The C# core repeats them. Keep both in step.
  - Floor quad: dat ground, ground border, flat on-bottom items, items with no blocking attribute.
  - Upright billboard: walls, objects and creatures, bottom-right cell on the tile.
  - Light: the dat light attribute, radius in tiles, colour from the 6x6x6 cube.
- Test: `python3 -I unity/tools/hd2d_preview_test.py` (synthetic sprites, runs in CI).
- Side walls are left out: the art is oblique, a camera-facing card floats.

## Chat, death and fight modes (O433 phase 2, track F)

- Model: `Core/Chat.cs` (`ChatModel`, `TalkType`, `ChatPackets`, `BubbleSet`, `FightModes`), parser side `Core/GameChat.cs`, tests `Core.Tests/ChatTests.cs`.
- Chat window (`ChaosApp.Chat.cs`): tabs Default, Server Log, channels and private. Enter focuses the line. With the line focused: Tab and Shift+Tab switch tabs,
  Ctrl+O opens the channel list, Ctrl+E closes the tab (the windows keep those keys otherwise). Right-click on a tab closes it. The "+" button opens the channel list
  (`ChannelsWindow`: click joins, "Message to" opens a private tab). Private message: `*name* text`. `#y text` yells, `#w text` whispers, `/ignore name` and `/unignore name`.
- Floating speech (`DrawBubbles`): say, whisper, yell, spells and monster speech float over the speaker, in the classic and the front-art live view.
  Lifetime 60 ms per character, 3 to 12 s, at most 3 lines stack per creature.
- Death (0x28): a modal window with the penalty. OK logs out and goes to the character list.
- Fight modes (`FightWindow`): offensive / balanced / defensive, stand / chase, secure mode. Saved in PlayerPrefs (`chaos.fight`), sent after the login and at each change (0xA0).

## Items and economy (O433 phase 3, track J)

- Rarity and tooltips: `Core/ItemInfo.cs` (`ItemRarity`, `TipLines`, `ItemTips`), `ItemSlots.Frame` and `ChaosApp.Items.cs`. Slots of the equipment and container windows,
  the text window and the stash list get a frame in the rarity colour (unique colour first, a gold corner for a locked item). Rarity needs the item attributes, so identity Chaos.
  Hovering an item for 60 ms asks opcode 242 (`get {items: [{pos, iid, cid, n}]}`, the slot on the page the window shows for a container), the tooltip is cached by per-item id and version
  (30 s for a plain item) and drawn at the pointer. An answer for another item (the slots shifted) is dropped and asked again at most twice.
- Outfit window (Ctrl+U, `OutfitWindow`, `Core/Dialogs.cs` `OutfitWindowState`): 0xD2 asks, 0xC8 lists outfits with addons, mounts and, on identity Chaos, wings, auras and shaders; colours by
  the 19 x 7 palette; Ok sends 0xD3 (wings, aura and shader only with the markers). Wire layouts follow TFS 1.4.2 `sendOutfitWindow` and `parseSetOutfit`. The base server tree is not in this repo, so
  the extras are read from the OTCv8 layout: ids of wings and auras are 16 bits, a shader's id a byte, with the other width as the fallback; the set packet ends with wings, aura, shader name.
  Check both on a live run (log in with `CHAOS_UNITY_IDENTITY=chaos`, open the window).
- Modal windows (0xFA, 0xF9) and text windows (0x96 books and signs, 0x89 write, 0x97 door lists, 0x8D answer) are server-driven overlays without a toolbar button (`ChaosApp.Items.cs`).
  A text window is writable when its max length is above its text length (the server sends the text length as the length of a read-only one). Escape answers a modal with its escape button.
- Bank (Ctrl+J, `Core/Bank.cs`, `BankWindow`, opcode 60), stash (Ctrl+H, `Core/Stash.cs`, `StashWindow`, opcode 110: tabs, items in batches, take out, drop a bag item on the window,
  stow everything, collect inbox) and store (Ctrl+T, `Core/Store.cs`, `StoreWindow`, opcode 218: tree, pages, search, history, buy). The store takes Chaos Coins the account has; nothing
  about payment is in the client (`pay_*` messages are ignored, the buy URL is never opened).
- Texts of these windows are in `Core/LocItems.cs`, merged into `LocStrings.PtBr` (a key that another file also has is not an error).
- Tests: `Core.Tests/ItemTests.cs` (rarity, tooltip lines, request and cache rules, the four packet layouts with the plain and the Chaos wire, bank, stash, store).
- Not done: rarity frame and glow on items on the map, tooltip compare (Ctrl) and Alt help, tooltips on stash, shop and trade rows, gifts and try-on in the store, the stash block list and
  Find my item, the rarity names of old items by description tag. The toolbar holds one button per window and is already wider than 960 px: the new windows are reached by their keys.
