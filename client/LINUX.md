# Running the client on Linux

Tested in a Ubuntu 24.04 cloud container (software OpenGL, virtual display): the client builds, logs in to the server
and enters the game.

## Build
```
sudo apt-get install -y cmake g++ libboost-all-dev libphysfs-dev libogg-dev libvorbis-dev zlib1g-dev libzip-dev \
  libbz2-dev libssl-dev libopenal-dev libglew-dev libluajit-5.1-dev libgl1-mesa-dev libglu1-mesa-dev libx11-dev
tools/assemble_client.sh <base-client-dir> <game-dir>       # patches (C++ and Lua) + overlay (incl. spell icon sheets)
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
- Accounts with more than one character could not log in (stuck at "Connecting to login server...",
  `protocollogin.lua:338: attempt to index a nil value`). The server's character list (0x64) entry is world id u8,
  name, then level u32, vocation u16 (server id), outfit (looktype u16; head, body, legs, feet, addons u8, or an item
  id u16 when the looktype is 0) and mount u16; the client read only world id and name, so the second entry's world id
  came out of the first one's level (with one character the leftover bytes were read as the account status and
  premium time, hence "-20726 days left"). `base-patches/0025-chaos-character-list-entries.patch` reads the whole
  entry for 1098, so the list also shows level, class and outfit. Tested with 1, 2 and 5 characters on an account.

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
`base-patches/0014-chaos-branding.patch` renames what the player reads in the base client: window title "Cinders of Chaos",
"Chaos Coins", "Cyclopedia", option help texts, rules and store texts. It also hides the Google sign-in button
(our login server has none), turns the base client's built-in test servers (Ctrl+Alt+T) into a no-op, fetches
store offer images only from `Services.storeWidget` when it is set, and replaces the paid-services terms of the
base client's company with a short Cinders of Chaos text. Map marker names in the minimap data are left as they are.

## No scripting bot
`base-patches/0015-no-bot-no-cavebot-no-scripts.patch` and `tools/assemble_client.sh` leave the vBot module (`game_bot`, Lua scripts
and its cavebot) out of the client and remove the helper's Cavebot and Scripts tabs, panels, hotkeys, shortcut and HUD options. The helper
keeps healing, potions, haste, shooter, equipment, timers, alarms and tools (auto healing tested in game).
`base-patches/0016-chaos-vocation-ids.patch`: the server sends the vocation in Tibia's ids (3 = sorcerer) while the modules expect server
ids (3 = paladin), so the helper offered the wrong spells; the 1098 profile now translates them (feature `GameChaosVocationIds`).
The same patch gives the Thief line its own ids: the server sends 6 (the client's free sixth slot) for the Thief, 16 for the
Ninja and 26 for the Samurai, and the client turns them into the server ids 11, 12 and 13, so the two ascended classes are told
apart (the other vocations still arrive as their base vocation). The names Thief / Ninja / Samurai are in `VocationNames`,
`g_game.getVocationName(Base)`, `translateVocationName` and `getVocationId`; `translateVocation` keeps 11-13 as they are (the spell
data lists them), `Creature:isThief()` is new, and the helper treats the line as its class 6 (`game_chaosspells` fills its spell
lists). 11-15 used to be other servers' promoted ids in those tables; with this server they are the Thief line. Tested: login as a
Thief shows vocation 11 "Thief", and the Ascendant Oracle switches the client to 12 "Ninja" without a relog (the server resends 0x9F).

## Name plates
`base-patches/0022-chaos-nameplate.patch` adds `Creature:setNameplate(guild, font, guildColor, nameColor, frameImage, border)`:
`drawInformation` draws a 9-slice frame behind the name (lifted 2 px off the health bar), the name in its own colour and
a guild line between the name and the engine's title line (`setTitle`, unchanged for monsters). Used by `game_nameplate`
(see `MANIFEST.md` and server/README.md "Name plates and titles"). Built and tested on Linux; the Windows binary needs a
rebuild with this patch (without it the module falls back to title and guild as plain text above the name).
