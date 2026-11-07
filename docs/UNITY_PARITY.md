# Unity client parity with the main client

Goal: a player can use either client on the same server, later only Unity (O405, track D).
This file lists every module of the main client (`client/overlay/modules/`, 169 of them) with its opcode, what Unity has, a priority and an effort.
It also lists the base protocol opcodes the Unity parser lacks and a plan in three phases.
Edit the module rows by hand when a status changes. A module row changes in the same commit as its Unity window.

Counts: 1 done, 16 partial, 137 missing, 15 not applicable.
By priority: 13 P0 core loop, 30 P1 needed to play, 83 P2 systems, 28 P3 polish, 15 N/A.

## Who Unity is on the server

The server gates on the OS word, the markers of the game login and the client version word.
Full audit and the byte layout: `unity/README.md` "Both clients".
- OS word 21. The engine turns extended opcodes on from 10 up (src-patches 0015, 0021, base `login`), so Unity always got every Chaos opcode.
  `server/tools/loadtest.py` proves it: OS 10 and no markers, and the Chaos modules talk to its bots.
- Markers `u16 0` (identity Extended, the default): plain 10.98 wire. No feature list, plain outfits, one 0x64 map, no item attributes, no compression.
- Markers of the main client (identity Chaos, `CHAOS_UNITY_IDENTITY=chaos`): feature list 0x43, outfits with wings, aura and shader, 0x4B floors, item attributes (feature 126), 16-bit spell ids (feature 152).
  Parsed and tested on a fake server. Not yet run against a live server.
- Client version word `0x4343 << 16 | build`, the guard handshake on 189 and the hello on 190 are done. The real guard key is never embedded by default.

## Core loop (base protocol features)

| Feature | Unity | Note |
|---|---|---|
| Account login, character list | done | `LoginClient`. No character creation form. |
| Game login, guard handshake, pings | done | `GameSession`. |
| Map, floors, 8 directions, light | done | 18 x 14 tiles read, 15 x 11 shown. Another aware range is refused. |
| Walk by keys and by click | done | No auto-walk to a clicked tile (0x64 from the client), no stop. |
| Attack, follow, cancel, battle list | done | `BattleListWindow`. Fight modes and secure mode (0xA0) are sent at the login and on change (`FightWindow`, saved in PlayerPrefs). |
| Spells, hotbar, cooldowns | partial | This track: spellbook, 12 hotbar slots with cooldown numbers. No item or rune slots, no icons. |
| Chat | done | Tabs (Default, Server Log, channels, private), channel list, `*name* text`, `#y` and `#w`, unread counts, floating speech. No item links, no channel creation or invites. |
| Containers, equipment, use, move | partial | Open, close, up, use, drag. No split stack dialog, no use-with, no look. |
| NPC trade, NPC talk | missing | 0x7A, 0x7B, 0x7C and the buy and sell requests. |
| Death | partial | 0x28 shows a death window with the penalty; OK goes to the character list. No recap window. |
| Party | missing | The shield (0x91) is read. No invite, join, leave, no frames. |
| Outfit window | missing | 0xC8 and the set outfit request. Chaos identity brings wings, aura and shader fields. |
| Skills, stats | partial | `SkillsWindow` reads 0xA0 and 0xA1. |
| Text windows (books, signs), house windows | missing | 0x96, 0x97. |
| Look, use with, use on creature | missing | Needed for runes, tools, doors with keys. |
| VIP list, quest log | missing | |
| Player trade | missing | 0x7D, 0x7E, 0x7F. |


## The 169 client modules

Status: done, partial, missing, or N/A (platform code of the main client that Unity does not need). Priority: P0 core loop, P1 needed to play the whole game, P2 systems and windows, P3 polish. Effort: S under a day, M a few days, L a week or more.

| Module | Opcode | What it does and where Unity is | Status | Prio | Effort |
|---|---|---|---|---|---|
| `client_chaos_charselect` | none | Character cards and creation. Unity lists the characters from the login answer; no cards, no creation form. | partial | P0 | M |
| `client_chaos_login` | none | Login screen. Unity has account, password, server fields and the logo; no news, no medallions. | partial | P0 | M |
| `game_bagpanel` | none | Inventory panel. Unity has an equipment window and a containers window with drag and use; no tabs, no outfit, no coins. | partial | P0 | M |
| `game_chaosguard` | 190 | Client guard hello (opcode 190) and the 189 handshake in Core/ClientGuard.cs. | done | P0 | S |
| `game_chaoshud` | none | Character plate. Unity shows health and mana bars and numbers; no portrait, no experience chip. | partial | P0 | M |
| `game_chaosspells` | 219 | Chaos spells in the spell list and action bar. Unity takes the list from opcode 219; no icon sheets. | partial | P0 | S |
| `game_chatpanel` | none | Chat panel. Unity: tabs, Ctrl+O channel list (chat line focused), Ctrl+E close tab, Tab / Shift+Tab, private tabs, history cap, unread counts. No custom channel creation, no layout modes. | done | P0 | M |
| `game_floatchat` | none | Floating chat over the map: lines float over the speaker in the classic and the front-art live view, 60 ms per character (3 to 12 s), 3 stacked. | done | P0 | M |
| `game_hotbar` | none | Central hotbar. Unity has 12 F-key slots that say a line or a spell, saved per character, with cooldown numbers; no ornate frame, no globes, no item or rune slots. | partial | P0 | M |
| `game_npctalk` | none | NPC dialogue. Needs the NPC speech (0xAA types) and channel handling. | missing | P0 | M |
| `game_npctradewindow` | 113 | NPC buy and sell list. Needs 0x7A, 0x7B, 0x7C and the buy and sell requests. | missing | P0 | L |
| `game_partyframes` | 235 | Party member frames. Party shield (0x91) is read; no frames. | missing | P0 | M |
| `game_spellbook` | 219 | Spellbook. Unity has the list, filters, search, cast by click, hotkey assignment; no area preview, no icons. | partial | P0 | M |
| `client_chaos_locale` | 157 | English and pt-BR texts. Core/Loc.cs does it for Unity windows; no language option in a menu yet. | partial | P1 | S |
| `client_chaos_topbar` | 115 | Top menu with unlocks by level. Unity has a flat toolbar of windows. | missing | P1 | L |
| `game_antibot` | 211 | Presence check modal and report dialog (antibot.lua). Unity cannot answer a check yet. | missing | P1 | S |
| `game_bank` | 60 | Bank window. | missing | P1 | M |
| `game_buffbar` | 234 | Buff and debuff icons with timers. | missing | P1 | M |
| `game_castbar` | 231 | Cast bar for cast time spells. | missing | P1 | S |
| `game_chaosinfo` | 237 | Info and Services window. | missing | P1 | M |
| `game_chaosnotify` | 79 | Toasts. Many systems report through it. | missing | P1 | M |
| `game_chaosscale` | 157 | Display scale factor for numbers. | missing | P1 | S |
| `game_damagescatter` | none | Typed damage numbers. Needs the 0xB4 fields (capability bit 7); the text parser is track B. | missing | P1 | M |
| `game_deathrecap` | 154 | Death recap window. Unity shows a death window (0x28); no recap data (opcode 154). | missing | P1 | M |
| `game_energyshield` | 224 | Energy shield bar. The server sends plain text es:cur:max. | missing | P1 | S |
| `game_goals` | 178 | Next Goals window and tracker. | missing | P1 | M |
| `game_groundlabels` | 230 | Loot labels on the ground. | missing | P1 | M |
| `game_helper` | none | The helper: heals, potions, rotation, auto target. A large part of the play loop for many players. | missing | P1 | L |
| `game_helperrotation` | 116 | Helper cast bookkeeping and Auto rotation; Everfull potions on 116. | missing | P1 | M |
| `game_hunt` | 241 | Hunt tracker. | missing | P1 | M |
| `game_itemrarity` | 126 (feature) | Item rarity. Item attributes are parsed in Chaos identity (Item.Attr); nothing draws a rarity frame yet. | partial | P1 | M |
| `game_itemtooltip` | 242 | Rich item tooltips. | missing | P1 | L |
| `game_kitewalk` | 186 | Option: keep attacking while moving. One message on opcode 186. | missing | P1 | S |
| `game_lootfilter` | 238 | Loot filter and loot channel. | missing | P1 | M |
| `game_monkchi` | 247 | Monk chi pips. Server text chi:chi:max:decay. | missing | P1 | S |
| `game_monsterbar` | 125 | Tiered monster health bar. | missing | P1 | M |
| `game_passivetree` | 65 | Passive tree. Opcode 65. Large JSON in chunks. | missing | P1 | L |
| `game_rift` | 228 | Rift run HUD. | missing | P1 | M |
| `game_rightclickequip` | 188 | Option: right-click equips. One message on opcode 188. | missing | P1 | S |
| `game_shop` | 218 | Chaos store. | missing | P1 | L |
| `game_simpleskills` | none | Melee, Ranged, Magic, Shielding rows. Unity lists the seven weapon skills. | partial | P1 | S |
| `game_skillstats` | 119 | Combat stat rows in the skills window. | missing | P1 | S |
| `game_stash` | 110 | Supply Stash. | missing | P1 | M |
| `client_chaos_infolift` | none | Name and bar lift for tall looks. | missing | P2 | S |
| `client_chaos_numbers` | none | Short numbers (1k, 2.45M). | missing | P2 | S |
| `client_chaos_screenfit` | none | Windows taller than the screen scroll. Unity clamps the title bar only. | missing | P2 | S |
| `client_chaos_theme` | none | Dark fantasy UI theme. Unity windows use one flat dark style. | partial | P2 | M |
| `game_achievements` | 250 | Achievements window. | missing | P2 | M |
| `game_arena` | 236 | Ranked PvP arena queue and HUD. | missing | P2 | M |
| `game_autoloot` | 216 | Auto loot lists. | missing | P2 | M |
| `game_autotarget` | none | Auto Target choice rules of the helper. | missing | P2 | M |
| `game_badgeslot` | none | Badge slot 13 in the equipment. Unity equipment draws 10 slots. | missing | P2 | S |
| `game_battleground` | 200 | Battleground queue, HUD and scoreboard. | missing | P2 | L |
| `game_battlepass` | 227 | Season pass window. | missing | P2 | M |
| `game_bestiary` | 253 | Bestiary, kill tasks and tracker. | missing | P2 | M |
| `game_bounty` | 223 | Bounty board. | missing | P2 | M |
| `game_candlemarks` | 176 | Candlemarks counter and shop. | missing | P2 | M |
| `game_chaoslayout` | none | Saved window layout per character. | missing | P2 | M |
| `game_chaosshaders` | none | Outfit shaders. The shader name is parsed in Chaos identity, nothing draws it. | partial | P2 | L |
| `game_chaossound` | none | Game sounds. | missing | P2 | M |
| `game_chaosuiscale` | none | Interface scale. Unity scales with the window height. | partial | P2 | S |
| `game_chaosview` | none | Map zoom and the largest map area. Unity shows 15 x 11 tiles. | missing | P2 | S |
| `game_chaosweather` | 114 | Rain and ambient particles. | missing | P2 | M |
| `game_charms` | 198 | Charms grid. | missing | P2 | M |
| `game_chatlinks` | 249 | Item links in chat. | missing | P2 | M |
| `game_codex` | none | Codex encyclopedia, static data from the server tools. | missing | P2 | L |
| `game_conquest` | 167 | Conquest vendor window. | missing | P2 | M |
| `game_cosmetics` | 225 | Cosmetics window. | missing | P2 | L |
| `game_crafting` | 232 | Crafting bench. | missing | P2 | M |
| `game_craftingtable` | 91 | Base crafting tables. | missing | P2 | M |
| `game_craftskills` | none | Profession skills in the skills window (skills packet extra rows). | missing | P2 | S |
| `game_daily` | 207 | Daily reward window. | missing | P2 | S |
| `game_deadguard` | none | Removes a dead monster left at 0 percent after 3 seconds. | missing | P2 | S |
| `game_descent` | 205 | Ember Descent trial HUD and boons. | missing | P2 | L |
| `game_dpsmeter` | 204 | DPS meter and combat log. | missing | P2 | M |
| `game_dungeons` | 109 | Dungeon finder. | missing | P2 | M |
| `game_embercache` | 174 | Ember Cache and day book. | missing | P2 | M |
| `game_factions` | 215 | Factions window. | missing | P2 | M |
| `game_gamble` | 199 | The Gambler window. | missing | P2 | M |
| `game_groundfx` | none | Spell effects under creatures. | missing | P2 | M |
| `game_groupqueue` | 160 | Group queue and ready check. | missing | P2 | M |
| `game_guild` | 252 | Guild window. | missing | P2 | L |
| `game_guildwar` | 197 | Guild wars and guild boss. | missing | P2 | L |
| `game_helperhud` | none | Helper HUD on the map. | missing | P2 | S |
| `game_helpersupport` | none | Helper support spell tab. | missing | P2 | M |
| `game_helpertimers` | none | Helper cooldown channels. | missing | P2 | M |
| `game_helpsearch` | none | Help search over How it works, unlocks and Codex. | missing | P2 | M |
| `game_hideout` | 192 | Hideout decoration and visits. | missing | P2 | L |
| `game_howitworks` | none | How it works cards. | missing | P2 | S |
| `game_hudmove` | none | Movable HUD panels. | missing | P2 | S |
| `game_infinitytower` | 214 | Infinity Tower window. | missing | P2 | M |
| `game_invasion` | 251 | Invasion HUD and event list. | missing | P2 | M |
| `game_itemfinder` | 155 | Item finder. | missing | P2 | M |
| `game_leaderboard` | 229 | Leaderboards. | missing | P2 | M |
| `game_loadouts` | 206 | Loadouts (Armory). | missing | P2 | M |
| `game_lookpreview` | none | Look preview panel. | missing | P2 | M |
| `game_lootscreen` | none | Hides the loot line on the game screen. | missing | P2 | S |
| `game_mapmarkers` | 153 | Party and point markers on the minimap, NPC quest marks. | missing | P2 | M |
| `game_mapoverlay` | 245 | Explored map overlay on the game view. | missing | P2 | M |
| `game_market` | 221 | Player market. | missing | P2 | L |
| `game_minimapsync` | none | Minimap after death or teleport. Unity has a minimap window; no marker sync. | partial | P2 | S |
| `game_nameplate` | 248 | Name plates with titles and frames. | missing | P2 | S |
| `game_npctravel` | 121 | Go to NPC button. | missing | P2 | S |
| `game_orbexchange` | 209 | Orb Exchange. | missing | P2 | M |
| `game_outfitextras` | none | Customise Character window. | missing | P2 | L |
| `game_pact` | 222 | Chaos Pact window. | missing | P2 | M |
| `game_partyfinder` | 208 | Party finder. | missing | P2 | M |
| `game_pets` | 254 | Pets window. | missing | P2 | M |
| `game_playerinspect` | 240 | Inspect player. | missing | P2 | M |
| `game_pouches` | 226 | Loot bag rules and auto seller. | missing | P2 | M |
| `game_professions` | 195 | Professions. | missing | P2 | M |
| `game_proficiencycatalog` | none | Weapon list of the proficiency window, built on the client. | missing | P2 | S |
| `game_pvpzone` | 193 | Scorched Marches zone. | missing | P2 | M |
| `game_raid` | 213 | Weekly raid window and HUD. | missing | P2 | L |
| `game_riftatlas` | 159, 210 | Rift Atlas and Waystone Atlas. | missing | P2 | L |
| `game_season` | 246 | Seasons window. | missing | P2 | M |
| `game_siege` | 233 | Guild siege HUD. | missing | P2 | M |
| `game_spellsupports` | 243 | Spell supports and action bar pips. | missing | P2 | M |
| `game_targetguard` | none | Which creatures Auto Target may pick. | missing | P2 | S |
| `game_tileoverlays` | 156 | Timers over fields and server bars on map tiles. | missing | P2 | S |
| `game_townportal` | 239 | Town Portal cast bar and style window. | missing | P2 | S |
| `game_transmog` | 212 | Transmog. | missing | P2 | M |
| `game_unlocks` | 225 | Owned and locked lists. | missing | P2 | S |
| `game_unveil` | 196 | Unveil window. | missing | P2 | S |
| `game_waystone` | 202 | Waystone device window. | missing | P2 | M |
| `game_weeklychest` | 117 | Weekly Chest. | missing | P2 | M |
| `client_chaos_credits` | none | Credits window from docs/CREDITS.md. | missing | P3 | S |
| `client_chaos_perf` | none | Performance overlay. | missing | P3 | S |
| `client_chaos_streamer` | none | Streamer and cinema mode. | missing | P3 | S |
| `client_chaos_uifade` | none | Window fade in and out. | missing | P3 | S |
| `game_admin` | 120 | Server driven admin panel. The admin app covers the owner. | missing | P3 | L |
| `game_bossanimate` | none | Idle animation for bosses with walk frames only. | missing | P3 | S |
| `game_bossspawns` | 217 | Boss spawn list. | missing | P3 | M |
| `game_cardborder` | 172 | Card border in deck windows. | missing | P3 | S |
| `game_chaosmusic` | none | Region music. | missing | P3 | M |
| `game_chaosshots` | none | Automatic screenshots. | missing | P3 | S |
| `game_chaossurvey` | 122 | New player survey. | missing | P3 | S |
| `game_chestaura` | 118 | Auras under chests and Templar sigils. | missing | P3 | M |
| `game_chronicle` | 171 | Ashen Chronicle and memorial. | missing | P3 | M |
| `game_combatdecals` | none | Stains on the ground after combat. | missing | P3 | M |
| `game_community` | 203 | Community goal window. | missing | P3 | M |
| `game_cosmeticfx` | 225 | Footprints and outlines. | missing | P3 | M |
| `game_dropfeed` | 229 | Drop feed option. | missing | P3 | S |
| `game_effectopacity` | none | Spell effect opacity option. | missing | P3 | S |
| `game_errorcolor` | none | Error messages in their own colour. | missing | P3 | S |
| `game_event` | none | Event manager. | missing | P3 | S |
| `game_levelwings` | 191 | Level up effect. | missing | P3 | S |
| `game_lootbeams` | none | Beams over loot corpses. | missing | P3 | S |
| `game_mentor` | 194 | Mentors. | missing | P3 | M |
| `game_nameshaders` | none | Name shaders (needs engine work in the main client too). | missing | P3 | M |
| `game_nemesis` | 163 | Nemesis tab. | missing | P3 | S |
| `game_patchnotes` | 244 | Patch notes window. | missing | P3 | S |
| `game_referral` | 220 | Referral. | missing | P3 | S |
| `game_visualfx` | none | Hit flash, shake and other map effects. | missing | P3 | M |
| `client_chaos_firststart` | none | Android first start: downloads game data. Unity gets its data from the build. | N/A | N/A | S |
| `client_chaos_phonetest` | none | Android emulator smoke test. | N/A | N/A | S |
| `client_chaos_rmlform` | none | RmlUi form layer of the main client. Unity has its own UI. | N/A | N/A | L |
| `client_chaos_rmlmirror` | none | RmlUi window mirror of the main client. | N/A | N/A | L |
| `client_chaos_rmloptions` | none | RmlUi options window of the main client. | N/A | N/A | M |
| `client_chaos_rmltest` | none | RmlUi spike test window. | N/A | N/A | S |
| `client_chaos_settings` | none | g_settings list helper. Unity uses PlayerPrefs. | N/A | N/A | S |
| `client_chaos_updater` | none | Signed updater of the main client. Unity ships through the launcher (O314). | N/A | N/A | L |
| `client_terminal` | none | Console stand-in. | N/A | N/A | S |
| `game_mobilebag` | none | Phone item cells. | N/A | N/A | S |
| `game_mobilehud` | none | Phone hotbars off. | N/A | N/A | S |
| `game_shaderfx` | none | UI widget shaders of the main client. Unity does its own. | N/A | N/A | M |
| `game_sidepanelfit` | none | Side panel height of the main client layout. | N/A | N/A | S |
| `game_touchscroll` | none | Phone swipe scroll. | N/A | N/A | S |
| `game_walkpad` | none | Phone walking pad. | N/A | N/A | S |

## Base protocol opcodes the Unity parser lacks

Built from the 10.98 opcode table the main client parses. The engine source is not in this repo, so confirm on a live run:
`GameSession` logs `parse: unknown opcode 0xNN` for every opcode it cannot read and the rest of that packet is lost.
Track B adds 0x83, 0x84, 0x85 and 0xB4 detail in parallel. They are not listed as missing here.

Server to client, not read by `GameParser`:

| Opcode | Meaning | Needed for | Prio |
|---|---|---|---|
| 0x0B | GM actions | none | P3 |
| 0x33, 0x42 other sizes | change of the aware range | a larger view than 18 x 14 (map zoom, game_chaosview) | P2 |
| 0x7A | open NPC shop | NPC trade | P0 |
| 0x7B | player goods (sell list) | NPC trade | P0 |
| 0x7C | close shop | NPC trade | P0 |
| 0x7D, 0x7E, 0x7F | player trade offer, counter offer, close | trade between players | P2 |
| 0x96 | text window | books, signs, writeable items | P1 |
| 0x97 | house window | houses | P2 |
| 0xA8, 0xA9 | creature square and cancel variants | none known | P3 |
| 0xAE | rule violation channel | none (Chaos has its own reports) | P3 |
| 0xB6 | walk wait | smoother walking on slow ground | P2 |
| 0xB7, 0xB8 | unjustified points, PvP situation | PvP skull display | P2 |
| 0xC8 | outfit window | outfit change, mounts, extended outfit lists | P1 |
| 0xD4 | VIP logout | VIP list | P2 |
| 0xDE | edit VIP | VIP list | P3 |
| 0xF0, 0xF1 | quest log, quest line | quest log | P2 |
| 0xF6 to 0xF9 | base market | none (Chaos market uses opcode 221) | P3 |
| 0xFA | modal window | modal dialogs of base scripts | P1 |
| 0xDF, 0xEE | coin and resource balance | base store, resources | P2 |

Inside packets Unity reads, it skips or ignores: 0x9F spell list body, 0xDD map flags (read, not shown), 0x8D to 0x95 creature fields beyond the ones in `Creature`.

Client to server packets Unity sends: walk and turn, say, use, move, close, up, attack, follow, pong, logout, extended opcodes.
Sent by the chat track: talk with type, channel or receiver (0x96), channels (0x97 to 0x9A), NPC channel close (0x9E), fight modes (0xA0). Read by it: 0xAA all 10.98 talk types (position for 1, 2, 3, 9, 10, 36, 37; channel id for 6, 7, 8, 14; none for 4, 13, 15), 0xAB to 0xB3, 0xB4 console kinds by tab, 0x28 with death type and penalty (the main client enables both features). 0xA7 is not a fight mode echo in 10.98 (it stays read and ignored). The NPC channel tab is a chat tab named NPCs; trade is the NPC track's.
Not sent yet: use with (0x83), use on creature (0x84), look (0x8C), rotate (0x85), party (0xA3 to 0xA8), NPC shop (0x79 to 0x7C), outfit (0xD2, 0xD3, 0xD4), auto-walk (0x64), stop (0xBE), VIP (0xDC to 0xDE), quest log (0xF0, 0xF1), equip hotkey (0x77).

## Migration plan

### Phase 1: play parity (both clients on one server, track D to F)
Goal: a player can hunt, trade and group in Unity with the same account and character as in the main client.
1. Done in this track: identity, extended opcodes, JSON and chunks, spellbook, hotbar with cooldowns, UI texts in two languages.
2. Core loop rows with P0: NPC trade and talk (0x7A to 0x7C, `game_npctradewindow`, `game_npctalk`), chat channels and private messages, party actions and frames, death screen, fight modes, use with and look, outfit window.
3. P1 rows that change how a hunt feels: typed damage numbers (turn on capability bit 7 when the text parser reads the fields), buff bar, monster bar, tooltips and rarity frames, loot labels and filter, helper, anti-bot presence check, display scale, the two option messages (186, 188).
4. Run identity Chaos against a live server, record the feature list from the log line `Server features:`, then make Chaos the default.
5. Exit test: the tester bot checks (`server/tools/tester_checks.py`) pass with a Unity driven account, and a human plays 2 hours without a missing window.

### Phase 2: full parity
Goal: every module of the table is done or N/A.
1. P2 windows by group: economy (shop, market, orb exchange, stash, bank, crafting), social (guild, party finder, mentor), progression (passive tree, atlas, season, achievements, goals), PvP (arena, battleground, zones).
   Most are JSON windows on one opcode. Build a small widget kit first (tabs, grids, lists, tooltips) so each window is a few hundred lines.
2. P3 polish: music, sound, weather, decals, shaders on outfits and names, streamer mode, credits.
3. Chunked payloads through `ExtOpcodes` need no change. Add an inflater for packet compression before the owner turns `packetCompression` on for Unity players.
4. Keep the table current: a module row changes status in the same commit as its window.

### Phase 3: the switch
Goal: Unity is the game, the main client is retired.
1. Launcher (O314) installs Unity by default, the main client stays as a fallback for one season.
2. Remove the server paths that exist only for the main client when nothing uses them: the OS gate stays, the markers stay (they are the Unity identity too).
   Engine gates on the OTCv8 marker are the contract of the Chaos identity, so they stay.
3. Move art tooling to Unity: sprite pair import, HD-2D, 3D characters (see `unity/README.md`).
4. Retire the Lua client modules and their `check_*` CI steps only after phase 2 is complete and a season has run on Unity.
5. Mobile: the Android client (O313) is a separate track and needs a Unity build for Android before it can switch.
