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
- Character plate (`Core/Plate.cs`, `Unity/ChaosApp.Plate.cs`): outfit portrait, name, level, health and mana bars (right-click for percent and eased bars, kept per character; eased bars and the movable plate: "Core loop user experience") and the experience line with the percent to the next level, all from 0xA0. The main client's plate uses no extended opcode.
- `ChaosApp.DrawOutfit(rect, outfit)` draws a standing outfit in a GUI rectangle; `ChaosApp.ShowMenu(at, items)` is a small popup menu any window can use.

## HUD: toasts, buffs, bars, anti-bot, options (O433 phase 3, track H)

- Models in `Core/Hud.cs` (one `HudState` per session, `session.Hud`), tests `Core.Tests/HudTests.cs`, pt-BR texts in `Core/HudStrings.cs` (merged into `LocStrings.PtBr`).
- Toasts (opcode 79, flat `{action, message}`): `ToastCenter`, 21 types with the main client's colours and times, three shown, queue of 12, Accept and Decline on 151 and 152 (plain text), danger line for hunt warnings.
- Under the plate: energy shield (224, text `es:cur:max`), Monk chi (247, text `chi:chi:max:decay`), buff squares (234, `sync` then `full` and `diff`). No icon art: initials on a colour.
- Monster bar (125): `query {cid}` on every new target, `info` gives tier, role, level and modifiers, `mech` is the boss cast bar. Cast bars (231) over the caster, click on your own cancels.
- Anti-bot (211): modal check with the item pictures and a countdown, report dialog (`OpenReport(name)`; "Report Player" is in the player right-click menu).
- Options window (Ctrl+L): language (PlayerPrefs `chaos.lang`, hello on 157), keep attacking while moving (186), right-click equips (188), buff bar, the display scale the server reports (157). The two options and the language go out once after the login (`HudState.Hello`).
- Not done: icon art for buffs and toasts, frame art for the monster bar, the Town Portal bar, in-world tier labels, monster scaling by tier, catacomb Start protection zone check.

## Demo tour video

The owner's video of the client running the game, not a test scene. `ChaosUnity -chaosDemoTour OUT_DIR` starts a fake game server in the
player's own process (`Core/DemoTour.cs`, `FakeGameServer`), logs in to it through the normal `ChaosApp` flow (login port, character list,
game port with the guard challenge: the key, the RSA modulus and the Extended wire reach the app through the same environment variables it
always reads), switches on the F8 front-art live view and plays about 23 seconds. No real server data and no accounts: the art is the
real pair's outdoor ids when found (`-chaosPair`, `CHAOS_PAIR_DIR`, `things/`), else its temple floors, else the synthetic art.
The fake server has a login port and a game port of its own, so a slow login (software GL) is never taken for a game client.
The player keeps running without focus (`Application.runInBackground`, set in `ChaosApp.Awake`): the tour's resize drops the focus under
xvfb, and a player in another window must keep its session (reads, pings) alive.
- Server timeline (`FakeGameServer`, times in `TourPlan`): a skeleton and a ghoul walk in, an archer shoots, the hero fights (0x83 effects,
  0x85 missiles, 0xB4 numbers, 0x8C and 0xA0 health), casts a fire spell and a heal (0xAA spell words, 0xA4 and 0xA5 cooldowns), loot lines,
  an NPC greets and opens its shop (0x7A, 0x7B), toasts (79: journey, achievement, party invite, season pass), a buff added (234), a party
  forms (235). The map is a function of the tile (`TourMap`), so the strips of the hero's walk match the first view.
- Player side (`Unity/ChaosApp.Tour.cs`, `TourDirector`): walks five steps, attacks, casts, talks to the NPC and trades, then opens and closes
  the spellbook, party frames, passive tree and skills windows in turn and two top-menu drop-downs, with the HUD on.
- Deterministic: `Time.captureFramerate = 60`, the game clock (`GameSession.TestClock`) is the frame count and the script runs on that clock,
  never the wall clock. One PNG per frame, `OUT_DIR/demo_tour_0000.png ...`, 1280x720, 1381 frames. Exit code 0 when all were written.
- With `-chaosHd2dShot` too, the screenshots run first and `Hd2dShot` hands the process over to the tour. Log lines: `chaos demo tour:`.
- CI (`unity-prototype.yml`, Linux target): one player run with both flags under xvfb, a second run with the tour alone if no frames came,
  then `ffmpeg -framerate 60 -i demo_tour_%04d.png -vf scale=1280:720,format=yuv420p -c:v libx264 -crf 20` writes `demo_tour.mp4` into the
  `hd2d-shots` artifact. The PNG frames are deleted after encoding; `demo_tour_still_1..4.png` stay.
- Test: `Core.Tests/TourTests.cs` (the server against a real `GameSession`, no Unity).

## Walking video

Phase 19, track W. The owner asked for a video of the Unity client walking ("grava um vídeo andando no Unity"). `ChaosUnity -chaosWalkTour OUT_DIR` records about 30 seconds at 1280x720 and 60 fps of the smooth 8-direction walk (see "Smooth 8-direction walking") in each view. A second recorded run next to the demo tour, in its own player process. Plan and numbers: `Core/WalkTour.cs`. Player side: `Unity/ChaosApp.WalkTour.cs`.
- Server (`FakeGameServer.UseWalkTour`, `Core/DemoTour.cs`): the demo tour's fake server in a walking mode. Each step the hero asks for (the 8 step opcodes 0x65 to 0x68 and 0x6A to 0x6D, an auto-walk path 0x64, turns 0x6F to 0x72) is answered `WalkTourPlan.RoundTripMs` (120 ms, 60 each way) after it was sent. It is not run before the step ahead of it has used its time (`WalkTiming.StepMs`, the client's own formula, so the two agree to the millisecond), as the real server queues a walking player's steps. So a step sent in the pre-walk window is answered one lead plus one round trip after the send, which is one round trip after it starts to glide. A diagonal answer carries both map strips, in the engine's order. A step onto a tile that is not bare ground, or one a creature stands on, is refused with 0xB5.
- Creatures: a skeleton and a ghoul walk their own diagonals out and back (6 tiles each, `WalkTourPlan.Creatures`), one tile every monster step time, so each glide starts as the one before ends. They come into view and leave it as the engine says (0x6A add, 0x6C remove, 0x6D move inside the view).
- Plan (`WalkTourPlan.Segments`): classic (a round and a turn on the spot), HD-2D (the round the other way), live front-art (the round), then the 3D world when `world3dReady` (two click paths of 3 diagonal tiles out and back, a diagonal run of 4 tiles out and back). A round is 22 steps in all 8 directions: diagonals of 4 tiles, short straights, back to the start tile. Each segment starts standing for 0.3 s (0.6 s the first), the view changes there. About 33 s with the 3D world, about 25 s without. The times in the plan are the nominal ones (speed 220 on a ground of 150: 300 ms straight, 420 ms diagonal); the art's real ground speed moves them. Without the 3D models in the build the 3D segment is left out and the log says so.
- The route: keys are held for a number of steps sent, not for a time, so the route is the same tile for tile whatever the step times are. Tests check every route tile is bare ground even with pond, wall and torch, and that the creatures stay two tiles away from it.
- Input: the keys go the player's way. The conductor (`WalkTourConductor`) gives a `WalkInput` mask each frame to `ChaosApp.HandleWalk` (`WalkMaskSource`), then `WalkInputState` folds it into a direction and `GameSession.Walk` sends the step with prediction and pre-walk. A diagonal from rest is two keys: the first, 30 ms later the second, inside `WalkInputState.GraceMs`, so no straight step goes first. Between legs the keys change without a release. The turn on the spot (`GameSession.Turn`) and the click paths (the path finder and `StartAutoWalk`, as a click on a tile) are not key input. There is no hotkey for a turn in the Unity client.
- Captions: a bar at the top of each segment with the view and "8 direções, passo contínuo" (`WalkTourPlan.Caption`, `Loc.T`, keys in `Core/LocPhase19W.cs`). The director sets the language to pt-BR for the run, so the HUD is pt-BR too.
- Measured, per segment (`WalkSegmentReport`, log lines `chaos walk tour: segment N View: S s, steps sent A, steps confirmed B, longest standstill X ms, start delay Y ms`): steps sent (key steps and the steps of click paths), steps confirmed (moves of the player the server answered, `GameParser.PlayerMoves`), the longest time the drawn hero stood still while a key was held (`WalkStandstill`, one value per frame from `WalkMath.Drawn`, so the camera's own number), and the start delay (key down to the first motion, not part of the standstill). The run fails with `chaos walk tour: failed: ...` and exit code 1 (after the last frame, so the video can be looked at) when a segment's standstill is over `WalkTourPlan.StandstillLimitMs` (50 ms), when steps sent and confirmed differ, when the server refused a step, when a key was held for 600 ms and the hero never moved, or when a leg or a click path was not finished.
- Deterministic like the demo tour: `Time.captureFramerate = 60`, the game clock is the frame count, one PNG per frame `OUT_DIR/walk_tour_0000.png ...`. The plan sets the length of the run (at most 75 s). One second of the last view follows the plan.
- CI (`unity-prototype.yml`, "HD-2D screenshots", Linux target): after the screenshot run, the tour and the window smoke run, a third player run `-chaosWalkTour "$out"` (log `player_walk.log`, timeout 2100 s). Then the log lines are printed into the job log, `ffmpeg -framerate 60 -i walk_tour_%04d.png -vf scale=1280:720,format=yuv420p -c:v libx264 -crf 20` writes `walk_tour.mp4` into the `hd2d-shots` artifact, `walk_tour_still_1..4.png` stay and the frames are deleted. A player exit code over 0 prints an Actions error and fails the step at the end (the artifact is uploaded all the same). The demo tour and the smoke run are not touched. Next to `-chaosHd2dShot`, `-chaosDemoTour` or `-chaosWindowSmoke` the flag is ignored.
- Tests (`Core.Tests/WalkTourTests.cs`): the plan (views in order, timing per segment and in all, all 8 directions held through one or two keys, 8 diagonal runs of 4 or more tiles, one turn, two click paths, closed rounds, the route on bare ground in the strictest art, the creatures clear of it, pt-BR captions), the standstill meter on synthetic frames, and the whole plan against a real `GameSession` on the fake server's sockets on a simulated 60 fps clock, with the app's `Walkable` check and the real meadow's ground speed 150 (300 ms straight, 420 ms diagonal): a diagonal answered after the round trip, every segment with 0 ms standstill, sent equal to confirmed, 80 server steps, one turn, two auto-walks, none refused, the hero on the start tile after each segment, the creatures gliding in 90% or more of the frames they are on the 15 x 11 screen.
- The meadow must be walkable to the client. The real pair's plainest grass is a ground the dat flags not walkable: on it `WalkMap.Walkable` refused every grass tile, so each step there waited for the step ahead to be confirmed and was not drawn before its answer (120 to 150 ms standing per step), and the 3D segment's path finder found no click path. `Hd2dDemo.PickOutdoor` now takes only grass and dirt grounds without NotWalkable or BlockPath (`World3dTests.cs` checks it).
- Not tested: the Unity player part (the view switches, the caption, the frame capture, `StartAutoWalk` in the app), the 3D world segment in the player (needs the models in the build), and the video itself.

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
- the walking video (`WalkTourTests.cs`): the plan, the standstill meter and the whole plan against a real session on the fake server (see "Walking video");
- the demo tour server (`TourTests.cs`): a real session logs in through the login and the game port and plays the whole script on a simulated 60 fps clock (steps, fights, spells, shop, party, toasts, buffs);
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

## Progression: passive tree, skills, goals, hunt, rift, info, top menu (phase 3, track K)

Same server messages as the main client. Pure code in `Core/PassiveTree.cs`, `Core/BuildCode.cs`, `Core/Progression.cs`, `Core/TopMenu.cs` (one `Progression` hub on `GameSession.Progress`), tests in `Core.Tests/ProgressionTests.cs`.
- Passive tree, Ctrl+N (`PassiveTreeWindow`, opcode 65). The server sends only the allocation, so the layout is a file: `Resources/PassiveTree.json`, written by `luajit unity/tools/gen_tree_data.lua` from `client/overlay/modules/game_passivetree/treedata` (positions, links, names, stat lines per class; CI runs `--check`). Run it again when the main client's tree changes.
  Drag pans, the wheel zooms round the pointer, Fit shows all. Hover shows the tooltip (stats, description, mastery effects, "Requires", the cost of the path). A click plans the path to the node (green), a click on a planned node takes it and what hangs on it out, `<` and `>` undo and redo, Apply sends one `planApply`. A mastery asks for its effect. Right-click on a saved node refunds it, Reset resets the tree, both at the server's price. Search frames matches in orange (Enter and Shift+Enter step). Build Code exports the tree code, the full CC1 code (class, level, tree, gear), previews a pasted code on the tree and applies it; the server decides.
  Totals button: raw against effective stats after the soft cap, critical chance and damage, attack speed (`statTotals`, asked again when the allocation changes).
  Not done: node icons, curved links, Paragon, trials, auto build, other characters' trees, loadouts.
- Skills (Ctrl+K): Melee (the best of sword, club and axe), Ranged, Magic / Wand, Shielding, Fishing, Fist for the Monk line, then the combat stat rows (opcode 119: damage, attack, defense, armor, mitigation).
- Next Goals (Ctrl+Y, opcode 178) and the goal tracker (opens by itself when the server sends rows; the welcome path has a Skip button that asks twice). Hunt Tracker (Ctrl+I, opcode 241): session clock, pause, reset, restock, four lists. Rift HUD (opcode 228): opens on the server's start. Info and Services (opcode 237): pages from the Adventure, Character, Economy and System menus.
- The top menu replaces the flat toolbar: Character, Hunt, Adventure, Economy, Social, System and Windows. Entries are sorted by text and follow the level unlocks of opcode 115 (hidden, grey with the level, a New badge, an on-screen text and a Go box). Windows lists every window no entry names. To put a new window in a category, add a line to `TopMenu.Categories` with `win:ClassName`; without one it shows under Windows.

## Phase 6, track W: P1 systems (picking up, loot filter, tooltips, stash, store)

Same server messages as the main client; pure code in Core, tests in `Core.Tests/Phase6WTests.cs`, texts in `Core/LocPhase6W.cs`.
- Ground labels: a left click on an item label picks it up (`GroundPick`, `GroundLabelsModel.Activate`). The top item of a pile moves into the backpack (slot 3) at once, a lower one is raised by the server first (`raise`, answer `raised`), errors are told in the chat.
- Loot filter (opcode 238): peek on open bags and corpses (glow, rarity frame, dim veil, `LootPeek`), the Rules tab (counters per rule, sound choice, volume, mute, Hunt Tracker flag; the sounds are not played), Autoloot steppers and a preview in the Filter tab.
- Item tooltip: hold Ctrl to compare with the worn items of the same kind (`ItemCompare`), hold Alt for the plain line per term (`ItemHelp`, generated from `itemhelp.lua`), sources lines above the weight.
- Stash: Find (query, pages, a stash result opens its tab) and Never stash (drop an item of a bag on the panel, Remove).
- Store: Gift, the rotation countdown, TRY ON (the server plays the effect, no look preview panel).
- Options > General: damage number spread on or off and its strength. Skills: bar tooltips and boosted levels in green.
- Not done: map outlines for items, beams, rule sounds, tooltip card layout, in-world tier labels and oversized monsters of the monster bar, Helper follow, auto sell, exercise weapons.

## Phase 7, track Y: P1 systems (passive tree, monster bar, rarity, tooltips, loot filter, labels, toasts, damage numbers, store)

Pure code in `Core/Phase7Y.cs` and `Core/Phase7YTree.cs`, tests in `Core.Tests/Phase7YTests.cs`, texts in `Core/LocPhase7Y.cs`, glue in `Unity/ChaosApp.Phase7Y.cs`.
- Passive tree: the Paragon panel (button Paragon, `ParagonPanel`: paragonState, + and - with Shift for five, Apply sends the absolute allocation, Reset asks first and shows the server's price)
  and another character's tree read-only (Inspect Player > View tree sends the inspect packet to `PassiveTree.ShowOther`; banner, Back to my tree; planning, Apply, Reset, refunds and build import are off while it shows;
  a sync of the own tree ends the view). The main client enables one loadout slot only, so loadouts have nothing to port.
- Monster bar world side: a tiered monster's name in its tier colour with the tier word and the modifier lines over it (`MonsterWorld`, two modifiers to a line, in every view that draws names).
  The draw size in the classic map view (`MapView.CreatureScale`): boss and omen guardian 1.5, any other body over 68 px tall or 96 px wide shrunk to fit, never below 0.5,
  the body measured from the sprites' opaque pixels (`BodyBox`, a stand-in for the main client's outfit anchors) and the tier asked for at once.
- Items on the map: a rarity outline (Uncommon and up, unique colour first; Legendary and Divine pulse), the sprite drawn again tinted one pixel to each side behind itself. Options > Visual switches it.
- Tooltips: with Ctrl the worn items of the same kind are plates beside the main one (`TooltipPlates`). Ground label tooltips: hover asks the server (opcode 230 `tip`), cache per tile, stack, id and count.
- Loot filter: the rule sound of a kill plays from `game_lootfilter/sounds/*.ogg` (`LootRuleSounds`), a play button per rule, the rare-drop cue stays silent for that kill;
  the rule counters head the Hunt Tracker's Chaos Drops tab while the option is on.
- Ground labels: tooltip, right click opens the item menu, the loot label accent cosmetic sits behind highlighted labels.
- Toasts: the creature of task, bounty, bestiary and battle pass toasts over the icon, the module's plate, Accept and Decline from the four-state strips.
- Damage numbers: critical and condition numbers in the bitmap fonts `chaos-display-16px` and `chaos-outline-11px` (`BitmapFont` reads the .otfont text and its sheet; the stock numbers when the files are missing).
- Store: an offer's footprint print, plate frame or colour sample is its icon (`StoreLookIcon`).
- Files: CI copies `game_lootfilter`, `game_nameplate`, the toast plate and the two fonts into StreamingAssets (unity-prototype.yml). The art is the main client's own, nothing is committed to the Unity project.
- Not done: node icons, curved links, Paragon masteries, trials and auto build of the tree; the draw size and the outline in the live and HD-2D views; the tooltip card layout; the store's look preview try-on panel;
  the catacomb Start protection zone check. Not run in a real player build: the drawing glue is checked by `Client.Check` only.

## Running it

1. Open `unity/Client` in Unity 2022.3 LTS and press Play.
2. The sprite pair (`Tibia.dat` and the sprites) is found in this order (section "Sprite pair"): the flag `-chaosThings DIR`, loose files in the folder the login
   screen names (default `things/` beside the executable: development), the encrypted blobs `things_enc/` of the install, the main client's `chaos.pack` next to it.
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
    - The input `embed_client_key` puts `CHAOS_CLIENT_KEY` into the build, exactly as the main client's `Chaos.exe` carries it. It is the way to a player build
      (owner decision 2026-11-08, "Shipping the Unity client"); the key is in the build and never in the repository.
    - Otherwise the build is a **DEV package**: set `CHAOS_CLIENT_KEY` on the PC that runs it, or test against a server with the guard in mode "log".

The artifact `chaos-unity-<target>` is kept 7 days.

## Shipping the Unity client

Owner 2026-11-07 (pt-BR): "Quero que os jogadores consigam jogar em ambos os clientes. Mais pra frente iremos migrar totalmente pro unity."
Players pick the client in the game launcher (O314): "Main client" or "Unity client (beta)". Same account, same server, same signed update path.
Phase 16 track A. Written and tested here (Python, Rust, PHP, shell); not run on Windows, not published yet.

Route, step by step:
1. Build. Actions > Unity prototype > target `StandaloneWindows64` (needs the Unity secrets above). The job keeps the raw build as the artifact
   `chaos-unity-StandaloneWindows64` and packs it as the artifact `chaos-unity-windows-package` (7 days): `CindersOfChaos-Unity-Windows.zip` and its `.sha256`.
   Linux and Android builds are unchanged and are not packed.
2. The zip holds the player folder at its root (`ChaosUnity.exe`, `UnityPlayer.dll`, `ChaosUnity_Data/...`, `MonoBleedingEdge/...`) and `unity_build.json`:
   every file with path, size and SHA-256, in the shape of the `native` section the launcher already reads, plus the package number (the `client_build` input).
   `client/tools/make_unity_manifest.py pack` writes it, and the boolean `embed_client_key` (the workflow input; never the key): keyed or dev, see below. Not signed: the update key never leaves the VPS. Left out: `*_BurstDebugInformation_DoNotShip`,
   `*_BackUpThisFolder_ButDontShipItWithYourGame`, `.pdb`. Refused: links, scripts (`.bat`, `.cmd`, `.ps1`, shortcuts), odd names, `.exe` outside the root,
   more than 4096 files or 12 folders deep. The launcher applies the same rules.
3. No release is made by the workflow. To publish, the owner downloads the zip and attaches it to a GitHub release by hand, tag `unity-N`
   (asset name `CindersOfChaos-Unity-Windows.zip`).
4. Publish on the VPS: admin app, tab Comandos > card "Site e update do client" > field "Release do client Unity (beta)" > button "Publicar client Unity".
   Shell fallback: `chaos-ctl.sh publish-unity unity-N [--version N]`, which runs `publish_client_update.sh --unity unity-N`.
   It downloads the zip, extracts it safely, hashes the files again (they must match `unity_build.json`), copies them as plain blobs to
   `updates/unity/native/<sha[:2]>/<sha>` and writes `updates/unity/manifest.json` signed with the same Ed25519 key, last.
   The main client's `updates/live` is not touched (it is only read, for the sprite pair of a keyed package). The player files are plain blobs (public client code);
   the sprite pair blobs are the main client's own encrypted blobs, copied as they are (section "Sprite pair"). No `CHAOS_CLIENT_KEY` is needed to publish;
   with one at hand the publisher also decrypts the pair blobs to check them.
   The manifest version counts on its own: the tag number, else the published one plus 1, and it must go up.
5. Players: the launcher shows "Client: Main client | Unity client (beta)". A DEV package (`"dev": true` in its manifest) is refused with a message; testers pass `--allow-dev-unity`. Unity is installed in `unity/` inside the game folder with its own
   `.cinders_launcher` state, through the same update code (resume, hash check, journaled swap with rollback). The choice is saved in
   `.cinders_launcher/settings.json`. `Jogar` starts `unity/ChaosUnity.exe`. Details: `launcher/README.md` "Client choice".

Files: `client/tools/make_unity_manifest.py` (pack, build, verify; tests `make_unity_manifest_test.py`), `server/deploy/publish_client_update.sh --unity`
(tests `publish_client_update_test.py`), `server/deploy/chaos-ctl.sh publish-unity` (tests `chaos_ctl_test.py`), `launcher/src/choice.rs`, `manifest.rs`
(layout `Tree`), `config.rs`, `launcher/tests/unity_update.rs`, `launcher/tests/vector.rs` (a manifest signed by Python), the website downloads page.

Decided by the owner (2026-11-08, pt-BR): "Embutir como no principal". The guard key and the sprite pair: see "Sprite pair" below.

Open before players use it:
- **Not run on Windows or against a live server.** The window smoke run (CI) and the fake server are the only runs. The swap of a loaded player on Windows is untested, as for the main client.
- **Code signing.** Same as the launcher: unsigned programs get antivirus and SmartScreen warnings.

## Sprite pair

Owner 2026-11-08 (pt-BR): "Embutir como no principal". The Unity player build for players carries the client guard key exactly like the main client's `Chaos.exe`
does, and the sprite pair reaches the player the way the main client's does, so nobody copies files by hand. O433 phase 17. Written and tested here (C#, Python, Rust);
not run in a Unity player, on Windows or against the real VPS.

The key. The workflow input `embed_client_key` (and the secret `CHAOS_CLIENT_KEY` being set) puts the key into the build as the Resource `chaos_client_key`;
`ChaosApp.GuardKey()` reads it for the guard answer and, now, for the pair. It is never in the repository, a log, a test or a committed file: the Core tests use a key made up
from a sentence. The key can be read out of a build, as out of the main client's exe (the main client's pack only deters copying, base patch 0102). What the flag decides:
- `embed_client_key = true`: a **keyed** package. The job log says so (a warning), `unity_build.json` holds `"embed_client_key": true` (a boolean, never the key),
  the signed manifest says `"dev": false`, the publisher adds the sprite pair.
- `embed_client_key = false`: a **dev** package. The job log says so, `unity_build.json` holds `false`, the manifest says `"dev": true`, the publisher adds no pair (the build could
  not open it) and the launcher refuses to install it: the message "development build ... not offered to players". Testers run `cinders-launcher --allow-dev-unity`
  (or `CINDERS_ALLOW_DEV_UNITY=1`). A zip made before phase 17 has no field and is published as dev.

Where the pair is found (`Core/ThingsPair.cs`, `PairLocator.Find`; glue `ChaosApp.LoadPair`):
1. `-chaosThings DIR`: loose `Tibia.dat` with `Tibia.spr` or `Tibia.sprshards` (an explicit choice: when wrong the login screen says so, no fall back).
2. Loose files in the folder of the login screen (`things/` beside the player by default; the `unity/things/` of a tester). Shards are read like the engine does:
   a broken shard set falls back to a single `Tibia.spr`.
3. The encrypted blobs of the install: `things_enc/Tibia.dat.chub`, `Tibia.sprshards.chub` and one `Tibia.NNN.spr.chub` per shard, installed by the launcher from the unity channel.
   Shards are decrypted one at a time when a sprite needs them (`SprShardSet`, 6 kept in memory, about 30 MB each); the dat and the index at the start.
4. The main client's pack: `-chaosPack FILE`, else `chaos.pack` in the folder above the player (the launcher installs the main client in `<install>/` and Unity in `<install>/unity/`),
   else beside the player. Only the pair entries `data/things/<n>/Tibia.*` are kept out of the pack; the rest of it is read and thrown away. The pair then lives in memory (about a gigabyte
   with the real pair; the main client holds the whole pack in memory the same way) and the open takes seconds.
A wrong key (a dev package against real blobs, a pack of another build) fails with "wrong key or changed file" (and a hint for a dev build), never with the key or any content.
A shard that does not fit the index or does not decrypt draws nothing and is reported once (`SprFile.ShardError`), as the engine does.

The container, ported from the engine and not guessed (`Core/PackCipher.cs`, `PackReader.cs`, `SprShards.cs`):
- `chaos.pack` (base patch 0102, `src/framework/util/chaospack.h`; writer `client/tools/pack_client.py`): 28-byte header `CHPK`, version 2, flags (bit 0 dev key), 2 reserved, 12-byte nonce,
  u64 LE length of the uncompressed ZIP; then AES-256-GCM of a zlib stream of a store-only ZIP (additional data = the header), then the 16-byte tag.
- Update blob (base patch 0103, `chaosblob.h`; writer `client/tools/update_crypt.py`): the same header with `CHUB`, version 1 and the file's length; AES-256-GCM of the file; tag.
- Keys: HKDF-SHA256 of the 32-byte client key with salt `CindersOfChaos/pack/v1` and info `chaos-pack-aes-256-gcm`, or `CindersOfChaos/update/v1` and `chaos-update-blob-aes-256-gcm`.
  (A rotation `old,new` of the server key: the build uses the last one, as the guard does.)
- AES-GCM is written in the Core (AES in ECB mode makes the counter stream, GHASH is managed) because `AesGcm` is not in Unity's Mono. The tag is checked at the end and nothing is returned before
  it verified. Like the engine, inflate runs on bytes the tag has not yet authenticated, into a size fixed by the header. Unlike the engine, bytes after the zlib stream and the Adler-32 trailer
  are not checked (the tag covers them). Shards: `chaos-spr-shards 1` index, each shard a `.spr` of one id range, id in the shard = id - first + 1 (base patch 0048).
- Tests (`Core.Tests/Phase17Tests.cs`): the NIST GCM vector, RFC 5869, a pack and a blob made by the real Python tools with a made-up key, C# writers that mirror them
  (a pack over one 4 MB chunk, tampered tag, body, header and length, version 1, a member that is not stored, unsafe names), the shard index, the shard set against a single file,
  and `PairLocator` over a fake install folder for every order and every failure.

The channel (`client/tools/make_unity_manifest.py build --pair-from LIVE_DIR`, called by `publish_client_update.sh --unity`): for a keyed package the publisher reads the main client's
published `updates/live` (the live manifest must be signed by the same update key), takes `data/things/<n>/Tibia.dat`, `Tibia.sprshards` and the shards, checks each blob (size, SHA-256, `CHUB` header,
not the development key; with `CHAOS_CLIENT_KEY` also the decrypted hash and the shard index), and copies them byte for byte as native files `things_enc/<name>.chub`. Same encryption, same key,
the same signature of the manifest; nothing is decrypted or re-encrypted. `--no-pair` leaves it out. Publish the main client first; after a main release that changes the pair, publish the Unity
package again with `--version N+1` (the manifest version must go up). The Unity update then downloads only the changed shard blobs.

Not done: shard decryption on a background thread (the first sprite of each shard waits for about 30 MB of AES-GCM on the main thread); the time of GCM in Mono is not measured;
the launcher shows no dedicated screen for a dev package (it is the error text); the admin app has no button for `--no-pair`.

## Protocol notes

- The game login says who we are in two places (full audit in "Both clients"): the OS word and the marker bytes after the random byte.
  Identity Extended (default): OS 21 and `u16 0`. The server sends no feature list, plain outfits (no wings, aura or shader), one 0x64 map, no item attributes, never compresses.
  A zero where the adler32 goes means a deflated packet: `Core/Inflate.cs` inflates it (the server only deflates for Identity Chaos, config `packetCompression`).
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
| guard (0021) | challenge 189, hello 190 | `ClientGuard.cs`, unchanged. The real key comes from `CHAOS_CLIENT_KEY` at build time; embedded only with the workflow input `embed_client_key` (owner 2026-11-08: a player build carries it like the main client), never in the repository. |
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
3. `packetCompression` may be on: Unity inflates (`Core/Inflate.cs`, wire audit below). Not yet seen on a live server.
4. leave capability bit 7 off until the 0xB4 parser reads the three extra fields (percent, type, creature id). `ClientIdentity.Capabilities` holds the bits.

UI text: the English text is the key, `Loc.T("text", args)` looks it up in `LocStrings.PtBr` (`Core/Loc.cs`). Arguments are `{0}`. The language is `chaos.lang` or the system language.
A test fails when a `Loc.T` key in `Unity/` has no pt-BR entry. Server texts come in the player's language from the server (opcode 157 `hello` with `lang`).
Window titles of the older windows are not translated yet.

Parity: `docs/UNITY_PARITY.md` has the module table (169 rows), the missing base opcodes and the migration plan.

## Wire audit

Phase 6, track T. The parser was checked against the patches, not against itself: `Core.Tests/WireAuditTests.cs` holds byte vectors written by hand from
what the patches write (about 100 checks), plus `server/tools/cast_relay.py`, which parses the same server stream and has its own tests.
The base server and the base client are not in this repo, so a layout only they define is marked "base" and stays on the live-run list.

Verified, by patch:
- Login markers (src 0003, 0051, 0079): `u16 5 "OTCv8"`, `u16` version, `"OTCv8TierByte"`, `"A"`, `u32`, `"C"`, capability byte 0xC0 (bit 7 typed numbers, bit 6 16-bit spell ids). The test
  also reads the bytes the way `onRecvFirstMessage` does. Extended is `u16 0`.
- 0x43 feature list (src 0003): `u16` count, `u8` feature and `u8` enabled. 126, 152 and 155 are the Chaos features.
- Items (src 0003, 0050, 0081): id, mark, count byte for stackable, fluid, splash and quivers, phase byte for more than one phase, then `u16` count and `u16` key + `u64` value, in the inventory (0x78),
  containers (0x6E, 0x70, 0x71, 0x72 with and without the sliding item), tiles (0x6A) and the browse field's bag (count 0). A 500 slot bag is a page of 250 (capacity byte 250, size 500, first index 250). Key 3 carries 1 or 2.
- Creatures (src 0077, 0083): 0x61, 0x62, 0x63, the facing bytes 4 to 7 (north-east, south-east, south-west, north-west), the refresh by id (`0x6B 0xFFFF id` and the full form with remove = own id),
  outfits with mount, wings, aura and shader (also 0x8E and the item look), the square 0x93 (id, 1, colour).
- Text and numbers (src 0037, 0051, 0052; base 0100): 0xB4 modes 23 to 29 with and without feature 155, 0xA4 with a byte or a `u16` id (0079, ids above 255), 0xA5 group id stays a byte,
  0xA0 and 0xA1 (display scaled `u32` health and mana, the seven crafting skills of base 0012, the 24 byte tail).
- Basic data 0x9F (base 0016, `ascension.lua`): the class byte (1 to 29) becomes the vocation id with the table of that patch and is read again after an ascension.
- UTF-8 text (base 0028): a string that is valid UTF-8 with a non-ASCII character is read as UTF-8, anything else as Latin-1, a byte order mark is dropped (`ByteReader.Str`). Extended opcode payloads keep their bytes (`StrRaw`) and decode their own UTF-8.
- Map (src 0072, aware range): 0x64, 0x65 to 0x68, 0x4B, 0xBE and 0xBF with the skip chain across floors, at 17 x 13 and at 29 x 21.
- Compression (src 0069, 0073; base 0131, 0135), below.
- Verified from `cast_relay.py` only, not in a patch: the 0x17 login tail, 0xA0 field order, the tile and creature layout of the base (mark, speech bubble, helpers, unpassable), the step time.

Mismatches found and fixed (patch, what the main client does, what Unity did):
1. src 0069 / 0073, base 0131: the server deflates packets of an Identity Chaos connection when `packetCompression` is on. Unity threw on the zero checksum word. Now `RawInflater` (below).
2. Aware range, src 0003 `GameChangeMapAwareRange`, `game_chaosview`: 0x42 other than 17 x 13 made Unity throw, and the map messages used the constants 8, 9, 6, 7 and 18 x 14. Now `World.Range` (`AwareRange`) drives every map read.
3. Base 0016 (`GameChaosVocationIds`, always on in the 1098 profile) and `ascension.lua`: the class byte of 0x9F was dropped, so an ascension left the vocation of the character list. Now it sets `World.PlayerVocation`.
4. Base 0028: server texts in UTF-8 ("ação" as `C3 A7 C3 A3`) showed as "Ã§Ã£" in chat and windows. Now `ByteReader.Str` applies the main client's rule.
5. Src 0037 with 0085: health and mana come as `u32` clamped by the display scale; `(int)` turned a value above 2^31 negative. Now `FitInt` keeps the bar in range.
6. The creature square 0x93 was skipped (the parser read a 0x86 that 10.98 does not send). Now it queues a Square event (nothing draws it yet).

Compression: `Core/Inflate.cs` is a small inflate (stored, fixed and dynamic blocks, the decoder of zlib's `puff`). The server's stream is one raw deflate stream per connection with a sync flush after every packet,
so each packet ends on an empty stored block and the only state between packets is the 32 KB history. Not `DeflateStream`: it cannot be fed one packet at a time. Packet layout: `u16` length, `u32` 0, XTEA of
(`u16` length of the deflated bytes, the bytes, padding); bodies under 128 bytes stay plain with a real adler32 and do not touch the stream. At most 65536 bytes per packet (base 0131); a final block, a bad block or
a stream that ends inside a block is a `CompressionException`, and `GameSession` closes the connection (the stream is out of step for good; the main client does the same). Tests: four packets of one stream made by zlib
(level 3, window 2^14, memLevel 7, as the server's Deflater), sixty packets of a `DeflateStream` over 70 KB (history past 32 KB), the cap, error cases, and `Protocol.Decrypt` with plain packets between deflated ones.

Aware range: the server tells it with 0x42 (`u8` width, `u8` height; 17 x 13 by default) to a client that sent the markers, and the client asks with 0x33 (`u8` width, `u8` height, at most 29 x 21, what `game_chaosview` sends at
the game start). `AwareRange`: left = width / 2, right = 1 + width / 2, top and bottom the same for the height, a full map is (width + 1) x (height + 1) tiles from (x - left, y - top); only odd sizes make a window, so an even size
is refused. `GameSession.RequestAwareRange(w, h)` sends 0x33 (Identity Chaos only), `CHAOS_UNITY_AWARE=29x21` asks after the login. The views still draw 15 x 11 tiles: `World.RangeLeft` and the other constants stay the drawn window,
`World.Range` is what is read and kept (`ForgetOutside` follows it). The server's own answer to 0x33 (whether it resends the map) is in the base fork, so a live run should check that.

Not verified, live run needed: the 0xC8 outfit window lists after the current look (wings and auras with `u16` ids, shaders with a byte id, the other width is tried when names do not read, tested both ways), the 0xD3 set packet tail,
and everything marked "base" above.

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
## Combat helper, typed numbers, death recap, loot (O433 phase 3, track I)

- Helper (`Ctrl+R`, `HelperWindow`, loop in `Core/HelperEngine.cs`, rules in `Core/HelperLogic.cs`, settings in `Core/HelperConfig.cs`, Auto setup in `Core/HelperRotation.cs`).
  A port of the main client's `game_helper` and `game_helperrotation`. It runs every frame whether the window is open or not (the window ticks it once a frame) and does
  nothing until "Helper on". Tabs: Healing (3 spell rows, 3 potion rows, mana training, Auto Haste), Shooter (5 slots: spell, mana percent, monsters to cast on; Auto turn; Auto setup),
  Target (Auto Target, modes A..H). Saved per character in PlayerPrefs (`chaos.helper.-/<name>`, JSON, every number clamped on load).
- Pacing, as the main client's: a pass every 50 ms; heal every 250 ms, mana training 100, haste 500, Auto Target 250, shooter 100. Every cast goes through `HelperTimers` (per channel
  heal / attack / support at most 4, 4, 3 casts a second, the same words not within 500 ms; a potion at most every 600 ms) and `HelperCasts` (a cast waits for the server's cooldown packet
  0xA4 / 0xA5; no answer in 1.2 s or 3 round trips means refused and the spell backs off 2, 4, 8, 16 s; the group of a cast is held for two round trips; cast-time spells block other attacks).
  One shooter cast per pass. A hit taken heals at once (at most every 100 ms). Nothing is sent for 1.5 s after the server went quiet for 2.5 s. Paused in a protection zone (0xA2 bit 14).
  Potions are used on yourself (0x84 with your creature id) from the equipment or an open bag.
- Auto setup: `HelperRotation.Select` picks the class preset for the level, replaces spells the character cannot cast, tops up to 5, puts area spells first and the class ultimate
  (level 1200) in front. `Core/HelperRotationData.cs` is generated from `client/overlay/modules/game_helperrotation/autorotation_data.lua` by
  `luajit unity/tools/gen_helper_rotation_data.lua` (`--check` in the `core` job).
- Not ported (phase 5 track Q added runes, ally heals, food, Everfull held, presets, the Support tab and the HUD: see "Helper extras" below): Follow, Auto sell, exercise, the potion gate for closed backpacks,
  the line-of-sight check (every monster in the 7 x 5 window counts), the Auto Target engine and guard (summons are skipped by creature type).
- Typed damage numbers: with the Chaos identity the login now sends capability bit 7 (`0xC0` with wide spell ids). `GameParser.TextMessage` reads u16 percent, u8 type, u32 creature after
  the value pairs when feature 155 is on, and `FxEvent.TypedNumber` carries them. In the live view (`FrontFxDirector`, `FrontLiveFx`) a critical hit is bigger and slower, a condition tick smaller,
  mana drain and mana gain are water coloured, an energy shield hit is energy coloured, every number is scattered by `DamageScatter` (the main client's rolls: shift, speed, drift, the texts of one hit
  share a roll) and follows its creature.
- Death recap (`DeathRecapWindow`, `Core/DeathRecap.cs`, opcode 154): the server stores a recap at the death and sends it at the next login (auto), the window opens by itself unless
  "Open after a death" is off (`chaos.deathrecap.auto`). The toolbar button "Recap" opens the history of the last deaths.
- Loot (`LootWindow`, Ctrl+D): Loot (the loot channel, opcode 238: a click takes an item, Shift one), Filter (what glows and dims, presets, categories), Labels (ground labels, opcode 230,
  settings per character in `chaos.groundlabels.<name>`). Ground labels (`ChaosApp.Loot.cs`) are drawn over the map in the classic and the live view: the scan looks at the 17 x 13 tiles round you every
  400 ms (60 ms after a step), asks the server for the tiles whose candidate items changed (at most 30 a request, asked again after 3 s), and lays the labels out so none overlaps.
  Click on a corpse label opens the corpse. Hold Alt to show every item.
- Tests: `Core.Tests/HelperTests.cs` mirrors `helper_logic_test.lua`, `rotation_test.lua`, `helper_potions_test.lua`, `helpertimers_test.lua`, `autorotation_test.lua`, `scatterlogic_test.lua`,
  `deathrecaplogic_test.lua`, `lootfilter_test.lua` and `groundlabels_test.lua`, drives the engine with a fake game and a fake clock, and reads typed 0xB4 packets.

## Social and market (O433 phase 4, track M)

- One model for the list-style windows: `Core/Social.cs` (`SocialPanel`, `RowList`, `SocialRow`: section, text, row with up to 3 buttons, input, combo, bar) and one window class for all of them
  (`Unity/Windows/SocialWindow.cs`, the concrete windows in `SocialWindows.cs`). A panel turns the server's last message into rows, the window draws them (scroll, tabs, two header lines, status line,
  item icon with rarity frame, hover tooltip). An input row is a text field, a combo row a button that cycles the options (right-click goes back). No window has a Ctrl hotkey: the top menu opens them
  (`TopMenu` entries named like the unlock menu texts of opcode 115: Market, Guild Wars; Guild, Party Finder, Leaderboards, Inspect Player under Social; Group Queue under Adventure), or the server does
  (NPCs, a depot market item, the guild hall stone). Factions and the Conquest vendor are NPC-only like the main client, they are in the Windows list.
- Panels (all in `GameSession.Social`, `Core/GameSocial.cs`): `Market` (`Core/Market.cs`, opcode 221), `Guild` and `GuildWar` (`Core/Guild.cs`, 252 and 197), `PartyFinder` and `GroupQueue`
  (`Core/PartyFinder.cs`, 208 and 160, the ready check box is `ReadyCheckWindow`), `Inspect` (`Core/Inspect.cs`, 240), `Leaderboard` (`Core/Leaderboard.cs`, 229), `Links` (`Core/ChatLinks.cs`, 249),
  `Factions` and `Conquest` (`Core/Factions.cs`, 215 and 167; Go to NPC uses opcode 121). Requests carry what the main client sends (the guild and war windows add `tab` to every request).
- Item links (`ChaosApp.Social.cs`): Shift+click on an item of the equipment or a bag asks opcode 249 `register` and puts "[Name] " in the chat line; Enter writes the chips out as `[Name]{<r><id>}`; a chat
  line with links shows the names in the rarity colour and the tooltip of the link under the pointer. `ChaosApp.ShowTip(tip, extra, note)` is the one call a window makes to get the item tooltip box.
- Right-click "Inspect Player" on a player of the map (`ChaosApp.Party.cs`) asks opcode 240 by creature id.
- Texts: `Core/LocSocial.cs` (merged in `LocStrings`). `SocialTests` also checks that every `Loc.T` key of the social Core files, the tab names and the menu entries have a pt-BR text.
- Tests: `Core.Tests/SocialTests.cs` drives each panel with the server's messages and reads the requests back from the packets (market flow with the fee and tax maths, guild tabs, war offers and the
  boss, party finder filters and post input, group queue rules and the ready check countdown, inspect parts, leaderboard boards and records, link parsing and chips, factions, Conquest rows).
- Not done: the Modifiers filter of the market (Browse and buy orders) and the price history chart, dragging an item onto the Sell slot, the read-only passive tree view of Inspect, the faction emblems,
  the party finder menu badge and slot boxes, short numbers on the leaderboards, the guild hall's crafting bench window, the Ctrl compare of item tooltips. Nothing here ran against a live server.
## Endgame activities (O433 phase 4, track L)

Eleven activities of the main client, each a pure model in `Core/` and windows in `Unity/Windows/EndgameWindows[ABC].cs`. All open from the Adventure menu
(`Core/TopMenu.cs`, the menu texts are the keys of the server's level unlocks, so a locked one shows grey with its level) or by the server. None has a Ctrl hotkey.
`GameSession.Endgame` (`Core/GameEndgame.cs`) owns the models, asks for the first state 2.2 s after the login and is rebuilt with every session.

| Activity | Opcode | Model | Windows |
|---|---|---|---|
| Infinity Tower | 214 (flat JSON) | `TowerState` | `TowerWindow`, `TowerPanelWindow` (Ctrl+Shift+N skips, Auto box in `chaos.towerAutoSkip`) |
| Dungeons | 109 | `DungeonsState`, `DungeonsView` | `DungeonsWindow`, `DungeonCounterWindow` |
| Ashen Sepulchre raid | 213 | `RaidState`, `RaidView` | `RaidWindow`, `RaidHudWindow`, `RaidCalloutWindow` |
| Ember Descent | 205 | `DescentState`, `DescentView` | `DescentWindow`, `DescentHudWindow`, `DescentOfferWindow`, `DescentShopWindow` |
| Rift Atlas, Waystone Atlas | 210, 159 | `AtlasState`, `AtlasView` | `RiftAtlasWindow`, `WaystoneAtlasWindow` |
| Invasions | 251 | `InvasionState`, `InvasionView` | `InvasionHudWindow`, `InvasionWindow` (calendar) |
| Guild siege | 233 | `SiegeState`, `SiegeView` | `SiegeWindow`, `SiegeHudWindow` |
| Arena | 236 | `ArenaState`, `ArenaText` | `ArenaWindow`, `ArenaHudWindow` |
| Battleground | 200 | `BattlegroundState`, `BgView` | `BattlegroundWindow`, `BattlegroundHudWindow`, `BattlegroundBoardWindow` |
| Scorched Marches | 193 | `PvpZoneState`, `PvpZoneView` | `PvpZoneWindow`, `PvpZoneConfirmWindow`, `PvpZoneHudWindow` |
| Bounty board | 223 | `BountyState`, `BountyView` | `BountyWindow` |

- The view classes hold the main client's rules (`*view.lua`, `*math.lua`, `arenatext.lua`, `towerskip.lua`) with the same fields and defaults. The state classes read the
  server's messages and send the same actions. The tower is flat JSON, all the others are `{action, data}`. The atlas tree may come in parts; `ExtChunks` joins it.
- A HUD is an `EgHudWindow`: it opens when its activity starts, closes when it ends, and the x hides it for that run. Windows follow their state's `Visible` flag (`WindowSync`),
  and Show sets the flag at once and asks the server, as the bank does.
- Arena, battleground and the Marches turn the secure mode off for the fight and back on after it (`EndgameBridge`), the arena and the battleground also cancel the attack at the end.
  Server refusals and battleground alerts go to the text log through `Notice` and `Alert`.
- Texts: `Core/LocEndgame.cs` (pt-BR, merged in the `LocStrings` constructor, a key of the main table wins). Tests: `Core.Tests/EndgameTests.cs` feeds each module the servers' payloads
  and checks the requests, the view text, the timers on a fake clock, the Adventure menu entries and the pt-BR placeholders.
- Not done: the dungeon boss outfit and item finder, tier emblems and node art of the atlases, boon icons of the Descent, minimap flags for the Marches, saved HUD positions,
  the "how it works" cards. None of it ran against a live server.
## Collections, seasons and crafting (O433 phase 4, track N)

Thirteen windows, each a pure model in `Core/Collect*.cs` (the wire layout of its opcode is at the top of the file) and a window in `Unity/Windows/`. All models are built in `Core/GameCollect.cs`
(`GameSession.Achievements`, `Bestiary`, `Charms`, `Pass`, `Seasons`, `Daily`, `Weekly`, `Cosmetics`, `Transmog`, `Pets`, `Professions`, `Crafting`, `CraftTable`); a model owns its opcode and
a `Visible` flag, `ModelWindow` (`Unity/Windows/CollectUi.cs`) opens the window when the server sets it and asks the server when the player opens it. No Ctrl hotkeys: the windows are in the top menu
(Character: Achievements, Charms, Cosmetics, Pets, Transmog. Hunt: Bestiary. Adventure: Daily Reward, Season, Season Pass, Weekly Chest. Economy: Crafting Bench, Professions, Crafting Tables) with the
main client's level unlocks, or the server opens them (daily reward at the login, season pass and weekly chest, broker NPC, crafting tables).
- Opcodes: achievements 250, bestiary 253, charms 198, season pass 227, seasons 246, daily 207, weekly chest 117, cosmetics and unlocks 225, transmog 212, pets 254, professions 195,
  crafting bench 232, crafting tables 91. Crafting skills are in the 0xA1 skills packet (`GameParser.CraftSkills`, the seven skills after fishing) and drawn in the Professions window.
- Faithful to the main client's actions and fields: the same packets (`open`, `claim`, `calim` with a bare server day number, `place` / `move` / `take`, `apply` with the aimed modifier, `giftPrice`
  round trip, `salvageBatch` with its signature, `fetch` / `craft` with chunked replies), the same rules (stage percent, tier track, grid fit, quote with the daily cap, craft checks and pacing).
- Seasons send the Hardcore heartbeat (`beat`) every `heartbeat` seconds without the window open; the pets window asks again every 3 seconds while open; a craft repeats with the main client's pacing
  (860 ms craft, 1000 ms cooldown, 5 s without an answer stops it).
- Texts: `Core/LocCollect.cs`, merged into `LocStrings.PtBr` (a key the main table has wins).
- Tests: `Core.Tests/CollectTests.cs` (every model on the messages of the Lua tests and the server scripts, packets compared as text).
- Not done: the on-screen kill task tracker, the chat name colour and label accent (read, not applied), look and effect previews (cosmetics, pets, transmog, footprints, outlines), the item right-click
  entries (Transmog, Lock item), a charm item dropped from a backpack, rich item tooltips in the crafting tables, the gem guide table and the Codex link of the bench, the unlock toast of achievements,
  the daily window waiting for other login windows. Not run against a live server (as the other tracks).
## World, map and item utilities (O433 phase 4, track O)

Twenty one more modules of the main client, each a pure model in `Core/` (`WorldMarks.cs`, `WorldTravel.cs`, `WorldTiles.cs`, `WorldItems.cs`, `WorldItems2.cs`), made once in `WorldUtils` (`Core/GameWorld.cs`, `GameSession.Utils`)
and driven through the extended opcode layer. Drawing: `Unity/ChaosApp.World.cs` (map group, both map views through `TileScreenPx`, plus the Candlemarks counter, the Hideout placing bar and a small tooltip),
windows: `Unity/Windows/WorldWindows.cs` and `ItemWindows.cs`. No window has a hotkey: the top menu opens them (same menu texts and level unlocks as the main client) or the server does
(Waystone, Gambler, Unveil, Osric, the banker style NPCs). Texts: `Core/LocWorld.cs` (pt-BR, merged in `LocStrings`).
- Map: `MapMarkState` (opcode 153: party pins that glide, points of interest by category on the Minimap window, quest goals, the gold ! and ? over NPC heads, arrows for members out of view),
  `MapOverlayState` (245: the explored map see-through over the game view, opacity, zoom, pan, corner box, strip, rift squares), `MinimapSyncLogic`, `TileOverlays` (156: seconds over timed fields from a
  scan of the world four times a second, the server's bars), `WeatherState` (114: rain, embers, motes, dust, area colour mood, drawn in code), `NameplateState` (248, plain text: title, guild, frame).
- Places: `NpcTravel` (121), `WaystoneState` (202, raw JSON without the data wrapper), `TownPortalState` (239) and `LoadoutsState` (206) put their casts on the HUD cast bar, `HideoutState` (192: catalogue,
  placement check, the ghost on the map).
- Items: `AutoLootState` (216), `PouchesState` with the Auto Seller (226), `OrbExchangeState` (209), `GambleState` (199), `EmberCacheState` (174), `UnveilState` (196), `ItemFinderState` (155),
  `SpellSupportsState` (243, joins `part` messages), `PactState` (222, a loaded build previews in the passive tree), `CandlemarksState` (176).
- Settings of the markers and the overlay are kept in PlayerPrefs (`chaos.mm.*`, `chaos.mo.*`).
- Not done: icon art for marks and plates (coloured squares and a bordered box), the Tab hotkey and Shift + arrow pan of the overlay, drag and drop of runes, pips on the hotbar and the spellbook line
  (`SpellSupportsState.BookLine`), the action bar profile of a loadout, right-click menu entries (Where to find, Add to Loot List, Pouch settings), the Orb Exchange chart, the remembered minimap over a relog.
  Nothing here was run against a live server.
- Tests: `Core.Tests/WorldTests.cs` drives every model with the messages of the server scripts and reads back what it sends (about 400 checks): the placement check of the hideout, field timers on a
  synthetic world, rain fades, plate batches and retries, order forms, crate cells, part joining, and that every text has a pt-BR entry.

## Base gameplay actions (O433 phase 5, track P)

What a player does with items and players. Pure models in `Core/Play.cs`, `PlayLists.cs`, `PlayGuards.cs`, `PlayLook.cs`, wired by `Core/GamePlay.cs`; the app side is `Unity/ChaosApp.Play.cs` and `Unity/Windows/PlayWindows.cs`.
Wire layouts are TFS 1.4.2 `protocolgame.cpp` for 10.98 (the base tree is not in this repo, so check them on a live run).
- Look: Shift + left click on the map (0x8C with the tile, the stack position and the item id; a creature goes as 0x8D) or on a slot of the equipment or a bag. While the chat line is being written Shift + click on a slot still links the item.
  The answer is the text message the chat shows. Picking: `TilePick` (`LookIndex`, `UseIndex`, `TopCreature`) follows the base `getTopLookThing` and `getTopUseThing`.
- Use: a right click uses a map item or a slot item (Classic Controls). A multi-use item (rope, shovel, runes) starts the crosshair "Use with ..." unless the server listed it as equipment and "Right-click equips items" is on
  (opcode 188, `HudOptions.MultiUseIds`). The next left click is the target: a map item or a slot (0x83), a creature (0x84). A right click or Esc ends it. Rotate is 0x85.
- Item menu: Ctrl + right click on a slot or a map item. Open or Use, Use with ..., Rotate, Look, Trade with ... (own items, another player in view), then the hooks of the Chaos modules: Where to find (`ItemFinderState`),
  Add to / Remove from Loot List (`AutoLootState`), Pouch settings (`PouchesState.IsLootPouch`), Transmog (worn head, armor, hands, legs, feet), Lock item / Unlock item (`CraftingLockMenu`, `CraftingState.LockAt`, the server's lockAt).
- Trade: "Trade with ..." in the menu, then a click on a player sends 0x7D. `TradeWindow` opens on the server's 0x7D and 0x7E, a click on an item looks at it (0x7E), Accept is 0x7F, Reject or the x is 0x80.
  A changed counter offer clears your accept (TFS sends no accepted message).
- VIP list (`VipWindow`): 0xD2 entries, 0xD3 status, 0xD4 for an old logout. Add by name (0xDC), edit description, icon and notify (0xDE), remove (0xDD), double click opens a private tab. Quest log (`QuestLogWindow`): 0xF0 list, a pick asks 0xF1.
  Neither window has a hotkey (Ctrl keys are taken); the Windows menu lists them.
- Badge slot: `Parser.Inventory` has 14 slots, the equipment window draws slot 13 where ammo was (the server gives slot 10 nothing since src-patch 0058).
- Guards: `DeadGuard` (a monster at 0 percent for 3 s leaves the map), `TargetGuard` and `TargetLock` (the helper's locked target is dropped after 3 refused re-sends in 3 s), `AutoTargetCore` (goblins, bosses, special tiers first; `HelperEngine.RankOf` is set by the helper window from the name and the monster bar),
  `LootScreen` (the loot line stays off the screen), `LookPreview` + `LookPreviewWindow` (`ChaosApp.ShowLookPreview(option)`).
- Not done: map picking in the HD-2D scene (creatures only there), the reach rule of Auto Target (no pathfinder or line of sight in the Unity world) and its two options, the mount, wings, aura and shader drawn on the look preview and the effect stage, a call of `ShowLookPreview` from the Outfit, Cosmetics and Store windows,
  split stack dialog on drag, the equip hotkey (0x77), "Browse field", the rules of the quest log tracker, a Rift Key name check for the lock entry (the client has no item names). Nothing here was run against a live server.
- Tests: `Core.Tests/PlayTests.cs` (byte-level packets out and in, tile picking, menu entries, crosshair, trade, VIP, quest log, guards, Auto Target order and the engine with it, badge slot, look preview, texts).
## Visuals, audio and layout (O433 phase 5, track R)

Eighteen more modules of the main client. The rules are the Lua logic files without engine calls: `Core/Audio.cs` (sound mixer, region music, the overlay file finder), `Core/Visual.cs` (opacity, error colour, wings, loot beams,
decals, auras, cosmetic prints, ground ids, boss looks, hit flash, shake, name shaders), `Core/Layout.cs` (map zoom, movable HUD, screen fit, window fade, saved layout). `Core/GameVisual.cs` (`GameSession.Visual`)
connects them to the combat feed and the world. `FxFeed` got a `Tap`, so sounds, decals and flashes see every damage number and magic effect whether or not the live view runs.
- Files: the sounds and the music are the main client's own ogg files (`client/overlay/modules/game_chaossound/sounds`, `game_chaosmusic/music`, built by `client/tools/gen_music.py`), and the aura, decal and print
  pictures are its png files. Nothing is copied into the Unity project. The player looks in `CHAOS_OVERLAY_DIR`, `StreamingAssets/overlay/modules`, `overlay/modules` beside the executable, then the repository's
  `client/overlay/modules` (`OverlayFiles`). A build that ships the game folder copies the module folders `game_chaossound`, `game_chaosmusic`, `game_chestaura`, `game_combatdecals` and `game_cosmeticfx` to
  `StreamingAssets/overlay/modules`; the CI build does this (its ogg and png files only, `unity-prototype.yml`; track U adds `game_shaderfx`, the toast icons and `overlay/data`, see "Art of the main client's modules"). Without the files the game is silent and has no pictures for auras, decals and prints (drawn stand-ins for the rest); Options > Sound says so.
- Drawing: `Unity/ChaosApp.Visual.cs` draws in the map group through `TileScreenPx`, so the classic view and the front-art live view (F8) share it: ground rings (the 223 ground effect ids), decals, footprints, chest and
  Templar auras (the range frame as a nine-slice), cosmetic glows, loot beams, hit flashes and level-up wings. The HD-2D scene draws none of it. `Unity/ChaosApp.Audio.cs` plays the cues (8 voices) and cross-fades two
  music sources. The own name wears the picked name shader (`NameShadersWindow`, opcode 96).
- Layout: the map zoom (7 to 11 rows, Ctrl and the wheel, `ChaosApp.ViewTilesW/H` are no longer constants), the camera shake, the movable HUD pieces (plate, log out, chat, top menu; edit mode and reset in Options > Layout,
  saved per character in `chaos.hudpos.<name>`), windows taller than the screen (wheel scroll), the window fade, and the saved window places (`chaos.layout.<name>`, plus the open state of the minimap, battle list, equipment and containers).
- Options: the existing options window got four pages (General, Sound, Visuals, Layout), `Unity/Windows/VisualWindows.cs`; every option is in PlayerPrefs (`VisualPrefs`: `chaos.sound`, `chaos.music`, `chaos.lootbeams`,
  `chaos.visualfx`, `chaos.effectopacity` and flags). Texts: `Core/LocVisual.cs` (pt-BR).
- Not done: drawing a larger map area than 15 x 11 tiles (the wire is ready, see "Wire audit"); effects drawn under creatures (they are over them, IMGUI); the pack effect strips of the loot beams and wings
  (drawn in code instead); the outline shader of cosmetics; the grade, bloom, spell light, liquid shimmer, target and hover outlines and cooldown pulse of game_visualfx; the shift of Gravewarden Ulthar in the live view;
  the container, panel and size parts of game_chaoslayout. The audio and picture loading and the drawing compile (`unity/Client.Check`) but were not run in a Unity player or against a live server.
- Tests: `Core.Tests/VisualTests.cs` (about 190 checks): the mixer rules and files against `soundlogic.lua` and the module folder, the music rules and hysteresis with the files, the cursed and foot aura messages and
  the strip sizes, decal colours, beams, prints, ground ids against `groundfx_data.lua`, the layout rules, and a session fed with the combat events (cue, flash, stain, shake, ring, wings, kill, chest, footprint).
## Helper extras and the info windows (O433 phase 5, track Q)

Helper extras (all in the helper window, Ctrl+R; tabs Healing, Shooter, Target, Runes, Allies, Support, More). Rules: `Core/HelperExtras.cs` and `Core/HelperSupport.cs`, loop parts:
`Core/HelperEngineExtras.cs`, settings: `Core/HelperConfig.cs` (new fields are read with defaults, an older saved text still loads). Same pacing as the main client: the new parts run every 250 ms
(allies, attack runes, Support) or 1000 ms (food); a rune waits one second per kind (`HelperTimers` channels healRune, attackRune, food); an ally heal has a gap per target (1.2 s) and a budget of
8 in 10 s; nothing runs in a protection zone and every cast goes through `HelperCasts`.
- Runes: 2 healing rows on yourself (percent) and 3 attack rows per preset (monsters to hit, health range of the monsters, priority). An attack rune goes on the target while the spell rotation is on,
  when the monsters in its area reach the count. The rune must be in the equipment or an open bag (the main client's gate for closed backpacks is not ported).
- Allies: party members below a percent and a list of 5 friends below another; a single-target spell by name (the name is cleaned and quoted), a group spell by count, a healing rune. Your own healing
  comes first. Players come from the map (`IHelperHostExt.Players`, party shield from the creature).
- Food: eats a carried food every two minutes. The 10.98 state word has no hungry bit, so only the gap rules.
- Everfull held (`EverfullHeld`, opcode 116 `held`, `sync` sent when the helper starts): a Health or Mana Potion row follows the carried flask of its slot.
- Shooter presets: up to 20 named presets of the five slots, the attack rune rows and the Auto Target mode (`HelperConfig.AddProfile`, `SelectProfile`, `RenameProfile`, `DeleteProfile`); the live
  `Shooter`, `RuneAttack` and `AutoTargetMode` are the selected preset's. Buttons < and > cycle them. The main client's hotkey that cycles presets is not ported.
- Support: up to 8 support spells (shields, summons, fight buffs, vigils) cast by priority when off cooldown and while the effect is not on. A port of `supportspells.lua`. Unity has no buff bar, so the rule
  the main client uses when the bar cannot tell applies to every spell: the spell's own duration since our last cast, else at least a minute (or its cooldown). A vigil (a switch) is never cast blind, so
  it stays unused. A capped summon is cast only below the summon cap, counted from your summons on the map. "Fill from my class" is Auto setup's plan; the Auto setup button of the Shooter tab also fills an
  empty section. No timer section (the main client's Support absorbed it).
- Bot HUD (`HelperHudWindow`, no menu entry): a movable window with the rows of the ticked sections (combat, healing, support, player), on while "Show Bot HUD" is ticked in the More tab.
- helper timers (`game_helpertimers`) is the pure `HelperTimers` class that was already there: no window in the main client either.
- Not ported: the preset hotkey. (Follow, Auto sell, exercise weapons, the potion gate and the line-of-sight check came in phase 7 track X: see "Phase 7, track X" below.)

Info windows (none has a hotkey; the top menu opens them: Hunt > DPS Meter, Economy > Codex, System > Help Search; `Unity/Windows/InfoDataWindows.cs`, `Unity/ChaosApp.Info.cs`):
- DPS meter (`DpsMeterWindow`, `Core/DpsMeter.cs`, opcode 204): bars per skill with total, per second and share; tabs Damage / Healing / Taken / Received; the current fight, the session or one of the last
  10 fights (< >); party mode; the Combat log switch shows the detail table (hits, crits, average, max, overhealing, element split); Copy puts the summary on the clipboard, To chat writes one line into the chat
  input; Reset asks twice. The server starts pushing on `open` and stops on `close`, so the window only asks while it is open. Settings per character in PlayerPrefs `chaos.dpsmeter.<name>`.
- Short numbers (`Core/InfoNumbers.cs`, `ShortNumbers`): `Short`, `Exact` and `In` (the conservative text rule of `client_chaos_numbers`: ids, coordinates, years and times stay as they are). Server text of the
  kinds 17, 18, 19, 21 and 22 (status, event advance, look) is shortened in `GameParser.TextMessage`; `ShortNumbers.Enabled` turns it off.
- Names over tall looks (`Core/InfoLift.cs`, table `Core/InfoLiftData.cs`): the name and health bar of a player or an NPC wearing a tall look go up by the lift of its look type, in the classic view.
  Monsters keep the classic place, as in the main client. The 3D live view places its labels from the figure and is not changed.
- Data (`unity/tools/gen_info_data.lua`, `--check` in CI, run with luajit or lua5.3): `Resources/Codex.json` (from `codex_data.lua`), `HowItWorks.json`, `HelpSearch.json` and `Core/InfoLiftData.cs`.
  Rerun it after `server/tools/gen_codex_data.lua`, `gen_howitworks_data.lua`, `gen_guide_data.lua` or a new pair's `gen_info_lift.py`.
- Codex (`CodexWindow`, `Core/Codex.cs`): 11 tabs, filters (a click on a filter goes to the next option, right-click back), search (every word starts a word of the name or the page), the list and the page
  (tables with the tier rows that roll at the chosen item level marked, shared sections, links with Back, "Where to find" opens the item finder). The texts are English: the main client translates them
  through its own key table (`CodexText`), which Unity does not have. The crafting bench's right-click on a modifier calls `ChaosApp.OpenCodex(id)` (`CodexView.IdForMod`).
- How it works (`HowItWorksWindow`, `Core/HowItWorks.cs`): the card of a feature in en or pt-BR. A `?` button in the title bar of every feature window that has a card (`GameWindow.HowKey`, the table
  `HowItWorks.UnityWindows`); the first time a character opens such a window the card opens by itself (PlayerPrefs `chaos.howitworks.seen.<name>`, off with the box below the card `chaos.howitworks.auto`).
- Help search (`HelpSearchWindow`, `Core/HelpSearch.cs`): offline ranking over the cards, the unlock entries and the Codex, the first steps before the player types, snippets in the language chosen. A click
  opens a card or a Codex entry.
- Weapon list (`ProficiencyWindow`, `Core/ProficiencyCatalog.cs`): every dat item with a weapon market category and a name, by category with a search. The dat has no weapon type (the main client uses it for
  items without market data), the perk trees and weapon experience are not in Unity. No menu entry (the main client has none either); it is in the Windows list.
- Texts: `Core/LocInfo.cs` (pt-BR, merged in `LocStrings`).
- Tests: `Core.Tests/InfoTests.cs` mirrors the Lua tests of the helper extras, `dpsmath_test.lua`, `numbers_test.lua`, `infolift_core_test.lua`, `howcore_test.lua`, `helpcore_test.lua`, `codexview_test.lua` and
  `catalogcore_test.lua`, reads the real JSON files, and drives the engine with a fake game (about 300 checks).
- Not done: the Codex pt-BR texts, the DPS meter's icons, drag and resize of the panel (the window frame moves; size and position are not kept), the 3D label lift, Follow and Auto sell, the buff bar the
  Support section would read. Nothing here ran against a live server.
## Community, credits and tools (O433 phase 5, track S)

Sixteen more modules of the main client and a check that no opcode is forgotten. Models in `Core/Community.cs` (admin panel 120, boss spawns 217, survey 122, nemesis 163, referral 220),
`Core/CommunityGoal.cs` (community goal and Brazier 203, chronicle and Memorial 171, mentors 194, patch notes 244) and `Core/CommunityExtras.cs` (card borders 172, drop feed 229, credits,
streamer and cinema mode, performance record, automatic screenshots, Customise Character extras); the session part is `Core/GameCommunity.cs` (`GameSession.Community`), the windows
`Unity/Windows/CommunityWindows.cs` (all on the list-window framework: `SocialPanel` rows), the app glue `Unity/ChaosApp.Community.cs`. No window has a hotkey: the top menu opens them
(`Core/TopMenu.cs`) or the server does (survey at level 20 and 50, the Brazier, the pocket boss NPC, the mentor offer, the patch notes at the login). Texts: `Core/LocCommunity.cs`.
- Opcode coverage: `python3 -I tools/ci/check_unity_opcodes.py` (CI job `core`). Every `ChaosOpcodes` number of the server and every opcode a main client module registers must be handled in Unity or
  be in `tools/ci/unity_opcodes_allowlist.txt` with a reason ("not ported yet" is open work). The list can only shrink; `--list` prints the table. The test builds a made-up tree.
- Admin Panel: the same gate as the main client. The client asks for the catalog 600 ms after the login; only staff accounts get an answer, and the window is in the menu only then. The server re-checks every action.
- Credits: `python3 -I unity/tools/gen_unity_credits.py` writes `Core/CreditsData.cs` from docs/CREDITS.md with the parser of `client/tools/gen_credits.py` (`--check` in CI).
- Streamer mode (Ctrl+Shift+S): `ChatModel.Streamer` hides private message text (and the sender, with the sub-option) before a line is stored and masks IP addresses in server texts; the character list masks the
  other characters; the own name is not drawn. Cinema mode (Ctrl+Shift+H) draws the map alone. Options in PlayerPrefs (`chaos.streamerMode` ...).
- Screenshots: `ScreenCapture` into `screenshots/` of `Application.persistentDataPath`, 300 ms after the event (level up, valuable loot, achievement, new record line). Performance: `PerfCore` is perf_core.lua
  ported (stats, record, verdict, CSV, report); Record 60 s writes `chaos-perf-<time>.csv` and `.txt` next to the screenshots folder.
- Tests: `Core.Tests/CommunityTests.cs` drives every model with the server's messages and reads back what it sends (about 270 checks): the admin gate and confirm press, boss countdowns and pocket buttons,
  survey answers, nemesis times, referral rows, goal stages and Brazier limits, chronicle languages and memset, mentor pages and offer, patch notes in parts and the login wait for the Daily Reward window,
  the changelog, card borders, drop feed, credits, streamer masks through the chat model, the performance record (60 samples, CSV, report), screenshot rules, the extras plan, and that every text has a pt-BR entry.
- Not done: Boss Defeated screenshots, the window title and login fields of streamer mode, the Customise Character look preview and colour palette, boss pictures and stage icons, a Nemesis tab in the Bestiary window.
  `game_event` is N/A (no server system behind it). Not run against a live server (as the other tracks).

## Art of the main client's modules (O433 phase 6, track U)

Icons, globes and the monster bar frame come from the main client's own png files, read the way the sounds are (`OverlayFiles`: `CHAOS_OVERLAY_DIR`, `StreamingAssets/overlay/modules`, beside the executable, the repository).
Which file and which part is `Core/OverlayArt.cs`, the loading and drawing `Unity/ChaosApp.Art.cs`. Every drawing keeps its older stand-in, so a run without the files looks as before (one line in the log names the missing folder).
- Files: the pictures of `client/overlay/data` are named `../data/...` under the modules folder, so the CI step copies them to `StreamingAssets/overlay/data` (`images/game/spells`, `images/game/buffs`,
  `images/chaos/monsterbar`, `images/chaos/topbutton_ranking.png`) and `game_shaderfx` and `game_chaosnotify/images/toast` to `overlay/modules` (about 2 MB, gitignored). A game folder that ships the overlay needs the same two folders.
- Spell icons: the three sheets have 20 columns, cell n at column (n - 1) % 20, row (n - 1) / 20. The Unity client draws the 32 px sheet. `SpellIcons.Cell(words, id)` maps a spell to its cell from `Core/SpellIconData.cs`, generated from
  `game_chaosspells/spelldata.lua` by `python3 -I unity/tools/gen_spell_icon_data.py` (`--check` in CI). The spellbook rows and details, and the hotbar slots, draw the cell; a rune entry draws the rune's sprite; a stock spell has no cell
  in the repository (the base client's own table) and keeps its element colour square. The painted icons option is not ported.
- Buff icons: `BuffIcons.OwnName(spec, key)` is the rule of `buffmath.lua` (`buff:name`, else the key, else `spellbuff`), 26 px pictures, drawn in a thin gold (buff) or red (debuff) frame with the timer under them; a buff without a file keeps the coloured square.
- Toast icons: the 48 px picture of each of the 21 types (`ToastIcons`, same rows as `notifications.lua`, checked by the tests) at the left, the text beside it.
- Globes: `OrbArt` is the plain globe of `shaderfxlogic.lua`: a white mask cut to the fill from the bottom, tinted `#d8262c` or `#2f6ef0`, under the painted ring (art size 76, drawn 96 px), the number in the middle. They stand left and right of the hotkey bar
  (the bottom centre while it is closed). Option: Options > Visuals > "Health and mana globes" (`chaos.globes`). The liquid shader and slosh are not ported; the character plate keeps its bars.
- Monster bar: the 420 x 58 frame, the 344 x 16 fill and trail in its socket, the nine-slice name plate and level plate, and the modifier chip pictures (`MonsterBarArt`, numbers from `monsterbar.otui`). Without a picture the drawn bar of before.
- Hotbar item and rune slots (`Core/HotbarSlots.cs`, `HotkeyBarWindow`): a slot is a line to say (as before), or an item. Drop an item from the equipment or a bag on a slot, or use "Add to hotbar" in the item menu (first empty slot; not for worn items, bags or map items).
  The slot shows the sprite and how many you carry in the equipment and open bags (dimmed at 0). A press of the key or a left click uses it by its mode: Use (0x82), Use on yourself and Use on target (0x84 with your id or the attacked monster; nothing is sent without a target, as the base
  action bar), Use with ... (the crosshair of `ChaosApp.Play.cs`, then 0x83 or 0x84 on the click). A rune or any multi-use item starts as Use with ..., others as Use. Right click on an item slot: the four modes and Remove from hotbar.
  Saved with the other slots (`chaos.hotkey.<name>.<n>`): a line as before, an item as `item:<client id>:<mode>`, so an older save loads.
- Not done: item hotbar slots on the base client's Q and E side slots, drag from slot to slot, equip mode, the ornate hotbar frame, slot count and scale options; the monster look in toasts, toast plate and button art; the liquid shader of the globes.
  Nothing here was run in a Unity player or against a live server (the drawing compiles in `unity/Client.Check`).
- Tests: `Core.Tests/ArtTests.cs`: the cell maths and the table against `spelldata.lua` and the three sheets' sizes, buff names and file sizes, toast rows against `notifications.lua`, orb sizes and colours against `shaderfxlogic.lua`, monster bar geometry
  against `monsterbar.otui`, the slot model (parse, save, load, modes), the press rules on a fake host, the menu entry and the texts in pt-BR.
## Core loop user experience (O433 phase 6, track V)

The P0 rows of `docs/UNITY_PARITY.md` that the first phases left partial. Models are pure (`Core/AutoWalk.cs`, `Core/HudBars.cs`, `Core/SplitStack.cs`, `Core/NpcBubble.cs`, `Core/LoginExtras.cs`, `Core/PanelSettings.cs`), the glue is `Unity/ChaosApp.Phase6V.cs` plus edits in the plate, character select, equipment and party windows. Texts: `Core/LocPhase6V.cs`. Tests: `Core.Tests/Phase6VTests.cs`.
- Login screen: the news bar is the website's login services, one GET on `https://<login host without play.>/clientservices` (the endpoint `server/tools/clientservices.py` serves, `docs/LAUNCH.md`). It lists the running and next events, the boosted creature and boss with their outfit (drawn when the sprite pair is loaded) and the players online. A panel shows only with data; no data or no room, no bar. The medallions and crests around the sign-in panel are drawn in code. Event dates are the server's calendar stamps, compared with the machine clock.
- Character select: the website's account API (`chaos_client_api.php`, `website/README.md` "Client API") is asked once when the list opens: one `login` with the account and password the game login holds (HTTPS only, the token lives in memory and is ended on Back and on Enter). The answer adds the last login line, the season tag, wings, aura and shader names, merged into the card's outfit, and the slots header. A toggle on the screen turns it off (`chaos.account.api` in PlayerPrefs). Cards also get a class badge. Creating a character still opens the website page.
- Plate: health and mana bars ease to a new value and a fall leaves a pale chip (`HudBarTrack`, the timing of the main client's `hudbars_logic.lua`); the right click menu switches percent and eased bars. The strip on top of the plate moves it (the "status" piece of `HudLayout`, saved per character, double click resets). Under it the buff bar, shield and chi follow.
- Equipment window (the bag panel): tab row (Equip, Quest, Stats, Shop open their windows when the client has them), the coins of the open bags, Chaos Coins and the outfit.
- Auto-walk: a quick click (under 0.25 s, under 8 px) on a known tile finds the path with A* (`PathFinder`: straight 10, diagonal 30 because a diagonal step takes three times as long; tiles with a ground, nothing not walkable or not pathable, no creature) and sends it in one 0x64 packet (directions 1 east to 8 south-east, walking order, at most 100 steps). Escape sends 0xBE. A key step, a held button or a push ends it. A held button walks towards the pointer as before. The HD-2D scene has no tile picking: a quick click does nothing there.
- NPC: right click on an NPC (no more attack) offers Talk, Look, Copy Name. Talk says hi inside the talk radius (3 tiles), else walks to the nearest reachable tile within it, greets on arrival and gives up after 10 s or when the way is blocked. The bubble over the NPC shows its latest reply (wrapped, 8 lines at most), keyword chips and an end button (says bye); it closes when the NPC is out of range or the talk is idle for 120 s.
- Split stack: dropping a stackable with more than one asks how many (`SplitStackModel`: number, slider, 1, Half, All, Enter, Esc); Ctrl at the drop moves the whole stack. There is no equip hotkey: no main client module has one (right click equips through the server option, already done).
- Party frames: buff row and the gear settings of the main client (scale, show the panel, show myself, buffs, numbers, clicking follows, lock), saved as JSON in PlayerPrefs (`chaos.partyframes`).
- Not done: wings, aura and shader are named on the cards, not drawn; the in-client create window; bag pages, Sort and fight mode controls of the bag panel; an option to switch the NPC bubble off; buff icon art. Nothing here ran against a live server or a live website.

## Phase 7, track Q

UI, map and visual rows that were partial in `docs/UNITY_PARITY.md`. Pure rules: `Core/Phase7Q.cs` and `ViewZoom` in `Core/Layout.cs`. Drawing: `Unity/ChaosApp.Phase7Q.cs`. pt-BR texts: `Core/LocPhase7Q.cs`. Tests: `Core.Tests/Phase7QTests.cs`.
Pictures are the main client's own files, read through the overlay folders (`ArtTexture`). CI copies the added folders to `StreamingAssets` (`unity-prototype.yml`): `game_nameplate`, `game_chaosweather` and, from `data`, `images/chaos/skin`, `images/chaos/mapmarkers`, `images/chaos/mapoverlay` and `skins` (about 2 MB). A missing picture keeps the older drawing.
- Wide view: Options > Layout "Wide view" asks the server for 29 x 21 after the login (0x33, Identity Chaos only) and again when it changes; off asks 17 x 13. The classic view draws `ViewZoom.MaxRowsFor(range)` rows, two tiles less than the area (11 at the default, 19 at 29 x 21), `MapView` builds its mesh from `World.Range`. The zoom is kept per character (`chaos.viewrows.<name>`); a new character starts near 72 px a tile. HD-2D and the live view stay at 11 rows because their tile windows are the default area.
- Interface scale (Options > Layout): 75 to 300 percent of the automatic scale, lowered to what leaves 960 x 540 UI units (`UiScaleOption`).
- Theme (Options > Layout): window frames from `skin/window.png` cut in nine, corner pieces and crest (small windows lose them), skin cycle button (Classic, Forge and Embers, Abyssal Arcane: pictures under `data/skins/<id>`), buttons and text fields from the skin's sheet through `GUI.skin` (`ApplyControlSkin`, the stock look comes back when the option is off).
- Map pictures: points of interest, party pins and arrows, floor arrows, NPC head marks and the overlay's kinds are the main client's PNG files (`MarkArt`). The explored minimap is saved per character to `minimap/minimap_<name>.bin` in the data folder (`MinimapStore`, a few bytes a tile) and loaded at the entry. A death notes the open overlay and Minimap window in `chaos.deathnote`; the same character back within two minutes gets them reopened (`DeathNote`).
- Weather: rain and ambient layers are the main client's repeated tiles scrolled by the offsets of `WeatherState` (`TiledArt.Uv`); Options > Visuals "Rain, embers and area colours" switches the weather off.
- Plates: the frame pictures of `game_nameplate` cut in nine; store name plates and bundles show TRY ON (own plate, ten seconds).
- Cosmetics: the chat name colours colour the speaker's name (`ChatTint`), the label accent is the background of highlighted loot labels. The look preview draws the outline glow, footprints and the plate frame; store offers (click the picture) and the Cosmetics Preview button open it.
- Others: STREAMER badge and starred server and account fields at the login; Boss Defeated screenshot (`BossKillWatch`); the Gravewarden shift in the live view.
- Not done: the Tab hotkey and Shift + arrow pan of the overlay (no new hotkeys); mount, wings, aura and shader in the look preview; tabs, scroll bars and check boxes in the theme; HD-2D and live view rows above 11; the rows this track did not reach: `game_chaoslayout`, `client_chaos_infolift`, `game_groundfx` under creatures, `game_chaosshaders`, `game_outfitextras` card grid, `game_nameshaders` other players, `game_levelwings`, `game_lootbeams`, `game_visualfx`, `game_cosmeticfx` outline shader, `game_cosmetics` effect icons.
  Nothing here was run in a Unity player or against a live server (the drawing compiles in `unity/Client.Check`).
## Phase 7, track X: character select, spellbook, hotbar, helper, top menu

Pure rules in Core (`Phase7XCharacter.cs`, `Phase7XSpells.cs`, `Phase7XHotbar.cs`, `Phase7XHelper.cs`), glue in `Unity/ChaosApp.Phase7X.cs`, `HelperWindowP7.cs` and edits of the character select, spellbook, hotbar and helper windows and the top menu. Texts: `Core/LocPhase7X.cs`. Tests: `Core.Tests/Phase7XTests.cs`.
- Character cards: `ChaosApp.DrawOutfitFx` draws what the website knows on the card's outfit: the aura under the body (a ring on the ground only, `OutfitLayers.SmallAura`: a tall aura hid the body in the main client too, so a card leaves it out), the wings at the body's tile with the body lifted 6 pixels up and left (`GameWingOffset`), the shader as a pulsing tint (`OutfitShaderTint`, picked by the name's colour word and family: pulse, sparks, waves, ghost; an approximation of the GLSL files, which only the engine runs). Wings and auras are creature things of the dat, drawn from their idle frames.
- Create character window (`CharCreate`, `ChaosApp.CharCreateGui`): the login answer of the account API already carries the `account` block (`AccountAnswer.Create`: classes with lock, plays line and the two starter looks, name rules, Terms and its page, slots, the running season with its modes). The window has the name with the website's rules checked first (`CheckName`), the class buttons (a locked one dim, with its reason), male or female with a preview of the class look in the starter colours, the season and mode list, the hardcore tick, the Terms button and Create. `create` sends the website's fields (token, nonce, name, vocation, sex, season, mode, hardcore, town 0); on success the character list is read again from the login server and the new character is selected. A 403 `terms` shows the accept page; a token that ended logs in again. Without the API the button opens the website page as before.
- Spellbook: the details show the area preview (`SpellArea.Roles`: matrix with you at 2 and 3, the target for a spell centred on the target, a single target at its range up to 5, only you for a self spell; cell size 5 to 14 px; the legend Hit, You, Target and the note) and the rows Soul, Group, Type, Element, Target, Scales, Vocations (`SpellDetails`; initials up to three, else Every class or N classes, the names on hover). The window is taller (up to 660 px).
- Hotbar (`HotkeyBarWindow`): the gear on the bar opens the slot count (6, 8, 10, 12) and the scale (75 to 125, steps of 5), saved per character (`chaos.hotbar.opts.<name>`), fitted to the screen width (scale down to 60 first, then two slots less, never under four); the default stays twelve slots as before. The Q and E side slots are slots 13 and 14 of `HotbarModel` (item or line; the bare keys Q and E press them when they hold something; Ctrl keys are untouched, so Ctrl+E still opens the equipment). Drag a filled slot onto another to move it (a filled target swaps; the mode of an item goes with it). A bar saved with twelve slots loads with empty sockets.
- Helper, tab "Follow and sell" and the Shooter tab: Follow (`HelperFollow`: a friend by name or the party leader by shield, distance 1 to 5, 250 ms between asks, five asks that start no follow then five seconds of rest, a follow the player chose by hand is left alone, protection zone and helper off pause it; `GameSession.Follow`, `GameParser.FollowTarget` tracks it and `Following` pauses the fight systems), Auto sell (`HelperSell`: asks the Auto Seller by timer or low capacity, 31 s between asks, state sync every 10 s while unknown; sends `sell` or `sync` through `PouchesState`), the exercise weapon (`HelperExercise`: protection zone, standing still 2 s, a dummy within 5 tiles with a clear line, `0x83` use with), the potion gate (`PotionGate`, shared with attack runes and ally runes: a count of 0 is probed by id `0xFFFF, 0, 0` every 3 s, a server "Using ..." marks it found, "Sorry, not possible." or "You cannot use this object." backs it off 30 s, a spell's refusal never counts; the helper window chains `Talks.ServerText` to read the answers), the line-of-sight check (`SightLine`: Bresenham between the tiles, a thing with `BlockMissile` blocks; used by area counts, ally heals, attack runes and the dummy), the level-up notice (a rise of the level, never the first reading of a login: new spells open the Shooter tab with Add and Ignore; "Auto-update my spells" rewrites only a rotation Auto setup wrote; ignored spells are remembered) and the class change cleanup (a vocation that changes takes the old class's spells out of the slots and healing rows 400 ms later).
- Top menu: "More" sub-menus (Character: Inventory, Outfit; Hunt: Map Markers; Economy: House, Ancestral Store) open a second box beside the drop-down, separators, the Ctrl shortcut on a row, and the System entries Options, Helper, Admin Panel (the window's `InMenu`: only when the server sent the admin catalog), Join Discord (the main client has no link set yet and says so), Logout and Exit.
- Not done: stock spell icons (the base client's table is not in the repository), the painted spell icons option, the hotbar's ornate frame and equip mode, the shader as the real GLSL, a class icon on the create window, the helper's preset hotkey, per-entry icons and a separate Admin button in the top menu, the top menu on the login screen. Nothing here ran against a live server or a live website; the drawing compiles in `unity/Client.Check`.
## Phase 7, track Z

Gaps of the P2 gameplay system rows of `docs/UNITY_PARITY.md`. Models are pure (`Core/Phase7Z.cs`, `Phase7ZUnlocks.cs`, `Phase7ZCraft.cs`, `Phase7ZBestiary.cs`, `Phase7ZDaily.cs`, `Phase7ZDps.cs`, `Phase7ZSupports.cs`, `Phase7ZLoadouts.cs`, `Phase7ZMarket.cs`, `Phase7ZOutfits.cs`, `Phase7ZPvp.cs`, `Phase7ZInspect.cs`, `Phase7ZCodex.cs`), the glue is `Unity/Windows/Phase7ZWindows.cs` plus edits in the windows of each row. Texts: `Core/LocPhase7Z.cs` (the market, gem and travel wording follows `client_chaos_locale/pt_br.lua`). Tests: `Core.Tests/Phase7ZTests.cs`.
- Auto Target: `ReachCache` asks the host for the steps (A* on the known tiles, other monsters do not wall one off, at most 16 steps) and for a clear line (`SightLine` over the `BlockMissile` tiles); a tick shares 4 searches, an answer lives 600 ms and is still used up to 3 s when the budget is spent. `HelperEngine.Reach` plus the config options `autoTargetPriority` and `autoTargetReachable` (both on by default, in the helper window's Auto target tab) filter the candidates and the lock.
- Skills window: the seven profession rows under a Professions title (`CraftSkillRows`), shown once the 0xA1 packet carried a value.
- Go to NPC: `GameWindow.TravelKey` puts a title bar button on the Stash, Boss Spawns, Candlemarks, Gambler and Professions windows (Factions and Conquest had theirs).
- Outfit window: the owned entries, then the wardrobe's locked ones in grey with how to get them, an Only what I own box per list (PlayerPrefs `chaos.outfit.onlymine.<kind>`) and a have / all count (`WardrobeView`). Clicking a locked row only shows its tip: the main client shows it on the character for a few seconds, Unity does not.
- Codex: the Item Finder page has a Codex button (`CodexLinks.ItemIndex`), a right-click on a modifier of the crafting bench opens its page, the guide has a Gems page (`GemGuide`: the server's gemguide message, numbers only). `CodexText` is the number-to-%s lookup of `codextext.lua` over `CodexTextData.cs`, generated by `python3 -I unity/tools/gen_codex_text.py` (`--check` in the Unity workflow) from the Codex blocks of `pt_br.lua`; only the pt-BR language uses it.
- Task tracker: `TaskTrackerWindow` (not in the Windows list) opens by itself while a task is active; the Hunt menu has Kill Tasks (opens the Bestiary on the tasks tab) and Task Tracker (`act:killtasks`, `act:tracker`). Saved: `chaos.bestiary.tracker`, `chaos.bestiary.tracker.folded`.
- Daily: `DailyGate` holds a login window while a modal dialog or the patch notes are open, `DailyAnchor` closes it when the player walks more than 3 tiles from where it opened (a jump moves the anchor).
- DPS meter: row icons by `DpsIcons.Spec` (the spell's cell, the rune's sprite; the main client's own pictures are drawn as a coloured glyph), the corner handle resizes (180 x 110 to 600 x 700), position and size go into the settings JSON.
- Spell supports: a rune of the list or an item of a bag is dragged onto a free socket of the selected spell (`SupportDrop`), the hotbar slot of a spell with supports has one pip per rune and the tooltip lists them, the spellbook details have the supports line.
- Loadouts: `HotbarProfiles` keeps the 12 hotkey slots as the action bar profile of a loadout slot ("Loadout N"; PlayerPrefs `chaos.hotbarprofile.<name>.<profile>`), saved after a Save, put back after a Load.
- Orb Exchange and Market: `PriceChart.Rects` is the chart of `orbexchangeview.lua` (a step line and volume bars); the Orb Exchange book has it under the order list, the market has a `RowKind.Chart` row. The market's Prices button, the row marks, the suggested price and the far-price warnings are `MarketPrices` (`marketpriceview.lua`); a bag item dropped on the Sell tab is matched by its per-item id, else by look and count.
- Bounty and Dungeons: the creature's and the boss's outfit (`OutfitJson`: the bounty spelling `type`, `head` ... and the dungeon spelling `lookType`, `lookHead` ...).
- Scorched Marches: the safe exits and the shrine are flags on the minimap while the zone is entered.
- Inspect: the View tree button opens the inspected tree read-only in the passive tree window (track Y, `PassiveTree.ShowOther`); `InspectTreeView` in `Core/Phase7ZInspect.cs` keeps the lit-node maths, tested.
- Charms: a charm item dragged from a bag onto the grid is placed where it falls.
- Crafting table: the tooltip of opcode 91 is the rich item tooltip on the row and the detail header.
- Transmog: a 64 px live preview of the equipped item drawn as the picked look.
- Not done: Market Modifiers filter (typeahead over the Codex), per-shape charm slot art, the helper's Support tab timer section and buff duration (there is no buff bar rule in Unity), the Codex search in pt-BR. Nothing here ran in a Unity player or against a live server (the drawing compiles in `unity/Client.Check`).

## Phase 9, track D: outlines and shaders of three rows

Rows of `docs/UNITY_PARITY.md`: game_itemrarity (done), game_cosmeticfx (done), game_visualfx (partial, shorter gap list). Rules in `Core/Phase9D.cs` (tests `Core.Tests/Phase9DTests.cs`), glue in `Unity/ChaosApp.Phase9D.cs`, shaders in `Resources/Shaders/ChaosFx.cginc` and the two surface shaders. pt-BR texts: `Core/LocPhase9D.cs`.
- Rarity outline of items (`ItemGlowFx`): the engine's soft glow of the main client (base patch 0044: reach 3 sprite pixels, falloff by smooth step, opacity 225 of 255, minimum rarity Uncommon, Legendary and up pulse 0.5 to 1 in 2.2 s) as the silhouette at rings of one pixel, outer ring first (24 copies; eight per ring). A mesh view cannot grow a quad inside the atlas, so the engine's one growing pass becomes steps.
  - Classic view: `MapView.DrawItem`, mode Solid of `Chaos/MapFx`, falloff and pulse in the alpha. Without the shader the older four tinted copies stay.
  - HD-2D (`Hd2dView.AddItem`) and live view (`FrontLiveView.AddItem`): the copies sit 0.004 behind the upright sprite, mode `FX_ITEMGLOW` of `ChaosFx.cginc` (flat colour, unlit; the strength channel carries the pulse period in 4 s units; the falloff is in the colour because both shaders cut out by alpha). The live view's batches gained the second UV set and the colour list (`UV2`, `Col`: one entry per vertex on every path, a test counts them).
  - Divine: the item's own sprite is drawn with `FX_METAL`: the haze metal of the store families in tint #22e5ff at strength 0.5 (`itemrarity.lua` DIVINE.metal) and a bright band that sweeps across. The main client's own metal shader is not in the repository (the Lua only names it, `item_metal_cyan`), so the look is Unity's reading of it. The classic view draws it too.
  - `ItemGlowReal` of each scene view says the shader is in use; `DrawItemRings` (the ground ring of phase 8 track A) then stays off. It is the fallback when `Hd2dSprite` is missing, and a thing lying flat keeps it out of the glow (rarity items stand up).
- Creature outlines in the live view: `FrontLiveCreatures.ApplyOutline` shows eight copies of the creature's picture behind it (`FrontArtSprite` mode Solid, unlit, `_FxTop` for the gradient of bought outlines). The pulse and the alpha go into the colour. The hit flash is the sprite shader's hit modes (`Phase8CLook(c, ok, ok)` with `FxShaderOk`); the soft disc and the glow picture stand down (`LiveFxOn`).
- Hover outline: `OutlineRules.Of` has the third kind (faint white, one pixel, steady; target and follow win). Option hoverOutline (off by default, as in the main client), found by `HoverCreatureId` (label box in the scene views, tile in the classic view).
- Spell light (`SpellLightFx`, `SpellLightState`): the id lists, colours and numbers of `visualfx_logic.lua` (13 themes, 12 lights, 320 ms, 90 ms dedupe, 12 % floor). `VisualEffects.OnFx` feeds it from every effect message. HD-2D: Unity point lights put in front of the scene's lights (`Hd2dView.SpellLights`, at most 4). Live view: frame lights (`FrontLiveView.FrameLights`, picked before the layout lights). Classic view: a faint coloured disc, as the immediate-mode GUI cannot add light. Option spellLight (on).
- Spell effects from the art file: the classic view draws the magic effects of the pair frame by frame (`SpellFxTrack`, `DrawSpellFx` over `DrawPackEffect`): the dat has them, the view needed only the list of what plays. An effect the pair lacks is forgotten; the level-up effect and the beams keep their own paths. The live view keeps its own look (`FrontLiveFx`).
- Added in phase 15 track B (below): glowing effects and light added to the classic map. Nothing here ran in a Unity player: the shaders compile only in the CI Unity build, and `Phase9DTests` checks their text, the mode numbers and the one-entry-per-vertex rule of the mesh paths.

## Phase 15, track B: additive effects and light of the classic view

Row game_visualfx of `docs/UNITY_PARITY.md` is done. Numbers: `Core/Phase15B.cs` (`AddFx`, tests `Core.Tests/Phase15BTests.cs`), glue: `Unity/ChaosApp.Phase15B.cs`, shader: `Resources/Shaders/ChaosAdd.shader` (plain vertex and fragment, `Blend SrcAlpha One`, `ZTest Always`, `Cull Off`; found by `Resources.Load`, so no always-included list is needed).
- The immediate-mode GUI has no additive blend, so during `EventType.Repaint` the classic view calls `Graphics.DrawTexture(rect, tex, uv, 0, 0, 0, 0, colour, material)` with the `Chaos/Add` material. `Graphics.DrawTexture` ignores the GUI clip, so `AddFx.Clip` cuts each quad and its texture rect to the map rect.
- Glowing effects: `AddFx.Glows` is `visualfx_logic.lua` `L.glows` (fire, energy, holy and arcane themes, not ids 5 and 6; 86 ids, a test pins count, first, last and sum). `DrawPackEffect` has an `add` flag; `DrawSpellFx` sets it for those ids while the option Light around spell effects is on, as in the main client.
- Spell light: the coloured soft disc is added (`DrawSpellLightAdd`, alpha `AddFx.LightAlpha`, gain 0.7), so it brightens a dark map. The faint 0.32 tint (`DrawSpellLightDiscs`) stays as the fallback when the shader is missing or `CHAOS_NO_FX_SHADERS` is set. Options unchanged.
- HD-2D and the live view are untouched (point lights and frame lights).
- Untested: nothing ran in a Unity player. The group offset of `Graphics.DrawTexture` inside the map group, the shader compile and the look of the gain are for the CI build and a visual check.

## Phase 8, track C: shaders of the visual effect rows

The effect rows of `docs/UNITY_PARITY.md` (game_chaosshaders, game_nameshaders, game_levelwings, game_lootbeams, game_cosmeticfx, game_visualfx) now draw with shaders.
The GLSL of `client/overlay/data/shaders` is ported to built-in pipeline shaders in `Assets/Chaos/Resources/Shaders`:
- `ChaosFx.cginc`: one HLSL function per effect family, shared by the three views: the store families (haze, waves, pulse, sparks), the eight Chaos outfit shaders,
  hit white and hit red, the one colour silhouette of an outline, the water and lava ripple. The mode numbers are `FxMode` in `Core/Phase8CFx.cs`
  (`Phase8CTests` reads the defines and fails when they differ).
- `ChaosMapFx.shader` (`Chaos/MapFx`): a drop-in for `Sprites/Default` on the classic map mesh. The second UV channel carries mode, strength and the cell corner,
  mode 0 is the plain sprite. `MapView` sets it per quad: a creature's outfit shader or flash, the silhouette ring of an outline, a water or lava ground.
- `ChaosGrade.shader` (`Chaos/MapGrade`): colour grade, vignette, area mood and soft glow (bright pass, two blurs, screen blend) as an image effect, `MapGradePost`
  on the classic camera. While it draws, the weather's flat mood tint stays off.
- `Hd2dSprite.shader` and `FrontArtSprite.shader` call the same function: the HD-2D batches carry mode and colour per vertex (`Hd2dView`), the live view's
  creature materials carry `_FxMode`, `_FxStrength`, `_FxTint` (`FrontLiveCreatures`).
- The numbers (colours of the 26 outfit shaders, the grade and bloom values, the liquid ground ids, the outline colours of the 13 bought arts, the pulse of the cooldown flash)
  live in `Core/Phase8CFx.cs` and are tested against the Lua files; the Unity glue is `Unity/Phase8CFx.cs` (`FxShaders`, `MapFxLook`, `Phase8CPrefs`, `MapGradePost`)
  and `Unity/ChaosApp.Phase8C.cs` (what each creature asks for, the pack effects, the cooldown pulse).
- Level-up wings and loot beams are the effects of the client pair (ids 4047 and 4090 to 4101) drawn from the dat frame by frame (`PackFx`); the corpse beams also come
  from the loot filter's `beam` message (opcode 238). Without these effects in the pair the old drawn wings and beams stay.
- Options (Options > Visuals): Colour grade and vignette, Soft glow (off by default), Living water and lava, Outfit shaders on characters.
- Fallbacks: every shader is looked up by `FxShaders` (Resources, then `Shader.Find`; `CHAOS_NO_FX_SHADERS=1` turns them off). When one is null the view draws as before:
  the plain sprite, the soft disc for a hit, the glow picture for an outline, no grade.
- The shaders are compiled only by the CI Unity build. `Client.Check` and `Core.Tests` do not see them; `Phase8CTests` checks their text (braces, includes, no GLSL left, names, defines).
- Name shaders of other players: nothing to port. The server has no opcode 96 handler and no base patch puts a shader in a creature packet, so the main client draws only its own (evidence in the `game_nameshaders` row of `docs/UNITY_PARITY.md`). The row is done.
- Left (see the rows): the spell light and glowing spell effects (the classic view draws no spell effects from the dat),
  the hover outline, outlines and the flash shader in the live view.
## Phase 8, track B

Gaps of eleven P2 partial rows of `docs/UNITY_PARITY.md`; eight rows are done, three stay partial with a shorter gap list. Pure logic: `Core/Phase8B.cs` (ground rings, charm slots, effect icons, overlay keys, the Customise Character view), `Core/Phase8BMarket.cs` (market modifiers), `Core/Phase8BLayout.cs` (open backpacks); glue: `Unity/ChaosApp.Phase8B.cs` and edits in the windows of each row. Texts: `Core/LocPhase8B.cs`. Tests: `Core.Tests/Phase8BTests.cs`. Pictures come from client/overlay through the OverlayFiles loader; the workflow copy list (`unity-prototype.yml`) gained the module `game_cosmetics` (effect icons) and `images/chaos/charmslot_*.png`.
- Market: the Modifiers section of Browse is rows of `Input` (typeahead) and `Combo` (the matches, the first one chosen as you type) over `ModCatalog` (the Codex entries `mod:` and `power:`, a power is the modifier `chaos_mod_<power>`), lowest value, lowest tier, all or at least N, sockets, quality, four flag buttons. `MarketMods.Request` is the filter the server reads (limits from the `meta` message), `MatchedMods` adds "Matches: ..." lines under a Browse tooltip (`SocialRow.TipExtra`), a buy order takes the Browse rows with Use Browse modifiers and shows them in its sub line (`FilterText`). The text boxes wait for Search, the combos and flags search at once.
- Helper Support: `SupportContext.BuffActive` reads `BuffBar.ActiveNames` through `IHelperHostBuffs` (null while the server's list has not come: the older duration rule), `Hasted` the player state. A vigil the bar showed on that drops without our cast settling is the player's switch: after two seconds its row is unticked (`HelperEngine.ConfigDirty` makes the window save). Two vigils in one tick, or a drop within 2 s of a death, login or teleport (`NoteClear`, 10 s at a login) are not. Timer rules: `AutoPlanFull` (a fight buff with no free Support row), saved in the helper JSON under `support.timers`, cast by `TimerTick` through the same rate guard when no Support row went out.
- View: `FrontLive.Window` and `Hd2dWorld3d.ViewHash` read `World.Range`, the HD-2D camera and `ViewMaxRows` follow the rows; the far plane of HD-2D is 260. A wide aware range makes more floor and props to build in the live view (the build cost grows with the area).
- Look preview and Customise Character: the preview uses `DrawOutfitFx` (a `Mount` layer under the rider, the rider up by the mount's displacement; this is Unity's reading of `Outfit::draw`, not measured against the engine; tall auras are drawn behind the body). The window is now a card grid: categories, search (`ExtrasView.Filter`), card hover previews the glow, footprints or plate frame (`Bundle` of the chosen options), layer boxes, Equipped now.
- Ground effects: `MapView.Flats` (ring and glow quads in the tile's turn) and `FrontLiveFx.DrawGrounds` (face-up quads on the floor); `GroundRing` has the size, fade and the two 32 x 32 alpha pictures.
- Map overlay keys: `OverlayKeys` and `KeyRepeat`. Tab was the chat's next channel when no field was edited, it is Ctrl+Tab now (Tab in the chat line still steps), as the main client moved it.
- Open backpacks: `ContainerMemory` (pending uses from `GameSession.ItemUsed` matched by item id within 3 s with the window that opens), `ContainerRestore` (one open every 150 ms, 2 s wait, transient parents closed again). Saved in PlayerPrefs `chaos.containers.<name>`, never while the restore runs; `chaos.rememberbackpacks` 0 turns it off (no options row yet).
- Info lift: `InfoLift.ForView` is 0 in the HD-2D and live views (their labels are at the figure's top).
- Not done: side panels and window sizes of the layout (Unity has neither), the effect stage and card layout of the look preview, the colour palette tabs and the outfit, mount, wings, aura and shader categories of Customise Character (in the Outfit window), HD-2D (not live) draws no map effects at all. Nothing here ran in a Unity player or against a live server (the drawing compiles in `unity/Client.Check`).
## Phase 8, track A

Gap lists of the P0 and P1 partial rows of `docs/UNITY_PARITY.md`. The rules are pure (`Core/Phase8A.cs`, `Phase8ATip.cs`, `Phase8ATree.cs`, tests `Core.Tests/Phase8ATests.cs`); the drawing is `Unity/ChaosApp.Phase8A.cs` and `Unity/Windows/PassiveTreeWindowPhase8A.cs`. pt-BR texts: `Core/LocPhase8A.cs`.
- Hotbar: `HotbarFrame` draws the main client's art (body with gem, slot frame, ready frame, socket, key box; the files of `client/overlay/modules/game_hotbar/images`) and keeps the plain fill when a file is missing. Seen bug: the Q and E key labels were cut in the demo tour (they read as O and F). The label box is now `HotbarFrame.KeyLabel` (as tall as the font needs, 16 px for 10 px text), the style has no padding and `TextClipping.Overflow`. Not seen in a Unity player: the cause (a padded skin label in a 14 px box) is inferred from the symptom, the fix does not depend on it. Equip mode: `ItemMode.Equip` (saved as mode 4), `IHotbarEquipHost.IsWorn`, outcome `AlreadyWorn`.
- Painted icons: Options > Visual, key `chaos.painted`, off by default. Spells (`spells_painted/<cell>.png`), buffs (`buffs_painted/<name>.png`) and the tree's keystones and masteries (`painted_nodes.png`, cells from `PassiveTreeIcons.json`). Stock spell icons stay impossible (the base client's table is not in the repository).
- Toasts: a press pauses the timer (`ToastPause`, `Toast.PausedAt`), a phone keeps only invitations (`ToastCenter.Phone`), the danger window has a close button.
- Ground labels in HD-2D: `TileScreenPx` projects the tile through the HD-2D camera (`Hd2d.WorldX` and `WorldZ`).
- Rarity: live and HD-2D draw a ring on the ground under the rarest item of a tile (`RarityGlow`, a drawn ring texture, same colours and pulse, Divine shimmers). The sprite outline and the metal shader are not ported there.
- Monster size: `FrontLiveCreatures.CreatureScale` and `Hd2dView.CreatureScale` (set from `MonsterScaleFor` each frame) scale the quad of a monster; the HD-2D mesh scales about the feet (`SceneScale.About`), the label head follows.
- Tooltip: `TipCard.Build` is `L.card` of `tooltiplogic.lua`, `TipCardLayout.Plan` lays it out with a measure function the Unity side gives (`ChaosApp.PlanCard`, `DrawCard`). `TipLines.Out`, `SetLines`, `Range` and `ChargesText` became internal for it.
- Top menu: `TopMenuIcons` (entry text to icon; the tests check that every entry of `TopMenu.Categories` has one and that the files exist when the client folder is there), the Admin button after Windows for staff (`TopMenuAdmin`).
- Helper: `HelperPresetKey` (key per character `chaos.helper.presetkey.<name>`, no default, validity rules, `Cycle`), button in the presets bar.
- Store: `StoreTryPanel.PlanOf`, `LookPreviewWindow.TryUntil`, `ChaosApp.TryLookPreview`.
- Passive tree: `unity/tools/gen_tree_data.lua` now also writes the icon key (`k`), the class variant icon keys (`ik`), the group (`g`) and orbit (`b`) of each node and the group centres into `PassiveTree.json` (about 140 KB more), and `PassiveTreeIcons.json` (the clip of each used icon key, the painted cells). `TreeIcons`, `TreeNodeArt` (sizes and frame files of `passivetree.otui`), `TreeArcs` (the arc round the group centre when both nodes share group and orbit and the short way is under 0.9 pi). Panels: Trials (`TreeTrials`), Auto build (`AutoBuild`, its preview feeds `PassiveTree.PreviewNodes`), Paragon Mastery (`ParagonPanel` partial: `MasteryRows`, `Exchange`). Toolbar buttons Trials and Auto build, button Masteries in the Paragon panel.
- Not done: the top bar on the login screen, Alt+letter menu shortcuts (no new hotkeys), the Developer entries, the end caps and handle of the hotbar frame, the sprite outline of rarity in the scene views. Nothing here ran in a Unity player or against a live server (the drawing compiles in `unity/Client.Check`, the rules are tested on fakes).

## Phase 9, track E

Outfit and look UI: the rows `game_outfitextras`, `game_lookpreview`, `client_chaos_topbar` (login screen), `game_chaoslayout` and the Outfit window of `docs/UNITY_PARITY.md`, all done. Pure rules: `Core/Phase9E.cs`, tests `Core.Tests/Phase9ETests.cs`, glue `Unity/ChaosApp.Phase9E.cs`, `Unity/Windows/OutfitExtrasWindow.cs`, texts `Core/LocPhase9E.cs`.
- Customise Character: `ExtrasLook` has the category list (outfit, mount, wings, aura, shader, colors, then the cosmetic rows; wings, aura and shader only with the Chaos lists), the picture cards (`WardrobeView` rows, None first, search, Only what I own), apply / current / card look of customisecore.lua, the 7 x 19 palette with its four tabs and the addon bits. The window asks the server for the outfit window on open (0xD2) and starts from the 0xC8 look; Apply sends 0xD3 (a layer box left off sends none) and then the cosmetics. The Outfit window does not open on the packet while this window is open. No wire change: the id widths of the packet are still the live-run check of the Outfit window row.
- Effect stage: `PreviewStage` is the stage of lookpreview_core.lua (steps of a skin's `play` list, timeline, scene of a spell or a kill, missile pattern, extent, layout). `ChaosApp.DrawEffectStage` draws it tile by tile from the dat (`Effect`, `Missile`) and the atlas: ground effects under the creatures (`GroundFx`), the troll (look 15, fades in a kill scene), the character facing east, the rest over them. `DrawOutfitFx` got a `fixedCell` so a creature is drawn at the stage's tile size. Used by the look preview window (Compare with default), the Cosmetics Preview button for rows with a `play` list and the Customise Character cards under the pointer.
- Cards: `LookCards.Layout` is cardLayout (scales 3, 2, 1.5, 1, feet centred); `DrawLookCard` draws a look at it. The Outfit window's list rows and the Customise Character grid use it.
- Login bar: `LoginMenu` lists the System entries the main client marks `offline` (Options, Sound, Join Discord, Credits, Exit); `LoginBarGui` draws a System drop-down at the top left of the login screen and the character list, and a small options window (language, sound, visual and layout pages) and the credits list. No Developer entries, no Alt+letter keys.
- Window sizes: `GameWindow.ResizeGrip` (a grip in the bottom right corner, a double click goes back), `WindowSize` (minimum 160 x 100, at most the screen), `WindowLayout.NoteSize` (two more numbers in a window's entry, only for a window the player resized). Windows that size themselves have `Resizable => false`.
- Not run in a Unity editor or against a live server: the drawing code is only compiled (`Client.Check`). Approximations: a creature's box on the stage is the stock look's; no Walk switch.

## Smooth 8-direction walking (phase 18, track M1)

Walking glides at a constant speed in all four views (classic, HD-2D, live front-art, 3D) and takes 8 directions. The server stays tile based and authoritative. Pure logic: `Core/SmoothWalk.cs`, tests: `Core.Tests/SmoothWalkTests.cs`.

What made it hitch: a step was sent only when the server had answered the last one and the glide was over, and a glide began when its answer arrived. Each tile cost one round trip of standing still. The camera follows the player's drawn position, so it stopped as well.

What it does now:
- Pre-walk. The next step goes out `WalkTiming.PreWalkLeadMs` (90 ms, at most 60% of a step) before the current glide ends, up to `MaxPending` (2) steps in flight. The server queues the next step of a walking player.
- Prediction. `StepPredictor` keeps the steps sent and not confirmed (`Creature.Pred`). `WalkMath` draws them at once, one after the other, so the player and the camera glide without waiting. A step onto a tile the client thinks blocked is sent but not drawn (`GameSession.Walkable`).
- Reconcile. The answer (0x6D) keeps the predicted start, so nothing moves. A move that was not predicted, a cancel (0xB5), a teleport (0x64), a floor change or no answer in 1.5 s clears the prediction and the player is where the server says.
- Other creatures and auto-walk. `WalkChain` starts a confirmed move when the last glide ends (early), or up to 25% of a step (60 ms at most) in the past when it is a little late. A creature whose moves come on time never stops. A move later than that stands for the delay (no render buffer).
- Camera and views read `WalkMath.Drawn` / `Between`; the live front-art picture follows the same function through the game clock.
- 8 directions. Held keys (WASD, arrows, numpad 8 4 6 2) fold into one mask, two keys make a diagonal, opposite keys cancel, numpad 7 9 1 3 are diagonals. The first key of a pair waits 45 ms for the second (`WalkInputState`) so W then D does not send a step north first. A held mouse button walks towards the pointer in 8 sectors of 45 degrees with 6 degrees of hysteresis (`WalkInput.Sector`).
- Diagonal step time is one constant, `WalkTiming.DiagonalNum / DiagonalDen` = 7 / 5, the server's `PLAYER_DIAGONAL_STEP_NUM / _DEN` of `server/src-patches/0018-movement-speed.patch`. It applies to players only (`WalkTiming.IsPlayerId`): monsters and NPCs keep the stock 1x diagonal on the server, so here too. The path finder costs a diagonal with the same constant (14 against 10).
- No "Smooth walking" option: it is always on.
- A recorded video of it in all four views, with the numbers: see "Walking video".

Not tested: on a live server (round trip, the server's queue of steps), with a real gamepad or touch, in the Unity player.

## Window smoke run

Phase 10, track F. Almost every window of phases 1-9 only compiled until now. `ChaosUnity -chaosWindowSmoke OUT_DIR` runs the app in the CI player, logs in to the demo tour's fake server and opens every window once. A report, not a gate.
- Steps, in order (`Core/Phase10F.cs` `WindowSmokePlan`): the login screen, its System bar, the four pages of its options window, the credits; the character list and its bar; every top menu drop-down (`menu:`) and every More sub-menu (`more:`); every window class of `ChaosApp.MakeWindows` in registry order (`win:`); every Info page (`info:`, the menu's pages and all `ChaosInfo.Pages`); every page of the Options window (`options:`). One step at a time: all windows and menus close, the step opens, 4 frames draw, the screenshot is taken, the step closes. Window fade is off during the run.
- Per step (`ChaosApp.Smoke.cs`): every Unity log line goes to the open step (`Application.logMessageReceived`; a line between steps goes to `background`), plus a try/catch around the open. `SmokeLog.Classify`: exception, layout (`GUI Error`, `Getting control`, GUIClip and layout group messages, also as exceptions) or logged error. The same message and first stack line twice is one issue with a count. The window's rect is checked at 1280x720 in UI units: `zeroSize` (a side under 2) and `offScreen` (any edge more than 1 outside). `openAtEnd` false means the window shut itself while drawing.
- Output in OUT_DIR: `window_smoke.json` (`summary`, one entry per step with `name`, `kind`, `frames`, `offScreen`, `zeroSize`, `openAtEnd`, `rect`, `exceptions` [{kind, message, stack = first stack line, count}], and `background`), and `window_smoke_sheet_1.png`, `_2.png` and so on: 1280x720, 24 tiles per sheet (6 x 4, `SmokeSheet`), each tile the crop of the window (rect plus 8 px) under a label with its name and flags (EX exceptions, GUI layout errors, ERR logged errors, ZERO, OFF, SHUT); a red border marks a step with a problem. The sheet is drawn by IMGUI in front of the app and captured like a frame.
- Log lines: `chaos window smoke: N windows, M with errors` (M counts steps with any problem, off screen and empty rects included), then a detail line with the totals. Exit code 0; 1 only when the run itself broke (login failed, no world after 300 s, over 1500 s, no screenshot).
- CI (`unity-prototype.yml`, step "HD-2D screenshots"): after the screenshots and the tour (and its fallback) a second, short player run `-chaosWindowSmoke "$out"` writes `player_smoke.log`, the json and the sheets into `hd2d-shots`. The tour video is not touched: the smoke is its own process. After the video the step prints the player's summary lines and every window with a problem (exceptions with the first stack line, layout errors, off screen), and an Actions warning when there are any. It never fails the job. Next to `-chaosDemoTour` or `-chaosHd2dShot` the smoke flag is ignored (those run instead).
- Tests: `Core.Tests/Phase10FTests.cs` (order, classification, rect checks, sheet maths, json round trip) and `Core.Tests/FakeModulesTests.cs` (the responder). Locally only the pure parts run; the player part runs in CI. Set `CHAOS_SMOKE_SAMPLE=FILE` to have the tests write a sample json.
- Module responder (phase 11, track G; `Core/FakeModules.cs`, `FakeGameServer.ModuleResponder`, on only with `-chaosWindowSmoke`, the demo tour video keeps its server): a window opens, asks its module (`open`, `list`, `fetch` ...) and the fake server answers with a small sample message set in the server's JSON shape. Each message names its server file (`Source`); `Core.Tests/FakeModulesTests.cs` feeds every sample to a real `GameSession`, checks the state is not empty and checks that every key is in the cited `server/data/scripts/chaos` file. Over 8192 bytes a message leaves in parts like `Chaos.send` (`ExtChunks.Split`). A step stays open until its answers are in (no new extended message for 3 frames, 60 frames at most).
  - Covered (opcode, window): 250 achievements, 253 bestiary (summary, list, entry, board, tracker), 198 charms, 227 season pass (state, tiers), 246 season (overview, journey, chapter), 207 daily, 117 weekly chest, 225 cosmetics (state, style, colours, wardrobe), 212 transmog (state, looks), 254 pets, 195 professions, 232 crafting bench, 91 craft tables (fetch, money), 241 hunt tracker, 178 goals (goals, tracker), 252 guild, 197 guild wars, 208 party finder (init, list), 160 group queue, 214 Infinity Tower window (open, state; flat messages); base protocol 0x97 channel list answered with 0xAB (3 channels). Phase 12, track H (`Core/FakeModulesP12.cs`): 60 bank (openBank: open), 110 stash (Stash: make SendItems gives tabs and addItems, SendCategories, Open), 218 store (init: category_groups and categories with the status block, get_page: category_page), 221 market (open: meta, browse: page, sellable, mine, history, orders), 109 Dungeons (fetch: dungeon x2, solo, group, list), 213 Raid (open: info with the vendor stock, journal), 223 bounty (open: board, 2 bands, 4 contracts), 229 leaderboard (open: meta, get: board), 216 auto loot, 226 pouches (open: settings, as_open: autoseller), 239 town portal, 193 Marches window (open: state without confirm). Server files cited: bank, stash (+ stash_core), shop, market (+ market_core, market_orders_core), dungeons, raid (+ raid_core), bounty, leaderboard, autoloot, pouches and autosell, townportal (+ core), pvpzone.
  - Context HUDs: the smoke sends the push from the fake server before the step (`FakeModules.Context`), waits for the window to open and clears it after (the server's end message where there is one, then `Endgame.Clear` and `RiftHud.Hide` in the player): Infinity Tower panel (214 state), Dungeon counter (109 start), Raid HUD and call-out (213 hud, alert), Descent HUD, offer and shop (205), Invasion HUD (251), Siege HUD (233), Arena HUD (236), Battleground HUD and scoreboard (200 hud, end), Marches confirm and HUD (193 state with confirm, hud), Rift (228 start), Ready check (160 check), Task tracker (253 tracker). The Bot HUD is classified `context` (json `context` = the reason, flag `CTX`, not an error, `summary.context` counts them): it opens from the helper's own client setting, no server message drives it. A drivable HUD whose window does not open after the push is `context` too.
  - Every How it works card counts as seen for the character (`HowItWorksWindow.MarkAllSeen`, in memory, nothing saved), so no first-open card covers a window.
  - Still empty after phase 14 (nothing answers or the window needs a real situation): spellbook beyond the tour's, helper book, NPC and item tooltips. Streamer, Performance, Screenshots and Credits read local data and were never empty. The waystone window (202) has no request: the device pushes it open, so it is a context (`WaystoneWindow`, source `server/tools/patch_waystone_hideout.py`). Add a module by builders in `FakeModulesP13.cs` (`Phase13Modules`, `Answer13`), `FakeModulesP12.cs` (`Phase12Modules`, `Answer12`, `SampleData` for a request body) or `FakeModules` and an entry in the catalog; `Core.Tests/FakeModulesTests.cs` checks every key against the cited file and the state the Unity parser keeps.
- Not covered: windows that wait for a server reply and are not listed above draw their empty state (the demo tour's script keeps playing during the run); menu actions (`act:` entries: Kill Tasks, Task Tracker, Join Discord, Log out, Exit) are not run, their windows are opened by class; windows only reachable from inside another window (confirm boxes, pickers) and states that need input (hover tooltips, drags, typing) are not drawn; the front-art live and HD-2D views are off (classic map view); windows that open themselves from `Tick` on a server message can show up in the next step's frame, their lines then count there.
- Phase 12, track H (screen fit and the checks that see a bad window):
  - Fit: `GameWindow.ClampToScreen` (default false) cuts a window's rect to the screen when it is placed and whenever it grows past it, through one shared helper (`GameWindow.FitToScreen` over `Core/Phase12H.cs` `WindowFit.Fit`: no side larger than the screen less a 4 unit margin, no edge outside). It is on for every `EgHudWindow` (tower panel, dungeon counter, raid HUD, descent, invasion, siege, arena, battleground, Marches HUD and the Marches rules box) and for every window that sizes itself (`Resizable` false: bot HUD, party frames, hotkey bar, task tracker, info data windows, raid call-out). The other windows keep the older screen fit (`client_chaos_screenfit`: a window taller than the screen can be moved with the wheel), because their content is laid out in absolute units.
  - `PvpZoneConfirmWindow` (the Marches rules box): `Place` is at most the screen (`min(500, w - 16)` by `min(380, h - 118)`), the rules text and the two tick boxes sit in a scroll view (`WindowFit.ScrollContent`, `ViewHeight`), the Enter and Cancel buttons stay in a fixed bar at the bottom. The exact cause of the oversize rect in the CI sheet could not be reproduced without the player: the old window had a fixed 500 x 380 rect and a text measured by `Eu.Wrap` without any bound. Both are bounded now and the smoke run flags the case (see below).
  - `RaidCalloutWindow` (the "Raid" bar with no text after the fake alert push, opcode 213): not the payload. The fake `alert` is the server's `{text, kind}` (`raid.lua` `alert`) and `RaidState.Handle` parsed it and showed the call-out (4 s, `RaidView.AlertSeconds`). The window rect was 520 x 40, the body under the title bar is the window less 32, so 8 high, and the label inside it 4 high: the text was clipped away. The window is 520 x 62 now (body 30) and not resizable.
  - Found on the way: the Raid window's Vendor tab read `info.vendor` as a list, the server sends `vendor = {marks, stock = [rows]}` (`raid.lua` `vendorView`), so the tab was always empty in the real game. `RaidView.VendorStock` reads `stock` (and still a plain list).
  - Checks in every window step (`ChaosApp.Smoke.cs`, pure parts in `Core/Phase12H.cs` and `Phase10F.cs`): `OVER` (`SmokeRect.Oversize`: a side larger than the screen after the frames; `OffScreen` already covered an edge outside), `THIN` (`SmokeBody.Thin`: the body under the title bar, window height less 32, is under 24 units: no room for a line), `EMPTY` (`SmokeBody.Ink`: the screenshot of the body, sampled with a stride, has under 0.4% ink; the main colour is the busiest of 16 levels per channel and ink is a pixel more than 36 away from it; only measured when the screenshot is RGBA32/ARGB32/BGRA32 and at least 64 pixels were sampled). All three make the step a problem (red tile, flags on the label, `oversize`, `thin`, `emptyBody`, `ink` per window in `window_smoke.json`, `oversize` and `emptyBody` in `summary`, the detail line ends with `N oversize, M thin or empty body`). `EMPTY` is a heuristic: a window that only has a "Loading..." line can stay under the limit and be flagged, which is what it is for; a window with a flat panel and a few icons is not. The CI step prints the flags.
  - Tests: `Core.Tests/Phase12HTests.cs` (the clamp, the scroll maths, the thin limit, the ink share on synthetic images: text, gradient, a dot, bottom-up rows, stride, too few samples), the oversize and report counts, and `FakeModulesTests.cs` (the new answers).
- Phase 13, track G (fake server replies for the windows the phase 12 smoke found empty; `Core/FakeModulesP13.cs`, `Core/Phase13G.cs`, tests `Core.Tests/FakeModulesP13Tests.cs`):
  - New module answers (opcode, request, reply, server file cited per message; every key is checked against that file by `FakeModulesTests`, the opcode against `chaos_constants.lua` (Admin: `admin/core.lua`) and the Unity state by `FakeModulesP13Tests`): 215 Factions (open: state with 2 factions, 4 contracts, 3 offers), 167 Conquest Vendor (open: state, every tab has rows), 120 Admin (catalog: 2 categories, a dangerous action; the app asks for it 600 ms after the login and only a staff account gets an answer from the real server, so the Admin window needed no smoke change), 217 Boss Spawns (open and refresh: list and pocket), 220 Referral (open and sync: status), 163 Nemesis (get), 203 Community goal (open), 244 Patch notes (open: list and note, changelog), 171 Chronicle (open: state, mem: the Memorial data), 240 Inspect (privacy, inspect: result, equip, records), 205 Descent (open: info), 251 Invasion (calendar), 233 Guild Siege (open: info), 236 Arena (open: state with the season cards), 200 Battleground (open: state with the queue, season and vendor pages), 209 Orb Exchange (open: meta, book for the pair asked, mine), 199 Gamble, 174 Ember Cache, 206 Loadouts, 243 Spell Supports (open: state and bar), 222 Chaos Pact (open and sync), 176 Candlemarks, 238 Loot filter (sync: settings and a kill; open: settings), 192 Hideout (open: state, visits), 210 Rift atlas and 159 Waystone atlas (open: tree, unless the request says `tree: false`, then state).
  - Set up by the smoke run instead of a reply (`SetupWindow` in `ChaosApp.Smoke.cs`; the calls a player's click makes): How it works (`HowItWorksWindow.Show` of the first card; the window was empty because no card was chosen, `MarkAllSeen` stays), Inspect (`InspectName("Vex")` asks for a player, the fake server answers with the sample), Trade (`FakeGameServer.PushTrade`: base protocol packets 0x7D and 0x7E built by `FakeModules.TradePacket`, with the tour's ground ids so the item wire form matches the client's dat; the step waits for the trade to open and the window closes the trade itself when the step ends).
  - Found on the way: the server sends `open = 1` (a number) in the hunt tracker state (`hunt.lua`) and the Ember Cache state (`embercache.lua`) to show the window, and the Unity parsers read it with `Json.Bool`, which is false for a number: a server-opened window never showed. Both read the number 1 as true now (`HuntTracker`, `EmberCacheState`). `weeklychest.lua`'s header comment says the same `open = 1`, but that was stale (corrected in phase 14): the code sends `shown = 1` and `open` is a count (phase 14 track H checked it, see below).
  - Covered windows (`SmokeCover` in `Core/Phase13G.cs`): for a window step the rect of the window and the rects of the other open windows drawn after it (a later place in the window list is drawn above) give the share of its area those hide (overlaps counted once, exact union over a coordinate grid). At 50% or more the record has `covered` true and the label flag `COVER`; `window_smoke.json` has `covered` and `coverShare` per window and `covered` in the summary, the log line `chaos window smoke: covered: NAME: N% hidden by windows drawn after it`. A report only: it is not a problem and fails nothing. A raised window (`RaiseNext`) is not looked at, the order is the list order.
  - Not covered by a sample after phase 13: the Mentor window (194), the Survey (122), the Drop feed, the Battleground scoreboard: all four are covered in phase 14 track H (below). The Gamble, Orb Exchange and Candlemarks buy and order buttons are not pressed (the run only draws).
  - No new Loc keys: every text of the samples is server text; the windows draw it through their existing keys.
- Phase 14, track H (wire types and the last smoke gaps; `Core/ExtOpcodes.cs` `Json`, `Core/FakeModulesP14.cs`, tests `Core.Tests/Phase14HTests.cs` and `FakeModulesP14Tests.cs`):
  - The bug class: the server's Lua JSON encoder (the base `lib/core/json.lua`) writes a Lua boolean as `true` or `false`, but many Chaos payloads carry flags as the numbers 1 and 0 (`open = 1`, `done = 1`, `pw = 1`, `boss = seg.boss and 1 or 0`, `p = s.paused and 1 or 0`, `hc`, `ssf`, `fallen`, `records`), some values as text, an empty Lua table as `[]` (never `{}`) and a table keyed by the strings "1", "2" as an object. `Json.Bool` is false for a number, so a window the server opens that way never showed (found in phase 13 for the hunt tracker and the Ember Cache).
  - One tolerant helper set in `Json`: `Truthy(value, fallback)` and `Truthy(object, key, fallback)` (true for `true`, a nonzero number, "1" and "true" in any case; false for `false`, 0, NaN, any other text; null, a list or an object give the fallback), `AsNumber` (a number or a numeric string), `Int` and `Number` read numeric strings, `Text` reads a whole number as its digits (`NumberText`, like Lua `tostring`), `List` reads an object keyed 1, 2, 10 as the list in number order. `Json.Bool` stays strict and is for what this client wrote itself (its own PlayerPrefs files). `CF.On` (the collect models) follows `Truthy`.
  - The audit: every one of the 419 `Json.Bool` reads of `Chaos/Core` and `Chaos/Unity` (50 files) became `Json.Truthy` (a superset: the same for a boolean). About 35 typed `is bool` reads of server payloads (a `Json.Get(...) is bool b` or `as bool?`) went through `Truthy` as well: Stash access (`canWithdraw`, `canDeposit`), Endgame (`isLeader`, `current`, the killed marks, `rated`, `canEnter`), Season modes (`ssf`, `hc`, `eligible`), Charms (`active`), Professions (`on`), Transmog and Crafting (`ok`, `installed`), the passive tree (`change`), `near` of the shop windows, item tips (`set`, `bd`, `pw`), Guild (`guild`), Party finder (`title`), the loot filter (`show`, `icons`, `notify`, `hunt`, `corpse`), the Community goal (`autoEnabled`), the account (`terms`), Community admin parameter defaults, FX missiles. Left strict on purpose, because the client writes them: Audio, Visual, loot beam and Dps meter settings, the window layout, the helper config and the damage scatter prefs (all PlayerPrefs JSON written by Unity as `true` and `false`). Already tolerant before: the `CF.B` readers of the collect models, `ItemCompare`, `GroundLabels`, the hunt tracker and Ember Cache `open`.
  - Server payloads found with numbers for flags (from `and 1 or 0`, `= 1` in the Lua): `combatlog_core.lua` boss, live, share; `memorial.lua` records, fallen; `pets.lua` open; `cosmetics.lua` pulse, `cosmetics_core.lua` m, x; `groundloot_core.lua` and `lootfilter.lua` u, o, pw; `hunt_core.lua` p, bu; `season_modes.lua` hc, ssf; `achievements_core.lua` ascended, guild, tutorial; `daily.lua` Broken, TakenReward, Login; `deathrecap_core.lua` c, mp, pvp; `wardrobe_core.lua` o; `templar_aura_core.lua` p; `welcomepath_core.lua` p; `weeklychest_core.lua` done and open per activity; `hunt.lua` and `embercache.lua` open. The tests feed these shapes to the real models (`Phase14HTests`).
  - Weekly chest: the task text said `weeklychest.lua` sends `open = 1` and Unity ignores it. The code sends `shown = 1` (the first push after the window was opened by the player's `open` request) and `open` is the number of activities the character can do. The main client reads neither as a flag (`onMessage` only stores `msg.data`, the window shows from the player's click), so nothing was missing: the Unity weekly chest is the same. The header comment of `weeklychest.lua` said `open = 1 | nil`; it is corrected. `Phase14HTests` pins it: `shown = 1` is read and does not open the window, `open = 2` is the count in the chest line.
  - Not changed: an empty `data` object arrives as `[]` and the handlers that check `data is Dictionary` skip such a message (about 23 handlers). No server message of those modules sends an empty table as its whole payload that matters, but a future one would be dropped silently; the helpers above make a `[]` member read as missing everywhere else.
  - Mentor (194, `FakeModulesP14.cs`): `open` and `sync` answer the status view of `mentor_core.lua K.view` (a registered mentor with two apprentices, an invite, three shop offers, a top list), `list` the browse rows. The window opens on Mentoring. Survey (122): a context: the push `open {s = 20, max = 200}` before the step, `done` after (the way `survey.lua` opens it); stage 50 and the numbers as text are in the tests. Drop feed: the server posts a text line (`retention_loot.lua` `post`, type 19, pattern `%s (Lv %d) found %s!` with an item link), no module message exists for it: the smoke pushes the line as a 0xB4 text message (`FakeGameServer.PushText`, `SetupWindow`) and the test reads the line pattern and message type from the config file and the link through the chat parser. Battleground scoreboard: the context is a running match now (`state` with `match`, `hud` and a live `board`), the window asks `board` on opening and the responder answers; the end summary is no longer shown by the smoke (`FakeModules.BgEnd`, tested in `FakeModulesP14Tests`).
  - No new Loc keys.
