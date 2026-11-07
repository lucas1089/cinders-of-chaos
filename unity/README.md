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
  - `Assets/Chaos/Editor/ChaosBuild.cs` is the batch build.
- `Core.Tests/` is a .NET 8 console project. It compiles `Core/` and runs the checks.
- `Client.Check/` compiles the Unity scripts (`Core/` and `Unity/`) against the engine's reference assemblies from NuGet,
  so a C# error shows on every PR without a Unity license: `cd unity/Client.Check && dotnet build`.

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
- Effects: bloom on bright pixels, tilt-shift depth of field (middle 44% of the height sharp, top and bottom blurred, by screen Y),
  exponential fog, vignette, warm grade.
- `lowQuality` (phones): keeps bloom and fog, drops depth of field, HDR and soft shadows.
- Pipeline: the built-in one with our own image effect (`Hd2dEffect.OnRenderImage`), shaders in `Assets/Chaos/Shaders/`.
  URP was not taken: its assemblies are not on NuGet, so `Client.Check` could not compile it and nothing in CI would check the URP asset
  that an editor script makes. `ChaosBuild` adds the shaders to Always Included Shaders.
- Not checked without a Unity license: the shader text (`Client.Check` compiles the C# only). Look at it once in the editor.
