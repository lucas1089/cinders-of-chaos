# Client base: Astra

Chosen because its engine is OTCv8-based, the same wire protocol as the Hellgrave Exodus server: wings, auras and outfit shaders in the outfit packets, `g_shaders.createOutfitShader` with a vertex stage (91 of the 95 Exodus outfit shaders need it), and HD upscaling (xBRZ, scale factor 1 to 4, or a 64px `.spr`). Compared with OTC-Fonticak (Redemption: extra `effect` field in every outfit packet, fragment-only shaders) and Black Talon (binaries only). Speed was judged from the code, not measured.

**Source.** You have permission to use the Astra tree and the other servers' files. The tree is about 300 MB (230 MB of it `data/` images and sounds), so it is not committed: `tools/assemble_client.sh <astra-dir> <out>` takes your copy, applies `base-patches/`, drops in `overlay/` and leaves a folder to build with CMake. Not run yet.

## Patches (`base-patches/`, dry-run applied to the Astra tree you gave me)
1. `init.lua`: server entry named Chaos, version 860 -> 1098.
2. `gamelib/game.lua`, `client_entergame`, `corelib/globals.lua`, `game_things/things.lua`: supported versions include 1098; default assets folder is `data/things/1098`.
3. `game_features/features.lua`: a 1098 profile. The ladder is the one in the Exodus client's `features.lua` (74 features), plus `GameOutfitShaders` (Astra reads the shader list only with that flag; Exodus has it implicit). `GameOrangeNpcNameColor` does not exist in Astra and was left out.
4. `client_settings/classes/dataset.lua`: HD upscaling on by default; spell effect opacity defaults: own 100%, other players 60%, creatures 80%. The sliders already exist in Astra's options window.

## What the overlay replaces in Astra
- `game_stash` (Astra's targets its 8.60 server): ours, extended opcode 110.
- `game_battlepass`: ours, the Exodus one (raw opcode 39).
- `client_background`: ours (themed login background).
- `game_mainpanel`, `game_healthcircle` stay Astra's own (ours are in `alternates/`); `game_realminimap` and `game_sidebars` also stay Astra's own, they came from there.

## Still open
- Whether Astra's engine parses the 10.98 `Tibia.dat` and the Exodus login packet. Its own profiles are 8.60 and 15.24, so 10.98 is untested ground. The login sends OTCv8 version 310, which the Exodus server accepts as OTCv8 (needs at least 254).
- Astra's native modules built for its 8.60 server may expect packets the Exodus server does not send; read the terminal log on first run.
- You supply `Tibia.spr`/`Tibia.dat` for 10.98 (proprietary, not in the repo).
