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
  - `Assets/Chaos/Editor/ChaosBuild.cs` is the batch build.
- `Core.Tests/` is a .NET 8 console project. It compiles `Core/` and runs the checks.
- `Client.Check/` compiles the Unity scripts (`Core/` and `Unity/`) against the engine's reference assemblies from NuGet,
  so a C# error shows on every PR without a Unity license: `cd unity/Client.Check && dotnet build`.

## HD-2D view (O432)

A visual proof: the same pixel-art sprites in a 3D scene, with real lights, shadows and a tilted camera. F9 switches between
the classic flat view and HD-2D; the choice is saved in PlayerPrefs (`chaos.hd2d`). F9 is also hotkey slot 9: while the hotkey bar
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
  lights). Models: the CC0 Modular Ruins Pack by Quaternius (OBJ + MTL, no textures), 19 pieces in `Assets/Chaos/Resources/Ruins3d/`
  with the pack's `License.txt` (credited in `docs/CREDITS.md`). The repo commits no `.meta`: Unity makes them on import.
  `Resources.Load<GameObject>("Ruins3d/Wall")` works in the player; `ChaosBuild.cs` does not exclude them.
- Mapping (`Core/Hd2dRuins.cs`, tested in `Core.Tests/RuinsTests.cs`): from the HD-2D layout, ground becomes a floor piece per tile
  (Floor_Standard, Floor_Squares, a few Floor_Diamond); a ground border is dropped; a blocking on-bottom upright thing (the wall) becomes
  one Wall segment per cell of width and one course per cell of height, turned to face the open side (south, east, west, north);
  a blocking upright thing that is not on-bottom (pillar) becomes a column; a light source becomes a Torch on the wall of its tile,
  else candles on a short column. Decals (carpet), loose items and creatures stay sprites. A few props (barrel, crate, pots, chest,
  skull, bookcase) stand on free tiles in front of a wall. The Hd2dView light list is unchanged. One tile is one unit (pack scale 0.5).
- Look: `Unity/Hd2dRuins3d.cs` copies the pack's materials and restyles them (`Hd2dRuins.Restyle`): stone pulled to cold grey and x 0.7,
  wood and metal dark, flames warm and emissive. Standard shader, the view's point lights and ambient, shadows on.
- See it: the `hd2d-shots` artifact of `unity-prototype.yml` (Linux target) holds `hd2d_3d.png` next to `hd2d.png` and `classic.png`.
  Same room, same camera, same post effects. If the models are not in the build the step skips `hd2d_3d.png` and says so in the log.
- Unsure until seen: which side of the pack's walls is the nicer face, and the colour balance (the restyle lifts the pack's linear
  colours with a gamma first). Both are one-line changes in `Hd2dRuins.cs`.

Limits, said plainly:
- The sprites are drawn for an oblique view. Upright walls look right only with this fixed camera: there is no camera rotation.
- Only the player's floor is drawn (no floors above or below).
- The classic UI windows are not ported to anything 3D; they draw over the scene as before.
- Lights and shadows are an approximation (shadows from billboards, no baked light). A creature's light is its dat or server light level.
- Not run in a Unity editor or player in the session that wrote it: the code compiles in `Client.Check` and the layout is tested, the look is
  unchecked until the first screenshot run.

## Tests

```
cd unity/Core.Tests && dotnet run -c Release
```

The checks cover:
- crypto vectors shared with `server/tools/loadtest.py`;
- the dat and spr readers on synthetic files;
- the login answer, map descriptions with skip counters, moves, the east strip, turns, items, pings;
- a whole game login against a fake server on localhost. It uses its own RSA key, real XTEA and the guard handshake.

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
- Effects, in shader order: tilt-shift depth of field (middle 28% of the height sharp, `focusHalf` 0.14, `focusFeather` 0.22; a light
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
