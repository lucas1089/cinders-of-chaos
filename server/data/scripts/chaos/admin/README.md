# Chaos admin panel

Server side of the in-game administrator panel (client module: `client/overlay/modules/game_admin`).
Everything is driven by a registry of actions; the client builds its forms from the `catalog` message.

**Status: nothing here has been run on a real TFS 1.4.2 / OTClient.** Only `luac -p` syntax checks and a
mock-API smoke test (catalog build + dispatch path) were done. See "Untested" at the end.

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
| `actions_store.lua` | Store category: sales dashboard (per day, category, top offers), recent purchases, donations (coin orders; Pix / PayPal with their provider status; refunds and chargebacks with the coins taken back), record a donation, give Chaos Coins (`chaos_shop_purchases`, `chaos_coin_orders`, `chaos_coin_payments`; server/README.md "Store") |

Action files only write into the global `ChaosAdminPending[id]`, so load order inside the folder does not matter.

## Security model

* Every opcode message from every player is checked on the server: `player:getGroup():getAccess()` and
  `group id >= ChaosAdminConfig.minGroup`. Non-admins get no reply at all (the client therefore never shows the panel);
  a denied attempt is logged (rate limited to one entry per 5 s).
* `run` re-checks the group against the action's required group (category default, `minGroup`, `dangerous`).
* Parameters are validated and coerced on the server from the action's `params` schema (type, range, options, length).
  Unknown keys are dropped. The client schema is only a UI hint; the `confirm` flag is client-side convenience only.
* Targets with an equal or higher group than the actor cannot be touched (except self); `set_group` cannot exceed own group.
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
Categories are fixed in `core.lua` (`ChaosAdmin.categories`).

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
The staff ladder (docs/GM_HANDBOOK.md section 4, `ChaosAdminLadder` in `actions_players.lua`): mute takes 1 to 1440
minutes (24 h, default 60); a ban of 30 days or more (3650 = permanent) is refused below group 5 (administrator), a
shorter one (default 7 days) works from group 4. `tests/staff_permissions_test.lua` checks both.

Server: broadcast, save, reload (talkactions, scripts, monsters, npcs, config, actions, movements, creaturescripts,
globalevents, spells, weapons, items, quests, raids, mounts, chat, events, global, all; dangerous), shutdown / restart with
countdown (dangerous; announces at 60/30/10/5/... marks, saves, then `GAME_STATE_SHUTDOWN` - TFS cannot restart itself,
use a supervisor), cancel_countdown, set_state (open/close), online, stats.

World: spawn_monster, spawn_npc, create_item, remove_items (movable items on a tile), clean_map, set_time (only if
`Game.setWorldTime` exists), set_weather (rain storage from `customs/globalevents/rain.lua`), town_teleport, list_towns, start_raid.

Economy: give_gold, remove_gold, give_bank, item_price (item info + market table stats), market_offers, market_buy_orders (Chaos market buy orders and the escrow they hold, read only), stash_give, stash_info
(stash ones only if the build exposes the stash API).

Events: list, start, stop (hooks), broadcast_template, set_exp (experience multiplier through `EventCallback.onGainExperience`).

Content: reload_content (quests / tasks via scripts reload), hooks, hook_run (dungeon/tower/boss hooks), boss_spawn.

Accounts & Security: account_lookup (never returns password/email), ban_list, ip_ban, ip_unban, ip_ban_list, sessions, admin_log.

Tools: talkaction (whitelisted legacy `data/talkactions/scripts/<name>.lua`, run in a throw-away environment as the caller),
invisible, ghost (group 6), god_mode (group 5; uses `healthchange` + `manachange` CreatureEvents), speed. Cheat tools only affect the caller.

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
