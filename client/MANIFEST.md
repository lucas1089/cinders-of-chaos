# Client module manifest

Status of every requested module. **Nothing here has been run.** The session that assembled it had no OTClient runtime, so "loads" means "the code looks self-contained", not "tested".

Layout: `overlay/modules/<name>` is copied into the client's `modules/` folder; `overlay/data/images/...` into its `data/images/`. Source clients put some of these under `mods/`; they were all moved to `modules/` here, so check `autoload` and `autoload-priority` in each `.otmod` when wiring them in.

Protocol target is 10.98 on Hellgrave Exodus (TFS 1.4.2). The sources are mostly 8.60 or 12.x+ clients, so the real risk is the client engine (C++ API) and the server contract, not the Lua.

| Module | Source client | Server contract | Client-engine needs | Verdict |
|---|---|---|---|---|
| game_stash | Black Talon | extended opcode 110 + `!stash` talk | none after port | Ported off `client_manager` (opcode now constant 110, JSON decoded locally); untested |
| game_bank | Evolisca | extended opcode 60 | none | Needs server script |
| game_autoloot | Evolisca | extended opcode 216 | none | Needs server script (Exodus has a partial autoloot) |
| game_itemrarity | Black Talon | none | optional `g_game.setRarityShaderEnabled` (guarded) | Client-only; frames work without the shader. Server must send item rarity somehow (see Exodus rarity customs) |
| game_battlepass | Exodus GitHub client | raw game opcode 39 via `ProtocolGame.registerOpcode` (not extended) | needs custom C++ packet parsing | Needs engine and server work |
| game_passivetree | Exodus GitHub client | extended opcode 65 | none | Needs server script |
| game_daily | Evolisca | extended opcode 207 | none | Needs server script |
| game_healthcircle | Black Talon | none | none | In `alternates/`: Fonticak has its own |
| game_mainpanel | Astra | none | none | In `alternates/`: Fonticak has its own |
| game_chaosnotify (was game_notifications) | MagicHeard | extended opcodes 79, 151, 152 | none | Needs server script |
| game_itemtooltip | OxygenOT/Zerion (`game_tooltips`) | none | none | Client-only. Black Talon's richer one needs opcode 52 |
| game_sidebars | Astra | none | none | Client-only |
| game_realminimap | Astra | none | none | Client-only |
| game_nameshaders | Black Talon | extended opcode 96 | also hooks `onOpenOutfitWindow` with extra shader lists | Needs engine and server work |
| game_dungeons | Exodus GitHub client | extended opcode 109 | none | Needs server script (Exodus has dungeon customs) |
| game_infinitytower | Luminaris | extended opcode 214 | none | Needs server script. It is classic-style, so no conversion was needed |
| game_event | Black Talon | none seen in the module | none | Client-only UI; wiring to a server event system is open |
| game_creatureinformation | OTC-Fonticak | none | engine APIs of Fonticak | Not copied: use Fonticak's own, which is the same module |

Opcode numbers above do not collide with the ones the Exodus server already uses (106, 91, 181, 107, 202, 1, 136, 99, 201, 92, 89). The stash and battlepass numbers are not fixed in the Lua and still have to be chosen.

## Shared assets copied
`data/images/topbuttons/` (loot, bank from Evolisca; battlepass, dungeon, passive_tree from Exodus client; minimap from Astra), `data/images/ui/events/` (Black Talon, event banners), `data/images/ui/` rarity frames (copied from game_itemrarity).

## Licence and provenance
Most sources have no licence file or are other live servers' clients (Black Talon, Evolisca, MagicHeard, Luminaris, OxygenOT/Zerion, Astra). Only OTC-Fonticak is MIT. Treat this overlay as a private working copy: get permission or replace the code and art before any public release.

## Not done
Server-side scripts, engine changes, any runtime test, translation of Portuguese/Spanish strings.

## Added after the first draft
The theme (`client_chaos_theme`, `client_chaos_topbar`, `client_background`, `data/images/chaos/`, generator in `tools/gen_theme_art.py`) and the admin panel (`game_admin`, opcode 120) are in the overlay too. The server counterparts are in `../server/`.
