# Unity client parity with the main client

Goal: a player can use either client on the same server, later only Unity (O405, track D).
This file lists every module of the main client (`client/overlay/modules/`, 169 of them) with its opcode, what Unity has, a priority and an effort.
It also lists the base protocol opcodes the Unity parser lacks and a plan in three phases.
Edit the module rows by hand when a status changes. A module row changes in the same commit as its Unity window.

Counts: 35 done, 33 partial, 86 missing, 15 not applicable.
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
| Chat | done | Tabs (Default, Server Log, channels, private), channel list, `*name* text`, `#y` and `#w`, unread counts, floating speech. Item links through game_chatlinks (Shift+click, coloured names, hover tooltip). No channel creation or invites. |
| Containers, equipment, use, move | partial | Open, close, up, use, drag. No split stack dialog, no use-with, no look. |
| NPC trade, NPC talk | done | `NpcTalkWindow`, `NpcTradeWindow`, `Core/NpcTrade.cs`. 0x7A, 0x7B, 0x7C in, 0x79, 0x7A, 0x7B, 0x7C out, NPC speech, currency (opcode 113). Not tried on the live server. No buy-in-backpacks fee, no modal windows. |
| Death | done | 0x28 shows a death window with the penalty; OK goes to the character list. The recap window (opcode 154) opens at the next login. |
| Party | done | `PartyFramesWindow` (Ctrl+G, opcode 235), right-click menu on a player (invite, join, revoke, pass leadership, leave, shared experience: 0xA3 to 0xA8), invitation box with Accept and Decline. Not run against a live server. |
| Outfit window | partial | `OutfitWindow` (Ctrl+U), `OutfitWindowState` in `Core/Dialogs.cs`: 0xD2 request, 0xC8 lists (outfits with addons, mounts; on identity Chaos wings, auras, shaders), colours, 0xD3 set. The Chaos ids' widths and the set packet's tail are read from the OTCv8 layout, not from this repo: check on a live run. No preview of wings, aura or shader. |
| Skills, stats | done | `SkillsWindow` reads 0xA0 and 0xA1, the simple skill list (Melee, Ranged, Shielding, Fishing, Fist for the Monk line) and the combat stat rows (opcode 119). |
| Text windows (books, signs), house windows | done | 0x96 in (the item with its attributes, text, writer, date), 0x89 write, 0x97 door list, 0x8D answer. `ChaosApp.Items.cs`, `TextWindows`. Not run on a live server. |
| Modal windows | done | 0xFA in (title, message, buttons, choices, escape and enter button, priority), 0xF9 answer. Queue, Enter and Escape keys. `ModalWindows`. |
| Look, use with, use on creature | missing | Needed for runes, tools, doors with keys. |
| VIP list, quest log | missing | |
| Player trade | missing | 0x7D, 0x7E, 0x7F. |


## The 169 client modules

Status: done, partial, missing, or N/A (platform code of the main client that Unity does not need). Priority: P0 core loop, P1 needed to play the whole game, P2 systems and windows, P3 polish. Effort: S under a day, M a few days, L a week or more.

| Module | Opcode | What it does and where Unity is | Status | Prio | Effort |
|---|---|---|---|---|---|
| `client_chaos_charselect` | none | Character cards and creation. Unity draws cards from the login answer (outfit, name, level, class, world), keys and Enter; "Create character" opens the website page (createcharacter.php), as the login server only lists. No wings, aura, shader, season or last-login line (those come from the website account API). | partial | P0 | M |
| `client_chaos_login` | none | Login screen. Unity has account, password, server fields and the logo; no news, no medallions. | partial | P0 | M |
| `game_bagpanel` | none | Inventory panel. Unity has an equipment window and a containers window with drag and use; no tabs, no outfit, no coins. | partial | P0 | M |
| `game_chaosguard` | 190 | Client guard hello (opcode 190) and the 189 handshake in Core/ClientGuard.cs. | done | P0 | S |
| `game_chaoshud` | none | Character plate: outfit portrait, name, level, health and mana bars (right-click: percent), experience line with the percent to the next level (0xA0). No opcode in the main client either. No eased bars, not movable. | partial | P0 | M |
| `game_chaosspells` | 219 | Chaos spells in the spell list and action bar. Unity takes the list from opcode 219; no icon sheets. | partial | P0 | S |
| `game_chatpanel` | none | Chat panel. Unity: tabs, Ctrl+O channel list (chat line focused), Ctrl+E close tab, Tab / Shift+Tab, private tabs, history cap, unread counts. No custom channel creation, no layout modes. | done | P0 | M |
| `game_floatchat` | none | Floating chat over the map: lines float over the speaker in the classic and the front-art live view, 60 ms per character (3 to 12 s), 3 stacked. | done | P0 | M |
| `game_hotbar` | none | Central hotbar. Unity has 12 F-key slots that say a line or a spell, saved per character, with cooldown numbers; no ornate frame, no globes, no item or rune slots. | partial | P0 | M |
| `game_npctalk` | none | NPC dialogue: private NPC speech (0xAA type 10), words to the NPC (0x96 type 12), quick words, {keyword} chips. No speech bubble over the NPC, no walk-up on Talk. | partial | P0 | M |
| `game_npctradewindow` | 113 | NPC buy and sell list: tabs, search, amount slider, total, currency of opcode 113. No buy-in-backpacks option. | done | P0 | L |
| `game_partyframes` | 235 | Party member frames. `Core/Party.cs`, `PartyFramesWindow`: outfit, class colour, level, leader mark, health and mana bars, state, distance, shared experience bonus, invite box. No buff icons, no settings window, not movable as a panel. | partial | P0 | M |
| `game_spellbook` | 219 | Spellbook. Unity has the list, filters, search, cast by click, hotkey assignment; no area preview, no icons. | partial | P0 | M |
| `client_chaos_locale` | 157 | English and pt-BR texts. Core/Loc.cs for Unity windows; the Options window (Ctrl+L) has the language selector (PlayerPrefs chaos.lang) and tells the server by hello on 157. Server texts follow the choice. | done | P1 | S |
| `client_chaos_topbar` | 115 | Top menu with unlocks by level. | partial | P1 | L |
| `game_antibot` | 211 | Presence check modal (click the picture of the word, countdown, another picture, answer) and the report dialog (reasons from the server, name, note), from the player right-click menu and Options. `Core/Hud.cs` Antibot, `ChaosApp.Hud.cs`. Items drawn from client ids. | done | P1 | S |
| `game_bank` | 60 | Bank window (Ctrl+J): balances, deposit, withdraw, transfer with amount box and slider, deposit all, withdraw all, the banker NPC opens it. `Core/Bank.cs`, `BankWindow`. Gold only. Not run on a live server. | done | P1 | M |
| `game_buffbar` | 234 | Buff and debuff squares (initials, colour by key, red for debuffs) with timers, stacks and Alt tooltip under the plate. `Core/Hud.cs` BuffBar. No icon art. | partial | P1 | M |
| `game_castbar` | 231 | Own cast bar (click cancels) and bars over other casters. `Core/Hud.cs` CastBar. The Town Portal hand-off is not ported. | done | P1 | S |
| `game_chaosinfo` | 237 | Info and Services window. | done | P1 | M |
| `game_chaosnotify` | 79 | Toasts: 21 types with colours and times, three at once, queue of 12, wrapped height, Accept and Decline or Start on opcodes 151 and 152, danger line. `Core/Hud.cs` ToastCenter. No icons or monster look in the toast; catacomb Start sends without the protection zone check. | partial | P1 | M |
| `game_chaosscale` | 157 | Factor kept from the scale message and hello on login and level change; the server scales its own numbers. Shown in Options (read only). | done | P1 | S |
| `game_damagescatter` | none | Typed damage numbers. `GameParser.TextMessage` reads the 0xB4 fields (percent, type, creature) with feature 155; capability bit 7 is on; the live view scatters, sizes (critical bigger, condition smaller) and colours them and numbers follow their creature (`Core/DamageScatter.cs`). No option to turn the scatter off or set its level yet; no type fonts. | partial | P1 | M |
| `game_deathrecap` | 154 | `DeathRecapWindow` (`Core/DeathRecap.cs`): history, attackers with element bars, killing blow, loss, last hits, tips. Opens by itself on the server's auto recap (next login) unless "Open after a death" is off. No outfit icons on the rows. | done | P1 | M |
| `game_energyshield` | 224 | Shield bar under the plate, eased over 900 ms, hello after login. `Core/Hud.cs` EnergyShield. | done | P1 | S |
| `game_goals` | 178 | Next Goals window and tracker. | done | P1 | M |
| `game_groundlabels` | 230 | Loot labels over ground items in the classic and the live view (`Core/GroundLabels.cs`, `ChaosApp.Loot.cs`, settings in `LootWindow`). Click on a corpse label opens the corpse. No tooltips, no click to pick up an item (raise), no accent cosmetic, none in HD-2D. | partial | P1 | M |
| `game_helper` | none | `HelperWindow` (Ctrl+R) over `Core/HelperEngine.cs`: heals by threshold (spells, potions), mana training, Auto Haste, five-slot spell rotation with auto turn, Auto Target modes A..H, saved per character. Not ported: runes, party and friend heals, Follow, Auto sell, food, exercise, Everfull follow, potion gate, shooter profiles, line of sight, the HUD. | partial | P1 | L |
| `game_helperrotation` | 116 | Cast bookkeeping (a cast waits for the cooldown packet, refused casts back off), per-channel rate guard, Auto setup from the class presets (`Core/HelperRotation.cs`, data generated from `autorotation_data.lua`). No level-up notice, no Everfull potions message (116). | partial | P1 | M |
| `game_hunt` | 241 | Hunt tracker. | done | P1 | M |
| `game_itemrarity` | 126 (feature) | Item rarity. Frame in the rarity colour (unique colour first) and a gold mark for a locked item on the equipment and container slots, the text window item and the stash list. Needs identity Chaos (the attributes). No frame or outline on items on the map, no shader glow, no loot filter frame. `Core/ItemInfo.cs` `ItemRarity`, `ItemSlots.Frame`. | partial | P1 | M |
| `game_itemtooltip` | 242 | Rich item tooltips on hover of an equipment or container slot: kind, level, quality, base stats, prefixes and suffixes with tier and range, veiled slot, sockets, set block, requirements (red above the level), passive, flavour, charges, weight; cache by per-item id and version, hover delay, answer matched to the item. No compare view (Ctrl), no Alt help, no source lines, no card layout. `Core/ItemInfo.cs` `ItemTips`, `TipLines`. | partial | P1 | L |
| `game_kitewalk` | 186 | Option in the Options window, saved in PlayerPrefs, sent at login and at change as {on}. | done | P1 | S |
| `game_lootfilter` | 238 | Loot channel (kills with items, click takes, Shift one), filter settings and presets in `LootWindow` (`Core/LootFilter.cs`). No rarity frames on open bags (peek), no beams, no rule counters or sounds, no autoloot sections. | partial | P1 | M |
| `game_monkchi` | 247 | Chi pips under the plate that empty at the decay time, hidden for other classes. `Core/Hud.cs` MonkChi. | done | P1 | S |
| `game_monsterbar` | 125 | Tiered target bar: tier colour, label, role, level, percent, damage trail, modifier chips with tips, boss mechanic cast bar. `Core/Hud.cs` MonsterBar. No frame art, no oversized monster scaling, no in-world tier labels. | partial | P1 | M |
| `game_passivetree` | 65 | Passive tree. Opcode 65. | partial | P1 | L |
| `game_rift` | 228 | Rift run HUD. | done | P1 | M |
| `game_rightclickequip` | 188 | Option in the Options window, sent as {on}; the multi-use id list is kept (`HudOptions.MultiUseIds`). Unity has no use-with, so the plain-use rule is not needed yet. | done | P1 | S |
| `game_shop` | 218 | Chaos store (Ctrl+T): category tree with groups, pages, search, history, offers with item or outfit icon, price, old price, tags, Buy with confirmation and the server's answer, coin balance. Never any real payment: `pay_*` messages are ignored, the buy URL is not opened. No gift, no try-on preview, no rotation countdown, no coin icons for image offers. `Core/Store.cs`, `StoreWindow`. | partial | P1 | L |
| `game_simpleskills` | none | Melee, Ranged, Magic, Shielding rows. Unity lists the seven weapon skills. | partial | P1 | S |
| `game_skillstats` | 119 | Combat stat rows in the skills window. | done | P1 | S |
| `game_stash` | 110 | Supply Stash (Ctrl+H): tabs, search, sort, item grid with rarity frames, take out (row or stack with an amount), drop an item of a bag on the window, Stow everything with its report, Collect inbox, Slots opens the store. No never-stash list, no Find my item. `Core/Stash.cs`, `StashWindow`. | partial | P1 | M |
| `client_chaos_infolift` | none | Name and bar lift for tall looks. | missing | P2 | S |
| `client_chaos_numbers` | none | Short numbers (1k, 2.45M). | missing | P2 | S |
| `client_chaos_screenfit` | none | Windows taller than the screen scroll. Unity clamps the title bar only. | missing | P2 | S |
| `client_chaos_theme` | none | Dark fantasy UI theme. Unity windows use one flat dark style. | partial | P2 | M |
| `game_achievements` | 250 | Achievements window. | missing | P2 | M |
| `game_arena` | 236 | Ranked PvP arena queue and HUD. Unity: `ArenaWindow` (mode cards with season line and rating, queue and leave, status, recent matches), `ArenaHudWindow` (both sides with health bars, countdown, result with rating and season change); secure mode off for the match and restored. Not run on a live server. | done | P2 | M |
| `game_autoloot` | 216 | Auto loot lists. | missing | P2 | M |
| `game_autotarget` | none | Auto Target choice rules of the helper. | missing | P2 | M |
| `game_badgeslot` | none | Badge slot 13 in the equipment. Unity equipment draws 10 slots. | missing | P2 | S |
| `game_battleground` | 200 | Battleground queue, HUD and scoreboard. Unity: `BattlegroundWindow` (Queue, Season, Vendor tabs, roles, deserter confirm), `BattlegroundHudWindow` (score bars, wells, notices), `BattlegroundBoardWindow` (scoreboard and summary). No tier emblems. Not run on a live server. | done | P2 | L |
| `game_battlepass` | 227 | Season pass window. | missing | P2 | M |
| `game_bestiary` | 253 | Bestiary, kill tasks and tracker. | missing | P2 | M |
| `game_bounty` | 223 | Bounty board. Unity: `BountyWindow` (band tabs, contracts with task, reward, progress, Accept, Abandon, Reroll, weekly chest, refresh timer). No creature outfit preview. | partial | P2 | M |
| `game_candlemarks` | 176 | Candlemarks counter and shop. | missing | P2 | M |
| `game_chaoslayout` | none | Saved window layout per character. | missing | P2 | M |
| `game_chaosshaders` | none | Outfit shaders. The shader name is parsed in Chaos identity, nothing draws it. | partial | P2 | L |
| `game_chaossound` | none | Game sounds. | missing | P2 | M |
| `game_chaosuiscale` | none | Interface scale. Unity scales with the window height. | partial | P2 | S |
| `game_chaosview` | none | Map zoom and the largest map area. Unity shows 15 x 11 tiles. | missing | P2 | S |
| `game_chaosweather` | 114 | Rain and ambient particles. | missing | P2 | M |
| `game_charms` | 198 | Charms grid. | missing | P2 | M |
| `game_chatlinks` | 249 | Item links in chat: Shift+click on an item of the equipment or a bag asks the server for a link (register), the name goes into the chat line as a chip and is written out as [Name]{<r><id>} when the line is sent (up to 3, 250 characters, no links to NPCs, the Help channel needs the tutor right); a line with links shows the names in the rarity colour and the tooltip of the link under the pointer (get, 10 minute snapshots, expired answers). Core/ChatLinks.cs, ChaosApp.Social.cs. No Ctrl compare. | done | P2 | M |
| `game_codex` | none | Codex encyclopedia, static data from the server tools. | missing | P2 | L |
| `game_conquest` | 167 | Conquest vendor (opcode 167): Uniques, Set Pieces, Raid and Ascended, Cinderheart (Omen Keys, attune, Ascended Shards, conversions), Refine and Progress pages, one purchase at a time, opened by the NPC. ConquestWindow, Core/Factions.cs. | done | P2 | M |
| `game_cosmetics` | 225 | Cosmetics window. | missing | P2 | L |
| `game_crafting` | 232 | Crafting bench. | missing | P2 | M |
| `game_craftingtable` | 91 | Base crafting tables. | missing | P2 | M |
| `game_craftskills` | none | Profession skills in the skills window (skills packet extra rows). | missing | P2 | S |
| `game_daily` | 207 | Daily reward window. | missing | P2 | S |
| `game_deadguard` | none | Removes a dead monster left at 0 percent after 3 seconds. | missing | P2 | S |
| `game_descent` | 205 | Ember Descent trial HUD and boons. Unity: `DescentWindow` (info, forge, Descend, Weekly), `DescentHudWindow` (room, depth, embers, boons, curses, party, result), `DescentOfferWindow` (3 cards, curse box), `DescentShopWindow`. Boons as text, no icons. Not run on a live server. | done | P2 | L |
| `game_dpsmeter` | 204 | DPS meter and combat log. | missing | P2 | M |
| `game_dungeons` | 109 | Dungeon finder. Unity: `DungeonsWindow` (list with queue colours, difficulties, requirements, loot, challenges, solo and group boards, join and leave, queue timer), `DungeonCounterWindow` (kill counter, objectives, banner). No boss outfit, no item finder. | partial | P2 | M |
| `game_embercache` | 174 | Ember Cache and day book. | missing | P2 | M |
| `game_factions` | 215 | Factions (opcode 215): faction tabs with rank bars, lore, rival, week cap, tokens with Turn in, Go to NPC (opcode 121), contracts with Deliver, quartermaster offers (Buy, Craft), opened by the faction NPCs. FactionsWindow, Core/Factions.cs. No emblem art. | done | P2 | M |
| `game_gamble` | 199 | The Gambler window. | missing | P2 | M |
| `game_groundfx` | none | Spell effects under creatures. | missing | P2 | M |
| `game_groupqueue` | 160 | Group queue (opcode 160): arena by party size, battleground, dungeon with difficulty, join and leave, raid check, Find a group, and the ready check box with its countdown (Accept, Decline). GroupQueueWindow, ReadyCheckWindow, Core/PartyFinder.cs. | done | P2 | M |
| `game_guild` | 252 | Guild window (opcode 252): overview with the XP bar, perks, bank deposit and withdraw, scroll and log; members; guild hall (buy, rent, upgrades, hub); guild stash (take); top guilds. GuildWindow, Core/Guild.cs. The hall bench module is not opened (a line says so). | done | P2 | L |
| `game_guildwar` | 197 | Guild wars (opcode 197): offers (accept, decline, take back), running wars (surrender with a second click, kill log), declare form, war board, weekly guild boss (fuel bar, summon, gold and material feeding, banner, spoils, board). GuildWarWindow, Core/Guild.cs. | done | P2 | L |
| `game_helperhud` | none | Helper HUD on the map. | missing | P2 | S |
| `game_helpersupport` | none | Helper support spell tab. | missing | P2 | M |
| `game_helpertimers` | none | Helper cooldown channels. | missing | P2 | M |
| `game_helpsearch` | none | Help search over How it works, unlocks and Codex. | missing | P2 | M |
| `game_hideout` | 192 | Hideout decoration and visits. | missing | P2 | L |
| `game_howitworks` | none | How it works cards. | missing | P2 | S |
| `game_hudmove` | none | Movable HUD panels. | missing | P2 | S |
| `game_infinitytower` | 214 | Infinity Tower window. Unity: `TowerWindow` (season, points bar with claimable milestones, podium, ranking, Enter and Leave), `TowerPanelWindow` (floor, monsters, timers, Next floor now with Ctrl+Shift+N, Auto, Leave). Not run on a live server. | done | P2 | M |
| `game_invasion` | 251 | Invasion HUD and event list. Unity: `InvasionHudWindow` (waves, breach, sides, top defenders, fold) and `InvasionWindow` (calendar), in the Adventure menu as Invasions. Not run on a live server. | done | P2 | M |
| `game_itemfinder` | 155 | Item finder. | missing | P2 | M |
| `game_leaderboard` | 229 | Leaderboards (opcode 229): weekly boards pick list sorted by name (kept per character), class tab, season toggle and modes, champions, own rank, reset timer; the Records view (categories, boards, period, variant, size, class, Realm Firsts, My Records). LeaderboardWindow, Core/Leaderboard.cs. Exact numbers instead of short ones. | done | P2 | M |
| `game_loadouts` | 206 | Loadouts (Armory). | missing | P2 | M |
| `game_lookpreview` | none | Look preview panel. | missing | P2 | M |
| `game_lootscreen` | none | Hides the loot line on the game screen. | missing | P2 | S |
| `game_mapmarkers` | 153 | Party and point markers on the minimap, NPC quest marks. | missing | P2 | M |
| `game_mapoverlay` | 245 | Explored map overlay on the game view. | missing | P2 | M |
| `game_market` | 221 | Player market (opcode 221): Browse (search, category, rarity, currency, sort, level and price range, pages, hover tooltip, Buy with a confirmation per currency), Sell (backpack list, prices, duration, fee text), My Offers (cancel), History, Buy Orders (browse, own, post with item search, fill, cancel). MarketWindow, Core/Market.cs. Not ported: the Modifiers filter of Browse and of an order, the price history chart, drag an item onto the Sell slot. | partial | P2 | L |
| `game_minimapsync` | none | Minimap after death or teleport. Unity has a minimap window; no marker sync. | partial | P2 | S |
| `game_nameplate` | 248 | Name plates with titles and frames. | missing | P2 | S |
| `game_npctravel` | 121 | Go to NPC button. | missing | P2 | S |
| `game_orbexchange` | 209 | Orb Exchange. | missing | P2 | M |
| `game_outfitextras` | none | Customise Character window. | missing | P2 | L |
| `game_pact` | 222 | Chaos Pact window. | missing | P2 | M |
| `game_partyfinder` | 208 | Party finder (opcode 208): browse with the activity, role and level filters, Apply by role, Withdraw, quick join queue, My Group form (activity, range or target or title, wanted counts, level band, notes, duration, auto accept), applications (Accept, Decline), notices and nudges as chat lines. PartyFinderWindow, Core/PartyFinder.cs. No badge on the menu button, no slot boxes (text composition). | done | P2 | M |
| `game_pets` | 254 | Pets window. | missing | P2 | M |
| `game_playerinspect` | 240 | Inspect player (opcode 240): by typed name or the right-click Inspect on a player; header with the outfit, equipment rows with item tooltips (transmog looks), profile, combat sheet, records, the privacy setting, denials. InspectWindow, Core/Inspect.cs. The passive tree is a summary line, not the read-only tree view. | partial | P2 | M |
| `game_pouches` | 226 | Loot bag rules and auto seller. | missing | P2 | M |
| `game_professions` | 195 | Professions. | missing | P2 | M |
| `game_proficiencycatalog` | none | Weapon list of the proficiency window, built on the client. | missing | P2 | S |
| `game_pvpzone` | 193 | Scorched Marches zone. Unity: `PvpZoneWindow` (rules, shrine, pledge, vendor, record), `PvpZoneConfirmWindow` (risk and boxes), `PvpZoneHudWindow` (embers, contest, goals with the compass to the nearest exit and shrine). Marks are not drawn on the minimap. | partial | P2 | M |
| `game_raid` | 213 | Weekly raid window and HUD. Unity: `RaidWindow` (Raids, Journal, Vendor tabs), `RaidHudWindow` (boss, phase, enrage, counts, stacks) and `RaidCalloutWindow` (alerts, loot). Not run on a live server. | done | P2 | L |
| `game_riftatlas` | 159, 210 | Rift Atlas and Waystone Atlas. Unity: `RiftAtlasWindow` and `WaystoneAtlasWindow` (one model, `Core/EndgameAtlas.cs`): pannable and zoomable node map, allocate, refund with gold or orbs, reset, totals, the grid of completed cells. Nodes show a glyph letter, not the art. Not run on a live server. | done | P2 | L |
| `game_season` | 246 | Seasons window. | missing | P2 | M |
| `game_siege` | 233 | Guild siege HUD. Unity: `SiegeWindow` (sign-up, signed guilds, champions, rules, countdown) and `SiegeHudWindow` (teams by score, obelisk holder, you). Not run on a live server. | done | P2 | M |
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
| 0x7D, 0x7E, 0x7F | player trade offer, counter offer, close | trade between players | P2 |
| 0xA8, 0xA9 | creature square and cancel variants | none known | P3 |
| 0xAE | rule violation channel | none (Chaos has its own reports) | P3 |
| 0xB6 | walk wait | smoother walking on slow ground | P2 |
| 0xB7, 0xB8 | unjustified points, PvP situation | PvP skull display | P2 |
| 0xD4 | VIP logout | VIP list | P2 |
| 0xDE | edit VIP | VIP list | P3 |
| 0xF0, 0xF1 | quest log, quest line | quest log | P2 |
| 0xF6 to 0xF9 | base market | none (Chaos market uses opcode 221) | P3 |
| 0xDF, 0xEE | coin and resource balance | base store, resources | P2 |

Inside packets Unity reads, it skips or ignores: 0x9F spell list body, 0xDD map flags (read, not shown), 0x8D to 0x95 creature fields beyond the ones in `Creature`.

Client to server packets Unity sends: walk and turn, say, use, move, close, up, attack, follow, party (0xA3 invite, 0xA4 join, 0xA5 revoke, 0xA6 pass leadership, 0xA7 leave, 0xA8 shared experience), pong, logout, extended opcodes, NPC shop (0x79 to 0x7C), words to an NPC (0x96 type 12).
Sent by the chat track: talk with type, channel or receiver (0x96), channels (0x97 to 0x9A), NPC channel close (0x9E), fight modes (0xA0). Read by it: 0xAA all 10.98 talk types (position for 1, 2, 3, 9, 10, 36, 37; channel id for 6, 7, 8, 14; none for 4, 13, 15), 0xAB to 0xB3, 0xB4 console kinds by tab, 0x28 with death type and penalty (the main client enables both features). 0xA7 is not a fight mode echo in 10.98 (it stays read and ignored). The NPC channel tab is a chat tab named NPCs; trade is the NPC track's.
Items track: outfit window (0xC8 in, 0xD2, 0xD3, 0xD4 out), text windows (0x96, 0x97 in, 0x89, 0x8D out), modal windows (0xFA in, 0xF9 out).
Not sent yet: use with (0x83), use on creature (0x84), look (0x8C), rotate (0x85), auto-walk (0x64), stop (0xBE), VIP (0xDC to 0xDE), quest log (0xF0, 0xF1), equip hotkey (0x77).

## Progression track (phase 3, track K)

Built on the same server messages as the main client. Pure parts in `Core/Progression.cs`, `Core/PassiveTree.cs`, `Core/BuildCode.cs`, `Core/TopMenu.cs`, tests in `Core.Tests/ProgressionTests.cs`.
- Passive tree (`PassiveTreeWindow`, Ctrl+N, opcode 65): pannable and zoomable node graph with tooltips, planner (a click plans the path, a click on a planned node takes it out, undo and redo, Apply sends planApply), masteries with their effect choice (planned and saved), refund by right-click and Reset with the server's prices (respecInfo), boss points, search with Prev and Next, build codes (export, full CC1 export, preview, apply, cancel; decode and encode checked on `docs/build_code_vectors.txt`).
  The layout is `Resources/PassiveTree.json`, made by `unity/tools/gen_tree_data.lua` from the main client's tree data (CI `--check`).
  Missing: node icons (nodes are coloured discs by type), curved links inside an orbit (links are straight), the Paragon track, trials, the stat totals panel and trends, the auto build helper, the tree of another character, loadouts. Stat lines are English (the main client translates them from its own table).
- Skills window: Melee, Ranged, Magic / Wand, Shielding, Fishing, Fist (Monk line) and the combat stat rows. Not here: crafting skill rows (`game_craftskills`).
- Next Goals (`GoalsWindow`, Ctrl+Y) and the tracker (`GoalTrackerWindow`, opens by itself), Hunt Tracker (`HuntWindow`, Ctrl+I, restock), Rift HUD (`RiftWindow`, opens on the server's start), Info and Services (`InfoWindow`: character, services, house, rift keys, events, Ancestral Store, server info).
  The "where" buttons open Unity windows and Info pages; a map mark, the Bestiary, Kill Tasks and the Item Finder say "That window is not available" until those windows exist.
- Top menu: category buttons Character, Hunt, Adventure, Economy, Social, System and Windows, with drop-downs sorted by text, entries hidden or grey by level (opcode 115), the New badge, the on-screen text and the Go box. The Windows category lists every window no entry names, so a new window is always reachable. Entries of main client modules that have no Unity window yet are not shown. No Alt hotkeys (the Ctrl keys of the windows stay) and no locked-entry message on a hotkey.
- Not run against a live server (as the other tracks).

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
