# Client base

The client is an OTClient-family engine whose wire protocol matches the server: wings, auras and outfit shaders in the outfit packets, `g_shaders.createOutfitShader` with a vertex stage (91 of the 95 server outfit shaders need it), and HD upscaling (xBRZ, scale factor 1 to 4, or a 64px `.spr`). Speed was judged from the code, not measured.

**Source.** The tree is about 300 MB (230 MB of it `data/` images and sounds), so it is not committed: `tools/assemble_client.sh <base-client-dir> <out>` takes your copy, applies `base-patches/`, drops in `overlay/` and leaves a folder to build with CMake. Not run yet.

## Patches (`base-patches/`, applied and built on Linux, see `LINUX.md`)
1. `init.lua`: server entry named Cinders of Chaos, version 860 -> 1098.
2. `gamelib/game.lua`, `client_entergame`, `corelib/globals.lua`, `game_things/things.lua`: supported versions include 1098; default assets folder is `data/things/1098`.
3. `game_features/features.lua`: a 1098 profile (74 features, the usual OTClient version ladder) plus `GameOutfitShaders`, which the client needs to read the shader list. `GameOrangeNpcNameColor` does not exist in this client and was left out.
5. `src/client/protocolgameparse.cpp` (C++, `0008`): the 0x9F player-info packet reads 1-byte spell ids and no magic-shield byte when the protocol is 1098 (found by the first real login, see `LINUX.md`).
4. `client_settings/classes/dataset.lua`: HD upscaling on by default; spell effect opacity defaults: own 100%, other players 60%, creatures 80%. The sliders already exist in the options window.
16. `0036` (`client_settings/classes/dataset.lua`, `client_settings/options/effects.otui`): two options for the level-up wings (overlay module `game_levelwings`, `MANIFEST.md`), both on by default: `levelWingsOwn` ("Level-up wings on my character") and `levelWingsOthers` ("Level-up wings on other characters"), in a new panel at the bottom of Options > Graphics > Effects. Lua and OTUI only (no C++). Applies after 0001-0035; tested in the Linux client (the panel, both checkboxes through Ok, and both options against a live level-up).
6. `0018` (C++) and `0019` (Lua): short numbers (15.3k, 2.45M) above the map and in the windows and server messages; `0019` uses the globals of the overlay module `client_chaos_numbers` (see `MANIFEST.md`, "Short numbers").
7. `0027` (C++): xBRZ 1.8 (GPL-3, from https://sourceforge.net/projects/xbrz/, xBRZ_1.8.zip) replaces the bundled 1.4 in `src/framework/graphics/`; `spritemanager.cpp` pads each sprite by 2 px with its edge pixels before scaling (1.8 treats outside pixels as transparent, which notched sprite seams) and uses `ARGB_UNBUFFERED` (no 64 MB table); local changes are listed at the top of `xbrz.cpp`/`xbrz.h`.
8. `0028` (C++): `src/framework/net/inputmessage.cpp` `InputMessage::getString` turns server text that is valid UTF-8 with non-ASCII characters into cp1252, the encoding the client draws (base NPC lines saved as UTF-8 showed "Ã§" for "ç"); Latin-1 text and anything not valid UTF-8 pass unchanged (see `MANIFEST.md` "OFL fonts", Characters). Built and checked in the Linux client.

9. `0029` (C++): movement speed, the client half of server src-patch `0018` (server/README.md "Movement speed").
   `Creature::getStepDuration` rounds a player's step up to 10 ms (not the 50 ms server beat) and makes a player's
   diagonal step 7/5 of a straight one (stock 3x). Monsters and NPCs keep the beat and step diagonally in a straight
   step's time, as the server moves them. The walk offset now spans the whole step, so a diagonal glides instead of
   moving fast and then standing. The path finders cost a diagonal 1.4 (stock 3). The constants must match the
   server's `PLAYER_STEP_ROUNDING` / `PLAYER_DIAGONAL_STEP_NUM` / `_DEN` (`server/tests/movement_speed_test.lua` checks).

10. `0030` (C++): transmog, the client half of server src-patch `0019` (server/README.md "Transmog"). Item custom attribute 8 is the client id of a look: `Item::draw` (map, inventory and container slots, trade, market, drag) and `Item::drawToImage` draw that look's thing type with its own patterns and animation; the item's id, flags, stack position, light, packets and tooltips stay its own, so moving, using and trading are unchanged. A stackable or fluid / splash look is ignored. Lua `item:getAppearanceId()` / `item:setAppearanceId(clientId)` for windows that build items from server data (`game_transmog`, `game_market`, `game_playerinspect`). Built and checked in the Linux client.

11. `0031` (C++ and `init.lua`): the signed updater's native part (`MANIFEST.md` "Signed updater"). New header
    `src/framework/util/chaosupdate.h`: Ed25519 verification through OpenSSL's EVP interface (the client already links
    OpenSSL 3 for RSA, SHA and TLS; no crypto code of our own), streaming SHA-256 and the write-dir path rule. Lua:
    `g_crypt.ed25519Verify(keyHex, message, sigHex)`, `g_crypt.sha256Encode` (existed, now bound),
    `g_resources.fileSha256 / fileSize / appendFileContents`, and `moveUpdateFile / removeUpdateTree / mountUpdateDir /
    unmountUpdateDir`, which act only inside `chaos_update/` of the write dir. `init.lua` gets `Services.update`
    (manifest URL, public key, package number, required, download link) and runs
    `modules/client_chaos_updater/bootstrap.lua` before `g_modules.discoverModules()`, so a verified update folder is
    mounted in front of the client's own files. Vectors: `tools/chaosupdate_test.cpp` (RFC 8032 tests 1-3, a manifest
    signed by `tools/make_update_manifest.py`, SHA-256, paths). Built and tested in the Linux client.

12. `0032` (`CMakeLists.txt`): the sound framework is built by default (`FRAMEWORK_SOUND` ON; the base had it OFF, so
    `g_sounds` did not exist). It brings OpenAL and Ogg Vorbis: the base's `vcpkg.json` already lists `openal-soft`,
    `libogg` and `libvorbis` (Windows); on Linux see `LINUX.md`. Needed by the loot filter's rule sounds
    (`game_lootfilter`, `MANIFEST.md`); `-DFRAMEWORK_SOUND=OFF` leaves it out again and the filter stays silent.
13. `0033` (`src/framework/CMakeLists.txt`): the Windows static build with sound. The base set
    `CMAKE_FIND_LIBRARY_SUFFIXES` to `.a` after its OpenGL lookup, so with MSVC every later `find_library` (OpenAL,
    Vorbis, VorbisFile, Ogg) missed vcpkg's `.lib` files and the configure step failed (Windows package run 11). MSVC
    keeps `.lib` there now; vcpkg's static `openal-soft` is linked as static (`AL_LIBTYPE_STATIC`, plus `ole32` and `avrt`).

14. `0034` (C++, `src/client/outfit.cpp`): rider seat on negative-displacement mounts (`MANIFEST.md` "Rider seat on
    donor mounts"). The client draws such a mount by its own displacement and the rider at its usual place, so on the
    centred donor B mounts the rider sat beside the saddle. A data-only fix is not possible: on that path the rider's
    place does not depend on the mount's data, and a non-negative displacement moves the mount twice as far as the
    rider. When the mount has a negative displacement and the Bones attribute and the rider has no Bones, the rider is
    moved by the mount's Bones pair for its direction (signed pixels, set by `tools/sprites/set_rider_seat.py`).
    Everything else draws as before (a stock mount was pixel-identical in the test); a client without the patch ignores
    a mount-only Bones attribute. Built and checked in the Linux client. Since things_custom16 each direction has its
    own seat (data only, same patch). Checked live on 2026-10-12 with 0001-0041 and things_custom17: mounts 141-145
    seated in all four directions, standing and walking; stock mount 368 unchanged (`MANIFEST.md` "things_custom16").

15. `0035` (C++, CMake, `modules/gamelib/protocollogin.lua`): the client guard, the client half of server src-patch 0021
    (server/README.md "Client guard"; overlay module `game_chaosguard` sends the Lua hello). Both login packets carry
    `0x4343 << 16 | CHAOS_CLIENT_BUILD` in their u32 client version field instead of 1098; extended opcode 189 (the
    server's challenge) is answered in C++ with an HMAC-SHA256 over the nonce, account, character and build
    (`src/client/chaosguard.h`, OpenSSL; vectors `tools/chaosguard_test.cpp`, run in CI) and never reaches Lua;
    `g_game.getChaosClientId()` / `getChaosClientBuild()` for Lua. The chain 0001-0035 applies to the `windows-assets`
    base client; built and tested in the Linux client.

17. `0037` (`client_settings/classes/dataset.lua`, `client_settings/options/interface.otui`): the option "Right-click
    equips items" (`rightClickEquip`, on by default) in a new panel after "Show Link Copy Warning" in Options >
    Interface; its `apply` hands the new value to the overlay module `game_rightclickequip` (`MANIFEST.md`), which tells
    the server (extended opcode 188; server/README.md "Right-click equips"). Without the patch the option counts as on.
    Lua and OTUI only (no C++). Applies after 0001-0036, and 0038 applies after it; tested in the Linux client (the
    checkbox through Ok turns it off on the server, `setOption` back on).

18. `0038` (C++, `src/client/outfit.h/.cpp`, `creature.h/.cpp`, `luafunctions_client.cpp`): silhouette outlines for the
    outline cosmetics (`MANIFEST.md` "game_cosmeticfx", server/README.md "Footprints and outlines"). Lua:
    `creature:setOutline(r, g, b, a, widthPx, pulseMs)` (colour 0-255, width 1-3 sprite pixels, 0 takes it off;
    `pulseMs > 0` breathes the alpha between 45% and 100%), `creature:setOutlineGradient(r, g, b, a)` (the colour at the
    top of the silhouette, after `setOutline`; the first colour is at the feet), `clearOutline()`, `hasOutline()`.
    How: `Outfit::draw` queues one `DrawQueueItemOutfitOutline` before the mount and keeps pointers to the queue items of
    the mount, the body, each addon and the rider (shaded or not, the walking frame included); at draw time it draws
    each part once more from that item's final rect and texture, grown by the width, through its own program: the
    fragment samples the part's alpha in 8 directions at 1-4 radii (clamped to the part's own frame in the sprite sheet)
    and paints only where the part is transparent and a neighbour is not. The parts are drawn after it, so lines inside
    the silhouette (rider over mount, addons) are covered and only the outer contour stays. Wings and auras are not
    outlined (the line goes under the wings); names, bars and the outfit shader are not touched (the shader still
    draws the body; the outline is a separate pass). The width is in sprite pixels times `g_sprites.getOffsetFactor()`,
    so with HD upscaling (xBRZ, `0027`) the line keeps its look; queue scaling (`setDrawScale`) and opacity apply.
    Widgets: only a widget's own preview creature (id 0, `UICreature:setOutfit`) draws it (the Cosmetics window
    sample), never a map creature shown in the battle list. Why this and not a framebuffer per creature: one extra quad
    per part with no framebuffer switch, so 40 outlined creatures cost about as much as 40 more sprites; a framebuffer
    pass would bind, clear and resolve once per creature and break the draw cache batching. Why not 8 offset copies in
    a flat colour: 8 draws per part (16 for a 2 px line) instead of one, for the same picture.
    Measured in the Linux client (software OpenGL, Xvfb): 39 outlined monsters and 2 players on screen ran 14.6-17.2 fps
    against 15.2-18.7 fps without outlines, within the noise of the moving crowd. Applies after 0001-0037 and touches
    no file a depot window or quiver change would (built and tested in the Linux client, outlines standing, walking,
    mounted, with an outfit shader, at scale factor 1 and 2, gradient and pulsing ones; screenshots outside the
    repository).
19. `0039` (`client_settings/classes/dataset.lua`, `client_settings/options/interface.otui`,
    `client_settings/options/gameplay.otui`, `modules/game_inventory/inventory.lua`): the option "Keep attacking while
    moving" (`keepAttackingWhileMoving`, on by default) in a new panel after "Right-click equips items" in Options >
    Interface; its `apply` hands the new value to the overlay module `game_kitewalk` (`MANIFEST.md`), which tells the
    server (extended opcode 186; server/README.md "Keep attacking while moving", src-patch 0028). While it is on, the
    base "Auto Chase Off" (`game_inventory` `check()`, run on every `onWalk` / `onAutoWalk`) no longer switches the
    stance to Don't Chase when the player walks while attacking: the server keeps the walk and resumes the chase when it
    ends. The "Auto Chase Off" tooltip says so. Lua and OTUI only (no C++). Applies after 0001-0038, and 0040 applies after it;
    the chain 0001-0040 applies to the `windows-assets` base client with no fuzz. Built (0001-0039) and tested in the
    Linux client (the checkbox through Ok turns it off and on on the server; kiting by map and minimap clicks and keys).

20. `0040` (C++ `src/client/game.h/.cpp`, `protocolgame.h`, `protocolgamesend.cpp`; Lua `modules/game_bugreport/bugreport.lua`):
    System > Report a Bug sends what the player typed (server/README.md "Bug reports"). The base bound
    `g_game.reportBug(comment)` with one string while `game_bugreport` calls `reportBug(category, text, position)`; the
    Lua binder drops extra arguments from the top of the stack, so the category number ("0" to "3") went out as the
    whole text, always as category 3 (other). `Game::reportBug(category, comment, position)` and
    `ProtocolGame::sendBugReport` now send the 10.98 packet the server reads: u8 category (0 map, 1 typo, 2 technical,
    3 other; anything else becomes 3), the text, and the position after it for a map report. The dialog passes the
    local player's position when it has none (a nil position would fail the binder's cast). No new Lua function.
    Applies after 0001-0039 (checked with `patch --dry-run` on the base tree with 0001-0039 applied); the patched
    `protocolgamesend.cpp`, `game.cpp` and `luafunctions_client.cpp` compile (`g++ -fsyntax-only`); not built into a
    client or run against a server yet.

21. `0041` (C++ `src/client/tile.h/.cpp`, `luafunctions_client.cpp`; `client_settings/classes/dataset.lua`,
    `client_settings/options/interface.otui`): more widgets over a tile for the overlay module `game_tileoverlays`
    (`MANIFEST.md`). A tile drew one widget (`Tile:setWidget`), which the ground loot labels use, so a second module
    could not draw over the same tile. Lua: `tile:addOverlayWidget(w)`, `removeOverlayWidget(w)`,
    `hasOverlayWidget(w)`, `getOverlayWidgets()`. `Tile::drawWidget` draws them after the `setWidget` one, placed the
    same way (centred on the tile, moved by their margins; only the player's floor, clipped to the map), so they follow
    walking, scrolling, zoom and floor changes and are not in the UI tree (no mouse input). At most 16 per tile (the
    oldest is dropped); hidden or destroyed ones are skipped. Lua owns them: `Tile::clean` (the server sending a tile
    again, the area leaving the view) forgets them without destroying them, and the module puts them on the new tile.
    Also the option "Field timers over magic walls and fields" (`fieldTimers`, on by default) in a new panel after "Keep
    attacking while moving" in Options > Interface; its `apply` hands the value to `game_tileoverlays`. The base already
    had `Tile:setTimer` (one timer per tile, at most 60 s, tenths of seconds, no unknown state), which did not fit the
    fields (fire lasts up to 6 minutes). Applies after 0001-0040 (checked with `patch --dry-run` on the base tree with
    0001-0040 applied).
22. `0042` (C++ `src/client/mapview.cpp`): creature names and their small health bars are drawn over the light.
    `MapView::drawMapForeground` queued the light view after the creature information, so the ambient light darkened
    names like the ground: in an unlit arena a world boss's name came out at about 40% of its colour (the README shot
    `endgame_worldboss`: `#e03a1e` read as `#59150c` on the boss's red body). The light is now queued just before the
    creature information; static and animated texts were already after it. No Lua change. No other patch touches
    `mapview.cpp`, so it applies after 0001-0041 (`patch --dry-run` on the base file); not built yet (no room on the
    build machine).
23. `0043` (Lua `modules/gamelib/protocolgame.lua`): extended opcode handlers and stray parts. `ProtocolGame:onExtendedOpcode`
    calls every module's handler (plain and JSON) through `pcall`: an error is logged as `Extended [JSON ]opcode <n>: ...`
    and stops nothing else (the JSON handler of the same opcode, the next message). It joins the parts of
    `Chaos.sendChunked` ("S", "P", "E"); a "P" or "E" with no "S" before it concatenated nil and raised from the
    dispatcher, now it is dropped with a warning. The decode-error message concatenated the pcall status (a boolean),
    which raised a second error in place of the message; it now names the opcode and uses `tostring`. The hunk carries
    the whole function and the tables before it as context: the client protocol fuzz test
    (`game_chaosguard/opcode_fuzz_test.lua`) loads the function from the patch and sends every message through it. No
    other patch touches `protocolgame.lua`; the whole chain 0001-0043 applies (`patch --dry-run`, then applied, on the
    base tree of the `windows-assets` branch); no C++ change, not built yet.

24. `0044` (C++ `src/client/item.h/.cpp`, `uiitem.h/.cpp`, `luafunctions_client.cpp`; framework
    `graphics/drawqueue.h/.cpp`, `graphics/paintershaderprogram.h/.cpp`, `ui/uiwidget.h`, `ui/uiwidgetimage.cpp`,
    `luafunctions.cpp`; Lua / OTUI `client_settings/classes/dataset.lua`, `client_settings/options/graphics.otui`):
    the soft rarity outline of items and UI widget shaders (`MANIFEST.md` "game_itemrarity", "game_shaderfx").
    Items: `Item::draw` (the map) and `Item::draw(Rect, animate, outline)` (a slot) queue one
    `DrawQueueItemItemOutline` before the sprite and point it at the sprite's own queue item (the plain one or the item
    shader's, `DrawQueue::last()`); at draw time it draws that sprite once more, grown by the reach, through its own
    program: the alpha of the sprite in 8 directions on rings of half and whole steps (clamped to the sprite's frame
    rect), the nearest opaque ring weighted most (a smooth falloff), painted only where the sprite is transparent. The
    sprite draws over it. Same approach as the creature outline of `0038` (one extra quad per item, no framebuffer),
    with a soft edge instead of a line. The colour comes from the item's custom attributes (4 unique, else 1 rarity)
    and a style Lua sets: `Item.setRarityOutlineColor(rarity 1-15 | 16 unique, r, g, b, a)`,
    `Item.setRarityOutlineStyle(width 1-4, minRarity, pulseFromRarity, pulseMs)`,
    `Item.setRarityOutlineEnabled(onMap, inSlots)`, `isRarityOutlineOnMap()` / `isRarityOutlineInSlots()`,
    `item:getRarityOutlineColor()`. No colour set: nothing drawn (a client without `game_itemrarity` draws as before).
    Slots: `UIItem` draws it in inventory slot styles and container `itemN` widgets only (the same test as the expiry
    timers), not in the store, market, tooltips or the action bar; `UIItem:setRarityOutlineMode(-1 by slot, 0 never,
    1 always)`. The reach is in sprite pixels times `g_sprites.getOffsetFactor()` (HD upscaling keeps the look); the
    queue's opacity and a pulse (50%-100% alpha) apply. UI: the base parsed `image-shader` in OTUI and drew it through
    `DrawQueueItemImageWithShader`, but bound no Lua setter (corelib's `globals.lua` keeps `setImageShader` as a Lua
    field, so the base modules' calls never reached C++; they still do not). New Lua: `UIWidget:setUiShader(name)`,
    `getUiShader()`, `setUiShaderParams(a, b, c, d)`, `getUiShaderParam(i)`; the four values reach the shader as
    `uniform vec4 u_Params` (`PainterShaderProgram` `PARAMS_UNIFORM` 17, set right before each widget draws, so widgets
    sharing a program keep their own values). An image shader that is not registered now draws the plain image (it drew
    nothing). Options: a new panel at the bottom of Options > Graphics with `rarityOutlineMap` ("Rarity outline on
    dropped items"), `rarityOutlineSlots` ("Rarity outline in bags and inventory"), `rarityFrameShine` ("Shine on
    legendary and unique frames"), all on, and `liquidOrbs` ("Liquid health and mana orbs", off); each `apply` hands
    the value to `game_itemrarity` / `game_shaderfx`. Checked: the chain 0001-0044 applies to the `windows-assets` base
    client with no fuzz and 0048 applies after it (`patch --dry-run`); every changed C++ file compiles
    (`g++ -std=c++20 -fsyntax-only`); the two GLSL programs in the patch compile as desktop GLSL 1.10 and GLSL ES 1.00
    (`tools/check_shaders.py` with glslangValidator). Not built into a client or run (no room on the build machine):
    previews were rendered offline from the shader math with numpy, outside the repository.
25. `0049` (Lua / OTUI `client_settings/classes/dataset.lua`, `client_settings/options/effects.otui`,
    `modules/game_healthcircle/option_healthcircle.otui`): one spell effect opacity control. The base had six: Options >
    Effects "Opacity Effects" (`opacityEffects`) and "Own Spells / Other Player Spells / Creature Spells / Boss Area
    Creature Effect", plus the same four per-source sliders in the HP/MP circle options (`spellOpacityOwn` ...). On
    10.98 the server sends no effect source (`GameEffectSource` off), so `Effect::draw` uses the "own" alpha for every
    magic effect: "Opacity Effects", "Own Spells" and the circle's "Own Spells" all set that one value (the last one
    applied won) and the other three did nothing. Now `opacityEffects` is the only control, labelled "Spell effects
    opacity", 25-100% in steps of 5 (boss warning circles never vanish); its `apply` clamps to 25..100 and sets the
    alpha of all four sources. The four per-source sliders are removed from both windows (the Effects panel shrinks
    from 205 to 137 px; the HP/MP circle window keeps its size, with room left at the bottom; its Lua skips sliders it
    does not find). The g_settings key `opacityEffects` is kept; the overlay module `game_effectopacity` moves an old
    lower "Own Spells" value into it once and clamps an old stored 0-24 (`MANIFEST.md`). Missiles keep their own
    slider; the loot highlight, drawn with the own alpha, follows it as before. No C++ change. The chain 0001-0044,
    0048, 0049 applies to the `windows-assets` base tree with no fuzz (`patch`), and the patched `dataset.lua` parses in
    LuaJIT and Lua 5.3. Not run in a client.

26. `0048` (C++ `src/client/spritemanager.h/.cpp`): the sprite file split into shards, read on several threads
    (`MANIFEST.md` "Sharded sprites"). `SpriteManager::loadSpr` looks for `<name>.sprshards` before `<name>.spr`. The
    index (text, written by `tools/sprites/spr_shards.py`) lists the shard files `<name>.NNN.spr`; each is a normal
    `.spr` with a u32 count (signature, count, address table, records) holding one range of sprite ids (16384 by
    default: 46 shards for the 745,653 sprites of things_custom23). `loadSpr` reads the index and checks on the main
    thread that every shard is there with the size the index gives (`PHYSFS_stat`); a bad line, a gap in the ranges,
    a missing or short shard drops the whole set and the single `.spr` loads as before. Then it returns: up to 8
    background threads (`hardware_concurrency`, at most 8; none in the browser build) open the shards and read their
    address tables into one table (each thread its own range, a lock and a ready flag per shard). A sprite needed
    before its shard is read reads that shard on the spot. A shard whose header (signature, count) or an address turns
    out wrong draws nothing and is logged once. Sprite reads then go to the shard's own file. The workers only call
    PhysFS with paths resolved on the main thread and never log; `unload`, a new `loadSpr` and the destructor join
    them. The log says `Sprites: N in 46 shard files, loaded in X ms` (or `in one file`) and, at the first sprite drawn
    after the background reads end, how long they took. No Lua binding changes.
    Measured on the things_custom23 pair (599,654,574 bytes, 46 shards; Linux build of 0001-0043 + 0048, Mesa
    software GL; 9 loads each through `g_sprites.loadSpr`, page cache dropped with `posix_fadvise` before each cold
    load; a virtual disk, so "cold" still came from the host's cache): one file cold median 6.4 ms (3.5-12.3), warm
    1.3 ms; sharded cold median 1.6 ms (1.3-8.0), warm 1.7 ms (1.3-15.6: the long ones waited for the previous load's
    threads). The engine never read sprite data at load (it streams records), so the load was already only the 3 MB
    address table: sharding makes it shorter, but the gain is milliseconds. A loader harness (the same PhysFS calls,
    31 runs): the blocking part 0.3 ms sharded against 1.8 ms single (cold), 0.2 against 0.6 ms (warm); the 46 tables
    in the background in 5.3 ms on 8 threads, 5.9 ms on 4 and 14.5 ms on 1 (cold), 1.0-3.9 ms warm (on a warm cache
    the threads cost more than they save, off the main thread). The real gain is in updates: a sprite change downloads
    only its shards (`docs/LAUNCH.md` "Client updates"), and no file reaches the 512 MB limit of
    `ResourceManager::readFileContents` (the single spr is 600 MB). No other patch touches `spritemanager.*`; the
    whole chain 0001-0049 applies to the `windows-assets` base client (`patch --dry-run`, then applied, no fuzz).
    Built (0001-0043 + 0048) and tested in the Linux client: the login screen draws from the shards, and the single
    file loads when the index is renamed.

27. `0045` (Lua / OTUI `modules/game_outfit/outfit.lua`, `data/styles/40-outfitwindow.otui`): a Shader row in the
    Outfit window (ROADMAP 86). The 10.98 outfit window packet lists the shaders the character owns and the engine
    reads them (`GameOutfitShaders`, `parseOpenOutfitWindow` -> `shaderList`), but this window had no row for them, so
    no shader could be picked. The Shader row takes the Familiar row's place (10.98 has no familiars; with
    `GamePlayerFamiliars` on the Familiar row stays). It lists "None" and the owned shaders by name ("Ember Glow",
    "Blood Pulse"), each button previewing the current outfit with that shader; the search box filters them. The pick
    shows in the preview, survives a preset pick (presets store no shader) and goes out in the set-outfit packet; only
    a shader of the list is sent (else none), since the server refuses the whole change for a shader the character
    does not own. `updateAppearanceText` ignores a key with no row (worn wings). Logic: `OutfitShaderList` of the
    overlay module `game_chaosshaders` (`MANIFEST.md` "Outfit shaders in the Outfit window"); without it the row stays
    hidden. The other half is server src-patch 0036 (the engine kept no shader ownership). The chain 0001-0045,
    0048, 0049 applies to the `windows-assets` base client with no fuzz. Run in the Linux client against a live
    server with 0036 (server/README.md "Chaos outfit shaders").

28. `0050` (`init.lua`): `Services.account`, the HTTPS URL of the website's account API (`chaos_client_api.php`,
    website/README.md "Client API"), empty by default. The overlay module `client_chaos_charselect` (`MANIFEST.md`
    "Character select") reads it: the character select asks the site for each character's wings, aura and shader, and
    "Create character" creates characters there; empty turns both off. `client/tools/set_account_api.py <client> URL`
    writes it (https only; `--allow-http` takes 127.0.0.1 for a local test site). Lua only. The chain 0001-0045, 0048,
    0049, 0050 applies to the `windows-assets` base client with no fuzz (`patch --dry-run`, then applied).

29. `0051` (C++ `src/client/creaturehit.h` (new), `thingtype.h/.cpp`, `outfit.h/.cpp`, `creature.cpp`, `mapview.h/.cpp`,
    `uimap.h/.cpp`, `luafunctions_client.cpp`, `CMakeLists.txt`; Lua / OTUI `game_interface/widgets/uigamemap.lua`,
    `game_interface/gameinterface.lua`, `game_hotkeys/hotkeys_manager.lua`, `game_actionbar/actionbar.lua`,
    `client_settings/classes/dataset.lua`, `client_settings/options/interface.otui`): big creature click. A creature
    drawn over more than its own tile (the 4x4 guardians 2208-2212, world bosses, 2x2 bosses, class looks and mounts
    wider than a tile, a draw scale above 1 from `0020`) takes a click on any visible pixel; before, only its own
    bottom-right tile did. Covered: left and right-click attack, the right-click menu, look, the use-with crosshair,
    Alt-click attack and Shift-right-click follow, the hotkey crosshair and the action bar's smart cast. How:
    `ThingType::getTexture` keeps a one-bit alpha mask of each creature texture it builds (1/32 of the texture).
    `Outfit::draw` records the parts it queues (mount, body, addons: the parts the outline of `0038` collects; wings and
    auras do not count), and `Creature::draw` gives the map view one record per drawn creature: the stock one-tile click
    box, the parts (rect, texture rect, mask), the draw scale and the floor. `MapView::getCreatureAt` maps the mouse
    into the map framebuffer like `getPositionOffset` (zoom, walking camera), undoes the draw scale and tests the masks
    of the last frame's records. Only creatures on the clicked tile's floor or above count (a creature under an upper
    floor is not taken). The topmost one drawn wins; the own character is left out of that pass and keeps every click
    that only a big creature's overhang would take. Pure maths in `creaturehit.h`, tested by
    `tools/creaturehit_test.cpp` (CI step "Big creature click maths"). Lua: `UIMap:getCreatureAt(mousePos)`, nil when
    the point is on no creature, then the tile's own lookups apply as before. `uigamemap.lua` takes it for look,
    creature and attack; the tile's use thing stays the tile's own, so a use never goes to the creature. The use-with
    crosshair and the hotkey crosshair prefer it unless the tile's target is a force-use item. The battle list is
    unchanged. Hover: a big creature under the mouse gets the soft outline of `0044` (`DrawQueueItemItemOutline`, warm
    white, 2 px) under its largest part; option `bigCreatureHover` ("Outline big creatures under the mouse", on) in a
    new panel after "Right-click equips items" in Options > Interface, `UIMap.setBigCreatureHover(bool)`. The chain
    0001-0045, 0048-0051 applies to the `windows-assets` base client with no fuzz. Built and run in the Linux client
    (things_custom24 pair) against a local server (base, src-patches 0001-0036, `install_all.py`): on a 2x2 look (35)
    its top-left tile was attacked, looked at ("You see a rat") and hit with a Hexdart rune through the crosshair; the
    4x4 guardian (2208) attacked and looked at two tiles up and left of its own; the own character kept clicks under the
    guardian; a rat under the guardian was taken only where the guardian is transparent; hits matched the sprites at
    two zoom levels and with the guardian's own tile under the console; the option turned the outline off and on;
    Smart control's click and Regular control's Alt-click attacked the guardian by its overhang. Not run: a creature
    on a floor above (no upper floor near the test spot).
30. `0052` (Lua `mods/game_helper/helper.lua`, `classes/magic_shooter.lua`, `tools_panel.lua`): the helper's rotation
    against our server. Every cast of the magic shooter (spells, runes) and of the healing waits for the server's answer:
    the cooldown packets (`onSpellCooldown` / `onSpellGroupCooldown` signals) confirm it, no answer within 1.2 s (3 round
    trips on a slow line) means refused and that spell backs off 2, 4, 8, 16 s while the rest of the rotation goes on
    (overlay `game_helperrotation`, `ChaosHelperRotation`). Before, a spell the server refused (level, target, room, a
    corpse) went out every 200 ms for ever and the spells below it in its group never did; with a round trip over 200 ms
    the next spell of a group went into the group cooldown. The helper's own 200 ms pre-cooldowns no longer pass for
    server packets; the shooter's casts go through the `0026` rate guard too. The shooter checks the level and skips
    spells the server does not have (`notOnServer`, `game_chaosspells/spellfix.lua`); healing checks class, level and
    mana, so a refused heal no longer ends the priority loop above the next heal. A class casts a spell when its server
    vocation id is in the entry (the old map let a Mystic try Elementalist-only spells and kept the Illusionist,
    Berserker and Beastmaster from their own Chaos spells). A self-centred Chaos attack spell (no area table) needs a
    monster within 3 sqm instead of always counting one. A spell that needs a target is targetable even with an area
    (Radiant Shard). While a cast-time spell charges (`ChaosHelperRotation.CAST_MS`, or `game_castbar.isCasting()`)
    the shooter casts nothing and a heal waits unless health is below 50%: any other spell interrupted it and the
    server refunded its cooldown, so Colossus Fall took every attack turn and never landed. Magic shield: the server has
    no spell that ends it, so the "exana" option does nothing (before, the helper shouted "exana vita" every 50 ms, or
    Bushido Focus, which has id 245, and held the shooter's support spells back while the shield was up). Lua only;
    applies after 0001-0051 (checked against the assembled tree). Tested in the Linux client (0001-0052, things_custom24
    pair) against a local server (base, src-patches 0001-0036, `install_all.py`), 90-150 s per class against bears:
    Berserker 157 casts sent, 157 accepted; Elementalist 82/82; Deadeye 48/48; Lich and Illusionist only their refused
    spells failed (Corpse Explosion with no corpse, Umbral Stride with no room: 7-12 tries in 2 minutes, the rest of
    the rotation unaffected); no "You are exhausted"; every accepted spell at least its cooldown apart, the attack group
    at least 2 s; a 2.5 s client stall was followed by 1-4 casts in the next 6 s, no burst. Not run on Windows.

31. `0053` (OTUI `client_settings/options/interface.otui`): Language. Options > Interface gets a "Language" row after
    "Field timers over magic walls and fields" (0041): a label and a button with the current language that opens the
    choice of the overlay module `client_chaos_locale` (`ChaosLocale.showMenu`, `MANIFEST.md` "Localization"). The
    choice is the module's own setting (`chaos-language`), not a `client_settings` option, so the window's Ok / Apply
    do not touch it; without the module the button hides itself. OTUI only; its context is 0041's field timers panel
    (checked with `patch --dry-run` on that context, not on the assembled tree). Not run in a client yet.

32. `0054` (OTUI `client_background/background.otui`, Lua `client_background/casts.lua`): the login screen's panels
    through `tr()`. The Event Schedule panel's column heads "Active" and "Upcoming" were baked into
    `/images/ui/schedule`; the overlay's recoloured copy has them erased (`tools/gen_ui_reskin.py` `TEXT_FREE`) and
    the patch draws them as two labels (`$var-cip-font`, the old bronze `#8d5a3a`) over the head band. The Casts
    panel's counts (`setCounts`) are `tr('%d Players Casting', n)` / `tr('%d Viewers', n)` (and the singulars). The
    pt-BR texts, with the panel's other `tr()` labels (Boosted, Creature, Casts, Watch), are in
    `client_chaos_locale/pt_br.lua`. Applies after 0014 (casts.lua; checked with `patch --dry-run` on the assembled
    tree's files). Run in the Linux client (pt-BR and English login screens, 2026-10-14).
33. `0055` (C++ `src/client/map.h`, `tile.h/.cpp`, `mapview.cpp`, `luafunctions_client.cpp`): ground effects. An effect
    id registered with `g_map.setGroundEffect(id, true)` is drawn under every creature, like a decal on the floor:
    `Tile::drawTop` skips it and `MapView::drawFloor` draws it after the bottom layer. A big effect reaches up and left
    of its tile into tiles drawn earlier, so with `GameMapDrawGroundFirst` (the 1098 profile, `0006`) the first tile
    it covers (the earliest diagonal of the painter order) draws it after its own bottom layer; the walls and items of
    the later tiles still go over it. In the negative-offset layer pass it is queued after every bottom layer. Lua:
    `g_map.setGroundEffect(id, on)`, `g_map.isGroundEffect(id)`, `g_map.clearGroundEffects()`. `game_groundfx` registers
    every floor-shaped spell effect (its generated `groundfx_data.lua`, MANIFEST). The overlay's
    `game_townportal` registers the Town Portal channel circle (effect 744, `portal_pad`; live test winpkg-35: the
    circle covered the character); a client without the patch skips the call and draws it as before. Applies after
    `0001`-`0054`; `tile.cpp`, `mapview.cpp` and `luafunctions_client.cpp` compile (`g++ -fsyntax-only` with the
    Linux build's flags). Not yet run in a client.
34. `0056` (Lua and OTUI): fixes from the winpkg-35 test (owner's screenshots 14-31, MANIFEST.md "Client fixes of
    winpkg-35"). `client_settings`: the four rarity options of Graphics one per row (the right column began at a
    fixed 250 px and ran over the left one and the info icon) with an Orb size box (`liquidOrbSize`, small / medium /
    large, read by `game_shaderfx`); the Graphics Engine box greyed out with a tooltip when `g_graphics.getVersion()`
    is not OpenGL ES (only an ANGLE build can switch to Vulkan or DirectX; the Windows package is desktop OpenGL, so
    "DirectX11" there was a label); the Options menu buttons sized by their real height (22 px entries, 21 px
    sub-items, 3 px gap; 20 px squeezed "Graphics" / "Effects") and named by `tr()` labels drawn over the tab images
    (their 7 px baked words are erased, `tools/gen_ui_reskin.py` TEXT_FREE); `backgroundFrameRate` and `limitEffects`
    no longer log "Failed to apply tmp option" while their no-limit box is checked. `game_things`: HD Sprite
    Upscaling (`hdmodeBox`) is set right before the dat / spr load (the option's own apply ran from an event that could
    come after the load at start; xBRZ runs on the CPU, so the renderer does not matter). `game_modaldialog`: a button
    is as wide as its label ("Skip tutorial" was cut to 43 px). `game_console`: Enter or Shift+Enter on an empty chat
    closes it in "Chat On" and "Chat On*" and gives the keys back to walking; with text it sends, and "Chat On*" closes
    after (the rule is `ChaosChatLogic.enterAction`, overlay `game_chatpanel`); the temporary chat compared the button
    text with the English "Chat On*", so in pt-BR it never closed. `game_interface`: the bottom splitter's minimum
    118 -> 96 (`game_chatpanel` sizes the area). `game_skills`: `getContentPanelHeight` counts rows by
    `isExplicitlyVisible` (`isVisible` is false for every row while the window is closed, so a height measured then was
    0 and the window could not grow past the 125 px floor, Hit Points cut off) and `online` sets the maximum from the
    content instead of a fixed 390 / 680 (the seven profession rows of `game_craftskills` did not fit). `client_background`, `client_topmenu`: a failing clientservices
    request is logged once per address and retried after 1, 2, 4 ... 30 minutes (the status request scheduled two
    retries per failure, doubling the requests). `mods/game_helper`: the bot HUD calls go to `ChaosBotHud` (overlay
    `game_helperhud`) when the cavebot file is left out (`assemble_client.sh` deletes it, and with it the HUD, so "Show
    Bot HUD" did nothing); the Set Key bar, New Preset and Add buttons lose the `buttons-blue` image (the overlay
    Button style clips 64 x 24 with border 5 and cut that sheet into empty blue boxes); Set Key, Rename, Duplicate, New
    Preset and "My character save" are as wide as their labels. Applies after `0001`-`0055` (checked with the full
    chain on the base archive of `windows-assets`). Not yet run in a client.
35. `0057` (Lua `mods/game_helper/helper.lua`, `modules/game_actionbar/actionbar.lua`,
    `mods/client_settings/classes/custom-hotkeys.lua`): every spell picker (the helper's Assign Healing / Attack Spell,
    Select Attack Spell, Assign Training / Haste / Cure Paralyze Spell, the action bar's and the custom hotkeys' Assign
    Spell) calls `ChaosSpellCore.setupPicker` (overlay `game_spellbook`, `spellbook_core.lua`) instead of sorting by name:
    level then name, rows above the level dimmed, the "Only show learned spells" box works (the helper had forced it on
    and disabled it, and no picker read it), the search and the box filter together, the empty preview at the top
    says what to do. Applies after `0001`-`0056` (checked with the full chain on the base archive). Not yet run in a client.
36. `0058` (Lua `modules/corelib/keybinds.lua`): no "Open Prey Dialog" hotkey (Ctrl+Y by default). `game_prey` needs
    the `GamePrey` feature, which the 10.98 profile of `game_features` leaves off: the 10.98 server sends no prey data
    and no prey byte in the login packet, so turning it on would misread that packet. `game_prey.show` returned at once
    and the hotkey did nothing. The module stays loaded (`game_interface` loads it and calls it), inert. Applies after
    `0001`-`0057` (checked with the full chain on the base archive). Not yet run in a client.
37. `0059` (Lua, OTUI, OTMOD, JSON): no other server's or client's name in what the player reads. The side-bar
    shortcut beside the orb (second icon of the left column) said "Open <another server> Bot"; it reads "Open Helper"
    now, the helper's settings and save-data boxes say "Helper" (pt-BR in `client_chaos_locale/pt_br.lua`) and the
    handler is `onOpenHelperClick`. Also renamed: the report reasons (`data/json/report-name.json`,
    `report-statement.json`), the Cyclopedia magical archive spell texts, the map marker labels (`gamelib/core/markers.lua`,
    `game_realminimap/markers.lua`, `markers.json`), the "Connection refused" box of `client_entergame/characterlist.lua`,
    the `game_memleak` warning and six `.otmod` descriptions; the hidden stock top menu's Discord button lost its
    hard-coded invite of another server (`Services.status` still sets the link). `.otmod` author and website lines
    (attribution), comments, identifiers and the C++ sources are unchanged. The removed lines of the patch carry the old
    names (a diff has to), as in `0014`. Applies after `0001`-`0058` with no offset or fuzz (full chain on the base
    archive). Not yet run in a client.

38. `0060` (Lua `modules/game_outfit/outfit.lua`, OTUI `data/styles/40-outfitwindow.otui`): the Customise Character
    window lists every outfit, mount, aura and shader of the game (the server's wardrobe catalogue, kept by the overlay
    module `game_unlocks`), the ones not owned greyed with their source in the tooltip; they can be looked at, not
    worn: Ok is disabled while a part in use is locked and `accept()` sends nothing then. Presets with a locked part
    are greyed. "Only mine" (now `tr()`) works on every list, is kept per character and list and no longer resets on a
    row change. Cards show the look facing south, filling the card (`game_lookpreview.fitCard`). The rule is
    `UnlocksCore` (`unlocks_core_test.lua`); without `game_unlocks` the window is as before (`MANIFEST.md` "Owned and
    locked lists"). Applies after `0001`-`0059` (checked with `patch --dry-run` on the chain applied to the base
    archive). Not yet run in a client.
39. `0061` (C++ `src/client/protocolgameparse.cpp`): **Container open recovery.** A container open packet (0x6E) the
    client cannot read used to leave the old window on that container id while the server already held the new
    container there, so every later add / update / remove of the new container landed in the wrong window (owner
    2026-10-16: "the loot bag and the backpack are conflicting"; cause: gems whose items.otb nodes lacked
    `FLAG_ANIMATION`, server/README.md "Gems and sockets"). `parseOpenContainer` now catches the error, closes the id
    locally (`Game::processCloseContainer`: the stale window goes; later add / update / remove packets for the id are
    ignored, as the stock `processContainer*` do for an unknown id), sends a close for the id to the server (its close
    answer then finds nothing), logs one line "Container N could not be opened (item C): ..." with the client id of
    the item being read (a short item is often noticed one item later), and rethrows, so the packet's rest is dropped
    and logged as before. The full chain `0001`-`0061` applied to a fresh copy of the base archive; the patched file
    compiled with the build's own flags (no new warnings). Not yet run in a client: open a container holding an item
    with mismatched bytes (`server/tools/check_item_wire.py` lists them) and check the window closes and reopens cleanly.
40. `0062` (Lua `mods/game_helper/helper.lua`, `classes/magic_shooter.lua`): **the helper's cooldown channels**
    (server/README.md "Cooldown channels"; owner 2026-10-16: heal and attack never wait for each other). The helper
    serialised them in the client although the server (engine src-patch 0042) keeps them apart: one cast guard of 4 a
    second for every spell (`0026`), one 1 s object-use timer for potions, the healing rune, the shooter's runes and the
    special foods plus a 1.1 s potion "turn" after every rune, and a heal waited while a cast-time spell charged
    (`0052`). Now `helperCastAllowed(words, channel)` keeps a guard per channel (heal, attack, support; healing spells
    and the friend heals "heal", the shooter the channel of the spell's group, the rest "support"), and potions, the
    healing rune, attack runes, support runes and special foods each have their own timer (`objectUseReady` /
    `markObjectUse`, `_Helper.isObjectUseOnCooldown(channel)` / `setObjectUseCooldown(ms, channel)`). A heal goes out
    during a cast-time spell (the server no longer interrupts the cast for it); the shooter still waits with attack
    spells and attack runes. Both from the overlay `game_helpertimers` (`ChaosHelperTimers`); without it the old shared
    guard and timer stay. The chain `0001`-`0062` applied to the base archive; both files parse in LuaJIT and Lua 5.3;
    tests `game_helpertimers/helpertimers_test.lua`. Not yet run in a client: a heal under 50% during an attack rotation
    and a cast-time spell, potion and rune in the same second.

### Names check of the assembled client

`check_names.py` skips `base-patches/` and the base tree is not in git, so names from the base client reach the game
unless the assembled tree is read. Before each release, and after a base patch that adds UI text:

    client/tools/assemble_client.sh <base-client-dir> <out>
    python3 -I tools/ci/check_names.py --client <out>

It reads what the player sees in `init.lua`, `modules/`, `mods/`, `data/` and `layouts/` (Lua string literals with a
space, a URL or given to `tr()`; OTUI/OTML text, tooltip, placeholder, title and description values and URLs; `.otmod`
name and description; JSON keys and values) against the same name list as the repo check. Names added from
2026-10-16 on are stored only as hashes (`DENY_HASHES`, see the script's docstring). Skipped on purpose:
`data/json/hunting_places.json` (no module reads it) and one creature name of the helper's `spelldata.json`
(`CLIENT_ALLOW`). `windows-package.yml` runs it on the Linux client job's assembled tree, so a package with such a
name fails. `assemble_client.sh` also deletes the base native splash picture and the browser emblem: both show the
base client's name. Images are not read for baked-in text; check new base pictures by eye.

### Client guard: the build secret

The key the client proves itself with is read by CMake (`src/client/CMakeLists.txt`, patch 0035) at configure time:
the environment variable **`CHAOS_CLIENT_KEY`** (64 hex digits), else the file `-DCHAOS_CLIENT_KEY_FILE=<path>`, else
the public development key (a configure warning; only a server with `clientGuardAllowDevKey = true` accepts it). It is
never cached in `CMakeCache.txt` and never written into the source tree: `build/chaosguard/chaosguard_key.h` holds it
shuffled and XOR-masked with a random mask (volatile arrays, put together only for the HMAC and wiped after). That is
obfuscation, not protection: whoever has the binary can recover the key with a debugger. `-DCHAOS_CLIENT_BUILD=N`
(1..65535, default 1) is the build number the server checks (`clientGuardBuilds`, the updater's `min_package`).
- **Owner, once:** `openssl rand -hex 32`; GitHub -> Settings -> Secrets and variables -> Actions -> New repository
  secret **`CHAOS_CLIENT_KEY`** with that value; the same value as `CHAOS_CLIENT_KEY` in the game server's
  `/etc/chaos/chaos.env` (server/README.md "Client guard").
- **Workflows:** `windows-package.yml` (its Windows and Linux client jobs) and `windows-client.yml` pass the secret to the build step only (GitHub masks it
  in the logs) and take the input `client_build` (`windows-package.yml` also writes it into `Services.update.package`).
  Raise it for every new exe. Without the secret the run warns and the client gets the development key.
- **Linux / local:** `CHAOS_CLIENT_KEY=$(cat ~/chaos-keys/client.key) cmake <game-dir> ... -DCHAOS_CLIENT_BUILD=N`
  (`LINUX.md`); a build without it is a development client.

## What the overlay replaces
- `game_stash` (the client's own targets a different protocol): ours, extended opcode 110.
- `game_battlepass`: ours, the Chaos season pass (extended opcode 227, server `seasonpass.lua`).
- `game_task_hunt` (deleted by `assemble_client.sh`): bounty tasks, preferred list, talisman, weekly tasks and task shop
  read packets of newer protocols the 10.98 server never sends, so the window showed placeholders and buttons that did
  nothing. Ours: Hunt > Kill Tasks (`game_bestiary`, extended opcode 253) and Adventure > Bounty Board (`game_bounty`,
  223). Its callers (`game_sidebuttons`, `game_trackers`) check that the module exists.
- Prey: no Chaos equivalent and no top menu entry; base patch `0058` drops its hotkey (`game_prey` stays loaded, inert).
- Login background: the client's own `client_background` module stays (other modules call its functions); the overlay replaces only its images `data/images/title.png` (the login background) and `data/images/ui/logo.png` (the Cinders of Chaos logo). The overlay module `client_chaos_login` lays the login screen out on top of both stock modules (see `MANIFEST.md`, "Login screen"); `title.png` and the logo are made by `tools/gen_login_art.py` from the login artwork in `tools/art_src/`.
- `game_mainpanel`, `game_healthcircle`, `game_realminimap` and `game_sidebars` stay the client's own (the first two have alternates in `alternates/`).

## Still open
- Whether the client's engine parses the 10.98 `Tibia.dat` and the server login packet. Its own profiles are 8.60 and 15.24, so 10.98 is untested ground. The login sends OTClient version 310, which the server accepts (it needs at least 254).
- Native modules built for another protocol may expect packets the server does not send; read the terminal log on first run.
- You supply `Tibia.spr`/`Tibia.dat` for 10.98 (not in the repo).
