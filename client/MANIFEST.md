# Client module manifest

Status of every requested module. **Nothing here has been run.** The session that assembled it had no OTClient runtime, so "loads" means "the code looks self-contained", not "tested".

Layout: `overlay/modules/<name>` is copied into the client's `modules/` folder; `overlay/data/images/...` into its `data/images/`. Some of these were under `mods/` originally; they were all moved to `modules/` here, so check `autoload` and `autoload-priority` in each `.otmod` when wiring them in.

Protocol target is 10.98 on the base server (TFS 1.4.2). The sources are mostly 8.60 or 12.x+ clients, so the real risk is the client engine (C++ API) and the server contract, not the Lua.

| Module | Server contract | Client-engine needs | Verdict |
|---|---|---|---|
| game_stash | extended opcode 110 + Economy > Supply Stash talk | none after port | Ported off `client_manager`; replaces the base client's own stash. Stash tabs (Chaos Pact and account storage): a tab bar (All, 1..n, Orbs / Gems / Keys when owned; withdraw-only tabs dimmed with a tooltip) filled from the server's `tabs` message, each item carries its `tab`, a line under the list with the use of the selected tab. Item tooltips fall back to `setTooltip` (the donor client's `buildTooltip` is not in this client: opening a stash with items raised an error before). Tested in game (server/README.md "Chaos Pact and account storage") |
| game_bank | extended opcode 60 | none | Needs server script |
| game_autoloot | extended opcode 216 | none | Needs server script (base server has a partial autoloot) |
| game_itemrarity | item custom attributes (server engine patch 0003, client feature 126 negotiated at login) | none (the engine already parses the attributes) | Rarity of an item from its custom attribute (keys `ChaosItemAttr`, same numbers as the server's `Chaos.itemAttr`), description tag as fallback; 15 rarities; frame in the rarity colour (unique orange) on container and inventory slots; turns feature 126 off at logout. `itemrarity_test.lua`; tested in game. Soft rarity outline (base patch 0044, not built or run yet): at load it hands the engine one colour per rarity and the unique colour (`Item.setRarityOutlineColor`, alpha 225; `getRarityOutlinePlan` / `applyRarityOutline`, tested), a reach of 3 sprite pixels, no outline for Common, a breathing outline from Mythic up (2.2 s), and the Graphics options `rarityOutlineMap` / `rarityOutlineSlots` (`onOutlineOption`); the engine draws it around dropped items on the map and items in inventory and container slots. A client without 0044 has no `Item.setRarityOutlineColor` and nothing changes. `updateRarityFrame` also calls `game_shaderfx` (`onSlotItem`: grey a locked item; `onRarityFrame`: the shine) when that module is loaded |
| game_battlepass | extended opcode 227 (JSON) + Adventure > Season Pass; toasts through `game_chaosnotify` (action `seasonpass`) | none | Replaced: the Chaos season pass window (Chaos skin, 760 x 560): tier, pass XP bar, Claim all; Rewards page (50 tier rows, free and premium reward with item / outfit / mount icon and Claim, locked / premium / claimed states), Challenges page (daily and weekly with progress and reset timers, the day's pass XP per source and cap), Packs page (premium pass and the three season packs: Buy, Upgrade for the difference, Gift to a character name with the receiving account's price). Server `data/scripts/chaos/seasonpass.lua` (server/README.md "Season pass"). The old raw opcode 39 window and its images are gone. Logic `passview.lua` (tested by `passview_test.lua`); tested in game with two clients |
| game_passivetree | extended opcode 65 (also `planApply` / `masteryChoose` out, `planResult` back; `sendNodes` carries `masteries`) | none | Needs server script. Paragon panel (`paragon.lua`, `paragon.otui`, `paragonmath.lua`) on the same opcode. Planner (`planner.lua`, logic `treeplan.lua` tested by `treeplan_test.lua`): a click plans the shortest path from the allocated set over nodes the class may take, planned nodes get the `checked` frame, plan bar with cost against free points, Undo / Redo (Ctrl+Z / Ctrl+Y) / Clear, Apply Plan sends the whole plan once. Mastery nodes: the effect choice window (`mastery.otui`), a saved one changes for the node refund price. Search box (`search.lua`, Ctrl+F): frames every node whose name or bonus text matches, Next / Prev centre the view, a match count. Read-only view of an inspected character's tree (`viewother.lua`, from `game_playerinspect`). Zoom levels cached as panel pairs (a step back to a built level creates no widget; `getTreeStats()`), zoom keeps the centre. Tested in game (server/README.md "Passive tree planner and mastery nodes"). Art: every node icon is a painted cell of the tree's own atlas `images/passivetree/skills.png` (the icon set that came with the tree); `client/tools/gen_keystone_icons.py` picks the cells of the medium and large nodes (one icon per node, none shared with a small node): the 27 path notables, the class section notables and masteries 665-668 and 619-623 are clipped from the atlas (`treedata/icons.lua` `nt*` / `ms*`, `--check` verifies the clips), the keystones are those atlas icons scaled once to the 64 px cells of `keystones.png`, and the class starts `classstart_<line>.png` are the root start medallion with the class icon in its centre; the old flat generated glyphs are gone. The twelve build archetype keystones (2026-10-12, server/README.md "Build archetypes") are cells 28-39 of `keystones.png`, named in `KEYSTONE_NAMES`; a keystone without a class list shows its own text lines too. The second round's four (Snarewright's Creed, Covenant of Vigils, Iron Tithe, Hollow Vessel; nodes 105, 99, 102, 96) are cells 40-43. Rendered offline in the Linux client (read-only preview of each line). With "Painted icons" on, keystones and masteries use `painted_nodes.png` (`treedata/painted.lua`, "Painted icons" below) |
| game_shop | extended opcode 218 (JSON) | none | Chaos store: categories, pages, purchase, coin gifts, history; an offer shows the price the server sends, the old price struck through (`oldCost`), its tags (Sale / New / Featured / Bundle / Starter), "Owned." with the Buy button off, and a GIFT button when the server says it can be gifted (`giftoffer.otui`: a character name, then a confirmation; `buy` carries `gift`). The client never computes a price. **Donate** button: the donation window (`pay.lua`, `pay.otui`): the voluntary donation notice in English and Portuguese (cp1252 escapes; "nobody is required to donate, the game is fully playable for free"), under it the website's refund sentence (no refund except where the law requires one, not a purchase, no real-world value; "This was a voluntary donation, not a purchase..." once the order is paid or credited) with where the Donation Terms are (`page.php?plugin=chaos&p=legal&doc=donations` on the website, as text), the method (Pix (BRL) / PayPal (USD)), the packs with "Donate <price>"; then the QR code drawn with widgets (`qrcode.lua`: byte mode, level M, versions 1-40, one widget per dark run) of the Pix copy-and-paste code (sent as hex) or of the PayPal link (also opened with `g_platform.openUrl`), the code with a Copy button, a countdown, Cancel; it asks `pay_status` every 3 s and shows the thank-you when the server pushes `pay_paid` (toast `PayToast` + balance, no relog). Pure logic in `payview.lua` and `qrcode.lua`, tested by `payview_test.lua` (the notice and the refund sentences equal the server's, thank-you texts, "Donate" wording, countdown, hex) and `qrcode_test.lua` (block table, format and version bits, pinned matrices checked against an independent encoder and decoder). Server `data/scripts/chaos/shop.lua`, `shop_payments.lua` (server/README.md "Store"); tested in game Cosmetic offers (server `cosmetics.lua`): a SHOW button in place of GIFT plays the effects for the buyer only (action `preview {category, page, offer}`), a chat colour tints the title, a label accent sits behind it The weekly rotation ("This week") shows a countdown on its category (`rotation.lua`, `rotation_test.lua`: the server sends `endsIn`); the donation tab has an optional creator code field (sent with `pay_create`) and says "double Chaos Coins (+100%)" for the first donation. |
| game_market | extended opcode 221 (JSON, long answers joined by `registerExtendedJSONOpcode`) + Economy > Market, Alt+E; the market item of a depot locker opens it | none | Our player market (Chaos skin, 900 x 600, fits 1280x720) for gold and Chaos Coins, server `data/scripts/chaos/market.lua`: Browse (search, category, rarity, currency, sort, item level and price ranges, pages of 10; a collapsible Modifiers section: up to 6 rows of modifier / legendary power (a search box filters the Codex names, grouped prefixes / suffixes / powers, scrolling list) + lowest value + lowest tier (T1 lowest, T8 best, "T5+"), all rows or at least N, sockets, quality, free prefix / suffix, power, bound, checked before sending (`MarketView.modRequest`) and kept while logged in; rows with icon, rarity frame, name, seller, time left, prices; hover = the full rich tooltip through `game_itemtooltip.showTip` with the matched modifiers under it, Buy asks the currency), Sell (backpack picker with the reason an item cannot be listed, or drag an item onto the slot; amount, gold / coin price, 1 / 3 / 7 days, the fee and tax), My Offers (active with Cancel, sold / expired / cancelled), History, Buy Orders (the open orders with Sell: the seller's items of that kind from the backpack, greyed with the reason when they do not fit, a stack in part; My orders with Cancel and the ended ones; the post form: item found by name, how many, price each in gold or Chaos Coins, 1 / 3 / 7 days, lowest rarity / item level and the Browse tab's modifier filter, the escrow and fee before posting). Long names shortened at a word (`SupportsText.shorten`), other texts wrap. Toasts through `game_chaosnotify` (action `market`). The top bar entry (Economy > Market) points at this module only now. Logic `marketview.lua` (tested by `marketview_test.lua`); tested in game at 1280x720 and 1920x1080 (server/README.md "Market"). Price history (action `prices`, server `market_history.lua`): a click on a Browse offer shows its item key's typical price, last sale, 7-day median / volume / range and a 30-day chart of daily medians (the Orb Exchange chart code); rows priced well under / over typical are marked; the Sell form suggests a price (Use typical) and warns far below / above. Logic `marketpriceview.lua` (`marketpriceview_test.lua`) |
| game_orbexchange | extended opcode 209 (JSON: `open` / `book {base, quote}` / `place {give, giveQty, want, wantQty, days}` / `cancel {id}` / `mine` / `wallet` out; `meta`, `book`, `mine`, `wallet`, `done`, `error` back, chunked by `Chaos.sendChunked` and joined by `registerExtendedJSONOpcode`) + Economy > Orb Exchange | none (menu entry through `ChaosTopBar.addEntry`; an "Orb Exchange" button is added next to the Close button of `game_market`'s window from this module, no change there) | Orb Exchange window (Chaos skin, 900 x 600, fits 1280x720), server `data/scripts/chaos/orbexchange.lua`: a strip of every orb on the exchange (item sprites) picks the base, "priced in" picks gold or another orb; the book (asks over the spread line over bids, price / quantity / orders / total, depth bars; a click on a level fills the form to buy or sell at that price), last price, 24h change, high / low, volume and turnover, an hourly price chart (step line and volume bars drawn from widgets), the last trades, the order form (Buy / Sell, quantity, price each, days, the totals, fee and the orb-for-orb fee before placing); My Orders: open orders with progress and Cancel, my fills, closed orders. Refreshes every 5 s while the book is open. Logic `orbexchangeview.lua` (tested by `orbexchangeview_test.lua`); tested in game with two characters (server/README.md "Orb Exchange") |
| game_spellbook | extended opcode 219 (JSON) + Character > Spellbook | none | Spellbook window: search, vocation filter, spell details and an area-of-effect grid; server `data/scripts/chaos/spellbook.lua`; with "Painted icons" on, Chaos spells show `images/game/spells_painted/<clientId>` ("Painted icons" below); untested in a client |
| game_craftskills | skills packet (crafting skills after fishing) | base patch 0012 (`GameChaosCraftingSkills`) | Profession section at the bottom of the skills window, live updates, `getSkill(index)` for other modules (`game_craftingtable`); tested in game |
| game_daily | extended opcode 207 | none | Daily reward window (server `data/scripts/chaos/daily.lua`). Shows the account-wide login streak: streak and best, grace charges, next milestone and the title. A window opened by itself at login waits while a server modal dialog or another login window (`LOGIN_BLOCKERS`) is on screen, and reports `closed` so the server's login window queue can open the next one. Jumps (login placement, teleports) no longer close it. Tested in game |
| game_bounty | extended opcode 223 (JSON) + Adventure > Bounty Board | none | Bounty board: today's contracts per level band (tabs), creature preview, reward, Accept/Abandon, progress bars, timer to the next roll, weekly chest count; Adventure > Bounty Board in the top menu; toasts through game_chaosnotify (action `bounty`); server `data/scripts/chaos/bounty.lua`; tested in game |
| game_rift | extended opcode 228 (JSON, server -> client; `query` back after a reload) + Adventure > Rifts | none | Rift run HUD (`ChaosPanelDark` under the character plate and the buff bar below it, re-placed with its clock as the bar grows): tier, theme, a local countdown, kills / left with a bar to the guardian, the guardian line, the modifiers (boons gold, suffixes violet since 2026-10-12, `RiftMath.modColor`; the server sends `mods[].side`) and the reward bonuses, the Rift Atlas's Swift line while the rift runs (the tier's Swift time from the server's `swift`, the time to spare or "missed", `RiftMath.swiftLine`, since 2026-10-12), then Sealed / Collapsed / Left; `riftmath.lua` tested by `riftmath_test.lua`; server `data/scripts/chaos/rift.lua`; tested in game (the suffix colour not seen in game) |
| game_arena | extended opcode 236 (JSON) + Adventure > Arena | none (uses `g_game.setSafeFight` / `cancelAttack`) | Ranked PvP arena: window (rating, W-L-D and best per mode, the PvP season tier or placement per mode, Queue 1v1 / Queue 2v2 / Queue 3v3, Leave Queue, queue time and rating window, the level range you can face, first-win bonus, last 10 matches), match HUD at the top of the map (both teams' names and health, countdown / fight clock, your team on the left), VICTORY / DEFEAT / DRAW toast with the rating change and reward; turns secure mode off for a match and back on after; Adventure > Arena in the top menu; `arenatext.lua` tested by `arenatext_test.lua`; server `data/scripts/chaos/arena.lua`; tested in game with two clients |
| game_battleground | extended opcode 200 (JSON through `registerExtendedJSONOpcode`: `open` / `query` / `queue {role}` / `role {role}` / `leave` / `board` / `buy {key}` out; `state`, `start`, `hud`, `board`, `alert`, `end`, `msg` back) + Adventure > Battleground | none (menu entry through `ChaosTopBar.addEntry`; `g_game.setSafeFight` / `cancelAttack`) | The Ember Wells battleground and the PvP seasons: the window (Chaos skin, 660 x 540) with Battleground (rules, the bracket and its reference level, role buttons of the class, queue status and estimated wait, the four season cards 1v1 / 2v2 / 3v3 / Battleground with tier emblem, tier and rating or the placement, honor and record), PvP Season (season number and end, the rules, the cards, the rewards per tier) and Honor Vendor (items with their icons, cosmetics); Queue / Leave Queue / Leave Match (confirm), Find a Group (Party Finder). In a match: the HUD at the top of the map (both teams' scores towards 1000, the clock, the three wells with owner, capture progress or contested, downed / AFK countdowns, Scoreboard button), the scoreboard window and the end summary (result, score, season change, honor and the weekly first win). Art `images/chaos/battleground/` (tier emblems from donor icon cells in drawn crests, well and honor icons) from `client/tools/gen_battleground_art.py`. Pure helpers `bgview.lua` (`bgview_test.lua` in CI); `game_arena` shows the season line per mode and a 3v3 card (`arenatext_test.lua`); server `data/scripts/chaos/battleground.lua`, `arena_season.lua` (server/README.md "Battleground and PvP seasons"); tested on a live test server with two clients |
| game_siege | extended opcode 233 (JSON) + Adventure > Guild Siege | none | Guild siege: HUD at the top of the map during a siege (title, time left or "gates open in", obelisk holder in the guild colour / contested / neutral, a row per guild with colour, members inside, kills and score, your kills/downed/points; final score at the end) and a sign-up window (ornate skin: next siege and countdown, status, your guild with Sign up / Withdraw, signed-up guilds, champions, rules). Adventure > Guild Siege in the top menu. Pure helpers in `siegemath.lua` (tested by `siegemath_test.lua`). Server `data/scripts/chaos/siege.lua`; tested in game |
| game_invasion | extended opcode 251 (JSON, server -> client; `query` / `calendar` back) + Adventure > Events | none | Invasion HUD (`ChaosPanelDark` under the character plate, beside the rift HUD while a rift runs): area, faction and target, wave N of M, invaders left, a local countdown, "Horde slain" bar, breach meter (amber / orange / red), the boss's health, top 3 contributors, your rank, share and kills; click to fold; the end result (held / fallen / free again) and the occupation. "Upcoming Events" window (invasions, world event, Victory buff). Toasts through game_chaosnotify (type `INVASION`, action `invasion`). Pure helpers `invasionmath.lua` (tested by `invasionmath_test.lua`). Server `data/scripts/chaos/invasion.lua`, `worldevents.lua`; tested in game |
| game_guild | extended opcode 252 (JSON) + Social > Guild | none | Guild window in the Chaos skin: guild level and XP bar, perks, members' contribution (this week / total), guild bank (deposit, leader withdraw), guild hall (buy, rent, upgrades with buttons for the leader and vice-leaders), guild depot with its log, weekly top guilds; the hall's crafting bench opens `game_crafting`. Social > Guild in the top menu. Pure helpers in `guildmath.lua` (tested by `guildmath_test.lua`). Server `data/scripts/chaos/guild.lua`, `guild_hall.lua`; tested in game |
| game_guildwar | extended opcode 197 (JSON through `registerExtendedJSONOpcode`: `open` / `refresh` / `close` / `declare {target, fragLimit, hours, stake}` / `accept` / `decline` / `cancel` / `surrender {id}` / `log {id}` / `bossGold {amount}` / `bossItem {key}` / `bossSummon` out; `state`, `message`, `log` back) + Social > Guild Wars, a button in the Guild window, the guild hall's Summoning Stone | none (menu entry through `ChaosTopBar.addEntry`) | Guild Wars window (Chaos skin, 660 x 620): Wars (offers with Accept / Decline / Take back, running wars with score, time left, terms, Kill log with the refused kills and their reason, Surrender with a confirmation, history), Declare War (guild, frag limit, duration, gold stake with the winner's take), War Board (the server's running and latest wars) and Guild Boss (the Summoning Stone's fuel bar, Summon, gold and material donations with the embers they give, the guild banner tier, this week's contributors, the weekly guild boss board). Pure helpers `guildwarview.lua` (`guildwarview_test.lua` in CI); `game_guild` has an Open button for it. Server `guildwar.lua`, `guildboss.lua` (server/README.md "Guild wars in game", "The weekly guild boss"); tested on a live test server with two clients |
| game_crafting | extended opcode 232 (JSON) + Economy > Crafting Bench | none | Crafting bench: drag an item from the backpack onto the slot or pick it from the gear grid, see rarity, item level, modifiers / maximum, use any of the eight orbs (the seven crafting orbs and the Orb of Sockets; buttons enabled only when the server says the orb fits), the item's sockets under its modifiers (gem, effect, Remove for gold / Shatter: action `gem`), result line and the last 8 crafts; Economy > Crafting Bench in the top menu; server `data/scripts/chaos/crafting.lua` + `data/lib/chaos_crafting.lua`. Tabs Orbs / Salvage (Economy > Salvage opens the second): salvage the item on the bench into rune shards with a preview, "salvage all" of one container up to a chosen rarity (combo boxes, the batch marked in the gear grid, a confirmation box, 50 items at most), combine shards into the eight orbs (Ctrl+click: up to 10), Lock / Unlock of the item on the bench (locked items dimmed in the grid); actions `salvage`, `lock`, `salvageScope`, `salvageBatch`, `combine` on the same opcode (server `salvage.lua`, server/README.md "Salvage"); tested in game |
| game_craftingtable | extended opcode 91 of the base crafting script (JSON: `fetch {category, page}` / `craft {category, craftId}` / `tip {category, craftId}` out; `show {category}`, `money`, `chunkedFetch` pieces of `fetch {category, page, totalPages, crafts}`, `craft {success}`, `message {kind, text}`, `tip {category, craftId, tip}` back; `message`, `tip` and the material names come from `server/tools/patch_base_crafting_ui.py`, each recipe's `bonus` from `server/tools/patch_base_crafting_bonus.py`) + Economy > Crafting Tables (only explains where the tables are) | none (skills from base patch 0012 through `g_game.onCraftingSkill` and `game_craftskills.getSkill`) | Crafting Table window (Chaos skin, 860 x 600), opened by the server when a crafting table is used: the seven categories as tabs (the table's marked), recipe list with search (recipe and material names) and All / Can craft, the recipe with result icon and item tooltip (`game_itemtooltip.showTip`), skill needed against the player's, gold against what he carries, the crafting bonus at the player's skill (equipment: "Rarity at item level N: Common 18% / ... / Legendary 0.6%"; potions and runes: "Bonus yield: +3 at 17.5% / +5 at 4%"; also in the result tooltip), materials with have/need, Craft with a count (one request after the other), a bar for the 860 ms, the server's answer in green or red; Craft off with the reason on another table's tab, after walking away, or when something is missing. Pure logic `craftingtableview.lua` (`craftingtableview_test.lua` in CI). Tested in game on the full map (server/README.md "Crafting Table window") |
| game_codex | none (static data, no opcode) + Economy > Codex, Alt+K | none | Codex: an encyclopedia of the item system in the Chaos skin. Tabs Modifiers, Powers, Orbs, Gems, Uniques, Sets (item sets: pieces, bonuses, sources; filters family and level), Rift, Supports, Basics; a search box (every word must start a word of the name or the page), the tab's filters (prefix / suffix, item kind, group, item level: the list shows the tiers that roll at that level and the page marks them; uniques by level and source; rift modifiers by key tier; supports by spell kind), the list on the left, the page on the right (tier table with value ranges and item levels, rolls on, roll chance per kind, rules, the orbs that act on it, sources), links between pages (Backspace or right-click goes back; the search box has the focus, so Backspace goes back while it is empty). Every text wraps; tooltips use `SupportsText.wrap` of `game_spellsupports`. The data `codex_data.lua` is generated from the server's data files by `server/tools/gen_codex_data.lua` (CI fails when it is stale); the logic without client API is `codexview.lua` (tested by `codexview_test.lua`). `game_crafting`: right-click a modifier on the bench opens its page (`openModifier(key, group)`; checked in game for a Rift Key modifier and a legendary power). Tested in game at 1280x720 and 1920x1080 |
| game_itemfinder | extended opcode 155 (JSON: `search {q, p}` / `item {id}` / `item {cid}` / `page {id, k, p}` out; `results`, `item`, `page`, `busy` back, joined by `registerExtendedJSONOpcode`) + Economy > Item Finder | none | Item finder ("where does this drop") in the Chaos skin (820 x 580): a search box (type-ahead 350 ms after the last key, at least 2 letters), the results with item icons and what each has (drops, shops, recipes, ...), pages of 12; the item on the right with its sections in the server's order (Monsters and bosses with chance and count, bosses marked; Chaos drops; Chests and rewards; Crafted from with the material icons; NPCs that sell it with the price and town; Store and vendors; The Gambler; Gathering; Used to make; NPCs that buy it; Other uses), each section with its own pages of 15. A linked item (a recipe's product or material) opens on a click; Back / Backspace goes back. A Codex button opens the item's Codex page when the Codex has one; the Codex has a "Where to find" link on its item pages (`game_codex` `codex.lua`, entries' `items`). Opened from the game's right-click menu of an item (inventory, containers, the map: `addMenuHook` "Where to find"), from a right-click on a market row or a loot channel icon (`attach(widget, clientId)`, one line each in `game_market` and `game_lootfilter`), and from the Codex. A request without an answer goes out once more after 0.9 s (the server drops requests closer than 200 ms). Logic in `itemfinderlogic.lua` (`itemfinderlogic_test.lua`, also checks the item ids of the real Codex data). Tested in game (server/README.md "Item finder") |
| game_leaderboard | extended opcode 229 (JSON) + Social > Leaderboards | none | Leaderboards (ornate skin): tabs per board from the server (World Boss, Bounty Hunter, Rifts, Class Ladder with a tab per class), top 20 with titles next to the names, last week's title holders, own rank and value, time to the Monday reset. Social > Leaderboards in the top menu, which replaces the base `game_highscores` entry: that window asks with game packet 0xB1, which the server does not answer, so it stayed empty. The board and class tabs are as wide as their labels in the font they are drawn with, in as many rows as needed (`tabrows.lua`, tested by `tabrows_test.lua`). Server `data/scripts/chaos/leaderboard.lua`; tested in game Season modes: in the Season view a row of mode tabs (All / Standard / Self-Found / Hardcore / HC Self-Found / Fallen, from the meta) sends `mode` with `get`; a fallen Hardcore character gets a skull (`buffs/skull_red`) after its name with the level and cause as tooltip, on every ladder. The **Records** button switches to the competitive records (server `records.lua`, actions `rmeta` / `rcat` / `rget` / `rboard` / `rfirsts` on the same opcode): category tabs, a board row, filter rows (This week / Season / All time, boss or difficulty or band or floor, party size, class), the rows with the date and the party in the tooltip, the all-time record, a "your rank" line and the Realm Firsts tab; pure parts in `recordsview.lua` (`recordsview_test.lua`). |
| game_chaosinfo | extended opcode 237 (JSON) | none | Info & Services window (Chaos skin): a page list (Character Info, Services, Auto Seller, House, Rift Keys, Events, Ancestral Store, Server Info), each page's commands as buttons / text fields / choice lists, and the server's answer as text. Opened by the top menu (`openPage(id)`); pages and buttons the server does not offer are hidden (`catalog`). Services has a Plate frame row (a frame name field with Use Frame, My Frames and Title Frame: the 13 store frames and the 3 exclusive ones, command `plateframe` of `shop.lua`; the server's `commands_ui_core.lua` now lets the name through). Server `data/scripts/chaos/commands_ui.lua`; tested in game Character Info also shows the item sets worn (command `sets`, server `itemsets.lua`; button Item Sets) |
| game_season | extended opcode 246 (JSON) + Adventure > Season | none (own join dialog `seasonjoin.otui`) | Seasons window (Chaos skin): season name and tag, time left or time to the start, the season modifier, this character's status with a Join button when it may join (confirmation dialog), the account's reward track with progress and what is unlocked, the account's season titles. Adventure > Season in the top menu. `game_leaderboard` got a "[S1] only" toggle (season view of every board) while a season runs. Server `data/scripts/chaos/season.lua`; tested in game Season modes (server `season_modes.lua`): the join dialog offers Standard / Self-Found / Hardcore / Hardcore Self-Found with their warnings ("I understand" for Hardcore), pure logic `seasonjoin.lua` (`seasonjoin_test.lua`); the window shows the mode or the fall; a Hardcore character sends a heartbeat (`beat`, every 2 s) and asks for its state after a reconnect (`sync`); buff bar icons `self_found` / `hardcore_ward` (`client/tools/gen_buff_icons.py`). Seasonal Journey (server `season_journey.lua`): a Journey tab (`journey.lua`, pure `journeyview.lua` with `journeyview_test.lua`; actions `journey`, `journeyChapter`, `journeyDone` on 246): chapters with their state, the chosen chapter's objectives with progress bars and mode tags, its rewards (item icons, set pieces), a banner when something completes; a preview for characters outside the season; the window is 660 x 540 with Season / Journey tabs. `game_chaosnotify` shows the `journey` toast (opcode 79). |
| game_hunt | extended opcode 241 (JSON) + Hunt > Hunt Tracker | none | Hunt tracker: session time with Pause/Resume and Reset, exp/h, time to the next level, loot, supplies and profit per hour, damage and healing, tabs for kills per monster, looted items (icons, counts, gold), supplies used and Chaos drops (orbs, uniques, rarity items in rarity colours; the loot filter's rule counters on top when that option is on), Copy summary. Hunt > Hunt Tracker in the top menu, next to the base `game_analyser` entry (whose loot/supply/kill panes need game packets this server does not send). Server `data/scripts/chaos/hunt.lua` counts everything; pure helpers `huntmath.lua` (tested by `huntmath_test.lua`); tested in game |
| game_dpsmeter | extended opcode 204 (JSON, joined by `registerExtendedJSONOpcode`; `open` / `close` / `seg` / `party` / `share` / `reset` out, `state` back) + Hunt > DPS Meter and the Hunt Tracker's Meter button | none (uses `Spells.getSpellIcon`, `g_window.setClipboardText`, `game_console.getConsole`) | DPS meter: a movable, resizable, lockable panel (`ChaosPanelDark` look) with a bar per skill (spell icon from the spell sheet, rune item, buff bar icons for damage over time, our icons in the buff-icon frame), total, per second and share; tabs Damage / Healing / Taken / Received; dropdown current fight / session / last 10 fights (bosses named); party mode with the members' DPS / HPS (totals only, sharing members of the same realm); Combat Log window with hits, crit rate, average, max, overhealing and the element split; Copy (clipboard) and To chat (one line into the chat input, never sent by itself). Settings in g_settings node `chaosDpsMeter`. Icons `data/images/game/dpsmeter/*.png` (`client/tools/gen_dpsmeter_icons.py`). Pure helpers `dpsmath.lua`, tested by `dpsmath_test.lua`. Server `data/scripts/chaos/combatlog.lua`; tested in game |
| game_chaosscale | extended opcode 157 (JSON: `scale {level, f}` in; `hello` out at a game start, when the module loads in game and when the own level differs from the last factor's) | none | Display scale (see "Display scale" below; server/README.md "Display scale"): keeps the factor of the own level, scales the flat mana costs in `SpellInfo` (action bar, spell list) and gives `chaosDisplayFactor()` / `chaosDisplayValue(n)`. Pure helpers `scalelogic.lua`, tested by `scalelogic_test.lua`; checked in the Linux client at levels 100, 300, 700 and 1000 |
| game_deathrecap | extended opcode 154 (JSON, joined by `registerExtendedJSONOpcode`; `open {id?}` / `get {id}` out, `history {list, sel, recap}` / `recap {id, recap, auto}` back) + Hunt > Death Recap | none (menu entry through `ChaosTopBar.addEntry`; `UICreature` for the looks) | Death Recap window (Chaos skin, 680 x 520): opens by itself after a death (at the next login, with the experience and levels lost) or a defeat in a mode, unless "Open after a death" is off (g_settings node `chaosDeathRecap`). Left: the last 5 deaths (time, killer, loss or mode); right: killed / defeated by, time, level, mode, PvP, what was lost, the killing blow, the time window and hit count, damage taken (health / mana) with an element bar, a row per attacker (look, name, a summon with its master, total and share in short numbers, an element-coloured bar, hits, crit rate, mana part, the element split; tooltip with the exact numbers), "Others", and the last 6 hits. Pure logic `deathrecaplogic.lua` (numbers by `formatShortNumber`), tested by `deathrecaplogic_test.lua`. Server `data/scripts/chaos/deathrecap.lua`; tested in game with two clients |
| game_lootfilter | extended opcode 238 (JSON) + Hunt > Loot Filter | base patch 0032 for the rule sounds (`g_sounds`); the generated dat for the ray effects 424..428 | Loot Filter window (ornate skin: presets, glow/dim thresholds, category toggles, Rarity Autoloot selectors locked without the store unlock, preview row of the 15 rarities, a unique, an orb and plain loot). Hooks the container windows from outside (`Container` signals + `peek` to the server, which knows the rarities): glow, frame or dim on the slot widgets; dims in corpses only. Lays the loot feed over the console's Loot tab: one row per kill, icons only, no text: the killed monster's look first (a `UICreature` at item size facing south, from the server's `kill.look`: rift looks and tier shaders included; old scaling, centred, so small creatures stay 1:1 and big ones shrink; hover: its name and the kill time), then the item icons (count on the icon, rarity glow / frame / dim, click to loot, Shift = one, greyed with a check when gone, hover: the item tooltip); an empty corpse is the monster icon with a dark veil and a small slashed ring (`images/lf_empty.png`). Rows wrap (grid flow). The stock Loot tab text stays behind the panel (shown again when "Loot tab shows item icons" is off). Coloured rare-drop lines over the map. Hunt > Loot Filter in the top menu. Rules and the feed rows (`L.feedRow`, `L.outfit`, `L.killTip`, `L.iconCount`) in `lootfilterlogic.lua` (tested by `lootfilter_test.lua`); art from `tools/gen_lootfilter_art.py`. Every engine/console callback runs in `pcall`, the window is optional, images are checked before use. `game_itemrarity`/`game_itemtooltip` unchanged. Rule counters and sounds (right panel): per filter rule (Uniques, Legendary powers, Rarity glow, Modifier tier, Orbs) the drops of this session and in total (reset per rule, session, totals), a sound per rule (Chime, Bell, Ping, Drum, Fanfare or none), volume, Mute all, saved on the character; a kill plays the first matched rule's sound on the Effect channel (`g_sounds`; needs base patch 0032); optionally the counters in the Hunt Tracker's Chaos Drops tab (`game_hunt` reads `getCounters()`). Sounds `sounds/*.ogg` synthesised by `tools/gen_lootfilter_sounds.py` (our own; no recorded or base client audio). Server `data/scripts/chaos/lootfilter.lua`; tested in game. The supplies category reads "potions, runes" (arrows and bolts are gone: server/README.md "Infinite arrows and quivers"); quivers count as equipment |
| game_pact | extended opcode 222 (JSON: `open` / `sync` / `claim` / `buildSave` / `buildRename` / `buildDelete` / `buildLoad` out, `status` / `buildCode` / `message` back) | none (menu entry through `ChaosTopBar.addEntry`, Character > Chaos Pact) | The Chaos Pact window (Chaos skin, 560 x 560): Pact status and end date, the title, Claim daily coins, a Store button; the account limits table (free / Chaos Pact / bought / yours, inactive bonuses marked off); the special stash tabs; saved passive tree builds per account (Load opens the passive tree and asks for the preview through `game_passivetree.sendAction('buildPreview')`, Overwrite, Delete with a second click, Save current build), read-only slots dimmed. Logic `pactview.lua` (tested by `pactview_test.lua`); tested in game (server/README.md "Chaos Pact and account storage") |
| game_depottabs | extended opcode 111 (JSON; server -> client `tabs {tabs, max, size, used, ids, chest, lockers, inbox, market, hint, store, names, colors, palette, nameMax, town}`, `open {tab, ok, text}`; client -> server `open {tab}`, `style {tab, name, color}`) | none (wraps the stock `game_containers` onOpen handler at runtime; no base file changed) | The depot window: opening a depot locker opens one centred window ("<town> Depot") instead of the locker, chest and box container windows. 17 tab buttons in rows of 6 plus a "+ Tabs" store button (name or number, colour accent, lock on locked tabs, tooltip with the count or the store hint), the active tab's 100 slots as normal Item widgets (drag and drop, stacking, use, look), "87/100 items" and "4 of 17 tabs", Inbox, Market, Buy Tabs (the Store at Depot Tabs) and Close. Right-click a tab or the pencil: rename (16 characters) and colour (12 palette colours or default), stored per account by the server. The locker, chest and box are real containers opened with the engine's use packet; a tab switch asks the server first. Walking away closes them and the window. Stock windows of a box opened elsewhere keep the "Tab 3 (87/100)" title. Logic `depottabsview.lua` (tested by `depottabsview_test.lua`); window `depottabs.otui`; icons from `tools/gen_depot_art.py` (`data/images/game/depot/`: lock, edit, store); tested in game (server/README.md "Depot tabs") |
| game_referral | extended opcode 220 (JSON: `open` / `sync` / `enter {code}` out, `status` / `message` back) | none (menu entry through `ChaosTopBar.addEntry`, Character > Referral) | The Referral window (Chaos skin, 560 x 540): the account's code with Copy code (clipboard), what the friend and the referrer get, the friend's code box while the account is new (else who referred it, or why it cannot), the referred friends with level and the state of each milestone, this month's links and rewards and the coins earned. Logic `referralview.lua` (tested by `referralview_test.lua`); tested in game (server/README.md "Referral program"). The rewards text lists the tier rewards too (3, 5 and 10 friends at the qualifying level, server `referral_config.lua` `tiers`; `V.rewardsText`) |
| game_mentor | extended opcode 194 (JSON: `open` / `sync` / `list` / `register` / `retire` / `choose` / `invite` / `accept` / `decline` / `dismiss` / `release` / `seek` / `buy` out, `status` / `mentors` / `message` back, chunked by `Chaos.sendChunked`) | none (menu entry through `ChaosTopBar.addEntry`, Social > Mentors) | The Mentors window (Chaos skin, 680 x 580), five tabs. Find a mentor: the rules or why this character cannot pick, class / language / online filters with Search, "Looking for a mentor" (the Party Finder tag), invitations (Accept / Decline) and the referrer's mentor (Choose), the mentor list (name, level, class, online, language, hours, graduates, free places, note, Choose). My mentor: the mentor, since when, time hunted together, whether the bonus is on now and why not, the milestones with their state (paid / no marks / month cap / before the link) and marks, Dismiss. Mentoring: the requirements, the mentor card (language, hours, note, taking apprentices, show on website; Become a mentor / Save card, Retire), marks / today / month counters, Invite by name, the apprentices with their milestone steps and Release. Marks Shop: titles, cosmetics, supplies with price, owned and weekly limits. Top Mentors: rank by graduates. Party Finder rows, tooltips and applicants show "Mentoring" / "Looking for mentor" (`partyfinderview.lua`). Logic `mentorview.lua` (`mentorview_test.lua` in CI). Rendered in the Linux client with payloads made by the server core (offline); not run against a live server |
| game_unveil | extended opcode 196 (JSON: `open {path, id, clientId, name, rarityName, level, sig, orbs, offers}` / `result {ok, text, veil}` in, `choose {path, id, sig, choice}` out), server `veiled.lua` | none (opened by the server when an Orb of Unveiling is used on a veiled item, by use-with or the crafting bench) | The Unveil window (Chaos skin, 660 x 352): the item, the orbs left, three cards (veiled tier V1..V4 in its colour, name, text, range, "Effect of its own" for the hook modifiers); pick one, Unveil (final, one orb), the result line; the cards of a revealed item stay dimmed. Also: `game_itemtooltip` shows the veiled slot (`tip.veil`) in violet ("Veiled modifier" / "V4 Wraithstride [8-10]" + its text), `game_market` adds "Veiled" / "Unveiled" to a Browse row's sub line. `unveilview_test.lua`; tested in game (server/README.md "Veiled modifiers") |
| game_pouches | extended opcode 226 (JSON: `open` / `sync` / `set {rules}` out, `settings {rules, ids, titles, owned, rarities, open}` back) | none (uses `game_interface.addMenuHook`) | The Loot Pouch rules window (Chaos skin) of the store pouches (server `data/scripts/chaos/pouches.lua`): items on the autoloot list, coins, uniques, gear from a rarity (combo), supplies, gems, everything else; saved on the character at once; status line and Open Store when the character has no Loot Pouch. Opened by right-clicking the Loot Pouch > "Pouch settings" (shown only for the Loot Pouch's look with the item lock flag the server sets on every pouch) or by the Loot Filter's "Loot Pouch" button (`game_lootfilter/lootfilter.otui`). The pouches are ordinary containers (use = open); their tooltip lines "Store item: cannot be traded" and what it collects come from the server (`tip.store`, `tip.collects` in `game_itemtooltip/tooltiplogic.lua`). Logic `pouchesview.lua` (tested by `pouchesview_test.lua`); tested in game (server/README.md "Store pouches") |
| game_transmog | extended opcode 212 (JSON: `open` / `looks {kind}` / `apply {slot, look}` / `remove {slot}` out; `state {money, fee, slots, kinds, total, sets}`, `looks {kind, rows}`, `result {ok, text}` back, long ones joined by `registerExtendedJSONOpcode`) | base patch 0030 (`item:setAppearanceId`) | The Transmog window (Chaos skin): the six equipment slots with their current look, own look and preview side by side, the account wardrobe of the selected item's kind as a searchable grid, Apply (gold fee) and Remove look; Collection tab with progress bars per kind and the appearance sets (owned, or how to get them: store, achievement, season, exclusive). Character > Transmog, or right-click an equipped item > "Transmog". The look itself is drawn everywhere by base patch 0030 (item custom attribute 8); tooltips add "Appearance: <look>" (`game_itemtooltip/tooltiplogic.lua`, `tip.look`); `game_market` rows and the sell picker and `game_playerinspect` slots draw the look from server data. Logic `transmogview.lua` (tested by `transmogview_test.lua`); tested in game (server/README.md "Transmog") |
| game_cosmetics | extended opcode 225 (JSON: `open` / `select {kind, id, line}` / `preview {id}` / `hello` out; `state {line, lineName, rows, collection}`, `style {accent}`, `colors {names, full}`, `looks {names, full}`, `tryfx {kind, art, pulse}`, `result {ok, text}` back, joined by `registerExtendedJSONOpcode`), server `cosmetics.lua`, `exclusives.lua` | none | The Cosmetics window (Character > Cosmetics, Chaos skin, 720 x 480): tabs Spell Effects (the skins of the character's class line first, other lines dimmed), Kill Effects, Loot Labels, Chat Colours, Footprints, Outlines, Collection; a Default row per tab, Use, Preview (effects only the player sees, sent by the server; footprints and outlines drawn here by `game_cosmeticfx`), Open the Store; a sample per colour (the player's own chat line, rarity labels on the accent) and per footprint / outline (the character with its outline line through `game_cosmeticfx.applyOutline`, or the glow behind it on an engine without base patch 0038; prints beside it); a "Show other players' footprints / outlines" box on those two tabs. Collection: the exclusives of every visual kind (server `exclusives.lua`), owned first, kind, "Achievement: X" or "Boss: Y, rare drop", where it is chosen, the look on the own character (outfit, mount, wings, aura, shader). Once in the game it asks the server for the full style, colours and looks (`hello`: a send from the server's login event can arrive before the client is in the game, and a reconnect runs no login event). Colours the speaker's name in chat for player lines only (wraps the stock `game_console` `Message:updateLabel` after `game_chatlinks`; loads at priority 1003), hands the label accent to `game_groundlabels` and `looks` / `tryfx` to `game_cosmeticfx`. Logic `cosmeticslogic.lua` (tested by `cosmeticslogic_test.lua`); tested in game with two clients (server/README.md "Cosmetics", "Footprints and outlines", "Exclusives") |
| game_shaderfx | none | base patch 0044 (`UIWidget:setUiShader` / `setUiShaderParams`, `u_Params` in the shader); without it every call is skipped and the images stay plain | UI widget shaders, all GLSL written for this client (`data/shaders/chaos_ui_*.frag`, compile-checked by `tools/check_shaders.py`). Liquid health and mana orbs (`chaos_ui_orb`: layered sine surface, own value noise for the swirl and the bubbles, a fake sphere normal for the shading, a foam line; the value change makes it slosh, eased back in about 2 s) at the bottom corners of the game window, option `liquidOrbs` (off by default); a light sweep across the rarity frame of Legendary-and-up and unique items in inventory and container slots (`chaos_ui_shine`, a slanted band every 3.5 s, each slot at its own phase; option `rarityFrameShine`); greyscale for locked items (custom attribute 3; `chaos_ui_grey` as the slot's item shader, and only our grey is taken back) and `setGreyed(widget, on)` for any widget. Art `images/orb_mask.png` and `images/orb_ring.png` from `tools/gen_orb_art.py`. Pure helpers `shaderfxlogic.lua` (fill, slosh, phase, shine rule, locked rule), tested by `shaderfx_test.lua`. Not built or run in a client: offline numpy renders of the shader math only (outside the repository) |
| game_cosmeticfx | none of its own (`game_cosmetics` hands it the server's `looks` and `tryfx`) | `0038` for the outline line (`Creature:setOutline` / `setOutlineGradient` / `clearOutline`); without it the glow picture (uses `Tile:setWidget`, `Creature:addBottomWidget` / `clearBottomWidgets`, `UIWidget:setRotation`) | Footprints and outlines of every player on screen, drawn by this client: a print on the tile a player left (turned to the step, fading in 3.2 s; 160 on screen, 8 per walker; never on a tile with another module's widget; none while the own character stands in a protection zone) and an outline: a 2 px line that follows the player's silhouette (body, addons, mount and rider, the walking frame; drawn by the engine under the outfit's parts, so it stacks with outfit shaders, wings and auras and stays off names and bars). Colours per art key in `CF.OUTLINES` (one colour, or a vertical gradient: Ember, Storm, Paragon's Radiance, Void Corona, Cinderheart Blaze); pulsing ones breathe in the engine (1.8 s). Feature check per creature (`CF.hasEngineOutline`): a client without base patch 0038 gets the old soft glow behind the player (a bottom widget) instead. `applyOutline(creature, art, pulse)` for `game_cosmetics`' sample. Settings (g_settings node `chaosCosmeticFx`) hide other players' footprints / outlines; the own character always shows. Pictures `images/prints/*.png` (64 x 64, pointing north) and, for old engines only, `images/glows/*.png` (128 x 128) from `tools/gen_cosmeticfx_art.py` (shapes and noise with a fixed seed, no reference art). Logic `cosmeticfxlogic.lua` (tested by `cosmeticfxlogic_test.lua`, which also checks a picture and outline colours for every art key of the server's `cosmetics_config.lua`, the gradients and the feature check); tested in game with two clients (server/README.md "Footprints and outlines") |
| game_hideout | extended opcode 192 (JSON through `registerExtendedJSONOpcode`: `open` / `get` / `enter` / `leave` / `visit {guid}` / `place {key, x, y, r}` / `move {id, x, y, r}` / `remove {id}` / `clear` / `theme {key}` / `perm {level}` / `kick` / `visits` / `like {owner}` out; `state`, `visits`, `result` back), server `hideout.lua` | none (uses the engine's `Tile:setWidget` for the preview) | The Hideout window (Character > Hideout, next to Town Portal; a Go to Hideout button in the Portal Style window; Chaos skin, 720 x 500): Decorate (catalogue with kind / source / unlocked-only / search filters, lock reasons, Place, Open the Store for store decorations, the placed list with Move / Remove / Put all away), Hideout (themes, who may visit, Enter / Leave / Send visitors out / Like), Visit (VIP, party and guild hideouts, the showcase by likes or visits, recent visits). Placement mode: the window steps aside, a bar over the map (Rotate, Done), the hovered tile shows the decoration framed green or red (`HideoutLogic.check`, the server's rules), left click places, wheel rotates, right click ends. Logic `hideoutlogic.lua` (`hideoutlogic_test.lua` in CI); tested in game against a server copy (server/README.md "Hideouts") |
| game_groundlabels | extended opcode 230 (JSON), server `groundloot.lua`, `groundloot_core.lua` | none (uses the engine's `Tile:setWidget`) | Ground loot labels (PoE style): a name plate over every item on the ground worth seeing, in its rarity colour (uniques orange, orbs teal), stack count and rarity in the text ("Rare Fire Sword", "3x Chaos Orb"), framed in the colour when the loot filter makes it glow. The loot filter decides (`game_lootfilter`'s rules and settings, `getSettings()`): hidden items get no label, Rare+ always (setting), the rest only while Alt is held (hidden ones faded). "Corpse: 2 items" over a corpse you may loot that holds loot the filter cares about. A despawn timer where something decays (a corpse: until its loot is gone, all its container stages summed; ground items do not vanish on their own in this server). Labels of one tile stack, neighbours are moved up or down past each other, at most 40 (best first). Left click picks the item up into the backpack with the normal move (the engine walks there; an item lower in a pile is first put on top by the server, `raise`) or opens the corpse; right click the usual item menu; hover the rich tooltip (`game_itemtooltip.showTip`) or the corpse contents. Tiles in view are compared every 400 ms and when the player moves (the engine has no tile-change callback for Lua); only changed tiles are asked about. Settings (on/off, Rare+, Alt, corpses, timers, size) in g_settings, window from the Loot Filter's "Ground Labels" button. Logic `groundlabelslogic.lua` (tested by `groundlabels_test.lua`); tested in game at 1280x720 and 1920x1080 (server/README.md "Ground loot labels") The loot label accent cosmetic: `setAccent(color)` (called by `game_cosmetics`) gives highlighted labels that background; text and border keep the rarity colour (`GL.style`, tested) |
| game_levelwings | extended opcode 191 (JSON `play {id, lv, n}`, server -> client, sent to every player who sees the character; server `levelwings.lua`, `levelwings_core.lua`, `levelwings_config.lua`) | base patch 0036 (the two options; without it both count as on). Uses the engine's creature widgets (`Creature:addBottomWidget` / `addTopWidget` / `clearBottomWidgets`), no .dat / .spr change | Level-up wings: when a character on screen gains a level, a pair of golden wings opens behind it (in front while it faces north) and fades out: 12 frames over 660 ms, held to 1150 ms, gone at 1800 ms (`levelwingsmath.lua`). The widget is centred on the creature by the engine and sized by `g_sprites.spriteSize()` and the creature's draw scale, so it follows walks and HD scaling. One pair per creature (a new play restarts it), at most 12 at once. The stock level-up text and effect stay. No sound (the sound framework has no fitting asset). Settings: Options > Graphics > Effects, "Level-up wings on my character" / "on other characters". Frames `images/wings_01..12.png` (192 x 160, 2x a 32 px tile) from `client/tools/gen_levelwings_art.py` (drawn from scratch). Note: the engine's `Creature::removeBottomWidget` walks the wrong list, so the module only calls `clearBottomWidgets` when its widget is the creature's only bottom widget and otherwise leaves it blank for reuse. The map light tints the wings like everything else on the map (brownish gold in a dim, torch-lit room). Pure helpers tested by `levelwingsmath_test.lua`; tested in the Linux client against a live test server with two clients (own view and a spectator, both settings) |
| game_effectopacity | none (client only) | base patch 0049 (the one slider); without it the module only migrates the stored value | Spell effect opacity: base patch 0049 leaves one control, Options > Effects "Spell effects opacity" (the base's `opacityEffects` slider and g_settings key), 25-100% in steps of 5, for every magic effect (boss warning circles never vanish; missiles have their own slider). This module, at start: once per settings file, the value becomes the lowest one the player had set on the old controls (`opacityEffects`, Options > Effects "Own Spells" `ownSpellOpacity`, HP/MP circle "Own Spells" `spellOpacityOwn`; on 10.98 they all drove the same alpha), clamped to 25..100 (flag `chaosEffectOpacityMigrated`); later starts only clamp an out-of-range stored value. It goes through `GameOptions:setOption`, so the slider and the engine follow. No UI of its own. Logic `effectopacitylogic.lua` (tested by `effectopacitylogic_test.lua`, which also reads patch 0049: the 25 minimum, the clamp, the removed sliders, no C++). Not run in a client |
| game_rightclickequip | extended opcode 188 (JSON: `{on}` out at every login and when the option changes; `multiuse {ids}` back at login, the client ids of the multi-use weapons a right-click equips; server `rightclick_equip.lua`, `rightclick_equip_core.lua`, `rightclick_equip_config.lua`) | base patch 0037 (the option; without it it counts as on). Server src-patch 0024 does the equipping | Right-click equips items: the server puts on equipment that is used and has no use of its own, and takes a worn piece off into the backpack (server/README.md "Right-click equips"), so the base mouse controls do it with their own use click: a right-click in Classic Controls, Ctrl + click in Regular Controls, a left-click in Left Smart-Click, "Use" in the context menu. Ctrl / Shift / Alt keep their meanings. One hook: the base starts a use with on a multi-use item, and the stock weapons are multi-use (their use with breaks furniture); `game_interface`'s `processMouseAction` is wrapped so that the preset's use click on a listed multi-use weapon in the inventory or an open container sends a plain use instead. Tools that are also weapons (machete, crowbar, scythe) are not listed and keep their use with; "Use with ..." stays in the menu. Option "Right-click equips items" in Options > Interface. Logic `rightclickequiplogic.lua` (the option, the message, the list, the click per mouse preset, the decision), tested by `rightclickequiplogic_test.lua`; tested in the Linux client against a live test server (every slot, both ring slots, two-handed swaps, bow and quiver, the three mouse presets, the option off) |
| game_kitewalk | extended opcode 186 (JSON: `{on}` out at every login and when the option changes; server `kitewalk.lua`, `kitewalk_core.lua`) | base patch 0039 (the option, and "Auto Chase Off" no longer switching the stance while it is on; without the patch the option counts as on). Server src-patch 0028 does the kiting | Keep attacking while moving: a walk by a click on the map or the minimap, or by keys, keeps the attack target and the attacks; the clicked path wins over Chase Opponent, melee hits when adjacent, a bow, wand or spell in range, and the chase starts again when the walk ends (server/README.md "Keep attacking while moving"). The base client never cancelled the attack on a click walk; its option "Auto Chase Off" (Options > Gameplay, on by default) switched the stance to Don't Chase on every manual walk while attacking, which 0039 skips while this option is on. Option "Keep attacking while moving" in Options > Interface (on by default). Logic `kitewalklogic.lua` (the option, the message, when to send), tested by `kitewalklogic_test.lua` (also checks patch 0039); tested in the Linux client against a live test server |
| game_tileoverlays | extended opcode 156 (JSON: `bars {s = [{i, p, n, c, v | l + t}], d}`, `clear` in; `hello` out at every game start), server `tilebars.lua`, `tilebars_core.lua` | base patch 0041 (`Tile:addOverlayWidget`, the option "Field timers over magic walls and fields"); without it a tile's single widget slot is used when free and the option counts as on | Two things drawn over map tiles, each a widget the engine draws over its tile, so they follow walking, scrolling, zoom and floor changes and take no mouse input. **Field timers** (client only): the seconds left over magic walls, wild growth, fire / poison / energy fields ("1:05" past a minute, orange in the last 5 s). The table client item id -> time until gone (each stage of a decay chain summed) is `fielddata.lua`, made by `client/tools/gen_field_timers.py SERVER_DIR` from the installed base's `items.xml` (type magicfield with a duration) and `items.otb` (server -> client ids); cycles and client ids shared by different times are left out; run it again when items change (`--check` tells). The engine's `Tile.onAddThing` / `onRemoveThing` callbacks (on while the option is on) start a timer when a field appears on a tile that was already in view, judged from where the player stood before the step that brought new tiles in; a field that came into view with its tile (walking, a floor change, the login, turning the option on) shows "~", never a guessed number. A tile the server sends again keeps its timer (same field back within 250 ms). Out of view the timers are dropped. No Chaos system creates timed fields (checked: spells and scripts). **Server bars**: a label (with "m:ss" for a countdown) over a 64 px bar in the server's colour, stacked when one tile has several; brazier captures, profession node respawns, the invasion breach (server/README.md "Progress bars over tiles"). Option "Field timers over magic walls and fields" in Options > Interface (on by default). Logic `tileoverlayslogic.lua`, tested by `tileoverlayslogic_test.lua` (also the generated table and patch 0041); generator test `client/tools/gen_field_timers_test.py` (CI) |
| game_ringslot | none (server src-patch 0023 makes inventory slot 10, the old ammunition slot, a second ring slot; server/README.md "Second ring slot") | none | The second ring slot: the empty slot 10 gets the tooltip "Ring" (`ringslotlogic.lua`, tested by `ringslotlogic_test.lua`), the soul label's tooltip no longer names ammunition. Its placeholder image is the ring's: the Chaos skin draws `data/images/game/slots/ammo(-blessed).png` with the ring silhouette (`tools/gen_skin.py`), so the inventory window and the action bar's equipment presets show a ring slot. The item tooltip (`game_itemtooltip`) shows a quiver's slot as its own line "Off-hand: Quiver" and the inspect window (`game_playerinspect`) names slot 10 "Ring". |
| game_patchnotes | extended opcode 244 (JSON) + Social > Patch Notes | none | Patch Notes window (ornate skin): weeks on the left (date, title, NEW), the selected week on the right with the title, date, intro, coloured section headings (New, Changes, Fixes, Balance), bullets, sub-bullets and highlighted leads; "Don't show automatically" checkbox. The notes are Markdown files on the server (`server/data/patchnotes/`), so new notes need no client update; long notes arrive in parts. Opens by itself once per new week at login, after the Daily Reward window (server login window queue; the client also never shows it over a visible daily window). Social > Patch Notes in the top menu. Drawing and the login wait in `patchnotesview.lua` (tested by `patchnotesview_test.lua`). Server `data/scripts/chaos/patchnotes.lua`; tested in game |
| game_monkchi | extended opcode 247 (plain text `chi:<chi>:<max>:<decaySec>`, server -> client) | none | The Monk's chi HUD: five pips over the bottom of the map (server `monk_combat.lua` / `monk_chi_core.lua`). Only the Monk line (server ids 17-19) sees it; max 0 hides it. Pure helpers `chimath.lua`, tested by `chimath_test.lua`. Built, not tested in game |
| game_nameplate | extended opcode 248 (plain text `cid\|title\|color\|guild\|frame` lines; `q\|id,...` queries) + the Achievements window | base patch `0022-chaos-nameplate.patch` (`Creature:setNameplate`; the title line is the engine's `setTitle`) | Name plates over players: title in its source colour, `{guild}`, the name in gold on a 9-slice frame (`images/plate_<id>.png` from `tools/gen_nameplate_art.py`: default, gold, crimson, violet, frost, ember, verdant, bone, ashen, sapphire, rose, jade, copper, obsidian, amber, storm, and the never-sold laurel, sepulchre, infernal with a crowned ornament; `nameplatemath.lua` FRAMES lists them). Cached by creature id, asks the server for players without a plate (batched); monsters and NPCs untouched. Without patch 0022 it falls back to title and guild as one block above the name. Parsing and batching in `nameplatemath.lua` (tested by `nameplatemath_test.lua`). Server `data/scripts/chaos/nameplate.lua`, `titles.lua`; tested in game Frames ember, verdant and bone added (store, server `shop.lua` FRAMES). Frame cinderwrought (crowned) added for the season pass premium track (server `seasonpass_config.lua`) |
| game_achievements | extended opcode 250 (JSON) + Character > Achievements | none | Achievements window (Chaos skin): points of the character and the account, categories with done/total (plus All and Recently unlocked), a row per achievement with points, description, title / reward line and a progress bar ("Unlocked <date>" when done), hidden ones as "???", the title box (sends the Achievements window; shown when the server has the name plates) and the recent unlocks. Character > Achievements in the top menu. The unlock toast is game_chaosnotify's `achievement` action ("ACHIEVEMENT UNLOCKED"). Pure helpers `achievementsview.lua`, tested by `achievementsview_test.lua`; server `data/scripts/chaos/achievements.lua`; tested in game. Reward track (server message `track`): a bar to the next account point milestone with one pip per milestone (tooltip = the cosmetic's preview: kind, description, colour or label background, points to go), a "Reward track" entry in the category list (rows per milestone and per category completion, chat colours drawn in their colour, label accents behind the kind line), each category's tooltip names its completion title and cosmetic; hidden for a server without it (server/README.md "Achievements") |
| game_pets | extended opcode 254 (JSON) + Character > Pets | none | Pets window (Chaos skin): every species in a list (owned first with level and whether it is out, the others dimmed as "Not owned"), the selected one with its outfit, name and species, an XP bar (updated live after kills), its two abilities with values, cooldowns and the level the second unlocks at, how to get a species not owned yet, a rename box and Summon / Dismiss buttons, and a status line (out, resting and why, zone rule, death and call cooldowns). Character > Pets in the top menu. Pure helpers `petsview.lua`, tested by `petsview_test.lua`; server `data/scripts/chaos/pets.lua`; tested in game |
| game_buffbar | extended opcode 234 (JSON, server -> client; `sync` / `off` back) + Character > Buff Bar | none | Buff / debuff bar fixed under the character plate (`game_chaoshud`): small icons with a countdown and a stack count, left to right in rows as wide as the plate (10 icons of 26 px), buffs first, then debuffs (red border); a full row starts a new one below and the bar grows and shrinks with the rows. Anchored to the plate (left-aligned with its drawn edge, 2 px under it), so it follows the plate however it is moved (margins, `setPosition`, window resize); not movable or resizable on its own, an old saved position / size / lock is dropped. Empty: hidden (no space, clicks pass); the strip itself is phantom, so only icons take clicks. Plate hidden: the bar hides too; no plate module: the plate's own spot at the top-left of the game view. Hover for name, effect and time left; right click an icon for the settings. Everything comes from the server (`buffbar.lua`, registry `data/lib/chaos_buffs.lua`): engine conditions (haste, regeneration, food, poison, burning, freezing, drowning, energy, bleeding, slow, drunk, mana shield, invisible, in fight, skull timers ...), Chaos class buffs, world buffs, the Victory buff, Golden Hour / Chaos Storm, the day's events, double experience, trial kill stacks, chi, Rage, Reprisal, the Iron Palm stun on a player (Stunned, Stun Immunity) and the Templar aura ("<Templar>'s Aura", stacks = the reduction in percent, the tooltip with the Templar, class, reduction and the Sentinel's regeneration; icons `stunned`, `stun_immune`, `templar_aura`). Diffs only (add / update / remove) and a full list every 30 s; the countdown runs here from the milliseconds the server sent. Show / hide and countdown in the settings window (g_settings node `chaosBuffBar`). Icons: always our own `data/images/game/buffs/<name>.png`, 26x26 pixel art drawn 1:1 and unsmoothed (`client/tools/gen_buff_icons.py`, one per registry key; an ember-gold frame for buffs, a blood-red frame with corner thorns for debuffs; class buffs show their spell's art in that frame). `buff:<name>` names it; an older `spell:` / `cond:` spec falls back to the key's icon (`BuffMath.ownName`), so no stock condition art is used. Pure helpers `buffmath.lua` (order, row flow, attach to the plate), tested by `buffmath_test.lua`. Painted icons (setting "Painted icons" in the settings window, off): `images/game/buffs_painted/` ("Painted icons" below). Tested in game, see server/README.md "Buff bar and party frames"; the plate layout with 23 icons (3 rows), the plate moved by margins and by `setPosition`, hidden and shown, the rift HUD below, at 1280x720 and 1920x1080. Ember Blessings (server `blessings.lua`): one entry per kind (`blessing_xp`, `_gold`, `_damage`, `_ward`, `_speed`, `_regen`, `_crit`, `_loot`, `_rarity`, `_orb`), 60 s countdown, icons `buffs/blessing_*.png` from `gen_buff_icons.py` (motif plus an ember flame in the corner); nothing new in the module itself, tested in game with three blessings and a refresh. Vigils (server `vigils.lua`, 2026-10-12): `vigil_wrath`, `_iron`, `_haste`, `_clarity` per vigil that covers the character (stacks = the effect in percent, no timer) and `vigil_tithe` for Iron Tithe, icons `buffs/vigil_*.png` from `gen_buff_icons.py` (a banner with the vigil's emblem); nothing new in the module, not run in game |
| game_partyframes | extended opcode 235 (JSON; `open` / `close` / `kick` / `lead` / `invite` out, `state` back) + Hunt > Party Frames | none (uses `g_game.follow`, `look`, `partyPassLeadership`, `partyLeave`, `openPrivateChannel`, `g_map.getCreatureById`) | Party frames: a movable panel with a frame per member (outfit, name in the class colour, level, leader crown, health and mana bars with numbers, floor arrow and distance, in fight / dead / connection lost, the member's first buffs and debuffs, their names listed in the frame's tooltip, e.g. a Templar's aura), live from the server every 500 ms, hidden while not in a party. Exact numbers only for members in range (50 squares, 2 floors); far members show a rough health bar. Left click selects (and follows when on), shift+click looks, right click: message, follow, look, pass leadership and remove from the party (leader), invite a player (by name), leave, copy name. Scale, own frame (off by default), buffs row, numbers, follow and lock in the gear window (g_settings node `chaosPartyFrames`). The stock Hunt > Party window (`game_party_list`, a side bar window) is untouched. Marks `data/images/game/partyframes/*.png` (`client/tools/gen_partyframe_art.py`). Pure helpers `partymath.lua`, tested by `partymath_test.lua`. Tested in game with three characters. Default position (no saved one; saved positions are kept): the right edge of the game view below the map overlay's corner box and above its strip (`PartyMath.defaultPosition` / `freeArea`, re-read as the layout changes), clear of the invasion / rift HUDs and the strip at 1280x720, 1366x768 and 1920x1080 (measured in game, tests in `partymath_test.lua`; at 1280x720 four frames with buffs cover the lower 14 px of the overlay's corner box, only in its "corner" mode); the frames stay above the map overlay |
| game_castbar | extended opcode 231 (JSON; `start` / `end` / `other` / `otherEnd` in, `cancel` out; server `casting.lua`, `data/lib/chaos_casting.lua`) | none | Cast bar of the cast-time spells over the character: spell name and time left on a dark plate, filled on the client clock from the server's cast time; the server alone completes or interrupts (moved, paralysed, new spell, portal, cancelled, failed: red with the reason for a moment); click the bar to cancel (refunded). Smaller bars over other players in view while they cast. The Town Portal channel (`game_townportal`) uses the same bar (blue). A bar whose end never came goes after 3 s. Pure parts `castbarmath.lua` (`castbarmath_test.lua`). Tested in game at 1280x720 (four spells, interrupts, death, the other-player bar with a simulated message) |
| game_bestiary | extended opcode 253 (JSON) + Hunt > Bestiary, Hunt > Kill Tasks | none | Bestiary window (Chaos skin) with two tabs. Bestiary: categories with known / total, search, "Known only", a paged list (60 rows) with the stage colour, level and kills, and the selected monster's page: outfit, stage and a bar to the next one, what the stage reveals (level, health, experience; elements, immunities, where it lives; loot as item icons with chances; Chaos uniques), the completion bonus and Take task. Kill Tasks: the daily board and your tasks with rewards, progress, Accept / Abandon (Accept greyed with the reason at a limit) and the limits line. Task tracker HUD (`tracker.otui`) at the bottom right of the visible map (anchored left of `gameRightPanels`, above `bottomSplitter`): kill tasks (T) and bounty contracts (B) with live bars; click the title to fold; on/off in the window or Hunt > Task Tracker (kept in `g_settings`). Hunt > Bestiary / Kill Tasks / Task Tracker in the top menu; toasts through game_chaosnotify (type `BESTIARY`, action `bestiary`). Pure helpers `bestiaryview.lua`, tested by `bestiaryview_test.lua`; server `data/scripts/chaos/bestiary.lua`; tested in game |
| game_bossspawns | extended opcode 217 (JSON: `open` / `refresh` out, `list {now, refresh, cats, rows}` back, chunked by `Chaos.sendChunked` and joined by `registerExtendedJSONOpcode`) + Adventure > Boss Spawns | none (menu entry through `ChaosTopBar.addEntry`) | Boss Spawns window (Chaos skin, 700 x 560, fixed size): every boss of the server by category with foldable headers (count and how many are alive), Expand all / Collapse all, a search over names and places; each row the boss outfit, name, level, place with coordinates (or a note) and the respawn column: Alive, Respawns in (countdown), In (countdown, the day and time for far ones), Random, On demand, the player's own cooldown, Respawn due, Not seen yet, with the last kill and its killer under it; the tooltip has the full rule. Countdowns tick every second in the client, the list is asked again every 30 s while open. Pure logic `bossspawnsview.lua` (`bossspawnsview_test.lua` in CI). Rendered in the Linux client with a payload made by the server core (offline, login screen); not run against a live server |
| game_riftatlas | extended opcode 210 (JSON: `open` / `alloc {id}` / `refund {id, pay}` / `reset {pay}` out; `tree` (chunked by `Chaos.sendChunked`, joined by `registerExtendedJSONOpcode`), `state`, `credit` back) + Adventure > Rift Atlas and the Rift Atlas button of the rift HUD (`game_rift/rift.otui`) | none (menu entry through `ChaosTopBar.addEntry`) | Rift Atlas window (Chaos skin, 980 x 620): a node map of the 81 nodes the server sends (drag to pan, wheel or +/- to zoom, Centre), node frames and link lines of the passive tree (`/images/passivetree/`), icons and backdrop from `tools/gen_riftatlas_art.py` (`data/images/riftatlas/`: five 21-icon sheets, `start.png`, `background.png`; procedural, the spell icon plate style); the selected node with Allocate / Refund (gold or an orb), a keystone asks first; the points counter; the completion grid (4 themes x 15 tiers, Flawless, Swift, the 3 Omens) with a tooltip per cell (a Swift cell names its tier's own time, `grid.swiftTiers`, `RiftAtlasView.swiftSeconds`; an older server's one `grid.swift` otherwise); the totals of the allocation; Reset all (gold or orbs). Pure logic `riftatlasview.lua` (`riftatlasview_test.lua` in CI; also checks the real server tree when the repository is there). Rendered in the Linux client with payloads of the server core (offline, login screen); not run against a live server |
| game_partyfinder | extended opcode 208 (JSON: `open` / `hide` / `refresh` / `post` / `unlist` / `apply` / `withdraw` / `accept` / `decline` / `queue` / `unqueue` out, `init` / `list` / `badge` / `notice` back, chunked by `Chaos.sendChunked`) + Social > Party Finder | none (menu entry through `ChaosTopBar.addEntry`) | Party Finder window (Chaos skin, 720 x 560, fixed size), two tabs. Browse: activity and role filters, "Fits my level", one row per group (activity with its tier / floor range or target, note, leader, minimum level, time left counting down, the composition as role boxes: filled in the role colour, open slots outlined, tooltip with names and classes, up to 10 in a line and a raid listing of 15 wrapped into two rows of 8 + 7 (`V.slotGrid`, the row grows); "Needs 1 Healer, 2 DPS"), Apply (a role menu when the class fits more than one open role), Withdraw, Manage for the own group; "Join as" role / activity quick-join queue with its status. My Group: the listing form (activity, range / target / title, own role, wanted counts up to the activity's caps (`V.limits`: raid 15 with 3 tanks / 4 healers / 12 DPS and a 2 / 3 / 9 proposal, others 10 and 0-6) with "group of n / max", minimum level, expiry, note, auto-accept quick joins), Post / Update, Close listing, the listing summary, and the applications (name, level, class, role, quick join, age) with Accept / Decline. A new application shows a toast (top right, click opens My Group) and a red badge on the Social menu button, the menu entry text and the tab. Pure logic `partyfinderview.lua` (`partyfinderview_test.lua` in CI). Rendered in the Linux client with payloads made by the server core (offline, login screen); not run against a live server |
| game_antibot | extended opcode 211 (JSON: `answer {t, k}` / `another {t}` / `reportOpen {name}` / `report {name, reason, note}` out; `check {t, w, o, s, a, r}` / `checkResult` / `reportOpen {name, reasons, noteMax}` / `reportResult` back) + System > Report a Player, right-click a player > Report Player | none (menu entry through `ChaosTopBar.addEntry`, the right-click entry through `game_interface.addMenuHook`) | Presence check modal (Chaos skin, 400 x 290, centred, static): "Click the picture of: <word>", four item pictures in the buff icon frame (1 px gold border on a dark plate, hover highlight), countdown bar (colour turns at 25 s and 10 s), "Another picture" (one retry), result line; the client gets client ids and random keys only, never the answer. Report Player dialog (380 x 350): name, reason box (reasons from the server), note with a counter, the privacy line (public channels only, never private messages), Send / Cancel, the server's answer. Pure logic `antibot_logic.lua` (`antibot_logic_test.lua` in CI). Rendered in the Linux client offline (login screen) with a challenge built from the server pool; not run against a live server |
| game_factions | extended opcode 215 (JSON: `open {f?}` / `close` / `turnin {f}` / `deliver {key}` / `buy {key}` / `craft {key}` out; `state` (chunked by `Chaos.sendChunked`, joined by `registerExtendedJSONOpcode`), `msg {text, ok}`, `npc {f}` (a faction NPC opens the window) back) + Adventure > Factions | none (menu entry through `ChaosTopBar.addEntry`) | Factions window (Chaos skin, 820 x 590, fixed size): four faction cards (emblem, name, rank in its colour, "<NPC> is here", rank bar with reputation / next threshold; the shown one highlighted), the shown faction's emblem, lore, rival line, rank bar, the next rank, the week against the cap (red at the cap), today's diminishing returns, tokens carried with Turn in (enabled next to the NPC with tokens and room under the cap), and two tabs: Contracts (Daily / Weekly tag, text, progress bar, reputation, Deliver for deliveries) and Quartermaster (item, name, kind or item level and rarity, price in gold and tokens, needed rank in the state colour, Buy / Craft / Locked / Owned / Sold out with the reason; tooltip with the fixed modifiers). Emblems `data/images/factions/<key>.png` and `_small.png` from `tools/gen_faction_art.py` (our own pixel art, the buff icon frame). Pure logic `factionsview.lua` (`factionsview_test.lua` in CI). Rendered in the Linux client with payloads made by the server core (offline, login screen); not run against a live server |
| game_descent | extended opcode 205 (JSON: `open` / `start {weekly}` / `craft` / `pick {offer, card, curse}` / `buy {key}` / `ready` / `leave` / `query` out; `info`, `hud`, `offer`, `shop`, `closeOffer` / `closeShop` / `closeInfo`, `msg {text}`, `end` back) + Adventure > Ember Descent and the portal next to the temple | none (menu entry through `ChaosTopBar.addEntry`) | The Ember Descent: run HUD under the character plate (room x / N and type, theme, run clock, depth bar, wave and monsters left, embers, reward bonus and ward, held boons and curses as 26 px icons with stacks and tooltips, party, Continue / Leave), the boon choice (three cards with icon, rank, text and a curse strip with its checkbox, a countdown), the merchant (wares with prices) and the entry window (free runs, sigils, records, forge). Pure logic `descentmath.lua` (`descentmath_test.lua`). Icons `data/images/game/buffs/descent_*.png` (also on the buff bar) from `client/tools/gen_descent_icons.py` (cells of the element icon sets in the buff frame). Tested in game against a live test server (screenshots kept outside the repository) |
| game_raid | extended opcode 213 (JSON through `registerExtendedJSONOpcode`: `open` / `start` / `continue {id}` / `join {id}` / `leave` / `buy {key}` / `journal` / `query` out; `info`, `journal`, `hud`, `alert`, `loot`, `end`, `msg`, `closeInfo` back) + Adventure > Raid: Ashen Sepulchre and the portal next to the temple | none (menu entry through `ChaosTopBar.addEntry`) | The Ashen Sepulchre, the weekly raid: the raid window (Chaos skin, 660 x 500) with This Week (the loot lockout of each boss and the time to the reset, the raids of this week with Continue / Join), Boss Journal (per boss: intro, role hint, phases, every mechanic with its numbers, the personal loot preview) and Vendor (the week's seeded stock for Sepulchre Marks with weekly limits); Open New Raid / Leave Raid. In a raid: a HUD under the character plate (the boss and its health, phase, enrage clock, bosses slain, raiders / fallen / adds / effigies, the player's own Sundered / Hexed / Withering Hex, the last call-outs) and mechanic call-outs over the map (coloured by kind). The buff bar shows the boss debuffs (icons `buff:raid_*` from `client/tools/gen_raid_icons.py`). Pure helpers `raidview.lua` (`raidview_test.lua` in CI); server `data/scripts/chaos/raid.lua` (server/README.md "The Ashen Sepulchre, the weekly raid"); tested alone on a live test server (window, journal, vendor, HUD, call-outs, lockouts). `game_partyframes` wraps a raid of up to 15 frames into columns (`PartyMath.grid`, tested in `partymath_test.lua`) |
| game_community | extended opcode 203 (JSON: `open` / `close` / `donate {gold}` out; `state` (chunked by `Chaos.sendChunked`, joined by `registerExtendedJSONOpcode`), `msg {text, ok}`, `brazier {}` (the Great Brazier was used: opens the dialog) back) + Adventure > Community and the Great Brazier next to the main temple | none (menu entry through `ChaosTopBar.addEntry`) | Community window (Chaos skin, 720 x 600): the goal's name, text and time left, its bar (points / target, percent) with marks at 25 / 50 / 75%, four stage chips (icon, name, short buff, Active with the time left / Reached / At n%; the open one highlighted, tooltip with the full buff and hours), your contribution (points, rank, today against the daily cap, today's points per source against its cap, red at the cap, the reward rules), the top contributors, the week's world modifiers (icon, name, text, time left, "set by the staff") and Feed the Brazier. The Brazier dialog: gold carried and today's room, an amount (`150k`, `1.5m`, `25,000`), +10k / +100k / +1m, a preview (gold taken in whole thousands, points) and Give gold (only next to the Brazier). Countdowns run on the client between states. Icons `data/images/game/buffs/community_*.png` and `wmod_*.png` (also on the buff bar) from `client/tools/gen_community_icons.py` (cells of the element icon sets in the buff frame first, the rest drawn with the buff icon kit). Pure logic `communityview.lua` (`communityview_test.lua`). Rendered in the Linux client with payloads made by the server core (offline, login screen; the buff bar with the game panel shown); not run against a live server |
| game_loadouts | extended opcode 206 (JSON: `open` / `save {slot, name, icon}` / `load {slot}` / `rename {slot, name, icon}` / `delete {slot}` / `cancel` out; `state {slots, limit, active, cooldown, castMs, inPz, ...}` joined by `registerExtendedJSONOpcode`, `result {ok, text, lines}`, `cast {ms}`, `castEnd {result}` back; the channel also draws on the `game_castbar` bar, opcode 231) | none (menu entry through `ChaosTopBar.addEntry`, Character > Loadouts; the Loadouts button in the passive tree window is created at runtime from this module, `game_passivetree` is not changed) | The Loadouts (Armory) window (Chaos skin, 700 x 540): the slot list (icon, name, points / runes / gear completeness, ACTIVE / CHECK / LOCKED tags, locked slots with their unlock level), the selected loadout's summary (class and ascension, passive points, keystones, Paragon points, supports per spell, gear set completeness with every missing item and where it is, the free-refund warnings of a changed tree, the action bar profile), name box and icon button, Save / Load / Rename / Delete (Delete asks to confirm), the switching hint (instant in a protection zone, channel time, cooldown countdown, instance) and the server's answer. Client-side only: the action bar profile per character and slot (`g_settings` node `loadouts`), switched to after a load. Logic `loadoutsview.lua` (tested by `loadoutsview_test.lua`); tested in game (server/README.md "Loadouts (Armory)") |
| game_charms | extended opcode 198 (JSON: `open` / `place {ref \| pos, sid, iid, x, y}` / `move {id, x, y}` / `take {id}` / `salvage {ref, sid, iid}` / `reforge {ref, sid, iid}` out; `state {cols, rows, cells, placed, bag, groups, totals, shards}` joined by `registerExtendedJSONOpcode`, `result {ok, text}` back) | none (menu entry through `ChaosTopBar.addEntry`, Character > Charms) | The Charms window (Chaos skin, 640 x 520): the 5 x 4 charm grid (open cells, locked cells with a padlock and the unlock reason as tooltip, placed charms sized by shape with the rarity colour as border), the Cells list (level 200 / 400 / 600 / 800 and the "Edge of Ruin" achievement), Your Charms (the charms in the backpack), Totals (capped ones marked), Salvage / Reforge. Drag and drop: from the list onto the grid with a green / red preview of the cells, a placed charm to move it or back onto the list to take it out, an item from an open backpack onto the grid. A tooltip per charm. Art: each charm is drawn as an item sprite of the live pair (UIItem; stock 10.98 trinkets, one per modifier and unique, none shared, `charmsview.lua` `V.LOOKS`; 32 px, a 2x2 charm 64 px), in the skin's slots `data/images/chaos/charmslot_1x1/2x1/1x2/2x2.png` (`client/tools/gen_skin.py`, exact tile sizes, not sliced) with the loot filter's frame and glow in the rarity colour; locked cells are dimmed slots with the depot padlock. The old generated round glyphs (`gen_charm_icons.py`, `data/images/game/charms/`) are gone. Logic `charmsview.lua` (tested by `charmsview_test.lua`); tested in game (server/README.md "Charms") |
| game_professions | extended opcode 195 (JSON: `open` / `close` / `sell {id, n}` / `sellAll` out; `state {profs, bonus, cap, per, tiers, demand, areas, broker, full, capDay, late, nextDay, nextWeek, respawn}` joined by `registerExtendedJSONOpcode`, `result {ok, text}`, `levelup {k, lv}`, `npc {}` (the Material Broker opens the window) back); the gathering channel uses `game_castbar` (opcode 231) | none (menu entry through `ChaosTopBar.addEntry`, Economy > Professions) | Professions window (Chaos skin, 820 x 580): the four gathering professions (level, experience bar, tier), the experience bonus, where to gather (areas, your ready nodes, fishing, nearest town), the Material Broker's board of the week (price x demand, sold today, carried, Sell / Sell All next to a broker). Logic in `professionsview.lua` (`professionsview_test.lua`); buff icon `data/images/game/buffs/professions.png` (`client/tools/gen_buff_icons.py`). Tested in game (server/README.md "Professions") |
| game_gamble | extended opcode 199 (JSON: `open` / `close` / `buy {i, w, id}` / `reroll {w}` out; `state {w, items, level, gate, near, money, left, hours, at, tz, reroll, rerolls, rerollMax, odds, npc, last}` joined by `registerExtendedJSONOpcode`, `result {ok, text, reveal}`, `npc {}` (the Gambler opens the window) back) | none (menu entry through `ChaosTopBar.addEntry`, Economy > The Gambler) | The Gambler window (Chaos skin, 690 x 610): a grid of sealed crates (look with a "?" seal, name, slot, item level, price; the rarity hidden), the countdown to the next 4-hour stock with its time and zone, Fresh Crates (the paid early refresh), the odds per crate, the reveal of the last crate in its rarity colour; buying only next to the Gambler (the server checks). One purchase at a time (every Buy button waits for the answer, 4 s at most); the answer fills the grid in place, so no cell is destroyed under the mouse; the reveal takes only client ids 1..65535 and a new engine item per look, and answers after Close or an unload are ignored. Logic in `gambleview.lua` (`gambleview_test.lua`), the window flow on a mock UI in `gamble_flow_test.lua`. Tested in game (server/README.md "The Gambler") |
| game_pvpzone | extended opcode 193 (JSON through `registerExtendedJSONOpcode`: `open` / `query` / `enter {accept, hcAccept}` / `pledge {faction}` / `buy {key}` out; `state`, `hud`, `enter`, `hide`, `msg` back) + Adventure > Scorched Marches | none (menu entry through `ChaosTopBar.addEntry`; `g_game.setSafeFight`) | The Scorched Marches, the open-world PvP zone: the window (Chaos skin, 600 x 520: the rules, the Cinder Shrine timer and holder, the faction pledge rows, the embers vendor with item icons and weekly limits, the record; Enter), the entry confirmation (460 x 360: every rule, the carried embers at risk, "I understand", a Hardcore line; Enter disabled for Hardcore characters), the HUD at the top of the map in the battleground HUD's place (embers carried / cap bar, the pledge, the shrine line: timer, warden, capture progress or contested, the holder and its time left, protection or the exit channel). Secure mode off inside, restored on leaving. Pure helpers `pvpzoneview.lua` (`pvpzoneview_test.lua` in CI); server `data/scripts/chaos/pvpzone.lua` (server/README.md "The Scorched Marches (open-world PvP zone)"); tested on a live test server with two clients |
| game_healthcircle | none | none | In `alternates/`: the base client's own is used |
| game_mainpanel | none | none | In `alternates/`: the base client's own is used |
| game_chaosnotify (was game_notifications) | extended opcodes 79, 151, 152 | none | Needs server script (`notifications.lua`). Toast types per message kind; `sale` = ITEM SOLD with the toast scales icon (`images/toast/market.png`, as MARKET; server market.lua / orbexchange.lua: item, price, fee, proceeds, or "While you were away: ..." at login), `achievement` = ACHIEVEMENT UNLOCKED with the trophy icon (`topbutton_ranking`); titles use each type's colour. Three toasts shown, stacked by their own heights (no overlap with the 140 px invitation toasts), the rest wait in a queue capped at 12 (the oldest message toast gives way). Logic `notifyview.lua` (tested by `notifyview_test.lua`); `testNotifications()` shows a sale and an achievement too. Invitation toasts (PARTY_INVITE: Accept / Decline; CATACOMB_FREE: Start / Cancel) use the styles of `toastbuttons.otui` (`ChaosToastAccept`, `ChaosToastDecline`, 80 x 24, normal / hover / pressed / disabled clips); the label is drawn by the client in the Chaos heading font when loaded. Art `images/toast/` (accept.png, decline.png, party_invite.png and catacomb_invite.png, both 48x48) comes from `client/tools/gen_toast_art.py`: iron plates with a gold rim, an ember-green or muted crimson accent; the catacomb icon is a stone archway with a skull keystone, an iron band, a gold rim and ember light on the stairs inside; the old stock yes / no scribbles, the party icon and the catacomb icon with baked text are gone; checked offline in the client (hover and pressed). Message toast icons (48x48, same generator, frame and materials, no text): GM_BROADCAST and the fallback `announce.png` (sealed scroll, gold seal), TASK_COMPLETE `task.png` (pinned parchment, check mark), BATTLE_PASS and SEASON_PASS `season_pass.png` (laurel medallion, ember stone), NEW_PLAYER `new_player.png` (lantern), ASCENSION `ascension.png` (winged flame), MARKET `market.png` (scales), INVASION `invasion.png` (crossed axes), BOUNTY `bounty.png` (wanted poster and dagger), BESTIARY `bestiary.png` (clawed tome), JOURNEY `journey.png` (compass), BOSS_POINT `boss_point.png` (crowned skull); the stock `gm.png`, `task.png` and `battlepass.png` with baked text are gone; contact sheet of every toast type checked in the client |
| game_itemtooltip | extended opcode 242 (JSON), server `item_tooltip.lua` | none | Rewritten: server-driven rich tooltip on hover over inventory and container items (rarity, item level and tier, base stats, modifiers with roll ranges, sockets and gems, unique and set, requirements) on the Chaos tooltip plate; Ctrl shows the equipped item(s) of the same slot side by side with green/red differences; cached by per-item id and version. View logic `tooltiplogic.lua` (tested by `tooltiplogic_test.lua`); tested in game (server/README.md "Item attributes in packets and rich tooltips") The icon draws a transmog look (`tip.look`, `item:setAppearanceId`, base patch 0030), also in item link tooltips. Item set pieces: the title "Set ..." in the set green and a set block (`L.setLines`: pieces that count, every piece worn / below its level / not worn, every bonus active or dim); the cached set pieces are dropped when the equipment changes (`LocalPlayer.onInventoryChange`, `L.dropSetTips`). Tested by `tooltipsets_test.lua`; checked on a live test server (server/README.md "Item sets") Quivers (server/README.md "Infinite arrows and quivers"): the slot "Quiver", the base's implicit modifiers as signed rows in the modifier colour (`b.imp`) and the gold note line `tip.note` ("Works only while you hold a bow or crossbow."); tested in `tooltiplogic_test.lua` and in game. No ammunition count or warning in the client: the ammunition slot holds the quiver (count 1) |
| game_chatlinks | extended opcode 249 (JSON), server `itemlink.lua`, `itemlink_core.lua` | none | Item links in chat: Shift+click an item in the inventory or a container (with the chat input active) puts `[Item Name]` in the message, up to 3; the server checks the player carries the item and keeps a snapshot of its tooltip for 10 minutes under a random id; sending writes the chip out as `[Item Name]{<r><id>}` (ASCII, readable in other clients) in ordinary speech, so default channel, party, guild, channels and private messages all carry it. Messages with links are drawn with the name in the rarity colour (unique orange); hovering one asks the server for the snapshot and shows the rich tooltip through `game_itemtooltip` (`showTip` / `hideTip`; Ctrl compares). Wraps three functions of the stock `game_console` (`Message:updateLabel`, `Message:handleMouseRelease`, `Chat:sendMessage`, `Chat:sendMapText`) and puts them back on terminate; hooks `UIItem.onMouseRelease` in front of the stock handler. No links in the Help channel (server patch `tools/patch_help_itemlinks.py` for modified clients), NPC, loot and spell tabs. Logic `chatlinks_logic.lua` (tested by `chatlinks_logic_test.lua`); tested in game with two clients (server/README.md "Item links in chat"). Its wrapped handlers return exactly one value: the engine calls a table of connected handlers (`g_game.onGameStart` / `onGameEnd`, `UIItem.onMouseRelease`) and stops the rest of the table with "function call didn't return the expected number of results" on two, which skipped every onGameStart after it at each login (party frames never asked for their state, the map overlay, rifts, ...) The parts it draws stay on the label (`label.chatParts`) so `game_cosmetics` can colour the speaker's name on top |
| game_playerinspect | extended opcode 240 (JSON), server `inspect.lua`, `inspect_core.lua` | none | Inspect Player window (Chaos skin): outfit, name, level and class, guild and rank, achievement points, best rift tier, Vocation Trial tier, the ten equipment slots with rarity frames and the rich tooltip on hover (through `game_itemtooltip`). Opened from the top menu (Social > Inspect Player: type a name, any online player) and from the right-click menu of a player (`game_interface.addMenuHook`, within 10 tiles). The Passive Tree (n) button opens the character's tree read-only in `game_passivetree` (the server's `tree` packet; it and the `equip` packets come through `Chaos.sendChunked`, parts joined by `playerinspect_logic.lua`). The checkbox "Allow others to inspect me" is the character's privacy setting (default on). Named `game_playerinspect` because the base client already has a module `game_inspect` (Inspect Object). Logic `playerinspect_logic.lua` (tested by `playerinspect_logic_test.lua`); tested in game with two clients (server/README.md "Inspect Player") |
| game_npctalk | none (the NPCs' own private talk: MessageModes.NpcFrom / NpcTo, nothing on the server) | none (replaces the hooks of the base `game_npctrade` dialog window while loaded: `tryHandleNpcDialogMessage`, `onNpcPlayerTalk`, `onNpcConversationAttempt`, `endNpcConversation`, `setNpcDialogWindowEnabled`; `game_interface.talkToNpc`; `g_game.use` on an NPC; `g_map.addThing` for the conversation NPC's map texts; all restored on unload) | NPC dialogue window: Talk (the NPC's menu, a left click with smart controls, Use / right-click with classic controls) walks into the talk radius (3 tiles; a reachable tile, so NPCs behind counters work) and says "hi"; the conversation runs in a speech bubble over the NPC (Chaos skin, tail pointing at its name, under it when there is no room above; follows the NPC and the camera every frame, kept inside the visible map between the top menu bar, the side panels and the console): name, portrait, "You: ...", the reply with clickable {keywords} (and chips), a text field, Yes / No / Trade / Bye when they fit; long replies wrap and scroll; the conversation so far in the name's tooltip (`SupportsText.wrap`). Lines of other NPCs stay in the console; the conversation NPC's lines leave the map and the console (copy to the console: "..." menu, g_settings `npcTalk.consoleCopy`). Esc, Bye or x say "bye"; walking out of range or 120 s idle close it; a second NPC gets "bye" to the first, then "hi" 1.5 s later. Server windows (the Oracle's Choice, the Keeper's trials, the trade window) open as usual. Off: Options > Interface > Disable NPC Dialog Window (console as before). Art `images/tail_*.png` from `client/tools/gen_npctalk_art.py`; logic `npctalk_logic.lua` (tested by `npctalk_logic_test.lua`); tested in game at 1280x720 and 1920x1080 |
| game_mapoverlay | extended opcode 245 (JSON, `watch` to the server, `marks` and `rift` back); server `map_marks.lua` | `g_minimap.clearArea` (client base-patch 0024, forgets the explored tiles of a rift square so each run starts fresh) | See-through map over the game view, centred on the character (Tab by default; the stock Next Channel moves to Ctrl+Tab; rebindable in Options > Hotkeys), wheel or +/- zoom x1..x16 (toward the cursor while panned), Ctrl + wheel opacity 20-100% in 10% steps, centred or top-right box; hold the middle mouse button and drag (or Shift + arrows, Ctrl + Shift + arrows while chat is on) to pan the map and its icons, Home / Ctrl+Home (hotkey "Minimap: Map Overlay Centre", rebindable) or the strip's Centre button snaps back to the character; while panned a "Panned" note shows on the strip and the character keeps a marker (an edge arrow when off screen); the pan is kept in memory only and resets when the overlay closes, on logout and when a new rift run starts. A compact control strip (opacity -/+, zoom -/+, Centre, Close, hint; the only clickable part, the rest stays click-through) sits in the bottom right corner of the free game view. A settings window (Hunt > Map Overlay Settings) with opacity, zoom, position, the strip switch and mark filters. Own icons (`tools/gen_mapoverlay_icons.py`) for party members, temple, depots, NPCs, rift entrance / guardian / chest / coffer / goblin, treasure goblins, world boss, invasion target and boss, dungeon bosses, and the character. Pure helpers `mapmath.lua` (pan, zoom toward the cursor, clamping, free view area; tested by `mapmath_test.lua`); server rules in `map_marks_core.lua` (tested by `tests/map_marks_test.lua`). Tested in game in town, in a hunting area and in a rift; also a party member (two clients), a rift's coffer (until it is opened or crumbles at the seal), chest, guardian and goblin, a treasure goblin, the world boss, an invasion target and boss, wheel / Ctrl+wheel / strip buttons / middle-drag pan with the icons moving with the map |
| game_mapmarkers | extended opcode 153 (JSON: `hello {party, poi}` at login and `set {party}` / `set {poi}` out; `party {m}`, `poi {v, marks}` (chunked) and `reveal {marks}` back; server `partymarkers.lua`, `poi.lua`) + Hunt > More > Map Markers | none (children of the base minimap widget, `UIMinimap:getTilePoint`, `connect` on its camera, zoom, geometry and mouse move) | Map markers on the minimap and on the full map (the same widget, Ctrl+Shift+M): the other party members as pins in a party colour (one white image tinted per member, a member keeps its colour), an up / down triangle when on another floor than the one shown, an arrow on the edge toward a member out of view (8 directions, clear of the minimap window's controls), gliding to the new place in 0.8 s; points of interest (temples, depots, banks, Chaos NPCs, shops, travel, blessings, crafting, guild hall, portals, dungeons, boss places, hunting areas), the remote ones once discovered. Hover: name, health, floor and distance of a member, the name of a point. The markers never take the mouse (clicks, drags, the wheel stay the minimap's). Settings window with party members on / off, points of interest on / off and a check box per category (g_settings node `mapMarkers`). Icons `data/images/chaos/mapmarkers/*.png` (`client/tools/gen_mapmarker_art.py`). Pure helpers `markermath.lua`, tested by `markermath_test.lua` (settings, colours, floor arrows, edge clamp, glide, hover text, category filters). Tested in the Linux client against a live test server with two clients and a bot in a party (server/README.md "Map markers") |
| game_sidebars | none | none | Not in the overlay: it is the base client's own module |
| game_realminimap | none | none | Not in the overlay: it is the base client's own module |
| game_nameshaders | extended opcode 96 | also hooks `onOpenOutfitWindow` with extra shader lists | Needs engine and server work |
| game_dungeons | extended opcode 109 | none | Needs server script (base server has dungeon customs). Server action `open` shows the window (the base dungeon entry tile, server `tools/patch_base_dungeon.py`) |
| game_infinitytower | extended opcode 214 | none | Needs server script. It is classic-style, so no conversion was needed. The "Top Rank Rewards" podium shows the chests the server sends in `topRewards` (look = the chest's client id, tooltip = its contents; server/README.md "Infinity Tower season rewards"); before the first update the stock chest looks 2478, 2472, 2469 (the old ids 63194-63196 did not exist in the 10.98 items) |
| game_event | none seen in the module | none | Client-only UI; wiring to a server event system is open |
| game_creatureinformation | none | engine APIs this client lacks | Not included |
| client_chaos_numbers | none | none | Short-number formatter for every module (`formatShortNumber`, `shortNumbersIn`); self test `numbers_test.lua` runs in CI; not run in a client |
| client_chaos_login | none | none | Login screen layout (see "Login screen" below); art from `tools/gen_login_art.py` (from the login artwork in `tools/art_src/`); tested in the Linux client at 1280x720, 1366x768, 1920x1080 and 1024x768. The living scene behind it (see "Login scene"): `loginscene_core.lua` (tested by `loginscene_core_test.lua` in CI), `loginscene.lua`; tested in the Linux client at 1280x720 and 1920x1080 |
| client_chaos_charselect | none (HTTPS to the website's account API) | base patch 0050 (`Services.account`); base patch 0025 (the 10.98 list's outfits) | The character select and Create character (see "Character select" below); `charselect_core_test.lua` runs in CI; art from `tools/gen_charselect_art.py`; tested in the Linux client at 1280x720 and 1920x1080 |
| client_chaos_updater | none (HTTPS from the website) | base patch 0031 | Signed updater on the login screen (see "Signed updater" below); `updater_core_test.lua` runs in CI; tested in the Linux client |
| game_chaosguard | extended opcode 190 (JSON `hello {build, modules}`, client -> server, once per login) | base patch 0035 (`g_game.getChaosClientBuild`; the HMAC answer on opcode 189 is C++ only) | The client guard's Lua hello (server/README.md "Client guard"): the build and how many of our modules (`game_*`, `client_chaos_*`) are loaded; the server expects it within 30 s and at least 20 modules. `guardhello_test.lua` runs in CI; tested in the Linux client. Also holds `opcode_fuzz_test.lua`, the client half of the protocol fuzz test (every module's opcode handlers through base patch 0043's dispatcher, server/README.md "Protocol fuzz test") |

Opcode numbers above do not collide with the ones the base server already uses (106, 91, 181, 107, 202, 1, 136, 99, 201, 92, 89). The stash uses 110 and the season pass (game_battlepass) 227.

## Shared assets copied
`data/images/topbuttons/` (loot, bank, battlepass, dungeon, passive_tree, minimap), `data/images/ui/events/` (event banners), `data/images/ui/` rarity frames (copied from game_itemrarity).

## Not done
Server-side scripts, engine changes, any runtime test, translation of Portuguese/Spanish strings.

## Added after the first draft
The theme (`client_chaos_theme`, `client_chaos_topbar`, `data/images/chaos/`, generator in `tools/gen_theme_art.py`) and the admin panel (`game_admin`, opcode 120) are in the overlay too. The server counterparts are in `../server/`.

## Healing helper: no replay after a stall (base patch 0026)
`base-patches/0026-helper-no-cycle-replay.patch` (`mods/game_helper/helper.lua`): the helper's cycles schedule their next run from now (after a client stall they run once instead of replaying every missed 50 ms cycle) and its spell casts go through a rate guard; tested in game (one cast after a 2.5 s stall, 17 before).

## HD upscaling: xBRZ 1.8 (base patch 0027)
`base-patches/0027-xbrz-1.8.patch`: xBRZ 1.4 -> 1.8 with edge padding per sprite; before/after compared in the Linux client at x2, x3 and x4 (outfits and items) and offline on effects (see `BASE.md`).

## Monster bar (new)
`game_monsterbar` (opcode 125) shows a bar at the top of the map for the creature you attack. The server side is `server/data/scripts/chaos/monster_tiers.lua`. The client's own `game_boss_health` was not reused: it waits for a native boss-health packet that the 10.98 server does not send.
Look (`monsterbarstyle.lua`, tested by `monsterbarstyle_test.lua`): seven styles from the server's tier and role: normal (plain iron, rivets), magic (sapphire gems), rare (gold filigree, topaz), legendary (iron flame crowns, ember gems), boss (bone horns over skull caps, crimson), guardian (a rift guardian: the boss look with violet rift shards) and omen (an Omen guardian: obsidian band, pale gold crescents, violet omen eye). The name and the level (`Lv N`) sit on iron plates in the style's colour, in the theme's heading font when it is loaded; a long name drops the tier word, and a name still wider than the widest plate (300 px) is cut with "..." (`fitTitle`). The longest titles fit whole: "Sangrith the Bloodmoon Herald" 220 px (its "Omen Guardian" tag dropped), "Rift Guardian Abyssal Sovereign" 224 px, "Kaelgor the Infernal Warlord" 214 px, of 272. Bosses and rift guardians are named in `#ff6a50` (the fill's sheen) on the bar and in the world: the UI red `#e03a1e` was hard to read on dark ground and on a red boss; the test checks every tier colour for 4.5:1 on dark red-black ground and the boss colour for 3:1 on a red body. Names in the world are drawn over the light since base patch 0042 (`BASE.md`). The fill is blood red for every style (a sheen in the style's colour), with a damage trail: the part just lost stays lit for 350 ms, then shrinks to the health. Modifiers are 26 px chips under the bar in the buff-icon style with the blood-red debuff frame (a threat to the player), with tooltips. `preview(info)` shows the bar with made-up data (screenshots, checks).
Art: `tools/gen_monsterbar_art.py` writes `data/images/chaos/monsterbar/` (frame_, fill_, plaque_<style>, trail, mods/<modifier>). It reuses the gen_skin.py materials (iron, gold, gems, rivets, the HUD fill) and the gen_buff_icons.py motifs and frame; every alpha edge is hard, with no blur or glow halo. The small bars over creatures are drawn by the engine (a 27x4 rect in the creature's information colour); tiered monsters get their style's colour there through `setInformationColor`, as before. Checked offline in the client with injected data (every style, the tooltip); not yet in a live fight.
Placement (`monsterbarmath.lua`, `monsterbarmath_test.lua`): the bar is a child of the map panel, which in the extended view starts above the window (y -80 at 1280x720). The bar goes 6 px under the top menu bar, centred over the character, moved right of the character plate when they would touch (1024x768). It is placed again when the map panel changes size. Checked in game at 1024x768, 1280x720, 1366x768 and 1920x1080.
Boss cast bar (`monsterbarmech.lua`, `monsterbarmech_test.lua`, `monsterbarmech.otui`, 2026-10): the action `mech` on the same opcode 125 (server `boss_mechanics.lua` and `raid.lua`, server/README.md "Boss mechanics") names the next boss mechanic with a countdown, "Kaelgor: Meteor Rain 2.4s - move out", in a 344 x 18 bar under the monster bar (in its place when nothing is targeted). Colour by kind: red telegraph (move out), purple channel (kill the totem), green soak (stand in the circle), blue line of sight (hide behind a pillar), grey interrupted. It holds 600 ms after the hit, then hides. `previewMech({ boss, label, ms, kind })` shows it without a server. Not yet seen in a live fight.

## Outfit shaders for monsters (new)
`game_chaosshaders` registers the 17 shader names the server sends (same list as the base client) using the files in `overlay/data/shaders/`, and `ember_pixent` (`pixent_ember.frag`: `pixent_green.frag` with an ember colour; shader 18 of the server's exclusives, a boss drop). It also registers six outfit shaders written for this server, shaders.xml ids 19-24 (server/README.md "Cosmetics", "Chaos outfit shaders"; off on the server as shipped): `chaos_ember_glow` (a flickering ember rim, warm light, sparks drifting up), `chaos_frost_rime` (cooled to ice, a white-blue rim, crystals that glint), `chaos_void_flicker` (violet dark, a flickering edge, bands that drop out), `chaos_holy_radiance` (a breathing gold light, slow rays, a bright rim), `chaos_blood_pulse` (a heartbeat floods it red and lights veins), `chaos_spectral_ghost` (pale and see-through, a cold rim, rising waves). Vertex stage `chaos_outfit_vertex.frag`, fragments `chaos_outfit_*.frag`; they keep the outfit's four colours (the template layer) and lay their noise out in sprite pixels. Compile-checked (`tools/check_shaders.py`); `chaos_ember_glow`, `chaos_void_flicker` and `chaos_blood_pulse` were seen worn in the Linux client (below). The monster modifiers in `monster_tiers.lua` pick one of them per monster, and the monster bar lists the modifier names under the bar. Untested; it relies on the base client's `g_shaders.createOutfitShader(name, vertex, fragment)`, which exists in the base client's `game_shaders`. The season pass premium track adds two more written for this server, `chaos_ash_drift` (Ash Drift, id 25) and `chaos_cinder_crown` (Cinder Crown, id 26), `chaos_outfit_ash_drift.frag` / `chaos_outfit_cinder_crown.frag` on `chaos_outfit_vertex.frag` (server/README.md "Season pass"; `outfitshaderlist_test.lua` checks them against `seasonpass_config.lua`).

Pixent fix: `shine122.frag`, `pixent_green.frag` and `pixent_blue.frag` (server shaders 15-17: Explosive, Venomous, Swift, and the store shaders 15 and 17) called `smoothstep(.001,.001,metal)`. Equal edges are undefined in GLSL; Mesa llvmpipe (the software-rendered test client) turned them into a coloured checker grid over the whole sprite. They now use `step(.001,metal)`, the hard threshold the equal edges meant. Checked in the test client with 17 demons, one per shader: before, 14-17 drew as checker grids (14, Blazing, an energizer like 9-13, only while the pixent ones were on screen); after, all 17 draw the sprite with their colour and sparkles under llvmpipe for several minutes, the same as Mesa softpipe, which drew all of them right even before the fix. A GPU driver usually reads equal edges as a step, so the Windows client may not have shown it.

In the world a tiered monster's name is coloured by tier and its modifiers are drawn on a line above the name (`Creature:setTitle` and `setInformationColor` of the base client engine); on the bar the modifiers sit under the bar.

## Outfit shaders in the Outfit window (new)
`game_chaosshaders/outfitshaderlist.lua` (`OutfitShaderList`, pure logic; `outfitshaderlist_test.lua`) is the logic of the Shader row that base patch `0045` adds to the base Outfit window (`game_outfit`, BASE.md 27; ROADMAP 86). The server's outfit window packet lists the shaders the character owns as {shaders.xml id, name}; `entries` keeps the valid ones (no repeats, at most 255) sorted by a display name: the store's names (`shop_config.lua`, by id), the exclusives' and the Chaos shaders' (`exclusives_config.lua`, `cosmetics_config.lua`), else the name made readable. `rows` gives "None" plus the owned ones (filtered by the search box), `outgoing` the name the set-outfit packet carries: an owned one or "" (the server refuses the whole outfit change for a shader the character does not own, so a worn shader that left the list is dropped), `text` the row's label. The test checks every label against those three server files and that every labelled name is registered by `chaosshaders.lua`. Tested in the Linux client against a live server with src-patch 0036: no shader owned, the row is greyed; four owned (Blood Pulse, Ember Glow, Heartblood, Void Flicker), the list shows them with previews, a pick previews and is worn after Ok (server `lookShader` 19), and both survive a relog.

## Chaos spells in the client (new)
`game_chaosspells` adds the 77 Chaos spells to the spell list, action bar, hotkeys and cooldown display (`SpellInfo.Default`, `SpellIcons`, `SpelllistSettings.Default.spellOrder`). The data (`spelldata.lua`) is generated from `server/data/spells/chaos/spells_chaos.xml` by `tools/gen_spell_data.py` (CI fails if it is out of date). All three spell icon sheets (`overlay/data/images/game/spells/spell-icons-32x32.png`, `-22x24.png`, `-20x20.png`, 20 columns, 300 cells: 15 rows) are our own generated art and replace the base client's sheets when `tools/assemble_client.sh` copies the overlay: `tools/gen_all_spell_icons.py --spells-lua <client>/modules/gamelib/spells.lua --out-dir overlay/data/images/game/spells` draws every cell the client's `SpellIcons` table names from the spell's words (element from flam/frigo/vis/tera/mort/san/pox/kor/ico/..., kind from exori/exevo hur/lux/mas/exura/exana/utani/utamo/utevo/ad... runes, tier from infir/min, gran, max), the 77 Chaos spells at cells 201 to 277 (the Thief line's nine at 237-245, Berserker and Beastmaster at 246-249, the Necromancer line The snares (Snare Trap, Seeker Mine, Detonate Mines) and the four vigils of the second round of build archetypes (2026-10-12) are icon cells 282-288 (`client/tools/gen_spell_icons.py`, the sheets regenerated with `gen_all_spell_icons.py`; only those cells changed).
at 250-258, the Monk line at 259-268, the Templar line at 269-277, the Illusionist's two heals at 278-279, Town Portal at 280, the Thief line's Shadow Mend at 281) with the drawings of `tools/gen_spell_icons.py`, and a neutral filler in every unused cell, so no base icon is left. Rerun it after changing `gen_spell_icons.py` or the order of `spells_chaos.xml`. Spells are matched by icon key and words, not by display name. Untested in a client; it assumes the client reads `SpellInfo`/`SpellIcons` when the windows open.

## Helper rotation (new, `game_helperrotation`, `game_chaosspells/spellfix.lua`, base patch 0052)

`game_helperrotation` (`rotation.lua`, global `ChaosHelperRotation`, not sandboxed; `rotation_test.lua`) is the helper's
cast bookkeeping: a cast waits for the server's cooldown packet, a refused one backs off 2-16 s, a group is held about two
round trips while its cast waits, nothing goes out while a cast-time spell charges (`CAST_MS`, checked by the test against
the server scripts), level / mana / server-has-it checks, the self-area monster count. The test also runs the shooter's
loop against a server model: the old helper stuck on a refused spell (480 refusals, the spells below it never cast), the
new one 9 tries and every spell on its cooldown, also at 400 ms and after a 2.5 s stall.
`game_chaosspells/spellfix.lua` (`ChaosSpellFix`; `spellfix_test.lua`) lines the client's stock spell entries up with the
installed server: ten entries had other ids than the server and four stock spells the server does not have held the ids
of Chaos spells (238 Shadow Veil, 244 Iaijutsu, 245 Bushido Focus, 248 Wild Bond), so cooldowns went to the wrong spell
and a helper rule could resolve to the wrong words; the six ascension spells follow the server's new ids below 256
(`server/tools/patch_spell_ids.py`); mana, level, groups, target, range and vocation ids where they differ; rune groups.
The 42 stock entries of spells the server does not have keep their entry but are marked `notOnServer` and moved to id +
1000; the spells the server removed (`ChaosRemovedSpells`, the conjure spells) keep entry and id (the rune cooldown icons
use them), are marked `notOnServer` and leave the spell list (`hideRemovedSpells`) and the helper's lists. The helper's
own id lists (`spelldata.json`) are remapped to the server ids, and vigils (toggles), Town Portal and Flickerdash are not
offered to the helper. Base patch 0052 (`BASE.md`) uses both.

## Spellbook (new)
`game_spellbook` opens on Character > Spellbook (or Character > Spellbook in the top menu, which asks the server with `open`). Left: search box (name or words), a filter ("My vocation" / "All spells") and the spell list (icon, name in the element colour, words, level in red when it is above yours). Right: icon, name, words, level, magic level, mana, soul, cooldown (group cooldown in the tooltip), group, type, element, target, what it scales with, vocations (initials, full names in the tooltip), premium, the description and the area of effect drawn as a grid (hit cells in the element colour, your tile gold, the target outlined white; single-target spells show you and the target, self spells only you; cells shrink to fit areas up to 21 x 21). Icons come from `Spells.getSpellIcon(words)` of gamelib; runes show their rune item. Names, descriptions and areas come from the server (`server/data/scripts/chaos/spellbook.lua`), so the client keeps no spell data of its own. Not run in a client: the layout sizes, the theme styles in this window and the combo box popup were checked by reading only.

## Short numbers (new)
Every number the client shows is short: 1000 -> 1k, 15300 -> 15.3k, 2450000 -> 2.45M, 1200000000 -> 1.2B (three significant digits, trailing zeros dropped, rounded down so 999999 is 999k, below 1000 as it is, negatives keep the sign). `client_chaos_numbers` (not sandboxed, autoload-priority 10, so it loads before gamelib and every game module) defines the globals `formatShortNumber(n)`, `formatExactNumber(n)` (15,300, for tooltips), `shortNumbersIn(text)` (shortens standalone integers inside a text, `1,234,567` and `1.234.567` included, and leaves times, dates and years, coordinates, ids, `#123`, numbers glued to letters, decimals and the loot markup `{id:value|...}` alone) and `shortNumbersInMessage(mode, text)` (only the look, damage, healing, experience, status, loot, NPC trade, mana and potion message modes; chat, private, NPC talk, login and broadcasts stay as they are). `numbers_test.lua` (luajit and lua5.3, CI step "Client unit tests") checks the rule against an integer reference and the text cases. The numbers above the map use the same rule in C++ (base patch 0018).

Used by base patch `0019-short-numbers.patch` (health/mana in healthinfo and topbar, the skills window, inventory capacity and soul, on-screen and console server messages, NPC trade balance and list prices, market/store/forge/prey/cyclopedia/soulseal/task balances, the analysers, highscores) and by the overlay modules bank, shop, infinity tower, dungeons, battle pass, stash, craft skills, passive tree and spellbook. Exact values are kept in tooltips where a widget can show one, and everywhere the player types or confirms an amount (bank deposit/withdraw/transfer dialogs, NPC trade price of the selected item, market offers and create-offer totals, store offer prices, shop buy confirmation, analyser clipboard exports). Not run in a client.

## Ornate UI skin (new)
The whole interface is redrawn as iron, gold trim, blood-red and arcane-blue gems instead of flat recoloured stone. All art is procedural, made by `tools/gen_skin.py`: tileable noise materials, a height map with lighting for bevels, plus rivets, gold filigree and gems. Regenerate it with `python3 client/tools/gen_skin.py --base <assembled base client dir>`. The groups are `frames controls stock hud ornaments`, and only `stock` needs `--base`. Run `gen_ui_reskin.py` first if you use it. `gen_skin.py` takes every file it draws off `RESKIN_FILES.txt`, so the recolour tool never overwrites them. `gen_theme_art.py` no longer draws the chaos/ frames by default.
- **Windows**: `data/styles/10-windows.otui` (copied from the patched base, then edited) points `Window` at `chaos/skin/window` (borders 12/32) and keeps the stock paddings. `NewWindow` keeps the redrawn `ui/popupwindow`. `Window`, `NewWindow` and `ChaosWindow` set `&chaosOrnate`. For those, `client_chaos_theme` adds gold corner pieces and a crest as phantom children, one frame after creation, so `prev` anchors and child indexes are untouched. It also centres the title on the title plate and paints it gold, because many base windows move it for the old 17 px bar.
- **Buttons**: `data/styles/10-buttons.otui` points `Button` at `chaos/skin/button`: border 5, normal/hover with an ember glow/pressed/disabled. `ui/buttons`, `ui/button`, the tab sheets, `ui/menubox` (popup menus), `ui/textedit`, the inner panel frames, the map frame, `ui/window` (mini windows), the item, inventory and action bar slots (stock silhouettes kept) and the top bars are redrawn in place, at the same size and layout. Scroll bars, check boxes, the mini window buttons, combo boxes, the console sheet, `common_buttons/*` and the arrows are "relit". Their layout comes from the stock image, and their pixels are remapped to iron/bronze/gold. Mini window titles are gold (`data/styles/30-miniwindow.otui`). Tooltips are a dark gold-rimmed plate (`client_chaos_theme` wraps `g_tooltip.display*`).
- **Top menu bar**: `client_chaos_topbar` uses the skin button and a framed bar (`chaos/skin/menubar`). The stock top strip of `client_topmenu` (Join Discord link, console, DAT Offset Studio, options and exit icons) is kept hidden on the login screen and in game; its buttons are entries of the menu instead. On the login screen the bar shows only the entries marked `offline` (System: Options, Join Discord, Console, DAT Offset Studio, Exit). In game, Unjustified Points (Hunt) was added, since its stock button sat on the hidden bars. Weapon Proficiency and the stock Blessings window have no entry: the server sends no proficiency data and does not answer the base blessings request on 10.98, so both windows stay empty. The invite link is `ChaosTopBar.COMMUNITY_URL` in `chaos_topbar.lua` (empty for now: the entry then says the link is not available yet). Icons `topbutton_community/console/exit/proficiency/pvp` come from `tools/gen_theme_art.py icons`.
- **HUD**: new module `game_chaoshud` puts a character plate in the game root panel, over the top-left of the map. It shows the outfit portrait in a gold ring, a level badge, the name, health and mana bars with short numbers and an experience line. `hudmath.lua` is tested by `hud_test.lua`.
- **Character list**: base patch `0021-chaos-skin-character-list.patch` changes the hard-coded grey row colours to the palette.
- **Fixes found while testing**: `game_chaosspells` connected an `onGameStart` handler that returned `true`, and `signalcall` stops at that, so every handler after it (passive tree, dungeons, bank, top menu hiding, ...) never ran. It is wrapped now. With those handlers running, two missing assets showed up: `game_dungeons/challenge.otui` used a font the client does not have (now `Verdana Bold-13px`), and `images/animations/button-highlight-22x22`, which the base proficiency window wants, is now generated.
Checked in the Linux client at 1280x800: login, character list, game screen, skills, options, spellbook, shop, daily reward, passive tree, the popup menu and tooltips. No errors in the log.

Checked in a live client after base patch 0043, 2026-10-13, at 1280x720: Market, Bestiary, Achievements, Leaderboards, Guild Siege and Pets each opened once through its toggle and showed the server's data. No `Extended opcode` error and no stray part warning in the log. The first run showed only an empty Market: the server dropped every request. Fixed on the server, server/README.md "Extended opcode dispatch".

## Login screen (new, `client_chaos_login`, `tools/gen_login_art.py`)
No base patch: the module restyles the stock `client_background` and `client_entergame` widgets at runtime, so every function of the stock login (remember account and password, auto login, server list, recordings, error boxes, 2FA token field, character list afterwards) is unchanged.
- **Composition**: the team's login artwork (`tools/art_src/login_reference.webp`: gothic cathedral city over lava, the "Cinders of Chaos" logo in its thorn frame) fills the window, and the real widgets sit where the artwork painted its mock interface. Splash: "PRESS ANY KEY TO START" on a dark translucent bar with thin gold-iron edges (serif lettering as an image, `presskey.png` + `presskey_text.png`: the client's font atlas has no room for another font; a translated text shows as a label instead), the server status under it with a spinner while it is checking. Panel state: the framed sign-in panel at the bottom centre, its top crest under the logo's lower spike, with a rune medallion at each end. Inside the panel: ACCOUNT and PASSWORD fields (and the narrow TOKEN field), remember account / remember password / auto login, SIGN IN and CREATE ACCOUNT, OPTIONS, CREDITS and EXIT GAME, and the forgot-password link; the new buttons call the stock functions (`EnterGame.doLogin`, the options window, `g_app.exit`). Corners: server drop-down, recordings button and server status (top left), `Version` (top right). The stock event schedule, boosted and cast panels go under the sign-in panel when they fit (1920x1080), else beside it (schedule and boosted bottom left, casts bottom right above the corner mark), else (4:3 at 1024x768) they are hidden.
- **Generator mark**: the artwork has a small four-pointed sparkle in its bottom right corner, the visible mark of the image generator that made it. It is kept as it is: the generator copies those pixels back unchanged after cleaning, no widget is placed on it and `login.lua` does not draw embers, ash or sparks over it (`MARK_BOX`).
- **Press any key to start**: on the first login screen of a run the panel is hidden; any key or a click on the background reveals the panel with a short fade. It is skipped when auto login is on with a saved account, and never shown again after a logout. `EnterGame.show` is wrapped, so the error boxes and logout still bring the panel back.
- **Background and logo**: `data/images/title.png` is 1920x1536: the artwork upscaled to a 1920x1072 band at row 232, with a darkened, blurred mirror of its edges above and below, so every window from 16:9 to 5:4 shows the full width without stretching (wider windows crop rows, keeping the bottom; narrower ones crop the sides). The logo stays painted in the picture; `chaos/logo.png` (the logo cut out of the artwork) is placed exactly on it, so it is never drawn twice, and carries the animation: `chaos/login/logo_hot.png` (the hottest parts of the letters) breathes over it and 12 sparks (`spark.png`) rise off the tops of CINDERS and CHAOS. Also: `chaos/login/glow.png` (lava and lit windows, same frame as `title.png`) flickers, 22 rising embers and 10 falling ash flakes; all on one timer at 20 per second that does nothing while the login screen is hidden. Positions are artwork pixels mapped through the crop (`LOGO_BOX`, `PRESS_BOX`, `STATUS_Y`, `SPIN_*`, `PANEL_Y` in `login.lua`).
- **Generator**: `python3 -I client/tools/gen_login_art.py [bg] [ui] [logo] [brand]` (Pillow, numpy, scipy and `opencv-contrib-python-headless`; deterministic for given library versions). `bg` cleans the artwork of its mock interface and writes `title.png` and `glow.png`: the bar's darkening is divided out (per column and colour channel) to bring back the stairs under it, its lettering is covered by a gradient-domain copy of the stairs above, CONNECTING... and the spinner are filled by FSR inpainting (OpenCV xphoto), the LOGIN button, the top right icon and the bottom right LOGIN + crosshair icon are replaced by gradient-domain copies (seamlessClone) of the rock and stonework next to them; upscale: Lanczos + light unsharp mask. `logo` writes `chaos/logo.png` (1168x740, 2x), `logo_small.png`, `ui/logo.png` and `chaos/login/logo_hot.png`: alpha from a hand-traced outline of the thorn frame (`LOGO_LEFT` / `LOGO_RIGHT`) snapped to the picture by a guided filter, plus the flames and sparks outside it keyed by heat, background colour removed from the soft edges. `brand` writes `docs/brand/` (the logo on transparency, on black, and a 1024x1024 icon). `ui` writes the panel, crest, medallions, button and field sheets, press-key bar and lettering, spinner, ember, spark and ash. The website (`website/tools/gen_site_art.py`) and README banner (`docs/tools/gen_readme_art.py`) take the logo from here.
- **Not covered**: the custom server host box of the stock window (only shown when `ALLOW_CUSTOM_SERVERS` is on) is not laid out; the invalid-email warning is hidden because accounts are names. `Services.createAccount` and `Services.recoveryPassword` (init.lua) are empty, so both links show a short note instead of opening a page.

## Login scene (new, `client_chaos_login`: `loginscene_core.lua`, `loginscene.lua`)
The login background can be a piece of our own world instead of the artwork: a ruined courtyard in the ash wastes
("The Cinder Ossuary") built from game tiles, with our own monsters walking in it. Lua and OTUI only, no base patch.
- **Tiles**: the dark tile set (client ids 27484-27557, "Dark tile set"): obsidian floor with magma veins, ash and
  bone earth with their border pieces, a moss bed and a wet rock shelf, a cursed pool, a road of ruined flagstones up to
  a wall of dark, ruined and obsidian wall pieces along the top; torches at the wall's foot, braziers and pillars along
  the road, dead trees, outcrops, glowcaps, blood crystals, bones and rubble. Each is a `UIItem` whose item gets a map
  position, so the 4x4 seamless ground patterns tile as on the map; things bigger than a tile are drawn up and left
  of their tile, as on the map. Tiles are 32 px times a whole factor (about 11 rows: 64 px at 720p, 96 px at 1080p).
- **Monsters** (`UICreature`): Death Mage with two Risen Skeletons, Dark Sorcerer, Bone Golem, Lich Shade, Gloomfire,
  Dreamgorger, Grindmaw the Mauler (server/data/monster/monsters/chaos). They are at the sides, never behind the logo
  or the sign-in panel (their whole footprint, two tiles for the big ones), and never on the outer columns or the
  bottom row, which hang over the window's edges. They and their patrols are placed before the small scattered things
  (bones, rubble, bushes, glowcaps), so those keep off the patrols; all nine get a place at 1024x768 to 1920x1080.
- **Patrols**: most monsters walk. `layout` gives each one a patrol where it fits: 2 to 4 tiles back and forth along
  its row (or 2 to 3 along its column), or a small loop of 3x2 tiles, with a pause of 1.5 to 5 s at each end (at one
  corner of a loop). Two passes: first every monster takes its shortest patrol (where it is crowded one tile out and
  back), then each grows to the longest that still fits. A monster with no room at all stands and turns now and then
  (at 1280x720 all nine walk, at 1920x1080 eight, at 1024x768 six). Every tile a patrol may cover (the big
  ones' 2x2 footprint at each node) is taken for it, so monsters never meet, never cross an object, the pool, the
  wall rows, the logo or the panel area, and stay in the scene. Steps are one straight tile, timed like the client's
  `Creature::getStepDuration` for a monster on 10.98: 1000 x ground speed (the dat's, from `dark_tiles.csv`) / speed,
  rounded up to the 50 ms server beat, with a stroll speed per monster (110-190; their hunting speeds of 49-800 would
  crawl or race). `newWalker(path)` turns a patrol into position (fractional while stepping), facing and
  stepping/standing for a time, and the tile it is on (while stepping, the one it steps to, as on the map);
  `loginscene.lua` moves the widgets on a 25 ms timer of its own (only the walkers, only while the scene shows), faces
  the walk direction, shows the walking frames while stepping and the idle frames while standing (the floating ones
  always drift), starts them at staggered times, and the name tag follows its monster. A walker that reaches a new
  tile moves in the widget order to where a thing on that tile draws (by row, then column), so it passes in front of
  and behind its neighbours as on the map. The frames are the outfit's own walking frames at the `UICreature` frame
  rate (`UI_CREATURE_TICKS_PER_FRAME`); a widget has no step-synced walk phase as a creature on the map has.
  A creature's widget is two tiles square ending on its own tile: `DrawQueue::correctOutfit` maps two tiles onto the
  rect, so they draw at the map's scale.
- **Layout** (`loginscene_core.lua`, no client API): `layout(cols, rows, seed, keep)` decides every ground, border
  piece (the sample scene's rule of `gen_dark_tiles.py`: a piece is named by where its family's ground lies), object,
  light and creature, in drawing order; deterministic (a Park-Miller generator, the same in LuaJIT and Lua 5.3), so
  a resize to the same grid gives the same picture. Tests: `loginscene_core_test.lua` (CI).
- **Mood**: warm light pools flicker over torches, braziers and magma, violet and teal ones over the glowcaps; a
  vignette darkens the edges and a dark pool sits behind the logo so its flames read over the tiles; the embers, ash,
  logo sparks, splash bar and sign-in panel stay as they are. Art: `tools/gen_login_art.py scene`
  (`data/images/chaos/login/scene_*.png`, radial falloffs drawn in code).
- **Captions** in the bordered Chaos fonts ("OFL fonts"): the place name bottom right in `chaos-display-16px`, and every
  six seconds one monster's name fades in over it in `chaos-outline-11px`.
- **Setting**: `chaosLoginBackground` (g_settings): `scene` (default), `art` (the artwork of "Login screen", kept as
  the fallback) or `alternate` (scene and artwork crossfade every 40 s, 2.5 s fades). The link "Background: ..." in
  the top right corner cycles it. Without the dat/spr pair the artwork shows: the scene loads the pair at start the
  way `client_entergame` does at sign in (client version 1098 first, so the 10.98 features apply); sign in then finds
  it loaded.
- Checked in the Linux client (Mesa software GL) at 1280x720 and 1920x1080: splash and panel over the scene, the art
  setting, the switch to alternate and its fade to the artwork; screenshots outside the repository. Patrols checked at
  1280x720, 1920x1080 and 1024x768 (2026-10-13): every walker moved, no script errors, drawing order right as they
  pass each other.

## Character select (new, `client_chaos_charselect`, base patch 0050)
The stock character list (a restyled table, base patch 0021) is replaced on screen by a full-screen character
select over the login scene; the stock module stays loaded and keeps every function. Lua and OTUI only.
- **How it hooks in.** `charselect.lua` wraps `CharacterList.show / hide / isVisible / destroy /
  rebuildCharactersList`: when the stock window opens before the game it is hidden and the new screen shows (input
  lock on it); in the game (switching characters) the stock window shows as before; the setting
  `chaosCharSelect = stock` keeps the stock window everywhere. The cards follow the stock list's rows (its sort and
  pins); choosing a card focuses that row, so Play is the stock `CharacterList.doLogin()`. Back is the stock Cancel
  (`CharacterList.hide(true)`), auto reconnect is `CharacterList.toggleAutoReconnect()`, the account status line is
  read from the stock window, "Show hidden characters" is shown on and greyed as in the stock window (10.98 sends no
  hidden flag), "Record session" is the same setting. Login queue, error boxes and the waiting window are the stock
  ones. A scripted or launcher login that skipped "press any key" no longer leaves the splash's CONNECTING line over
  the list (`ChaosLogin.endSplash` in `client_chaos_login/login.lua`).
- **Cards.** Class badge (`tools/gen_charselect_art.py`: the website's class badges at 40 px), name, class and
  ascension ("Juggernaut (Warrior)"), level, world, last login ("Last played 2 hours ago", from the website), season
  tag. Mouse: click chooses, double-click plays, the wheel scrolls. Keys: Up / Down / Left / Right, Home / End,
  Page Up / Page Down choose, Enter plays, Escape goes back.
- **The chosen character** stands large on a stone dais, its body centred on the dais and standing on the centre of
  its top face (a flying one hovering over it), walks in place for a moment when chosen, then idles; a click on it
  turns it. Name, class and level, world, season and last login under the dais.
- **Platform (2026-10-13, owner: first the orange pedestal made the character look odd, then the character stood at
  the wrong angle on the grey dais that replaced it).** That dais was a flat ellipse with a front wall, seen from a low
  camera; the sprites use the game's own projection, so the figure looked pasted on at the dais's back edge. Now
  `platform.png` (41x41 sprite pixels, `gen_charselect_art.py`, our own art) is drawn in that projection, as the
  pair's stock blocks and stairs are: the ground seen straight from above, so the top face is a true octagon (not a
  squashed one); height drawn down and right at 45 degrees, one pixel per pixel of height; the light from the upper
  left (lit top and left edges, a lighter lip, the wall facing right lighter than the one facing down); the game's
  dithered checker shadow along the lower right base and a few checker pixels under the feet. It is a two-step
  octagonal dais, both steps centred on the feet point, each one pixel thick, dark cool grey, a faint ground shadow one
  pixel all around it, in three sizes: `platform.png` 41x41, `platform_l.png` 49x49 and `platform_xl.png` 57x57
  (lower step 19, 23 and 27 pixels from the centre). Centred dais (2026-10-13, owner: "still misaligned"; the
  characters were right, the art was not): the first octagon had its top step 2 pixels up and left of its lower step,
  2-pixel walls and a 2-pixel shadow down and right, so its whole silhouette's centre sat 3.5 sprite pixels down and
  right of the feet point (14 px at 4x) and every character read up and left of the dais. Now the steps share one
  centre (an equal rim on every side, seen from above) and the silhouette, shadow included, fills the canvas with its
  centre within half a pixel of the feet point (the one-pixel wall); `gen_charselect_art.py` `check_core` refuses
  art that breaks this, and `charselect_core_test.lua` checks `PLATFORMS` against the image sizes. `CharSelectCore.platformFor`
  picks the smallest one the body's reach fits with at most 3 pixels over its edge (`OVERHANG`): a wide body gets a
  wider dais, the character is never shrunk (`CharSelectCore.PLATFORMS`; the generator refuses to write art that does
  not match).
  The client draws it at the character's own scale (T / 32: 2x, 3x, 4x) with `image-smooth: false`, so its pixels
  are the sprites' pixels (`platformRect`). Seen from above it reaches as far below the feet as above them, so the
  name lines start under it (`platformBelow`) and the Create character preview panel is 240x300. Three designs in
  this projection were compared on five characters (a round slab, a flat rune slab one pixel thick, the octagonal
  dais); `python3 -I client/tools/gen_charselect_art.py platforms DIR` writes all three outside the repo. The
  octagon's 45 degree sides run along its 45 degree walls, as the stock blocks do.
- **No tall auras in the preview (owner: the red crystal behind Varek).** The tall red spike was the character's aura
  from the website (1512, Crimson Blaze). `CharSelectCore.previewOutfit` keeps an aura only when it is small and sits
  at the feet (`smallAura`: at most 30 sprite pixels above its ground row, that row at least 8 pixels down): 932, 934 and
  1487 are kept; 712, 933, 935, 936, 1511-1529 and 2136-2139 are left out. Wings always show. The game itself still
  draws every aura.
- **Flying characters.** A floating look (a robe or a wraith tail, no feet: the Lich 2059, the robed wizard 2077,
  the Bone Lord wraiths 2167 / 2168 and the Necromancer ascension's robes 2183 / 2184; the table's flag) hovers
  `CharSelectCore.HOVER` (5) sprite pixels over the top face. A winged character flies too: the engine
  (`GameWingOffset`, on) draws its body 6 sprite pixels up and left of its wings, and bobs it 0 to 4 more while it
  animates; `CharSelectCore.figure` takes the left shift back (the body stays centred) and keeps the lift as its hover.
  Under a flying character a soft dark shadow (`hover_shadow.png`, 22x8 sprite pixels, dithered rim) lies on the top
  face (`shadowRect`).
- **Slots line.** The header reads "3 characters, 3 of 5 slots used". The limit is the website's
  `chaos_character_limit`: the pact's free slots (`characters.free`, 5) plus bought `charSlots` and
  `charSlotsLegacy`. An account with as many characters as slots or more (characters inserted by hand) reads
  "10 characters, no free slot", never more used than the total (`slotsText`); the Create character window then says
  where more slots are sold (`slotsLine`).
- **Where a character stands (fixed 2026-10-13, twice: owner, first "off-centre", then "still displaced, the flying
  one most").** `UICreature` draws a creature at its tile's top left and maps the square (-32, -32)..(32, 32) of those
  pixels onto its rect, so where a body lands depends on its art and displacement (a 1x1 look in its own tile, our 2x2
  class looks in the middle of their 64 px frame). Our sprites are oblique: the body leans up and left with its height,
  and its lowest pixel is often a cape tip, a weapon or a trailing robe, not the feet. So the anchor is what the eye
  reads. `client/tools/sprites/gen_outfit_anchors.py` reads the pair and writes `outfit_anchors.lua`, per creature
  thing (outfits, wings, auras) from the first south frame with every addon: the body's centre (the alpha-weighted
  centroid of its solid pixels: an opening of the mask leaves out what it holds, a blade, a staff, a torch, up to four
  pixels wide, and only the biggest connected part is kept, so the leaves at a staff's end fall away), its ground row
  (where the lowest 12% of its solid mass begins, the legs' columns only: a cape tip or a weapon under the feet does
  not count), the visible bounds, the size in tiles, the floating flag (`FLOATING`, chosen by eye) and the body's
  reach (how far it spreads either side of its centre, for the dais size). `gen_outfit_anchors_test.py` (CI) checks
  the measuring on synthetic figures: a cape tip, thin and thick staffs, a leafy staff, a leaning body, a robe.
  The CI job `live-pair` runs the tool with `--check` against `windows-assets`; regenerate it with every new pair (a
  look missing from it falls back to its size and displacement). `CharSelectCore.figure` adds the wings and the aura
  (a big aura moved by `(w - 1) * 16, (h - 1) * 16`, as `GameBigAurasCenter` draws it) to the bounds, `fitPreview`
  picks 4x when the whole picture fits under the top menu, else 3x, else 3x lower, and `placeRect` puts the body's
  centre on the dais centre and its ground row on the top face, or HOVER above it (the create window: 3x, 2x for a
  look too wide for its panel). Measured in the Linux client at 1280x720 and 1920x1080 by diffing frames with and
  without the body on a plain background: the 42 class looks of `class_looks_core.lua` and the ten test characters
  have their drawn centre and ground row on the target exactly (one sprite pixel for a character whose own addons
  differ from the all-addon frame); checked by eye on 2x close crops of all of them. The turned directions use the
  south anchor. Nudge left (2026-10-13, owner: "the characters are still off the platform; just move them left"):
  `CharSelectCore.NUDGE_X` (sprite pixels, negative is left) moves every character off the dais centre; its default
  is -2. Three horizontal anchors were compared live on the ten test characters and the 42 class looks: the full
  figure's box (body, weapons, shields and addons; never wings or aura), a 50/50 blend with the body centroid, and
  the body centroid nudged 2 left. The box and the blend moved most looks right, not left (2.6 and 1.3 sprite pixels
  on average: staffs and weapons held out to the sides; the Illusionist 11), so the centroid with the nudge is the
  default. `gen_outfit_anchors.py --centre body|bbox|blend` writes the other two (default `body`; the dais size
  keeps using the body's own reach).
- **No text through the dialogs.** While the select shows, the login screen's logo and its server status line
  ("Connecting..." / "Server online") are hidden; a dark veil covers the select behind the Create character window, so
  the hero's world line no longer shows beside it.
- **Outfit, and the "generic outfit" seen before.** The 10.98 character list of our login server carries each
  character's look type, colours and addons (base patch 0025 reads them; the stock list drew them). What looked
  generic was the data: characters made on the website kept ZnoteX's starter outfit (look 128 / 136, the same
  colours for everyone) until their first login put the class look on, and the test characters had been inserted
  with one look for all. Fixed at the cause on the website: a new character gets its class's look with both addons at
  creation (website/README.md "Client API"). The list cannot carry wings, aura and shader (the base server keeps them
  in `players.wings_id` / `aura_id` / `shader_id`); the character select adds them from the website's account API
  (`accountapi.lua`, one HTTPS login per character select, then a token), so a changed login packet was not needed.
  `CharSelectCore.mergeOutfit`: the list's look type, colours and addons win, the website adds wings, aura, shader.
- **World name.** A card shows the world name the login server sends only when it is a name of the client's own
  `Servers` config; anything else (a test server whose `config.lua` still has its base data's `serverName`) shows the
  chosen server's name instead. Production sets `serverName` with `server/tools/prod_config.py` (docs/LAUNCH.md).
- **Create character** (`charcreate.lua`): name with the website's rules as a hint (letters and spaces, 3-20, up to
  3 words, no one-letter word), the seven classes as badges (Monk, Necromancer and Templar greyed with "locked for
  this account" unless the account unlocked them), Male / Female with a walking preview of the class look in the
  starter colours, the season (none, or a mode of the running season; Hardcore needs "I understand"), the slots
  used. The website checks everything again with the website form's own code; its errors show in the window. After
  a creation the character list is read again from the login server and the new character is chosen. Without
  `Services.account` the button is off with a tooltip pointing to the website.
- **Credentials.** The account name and password the stock client already holds in memory for the login (`G.account`,
  `G.password`) go to the website once per character select, over HTTPS; the token it answers lives in memory only
  and is ended on the site when the select goes back to the login screen. Nothing new is written to the settings.
- **Theme fix found here.** A `ChaosComboBox` never opened its list: `UIComboBox` creates the style
  `<style>PopupMenu` and `UIPopupMenu` `<that>Button`, and `client_chaos_theme/styles.otui` had neither
  ("'ChaosComboBoxPopupMenu' is not a defined style"; the loot filter's and ground labels' combo boxes had the same
  problem). The four styles (`ChaosComboBoxPopupMenu`, `...PopupMenuButton`, `...PopupScrollMenu`,
  `...PopupScrollMenuButton`) are now in the theme.
- **Tests.** `charselect_core_test.lua` (LuaJIT and Lua 5.3, CI): classes against `chaos_constants.lua`, icons, card
  text, last login, world names, outfit merge, navigation, the dais rects, sizes and reach below the centre, `fitsAt`, the hover shadow, the aura filter, the
  slots text, the wing lift and hover, a floating look, a cape-tip look, the placement maths (every thing of the
  anchor table at 3x and 4x, 1x1 and 2x2 looks, wings and auras, the scale choice, the fallback, every class look
  present, every look within its dais), name hints, requests, error texts, URLs. `gen_outfit_anchors_test.py` for the
  anchor measuring.
  `website/tests/chaos_client_api_test.php` for the site's side. Run in the Linux client (base patches 0001-0045,
  0048-0050, Xvfb, software OpenGL) at 1280x720 and 1920x1080 against a local test server (a test build of the
  engine with the current Chaos scripts; the login server's 10.98 list) and the local site (pinned ZnoteX with every patch, PHP's built-in server, MariaDB):
  the cards and the large character with wings and aura from the site, arrow keys / Home / click choosing the stock
  row, Escape and Back to the login screen (logo back), a logout returning to the select; Create character: the
  locked Monk and Templar, the Necromancer unlocked, the female preview, the season list, Hardcore refused without
  "I understand", a taken name and a sixth character refused by the site, then a Hardcore Self-Found Necromancer
  created, the list read again with it chosen (class look, [S1]), and at its first login the server joined it to the
  season with that mode (`chaos_season_players`, `chaos_season_modes`, the request row gone).

## Paragon panel (new)
`game_passivetree` has a Paragon button next to Apply Plan / Reset. It opens a `ChaosWindow` (ornate skin: `ChaosPanelDark` per category, `ChaosButton` +/-, Apply / Reset / Close) inside the tree window, built from the server's `paragonState` (`paragon.lua`, `paragon.otui`): points available / spent / total, four categories with two stats each (points / max, value / cap, tooltips with the per-point value), shift-click for 5 points, Apply sends the absolute allocation (`paragonApply`), Reset asks first (level x 250 gold, `paragonReset`). Below level 1000 it shows "Unlocks at level 1000". The "Info & Bonuses" list gets a Paragon section. The +/- maths are in `paragonmath.lua` (tested by `paragonmath_test.lua`); the server validates everything (server/README.md "Paragon"). Checked in the Linux client at 1280x800.

## Classes (base patch 0016, `game_chaosspells`, `game_passivetree`, `game_spellbook`)
The class rework (docs/CLASSES.md) is in the client: `0016-chaos-vocation-ids.patch` maps the server's class byte (base slot + 10 / + 20
for the two ascended classes: 1/11/21 Warrior / Juggernaut / Berserker, 2/12/22 Ranger / Deadeye / Beastmaster, 3/13/23 Mystic /
Elementalist / Illusionist, 6/16/26 Thief / Ninja / Samurai) to the server's vocation ids, which the modules use; it names the classes
(`g_game.getVocationName`, `VocationNames`, `translateVocationName`), sorts them for item / market / wheel lookups and
`Creature:isKnight/isPaladin/isSorcerer/isDruid`, and gives the helper its classes (1 Warrior line, 2 Ranger line, 3 Mystic /
Elementalist, 4 Illusionist with the druid's heals, 6 Thief line). The C++ part needs a rebuild.
Classes five to seven (phase B: tested in game with this client, level 300 rotations measured, ROADMAP C5-C7 and
docs/CLASSES.md; behind the store's class unlock): the class-byte table is `[3][10]` and reads
slots 7, 8 and 9: 7/17/27 Necromancer / Lich / Bone Lord (20 / 21 / 22), 8/18/28 Monk / Shadowfist / Iron Sage (17 / 18 / 19),
9/19/29 Templar / Inquisitor / Sentinel (23 / 24 / 25). Names in every name map, `translateVocation` returns their own ids (their
spell lists name them), the Necromancer line wears the casters' items (market 1, dat profession 3), `Creature:isNecromancer`,
`isChaosMonk` (not `isMonk`, which switches on the newer-protocol monk features) and `isTemplar`, helper classes 7 / 8 / 9.
`game_chaosspells` also gives the Necromancer line the casters' stock healing and support instants (as the server does, no rune
conjuring, no stock summon). A client binary built before this 0016 passes the three classes' bytes through unmapped (7 reads
as the Deadeye, 8 as the Juggernaut, the others as no class), so the names are wrong until it is rebuilt. `game_chaosspells` also lists the
Mystic / Illusionist / Berserker / Beastmaster on the client's stock spell entries the server gave them (and restores them on unload),
`game_passivetree` falls back to the class key before the server names it, and the spellbook shows one-word class names with three
letters (Ber, Bea) so the classes stay apart. Checked in the Linux client: the class byte 21 reads as 14 "Berserker" (base "Warrior",
`isKnight` true), the migration popup, the free switch, Wild Bond's companion, the spellbook.

## Dark tile set (new, `tools/sprites/gen_dark_tiles.py`, `tools/sprites/darklib.py`)
74 environment things of our own, drawn in code (periodic noise, Voronoi cells, height maps lit from the upper left; no sprite of any client is read): 9 grounds with 4x4 seamless patterns (one animated, the cursed pool), 48 border pieces (edges, outer and inner corners of obsidian, ash soil, wet rock and dark moss), 3 walls (2x2 patterns) and 14 objects (2x2 trees and rock outcrop, 1x2 pillar, brazier and torch, 1x1 pieces). Client ids 27484-27557, appended after the last stock item; server ids are +3000 (server/README.md "Dark tile set").
- Drawing: every tile at 128 px, then a detail pass: cavity shading and lit rims on the grounds' height maps, and on objects a soft volume light from the silhouette, a bright rim on the edge facing the light, a core shadow on the far edge and a small gloss (matte for rubble and bones). Downsampled (premultiplied box average, light sharpening, hard alpha) to the 64 px masters and the 32 px sprites. The braziers, torches, magma floor, glowcaps, crystals and the pool carry the dat light flag.
- `tools/sprites/dark_tiles/`: `masters/*.png` (64 px, one sheet per thing: patterns as laid out in the world, animation phases side by side, for a future 64 px spr), `contact_32.jpg`, `contact_64.jpg`, `scene_32.png` (a sample area over plain green).
- Run: `python3 -I gen_dark_tiles.py --ours-dat Tibia.dat --ours-spr Tibia.spr --out-dir OUT --masters dark_tiles/masters --sheets dark_tiles --manifest-out ../../../server/data/items/dark_tiles.csv --lua-out ../../../server/data/lib/chaos_dark_tiles.lua`. Order in the rebuild chain: merge_outfits.py -> gen_effects.py -> set_multiuse.py -> gen_dark_tiles.py. The input must have 27483 items (or be an earlier output: the set is rebuilt in place and the pair comes out identical). Deterministic; the output is re-read and checked pixel by pixel; outfits, effects, missiles and stock items are copied byte for byte.
- Checked in the Linux client at normal size and with HD upscaling (xBRZ x2) in a rift, the world boss arena and the ascension trial room.

## Donor art libraries (new, `tools/sprites/import_donor_things.py`)
Two donor clients were converted into separate 10.98 library pairs (not in git, too big): donor B (the 64px-style
donor: 31,330 things, 535,781 sprites, 0.86 GB spr) and donor C (29,006 things, 274,559 sprites, 0.55 GB spr), each
with `catalogue.csv` (library id, source id, size, frames, flags, short description, sprite hash) and contact sheets
with the library ids. Only things whose art is not already in our pair are kept (pixel compare), exact duplicates and
empty entries are dropped. `import_donor_things.py import` appends chosen library ids to a live pair (verified: old
entries byte-identical, new ones pixel-identical to the library).
More libraries (October 2026, same layout, outside git; each deduped against our pair and every earlier library,
by decoded sprite pixels; pass the earlier sprs with `--known-spr`, `--key-cache` keeps their pixel keys):

| library | source format (`--source`) | outfits | items | effects | missiles | sprites | spr |
|---|---|---|---|---|---|---|---|
| donor D | 10.98, RGB spr re-encoded with alpha (`v1098`) | 1,255 | 20,098 | 351 | 76 | 427,376 | 493 MB |
| donor E | 7.72 art-only dat, no flags (`v772`); every row "library only: commercial server art" | 992 | 30,430 | 340 | 146 | 250,007 | 328 MB |
| donor F | 10.98 + extra bytes 39/41 (`v1098 --extra-flags`) | 457 | 5,846 | 266 | 23 | 103,147 | 146 MB |
| donor G | 10.98, own signature (`v1098`) | 675 | 3,746 | 199 | 17 | 67,334 | 104 MB |
| donor H | 7.72 with frame groups and animators (`v772`) | 253 | 6,122 | 65 | 35 | 53,298 | 89 MB |
| donor I | 8.60, no frame groups (`v860`): wings, auras | 297 | 14 | 28 | 0 | 20,176 | 27 MB |
| donor J | 10.10-style, no frame groups, RGB spr (`v1098`); its dark walls and lava grounds kept with `--include` | 372 | 6,682 | 111 | 38 | 46,307 | 81 MB |
| donor K | 8.60 with frame groups (`v860`), monster names in the catalogue (`--names`) | 88 | 250 | 106 | 45 | 8,261 | 10 MB |
| donor M | scrambled 8.x flag bytes (`donor-m`: only light and displacement kept), RGB spr | 361 | 5,035 | 116 | 34 | 50,069 | 83 MB |
| donor N | 15.11 protobuf appearances + LZMA sprite sheets (`v1511`, 64 px sprites cut into tiles) | 13 | 156 | 0 | 0 | 6,426 | 8 MB |
| donor O | newer build of donor G: only what G lacks | 0 | 29 | 0 | 0 | 28 | 0.06 MB |
| donor Q | 10.98 native dat, byte 40 read as displacement where the outfit has none (`--map-flags`); retail-style rows tagged "library only: retail-style art" | 495 | 2,077 | 508 | 107 | 181,398 | 287 MB |
| donor R | 10.98, XOR'd dat, RGB spr (`v1098`); 4,217 rows "library only: retail-style art" | 233 | 3,997 | 45 | 28 | 55,514 | 70 MB |
| donor S | 10.98 (`v1098`); 447 rows "library only: retail-style art" | 56 | 751 | 23 | 11 | 26,326 | 42 MB |
| donor T | 15.x protobuf appearances + LZMA sheets (`v1511`): only the donor's extra (custom) appearances file, its main set is the retail set and was skipped; 34 rows "do not use live: branded" (the donor's coin, logo, name and people), 101 rows "library only: retail-style art" | 38 | 210 | 0 | 0 | 32,992 | 28 MB |
| donor U | 8.60 extended dat with frame groups and durations (`v860`), alpha spr; 18 rows "do not use live: branded", 16 rows "named character (do not use live)", 201 rows "library only: retail-style art" | 325 | 257 | 148 | 9 | 84,703 | 88 MB |
| donor V | 10.98 (`v1098`), 1.14 GB source spr; 11 rows "named character (do not use live)", 162 rows "library only: retail-style art"; items reviewed by sheet only | 309 | 4,874 | 180 | 43 | 89,559 | 143 MB |

Donors T, U and V (October 12, 2026) are built but not yet on the library branch. U and V were read from the zips
without storing the whole source spr: the spr was streamed twice into a compact copy that holds only the things with
art not yet in our pair or an earlier library; things whose art was all known are listed in `skipped.csv` as "already
in ours or an earlier library (compact spr)". The fourth client of that batch added no usable art (its 264 new
sprites belong to no thing; its art is already library R). The tag ranges are in each library's `build.log`.
Most useful for our gaps (library ids):
- **T**: outfits 9-11 (a horned scorpion beast in three colours: rift or boss creature), 28-29 (a crystal nexus,
  blue and red: battleground or siege objective), 30 (a blue drake), 33-38 (glowing ground runes in six colours:
  marker or aura); items 121-123, 135, 155-158, 160, 163 (stone walls and pillars with gold or iron trim), 169-170
  (wall torches with embers), 176 (an animated lightning floor), 184 (an ember training dummy), 237 (an orb with
  light), 258-275 (animated red and blue crystal clusters and flame spires, crystal braziers 274-275).
- **U**: wings 8, 18, 23, 36, 37, 39, 40, 47, 50, 57 (dark, bat, bone and demonic); auras 41, 42, 58-60, 64, 65,
  73, 81; big beasts 85-95 (fire, void, shadow and demon beasts: mounts or rift bosses); bosses 96-98 (a fire
  swarm, a blood colossus, a blood tentacle), 231 (a void eye), 267-268 (horned beasts, blue and red), 298;
  effects 23 (smoke vortex), 24 (a demon burst), 81-84 (big sealed orbs: shields or wards), 86, 92-93, 105, 109
  (arcane vortices), 126-128 (dark thorn rings), 136-137 (lightning strikes), 139 (a red slash), 146 (a meteor);
  missiles 2, 3, 5 (crescent and spear bolts).
- **V**: bosses and creatures 1 (a winged gold demon), 58, 59, 62, 63 (void and ice golems), 74, 76-78, 80-83
  (fire demons and hellhounds), 101, 121, 122, 141-145 (void spiders and wraiths), 153, 155, 203, 207 (a burning
  skull beast); 241, 243, 246 (crystal drakes, six colours 241-247); 277-281 (armoured beasts in five glow
  colours: faction mounts); 283, 284, 287 (bone dragons, six colours 283-288); effects 17-18 (void portals), 20,
  23 (dark planets), 46-48 (fire claws), 57, 59, 60 and 98, 100, 101 (rune and blood rings), 83 (a fire tornado),
  106-145 (footprints in many colours and shapes), 155, 165, 167, 170; items 3553-3554 (blood pentagrams), 3190,
  3194 (sigil floors), 3598 (a cage), 4210, 4215 (chains), 3115, 3133, 3164 (void and blood grounds and walls)
  and the corrupted void biome 4600-4971 (grounds, crystals, vines, glowing shrines 4912-4923).

Older layouts are converted: outfits without frame groups get an idle group (phase 0, the old standing frame) and a
walking group (the walk frames), or one walking group when they animate always; animated groups without animator data
get the old client's timing (items 500 ms, effects 75 ms once, missiles 100 ms, walking 300 ms). Flags are mapped by
name; flags our table lacks (7.72 floor change, 15.x corpse, cyclopedia, ...) are listed in the `stripped` column.
Rows tagged "named character (do not use live)" are characters of other franchises (donors D, F, G, J, K, U, V);
rows tagged "do not use live: branded" carry another server's name or logo (donors T, U); donor E,
named characters, branded and "retail-style" rows are library only. `donor_b_selection.csv` is the recommended first
live set (32 outfits incl. Golden Dragon and Scaleborn looks and class outfits, 24 effects, 16 missiles, 112 items),
run with `--first-item 28000` after `gen_dark_tiles.py`; it writes `donor_items.csv`, which goes to
`server/data/items/donor_items.csv` for `server/tools/install_donor_items.py` (install_all step `donoritems`).
Donor B centres big creatures with negative displacements; the 1098 profile enables `GameNegativeOffset`
(base-patches/0006) for that. Catalogue rows tagged "named character" (donor C) are recognisable characters of other
works: library only, never live. Not checked in the test client yet.

## Class looks pair (things_custom10, new)
The 21 class looks (male and female, `server/data/scripts/chaos/class_looks_core.lua`) on top of things_custom9_fx (dat
9cd3c674..., spr 3271f987...: things_custom8 plus fist weapons and bone effects). Picks, sources and edits per look:
`tools/outfit_art/class_looks_sources.csv` (licence tracing; boards in `tools/outfit_art/out/survey/final_<line>_*.png`,
made by `tools/outfit_art/survey.py final`). The generated Warrior-line art (`tools/outfit_art/build.py`) is not in it.

    python3 -I tools/sprites/import_outfits.py --src-dat L/donorJ/Tibia.dat --src-spr L/donorJ/Tibia.spr \
        --ours-dat things_custom9_fx/Tibia.dat --ours-spr things_custom9_fx/Tibia.spr --looks 125,126,63,64,20,18 --expect-first 2039 --out-dir j
    ... donorD --looks 981,982,1037,1038,182,183,531,532,1015,1016,999,1000 --expect-first 2045 (on j) --out-dir d
    ... donorF --looks 11,12,224 --expect-first 2057 (on d) --out-dir f
    ... donorH --looks 133,134,135,136,70,225,226,176,177 --expect-first 2060 (on f) --out-dir h
    python3 -I tools/outfit_art/add_template.py --ours-dat h/Tibia.dat --ours-spr h/Tibia.spr --looks 1505,1506,1508,1510 \
        --expect-first 2069 --out-dir things_custom10

(L = the donor library folder.) Each step verifies its output (old entries byte-identical, new sprite slots
pixel-identical, 3000 sampled old sprites unchanged). `add_template.py` copies one-layer outfits as new look types with a
colour template: the outfit's accent colour (the commonest saturated hue) becomes grey in the art and is marked head /
body / legs / feet by its place along the figure. Result: dat 646583fa5a406e774466bf090221c929, spr
531461f7ab57ecc2f9ad9a33da7cb281, 2072 outfits. Server side: `server/tools/install_outfits.py` writes the class looks
block of outfits.xml (type 1 male, type 0 female, locked); the store leaves out class looks and the former stock class
looks (`L.retired`). Checked in game: the test characters got and wore their class look at their first login.

**things_custom10b** (the live candidate; things_custom10 plus 9 looks, ids of 10 kept): no class look may be stock art
of the commercial game. Warrior, Ranger and Monk used free stock looks (1455-1458, 1464, 1465), and a silhouette and
shading compare against every stock 10.98 outfit (IoU of the standing south frame and the luminance correlation in
the overlap) showed that donor F 11/12 (Berserker, 2057/2058) are stock look types 255/264 recoloured and donor J 20
(Inquisitor, 2043) is stock 145 with a skull mask. Replacements, appended on top of things_custom10:

    python3 -I tools/sprites/import_outfits.py --src-dat L/donorD/... --ours-dat things_custom10/... --looks 1033,1034,245,246,1118 --expect-first 2073 --out-dir d
    python3 -I tools/sprites/import_outfits.py --src-dat L/donorH/... --ours-dat d/... --looks 65,66,86,95 --expect-first 2078 --out-dir things_custom10b

Result: dat 7ba1d4794c09c7d76dc943ff23e60a78, spr ade7204ff0c9393d6aa4836507515c0d, 2081 outfits. 2043, 2057 and 2058
stay in the pair unused (removing them would move every later id). The compare only knows the 10.98 stock art: a donor
look ported from a later version of the commercial game would pass it.

## New class look art (`tools/outfit_art/class_art.py`, `class_art_line.py`; not in any pair yet)
Owner-approved new art for the class look slots with no usable donor art: Lich female (today 2059 for both sexes),
Inquisitor female (today 2077 for both), a matched Necromancer pair (today 2044 / 2064, two unrelated outfits), and
alternatives for the Thief, the Ninja and the Templar, both sexes. Ten looks in all. Our own art: the outfit rig of
the Warrior line (signed-distance parts on a posed body, our palette, the shape is the art). No donor, stock or AI
pixels. The PixelLab repaint step of the art studio is not used: no token in this environment.
- Each look: 2 addons that carry the class identity, as the client draws them (an addon pattern holds only the pixels
  that change when the addon is worn). Lich: bone-iron crown with void gems; phylactery and gold trim. Inquisitor:
  censer on a chain; pointed hood with a gold seal (the base carries an upright holy mace). Necromancer: bone staff
  with a skull head; skull mantle and collar (hooded base; hers shows ash-grey locks). Thief: hood and face scarf;
  second dagger and a knife bandolier. Ninja: face mask and crimson headband; crimson scarf (black cowl base).
  Templar: great helm with a cross visor and gold crest; kite shield with a holy cross (the base holds the sword up).
- Layout (`import_art_things.py` keys): 2x2 tiles, displacement 8,8 (the stock player place), 2 layers (art + colour
  template: head hair / hood / cowl, body robe / tunic / tabard, legs trousers / skirt, feet boots), 4 directions,
  3 addon patterns, 2 mount patterns (on foot, riding). `--layout 2+4` (default): idle 2 phases (a 1 px breath,
  600 ms), walking 4 phases; `--layout 1+8` gives the stock player layout.
- Edges: a 2x2 outfit cannot draw past its frame's right or bottom edge. Weapons held low on the weapon side and a
  long stride cross it in some directions, so weapons are held up and the stride is shorter than the Warrior line's
  (7 degrees). `class_art.py edges` checks every pose, direction and addon: 0 of 1,920 overflow.
- Test: `class_art_test.py` (designs, addon diff, the sheet read back by the importer's own layout code for both
  layouts, quick renders with template colours only, deterministic, an import round trip on a tiny pair). CI runs it.

```
python3 -I client/tools/outfit_art/class_art.py look [KEY ...] --out-dir OUT     # standing, 4 directions, addons
python3 -I client/tools/outfit_art/class_art.py edges [KEY ...]                  # overflow check, no drawing
python3 -I client/tools/outfit_art/class_art.py build [KEY ...] --out-dir OUT    # sheets, things.csv, previews (~30 min)
python3 -I client/tools/sprites/import_art_things.py --ours-dat P19/Tibia.dat --ours-spr P19/Tibia.spr --out-dir NEW \
    --things OUT/things.csv --first-outfit 2173 --expect-items N
```
Planned ids (after pair 19, outfits 2161-2172): 2173 Lich F, 2174 Inquisitor F, 2175 / 2176 Necromancer M / F, 2177 /
2178 Thief M / F, 2179 / 2180 Ninja M / F, 2181 / 2182 Templar M / F. Not imported, not in `class_looks_core.lua`.
Superseded: after review the owner asked for donor art for these slots instead ("Class looks pair 20"; 2173-2184 are
now donor looks). The tools stay.

## Spell icons from the element icon sets (new)
The three spell icon sheets now use pixel-art ability icons (six element sets of 40, 32x32 with an element-coloured
frame, owned by the project) instead of the generated drawings in 259 of the 280 cells: the 79 Chaos spells (cells
201..279, one icon per spell chosen by element and role, `tools/spell_icon_art/chaos_spell_icons.csv`) and the 180 cells
the client's `SpellIcons` table names (stock spells and runes, picked by element and kind from the icon tags in
`tools/spell_icon_art/icon_tags.csv`, written to `stock_spell_icons.csv`; 225 different icons, a few repeat). The 22x24
and 20x20 cells are redrawn from the inner art with a crisp 1 px frame. `tools/build_spell_icon_art.py --src <icon sets>
--spells-lua <client>/modules/gamelib/spells.lua` writes `tools/spell_icon_art/spell_icons_32.png`;
`tools/gen_all_spell_icons.py` uses it for every cell it covers and keeps the generated drawings for the rest (and for
all cells with `--no-art`, which reproduces the earlier sheets exactly). Shown in the spellbook and the action bar in
game. Unused icons and the sets' other variants (transparent, locked, borders) are kept outside the repository.

## Pack items and monsters (new, `tools/sprites/import_art_things.py`, `tools/sprites/art_import/`)
Art from the October 2026 art sets (permission given by the owner), converted once to our format and stored in
`tools/sprites/art_import/`: `things.csv` (one row per thing, in id order: kind, name, atlas rectangle, size, patterns,
phases, dat flags, server id for new looks, extra data) and the atlases `icons.png`, `grounds.png`, `water.png`,
`shores.png`, `lake.png`, `trees.png` and `creatures/<key>.png`. 16 px icons were upscaled to 32 px with Scale2x (crisp,
no blur); creatures, trees, lake and shore art are 32 px grid art at their drawn size. The grounds come from dual-grid
templates: the fill tile and 12 border pieces (4 edges, 4 outer and 4 inner corners) are composed from the template's
16 corner tiles; a border piece goes on the neighbour tile like a stock border and carries the rim. Waters are 3x3
patterns with 8 synchronised frames, shore pieces 8 frames (straight pieces with 3 variants as patterns).
- 651 items (client 33000-33650) and 39 outfits (2000-2038): idle (2 phases) and walking (4 phases) frame groups,
  4 directions, base + colour mask layer (the pack's head/body/legs/feet regions), sizes 2x2 to 4x4.
- Run it last in the rebuild chain (after gen_dark_tiles.py, import_vfx.py and the donor B import):
  `python3 -I client/tools/sprites/import_art_things.py --ours-dat <pair>/Tibia.dat --ours-spr <pair>/Tibia.spr --out-dir OUT
  --first-item 33000 --first-outfit 2000 --manifest-out server/data/items/art_items.csv --outfits-out server/data/items/art_outfits.csv`.
  `--first-item` / `--first-outfit` pad with blank entries so the ids stay fixed (the run stops if the input already has
  more items or outfits). Deterministic; verified on every run: the output re-parses, every sprite slot of the new
  things is pixel-identical to the art, the padding is blank, every old entry byte-identical, 3000 old sprites unchanged.
  On the live pair of 2026-10-09 (dat d22381be..., spr 998ea340...) it gives dat 5b2e13ab5c052b7f9922c12b5ae67da9,
  spr dfaf88d98291c2a9be2f10ad541b3c41.
- Server side: server/README.md "Pack items and monsters". Checked in the Linux client at normal size.

## Store pouch looks (new, `tools/sprites/gen_pouch_art.py`, `tools/sprites/art_import/pouches.csv`)
Three item things of our own art for the store pouches, so they cannot be mixed up in a backpack (they were the stock expedition,
brocade and fur bags): client 33651 Orbs Pouch (a round violet velvet pouch, gold drawstring, a glowing cyan orb), 33652 Rift Key
Pouch (a dark iron strongbox with riveted bands, a gold key and a key ring), 33653 Loot Pouch (a tall leather sack, gold trim,
gold coins spilling). `gen_pouch_art.py` draws them at 128 px from shape fields with `darklib.py` (rim light, 1 px outline) and
downsamples them 4:1 to the 32 px atlas `art_import/pouches.png` (deterministic; no client sprite is read). `pouches.csv` rows
copy the dat flags of the stock bags (`copy:8861`, `copy:7343`, `copy:10325`: container, pickupable) and name the server ids
32082 / 32083 / 32081 (mode replace); the server points the pouch nodes at them (`clientId` in `pouches_config.lua`,
`install_pouches.py`).
- Append them as the last step of the rebuild chain, after `import_art_things.py` with `things.csv`:
  `python3 -I client/tools/sprites/import_art_things.py --ours-dat <pair>/Tibia.dat --ours-spr <pair>/Tibia.spr --out-dir OUT
  --things client/tools/sprites/art_import/pouches.csv --first-item 33651 --expect-items 33650` (`--expect-items`, new: the run
  stops unless the input has exactly 33650 items). Verified like the art import (output re-parses, the three sprites
  pixel-identical to the atlas, every old entry byte-identical, 3000 old sprites unchanged). On the live pair of 2026-10-09
  (dat 5b2e13ab..., spr of 699,745 sprites) it gives dat b243485112b7bea43016d7dd49097472, spr cfd09de9f81c8f2ffdd29db1e01fa69b
  (699,748 sprites), twice identical.
- **Windows package pair:** the package takes the merged pair from the private branch `windows-assets`
  (one archive `things/things-1098.tar.xz`, `SHA256SUMS.parts`, its README). Since 2026-10-11 that archive holds things_custom15
  (windows-assets c1441a8: the pouches, fist weapons, class looks, monster looks, the bone effects, the Cinderheart look,
  the raid boss and faction looks and the mount rider seats for client patch 0034), so servers no longer need `install_pouches.py --stock-looks`. Keep that flag only for
  clients still on an older pair: a pair without 33651-33653 shows nothing for a pouch.
- Checked in the Linux client with the new pair: in a bag next to the stock bags, in the store (Convenience), in the container
  window titles, and on the kill routing screenshots.

## Fist weapons and bone effects (new, `tools/sprites/gen_fistfx_art.py`, `art_import/fist_weapons.csv`, `art_import/fx_art.csv`)
Six item things for the Monk line's fist weapons and four things for the Necromancer line, our own art: PixelLab paintings
(Create image Pro, prompts in `tools/art_studio/prompts/items/fist-weapons.md`, `bone-spear.md`, `bone-shards.md`,
`bone-skulls.md`; 8 calls, 80 generations) picked unchanged into `tools/sprites/art_import/fistfx_src/`.
`gen_fistfx_art.py` turns them into `art_import/fist_weapons.png` (the six 32 px icons; the unique's skull gets ember eye
sockets) and the frame strips of `art_import/bone_fx/`: the bone spear missile (8 directions from one painting by
RotSprite and flips, 2 frames with a violet mote trail), `bone_spear` (impact: a violet snap and six splinters, 7 x 70 ms),
`bone_burst` (eight shards thrown out and falling, dust, a broken violet ring, 9 x 80 ms) and `bone_aura` (three skulls
and four shards rise from a violet ground ring, circle once, sink, 14 x 90 ms). Effects are 3x3 tiles sent at the target
+ (1, 1); nothing is repainted per frame (the pieces are moved, flipped and turned), alpha 0 / 255, last frame empty.
- Client ids: items 33654..33659 (charred hand wraps, ashbound cestus, ember knuckles, ossuary gauntlet, cinderforged
  talons, pyre saint's grasp; server ids +3000, `server/data/items/fist_items.csv`, `server/tools/install_fist_weapons.py`);
  effects 583..585 (bone_spear, bone_burst, bone_aura), missile 153 (bone_spear); Lua names
  `server/data/lib/chaos_vfx_art.lua`, catalogue `server/data/spells/vfx_art_catalog.csv` (both written by the import).
- Two steps, last in the rebuild chain (after the store pouch looks); `import_fx_art.py` is new (effects and missiles
  from frame strips, verified like `import_vfx.py`):
  ```
  python3 -I client/tools/sprites/gen_fistfx_art.py                      # only after changing the sources
  python3 -I client/tools/sprites/import_art_things.py --ours-dat <pair>/Tibia.dat --ours-spr <pair>/Tibia.spr --out-dir STAGE \
      --things client/tools/sprites/art_import/fist_weapons.csv --first-item 33654 --expect-items 33653 \
      --manifest-out server/data/items/fist_items.csv
  python3 -I client/tools/sprites/import_fx_art.py --ours-dat STAGE/Tibia.dat --ours-spr STAGE/Tibia.spr --out-dir OUT \
      --expect-first-effect 583 --expect-first-missile 153 \
      --lua-out server/data/lib/chaos_vfx_art.lua --catalog-out server/data/spells/vfx_art_catalog.csv
  ```
  On the live pair of 2026-10-09 (dat b243485112b7bea43016d7dd49097472, spr cfd09de9f81c8f2ffdd29db1e01fa69b, 699,748
  sprites): STAGE dat 169d841aa41243f7804cc74a474584b5, spr 92a7862ccb45e83aabce07fadf33d76a (699,754 sprites); OUT (the
  test pair `things_custom9_fx`) dat 9cd3c674f57427fd3afe1c3cc481e599, spr 3271f98791957e4a5802b64f353ea474 (699,924
  sprites), twice identical. Both runs check their input (`--expect-*`), so on a pair with more items, effects or
  missiles (e.g. after the class outfit import, which only adds outfits and keeps these ids) the ids must be re-planned.
- Checked in the Linux client (assembled fresh, this pair): the six icons in the inventory and a backpack (the unique in
  its rarity frame), look texts, a Monk fighting with the ossuary gauntlet, the three effects and the missile cast by
  the Necromancer line.

## Monster looks pair (things_custom11, new, `tools/sprites/donor_pick.py`, `tools/sprites/monster_looks/`)
26 creature outfits for the rift-exclusive looks and the monsters that had no art, all donor-library creatures (owner
rule: donated sprites first; no new art was needed): 2100-2115 the four rift families (minion, brute, elite, guardian of
Abyssal Rift, Obsidian Hall, Ashen Crypt, Forsaken Sanctum), 2116-2118 the Omen guardians, 2119-2125 Saga, Gloomfire,
Jadefen Badger, Dawn Strayer, Plant, Tarrasque, Cunning Hyaena. Picks: `tools/sprites/monster_looks/picks.csv`; licence
tracing: `monster_looks/sources.csv`. Server side: server/README.md "Rifts" (looks) and
`server/data/monster/CUSTOM_MONSTERS.md`.
- `donor_pick.py` (new) cuts the picks from the libraries into one small pair in pick order, three of them recoloured
  (rule `green>ember`: green glows turn ember orange, alpha kept). It checks every sprite slot against the donor (the
  recolour recomputed), that no pick is already in the live pair (same art, shifted or not), and that no pick has the
  silhouette of a stock outfit 1..1465 (mean IoU of the four idle masks >= 0.9 stops the run). That check found four
  first picks that were recoloured stock creatures; they were replaced. Libraries C, D, H and J were surveyed but not used:
  much of their art is older stock art. Donor B, named-character and library-only rows were skipped.
- `import_outfits.py` got `--first-outfit N`: blank outfits pad the list so the first new id is N on any smaller input
  pair. The ids stay 2100-2125 whatever class looks come before (the blank entries are verified blank).

      python3 -I client/tools/sprites/donor_pick.py --picks client/tools/sprites/monster_looks/picks.csv --lib-dir L \
          --out-dir MINI --base-dat things_custom10b/Tibia.dat --base-spr things_custom10b/Tibia.spr
      python3 -I client/tools/sprites/import_outfits.py --src-dat MINI/Tibia.dat --src-spr MINI/Tibia.spr \
          --ours-dat things_custom10b/Tibia.dat --ours-spr things_custom10b/Tibia.spr \
          --looks 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26 --first-outfit 2100 --out-dir things_custom11

  (L = the donor library folder, md5s as on the sprite-libraries branch.) MINI: dat 59f9ff75b7ac65066dda1a2f49e595dc, spr
  2cda2c434b98a14e3b46d4a7d422401f (26 outfits, 3,936 sprites). Input things_custom10b (things_custom10 + class looks
  2073-2081): dat 7ba1d4794c09c7d76dc943ff23e60a78, spr ade7204ff0c9393d6aa4836507515c0d. Output **things_custom11**:
  dat 74aa990f1ed43d6ac30812001c8662c9, spr c2223fe12f35f3532536db1339de8523, 2125 outfits (2082-2099 blank), 719,970
  sprites; built twice with identical md5s. Verified by the importer: 7,396 sprite slots and 780 frames of the 26
  outfits pixel-identical to MINI, flags and animators equal, the 2081 old outfits and every item, effect and missile
  byte-identical, 3000 sampled old sprites unchanged. Only outfits were added: no corpse items.
- CI: `tools/ci/check_content.py` takes its outfit limit (MAX_OUTFIT) from the highest `look` in `picks.csv` (at least
  2081, the end of things_custom10b). It is 2125 now, so new picks raise it without an edit there. A monster file with
  a lookType above it fails unless it is listed in `needs_sprites.txt` (checked: 2126 is flagged, 2125 passes).
  things_custom12 ("Necromancer line effects" below) was the live pair (windows-assets 4975d74); it only adds effects, so it also has 2125
  outfits. things_custom13 ("The Cinderheart look" below) followed at windows-assets 0810c26; things_custom14
  ("Raid boss and faction looks" below) followed at windows-assets 7777e70; the live pair is now things_custom15 ("Rider seat
  on donor mounts" below, windows-assets c1441a8).
- Checked in the Linux client on a test server: each world and omen monster spawned, and one tier 8 rift of each
  theme with its packs and its guardian (screenshots and boards in the session scratchpad `monsters/`).

## Necromancer line effects (new, `tools/sprites/gen_necro_fx.py`, `art_import/necro_fx.csv`)
Seven effects in the owner-approved Necromancer style sample, our own art: the bone spear's impact and the Bone Lord's
bone effects (golem rise, banner, minion rally, offering burst, bone ward) are shapes drawn in Python and repainted by
one PixelLab "Edit images (Pro)" call over one 512x384 sheet of all their frames (`art_import/necro_fx_src/sheet_shape.png`
-> `sheet_paint.png`, seed 4102 of two calls; 50 generations, balance 1835 -> 1785); `lich_soul_drain` is the style
sample's own effect (`soul_drain_paint.png`, its shape and call scripts kept next to it). The effects already in the pair
and the donor libraries were surveyed first (server/data/spells/README_FX.md "Necromancer line effects": the choice
per spell); only these had no fitting donor. No pixel of the owner's style reference sheets is used.
- Client ids on things_custom12: effects 586..592 (necro_spear_hit, lich_soul_drain, bonelord_golem_rise,
  bonelord_banner, bonelord_rally, bonelord_offering, bonelord_ward); 2x2 effects send at the target (offset 0,0), the
  rally is 1x1. No missile (the bone spear missile 153 is kept). Lua names and catalogue rows are merged into
  `server/data/lib/chaos_vfx_art.lua` / `server/data/spells/vfx_art_catalog.csv`.
- A separate, re-runnable step (its own spec) after the fist weapons and bone effects and the monster looks import; it only
  appends effects, so it runs on any pair with 585 effects (`--expect-first-effect 586` stops it otherwise):
  ```
  python3 -I client/tools/sprites/gen_necro_fx.py build        # strips from the checked-in shape + painting (deterministic)
  python3 -I client/tools/sprites/import_fx_art.py --ours-dat things_custom11/Tibia.dat --ours-spr things_custom11/Tibia.spr \
      --out-dir things_custom12 --spec client/tools/sprites/art_import/necro_fx.csv --expect-first-effect 586 \
      --lua-out server/data/lib/chaos_vfx_art.lua --catalog-out server/data/spells/vfx_art_catalog.csv --merge
  ```
  `--merge` (new in `import_fx_art.py`) keeps the bone effects' entries in the Lua and catalogue files and replaces only
  this spec's ones; re-running gives the same files. (`gen_necro_fx.py shapes` / `paint` remake the sheet and repaint it;
  only needed to change the art.)
- Input things_custom11 (things_custom10b + outfits 2100-2125): dat 74aa990f1ed43d6ac30812001c8662c9, spr
  c2223fe12f35f3532536db1339de8523 (719,970 sprites). Output **things_custom12** (live pair until windows-assets 0810c26; was 4975d74): dat
  4712f7484d391e66c04b7ecf72c940e7, spr dc92483b0744a6389151d8c7b85d9342 (720,098 sprites), twice identical. The same
  step on things_custom10b (dat 7ba1d479..., spr ade7204f...) gives the test pair things_custom10b_fx: dat
  fc9a9adbfac0845e34ebe1b2b6117f8e, spr 11a82c220f271f0cd4400cb93d7b857b (716,162 sprites).
- Checked in the Linux client with things_custom12 on a test server: every spell of the line cast at a target dummy
  (Necromancer, Lich, Bone Lord at level 300); the new effects show on the target or caster tile, the pack effects at
  their offsets, the Soul Rot ticks each second.

## The Cinderheart look (things_custom13, outfit 2126, `tools/sprites/monster_looks/`)
One more donor-library creature for the final Ascended boss, Ysgrath the Cinderheart (server/README.md "Ascended Omens
and the Cinderheart"): donor F outfit 200, a cloaked sovereign wreathed in cinders (5x5, idle and walk, 8 phases;
picks.csv row 27 `cinderheart`, sources.csv row 2126). Library surveyed first: the flame demon G31 is Gloomfire's art
(donor F 53, already 2120); F200 is new, passes the stock silhouette check (below 0.7) and is not in the live pair.
Same two tools, ids planned in the reserved 2126-2130:
```
python3 -I client/tools/sprites/donor_pick.py --picks client/tools/sprites/monster_looks/picks.csv --lib-dir L \
    --out-dir MINI27 --base-dat things_custom10b/Tibia.dat --base-spr things_custom10b/Tibia.spr
python3 -I client/tools/sprites/import_outfits.py --src-dat MINI27/Tibia.dat --src-spr MINI27/Tibia.spr \
    --ours-dat things_custom12/Tibia.dat --ours-spr things_custom12/Tibia.spr --looks 27 --first-outfit 2126 \
    --out-dir things_custom13
```
MINI27 (the 26 picks above + this one): dat e7799591df952ef2c77d9dc753dad85e, spr cace9d9cb091960ce75119313ca6ff7b
(4,395 sprites). Input things_custom12 (dat 4712f7484d391e66c04b7ecf72c940e7, spr dc92483b0744a6389151d8c7b85d9342).
Output **things_custom13**: dat 945753ee2f4661865a4705896fb4958b, spr 41566d56528cf123446cfffa86d16e6a, 2126 outfits,
720,569 sprites (471 appended), built twice with identical md5s. Verified by the importer: 1,600 sprite slots and 64
frames pixel-identical to the donor, the 2125 old outfits and every item, effect and missile byte-identical, 3000
sampled old sprites unchanged. Checked in the Linux client with this pair on a test server (the boss spawned, walking,
in its arena). things_custom13 was the live pair on the `windows-assets` branch (0810c26, replacing things_custom12; replaced by things_custom14 at 7777e70); a pair without
outfit 2126 draws nothing for the Cinderheart. CI: `check_content.py` reads 2126 from
picks.csv, so the monster file passes.

## Raid boss and faction looks (things_custom14, outfits 2127-2139, `tools/sprites/monster_looks/`)
Thirteen more donor-library outfits, ids in the reserved 2127-2160: the five Ashen Sepulchre bosses (they wore unused stock
looks 1281, 354, 863, 1369, 1445), and an exclusive mount and aura for each faction (they were store mounts and auras).
Libraries surveyed first (F, G, I, K, M, B; R and S are retail-style, library only): the rift-creature libraries F and G
have no rideable quadruped that passes the stock silhouette check (their three-headed hounds 513-516 are stock 240
recoloured, IoU 0.97; the war mammoths 73-77 are standing beast-men), so the mounts are donor B mount art (the library
of the live Bone Steed 1561); the auras are donor I aura outfits (two-layer rings, back / front). Rows of picks.csv
(`sources.csv` has the licence tracing):

| look | key | use | donor | edit |
|---|---|---|---|---|
| 2127 | raid_ulthar | Gravewarden Ulthar | G 671 (4x4, hooded black plate warden) | none |
| 2128 | raid_morwen | Morwen the Ash-Sister | F 292 (4x4, hooded robed sister) | green>ember |
| 2129 | raid_colossus | The Marrow Colossus | G 495 (3x3, many-legged bone colossus) | green>ember |
| 2130 | raid_hexmaw | Vhoss the Hexmaw | F 395 (2x2, coiled violet maw) | none |
| 2131 | raid_sovereign | Varkhul the Ashen Sovereign | F 257 (4x4, ash-grey winged sovereign) | none |
| 2132 | mount_vigil | mount 142 Pyrewarden Charger (Ashen Vigil) | B 1935 (barded warhorse) | none |
| 2133 | mount_compact | mount 143 Forgeborn Emberwolf (Cinderforge Compact) | B 1943 (molten wolf, light) | none |
| 2134 | mount_choir | mount 144 Veilrunner (Veiled Choir) | B 3941 (rift steed, light) | none |
| 2135 | mount_circle | mount 145 Thornbound Stag (Thornbound Circle) | B 4081 (great stag) | none |
| 2136 | aura_vigil | aura 25 Pyrelight Mantle | I 152 (gold sparks, gold ribbon) | aura-feet |
| 2137 | aura_compact | aura 26 Forgeflame Ring | I 147 (flame ring) | aura-feet |
| 2138 | aura_choir | aura 27 Veiled Eyes | I 146 (violet eyes in gold rings) | aura-feet |
| 2139 | aura_circle | aura 28 Thornfire Wreath | I 270 (green swirl) | aura-feet |

- `donor_pick.py` changes: a pick found in the base pair exactly at its own planned id is an earlier import and passes the
  in-pair check, so the base is now the live pair itself (all 40 picks checked against things_custom13: no new pick is in
  it); and no pick may be a catalogue row tagged "named character" or "library only" (new check: the first
  choice for Vhoss, G 446, is tagged and was replaced). New optional last column `edit` of picks.csv; rule `aura-feet` (flags only, no pixel changed, verified like the
  recolour): donor I placed auras for a client without `GameBigAurasCenter`, so they drew about a tile off the feet; the
  displacement is set so the centre of the art lands on the feet point (14, 20), the point `import_vfx.py` uses for our own
  auras (2136: (20, 11), 2137: (30, 24), 2138: (28, 21), 2139: (11, 3)).
- Silhouette check of the 13 new looks: below 0.7 but one (Vhoss: 0.71 against stock 720, a werebear: checked by eye,
  different art; the other bosses up to 0.46; mounts up to 0.32; auras up to 0.56); none is in the live pair. Server side: server/README.md "Factions" (aura and mount ids) and "The
  Ashen Sepulchre" (looks); `server/tools/apply_monster_looks.py` writes family `raid` rows into the boss XMLs and refuses a
  monster file with a `faction` look; `install_auras.py` reads `server/data/XML/chaos_auras_donor.csv` after
  `chaos_auras.csv`; `install_outfits.py` MOUNTS has 142..145.

```
python3 -I client/tools/sprites/donor_pick.py --picks client/tools/sprites/monster_looks/picks.csv --lib-dir L \
    --out-dir MINI40 --base-dat things_custom13/Tibia.dat --base-spr things_custom13/Tibia.spr
python3 -I client/tools/sprites/import_outfits.py --src-dat MINI40/Tibia.dat --src-spr MINI40/Tibia.spr \
    --ours-dat things_custom13/Tibia.dat --ours-spr things_custom13/Tibia.spr \
    --looks 28,29,30,31,32,33,34,35,36,37,38,39,40 --first-outfit 2127 --out-dir things_custom14
```
MINI40 (all 40 picks): dat 9c1af6a4f24f90ce2017d4fe563420cb, spr 83b5714dfc8f8c8019c47fe57954099e (7,677 sprites; 21,784
sprite slots and 1,792 frames equal to the donors, recolours and edits recomputed). Input things_custom13 (dat
945753ee2f4661865a4705896fb4958b, spr 41566d56528cf123446cfffa86d16e6a, 720,569 sprites). Output **things_custom14**: dat
1667a34964182518d2a802638288881a, spr 5aa948775e41748bd885620eeae34e62, 2139 outfits, 723,857 sprites (3,288 appended),
built twice with identical md5s. Verified by the importer: 12,788 sprite slots and 852 frames of the 13 outfits
pixel-identical to MINI40, flags and animators equal, the 2126 old outfits and every item, effect and missile
byte-identical, 3000 sampled old sprites unchanged.
- Checked in the Linux client with this pair on a test server: each boss spawned and walking (east) and turned south;
  each mount ridden (walking east, facing south and north); each aura on a character standing and walking (screenshots
  and a contact sheet kept outside the repository). The riders of the four mounts and the Bone Steed sat beside the
  saddle on this pair: fixed by base patch 0034 and things_custom15 ("Rider seat on donor mounts" below).
- The live pair stays things_custom13 until things_custom14 is pushed to `windows-assets`; a client on things_custom13
  draws nothing for 2127-2139 (raid bosses invisible, faction mounts and auras empty), so the server change and the pair
  go out together. CI: `check_content.py` reads 2139 from picks.csv.

## Rider seat on donor mounts (things_custom15 and 16, base patch 0034, `tools/sprites/set_rider_seat.py`)
The donor B mounts (Bone Steed 1561, faction mounts 2132-2135: 3x4, 3x5 and 5x4 with displacement (-32, -32), 2134
(-64, -32)) are centred on their tile with negative displacements. The client draws a negative-displacement mount by its
own displacement and the rider at its usual place (stock rider displacement (8, 8)), so the rider sat half a tile left of
the saddle and a little low (it needed 16 px right and 4-8 px up) in every direction. Stock 10.98 mounts have no displacement and
take the other path (mount and rider share the box), so they were never affected.
- Why not data only: on the negative path the rider's place does not depend on the mount's dat entry at all, and a
  non-negative displacement (the other path) moves the mount twice as far as the rider, so a displacement edit cannot
  seat the rider without moving the mount off its tile (the most it moves the rider is 8 px). Hence base patch 0034
  (client/BASE.md) plus a seat in the data.
- The seat is the dat Bones attribute of the mount (10.98 byte 39: four x, y pairs of signed 16-bit pixels, file order
  north, south, east, west). Patch 0034 moves the rider by the pair of its direction when the mount has a negative
  displacement and Bones and the rider has none. A client without 0034 ignores a mount-only Bones attribute, so the new
  pair draws exactly as things_custom14 there (checked: unpatched client + new pair = the before screenshots).
- Seats (`tools/sprites/monster_looks/rider_seats.csv`): things_custom15 had one pair for all four directions,
  (16, -8) for 1561, 2132, 2134, 2135 and (16, -4) for the wolf 2133. That was wrong in several directions; things_custom16
  below has a pair per direction.
- `set_rider_seat.py` (new) inserts the attribute before the entry's 0xFF (or replaces an existing one; a re-run on its
  output gives the same files), copies the spr, and verifies: the output re-parses with the same counts, each seated
  entry is its old bytes plus only the attribute (which decodes to the spec; sprites and displacement unchanged), all
  36,439 other entries are byte-identical, the spr is byte-identical. `datspr.py` now records each entry's flag-list
  end (`attr_end`).

```
python3 -I client/tools/sprites/set_rider_seat.py --ours-dat things_custom14/Tibia.dat --ours-spr things_custom14/Tibia.spr \
    --spec client/tools/sprites/monster_looks/rider_seats.csv --out-dir things_custom15 \
    --expect-dat-md5 1667a34964182518d2a802638288881a
```
Input things_custom14 (dat 1667a34964182518d2a802638288881a, spr 5aa948775e41748bd885620eeae34e62). Output
**things_custom15**: dat 1a5ff177c24510e28a59dea4436345fb (4,667,486 bytes, +85: 5 x 17), spr
5aa948775e41748bd885620eeae34e62 (unchanged, 723,857 sprites), 33,659 items, 2,139 outfits, 592 effects, 153 missiles;
built twice and re-run on its own output with identical md5s. `things-1098.tar.xz` built like things_custom14's
(Tibia.dat and Tibia.spr at the archive root, owner 0/0, `xz -9 -T3`): sha256
c7ff0d06dde1b7ff32b3eec1fc51b691bac8bfd72dc8b364284fab952ad36b57 (65,515,220 bytes). It went to `windows-assets` at
c1441a8 ("Windows package pair" above). The pair and patch 0034 go out together (the Windows package builds the client
with all base patches); a client with 0034 on things_custom14 draws the riders as before.
- Checked in the Linux client (base client of `windows-assets` + 0001-0034 + overlay, built fresh) on a test server
  with this pair: each faction mount and the Bone Steed ridden, standing and walking in all four directions, before
  (old client, things_custom14) and after; the rider sits on the saddle. A stock mount (368) draws pixel-identical
  with and without 0034. The outfit window preview was not checked.

### things_custom16: a seat per direction (2026-10-11)
The owner saw misaligned riders on things_custom15. Every mount was checked again: the 140 of the base mounts.xml and
our 141-145 (`server/tools/install_outfits.py` MOUNTS). The achievement, season, store and faction rewards all use
these ids. Each was drawn with rider look 128 in all four directions, standing and at walk phase 3. The renders are
offline and follow the 0001-0034 draw code (`Outfit::draw`, `ThingType::draw`). They match the in-game screenshots
of things_custom15.
- The 140 base mounts have no displacement and take the stock path. Their riders sit on the saddle in every direction.
  No change.
- All five donor mounts were off, because one pair cannot fit four directions. The rider frame's hips are at a
  different place in each direction (look 128: north (-1, 5), east (-6, 4), south (4, -6), west (5, -1) from its
  point), and the art is not symmetric. Found on things_custom15:
  - north, all five: the rider sat too high, up at the neck, and stuck out left of the spine.
  - east, all five: the rider sat on the rump and sank into the body. Worst on 2132 and 2134 (12 px low).
  - west, all five: the rider sank into the body with the torso over the neck. On the wolf 2133 it sat on the head
    and front legs.
  - south: the rider floated above the back of 1561. The others were 2 px right; 2134 was 2 px low.
- New seats (x y in pixels, + is right / down), chosen on candidate renders so the hips sit on the saddle or the back
  middle. They were also checked with looks 130 and 136:

  | look | mount | north | east | south | west |
  |---|---|---|---|---|---|
  | 1561 | 141 Bone Steed | 20 -1 | 22 -16 | 14 -4 | 14 -14 |
  | 2132 | 142 Pyrewarden Charger | 20 -8 | 25 -20 | 14 -8 | 12 -18 |
  | 2133 | 143 Forgeborn Emberwolf | 20 0 | 20 -8 | 14 -2 | 13 -8 |
  | 2134 | 144 Veilrunner | 20 -4 | 24 -20 | 14 -10 | 12 -18 |
  | 2135 | 145 Thornbound Stag | 20 -4 | 18 -15 | 14 -8 | 14 -16 |

- Data only: no engine change beyond 0034 (it already reads a pair per direction). The stock path needs no seat.

```
python3 -I client/tools/sprites/set_rider_seat.py --ours-dat things_custom15/Tibia.dat --ours-spr things_custom15/Tibia.spr \
    --spec client/tools/sprites/monster_looks/rider_seats.csv --out-dir things_custom16 \
    --expect-dat-md5 1a5ff177c24510e28a59dea4436345fb
```
Output **things_custom16**: dat fc0bd91246387611e3f5f4489023a492 (4,667,486 bytes, the same size: only the five Bones
values change), spr 5aa948775e41748bd885620eeae34e62 (unchanged). The tool's checks passed: 36,439 other entries
byte-identical, spr byte-identical. The same spec on things_custom14 (`--expect-dat-md5 1667a349...`) gives the same dat.
A re-run on its own output does too. `things-1098.tar.xz` is built like things_custom15's, mtime 2026-10-11 17:00:
sha256 5952476dde9fb93f866bb4e41ec7662490560aec777ad891806bc5a110c0e83b (65,521,896 bytes).
Live on `windows-assets` at 1cae7c3 (owner's approval, 2026-10-11). A client still on things_custom15 keeps the old
seats. No server change goes with it.
- Not checked in a live client. The before/after contact sheets of all 145 mounts are offline renders, kept outside
  the repository.

## Achievement wings (things_custom17, outfits 2140-2142, `tools/sprites/monster_looks/`)
Three donor-library wings for the achievement exclusives (server/README.md "Exclusives"). Before this pair, wings were
the only kind with no achievement exclusive. The live pair had one unused wings look, 1486, and it is the Cinderheart's
boss drop. Owner rule: donor sprites first. Donor I (8.60, the wings and auras library of the faction auras) has about
80 wings. No art was generated and no pixel was changed.

| look | key | wings | achievement | donor | frames |
|---|---|---|---|---|---|
| 2140 | wings_bloodthorn | 17 Bloodthorn Pinions | Colossus Hunter (`wb_all`) | I 286 (thorned black wings, blood-red veins, a red core) | 3x3, 8 |
| 2141 | wings_gravecrow | 18 Gravecrow Wings | Nobody Kneels (`raid_flawless`, hidden) | I 143 (grave-black raven wings, a skull mask on each) | 3x3, 9 |
| 2142 | wings_riftglass | 19 Riftglass Wings | Lord of Thresholds (`rift_100`) | I 296 (violet crystal wings that splinter and reform) | 3x3, 9 |

- Findings. Wings in the pair are one-layer outfits: 4 directions, no addons, `animateAlways`, one group (or an idle
  and a walking group), 2x2 or 3x3. The donor I picks have the same layout, so they import with no conversion. The
  first pick for the raid wings, I 295 (black smoke wings), is the store's Mortis Mirage (stock 1179) recoloured:
  silhouette IoU 1.00, and `donor_pick.py` stopped the run. I 143 replaced it. Donor I 24, 25, 133 and 136 are stock
  940 recoloured (IoU 1.00) and were not used.
- Silhouette check of the three: 0.20 (2140), 0.33 (2142), 2141 has no stock outfit of its size. None is in the live
  pair. They are not store looks or recolours of one, so no tint was needed.
- Placement. The donor I wings use the stock convention (no displacement): donor I 24 has exactly the bounding boxes of
  stock 940. The centre of each new wing over all frames, per direction, is within the range of the stock wings
  (2140 N (-6, -1), S (-6, -12); 2141 N (-6, 0), S (-2, -18); 2142 N (-7, -4), S (-7, -13); stock 940 N (-6, 12),
  1181 S (-1, -16)). So no displacement edit.
- picks.csv rows 41-43 (family `exclusive`, rank `wings`), `sources.csv` rows 2140-2142 (licence tracing).
  `server/tools/apply_monster_looks.py --check` refuses a monster file with an `exclusive` look.

```
python3 -I client/tools/sprites/donor_pick.py --picks client/tools/sprites/monster_looks/picks.csv --lib-dir L \
    --out-dir MINI43 --base-dat things_custom16/Tibia.dat --base-spr things_custom16/Tibia.spr
python3 -I client/tools/sprites/import_outfits.py --src-dat MINI43/Tibia.dat --src-spr MINI43/Tibia.spr \
    --ours-dat things_custom16/Tibia.dat --ours-spr things_custom16/Tibia.spr \
    --looks 41,42,43 --first-outfit 2140 --out-dir things_custom17
```
MINI43 (all 43 picks): dat e382de93fee39c1964770266ba6f15e4, spr fad0edab2c4c7fda2603e901b8b77c7b (8,245 sprites;
22,720 sprite slots and 1,896 frames equal to the donors, recolours and edits recomputed). Input things_custom16 (dat
fc0bd91246387611e3f5f4489023a492, spr 5aa948775e41748bd885620eeae34e62, 723,857 sprites). Output **things_custom17**:
dat 8f0dcbfe56be1a6b3f86677e497cdeaa (4,671,492 bytes), spr 6aee9a3429bdb9039787cb7eacf079c8 (587,305,926 bytes,
724,425 sprites, 568 appended), 2,142 outfits. The spr had to change: new art means new sprites. Built twice with
identical md5s. Verified by the importer: 936 sprite slots and 104 frames of the three outfits pixel-identical to
MINI43, flags and animators equal, the 2,139 old outfits and every item, effect and missile byte-identical, 3000 sampled
old sprites unchanged. The mount seats of things_custom16 are kept (old entries byte-identical).
- `things-1098.tar.xz` is built like things_custom16's (Tibia.dat and Tibia.spr at the archive root, owner 0/0, GNU tar,
  `xz -9 -T3`), mtime 2026-10-11 21:00: sha256 415763cd16249264769eba8840c31cd511b19713e50cdd0cfbcbeb0b2b04e01f
  (65,635,764 bytes). Its two files unpack to the md5s above.
- Live on `windows-assets` at 854d34c (owner's approval, 2026-10-11). A client still on things_custom16 draws nothing
  for 2140-2142: the three wings show as no wings, so the server change and the pair go out together. CI: `check_content.py` reads 2142 from picks.csv.
- Checked in the Linux client (base client + overlay, offline, data/things pointed at things_custom17): each wing on
  a Warrior and a Mystic class look in all four directions, animated, and in the wardrobe's Collection tab with the
  server's own rows (`exclusives_core.lua` `K.rows`): owned and not owned, the hidden achievement as "???". Not checked
  on a live server. The screenshots are kept outside the repository.
- The wardrobe's source line (`howLabel`) now wraps to two lines: the longer achievement lines were cut off.

## Sprite tools: outfit composer and pair checker (`tools/sprites/compose_outfit.py`, `tools/sprites/check_pair.py`)
Two tools the owner approved; the ideas come from a third-party editor, the code is our own (none of it was read).

**Outfit layer composer** (`compose_outfit.py`, specs in `tools/sprites/compose/`). Builds a new outfit (a creature
look, a wings or aura cosmetic, a mount) from layers. A layer is a thing of the live pair (`live:outfit:2140`), of a
donor library (`lib:I:outfit:286`, read from `--lib-dir`) or a PNG sheet. Per layer: offset (fixed, per direction,
or the base's rider seat), flip per direction, opacity, order front / back per direction, a glow, frame mapping
(loop, hold, repeat, still, a list; per frame group), colour mask (own, none, keep), addon and mount patterns. Roles
`wings`, `aura` and `rider` place a layer as our client draws it (wings behind facing south / east and 6 px right /
down, GameWingOffset; aura back and front layers, centred when big, GameBigAurasCenter; rider on the seat of patch 0034,
mounted pattern). Frames are anchored bottom-right like the client; each layer lands at (output displacement - layer
displacement + offset). Content past the tile's right / bottom edge lowers the output displacement (`"auto"`).
- Mask rules: the base's mask is kept; an uncoloured front layer clears the mask where it covers (alpha >= 128); a
  layer can bring its own mask; addon patterns are cut where a front layer covers, since the client draws them over
  pattern 0. The glow is only on pixels the layer leaves empty, within 1-3 px, in one `gen_effects.py` palette ramp
  with its crisp "glow" alpha levels and an ordered dither (no faint wash). It never touches the mask.
- Output: `<key>.png` in the `import_art_things.py` outfit layout and `<key>.csv`, a things.csv row (`--csv-out`
  collects rows). `--preview` draws every group, mount and addon pattern, phase and direction on one contact sheet,
  with a tinted row when there is a mask and the creature's tile outlined.
- `import_art_things.py` now reads more outfit layouts (all optional, old rows give the same bytes: checked on the 39
  outfits of `things.csv`): phases per group (`8`, `1+8`), extra keys `gtypes`, `layers`, `addons`, `mounts`,
  `exact`, `durs<g>`, `anim<g>`, outfit flags (`displacement` may be negative, `bones` = byte 39), atlas paths relative
  to the things file.
- Examples (`compose/`): `warrior_bloodthorn` (Warrior 2073 with wings 2140, ember glow; 3x3, displacement -12 -14),
  `mystic_pyrelight` (Mystic 2060 in aura 2136; 3x3, -12 -21), `charger_rider` (Warrior 2073 riding the Pyrewarden
  Charger 2132 as one look; 3x4, -32 -32, seat dropped). Built from things_custom17 and imported into a copy of it
  (`--first-outfit 2161`: 3 outfits, 1,613 sprites appended, importer and guard checks passed); not in the live pair.
- Tests: `compose_outfit_test.py` (synthetic things: offsets, size growth, auto displacement, order per direction,
  wings role, flip, opacity, frame mapping, masks, addon cut, rider seat, glow bounds and colours, spec validation, a
  PNG round trip, an import round trip on a tiny pair). CI installs `python3-numpy python3-pil` for it.

```
python3 -I client/tools/sprites/compose_outfit.py client/tools/sprites/compose/*.json --validate
python3 -I client/tools/sprites/compose_outfit.py client/tools/sprites/compose/warrior_bloodthorn.json \
    --ours-dat P/Tibia.dat --ours-spr P/Tibia.spr [--lib-dir L] --out-dir OUT --preview [--csv-out OUT/things.csv]
python3 -I client/tools/sprites/import_art_things.py --ours-dat P/Tibia.dat --ours-spr P/Tibia.spr --out-dir NEW \
    --things OUT/things.csv --first-outfit N --expect-items 33659
```

**Pair checker** (`check_pair.py`, pure Python, no numpy). Parses the dat with the client's own 10.98 rules (not
`datspr.py`), so a byte read differently shows up. Errors: header counts the client cannot load, truncated entries,
no end byte within 255 flags, flag bytes that are not 10.98 and not ours (byte 39, the rider seat, is ours; 40-43
are refused), a 0 dimension, more than 65535 sprites in a thing, an animator start phase out of range, sprite ids
above the spr count, trailing bytes; in the spr a table that does not fit, bad offsets, truncated records or pixel
runs that do not decode to 32x32. Sprite 0 is allowed everywhere (the client draws nothing). Warnings: odd but valid
values (flag order and duplicates, item flags on other things, displacement, elevation, light, seats without a
negative displacement, async / loop / durations, pattern counts, missiles above 254, empty things, ids pointing at
empty slots, groups of one outfit with other layers or patterns, empty masks, masks holding art). Auras' second layer
is a front layer: their ids come from `server/data/XML/chaos_auras*.csv` (`--aura-looks`).
- Append-only mode (`--old OLD.dat OLD.spr`, `--new-only`, `--allow-changed 'outfit:1561,2132-2135'`): every old
  thing and sprite record byte-identical, only new ids added. `import_art_things.py`, `import_outfits.py` and
  `import_donor_things.py import` call it at the end of every run (`check_append_only`) and stop on an error.
  `set_rider_seat.py` changes old entries on purpose: check its output with `--allow-changed`.
- Live pair things_custom17 (windows-assets 854d34c, md5s above): 0 errors, 230 warnings, 12 s. Warnings: 95 phases
  of 0 ms (items 22664 to 25886, missiles 83, 96, 102-106, outfits 1270, 1374, 1375); 64 odd exact sizes (items 25651..); outfit
  267's groups differ in pattern z (the client indexes both with the walking group's); 7 outfits whose second layer
  is art, not a mask (932, 936, 1207, 1208, 1228, 1229, and 2043, the unused former Inquisitor look); 18 missiles
  without 3x3 patterns (43, 46, 47, 52, 137-149, 152); outfit 1239 has 8 directions; outfit 637 points at 9 empty sprite
  slots; 34 items without a sprite. Info: 8,381 blank padding entries, 150,867 sprite ids without a record, 27,143
  records no thing uses, 31 masks with a few stray pixels. Nothing was changed in the pair.
- Libraries: G 0 errors, 156 warnings (148 exact sizes, 8 things over 8 tiles); I 0 / 33 (23 wings / auras with a
  second art layer, 8 outfits with 4 addon patterns); K 0 / 30; U 0 / 31 (outfits 79, 189 with groups of different
  layers). Append-only runs on the real history: things_custom16 -> 17 passes; 15 -> 16 fails on exactly the five
  seated mounts and passes with `--allow-changed 'outfit:1561,2132-2135'`.
- CI: `check_pair_test.py` (synthetic pairs: good, wrong counts, truncated dat and spr, bad runs, flags, animators,
  masks, append-only violations) in the checks job; job `live-pair` checks out `windows-assets` (sparse `things`, read
  only, default token; skipped for pull requests from forks), verifies the archive's sha256 and runs the checker.

```
python3 -I client/tools/sprites/check_pair.py P/Tibia.dat P/Tibia.spr [--verbose]
python3 -I client/tools/sprites/check_pair.py NEW/Tibia.dat NEW/Tibia.spr --old P/Tibia.dat P/Tibia.spr --new-only
```

## Pair warning fixes (things_custom18, `tools/sprites/fix_pair_warnings.py`, `tools/sprites/pair_fixes/`)
The owner approved fixing the warnings of things_custom17 that matter in game. Each group was checked against the
client's draw code (0001-0041). All flagged stock-range things are byte-identical to the base client's pair, so
the problems came with the base. Only the dat changes. No sprite is added or edited.
- `fix_pair_warnings.py` (new) applies `pair_fixes/fixes.csv` (kind, thing, group, argument, reason) to copies of
  a pair. Kinds: `durations`, `zero_empty`, `clear_addon_masks`, `drop_addon_rows`, and since things_custom21
  `displacement` ("Player look displacement" below; see its docstring). Each fix
  checks its premise first: a duration must be 0 ms, a zeroed sprite id must be an empty slot, a cleared mask must be
  a pixel copy of its art. A fix already applied is a no-op. It verifies that every other thing is byte-identical,
  each fixed thing differs only in its fix's fields, the spr is byte-identical, and the append-only check with
  exactly the changed things passes. `--changes-out` writes every changed field (`pair_fixes/things_custom18_changes.csv`,
  2,904 rows). Tests: `fix_pair_warnings_test.py` (synthetic pair; in CI).
- **0 ms phases (95, fixed).** All are async animators, so the client skips a 0 ms phase on the next draw. Every
  such frame holds real art. The all-zero grounds 22894, 23469 and 23470 flashed through 15 frames at the frame
  rate. Set: a phase to the thing's other phases (22664 500 ms; 22679, 24732, 25885, 25886, outfit 1270 idle 100 ms);
  the three grounds 100 ms like their sibling 23471; outfits 1374 and 1375 idle 100 ms (stock 8-phase idle groups);
  missiles 83, 96, 102, 103, 105, 106 100 ms (stock animated missiles). Async, loop and start bytes are unchanged.
  Our client draws missiles at phase 0, so the missile change only matters to other readers of the pair.
- **Outfit 637 (9 refs, fixed).** All nine are one tile: the colour mask, top-left tile, north, addon 2, mounted,
  sprites 220064, 220130 and 220194. Donor D outfit 125 is the same look. There this tile holds one magenta pixel,
  no template colour. Our base's masks are donor D's without the magenta pixels, so the tile was left blank and its
  record dropped. Blank on purpose: the refs now point at sprite 0. No visible change.
- **Outfit 267 (fixed).** The idle group had 2 addon rows, the walk group 1. The client merges the groups and
  indexes both with the last group's patterns, so idle stepped through frames 0-4 with repeats and walk showed idle
  frames. The
  walk group was never drawn. Row 1 is a phase-shifted copy of row 0 with tiles missing; row 0 equals the walk
  group. The idle group now keeps row 0 only (512 bytes shorter). Idle and walk now cycle all 8 frames.
- **Outfits 1207, 1208, 1228, 1229 (store looks, fixed).** Their base-pattern masks are real. In the addon patterns
  the second layer is a pixel copy of the addon art (1208: 368 copies and 166 real masks). The client never draws
  layer 2 of a creature. Its shader tints the base wherever a mask pixel has a channel above 0.9, so the addons'
  bright pixels took a random part colour. On 1228 and 1229 the bone spikes and trims went blue or purple. The 2,798
  copied sprites now point at 0: addons draw in their own colours. 1208's real addon masks are kept. No library
  has real addon masks for these looks (donor D 626 = 1208 with the same copies).
- **Accepted warnings (121 remain).**
  - exact-size (64): the client reads the byte and never uses it. Drawn sizes come from the texture bounds.
  - mask-not-mask 932, 936: base auras ("Fire Essence", "Bats", base auras.xml ids 1 and 5). An aura's second
    layer is its front layer and is drawn as such. The checker only knows the `chaos_auras*.csv` ids.
  - mask-not-mask 2043: the unused former Inquisitor look.
  - missile-patterns (18): 43, 46, 47 and 52 are blank (sprite 0). 137-149 and 152 are donor B missiles with one
    pattern. Our client then draws them only when flying north-west (the texture index of other directions is out of
    range). No server script or monster sends them. Give them 3x3 patterns before a spell uses one.
  - outfit-directions 1239 (Fire Panther mount): patterns 0-3 are its four directions; 4-7 hold stray sprites the
    client never reads.
  - thing-empty (34 items): stock invisible things (stairs and "nothing special" markers, god rays, moon rays, an
    energy barrier, "Empty Item"). The same in the base pair; no art to restore.

```
python3 -I client/tools/sprites/fix_pair_warnings.py --ours-dat things_custom17/Tibia.dat --ours-spr things_custom17/Tibia.spr \
    --out-dir things_custom18 --expect-dat-md5 8f0dcbfe56be1a6b3f86677e497cdeaa \
    --changes-out client/tools/sprites/pair_fixes/things_custom18_changes.csv
python3 -I client/tools/sprites/check_pair.py things_custom18/Tibia.dat things_custom18/Tibia.spr \
    --old things_custom17/Tibia.dat things_custom17/Tibia.spr \
    --allow-changed 'item:22664,22679,22894,23469,23470,24732,25885,25886;outfit:267,637,1207,1208,1228,1229,1270,1374,1375;missile:83,96,102,103,105,106'
```
Output **things_custom18**: dat 63fd01750be7696bcf590d0145643cb1 (4,670,980 bytes, -512), spr
6aee9a3429bdb9039787cb7eacf079c8 (unchanged: 587,305,926 bytes, 724,425 sprites), 33,659 items, 2,142 outfits, 592
effects, 153 missiles. 23 things changed, 36,424 byte-identical. Built twice with identical md5s. A run on its own
output changes nothing. Append-only with exactly those 23 ids: 0 errors (one id fewer: 1 error). Full check: 0
errors, 121 warnings (things_custom17: 230).
- `things-1098.tar.xz` is built like things_custom17's (Tibia.dat and Tibia.spr at the archive root, owner 0/0,
  GNU tar, `xz -9 -T3`), mtime 2026-10-12 13:00: sha256 91c94c7db59244751aa98b6134e2ff76404c618aed771c42c20d26981efe15bb
  (65,646,396 bytes). Its two files unpack to the md5s above. A rebuild gives the same sha256.
- On `windows-assets` since 2026-10-12 (f543599, approved by the owner). Nothing in `main` pins the pair's md5: CI `live-pair` and
  the Windows package check the archive against the branch's own `SHA256SUMS.parts`. No server change goes with it.
  A client still on things_custom17 keeps the old animations and tints.
- Checked offline: before / after contact sheets that follow the client's draw code (group merge, mask shader with
  test colours). Not checked in a live client.

## Class looks pair 19 (things_custom19, outfits 2161-2172, `tools/sprites/monster_looks/classlook_picks.csv`)
The owner approved six class look swaps (docs/CLASSES.md "Content per class"). Twelve donor-library outfits, imported
unchanged. No art was generated and no pixel was changed. 2143-2160 are blank padding, kept for the open look slots.

| looks | class | donor | look |
|---|---|---|---|
| 2161 / 2162 | Juggernaut | D 997 / 998 | gilded plate, tower shield |
| 2163 / 2164 | Ranger | H 246 / 247 | hooded archer |
| 2165 / 2166 | Beastmaster | D 166 / 167 | fur cloak |
| 2167 / 2168 | Bone Lord | D 508 / 509 | bone wings, skull rack |
| 2169 / 2170 | Shadowfist | D 1057 / 1058 | claws, violet glow |
| 2171 / 2172 | Sentinel | D 992 / 993 | holy orbs, tower shield |

- Every one has a colour mask, both addon patterns and an 8-frame walk. All but the Ranger pair have a mounted
  pattern. The Ranger pair has none, like the look it replaces (2078 / 2079): the client then draws the rider without
  the mount. The art is mostly in the addons: with addons 0 several look like a plain body. The server wears class
  looks with both addons (server/README.md "Class looks").
- Silhouette against stock (best IoU): 0.64 to 0.86; none is a pixel copy of a pair look. Per look in
  `outfit_art/class_looks_sources.csv` (licence tracing).
- The server uses them: `ChaosClassLooks.PAIR19_LOOKS` is on since the pair push (server/README.md "Class looks").
  A client still on things_custom18 draws nothing for 2161-2172. The dat and spr signatures are unchanged (0x42a3,
  0x57bbd603), so the server cannot tell the pairs apart: players need the package rebuilt from the branch.

```
python3 -I client/tools/sprites/donor_pick.py --picks client/tools/sprites/monster_looks/classlook_picks.csv --lib-dir L \
    --out-dir MINI12 --base-dat things_custom18/Tibia.dat --base-spr things_custom18/Tibia.spr
python3 -I client/tools/sprites/import_outfits.py --src-dat MINI12/Tibia.dat --src-spr MINI12/Tibia.spr \
    --ours-dat things_custom18/Tibia.dat --ours-spr things_custom18/Tibia.spr \
    --looks 1,2,3,4,5,6,7,8,9,10,11,12 --first-outfit 2161 --out-dir things_custom19
python3 -I client/tools/sprites/check_pair.py things_custom19/Tibia.dat things_custom19/Tibia.spr \
    --old things_custom18/Tibia.dat things_custom18/Tibia.spr
```
MINI12: dat 7afd00b335071b8cec334b3f9735335f, spr 4c7602c35fc3a89845d3c87d5a9edb8b. Input things_custom18 (dat
63fd01750be7696bcf590d0145643cb1, spr 6aee9a3429bdb9039787cb7eacf079c8). Output **things_custom19**: dat
e73621a13faaa9f1f5aa94bbef25d443 (4,791,972 bytes), spr d700334dc8811dd02a59e33a37805224 (593,188,851 bytes,
733,798 sprites, 9,373 appended), 33,659 items, 2,172 outfits, 592 effects, 153 missiles. Built twice with identical
md5s. Verified by the importer: 29,760 sprite slots and 3,720 frames of the twelve outfits pixel-identical to MINI12,
flags and animators equal, the 2,142 old outfits and every item, effect and missile byte-identical, 3000 sampled old
sprites unchanged.
- `check_pair.py`: append-only against things_custom18 passes (36,447 old things and 724,425 old sprites compared;
  new: 30 outfits, 9,373 sprites). Full check: 0 errors, 121 warnings, the same 121 as things_custom18; none in the
  new looks (2165 and 2170 have one cyan mask pixel each, info only).
- `things-1098.tar.xz` is built like things_custom18's (Tibia.dat and Tibia.spr at the archive root, owner 0/0,
  GNU tar, `xz -9 -T3`), mtime 2026-10-12 14:00: sha256 a203681267535b90cc420a6f6bed8931c7e59a8845d2cfcd6b9f27ac74a78c41
  (66,144,948 bytes). Its two files unpack to the md5s above. A rebuild gives the same sha256.
- On `windows-assets` since 2026-10-12 (b36204f2, approved by the owner). CI `live-pair` and the Windows package
  read the branch's own `SHA256SUMS.parts`, so nothing in `main` pins the pair's md5.
- Checked offline: a contact sheet of the twelve looks, addons 0 and 3, four directions and the mounted pattern,
  drawn with the client's colour shader. Not checked in a live client.

## Class looks pair 20 (things_custom20, outfits 2173-2184, `tools/sprites/monster_looks/classlook_picks20.csv`, `tools/sprites/compose/classlook_*.json`)
The owner found the generated art for the open slots ("New class look art") not good enough and asked for donor art.
Twelve looks for six classes, donor-library pixels only: eight outfits imported unchanged and four composed from two
donor outfits each (a donor body with its own addons plus one addon part of another donor outfit of the same body
family). The owner approved the picks. On `windows-assets` since 2026-10-12 (77b9cc9b), and the server uses them:
`ChaosClassLooks.PAIR20_LOOKS` is on (server/README.md "Class looks"). A client still on things_custom19 or older
draws nothing for 2173-2184, and the server cannot tell the pairs apart: players need the package rebuilt from the
branch.

| looks | class | donor | look |
|---|---|---|---|
| 2173 / 2174 | Lich | D 219 / 220 | skeletal lord: skull face, skull cape, bone sceptre (a matched pair; replaces 2059 for both sexes) |
| 2175 / 2176 | Thief | D 521 / 522 | hooded rogue, twin daggers |
| 2177 / 2178 | Ninja | D 789 / 790 | black shinobi, red-eyed mask, katana |
| 2179 / 2180 | Templar | D 609 / 610 | gilded holy knight, kite shield, sceptre / spear (displacement 8,8 added) |
| 2181 / 2182 | Inquisitor | D 419 / 420 + D 827 / 828 addon 1 | witch-hunter hat, rapier, holy sceptre (composed; replaces 2077 for both sexes) |
| 2183 / 2184 | Necromancer | D 856 / 857 + D 829 addon 1 | blood hood / witch hat, blood orb, skull (composed; replaces 2044 / 2064) |

- Search: every masked 4-direction outfit of libraries B-V up to 3x3 that is not tagged "named character" or "do not
  use live: branded" (1,259 rows; B, E and M have none with a colour mask). The owner also allowed "library only" rows
  for these slots, marked as such; none was needed (S 54 / 55, retail-style, is the Templar alternative B).
- Stock check, now by pixels (`donor_pick.py`): the silhouette IoU alone refused looks that only share a common body
  shape (D 790 has 0.96 with the gold plate 1064). The pick's base pattern is compared pixel by pixel (and by luminance
  correlation, for recolours) with the closest stock outfits; >= 0.6 is stock art and refused. Known copies score 1.00
  (D 1001 = stock 152, D 1049 = 145); the picks 0.00-0.57. 0.7-0.9 IoU is still printed for a check by eye.
- Every pick: a colour mask, both addon patterns (the class identity is in them), an 8-frame walk, a mounted pattern,
  a look per sex. None duplicates a look of the pair (`donor_pick.py` and the importers check).
- Placement: D 609 / 610 have no displacement although their art sits like a stock player outfit's, so the client would
  draw them 8 px low and right of their tile; `donor_pick.py` edit `player-disp` sets 8,8 (no pixel changed). The
  current Thief and Ninja looks 2051 / 2052 and 2069 / 2070 have the same fault (feet 6-8 px low); not changed here
  (fixed in things_custom21, "Player look displacement" below).
- Composer: a layer's `addons` may now be a map (`{"2": 1}`: drawn only on output addon pattern 2, from its own addon
  pattern 1, with its own mask). The Inquisitor's sceptre reaches past the tile, so the composer lowered the
  displacement to 6,6 (the male look is 3x3).
- Sheets (offline, the client's mask shader, the tile outlined): per slot 3-4 candidates with all directions, idle and
  walk, addons 0 and 3, each addon alone, two tints; the alternatives are in the sheets and in the build notes.

```
python3 -I client/tools/sprites/donor_pick.py --picks client/tools/sprites/monster_looks/classlook_picks20.csv --lib-dir L \
    --out-dir MINI8 --base-dat things_custom19/Tibia.dat --base-spr things_custom19/Tibia.spr
python3 -I client/tools/sprites/import_outfits.py --src-dat MINI8/Tibia.dat --src-spr MINI8/Tibia.spr \
    --ours-dat things_custom19/Tibia.dat --ours-spr things_custom19/Tibia.spr --looks 1,2,3,4,5,6,7,8 --first-outfit 2173 --out-dir P20A
for k in inquisitor_male inquisitor_female necromancer_male necromancer_female; do
    python3 -I client/tools/sprites/compose_outfit.py client/tools/sprites/compose/classlook_$k.json --lib-dir L \
        --out-dir COMP --csv-out COMP/things.csv; done
python3 -I client/tools/sprites/import_art_things.py --ours-dat P20A/Tibia.dat --ours-spr P20A/Tibia.spr \
    --out-dir things_custom20 --things COMP/things.csv --first-outfit 2181 --expect-items 33659
python3 -I client/tools/sprites/check_pair.py things_custom20/Tibia.dat things_custom20/Tibia.spr \
    --old things_custom19/Tibia.dat things_custom19/Tibia.spr
```
MINI8: dat 140d66e2d7f5a54e8fa36158f3332ef9, spr e8761e87eb18fc49c353b7e8b47c995b. P20A: dat
51a24ae40e7e44c996c140f8f5343aa5, spr af8deeececb87fe8a9e5aae9a7abdfc4. Input things_custom19 (dat
e73621a13faaa9f1f5aa94bbef25d443). Output **things_custom20**: dat 4dfc1c79d0c0e46cd04994c5ff4e09f7 (4,917,362 bytes),
spr 1a11296180c55dd64bbdce829580ec3b (599,349,497 bytes, 745,156 sprites, 11,358 appended), 33,659 items, 2,184
outfits, 592 effects, 153 missiles. Built twice with identical md5s. The importers verified every old thing
byte-identical, the new sprite slots pixel-identical to MINI8 and to the composed sheets, 3000 sampled old sprites
unchanged.
- `check_pair.py`: append-only against things_custom19 passes (36,477 old things and 733,798 old sprites compared; new:
  12 outfits, 11,358 sprites). Full check: 0 errors, 121 warnings, the same groups as things_custom19; none in the
  new looks.
- `things-1098.tar.xz` like things_custom19's (Tibia.dat and Tibia.spr at the root, owner 0/0, GNU tar, `xz -9 -T3`),
  mtime 2026-10-12 16:00: sha256 4ec97152be8b54f2ede683ee27dfdfe7944b6c36ee9190785e7f069355d11202 (66,679,488 bytes).
  Its two files unpack to the md5s above. A rebuild gives the same sha256.
- On `windows-assets` since 2026-10-12 (77b9cc9b, pushed by the owner after approving the picks). CI `live-pair` and
  the Windows package read the branch's own `SHA256SUMS.parts`, so nothing in `main` pins the pair's md5.
- Not checked in a live client.

## Player look displacement (things_custom21, `tools/sprites/fix_pair_warnings.py` kind `displacement`)
The owner approved fixing the fault noted in "Class looks pair 20": player looks with no displacement whose art sits
like a stock player look's. Our client (ThingType::draw, no GameCenteredOutfits in the 1098 profile) draws a frame
pixel at (x - dx - (w-1)*32, y - dy - (h-1)*32) from the creature's tile, so such a look stood about 8 px low and
right of its tile. Its name, health bar, light and target square (Creature::draw, `getDisplacement`) were 8 px off too.
Mounted, the rider's own displacement cancels out on stock mounts (positive path of `Outfit::draw`), so a ridden look
draws exactly as before; on the negative-displacement donor mounts the rider is drawn by its displacement, as the
seats of patch 0034 expect (they were set with stock 8,8 riders). Only the dat changes: 22 outfits get dat byte 25 =
8,8 (14 inserted in flag order, 8 had 0,0). No sprite is added or edited.
- Check (`fix_pair_warnings.py --scan-displacement --looks IDS`, then by eye). Wearable looks: every looktype of the
  installed outfits.xml plus `class_looks_core.lua` and `exclusives_config.lua` (291 looks). 161 of them have 8,8; their
  feet line (lowest row with 3 or more art pixels, median of four directions) is row 24 of the tile. 66 are 2x2 or
  larger with no displacement. 36 of those have art within 3 px of the frame's bottom and right edges (stock 8,8 art
  touches them; art drawn for no displacement keeps about 8 px clear). 24 of these stand 5 px or more low (feet 29 to
  31.5); 8,8 brings them to 21-23.5. Two of the 24 were left: 2059 (Lich Class (old)) and 2174 (Lich Class, female)
  only measure low because chains and a cape trail below the feet. A silhouette match with the stock 8,8 looks puts
  them at -7,-7 and 3,4. On a tile grid they stand right. Borderline and left: 884 / 885 (feet 4.5 px low, 8,8 would
  be 3.5 px high). The match puts the 22 fixed looks at 4,4 to 13,13 (most 6-9).
- Mounts (146 with no displacement, the stock convention; the five donor mounts are negative), wings (stock 0) and
  auras have their own placement rules and are not player looks: none changed.
- Fixed (fixes.csv, kind `displacement`, arg 8,8): class looks 2049 / 2050 (Illusionist), 2071 / 2072 (Samurai),
  2051 / 2052 (Thief (old)), 2069 / 2070 (Ninja (old)), 2065 / 2066 (Bone Lord (old)); class outfits 1505 / 1506
  (Shadow / Crimson Ninja; the art of 2069 / 2070) and 1508 / 1510 (Oni / Dark Samurai; the art of 2071 / 2072); the
  exclusive Ashen Seraph 1459; outfits.xml 329 (Newly Wed), 745 / 746 (Recruiter), 852 / 853 (Winter Warden), 873 /
  874 (Philosopher).
- Premise of the kind: outfit, no displacement or 0,0 (another value stops the run), every frame group 2x2 or larger,
  idle art (phase 0, addon 0, mount 0, layer 0, all directions) within 3 px of the frame's bottom and right edges, and
  its feet line 5 px or more below row 24. A fix already applied is a no-op. Verified: the flags differ only in the
  displacement, frame groups and sprites identical. Tests: `fix_pair_warnings_test.py` (insert before a later flag,
  replace 0,0, a no-op on 8,8, each premise refusal, the scan).

```
python3 -I client/tools/sprites/fix_pair_warnings.py --ours-dat things_custom20/Tibia.dat --ours-spr things_custom20/Tibia.spr \
    --scan-displacement --looks IDS
python3 -I client/tools/sprites/fix_pair_warnings.py --ours-dat things_custom20/Tibia.dat --ours-spr things_custom20/Tibia.spr \
    --out-dir things_custom21 --expect-dat-md5 4dfc1c79d0c0e46cd04994c5ff4e09f7 \
    --changes-out client/tools/sprites/pair_fixes/things_custom21_changes.csv
python3 -I client/tools/sprites/check_pair.py things_custom21/Tibia.dat things_custom21/Tibia.spr \
    --old things_custom20/Tibia.dat things_custom20/Tibia.spr \
    --allow-changed 'outfit:329,745,746,852,853,873,874,1459,1505,1506,1508,1510,2049,2050,2051,2052,2065,2066,2069,2070,2071,2072'
```
Input things_custom20 (dat 4dfc1c79d0c0e46cd04994c5ff4e09f7, spr 1a11296180c55dd64bbdce829580ec3b). Output
**things_custom21**: dat 29e959f34600c3e5c11eec72f4aa34f5 (4,917,432 bytes, +70), spr 1a11296180c55dd64bbdce829580ec3b
(unchanged: 599,349,497 bytes, 745,156 sprites), 33,659 items, 2,184 outfits, 592 effects, 153 missiles. The earlier
fixes.csv rows are no-ops on things_custom20. 22 things changed, 36,467 byte-identical. Built twice with identical md5s;
a run on its own output changes nothing. `pair_fixes/things_custom21_changes.csv`: 22 rows.
- `check_pair.py`: append-only with exactly those 22 ids: 0 errors (21 ids: 1 error). Full check: 0 errors, 121
  warnings, the same as things_custom20.
- `things-1098.tar.xz` like things_custom20's (Tibia.dat and Tibia.spr at the root, owner 0/0, GNU tar, `xz -9 -T3`),
  mtime 2026-10-12 17:00: sha256 b0a3d8a4101c7251fd6809a1f07160c73419884a4dbc2ba9524a4cf54ddb522d (66,683,748 bytes).
  Its two files unpack to the md5s above. A rebuild gives the same sha256.
- On windows-assets since 2026-10-12 (commit 0f1f416b, owner approved). No server change: the look ids
  stay the same. A client on things_custom20 keeps drawing the 22 looks 8 px low.
- Checked offline: before / after sheets of the 22 looks, four directions with both addons, on a tile grid with the
  stock look 128 beside them, placed by the client's draw rule. Not checked in a live client.

## Class signature effects (things_custom22, effects 593-627, `tools/sprites/gen_class_fx.py`, `art_import/class_fx.csv`)
ROADMAP C4 left the effects open: the class lines shared the pack effects (aura_burst_gold for Iron Bellow, Bushido
Focus, Zealotry and Banner Call; shield_bubble for Counter Stance, Chi Ward and Soulward; healing_bloom for Purifying
Wellspring, Vow of Mending and Lay on Hands; dawn_aegis for Lightward and Aegis of Faith; earth_spikes for Earthbreaker
and Briar Prison; whirlwind for Reaping Gyre and Whirling Heel; shade_vanish for the Thief, the Ninja and Umbral
Stride; teleport_in for Wild Bond and Moonfang Pack; cursed and toxic_burst for the Necromancer line and the
Illusionist; the Ranger's spells used the Templar's holy art), and the snares and vigils sent stock effects only.
35 effects of our own procedural art, one look per line (palette and shape): Warrior iron, rock and ember; Ranger
amber, leaf and wind; Mystic prism and rose (the Elementalist a three-element glyph); Thief smoke, ink and sakura;
Necromancer void and soul green; Monk chi, violet and jade; Templar gold. Which spell sends which: server/README.md
"Class signature effects"; looks: server/data/spells/README_FX.md "Class signature effects".
- `gen_class_fx.py build` draws every frame in Python (discs, capsules, triangles, polygons, rings on a 4x supersample,
  quantised per material to hard ramps with a dark outline; no painting service, no reference pixels) and writes the
  strips `art_import/class_fx/<name>.png` and the spec `art_import/class_fx.csv`; deterministic (`build --check`
  compares). Checks: alpha 0 / 255, every frame but the last has art, the last is empty, nothing touches the frame's
  edge, the two 1x1 area effects keep 65 % of every frame transparent. 33 effects are 3x3 sent at the target + (1, 1)
  (the target is the centre tile), ranger_arrowfall and ninja_smoke are 1x1 on the tile. `preview --out DIR --dat D
  --spr S` writes a frame-by-frame sheet (`class_fx_frames.png`, one sheet per effect in `frames/`) and a mock combat
  scene per class (`scenes/`, `class_fx_scenes.png`: the class look and a rift minion from the pair, the effects at
  their peak frame by the client's draw rule).
- Built on things_custom21 (dat 29e959f34600c3e5c11eec72f4aa34f5, spr 1a11296180c55dd64bbdce829580ec3b):
  ```
  python3 -I client/tools/sprites/gen_class_fx.py build
  python3 -I client/tools/sprites/import_fx_art.py --ours-dat things_custom21/Tibia.dat --ours-spr things_custom21/Tibia.spr \
      --out-dir things_custom22 --spec client/tools/sprites/art_import/class_fx.csv --expect-first-effect 593 \
      --lua-out server/data/lib/chaos_class_fx_ids.lua --catalog-out server/data/spells/class_fx_catalog.csv
  python3 -I client/tools/sprites/check_pair.py things_custom22/Tibia.dat things_custom22/Tibia.spr \
      --old things_custom21/Tibia.dat things_custom21/Tibia.spr
  ```
  The ids go to their own Lua file (not `chaos_vfx_art.lua`), loaded only with the server switch on.
  `import_fx_art.py` now names its spec in the generated header.
- Output **things_custom22**: dat 9d1591bef8f9f89d102219baf8c38578 (4,929,187 bytes), spr
  09f3a073b0a071d54b9604a422a9dffd (599,654,574 bytes, 745,653 sprites: 497 new), 33,659 items, 2,184 outfits, 627
  effects, 153 missiles. Built twice with identical md5s. The importer verified 264 frames pixel-identical to the
  strips and every old thing byte-identical. `check_pair.py`: append-only, 0 errors (35 new effects, 497 new sprites);
  full check 0 errors, 121 warnings, the same as things_custom21.
- `things-1098.tar.xz` like things_custom21's (mtime 2026-10-12 23:00): sha256
  81cd9eefb35e2f1467af13a17bc1d88c61ebed02c19aeaaaf91f453e7c0235b5 (66,725,980 bytes); unpacks to the md5s above.
- On windows-assets since 2026-10-12 (commit 13e289c7, owner approved). The server switch `ChaosClassFx.PAIR22_FX`
  is on; a client still on things_custom21 draws nothing for the 35 new effect ids.
- Checked offline only (frame sheets and the mock scenes); not run in a client.
- Checked in a live client, 2026-10-13, Linux build, base patches 0001-0044, 0048 and 0049, pair things_custom23 from
  windows-assets: the class effects draw at the placements the server sends. Skyfall Cleave drew nothing of its own
  before a server fix; server/README.md "Class signature effects".

## Pack effect cuts (things_custom24, effects 628-634, `tools/sprites/gen_pack_fx.py`, `art_import/pack_fx.csv`; on windows-assets 407ad9b6, switch on since 2026-10-13 (pair 24 at 407ad9b6))
**Source and licence.** The oblique spell effect set that `import_vfx.py` reads (`--src-spells`; effects 429-558 are
all of its 68 effects). The owner re-uploaded it on 2026-10-13: byte-identical to the copy used for effects 429-558,
plus preview GIFs and an engine helper script. Its licence: use in unlimited personal and commercial projects (games
included), modified or unmodified; no attribution needed; no reselling, redistributing, sublicensing or sharing of the
assets themselves, alone or inside another asset pack, template or generator, even modified; no machine-learning
training. Shipping the art inside the game client is use in a game. The set and anything cut from it stay out of git:
`art_import/pack_fx/` is ignored, only the spec and `art_import/pack_fx.sums` (sha256 of each strip's RGBA pixels) are
committed. The set itself is kept with the art libraries outside the repository.
- 7 one-shot cuts of status loops for things sent on every proc or tick (the full loops run 1.3-2 s): reflect_bubble
  (shield bubble 0-7), tick_bleed, tick_burn, tick_poison, tick_curse, tick_regen (frames 0-11), tick_chill (frozen
  0-9); 70 ms per frame, alpha 0 / 255 (soft glows become an ordered 4x4 dither), the last three frames dissolve in the
  same dither, an empty last frame; placed like `import_vfx.py` (the set's feet point on (14, 20)), cut to whole
  tiles: 3x3 sent at +1,+1, tick_bleed 3x2 at +1,+1, tick_burn 2x3 at 0,+1. About 690 sprites.
- `python3 -I gen_pack_fx.py build --src SET` writes the strips, the spec and the sums; `build --check` (CI, Pillow
  12.3.0 / numpy 2.5.3 like the class effects) compares the spec and sums with the script's table without the set,
  and rebuilds byte-exact when `--src` is given. `preview --out DIR`: frame sheets and GIFs per cut.
- Appended to things_custom24 after everything else (ids = its effect count + 1..; 628.., things_custom23 ends at
  effect 627):
  ```
  python3 -I client/tools/sprites/gen_pack_fx.py build --src SET
  python3 -I client/tools/sprites/import_fx_art.py --ours-dat IN/Tibia.dat --ours-spr IN/Tibia.spr --out-dir OUT \
      --spec client/tools/sprites/art_import/pack_fx.csv --expect-first-effect N \
      --lua-out server/data/lib/chaos_pack_fx_ids.lua --catalog-out server/data/spells/pack_fx_catalog.csv
  python3 -I client/tools/sprites/check_pair.py OUT/Tibia.dat OUT/Tibia.spr --old IN/Tibia.dat IN/Tibia.spr
  ```
  Server use: server/README.md "Pack effects for procs and bosses" (switch `ChaosPackFx.PACK_FX`, on since 2026-10-13 (pair 24 at 407ad9b6)).

## Large spell effects (things_custom24, effects 635-655, `tools/sprites/gen_big_fx.py`, `art_import/big_fx.csv`; on windows-assets 407ad9b6, switch on since 2026-10-13 (pair 24 at 407ad9b6))
Our own procedural art: big soft glowing effects for boss telegraphs and big attacks, rift guardians and the strongest
area spells of each class line (server/README.md "Large spell effects", switch `ChaosBigFx.BIG_FX`, on since 2026-10-13 (pair 24 at 407ad9b6)).
- Drawing: each frame is computed as fields at 4x supersampling with numpy only (radial gradients, seeded value noise,
  rings, glow, particles, jagged bolts, leaning beams), coloured through the element ramps of
  `item_forge_data/style.json` (fire, ice, lightning, poison, holy, void, blood; arcane has its own teal ramp in the
  script) with a hot tip, over an optional dark smoke field; box-averaged to the 32 px grid with premultiplied alpha.
  The alpha stays soft (1..254; under 12 is cut to 0): the pair's spr has an alpha channel and the client blends it,
  like the animated pack effects 429-558. No pixel of any other game or client is read or used.
- 21 effects, every one sent at its centre tile (offset (N-1)/2):
  telegraph 5x5 / 7x7 / 9x9 (red rim, translucent fill, a timer ring growing to the rim, turning ticks; 10 x 100 ms);
  shockwave rings fire 7, frost 7, lightning 7, holy 5, blood 9 (10 frames); novas fire 9, frost 7, poison 7, holy 7,
  void 7 (gathers in first, 13 frames), arcane 7 (12 x 70 ms); pillars of light holy 5 and arcane 5 (a beam lands,
  leaning like the pair's tall things, a glyph ring, rising motes); meteor fire 7 (falls 8 frames, impact at 560 ms,
  13 x 70 ms); lightning burst 7 (forked bolts, new every second frame, a sky bolt; 10 x 60 ms); holy sanctum 5
  (two rings, a turning hexagram, rune ticks; 12 x 80 ms); void rift 7 (an upright tear, spiral arms, motes drawn in;
  13 x 80 ms); blood geyser 5 (a pool, a spout, ballistic droplets). Every strip: last frame empty, nothing on the
  frame's edge, 10-13 frames.
- Size: 6,751 sprites, 17,622,095 bytes added to Tibia.spr (things_custom22: 599.7 MB -> 617.3 MB, +2.9%); xz of the
  whole spr grows by about 4.3 MB. Soft pixels are what costs: a 9x9 telegraph is 606 sprites / 2.1 MB alone. A trial
  import on things_custom22 (scratch only, no pair kept) verified all 237 frames pixel-identical after the round trip.
  `gen_big_fx.py stats` prints the table per effect.
- `python3 -I gen_big_fx.py build` writes the strips (`art_import/big_fx/`, about 5 MB of PNG, ignored by git), the
  spec and `art_import/big_fx.sums` (sha256 of each strip's RGBA pixels); `build --check` (CI, Pillow 12.3.0 /
  numpy 2.5.3 like the class effects) renders again and compares the spec, the sums and the strips on disk.
  `preview --out DIR [--dat D --spr S]`: a GIF per effect on an 11x11 tile area with a player look for scale, and a
  sheet of every frame. About 2 minutes for either.
- The spec has an `alpha` column (`soft`): `import_fx_art.py` keeps the alpha levels for such rows (other specs keep
  the 0 / 255 cut at 128). Appended to things_custom24 after the pack cuts (effects 635-655):
  ```
  python3 -I client/tools/sprites/gen_big_fx.py build
  python3 -I client/tools/sprites/import_fx_art.py --ours-dat IN/Tibia.dat --ours-spr IN/Tibia.spr --out-dir OUT \
      --spec client/tools/sprites/art_import/big_fx.csv --expect-first-effect N \
      --lua-out server/data/lib/chaos_big_fx_ids.lua --catalog-out server/data/spells/big_fx_catalog.csv
  python3 -I client/tools/sprites/check_pair.py OUT/Tibia.dat OUT/Tibia.spr --old IN/Tibia.dat IN/Tibia.spr
  ```
- The client draws a thing from its bottom-right tile, so a 9x9 effect is drawn with the tile 4 right / 4 down of its
  centre; near the right or bottom edge of the view that tile can be outside what the client draws and the effect is
  cut. Not seen in a client yet.

## Rift rank variants (things_custom24, outfits 2200-2207, `tools/sprites/rift_variants.py`, `art_import/rift_variants.csv`; on windows-assets 407ad9b6, switch on since 2026-10-13 (pair 24 at 407ad9b6))
Eight new looks of rift monsters, our own art: PixelLab (edit-animation, owner approved) repainted the frames of a rift
look of our pair, so each variant keeps its base's size, frame groups, phases, timing, flags and feet line. Only our
own frames were sent as input; no outside reference art. Base looks (donor-library art of things_custom11, sources in
`monster_looks/sources.csv`): 2100, 2101, 2102, 2106, 2108, 2112, 2113, 2114.
- Spec `monster_looks/rift_variants.json`: per variant the key, planned look, base, theme, rank, name, the PixelLab jobs
  with prompts and seeds, and the post-processing numbers. The raw PixelLab results are not in git.
- `rift_variants.py extract` writes the base frames from a pair. `build` post-processes deterministically: alpha 0 / 255,
  specks dropped, one alignment shift per variant against the base's opaque core (all 0, 0: the edits came back
  registered; the lowest row of every frame equals the base's), a darker grade, one palette per variant (18-32 colours,
  glow accents kept), a dark rim on bright edges. Output: `art_import/rift_variants/<key>.png` (import_art_things.py
  layout, layers=1), `art_import/rift_variants.csv` and `monster_looks/rift_variant_picks.csv` (picks.csv rows, family
  `riftvariant`, appended to picks.csv with the pair). `check` and `rift_variants_test.py` need no pair.
- Append (ids from 2200; on things_custom24, which ends at outfit 2193, the importer pads 2194-2199 with blank outfits):
  ```
  python3 -I client/tools/sprites/import_art_things.py --ours-dat IN/Tibia.dat --ours-spr IN/Tibia.spr --out-dir OUT \
      --things client/tools/sprites/art_import/rift_variants.csv --first-outfit 2200 --expect-items <items of IN>
  python3 -I client/tools/sprites/check_pair.py OUT/Tibia.dat OUT/Tibia.spr --old IN/Tibia.dat IN/Tibia.spr
  ```
  A trial on a scratch copy of things_custom23 (`--expect-items 33659`, things_custom24: 33903): 8 outfits, 15 blank,
  716 new sprites (715 appended), 808 sprite slots pixel-identical, old things byte-identical, check_pair's append-only
  guard passed. Leave out `--sheets`: with no item rows the importer's item sheet fails on an empty image.
  Server use: server/README.md "Rift rank variants" (`looks.variantsOn`, on since 2026-10-13 (pair 24 at 407ad9b6)).

## Bigger guardians (things_custom24, outfits 2208-2212, `tools/sprites/big_bosses.py`, `art_import/big_bosses.csv`; on windows-assets 407ad9b6, switch on since 2026-10-13 (pair 24 at 407ad9b6))
Five 4x4 looks of our own for the rift guardians and the Omen seer, each with a 4-frame idle group and an 8-frame walk
group (the bases had 2-4 walk phases and a still idle). Only our own frames went to PixelLab: the guardian looks of our
pair (donor-library art of things_custom11, as for the rank variants). The world boss looks (842, 1472, 238, 862, 591)
are stock art and were left out.

| Key | Look | Base | Guardian | What changed |
|---|---|---|---|---|
| abyss_guardian_big | 2208 | 2103 (4x4) | Abyssal Sovereign | 8-frame walk, 4-frame idle |
| obsidian_guardian_big | 2209 | 2107 (4x4) | Obsidian Colossus | 8-frame walk, 4-frame idle |
| crypt_guardian_big | 2210 | 2111 (3x3) | Crypt Dreadknight | repainted at 4x4 (Edit images), 8-frame walk, 4-frame idle |
| sanctum_guardian_big | 2211 | 2115 (4x4) | Sanctum Warden | 8-frame walk, 4-frame idle |
| omen_seer_big | 2212 | 2118 (3x3) | Thalcyra the Stormbound Seer | repainted at 4x4, 8-frame walk, 4-frame idle |

- Painting: for a 3x3 base one "Edit images (Pro)" call over our four idle frames scaled to the 128 px canvas; then per
  direction one "Animate with text (v3)" call for the walk (8 frames) and one for the idle (4 frames), each from that
  direction's idle frame. Prompts and seeds per call in the spec `monster_looks/big_bosses.json`; raw results outside git.
- Second walk pass (owner approved): where the legs barely moved, the walk is now a stride between two of the look's
  own walk phases (Animate with text, first and last frame, phase a to b and back; frames 0, 2, 4, 6 of each half):
  Sanctum Warden all four directions (phases 1 and 2), Obsidian Colossus north and west (phases 0 and 1), Crypt
  Dreadknight all four (two stride poses of its 4x4 repaint, left and right leg forward, Edit images). Thalcyra east and
  west use a re-animation closed on the source frame (steadier silhouette). Colossus east and south keep the first walk
  (their strides grew lava flare blobs); the Abyssal Sovereign floats and keeps its walk. Calls tried and not used are
  listed per look in the spec (`tried_not_used`).
- `big_bosses.py build` (deterministic): alpha 0 / 255 and specks dropped, one shift per direction against its source
  frame (the animations drift), pixels over 8 px from the source frame or a stride's key poses and islands under 12 px
  dropped (loose sparks and props), one vertical shift onto the base's feet line moved to the 4x4 canvas, a light grade,
  one palette per look (32 colours plus up to 4 glow accents), a dark rim on bright edges. Sheets
  `art_import/big_bosses/<key>.png`: idle phases 0-3 then walk phases 0-7, one row each, columns north, east, south,
  west, 128 px cells; rows in `art_import/big_bosses.csv` (groups 0 / 1, exact 128, 300 ms per phase, no flags);
  `monster_looks/big_boss_picks.csv` (family `bigguardian`, appended to picks.csv with the pair on 2026-10-13). `check` and
  `big_bosses_test.py` need no pair.
- Append after the rank variants (ids from 2208; the importer pads blank outfits up to `--first-outfit`):
  ```
  python3 -I client/tools/sprites/import_art_things.py --ours-dat IN/Tibia.dat --ours-spr IN/Tibia.spr --out-dir OUT \
      --things client/tools/sprites/art_import/big_bosses.csv --first-outfit 2208 --expect-items <items of IN>
  python3 -I client/tools/sprites/check_pair.py OUT/Tibia.dat OUT/Tibia.spr --old IN/Tibia.dat IN/Tibia.spr
  ```
  In things_custom24 as its last step (2026-10-13, the art of the second walk pass, 07891edb; "Themed sets"): 5
  outfits 2208-2212 as planned, no blank padding, 2,769 sprites appended, `check_pair.py --old`: no new warning.
  Walk and idle GIFs read back from the pair were checked offline; not run in a client. The ids are fixed in
  `rift_config.lua` `looks.bigGuardians` (no ids file); `big_boss_picks.csv` and `rift_variant_picks.csv` were appended
  to picks.csv on 2026-10-13 (check_content.py's outfit limit is now 2212).
  Server use: server/README.md "Bigger guardians" (`looks.bigGuardiansOn`, on since 2026-10-13 (pair 24 at 407ad9b6)).

## Painted icons (setting "Painted icons", off; `tools/gen_painted_icons.py`, `tools/painted_icon_art/`)
A painted set of the buff bar's icons, the Chaos spells (spellbook) and the passive tree's keystones and masteries:
236 icons (100 drawn buff icons, 88 spells, 44 keystones, 4 masteries) plus the 22 class buffs that show their
spell's art. Our own art only: each icon is a PixelLab "Edit images (Pro)" repaint of our current icon (16 per call,
one generic prompt, seeds 7001-7015, 15 calls). Another client's icon set was studied for size and style only; none
of it was sent, copied or sampled.
- Source (committed): `painted_icon_art/painted_64.png` (one 64 px cell per icon, the raw repaint) and
  `painted_icons.csv` (kind, name, frame, element, the call and seed). `gen_painted_icons.py pack` built them from the
  raw results and classified each element once; the csv fixes it.
- Build (deterministic, `--check` in CI compares every output with a fresh build): scale (Lanczos) and sharpen, clamp
  to the palette of the icon's element (fire, blood, holy, nature, frost, arcane, steel, mixed: the ramps of
  `gen_buff_icons.R` with midpoints plus shared dark, bone, wood and steel ramps; no dither), then our frame drawn by the
  script: the buff bar's ember-gold frame, or the blood-red debuff frame with corner thorns (the frame each icon has
  now). Keystones and masteries get no frame (the tree draws the node frame).
- Outputs: `images/game/buffs_painted/<name>.png` (26 x 26, the bar's cell), `images/game/spells_painted/<clientId>.png`
  (32 x 32, the spellbook), `images/passivetree/painted_nodes.png` (64 px cells) and
  `modules/game_passivetree/treedata/painted.lua` (key -> clip).
- Client: one setting, the "Painted icons" box in the Buff Bar settings (right click an icon), g_settings
  `chaosPaintedIcons`, off by default. `game_buffbar` (`BuffMath.iconPath`, tested) redraws at once; `game_spellbook`
  (Chaos spells, by their words in `game_chaosspells`' data) and `game_passivetree` (`paintedTreeIcon`) use it the next
  time they draw. A name with no painted icon keeps its normal icon, so new buffs need no new painting.
- Why behind a setting and not in place: the painted set is a fixed snapshot (a new buff or spell needs a PixelLab call
  before it has one), and the current generators (`gen_buff_icons.py`, `gen_descent_icons.py`, `gen_raid_icons.py`,
  `gen_community_icons.py`) keep owning `images/game/buffs/`. The setting keeps both sets whole and lets the owner
  compare in game; `--check` stays deterministic because it only reads the committed source sheet.
- Not run in a client. Stock spells in the spellbook keep the sheet icons.

## Aura displacement (things_custom23, `tools/sprites/fix_pair_warnings.py` kind `displacement`)
**On windows-assets since 2026-10-13 (c91dd6f9, owner approved).** The owner approved fixing the Scarlet Glimmer aura (look 712, auras.xml 30, the boss exclusive
`aura_scarlet`). It had no displacement (the client reads 0,0). In a live client it drew about 17 x 12 units right and
below its place (server/README.md "Exclusives", the in-game check). Only the dat changes: 712 gets dat byte 25 =
17,17, the value of the stock Fire Essence 932. No sprite is added or edited.
- Draw rule (`Outfit::draw`, 1098 profile with GameBigAurasCenter): an aura frame moves (w-1)*16, (h-1)*16 right and
  down, then back by its displacement and (w-1)*32, (h-1)*32. A frame pixel lands at (x - dx - (w-1)*16, y - dy -
  (h-1)*16) from the tile's top left. Wings get no centring offset: (x - dx - (w-1)*32, y - dy - (h-1)*32).
- Measure (`--scan-aura-displacement`): per direction the mean of the art pixels (idle group, every phase and layer),
  drawn by that rule, then the median of the four directions; px from the tile centre, + = right / down. The stock
  ground auras 932 / 933 / 934 sit at -4.5,-3.3 / -0.9,-1.0 / -3.3,-3.1; 1487 at -5.5,-7.1; the head-height 935 / 936
  at -9 to -16. 712 at +12.8,+12.8. Its art differs per direction (an orb with sparkles, mirrored N/S and E/W). In every
  direction its cross axis is frame px 47.0, the centre of the frame's bottom-right tile, where 932 and 933 also put
  theirs (44.1-44.5). Drawn with 0,0 that axis is 15 px right / below the tile centre; with 17,17 it is 2 px up-left,
  and the median centre -4.2,-4.2, inside the ground auras' range. One value cannot centre both axes. Along its
  direction the art mirrors about the frame centre, not the bottom-right tile. So the orb leads the wearer facing
  north or west and sits on the body facing south or east.
- Scan of every aura and wings look of the pair (auras.xml 1-30: 932-936, 1511-1529, 2136-2139, 1487, 712; wings.xml
  1-19: 937-941, 1177-1186, 1486, 2140-2142): only 712 has no displacement and stands 8 px or more right and below.
  The seven 3x3 Chaos auras without displacement (1518, 1519, 1521, 1522, 1524, 1526, 1528) sit at -11 to -2 / -3 to
  +4: the centring offset places them. Every wings look sits at -12 to -27 up-left, like the stock wings (0,0). The
  donor auras 2136-2139 sit 8-9 px low but have displacements of their own (things_custom14): not this fault, left.
- `fix_pair_warnings.py`: the `displacement` kind has an aura premise for looks of `--aura-looks` (default the client
  ids of `server/data/XML/chaos_auras*.csv`): no displacement or 0,0, every frame group 2x2 or larger, centre 8 px
  or more right and below with no displacement (`AURA_OFF`), within 6 px of the tile centre with the new value
  (`AURA_NEAR`). The player-look premise is unchanged. New `--scan-aura-displacement --looks IDS [--wings IDS]`.
  Tests: `fix_pair_warnings_test.py` `test_aura_displacement` (17,17 inserted, 0,0 replaced, a no-op on its output,
  each refusal, the scan, the wings rule).

```
python3 -I client/tools/sprites/fix_pair_warnings.py --ours-dat things_custom22/Tibia.dat --ours-spr things_custom22/Tibia.spr \
    --scan-aura-displacement --looks 932-936,1511-1529,2136-2139,1487,712 --wings 937-941,1177-1186,1486,2140-2142
python3 -I client/tools/sprites/fix_pair_warnings.py --ours-dat things_custom22/Tibia.dat --ours-spr things_custom22/Tibia.spr \
    --out-dir things_custom23 --expect-dat-md5 9d1591bef8f9f89d102219baf8c38578 --link-spr \
    --changes-out client/tools/sprites/pair_fixes/things_custom23_changes.csv
python3 -I client/tools/sprites/check_pair.py things_custom23/Tibia.dat things_custom23/Tibia.spr \
    --old things_custom22/Tibia.dat things_custom22/Tibia.spr --allow-changed 'outfit:712'
```
Input things_custom22 (dat 9d1591bef8f9f89d102219baf8c38578, spr 09f3a073b0a071d54b9604a422a9dffd; the
windows-assets archive, sha256 checked against SHA256SUMS.parts). Output **things_custom23**: dat
8ca5332525db229ca0472fe292653986 (4,929,192 bytes, +5), spr 09f3a073b0a071d54b9604a422a9dffd (unchanged), 33,659
items, 2,184 outfits, 627 effects, 153 missiles. The earlier fixes.csv rows are no-ops on things_custom22. 1 thing
changed, 36,523 byte-identical. Built twice with identical md5s; a run on its own output changes nothing.
`pair_fixes/things_custom23_changes.csv`: 1 row.
- `check_pair.py`: append-only with `outfit:712`: 0 errors (without it: 1 error). Full check: 0 errors, 121
  warnings, line for line those of things_custom22.
- `things-1098.tar.xz` like things_custom22's (Tibia.dat and Tibia.spr at the root, owner 0/0, GNU tar, `xz -9 -T3`),
  mtime 2026-10-13 04:00: sha256 a866a48ef97451c53334f6361ba30a14122617bc9432c5393890792bfcf8672b (66,722,480 bytes).
  It unpacks to the md5s above. A rebuild gives the same sha256. On windows-assets since 2026-10-13 (c91dd6f9).
- No server change: the look id stays 712. A client on things_custom22 keeps drawing the Glimmer off its tile.
- Checked offline: a before / after sheet, four directions, on a tile grid with the stock look 128 and Fire Essence
  932, by the client's draw rule. The "before" column matches the in-game screenshots direction by direction. The
  fixed pair was not run in a live client.

## Everfull Ration look (new, `tools/sprites/gen_store_food_art.py`, `tools/sprites/art_import/store_food.csv`)
Our own art for the store's infinite food (server id 32084, `server/data/scripts/chaos/store_food_config.lua`): a glazed
earthen bowl with a gold rim, a roast haunch with its bone and four gold sparks. Drawn in code with the store pouches'
helpers (`gen_pouch_art.py`: 128 px shape fields, rim light, outline, 4:1 downsample), deterministic, written to
`art_import/store_food.png` (32 x 32). **Not in a pair yet:** client id 33904 (after the pair 24 items, 33903) is reserved;
append it to the next pair with
`python3 -I client/tools/sprites/import_art_things.py --ours-dat IN/Tibia.dat --ours-spr IN/Tibia.spr --out-dir OUT
--things client/tools/sprites/art_import/store_food.csv --first-item 33904 --expect-items 33903` (flags copied from the
dragon ham, client 3583; mode replace keeps server id 32084), then set `ownLook = true` in `store_food_config.lua` and run
`install_store_food.py` again. Until then the item shows the dragon ham's look.

## Themed sets, auras and grounds (things_custom24, `tools/sprites/gen_theme_art.py`, `art_import/theme*`)
**On windows-assets (407ad9b6, owner approved 2026-10-13); switches on since 2026-10-13 (pair 24 at 407ad9b6).** Our own art for the themes of five reference sheets and four set showcases the owner
showed: ten equipment sets, two auras, a pair of wings, four grounds with borders, six monster recolours. The sheets
were looked at for themes, palettes and silhouettes only. No pixel of them was copied, traced, cropped, recoloured or
resampled, no image code read them and none was sent to a painting service. The item icons are PixelLab paintings
(2026-10-13, below); auras, wings and grounds are drawn in Python: shape masks and material ramps lit from the upper
left, 128 px downsampled 4:1 for grounds (`darklib.py`), the class effect canvas for auras and wings
(`gen_class_fx.Canvas`). The same pair also carries the rift rank variants, the pack effect cuts and the large spell
effects and, as its last step, the bigger guardians (their sections).
- Modules: `theme_items.py` (the 18 kind drawers and 10 motifs), `theme_sets.py` (set names, materials, shapes, the
  class kits), `theme_grounds.py` (textures, rims, the dark set's border geometry, `pieces_for`, preview scenes),
  `theme_cosmetics.py` (auras, wings, placement), `theme_recolour.py` (variants of our own monster looks).
- Items (client 33660-33851, 192): six full sets of 18 pieces (sword, axe, club, bow, crossbow, wand, rod, shield,
  helmet, armor, legs, boots, amulet, ring, backpack, spellbook, arrow, bolt): Cryptbone (bone and grave iron, green
  soul fire), Voidmourn (black rift steel, blue glow), Wildroot (wood, leaf, bronze), Moonsilver (silver, night blue,
  crescent), Sunsworn (gold, crimson, ruby), Oathsteel (steel, red cross). Four kit sets of 21 pieces: a melee kit
  (warhelm, plate, greaves, sabatons, blade, bulwark), a caster kit (hat, robe, kilt, slippers, staff, grimoire), a
  ranged kit (hood, jerkin, leggings, striders, longbow, arbalest) and a shared amulet, ring and backpack: Rimeglass
  (blue ice crystal), Emeraldine (gold, emeralds), Starwing (winged gold, teal stones), Thornwild (green leaf, orange
  wood, green glow). Same client and server ids and transmog sets as the procedural build they replace. Dat flags
  copied from a stock item of each kind (`copy:`), so slots, stackable and container stay stock. Arrows and bolts:
  one painted piece each, the 8 stack patterns (1, 2, 3, 4, 5, 10, 25, 50 pieces) made by `theme_items.py`.
- Item painting (owner approved the subscription, then the US$ 25 credits): PixelLab "Create image (Pro)"
  (`/generate-image-v2`), style A: classic 32x32 icons, near-black 1 px outline, light from the top-left. One text
  prompt per piece or per pair of pieces (two side by side on a 64x32 canvas), the set's palette (`theme_items.M`
  ramps, at most 24 colours) and one stock item of our 10.98 pair as style reference. 110 calls, 1,100 generations
  of the subscription, 2,624 candidates; the credits were not touched. Every call is logged (prompt, size, seed,
  reference, usage); `art_import/theme_items_prompts.csv` keeps the job of every piece. Raw candidates stay outside git.
- Picks: a deterministic score ranks the candidates (dark outline share, size against a target per kind, art cut
  by the cell edge or the pair's split line, specks left out, colour count); an eye pass over the shortlists chose
  another candidate for 129 of 192 pieces, 8 of them from the first style round (`art_import/theme_items_picks.csv`,
  column `by`). `gen_theme_art.py items-import --raw RAW` runs `item_post.py` on the picks (alpha 0 / 255, biggest
  blob, at least 1 px margin, area averaging for shrinks under 0.85, a dark rim, palette clamp to 24 colours) and
  writes `art_import/theme_items/<set>.png`; a rerun gives byte-identical strips. `item_post.py --check
  art_import/theme_items` checks them cell by cell. `build` reads the committed strips, never the raw results.
- Variants (a proposal, not in the pair, not wired): `item_forge.py` recolours every base piece as rare (sapphire),
  epic (amethyst, white cross glints), fire, ice, poison and void (a deep violet ramp of our own). `build` writes
  `art_import/theme_variants/<set>.png` (one column per piece, one row per variant) and `art_import/theme_variants.csv`
  with a proposed use: rare and epic as drop tier looks, the four elements as element transmog styles.
- Learning: `item_forge_learn.py --own art_import/theme_items` adds the picks to the forge's statistics (source
  `pixellab-own`) and three parts cut from them (`item_forge_data/parts.csv`: a winged helm, a crescent round shield,
  a skull club).
- Grounds (client 33852-33903, 52): swamp (walkable, speed 170), acid pool, lava, deep water (blocking, 8 phases of
  160 / 180 / 200 ms, synchronised; lava and acid give light), each a 4x4 pattern ground and 12 border pieces with
  the same phases. A piece lies on the lower tile next to the family, carries its texture at that tile's world
  position and a rim: stone lip (acid), basalt crust (lava), mud bank (water), dark fringe (swamp). The edges are
  periodic in the world coordinate (`gen_dark_tiles.border_mask`), so pieces meet. Checked by the build: grounds
  opaque, every piece continuous along the edges it continues.
- Outfits 2185-2187: Blood Vortex aura (three blood streams spiral round the feet), Rune Seal aura (two rings, turning
  runes, a six-point star, motes), Runic Wings (pale feathers, blue runes, a slow beat). 3x3, 4 directions, one frame
  group of 8 phases, `animateAlways`. Auras: 2 layers (back, front: the art north of the centre line goes behind),
  displacement 17,17: the scan (`fix_pair_warnings.py --scan-aura-displacement`) puts them at -3.2,-5.0 and
  -3.4,-3.9 px, inside the stock ground auras' range. Wings: no displacement, art centre -14.5,-21.3 px, inside the
  stock wings' range.
- Outfits 2188-2193: frost, venom and void recolours of our rift looks 2108 (skeleton) and 2104 (hound): hue of the
  saturated pixels moved to the variant's, values kept, the rest lightly tinted; same frame groups and timing.
  `gen_theme_art.py recolour` reads them from the pair, so it is a second spec and step.
- Deterministic for Pillow 12.3.0 and numpy 2.5.3 (CI pins them, like gen_class_fx.py). CI: `build --check` in the
  checks job, `recolour --check` on the live pair in the live-pair job.

```
python3 -I client/tools/sprites/gen_theme_art.py build
python3 -I client/tools/sprites/gen_theme_art.py recolour --dat things_custom23/Tibia.dat --spr things_custom23/Tibia.spr
python3 -I client/tools/sprites/import_art_things.py --ours-dat things_custom23/Tibia.dat --ours-spr things_custom23/Tibia.spr \
    --out-dir S1 --things client/tools/sprites/art_import/theme_things.csv --first-item 33660 --first-outfit 2185 \
    --expect-items 33659 --manifest-out server/data/items/theme_items.csv
python3 -I client/tools/sprites/import_art_things.py --ours-dat S1/Tibia.dat --ours-spr S1/Tibia.spr \
    --out-dir S2 --things client/tools/sprites/art_import/theme_recolour.csv --first-outfit 2188 --expect-items 33903
python3 -I client/tools/sprites/import_art_things.py --ours-dat S2/Tibia.dat --ours-spr S2/Tibia.spr \
    --out-dir S3 --things client/tools/sprites/art_import/rift_variants.csv --first-outfit 2200 --expect-items 33903
python3 -I client/tools/sprites/import_fx_art.py --ours-dat S3/Tibia.dat --ours-spr S3/Tibia.spr --out-dir S4 \
    --spec client/tools/sprites/art_import/pack_fx.csv --expect-first-effect 628 \
    --lua-out server/data/lib/chaos_pack_fx_ids.lua --catalog-out server/data/spells/pack_fx_catalog.csv
python3 -I client/tools/sprites/import_fx_art.py --ours-dat S4/Tibia.dat --ours-spr S4/Tibia.spr --out-dir S5 \
    --spec client/tools/sprites/art_import/big_fx.csv --expect-first-effect 635 \
    --lua-out server/data/lib/chaos_big_fx_ids.lua --catalog-out server/data/spells/big_fx_catalog.csv
python3 -I client/tools/sprites/import_art_things.py --ours-dat S5/Tibia.dat --ours-spr S5/Tibia.spr \
    --out-dir things_custom24 --things client/tools/sprites/art_import/big_bosses.csv --first-outfit 2208 --expect-items 33903
python3 -I client/tools/sprites/check_pair.py things_custom24/Tibia.dat things_custom24/Tibia.spr \
    --old things_custom23/Tibia.dat things_custom23/Tibia.spr
python3 -I client/tools/sprites/gen_theme_art.py preview --out PREVIEWS --dat things_custom24/Tibia.dat --spr things_custom24/Tibia.spr
```
`import_art_things.py` knows the otb group and flags of the 18 kinds (OTB table; old rows unchanged). The pack and big
effect strips must be on disk (`gen_pack_fx.py build --src SET`, `gen_big_fx.py build`; both `--check` OK).
Input things_custom23 (the windows-assets archive at c91dd6f9, sha256 a866a48e... checked against SHA256SUMS.parts;
dat 8ca5332525db229ca0472fe292653986, spr 09f3a073b0a071d54b9604a422a9dffd). Output **things_custom24** (2026-10-13,
rebuilt with the bigger guardians; replaces the guardian-less build of the same name, dat 54864ed6..., spr
83ea0f2a..., and the procedural-item build before it, neither pushed): dat 734dda1f0dbabb247c3710f809fe5324
(5,037,907 bytes), spr fb385bf2d0214c37c594bda64c3d190b (634,416,681 bytes, 762,960 sprites, 17,307 appended),
33,903 items, 2,212 outfits, 655 effects, 153 missiles. New: items 33660-33903, outfits 2185-2193 (themed),
2194-2199 (blank padding), 2200-2207 (rift rank variants), 2208-2212 (bigger guardians), effects 628-634 (pack cuts),
635-655 (large effects). S5 is the guardian-less build (its md5s above). The guardian step: 5 outfits, 0 blank,
3,840 sprite slots pixel-identical to the art, 2,772 distinct sprites (2,769 appended, 3 reused).
Built twice with identical md5s and identical ids files; each importer verified its new frames pixel-identical to the
art and every old thing byte-identical. `check_pair.py --old`: 0 errors (36,524 old things and 745,653 old sprites
compared), 124 warnings: the 121 of things_custom23 line for line plus `size-large` for the three 9x9 effects 637,
642, 643 (expected; "Large spell effects"). The guardians add no warning (INFO `sprite-zero-slots` 4,041 -> 4,046).
- `things-1098.tar.xz` like things_custom23's (Tibia.dat and Tibia.spr at the root, owner 0/0, GNU tar, `xz -9 -T3`),
  mtime 2026-10-13 17:00: sha256 b1dbdf8d809e2a981955691439650978ad1a9562dc3a8830e0a6d35911e31e80 (72,714,268 bytes), packed
  twice with the same sha256. It unpacks to the md5s above; the same
  command on things_custom23 gives its published sha256 (a866a48e...). Pushed to windows-assets at 407ad9b6 (owner approved 2026-10-13; the archive's sha256 checked, it unpacks to the md5s above).
- Server side: server/README.md "Themed sets, auras and grounds" (switch `ChaosThemeArt.PAIR24`, on since 2026-10-13 (pair 24 at 407ad9b6)). A
  client on things_custom23 draws nothing for the new ids. The pack, big effect, rank variant and bigger guardian
  switches are on since the same day. The client has no switch of its own for this pair: it draws whatever the pair
  holds.
- Checked offline only (contact sheets, inventory slots at 1x and 4x, an equipment panel per set, the variants, the new effects frame by frame, the auras and wings on looks 128 and 2073 in four
  directions by the client's draw rule, ground patches, everything read back from the pair). Not run in a client.

## Leaderboards: fastest-time boards with class tabs (`game_leaderboard`)
Boards of mode "min" (the Cinderheart's fastest kills) come with `format = "time"` (values shown m:ss,
`TabRows.valueText` in `tabrows.lua`, tested by `tabrows_test.lua`) and `byClass = true`: the class tabs of the ladder
show on that weekly board too, "All classes" first; the chosen class is kept per window (`classGroup`) apart from the
ladder's class. Server: server/README.md "Leaderboards".

## OFL fonts (`fonts-src/`, `tools/make_ofl_fonts.sh`, `tools/make_fonts.py`)

The client ships bitmap fonts made from four free fonts under the **SIL Open Font License 1.1** (OFL), all from the
google/fonts repository (commit bd8f81ddb5c74d5c8897b36ad88b440266245103, 2026-10-09). `client/fonts-src/<Family>/`
holds the font file used, its `OFL.txt` and a README (source URL, version, upstream commit, SHA-256):

| Family | File (version) | Bitmap fonts | Role (`ChaosTheme.fonts`) | Used for |
|---|---|---|---|---|
| Cinzel | Cinzel-VariableFont_wght.ttf (2.000), weight 700 | `chaos-title-15px` (shadow) | `title` | every Chaos-skinned window title |
| | | `chaos-splash-20px` (outline + shadow, glyphs space..Z) | `splash` | the login "PRESS ANY KEY TO START" |
| | | `chaos-display-16px` (antialiased border + shadow, glyphs space..~) | `display` | the login scene's place name |
| Alegreya SC | AlegreyaSC-Bold.ttf (2.003) | `chaos-subtitle-16px` (shadow) | `subtitle` | Codex page title, the item on the crafting bench |
| | | `chaos-heading-14px` (shadow) | `heading` | Codex section headings, the NPC's name in the dialogue bubble |
| IM Fell English | IMFeENrm28P.ttf (3.00) | `chaos-dialogue-15px` | `dialogue` | what NPCs say in the dialogue bubble (`game_npctalk`) |
| Alegreya Sans | AlegreyaSans-Medium.ttf (2.004) | `chaos-body-13px`, `chaos-body-12px` | `body` (off) | trial body font: Codex paragraphs, only when switched on |
| | | `chaos-outline-12px`, `chaos-outline-11px` (antialiased border) | `outline`, `outlineSmall` | text straight over the game picture: the login scene's monster names (11); 12 for later uses |

Everything else keeps the stock Verdana. `client_chaos_theme`: `ChaosTheme.font(role[, fallback])` gives the role's
font name when that font is loaded, `ChaosTheme.applyFont(widget, role)` sets it (nothing changes without the font).
The `body` role is off unless the setting `chaosBodyFont` (g_settings) names one of its fonts:
`modules.client_chaos_theme.ChaosTheme.setBodyFont(true)` (13 px), `('chaos-body-12px')` or `(false)`, e.g. from the
terminal; the Codex uses it from the next page it shows. The bitmap fonts are named by role, not family: the OFL does
not let a modified (converted) font use a Reserved Font Name, and IM Fell's own copyright string reserves "IM FELL
English Roman".

**Bordered fonts** (`--border`, 2026-10-13): text drawn straight over the game picture needs a dark rim to read on
light and dark ground alike. `make_fonts.py --border R` draws an antialiased round border of R pixels (a fraction is
fine) from the glyph's own antialiased mask: each pixel's coverage spread over a 4x4 block, the maximum over a disc
of 4R sub-pixels, averaged back (box), so the ring is never wider than R, has soft edges and round corners and stays
aligned with the hinted glyph (the older `--outline N` grows by whole pixels with a square step). `--max-cell-width N`
squeezes the few glyphs wider than the cell (the per mille sign and the em dash) horizontally, so they do not decide
the cell of the whole sheet: with it the 11 and 12 px bordered sheets keep a 256 slot of the font atlas. The three
sheets take 3 slots of 256: the room comes from `var-cip-font-wheel.otfont`, a second atlas copy (512 slot) of the
Verdana Bold 11 wheel sheet under the name `$var-cip-font-wheel`, which nothing looks up (the styles' value
`$var-cip-font-wheel` is resolved to `Verdana Bold-11px-wheel` by the UI before the lookup, no Lua names it), now a
copy of `Icon-VBold-11px` like the other replaced fonts. `--atlas-check` on the assembled client: 35 fonts, 96.9%
used, 2 slots of 256 free; the Linux client agrees (`g_atlas.getStats()` font part `0 0 0 2 0 0 0`, all three fonts
loaded). So the "one 256x256 slot free" below is two now. Tests: `make_fonts_test.py` (disc, ring pad, squeeze, a bordered render: white ink, dark
soft ring, nothing wraps round the cell).

**Licence.** The OFL allows bundling the fonts and fonts made from them with the game (free or sold) if every copy
carries the copyright notice and the licence, the fonts are never sold by themselves and stay under the OFL. So
`data/fonts/chaos/OFL-<Family>.txt` ships with the client, the login screen's Credits box and the README name the
fonts and their authors.

**Regenerate:** `bash client/tools/make_ofl_fonts.sh` (sizes, weights, outline/shadow and space widths are in it; it
writes `overlay/data/fonts/chaos/` and copies the licence texts). `tools/make_fonts.py` turns a TTF/OTF into OTClient
bitmap fonts (`<name>-<size>px.png` glyph sheet + `.otfont`): white glyphs (the client tints them), optional outline
and baked shadow, `--weight` for a variable font, `--space-width`, glyphs 32..255 by default (`--first/--last/
--encoding`, `--tight`); each glyph's advance is kept with an invisible marker pixel (the client measures a glyph by
its last non-transparent column, and the outline and a right shadow are taken back by the `.otfont` spacing). Tests:
`tools/make_fonts_test.py` (CI). A local override: `.otfont`/`.png` pairs in the git-ignored `client/local-fonts/`
replace the shipped ones of the same name (`tools/assemble_client.sh`).

**Characters.** The client draws a string byte by byte: byte N is glyph N of the font (`BitmapFont`, glyphs
first-glyph..255 laid out row by row from the sheet's top left, as in the stock 16x14-cell `_cp1252` Verdana sheets),
and a byte past the sheet has no glyph and is not drawn. There is no UTF-8 in the text path: typed text comes in as
Latin-1, servers send Latin-1. So every Chaos font holds the printable cp1252 range 32..255 (á é í ó ú â ê ô ã õ ç à ü
ñ and the capitals, º ª « » ¿ ¡ ° ± × ÷ © ®, and cp1252's € ‚ „ … ‘ ’ “ ” – — ™ • Œ œ in 128..159; the no-break space
advances like a space, the soft hyphen is a hyphen, 127 and the five bytes cp1252 leaves undefined stay empty), except
the splash (space..Z: with the accented capitals it would need a 512 slot). Accented capitals reaching above a font's
line box get room: the dialogue text sits 1 px lower (line 20 -> 21 px), the trial body font 1 / 2 px lower (13 px:
line 14 -> 16, 12 px: 13 -> 16), title, splash, subtitle and heading draw ASCII exactly as before (same pixels in the
client; the heading's one-line text box is 1 px shorter, `--tight`). Server scripts saved as UTF-8 (many base NPC
lines, e.g. "isn´t", "jalapeño") sent "Ã§" for "ç" in every font: base patch `0028-utf8-server-text-to-cp1252.patch`
(`InputMessage::getString`) turns a server string that is valid UTF-8 with non-ASCII characters into cp1252 (a
character cp1252 lacks becomes `?`); Latin-1 text and anything not valid UTF-8 pass unchanged. UTF-8 in the client's
own .lua/.otui text is not converted (keep it ASCII).

**The font atlas.** The client copies every bitmap font into one 2048x2048 texture (framework `Atlas::cacheFont`, a
power-of-two buddy allocator; out of space is a fatal error at start). `make_fonts.py --atlas-check DIR` replays it;
like the client (`FontManager::importFont`) it skips a font whose name is loaded already. The stock fonts leave 2
slots of 256x256, not enough, so the overlay replaces nine stock fonts nothing uses (`data/fonts/Verdana-Strikethrough
-11px.otfont`, `Verdana-11px-italic.otfont`, and `Verdana Bold-10px.otfont` / `Verdana Bold-11px-low-space.otfont`,
the `vbot-verdana-11px-*` fonts of the removed bot; and, for the full glyph range, `Verdana-8px.otfont`,
`Verdana-8px-antialiased-espaco.otfont` ("Verdana 8px-anti-espaco"), `verdana-9px-italic.otfont`,
`terminus-10px.otfont` (only the removed bot used it) and `var-cip-font.otfont` ("cipSoft", a second atlas copy of the
Verdana 11 sheet): no module, style or engine code names them) with a copy of `Icon-VBold-11px`, which then loads
once: their sheets never reach the atlas, however the overlay is copied in. The Chaos sheets with glyphs 32..255:
title, subtitle and dialogue take a 512 slot each, heading, both body sizes and the splash a 256 slot each. The atlas
keeps one 256x256 slot free (1.6%): measured in game, `g_atlas.getStats()` font part `0 0 0 1 0 0 0` (free per slot
size 32..2048), and `--atlas-check` agrees; without the five new replacements the sheets do not fit (`--atlas-check`)
and the client would stop at start ("[Atlas] Out of space for new fonts"). `assemble_client.sh` prints the check. Any
new sheet must fit that one slot (a 256 slot holds 224 glyphs of at most 16x18 px, or fewer glyphs: `--last 90`, as
the splash) or a stock font must make room.
Checked in the Linux build at 1280x720 and 1920x1080 (login splash, Codex, crafting bench, achievements, NPC bubble).
Glyphs 32..255 and patch 0028 checked in the Linux client at 1280x720: every role with accents and cp1252 symbols, the
ASCII lines compared pixel by pixel with the previous sheets, a server modal dialog (title in the title font) and an
NPC line in the bubble's style through `InputMessage::getString` (no server: the bytes were fed in from Lua).

## Sharded sprites (new, base patch 0048, `tools/sprites/spr_shards.py`)
The 600 MB `Tibia.spr` can ship as shard files that the client reads on several threads and the updater replaces one
by one (client/BASE.md 0048; docs/LAUNCH.md "Client updates").
- **Files** in `data/things/1098/`: `Tibia.sprshards` (text index: format line `chaos-spr-shards 1`, signature, sprite
  count, shard size, then one line per shard: first id, count, file name, size, SHA-256) and `Tibia.000.spr` ..
  `Tibia.045.spr`. Each shard is a normal `.spr` with a u32 count holding 16384 sprite ids (the last one the rest),
  its records byte for byte as in the single file. Ids are cut by range, not by bytes: new sprites are appended at the
  end of the pair, so an import changes the last shard (and adds new ones), not all of them. A record two ids share
  stays shared inside one shard and is copied when the ids fall in two shards.
- **Tool**: `python3 -I client/tools/sprites/spr_shards.py split Tibia.spr OUT_DIR [--per-shard 16384]` (deterministic:
  same input, same bytes; removes shard files of an older split), `verify Tibia.spr OUT_DIR` (every record of every id
  byte-identical to the single file, empty ids included, the index's sizes and SHA-256, and the shards joined in
  memory compared by MD5 with the single file), `check OUT_DIR` (the index alone), `join OUT_DIR OUT.spr`. Tests:
  `spr_shards_test.py` (CI). On things_custom23: 745,653 sprites into 46 shards (571.9 MB, largest 29.1 MB) in 5.7 s,
  verify 5.0 s, joined MD5 09f3a073b0a071d54b9604a422a9dffd = the single file's; a second split gave the same bytes.
- **Assembly**: `tools/assemble_client.sh <base> <out> <things-dir>` copies the dat and splits and verifies the spr
  (`CHAOS_SPR_SHARDS=0` copies the single file instead); without the third argument the pair is left to you as before.
  The Windows package keeps the single `Tibia.spr` for now (owner decision, 2026-10-13): its map editor reads the
  sprites from `client\data\things\1098`, and a client loads the single file when there is no index. Shards reach
  players through updates only.
- **Loading**: the index wins over `Tibia.spr` when both are there; a broken set (missing or short shard, bad index)
  falls back to `Tibia.spr`. Measurements: client/BASE.md 0048 (load already took only milliseconds, since the engine
  streams sprite records; sharded it blocks for about 1.6 ms against 6.4 ms cold).
- **Updates**: `make_update_manifest.py` lists every shard as its own file and checks the set before publishing (index,
  sizes, headers, each shard's SHA-256 against the index). It refuses a shard set next to the single `Tibia.spr`
  (players would download both; `--with-single-spr` ships both on purpose) and a shard set without `--min-package`
  (a client built before 0048 ignores the shards and would draw a new dat with its old spr). It warns when it publishes
  a single `Tibia.spr` with no shard set: a client whose install has an index keeps loading its shards.

## Signed updater (new, `client_chaos_updater`, base patch 0031)

Before login the client fetches a signed manifest from the website, compares SHA-256 hashes, downloads what changed
in parallel, checks every file and applies the whole update at once. Operator side: docs/LAUNCH.md "Client updates";
website side: website/README.md "Client updates".

**Trust.** `manifest.json` is an envelope `{format, key, signature, payload}`; `payload` is the manifest's JSON text and
the Ed25519 signature covers its exact bytes. The public key is in `init.lua` (`Services.update.publicKey`, not
updatable by an update); the private key stays with the operator (`tools/make_update_manifest.py keygen`, refused
inside a git work tree). The client refuses: a missing or bad signature, another key, a manifest older than the
version it applied (no replay of an old signed manifest), another product, and any path that is absolute, has `..`,
`.` or an empty segment, a backslash, a colon, a Windows device name, a character outside `[A-Za-z0-9 ._()+,-]` or
lies outside `modules/ mods/ data/ layouts/`, or names native code (`.exe .dll .so .dylib .bat .cmd .ps1 .sh ...`).
Files are fetched by hash (`files/<xx>/<sha256>`) and each one's SHA-256 must match before it counts. The C++ helpers
write only inside `chaos_update/` of the write dir (`chaosupdate::isSafeUpdatePath`).

**Native code is never downloaded.** Choice: binary (exe/DLL) updates go only through the Windows package
(`windows-package.yml`), not through a staged swap by a launcher. Reasons: a launcher that replaces the running exe is
new native code that itself cannot be updated safely, Windows locks the running exe and DLLs (swap logic and rollback
on a half-written exe are where updaters brick installs), antivirus tools flag self-replacing executables, and the
signing key would then be able to run arbitrary native code on every PC instead of the Lua the client already
sandboxes to its modules. An update that needs a new exe sets `min_package`: older packages show "A new client
download is required" (with `Services.update.download`) and cannot log in.

**Flow.**
1. `init.lua` (patch 0031) runs `bootstrap.lua` before `g_modules.discoverModules()`: when `chaos_update/state.txt` says
   `status=ok` for this client package (hash of `init.lua` and the build date/commit), `chaos_update/files` is mounted
   in front of the client's own folder. A half-applied update (`status=applying`) or a tree made for another package
   is not mounted: the client starts with its own, consistent install files.
2. On the login screen (`autoload-priority` 1110, after `client_chaos_login`) a Chaos-styled panel over a dimmed screen
   blocks the login (`EnterGame.doLogin` is guarded) while it: fetches the manifest (`?t=` against caches), checks the
   signature and the payload, hashes the files the client sees (time-sliced, 12 ms per frame, with a cache of
   real dir + path, mtime and size in `chaos_update/hashcache.txt`), and decides per file: keep, download, or drop a stale
   tree copy that hides a right install file.
3. Download pool (`updater_core.lua` `M.download`): N requests at once (`parallel` in the manifest, default 4, the client
   setting `chaos-update-parallel` wins, 1..8); one blob per distinct hash, largest first; a blob over 8 MB goes in
   8 MB `Range` parts that run in parallel too (the 570 MB `Tibia.spr` does not sit on one connection), each part a
   file `<sha>.c<i>`, so an interrupted run resumes with the parts it has; a server ignoring `Range` answers 200 with
   the whole file (up to 512 MB, the engine's body limit). Each request retries 5 times with backoff 0.5, 1, 2, 4,
   8 s; a blob's SHA-256 is checked as soon as its last part is on disk, a mismatch deletes it and refetches it (5
   tries), then the update is refused. Progress: files done / total, bytes done / total across all requests (parts
   in flight counted by their percent), speed, parallel count.
4. Apply only when every blob is in and verified: `state.txt` `status=applying`, stale and dropped tree files removed,
   staged blobs renamed into `chaos_update/files/<path>` (copied for a second path with the same content), then
   `status=ok` with the new version. Then the client restarts (`g_app.restart`; if that fails it asks the player
   to start it again).
5. Fallback: server unreachable, or the update refused: "You can play with the current files" with Retry and Play,
   unless `Services.update.required`, a `min_version` above the applied version, or a `min_package` above this package.

**Files.** `updater_core.lua` (no client API: a linear JSON decoder (corelib's `json.decode` builds strings by
repeated concatenation and took minutes and gigabytes on the 0.8 MB manifest), paths, envelope, manifest, diff,
pool, apply; `updater_core_test.lua`, 192 checks, LuaJIT and Lua 5.3, fake HTTP server and disk), `bootstrap.lua`, `updater.lua` + `updater.otui` (panel),
`signature_vectors.lua` (`ChaosUpdater.selfTest()` runs them through `g_crypt` in the client).
Tools: `tools/make_update_manifest.py` (keygen / build / verify; `cryptography` when installed, else
`tools/ed25519_ref.py`, the RFC 8032 reference code), `tools/make_update_manifest_test.py`, `tools/chaosupdate_test.cpp`
(native vectors), `tools/set_update_config.py` (writes `Services.update` into an assembled `init.lua`),
`tools/serve_updates.py` (local test server: ranges, per-connection rate, latency, dropped connections; tests only).
CI (`ci.yml`): the Python tests, an unsigned dry run over the overlay, the C++ vectors, the Lua tests;
`windows-package.yml` dry-runs the real package folder (dat/spr included).

**Tested in the Linux client** (base patches 0001-0029 + 0031, 1280x720, `tools/serve_updates.py` over plain HTTP on
127.0.0.1; production is HTTPS). Manifest of the whole client: 5741 files, 802 MB, Tibia.spr 563-570 MB.
- Up to date: the first check (no hash cache, Tibia.spr hashed) answered in about 8 s after start; later checks in
  about 1 s. A module file changed by hand was found, fetched again, applied, and the client restarted itself
  (`g_app.restart` works on Linux) with "update 1 mounted".
- Update applied: update 2 (new Tibia.dat/.spr pair, the login background, a module, a new file; 551.6 MB in 6
  files) downloaded, applied, restarted; the new background shows, the module's log line appears, the client reads
  `Tibia.dat` from `chaos_update/files` (same SHA-256 as the new pair) and `g_things.loadDat` loads it.
- Tampered file (same size, one byte changed on the server): five tries, then "Update refused
  (data/update_test/marker.txt: hash mismatch (file refused))"; state and files stay at update 2, staging empty.
- Bad signature (one file's hash swapped in the payload, old signature kept): "Update refused (bad signature)",
  nothing downloaded.
- Offline: "Update server unreachable", Retry / Play; with `required = true`: Retry only, `EnterGame.doLogin` refused.
- Interrupted: the client killed with 33 of 70 parts on disk; the next start fetched only the missing parts, while
  the server cut every 9th response mid-body (each retried and finished).
- `ChaosUpdater.selfTest()` in the client: RFC 8032 vectors, the manifest vector and SHA-256 all pass.

Download time of update 2 (551.6 MB), 1 request at a time against the default 4 (the test machine was shared and
loaded, about 14 on 4 cores, so the client itself tops out near 24 MB/s):

| Server link (per connection) | 1 at a time | 4 parallel (default) | 8 parallel |
|---|---|---|---|
| 4 MB/s, 40 ms latency | 171.6 s | 54.6 s (3.1x) | |
| 16 MB/s, 30 ms latency | 61.0 / 65.9 s | 22.0 / 30.5 s | 35.6 s |
| unlimited (local) | 22.8 / 32.7 s | 23.9 / 20.5 s | |

Parallel requests pay off whenever one connection is slower than the client can write and hash; on a fast local
link the client's own copy and hash work is the limit and more requests change nothing.
Screenshots of the runs: `01-up-to-date`, `02-downloading`, `02-update-applied`, `02-after-restart-update-loaded`,
`03-tampered-file-refused`, `04-bad-signature-refused`, `05-offline-fallback`, `06-offline-required-blocked`,
`07-download-progress` (kept outside the repository with the test session's files).

## Display scale (new, `game_chaosscale`; server/README.md "Display scale", server src-patch 0037)
Every combat number a player sees is the internal number x the factor of the player's own level (x1 up to level 100,
x1000 at level 1000, x10000 from level 1500; a whole number). The server sends those numbers already scaled: the damage
and heal numbers above the map and in the Server Log, the own health and mana (HUD plate, health info, top bar), the
energy shield bar, the DPS meter and combat log, the death recap, party frames, the hunt tracker, damage boards, the
bestiary's monster health and the spellbook's mana costs. The client needs the factor only for what it works out itself:
`game_chaosscale` keeps it (opcode 157) and sets the flat mana cost of every spell in `SpellInfo` to the raw cost x
factor (kept in `chaosRawMana`; a cost in percent of max mana is left to `game_chaosspells`, which follows the scaled
max mana), so the action bar greys a spell out at the right shown mana. The module is sandboxed and puts `ChaosScale`,
`chaosDisplayFactor()` and `chaosDisplayValue(n)` in `_G`.
- Item tooltips (`game_itemtooltip`): the server scales an item's flat health / mana / damage / heal rows by the factor
  of the item's level requirement and sends it as `ds`; the stats rows it scaled carry `sc`. The Ctrl compare view
  (`tooltiplogic.lua` `L.diff`, `L.toScale`) brings the worn item's `sc` rows to the hovered item's `ds` before taking
  the difference, so items of different levels compare by their real numbers (`tooltiplogic_test.lua`).
- Units: the short numbers of `client_chaos_numbers` already write k / M / B / T (2.6M, 4.29B; `numbers_test.lua` has the
  scale's range). The DPS meter (`dpsmath.lua` `DpsMath.short`) and the hunt tracker (`huntmath.lua` `HuntMath.short`)
  wrote "kk" / "kkk"; they now write M / B / T like every other number (73.4M, 4.2B).
- Checked in the Linux client against a live server (src-patches 0001-0037): at level 1000 "2.6M" / "1.8M" above the
  target, "A rat loses 2.6M hitpoints due to your attack." in the Server Log, health 15.9M, the DPS meter at 3.5M DPS; at
  level 100 the internal numbers (260, 180, health 2.47k); a lost level and a reattach brought the factor back.
