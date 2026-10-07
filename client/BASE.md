# Client base: OTC-Fonticak

Chosen because it has C++ source with an MIT licence, a feature ladder that covers 10.98, and built-in HD (xBRZ upscale, scale factor up to 4). Compared against Astra (feature profile only for 8.60 and 15.24) and Black Talon (binaries only). Speed was judged from the code, not measured.

`tools/assemble_client.sh <dir>` clones upstream, applies `base-patches/`, drops in `overlay/` and leaves a folder you build with CMake. Not run yet.

## Patches (`base-patches/`)
1. `init.lua`: default server protocol 860 -> 1098 (the login reads it from `Servers_init`; set your host/port there too).
2. `client_options/data_options.lua`: `hdGraphics` default on. This upscales the 32px sprites 2x at load time, so it is smoothed, not true HD art. A real HD `.cwm` sprite file is picked up automatically if present.

## Where the overlay overlaps Fonticak's own modules
- `game_stash`: ours replaces the native one (the native stash needs 11.x packets, absent in 10.98). Ported off Black Talon's `client_manager`; uses opcode 110.
- `game_notifications`: Fonticak has a popup/screenshot module of that name used by 6 other modules, so ours was renamed `game_chaosnotify`.
- `game_mainpanel`, `game_healthcircle`: Fonticak's are used by 23 and 4 other modules. Ours sit in `alternates/` and are not installed.
- `game_creatureinformation`: use Fonticak's own (it is where the module came from).
- `client_background`: ours replaces the stock one on purpose.

## Still open
- Whether Fonticak's 860-era login and parser work against the Exodus 10.98 server. Needs a real run.
- The remaining overlay modules were written against other clients' APIs; load them one at a time and read the terminal log.
- You supply `Tibia.spr`/`Tibia.dat` for 10.98 (proprietary, not in the repo).
