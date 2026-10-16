# Chaos admin panel

Server side of the in-game administrator panel (client module: `client/overlay/modules/game_admin`).
Everything is driven by a registry of actions; the client builds its forms from the `catalog` message.

**Status: nothing here has been run on a real TFS 1.4.2 / OTClient.** `server/tests/admin_panel_test.lua` (CI, LuaJIT
and Lua 5.3) loads `core.lua` and every `actions_*.lua` against a mocked engine: every action registers with a valid
params schema, the permission levels hold, the catalog parts, the stash actions and a few Chaos actions run against mocked
systems. See "Untested" at the end.

## Install

1. Copy this directory to `data/scripts/chaos/admin/` of the server (revscript loader picks up every `.lua`).
2. Run `server/sql/chaos_admin.sql` against the server database (creates `chaos_admin_log`).
3. Copy `client/overlay/modules/game_admin` into the client `modules/` folder.
4. Edit `ChaosAdminConfig` at the top of `core.lua`:
   * `minGroup` (default 4): minimum group id to see/use the panel. The group must also have `getAccess() == true`.
   * `categoryMinGroup`, `dangerousMinGroup` (default 6), per-action `minGroup` in the action files.
   * `talkactionWhitelist` for the Tools > Run talkaction action.
5. Opcode is `CHAOS_ADMIN_OPCODE = 120` in `core.lua`; keep `OPCODE` in `admin.lua` identical.

## Files

| File | Purpose |
|---|---|
| `core.lua` | config, registry, permission checks, param validation, audit log, catalog, opcode handler |
| `actions_players.lua` | Players category |
| `actions_server.lua` | Server category |
| `actions_world.lua` | World category |
| `actions_economy.lua` | Economy category |
| `actions_events.lua` | Events category + built-in event hooks + experience event callback |
| `actions_content.lua` | Content category |
| `actions_security.lua` | Accounts & Security category |
| `actions_tools.lua` | Tools category |
| `actions_chaos_currency.lua` | Chaos: Currencies (Candlemarks, Conquest Tokens, Ember Cache points, beta starter coins) |
| `actions_chaos_progress.lua` | Chaos: Progression (seasons, season pass, achievements, the Ashen Chronicle) |
| `actions_chaos_class.lua` | Chaos: Classes (Vocation Trials, ascension quest, passive tree) |
| `actions_chaos_player.lua` | Chaos: Buffs & Gear (Ember Blessings, blessings and the Eternal Blessing, Idle Hall, equipment sets, item set bonuses, charms) |
| `actions_chaos_bosses.lua` | Chaos: Bosses & Events (pocket bosses, the Ashen Sepulchre raid, world bosses, invasions, treasure goblins) |
| `actions_chaos_instances.lua` | Chaos: Instances & PvP (every instance type, rifts, Infinity Tower, arena, battleground, guild siege) |
| `actions_chaos_social.lua` | Chaos: Guilds & Market (mentors, market and Orb Exchange sweeps, guild wars, weekly guild boss, community goal) |
| `actions_staff_tools.lua` | Tools: the staff chat commands of the Chaos systems as panel actions (`/testkit`, `/areagen`, `/creatorcodes`, `/itemfinder`, `/memorial`, `/hideout`, `/gmnotify`, `/telemetry`, `/records`) |
| `testkit.lua` | `/testkit` and `ChaosTestKit.give` (the panel's Tools > Test kit calls the same function) |
| `actions_store.lua` | Store category: sales dashboard (per day, category, top offers), recent purchases, donations (coin orders; Pix / PayPal with their provider status; refunds and chargebacks with the coins taken back), record a donation, give Chaos Coins (`chaos_shop_purchases`, `chaos_coin_orders`, `chaos_coin_payments`; server/README.md "Store") |

Action files only write into the global `ChaosAdminPending[id]`, so load order inside the folder does not matter. They
reach the Chaos systems only inside handlers, through `ChaosAdmin.system(name, fn)`: a system that is not loaded on a
server gives "X is not loaded on this server." instead of an error. `botreview.lua` and `reports.lua` add their own
Accounts & Security actions the same way.

## Security model

* Every opcode message from every player is checked on the server: `player:getGroup():getAccess()` and
  `group id >= ChaosAdminConfig.minGroup`. Non-admins get no reply at all (the client therefore never shows the panel);
  a denied attempt is logged (rate limited to one entry per 5 s).
* `run` re-checks the group against the action's required group (category default, `minGroup`, `dangerous`).
* Parameters are validated and coerced on the server from the action's `params` schema (type, range, options, length).
  Unknown keys are dropped. The client schema is only a UI hint; the `confirm` flag is client-side convenience only.
* Targets with an equal or higher group than the actor cannot be touched (except self); `set_group` cannot exceed own group.
  Offline targets too: `ChaosAdmin.targetAny` reads the character's group from `players`.
* The Chaos categories open at group 4 (a gamemaster inspects and fixes: views, cooldowns, a stuck character, the Idle
  Hall, closing an instance); whatever gives value (currencies, items, XP, points, tiers, charges) has `minGroup = 5`;
  whatever wipes progress or takes a paid thing (achievements, trials and ascension resets, season start / end, the
  Chronicle reset, the guild boss week reset, the Eternal Blessing removal, stash_remove) is `dangerous` (group 6).
* Requests are throttled (`throttleMs`, default 150 ms) and limited to 8 KB.
* Every attempt (ok, fail, denied, invalid) is written to the console and to `chaos_admin_log`.
* Handlers run in `pcall`; errors are reported as failed actions.

## Protocol (extended opcode 120, JSON strings)

Envelope in both directions: `{"action": "<name>", "data": { ... }}`

### Client -> server

| action | data | notes |
|---|---|---|
| `catalog` | none | request the catalog |
| `run` | `{"rid": <int>, "id": "<category.action>", "params": {name: value, ...}}` | run one action. `rid` is echoed back |

### Server -> client

`catalog`
```json
{"action":"catalog","data":{"group":6,"categories":[
  {"id":"players","label":"Players","actions":[
    {"id":"players.kick","name":"Kick","description":"...","confirm":true,"dangerous":false,
     "params":[{"name":"player","label":"Player","type":"player","required":true,
                "min":null,"max":null,"default":null,"options":null,"hint":null}]}]}]}}
```
Only categories/actions the requesting group may use are included.

`result`
```json
{"action":"result","data":{"rid":3,"id":"players.kick","ok":true,"message":"Bob was kicked.","lines":["optional","output lines"]}}
```

### Param types

`player` (name, validated charset), `string` / `text` (max length), `int` (min/max, numeric strings accepted),
`bool`, `select` (`options`: list of `{value,label}`; server accepts only listed values), `pos` ("x,y,z"),
`ip` ("a.b.c.d").

## Writing an action

```lua
ChaosAdminPending = ChaosAdminPending or {}
ChaosAdminPending["players.example"] = {
  id = "players.example", category = "players", name = "Example", description = "...",
  minGroup = 5,            -- optional, raised to category/global minimum
  dangerous = false,       -- true => requires dangerousMinGroup and confirm click
  confirm = false,
  params = {{name = "player", label = "Player", type = "player"}},
  handler = function(actor, p)   -- p = validated params
    return true, "message", {"optional", "lines"}   -- ok, message, lines
  end,
}
```
Categories are fixed in `core.lua` (`ChaosAdmin.categories`, each with a `categoryMinGroup`). Category and action labels
are English text sent by the server; the client shows them as they come (no `tr()` keys), as before.

The catalog for group 6 is about 60 KB (176 actions), sent in 8 parts of at most 8000 bytes by `Chaos.sendChunked`;
`tests/admin_panel_test.lua` checks the parts and their join.

## Hooks (events, dungeons, towers, bosses)

TFS 1.4.2 has no Lua API to fire an existing `GlobalEvent` by name, so existing systems are exposed through hooks:

```lua
ChaosAdminRegisterHook("worldboss", {
  kind = "boss",            -- "event" -> Events tab; "dungeon" | "tower" | "boss" | "other" -> Content tab
  description = "Spawn the world boss",
  start = function(actor, hook) ... return true, "message" end,   -- or the NAME of a global function
  stop = "myGlobalStopFunction",
  reset = function() ... end,
})
```
Built-in hooks: `weather_rain`, `double_exp`. No dungeon/tower hooks are registered by default because the
existing customs (`customs/dungeon`, `customs/tower_defense`, infinity tower) expose no known start/stop API;
add a `ChaosAdminRegisterHook` call next to them.

## Actions

Players: info, kick, ban (account), unban, mute, set_level, set_skill (raise only), set_vocation, give_item, remove_item,
give_premium, teleport_to, summon, heal, set_group (dangerous), add_storage (set storage).
give_item (Players) and create_item (World) create items, so they need group 5 like the Economy actions
(`minGroup = 5` on the action); the other Players and World actions stay at group 4.
The `/` commands outside the panel follow the same line (`Chaos.staffCommand(..., true)` in `chaos_constants.lua`,
docs/GM_HANDBOOK.md section 2: staff never give value): `/coins`, `/charm give`, `/pact`, `/rift key|omen|fragments`,
`/ascended sigil|shards|relic`, `/newplayerkit` (kit, milestone, reset), `/guild xp|bank` and `rent <guild>, paid`,
`/classunlock`, `/cosmetic`, `/exclusive` and `/transmog` grants and `/pet give` need group 5; the rest group 4. Every
staff use is in the admin log.
The staff ladder (docs/GM_HANDBOOK.md section 4, `ChaosAdminLadder` in `actions_players.lua`): mute takes 1 to 1440
minutes (24 h, default 60); a ban of 30 days or more (3650 = permanent) is refused below group 5 (administrator), a
shorter one (default 7 days) works from group 4. `tests/staff_permissions_test.lua` checks both.

Server: broadcast, save, reload (talkactions, scripts, monsters, npcs, config, actions, movements, creaturescripts,
globalevents, spells, weapons, items, quests, raids, mounts, chat, events, global, all; dangerous), shutdown / restart with
countdown (dangerous; announces at 60/30/10/5/... marks, saves, then `GAME_STATE_SHUTDOWN` - TFS cannot restart itself,
use a supervisor), cancel_countdown, set_state (open/close), online, stats.

World: spawn_monster, spawn_npc, create_item, remove_items (movable items on a tile), clean_map, set_time (only if
`Game.setWorldTime` exists), set_weather (rain storage from `customs/globalevents/rain.lua`), town_teleport, list_towns, start_raid.

Economy: give_gold, remove_gold, give_bank, item_price (item info + market table stats), market_offers, market_buy_orders
(Chaos market buy orders and the escrow they hold, read only), and the stash on the server's own system (`stash.lua`
`ChaosStash.staffGive` / `staffSummary` / `staffFind` / `staffRemove`; server/README.md "Stash"):
stash_give (an item made straight into a tab of an online character, Auto = routed like a deposit; through the journal:
the row first, the serial saved with the character, then the entry), stash_info (entries and items per tab, offline too;
with an item: the merged stack and every stored row with its id), stash_remove (dangerous: a row or an amount of a
merged stack taken out through the journal and destroyed). The stock `Player:addItemStash` is no longer used.

Events: list, start, stop (hooks), broadcast_template, set_exp (experience multiplier through `EventCallback.onGainExperience`).

Content: reload_content (quests / tasks via scripts reload), hooks, hook_run (dungeon/tower/boss hooks), boss_spawn.

Accounts & Security: account_lookup (never returns password/email), ban_list, ip_ban, ip_unban, ip_ban_list, sessions, admin_log.

Tools: talkaction (whitelisted legacy `data/talkactions/scripts/<name>.lua`, run in a throw-away environment as the caller),
invisible, ghost (group 6), god_mode (group 5; uses `healthchange` + `manachange` CreatureEvents), speed. Cheat tools only affect the caller.
The staff chat commands (`actions_staff_tools.lua`; the talkaction files are unchanged, the actions call the same
functions): testkit (5, `ChaosTestKit.give`), areagen_status, areagen_goto, creatorcodes_status (5), creatorcodes_run (5,
`ChaosCreatorCodes.round`), itemfinder (index, search, rebuild), memorial (status, refresh), hideout_enter
(`ChaosHideout.enter`), gmnotify (`ChaosNotify.gmBroadcast`), telemetry (5, status, flush), records (5, status, rebuild).
`/botreview` and `/reports` are Accounts & Security actions already (registered by their own files).

### The Chaos actions

Group 4 unless marked (5) = administrator, (D) = dangerous, group 6. Every one is in the audit log.

* Chaos: Currencies: candlemarks_view (offline too), candlemarks_give (5), candlemarks_take (5), candlemarks_ip_reset (the
  character goes first in its IP's earning order); conquest_view, conquest_give (5), conquest_take (5, a conditional
  update), conquest_pity_reset; embers_view, embers_give (5, `ChaosEmberCache.credit` by source), embers_take (5);
  beta_view, beta_give (5, `ChaosBeta.grantStarter`, once per account).
* Chaos: Progression: season_status, season_player, season_start (D), season_end (D) (the server_config override of
  `/season start|end`); pass_view, pass_xp (5); achievements_view, achievements_grant (5), achievements_stat (5),
  achievements_reset (D); chronicle_status, chronicle_world, chronicle_complete (5), chronicle_reset (D).
* Chaos: Classes: trials_view, trials_cooldown, trials_tier (5), trials_tokens (5), trials_reset (D); ascension_view,
  ascension_cooldown, ascension_stage (5), ascension_reset (D), ascension_set (5, `ChaosAscension.ascend` as
  `/ascendset`); tree_view, tree_points (5, extra points +/-), tree_reset (5, the free reset of every preset).
* Chaos: Buffs & Gear: embers_blessing_view, embers_blessing_give (5), embers_blessing_clear; blessings_view,
  blessings_grant (5), blessings_remove; eternal_grant (5), eternal_remove (D); idlehall_send, idlehall_release;
  gearset_list, gearset_give (5, a set piece with rarity and item level through `ChaosCrafting.createItem`),
  itemsets_state (the set bonuses active); charm_give (5, as `/charm give`).
* Chaos: Bosses & Events: pocket_view, pocket_set (5, daily left and bonus), pocket_reset_day, pocket_runs; raid_status,
  raid_lockouts, raid_reset_lockouts (5); worldboss_status, worldboss_start (5), worldboss_stop (5); invasion_status,
  invasion_start (5), invasion_stop (5); goblin_spawn (5).
* Chaos: Instances & PvP: instances_list, instances_close (any instance type: dungeons, rifts, tower, raids, pockets,
  trials, ascension, arena, battleground, siege, ...), instances_lines; rift_status, rift_omen_key (5); tower_season,
  tower_pay (5), tower_record (5, as `/towerrun`); arena_status (ratings of a player too), arena_stop (5); bg_status,
  bg_stop (5); siege_status, siege_control (5: start, open gates, end, cancel).
* Chaos: Guilds & Market: mentor_view, mentor_unlink; market_sweep (5); orbx_escrow, orbx_sweep (5); guildwar_list,
  guildwar_end (5); guildboss_status, guildboss_fuel (5), guildboss_reset (D); community_status.

Where a system has a public function the action calls it. Where its staff command writes by itself (Candlemarks and
Conquest give / take, the pocket charge row, the raid lockout reset, the mentor unlink, the guild boss fuel and week),
the action runs the same single statement on the system's own table name and updates the system's cache; no talkaction
file was changed.

Skipped (staff commands left in the chat, no panel action yet): `/pact` (days, extras: account-wide paid value, kept to
the command and the store), `/marches` (test toggles), `/faction`, `/atlas`, `/daily`, `/leaderboard`, `/journey`,
`/descent`, `/guild`, `/cosmetic`, `/exclusive`, `/transmog`, `/pet`, `/classunlock`, `/professions`, `/referral`,
`/gamble`, `/poi`, `/patchnotes`, `/supports`, `/spells`, `/treestats`, `/newplayerkit`, `/ascended`, `/coins` (Store >
Give Chaos Coins exists), `/market info`, `/orbx info`, `/guildwar expire`, `/areagen fill`, `/raid` fight helpers
(kill, phase, mech, stacks), `/rift key|fragments|lives`, `/invasion schedule|wave|breach|event`, `/siege portal|arena|signup|clear`:
their state is private to the system file (a local function or table) or a fight test helper, and the talkaction
files were not to be changed.

## Untested / assumptions

* Nothing was executed against TFS 1.4.2; API names were written from memory of TFS 1.4.x and from the base server scripts
  (`ban.lua`, `ipban.lua`, `reload.lua`, `force_raid.lua`, ...). Anything marked "if supported" is guarded.
* Assumed schema: `players`, `accounts`, `account_bans`, `ip_bans`, optionally `market_offers` (standard TFS 1.4.2 columns).
  `ip` values use the same encoding as `Player:getIp()` (`Game.convertIpToString`).
* `set_skill` uses `Vocation:getRequiredSkillTries/ManaSpent` + `addSkillTries/addManaSpent`; cannot lower skills.
* `mute` uses `CONDITION_MUTED`, which TFS only applies to some chat paths; verify it blocks speech on your build.
* The exp event assumes this server's `EventCallback.onGainExperience` is actually invoked by the engine
  (`data/scripts/lib/event_callbacks.lua` lists it, the engine side was not verified). The server also has its own `storage 6000` 2x exp.
  Both count under the global experience cap (`xpcap.lua`, index 85: at most 4x a kill's base; server/README.md "Experience
  cap"), so `double_exp` doubles only while the other bonuses leave room.
* `god_mode` relies on per-player `healthchange`/`manachange` CreatureEvents.
* Admin log DB writes use `db.asyncQuery`.
* The Chaos actions (`actions_chaos_*.lua`, `actions_staff_tools.lua`) and the stash actions are unit tested against
  mocked systems only (`tests/admin_panel_test.lua`; the stash's staff functions also against the stash test's in-memory
  database, `tests/stash_test.lua`). None was run on a live server or in a client. Not checked live in particular: the
  sizes of the 60 KB catalog in 8 parts at login, `Player:removeBlessing`, the gear set piece forge with a high item
  level, the season override picked up by the season check, the Idle Hall move and release, the pocket charge row
  written beside a running pocket.
