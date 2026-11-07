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
    - `World.cs`: tiles, stacks, creatures.
    - `Protocol.cs`: framing, login packets, the TCP connection, the login answer.
    - `Game.cs`: `GameParser` reads the server's messages into a `World`. `GameSession` adds login, guard, pings and walking.
  - `Assets/Chaos/Unity/` holds the app.
    - `ChaosApp.cs` builds everything from code at start.
    - `MapView.cs` is one dynamic mesh per frame, drawn in the stock order.
    - `SpriteAtlas.cs` is a 4096x4096 atlas of 32 px cells.
    - `Hd2dView.cs`, `Hd2dShot.cs`, `Hd2dPost.cs`: the HD-2D view (see below). Core: `Hd2d.cs`, `Hd2dDemo.cs`.
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
  `unity/tools/front_art_packs.py build PACKS_DIR OUT` takes every idle frame of each strip (64 x 64 canvases cut by the box
  around all frames, so the figure never jumps; feet on the bottom row) into `idle.png` (frames side by side, facing right) and
  `idle_w.png` (each frame mirrored, for the three west headings), each with a dome normal map `_n` and an emission mask `_e` per
  frame (glow modes per figure: the rule, every warm pixel for the fire demon, no cyan for the frost demon). The scene plays them
  at 8 frames a second (`PackFps`, each figure 3 frames apart) by the material's texture scale and offset, which the sprite, its
  shadow caster and the ground silhouettes (`FrontArtCast` reads `_MainTex_ST`) all follow; `Hd2dShot` adds
  `front_art_anim_00..15.png`, the east horde over two seconds. `seal OUT ENC` encrypts,
  `open ENC Resources/FrontArt` is the step of `unity-prototype.yml` before the build. The opened `pk_*` folders are ignored by git;
  without them (no secret) the scene leaves the extras out. 40 texels a unit (1.6 units; the 32-texel skeleton 1.0). To change the
  figures: download the packs from the owner's Drive, run build and seal with the key, commit the new `.enc`.
  `Editor/FrontArtImport.cs` keeps the pictures uncompressed, point filtered, without mips; normal and emission maps linear.
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

## Tests

```
cd unity/Core.Tests && dotnet run -c Release
```

The checks cover:
- crypto vectors shared with `server/tools/loadtest.py`;
- the dat and spr readers on synthetic files;
- the login answer, map descriptions with skip counters, moves, the east strip, turns, items, pings;
- a whole game login against a fake server on localhost. It uses its own RSA key, real XTEA and the guard handshake;
- the 3D character mapping (`CharsTests.cs`): the 21 classes against the vocation files, the monster rules over every monster name of the server
  (it prints the share per model), size, hand bones, idle clips, the label font and the line-up. The fetch script: `python3 -I unity/tools/fetch_3d_assets_test.py`.

On the real pair: `dotnet run -c Release -- probe DAT SPR OUTDIR [outfit ids...]` draws outfits.png and items.png.

Against a server: `dotnet run -c Release -- live PAIR_DIR HOST ACCOUNT PASSWORD [CHARACTER] [RSA_MODULUS_FILE]`.
It logs in, enters, takes four steps and prints the opcodes it read. The guard key is read from `CHAOS_CLIENT_KEY`
(64 hex digits). Without it the dev key is used, which the live server refuses in mode "enforce".

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

- The game login sends u16 0 as client markers.
  The server then sends no feature list and plain outfits (no wings, aura or shader).
  It sends one 0x64 map and no item attributes, and never compresses.
  An adler32 of 0, which would mean a compressed packet, is refused.
- The step time follows `server/tools/cast_relay.py` `step_ms` (src-patch 0018).
- An opcode the parser does not know stops that packet. The next packets go on. `live` lists what it read.

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
