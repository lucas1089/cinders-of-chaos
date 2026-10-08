# Client base

The client is an OTClient-family engine whose wire protocol matches the server: wings, auras and outfit shaders in the outfit packets, `g_shaders.createOutfitShader` with a vertex stage (91 of the 95 server outfit shaders need it), and HD upscaling (xBRZ, scale factor 1 to 4, or a 64px `.spr`). Speed was judged from the code, not measured.

**Source.** The tree is about 300 MB (230 MB of it `data/` images and sounds), so it is not committed: `tools/assemble_client.sh <base-client-dir> <out>` takes your copy, applies `base-patches/`, drops in `overlay/` and leaves a folder to build with CMake. Not run yet.

## Patches (`base-patches/`, applied and built on Linux, see `LINUX.md`)
1. `init.lua`: server entry named Chaos, version 860 -> 1098.
2. `gamelib/game.lua`, `client_entergame`, `corelib/globals.lua`, `game_things/things.lua`: supported versions include 1098; default assets folder is `data/things/1098`.
3. `game_features/features.lua`: a 1098 profile (74 features, the usual OTClient version ladder) plus `GameOutfitShaders`, which the client needs to read the shader list. `GameOrangeNpcNameColor` does not exist in this client and was left out.
5. `src/client/protocolgameparse.cpp` (C++, `0008`): the 0x9F player-info packet reads 1-byte spell ids and no magic-shield byte when the protocol is 1098 (found by the first real login, see `LINUX.md`).
4. `client_settings/classes/dataset.lua`: HD upscaling on by default; spell effect opacity defaults: own 100%, other players 60%, creatures 80%. The sliders already exist in the options window.
6. `0018` (C++) and `0019` (Lua): short numbers (15.3k, 2.45M) above the map and in the windows and server messages; `0019` uses the globals of the overlay module `client_chaos_numbers` (see `MANIFEST.md`, "Short numbers").
7. `0023` (Lua, `mods/game_helper/helper.lua`, on top of 0015/0016): no packet burst after a long frame. The engine replays every missed 50 ms helper cycle back to back (`ScheduledEvent::nextCycle` adds the delay to the old due time) and `g_clock.millis()` is cached per frame, so cooldowns did not stop them: a 2 s stall sent ~40 cycles at once, and a heal the server rejects ("wrong vocation") never gets a cooldown and went out 20 times a second, so the server kicked for packets per second. Now a cycle in the same frame or < 25 ms of real time after the last one is skipped, and the heal spells the helper says (own heal, sio, gran sio, tio sio, mas res) are limited by `g_clock.realMillis()`: one per 200 ms, the same spell again only after 500 ms unless the server's cooldown arrives first. Heal cooldowns are 1 s or more, so normal healing keeps its timing (it only drops the duplicate cast sent while the cooldown was still on its way). Potions already set a local exhaustion and are unchanged.

## What the overlay replaces
- `game_stash` (the client's own targets a different protocol): ours, extended opcode 110.
- `game_battlepass`: ours (raw opcode 39).
- Login background: the client's own `client_background` module stays (other modules call its functions); the overlay replaces only its images `data/images/title.png` (Chaos background) and `data/images/ui/logo.png` (Chaos logo).
- `game_mainpanel`, `game_healthcircle`, `game_realminimap` and `game_sidebars` stay the client's own (the first two have alternates in `alternates/`).

## Still open
- Whether the client's engine parses the 10.98 `Tibia.dat` and the server login packet. Its own profiles are 8.60 and 15.24, so 10.98 is untested ground. The login sends OTClient version 310, which the server accepts (it needs at least 254).
- Native modules built for another protocol may expect packets the server does not send; read the terminal log on first run.
- You supply `Tibia.spr`/`Tibia.dat` for 10.98 (not in the repo).
