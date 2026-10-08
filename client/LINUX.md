# Running the client on Linux

Tested in a Ubuntu 24.04 cloud container (software OpenGL, virtual display): the client builds, logs in to the server
and enters the game.

## Build
```
sudo apt-get install -y cmake g++ libboost-all-dev libphysfs-dev libogg-dev libvorbis-dev zlib1g-dev libzip-dev \
  libbz2-dev libssl-dev libopenal-dev libglew-dev libluajit-5.1-dev libgl1-mesa-dev libglu1-mesa-dev libx11-dev
tools/assemble_client.sh <base-client-dir> <game-dir>       # patches (C++ and Lua) + overlay + spell icons
mkdir build && cd build
cmake <game-dir> -DCMAKE_BUILD_TYPE=Release -DLUAJIT=ON -DPHYSFS_LIBRARY=/usr/lib/x86_64-linux-gnu/libphysfs.so
make -j$(nproc)
```
`-DPHYSFS_LIBRARY=...so`: Ubuntu's static `libphysfs.a` has no archive index and the link fails without it.

## Run
Put `Tibia.dat`/`Tibia.spr` (10.98) in `<game-dir>/data/things/1098/`, copy or link the client binary that CMake built into
`<game-dir>` and start it from there. Without a GPU: `LIBGL_ALWAYS_SOFTWARE=1 ./<client binary>`; headless:
`Xvfb :99 &` then `DISPLAY=:99 ...`.

## What the first run found (fixed)
- The client's own 0x9F player-info packet uses 2-byte spell ids and an extra byte; 10.98 servers send 1-byte ids
  (`base-patches/0008-protocol-1098-player-info.patch`). Without it the rest of the login packet was dropped.
- Several imported modules depended on modules or UI styles of the clients they came from (stash, bank, event...);
  a missing style or module stops the client at start. Fixed with guards and `client_chaos_theme/compat.otui`.
- The overlay used to replace `client_background`, which other base modules call; now only its images are replaced.

## What the in-game test found (fixed)
- The missing `getItemsPrice` in the base cyclopedia was not harmless: its `onGameStart` handler raised an error and every
  `onGameStart` handler connected after it (battle list, skills, VIP, quest log and all the Chaos modules) never ran at login.
  `base-patches/0009-cyclopedia-start-guard.patch` guards it; the Chaos menu also connects first (`pushFront`).
- The engine hands HTTP results to Lua as a table (`{status, headers, body, ...}`) but `corelib/http.lua` expected the body
  string, so no HTTP JSON call worked (boosted creature, event calendar, players online).
  `base-patches/0011-http-result-body.patch` passes the body on.
- `base-patches/0010-extended-view.patch` turns on the extended view: the map fills the whole window and the panels float on it.

## Login screen services
Start `server/tools/clientservices.py` next to the game server (see `server/README.md`) so the login screen shows the
boosted creature and boss, the event calendar and the players online. `init.lua` points at `http://127.0.0.1:8090/clientservices`.

- The server sends 14 skills (the classic seven plus crafting, woodcutting, mining, herbalist, armorsmith, weaponsmith
  and jewelsmith) where the client read seven, so critical hit and leech showed the crafting numbers and the 35 bytes
  left over were read as opcode 0x00, dropping the rest of the message ("parse message exception ... 292 unread") at
  login and on every skill update. It also sends inventory slots up to 16 (gloves) where the client stopped at 15
  ("invalid slot"). `base-patches/0012-chaos-skills-and-slots.patch` adds the feature `GameChaosCraftingSkills`
  (enabled in the 1098 profile, patch 0006), reads the seven crafting skills (passed to Lua as
  `g_game.onCraftingSkill(index, level, base, percent)`) and accepts slot 16.

## Branding
`base-patches/0014-chaos-branding.patch` renames what the player reads in the base client: window title "Chaos",
"Chaos Coins", "Cyclopedia", option help texts, rules and store texts. It also hides the Google sign-in button
(our login server has none), turns the base client's built-in test servers (Ctrl+Alt+T) into a no-op, fetches
store offer images only from `Services.storeWidget` when it is set, and replaces the paid-services terms of the
base client's company with a short Chaos text. Map marker names in the minimap data are left as they are.
