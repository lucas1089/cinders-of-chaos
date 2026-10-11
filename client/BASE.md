# Client base

The client is an OTClient-family engine whose wire protocol matches the server: wings, auras and outfit shaders in the outfit packets, `g_shaders.createOutfitShader` with a vertex stage (91 of the 95 server outfit shaders need it), and HD upscaling (xBRZ, scale factor 1 to 4, or a 64px `.spr`). Speed was judged from the code, not measured.

**Source.** The tree is about 300 MB (230 MB of it `data/` images and sounds), so it is not committed: `tools/assemble_client.sh <base-client-dir> <out>` takes your copy, applies `base-patches/`, drops in `overlay/` and leaves a folder to build with CMake. Not run yet.

## Patches (`base-patches/`, applied and built on Linux, see `LINUX.md`)
1. `init.lua`: server entry named Cinders of Chaos, version 860 -> 1098.
2. `gamelib/game.lua`, `client_entergame`, `corelib/globals.lua`, `game_things/things.lua`: supported versions include 1098; default assets folder is `data/things/1098`.
3. `game_features/features.lua`: a 1098 profile (74 features, the usual OTClient version ladder) plus `GameOutfitShaders`, which the client needs to read the shader list. `GameOrangeNpcNameColor` does not exist in this client and was left out.
5. `src/client/protocolgameparse.cpp` (C++, `0008`): the 0x9F player-info packet reads 1-byte spell ids and no magic-shield byte when the protocol is 1098 (found by the first real login, see `LINUX.md`).
4. `client_settings/classes/dataset.lua`: HD upscaling on by default; spell effect opacity defaults: own 100%, other players 60%, creatures 80%. The sliders already exist in the options window.
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
    own seat (data only, same patch).

15. `0035` (C++, CMake, `modules/gamelib/protocollogin.lua`): the client guard, the client half of server src-patch 0021
    (server/README.md "Client guard"; overlay module `game_chaosguard` sends the Lua hello). Both login packets carry
    `0x4343 << 16 | CHAOS_CLIENT_BUILD` in their u32 client version field instead of 1098; extended opcode 189 (the
    server's challenge) is answered in C++ with an HMAC-SHA256 over the nonce, account, character and build
    (`src/client/chaosguard.h`, OpenSSL; vectors `tools/chaosguard_test.cpp`, run in CI) and never reaches Lua;
    `g_game.getChaosClientId()` / `getChaosClientBuild()` for Lua. The chain 0001-0035 applies to the `windows-assets`
    base client; built and tested in the Linux client.

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
- **Workflows:** `windows-package.yml` and `windows-client.yml` pass the secret to the build step only (GitHub masks it
  in the logs) and take the input `client_build` (`windows-package.yml` also writes it into `Services.update.package`).
  Raise it for every new exe. Without the secret the run warns and the client gets the development key.
- **Linux / local:** `CHAOS_CLIENT_KEY=$(cat ~/chaos-keys/client.key) cmake <game-dir> ... -DCHAOS_CLIENT_BUILD=N`
  (`LINUX.md`); a build without it is a development client.

## What the overlay replaces
- `game_stash` (the client's own targets a different protocol): ours, extended opcode 110.
- `game_battlepass`: ours, the Chaos season pass (extended opcode 227, server `seasonpass.lua`).
- Login background: the client's own `client_background` module stays (other modules call its functions); the overlay replaces only its images `data/images/title.png` (the login background) and `data/images/ui/logo.png` (the Cinders of Chaos logo). The overlay module `client_chaos_login` lays the login screen out on top of both stock modules (see `MANIFEST.md`, "Login screen"); `title.png` and the logo are made by `tools/gen_login_art.py` from the login artwork in `tools/art_src/`.
- `game_mainpanel`, `game_healthcircle`, `game_realminimap` and `game_sidebars` stay the client's own (the first two have alternates in `alternates/`).

## Still open
- Whether the client's engine parses the 10.98 `Tibia.dat` and the server login packet. Its own profiles are 8.60 and 15.24, so 10.98 is untested ground. The login sends OTClient version 310, which the server accepts (it needs at least 254).
- Native modules built for another protocol may expect packets the server does not send; read the terminal log on first run.
- You supply `Tibia.spr`/`Tibia.dat` for 10.98 (not in the repo).
