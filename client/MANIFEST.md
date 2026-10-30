# Client module manifest

Status of every requested module. **Nothing here has been run.** The session that assembled it had no OTClient runtime, so "loads" means "the code looks self-contained", not "tested".

Layout: `overlay/modules/<name>` is copied into the client's `modules/` folder; `overlay/data/images/...` into its `data/images/`. Some of these were under `mods/` originally; they were all moved to `modules/` here, so check `autoload` and `autoload-priority` in each `.otmod` when wiring them in.

Timers (O197): a `cycleEvent` / `scheduleEvent` under 100 ms runs only while its window, effect or animation is visible and is removed on hide and in `terminate`; the login animation, event marquees, cosmetic effects and look previews sleep when idle.

Protocol target is 10.98 on the base server (TFS 1.4.2). The sources are mostly 8.60 or 12.x+ clients, so the real risk is the client engine (C++ API) and the server contract, not the Lua.

| Module | Server contract | Client-engine needs | Verdict |
|---|---|---|---|
| game_stash | extended opcode 110 + Economy > Supply Stash | none after port | Ported off `client_manager`; replaces the base client's own stash. The one item storage (server/README.md "Stash"): any item can be dropped in (whole items with their attributes, plain stacks merged), a whole item withdraws as one (`Redeem {row}`); O316 (the depot is retired): the tab bar (All, the one Stash tab of 30 slots plus the expansions bought, the old tabs 2-30 dimmed, the affinity tabs with their item as icon and name, Old depot; withdraw-only tabs dimmed, tooltips with the class, the owner source and why a tab is withdraw-only) from the server's `tabs` message, the slot line ("Stash: 12 of 55 slots (30 free + 1 expansions of 25)"), the **Buy Slots** button (opens the store at the category the server names, `tabs.store`, through `game_shop` `openCategory`) and the **Inbox** button (`CollectInbox`: the server moves the inbox into the stash, what cannot be stashed into the backpack; the label carries the count, greyed outside a protection zone); a `Toggle` with `closeLockers` closes the locker window the engine opened for a depot locker (`Stash.CloseLockers`); deposit and withdraw in town only unless remote deposit is unlocked (store or the Chaos Pact): the Stow Everything button greyed with a tooltip that says where to unlock and a refused drop says so (the window is 760 wide since O316); items greyed out with a tooltip outside a protection zone (the local player's Pz state, live while walking, or the server's hideout answer; `access` after a refusal); the Stow Everything button and its report box (`StowReport`). Logic `stashview.lua` (tested by `stashview_test.lua`). A drop returns true once it sent the deposit (2026-10-22: the base client offers a drop to every widget under the mouse until one returns true; the list and the window both answered false, so one drag sent two deposits of the same slot and the second took the item to the right), and the deposit names the item (`ItemId` = its client id, `Count`; `StashView.depositData`). Item tooltips fall back to `setTooltip`. **No flash on open (O316 follow-up, 2026-10-29):** two causes. (1) `Stash.Toggle` showed the window empty and the tab bar and list were rebuilt when the server answered: it now stays hidden (`Stash.opening`) and `Stash.Reveal` shows it once, when the last `addItems` packet is drawn, or after `StashView.REVEAL_MS` (1.5 s) without an answer (`StashView.revealReady`). (2) The engine opened the locker window and `CloseLockers` closed it a moment later: the server now names the depot lockers' client ids in `addCategorys.lockers` (while `depot.openStash` is on) and `Stash.OnContainerOpen` (`Container.onOpen`) closes a locker the moment it opens (again one cycle later if its window was made after the handler). Tested by `stashview_test.lua`. The tabs of before were tested in game; the whole-item stash and the no-flash opening are not run in a client yet |
| game_bank | extended opcode 60 | none | Server `bank.lua`. Gold tab only (the star tab is hidden: no star currency). Deposit all / Withdraw all; amount dialog with input, slider, 25% / 50% / All, OK / Cancel. Logic in `bank_core.lua` (tested). The toggle shows the window at once (this session's last state, else "-" until the reply) and raises it over later windows; a reply opens it only when asked for or already open (`B.onReply`), so a reopen inside the server's 300 ms rate limit no longer stays hidden and a late reply after a close does not reopen it. The banker NPC (`service_npcs*.lua`, 2026-10-20) opens it with an `npc` action (an open window stays open). The state is dropped at logout. |
| game_autoloot | extended opcode 216 (JSON: `open` / `add` / `remove` / `clear` / `sync` out, `open` / `list` back) | none | Auto Loot window; the list is the server's (`autoloot.lua`, base storages 80000+). It also takes over the item menu's base Quick Loot entries (`game_quickloot`, which talks Quick Loot packets a 10.98 server does not have; live test winpkg-35): "Manage Loot containers" opens the Loot Bag rules (`game_pouches`), "Add to Loot List" / "Remove from Loot List" edit the server list quietly (`quiet`, answer `list`, the window stays shut) |
| game_itemrarity | item custom attributes (server engine patch 0003, client feature 126 negotiated at login) | none (the engine already parses the attributes) | Rarity of an item from its custom attribute (keys `ChaosItemAttr`, same numbers as the server's `Chaos.itemAttr`), description tag as fallback; seven rarities (id-keyed, old ids alias onto them, README "Item rarities"); frame in the rarity colour (unique orange) on container and inventory slots; turns feature 126 off at logout. `itemrarity_test.lua`; tested in game. Soft rarity outline (base patch 0044, not built or run yet): at load it hands the engine one colour per rarity and the unique colour (`Item.setRarityOutlineColor`, alpha 225; `getRarityOutlinePlan` / `applyRarityOutline`, tested), a reach of 3 sprite pixels, no outline for Common, a breathing outline from Mythic up (2.2 s), and the Graphics options `rarityOutlineMap` / `rarityOutlineSlots` (`onOutlineOption`); the engine draws it around dropped items on the map and items in inventory and container slots. A client without 0044 has no `Item.setRarityOutlineColor` and nothing changes. `updateRarityFrame` also calls `game_shaderfx` (`onSlotItem`: grey a locked item; `onRarityFrame`: the shine) when that module is loaded **Stock value frames off in containers** (owner 2026-10-27, "alguns quadrados da bp ficam verdes e dourados"): the stock `ItemsDatabase.setRarityItem` frames a container slot by gold price (green from 1000, blue 10 000, purple 100 000, yellow 1 000 000) and skips the redraw when its cached clip looks unchanged, so potions and runes lit up green and emptied slots kept a yellow frame. On `Container` signals the module sets `drawRarity = false` on the items panel and resets every slot with the cache dropped (`silenceStockValueFrames` / `resetStockValueFrame`, tested in `itemrarity_test.lua`). Chosen: removed, not an icon; rarity frame and loot filter glow stay |
| game_battlepass | extended opcode 227 (JSON) + Adventure > Season Pass; toasts through `game_chaosnotify` (action `seasonpass`) | none | Replaced: the Chaos season pass window (Chaos skin, 760 x 560): tier, pass XP bar, Claim all; Rewards page (50 tier rows, free and premium reward with item / outfit / mount icon and Claim, locked / premium / claimed states), Challenges page (daily and weekly with progress and reset timers, the day's pass XP per source and cap), Packs page (premium pass and the three season packs: Buy, Upgrade for the difference, Gift to a character name with the receiving account's price). Server `data/scripts/chaos/seasonpass.lua` (server/README.md "Season pass"). The old raw opcode 39 window and its images are gone. Logic `passview.lua` (tested by `passview_test.lua`); tested in game with two clients |
| game_passivetree | extended opcode 65 (also `planApply` / `masteryChoose` out, `planResult` back; `sendNodes` carries `masteries`) | none | Needs server script. Paragon panel (`paragon.lua`, `paragon.otui`, `paragonmath.lua`) on the same opcode. Planner (`planner.lua`, logic `treeplan.lua` tested by `treeplan_test.lua`): a click plans the shortest path from the allocated set over nodes the class may take, planned nodes get the `checked` frame, plan bar with cost against free points, Undo / Redo (Ctrl+Z / Ctrl+Y) / Clear, Apply Plan sends the whole plan once. Mastery nodes: the effect choice window (`mastery.otui`), a saved one changes for the node refund price. Search box (`search.lua`, Ctrl+F): frames every node whose name or bonus text matches, Next / Prev centre the view, a match count. Read-only view of an inspected character's tree (`viewother.lua`, from `game_playerinspect`). Zoom levels cached as panel pairs (a step back to a built level creates no widget; `getTreeStats()`), zoom keeps the centre. Tested in game (server/README.md "Passive tree planner and mastery nodes"). Art: every node icon is a painted cell of the tree's own atlas `images/passivetree/skills.png` (the icon set that came with the tree); `client/tools/gen_keystone_icons.py` picks the cells of the medium and large nodes (one icon per node, none shared with a small node): the 27 path notables, the class section notables and masteries 665-668 and 619-623 are clipped from the atlas (`treedata/icons.lua` `nt*` / `ms*`, `--check` verifies the clips), the keystones are those atlas icons scaled once to the 64 px cells of `keystones.png`, and the class starts `classstart_<line>.png` are the root start medallion with the class icon in its centre; the old flat generated glyphs are gone. The twelve build archetype keystones (2026-10-12, server/README.md "Build archetypes") are cells 28-39 of `keystones.png`, named in `KEYSTONE_NAMES`; a keystone without a class list shows its own text lines too. The second round's four (Snarewright's Creed, Covenant of Vigils, Iron Tithe, Hollow Vessel; nodes 105, 99, 102, 96) are cells 40-43. The third round's eight (2026-10-20: Executioner's Verdict, Earthbreaker, Rampage, Last Stand, Longshot, Barbed Quiver, Opening Shot, Hobbling Shot; nodes 428, 409, 466, 523, 561, 542, 599, 447) are cells 44-51. The signature keystones of the Thief, Necromancer, Monk and Templar lines (2026-10-20: Shadow Twin, Viper's Verdict, Corpse Detonation, Reaper's Toll, Seventh Palm, Piercing Palm, Radiant Rebuke, Dawnchain; per-class variants of 621 / 624, now open to every class) are cells 52-59 (no painted icon yet). Rendered offline in the Linux client (read-only preview of each line). With "Painted icons" on, keystones and masteries use `painted_nodes.png` (`treedata/painted.lua`, "Painted icons" below). The "Boss points n/10" tooltip (`bosspoints.lua`) starts with where the kills come from: world boss events, pocket bosses (Adventure > Boss Spawns), the Trial Warden, the other spawns, party help (2026-10-15). Auto build (`autobuild.lua` / `.otui`, logic `autobuildview.lua`, tested by `autobuildview_test.lua`): dropdown of recommended builds and focus themes, preview in the tree, Apply and Reset and apply (opcode 65 `autobuild*`). The picked build's preview is asked for whenever none is shown (new pick, reopened window, after an Apply), asked again after 4 s up to 3 tries and on the server's "too fast" (`autobuildError {retry}`), then an error line instead of "Asking the server for a preview..." for good (`autobuild_test.lua` runs the window against a mocked client). Stat help (`statinfo.lua` / `.otui`, logic `statinfoview.lua`, tested by `statinfoview_test.lua`): Primary / Secondary line in the toolbar, gold / silver node borders only while the Stats panel is open (always on they framed nearly every node, so a tree with 0 points looked lit up; one border rule for search frames and stat marks, `applyTreeNodeBorder`), description lines in tooltips, Stats panel (`statInfo`). Saved allocation shown whole (2026-10-21): the nodes of `sendNodes` that connect to a start over the undirected links (`TreePlan.connected`, the server's rule), every `nodes.lua` link listed back at load (`TreePlan.linkBack`; 115 lacked 50 and 364 lacked 365, so a branch past them showed dim although saved), and the planner counts the saved ids as owned (`getTreeSaved`, `TreePlan.ownedIds`), so it never prices them; tested by `treelinks_test.lua` (every link on both ends, client links = server links, the server's path to every node of every class shown allocated). Node states: `on` = allocated, `checked` = planned, else dim; the state blocks use `$hover !on` / `$checked !on` (`!$on` is an unknown state to the engine and never matched). Toolbar (2026-10-20): a solid dark strip at the top (`toolbar`, 68 px); row 1 the free points and boss points as labels and the Primary / Secondary line (cut with "..." to the free width, the whole line as tooltip); row 2 the actions Apply Plan, Reset, Paragon, Build Code, Auto build, Stats, Trials and `game_loadouts`' Loadouts button, one width each (at most 150 px, centred), sized to the window by `layoutTreeToolbar` (maths `toolbarview.lua`, tested by `toolbarview_test.lua`), long labels wrap to two lines. Not yet checked in the client. Totals and Paragon Mastery (O146): `statTotals` (opcode 65) fills a TOTALS section of the Stats list (raw against effective points and percents past the soft caps, critical chance and damage including gear; `totals.lua`, lines `totalsview.lua`, tested by `totalsview_test.lua`), and the Paragon window gets a Mastery button (`paragonmastery.lua` / `.otui`, maths `paragonmasterymath.lua`, tested by `paragonmasterymath_test.lua`): ranks +1 / +10 / +100 per mastery (`paragonMastery`) and the exchange of free tree points (`paragonConvert`, asks first). Not yet checked in the client. Trials window: a Clear button per pair row gives a pair up (`trialChoose` side 0, same price as a switch, `trialsmath.lua` `clearCard`). Class lanes: `treedata/classlanes.lua` (generated by `server/tools/gen_class_lanes.lua`), merged by `treelanes.lua` (from `treedata.lua`): a re-skinned named node shows a name made from the stats the class gets ("Pyre Litany" is "Physical Damage and Vitality" for a Beastmaster; "Attribute" stays), in the tooltip, the search and the refund box (2026-10-20; tested by `treelanes_test.lua`, every node of every class). pt-BR (O147): the stat lines of a node, keystone / mastery / notable descriptions (joined, translated, wrapped again: `treetext.lua`, tested by `treetext_test.lua`), the class text of the Info panel and the Paragon lines go through `tr()` |
| game_shop | extended opcode 218 (JSON) | none | Chaos store: categories, pages, purchase, coin gifts, history; an offer shows the price the server sends, the old price struck through (`oldCost`), its tags (Sale / New / Featured / Bundle / Starter), "Owned." with the Buy button off, and a GIFT button when the server says it can be gifted (`giftoffer.otui`: a character name, then a confirmation; `buy` carries `gift`). The client never computes a price. **Donate** button: the donation window (`pay.lua`, `pay.otui`): the voluntary donation notice in English and Portuguese (cp1252 escapes; "nobody is required to donate, the game is fully playable for free"), under it the website's refund sentence (no refund except where the law requires one, not a purchase, no real-world value; "This was a voluntary donation, not a purchase..." once the order is paid or credited) with where the Donation Terms are (`page.php?plugin=chaos&p=legal&doc=donations` on the website, as text), the method (Pix (BRL) / PayPal (USD)), the packs with "Donate <price>"; then the QR code drawn with widgets (`qrcode.lua`: byte mode, level M, versions 1-40, one widget per dark run) of the Pix copy-and-paste code (sent as hex) or of the PayPal link (also opened with `g_platform.openUrl`), the code with a Copy button, a countdown, Cancel; it asks `pay_status` every 3 s and shows the thank-you when the server pushes `pay_paid` (toast `PayToast` + balance, no relog). Pure logic in `payview.lua` and `qrcode.lua`, tested by `payview_test.lua` (the notice and the refund sentences equal the server's, thank-you texts, "Donate" wording, countdown, hex) and `qrcode_test.lua` (block table, format and version bits, pinned matrices checked against an independent encoder and decoder). Server `data/scripts/chaos/shop.lua`, `shop_payments.lua` (server/README.md "Store"); tested in game Icons and previews (2026-10-17): an offer or category carries `look`, its own cosmetic (server README "Store", "Icons and previews"); `shopicon.lua` (`ShopIcon.plan`, tested by `shopicon_test.lua`) turns it into the icon: the creature with the outline on it (`game_cosmeticfx.applyOutline`; the glow picture when the engine has no `0038`), a footprint's print, the plate frame's plate (`game_nameplate/images`), a spell skin's or kill effect's main effect (`game_lookpreview.effectIcon`: the generated picture of `game_cosmetics/images/fx`, else the sprites), a colour sample; outfits, mounts, wings, auras, shaders, pets and bundles are creatures (a bundle wears its parts). Picking or hovering an offer shows `look` in the shared look preview: `LookPreviewCore.fromStoreLook` (outline, shader, mount, bundle parts, effects played on the stage, prints, a plate frame as a note); offers are `focusable` so the pick is kept. Cosmetic offers (server `cosmetics.lua`): a SHOW button in place of GIFT plays the effects for the buyer only (action `preview {category, page, offer}`), a chat colour tints the title, a label accent sits behind it The weekly rotation ("This week") shows a countdown on its category (`rotation.lua`, `rotation_test.lua`: the server sends `endsIn`); the donation tab has an optional creator code field (sent with `pay_create`) and says "double Chaos Coins (+100%, up to 1000 extra)" for the first donation (`PayView.firstBonusText`, the cap from the server's `firstBonusMax`). **Category tree (2026-10-21, the base server store's layout):** the server sends `category_groups` (the parents: Premium & Services, Consumables, Cosmetics) before `categories` (the flat list as before, each with `parent` and `size`); `shoptree.lua` (`ShopTree.build/rows/toggle/path/reveal/find/label`, no client API, `shoptree_test.lua`) makes the tree: top categories, parent rows (`ShopGroup*`, + / -, not focusable, opened on press) and the subcategories of the open parent (`ShopSubCategory*`, indented, 40 px), one parent open at a time, opening one shows its first subcategory; every row shows its offer count ("Wings (21)"); the path of the shown category over the offers (`pathLabel`, "Cosmetics > Wings"); the shown category is kept by name when the list comes again. Category names are run-time `tr()` keys (pt_br.lua). A server without the tree sends no parent and no size: the flat list, no counts. Search box (`searchText`, 400 ms after typing, 2+ characters): `search {text}` -> `search_results`, each offer with `at` (category, page, row) that Buy, Gift and Show send, its path before the description; clearing the box goes back to the category. Buy, Gift and Show read the row's `sel` (no index parsing). `openCategory(name)` for other modules (game_stash Buy Slots: opens the parent and shows the category the server names, "Storage & Slots"; the depot window that used this was deleted in O316). Not run in a client yet. **TRY ON (O318, 2026-10-29):** the SHOW button is now TRY ON (`tryon.lua`, `TryOn.plan`, tested by `tryon_test.lua`): a look offer (outfit, addons, mount, wings, aura, shader, outline, footprint, a spell skin or other effect, a bundle with a worn part) is pinned for 10 s in the look preview on the own character (`Preview:setTry`, the button counts the seconds down); a cosmetic with an effect also plays it round the character on the map for the asker only (the `preview` action). Nothing is bought or granted and nobody else sees it. Name plate frames (O318 follow-up, 2026-10-29): TRY ON draws the frame on the own name plate on the map for 10 s, this client only (`game_nameplate` `previewFrame`, logic in `nameplatemath.lua`, `TryOn.plan` 4th argument), then the real plate is back. Not tried, they keep their icon: chat colours and loot label accents (the title shows the colour), pets (drawn alone), items, services, coins, pacts, hideout decorations. On the mobile layout (no look preview) only the offers with a server effect keep the button. |
| game_market | extended opcode 221 (JSON, long answers joined by `registerExtendedJSONOpcode`) + Economy > Market, Alt+E (the depot is retired: the top bar entry is the way in) | none | Our player market (Chaos skin, 900 x 600, fits 1280x720) for gold and Chaos Coins, server `data/scripts/chaos/market.lua`: Browse (search, category, rarity, currency, sort, item level and price ranges, pages of 10; a collapsible Modifiers section: up to 6 rows of modifier / legendary power (a search box filters the Codex names, grouped prefixes / suffixes / powers, scrolling list) + lowest value + lowest tier (T1 lowest, T8 best, "T5+"), all rows or at least N, sockets, quality, free prefix / suffix, power, bound, checked before sending (`MarketView.modRequest`) and kept while logged in; rows with icon, rarity frame, name, seller, time left, prices; hover = the full rich tooltip through `game_itemtooltip.showTip` with the matched modifiers under it, Buy asks the currency), Sell (backpack picker with the reason an item cannot be listed, or drag an item onto the slot; amount, gold / coin price, 1 / 3 / 7 days, the fee and tax), My Offers (active with Cancel, sold / expired / cancelled), History, Buy Orders (the open orders with Sell: the seller's items of that kind from the backpack, greyed with the reason when they do not fit, a stack in part; My orders with Cancel and the ended ones; the post form: item found by name, how many, price each in gold or Chaos Coins, 1 / 3 / 7 days, lowest rarity / item level and the Browse tab's modifier filter, the escrow and fee before posting). Long names shortened at a word (`SupportsText.shorten`), other texts wrap. Toasts through `game_chaosnotify` (action `market`). The top bar entry (Economy > Market) points at this module only now. Logic `marketview.lua` (tested by `marketview_test.lua`); tested in game at 1280x720 and 1920x1080 (server/README.md "Market"). Price history (action `prices`, server `market_history.lua`): a click on a Browse offer shows its item key's typical price, last sale, 7-day median / volume / range and a 30-day chart of daily medians (the Orb Exchange chart code); rows priced well under / over typical are marked; the Sell form suggests a price (Use typical) and warns far below / above. Logic `marketpriceview.lua` (`marketpriceview_test.lua`) |
| game_orbexchange | extended opcode 209 (JSON: `open` / `book {base, quote}` / `place {give, giveQty, want, wantQty, days}` / `cancel {id}` / `mine` / `wallet` out; `meta`, `book`, `mine`, `wallet`, `done`, `error` back, chunked by `Chaos.sendChunked` and joined by `registerExtendedJSONOpcode`) + Economy > Orb Exchange | none (menu entry through `ChaosTopBar.addEntry`; an "Orb Exchange" button is added next to the Close button of `game_market`'s window from this module, no change there) | Orb Exchange window (Chaos skin, 900 x 600, fits 1280x720), server `data/scripts/chaos/orbexchange.lua`: a strip of every orb on the exchange (item sprites) picks the base, "priced in" picks gold or another orb; the book (asks over the spread line over bids, price / quantity / orders / total, depth bars; a click on a level fills the form to buy or sell at that price), last price, 24h change, high / low, volume and turnover, an hourly price chart (step line and volume bars drawn from widgets), the last trades, the order form (Buy / Sell, quantity, price each, days, the totals, fee and the orb-for-orb fee before placing); My Orders: open orders with progress and Cancel, my fills, closed orders. Refreshes every 5 s while the book is open. Logic `orbexchangeview.lua` (tested by `orbexchangeview_test.lua`); tested in game with two characters (server/README.md "Orb Exchange") |
| game_spellbook | extended opcode 219 (JSON) + Character > Spellbook | none | Spellbook window: search, filter (Learned / Available soon / My vocation / All spells / Runes, saved per character), a second drop-down All types / Attack / Support and an "AoE" tag on attack spells that hit an area (`spellbook_core.lua` `kindOf`, `isAoE`), spell details and an area-of-effect grid; server `data/scripts/chaos/spellbook.lua`; with "Painted icons" on, Chaos spells show `images/game/spells_painted/<clientId>` ("Painted icons" below); untested in a client |
| game_craftskills | skills packet (crafting skills after fishing) | base patch 0012 (`GameChaosCraftingSkills`) | Profession section at the bottom of the skills window, live updates, `getSkill(index)` for other modules (`game_craftingtable`); tested in game |
| game_simpleskills | none (reads the skills the base window already gets) | none (needs the base `game_skills` rows `skillId0` .. `skillId6`) | The simplified skills list (owner debug item 46, server/README.md "One melee skill"): the club and axe rows are hidden and the sword row reads "Melee" with the best of the three skills and its percent (the server hits, casts and trains with the best of them), "Distance Fighting" reads "Ranged", the magic level "Magic / Wand" (wands and rods use it), the Fist Fighting row shows for the Monk line only (server vocation ids 17-19). Logic `simpleskills_logic.lua` (`simpleskills_logic_test.lua` in CI); the widget code (`simpleskills.lua`) is not tested without a client. Not run in a client: the row ids are the stock OTClient ones (`skillId0` fist, 1 club, 2 sword, 3 axe, 4 distance), check them in the Linux client |
| game_skillstats | extended opcode 119 (server `combat_stats.lua`: `stats {damage?, attack?, defense, armor, mitigation}` server -> client, `get` client -> server; JSON) | none (needs the base `game_skills` rows `damageHealing`, `attackValue`, `defenseValue`, `armorValue`, `mantraValue`, `mitigationValue`) | The combat stat rows below the skill bars of the Skills window, which the base module fills only from a newer protocol's packet a 10.98 server never sends (so they showed 0). The five rows show the server's numbers (short form, exact rules in server/README.md "Combat stat rows of the Skills window"), "-" until a message arrives (an older server), Damage/Healing and Attack Value hidden when the character has no attack weapon (wand, rod, bare hands), the Mantra row always hidden (the game has no such stat). Tooltips in pt-BR. Logic `skillstatsview.lua` (`skillstatsview_test.lua` in CI), widget code `skillstats.lua` run against a mocked client by `skillstats_glue_test.lua`. Not run in a client |
| game_daily | extended opcode 207 | none | Daily reward window (server `data/scripts/chaos/daily.lua`). Shows the account-wide login streak: streak and best, grace charges, next milestone and the title. A window opened by itself at login waits while a server modal dialog or another login window (`LOGIN_BLOCKERS`) is on screen, and reports `closed` so the server's login window queue can open the next one. Jumps (login placement, teleports) no longer close it. Tested in game |
| game_bounty | extended opcode 223 (JSON) + Adventure > Bounty Board | none | Bounty board: today's contracts per level band (tabs), creature preview, reward, Accept/Abandon, progress bars, timer to the next roll, weekly chest count; Adventure > Bounty Board in the top menu; toasts through game_chaosnotify (action `bounty`); server `data/scripts/chaos/bounty.lua`; tested in game. Rerolls (2026-10-15): `board.rerolls` above 0 shows a "Reroll (N)" button under an active contract (`reroll {key}`), not run in a client |
| game_rift | extended opcode 228 (JSON, server -> client; `query` back after a reload) + Adventure > Rifts | none | Rift run HUD (`ChaosPanelDark` under the character plate and the buff bar below it, re-placed with its clock as the bar grows): tier, theme, a local countdown, kills / left with a bar to the guardian, the guardian line, the modifiers (boons gold, suffixes violet since 2026-10-12, `RiftMath.modColor`; the server sends `mods[].side`) and the reward bonuses, the Rift Atlas's Swift line while the rift runs (the tier's Swift time from the server's `swift`, the time to spare or "missed", `RiftMath.swiftLine`, since 2026-10-12), then Sealed / Collapsed / Left; a "Pays in crafting orbs and keys" line with the full reward text as tooltip (O143, 2026-10-23); `riftmath.lua` tested by `riftmath_test.lua`; server `data/scripts/chaos/rift.lua`; tested in game (the suffix colour not seen in game) |
| game_arena | extended opcode 236 (JSON) + Adventure > Arena | none (uses `g_game.setSafeFight` / `cancelAttack`) | Ranked PvP arena: window (rating, W-L-D and best per mode, the PvP season tier or placement per mode, Queue 1v1 / Queue 2v2 / Queue 3v3, Leave Queue, queue time and rating window, the level range you can face, first-win bonus, last 10 matches), match HUD at the top of the map (both teams' names and health, countdown / fight clock, your team on the left), VICTORY / DEFEAT / DRAW toast with the rating change and reward; turns secure mode off for a match and back on after; Adventure > Arena in the top menu; `arenatext.lua` tested by `arenatext_test.lua`; server `data/scripts/chaos/arena.lua`; tested in game with two clients |
| game_battleground | extended opcode 200 (JSON through `registerExtendedJSONOpcode`: `open` / `query` / `queue {role}` / `role {role}` / `leave` / `board` / `buy {key}` out; `state`, `start`, `hud`, `board`, `alert`, `end`, `msg` back) + Adventure > Battleground | none (menu entry through `ChaosTopBar.addEntry`; `g_game.setSafeFight` / `cancelAttack`) | The Ember Wells battleground and the PvP seasons: the window (Chaos skin, 660 x 540) with Battleground (rules, the bracket and its reference level, role buttons of the class, queue status and estimated wait, the four season cards 1v1 / 2v2 / 3v3 / Battleground with tier emblem, tier and rating or the placement, honor and record), PvP Season (season number and end, the rules, the cards, the rewards per tier) and Honor Vendor (items with their icons, cosmetics); Queue / Leave Queue / Leave Match (confirm), Find a Group (Party Finder). In a match: the HUD at the top of the map (both teams' scores towards 1000, the clock, the three wells with owner, capture progress or contested, downed / AFK countdowns, Scoreboard button), the scoreboard window and the end summary (result, score, season change, honor and the weekly first win). Art `images/chaos/battleground/` (tier emblems from donor icon cells in drawn crests, well and honor icons) from `client/tools/gen_battleground_art.py`. Pure helpers `bgview.lua` (`bgview_test.lua` in CI); `game_arena` shows the season line per mode and a 3v3 card (`arenatext_test.lua`); server `data/scripts/chaos/battleground.lua`, `arena_season.lua` (server/README.md "Battleground and PvP seasons"); tested on a live test server with two clients |
| game_siege | extended opcode 233 (JSON) + Adventure > Guild Siege | none | Guild siege: HUD at the top of the map during a siege (title, time left or "gates open in", obelisk holder in the guild colour / contested / neutral, a row per guild with colour, members inside, kills and score, your kills/downed/points; final score at the end) and a sign-up window (ornate skin: next siege and countdown, status, your guild with Sign up / Withdraw, signed-up guilds, champions, rules). Adventure > Guild Siege in the top menu. Pure helpers in `siegemath.lua` (tested by `siegemath_test.lua`). Server `data/scripts/chaos/siege.lua`; tested in game |
| game_invasion | extended opcode 251 (JSON, server -> client; `query` / `calendar` back) + Adventure > Events | none | Invasion HUD (`ChaosPanelDark` under the character plate, beside the rift HUD while a rift runs): area, faction and target, wave N of M, invaders left, a local countdown, "Horde slain" bar, breach meter (amber / orange / red), the boss's health, top 3 contributors, your rank, share and kills; click to fold; the end result (held / fallen / free again) and the occupation. "Upcoming Events" window (invasions, world event, Victory buff). Toasts through game_chaosnotify (type `INVASION`, action `invasion`). Pure helpers `invasionmath.lua` (tested by `invasionmath_test.lua`). Server `data/scripts/chaos/invasion.lua`, `worldevents.lua`; tested in game |
| game_guild | extended opcode 252 (JSON) + Social > Guild | none | Guild window in the Chaos skin: guild level and XP bar, perks, members' contribution (this week / total), guild bank (deposit, leader withdraw), guild hall (buy, rent, upgrades with buttons for the leader and vice-leaders), Guild Stash with its log, weekly top guilds; the hall's crafting bench opens `game_crafting`. Social > Guild in the top menu. Pure helpers in `guildmath.lua` (tested by `guildmath_test.lua`). Server `data/scripts/chaos/guild.lua`, `guild_hall.lua`; tested in game |
| game_guildwar | extended opcode 197 (JSON through `registerExtendedJSONOpcode`: `open` / `refresh` / `close` / `declare {target, fragLimit, hours, stake}` / `accept` / `decline` / `cancel` / `surrender {id}` / `log {id}` / `bossGold {amount}` / `bossItem {key}` / `bossSummon` out; `state`, `message`, `log` back) + Social > Guild Wars, a button in the Guild window, the guild hall's Summoning Stone | none (menu entry through `ChaosTopBar.addEntry`) | Guild Wars window (Chaos skin, 660 x 620): Wars (offers with Accept / Decline / Take back, running wars with score, time left, terms, Kill log with the refused kills and their reason, Surrender with a confirmation, history), Declare War (guild, frag limit, duration, gold stake with the winner's take), War Board (the server's running and latest wars) and Guild Boss (the Summoning Stone's fuel bar, Summon, gold and material donations with the embers they give, the guild banner tier, this week's contributors, the weekly guild boss board). Pure helpers `guildwarview.lua` (`guildwarview_test.lua` in CI); `game_guild` has an Open button for it. Server `guildwar.lua`, `guildboss.lua` (server/README.md "Guild wars in game", "The weekly guild boss"); tested on a live test server with two clients |
| game_crafting | extended opcode 232 (JSON) + Economy > Crafting Bench | none | Crafting bench: drag an item from the backpack onto the slot or pick it from the gear grid, see rarity, item level, modifiers / maximum, use any of the eight orbs (the seven crafting orbs and the Orb of Sockets; buttons enabled only when the server says the orb fits), the item's sockets under its modifiers (gem, effect, Remove for gold / Shatter: action `gem`), result line and the last 8 crafts; Economy > Crafting Bench in the top menu; server `data/scripts/chaos/crafting.lua` + `data/lib/chaos_crafting.lua`. Tabs Orbs / Salvage (Economy > Salvage opens the second): salvage the item on the bench into rune shards with a preview, "salvage all" of one container up to a chosen rarity (combo boxes, the batch marked in the gear grid, a confirmation box, 50 items at most), combine shards into the eight orbs (Ctrl+click: up to 10); Ember / Crown Shards into the Ember / Crown Orb in the same grid (1,500 / 1,750; `recipeview.lua`, tested by `recipeview_test.lua`), Lock / Unlock of the item on the bench (locked items dimmed in the grid); "Lock item" / "Unlock item" in the game's item right-click menu (`addMenuHook`, `lockmenu.lua` tested by `lockmenu_test.lua`; action `lockAt`; the entry "Unlock item" shows for any locked item, the server undoes every plain lock); actions `salvage`, `lock`, `salvageScope`, `salvageBatch`, `combine` on the same opcode (server `salvage.lua`, server/README.md "Salvage"); tested in game 2026-10-23: waystones in the list; a waystone shows "<rarity> Waystone, tier N (monster level L)" and each orb its waystone text (`wsText`). |
| game_craftingtable | extended opcode 91 of the base crafting script (JSON: `fetch {category, page}` / `craft {category, craftId}` / `tip {category, craftId}` out; `show {category}`, `money`, `chunkedFetch` pieces of `fetch {category, page, totalPages, crafts}`, `craft {success}`, `message {kind, text}`, `tip {category, craftId, tip}` back; `message`, `tip` and the material names come from `server/tools/patch_base_crafting_ui.py`, each recipe's `bonus` from `server/tools/patch_base_crafting_bonus.py`) + Economy > Crafting Tables (only explains where the tables are) | none (skills from base patch 0012 through `g_game.onCraftingSkill` and `game_craftskills.getSkill`) | Crafting Table window (Chaos skin, 860 x 600), opened by the server when a crafting table is used: the seven categories as tabs (the table's marked), recipe list with search (recipe and material names) and All / Can craft, the recipe with result icon and item tooltip (`game_itemtooltip.showTip`), skill needed against the player's, gold against what he carries, the crafting bonus at the player's skill (equipment: "Rarity at item level N: Common 18% / ... / Legendary 0.6%"; potions and runes: "Bonus yield: +3 at 17.5% / +5 at 4%"; also in the result tooltip), materials with have/need, Craft with a count (one request after the other), a bar for the 860 ms, the server's answer in green or red; Craft off with the reason on another table's tab, after walking away, or when something is missing. Pure logic `craftingtableview.lua` (`craftingtableview_test.lua` in CI). Tested in game on the full map (server/README.md "Crafting Table window") |
| game_codex | none (static data, no opcode) + Economy > Codex, Alt+K | none | Codex: an encyclopedia of the item system in the Chaos skin. Tabs Modifiers, Powers, Orbs, Gems, Uniques, Sets (item sets: pieces, bonuses, sources; filters family and level), Rift, Supports, Basics, Lore (the world, rifts, Omens, bosses: `lore_data.lua`, English and Brazilian Portuguese); a search box (every word must start a word of the name or the page), the tab's filters (prefix / suffix, item kind, group, item level: the list shows the tiers that roll at that level and the page marks them; uniques by level and source; rift modifiers by key tier; supports by spell kind), the list on the left, the page on the right (tier table with value ranges and item levels, rolls on, roll chance per kind, rules, the orbs that act on it, sources), links between pages (Backspace or right-click goes back; the search box has the focus, so Backspace goes back while it is empty). Every text wraps; tooltips use `SupportsText.wrap` of `game_spellsupports`. The data `codex_data.lua` is generated from the server's data files by `server/tools/gen_codex_data.lua` (CI fails when it is stale); the logic without client API is `codexview.lua` (tested by `codexview_test.lua`). `game_crafting`: right-click a modifier on the bench opens its page (`openModifier(key, group)`; checked in game for a Rift Key modifier and a legendary power). Tested in game at 1280x720 and 1920x1080. pt-BR (O147): `codextext.lua` (tested by `codextext_test.lua`) turns a generated text into its template (numbers become %s), looks it up in `client_chaos_locale/pt_br.lua` and gives the numbers back; tabs, filters, options, headings, column heads, list lines and most paragraphs follow the language, names stay English, the search still matches the English text |
| game_itemfinder | extended opcode 155 (JSON: `search {q, p}` / `item {id}` / `item {cid}` / `page {id, k, p}` out; `results`, `item`, `page`, `busy` back, joined by `registerExtendedJSONOpcode`) + Economy > Item Finder | none | Item finder ("where does this drop") in the Chaos skin (820 x 580): a search box (type-ahead 350 ms after the last key, at least 2 letters), the results with item icons and what each has (drops, shops, recipes, ...), pages of 12; the item on the right with its sections in the server's order (Monsters and bosses with chance and count, bosses marked; Chaos drops; Chests and rewards; Crafted from with the material icons; NPCs that sell it with the price and town; Store and vendors; The Gambler; Gathering; Used to make; NPCs that buy it; Other uses), each section with its own pages of 15. A linked item (a recipe's product or material) opens on a click; Back / Backspace goes back. A Codex button opens the item's Codex page when the Codex has one; the Codex has a "Where to find" link on its item pages (`game_codex` `codex.lua`, entries' `items`). Opened from the game's right-click menu of an item (inventory, containers, the map: `addMenuHook` "Where to find"), from a right-click on a market row or a loot channel icon (`attach(widget, clientId)`, one line each in `game_market` and `game_lootfilter`), and from the Codex. A request without an answer goes out once more after 0.9 s (the server drops requests closer than 200 ms); an answer never reopens a closed window. Close button, Escape (the window's own key handler, which replaces `UIWindow:onKeyDown`) and the menu toggle close it (live test winpkg-35: it did not close). Logic in `itemfinderlogic.lua` (`itemfinderlogic_test.lua`, also checks the item ids of the real Codex data). Tested in game (server/README.md "Item finder") |
| game_leaderboard | extended opcode 229 (JSON) + Social > Leaderboards | none | Leaderboards (ornate skin): a dropdown of the server's boards (World Boss, Bounty Hunter, Rifts, Class Ladder with a tab per class, ...) on the top row next to the board's description and Records, sorted by the shown (translated) name with accents folded, the choice kept per character in g_settings node `leaderboardBoard` (World Boss by default; `boardpick.lua`, tested by `boardpick_test.lua`; the board names are run-time tr() keys), top 20 with titles next to the names, last week's title holders, own rank and value, time to the Monday reset. Social > Leaderboards in the top menu, which replaces the base `game_highscores` entry: that window asks with game packet 0xB1, which the server does not answer, so it stayed empty. The class and Records tabs are as wide as their labels in the font they are drawn with, in as many rows as needed (`tabrows.lua`, tested by `tabrows_test.lua`). Server `data/scripts/chaos/leaderboard.lua`; tested in game Season modes: in the Season view a row of mode tabs (All / Standard / Self-Found / Hardcore / HC Self-Found / Fallen, from the meta) sends `mode` with `get`; a fallen Hardcore character gets a skull (`buffs/skull_red`) after its name with the level and cause as tooltip, on every ladder. The **Records** button switches to the competitive records (server `records.lua`, actions `rmeta` / `rcat` / `rget` / `rboard` / `rfirsts` on the same opcode): category tabs, a board row, filter rows (This week / Season / All time, boss or difficulty or band or floor, party size, class), the rows with the date and the party in the tooltip, the all-time record, a "your rank" line and the Realm Firsts tab; pure parts in `recordsview.lua` (`recordsview_test.lua`). |
| game_cardborder | extended opcode 172 (JSON: `state {on, cards, decks}` in, `sync` out, joined by `registerExtendedJSONOpcode`) | none | Card borders (owner 2026-10-24): a card inside a deck window (Bronze, Silver, Golden Deck) gets a 2 px border child on its slot widget, green (`#7fe05a`) when the server says the card is on, dim red-grey (`#6a3a3a`) when it is off. The client cannot see action ids, so the server (`cards.lua`) sends the ids that are on at login, on `sync` and whenever the set changes. Hooks the `Container` signals from outside (like `game_lootfilter`), one redraw per container per frame, no per-frame loop; nothing is drawn before the first server message or for cards outside a deck. A card is told by its id, not its copy. Rules in `cardborderlogic.lua` (tested by `cardborder_test.lua`, which also loads the server's `cards_core.lua` payload). No UI text. The "drawn" flag lives on the items panel (`L.needsPass`), so a bag opened in a deck's window wipes the deck's borders. Not yet run in a client (server/README.md "Cards and decks") |
| game_chaosinfo | extended opcode 237 (JSON) | none | Info & Services window (Chaos skin): a page list (Character Info, Services, House, Rift Keys, Events, Ancestral Store, Server Info), each page's commands as buttons / text fields / choice lists, and the server's answer as text. Opened by the top menu (`openPage(id)`); pages and buttons the server does not offer are hidden (`catalog`). Every row wraps its buttons to more lines so none sticks out at the window's width (`ChaosInfoView.wrapRow`); every Services row and button has a tooltip. Services asks the server its state (`services`: Name / Vocation Change tokens, free switch, tutorial, familiar level, web shop orders, owned frames) on open and after each action: the text box shows that status and the last action's answer, and a button that cannot be used is disabled with the reason as tooltip. Its Plate frame row is a list of the character's own frames (Use Frame, My Frames, Title Frame; command `plateframe` of `shop.lua`). Character Info and Events put a heading over each answer. Character Info also runs the `deck` command on open (the cards: what is on and off, what each gives, the decks carried and how full, how to get a deck; server `cards.lua`, "Cards and decks"). Pages without automatic commands (House) show a hint instead of an empty box. Ancestral Store: a scrollable list (`store` / `buy` actions) with the player's Ancestral Points on top; each row has the item icon, its name, what it is (Aura, Wings, Exercise Chest), the price and its own Buy button; rows the player cannot afford are greyed out with the missing points as tooltip; the points and a message come back after each purchase. Server `data/scripts/chaos/commands_ui.lua`; tested in game The house broker and the services clerk (`service_npcs*.lua`) open a page with an `npc` action (`data.page`, a page the client knows). Character Info also shows the item sets worn (command `sets`, server `itemsets.lua`; button Item Sets). Services > Other has Leave Boss Room (command `leaveroom`, server `instance_limits.lua` `ChaosBossRooms.leave`): enabled only inside a running boss room (state `inBossRoom`); out to the room's exit, refused in a fight |
| game_season | extended opcode 246 (JSON) + Adventure > Season | none (own join dialog `seasonjoin.otui`) | Seasons window (Chaos skin): season name and tag, time left or time to the start, the season modifier, this character's status with a Join button when it may join (confirmation dialog), the account's reward track with progress and what is unlocked, the account's season titles. Adventure > Season in the top menu. `game_leaderboard` got a "[S1] only" toggle (season view of every board) while a season runs. Server `data/scripts/chaos/season.lua`; tested in game Season modes (server `season_modes.lua`): the join dialog offers Standard / Self-Found / Hardcore / Hardcore Self-Found with their warnings ("I understand" for Hardcore), pure logic `seasonjoin.lua` (`seasonjoin_test.lua`); the window shows the mode or the fall; a Hardcore character sends a heartbeat (`beat`, every 2 s) and asks for its state after a reconnect (`sync`); buff bar icons `self_found` / `hardcore_ward` (`client/tools/gen_buff_icons.py`). Seasonal Journey (server `season_journey.lua`): a Journey tab (`journey.lua`, pure `journeyview.lua` with `journeyview_test.lua`; actions `journey`, `journeyChapter`, `journeyDone` on 246): chapters with their state, the chosen chapter's objectives with progress bars and mode tags, its rewards (item icons, set pieces), a banner when something completes; a preview for characters outside the season; the window is 660 x 540 with Season / Journey tabs. `game_chaosnotify` shows the `journey` toast (opcode 79). |
| game_hunt | extended opcode 241 (JSON) + Hunt > Hunt Tracker | none | Hunt tracker: session time with Pause/Resume and Reset, exp/h, time to the next level, loot, supplies and profit per hour, damage and healing, tabs for kills per monster, looted items (icons, counts, gold), supplies used and Chaos drops (orbs, uniques, rarity items in rarity colours; the loot filter's rule counters on top when that option is on), Copy summary. Hunt > Hunt Tracker in the top menu, next to the base `game_analyser` entry (whose loot/supply/kill panes need game packets this server does not send). Server `data/scripts/chaos/hunt.lua` counts everything; pure helpers `huntmath.lua` (tested by `huntmath_test.lua`); tested in game Restock button (2026-10-15, server `restock.lua`, actions `restockQuote` / `restock` on 241): a quote box with what it buys, the gold and the 10% convenience fee in it, Yes buys that quote. |
| game_dpsmeter | extended opcode 204 (JSON, joined by `registerExtendedJSONOpcode`; `open` / `close` / `seg` / `party` / `share` / `reset` out, `state` back) + Hunt > DPS Meter and the Hunt Tracker's Meter button | none (uses `Spells.getSpellIcon`, `g_window.setClipboardText`, `game_console.getConsole`) | DPS meter: a movable, resizable, lockable panel (`ChaosPanelDark` look) with a bar per skill (spell icon from the spell sheet, rune item, buff bar icons for damage over time, our icons in the buff-icon frame), total, per second and share; tabs Damage / Healing / Taken / Received; dropdown current fight / session / last 10 fights (bosses named); party mode with the members' DPS / HPS (totals only, sharing members of the same realm); Combat Log window with hits, crit rate, average, max, overhealing and the element split; Copy (clipboard) and To chat (one line into the chat input, never sent by itself). Settings in g_settings node `chaosDpsMeter`. Icons `data/images/game/dpsmeter/*.png` (`client/tools/gen_dpsmeter_icons.py`). Pure helpers `dpsmath.lua`, tested by `dpsmath_test.lua`. Server `data/scripts/chaos/combatlog.lua`; tested in game |
| game_chaosscale | extended opcode 157 (JSON: `scale {level, f}` in; `hello` out at a game start, when the module loads in game and when the own level differs from the last factor's) | none | Display scale (see "Display scale" below; server/README.md "Display scale"): keeps the factor of the own level (spell mana costs are fixed and never scaled since 2026-10-21) and gives `chaosDisplayFactor()` / `chaosDisplayValue(n)`. Pure helpers `scalelogic.lua`, tested by `scalelogic_test.lua`; checked in the Linux client at levels 100, 300, 700 and 1000 |
| game_deathrecap | extended opcode 154 (JSON, joined by `registerExtendedJSONOpcode`; `open {id?}` / `get {id}` out, `history {list, sel, recap}` / `recap {id, recap, auto}` back) + Hunt > Death Recap | none (menu entry through `ChaosTopBar.addEntry`; `UICreature` for the looks) | Death Recap window (Chaos skin, 680 x 520): opens by itself after a death (at the next login, with the experience and levels lost) or a defeat in a mode, unless "Open after a death" is off (g_settings node `chaosDeathRecap`). Left: the last 5 deaths (time, killer, loss or mode); right: killed / defeated by, time, level, mode, PvP, what was lost, the killing blow, the time window and hit count, damage taken (health / mana) with an element bar, a row per attacker (look, name, a summon with its master, total and share in short numbers, an element-coloured bar, hits, crit rate, mana part, the element split; tooltip with the exact numbers), "Others", and the last 6 hits. Pure logic `deathrecaplogic.lua` (numbers by `formatShortNumber`), tested by `deathrecaplogic_test.lua`. Server `data/scripts/chaos/deathrecap.lua`; tested in game with two clients |
| game_nemesis | extended opcode 163 (JSON, joined by `registerExtendedJSONOpcode`; `get` out, `state {has, name, shown, monster, level, kills, traits, lastSeen, created, expiresIn, avenged, hunted}` back) + Hunt > Nemesis | none (menu entry through `ChaosTopBar.addEntry`; a `ChaosTabButton` "Nemesis" put into `game_bestiary`'s tab row at runtime, the Bestiary module is not edited) | Nemesis window (Chaos skin, 380 x 400): the name with its epithet, "A <monster> that killed you twice", rows for monster, level, kills, last seen and when it fades, its traits in colour with what they do, the counts of nemeses avenged and of others slain; an explanation when none hunts the character. Pure logic `nemesisview.lua`, tested by `nemesisview_test.lua`. Server `data/scripts/chaos/nemesis.lua`; not run in a live client yet |
| game_embercache | extended opcode 174 (JSON, joined by `registerExtendedJSONOpcode`; `open` / `close` / `get` / `offerQuote` / `offer` out, `state {open?, week, day, src, book}` and `offer {orbs, points, room, per, carried}` back) + Adventure > Ember Cache | none (menu entry through `ChaosTopBar.addEntry`) | Ember Cache window (Chaos skin, 400 x 560): this week's Ember points, the three milestones with their rewards and what is left, the Daily Sparks of the week, today's points with the Daily Spark and the double points left, the day book (experience, levels, kills, loot, supplies, profit, drops, deaths, time played) and the point table in the tooltip of "How to earn points"; the Offer junk orbs button (a quote from the server, a Yes / No box, the server takes the orbs). Pure logic `cacheview.lua`, tested by `cacheview_test.lua`. Server `data/scripts/chaos/embercache.lua`; not run in a live client yet |
| game_weeklychest | extended opcode 117 (JSON, joined by `registerExtendedJSONOpcode`: `open` / `close` / `get` out, `state` back) + Adventure > Weekly Chest | none (menu entry through `ChaosTopBar.addEntry`) | Weekly Chest window (Chaos skin, 420 x 470): the six activities of the bounty week with Done / Not yet / "Unlocks at level N", "N of M activities done this week" (M is smaller while systems are locked), the chest's gold and orbs, the bonus roll's range, chests opened so far. The server gives the rewards (a toast tells); the window only shows. Pure logic `weeklyview.lua` (`weeklyview_test.lua`). Also in this pass (no new module): `game_partyfinder` shows the server's `nudge {text, a, n}` as the toast with [Join] that opens the browse tab, and `game_partyframes` shows the party's shared-experience bonus in the header (`xp {p, on}` in the state; `PartyMath.xpView`, tested in `partymath_test.lua`). The tr() keys have pt-BR entries. Not run in a client yet |
| game_lootfilter | extended opcode 238 (JSON) + Hunt > Loot Filter | base patch 0032 for the rule sounds (`g_sounds`); the generated dat for the ray effects 424..428 | Loot Filter window (ornate skin: presets, glow/dim thresholds, category toggles, Rarity Autoloot selectors locked without the store unlock, preview row of the 15 rarities, a unique, an orb and plain loot). Hooks the container windows from outside (`Container` signals + `peek` to the server, which knows the rarities): glow, frame or dim on the slot widgets; dims in corpses only. Orbs glow softly (`L.glowStyle` = `soft`, owner request 2026-10-21: the wide teal glow and the frame hid the orb sprite): `images/lf_glow_soft.png`, a ring on the slot edge only (alpha 110 on the edge pixel, 40 on the next, nothing over the sprite) and no frame on top; gear and uniques keep `lf_glow.png` (2 px solid, 6 px fade) and the frame. Lays the loot feed over the console's Loot tab: one row per kill, icons only, no text: the killed monster's look first (a `UICreature` at item size facing south, from the server's `kill.look`: rift looks and tier shaders included; old scaling, centred, so small creatures stay 1:1 and big ones shrink; hover: its name and the kill time), then the item icons (count on the icon, rarity glow / frame / dim, click to loot, Shift = one, greyed with a check when gone, hover: the item tooltip); an empty corpse is the monster icon with a dark veil and a small slashed ring (`images/lf_empty.png`). Rows wrap (grid flow). The stock Loot tab text stays behind the panel (shown again when "Loot tab shows item icons" is off). Coloured rare-drop lines over the map. Hunt > Loot Filter in the top menu. Rules and the feed rows (`L.feedRow`, `L.outfit`, `L.killTip`, `L.iconCount`) in `lootfilterlogic.lua` (tested by `lootfilter_test.lua`); art from `tools/gen_lootfilter_art.py`. Every engine/console callback runs in `pcall`, the window is optional, images are checked before use. Container changes (add, remove, update, size) redraw a window's glow and frames once per frame (`L.coalescer`, tested; one call per item of a big Auto Seller sale or Loot Bag sort walked every slot each time); the `peek` request was already debounced. `game_itemrarity`/`game_itemtooltip` unchanged. Rule counters and sounds (right panel): per filter rule (Uniques, Legendary powers, Rarity glow, Modifier tier, Orbs) the drops of this session and in total (reset per rule, session, totals), a sound per rule (Chime, Bell, Ping, Drum, Fanfare or none), volume, Mute all, saved on the character; a kill plays the first matched rule's sound on the Effect channel (`g_sounds`; needs base patch 0032); optionally the counters in the Hunt Tracker's Chaos Drops tab (`game_hunt` reads `getCounters()`). Sounds `sounds/*.ogg` synthesised by `tools/gen_lootfilter_sounds.py` (our own; no recorded or base client audio). Server `data/scripts/chaos/lootfilter.lua`; tested in game. The supplies category reads "potions, runes" (arrows and bolts are gone: server/README.md "Infinite arrows and quivers"); quivers count as equipment |
| game_lootbeams | the loot filter's extended opcode 238 (`beam`, forwarded by `game_lootfilter`); `game_groundlabels` for ground items | base patch 0069 (`g_map.setLootBeam`); without it one warning and no beams | Loot beams (owner request): a thin light pillar over a corpse (or an item on the ground) that holds loot the player's loot filter makes glow, coloured by the best tier inside, with a soft glow pool at its base, about 3.5 tiles tall, gently pulsing. Replaces the old loot ray map effects (server `lootfilter_config.lua` `rayEffects`, now off), which read as a red splash over the next tiles. Colours: the 15 tiers in six groups (white Common-Uncommon, blue Rare-Epic, orange Legendary-Exotic, red Mythic-Eternal, pale blue Divine-Celestial, violet Cosmic-Transcendent), uniques green, orbs teal; higher groups stand a little taller. Only items the loot filter makes glow beam (`LootFilterLogic.classify` = highlight; legendary powers always; orbs only with "Beams for orbs"). Corpses: the server's `beam {k, p, i}` (the items still inside that may beam, to the owner and the party at the kill; `i = []` when looted empty, decayed or out of the history). Ground items: `game_groundlabels.getGroundItems()` (new export with `getRowsVersion()`). One beam per tile (the best), at most 24 (best colour, then nearest), engine cap 64. Since pair 36 (2026-10-22, owner: "Use as spells, level up e loot beams") a beam is the animated loot beam effect of the purchased beam pack (docs/CREDITS.md), one per group (`LootBeamsLogic.EFFECTS`: white `beam_silver_metal` 4101, blue `beam_rare` 4098, orange `beam_orange_fire` 4095, divine `beam_rainbow_prismatic` 4097, unique `beam_green_nature` 4092, orb `beam_ancient` 4090; checked against `server/data/lib/chaos_pack36_fx_ids.lua` by `lootbeams_test.lua`), added with `Effect.create` + `g_map.addThing` when the beam appears and again every 1750 ms while it stands; height and intensity then do nothing. A pair without those ids: the engine pillar below. Drawn by the engine (no widgets, no per-frame Lua): the module only calls `g_map.setLootBeam` / `removeLootBeam` when the set changes (a 300 ms check of the filter, the ground rows and the player's tile). Window *Loot Beams* (button in the Loot Filter window's footer): on/off, ground items, orbs, height (short / normal / tall: 2.5 / 3.5 / 4.5 tiles), intensity (soft / normal / bright), a colour legend; saved on this computer (`g_settings` `lootBeams`). The Ground Labels' "Corpse: N items mm:ss" label stays, drawn over the pillar just above its base. Rules in `lootbeamslogic.lua` (tested by `lootbeams_test.lua`: settings, tier to colour, the filter, lifecycle, ground items, the cap, the engine calls); server side server/README.md "Loot beams". Mock: the scratch render of `lootbeam.h` (client/BASE.md 0069). Not yet run in a client |
| game_pact | extended opcode 222 (JSON: `open` / `sync` / `claim` / `marksBuy` / `buildSave` / `buildRename` / `buildDelete` / `buildLoad` out, `status` / `buildCode` / `message` back) | none (menu entry through `ChaosTopBar.addEntry`, Character > Chaos Pact) | The Chaos Pact window (Chaos skin, 560 x 670): Pact status and end date, the title, Claim daily Pact Marks, a Store button; the Pact Marks section (O317): the balance, "this month the Pact gave you X extra experience" (character and account), and the shelf of cosmetics the Marks buy (name, price, Buy; `marksBuy`); the account limits table (free / Chaos Pact / bought / yours, inactive bonuses marked off); the special stash tabs; saved passive tree builds per account (Load opens the passive tree and asks for the preview through `game_passivetree.sendAction('buildPreview')`, Overwrite, Delete with a second click, Save current build), read-only slots dimmed. Logic `pactview.lua` (tested by `pactview_test.lua`); tested in game (server/README.md "Chaos Pact and account storage") |
| game_referral | extended opcode 220 (JSON: `open` / `sync` / `enter {code}` out, `status` / `message` back) | none (menu entry through `ChaosTopBar.addEntry`, Character > Referral) | The Referral window (Chaos skin, 560 x 540): the account's code with Copy code (clipboard), what the friend and the referrer get, the friend's code box while the account is new (else who referred it, or why it cannot), the referred friends with level and the state of each milestone, this month's links and rewards and the coins earned. Logic `referralview.lua` (tested by `referralview_test.lua`); tested in game (server/README.md "Referral program"). The rewards text lists the tier rewards too (3, 5 and 10 friends at the qualifying level, server `referral_config.lua` `tiers`; `V.rewardsText`) |
| game_mentor | extended opcode 194 (JSON: `open` / `sync` / `list` / `register` / `retire` / `choose` / `invite` / `accept` / `decline` / `dismiss` / `release` / `seek` / `buy` out, `status` / `mentors` / `message` back, chunked by `Chaos.sendChunked`) | none (menu entry through `ChaosTopBar.addEntry`, Social > Mentors) | The Mentors window (Chaos skin, 680 x 580), five tabs. Find a mentor: the rules or why this character cannot pick, class / language / online filters with Search, "Looking for a mentor" (the Party Finder tag), invitations (Accept / Decline) and the referrer's mentor (Choose), the mentor list (name, level, class, online, language, hours, graduates, free places, note, Choose). My mentor: the mentor, since when, time hunted together, whether the bonus is on now and why not, the milestones with their state (paid / no marks / month cap / before the link) and marks, Dismiss. Mentoring: the requirements, the mentor card (language, hours, note, taking apprentices, show on website; Become a mentor / Save card, Retire), marks / today / month counters, Invite by name, the apprentices with their milestone steps and Release. Marks Shop: titles, cosmetics, supplies with price, owned and weekly limits. Top Mentors: rank by graduates. Party Finder rows, tooltips and applicants show "Mentoring" / "Looking for mentor" (`partyfinderview.lua`). Logic `mentorview.lua` (`mentorview_test.lua` in CI). Rendered in the Linux client with payloads made by the server core (offline); not run against a live server |
| game_unveil | extended opcode 196 (JSON: `open {path, id, clientId, name, rarityName, level, sig, orbs, offers}` / `result {ok, text, veil}` in, `choose {path, id, sig, choice}` out), server `veiled.lua` | none (opened by the server when an Orb of Unveiling is used on a veiled item, by use-with or the crafting bench) | The Unveil window (Chaos skin, 660 x 352): the item, the orbs left, three cards (veiled tier V1..V4 in its colour, name, text, range, "Effect of its own" for the hook modifiers); pick one, Unveil (final, one orb), the result line; the cards of a revealed item stay dimmed. Also: `game_itemtooltip` shows the veiled slot (`tip.veil`) in violet ("Veiled modifier" / "V4 Wraithstride [8-10]" + its text), `game_market` adds "Veiled" / "Unveiled" to a Browse row's sub line. `unveilview_test.lua`; tested in game (server/README.md "Veiled modifiers") |
| game_pouches | extended opcode 226 (JSON: `open` / `sync` / `set {rules}`, Auto Seller `as_open` / `as_sync` / `sell` / `asrar {tier, on}` / `asevery {minutes}` (sell the Loot Bag every 5/10/15/30/60 minutes, off by default) / `aslist {op, item}` / `aspause {on}` out; `settings {rules, ids, titles, owned, rarities, open}` and `autoseller {unlocked, needs, paused, tiers, list, slots, cooldown, cooldownMax, last, notice, open}` back) | none (uses `game_interface.addMenuHook`) | The Loot Bag rules window (Chaos skin) of the store pouches (server `data/scripts/chaos/pouches.lua`): items on the autoloot list, coins, uniques, gear from a rarity (combo), supplies, gems, everything else; saved on the character at once (the server's defaults: everything, gear of any rarity); an "Auto Seller" button that opens the Auto Seller window (`getAutoSeller()` / `syncAutoSeller()` / `sellAll()` are for the helper's Auto sell, see "Helper"); status line and Open Store when the character has no Loot Bag. Opened by right-clicking the Loot Bag > "Pouch settings" (shown only for the Loot Bag's look with the item lock flag the server sets on every pouch) or by the Loot Filter's "Loot Bag" button (`game_lootfilter/lootfilter.otui`). The pouches are ordinary containers (use = open); their tooltip lines "Store item: cannot be traded" and what it collects come from the server (`tip.store`, `tip.collects` in `game_itemtooltip/tooltiplogic.lua`). Logic `pouchesview.lua` (tested by `pouchesview_test.lua`); tested in game (server/README.md "Store pouches"). **Auto Seller window** (`autoseller.otui`, logic `autosellerview.lua` tested by `autosellerview_test.lua`; owner 2026-10-13: "Tire os comandos do autosell e coloque no topmenu"): top menu Economy > Auto Seller (`client_chaos_topbar`, `toggleAutoSeller`, icon `topbutton_autoseller` from `tools/gen_theme_art.py icons=autoseller`: a loot sack, an arrow, a coin stack); Sell all (the Loot Bag) with the server's 30 s cooldown counted down on the button, the last sale's total, five rarity checkboxes in the loot filter's colours (Common, Uncommon, Rare, Epic, Legendary+; default Common and Uncommon), the corpse selling on / off, the list (item name, Add / Remove / Clear). Greyed out with the reason as tooltip without the Auto Seller or an active Pact. The client only sends choices; the server checks them (server/README.md "Store services", Auto Seller window). Run in a client (live test 2026-10-14): Sell all, the 30 s countdown, the rarity checkboxes saved on the server; fixed there: the item row's buttons were anchored to the edit box that was anchored to them (an anchor cycle, "layout update aborted" in the log; `tools/ci/check_layouts.py` now reports anchor cycles), and the rarity checkboxes are as wide as their text (`AutoSellerView.checkWidth`; a fixed 72 px clipped the names; window 460 px wide). **Loot Bag window while auto loot runs** (owner 2026-10-23: the client stuttered when the open Loot Bag took many items at once): the window is a stock container window, not this module. A kill burst now reaches it as one full container packet (server/README.md "Loot burst: one update"), and base patch `0122` keeps the slot widgets of an open window instead of rebuilding all 255 for each packet (`BASE.md` 69n; model test `tools/slot_reuse_test.py`). |
| game_transmog | extended opcode 212 (JSON: `open` / `looks {kind}` / `apply {slot, look}` / `remove {slot}` out; `state {money, fee, slots, kinds, total, sets}`, `looks {kind, rows}`, `result {ok, text}` back, long ones joined by `registerExtendedJSONOpcode`) | base patch 0030 (`item:setAppearanceId`) | The Transmog window (Chaos skin): the six equipment slots with their current look, own look and preview side by side, the account wardrobe of the selected item's kind as a searchable grid, Apply (gold fee) and Remove look; Collection tab with progress bars per kind and the appearance sets (owned, or how to get them: store, achievement, season, exclusive). Character > Transmog, or right-click an equipped item > "Transmog". The look itself is drawn everywhere by base patch 0030 (item custom attribute 8); tooltips add "Appearance: <look>" (`game_itemtooltip/tooltiplogic.lua`, `tip.look`); `game_market` rows and the sell picker and `game_playerinspect` slots draw the look from server data. Logic `transmogview.lua` (tested by `transmogview_test.lua`); tested in game (server/README.md "Transmog") |
| game_cosmetics | extended opcode 225 (JSON: `open` / `select {kind, id, line}` / `preview {id}` / `hello` out; `state {line, lineName, rows, collection, score}`, `style {accent}`, `colors {names, full}`, `looks {names, full}`, `tryfx {kind, art, pulse}`, `result {ok, text}` back, joined by `registerExtendedJSONOpcode`), server `cosmetics.lua`, `exclusives.lua` | none | The Cosmetics window (Character > Cosmetics, Chaos skin, 720 x 480): tabs Spell Effects (the skins of the character's class line first, other lines dimmed), Kill Effects, Loot Labels, Chat Colours, Footprints, Outlines, Collection; a Default row per tab, Use, Preview (effects only the player sees, sent by the server; footprints and outlines drawn here by `game_cosmeticfx`), Open the Store; a sample per colour (the player's own chat line, rarity labels on the accent) and per footprint (its prints); the outline and the Collection's looks on the character in the shared look preview (`game_lookpreview`, "Look preview"; window 930 x 480); a "Show other players' footprints / outlines" box on those two tabs. Since 2026-10-16 the list icons of spell skins and kill effects are a picture of the row's main effect (`images/fx/`, `tools/sprites/gen_cosmetic_fx_icons.py`; the sprites themselves when a picture is missing) and a footprint's print; the detail shows it at 64 px; the preview panel plays the row's effects (`play` of the state rows); every tab follows `game_unlocks` (locked rows greyed with their source, "Only mine"), and the server's `wardrobe` answer is handed to `game_unlocks` ("Cosmetics effect previews", "Owned and locked lists"). Collection: the exclusives of every visual kind (server `exclusives.lua`), owned first, kind, "Achievement: X" or "Boss: Y, rare drop", where it is chosen, the look on the own character (outfit, mount, wings, aura, shader). Once in the game it asks the server for the full style, colours and looks (`hello`: a send from the server's login event can arrive before the client is in the game, and a reconnect runs no login event). Colours the speaker's name in chat for player lines only (wraps the stock `game_console` `Message:updateLabel` after `game_chatlinks`; loads at priority 1003), hands the label accent to `game_groundlabels` and `looks` / `tryfx` to `game_cosmeticfx`. Logic `cosmeticslogic.lua` (tested by `cosmeticslogic_test.lua`); tested in game with two clients (server/README.md "Cosmetics", "Footprints and outlines", "Exclusives") **Collection score and combat cosmetics (O318, 2026-10-29):** the `state` carries `score` (server `collection.lua`): a strip over the lists ("Collection score: 142 - next reward at 220 (78 to go)") and the first row of the Collection tab (every milestone with its reward, and where the points come from); tabs Level-ups, Rare Loot and Emotes (the same rows, Default, Use and Preview; the window is 1100 x 500 and the tabs 90 px wide). Logic `cosmeticslogic.lua` (`scoreLine`, `milestoneLines`, `groupLine`, `scoreRow`, tested by `cosmeticslogic_test.lua`). Not run in a client yet. |
| game_shaderfx | none | base patch 0044 (`UIWidget:setUiShader` / `setUiShaderParams`, `u_Params` in the shader); without it every call is skipped and the images stay plain | UI widget shaders, all GLSL written for this client (`data/shaders/chaos_ui_*.frag`, compile-checked by `tools/check_shaders.py`). Liquid health and mana orbs (`chaos_ui_orb`: layered sine surface, own value noise for the swirl, round bubbles in a cell grid, a fake sphere normal for the shading, a foam line; a glass globe since 2026-10-28, owner pick of a numpy preview: the liquid seen through a lens, its surface curving with the ball, light from the upper left, a fresnel rim light, a sharp window highlight with a glint and a crescent reflection at the bottom; the value change makes it slosh, eased back in about 2 s) at the bottom corners of the game window, option `liquidOrbs` (off by default); a light sweep across the rarity frame of Legendary-and-up and unique items in inventory and container slots (`chaos_ui_shine`, a slanted band every 3.5 s, each slot at its own phase; option `rarityFrameShine`); greyscale for items their player locked (custom attribute 3 = 1; `chaos_ui_grey` as the slot's item shader, and only our grey is taken back; a bound item such as the Everfull potions carries 2 and keeps its colours: with 1 the red and purple flasks showed as dark, empty-looking ones, live screenshot 2026-10-16) and `setGreyed(widget, on)` for any widget. Art from `tools/gen_orb_art.py` (`--check` in CI): per orb size a ring `images/orb_ring_<size>.png` and a mask `images/orb_mask_<liquid>.png` at twice the drawn size (`L.orbArt`, set by `applyOrbSize`). Owner screenshot 2026-10-21: the one 76 px ring and 64 px mask stretched to the 150 / 190 px orbs drew a blurred, stepped ring with square rivets, and the bubbles (the peaks of a 22 x 14 value noise) read as upright pixel blocks; now 2x art (round, soft-edged rivets), round bubbles in a square cell grid and the swirl's noise grid turned off the screen axes (before / after rendered with a numpy port of the shader, not seen in a client). Pure helpers `shaderfxlogic.lua` (fill, slosh, phase, shine rule, locked rule, `applyItemGrey`), tested by `shaderfx_test.lua`. Live test 2026-10-14: a container holding a locked item (the Loot Bag, the Everfull Ration) overflowed the Lua stack at every open: `setItemShader` calls the slot's onItemChange, `game_itemrarity` answers with `onSlotItem` and the slot was marked grey only after the call, so each re-entry greyed again; `L.applyItemGrey` marks it first (a re-entrant mock slot in the test). |
| game_helper | none | none (overlay only; the base `mods/game_helper` is removed by `assemble_client.sh` after the patches) | The helper window and its loop: healing, potions, mana training, haste, the five-slot spell rotation, Auto Target, runes, Auto sell, Follow, party and friend heals, food and exercise. On a phone the window is 536 high, so it fits 540 interface pixels; see "Helper" |
| game_helperhud | none | base patch 0056 (the helper calls `ChaosBotHud` when its cavebot file is left out) | The helper's bot HUD (Tools > Bot HUD), see "Helper bot HUD" |
| game_targetguard | none | base patch 0112 (the helper's locked target and the battle list's attack next call `ChaosTargetGuard`) | Which creatures the player's own targeting may pick, see "Target guard" |
| game_autotarget | none of its own; asks the server for a creature's tier through `game_monsterbar` (opcode 125 `query`, answer `info`) | base patch 0117 (the helper's Auto Target calls `ChaosAutoTargetEngine`; two boxes in its Targeting panel); `g_map.findPath` / `g_map.isSightClear` of the base engine | Which monster the helper's Auto Target picks: only reachable ones, loot goblins / bosses / special monsters first, then the nearest with the lowest health, see "Auto Target priority and reach" |
| game_helpersupport | none | none (overlay only: it uses the helper's `_Helper` functions and `game_buffbar`'s `activeBuffs`) | The helper's Support spells tab: a list of support spells the helper casts by itself whenever they are off cooldown, see "Helper Support spells" |
| game_chatpanel | none | base patches 0056 (`game_console` reads `ChaosChatLogic.enterAction`; splitter minimum 96), 0065 (splitter drag, left margin) | Chat panel size and place (with the orbs) and the chat's Enter rule, see "Chat panel" |
| game_chaoslayout | none | none (the base's miniwindow restore reads a node nothing writes) | Window layout per character, see "Window layout per character" |
| game_chaosview | none (asks for the server's largest map area with `g_game.changeMapAwareRange`, server limit 29 x 21) | none | The map's zoom, see "Map zoom" |
| game_cosmeticfx | none of its own (`game_cosmetics` hands it the server's `looks` and `tryfx`) | `0038` for the outline line (`Creature:setOutline` / `setOutlineGradient` / `clearOutline`); `0078` for the footprints (`Tile:setFloorWidget`: under creatures; without it `Tile:setWidget`, drawn over everything); without `0038` the glow picture (uses `Creature:addBottomWidget` / `clearBottomWidgets`, `UIWidget:setRotation`) | Footprints and outlines of every player on screen, drawn by this client: a print on the tile a player left (turned to the step, fading in 3.2 s; 160 on screen, 8 per walker; never on a tile with another module's widget; none while the own character stands in a protection zone) and an outline: a 2 px line that follows the player's silhouette (body, addons, mount and rider, the walking frame; drawn by the engine under the outfit's parts, so it stacks with outfit shaders, wings and auras and stays off names and bars). Colours per art key in `CF.OUTLINES` (one colour, or a vertical gradient: Ember, Storm, Paragon's Radiance, Void Corona, Cinderheart Blaze); pulsing ones breathe in the engine (1.8 s). Feature check per creature (`CF.hasEngineOutline`): a client without base patch 0038 gets the old soft glow behind the player (a bottom widget) instead. `applyOutline(creature, art, pulse)` for `game_cosmetics`' sample. Settings (g_settings node `chaosCosmeticFx`) hide other players' footprints / outlines; the own character always shows. Pictures `images/prints/*.png` (64 x 64, pointing north) and, for old engines only, `images/glows/*.png` (128 x 128) from `tools/gen_cosmeticfx_art.py` (shapes and noise with a fixed seed, no reference art). Logic `cosmeticfxlogic.lua` (tested by `cosmeticfxlogic_test.lua`, which also checks a picture and outline colours for every art key of the server's `cosmetics_config.lua`, the gradients and the feature check); tested in game with two clients (server/README.md "Footprints and outlines") Print `laurel` (O318, `gen_cosmeticfx_art.py`, appended last so the other pictures stay byte for byte): the collection score's footprints Laurel Steps. |
| game_damagescatter | none (client only); the typed numbers come in the text messages (server src-patch 0051, feature 155 announced at login) | base patch 0081 (`AnimatedText:setScatter` / `setSpeedScale`), base patch 0100 (`g_map.onImpactText`, drift, fonts, follow option); without 0081 one warning and the numbers stay as they are, without 0100 slice A only | Damage numbers spread out and typed (owner request; slice A no protocol change, slice B base patch 0100 + server 0051): every damage, heal, mana and experience number gets a random pixel shift, a slightly random speed and (0100) a random drift (sideways either way, a varied rise; experience rises straight), so an area hit or a group hunt is not one column; with 0100 the server's type picks the font (a critical hit in `chaos-display-16px`, a damage-over-time tick in `chaos-outline-11px`, the rest stock), a crit floats 15% slower, and the numbers follow their creature (Options > Interface "Damage numbers follow the creature", on; set again at every game start). The server's labels (packet 0x84) keep only the shift and speed (`g_map.onAnimatedText`). Window Character > Damage Numbers: on / off and Spread (Subtle, Normal, Wide), kept per character (g_settings node `chaosDamageScatter`, key `world/name`; default on, Normal). Pure logic `scatterlogic.lua` (settings, own random generator, the roll, the group rule, types, modes, fonts, drift), tested by `scatterlogic_test.lua`; the types and the wire layout are cross-checked against both patches by `server/tests/impact_text_test.lua`. See "Damage number scatter" and "Typed impact numbers". Not run in a client |
| game_lookpreview | none (the windows hand it the picked row; the Store's offers carry a `look`, server `shop.lua`, a `bundle` option wears several parts; Cosmetics rows carry `play`, server `cosmetics.lua`) | `0038` for outlines on the preview, else a note; `0055` (through `game_groundfx`) for which effects go under the creature; reads the base `game_outfit` window; `fitCard` is called by `0060` | The shared look preview panel ("Look preview" below): the character drawn large (2x to 4x, zoomed on its body) with the picked or hovered look or effect applied by the engine, turn buttons, a slow turn, a walk toggle, the "Simple figure" toggle and "Compare with default"; a Cosmetics row's effects played in a loop around the character from the client's own sprites, a footprint's prints behind it; one widget in the Outfit window (docked at run time), Cosmetics, the Store and Pets; the Outfit window's cards facing south and filling the card (`fitCard`), the effect list icons (`effectIcon`). Logic `lookpreview_core.lua` (tested by `lookpreview_core_test.lua`); not run in a client yet `Preview:setTry(opt, ms)` / `clearTry()` (O318): a look kept on the character for `ms` milliseconds, over hover and pick, ended by the next `setOption`; used by the Store's TRY ON. A rare-loot effect row plays on the dying troll like a kill effect. |
| game_unlocks | the Cosmetics opcode 225 (`wardrobe` out; the answer `wardrobe {sex, hash, outfit, mount, wings, aura, shader}` arrives through `game_cosmetics`), server `wardrobe.lua` | `0060` (the Outfit window uses it; without the patch only the Cosmetics tabs do) | Owned and locked lists ("Owned and locked lists" below): one rule for every appearance and cosmetic list; locked entries greyed with their source in the tooltip, never usable; "Only mine" per character and list; the server's full outfit, mount, aura and shader catalogue for the Customise Character window. Logic `unlocks_core.lua` (tested by `unlocks_core_test.lua`); not run in a client yet |
| game_hideout | extended opcode 192 (JSON through `registerExtendedJSONOpcode`: `open` / `get` / `enter` / `leave` / `visit {guid}` / `place {key, x, y, r}` / `move {id, x, y, r}` / `remove {id}` / `clear` / `theme {key}` / `perm {level}` / `kick` / `visits` / `like {owner}` out; `state`, `visits`, `result` back), server `hideout.lua` | none (uses the engine's `Tile:setWidget` for the preview) | The Hideout window (Character > Hideout, next to Town Portal; a Go to Hideout button in the Portal Style window; Chaos skin, 720 x 500): Decorate (catalogue with kind / source / unlocked-only / search filters, lock reasons, Place, Open the Store for store decorations, the placed list with Move / Remove / Put all away), Hideout (themes, who may visit, Enter / Leave / Send visitors out / Like), Visit (VIP, party and guild hideouts, the showcase by likes or visits, recent visits). Placement mode: the window steps aside, a bar over the map (Rotate, Done), the hovered tile shows the decoration framed green or red (`HideoutLogic.check`, the server's rules), left click places, wheel rotates, right click ends. Logic `hideoutlogic.lua` (`hideoutlogic_test.lua` in CI); tested in game against a server copy (server/README.md "Hideouts") |
| game_visualfx | none (client only) | base patch 0126 (`Creature:flashHit`, `Creature.setSoftShadow`, `UIMap.setShake`), base patch 0127 (`g_map.setSpellLight*`, spell colour light), base patch 0132 (`g_app.setMapBloom`), base patch 0134 (`AnimatedText.setSoftMotion`), base patch 0136 (target and hover outline options), base patch 0138 (`sceneFade` option), base patch 0139 (`Creature.setDeathFade`, `deathFade` option), base patch 0142 (`Creature.setHitTint`, `hitFlash` apply), base patch 0146 (`Creature.setSmoothBars`, `smoothBars` option), base patch 0147 (`Missile.setTrails`, `Missile.addArcId`, `missileTrails` option), base patch 0153 (`g_shaders.setMapGrade`, `u_Params` / `u_Params2` of the map shader; without it the grade stays plain), base patch 0152 (`g_map.setGlowEffects`, `g_map.addGlowEffect`, additive spell effects on the `spellLight` option), base patch 0100 (`g_map.onImpactText` names the creature and the type of a damage number), base patch 0161 (`ChaosCooldownPulse.onEnd` hook in the action bar's `removeCooldown`, `cooldownPulse` option; without it no slot pulses); without 0126 the flash, shake and shadow do nothing and the grade (a map shader only) still works | Dark-fantasy look of the map, one switch per effect in Options > Graphics (all on): a creature that takes damage flashes white (red when it is the player) for 80 ms (110 ms on a critical hit), a big hit the player takes shakes the picture, creatures get a soft shadow, the map gets a vignette and a light colour grade, an optional soft glow around very bright light only (`bloom`, base patch `0132`, off by default) softer floating numbers (`numberMotion`, base patch `0134`, on) a short fade from black on a floor change or a teleport (`sceneFade`, base patch `0138`, on) a soft fade-out of a creature that dies (`deathFade`, base patch `0139`, on) and, with the same `hitFlash` switch, a soft white tint on a creature whose health percent falls (`Creature.setHitTint`, base patch `0142`). See "Visual effects (O203)". Option values are read from the settings once and kept (`L.newOptionCache`, O235): the options' apply (`onOption`) refreshes an entry, game start clears them, so a hit or a mouse move makes no settings call. with the grade on, a gentle colour mood by area that eases over 2 s (`grademood_logic.lua`, O234, base patch `0153`). On Android the first start switches off 8 heavy options once (`VisualFxLogic.MOBILE_OFF`, O313). Pure logic `visualfx_logic.lua`, `scenefade_logic.lua` and `grademood_logic.lua`, tested by `visualfx_test.lua`, `scenefade_test.lua` and `grademood_test.lua`. Not run in a client |
| game_chaosuiscale | none (client only) | base patch 0129 (`uiScale` option and line in Options > Interface, nearest filter for a whole scale); without it `g_app.scale` still works but the picture is soft | Interface scale for 1440p and 4K screens: 100 / 200 / 300 % (Options > Interface, saved per computer, applied at once). A step the window is too small for is lowered (200 % from about 2048x1152, 300 % from 3072x1728) and comes back when the window grows. Windows only: only the Windows window maps the mouse through the scale, so elsewhere the module leaves 100 %. A phone gets the highest whole step that leaves 960x540 interface pixels (a 1080-pixel-high phone: 200 %, about 1170x540) instead of the base phone zoom of 300 %, which left 780x360 and cut the login panel and the windows. On a phone the Back key (Escape) closes the options window too. See "Interface scale (O207)". Pure logic `uiscale_logic.lua`, tested by `uiscale_test.lua`. Not run in a client |
| client_chaos_uifade | none (client only) | base patch 0141 (`uiFade` option and checkbox in Options > Graphics); without it the effect stays on (the default) | Short fades on main windows and dialogs, from one hook on the `UIWindow` class. See "Window fade (O223)". Pure logic `uifade_logic.lua`, tested by `uifade_test.lua` and, on a mocked widget API, `uifade_widget_test.lua`. Not run in a client |
| client_chaos_screenfit | none (client only) | none | A window taller or wider than the screen scrolls instead of being cut off (O313): it opens with its title in view, a drag on any empty part moves it until its far edge reaches the screen edge, the mouse wheel scrolls it too. One hook on `UIWindow` (onDragMove, onMouseWheel, onVisibilityChange, onGeometryChange), installed at autoload priority 5 and copied onto the windows made before it, because a widget takes its class methods when it is made. Only windows on the root, not mini windows. A window that fits behaves as before. Pure rules `screenfit_logic.lua`, tested by `screenfit_test.lua`. Checked here in the desktop client at 1200x480: the options window opens at the top, scrolls by wheel and drag; not run on a phone |
| game_chaosweather | extended opcode 114 (server `weather.lua`: `set` server -> client, `hello` client -> server) | base patch 0130 (the `weather` option and checkbox in Options > Graphics, Lua and otui only); without it the rain still works, only the checkbox is missing (the option then stays on) | Rain over the game window, drawn by the client when the server says it rains (the same message also carries the area colour mood `m`, which goes to `game_visualfx.setMood`, O234). Three repeated 256 px rain pictures (`images/rain_*.png`, `tools/gen_rain_art.py --check`) on widgets over the game map panel only (under the side panels and the map's HUD), scrolled by `setImageRect` every 33 ms; 3 layers at most (about 130 rectangles at 1080p, 560 at 4K, all three layers), 1-3 layers by the strength 1-3, faded in and out by the server's fade, faded out under a roof (`g_map.isCovered`, every 400 ms), hidden at once by the option. Nothing runs while it is dry. Also the ambient particles (O226, `chaosambient*.lua`, `images/ember_*`, `mote_*`, `dust_*`, `tools/gen_ambient_art.py --check`; option `ambientParticles`, base patch 0144). A tick calls `setImageRect` and `setOpacity` on a layer only when the value changed (`L.newPaint`, O235; the rain rectangle moves every tick, a steady opacity and the slow ambient drift do not). Pure logic `chaosweather_logic.lua` and `chaosambient_logic.lua`, tested by `chaosweather_test.lua`, `chaosambient_test.lua`, `chaosambient_glue_test.lua`. See "Weather on the client (O208)" and "Ambient particles (O226)". Not run in a client |
| game_combatdecals | none (client only) | base patch 0148 (`combatDecals` option and checkbox in Options > Graphics); needs `Tile:setFloorWidget` of `0078`, `g_map.onImpactText` of `0100` and `AnimatedText:getColor` of `0081`; without the floor widget it draws nothing | Stains on the ground after combat (O231): blood where a monster dies, a scorch mark under a fire hit, frost cracks under an ice hit, a green stain under poison or earth. See "Combat decals (O231)" below |
| game_chestaura | extended opcode 118 (server `templar_combat.lua`: `sync` server -> client, JSON, only when the list changed) | base patch 0162 (`chestAuras` option and checkbox in Options > Graphics; without it the option counts as on); needs `Tile:setFloorWidget` of `0078`, `Tile.onAddThing` with `g_game.enableTileThingLuaCallback` and `Creature:addBottomWidget`; without the floor widget it draws no chest aura and no frame | Auras on chests and under the Templar line (O315): a looping gold sigil under reward chests (client 38758), dark smoke under cursed chests (38642), golden smoke under the Sealed Coffer (38657, the big gold chest), a slow sigil under the feet of every Templar-line player the server names and, in a party, a faint range frame. See "Chest and Templar auras (O315)" below |
| game_chaossound | none (client only; the hooks are `g_map.onImpactText` of `0100`, `Tile.onAddThing` with `g_game.enableTileThingLuaCallback`, `Creature.onHealthPercentChange`, `LocalPlayer.onLevelChange`) | base patch 0032 (`g_sounds`); without it one warning and nothing plays | Game sound (O238): short sounds for your hits and critical hits, kills, hits taken, dodges and blocks, spell casts by element (fire, ice, energy, holy, death, earth, physical, heal), level up, rare+ loot, goals and (off by default) windows and buttons. System > Sound opens a small window (master switch, four groups, volume Quiet / Normal / Loud, saved on this computer as `chaosSound`). See "Game sound (O238)". Rules in `soundlogic.lua` (`soundlogic_test.lua`), engine glue in `chaossound.lua` (`chaossound_test.lua`, mocked client). Sounds `sounds/*.ogg` from `tools/gen_sfx.py` (CC0 picks, docs/CREDITS.md "Sounds"). Not yet run in a client |
| game_waystone | extended opcode 202 (the base server's waystone script, its own JSON: `show {tiers, pick}` / `teleport_done` / `teleport_error {text}` / `choice_show {choices}` / `choice_done` / `choice_error {text}` in; `teleport {clientId}` / `choice` / `choice_apply {choiceId}` out) | none | The waystone device window (2026-10-22, player report: the device's Use did nothing, the base server's script sent `show` and no module listened): the six Waystone Tiers with the count carried (from the server, `server/tools/patch_waystone_hideout.py` part 2; a server without it: no counts, the server decides), Open portals for the picked tier (greyed when none is carried), Portal look (the unlocked pad looks in a dropdown), the server's refusals in the status line. A Waystone Tier used on the device or in the own hideout opens it with that tier picked. A reward text under the help line says what waystones pay (gear; the window is 506 high since O143, 2026-10-23). Logic `waystonelogic.lua` (`waystonelogic_test.lua`); not run in a client yet 2026-10-23: rows come from the server's `tiers` (fifteen with patch part 3: VII-XV keyed by their server ids) with each tier's monster `level` ("level 1700  2 held"); the six base rows stay for an older server. Beta 2026-10-24 ("only up to 6 on the device"): the list was a `UIScrollArea` of 258 px with no scrollbar, so only six rows of 43 px showed; it now has a `ChaosScrollBar`, and a tier not held shows its source in the status line (`W.sourceText`, the drop rule of `waystone_tiers_config.lua`). |
| game_groundlabels | extended opcode 230 (JSON), server `groundloot.lua`, `groundloot_core.lua` | none (uses the engine's `Tile:setWidget`) | Ground loot labels (ARPG style): a name plate over every item on the ground worth seeing, in its rarity colour (uniques orange, orbs teal), stack count and rarity in the text ("Rare Fire Sword", "3x Chaos Orb"), framed in the colour when the loot filter makes it glow. The loot filter decides (`game_lootfilter`'s rules and settings, `getSettings()`): hidden items get no label, Rare+ always (setting), the rest only while Alt is held (hidden ones faded). "Corpse: 2 items" over a corpse you may loot that holds loot the filter cares about. A despawn timer where something decays (a corpse: until its loot is gone, all its container stages summed; ground items do not vanish on their own in this server). Labels of one tile stack, neighbours are moved up or down past each other, at most 40 (best first). Left click picks the item up into the backpack with the normal move (the engine walks there; an item lower in a pile is first put on top by the server, `raise`) or opens the corpse; right click the usual item menu; hover the rich tooltip (`game_itemtooltip.showTip`) or the corpse contents. Tiles in view are compared every 400 ms and when the player moves (the engine has no tile-change callback for Lua); only changed tiles are asked about. Settings (on/off, Rare+, Alt, corpses, timers, size) in g_settings, window from the Loot Filter's "Ground Labels" button. Logic `groundlabelslogic.lua` (tested by `groundlabels_test.lua`); tested in game at 1280x720 and 1920x1080 (server/README.md "Ground loot labels") The loot label accent cosmetic: `setAccent(color)` (called by `game_cosmetics`) gives highlighted labels that background; text and border keep the rarity colour (`GL.style`, tested) |
| game_levelwings | extended opcode 191 (JSON `play {id, lv, n}`, server -> client, sent to every player who sees the character; server `levelwings.lua`, `levelwings_core.lua`, `levelwings_config.lua`) | base patch 0036 (the two options; without it both count as on). `Effect.create` + `g_map.addThing`; pair 36 (effect `w_fx_level_up`) | Level-up effect: when a character on screen gains a level, the level-up effect of the purchased game feel pack (pair 36, `w_fx_level_up` of `server/data/lib/chaos_pack36_fx_ids.lua`, a ring, a rising star and the words LEVEL UP in English baked into the art) plays on its tile + the effect's send offset (`LevelWingsMath.EFFECT`, checked against the ids file by `levelwingsmath_test.lua`). Since 2026-10-22 (owner: "Use as spells, level up e loot beams"); the golden wing images and `client/tools/gen_levelwings_art.py` (our own art, wings in four views since 2026-10-16/20) are retired and deleted. A pair older than 36: nothing is drawn (logged once). The stock level-up text and effect stay. Settings: Options > Graphics > Effects, "Level-up wings on my character" / "on other characters" (the old option names) switch the effect. Not run in a client yet |
| game_groundfx | none | base patch `0055` (`g_map.setGroundEffect`; without it nothing changes) | Ground effects: the effect ids of `groundfx_data.lua` are drawn under the creatures (rune circles, seals, glyphs, novas, shockwave rings, rifts, warning areas, and every effect that would cover a creature for 0.5 s or more), so spell effects no longer hide the player or the monster (owner, 2026-10-16). The list is data: `tools/sprites/ground_fx.csv` resolved to ids through the server effect catalogues by `tools/sprites/gen_ground_fx.py` (rules and the body-cover measure on the pair: server/data/spells/README_FX.md "Ground effects"; `gen_ground_fx_test.py`, `build --check` in CI). `groundfx_test.lua`. Not tested in a client yet |
| game_effectopacity | none (client only) | base patch 0049 (the one slider); without it the module only migrates the stored value | Spell effect opacity: base patch 0049 leaves one control, Options > Effects "Spell effects opacity" (the base's `opacityEffects` slider and g_settings key), 25-100% in steps of 5, for every magic effect (boss warning circles never vanish; missiles have their own slider). This module, at start: once per settings file, the value becomes the lowest one the player had set on the old controls (`opacityEffects`, Options > Effects "Own Spells" `ownSpellOpacity`, HP/MP circle "Own Spells" `spellOpacityOwn`; on 10.98 they all drove the same alpha), clamped to 25..100 (flag `chaosEffectOpacityMigrated`); later starts only clamp an out-of-range stored value. It goes through `GameOptions:setOption`, so the slider and the engine follow. No UI of its own. Logic `effectopacitylogic.lua` (tested by `effectopacitylogic_test.lua`, which also reads patch 0049: the 25 minimum, the clamp, the removed sliders, no C++). Not run in a client |
| game_rightclickequip | extended opcode 188 (JSON: `{on}` out at every login and when the option changes; `multiuse {ids}` back at login, the client ids of the multi-use weapons a right-click equips; server `rightclick_equip.lua`, `rightclick_equip_core.lua`, `rightclick_equip_config.lua`) | base patch 0037 (the option; without it it counts as on). Server src-patch 0024 does the equipping | Right-click equips items: the server puts on equipment that is used and has no use of its own, and takes a worn piece off into the backpack (server/README.md "Right-click equips"), so the base mouse controls do it with their own use click: a right-click in Classic Controls, Ctrl + click in Regular Controls, a left-click in Left Smart-Click, "Use" in the context menu. Ctrl / Shift / Alt keep their meanings. One hook: the base starts a use with on a multi-use item, and the stock weapons are multi-use (their use with breaks furniture); `game_interface`'s `processMouseAction` is wrapped so that the preset's use click on a listed multi-use weapon in the inventory or an open container sends a plain use instead. Tools that are also weapons (machete, crowbar, scythe, pick, shovel) are listed too, so they equip on a right-click; "Use with ..." stays in the menu. Option "Right-click equips items" in Options > Interface. Logic `rightclickequiplogic.lua` (the option, the message, the list, the click per mouse preset, the decision), tested by `rightclickequiplogic_test.lua`; tested in the Linux client against a live test server (every slot, both ring slots, two-handed swaps, bow and quiver, the three mouse presets, the option off) |
| game_kitewalk | extended opcode 186 (JSON: `{on}` out at every login and when the option changes; server `kitewalk.lua`, `kitewalk_core.lua`) | base patch 0039 (the option, and "Auto Chase Off" no longer switching the stance while it is on; without the patch the option counts as on). Server src-patch 0028 does the kiting | Keep attacking while moving: a walk by a click on the map or the minimap, or by keys, keeps the attack target and the attacks; the clicked path wins over Chase Opponent, melee hits when adjacent, a bow, wand or spell in range, and the chase starts again when the walk ends (server/README.md "Keep attacking while moving"). The base client never cancelled the attack on a click walk; its option "Auto Chase Off" (Options > Gameplay, on by default) switched the stance to Don't Chase on every manual walk while attacking, which 0039 skips while this option is on. Option "Keep attacking while moving" in Options > Interface (on by default). Logic `kitewalklogic.lua` (the option, the message, when to send), tested by `kitewalklogic_test.lua` (also checks patch 0039); tested in the Linux client against a live test server |
| game_tileoverlays | extended opcode 156 (JSON: `bars {s = [{i, p, n, c, v | l + t}], d}`, `clear` in; `hello` out at every game start), server `tilebars.lua`, `tilebars_core.lua` | base patch 0041 (`Tile:addOverlayWidget`, the option "Field timers over magic walls and fields"); without it a tile's single widget slot is used when free and the option counts as on | Two things drawn over map tiles, each a widget the engine draws over its tile, so they follow walking, scrolling, zoom and floor changes and take no mouse input. **Field timers** (client only): the seconds left over magic walls, wild growth, fire / poison / energy fields ("1:05" past a minute, orange in the last 5 s). The table client item id -> time until gone (each stage of a decay chain summed) is `fielddata.lua`, made by `client/tools/gen_field_timers.py SERVER_DIR` from the installed base's `items.xml` (type magicfield with a duration) and `items.otb` (server -> client ids); cycles and client ids shared by different times are left out; run it again when items change (`--check` tells). The engine's `Tile.onAddThing` / `onRemoveThing` callbacks (on while the option is on) start a timer when a field appears on a tile that was already in view, judged from where the player stood before the step that brought new tiles in; a field that came into view with its tile (walking, a floor change, the login, turning the option on) shows "~", never a guessed number. A tile the server sends again keeps its timer (same field back within 250 ms). Out of view the timers are dropped. No Chaos system creates timed fields (checked: spells and scripts). **Server bars**: a label (with "m:ss" for a countdown) over a 64 px bar in the server's colour, stacked when one tile has several; brazier captures, profession node respawns, the invasion breach (server/README.md "Progress bars over tiles"). Option "Field timers over magic walls and fields" in Options > Interface (on by default). Logic `tileoverlayslogic.lua`, tested by `tileoverlayslogic_test.lua` (also the generated table and patch 0041); generator test `client/tools/gen_field_timers_test.py` (CI) |
| game_badgeslot | 0113 (the inventory window draws slot 13, the badge slot, where the ammunition slot was; server src-patch 0058; server/README.md "Badge slot") | none | The badge slot: the empty slot 13 gets the tooltip "Badge" (`badgeslotlogic.lua`, tested by `badgeslotlogic_test.lua`, which also checks the 0113 patch text and the art), the soul label's tooltip no longer names ammunition. Its placeholder art is generated: `tools/gen_skin.py` group `badge` draws `data/images/game/slots/badge(-blessed).png` (a shield with a four-point star); the ammunition images went back to the stock arrow. The inspect window (`game_playerinspect`) names slot 13 "Badge"; the rarity glow (`game_itemrarity`), the shader effects (`game_shaderfx`) and the right-click equip (`game_rightclickequip`) cover slot 13. Until 2026-10-21 this module was `game_ringslot` (the second ring slot of src-patch 0023). |
| game_patchnotes | extended opcode 244 (JSON) + Social > Patch Notes | none | Patch Notes window (ornate skin): weeks on the left (date, title, NEW), the selected week on the right with the title, date, intro, coloured section headings (New, Changes, Fixes, Balance), bullets, sub-bullets and highlighted leads; "Don't show automatically" checkbox. The notes are Markdown files on the server (`server/data/patchnotes/`), so new notes need no client update; long notes arrive in parts. Opens by itself once per new week at login, after the Daily Reward window (server login window queue; the client also never shows it over a visible daily window). Social > Patch Notes in the top menu. Drawing and the login wait in `patchnotesview.lua` (tested by `patchnotesview_test.lua`). Server `data/scripts/chaos/patchnotes.lua`; tested in game. **Changelog tab** (2026-10-22): every server and client change that shipped, from the project history (server `changelog_core.lua`, file written at deploy time by `server/tools/gen_changelog.py`, server/README.md "Changelog"): entries grouped by date, coloured tags Server / Client / Content / Website, the client update a client change came with ("Client 55", or "Client: next update"), tag filter, NEW marks since the last look (client setting `chaos-changelog-seen`), the tab shows how many are new; the top line shows "Server updated: <date>" and this client's update and build (`ChaosUpdater.status()`, `Services.update`). The entries stay in English; the UI is in pt-BR too. The module listens with `ProtocolGame.registerExtendedJSONOpcode` (the changelog answer is chunked over 8192 bytes). Logic in `patchnotesview.lua` (tested); the tab is not yet tested in game |
| game_monkchi | extended opcode 247 (plain text `chi:<chi>:<max>:<decaySec>`, server -> client) | none | The Monk's chi HUD: five pips over the bottom of the map (server `monk_combat.lua` / `monk_chi_core.lua`). Only the Monk line (server ids 17-19) sees it; max 0 hides it. Pure helpers `chimath.lua`, tested by `chimath_test.lua`. Built, not tested in game |
| game_nameplate | extended opcode 248 (plain text `cid\|title\|color\|guild\|frame` lines; `q\|id,...` queries) + the Achievements window | base patch `0022-chaos-nameplate.patch` (`Creature:setNameplate`; the title line is the engine's `setTitle`) | Name plates over players: title in its source colour, `{guild}`, the name in gold on a 9-slice frame (`images/plate_<id>.png` from `tools/gen_nameplate_art.py`: default, gold, crimson, violet, frost, ember, verdant, bone, ashen, sapphire, rose, jade, copper, obsidian, amber, storm, and the never-sold laurel, sepulchre, infernal with a crowned ornament, and pactbound for an active Chaos Pact (O317); `nameplatemath.lua` FRAMES lists them). Cached by creature id, asks the server for players without a plate (batched); monsters and NPCs untouched. Without patch 0022 it falls back to title and guild as one block above the name. Parsing and batching in `nameplatemath.lua` (tested by `nameplatemath_test.lua`). Server `data/scripts/chaos/nameplate.lua`, `titles.lua`; tested in game Frames ember, verdant and bone added (store, server `shop.lua` FRAMES). Frame cinderwrought (crowned) added for the season pass premium track (server `seasonpass_config.lua`) Frame `gallery` (O318, `gen_nameplate_art.py`, crowned, never sold): the plate of the collection score's Connoisseur, Grand Collector and Hoard Sovereign titles. Try on (O318 follow-up): `previewFrame(frame, ms)` (called by `game_shop` TRY ON) draws a store frame on the own plate for 10 s and restores the real plate; `NameplateMath.beginTry / tryRecord / shown / endTry`, tested by `nameplatemath_test.lua`. Not run in a client yet. Frame `founder` (O322, `gen_nameplate_art.py`, crowned, never sold again): the Grand Founder Pack's plate, on sale 2026-11-20 to 2026-12-18 only. |
| game_achievements | extended opcode 250 (JSON) + Character > Achievements | none | Achievements window (Chaos skin): points of the character and the account, categories with done/total (plus All and Recently unlocked), a row per achievement with points, description, title / reward line and a progress bar ("Unlocked <date>" when done), hidden ones as "???", the title box (sends the Achievements window; shown when the server has the name plates) and the recent unlocks. Character > Achievements in the top menu. The unlock toast is game_chaosnotify's `achievement` action ("ACHIEVEMENT UNLOCKED"). Pure helpers `achievementsview.lua`, tested by `achievementsview_test.lua`; server `data/scripts/chaos/achievements.lua`; tested in game. Reward track (server message `track`): a bar to the next account point milestone with one pip per milestone (tooltip = the cosmetic's preview: kind, description, colour or label background, points to go), a "Reward track" entry in the category list (rows per milestone and per category completion, chat colours drawn in their colour, label accents behind the kind line), each category's tooltip names its completion title and cosmetic; hidden for a server without it (server/README.md "Achievements") |
| game_pets | extended opcode 254 (JSON) + Character > Pets | none | Pets window (Chaos skin): every species in a list (owned first with level and whether it is out, the others dimmed as "Not owned"), the selected one with its outfit, name and species, an XP bar (updated live after kills), its two abilities with values, cooldowns and the level the second unlocks at, how to get a species not owned yet, a rename box and Summon / Dismiss buttons, and a status line (out, resting and why, zone rule, death and call cooldowns). Character > Pets in the top menu. Pure helpers `petsview.lua`, tested by `petsview_test.lua`; server `data/scripts/chaos/pets.lua`; tested in game |
| game_buffbar | extended opcode 234 (JSON, server -> client; `sync` / `off` back) + Character > Buff Bar | none | Buff / debuff bar fixed under the character plate (`game_chaoshud`): small icons with a countdown and a stack count, left to right in rows as wide as the plate (10 icons of 26 px), buffs first, then debuffs (red border); a full row starts a new one below and the bar grows and shrinks with the rows. Anchored to the plate (left-aligned with its drawn edge, 2 px under it), so it follows the plate however it is moved (margins, `setPosition`, window resize); not movable or resizable on its own, an old saved position / size / lock is dropped. Empty: hidden (no space, clicks pass); the strip itself is phantom, so only icons take clicks. Plate hidden: the bar hides too; no plate module: the plate's own spot at the top-left of the game view. Hover for name, effect and time left; right click an icon for the settings. Everything comes from the server (`buffbar.lua`, registry `data/lib/chaos_buffs.lua`): engine conditions (haste, regeneration, food, poison, burning, freezing, drowning, energy, bleeding, slow, drunk, mana shield, invisible, in fight, skull timers ...), Chaos class buffs, world buffs, the Victory buff, Golden Hour / Chaos Storm, the day's events, double experience, trial kill stacks, chi, Rage, Reprisal, the Iron Palm stun on a player (Stunned, Stun Immunity) and the Templar aura ("<Templar>'s Aura", stacks = the reduction in percent, the tooltip with the Templar, class, reduction and the Sentinel's regeneration; icons `stunned`, `stun_immune`, `templar_aura`). Diffs only (add / update / remove) and a full list every 30 s; the countdown runs here from the milliseconds the server sent. Show / hide and countdown in the settings window (g_settings node `chaosBuffBar`). Icons: always our own `data/images/game/buffs/<name>.png`, 26x26 pixel art drawn 1:1 and unsmoothed (`client/tools/gen_buff_icons.py`, one per registry key; an ember-gold frame for buffs, a blood-red frame with corner thorns for debuffs; class buffs show their spell's art in that frame). `buff:<name>` names it; an older `spell:` / `cond:` spec falls back to the key's icon (`BuffMath.ownName`), so no stock condition art is used. Pure helpers `buffmath.lua` (order, row flow, attach to the plate), tested by `buffmath_test.lua`. Painted icons (setting "Painted icons" in the settings window, off): `images/game/buffs_painted/` ("Painted icons" below). Tested in game, see server/README.md "Buff bar and party frames"; the plate layout with 23 icons (3 rows), the plate moved by margins and by `setPosition`, hidden and shown, the rift HUD below, at 1280x720 and 1920x1080. Ember Blessings (server `blessings.lua`): one entry per kind (`blessing_xp`, `_gold`, `_damage`, `_ward`, `_speed`, `_regen`, `_crit`, `_loot`, `_rarity`, `_orb`), 60 s countdown, icons `buffs/blessing_*.png` from `gen_buff_icons.py` (motif plus an ember flame in the corner); nothing new in the module itself, tested in game with three blessings and a refresh. Vigils (server `vigils.lua`, 2026-10-12): `vigil_wrath`, `_iron`, `_haste`, `_clarity` per vigil that covers the character (stacks = the effect in percent, no timer) and `vigil_tithe` for Iron Tithe, icons `buffs/vigil_*.png` from `gen_buff_icons.py` (a banner with the vigil's emblem); nothing new in the module, not run in game. Time-friendly progression (server `catchup.lua`, 2026-10-15): `rested` (stacks = minutes of hunting left), `returning` (timer), `catchup` (stacks = percent), debuff `low_stamina`, icons `buffs/rested.png`, `returning.png`, `catchup.png`, `low_stamina.png` from `gen_buff_icons.py`; nothing new in the module, not run in game. Support spells (2026-10-17): `moonfang_pack` and `mirror_image` (Moonfang Pack 40 s, Hall of Mirrors 10 s; their spell art from `gen_buff_icons.py`); nothing new in the module, not run in game |
| game_partyframes | extended opcode 235 (JSON; `open` / `close` / `kick` / `lead` / `invite` out, `state` back) + Hunt > Party Frames | none (uses `g_game.follow`, `look`, `partyPassLeadership`, `partyLeave`, `openPrivateChannel`, `g_map.getCreatureById`) | Party frames: a movable panel with a frame per member (outfit, name in the class colour, level, leader crown, health and mana bars with numbers, floor arrow and distance, in fight / dead / connection lost, the member's first buffs and debuffs, their names listed in the frame's tooltip, e.g. a Templar's aura), live from the server every 500 ms, hidden while not in a party. Exact numbers only for members in range (50 squares, 2 floors); far members show a rough health bar. Left click selects (and follows when on), shift+click looks, right click: message, follow, look, pass leadership and remove from the party (leader), invite a player (by name), leave, copy name. Scale, own frame (off by default), buffs row, numbers, follow and lock in the gear window (g_settings node `chaosPartyFrames`). The stock Hunt > Party window (`game_party_list`, a side bar window) is untouched. Marks `data/images/game/partyframes/*.png` (`client/tools/gen_partyframe_art.py`). Pure helpers `partymath.lua`, tested by `partymath_test.lua`. Tested in game with three characters. Default position (no saved one; saved positions are kept): the right edge of the game view below the map overlay's corner box and above its strip (`PartyMath.defaultPosition` / `freeArea`, re-read as the layout changes), clear of the invasion / rift HUDs and the strip at 1280x720, 1366x768 and 1920x1080 (measured in game, tests in `partymath_test.lua`; at 1280x720 four frames with buffs cover the lower 14 px of the overlay's corner box, only in its "corner" mode); the frames stay above the map overlay |
| game_castbar | extended opcode 231 (JSON; `start` / `end` / `other` / `otherEnd` in, `cancel` out; server `casting.lua`, `data/lib/chaos_casting.lua`) | none | Cast bar of the cast-time spells over the character: spell name and time left on a dark plate, filled on the client clock from the server's cast time; the server alone completes or interrupts (moved, paralysed, new spell, portal, cancelled, failed: red with the reason for a moment); click the bar to cancel (refunded). Smaller bars over other players in view while they cast. The Town Portal channel (`game_townportal`) uses the same bar (blue). A bar whose end never came goes after 3 s. Pure parts `castbarmath.lua` (`castbarmath_test.lua`). Tested in game at 1280x720 (four spells, interrupts, death, the other-player bar with a simulated message) |
| game_bestiary | extended opcode 253 (JSON) + Hunt > Bestiary, Hunt > Kill Tasks | none | Bestiary window (Chaos skin) with two tabs. Bestiary: categories with known / total, search, "Known only", a paged list (60 rows) with the stage colour, level and kills, and the selected monster's page: outfit, stage and a bar to the next one, what the stage reveals (level, health, experience; elements, immunities, where it lives; loot as item icons with chances; Chaos uniques), the completion bonus and Take task. Kill Tasks: the daily board and your tasks with rewards, progress, Accept / Abandon (Accept greyed with the reason at a limit) and the limits line. Task tracker HUD (`tracker.otui`) at the bottom right of the visible map (anchored left of `gameRightPanels`, above `bottomSplitter`): kill tasks (T) and bounty contracts (B) with live bars; click the title to fold; on/off in the window or Hunt > Task Tracker (kept in `g_settings`). Hunt > Bestiary / Kill Tasks / Task Tracker in the top menu; toasts through game_chaosnotify (type `BESTIARY`, action `bestiary`). Pure helpers `bestiaryview.lua`, tested by `bestiaryview_test.lua`; server `data/scripts/chaos/bestiary.lua`; tested in game. Board rerolls (2026-10-15): `board.rerolls` above 0 shows "Reroll board (N)" on the Tasks tab (`reroll`), not run in a client |
| game_bossspawns | extended opcode 217 (JSON: `open` / `refresh` / `pocketEnter {k}` out, `list {now, refresh, cats, rows}`, `pocket {bosses, reset, inside}` and `pocketError {text}` back, the list chunked by `Chaos.sendChunked` and joined by `registerExtendedJSONOpcode`) + Adventure > Boss Spawns | none (menu entry through `ChaosTopBar.addEntry`) | Boss Spawns window (Chaos skin, 700 x 560, fixed size): every boss of the server by category with foldable headers (count and how many are alive), Expand all / Collapse all, a search over names and places; each row the boss outfit, name, level, place with coordinates (or a note) and the respawn column: Alive, Respawns in (countdown), In (countdown, the day and time for far ones), Random, On demand, the player's own cooldown, Respawn due, Not seen yet, with the last kill and its killer under it; the tooltip has the full rule. World, island and raid boss rows carry a Pocket button ("Pocket 2/3": charges left / daily, tooltip with the bonus charges, the reset countdown and the level; disabled without charges, under the level or while in a pocket) that opens the boss's private copy (server `pocketboss.lua`, server/README.md "Pocket bosses"); a refusal shows in the bottom line for 8 s. Countdowns tick every second in the client, the list is asked again every 30 s while open. Pure logic `bossspawnsview.lua` (`bossspawnsview_test.lua` in CI). Rendered in the Linux client with a payload made by the server core (offline, login screen);; the pocket boss NPC opens it with an `npc` action not run against a live server |
| game_riftatlas | extended opcode 210 (JSON: `open` / `alloc {id}` / `refund {id, pay}` / `reset {pay}` out; `tree` (chunked by `Chaos.sendChunked`, joined by `registerExtendedJSONOpcode`), `state`, `credit` back) + Adventure > Rift Atlas and the Rift Atlas button of the rift HUD (`game_rift/rift.otui`) | none (menu entry through `ChaosTopBar.addEntry`) | Rift Atlas window (Chaos skin, 980 x 620): a node map of the 81 nodes the server sends (drag to pan, wheel or +/- to zoom, Centre), node frames and link lines of the passive tree (`/images/passivetree/`), icons and backdrop from `tools/gen_riftatlas_art.py` (`data/images/riftatlas/`: five 21-icon sheets, `start.png`, `background.png`; procedural, the spell icon plate style); the selected node with Allocate / Refund (gold or an orb), a keystone asks first; the points counter; the completion grid (4 themes x 15 tiers, Flawless, Swift, the 3 Omens) with a tooltip per cell (a Swift cell names its tier's own time, `grid.swiftTiers`, `RiftAtlasView.swiftSeconds`; an older server's one `grid.swift` otherwise); the totals of the allocation; Reset all (gold or orbs). Pure logic `riftatlasview.lua` (`riftatlasview_test.lua` in CI; also checks the real server tree when the repository is there). Rendered in the Linux client with payloads of the server core (offline, login screen); not run against a live server. A reward note under the map (`rewardNote`, per mode: rifts pay crafting orbs and keys, waystones pay gear; O143). Waystone mode (`toggleWaystone`, Adventure > Waystone Atlas): the same window on extended opcode 159 (server `waystone_atlas.lua`, the same protocol), its own tree and state kept apart from the rift's, a grid the server sends as rows (`RiftAtlasView.listRows`: 4 map rows and Rare, each cell at its tier's column, coloured by band) |
| game_partyfinder | extended opcode 208 (JSON: `open` / `hide` / `refresh` / `post` / `unlist` / `apply` / `withdraw` / `accept` / `decline` / `queue` / `unqueue` out, `init` / `list` / `badge` / `notice` back, chunked by `Chaos.sendChunked`) + Social > Party Finder | none (menu entry through `ChaosTopBar.addEntry`) | Party Finder window (Chaos skin, 720 x 560, fixed size), two tabs. Browse: activity and role filters, "Fits my level", one row per group (activity with its tier / floor range or target, note, leader, minimum level, time left counting down, the composition as role boxes: filled in the role colour, open slots outlined, tooltip with names and classes, up to 10 in a line and a raid listing of 15 wrapped into two rows of 8 + 7 (`V.slotGrid`, the row grows); "Needs 1 Healer, 2 DPS"), Apply (a role menu when the class fits more than one open role), Withdraw, Manage for the own group; "Join as" role / activity quick-join queue with its status. My Group: the listing form (activity, range / target / title, own role, wanted counts up to the activity's caps (`V.limits`: raid 15 with 3 tanks / 4 healers / 12 DPS and a 2 / 3 / 9 proposal, others 10 and 0-6) with "group of n / max", minimum level, expiry, note, auto-accept quick joins), Post / Update, Close listing, the listing summary, and the applications (name, level, class, role, quick join, age) with Accept / Decline. A new application shows a toast (top right, click opens My Group) and a red badge on the Social menu button, the menu entry text and the tab. Pure logic `partyfinderview.lua` (`partyfinderview_test.lua` in CI). Rendered in the Linux client with payloads made by the server core (offline, login screen); not run against a live server |
| game_errorcolor | none | none | Error lines of the server ("You cannot use this object.", "You do not have enough mana.", the client's own "There is no way.") in a warm red (#ff7a5c) instead of white: gives `MessageTypes[MessageModes.Failure]` a coloured copy of the stock status-small settings (the stock table, shared with other modes, is not touched) and puts the stock entry back on unload. Pure helper `errorcolor_core.lua`, tested by `errorcolor_test.lua`. No text of its own, so nothing to translate. Not run in the client. |
| game_deadguard | none | none | Safety net for a dead monster that stays drawn at 0 percent health (removal packet lost, owner phone report): when a non-player creature reaches 0 percent (`Creature.onHealthPercentChange`) and is still on a tile 3 seconds later (the server removes it within milliseconds), it is taken off the map with `g_map.removeThing`, dropped as attack target (`g_game.cancelAttack`) and logged once with `g_logger.warning` (id and name), so a phone log shows if the root cause still happens. Players and the local player are never touched; a creature that heals above 0 or is removed by the engine in the meantime is left alone. Pure decisions in `deadguard_logic.lua`, tested by `deadguard_logic_test.lua` (luajit and lua5.3). No text of its own, so nothing to translate. Not run in the client. |
| game_lootscreen | none | none | The "Loot of a Bone Warrior: 84 gold coins." line is no longer drawn on the game screen (owner request 2026-10-27: it overlapped the character and other status text). Gives `MessageTypes[MessageModes.Loot]` a copy of the stock settings without `screenTarget` (the stock entry is put back on unload). The line still goes to the console, the Server Log and the Loot tab, so the loot feed, short numbers (`client_chaos_numbers`), trackers and the loot filter read it as before. Rare-drop announcements (a different message mode) are untouched. Pure helper `lootscreen_core.lua`, tested by `lootscreen_test.lua`. No text of its own, so nothing to translate. Not run in the client. |
| game_antibot | extended opcode 211 (JSON: `answer {t, k}` / `another {t}` / `reportOpen {name}` / `report {name, reason, note}` out; `check {t, w, o, s, a, r}` / `checkResult` / `reportOpen {name, reasons, noteMax}` / `reportResult` back) + System > Report a Player, right-click a player > Report Player | none (menu entry through `ChaosTopBar.addEntry`, the right-click entry through `game_interface.addMenuHook`) | Presence check modal (Chaos skin, 400 x 290, centred, static): "Click the picture of: <word>", four item pictures in the buff icon frame (1 px gold border on a dark plate, hover highlight), countdown bar (colour turns at 25 s and 10 s), "Another picture" (one retry), result line; the client gets client ids and random keys only, never the answer. Report Player dialog (380 x 350): name, reason box (reasons from the server), note with a counter, the privacy line (public channels only, never private messages), Send / Cancel, the server's answer. Pure logic `antibot_logic.lua` (`antibot_logic_test.lua` in CI). Rendered in the Linux client offline (login screen) with a challenge built from the server pool; not run against a live server |
| game_factions | extended opcode 215 (JSON: `open {f?}` / `close` / `turnin {f}` / `deliver {key}` / `buy {key}` / `craft {key}` out; `state` (chunked by `Chaos.sendChunked`, joined by `registerExtendedJSONOpcode`), `msg {text, ok}`, `npc {f}` (a faction NPC opens the window) back) + Adventure > Factions | none (menu entry through `ChaosTopBar.addEntry`) | Factions window (Chaos skin, 820 x 590, fixed size): four faction cards (emblem, name, rank in its colour, "<NPC> is here", rank bar with reputation / next threshold; the shown one highlighted), the shown faction's emblem, lore, rival line, rank bar, the next rank, the week against the cap (red at the cap), today's diminishing returns, tokens carried with Turn in (enabled next to the NPC with tokens and room under the cap), and two tabs: Contracts (Daily / Weekly tag, text, progress bar, reputation, Deliver for deliveries) and Quartermaster (item, name, kind or item level and rarity, price in gold and tokens, needed rank in the state colour, Buy / Craft / Locked / Owned / Sold out with the reason; tooltip with the fixed modifiers). Emblems `data/images/factions/<key>.png` and `_small.png` from `tools/gen_faction_art.py` (our own pixel art, the buff icon frame). Pure logic `factionsview.lua` (`factionsview_test.lua` in CI). Rendered in the Linux client with payloads made by the server core (offline, login screen); not run against a live server. The weekly cap rolls over (2026-10-15): a faction row may carry `wc`, its own cap this week; `FactionsView.capOf` prefers it over `weekCap` Hand-in line and Go to NPC button (O330): under the token row, `handInLabel` says where to hand tokens and deliveries in (the NPC and its place from the server's `at`; green when the NPC is next to you) and the `goNpcButton` takes you in front of the shown faction's NPC (`game_npctravel`, key `faction_<key>`; off when you already stand next to it); `V.handInText`, `V.goButton` in `factionsview.lua`, tested by `factionsview_test.lua` |
| game_descent | extended opcode 205 (JSON: `open` / `start {weekly}` / `craft` / `pick {offer, card, curse}` / `buy {key}` / `ready` / `leave` / `query` out; `info`, `hud`, `offer`, `shop`, `closeOffer` / `closeShop` / `closeInfo`, `msg {text}`, `end` back) + Adventure > Ember Descent and the portal next to the temple | none (menu entry through `ChaosTopBar.addEntry`) | The Ember Descent: run HUD under the character plate (room x / N and type, theme, run clock, depth bar, wave and monsters left, embers, reward bonus and ward, held boons and curses as 26 px icons with stacks and tooltips, party, Continue / Leave), the boon choice (three cards with icon, rank, text and a curse strip with its checkbox, a countdown), the merchant (wares with prices) and the entry window (free runs, sigils, records, forge). Pure logic `descentmath.lua` (`descentmath_test.lua`). Icons `data/images/game/buffs/descent_*.png` (also on the buff bar) from `client/tools/gen_descent_icons.py` (cells of the element icon sets in the buff frame). Tested in game against a live test server (screenshots kept outside the repository). Banked free runs (2026-10-15): `info.freeDailyCount` above 1 shows "Free descents: N ready" |
| game_raid | extended opcode 213 (JSON through `registerExtendedJSONOpcode`: `open` / `start` / `continue {id}` / `join {id}` / `leave` / `buy {key}` / `journal` / `query` out; `info`, `journal`, `hud`, `alert`, `loot`, `end`, `msg`, `closeInfo` back) + Adventure > Raid: Ashen Sepulchre and the portal next to the temple | none (menu entry through `ChaosTopBar.addEntry`) | The Ashen Sepulchre, the weekly raid: the raid window (Chaos skin, 660 x 500) with This Week (the loot lockout of each boss and the time to the reset, the raids of this week with Continue / Join), Boss Journal (per boss: intro, role hint, phases, every mechanic with its numbers, the personal loot preview) and Vendor (the week's seeded stock for Sepulchre Marks with weekly limits); Open New Raid / Leave Raid. In a raid: a HUD under the character plate (the boss and its health, phase, enrage clock, bosses slain, raiders / fallen / adds / effigies, the player's own Sundered / Hexed / Withering Hex, the last call-outs) and mechanic call-outs over the map (coloured by kind). The buff bar shows the boss debuffs (icons `buff:raid_*` from `client/tools/gen_raid_icons.py`). Pure helpers `raidview.lua` (`raidview_test.lua` in CI); server `data/scripts/chaos/raid.lua` (server/README.md "The Ashen Sepulchre, the weekly raid"); tested alone on a live test server (window, journal, vendor, HUD, call-outs, lockouts). `game_partyframes` wraps a raid of up to 15 frames into columns (`PartyMath.grid`, tested in `partymath_test.lua`) |
| game_community | extended opcode 203 (JSON: `open` / `close` / `donate {gold}` out; `state` (chunked by `Chaos.sendChunked`, joined by `registerExtendedJSONOpcode`), `msg {text, ok}`, `brazier {}` (the Great Brazier was used: opens the dialog) back) + Adventure > Community and the Great Brazier next to the main temple | none (menu entry through `ChaosTopBar.addEntry`) | Community window (Chaos skin, 720 x 600): the goal's name, text and time left, its bar (points / target, percent) with marks at 25 / 50 / 75%, four stage chips (icon, name, short buff, Active with the time left / Reached / At n%; the open one highlighted, tooltip with the full buff and hours), your contribution (points, rank, today against the daily cap, today's points per source against its cap, red at the cap, the reward rules), the top contributors, the week's world modifiers (icon, name, text, time left, "set by the staff") and Feed the Brazier. The Brazier dialog: gold carried and today's room, an amount (`150k`, `1.5m`, `25,000`), +10k / +100k / +1m, a preview (gold taken in whole thousands, points) and Give gold (only next to the Brazier). Countdowns run on the client between states. Icons `data/images/game/buffs/community_*.png` and `wmod_*.png` (also on the buff bar) from `client/tools/gen_community_icons.py` (cells of the element icon sets in the buff frame first, the rest drawn with the buff icon kit). Pure logic `communityview.lua` (`communityview_test.lua`). Rendered in the Linux client with payloads made by the server core (offline, login screen; the buff bar with the game panel shown); not run against a live server |
| game_chronicle | extended opcode 171 (JSON: `open` / `close` / `mem` / `memset {records, fallen}` out; `state` (chunked by `Chaos.sendChunked`, joined by `registerExtendedJSONOpcode`) and `mem` back) + Adventure > Chronicle | none (menu entry through `ChaosTopBar.addEntry`) | Chronicle window (Chaos skin, 820 x 580), three tabs. Chapters: the list (title, "Written on ...", "Open: n% written", "Not yet told") and the page: the story in the client's language (English or Portuguese, both sent by the server), a bar per realm goal, your points, what the written chapter changed (a note while its area is not on the map), the top contributors. Record: past seasons, who carried each chapter. Memorial: your choice (two boxes: records and realm firsts; your Hardcore fall) with Save, the question after a fall, the season's firsts, records and fallen. Pure logic `chronicleview.lua` (`chronicleview_test.lua`, also on a payload the server core builds). The tr() keys need pt-BR entries (`client_chaos_locale`). Not run in a client yet |
| game_loadouts | extended opcode 206 (JSON: `open` / `save {slot, name, icon}` / `load {slot}` / `rename {slot, name, icon}` / `delete {slot}` / `cancel` out; `state {slots, limit, active, cooldown, castMs, inPz, ...}` joined by `registerExtendedJSONOpcode`, `result {ok, text, lines}`, `cast {ms}`, `castEnd {result}` back; the channel also draws on the `game_castbar` bar, opcode 231) | none (menu entry through `ChaosTopBar.addEntry`, Character > Loadouts; the Loadouts button in the passive tree window is created at runtime from this module, `game_passivetree` is not changed) | The Loadouts (Armory) window (Chaos skin, 700 x 540): the slot list (icon, name, points / runes / gear completeness, ACTIVE / CHECK / LOCKED tags, locked slots with their unlock level), the selected loadout's summary (class and ascension, passive points, keystones, Paragon points, supports per spell, gear set completeness with every missing item and where it is, the free-refund warnings of a changed tree, the action bar profile), name box and icon button, Save / Load / Rename / Delete (Delete asks to confirm), the switching hint (instant in a protection zone, channel time, cooldown countdown, instance) and the server's answer. Client-side only: the action bar profile per character and slot (`g_settings` node `loadouts`), switched to after a load. Logic `loadoutsview.lua` (tested by `loadoutsview_test.lua`); tested in game (server/README.md "Loadouts (Armory)") |
| game_charms | extended opcode 198 (JSON: `open` / `place {ref \| pos, sid, iid, x, y}` / `move {id, x, y}` / `take {id}` / `salvage {ref, sid, iid}` / `reforge {ref, sid, iid}` out; `state {cols, rows, cells, placed, bag, groups, totals, shards}` joined by `registerExtendedJSONOpcode`, `result {ok, text}` back) | none (menu entry through `ChaosTopBar.addEntry`, Character > Charms) | The Charms window (Chaos skin, 640 x 520): the 5 x 4 charm grid (open cells, locked cells with a padlock and the unlock reason as tooltip, placed charms sized by shape with the rarity colour as border), the Cells list (level 200 / 400 / 600 / 800 and the "Edge of Ruin" achievement), Your Charms (the charms in the backpack), Totals (capped ones marked), Salvage / Reforge. Drag and drop: from the list onto the grid with a green / red preview of the cells, a placed charm to move it or back onto the list to take it out, an item from an open backpack onto the grid. A tooltip per charm. Art: each charm is drawn as an item sprite of the live pair (UIItem; stock 10.98 trinkets, one per modifier and unique, none shared, `charmsview.lua` `V.LOOKS`; 32 px, a 2x2 charm 64 px), in the skin's slots `data/images/chaos/charmslot_1x1/2x1/1x2/2x2.png` (`client/tools/gen_skin.py`, exact tile sizes, not sliced) with the loot filter's frame and glow in the rarity colour; locked cells are dimmed slots with the depot padlock. The old generated round glyphs (`gen_charm_icons.py`, `data/images/game/charms/`) are gone. Logic `charmsview.lua` (tested by `charmsview_test.lua`); tested in game (server/README.md "Charms") |
| game_professions | extended opcode 195 (JSON: `open` / `close` / `sell {id, n}` / `sellAll` out; `state {profs, bonus, cap, per, tiers, demand, areas, broker, full, capDay, late, nextDay, nextWeek, respawn}` joined by `registerExtendedJSONOpcode`, `result {ok, text}`, `levelup {k, lv}`, `npc {}` (the Material Broker opens the window) back); the gathering channel uses `game_castbar` (opcode 231) | none (menu entry through `ChaosTopBar.addEntry`, Economy > Professions) | Professions window (Chaos skin, 820 x 580): the four gathering professions (level, experience bar, tier), the experience bonus, where to gather (areas, your ready nodes, fishing, nearest town), the Material Broker's board of the week (price x demand, sold today, carried, Sell / Sell All next to a broker). Logic in `professionsview.lua` (`professionsview_test.lua`); buff icon `data/images/game/buffs/professions.png` (`client/tools/gen_buff_icons.py`). Tested in game (server/README.md "Professions") |
| game_conquest | extended opcode 167 (JSON: `open` / `close` / `buy {k}` out; `state {bal, level, pz, band, offers, groups, pity, today, cinder, refine, refineMax}` joined by `registerExtendedJSONOpcode`, `result {ok, text}`, `npc {}` (Iselde Varrow opens the window) back) | none (menu entry through `ChaosTopBar.addEntry`, Economy > Conquest Vendor) | The Conquest vendor window (Chaos skin, 720 x 560): Conquest Tokens and the level band, tabs Uniques / Set Pieces / Raid and Ascended (every offer with its look, group, level, set, price; the ones not yet seen shown locked with the server's reason), Cinderheart (Omen Keys of a chosen kind, attuning, Ascended Shards, shard and relic conversions), Refine (the worn items with a rarity: one rarity up, keeps the modifiers, adds one), Progress (bad-luck protection per group, today's tokens per source and the daily limit). One purchase at a time (the Buy buttons wait for the answer, 4 s at most; never rebuilt inside a click). Logic in `conquestview.lua` (`conquestview_test.lua`). Not run in game (server/README.md "Conquest Tokens, the Conquest vendor and bad-luck protection") |
| game_gamble | extended opcode 199 (JSON: `open` / `close` / `buy {i, w, id}` / `reroll {w}` out; `state {w, items, level, gate, near, money, left, hours, at, tz, reroll, rerolls, rerollMax, odds, npc, last}` joined by `registerExtendedJSONOpcode`, `result {ok, text, reveal}`, `npc {}` (the Gambler opens the window) back) | none (menu entry through `ChaosTopBar.addEntry`, Economy > The Gambler) | The Gambler window (Chaos skin, 690 x 610): a grid of sealed crates (look with a "?" seal, name, slot, item level, price; the rarity hidden), the countdown to the next 4-hour stock with its time and zone, Fresh Crates (the paid early refresh), the odds per crate, the reveal of the last crate in its rarity colour; buying only next to the Gambler (the server checks). One purchase at a time (every Buy button waits for the answer, 4 s at most); the answer fills the grid in place, so no cell is destroyed under the mouse; the reveal takes only client ids 1..65535 and a new engine item per look, and answers after Close or an unload are ignored. Logic in `gambleview.lua` (`gambleview_test.lua`), the window flow on a mock UI in `gamble_flow_test.lua`. Tested in game (server/README.md "The Gambler") |
| game_goals | extended opcode 178 (JSON: `open` / `close` / `tracker` out; `goals {header, goals, upcoming, gear, hunts, hereWhere}` chunked, `tracker {rows}`, `done {text}` back), server `goals.lua` + Adventure > Next Goals and Adventure > Goal Tracker (`ChaosTopBar.addEntry`) | none | Next Goals (Próximos objetivos) for every character (880 x 600, Chaos skin): the level band with its name, line and a band bar; the goals of the band (title, why, expected effort, progress bar, reward, a button: Open a window / Kill Tasks / Item Finder / Show on map, which flags the place on the minimap and centres it), up to 6 open goals of earlier bands, the band's goals done; a side column with the gear path (clickable lines), where to hunt (the teleport room hunts of the level, else the hunting grounds near the temple) and the next unlocks; a Seasonal Journey button for season characters; a "Tracker on screen" box. The tracker (`tracker.otui`) shows the first 3 open goals with bars at the left edge of the map, half way down; click the title to fold, a row to open the window (setting `chaos_goals_tracker`). Pure logic `goalsview.lua` (`goalsview_test.lua`). The tracker drops and sets its anchors again (`GoalsView.trackerAnchors`) when the geometry of the left panels, the map or the left horizontal panel changes, so it returns to its corner after Show Left Horizontal Panel is toggled; it is not draggable. Not run in a live client Ascension section (O123): below the goals, same rows and bars, the steps of the ascension quest (`ascension {rows}` on the same opcode, server `ascension_tracker.lua`); hidden once ascended or before the quest's level; shares the fold and the Goal Tracker switch; `GoalsView.onAscension` / `ascensionLine` (tested in `goalsview_test.lua`). |
| game_howitworks | none (static data, no opcode) | none | "How it works" cards (O331): one shared card per feature in very plain words, with five rows: who it is for (level, solo or party), monster levels, what drops, what a death costs, how often (a card made from an unlock entry has "What it is" and the level). The texts are `howitworks_data.lua`, GENERATED by `server/tools/gen_howitworks_data.lua` from the server configs (numbers) and `server/tools/howitworks_config.lua` (sentences, English and pt-BR in the data itself; pt-BR is turned into cp1252 here); `howcore.lua` (pure, tested by `howcore_test.lua`) finds a card by key, unlock key, goal key or window module. `howitworks.lua` (priority 900, before the windows it serves; tested on mocked widgets by `howitworks_test.lua`) API: `attach(window, key)` puts a small `?` button in the top right of a feature window (arena, battleground, Descent, raid, siege, Infinity Tower, Rift Atlas, Boss Spawns, Dungeons, Bounty, Daily, Weekly Chest, Ember Cache, Season, Factions, Gambler, Next Goals, Events, Crafting, Pets, Market: one line in each module's `init`, wrapped in `pcall`), `attachGoal(row, goalKey)` a `?` in a Next Goals row, and the "Next unlocks" lines of that window open the card on click, `showForUnlock(key)` is the `How it works` button of the "New" window of `client_chaos_topbar` (O259), `show`, `hide`, `hasUnlock`, `hasGoal`. The card is a scrolling `ChaosMainWindow` (520 x 440). Not run in a client yet. |
| game_candlemarks | extended opcode 176 (JSON: `open` / `buy {k}` out; `hud {b, p, n, e, w}` every minute, `state {balance, progress, block, earning, why, today, cap, level, weekEnds, offers}` joined by `registerExtendedJSONOpcode`, `result {ok, text}`, `npc {}` (Osric the Chandler opens the window) back) | none (menu entry through `ChaosTopBar.addEntry`, Economy > Candlemarks; the counter is anchored at runtime to the right of `chaosMenuBar`) | Candlemarks: a counter next to the Chaos menu bar (the account's balance and the minutes to the next coin, counted down in the client while earning, "paused" with the reason as tooltip; a click opens the shop) and the shop window (Chaos skin, 600 x 540): one row per offer with its look, name (with the boss for pocket boss charges), text, price, this week's use of its limit and Buy (disabled with the reason as tooltip: owned, limit, level, balance, or away from Osric); a line says whether Osric the Chandler is in range (buying only next to him, the server checks; the state carries `near`). Server texts arrive in the player's language. Logic in `candlemarksview.lua` (`candlemarksview_test.lua`). Not run in a client yet (server/README.md "Candlemarks") |
| game_pvpzone | extended opcode 193 (JSON through `registerExtendedJSONOpcode`: `open` / `query` / `enter {accept, hcAccept}` / `pledge {faction}` / `buy {key}` out; `state`, `hud`, `enter`, `hide`, `msg` back) + Adventure > Scorched Marches | none (menu entry through `ChaosTopBar.addEntry`; `g_game.setSafeFight`) | The Scorched Marches, the open-world PvP zone: the window (Chaos skin, 600 x 520: the rules, the Cinder Shrine timer and holder, the faction pledge rows, the embers vendor with item icons and weekly limits, the record; Enter; O275: a "How it works" panel of four numbered steps at the top), the entry confirmation (460 x 360: every rule, the carried embers at risk, "I understand", a Hardcore line; Enter disabled for Hardcore characters), the HUD at the top of the map in the battleground HUD's place (embers carried / cap bar, the pledge, the shrine line: timer, warden, capture progress or contested, the holder and its time left, protection or the exit channel; O275: two objective lines on top: embers carried and the way to the nearest safe exit, and during the shrine event what to do at the shrine). On entering the server's `enter {marks}` puts every safe exit and the Cinder Shrine on the minimap as flags (`addFlag`, taken off on leaving, at the game's end and, after a crash, at the next start; setting `pvpzoneFlags`). Secure mode off inside, restored on leaving. Pure helpers `pvpzoneview.lua` (`pvpzoneview_test.lua` in CI); server `data/scripts/chaos/pvpzone.lua` (server/README.md "The Scorched Marches (open-world PvP zone)"); tested on a live test server with two clients |
| game_healthcircle | none | none | In `alternates/`: the base client's own is used |
| game_mainpanel | none | none | In `alternates/`: the base client's own is used |
| game_chaosnotify (was game_notifications) | extended opcodes 79, 151, 152 | none | Needs server script (`notifications.lua`). Toast types per message kind; `sale` = ITEM SOLD with the toast scales icon (`images/toast/market.png`, as MARKET; server market.lua / orbexchange.lua: item, price, fee, proceeds, or "While you were away: ..." at login), `achievement` = ACHIEVEMENT UNLOCKED with the trophy icon (`topbutton_ranking`), `pact` = CHAOS PACT (the Pact or Pacto Completo ends in 3 days / 1 day, pact.lua, O317; its own icon `pact.png`, a gold-capped hourglass with ember sand, drawn by `gen_toast_art.py`); titles use each type's colour. Three toasts shown, stacked by their own heights (no overlap with the 140 px invitation toasts), the rest wait in a queue capped at 12 (the oldest message toast gives way). Logic `notifyview.lua` (tested by `notifyview_test.lua`); `testNotifications()` shows a sale and an achievement too. Invitation toasts (PARTY_INVITE: Accept / Decline; CATACOMB_FREE: Start / Cancel) use the styles of `toastbuttons.otui` (`ChaosToastAccept`, `ChaosToastDecline`, 80 x 24, normal / hover / pressed / disabled clips); the label is drawn by the client in the Chaos heading font when loaded. Art `images/toast/` (accept.png, decline.png, party_invite.png and catacomb_invite.png, both 48x48) comes from `client/tools/gen_toast_art.py`: iron plates with a gold rim, an ember-green or muted crimson accent; the catacomb icon is a stone archway with a skull keystone, an iron band, a gold rim and ember light on the stairs inside; the old stock yes / no scribbles, the party icon and the catacomb icon with baked text are gone; checked offline in the client (hover and pressed). Message toast icons (48x48, same generator, frame and materials, no text): GM_BROADCAST and the fallback `announce.png` (sealed scroll, gold seal), TASK_COMPLETE `task.png` (pinned parchment, check mark), BATTLE_PASS and SEASON_PASS `season_pass.png` (laurel medallion, ember stone), NEW_PLAYER `new_player.png` (lantern), ASCENSION `ascension.png` (winged flame), MARKET `market.png` (scales), INVASION `invasion.png` (crossed axes), BOUNTY `bounty.png` (wanted poster and dagger), BESTIARY `bestiary.png` (clawed tome), JOURNEY `journey.png` (compass), BOSS_POINT `boss_point.png` (crowned skull), PACT `pact.png` (hourglass); `python3 -I client/tools/gen_toast_art.py --check` fails when a shipped picture differs from the script; the stock `gm.png`, `task.png` and `battlepass.png` with baked text are gone; contact sheet of every toast type checked in the client |
| game_itemtooltip | extended opcode 242 (JSON), server `item_tooltip.lua` | none | Rewritten: server-driven rich tooltip on hover over inventory and container items (rarity, item level and tier, base stats, modifiers with roll ranges, sockets and gems, unique and set, requirements) on the Chaos tooltip plate; Ctrl shows the equipped item(s) of the same slot side by side with green/red differences; cached by per-item id and version. View logic `tooltiplogic.lua` (tested by `tooltiplogic_test.lua`); tested in game (server/README.md "Item attributes in packets and rich tooltips") Weapons add "Estimated DPS: ~N" (`b.fmt = 'est'`, server `weapon_dps_core.lua`; the compare view leaves it out for linked / inspected items like "Your Attack Interval"). The icon draws a transmog look (`tip.look`, `item:setAppearanceId`, base patch 0030), also in item link tooltips. Item set pieces: the title "Set ..." in the set green and a set block (`L.setLines`: pieces that count, every piece worn / below its level / not worn, every bonus active or dim); the cached set pieces are dropped when the equipment changes (`LocalPlayer.onInventoryChange`, `L.dropSetTips`). A tooltip with counted charges (`L.liveTip`, an exercise weapon in training) is dropped whenever its slot gets the item again and the hovered one is asked again, so the charges follow the training (server `patch_base_events.py` step 20 sends the item after every charge; `L.cacheDrop`, tested by `tooltiplogic_test.lua`; owner 2026-10-20). Tested by `tooltipsets_test.lua`; checked on a live test server (server/README.md "Item sets") Quivers (server/README.md "Infinite arrows and quivers"): the slot "Quiver", the base's implicit modifiers as signed rows in the modifier colour (`b.imp`) and the gold note line `tip.note` ("Works only while you hold a bow or crossbow."); tested in `tooltiplogic_test.lua` and in game. No ammunition count or warning in the client: the ammunition slot holds the quiver (count 1). Sources (2026-10-15): the tip's `src` (server `itemfinder.lua` `F.brief`) gives a "Drops from: ..." / "Sources: ..." line with the first two sources and, for items that come only by luck, the expected effort in gold ("~1 in 500 legendary kills", "~1 in 1,000 kills of Dragon") and the Conquest vendor price when it sells the item (`L.sourceLines`, `tooltiplogic_test.lua`). Used in (2026-10-22, owner: "Coloque pra que servem"): the optional `src.u = {n, m}` (server `K.brief`: the first two products of the item's recipes and exchanges, lowest level first, and how many more) gives a dim "Used in: Seraphic Emblem, Seraphic Bleeder +8 more" line (pt-BR "Usado em: ... +8 outros") under the sources; a server without `u` gives no line (`L.usedInText`, `tooltiplogic_test.lua`) The set block also shows for a plain piece of an open set (server `tip.set`, pair 28) with an "Active tier: n of 3" line (pt-BR in `pt_br.lua`), tested by `tooltipsets_test.lua` |
| game_chatlinks | extended opcode 249 (JSON), server `itemlink.lua`, `itemlink_core.lua` | none | Item links in chat: Shift+click an item in the inventory or a container (with the chat input active) puts `[Item Name]` in the message, up to 3; the server checks the player carries the item and keeps a snapshot of its tooltip for 10 minutes under a random id; sending writes the chip out as `[Item Name]{<r><id>}` (ASCII, readable in other clients) in ordinary speech, so default channel, party, guild, channels and private messages all carry it. Messages with links are drawn with the name in the rarity colour (unique orange); hovering one asks the server for the snapshot and shows the rich tooltip through `game_itemtooltip` (`showTip` / `hideTip`; Ctrl compares). Wraps three functions of the stock `game_console` (`Message:updateLabel`, `Message:handleMouseRelease`, `Chat:sendMessage`, `Chat:sendMapText`) and puts them back on terminate; hooks `UIItem.onMouseRelease` in front of the stock handler. No links in the Help channel (server patch `tools/patch_help_itemlinks.py` for modified clients), NPC, loot and spell tabs. Logic `chatlinks_logic.lua` (tested by `chatlinks_logic_test.lua`); tested in game with two clients (server/README.md "Item links in chat"). Its wrapped handlers return exactly one value: the engine calls a table of connected handlers (`g_game.onGameStart` / `onGameEnd`, `UIItem.onMouseRelease`) and stops the rest of the table with "function call didn't return the expected number of results" on two, which skipped every onGameStart after it at each login (party frames never asked for their state, the map overlay, rifts, ...) The parts it draws stay on the label (`label.chatParts`) so `game_cosmetics` can colour the speaker's name on top |
| game_playerinspect | extended opcode 240 (JSON), server `inspect.lua`, `inspect_core.lua` | none | Inspect Player window (Chaos skin): outfit, name, level and class, guild and rank, achievement points, best rift tier, Vocation Trial tier, the ten equipment slots with rarity frames and the rich tooltip on hover (through `game_itemtooltip`). Opened from the top menu (Social > Inspect Player: type a name, any online player) and from the right-click menu of a player (`game_interface.addMenuHook`, within 10 tiles). The Passive Tree (n) button opens the character's tree read-only in `game_passivetree` (the server's `tree` packet; it and the `equip` packets come through `Chaos.sendChunked`, parts joined by `playerinspect_logic.lua`). The checkbox "Allow others to inspect me" is the character's privacy setting (default on). Named `game_playerinspect` because the base client already has a module `game_inspect` (Inspect Object). Logic `playerinspect_logic.lua` (tested by `playerinspect_logic_test.lua`); tested in game with two clients (server/README.md "Inspect Player") |
| game_npctalk | none (the NPCs' own private talk: MessageModes.NpcFrom / NpcTo, nothing on the server) | none (replaces the hooks of the base `game_npctrade` dialog window while loaded: `tryHandleNpcDialogMessage`, `onNpcPlayerTalk`, `onNpcConversationAttempt`, `endNpcConversation`, `setNpcDialogWindowEnabled`; `game_interface.talkToNpc`; `g_game.use` on an NPC; `g_map.addThing` for the conversation NPC's map texts; all restored on unload) | NPC dialogue window: Talk (the NPC's menu, a left click with smart controls, Use / right-click with classic controls) walks into the talk radius (3 tiles; a reachable tile, so NPCs behind counters work) and says "hi"; the conversation runs in a speech bubble over the NPC (Chaos skin, tail pointing at its name, under it when there is no room above; follows the NPC and the camera every frame, kept inside the visible map between the top menu bar, the side panels and the console): name, portrait, "You: ...", the reply with clickable {keywords} (and chips), a text field, Yes / No / Trade / Bye when they fit; long replies wrap and scroll; the conversation so far in the name's tooltip (`SupportsText.wrap`). Lines of other NPCs stay in the console; the conversation NPC's lines leave the map and the console (copy to the console: "..." menu, g_settings `npcTalk.consoleCopy`). Esc, Bye or x say "bye"; walking out of range or 120 s idle close it; a second NPC gets "bye" to the first, then "hi" 1.5 s later. Every NPC line reaches the bubble twice over, through the console hook and through the game's own `onTalk` signal (`isDuplicate` makes the two copies one line; routing in `NpcTalkLogic.routeNpcLine`: NPC modes only, the conversation's NPC known by name ignoring case and spacing, or by its tile; O160). Server windows (the Oracle's Choice, the Keeper's trials, the trade window) open as usual. Off: Options > Interface > Disable NPC Dialog Window (console as before). Art `images/tail_*.png` from `client/tools/gen_npctalk_art.py`; logic `npctalk_logic.lua` (tested by `npctalk_logic_test.lua`); tested in game at 1280x720 and 1920x1080 |
| game_npctravel | extended opcode 121 (JSON `travel {k}` out; no message back: the server answers with a game message) | none | Go to NPC (O330): `modules.game_npctravel.travel(key)`, the one call behind the "Go to NPC" buttons of the panels that front an NPC's service (Factions, Gambler, Supply Stash, Boss Spawns, Candlemarks, Professions). A button is `@onClick: modules.game_npctravel.travel('stash')`; the keys are `npctravellogic.lua` `KEYS` (server `npc_travel_config.lua` `npcs`, held equal by `tests/npc_travel_test.lua`); one request a second per client, the server checks combat, instances, the cooldown and puts the player in front of the NPC (server/README.md "Travel to an NPC (O330)"). Logic and test: `npctravellogic.lua`, `npctravellogic_test.lua`. Button texts and tooltips in `pt_br.lua` |
| game_npctradewindow | extended opcode 113 (wraps `game_npctrade.show`, `refreshTradeItems`, `hide`) | none | NPC trade as a window (owner 2026-10-17): the buy / sell list of an NPC was the base mini window, 175 px wide, docked in a side panel. After the base shows it, this lifts it to the game view's root panel (where the base dialog places it too), 420 x 520 (smaller on a small view), centred and movable; tabs, prices, quantity and buttons are the base's own. Closing it ends the conversation as before. Geometry `tradewindowlogic.lua` (`tradewindowlogic_test.lua`). Currency (O189, owner beta 2026-10-24, "broken window. Where do players get azure coins?"): the 10.98 shop packet has no currency, so the base window always said "Currency: Gold Coin" and showed the gold. An NPC that trades for an item or a storage currency announces it on opcode 113 just before the shop (JSON `{action = "currency", data = {code, name, item?, amount, again?}}`, server `data/lib/chaos_npc_currency.lua`); once the base built the window this shows the currency's name and icon (none for a storage currency), "Balance:" and the player's amount in place of the gold (it replaces the base's `getPlayerMoney` while the window is open, so the buy button, the amount and the grey rows follow it; the balance packet after each purchase or sale updates it) and gives the gold back on close; a pending currency older than 15 s is dropped. Every row of every shop is rewritten to the whole item name and "Price 30, 85.00 oz" with a full tooltip (the base cut them at 15 and 16 characters). Texts "Balance:" and "Price %s" in `pt_br.lua`. Logic `tradewindowlogic.lua`; tests `tradewindowlogic_test.lua`, `tradewindow_test.lua` (glue against a mocked client). Not run in a client yet; Quick Sell / Sell All still say gold. |
| game_proficiencycatalog | none (the server has no proficiency system) | none | Weapon Proficiency window (owner 2026-10-17: it opened empty). Cause: the base window (`mods/game_proficiency`) fills its weapon list only from the server's catalogue packet, which the Chaos server never sends. When the window is about to open and no catalogue has come, this reads the weapons from the client's item data (market category or weapon type, with a name; `catalogcore.lua`, `catalogcore_test.lua`) and hands them to the window through the two functions the packet calls. The perk trees are the client's `proficiencies.json`; experience stays 0 and a perk choice is not kept (no server side). No menu entry since 2026-10-20 (owner: out of the menu); the module stays for the base window. Needs a live check that the dat holds market data for the weapons (a custom weapon without it is not listed). |
| game_outfitextras | the Cosmetics opcode 225 (`state` out, answered with `state`), the pets opcode 254 (`get`), the Info opcode 237 (`services`, `run plateframe`); reads `game_cosmetics`, `game_pets`, `game_chaosinfo`, `game_unlocks` | `0075`, `0090` | Customise Character window: the cosmetics as rows of Change Appearance (owner 2026-10-17, 2026-10-20), see below. |
| game_mapoverlay | extended opcode 245 (JSON, `watch` to the server, `marks` and `rift` back); server `map_marks.lua` | `g_minimap.clearArea` (client base-patch 0024, forgets the explored tiles of a rift square so each run starts fresh) | See-through map over the game view, centred on the character (on its drawn sprite, refreshed every frame while it walks so the map scrolls with the game view instead of jumping a tile per step; `MapOverlayMath.follow`; a step frame costs about 15 screen-to-tile lookups via `tileCentreNear`, the full view measure only runs on a resize or zoom) (Tab by default; the stock Next Channel moves to Ctrl+Tab; rebindable in Options > Hotkeys), click-through (every overlay widget but the control strip is phantom, so plain clicks, drags, hover and the wheel reach the game map; `mapoverlay_layout_test.lua` checks the .otui), Shift + wheel (or the wheel over the strip) or +/- zoom x1..x16 (toward the cursor while panned), Ctrl + wheel opacity 20-100% in 10% steps, centred or top-right box; Shift + middle-drag (or Shift + arrows, Ctrl + Shift + arrows while chat is on) to pan the map and its icons, Home / Ctrl+Home (hotkey "Minimap: Map Overlay Centre", rebindable) or the strip's Centre button snaps back to the character; while panned a "Panned" note shows on the strip and the character keeps a marker (an edge arrow when off screen); the pan is kept in memory only and resets when the overlay closes, on logout and when a new rift run starts. A compact control strip (opacity -/+, zoom -/+, Centre, Close, hint; the only clickable part, the rest stays click-through) sits in the bottom right corner of the free game view. A settings window (Hunt > Map Overlay Settings) with opacity, zoom, position, the strip switch and mark filters. Own icons (`tools/gen_mapoverlay_icons.py`) for party members, temple, depots, NPCs, rift entrance / guardian / chest / coffer / goblin, treasure goblins, world boss, invasion target and boss, dungeon bosses, and the character. Pure helpers `mapmath.lua` (pan, zoom toward the cursor, clamping, free view area; tested by `mapmath_test.lua`); server rules in `map_marks_core.lua` (tested by `tests/map_marks_test.lua`). Tested in game in town, in a hunting area and in a rift; also a party member (two clients), a rift's coffer (until it is opened or crumbles at the seal), chest, guardian and goblin, a treasure goblin, the world boss, an invasion target and boss, wheel / Ctrl+wheel / strip buttons / middle-drag pan with the icons moving with the map |
| game_mapmarkers | extended opcode 153 (JSON: `hello {party, poi}` at login and `set {party}` / `set {poi}` out; `party {m}`, `poi {v, marks}` (chunked) and `reveal {marks}` back; server `partymarkers.lua`, `poi.lua`) + Hunt > More > Map Markers | none (children of the base minimap widget, `UIMinimap:getTilePoint`, `connect` on its camera, zoom, geometry and mouse move) | Map markers on the minimap and on the full map (the same widget, Ctrl+Shift+M): the other party members as pins in a party colour (one white image tinted per member, a member keeps its colour), an up / down triangle when on another floor than the one shown, an arrow on the edge toward a member out of view (8 directions, clear of the minimap window's controls), gliding to the new place in 0.8 s; points of interest (temples, depots, banks, Chaos NPCs, shops, travel, blessings, crafting, guild hall, portals, dungeons, boss places, hunting areas), the remote ones once discovered. Game view: a coloured arrow on the edge of the game map panel (`getMapPanel()`, `getVisibleDimension()`, `LocalPlayer.onPositionChange`) toward a party member on the same floor outside the visible area, with the name and the distance in tiles next to it; none for a member in view on the same floor; a member on another floor gets a pin on their tile (in view) or the edge arrow (out of view) plus the gold floor triangle and the floors in the label (+1 up, -2 down; `gameFloorHint`; not run in a real client); refreshed on a party update and on the player's step, 150 ms at most, pooled widgets; check box "Arrows on the game view" (`game` in the settings node). Hover: name, health, floor and distance of a member, the name of a point. The markers never take the mouse (clicks, drags, the wheel stay the minimap's). Settings window with party members on / off, game view arrows on / off, points of interest on / off and a check box per category (g_settings node `mapMarkers`). Icons `data/images/chaos/mapmarkers/*.png` (`client/tools/gen_mapmarker_art.py`). Pure helpers `markermath.lua`, tested by `markermath_test.lua` (settings, colours, floor arrows, edge clamp, game view in-view test, arrow and floor hint, glide, hover text, category filters). Tested in the Linux client against a live test server with two clients and a bot in a party (server/README.md "Map markers") |
| game_minimapsync | none (client only) | base patch 0096 (the layout restore goes on after a failing window; without it the module still puts the minimap back). Reads `game_minimap`'s `minimapWidget`, `minimapWindow`, `fullmapView` and calls its `move`, `toggleFullMap`, `updateFloorImage`; `g_game` onGameStart / onMapKnown / onTeleport / onDeath / onGameEnd | The minimap ("Map View") window after a death, a respawn or a far teleport, see "Minimap after a death". Logic `minimapsync_logic.lua`, tested by `minimapsync_logic_test.lua` (also checks patch 0096). Not run in a client |
| game_sidepanelfit | none (client only) | none. Reads `game_interface`'s `getRootPanel` and the panels `horizontalRightPanel` / `horizontalLeftPanel`, and `client_settings.getOption` | The right and left horizontal panel take no space while they hold no shown window, see "Horizontal panels" |
| game_walkpad | none (client only) | none. Phones only (`g_app.isMobile()`). Finds the pad widget `keypad` that base module `client_mobile` creates and hooks it; settings keys `chaosWalkPadX` / `chaosWalkPadY` in g_settings | Movable walking pad: a 34 px handle in the pad's top left corner. Drag it and the whole pad follows (clamped inside the screen); release saves the place as a fraction of the free room. Double tap the handle: back to the default (left edge, above the health orb). Walking on the pad is the base's, unchanged. Pure rules `walkpad_logic.lua`, tested by `walkpad_test.lua` (luajit and lua5.3). No base patch. Not run on a phone: check that the pad walks, that the handle moves it, that it stays after a restart and that a double tap resets it |
| game_sidebars | none | none | Not in the overlay: it is the base client's own module |
| game_realminimap | none | none | Not in the overlay: it is the base client's own module |
| game_nameshaders | extended opcode 96 | also hooks `onOpenOutfitWindow` with extra shader lists | Needs engine and server work |
| game_dungeons | extended opcode 109 | none | Needs server script (base server has dungeon customs). Server action `open` shows the window (the base dungeon entry tile, server `tools/patch_base_dungeon.py`). Kill counter: "Kill N% of the monsters to unlock <boss>" (N = `need` of `start`, the server's `progressNeeded`, 85), and on `killed {unlocked = true}` the label and a notice "Boss unlocked!" (pt-BR "Boss liberado!"). Difficulty panel (2026-10-14): a `dungeon` payload with `health = {monsters, boss}` (six percents each: the Vault and the generated dungeons 6-9, trash 100-125%, bosses 100-225%) shows "Monster Health" and "Boss Health" from it in place of the table's 100-1300%; without the field (base dungeons, an older server) the table's texts of `dungeons.otui`; the panel is 179 px high so six lines fit (the fifth was cut before). Pure helpers `dungeonsview.lua` (panel texts, banner names; `dungeonsview_test.lua` in CI; server `dungeons_difficulty_test.lua` checks its copy of the table). Banners `images/dungeons/<name>.png` (966 x 100): the base dungeons' hand-made ones (Rootmaw now gets `Rootkraken`), and HollowVault, MarrowCrypts, IronCrucible, FallenSanctum, PyreThrone rendered from the dungeons' own generated maps with the sprite pair, the boss and monsters standing in them (`client/tools/gen_dungeon_banners.py`: `plan` with an installed server's items.otb, `build` with the pair, `--check` in CI against the plan and a fresh areagen dump, and in the live-pair job against a fresh render) |
| game_infinitytower | extended opcode 214 | none | Needs server script. It is classic-style, so no conversion was needed. The "Top Rank Rewards" podium shows the chests the server sends in `topRewards` (look = the chest's client id, tooltip = its contents; server/README.md "Infinity Tower season rewards"); before the first update the stock chest looks 2478, 2472, 2469 (the old ids 63194-63196 did not exist in the 10.98 items). O274: a tower panel over the game while inside a run (`TowerPanel` in `infinity_tower.otui`, shown on entering and hidden on leaving): the floor (boss marked), floors cleared, monsters left, the countdown to the next floor or the floor's time left, and a "Next floor now" button (hotkey Ctrl+Shift+N) that is enabled only when the server's pushed `state` (opcode 214, action `state`) says `canSkip`; the press is the action `skip`. Pure logic in `towerskip.lua`, test `towerskip_test.lua` (luajit and lua5.3). O144: the "Season Informations" panel has a `nextRewardLabel` that shows the next milestone floor, its first-clear reward and its repeatable reward from `floorRewards` of the update (server/README.md "Infinity Tower balance and floor rewards"); an "Automatic" tick beside "Next floor now" (towerskip.lua `shouldAutoSkip`, saved in g_settings `chaosTowerAutoSkip`) sends the skip once per state with `canSkip`, at most every 2 s |
| game_event | none seen in the module | none | Client-only UI; wiring to a server event system is open |
| game_creatureinformation | none | engine APIs this client lacks | Not included |
| client_terminal | none | none | Stand-in for the base Lua console: runs nothing, no Ctrl+T, no top bar entry (client/BASE.md "Lua console removed"); `terminal_test.lua` in CI; not run in a client |
| client_chaos_numbers | none | none | Short-number formatter for every module (`formatShortNumber`, `shortNumbersIn`); self test `numbers_test.lua` runs in CI; not run in a client |
| client_chaos_locale | sends `hello {lang}` on 157 (server `i18n.lua`) | none | Client language, English or Portuguese (Brazil); see "Localization". Self test `locale_core_test.lua` in CI; not run in a client |
| client_chaos_login | none | none | Login screen layout (see "Login screen" below); art from `tools/gen_login_art.py` (from the login artwork in `tools/art_src/`); tested in the Linux client at 1280x720, 1366x768, 1920x1080 and 1024x768. The living scene behind it (see "Login scene"): `loginscene_core.lua` (tested by `loginscene_core_test.lua` in CI), `loginscene.lua`; tested in the Linux client at 1280x720 and 1920x1080 |
| client_chaos_credits | none | none | Credits window (Chaos skin, 620 x 560, scrollable): every third-party source of `docs/CREDITS.md` (engine and libraries, fonts, art packs with the credit lines their licence asks for, free assets, tools), headings through `tr()` (pt-BR in `pt_br.lua`). Opened by the login screen's CREDITS button and by System > Credits (also on the login screen). Data `credits_data.lua` is generated by `tools/gen_credits.py` (cp1252 escapes; `--check`); `tools/ci/check_credits.py` checks the pt-BR headings and that every pack of the art `*sources.csv` files is listed. Pure logic `creditsview.lua` (`creditsview_test.lua` in CI). Not run in a client |
| client_chaos_charselect | none (HTTPS to the website's account API) | base patch 0050 (`Services.account`); base patch 0025 (the 10.98 list's outfits) | The character select and Create character (see "Character select" below); `charselect_core_test.lua` runs in CI; art from `tools/gen_charselect_art.py`; tested in the Linux client at 1280x720 and 1920x1080. A locked class now says "Reach level 200 with any character of your account to unlock it." (classes are not sold since 2026-10-15) |
| client_chaos_infolift | none | base patch 0111 (`Creature.setInformationLift`) | Names and bars over the head of tall looks (see "Name over tall looks" below): hands the per-look lifts of `info_lifts.lua` (generated from the pair by `tools/sprites/gen_info_lift.py`) to the engine once at start; `infolift_core_test.lua` runs in CI. Without the patch it does nothing |
| client_chaos_updater | none (HTTPS from the website) | base patches 0031, 0101, 0103 | Signed updater on the login screen (see "Signed updater" below), encrypted update files (base patch 0103); `updater_core_test.lua` runs in CI; tested in the Linux client (before the encryption) |
| client_chaos_firststart | none (HTTPS from the website) | base patches 0031, 0103, 0167, 0169 | Android only: the first-start screen of the phone client (see "Phone data" below): downloads the game data through the signed manifest's `android` section, unpacks it into the app folder, restarts; `firststart_core_test.lua` and `boot_test.lua` run in CI; not run on a phone |
| game_chaosguard | extended opcode 190 (JSON `hello {build, modules}`, client -> server, once per login) | base patch 0035 (`g_game.getChaosClientBuild`; the HMAC answer on opcode 189 is C++ only) | The client guard's Lua hello (server/README.md "Client guard"): the build and how many of our modules (`game_*`, `client_chaos_*`) are loaded; the server expects it within 30 s and at least 20 modules. `guardhello_test.lua` runs in CI; tested in the Linux client. Also holds `opcode_fuzz_test.lua`, the client half of the protocol fuzz test (every module's opcode handlers through base patch 0043's dispatcher, server/README.md "Protocol fuzz test") |

Opcode numbers above do not collide with the ones the base server already uses (106, 91, 181, 107, 202, 1, 136, 99, 201, 92, 89). The stash uses 110 and the season pass (game_battlepass) 227.

## Shared assets copied
`data/images/topbuttons/` (loot, bank, battlepass, dungeon, passive_tree, minimap), `data/images/ui/events/` (event banners), `data/images/ui/` rarity frames (copied from game_itemrarity).

## Not done
Server-side scripts, engine changes, any runtime test, translation of Portuguese/Spanish strings.

## Added after the first draft
The theme (`client_chaos_theme`, `client_chaos_topbar`, `data/images/chaos/`, generator in `tools/gen_theme_art.py`) and the admin panel (`game_admin`, opcode 120) are in the overlay too. The server counterparts are in `../server/`.

### game_admin (admin panel, opcode 120)
Opened from Admin > Admin Panel (`client_chaos_topbar`), the top-menu ADM button or Ctrl+Shift+F12; only a group the
server accepts ever gets a catalog. Everything in the window is built from the server's catalog (JSON joined from its
S/P/E parts by `ProtocolGame.registerExtendedJSONOpcode`; about 60 KB in 8 parts for group 6 since the Chaos categories,
2026-10-16). The category sidebar (186 px) scrolls with its own bar lane and shows the full label as a tooltip: 16
categories with the seven Chaos ones (Currencies, Progression, Classes, Buffs & Gear, Bosses & Events, Instances & PvP,
Guilds & Market). Category and action labels and descriptions are the server's English text, shown as sent (no `tr()`
keys, as before); the window's own strings are `tr()` keys with pt-BR in `client_chaos_locale`. No new client string.
Server side and the action list: `server/data/scripts/chaos/admin/README.md`. Not run in a client since the Chaos
categories were added.

## Visual effects (O203)
Four switches in Options > Graphics (base patch `0126`, module `game_visualfx`, `dataset.lua` keys `hitFlash`, `screenShake`,
`creatureShadow` on by default, `screenGrade` off until the owner has seen it, since it shifts the biome colours). Audit before it (grep of the base patches, BASE.md, this file, the engine tree and the shader folders): floor fading exists
(base option `floorFading`, `MapView` fades the floors), ambient light exists (Effects > ambient light slider, base light view,
the server's world light), spell light is partial (effects and missiles light by the dat's light flags, no colour table per
spell), weather is partial (the engine's `WeatherManager` has rain, snow and sand from the zone-weather packet (feature
`GameZoneWeather`; not checked here whether the server sends it; no ash; the server does not, see "Weather on the client (O208)" below), the UI scale is partial (HD scale factor option, `game_chaosscale` for numbers), water and
lava shaders, hit flash, screen shake, creature shadow and post-process did not exist.
- **Hit flash.** `g_map.onImpactText` (base patch `0100`) says which creature took a damage number and of which type. A plain or
  critical hit makes `Creature:flashHit(shader, ms)` draw the outfit with the outfit shader `chaos_hit_white` (creatures the
  player hits, and other fights) or `chaos_hit_red` (the player) for 80 ms (critical 110 ms), then the creature's own shader
  again (`chaos_outfit_hit_*.frag`, vertex stage `chaos_outfit_vertex.frag`). Damage-over-time ticks, heals, mana and
  experience do not flash; one creature flashes at most every 140 ms, and at most 8 flashes are alive at once, so an area
  spell on a pack costs at most 8 shaded outfits for 80 ms.
- **Screen shake.** Only the local player's received hits: a critical hit of at least 3% of the maximum health or any hit of at
  least 15% (the `percent` of `onImpactText`, x100). 2 px up to 30%, 3 px up to 50%, 4 px above, 180 ms falling off, no
  restart inside 300 ms unless the new hit is stronger. `UIMap.setShake(x, y)` adds a pixel shift (scaled to the sprite size)
  to `MapView::calcFramebufferSource`, so the picture, light, names and clicks move together; the map keeps a tile of margin
  around the visible area, so no edge shows. A 16 ms timer runs only while it shakes. Cap 4 px.
- **Soft shadow.** `Creature.setSoftShadow(on)`: `Creature::draw` queues one 64x32 ellipse texture (built in code once, alpha
  0 at the rim, 120/255 at most) under the feet, before the outfit, as wide as the look's tiles and the creature's draw scale;
  it stays on the tile while the creature jumps. One textured rect per visible creature.
- **Vignette and colour grade.** The map shader `chaos_map_grade` (`chaos_map_vertex.frag` + `chaos_map_grade.frag`), set on the
  game map panel by the module: 12% less colour, cool shadows and warm highlights, +6% contrast, the corners darkened by 44%.
  One texture read per pixel of the map picture, on a draw that already happens. A base map shader in use (the base's heat
  haze zones) is not replaced; turning "Enable shaders" off clears the map shader and asks the module to set it again.
- **Spell colour light (O205).** A magic effect that plays on the map lights the tiles around it for 320 ms in a colour that
  matches it (fire orange, ice blue, energy pale blue, holy gold, poison green, blood red, arcane violet, shadow dark violet,
  earth brown, healing green, water blue, death purple, physical grey), so spells glow in caves and at night. Option `spellLight`
  (Options > Graphics, on). Base patch `0127`: `Tile::addThing` asks `Map::spellLightEffect`, the engine keeps at most 12 live
  lights (a new effect finds the table full -> no light), radius 2 tiles (1-3), rise 15% / smooth fall, and `MapView::drawFloor`
  adds them to the light view, which only adds light where the ambient is low (no change on the daytime surface). The colour
  table is `L.THEME_IDS` of `visualfx_logic.lua` (211 effect ids from the stock set, ours 372-423, and the class, status and pack
  catalogs by name; combat feedback, damage ticks, warning circles, loot beams, buffs and portals have none; unknown effect ->
  no light); the module sends it to `g_map.setSpellLightColor` at game start. Without 0127 the calls are missing and nothing
  happens. Tested: the table, cap, fade, dim, option off, unknown effect (`visualfx_test.lua`). Not run in a client.
- **Living water and lava (O206).** Water and lava ground sprites shimmer: a gentle ripple of under one texture pixel (zero at the
  tile edge) and a brightness wave, a few percent on water and about 12% on lava; hue and alpha stay the sprite's own, so every
  biome keeps its colours. Option `liquidShimmer` (Options > Graphics, on). Shaders `chaos_liquid_water.frag`,
  `chaos_liquid_lava.frag` (vertex stage `chaos_liquid_vertex.frag`). Base patch `0128`: `Item::draw` looks the item's client id up
  in a byte table and draws a liquid ground through the existing shader item path; no extra pass, no Lua per tile. The module
  sends the table (`L.LIQUID`: stock water 629-634, 4597-4602 and 4609-4614, stock lava 728-730, pack water 33456-33463 and 35101, lava 35059 and 35070-35073; borders, bubbles
  and the magma floor are not liquids) at game start. Without 0128 the calls are missing and nothing happens. Tested: the id
  sets, the list, option off (`visualfx_test.lua`); the shaders compile (`check_shaders.py`). Not run in a client.
- **Soft glow (O210).** A halo around very bright light only, option `bloom` (Options > Graphics "Soft glow", default off), base patch `0132`. The owner's rule: the biome's colours stay, so the glow is built only from pixels of the finished map picture with a luma above 0.80 and screen-blended over the map (black adds nothing, white cannot get whiter); strength 0.35 (`L.BLOOM`, capped at 0.5). `visualfx.lua` creates the shaders `chaos_bloom_extract` and `chaos_bloom_blur` (vertex stage `chaos_bloom_vertex.frag`) and calls `g_app.setMapBloom(on, strength)`; the engine does the passes (cost in BASE.md 69y); a client without 0132 has no `g_app.setMapBloom` and the option does nothing. Tested: the default, the strength cap, the shader's luma numbers against `L.BLOOM` (`visualfx_test.lua`); the shaders compile (`check_shaders.py`). Not run in a client: the look, the cost and the default are open.
- **Soft damage numbers (O215).** Option `numberMotion` (Options > Graphics "Soft damage numbers", default on), base patch `0134`. Floating damage, heal, mana and experience numbers pop (75% -> 130% -> 100% size in the first quarter of their life), rise with an ease-out instead of a line, fade out smoothly and spread up to 8 px sideways by a golden-ratio step per text, so stacked hits do not sit on each other. `visualfx.lua` only calls `AnimatedText.setSoftMotion(on)` (at game start, on a change, off at terminate); the maths is in the engine header `chaostextmotion.h`. It is a layer under `game_damagescatter` (its random shift, speed and typed drift stay and add to it), not a copy of it; off gives the old motion exactly. A client without `0134` has no `AnimatedText.setSoftMotion` and the option does nothing. Tested: the default, the option wiring (`visualfx_test.lua`), the motion maths in C++ (`chaostextmotion_test.cpp`, CI, also ASan/UBSan). Not run in a client: the look (pop size and length, whether 75% text is readable), the feel of the spread beside the scatter strength, and the cost on a busy screen are open.
- **Target, follow and hover outline (O216).** Options `targetOutline` (Options > Graphics "Target and follow outline", default on) and `hoverOutline` ("Outline under the mouse", default off), added by base patch `0136` (Lua/OTUI only); no engine code, `Creature:setOutline` of `0038` is used as it is. The creature you attack gets a soft red outline with a 1.6 s pulse, the one you follow a steady green one, the one under the mouse a faint white 1 px one (`L.OUTLINE`); one creature has the strongest kind only (target, follow, hover) and the local player none. The stock target square stays (hiding it is not possible from Lua with what the module can see, so there is no `hideTargetSquare`). Event driven: `g_game.onAttackingCreatureChange` / `onFollowingCreatureChange`, and with the hover option on the map panel's `onMouseMove` (looked at every 33 ms at most, `UIMap:getCreatureAt` of `0045`, an engine call only when the creature under the mouse changed) and `onHoverChange`; a 500 ms check runs only while an outline is up (creature removed, outline lost). A bought cosmetic outline is kept: `game_visualfx` calls `game_cosmeticfx.setHighlight(id, true)` before it draws, `game_cosmeticfx` then skips that creature (and does not clear it); at the end `visualfx` clears its line and calls `setHighlight(id, false)`, which forgets the record and redraws the bought outline at once. Logout, module unload and an option turned off clear everything. Pure rules in `visualfx_logic.lua` (wanted kinds, diff, mouse gate), tested by `visualfx_test.lua`. Not run in a client: colours, width and pulse, big creatures and the cosmetic coming back are open.
- **Scene fade (O219).** Option `sceneFade` (Options > Graphics "Fade on floor change", default on), added by base patch `0138` (Lua/OTUI only, the panel grows from 219 to 238 px). Audit before it: the engine's floor fading (`floorFading`) only fades the floors above the player; the picture itself still changes in one frame on stairs, holes, ropes, portals and teleports. Chosen over a creature death dissolve (needs an engine draw change), a per-area tint (the `chaos_map_grade` vignette exists and a tint per area needs a server message) and a faded minimap or health bars (small, and the bars are drawn by the engine each frame). What it does: a black widget (`ChaosSceneFade`, `scenefade.otui`) on the game map panel, hidden and not drawn unless a fade runs. A one-floor change next to the old tile starts at 45% darkness and clears in 220 ms; a step of 4 tiles or more, or a jump of two floors or more, starts at 80% and clears in 380 ms (`SceneFadeLogic.CFG`, never above 85%). Quadratic ease-out, rounded to 1/48 so the widget is touched only when the picture changes; a running fade is never made clearer or shorter by a new one. No fade in the first 1.5 s after the game starts. Cost: while the option is on, one Lua call per step of the local player (`LocalPlayer.onPositionChange`, two subtractions); a 33 ms timer and the widget exist only for the 0.2-0.4 s of a fade; the hook is not connected while the option is off. Without `0138` the checkbox is missing and the effect stays on (the default). Tested: classify, quiet time, ease, cap, no weaker restart, widget updates per fade, option default and wiring (`scenefade_test.lua`). Not run in a client: the strengths and times, and that the black layer sits under the panels, are open.
- **Death fade (O221).** Option `deathFade` (Options > Graphics "Fade out dying creatures", default on), engine and checkbox in base patch `0139` (the panel grows from 238 to 257 px). A creature removed at 0 health leaves a copy of its last frame that fades out over 350 ms where it stood; the corpse appears at once as before. `game_visualfx` only calls `Creature.setDeathFade` (at game start, on a change, off at terminate); the work is in the engine (`chaosdeathfade.h`, `Map::removeThing`, `MapView::drawFloor`). Bounds: 32 ghosts at most (the oldest is dropped), none for the local player, one per creature, cleared on a floor change, a map clean and logout; copies only, no server state, nothing is delayed. Tested: option default and wiring (`visualfx_test.lua`), bookkeeping (`client/tools/chaosdeathfade_test.cpp`, CI). Not run in a client: the look (350 ms, smoothstep), a ghost over a creature in front of it, layered outfits when the atlas is full, and that the server sends health 0 before the removal (a creature that is removed without it just vanishes as before) are open.
- **Window fade (O223).** Option `uiFade` (Options > Graphics "Fade windows in and out", default on), added by base patch `0141` (Lua/OTUI only, the panel grows from 257 to 276 px). Module `client_chaos_uifade` (priority 520, after the theme) puts functions on the `UIWindow` class and edits no window: `onVisibilityChange` (fade in, opacity 0 -> 1 in 140 ms, ease-out cubic), `create` (a window made visible by the loader, which no show ever announces, is made clear and fades in from the first event of the next loop; one closed before that hides at once), `hide` (fade out in 100 ms, then the real hide), `show`, `isVisible` and `isExplicitlyVisible`. The base `g_effects.fadeIn / fadeOut` were not reused: they count 30 ms steps instead of reading the clock, and `fadeOut` with hide-on-finish leaves opacity at a wrong value. The timing is `uifade_logic.lua` (clock based, a fade always starts from the opacity the window has, rounded to 1/40 so the widget is touched only when the picture changes, a 16 ms timer only while a fade runs). **Input is never delayed.** A fading-in window is clickable and focused from the first frame. A closing window is phantom (clicks go to what is under it), hands its focus to the previous window in the `hide()` call (what the engine does when it hides a focused widget), and `isVisible()` / `isExplicitlyVisible()` answer false from that moment, so `UIWindow:onFocusChange` restores the game focus as before and a toggle hotkey in the next 100 ms opens the window instead of closing it twice. `show()` in the middle of a close restores the phantom flag and fades back in from the current opacity. **No invisible window is left behind:** every timer step returns if the widget is destroyed or its fade is no longer the current one; `setVisible(false)`, a hidden parent, `destroy()`, turning the option off and `terminate()` all end with the real state, opacity back to what the window had before (1 for the stock styles) and the phantom flag as it was. **Covered:** `UIWindow` instances (style `MainWindow`, `NewMainWindow`, the dialogs derived from them) at least 140x80 whose parent is the root or `gameRootPanel`; fade in on every show or creation as visible, fade out on `hide()`. **Not covered, instant as before:** `destroy()` (a ghost would keep the id of a window that is gone and break `getChildById`), `setVisible(false)` and C++ callers, `UIMiniWindow` (the side panels have their own show), phantom windows (tooltips), anything under 140x80, windows deeper in the tree, and a window that sets `chaosNoFade = true`. A module that replaces `window.onVisibilityChange` outright keeps its own and loses only the fade-in. The optional 2-4% scale or slide was left out: widgets have no scale, and a slide needs the anchors broken (windows are centred with `anchors.centerIn`). Cost: one 16 ms timer and about 9 `setOpacity` calls per open, 6 per close; nothing while no window moves. Tested: eligibility, ramps, turn rounds, rounding (`uifade_test.lua`); open, close, focus hand-over, toggle, destroy in both fades, other hide paths, windows that must not fade, own opacity, option off, terminate (`uifade_widget_test.lua`, mocked widgets). Not run in a client: the look and times, the real `UIWindow` lookup of class-level `onVisibilityChange` and of the shadowed `hide` / `show` (the same mechanism as `UIWindow:onKeyDown`), how it sits with windows that wrap their own `hide`, and the first frame of a window created visible are open.
- **Combat decals (O231).** Module `game_combatdecals`, Lua only, option `combatDecals` (Options > Graphics "Stains on the ground", default on, base patch `0148`, the panel grows 333 -> 352 px). Triggers: `Creature.onHealthPercentChange` to 0 gives blood under a monster (not the local player; names with skeleton, ghost, golem, elemental, slime and the like get none, the client knows no blood type); `g_map.onImpactText` (`0100`) gives a stain under a damage number whose colour (`AnimatedText:getColor()`) is orange (fire: scorch), cyan (ice: frost cracks) or green (poison and earth: stain); the number has no element, so the HUE is the signal (`CombatDecalsLogic.kindOfColor`: fire 15-55 deg, poison 80-160, ice 165-200, saturation 0.45 and up). Plain, critical and tick numbers count, mana and shield numbers and red, purple, blue and yellow ones do not. Each decal is a widget on the floor of its tile (`Tile:setFloorWidget`, as the footprints of `game_cosmeticfx`), turned a quarter at random, 2 pictures per kind; a tile whose floor widget another module holds gets none (a death stain tries two neighbours). Life 20-30 s drawn per decal, opacity 0.8 for the first fifth, then smoothstep to 0. Bounds: 24 alive (a death stain pushes the oldest out, a hit stain waits for room and a 250 ms gap), only inside the visible tiles of the player's floor. Cost: no timer and no per-frame work with no decal; one 100 ms `cycleEvent` while one lives, which does nothing while `g_window.isVisible()` is false (decals that ran out meanwhile go at the restore) and rescales the widgets when the tile size changed. Cleared on logout, floor change, a jump of more than a screen (teleport, map change), option off (the hooks are disconnected too). Art: `client/tools/gen_decal_art.py` (`--check` in CI; plain per-pixel maths, no filters, nothing third-party). Tested: `combatdecals_test.lua` (colour to element, caps, fade curve, on-screen test, tile choice, sizes, option) under luajit and Lua 5.3; the widget code is not tested. Not run in a client. Open: the real format of the colour `getColor()` returns to Lua (a string, a table or a userdata; `rgbOf` takes all three), the TFS colours of ice and earth in this server's fork, the look and size on the floor, a stain under a creature that dies on a tile with a ground label (skipped).
- **Light flicker (O228).** Option `lightFlicker` (Options > Graphics "Flickering fire light", default on), engine and checkbox in base patch `0149` (the panel grows from 352 to 371 px). `game_visualfx` only calls `g_map.setLightFlicker` (at game start, on a change, off at terminate); the work is in the engine (`chaoslightsoft.h`, `LightView::draw`). Warm lights (fire, torch, lava) change their radius by up to 12% with a deterministic noise of time and world tile; the soft falloff, the soft clamp of overlapping lights and the sub-image texture upload are always on. Tested: option default and wiring (`visualfx_test.lua`), the maths and the bench (`client/tools/chaoslightsoft_test.cpp`, `light_bench.cpp`, CI). Not run in a client.
- **Glowing spell effects (O233).** Base patch `0152`; no new option, the existing `spellLight` (Options > Graphics "Light the ground around spell effects") also switches it. `game_visualfx` sends `VisualFxLogic.glowIds()` (the fire, energy, holy and arcane effect ids of `THEME_IDS`, minus `GLOW_SKIP` 5 and 6) to `g_map.addGlowEffect` once and calls `g_map.setGlowEffects` with the option (at game start, on a change, off at terminate). The engine holds those effects while a floor is queued and draws them in one additive range at the end of the floor (`chaosglow.h`, `Painter::CompositionMode_AddAlpha`, `DrawQueue::setGlow`): 2 draw cache flushes and 2 blend changes per floor with glowing effects, nothing for a floor without. Tested: the rule, the list and the wiring (`visualfx_test.lua`), the bookkeeping (`chaosglow_test.cpp`, CI). Not run in a client (`client/BASE.md` "69zs").
- **Hit flash tint (O224).** Base patch `0142`; no new option, the existing `hitFlash` (see "Hit flash" above) also calls `Creature.setHitTint` through `onOption`. A health percent that falls on a creature on the map queues its outfit pieces once more as a white silhouette with an alpha that falls over 120 ms (peak 35% to 75% by hit size); heals, the first health of a creature and a death do not flash; 100 ms between flashes of one creature, 16 alive at once. See client/BASE.md 0142.
- **Area colour mood (O234).** No new option: it follows `screenGrade` (Options > Graphics "Vignette and colour grade", still off by default), because it is a part of that grade. Base patch `0153` gives the map shader two uniforms (`u_Params` rgb = tint added to the colour, `.w` = change of the colour kept; `u_Params2.x` = change of the contrast factor; all 0 = the grade of `0126`) and `g_shaders.setMapGrade(r, g, b, sat, con)` (clamped in the engine, atomics read by the draw thread). The server names the area's mood in field `m` of the weather message (opcode 114, `weather_core.lua` `moodAt`, `mood.areas` of `weather_config.lua`); `game_chaosweather` hands it to `game_visualfx.setMood(name)`; `grademood_logic.lua` holds the five presets (ice, swamp, desert, fire, crypt: tints of at most 0.036, colour change at most 0.10, contrast at most 0.03) and a 2 s smoothstep ease that starts from what is on the screen (walking along a border never jumps, a quick flicker over it never reaches the full mood). One 33 ms timer runs only while the values move; the engine is called only when a value changed at 1/1000. Leaving a region eases back to the plain grade; game start and end, the option off and unload reset at once. Tested: presets, ease, no-jump and grid rules (`grademood_test.lua`), the server lookup and field (`server/tests/weather_test.lua`). Not run in a client: the look of each preset (are they too weak or too strong), the shader on the GLES path, and the 2 s ease are open; the area boxes are guesses (server/README.md "Area colour mood (O234)").
- **Spawn fade and hit recoil (O232).** Base patch `0151`; no new option and no Lua: a creature that appears fades in over 180 ms with the existing `deathFade` switch (`Creature.setDeathFade`), and a creature whose health percent falls is nudged 1-2 px away from the player for 120 ms with the existing `hitFlash` switch (`Creature.setHitTint`). The local player never fades. See client/BASE.md 0151.
- **Smooth bars (O229).** Base patch `0146`; option `smoothBars` (Options > Graphics "Smooth health bars", default on, panel 295 -> 314 px). `game_visualfx` passes it to `Creature.setSmoothBars` (the bars over creatures, engine, `chaosbars.h`) and `dataset.lua`'s apply also tells `game_chaoshud.onOption`. `game_chaoshud` gets `hudbars_logic.lua` (global `HudBars`, tested by `hudbars_test.lua`, same timing as the engine: ease 150 ms, chip holds 250 ms and slides 300 ms, heal no chip) and two hidden chip widgets `hpChip` / `mpChip` behind the fills (`chaoshud.otui`). A track is observed when a stat changes; one 16 ms `cycleEvent` runs only while a bar or chip moves. A bar at rest is painted by the unchanged `HudMath.fillWidth`; login, logout and option off reset the tracks (no slide from empty). The experience line is not eased. The pulse on an action bar slot when a cooldown ends is the next entry.
- **Cooldown pulse (O229).** Base patch `0161`; option `cooldownPulse` (Options > Graphics "Pulse when a cooldown ends", default on, panel 371 -> 390 px). The base action bar calls the global `ChaosCooldownPulse.onEnd(button, duration, elapsed)` from `removeCooldown`; `game_visualfx` defines it (`cooldownpulse.lua`, style `cooldownpulse.otui`) with the timing in `cooldownpulse_logic.lua` (global `CooldownPulseLogic`, tested by `cooldownpulse_test.lua`): a cooldown of 3 s or more within 150 ms of its end gives a pale layer on the slot for 280 ms; one 16 ms `cycleEvent` only while a pulse is alive; game end, option off and unload remove every layer. Not run in a client.
- **Missile trails and arcs (O230).** Option `missileTrails` (Options > Graphics "Trails and arcs on missiles", default on), engine and checkbox in base patch `0147` (the panel grows from 314 to 333 px). `game_visualfx` calls `Missile.setTrails` (game start, a change, off at terminate) and sends the ids that arc (`VisualFxLogic.ARC_MISSILES`, the stock physical missiles) with `Missile.addArcId`; the work is in `Missile::draw` and `chaosmissile.h`. Tested: option default, the list and the wiring (`visualfx_test.lua`), the maths (`client/tools/chaosmissile_test.cpp`, CI). Not run in a client.
## Chest and Templar auras (O315)
Owner request 2026-10-29, looks approved from preview pictures. Module `game_chestaura` (Lua only, no engine patch of its own), option `chestAuras` (Options > Graphics "Auras on chests and Templars", default on, base patch `0162`, the panel grows 390 -> 409 px, pt-BR in `client_chaos_locale`). Files: `chestaura.lua` (the engine side), `chestaura_logic.lua` (the rules, tested by `chestaura_test.lua`), `images/` (written by `client/tools/gen_aura_art.py`).
- **Chest auras.** A floor widget (`Tile:setFloorWidget`, base patch `0078`: under the chest, creatures and walls) with 12 frames per loop, switched by image-clip every 200 ms on one 50 ms timer that runs only while a widget exists. The client finds the chests by client item id, there is no message: reward chest 38758 (`reward_sigil`, 64 px: gold pool, ring with a travelling glint, twinkles, a dashed sigil), cursed chest 38642 (`cursed_smoke`, 64 px: dark pool, smoke, embers, no ring), Sealed Coffer 38657 (`coffer_smoke`, 128 px, golden smoke, no ring, centred on the corner of the chest's tile, which is the middle of its 2 x 2 footprint). The coffer wears the big gold chest of pair 45 (server item 32312, `server/README.md` "Reward chests"). The old coffer look 4073 and the stock reward chest 21584 have no aura.
- **Finding them.** `Tile.onAddThing` / `onRemoveThing` (the engine reports tile things to Lua after `g_game.enableTileThingLuaCallback(true)`, shared with `game_tileoverlays` and `game_chaossound`) keep a small table of chest positions. A widget exists only while its tile is inside the visible tiles of the player's floor (plus one tile). Once a second the module checks the table (chest still there, still in view, widget alive), switches the callback on again when another module switched it off (and then scans the visible tiles once), and scans every 15 s as a net. An engine without the callback gets the scan every second. A tile that carries another module's floor widget (a footprint, a stain) gets no aura until it is free. Widgets go with the chest, a floor change, a minimized window (the timer does nothing), the option off and the end of the game.
- **Foot aura.** A creature bottom widget (`Creature:addBottomWidget`: drawn under the outfit, follows the walk), 24 frames at 250 ms (a turn takes 6 s), `foot/<line>_sigil.png` 64 px: Templar holy gold, Inquisitor white and ember, Sentinel steel and blue. It lies under every Templar-line player the server names (`sync`) that the viewer sees, the viewer's own character included. Created when the list arrives or the creature appears, taken back when it disappears or leaves the list. The ring's centre is moved down 12 px to the feet (`FOOT_DY`).
- **Range frame.** Only while the Templar is in a party, for the Templar and its party members: the server sets flag `p` per viewer, the client draws what it is told. One floor widget per Templar, `frame/<line>.png` (96 px, 3 x 3 tiles, a nine-slice with `image-border` 32: corners stay, edges stretch, the middle is empty), sized (2r + 1) x (2r + 1) tiles for the aura's radius r (Templar 4, Inquisitor 3, Sentinel 5, plus the passive tree's bonus; the server sends it). Hosted on the Templar's own tile, or the nearest free tile within 2 (the margins centre it) when that tile carries another floor widget; moves with the Templar by changing its margins, and gets a new widget only when the host changes. At most 6 frames at once. Tints: gold `255 214 110`, warm white `255 200 150`, blue `150 195 255`. The Chebyshev square is the same one the server uses for the aura (`M.distance`).
- **Message.** Extended opcode 118, JSON `{action = "sync", data = {t = [{i = creature id, l = 1 Templar | 2 Inquisitor | 3 Sentinel, r = radius, p = 0 | 1}]}}`, sent by `templar_combat.lua` only when the list a player sees changed (at most once a second, only to players within 16 sqm of a Templar-line player). The old holy_spiral effect every 4 s is gone.
- **Art.** `client/tools/gen_aura_art.py` draws everything from shapes and a fixed seed (numpy and Pillow, nothing third-party); `--check` is in CI (the pinned fx venv), `--preview DIR --pair PAIR_DIR` draws the looks on the real sprites. The six chest and foot strips are byte for byte the ones of the approved previews.
- **Tests.** `chestaura_test.lua` (frame index and clip, paths and the sizes of the written strips, boxes, the range square and its host, visibility rules, the message and its diffs) under luajit and Lua 5.3. The widget code is not tested.
- **Not run in a client. Open:** (1) whether floor widgets and creature bottom widgets are sized in sprite pixels (what this module assumes: the map scales them) or in screen pixels (what `game_combatdecals` and the footprints of `game_cosmeticfx` assume); `ChestAuraLogic.floorBox` is the one place to change. (2) Where a bottom widget is centred on the creature (the foot ring is moved down by `FOOT_DY`, and the margin may be ignored by the engine). (3) Whether `setImageBorder` draws the frame as a nine-slice (without it the 96 px picture is stretched whole, a thicker line). (4) The look and speed of the loops on a real floor. (5) A legacy reward chest of the 2 x 2 look (server 32310, client 38657) still on a map would show the coffer aura; the map step moves them to 32311.

## Weather on the client (O208)
Found in the base before the work: the base server sent a map effect per player every 100 ms while it rained (server/README.md "Weather on the
client (O208)"). The base client has a native `WeatherManager` (`src/client/weathermanager.cpp`: rain, snow, sand; a pool of 256 particles
drawn as lines or rects in `UIMap::drawSelf`, clipped to the map rectangle, with intensity fades), but it is reachable only through the
game-protocol packet `GameServerZoneWeather` (60, feature `GameZoneWeather`); there is no Lua binding for `g_weatherManager`, and the
stock server never sends the packet (nor does ours: it would need a server engine patch). There is no `ParticleManager`: `g_particles` is an
empty stub, `ExtendedIds.Particles` has no handler, and no `.otps` file exists. No weather or rain module existed. Using the native manager
would have taken a client patch (a Lua binding, 0130) and a server engine patch for the packet, so the module draws the rain with widgets
instead, and base patch `0130` is Lua and otui only (the option).
Module `game_chaosweather`: the server's `set {k, i, f}` (opcode 114) gives rain or none, the strength 1-3 and the fade; `chaosweather.lua`
makes a clipping root widget on the game map panel (`insertChild(1, ...)`, so the panels and the map's HUD stay above it) and one
`image-repeated` widget per layer (far, mid, near); every 33 ms `setImageRect` moves each picture by whole pixels (down and 0.3 right
for each pixel down, the slant of the streaks; the tiles wrap, so no seam), and the layer opacity follows the fade. Strength 1 shows a
thin far layer, 2 far and near (the nearest to the base's density), 3 all three. The picture is cheap: three widgets, their cached
vertex buffers rebuilt per step (about 40 rectangles each at 1080p) and nothing else. The timer and the roof check (`g_map.isCovered(pos, 0)`
every 400 ms) run only while it rains or still fades. The option `weather` (default on) comes from `game_visualfx` (`L.OPTIONS`, `onOption`
-> `modules.game_chaosweather.setEnabled`). Tested: the message parse and clamps, the targets, the fades, the scroll wrap and slant, the
rectangle covering the widget at 1x1 to 4K, the quad cap, the art sizes, the option wiring (`chaosweather_test.lua`, `visualfx_test.lua`); the
art against its generator (`gen_rain_art.py --check`, one tile also rendered to a PNG by hand). Not run in a client: the look (density,
speed, colours), the frame cost, whether `setImageRect` on a repeated image rebuilds as the source reads, whether `isCovered` fires next to a
building's south-east wall (the engine's rule looks one tile up and diagonally), and where the root sits among the map panel's children.
## Ambient particles (O226)
Brief: slow embers or ash in burnt places, fireflies or motes in forests and swamps, dust in caves; cheap, capped, nothing with the option off or the window hidden.
Rendering choice: the base client has no particle system a module can use (`g_particles` is an empty stub, no `.otps` files exist), and the native weather manager has no Lua binding (see O208 below), so no engine change: the same repeated-image widgets as the rain, inside `game_chaosweather`. `tools/gen_ambient_art.py` (Pillow, plain geometry, `--check` in CI) draws six seamless 512 px tiles: `ember_far/near` (orange spark, bright core, short tail), `mote_far/near` (soft pale green-yellow glow), `dust_far/near` (faint warm grey specks). A kind shows its two layers; `chaosambient.lua` moves each image rectangle by whole pixels every 50 ms (a slow drift plus a sine wander; embers rise, motes twinkle by an opacity pulse of 0.6-0.7 depth, dust does not), fades layers in and out by the server's fade (a change of mood cross-fades), and sets the root under the panels like the rain.
Area mood, chosen: the server (option 1 of the brief) adds an optional `a` (`embers` / `motes` / `dust`) to the weather `set` message from `weather_config.lua` `ambient.areas`; the old payload is unchanged outside a region, an unknown name shows nothing (`ChaosAmbientLogic.parseKind`). Deriving the mood from the tiles around the player was rejected: ground ids of forest, swamp and burnt land are only known by item name from the installed base data, which is not in the repository, and a scan per step would cost more than one lookup per 3 s tick on the server. See server/README.md "Ambient particles (O226)".
Caps: two layers per kind, at most 24 specks per 512 px tile for a kind (12+5 embers, 9+4 motes, 16+6 dust; the test compares the generator's numbers), about 40 rectangles at 1080p and 200 at 4K (`maxQuads`). Idle cost is zero: no widget until a mood is first shown, no timer while there is no mood, the option is off or the layers have faded out. Hidden window: every tick asks `g_window.isVisible()`; false hides the layers, stops the 50 ms timer and starts one 1 s poll, true fades the mood in again. Option `ambientParticles` (Options > Graphics "Ambient particles", default on, base patch `0144`, Lua and OTUI only, the panel grows 295 -> 314 px) comes through `game_visualfx` (`onOption` -> `modules.game_chaosweather.setAmbientEnabled`); without 0144 the checkbox is missing and the effect stays on. Terminal: `modules.game_chaosweather.ambientState()`.
Tested: message parse, option, targets, fades, cross-fade, idle stop, drift range and step size (at most 4 px), twinkle band, rectangle cover, caps, art sizes and counts against the generator (`chaosambient_test.lua`); timers and widgets with a mocked engine: hidden window, option off, mood change, reset (`chaosambient_glue_test.lua`). Not run in a client: the look (size, density, speed, colours), that `g_window.isVisible()` is false on a minimized window, the cost of `setImageRect` per tick on 2 repeated widgets, the root's place among the map panel's children.
## Game sound (O238)
Brief: the game was silent except for the loot filter's rule sounds; short sounds for the fight, spells and rewards, never noisy, with the client's own audio options respected.
Module `game_chaossound` (Lua and OTUI, no base patch beyond `0032`; autoload priority 1001). Window System > Sound (`ChaosSoundWindow`): master switch, groups "Hits, kills and damage taken", "Spells by element", "Level up, rare loot and goals" and "Windows and buttons" (off by default), volume Quiet 0.35 / Normal 0.7 / Loud 1.0. No new checkbox in the Options panel (its height is tight and the base has no visible audio option: the dataset keys `enableAudio`, `musicSoundVolume`, `uiSounds` have no panel; the sound pages of `settings.lua` are commented out).
Volume chain: module volume x the Effect channel's gain (`SoundChannels.Effect`; the Interface group uses the UI channel `ENumericSoundType.UI` when the client has it) x distance fade x the set's gain. `g_sounds.isAudioEnabled() == false` (the client's global audio switch) or a disabled channel mutes everything. Sounds are played with `g_sounds.play`, not `channel:play`: `SoundChannel::play` stops the channel's current source, so the Effect channel plays one sound at a time (and would cut the loot filter's alert). `SoundSource` has no Lua bindings (no `setPitch`), so the variation is 2-3 recorded variants per event, never the same twice in a row.
Events: your hit (`hit`) and critical (`crit`) from `g_map.onImpactText` mode 21 types 0/1; a hit you take (`hurt`) mode 22; a kill when a monster you hit in the last 2.5 s reaches 0 health (`Creature.onHealthPercentChange`; the number's `percent` is the hit's share of max health, not the remaining health); dodge (effect 416) and block (stock effect 3) on the player's own tile only; spell casts from any magic effect added to a tile, id -> theme through `modules.game_visualfx.VisualFxLogic.EFFECT_THEME`, theme -> sound set `ChaosSoundLogic.THEME_SOUND` (fire, ice = frost, energy and arcane, holy, death and shadow, earth and poison, physical, heal = healing; blood and water are silent); level up (`LocalPlayer.onLevelChange`, not at login); rare+ loot (`game_lootfilter` calls `modules.game_chaossound.onLootKill(data, alerted)` for each kill: unique 100 / Legendary / Rare tiers, silent when the loot filter's own rule sound played for the kill, so a drop sounds once; `game_lootbeams` makes no sound); goals (`game_goals` calls `onGoalDone`); windows (`UIWindow.onVisibilityChange`) and buttons (`UIButton.onMouseRelease`), not in the first 2.5 s of a game. Other modules may call `playEvent(key, dist)`.
The tile callback switch `g_game.enableTileThingLuaCallback` is shared with `game_tileoverlays` (it turns it off with its option); the module re-asserts it every 2 s while spell or combat sounds are on and the player is in game.
Limits (`ChaosSoundLogic`): events farther than 9 tiles (or on another floor) are skipped, nearer ones fade from full at 1 tile to 35% at 9; one event key has a gap (hit 90 ms, spells 160 ms, hurt 350 ms, level up 3 s ...); at most 3 sounds start inside 400 ms (5 for kill, crit, loot, goal, level up); at most 10 ordinary sounds a second; at most 6 sounds sounding at once (by file length), 8 for the important ones. An area spell on 20 monsters therefore plays about three sounds.
Sounds: 45 mono 44.1 kHz Ogg files (257 KB in all, each under 1.1 s) picked from four CC0 packs, cut and levelled by `client/tools/gen_sfx.py` (`--packs DIR` builds, `--check` verifies the committed files against `client/tools/sfx_sources.csv`: hash, mono, rate, length, total size; CI runs `--check`). Packs, authors and licence: docs/CREDITS.md "Sounds".
Tested: event mapping, theme mapping against the real `visualfx_logic.lua`, kills, loot, settings, distance, gap, burst, cap, variants, an area spell and a long fight (`soundlogic_test.lua`); the guards around `g_sounds` (absent, audio off, channel off or muted, failing `play`, one log line), the loot and goal hooks (`chaossound_test.lua`, mocked client). Not run in a real client: how the sounds feel, whether `onMouseRelease` / `onVisibilityChange` reach buttons and windows that define their own handler (a widget's own `onClick` / `onVisibilityChange` replaces a class-level one), and the real value of `Tile.onAddThing` for effects.

Streaming fix (2026-10-27, client log: `unable to refill audio buffer for '.../levelup.ogg': Out of Memory`, then `Invalid Name` 111 times, also for the loot filter's `chime.ogg` and `fanfare.ogg`). Cause, read from the engine (`soundmanager.cpp`, `streamsoundsource.cpp`): `g_sounds.play` plays a file from a preloaded buffer only when `g_sounds.preload` cached it, and `preload` keeps a file only when it decodes to at most `MAX_CACHE_SIZE` = 100000 bytes; anything else (and every file that was never preloaded) goes through a `StreamSoundSource` with four 100 KB buffers refilled every 100 ms. `levelup.ogg` (1.3 s mono 44.1 kHz = 114660 bytes) was over the limit, so it streamed on every level up; the loot filter never preloaded its sounds, so all of them streamed. A stream whose buffers fail (the first OpenAL error is `Out of Memory`; the later ones are the sticky error read by the next refill, `Invalid Name`) is never stopped by the engine (an underrun restarts it each poll), so it kept logging for as long as the client ran. Fixes: `levelup.ogg` is cut to 1.0 s (88200 bytes; `sfx_sources.csv` `trim_ms` 1000, new hash; the set's `ms` 1000) and `gen_sfx.py --check` now fails any sound that decodes to more than 100000 bytes; `game_lootfilter` preloads its five sounds at login (they are 30 to 40 KB decoded); `game_chaossound` never hands a missing file to the engine (one warning per file), tracks each source it starts (`S.track`) and every 2 s stops the ones past their length + 1.5 s and lets the ended ones go (`S.reap`; unit tested). The engine itself (a failed stream should stop, `alGetError` should be read after each call) is not patched: the base sound sources are not in this repository.

## Interface scale (O207)
Found in the base: `g_app.scale(f)` / `scaleUp` / `scaleDown` (used by the phone client only; no option, no text). It renders the
whole UI at window size / f into a framebuffer and stretches it; Win32 divides the mouse position by f. Missing: a setting, and a
sharp stretch (the framebuffer was linear-filtered). Base patch `0129` adds the nearest filter for whole factors and the option;
module `game_chaosuiscale` applies it. Steps are 100 / 200 / 300 % only because the fonts are bitmaps (a fractional stretch is
uneven). Limits: the interface keeps at least 1024x576 pixels (1080p: 100 % only; 1440p: up to 200 %; 4K: up to 300 %). The saved
value is the step index in the client's settings file. Tested: parsing, clamping, what fits (`uiscale_test.lua`). Not run in a client.
Skipped, with the reason: floor fading and ambient light already exist; weather and the UI scale are
partial and need a server packet, art or an engine rewrite; water and lava shaders were skipped
at first and came later as O206 (above); bloom needs a second framebuffer and a blur pass per
frame (costly on a weak PC). Not run in a client: the first build should check the Graphics tab fits
the four new rows (window 685x531), the flash on a pack, a shake from a boss hit, and the frame rate with all four on and off.

## Lazy modules (O202)
Two modules with a window that is opened rarely and no server push load on first use (`autoload: false`) instead of at start:
`game_codex` (the Codex, 800 KB of generated data, no opcode) and `client_chaos_credits` (the Credits window, no opcode).
Startup loads 125 modules instead of 127 and about 5.28 MB of Lua and OTUI instead of 6.15 MB (-0.87 MB, -14%; counted
from the `.otmod` files, not timed in a run). The menu entries stay: `client_chaos_topbar` (`LAZY_MODULES`) draws them
without loading and runs `g_modules.ensureModuleLoaded(name)` when one is used (Economy > Codex, Alt+K; System >
Credits). Callers that read the module ask for it first: `client_chaos_login` (CREDITS button), `game_itemfinder` (Codex
link), `game_market` (modifier choices) and `game_crafting` (right-click on a modifier; its tooltip only needs the module
to exist). A module stays eager when it registers an extended-opcode handler (it must receive server pushes), connects
`onGameStart` or keeps an event running; 100+ modules do. Add a name to `LAZY_MODULES` only for a module that has none of
those and whose callers load it.

## Healing helper: no replay after a stall (base patch 0026)
`base-patches/0026-helper-no-cycle-replay.patch` (`mods/game_helper/helper.lua`): the helper's cycles schedule their next run from now (after a client stall they run once instead of replaying every missed 50 ms cycle) and its spell casts go through a rate guard; tested in game (one cast after a 2.5 s stall, 17 before).

## HD upscaling: xBRZ 1.8 (base patch 0027)
`base-patches/0027-xbrz-1.8.patch`: xBRZ 1.4 -> 1.8 with edge padding per sprite; before/after compared in the Linux client at x2, x3 and x4 (outfits and items) and offline on effects (see `BASE.md`).

## Monster bar (new)
`game_monsterbar` (opcode 125) shows a bar at the top of the map for the creature you attack. The server side is `server/data/scripts/chaos/monster_tiers.lua`. The client's own `game_boss_health` was not reused: it waits for a native boss-health packet that the 10.98 server does not send.
Look (`monsterbarstyle.lua`, tested by `monsterbarstyle_test.lua`): seven styles from the server's tier and role: normal (plain iron, rivets), magic (sapphire gems), rare (gold filigree, topaz), legendary (iron flame crowns, ember gems), boss (bone horns over skull caps, crimson), guardian (a rift guardian: the boss look with violet rift shards) and omen (an Omen guardian: obsidian band, pale gold crescents, violet omen eye). The name and the level (`Lv N`) sit on iron plates in the style's colour, in the theme's heading font when it is loaded; a long name drops the tier word, and a name still wider than the widest plate (300 px) is cut with "..." (`fitTitle`). The longest titles fit whole: "Sangrith the Bloodmoon Herald" 220 px (its "Omen Guardian" tag dropped), "Rift Guardian Abyssal Sovereign" 224 px, "Kaelgor the Infernal Warlord" 214 px, of 272. Bosses and rift guardians are named in `#ff6a50` (the fill's sheen) on the bar and in the world: the UI red `#e03a1e` was hard to read on dark ground and on a red boss; the test checks every tier colour for 4.5:1 on dark red-black ground and the boss colour for 3:1 on a red body. Names in the world are drawn over the light since base patch 0042 (`BASE.md`). The fill is blood red for every style (a sheen in the style's colour), with a damage trail: the part just lost stays lit for 350 ms, then shrinks to the health. Modifiers are 26 px chips under the bar in the buff-icon style with the blood-red debuff frame (a threat to the player), with tooltips. `preview(info)` shows the bar with made-up data (screenshots, checks).
Art: `tools/gen_monsterbar_art.py` writes `data/images/chaos/monsterbar/` (frame_, fill_, plaque_<style>, trail, mods/<modifier>). It reuses the gen_skin.py materials (iron, gold, gems, rivets, the HUD fill) and the gen_buff_icons.py motifs and frame; every alpha edge is hard, with no blur or glow halo. The small bars over creatures are drawn by the engine (a 27x4 rect in the creature's information colour); tiered monsters get their style's colour there through `setInformationColor`, as before. Checked offline in the client with injected data (every style, the tooltip); not yet in a live fight.
Placement (`monsterbarmath.lua`, `monsterbarmath_test.lua`): the bar is a child of the map panel, which in the extended view starts above the window (y -80 at 1280x720). The bar goes 6 px under the top menu bar, centred over the character, moved right of the character plate when they would touch (1024x768). It is placed again when the map panel changes size. Checked in game at 1024x768, 1280x720, 1366x768 and 1920x1080.
Boss cast bar (`monsterbarmech.lua`, `monsterbarmech_test.lua`, `monsterbarmech.otui`, 2026-10): the action `mech` on the same opcode 125 (server `boss_mechanics.lua` and `raid.lua`, server/README.md "Boss mechanics") names the next boss mechanic with a countdown, "Kaelgor: Meteor Rain 2.4s - move out", in a 344 x 18 bar under the monster bar (in its place when nothing is targeted). Colour by kind: red telegraph (move out), purple channel (kill the totem), green soak (stand in the circle), blue line of sight (hide behind a pillar), grey interrupted. It holds 600 ms after the hit, then hides. `previewMech({ boss, label, ms, kind })` shows it without a server. Seen in a live fight on 2026-10-14 (Kaelgor, Sangrith). Live test 2026-10-14: with no monster targeted the bar sat at the monster bar's otui margin (44 px from the top of the map panel, which starts above the window in the extended view: y -28, off screen); `placeMech` now works out the monster bar's place first (`MonsterBarMech.margins`, tested with the 1280x800 view).

## Outfit shaders for monsters (new)
`game_chaosshaders` registers the 17 shader names the server sends (same list as the base client) using the files in `overlay/data/shaders/`, and `ember_pixent` (`pixent_ember.frag`: `pixent_green.frag` with an ember colour; shader 18 of the server's exclusives, a boss drop). It also registers six outfit shaders written for this server, shaders.xml ids 19-24 (server/README.md "Cosmetics", "Chaos outfit shaders"; off on the server as shipped): `chaos_ember_glow` (a flickering ember rim, warm light, sparks drifting up), `chaos_frost_rime` (cooled to ice, a white-blue rim, crystals that glint), `chaos_void_flicker` (violet dark, a flickering edge, bands that drop out), `chaos_holy_radiance` (a breathing gold light, slow rays, a bright rim), `chaos_blood_pulse` (a heartbeat floods it red and lights veins), `chaos_spectral_ghost` (pale and see-through, a cold rim, rising waves). Vertex stage `chaos_outfit_vertex.frag`, fragments `chaos_outfit_*.frag`; they keep the outfit's four colours (the template layer) and lay their noise out in sprite pixels. Compile-checked (`tools/check_shaders.py`); `chaos_ember_glow`, `chaos_void_flicker` and `chaos_blood_pulse` were seen worn in the Linux client (below). The monster modifiers in `monster_tiers.lua` pick one of them per monster, and the monster bar lists the modifier names under the bar. Untested; it relies on the base client's `g_shaders.createOutfitShader(name, vertex, fragment)`, which exists in the base client's `game_shaders`. The season pass premium track adds two more written for this server, `chaos_ash_drift` (Ash Drift, id 25) and `chaos_cinder_crown` (Cinder Crown, id 26), `chaos_outfit_ash_drift.frag` / `chaos_outfit_cinder_crown.frag` on `chaos_outfit_vertex.frag` (server/README.md "Season pass"; `outfitshaderlist_test.lua` checks them against `seasonpass_config.lua`).

Pixent fix: `shine122.frag`, `pixent_green.frag` and `pixent_blue.frag` (server shaders 15-17: Explosive, Venomous, Swift, and the store shaders 15 and 17) called `smoothstep(.001,.001,metal)`. Equal edges are undefined in GLSL; Mesa llvmpipe (the software-rendered test client) turned them into a coloured checker grid over the whole sprite. They now use `step(.001,metal)`, the hard threshold the equal edges meant. Checked in the test client with 17 demons, one per shader: before, 14-17 drew as checker grids (14, Blazing, an energizer like 9-13, only while the pixent ones were on screen); after, all 17 draw the sprite with their colour and sparkles under llvmpipe for several minutes, the same as Mesa softpipe, which drew all of them right even before the fix. A GPU driver usually reads equal edges as a step, so the Windows client may not have shown it.

In the world a tiered monster's name is coloured by tier and its modifiers are drawn on a line above the name (`Creature:setTitle` and `setInformationColor` of the base client engine); on the bar the modifiers sit under the bar.

## Outfit shaders in the Outfit window (new)
`game_chaosshaders/outfitshaderlist.lua` (`OutfitShaderList`, pure logic; `outfitshaderlist_test.lua`) is the logic of the Shader row that base patch `0045` adds to the base Outfit window (`game_outfit`, BASE.md 27; ROADMAP 86). The server's outfit window packet lists the shaders the character owns as {shaders.xml id, name}; `entries` keeps the valid ones (no repeats, at most 255) sorted by a display name: the store's names (`shop_config.lua`, by id), the exclusives' and the Chaos shaders' (`exclusives_config.lua`, `cosmetics_config.lua`), else the name made readable. `rows` gives "None" plus the owned ones (filtered by the search box), `outgoing` the name the set-outfit packet carries: an owned one or "" (the server refuses the whole outfit change for a shader the character does not own, so a worn shader that left the list is dropped), `text` the row's label. The test checks every label against those three server files and that every labelled name is registered by `chaosshaders.lua`. Tested in the Linux client against a live server with src-patch 0036: no shader owned, the row is greyed; four owned (Blood Pulse, Ember Glow, Heartblood, Void Flicker), the list shows them with previews, a pick previews and is worn after Ok (server `lookShader` 19), and both survive a relog.

## Chaos spells in the client (new)
`game_chaosspells` adds the 110 Chaos spells to the spell list, action bar, hotkeys and cooldown display (`SpellInfo.Default`, `SpellIcons`, `SpelllistSettings.Default.spellOrder`). The data (`spelldata.lua`) is generated from `server/data/spells/chaos/spells_chaos.xml` by `tools/gen_spell_data.py` (CI fails if it is out of date). All three spell icon sheets (`overlay/data/images/game/spells/spell-icons-32x32.png`, `-22x24.png`, `-20x20.png`, 20 columns, 320 cells: 16 rows) are our own generated art and replace the base client's sheets when `tools/assemble_client.sh` copies the overlay: `tools/gen_all_spell_icons.py --spells-lua <client>/modules/gamelib/spells.lua --out-dir overlay/data/images/game/spells` draws every cell the client's `SpellIcons` table names from the spell's words (element from flam/frigo/vis/tera/mort/san/pox/kor/ico/..., kind from exori/exevo hur/lux/mas/exura/exana/utani/utamo/utevo/ad... runes, tier from infir/min, gran, max), the 77 Chaos spells at cells 201 to 277 (the Thief line's nine at 237-245, Berserker and Beastmaster at 246-249, the Necromancer line The snares (Snare Trap, Seeker Mine, Detonate Mines) and the four vigils of the second round of build archetypes (2026-10-12) are icon cells 282-288 (`client/tools/gen_spell_icons.py`, the sheets regenerated with `gen_all_spell_icons.py`; only those cells changed). The Necromancer's summon spells Raise Bone Warrior, Archer and Mage (2026-10-18) are cells 298-300; the 2026-10-20 level 340-460 spells (Bastion Cry, Anvil Fall, Twin Verdict, Rampage Leap, Glacial Doom, Pack Frenzy, Shuriken Tempest) are cells 301-307 (a 16th row; only those cells changed), Tautstring (2026-10-20, the Ranger line's buff in place of the retired stock Hawkeye) cell 308 (only that cell changed; the stock entry `utito tempo san` leaves the spell list through `ChaosRetiredSpells` of `spelldata.lua`), Ironhold and Wildstride (2026-10-20, the Warrior and Ranger lines' buffs in place of the retired stock Bulwark and Windrunner, which pacified the caster) cells 309-310 (only those cells changed; `utamo tempo` and `utamo tempo san` are in `ChaosRetiredSpells`; the 15-spell cap of 2026-10-20 adds `ChaosCappedSpells`: Chaos words of 79 stock spells -> the class ids that keep them, `{}` for the 68 the server retired, which leave the spell list and are never cast; no icon changed), the previous last three of the 300-cell sheets (drawn by `gen_spell_icons.py`, bone sword / bone arrows / necrotic eye; only those cells changed). The Thief line's area strikes Blade Flurry (73) and Iaido Sweep (74, 2026-10-15) are cells 289-290 (new kit glyphs

Line spell quest icons, phase 7 (2026-10-28): the 21 quest spells have real icons in cells 349-369 of the three sheets (the placeholder glyphs of `gen_spell_icons.py` `ICONS` stay as the fallback of `gen_all_spell_icons.py --no-art`). Made with PixelLab "Create Image (Pro)", 21 calls at 32 x 32 with no reference image (one description per spell, 64 candidates each, $0.08 a call), one candidate chosen by eye per spell; the raw results stay outside git. Source, committed: `tools/quest_spell_art/quest_spell_32.png` (7 x 3 cells) and `quest_spell_icons.csv` (cell, spell, frame colour, call, candidate). `tools/gen_quest_spell_icons.py` builds them deterministically: the centre 28 x 28 of the candidate (no resampling) inside the 2 px frame of the first Chaos spell cell (201-279) with the same frame colour (grey, orange, purple, red, green, cyan; the stud and cut corners come with it), 22 x 24 and 20 x 20 redrawn with `gen_all_spell_icons.art_small` like the other art cells. It writes cells 349-369 of `tools/spell_icon_art/spell_icons_32.png` (the art sheet, now 19 rows, which `gen_all_spell_icons.py` and `gen_buff_icons.py` read) and pastes the same cells into the three client sheets (every other cell is untouched; `gen_all_spell_icons.py` needs the base client's `spells.lua`, so it is not the path). `--check` (CI step "Quest spell icons") compares the 21 cells in all four files; `pack --raw DIR` rebuilds the source sheet from raw results (`DIR/<call>/<NN>.png`); `--sheet OUT.png` writes a labelled contact sheet. The seven buff bar icons (`buffs/<key>.png`) are those cells in the buff frame (`gen_buff_icons.py` `SPELL_ICONS`, rerun, only the seven files changed). Painted icons (2026-10-28): `gen_painted_icons.py` builds the 21 spells as `spells_painted/349-369.png` and the seven buffs as `buffs_painted/<key>.png` straight from `quest_spell_32.png` (the finished art, centre 28 x 28, no repaint and no palette clamp, in the buff frame; the buffs box-reduced to 22 px), so the sheet `painted_64.png` and the csv are unchanged and no new art was made. The wiki (`gen_wiki_data.lua`, then `gen_wiki_art.py`) shows them as `sp-349` to `sp-369` instead of kit glyphs. A new look: change the csv candidate (or the frame), `pack`, run the build, rerun `gen_buff_icons.py`. Credit: docs/CREDITS.md, PixelLab.
Line spell quests, phases 4 and 5 (2026-10-28): the seven level 800 buffs (ids 143, 150, 153, 156, 159, 173, 178; server/README.md "Line spell quests") are in `spelldata.lua` with `quest = 2` and icon cells 363-369 in the three sheets (placeholder glyphs of `gen_spell_icons.py` `ICONS`, regenerated with `gen_all_spell_icons.py`; the sheets stay at 19 rows), each has a buff bar icon (`overlay/data/images/game/buffs/<key>.png`, `gen_buff_icons.py` `SPELL_ICONS`: the spell's cell, taken from the generated sheet until art is drawn) and a Timer rule in `game_helpersupport/supportspells.lua` `KINDS` (`auto = 'timer'`, so Auto setup keeps the buff up). `game_spellbook` shows a quest spell the character has not learned as locked (`spellbook_core.lua` status `quest`, `Core.questOf` reads `quest` from the spell data): the row says "Locked", the tooltip and the description name Archivist Odrenna and the level (500 / 800 / 1200), the details have a "Quest" row, and locked quest spells of the character's line are always in "Available soon". pt-BR texts in `client_chaos_locale/pt_br.lua`; tests `spellbook_core_test.lua`, `supportspells_test.lua`.
Line spell quests, phase 3 (2026-10-28): the seven level 1200 ultimates (ids 148, 151, 154, 157, 160, 174, 237) are in `spelldata.lua` with `quest = 3`, icon cells 356-362 (placeholder glyphs of `gen_spell_icons.py` `ICONS`; the three sheets got a 19th row, cells 363-380 are the filler plate) and in `autorotation_data.lua`, where each class has `ultimate = id` (not in a preset or the extras). `game_helperrotation/autorotation.lua` `select` puts the ultimate first, for one monster, when the character can cast it, on top of the 5 spells (`MAX_SPELLS` stays 5); `sel.ultimate` names it.
Line spell quests, phase 2 (2026-10-28): seven level 500 attack spells (ids 142, 149, 152, 155, 158, 172, 177; server/README.md "Line spell quests") are in `spelldata.lua` with `quest = 1` (`gen_spell_data.py` reads the quest numbers of the spells from `server/data/scripts/chaos/spellquest_config.lua`), icon cells 349-355 in the three sheets (placeholder glyphs of `gen_spell_icons.py` `ICONS`, pasted into the sheets; PixelLab art comes later) and in `game_helperrotation/autorotation_data.lua`. `spellfix.lua` has no fix entry for the retired Bog Splatter and Arcane Stitch any more (their ids 172 and 174 belong to the quest spells).

The helper's own per-vocation lists get every castable spell of the client's table, not only the Chaos spells (owner 2026-10-17: "some spells appear in the spellbook but not in the helper"): `ChaosSpellFix.extendHelperLists` adds the Chaos spells, the base spells of `F.EXTRA` (never added before: their entries came after the helper pass) and any other instant the server has that the helper's lists lack (`castableFromInfo`; the helper's ignored ids and `F.HELPER_EXCLUDE` stay out).
`flurry` and `sweep` in `gen_spell_icons.py`), the pack tools of the second pass cells 291-297 (Palm Shockwave, Shadow
Ricochet, Iron Chain, Bone Shrapnel, Sanctified Ground, Shield Wave, Fan of Knives; glyphs `palmwave`, `ricochet`,
`chain`, `shrapnel`, `shieldwave`, `knives`; the sheets regenerated, only those cells changed; no painted icon yet, so
the spellbook's "Painted icons" falls back to the sheet and the wiki to the kit drawing).
at 250-258, the Monk line at 259-268, the Templar line at 269-277, the Illusionist's two heals at 278-279, Town Portal at 280, the Thief line's Shadow Mend at 281) with the drawings of `tools/gen_spell_icons.py`, and a neutral filler in every unused cell, so no base icon is left. Rerun it after changing `gen_spell_icons.py` or the order of `spells_chaos.xml`. Spells are matched by icon key and words, not by display name. Untested in a client; it assumes the client reads `SpellInfo`/`SpellIcons` when the windows open.

## Helper rotation (new, `game_helperrotation`, `game_chaosspells/spellfix.lua`, base patch 0052)

`game_helperrotation` (`rotation.lua`, global `ChaosHelperRotation`, not sandboxed; `rotation_test.lua`) is the helper's
cast bookkeeping: a cast waits for the server's cooldown packet, a refused one backs off 2-16 s, a group is held about two
round trips while its cast waits, no attack spell or rune goes out while a cast-time spell charges (`CAST_MS`, checked by
the test against the server scripts; heals and support spells do, base patch 0062), level / mana / server-has-it checks, the self-area monster count. The test also runs the shooter's
loop against a server model: the old helper stuck on a refused spell (480 refusals, the spells below it never cast), the
new one 9 tries and every spell on its cooldown, also at 400 ms and after a 2.5 s stall.
`game_chaosspells/spellfix.lua` (`ChaosSpellFix`; `spellfix_test.lua`) lines the client's stock spell entries up with the
installed server: ten entries had other ids than the server and four stock spells the server does not have held the ids
of Chaos spells (238 Shadow Veil, 244 Iaijutsu, 245 Bushido Focus, 248 Wild Bond), so cooldowns went to the wrong spell
and a helper rule could resolve to the wrong words; the six ascension spells follow the server's new ids below 256
(`server/tools/patch_spell_ids.py`); mana, level, groups, target, range and vocation ids where they differ; rune groups.
Every stock spell and rune entry loses its premium flag: all spells are free (`server/tools/patch_free_spells.py`).
The 42 stock entries of spells the server does not have keep their entry but are marked `notOnServer` and moved to id +
1000; the spells the server removed (`ChaosRemovedSpells`, the conjure spells) keep entry and id (the rune cooldown icons
use them), are marked `notOnServer` and leave the spell list (`hideRemovedSpells`) and the helper's lists. The helper's
own id lists (`spelldata.json`) are remapped to the server ids, and vigils (toggles), Town Portal and Flickerdash are not
offered to the helper. Base patch 0052 (`BASE.md`) uses both.

Auto setup's rotation (`autorotation_data.lua`, written by `server/tools/rotation_sim.py --write`, O157): `spells` lists every attack spell the rotation can use (name, words, `area`), each class has its presets (free slots filled up to five by `fill_slots`) and `extras`, the attack spells no preset holds; `ChaosAutoRotation.select` tops a short preset up from the other presets, then the extras. `tools/ci/check_rotation_kit.py` fails when a kit spell is unknown or has the wrong area rule, `tools/ci/check_spell_icons.py` when a spell has no drawn icon cell in the three spell sheets.

## Helper cooldown channels (new, `game_helpertimers`, base patch 0062)

`game_helpertimers` (`helpertimers.lua`, global `ChaosHelperTimers`, not sandboxed; `helpertimers_test.lua`) keeps the
helper's timers per cooldown channel, like the server (server/README.md "Cooldown channels", engine src-patch 0042): a
cast guard per channel (heal 4, attack 4, support 3 casts a second, the same words not within 500 ms) and an object-use
timer per channel (potion, healRune, attackRune, supportRune, food; 1 s each). `castChannel(groups)` and
`runeChannel(groups)` pick the channel from a spell's or rune's groups. Base patch 0062 (`BASE.md`) makes the helper's
healing, friend heals, magic shooter, potions, healing rune and special foods use it, so a heal never waits for the attack
rotation and a potion never for a rune. The test also reads base patch 0062.

## Auto turn, class change and the Assign Spell lists (owner debug items 75, 84, 85, 2026-10-18)

- **Auto turn (item 75; base patch `0080`).** A wave or beam hits along the facing, but the shooter only turned for the one
  stock spell flagged `aimAtTarget`. `ChaosHelperRotation.turnDirection(spell, SpellAreas, ctx)` (`game_helperrotation/
  rotation.lua`) answers for spells with `directional = true` (the stock wave and beam entries; the generated Chaos entry of a
  server `direction="1"` spell, today Skewering Line, which also gets its script's `AREA_BEAM7` so the shooter counts the
  beam) or a `*WAVE*` / `*BEAM*` area of `SpellAreas` (Lesser Front Sweep has the area, not the flag): the facing toward
  the target (dominant axis; an exact diagonal keeps a facing that is one of the two sides), else the facing with most
  monsters; nil when the character already faces it. The **Auto turn** box under the Auto rotation button (default on,
  `g_settings` `chaosHelperAutoTurn`; pt-BR "Virar sozinho") switches it off. Tests: `rotation_test.lua`. To check live: the
  box fits in the Targeting & Spell Rules panel under the button; a Warrior/Mystic rotation with Fire Wave / Energy Beam
  turns toward the target before each cast and does not turn when already facing it.
- **Class change (item 84).** The server (`class_spells.lua`, `ChaosSpellbook.refresh`) refreshes the Spellbook window on
  any class change, and `autorotation_ui.lua` takes the old class's shooter rules and healing slots out of the Helper when
  the local player's vocation changes (a pt-BR message says how many; Auto rotation fills the new class). The action bar's
  own slots are the player's and stay. Tests: `autorotation_test.lua` (`dropForeignRules`, `dropForeignHeals`).
- **Assign Spell lists (item 85; base patch `0079`).** `ChaosSpellFix.allowsVocation` (`spellfix.lua`, exported on `_G`)
  is the class rule of the action bar's Assign Spell, the custom hotkeys' Assign Spell and the action bar's can-cast
  checks: the server vocation id or the base's folded id, never a `notOnServer` entry. Wild Bond (Beastmaster) and
  Moonfang Pack (Illusionist) show; the stock "Summon Paladin / Knight / Sorcerer / Druid Familiar" (not on the server) no
  longer do. Tests: `spellfix_test.lua`.

## Helper auto rotation (new, `game_helperrotation`: `autorotation*.lua`)

The helper's Targeting & Spell Rules panel gets an **Auto rotation** button at its top right (owner: "Coloque no helper
também um botão para configuração automática de rotação"). No base patch: `autorotation_ui.lua` finds the helper's
`magicShooterPanel` once the helper window exists, adds the button and fills the helper through its own tables and
functions (`_Helper.getShooterProfile`, `magicShooter.updateRulesList`, `_Helper.MagicShooter.rebuildCache`,
`_Helper.getHelperConfig`, `onLoadHelperData`, `_Helper.saveSettings`). A click reads the character's class (the
server vocation id), level and the spells it can cast (the helper's spell entries, which `spellfix.lua` lines up with
the server: on the server, its class listed, its level met, known) and sets the shooter's rules to the best rotation of
at most 5 attack spells for that class and level, in priority order, from `autorotation_data.lua` (generated by
`server/tools/rotation_sim.py --write`, checked in CI; server/data/spells/README.md "Rotations"). An area spell waits for
2 monsters when the rest still casts every 2 s on a lone target, else 1. A spell the character cannot cast is replaced
by the next one of an earlier preset and the gap is simulated again (`ChaosAutoRotation.gap`). An empty healing tab
gets the class's heals (up to 3, the strongest at 45%, then 65%, 85%); a filled one is replaced only after a yes, and a
custom rotation (rules the button did not write) too. The message: "Rotation set: A > B > C (max gap 2.0 s)". A
level-up refreshes a rotation the button set (and the player left alone). `autorotation.lua` (`ChaosAutoRotation`) is
the choice, pure Lua, tested by `autorotation_test.lua` (every class has presets, at most 5 spells, the gap at the level
bands 30-1000 and at every preset from level 15, no snare in a preset, the Lua gap check against the generator, replacement, custom detection, heals, the message).
With it (found by the live check, server/data/spells/README.md "Rotations"): `game_chaosspells/spellfix.lua` `F.EXTRA`
adds the base server spells the client had no entry for (Arcane Ripple and Bewitching Hex; Riftbolt, Crossfire Hex,
Fading Step and Gravity Snare left with the 15-spell cap of 2026-10-20; the server's numbers, checked by
`spellfix_test.lua` against `stock_spells.csv`), so the helper can cast them; the presets were regenerated for the cap
(the Mystic at level 8 has Kindling Spark alone) and for the cooldown ladder of the same day (attack cooldowns 2, 4,
6 s ... per class; the stock entries' `exhaustion` in `spellfix.lua` follows the server, checked by `spellfix_test.lua`); Sunder Guard's attack group cooldown is 2 s like the server's; `game_monkchi` tells its chi
(`currentChi`) and `ChaosHelperRotation.castable` holds a Monk finisher until it has its chi (attack finishers 4, Kindled
Breath and Chi Ward 1) instead of sending it to be refused.

## Spellbook (new)
`game_spellbook` opens on Character > Spellbook (or Character > Spellbook in the top menu, which asks the server with `open`). Left: search box (name or words), a filter ("My vocation" / "All spells") and the spell list (icon, name in the element colour, words, level in red when it is above yours). Right: icon, name, words, level, magic level, mana, soul, cooldown (group cooldown in the tooltip), group, type, element, target, what it scales with, vocations (initials, full names in the tooltip), the description and the area of effect drawn as a grid (hit cells in the element colour, your tile gold, the target outlined white; single-target spells show you and the target, self spells only you; cells shrink to fit areas up to 21 x 21). Icons come from `Spells.getSpellIcon(words)` of gamelib; runes show their rune item. Names, descriptions and areas come from the server (`server/data/scripts/chaos/spellbook.lua`), so the client keeps no spell data of its own. Not run in a client: the layout sizes, the theme styles in this window and the combo box popup were checked by reading only.

Speed and filter (2026-10-16): the window shows at once. The list is fetched about 3 s after login and kept with the
server's signature (`sig`); a reopen sends `open {have = sig}`, the server answers with two small messages when the list
is the same, and the rows (built once per list, layout updates off while building, icons looked up once) only refresh
their state: the right-hand label shows the level (red when too low, dim for other vocations), "Learn" for a needlearn
spell not learned, or the cooldown left. Before, every open waited for the 14 packets (one per 50 ms tick) and then
destroyed and rebuilt 234 rows, each scanning the painted-icon data and the disk. The filter (`spellbook_core.lua`,
global `ChaosSpellCore`, `spellbook_core_test.lua`, `spellbook_classes_test.lua`: Learned + Attack gives each of the 21 classes its 10 attack spells): Learned (castable now: vocation, level, magic level, learned),
Available soon (the next 10 levels), My vocation, All (spells only; the count counts spells), Runes (the rune
entries, kept out of the other filters and of the spell pickers; conjure spells stay spells); default Learned, saved per character (g_settings
`chaosSpellbook`). The selected row has a soft gold tint and frame (hover a faint lift); Up / Down move the selection. Long names are cut with "..." (full name in the row tooltip). A single-target spell's area shows the
target at its range (up to 5) and the legend's target square matches it. The spell pickers share the order and the
learned rule (base patch `0057`). Using a spellbook item opens the window (server `show` on opcode 219). Not run
in a client. 2026-10-20 (owner log "[SlowLua] ... spellbook.lua:732 took 7.161 ms", from the combo box): one filter
pass per change of the Type box, not a loop; the filter and Type boxes no longer change on the mouse wheel, and box
and search changes are coalesced into one pass (30 ms).

## Short numbers (new)
Every number the client shows is short: 1000 -> 1k, 15300 -> 15.3k, 2450000 -> 2.45M, 1200000000 -> 1.2B (three significant digits, trailing zeros dropped, rounded down so 999999 is 999k, below 1000 as it is, negatives keep the sign). `client_chaos_numbers` (not sandboxed, autoload-priority 10, so it loads before gamelib and every game module) defines the globals `formatShortNumber(n)`, `formatExactNumber(n)` (15,300, for tooltips), `shortNumbersIn(text)` (shortens standalone integers inside a text, `1,234,567` and `1.234.567` included, and leaves times, dates and years, coordinates, ids, `#123`, numbers glued to letters, decimals and the loot markup `{id:value|...}` alone) and `shortNumbersInMessage(mode, text)` (only the look, damage, healing, experience, status, loot, NPC trade, mana and potion message modes; chat, private, NPC talk, login and broadcasts stay as they are). `numbers_test.lua` (luajit and lua5.3, CI step "Client unit tests") checks the rule against an integer reference and the text cases. The numbers above the map use the same rule in C++ (base patch 0018).

Used by base patch `0019-short-numbers.patch` (health/mana in healthinfo and topbar, the skills window, inventory capacity and soul, on-screen and console server messages, NPC trade balance and list prices, market/store/forge/prey/cyclopedia/soulseal/task balances, the analysers, highscores) and by the overlay modules bank, shop, infinity tower, dungeons, battle pass, stash, craft skills, passive tree and spellbook. Exact values are kept in tooltips where a widget can show one, and everywhere the player types or confirms an amount (bank deposit/withdraw/transfer dialogs, NPC trade price of the selected item, market offers and create-offer totals, store offer prices, shop buy confirmation, analyser clipboard exports). Not run in a client.


## Damage number scatter (new)
Slice A of the damage number work (client only, the protocol is untouched). The numbers above the map all rose on one line, so an area hit stacked them. Base patch `0081` gives `AnimatedText` a pixel shift on top of the stacking offset (`setScatter({x=, y=})`, `getScatter`) and a speed scale (`setSpeedScale(f)`, `getSpeedScale`, clamped to 0.5 .. 2; 1 is the stock rise and fade of 1000 ms). The overlay module `game_damagescatter` rolls both for each new text from `g_map.onAnimatedText`. Strength per level (largest shift sideways / up-down in pixels, speed between): Subtle 6 / 4, 92% .. 108%; Normal 12 / 8, 85% .. 115%; Wide 20 / 12, 75% .. 125%. The physical number and the element number of one hit (same square within 80 ms) share one roll, so they stay side by side as before; the abbreviation (1k, 15.3k, 2.45M, base patch 0018) and the stacking of base `map.cpp` are untouched. Off, or a client without `0081`: the numbers draw exactly as before. Menu: Character > Damage Numbers (added with `ChaosTopBar.addEntry`). Settings are per character (`world/name`) in the client settings node `chaosDamageScatter`. Not run in a client. Slice B: "Typed impact numbers" below.

## Typed impact numbers (base patch 0100, server src-patch 0051)
Slice B of the damage number work. The server tags each damage, heal, mana and experience number with a percent (x100), a type (0 normal, 1 critical, 2 condition tick, 3 mana drain, 4 mana gain, 5 energy shield, 6+ scripts) and the creature it belongs to; the client asks for it at login (capability bit 7) and reads the fields only when the server announces feature 155, so either half works with the other's old version (server/README.md "Typed impact numbers", client/BASE.md `0100`). Every number goes through `g_map.onImpactText(animatedText, text, mode, typeId, value, percent, creatureId, pos)` before it reaches the map; `game_damagescatter` is the one module that gives the feel, extended in place rather than replaced by a new module (the updater never deletes a module folder, so an old `game_damagescatter` next to a new one would have rolled every number twice; its settings and menu entry carry over):
- **Shift and speed** (slice A, kept): the 0081 shift sits on top of the stacking offset, so the side-by-side layout of the numbers on one square stays and the two numbers of one hit share one roll.
- **Drift** (new, from the guide's design, better than the fixed rise): each hit floats in its own direction: sideways up to 6 / 14 / 24 px and a rise of 44-52 / 40-56 / 36-60 px over its life (Subtle / Normal / Wide; stock: 48 straight up). Experience rises straight.
- **Fonts by type:** critical `chaos-display-16px`, condition tick `chaos-outline-11px` (only when the font is loaded); other types keep the stock number font. A font change also stops a crit or a tick from being merged into a plain hit (and 0100's `merge()` checks the type too). A crit floats 15% slower.
- **Follow the creature:** Options > Interface "Damage numbers follow the creature" (`attachedImpactText`, on). The module turns `GameChaosAttachedImpactText` on or off from the option's apply and again at every game start, since the features are reset at each login. A number whose creature leaves, hides or changes floor stays where the creature was last drawn.
- **Abbreviation** (base patch 0018: 1k, 15.3k, 2.45M) is untouched: the hook receives the short text and the raw value.
- The hook never cancels a number; other modules may connect to it (answer true to drop one), e.g. a meter that counts crits from `typeId`.
- Mode numbers are this client's `Otc::MessageMode` (`DamageScatterLogic.MODE`: 21 damage dealt, 22 damage received, 23 heal, 24 experience, 25 damage others, 26 heal others, 27 experience others, 41 mana), checked against `const.h`.
Not run in a client.

## Ornate UI skin (new)
The whole interface is redrawn as iron, gold trim, blood-red and arcane-blue gems instead of flat recoloured stone. All art is procedural, made by `tools/gen_skin.py`: tileable noise materials, a height map with lighting for bevels, plus rivets, gold filigree and gems. Regenerate it with `python3 client/tools/gen_skin.py --base <assembled base client dir>`. The groups are `frames controls stock hud ornaments`, and only `stock` needs `--base`. Run `gen_ui_reskin.py` first if you use it. `gen_skin.py` takes every file it draws off `RESKIN_FILES.txt`, so the recolour tool never overwrites them. `gen_theme_art.py` no longer draws the chaos/ frames by default.
- **Windows**: `data/styles/10-windows.otui` (copied from the patched base, then edited) points `Window` at `chaos/skin/window` (borders 12/32) and keeps the stock paddings. `NewWindow` keeps the redrawn `ui/popupwindow`. `Window`, `NewWindow` and `ChaosWindow` set `&chaosOrnate`. For those, `client_chaos_theme` adds gold corner pieces and a crest as phantom children, one frame after creation, so `prev` anchors and child indexes are untouched. It also centres the title on the title plate and paints it gold, because many base windows move it for the old 17 px bar.
- **Buttons**: `data/styles/10-buttons.otui` points `Button` at `chaos/skin/button`: border 5, normal/hover with an ember glow/pressed/disabled. `ui/buttons`, `ui/button`, the tab sheets, `ui/menubox` (popup menus), `ui/textedit`, the inner panel frames, the map frame, `ui/window` (mini windows), the item, inventory and action bar slots (stock silhouettes kept) and the top bars are redrawn in place, at the same size and layout. Scroll bars, check boxes, the mini window buttons, combo boxes, the console sheet, `common_buttons/*` and the arrows are "relit". Their layout comes from the stock image, and their pixels are remapped to iron/bronze/gold. Mini window titles are gold (`data/styles/30-miniwindow.otui`). Tooltips are a dark gold-rimmed plate (`client_chaos_theme` wraps `g_tooltip.display*`).
- **Move up / Move down / Remove** (`10-buttons.otui` `MoveUpButton`, `MoveDownButton`, `RemoveButton`; the helper's rule rows and timer rows): 18 px Chaos buttons (the skin's `button_normal` / `hover` / `pressed` / `disabled` frame) with a white arrow tinted by state (`chaos/rule_arrow_up` / `_down`, `tools/gen_rule_arrows.py`, `--check`) or a red X; they were bare green and red arrows (beta 2026-10-20). The arrow was drawn in the frame's top-left corner (`icon-size` is an icon rect at 0 0 in this engine; owner 2026-10-22): without it the arrow is centred, and base patch 0107 keeps the Remove button at the style's 18 x 18 (the rows had set 17). Not yet seen in a client.
- **Top menu bar**: `client_chaos_topbar` uses the skin button and a framed bar (`chaos/skin/menubar`). The stock top strip of `client_topmenu` (Join Discord link, console, DAT Offset Studio, options and exit icons) is kept hidden on the login screen and in game; its buttons are entries of the menu instead. On the login screen the bar shows only the entries marked `offline` (System: Options, Join Discord, Console, DAT Offset Studio, Exit). In game, Unjustified Points (Hunt) was added, since its stock button sat on the hidden bars. Weapon Proficiency has no entry (removed 2026-10-20 at the owner's request; `game_proficiencycatalog` stays); the stock Blessings window has none: the server does not answer the base blessings request on 10.98, so it stays empty. Prey and Task Hunt have no entry either (2026-10-16): the base `game_prey` needs the `GamePrey` feature, off on 10.98 (no prey on the server), so it never opened, and its hotkey is gone (base patch `0058`); the base Task Hunt window (bounty tasks, preferred list, talisman, weekly tasks, task shop) never got data from the 10.98 server and showed placeholders, so `tools/assemble_client.sh` leaves it out. The task systems are Hunt > Kill Tasks and Task Tracker (`game_bestiary`) and Adventure > Bounty Board (`game_bounty`). The invite link is `ChaosTopBar.COMMUNITY_URL` in `chaos_topbar.lua` (empty for now: the entry then says the link is not available yet). Icons `topbutton_community/console/exit/proficiency/pvp` come from `tools/gen_theme_art.py icons`.
- **Top menu order**: every drop-down and its "More" sub-menu in alphabetical order of the shown, translated text (accents folded, so pt-BR sorts too), "More >" last; groups between separators stay groups; hotkey labels stay with their entry (`client_chaos_topbar/topbarlogic.lua`, `topbarlogic_test.lua`; owner request 2026-10-16).
- **Sub-menus of the top menu** ("More"): open beside their entry on a click or a hover, and the drop-down stays open (live test winpkg-35: "More" closed the drop-down and its entries came up as a separate popup). The engine keeps one popup menu at a time, so the sub-menu is a plain widget in the `PopupMenu` style; the drop-down keeps the mouse grab and passes the sub-menu's clicks on; a press outside both, Escape or an entry closes both.
- **Item tooltips** (`game_itemtooltip`): a request names the hovered item (`cid`, and `n` for a stack) and an answer for another item is dropped and asked again (`L.tipMatches`; live test winpkg-35: a Rope showed "Cheese 62" after the backpack's items shifted); the sources line names a monster once; items with charges show "Charges: n of max" or "Charges: unlimited" (`L.chargesText`, server `T.chargeInfo`). "Where to find" shows only on items that can be picked up or moved, never on ground, borders or walls (`game_itemfinder` `L.menuThing`).
- **Popup menu separators** (`client_chaos_theme`): `UIPopupMenu.addSeparator` adds none at the top of a menu or after another separator, and `display` drops trailing ones. The item menu of `game_interface` adds one per menu hook category before checking its entries (Report Player, Talk, Inspect Player, Transmog hide on an item), which showed three empty lines in a row (live test winpkg-35).
- **Town Portal circle under the character** (`game_townportal`): registers effect 744 (`portal_pad`) with `g_map.setGroundEffect` (base patch `0055`, `BASE.md`), so the channel circle lies on the floor under the creatures; without the patch it is drawn as before.
- **UI reskin (O155)**: rolled back on 2026-10-24 except the health and mana orbs; by default the tool now writes only the orb rings, `--full` the rest. `tools/import_hud_kit.py <pack-dir>` (art pack in docs/CREDITS.md; run after `gen_skin.py`) writes the orb rings (`game_shaderfx/images/orb_ring_*`, opening transparent, liquid 50 of 76 of the orb), the character plate and bar fills of `game_chaoshud` (portrait clip 48 px, opening radius 24), the action bar slots (`game/actionbar/slot-actionbar*`), `chaos/window`, `skin/window`, `ui/map-borderimage`, panels, buttons, tabs, text fields and `skin/tooltip` at their old sizes and borders. `gen_orb_art.py` keeps the masks and checks the rings exist.
- **HUD**: new module `game_chaoshud` puts a character plate in the game root panel, over the top-left of the map. It shows the outfit portrait in a gold ring, a level badge, the name, health and mana bars with short numbers and an experience line. `hudmath.lua` is tested by `hud_test.lua`. Since 2026-10-20 a right click on the health / mana bars offers "Show health and mana as percent" (or back to numbers), kept per character (g_settings node `chaosHud`, lowercase name -> true); `HudMath.percent` never rounds a nearly full bar up to 100%.
- **Character list**: base patch `0021-chaos-skin-character-list.patch` changes the hard-coded grey row colours to the palette.
- **Fixes found while testing**: `game_chaosspells` connected an `onGameStart` handler that returned `true`, and `signalcall` stops at that, so every handler after it (passive tree, dungeons, bank, top menu hiding, ...) never ran. It is wrapped now. With those handlers running, two missing assets showed up: `game_dungeons/challenge.otui` used a font the client does not have (now `Verdana Bold-13px`), and `images/animations/button-highlight-22x22`, which the base proficiency window wants, is now generated.
Checked in the Linux client at 1280x800: login, character list, game screen, skills, options, spellbook, shop, daily reward, passive tree, the popup menu and tooltips. No errors in the log.

Checked in a live client after base patch 0043, 2026-10-13, at 1280x720: Market, Bestiary, Achievements, Leaderboards, Guild Siege and Pets each opened once through its toggle and showed the server's data. No `Extended opcode` error and no stray part warning in the log. The first run showed only an empty Market: the server dropped every request. Fixed on the server, server/README.md "Extended opcode dispatch".

## Login screen (new, `client_chaos_login`, `tools/gen_login_art.py`)
No base patch: the module restyles the stock `client_background` and `client_entergame` widgets at runtime, so every function of the stock login (remember account and password, auto login, server list, recordings, error boxes, 2FA token field, character list afterwards) is unchanged.
- **Composition**: the team's login artwork (`tools/art_src/login_reference.webp`: gothic cathedral city over lava, the "Cinders of Chaos" logo in its thorn frame) fills the window, and the real widgets sit where the artwork painted its mock interface. Splash: "PRESS ANY KEY TO START" on a dark translucent bar with thin gold-iron edges (serif lettering as an image, `presskey.png` + `presskey_text.png`: the client's font atlas has no room for another font; a translated text shows as a label instead), the server status under it with a spinner while it is checking. Panel state: the framed sign-in panel at the bottom centre, its top crest under the logo's lower spike, with a rune medallion at each end. Inside the panel: ACCOUNT and PASSWORD fields (and the narrow TOKEN field), remember account / remember password / auto login, SIGN IN and CREATE ACCOUNT, OPTIONS, CREDITS and EXIT GAME, and the forgot-password link; the new buttons call the stock functions (`EnterGame.doLogin`, the options window, `g_app.exit`); CREDITS opens the `client_chaos_credits` window (the short box only without that module). Corners: server drop-down, recordings button and server status (top left), `Version` (top right). The stock event schedule, boosted and cast panels go under the sign-in panel when they fit (1920x1080), else beside it (schedule and boosted bottom left, casts bottom right above the corner mark), else (4:3 at 1024x768) they are hidden. Only with the sign-in panel itself (not during the splash, not on the character select, not in game), and each panel only with data (`ChaosLoginBar`, `loginbar.lua`, `loginbar_test.lua`): the schedule with at least one event, boosted with a creature or a boss (base patch `0071` `hasBoostedInfo`); casts only with `Services.casts = true` (our server has no cast list; `0071` stops the client asking for one). No data (the service unreachable): no bar. The row centres the shown panels. The services: `server/tools/clientservices.py`, started on 127.0.0.1 by the Linux server package and forwarded by the website (`tools/linux/server/README.txt` "Login screen services"); a release client built with `site_url` asks `<site>/clientservices`.
- **Generator mark**: the artwork has a small four-pointed sparkle in its bottom right corner, the visible mark of the image generator that made it. It is kept as it is: the generator copies those pixels back unchanged after cleaning, no widget is placed on it and `login.lua` does not draw embers, ash or sparks over it (`MARK_BOX`).
- **Press any key to start**: on the first login screen of a run the panel is hidden; any key or a click on the background reveals the panel with a short fade. It is skipped when auto login is on with a saved account, and never shown again after a logout. `EnterGame.show` is wrapped, so the error boxes and logout still bring the panel back.
- **Background and logo**: `data/images/title.png` is 1920x1536: the artwork upscaled to a 1920x1072 band at row 232, with a darkened, blurred mirror of its edges above and below, so every window from 16:9 to 5:4 shows the full width without stretching (wider windows crop rows, keeping the bottom; narrower ones crop the sides). The logo stays painted in the picture; `chaos/logo.png` (the logo cut out of the artwork) is placed exactly on it, so it is never drawn twice, and carries the animation: `chaos/login/logo_hot.png` (the hottest parts of the letters) breathes over it and 12 sparks (`spark.png`) rise off the tops of CINDERS and CHAOS. Also: `chaos/login/glow.png` (lava and lit windows, same frame as `title.png`) flickers, 22 rising embers and 10 falling ash flakes; all on one timer at 20 per second that does nothing while the login screen is hidden. Positions are artwork pixels mapped through the crop (`LOGO_BOX`, `PRESS_BOX`, `STATUS_Y`, `SPIN_*`, `PANEL_Y` in `login.lua`).
- **Phone (1000x461 and 960x540 interface pixels)**: the sign-in window is pinned by four anchors, so the stock `$mobile` size (320x300) of `enterGame` cannot shrink it (the runes and fields spilled out) or run it off the screen; on a phone the runes sit 12 px outside the panel, the logo stays under 42% of the height, the map name moves above the panel's right corner when the room beside it is too narrow, and the schedule lists show 4 rows (a 5th one wrapped into a second column over the first).
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
  default. `gen_outfit_anchors.py --centre body|bbox|blend` writes the other two (the dais size keeps using the
  body's own reach).
  Feet (2026-10-16, owner: "still misaligned"; a Test Thief, level 1, in stock look 130, the white robed mage with
  colours 0 and no addons, stood up and left of the dais): every sprite of the pair leans up and left with its
  height, stock looks as much as ours, so the body's centroid is up and left of the feet, and the centroid with the
  nudge left look 130's feet 12 sprite pixels right of and 3 below the dais centre. The anchor is now the centre of
  the feet (`--centre feet`, the default): the alpha-weighted centroid of the lowest 12% of the body's solid mass,
  that band taken as every part (thin lines left out) that touches the body's columns, so a foot reaching right of a
  leaning body counts and the foot of a staff beside it does not; its row is that centroid's, not where the band
  begins. `NUDGE_X` is 0. Player looks moved 5 sprite pixels right and 2 down on average; the bounds, flags and reach
  are unchanged (checked on pair 28 by compositing looks 128, 130, 2049, 2161 and 2175 on the dais art at 4x). The
  fallback for a look the table lacks (a newer pair) puts the feet where the table's looks of its size have them
  (`CharSelectCore.FEET_FALLBACK`; for 2x2 player looks 76% within 6 sprite pixels, the old rule, the middle of the
  own tile's bottom, 31%). Tests: `gen_outfit_anchors_test.py` (a leaning figure, a staff standing beside the body),
  `charselect_core_test.lua` (the fallback against the table's player looks, look 130's feet on the centre). Not yet
  checked in a running client.
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

## Name over tall looks (new, `client_chaos_infolift`, base patch 0111)

Owner report, 2026-10-22: "alguns outfits ficam com o nome no meio dele, não em cima" (a Necromancer in look 2183, the
name and the health bar across the chest).

- **Cause.** The engine anchors a creature's bar 2 px over the top of its own 32x32 cell, moved up by the look's
  displacement, and the name 12 px over the bar (`MapView::drawMapForeground`, `Creature::drawInformation`). That place
  comes from the dat alone. A stock look's head is at the top of that cell. Many imported 64x64 looks draw the head
  higher in their canvas: on pair 34 the body of the Necromancer 2183 / 2184 reaches 20 px over the bar line (displacement
  0), the old Lich look 2059 20, the Warrior 2073 / 2074 18, the Inquisitor 2077 16; the stock looks 128-160 reach 2 (median).
  The displacement itself cancels out (the bar and the picture move together); what differs is the art's height.
- **Data.** `tools/sprites/gen_info_lift.py Tibia.dat Tibia.spr [--check]` measures each creature thing: per
  direction (phase 0, base layer, every addon pattern) the top of the solid body (a raised staff, a spear or a plume
  left out: `gen_outfit_anchors.solid`, r = 2, biggest part), the largest over the four directions so the name does not
  jump when the creature turns. Lift = that gap - 4 (what a stock look shows), from 3 px on, capped at 96. Pair 34
  (dat 11babc2e0f6d93fe1c1cc40c75787f18): 1451 looks, e.g. 2183 / 2184 16, 2059 16, 2073 / 2074 14, 2077 12,
  2161 / 2162 11, 2181 10, 2173 7, 2064 6; 128 and 136 none. Written to `client_chaos_infolift/info_lifts.lua` with the
  dat md5; regenerate it with every new pair (CI's pair job runs `--check`). Tests: `gen_info_lift_test.py`
  (synthetic figures), `infolift_core_test.lua` (the table, the report's look lifted, the stock citizen not).
- **Engine.** Base patch 0111: `Creature.setInformationLift(look, px)` keeps the table; `drawMapForeground` moves the
  anchor of a player or an NPC up by its look's lift times the offset factor, before the map's stretch (so it scales
  with the zoom). Monsters keep the classic place (a dragon's name over its body). `game_npctalk` points its bubble's
  tail at the lifted name (`creature:getInformationLift()`).
- **Limits.** Mounted, the rider sits as before and the lift is the look's own. The name stays centred on the cell, not
  on the leaning figure. Not seen in a client run (the assembled sources pass `g++ -fsyntax-only`); renders of the
  measured looks with the moved bar checked by eye.

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
**Replaced by "Store item looks (pair 34)"** (the same art snapped to theme palettes, client 38608-38610).
Three item things of our own art for the store pouches, so they cannot be mixed up in a backpack (they were the stock expedition,
brocade and fur bags): client 33651 Orbs Pouch (a round violet velvet pouch, gold drawstring, a glowing cyan orb), 33652 Rift Key
Pouch (a dark iron strongbox with riveted bands, a gold key and a key ring), 33653 Loot Bag (was Loot Pouch; a tall leather sack, gold trim,
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
  (one archive `things/things-1098.tar.xz`, `SHA256SUMS.parts`, its README; since 2026-10-15 things_custom28 at b37b983c
  (dat 9f75ddfe73197bce388398e4c31ca255, spr e0c74346aac1febb01e2197fd75004e1; "Equipment sets" below); before it
  things_custom27 at 51a26d26
  (dat 223a1c2fc1b0f99997414a5b2cde1773, spr 40cccfc55924a53fcd16b3813c0e328a; "Pack farming spell effects" and
  "Catacomb kit" below); before it things_custom26 at 50645056, "Owner art" below; 2026-10-14 things_custom25 at ebe1b2b2, "Status words"). Since 2026-10-11 that archive held things_custom15
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
  the Monk's thirteen claw weapons (2026-10-23, `server/data/items/fist_claws.csv`) used donor B looks that the pair already
  holds (client ids 28000..28012, "Donor art libraries"); since pair 56 only the first three do, the other ten wear the new
  looks of "Pair 56" (client ids 44399..44408) and the donor slots 28003..28012 stay unused;
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
- The before/after contact sheets of all 145 mounts are offline renders, kept outside the repository.
- Checked in the Linux client on 2026-10-12 with the live pair things_custom17, which keeps these seats byte-identical.
  Client: base client of `windows-assets` 854d34c + base patches 0001-0041 + overlay, built fresh. Server: base server
  of `windows-assets` + src-patches + every `install_all.py` step, MariaDB, a god character on the Cinderhold temple
  floor. Each of 1561, 2132, 2133, 2134 and 2135 ridden with rider look 128, standing and mid-step in all four
  directions; again standing with look 136. The rider sits on the saddle or the back middle in every frame. The same
  run on a client built without 0034 shows the old fault: the rider beside the mount, left of the saddle. Stock
  mount 368 draws pixel-identical with and without 0034 when standing; walking frames differ only by step timing.
  No seat needed a change. Screenshots kept outside the repository.

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

## Everfull Ration look (things_custom25, item 33904, `tools/sprites/gen_store_food_art.py`, `tools/sprites/art_import/store_food.csv`; on windows-assets ebe1b2b2, switch on since 2026-10-14)
Our own art for the store's infinite food (server id 32084, `server/data/scripts/chaos/store_food_config.lua`): a glazed
earthen bowl with a gold rim, a roast haunch with its bone and four gold sparks. Drawn in code with the store pouches'
helpers (`gen_pouch_art.py`: 128 px shape fields, rim light, outline, 4:1 downsample), deterministic, written to
`art_import/store_food.png` (32 x 32). In things_custom25 (windows-assets ebe1b2b2) as client id 33904 (after the pair 24
items, 33903), appended with
`python3 -I client/tools/sprites/import_art_things.py --ours-dat IN/Tibia.dat --ours-spr IN/Tibia.spr --out-dir OUT
--things client/tools/sprites/art_import/store_food.csv --first-item 33904 --expect-items 33903` (flags copied from the
dragon ham, client 3583; mode replace keeps server id 32084). `ownLook = true` in `store_food_config.lua` since
2026-10-14; run `install_store_food.py` again. A client on an older pair draws nothing for 33904.
**Replaced by "Store item looks (pair 34)"** (client 38611, the same art in the cinderwrought palette).

## Gem looks (things_custom25, items 33905-33939, `tools/sprites/gen_gem_art.py`, `tools/sprites/art_import/gems.csv`; on windows-assets ebe1b2b2, switch on since 2026-10-14)
**Source and licence.** The owner's gem set (Google Drive folder "ots", `gems.zip`, 609 KB, 2026-10-14; the owner:
"Pode usar eles abertamente onde forem cabiveis", use them openly where they fit). Five gem families (bloomjade,
jadecomb, sunshard, tidegem, voidorb) in ten tiers each; per tier a 32 x 288 PNG (nine 32 px frames, alpha 0 / 255,
8-15 colours), a 192 px preview GIF (110 ms frames) and a 2304 x 256 preview sheet. No licence or readme file, no
metadata, no name of any other game or server. Only the 32 px strips are read.
- Our seven gems x five tiers from the source tiers 2, 4, 6, 8, 10: emerald = jadecomb, sapphire = tidegem,
  amethyst = voidorb, topaz = sunshard (warmed to gold); recoloured per pixel (hue / saturation / value, alpha and
  shading kept): ruby = bloomjade turned crimson, diamond = tidegem drained to ice white, onyx = voidorb drained to a
  warm black-grey. Nine phases at 110 ms (synchronised), so the gems sparkle in the inventory.
- `python3 -I gen_gem_art.py build --src DIR` writes `art_import/gems.png` (288 x 1120), `art_import/gems.csv`
  (client 33905-33939 after the Everfull Ration 33904; flags `copy:` the stock gem each item used, so stackable and
  multi-use stay; mode replace with server ids 32001-32035) and the Codex strips `overlay/data/images/game/gems/<key>.png`
  (five tiers, phase 0, 2x). `build --check` (CI, Pillow 12.3.0 / numpy 2.5.3) rebuilds from the committed atlas.
  `preview --out DIR --before-dat D --before-spr S`: sheet, GIF and a before / after against the stock sprites.
- Used by: the Codex gem pages (`game_codex`: `CodexArt`, the entry's `art` from `gen_codex_data.lua`), the website
  wiki's gem icons (`gm-<key>-<tier>`, `website/tools/gen_wiki_art.py`), and the items: `chaos_gems_config.lua`
  `ownLook = true` (on since 2026-10-14, pair 25) and `install_gems.py` again (server/README.md "Gems and sockets").
- Append after the Everfull Ration (client 33904) and before the status words:
  ```
  python3 -I client/tools/sprites/import_art_things.py --ours-dat S1/Tibia.dat --ours-spr S1/Tibia.spr --out-dir S2 \
      --things client/tools/sprites/art_import/gems.csv --first-item 33905 --expect-items 33904
  ```
- Built into things_custom25 with the Everfull Ration and the status words, below.

## Status words (things_custom25, effects 656-673, `tools/sprites/gen_status_fx.py`, `art_import/status_fx.csv`; on windows-assets ebe1b2b2, switch on since 2026-10-14)
**Source and licence.** The owner's text effect set (Google Drive folder "ots", `text_effects.zip`, 2.6 MB,
2026-10-14; the same grant as the gems). 15 word effects plus second / third takes of revived and rooted: per effect
a vertical strip of square frames (96 px = 3 x 3 tiles, the first revived take 64 px), 8-16 frames, soft alpha, and
preview GIFs and sheets. No licence or readme file, no metadata, no name of any other game or server. The folder
"cataclysm" holds the OBLIVION! word. The `_frames` preview sheets also show older plain word effects (TOXIC!,
CURSED!, CHILLED FOOT!, FREEZE!, POISONED!) for comparison; they are not read or used.
- 18 effects `word_*` (blessed, oblivion, charmed, cursed, drenched, feared, frozen, impaled, reaped, revived,
  revived_rise, revived_small, rooted, rooted_vines, shackled, shocked, smite, stunned): frames turned into a row, the
  64 px take centred in 96 px, an empty frame dropped, alpha under 12 cleared; 3 x 3 sent at the target + (1, 1),
  110 ms, alpha soft (`import_fx_art.py` keeps it, like the large effects).
- `python3 -I gen_status_fx.py build --src DIR` writes `art_import/status_fx/<name>.png` (committed, 420 KB) and the
  spec; `build --check` (CI) checks the spec against the strips and the PICKS table; `preview --out DIR`.
- Append after the gems (effects after things_custom24's 655):
  ```
  python3 -I client/tools/sprites/import_fx_art.py --ours-dat S2/Tibia.dat --ours-spr S2/Tibia.spr --out-dir OUT \
      --spec client/tools/sprites/art_import/status_fx.csv --expect-first-effect 656 \
      --lua-out server/data/lib/chaos_status_fx_ids.lua --catalog-out server/data/spells/status_fx_catalog.csv
  python3 -I client/tools/sprites/check_pair.py OUT/Tibia.dat OUT/Tibia.spr --old things_custom24/Tibia.dat things_custom24/Tibia.spr
  ```
- Output **things_custom25** (2026-10-14; things_custom24 -> Everfull Ration 33904 -> gems 33905-33939 -> words
  656-673; input the windows-assets archive at 407ad9b6, dat 734dda1f..., spr fb385bf2...): dat
  dc1613e4479df53cf2e98efa9a7a5e5b (5,051,529 bytes), spr d970b1cbc61476ae47fbf8b5bbbff0e8 (635,988,303 bytes,
  764,346 sprites: 1 + 292 + 1,093 appended, +1.57 MB), 33,939 items, 2,212 outfits, 673 effects, 153 missiles. Built
  twice (trial and rebuild) with identical md5s and ids files; the importers verified 1 ration slot, 315 gem slots and
  203 word frames pixel-identical, and a separate read-back of the pair (datspr.py) matched all 316 item frames and
  203 effect frames to the art. `check_pair.py --old`: append-only (36,824 old things and 762,960 old sprites
  compared), 0 errors, 124 warnings, line for line those of things_custom24 (INFO `sprite-zero-slots` 4,046 -> 4,064).
- `things-1098.tar.xz` like things_custom24's (Tibia.dat and Tibia.spr at the root, owner 0/0, GNU tar, `xz -9 -T3`),
  mtime 2026-10-14 14:00: sha256 d748be06d8bcce20318edc212a566866a5d660f3bf2daf9aa5d1df59bf9b0090 (72,959,236 bytes),
  packed twice with the same sha256; the same command on things_custom24 gives its published sha256 (b1dbdf8d...). It
  unpacks to the md5s above. Pushed to windows-assets at ebe1b2b2 (owner approved 2026-10-14). The client has no switch of its
  own: it draws whatever the pair holds. `outfit_anchors.lua` regenerated from this pair (only its dat md5 changed).
- Server side (switches on since 2026-10-14): server/README.md "Status words" (`ChaosStatusFx.STATUS_FX`), "Gems and
  sockets" (`chaos_gems_config.lua` ownLook), "Store pouches and the Everfull Ration" (`store_food_config.lua` ownLook).
  `tools/ci/check_content.py --pair` now names things_custom25 (2,212 outfits, padding 2194-2199 blank).
- Checked offline only (importer checks, the read-back, check_pair). Not run in a live client.

## Pack farming spell effects (pair 27 trial, effects 674-758, missiles 154-160, `tools/sprites/gen_pack27_fx.py`, `art_import/pack27_fx.csv`; live since windows-assets 51a26d26, switch on)
**Source and licence.** The owner's oblique effect sets in Google Drive "ots" (2026-10-15; the owner confirmed all
packs may be used): four of them (spell impacts and circles, auras and buffs, game feel, projectiles), read as loose
files (each variant's .json and its flattened `full` sheet), 32 px. Pack names, author and licence: docs/CREDITS.md. In short: use in
unlimited personal and commercial projects (games included), modified or not, no attribution needed; no reselling,
redistributing, sublicensing or sharing of the assets themselves, alone or in another pack, template or generator,
even modified; no machine-learning use. Shipping converted frames inside the game client is use in a game. The sets
and the strips stay out of git: `art_import/pack27_fx/` is ignored; only the spec, `art_import/pack27_fx.sums` and
`art_import/pack27_sources.csv` (each pick: name, kind, pack, source effect/variant, licence line; read by
tools/ci/check_credits.py) are committed. No effect of the 500 effect set, of the explosion packs or of the free packs
is used yet: every pick has a fitting variant in the four packs above.
- Pack farming spells (24 effects, 4 missiles): palm_quake, flurry_petals, iaido_dash_<8 dirs>, ricochet_burst,
  chain_sparks, sanctified_seal, shieldwave_bash_<8 dirs>, shrapnel_burst; missiles fan_knife, ricochet_bolt,
  chain_disc, shrapnel_shards.
- Spell impacts for every class line (from the impact set): nova_frost, meteor_fall, storm_chain, smite_radiant,
  judgment_holy, nova_radiant, mend_holy, gyre_steel, berserk_blood, slam_earth, terra_strike, cleave_blood_<8 dirs>,
  backstab_shadow, parry_steel, venom_flurry, drain_blood, claws_shadow_<8 dirs>, punch_fire, hammer_steel,
  healing_burst. Missiles shuriken_steel, soul_skull, holy_orb.
- Circles (one stage of the set: `variant@stage`): rift_void (void, start), summon_necro (necrotic, start), portal_pad
  (arcane, loop), boss_telegraph (blood, loop; 5x5 tiles).
- Statuses (loop cuts, last three frames dissolve): vigil_wrath, vigil_iron, vigil_haste, vigil_clarity, ward_shield,
  aegis_radiant, veil_stealth, zeal_oath, bellow_cry, curse_mark, stun_stars; buff_rested, buff_returning,
  buff_catchup, buff_low_stamina, hunter_focus.
- Game feel: levelup_rise (frames 0-7 of the level up effect; from frame 8 on it shows English words, not used),
  loot_beam_gold / _steel / _amethyst / _emerald, embercache_coins, candlemark_glow, portal_in, portal_out.
- Conversion like the pack effect cuts: layers merged (back at 60 %, or the `full` sheet), alpha 0 / 255 with a 4x4
  dither, placed by the sets' pivot (feet on (14, 20), tile centre on (16, 16), missile centre on (13, 13)), an empty
  last frame for effects. 7,725 sprites, 92 things.
- `python3 -I gen_pack27_fx.py build --src DIR [--src DIR]` (DIRs hold the sets); `build --check` (CI) checks the spec,
  sums and sources file against the script's table without the sets; `preview --out DIR`.
- Trial build (2026-10-15, scratchpad only, not pushed): on things_custom26 (dat 4a019fec..., spr 800cd7ce...)
  ```
  python3 -I client/tools/sprites/import_fx_art.py --ours-dat things_custom26/Tibia.dat --ours-spr things_custom26/Tibia.spr \
      --out-dir pair27 --spec client/tools/sprites/art_import/pack27_fx.csv --expect-first-effect 674 --expect-first-missile 154 \
      --lua-out server/data/lib/chaos_pack27_fx_ids.lua --catalog-out server/data/spells/pack27_fx_catalog.csv
  python3 -I client/tools/sprites/check_pair.py pair27/Tibia.dat pair27/Tibia.spr --old things_custom26/Tibia.dat things_custom26/Tibia.spr
  ```
  dat 873b5ccd506f44223036c9eb213e2c90 (5,154,074 bytes), spr 790590495de8137b55af419859993a30 (649,841,615 bytes,
  775,674 sprites), 758 effects, 160 missiles. `check_pair.py --old`: append-only, 0 errors, 124 warnings (those of
  things_custom26). Server side: server/README.md "Pack farming spell effects" (switch `ChaosPack27Fx.PAIR27_FX`,
  off). Not run in a live client.

## Catacomb kit (pair 27 trial: outfit 2234, items 33986-33994, `tools/sprites/gen_assets_art.py`, `art_import/assets_art.csv`; live since windows-assets 51a26d26, switch on)
**Source and licence.** The owner's Drive folder "ots/assets", a monster and tile kit added 2026-10-15 (credited in
docs/CREDITS.md: same drop and licence file). Licence: use in unlimited commercial projects
(games included), modified or not, no attribution needed; no reselling, redistributing or sharing of the assets
themselves; no machine-learning training. The source files and the cut sheets stay out of git:
`art_import/assets_art/` is ignored; the spec, `art_import/assets_art.sums` (sha256 of every sheet's RGBA pixels) and
`art_import/assets_art_sources.csv` (pack per thing, read by tools/ci/check_credits.py) are committed.
- What could be taken: only files the Drive connector saves to disk (about 38 KB and up); smaller files come back inline
  and are not transcribed. Of the kit's ten monsters only the headless rider has strips that large (idle in four
  directions, walk north and west). Pending (needs a zip of the kit, or the folders as parts): black cat, raven,
  scarecrow stalker, hedge witch, harvest werewolf, pumpkin brute, skeleton warrior, skeleton archer, wailing ghost; the
  props, nature, borders, roofs and floor changes; the docks kit (`32/`).
- Outfit 2234 `hollow_rider` (5x5, 160 px, layers 1): idle group 4 phases, walk group 4 phases, 140 ms. Walk east and
  south use the idle strips of those directions. Monster: the Hollow Rider (server/README.md "Catacomb kit (pair 27
  trial)").
- Items 33986-33994 (server 36986-36994, `server/data/items/assets_decor.csv`): crypt portal (3x3, 8 phases, purple
  light), collapsing portal (4x4, 8 phases), burnt-out portal ring (4x4), sealed crypt hatch (3x3, blocks), breaking
  seal (3x3, 8 phases), open hatch (3x3), sarcophagus closed / opening (8 phases) / open (2x3, block). Each draws up and
  left of its tile: put it on the south-east tile of its square.
- `python3 -I gen_assets_art.py build --src DIR` (DIR holds the sources under the names of `SOURCES`); `build --check`
  (CI) compares spec, picks and sources with the tables and any sheets on disk with the sums; `gen_assets_art_test.py`
  (CI) runs the pure parts on synthetic strips; `preview --out DIR --dat P --spr S`.
- Build (2026-10-15; pushed with the pair 27 effects as things_custom27, windows-assets 51a26d26), appended to pair 27 (dat 873b5ccd506f44223036c9eb213e2c90):
  ```
  python3 -I client/tools/sprites/import_art_things.py --ours-dat pair27/Tibia.dat --ours-spr pair27/Tibia.spr \
      --out-dir pair27a --things client/tools/sprites/art_import/assets_art.csv --first-item 33986 --first-outfit 2234 \
      --expect-items 33985 --manifest-out server/data/items/assets_decor.csv
  python3 -I client/tools/sprites/check_pair.py pair27a/Tibia.dat pair27a/Tibia.spr --old pair27/Tibia.dat pair27/Tibia.spr
  ```
  dat 223a1c2fc1b0f99997414a5b2cde1773 (5,159,243 bytes), spr 40cccfc55924a53fcd16b3813c0e328a (650,961,766 bytes,
  776,193 sprites: 519 appended), 33,994 items, 2,234 outfits, 758 effects, 160 missiles. The importer verified 1,166
  sprite slots pixel-identical to the art. `check_pair.py --old`: append-only (37,037 old things and 775,674 old sprites
  compared), 0 errors, 124 warnings (those of pair 27). Previews: the look in four directions, a GIF of each walk, the
  items, a crypt scene. Not run in a client.

## Equipment sets (pair 28: items 33995-34442, `tools/sprites/gen_gear_sets_art.py`, `art_import/gear_sets.csv`; live since windows-assets b37b983c, switch on)
**Source and licence.** Seven 256 x 256 item sheets the owner sent on 2026-10-15, "made for us": the owner's own art,
usable without restriction (docs/CREDITS.md "Owner art"). They are committed as `art_import/gear_sets/<set>.png`: the
same pixels as the sheets (exact palette PNGs, about 22 KB each; `art_import/gear_sets.sums` holds the sha256 of each
one's RGBA pixels; `SOURCES` the md5 of each sheet as sent).
- Seven sets of 64 pieces, one per sheet, in id order: Cinderwrought (fire and ember) 33995-34058, Wyrmscale (green
  dragon) 34059-34122, Rimewraith (teal frost, spectral) 34123-34186, Azure Vigil (blue and gold paladin) 34187-34250,
  Bloodmoon (crimson, blood) 34251-34314, Gildcrown (gold) 34315-34378, Blightfang (dark green, venom) 34379-34442.
  Server id = client id + 3000 (`server/data/items/gear_sets.csv`; server/README.md "Equipment sets (pair 28)").
- `LAYOUT` names every cell, read off the sheets (helmets, armours, legs and boots, shields and spellbooks, swords and
  axes, clubs and launchers, amulets and rings, wands and rods; the order differs a little per sheet: Wyrmscale and
  Blightfang draw eight legs and no boots, Gildcrown two legs and six boots, five shields and three spellbooks). Armour
  pieces carry a fit (heavy, medium, cloth, or anyone where a slot has too few pieces); melee weapons are two-handed
  for the larger half of a kind by art pixels. Names are the set's prefix and a noun per kind and fit. Dat flags are
  copied from a stock item of each kind (`copy:`), as for the themed sets.
- `python3 -I gen_gear_sets_art.py build --src DIR` (DIR holds sheet1.png .. sheet7.png); `build --check` (CI)
  compares the atlases with the sums and the things file with the layout; `gen_gear_sets_art_test.py` (CI) runs the
  pure parts; `preview --out DIR --dat P --spr S` draws each set in a bag (8 x 8 slots) and three class kits (heavy,
  medium, cloth) in equipment slots beside a stock look tinted in the set's colours (the client draws no gear on a
  character).
- Build (2026-10-15), appended to pair 27 (windows-assets 51a26d26, dat 223a1c2fc1b0f99997414a5b2cde1773):
  ```
  python3 -I client/tools/sprites/import_art_things.py --ours-dat pair27a/Tibia.dat --ours-spr pair27a/Tibia.spr \
      --out-dir pair28 --things client/tools/sprites/art_import/gear_sets.csv --first-item 33995 --expect-items 33994 \
      --manifest-out server/data/items/gear_sets.csv
  python3 -I client/tools/sprites/check_pair.py pair28/Tibia.dat pair28/Tibia.spr --old pair27a/Tibia.dat pair27a/Tibia.spr
  ```
  dat 9f75ddfe73197bce388398e4c31ca255 (5,166,592 bytes), spr e0c74346aac1febb01e2197fd75004e1 (651,827,354 bytes,
  776,641 sprites: 448 appended), 34,442 items, 2,234 outfits, 758 effects, 160 missiles. The importer verified 448
  sprite slots pixel-identical to the art. `check_pair.py --old`: append-only (37,047 old things and 776,193 old sprites
  compared), 0 errors, 0 warnings in the new things; the whole pair 0 errors, 124 warnings (those of pair 27). Live pair
  checks against it: recolour `--check` and the dungeon banners pass unchanged; `gen_outfit_anchors.py` was run again
  (only the dat md5 in `outfit_anchors.lua` changes: no outfit was added), so that file must go in with the pair.
  Not on windows-assets yet, not run in a client.

## Mystic line effects, Tier B (pair 29: effects 759-779, missiles 161-169, `tools/sprites/gen_pack29_fx.py`, `art_import/pack29_fx.csv`; not live, switch off)
**Source and licence.** The owner's oblique effect sets in Google Drive "ots" (the loose files: a variant's .json and
its flattened `full` sheet; the 500 effect set's `metadata.json` and `all` sheets), credited in docs/CREDITS.md. Use in
games, modified or not, no attribution; no resale or redistribution of the files. The 500 effect set is imported only:
never a style reference or an AI input (docs/SPRITE_STYLE.md); `style_check.py` is not run on it. The sets and the
strips stay out of git (`art_import/pack29_fx/` is ignored); the spec, `pack29_fx.sums` and `pack29_sources.csv` (pack
per pick, read by tools/ci/check_credits.py) are committed. No pick is recoloured: every Mystic pick has a variant in
its theme colour; the Druid-kit spells keep the nature green.
- 21 effects: storm_shock, covenant_bloodlust, pyre_rune, crypt_ice_strike, doom_skyfall, doom_tornado, ironbark_skin,
  briar_rooted, squall_spore_cloud, mirror_ring, mirror_glass_nova, umbral_step, psyche_fracture, wraith_veil,
  night_eyelid, night_cataclysm, weave_crush, mend_chime, reverie_pop, reverie_release, hex_curse. 9 missiles:
  witchfire_lance, storm_bolt, pyre_comet, crypt_lance, hex_missile, umbral_raven, psyche_prism, weave_marble,
  mend_shards. 3,402 sprites. Which spell sends which: server/data/spells/README_FX.md "Mystic line effects, Tier B".
- Conversion: `gen_pack27_fx.py`'s (layers merged, alpha 0 / 255 with a 4x4 ordered dither, loop cuts dissolve in their
  last three frames, an empty last frame, missiles in the 3 x 3 direction patterns). The 500 set: placed by its anchor
  tile (the feet point), its projectiles by their frame centre with the flat ground shadow under them removed
  (near-black pixels of alpha 90-170).
- Ground: `client/tools/sprites/ground_fx.csv` lists the floor shapes and body-covering effects of the pair (rules 3 and 4
  of `gen_ground_fx.py`, cover measured on pair 29 into `ground_fx_cover.csv`); `storm_shock` stays above.
- `python3 -I gen_pack29_fx.py build --src DIR [--src DIR]` (DIRs hold the sets); `build --check` (CI) checks spec, sums
  and sources against the script's table without the sets; `preview --out DIR`.

## Archmage (pair 29: outfits 2235 male / 2236 female, `tools/sprites/gen_archmage_art.py`, `art_import/archmage.csv`; not live, switch off)
The Mystic line's class outfit, in place of the retired donor look 1559 (server/README.md "Class looks"). Our own art:
the class-look outfit rig (`tools/outfit_art/class_art_line.py` `archmage`, rendered by `class_art.py`), no donor,
stock, pack or AI pixels, owner-approved 2026-10-16. A long tinted robe, a white beard (his) or long white hair (hers),
an ember orb on a wooden staff with a gold claw; addon 1 a tall pointed hat with a gold band; addon 2 a dark mantle,
gold hem trim and a floating ember sigil. The stock player layout: 2x2, displacement 8,8, 2 layers (art + colour
template: hair, robe, skirt, boots), 3 addon patterns, 2 mount patterns, idle 1 + walking 8 (150 ms). Default
colours 0 / 94 / 94 / 114. `class_art.py edges`: no pose crosses the frame. The sheets are committed
(`art_import/archmage/`, sums in `archmage.sums`); a render from the repo code (`gen_archmage_art.py build`, about 20
minutes) gives them pixel for pixel; `build --check` (CI) checks the things file and the sums. `style_check.py check`
on the in-game frames (all addons worn, `--palette` of the frames, `--cell 64`): outline, light, noise and alpha pass in
all four directions; against the seven theme palettes it fails as every template outfit does (the grey parts the player
tints; nearest wyrmscale, mean distance 5.9).

## Condition auras, blasts and fireworks (pair 29: effects 780-829, missiles 170-185, `tools/sprites/gen_pack29_vfx.py`, `art_import/pack29_vfx.csv`; not live, switch off)
**Source and licence.** Five animated effect packs of one studio, bought by the owner on 2026-10-16 (status
effects, projectiles, fireworks, blood, explosions; names, studio and credit line in docs/CREDITS.md, internal labels
`set29 ...`). The README of each pack: use in games, commercial too, modified or recoloured; no resale and no sharing
of the raw files; never used as training data for generative AI; credit appreciated. So they are import-only
(docs/SPRITE_STYLE.md): never a style reference, `style_check.py` is not run on them. The packs and the strips stay out
of git (`art_import/pack29_vfx/` is ignored); the spec, `pack29_vfx.sums` and `pack29_vfx_sources.csv` are committed.
The pack files were read as PNG pixels only (python3 -I; nothing in them runs).
- 16 condition auras `cond_<state>` (burning, poison, frozen, slowed, shocked, bleeding, cursed, stunned, fear,
  silenced, confused, regeneration, blessed, enraged, invulnerable, petrified): half size (a 2 x 2 box mean, the alpha
  cut with the 4x4 dither), over the head of the creature on the target tile, send offset 0, 0 (the engine sends them
  by id on a condition tick). About 22 px: they never hide the creature.
- 16 element blasts `blast_*` (dark, energy, lightning, arcane, ice, fire1-6, boss, massive, ground, magical, poison):
  1:1, centred on the body (the ground blast on the feet), 3 x 3 tiles (massive 4 x 4).
- 16 fireworks `fw_*`: 1:1, bursting over the head; `fw_grand` (the big red, white and blue one, 4 x 4) is the
  level-up.
- 2 hit splashes: `hit_blood` (a small red splash) and `hit_blood_spray` (a small spiky spray), offset 0, 0. The blood
  pack is red only (9 splatters, 2 gushes, a drip), so venom, undead and energy creatures keep the stock hit; 10 strips
  are not used.
- 16 missiles `bolt_*`: the east-pointing strips, head and 48 px of trail, turned to the eight directions by an exact
  nearest-pixel rotation, in the client's 3 x 3 patterns, 8 frames of 50 ms.
- 4,685 sprites, 66 things. Which code sends what: server/README.md "Condition auras, blasts and fireworks (pair 29)".
- Ground: `blast_ground` (from the floor) and `blast_energy` (rule 4, 0.56 s over the body) are `ground` in
  `ground_fx.csv`; the two firework rings stay `above` (rule 3 overruled: they burst in the air).
- `python3 -I gen_pack29_vfx.py build --src DIR` (DIR holds the five unzipped packs); `build --check` (CI) checks spec,
  sums and sources against the script's table without the packs; `preview --out DIR`.

## Pair 29 build (2026-10-16; not on windows-assets yet, switches off)
Input pair 28 (windows-assets b37b983c, dat 9f75ddfe73197bce388398e4c31ca255, spr e0c74346aac1febb01e2197fd75004e1):
```
python3 -I client/tools/sprites/import_fx_art.py --ours-dat pair28/Tibia.dat --ours-spr pair28/Tibia.spr --out-dir p29fx \
    --spec client/tools/sprites/art_import/pack29_fx.csv --expect-first-effect 759 --expect-first-missile 161 \
    --lua-out server/data/lib/chaos_pack29_fx_ids.lua --catalog-out server/data/spells/pack29_fx_catalog.csv
python3 -I client/tools/sprites/import_art_things.py --ours-dat p29fx/Tibia.dat --ours-spr p29fx/Tibia.spr --out-dir p29arch \
    --things client/tools/sprites/art_import/archmage.csv --first-outfit 2235 --expect-items 34442
python3 -I client/tools/sprites/import_fx_art.py --ours-dat p29arch/Tibia.dat --ours-spr p29arch/Tibia.spr --out-dir pair29 \
    --spec client/tools/sprites/art_import/pack29_vfx.csv --expect-first-effect 780 --expect-first-missile 170 \
    --lua-out server/data/lib/chaos_pack29_vfx_ids.lua --catalog-out server/data/spells/pack29_vfx_catalog.csv
python3 -I client/tools/sprites/check_pair.py pair29/Tibia.dat pair29/Tibia.spr --old pair28/Tibia.dat pair28/Tibia.spr
```
- p29fx (effects only): dat 2db4a8dab9601b364a5637cf2c732990, spr 4833114106ab6a6cd5be532ee4ac082c; the importer
  verified 1,022 frames and patterns pixel-identical to the strips.
- p29arch (Mystic effects and the Archmage, the pair 29 of the first build): dat 5388d3d8951ac2c532a9a75259280ced,
  spr 07be0eb619f83b9125f7af45fb8ee98f (780,964 sprites); the importer verified 3,456 outfit sprite slots
  pixel-identical to the sheets.
- **pair 29**: dat 34d232e6fd55c4c0fa1ea94801174d81 (5,293,242 bytes), spr 1626993416a249aff774160dd5524027
  (658,304,426 bytes, 785,649 sprites: 9,008 appended to pair 28), 34,442 items, 2,236 outfits, 829 effects, 185
  missiles. The last step verified 1,789 frames and patterns pixel-identical to the strips. Built twice with identical
  md5s.
- `check_pair.py --old`: append-only (37,495 old things and 776,641 old sprites compared; new: 2 outfits, 71 effects,
  25 missiles), 0 errors, 124 warnings (those of pair 28); `--new-only`: 0 errors, 0 warnings in the new things.
  `gen_outfit_anchors.py --check` passes on it once `outfit_anchors.lua` is regenerated (the dat md5 and 2235 / 2236);
  the tree keeps pair 28's file until the switch-on, because CI checks it against the live pair.
  `server/tools/check_item_wire.py` (an installed items.otb and this dat): 0 nodes disagree.
- Archive `things/things-1098.tar.xz` (tar --owner=0 --group=0 --numeric-owner --mtime='2026-10-16 00:00:00Z'
  --format=gnu of Tibia.dat and Tibia.spr, `xz -9 -T0`, xz 5.4.5): 75,621,980 bytes, sha256
  6b667bda73987e5a7ba646c70d7f9b87de82b6aaecaf6a3e2d269e1b440e15c1; packed twice with the same sha256; it unpacks to
  the md5s above. Switch-on step: `ChaosPack29Fx.PAIR29` and `Chaos.classes.outfitReplacement.enabled` (server/README.md
  "Mystic line effects, Tier B (pair 29)", "Condition auras, blasts and fireworks (pair 29)", "Class looks"), the
  regenerated `outfit_anchors.lua`, and the engine built with src-patch 0045 for the engine-sent auras, splashes, blasts
  and missiles. Not run in a client.

## Pair 30 build (2026-10-20; third-party pack art, import-only; built twice, NOT pushed to windows-assets, switch off)
Input pair 29 (windows-assets 3f52a3e6, dat 34d232e6fd55c4c0fa1ea94801174d81, spr 1626993416a249aff774160dd5524027).
Generators: `client/tools/sprites/gen_pack30_{items,looks,strips,grounds,decor,bldg,anim,fx}.py` (each docstring has its
rules, `build [--src DRIVEPACKS] [--check]`), shared `pack30lib.py`; specs, sums, file lists and source tables in
`art_import/pack30_*`; the cut sheets (`art_import/pack30_<cat>/`) are ignored by git. Ids ascend, so the chain runs in
id order; every step uses `--expect-items` = the item count of the step before (`import_art_things.py`, step 1 on pair 29
with 34,442), manifests go to `server/data/items/pack30_*.csv`:
```
items    --things art_import/pack30_items.csv   --first-item 34443 --expect-items 34442
looks    --things art_import/pack30_looks.csv   --first-item 34759 --first-outfit 2237 --manifest-out .../pack30_looks.csv --outfits-out .../pack30_outfits.csv
strips   --things art_import/pack30_strips.csv  --first-item 34834 --first-outfit 2312 --manifest-out .../pack30_strips.csv --outfits-out .../pack30_strips_outfits.csv
grounds  --things art_import/pack30_grounds.csv --first-item 34859
decor1   --things art_import/pack30_decor1.csv  --first-item 35159
decor2   --things art_import/pack30_decor2.csv  --first-item 35559
bldg     --things art_import/pack30_bldg.csv    --first-item 36059
anim     --things art_import/pack30_anim.csv    --first-item 36459
bldg2    --things art_import/pack30_bldg2.csv   --first-item 37113   (building overflow)
decor3   --things art_import/pack30_decor3.csv  --first-item 37713   (decor overflow)
python3 -I client/tools/sprites/import_fx_art.py ... --spec art_import/pack30_fx.csv --expect-first-effect 830 --expect-first-missile 186 \
    --lua-out server/data/lib/chaos_pack30_fx_ids.lua --catalog-out server/data/spells/pack30_fx_catalog.csv
python3 -I client/tools/sprites/check_pair.py pair30/Tibia.dat pair30/Tibia.spr --old pair29/Tibia.dat pair29/Tibia.spr [--new-only]
```
Intermediate md5s (dat / spr), items after the step:
- items: 36b91ee20f889334f35022d4311cd44c / c07099b272b7f9e463f663a8c88a0285 (34,724)
- looks: d4502bbd2be4aa5dff1e9f66daf50ad6 / 6964620e9b5d472b362746d841ed64de (34,833; outfits 2,311)
- strips: ef49ffcc694045d2562c0ea3b1e6e317 / 44482d8839e9a7a3fc1e0c1dd300c94f (34,858; outfits 2,384)
- grounds: 5880a36b7300e3f59e40a21004a2773a / 01c3519fe3b7fba0c44fcaa1a99400cd (35,116)
- decor1: 6f94c2eb8c96c1b461e82f0492673627 / 9ddb1eed3b2db2d44b687f04a8417773 (35,547)
- decor2: b82203609acd88b5f5cd7c8bb6e8572a / 14c03424577ecd1e77c9978bf991c440 (36,045)
- bldg: 24003da7da1e52e3f6d9c4b27f000a2b / a7f2d82c935a37250cb2b14d45448d4c (36,448)
- anim: 999b3885e791ba86f8ccf8cd5f6a38b5 / 1e95d4fd96b1e454bf94de1f7e84bae2 (36,626)
- bldg2: d9e6fe57e17cb8b1f29471d7bda00997 / b2a6176e705354456feb91ff908cfae2 (37,603)
- decor3: 1639749a22279a47ccf75cc1678fdac7 / 3d5b765a2bd6148ab958edeb74ec327b (38,092)
- **pair 30** (after fx): dat 8156792438dabee3aa768663d57a1619 (5,726,916 bytes), spr 7ca9981f628cb639a52d1316ae2d9ddc
  (765,715,120 bytes, 842,219 sprites: 56,570 appended to pair 29), 38,092 items, 2,384 outfits, 854 effects, 188 missiles.
  Built twice from pair 29: every intermediate and the final md5 identical, final files byte-identical, all manifests,
  the fx id table and the fx catalog byte-identical.
- `check_pair.py --old`: append-only, 0 errors, 124 warnings (those of pair 29); `--new-only`: 0 errors, 0 warnings.
- Archive `things/things-1098.tar.xz` (tar --owner=0 --group=0 --numeric-owner --mtime='2026-10-20 00:00:00Z'
  --format=gnu of Tibia.dat and Tibia.spr, `xz -9 -T0`, xz 5.4.5): 88,004,624 bytes, sha256
  c3a13c0f3bd7504b8cc2f27fd555d4af2e2b74bb933a2fba3efdbdb16eafebef; packed twice with the same sha256. Not pushed
  (the owner approves after the import). The tree keeps pair 29's `Tibia.dat` md5 reference and `outfit_anchors.lua`
  until the switch-on (`ChaosPack30Art.PAIR30`, off). Not run in a client with the real pair.

## Wings displacement (pair 31: outfits 937, 938, 1185, `tools/sprites/fix_pair_warnings.py` kind `displacement`; on windows-assets ed7db076, owner approved)
Owner beta report (2026-10-20): "Lullaby Wings below the body, Bride Wings to the left, Fiery Wings shifted", in the
Outfit window and on the map. The names are the base `data/XML/wings.xml` (base server download on windows-assets;
the base tree is not in git): 1 Fiery Wings 937, 2 Lullaby Wings 938, 3 Falanaar Wings 939, 4 Vampire Wings 940,
5 Bark Wings 941, 6 Electric Rider Wings 1177, 7 Vorondor Flames 1178, 8 Mortis Mirage 1179, 9 Angelic Wings 1180,
10 Nimbus Wings 1181, 11 Butterfly Wings 1182, 12 Dreadbone Spectra 1183, 13 Enslaved Wings 1184, 14 Bride Wings 1185,
15 Strenght Wings 1186 (sic). 16-29 are ours (1486, 2140-2142, 2187, 2225-2233; server/README.md "Exclusives").
Only the dat changes: three wings get a new displacement (dat byte 25). No sprite is added or edited.
- Draw rule (`Outfit::draw` of the base client, 1098 profile with GameWingOffset; the same in a widget and on the map):
  the wings draw at the creature's place, the body 6, 6 up-left of it (`dest -= Point(6, 6)`), each moved back by its
  own displacement and (w-1)*32, (h-1)*32. A wings pixel lands at (x - dx - (w-1)*32, y - dy - (h-1)*32). Body or
  mount negative displacement uses its own pass (`usesNegativeDisplacement`); wings take no part in it, so a negative
  wings displacement only moves the wings (GameNegativeOffset is on; 2231 / 2232 already have -6,-12).
- Measure (`--scan-wings-displacement`, `wing_offset`): per direction the alpha-weighted mean of the wings' art (idle
  group, every phase and layer) minus that of the body, the stock citizen look 128 (8,8, phase 0, layer 0), both drawn
  by that rule; px, + = right / down. Facing south the stock wings sit at x -3.1..+3.9, y -21.5..-4.2: tall wings
  further up. Premise box `WING_BOX`: |x| <= 5, -23 <= y <= 0. Pair 30, facing south:
  937 +0.6,+1.5 (wings at the waist); 938 +2.5,+4.3 (below the waist); 1185 -11.6,-7.2 with 8,8 (12 px left; the only
  2x2 wings with 8,8, the others use none or 0,0; N -11.7 too); 1186 -3.7,-7.7 (1,8) and 941 +2.2,-5.4 look right on
  the sheet and stay. Also outside the box: 939 +0.3 y (0.3 px; looks right), 2233 -5.1 x (looks right) and the owner
  art 2231 / 2232 (Gloomgild, Sunforged; -6,-12) at -12.6,-5.7: on the sheet the two wings stand apart, far left of
  the body facing south and split facing north. Not changed here; re-centred in pair 32 ("Ornate wings re-centred").
- Fixes (`pair_fixes/fixes.csv`, `pair_fixes/pair31_changes.csv`, picked by eye on a before / after sheet, then the
  premise): 937 none -> 0,6 (S +0.6,-4.5; up 6 px, toward its sibling art Cinder Plumes 1486 at 4,5: -10.0);
  938 none -> 0,8 (S +2.5,-3.7; up 8 px); 1185 8,8 -> -4,8 (S +0.4,-7.2; right 12 px, height kept).
- `fix_pair_warnings.py`: the `displacement` kind has a wings premise for looks of `--wings-looks` (default
  `WINGS_LOOKS`, the 29 looks above): X, Y in -32..32, any old displacement is replaced, every frame group 2x2 or
  larger, the south centre outside `WING_BOX` with the old value and inside with the new one. Auras and player looks
  are unchanged. New `--scan-wings-displacement [--looks IDS]`. Tests: `fix_pair_warnings_test.py`
  `test_wings_displacement` (inserted, 8,8 replaced by a negative value, a no-op on its output, each refusal, the scan).

```
python3 -I client/tools/sprites/fix_pair_warnings.py --ours-dat pair30/Tibia.dat --ours-spr pair30/Tibia.spr --scan-wings-displacement
python3 -I client/tools/sprites/fix_pair_warnings.py --ours-dat pair30/Tibia.dat --ours-spr pair30/Tibia.spr \
    --out-dir pair31 --expect-dat-md5 8156792438dabee3aa768663d57a1619 --link-spr \
    --changes-out client/tools/sprites/pair_fixes/pair31_changes.csv
python3 -I client/tools/sprites/check_pair.py pair31/Tibia.dat pair31/Tibia.spr \
    --old pair30/Tibia.dat pair30/Tibia.spr --allow-changed 'outfit:937,938,1185'
```
Input pair 30 (the windows-assets archive at 8075c7e, sha256 c3a13c0f... checked against SHA256SUMS.parts; dat
8156792438dabee3aa768663d57a1619, spr 7ca9981f628cb639a52d1316ae2d9ddc). Output **pair 31**: dat
f139cdb4be9f692f262fe4a4587697a0 (5,726,926 bytes, +10), spr 7ca9981f628cb639a52d1316ae2d9ddc (unchanged), 38,092
items, 2,384 outfits, 854 effects, 188 missiles. The earlier fixes.csv rows are no-ops on pair 30. 3 things changed,
41,416 byte-identical. Built twice with identical md5s and changes csv; a run on its own output changes nothing.
- `check_pair.py`: append-only with `outfit:937,938,1185`: 0 errors (without it: 3 errors). Full check: 0 errors, 124
  warnings, line for line those of pair 30.
- `things-1098.tar.xz` like pair 30's (the same tar and `xz -9 -T0` flags, mtime 2026-10-20 00:00Z; that recipe
  rebuilds pair 30's archive to its sha256): 88,006,208 bytes, sha256
  83075e18d35a55a59ca5c1cf73aef7740859ac002312d0d9767d15e62b2d1a52, packed twice with the same sha256; unpacks to the
  md5s above. **On windows-assets since 2026-10-20 (ed7db076, owner approved).** No server change: the look ids stay. A client on pair 30
  keeps drawing the three wings off.
  `outfit_anchors.lua` (character select) regenerated from pair 31: the md5 and the rows 937, 938, 1185.
- Checked offline: a before / after sheet, four directions, the wings on look 128 by the rule above; the owner
  approved it. Not run in a live client by us.

## Ornate wings re-centred (pair 32: outfits 2231, 2232, `tools/sprites/gen_owner_art.py` WING_SHIFT, `art_import/owner_wings_fix.csv`; on windows-assets 1f109dc0, owner approved)
Gloomgild Wings (2231, wings.xml 27, the Nyxareth drop) and Sunforged Wings (2232, wings.xml 28, the Cinderheart drop),
found while checking the wings for pair 31. The owner's ornate sheet draws each direction around its own point: two
separate wings with a gap for the body, and the gap moves from column to column. Against the body (the "Wings
displacement" rule and `wing_offset`), the displacement that would put each direction where the stock 3x3 wings
(940, 1178, 1179, 1181, 1183, 1184, 2140-2142, 2187) sit, by the per-direction median: N -23,0, E +10,-16, S -17,-5,
W -2,-22. Our other wings stay within about 10 px of their own value (2225, 2233). No single displacement places all
four: pair 26's -6,-12 (chosen from the old tile-centre scan, no body) was already the best one, each direction up to
16 px off (facing south the wings stood apart from the body, facing east in front of it). The committed art matched
the owner's sheet pixel for pixel, so this was the source, not the cut.
- Fix: every cell of a direction moves by whole pixels, the same for every phase (`gen_owner_art.py` `WING_SHIFT`,
  `shift_cell`; it refuses to push art past the 96 px cell edge), and one displacement, -12,-12, places all four:
  N +11,-12, E -22,+4, S +5,-7, W -10,+10 (displacement minus need; -12,-12 is inside the range the cells' free room
  allows, x -23..-9, y -21..-7, and keeps the old y). No pixel is edited; the sheets `owner_art/wings_gloomgild.png`
  and `wings_sunforged.png` are the old ones with the shift (`build --src` gives the same: the shift runs after the
  cut). After: each direction at its stock median (S -1.6,-12.7 from the body; 2140 -2.9,-11.8).
- `import_art_things.py`: new in-place mode. An outfit row with mode=replace and look=ID rewrites that existing outfit
  (its sprites appended, its entry bytes replaced, the outfit count unchanged), so the look ids, wings.xml and the
  server stay as they are; the append-only guard allows exactly those outfits. `gen_owner_art.py` writes the two rows
  (`art_import/owner_wings_fix.csv`, covered by `build --check`). Test: `compose_outfit_test.py` (replace in place,
  counts, the other things byte-identical, the two refusals).

```
python3 -I client/tools/sprites/import_art_things.py --ours-dat pair31/Tibia.dat --ours-spr pair31/Tibia.spr \
    --out-dir pair32 --things client/tools/sprites/art_import/owner_wings_fix.csv --expect-items 38092
python3 -I client/tools/sprites/check_pair.py pair32/Tibia.dat pair32/Tibia.spr \
    --old pair31/Tibia.dat pair31/Tibia.spr --allow-changed 'outfit:2231,2232'
python3 -I client/tools/sprites/gen_outfit_anchors.py pair32/Tibia.dat pair32/Tibia.spr
```
Input pair 31 (windows-assets ed7db076). Output **pair 32**: dat 23c7265b887dfc61ac80e516490a390a (5,726,926 bytes,
the same size: the entries keep their length), spr 8b4af2e6cf8dbcf886df1d67f349a980 (766,089,521 bytes, 842,592
sprites, 373 appended), 38,092 items, 2,384 outfits, 854 effects, 188 missiles. Built twice with identical md5s. The
importer verified 576 sprite slots pixel-identical to the sheets and every other thing byte-identical.
- `check_pair.py`: append-only with `outfit:2231,2232`: 0 errors (without it: 2 errors). Full check: 0 errors, 124
  warnings, line for line those of pair 31; INFO `spr-unused` 29,938 -> 30,270 (the two wings' old records).
- `outfit_anchors.lua` regenerated from pair 32 with the push (the md5 and the rows 2231, 2232).
- `things-1098.tar.xz` (the pair 30 / 31 recipe): 88,033,268 bytes, sha256
  54405b25e7e00a6fff72e32f21f89fb34f8aee69dd66a55652e079613a8ea52b, packed twice with the same sha256. **On windows-assets
  since 2026-10-20 (1f109dc0, owner approved).** No server change. A client on pair 31 keeps drawing the two wings off.
- Checked offline: a before / after sheet on look 128, four directions; the owner approved it. Not run in a live
  client by us.

## Pair 33 packs (outfits 2385-2667, items 38093-38607, `tools/sprites/gen_pack33.py`, `art_import/pack33_*`; built as pair 33 on 2026-10-21, on windows-assets 1c7c58df: "Pair 33 build")
Four purchased packs of one vendor, uploaded by the owner to the Drive folder "ots" on 2026-10-21 (internal labels
`set33 wings`, `set33 heads`, `set33 capes`, `set33 kit`; names and licence in docs/CREDITS.md). None of the four was
imported before: no earlier pair, csv or tool names their files (the wings zip is labelled v2 but its own readme says
v1.0; the kit is v2.0, its changelog says refined monster and boss sprites over v1.0, which we never had). The
"hollow" rider of the catacomb kit (`assets_art.csv`) is another pack.
**Licence** (each pack's LICENSE.txt, same text): personal and commercial games, modified or not, no attribution
(credit appreciated); no resale, redistribution, sublicensing or sharing of the assets, alone or in another pack, even
modified; never machine-learning training. So: in-game use is allowed, the art ships only inside the compiled
`Tibia.spr`; import-only like set30 (docs/SPRITE_STYLE.md): `style_check.py` is not run on it, no palette is sampled,
the cut sheets (`art_import/pack33_<slug>/`) and the contact sheets are never committed.
**What they are** (the packs' metadata and catalogue; 32 px oblique, light from the upper left):
- `set33 wings`: 100 wings in 8 elements (12 each, 16 neutral), 8 directions, 16 / 20 / 24 frame loops at 12 fps,
  frames 96-160 px with an anchor tile; a per-frame body lift and a ground shadow in the back layer.
- `set33 heads`: 100 head accessories (horns, ears, halos, crowns, orbiting charms; 8 elements), 8 directions, a back
  and a front layer, 16 frames at 12 fps, frames 64-128 px.
- `set33 capes`: 100 capes and cloaks (8 elements), 8 directions, back and front layers, 24 frames at 12 fps, 64-96 px.
- `set33 kit`: 664 sprites of a harvest farmland and its catacombs: 5 x 9 grounds + 2 x 9 crypt grounds, 95 borders,
  15 decals, corn and pumpkins, a corn maze, 3 wall sets + 2 crypt wall sets and a portcullis, 3 fences, wall
  decorations, 2 roof styles (86 pieces + 8 tower roofs), trees, props, 35 event-mechanic states (pumpkin growth,
  ritual circle and portal, crypt seal, grave, upright coffin, candy cauldron and mimic, lantern post, gibbet, bell,
  offering altar), event decorations, catacomb stairs, 5 monsters, 4 critters and a 3x3 boss (idle, walk, attack /
  death strips in 4 directions), render maps (`_albedo`, `_light`, `_normal`, `_height`, `_fx`) and floor parts.
**Cut** (`gen_pack33.py` docstring has the rules; `build --src SRC`, CI `build --check` and `gen_pack33_test.py`):
- Ids as built (after the owner's drop list of 2026-10-21, "Pair 33 build"): wings 2385-2476 (92), heads 2477-2568
  (92), capes 2569-2657 (89), kit looks 2658-2667; kit items unchanged. The ids and counts below are those of the first
  cut (all 100 of each).
- Wings 2385-2484: one layer (the combined sheet), dat directions N, E, S, W from the pack rows 6, 0, 2, 4 (diagonals
  dropped), one group, animateAlways, 83 ms; 44 3x3, 30 4x3, 26 4x4. The pack's lift is not used (the client lifts the
  body 6 px, GameWingOffset).
- Heads 2485-2584 and capes 2585-2684: aura things, layer 0 = the pack's back sheet, layer 1 = its front sheet
  (GameAuraFrontAndBack), 16 / 24 phases at 83 ms; heads 93 2x2, capes 90 2x2, the rest 1x1 to 3x3.
- Every frame trimmed to the union alpha box (alpha < 12 cleared); displacement = BODY_REF 8 minus the art right of /
  below the wearer's tile, plus the big-aura centring for heads and capes (wings -29..+6, heads +12..+40, capes
  -4..+26). Wings x since the build: WING_REF_X 4 and WING_X_FIX ("Pair 33 build").
- Kit looks 2685-2694 (idle 4 + walk 4, one layer, no mask): black cat, harvest werewolf, hedge witch, the boss (5x5),
  pumpkin brute (4x4), raven (hop as walk), scarecrow stalker, skeleton archer, skeleton warrior, wailing ghost.
  Attack / cast / death strips unused; the boss's last death frame is a corpse item (38607).
- Kit items 38093-38606 (514): 63 grounds (minimap colour from the mean), 110 borders and decals, 168 blocking props and
  walls (`bottom notwalkable notmoveable`), 157 walkable decor (open doors and gates, roofs, stairs, portal, circles,
  small decals), 16 wall hangings; 37 animated (strip phases, frame ms), 38 with light 3 / colour 206; 43 have a
  footprint over one tile (kept whole, anchored bottom-right: block the other tiles on the map or split them later).
  Not imported: the 28 floor parts (the dat draws a tall item whole), the static first frame of the 2 lantern strips,
  the render maps.
**Test pair** (local, scratchpad only, deleted): pair 32 (windows-assets 1f109dc0, dat 23c7265b..., spr 8b4af2e6...)
+ the four things files in id order, `import_art_things.py --first-item 38093 --first-outfit 2385 --expect-items
38092`: dat 61fa5ecf2e11431e409291d09be2704e (6,734,349 bytes), spr aaade8d5ea95b8b1930163646baaab11 (875,850,722
bytes, +109.8 MB; 98,349 sprites appended, 303 reused; 940,941), 38,607 items, 2,694 outfits; 235,780 sprite slots
pixel-identical to the sheets; built twice, identical md5s and manifests. `check_pair.py --old --new-only` with the
heads and capes as `--aura-looks`: 0 errors, 0 warnings; full check 0 errors, 324 warnings = pair 32's 124 + 200
`mask-not-mask` (the 200 aura looks until they are in `chaos_auras*.csv`). `fix_pair_warnings.py
--scan-wings-displacement`: facing south the wings' centre is x -10.0..+3.4 (median -4.2), y -18.3..-0.3 (median
-10.8) from body 128; 41 of 100 lie outside the premise box |x| <= 5 (all by x, leaning left), so the owner's preview
decides whether BODY_REF x needs a pack-wide shift. Heads: art centre about 21 px up-left of the tile centre (on the
head of a 2x2 look); capes -1..-13 px.
**Proposed use** (before the owner's decisions; what was done: "Pair 33 build", server/README.md "Pair 33 cosmetics"):
- Wings: 100 new wings.xml looks (ids 30-129, after our 16-29) sold in the store's Wings category per element, a few as
  exclusives (boss drops / achievements); `install_outfits.py` writes the lines behind a `PAIR33` switch like
  `chaos_owner_art.lua`. Theme review by name: circuit, hologram, neon butterfly, pixel block, thruster jet and gyro
  ring wings read as sci-fi.
- Heads and capes, step 1 (no engine change): auras (`chaos_auras_*.csv` ids 33-232), a store category each ("Head
  Accessories", "Capes") that sells auras; a player wears one aura, head piece or cape at a time. Step 2 (engine):
  two new outfit fields `head` and `cape` (server src-patch: Outfit_t, the outfit packet, the outfit window, a player
  column; client base patch: Outfit fields, drawn like the aura's back / front layers, rows in the Outfit window and
  `game_outfitextras`), so they stack with wings and auras. Theme review: atom orbit, circuit visor, neon headset,
  robot antennae, propeller beanie, ringed planet, mouse ears; academic gown, circuit, fiber optic, glitch pixel, neon
  tatter, aviator scarf and pompom capes.
- Kit: a harvest event map (farmland, corn maze, chapel, catacombs) with the event mechanics as item transforms
  (pumpkin growth, crypt seal stairs, graves and coffins that spawn monsters, the ritual circle portal), the five
  monsters, four critters and the boss in monster XML (`apply_monster_looks.py` picks), and the kit for the area
  planner and map makers (`install_pack_items.py` manifest to server ids 41093-41607).
- Server work per use: items.otb / items.xml (`install_pack_items.py`), wings.xml / auras (`install_outfits.py`,
  `install_auras.py`), store offers and prices (`shop_config.lua`), exclusives, Store and Cosmetics previews (they
  draw outfits already), `check_content.py --pair`, `outfit_anchors.lua` regenerated, `ChaosPack33.PAIR33` switch.
- The spr grows by about 110 MB (+11.7% sprites); the size of the packed `things-1098.tar.xz` was not measured.

## Pair 33 build (2026-10-21; pair 32 + the kept pack33 pieces; built twice, on windows-assets 1c7c58df since 2026-10-21, the owner's go)
Owner decisions of 2026-10-21: (1) pair 33 approved; (2) head accessories and capes become auras (no engine change),
two store categories "Head Accessories" and "Capes"; (3) the sci-fi themed pieces are dropped; (4) the wings' x
placement is fixed against the body.
- **Dropped** (`gen_pack33.py` DROP, by name; the build refuses a DROP name the pack does not have). The owner's list:
  wings circuit, hologram, neon butterfly, pixel block, thruster jet, gyro ring; heads atom orbit, circuit visor, neon
  ear headset, robot antennae, propeller beanie, ringed planet float, mouse ears; capes academic gown, circuit, fiber
  optic train, glitch pixel, neon tatter, aviator scarf, knit pompom capelet. Added on the same rule after reading the
  full lists: magnet field and plasma fly wings, the tesla crown (a modern name), the plasma train, ion hood, hex shield
  and magnet plate capes. Kept though borderline: clockwork wings and gear cape, brass fan, nebula, galaxy cloak, coil
  capelet, officer cape, pinwheel wings and hairpin. Kept: 92 wings, 92 heads, 89 capes (27 dropped); the kit whole.
- **Wings x.** Measured (`gen_pack33.py wingx`, the rule of `fix_pair_warnings.py` `wing_offset`: the wings' alpha
  mean, every phase, minus the body's, the body 6 px up-left, GameWingOffset). The body reference: stock look 128
  facing south has its art centre 7.2, 7.1 px from its tile's top left (8.8 / 8.9 px up-left of the tile centre), as
  its 8,8 displacement says, so 8 is right for the body itself (our class looks sit 2.5 px from the tile's left, median
  of 67, 4.7 px further left). The pack's wings sit 11.0 px left of their anchor tile's centre (median, -16.8..-3.4):
  the vendor's figure stands further left in its 64 px cell and lifts itself only about 2.7 px (its `lift_px`), our
  client 6. With BODY_REF 8 the wings' south centre was x -10.0..+3.4 from the body (median -4.2; 41 of 100 outside
  |x| <= 5). Fix: the wings' x reference WING_REF_X = 4 (every wing 4 px right), then WING_X_FIX for the 38 wings still
  more than WING_TOL 3 px off (-6..+7 px each, to the body's centre). After (on pair 33, `fix_pair_warnings.py
  --scan-wings-displacement --looks 2385-2476`): south x -2.9..+2.9 (median 0.0), y -18.3..-0.3 (median -11.1; the
  premise box -23..0), north x median -2.7; 0 outside the premise box. Heads and capes keep BODY_REF 8 (measured for
  the record: the heads' south centre 4.5 px left of body 128 at the head's height, the capes' 4.2 px right at theirs;
  no change asked).

```
python3 -I client/tools/sprites/gen_pack33.py build --src SRC          # tables + sheets (sheets ignored by git)
python3 -I client/tools/sprites/gen_pack33.py wingx --src SRC --dat pair32/Tibia.dat --spr pair32/Tibia.spr
(head -1 art_import/pack33_wings.csv; tail -q -n +2 art_import/pack33_{wings,heads,capes,kit}.csv) > art_import/pack33_all.csv
python3 -I client/tools/sprites/import_art_things.py --ours-dat pair32/Tibia.dat --ours-spr pair32/Tibia.spr --out-dir pair33 \
    --things client/tools/sprites/art_import/pack33_all.csv --first-item 38093 --first-outfit 2385 --expect-items 38092 \
    --manifest-out pack33_items_manifest.csv --outfits-out pack33_outfits_manifest.csv
python3 -I client/tools/sprites/check_pair.py pair33/Tibia.dat pair33/Tibia.spr --old pair32/Tibia.dat pair32/Tibia.spr [--new-only]
python3 -I client/tools/sprites/gen_outfit_anchors.py pair33/Tibia.dat pair33/Tibia.spr
```
(`pack33_all.csv` is the four things files joined in id order, header once; temporary, not committed.)
Input pair 32 (windows-assets 1f109dc0, archive sha256 54405b25..., dat 23c7265b887dfc61ac80e516490a390a, spr
8b4af2e6cf8dbcf886df1d67f349a980). Output **pair 33**: dat bd8bb6781f274c392a3332e7a043bdba (6,646,976 bytes), spr
05803c7851fe25b5d8dd3021c43a1fc4 (867,445,763 bytes, 933,382 sprites: 90,790 appended, 293 reused), 38,607 items,
2,667 outfits, 854 effects, 188 missiles. The importer verified 515 items and 283 outfits, 215,156 sprite slots
pixel-identical to the sheets and every old thing byte-identical. Built twice: identical md5s and manifests.
- `check_pair.py --old`: append-only, `--new-only` 0 errors, 0 warnings; full check 0 errors, 124 warnings, the
  categories and counts of pair 32 (the 181 aura looks are `--aura-looks` by default through
  `server/data/XML/chaos_auras_pack33.csv`; without it 181 `mask-not-mask`).
- `things-1098.tar.xz` (the pair 30 / 31 / 32 recipe, mtime 2026-10-21 00:00Z, `xz -9 -T0`, xz 5.4.5): 94,844,592
  bytes (under GitHub's 100 MB), sha256 01230938d712ab14a24ebfefd5194f875f36140078cfa2a7d36ec9cdf6cb9c3e, packed twice
  with the same sha256; unpacks to the md5s above. Committed on the local branch `windows-assets-pair33` (1c7c58df, on
  1f109dc0: the archive and SHA256SUMS.parts, like pairs 31 / 32); pushed to windows-assets on 2026-10-21 (the owner's go).
- `outfit_anchors.lua` from pair 33 (1,974 things, +283) landed with the push (the live-pair CI job checks the table
  against windows-assets). The server switches `ChaosPack33.PAIR33` and `ChaosHarvestArt.PAIR33` are on since then
  (server/README.md "Pair 33 cosmetics", "Haunted Harvest").
- The kit items' server side (items.otb / items.xml manifest to server ids 41093-41607, monsters, an event map) is not
  done: the importer's manifests are in the build folder only.
- Checked offline: the wings scan above, owner previews of every wings, head and cape on look 128 in four directions
  (`gen_pack33.py preview`) and contact sheets (`contact`), scratchpad only (never committed, never given to an AI
  tool). Not run in a client.

## Store item looks (pair 34: items 38608-38611, `tools/sprites/gen_store_items_art.py`, `art_import/store_items.*`; on windows-assets 584dab51 since 2026-10-21)
The Gem Pouch (server id 32095, 2026-10-28) adds no sprite: `pouches_config.lua` `clientId = 0` keeps the stock jewelled
backpack's own client id on its node (`install_pouches.py`).

Owner report 2026-10-22 with screenshots: the Loot Bag, Orbs Pouch, Rift Key Pouch and Everfull Ration showed grey in the
backpack and the purse ("ícones ainda estão cinzas"), while the store window drew them in colour.
- **Cause.** Not the art and not the client ids: the store window draws the same sprites (33651-33653, 33904). The
  server gave every pouch and the ration `chaos_locked = 1`, and `game_shaderfx` draws value 1 (a player's own lock, the
  crafting bench) with the grey shader (`shaderfxlogic.lua` `isLocked`). The Everfull potions had the same bug and got
  value 2 on 2026-10-16. Fix on the server: `bindLock = 2` in `pouches_config.lua` and `store_food_config.lua`; new
  items get 2, older ones are rebound at login (`ChaosPouches.rebind`, `ChaosStoreFood.rebind`; server/README.md
  "Store pouches"). Value 2 is still locked for every server and engine check (any value but 0).
- **New looks.** The old tiles failed `style_check.py` (362 to 425 colours a tile: the 4:1 downsample kept every
  in-between colour). `gen_store_items_art.py build` reads our own tiles `art_import/pouches.png` and
  `art_import/store_food.png` and snaps each to one theme palette (`style_check.snap`, CIE76 nearest colour): Loot Bag
  gildcrown, Orbs Pouch rimewraith (the violet and the cyan orb stay; the drawstring turns silver), Rift Key Pouch
  azurevigil, Everfull Ration cinderwrought. All four pass `style_check.py check` against their theme; `build` refuses
  a failing tile, `build --check` (CI, fx venv) compares the committed atlas and things file. Silhouettes unchanged.
- Things file `art_import/store_items.csv`: client 38608 Loot Bag, 38609 Orbs Pouch, 38610 Rift Key Pouch, 38611
  Everfull Ration; flags copied as before (`copy:10325`, `copy:8861`, `copy:7343` containers, `copy:3583` the
  stackable dragon ham); mode replace with server ids 32081-32084. The server points the items at them (`clientId`;
  `oldClientId` 33651-33653 / 33904 is replaced in place by `install_pouches.py` / `install_store_food.py`). The old
  sprites stay in the pair (append-only).

```
python3 -I client/tools/sprites/gen_store_items_art.py build [--preview DIR]
python3 -I client/tools/sprites/import_art_things.py --ours-dat pair33/Tibia.dat --ours-spr pair33/Tibia.spr --out-dir pair34 \
    --things client/tools/sprites/art_import/store_items.csv --first-item 38608 --expect-items 38607
python3 -I client/tools/sprites/check_pair.py pair34/Tibia.dat pair34/Tibia.spr --old pair33/Tibia.dat pair33/Tibia.spr [--new-only]
python3 -I client/tools/sprites/gen_outfit_anchors.py pair34/Tibia.dat pair34/Tibia.spr
```
Input pair 33 (windows-assets 1c7c58df, dat bd8bb6781f274c392a3332e7a043bdba, spr 05803c7851fe25b5d8dd3021c43a1fc4).
Output **pair 34**: dat 11babc2e0f6d93fe1c1cc40c75787f18 (6,647,045 bytes), spr c0bfd875474ccc6816ee6cecb13ef469
(867,454,211 bytes, 933,386 sprites: 4 appended), 38,611 items, 2,667 outfits, 854 effects, 188 missiles. The importer
verified the 4 sprite slots pixel-identical to the atlas and every old thing byte-identical. Built twice: identical
md5s and manifests.
- `check_pair.py --old`: append-only, `--new-only` 0 errors, 0 warnings; full check 0 errors, 124 warnings (those of
  pair 33). On pair 34 also: `gen_theme_art.py recolour --check` and `gen_dungeon_banners.py --check` pass.
- `outfit_anchors.lua` regenerated (only the dat md5 changes; no new outfit).
- `things-1098.tar.xz` (the pair 30-33 recipe: `tar --owner=0 --group=0 --numeric-owner --mtime='2026-10-21 00:00:00Z'
  --format=gnu`, `xz -9 -T0`, xz 5.4.5): 94,842,748 bytes, sha256
  8337f0877f164208cc938409beb6b8ea4e3d6acea8efc38e40502f6242ee82b5, packed twice with the same sha256; unpacks to the
  md5s above. Pushed to windows-assets at 584dab51 on 2026-10-21 (on 1c7c58df; the owner allowed new pairs without asking).
- A client on pair 33 or older draws nothing for 38608-38611: ship the new pair with the server change.
- Previews (before, after, before as the grey shader drew it): scratchpad only. Not run in a client.

## Store inbox icons (next pair after 56: items 38608, 38609, 38611 redrawn in place, `tools/sprites/gen_inbox_icons_art.py`, `art_import/inbox_icons*`; sources committed 2026-10-29, pair not built yet)
Owner request 2026-10-29 (pt-BR): "refaca esses icones no pixellab" for the Store Inbox window. It shows three store items:
- Loot Bag: client 38608, server 32081 (a brown leather coin sack). Orbs Pouch: client 38609, server 32082 (a violet pouch, cyan orb).
  Everfull Ration: client 38611, server 32084 (the roast on a plate). The Gem Pouch (server 32095) keeps the stock jewelled backpack look, no sprite of ours.
- **Art.** PixelLab Pro, 32 x 32, no background, 64 candidates a call, the theme palette of the old look as the palette (Loot Bag gildcrown, Orbs
  Pouch rimewraith, Everfull Ration cinderwrought; docs/SPRITE_STYLE.md). Three candidates a look were kept (a, b, c); the first is committed as
  `art_import/inbox_icons/{loot,orbs,ration}.png`. All nine pass `style_check.py check --theme <theme>`. PixelLab's pixels, owner to pick, not repainted.
  Credit: docs/CREDITS.md "Tools" (PixelLab).
- **Pick another.** `python3 -I client/tools/sprites/gen_inbox_icons_art.py build --src DIR --pick loot=b,orbs=a,ration=c` (DIR holds
  `<loot|orbs|ration>_<a|b|c>.png`). `build --check` (CI) rebuilds the atlas, things file (mode redraw) and sums from the committed sources.
- **How into the pair.** Same step as pair 53, on the newest pair (ids and flags stay, so no server change; the old sprites stay, unused):
```
python3 -I client/tools/sprites/redraw_items.py --dat pairN/Tibia.dat --spr pairN/Tibia.spr --out-dir pairN1 \
    --item 38608=client/tools/sprites/art_import/inbox_icons/loot.png --item 38609=client/tools/sprites/art_import/inbox_icons/orbs.png \
    --item 38611=client/tools/sprites/art_import/inbox_icons/ration.png
python3 -I client/tools/sprites/check_pair.py pairN1/Tibia.dat pairN1/Tibia.spr --old pairN/Tibia.dat pairN/Tibia.spr --allow-changed 'item:38608,38609,38611'
```
  then `gen_outfit_anchors.py` and `gen_info_lift.py` as for every pair, pack, push to windows-assets (owner approval) and rebuild with `windows-package.yml`.
  Not run against a pair yet.

## Jewelry looks (pair 35: items 38612-38640, `tools/sprites/gen_jewelry_art.py`, `art_import/jewelry.*`; built 2026-10-22, on windows-assets 099b9a2, owner approved)
Owner request 2026-10-22: "use sprites de rings e necklaces dos nossos assets". The 29 loot bases of rings and
necklaces (server `data/lib/chaos_jewelry.lua` `J.bases`; server/README.md "Rings and necklaces as gear") get their
own icons.
- **Source.** The free fantasy icon set of docs/CREDITS.md (internal label `set35 icons`): its 32 x 32 full sheet
  (512 x 4384, 16 x 137 cells), Drive file id and md5 in `gen_jewelry_art.py` `SOURCE`. The sheet is its 16 px art
  doubled pixel for pixel; `build` checks that for each pick, takes the 16 px cell and doubles it with Scale2x
  (`pack30lib.scale2x`, as the importer does for 16 px art). No colour changed, nothing redrawn. Imported art stays as
  it is (docs/SPRITE_STYLE.md), so `style_check.py` is not run on it (4 to 9 colours a tile). Each pick is named by
  sheet row and column in `PICKS` and in `art_import/jewelry_sources.csv`.
- Things file `art_import/jewelry.csv`: client 38612-38621 the ten rings (life, power, sword, axe, club, healing,
  death, prismatic, temptation, butterfly), 38622-38640 the 19 necklaces (bronze to cobra), in `J.bases` order. Flags
  `copy:<stock client id>` of each base (pickupable, moveable and the rest as before; one phase, so not animated);
  mode replace with the server id. `gen_jewelry_art.py build --check` (CI) checks the things file, the atlas size and
  the order, server ids, looks and stock ids against `chaos_jewelry.lua`; with `--src SHEET` it also rebuilds the
  atlas and compares it pixel for pixel.
- The server points the 29 items.otb nodes at 38612-38640 (`server/tools/patch_base_jewelry.py`, install step
  `jewelry`; FLAG_ANIMATION cleared on the lightning pendant 7889). `--stock-looks` puts the stock client ids back.

```
python3 -I client/tools/sprites/gen_jewelry_art.py build --src SHEET [--preview DIR]
python3 -I client/tools/sprites/import_art_things.py --ours-dat pair34/Tibia.dat --ours-spr pair34/Tibia.spr --out-dir pair35 \
    --things client/tools/sprites/art_import/jewelry.csv --first-item 38612 --expect-items 38611 --manifest-out jewelry_manifest.csv
python3 -I client/tools/sprites/check_pair.py pair35/Tibia.dat pair35/Tibia.spr --old pair34/Tibia.dat pair34/Tibia.spr [--new-only]
python3 -I client/tools/sprites/gen_outfit_anchors.py pair35/Tibia.dat pair35/Tibia.spr
python3 -I client/tools/sprites/gen_info_lift.py pair35/Tibia.dat pair35/Tibia.spr
```
Input pair 34 (windows-assets 584dab51, archive sha256 8337f0877f164208cc938409beb6b8ea4e3d6acea8efc38e40502f6242ee82b5,
dat 11babc2e0f6d93fe1c1cc40c75787f18, spr c0bfd875474ccc6816ee6cecb13ef469).
Output **pair 35**: dat 58a5433bb0eabd77034e99de50274390 (6,647,514 bytes), spr b0bf4694dfa3e9cea99c7ca4a98582e2
(867,504,488 bytes, 933,415 sprites: 29 appended), 38,640 items, 2,667 outfits, 854 effects, 188 missiles. Built twice:
identical md5s and manifests.
- `check_pair.py --old`: append-only, `--new-only` 0 errors, 0 warnings; full check 0 errors, 124 warnings (those of
  pair 34).
- `outfit_anchors.lua` and `info_lifts.lua`: on pair 35 only their dat md5 changes (no new creature; both `--check`
  pass on pair 35 after the two commands above). Regenerated on pair 35 when it was published.
- `things-1098.tar.xz` (the pair 34 recipe, xz 5.4.5): 94,843,556 bytes, sha256
  a879b8bb852fe0f92efe524a4bf262aec8bea3ad501c647e4a2bc3743a263b11; unpacks to the md5s above. On windows-assets 099b9a2 (owner
  approved 2026-10-22); windows-package.yml builds pair 35.
- A client on pair 34 or older draws nothing for 38612-38640: ship pair 35 with the server step, or install the server
  with `patch_base_jewelry.py DATA_DIR --stock-looks`.
- Preview: scratchpad only. Not run in a client.

## Purchased effect packs (pair 36: effects 855-4101, missiles 189-250, 176 effects and missiles redrawn in place; `tools/sprites/gen_pack36_fx.py`, `art_import/pack36_*.csv`; built 2026-10-22, on windows-assets ab96c012)
Owner requests 2026-10-22: "Use o máximo de assets de lá por favor. São todos comprados", "Use as spells, level up e
loot beams", use everything usable. Sources: the purchased effect packs of docs/CREDITS.md (a tile-grid set in four
parts, a large set of 500, the spell set already in the pair, spells and impacts, auras and buffs, fields and traps,
projectiles, game feel, the animated loot beams), read from a local folder outside the repo (`--src`). **Licence: the art may reach
players only inside the pair.** No strip, frame or sheet is committed: `art_import/pack36_fx/` is git-ignored; the repo
holds the tool, the things files (names, ids, offsets, durations), `pack36_fx_sources.csv` (pack, file and effect id
of each thing) and `pack36_fx.sums` (sha256 of each strip, for `build --check`).
- **Formats.** Grid, Mega and Spellcraft: the `oblique/32` sheet of each effect (32 px), placed by the anchor of its
  metadata. The other packs: 64 px sheets, halved (premultiplied 2 x 2 mean, ordered alpha), their pivot halved; the
  point is the tile centre or the feet. Loot beams: 24 frames of 64 x 128 halved to 32 x 64, 70 ms a frame.
- **In place** (`art_import/pack36_replace.csv`, column `replace`): 141 effects (the stock ids our `gen_effects.py`
  redrew, the procedural 372-428, the combat feedback 415 crit, 416 dodge, 417 and 628 reflect) and 35 missiles. The
  crit (173, 415), dodge and reflect ids get pack animations, not the pack's word pop-ups (owner 2026-10-17: "the
  animation, not the word"; 416 is also Mistborne Step, 417 a shield buff fallback). The word pop-ups (`w_text_*`,
  English words in the art) are appended and sent by nothing. Every engine, monster and script send of those ids shows the new art; send
  offset 0, 0 (628: 1, 1, as before); art past the bottom-right tile is moved up and left as a whole by (sx, sy)
  pixels, cut beyond 4 x 4 tiles (2 effects lose 3-6 % of their pixels). The effect's pivot (the ring's middle, the
  pack author's centre) goes with the art, so it sits (sx, sy) up and left of its place. The build records every pull
  in `art_import/pack36_replace_pivots.csv` (`gen_pack36_fx.pull`; checked by `build --check`), and the server sends
  each id at the whole-tile offset that brings the pivot back, 15 px off at worst (`tools/sprites/gen_fx_send_offsets.py`
  -> `server/data/lib/chaos_fx_send_offsets.lua`, 15 ids: Lua sends, and engine sends with src-patch 0060; server/README.md
  "Purchased effect packs (pair 36)"). Owner 2026-10-23: the first table moved every 3x3 / 4x4 art by its size, which
  put the teleport 11 (pivot pulled 4, 10 px) and the holy 201 / 262 a tile down and right. `gen_fx_send_offsets.py
  --pair DAT SPR` compares the pivots with the art of a pair (pair 40: all 141 in-place effects agree). The pair is
  unchanged. Cutting the art so the pivot sits exactly on its tile (no half-tile residue) would need a new pair.
- **Appended**: 3247 effects (tile spells 346, fields 150, areas 547, cones 784, Mega 1012, impacts 195, circles 21,
  auras 84, traps 31, game feel 65, beams 12; directional effects as `_n` .. `_nw`) and 62 missiles, named in
  `server/data/lib/chaos_pack36_fx_ids.lua` and `server/data/spells/pack36_fx_catalog.csv`. Server use:
  server/README.md "Purchased effect packs (pair 36)"; client use: `game_levelwings`, `game_lootbeams`.
- **Not imported**: three effects wider than 9 tiles (`area_lodestone_wall`, `cone_gravemist_breath`,
  `cone_downburst`); the spell set as new things (the pair already holds it,
  `chaos_vfx.lua` 429 and on; its art is used only for in-place redraws); the colour variants beyond the one chosen per effect; the large set's projectiles beyond the missile budget (uint8,
  250 of 255).

```
python3 -I client/tools/sprites/gen_pack36_fx.py inventory --src PACK_DIR ...
python3 -I client/tools/sprites/gen_pack36_fx.py build --src PACK_DIR ...          # strips + specs; --check compares
python3 -I client/tools/sprites/import_fx_art.py --ours-dat pair35/Tibia.dat --ours-spr pair35/Tibia.spr --out-dir pair36 \
    --expect-first-effect 855 --expect-first-missile 189 --spec art_import/pack36_replace.csv --spec art_import/pack36_missiles.csv \
    --spec art_import/pack36_tile.csv ... --spec art_import/pack36_beam.csv \
    --lua-out server/data/lib/chaos_pack36_fx_ids.lua --catalog-out server/data/spells/pack36_fx_catalog.csv
python3 -I client/tools/sprites/check_pair.py pair36/Tibia.dat pair36/Tibia.spr --old pair35/Tibia.dat pair35/Tibia.spr \
    --allow-changed 'effect:<the replace ids>;missile:<the replace ids>' [--new-only]
python3 -I client/tools/sprites/gen_outfit_anchors.py pair36/Tibia.dat pair36/Tibia.spr
python3 -I client/tools/sprites/gen_info_lift.py pair36/Tibia.dat pair36/Tibia.spr
```
Input pair 35 (windows-assets 099b9a20, dat 58a5433bb0eabd77034e99de50274390).
Output **pair 36**: dat 9cca9b759ace5be6ab94d2b2ffb124a4 (11,067,604 bytes), spr 7f27e7d968cbde505a63fe9fd84c9c31
(1,516,209,062 bytes, 1,332,953 sprites: 399,538 appended), 38,640 items, 2,667 outfits, 4101 effects, 250 missiles.
The first build (dat 1551e3288a0fddd86680e0fbd3ff2d73, windows-assets ecdc13e1, built twice with identical md5s) had
word pop-ups on 173, 415-417 and 628; this one replaces them with animations and changes nothing else.
- `check_pair.py --old --allow-changed` (the 141 effect and 35 missile ids above): `--new-only` 0 errors, 92 warnings
  (size-large: cones and areas of 9 x 8 tiles); full check 0 errors, 216 warnings.
- `outfit_anchors.lua`, `info_lifts.lua`: only their dat md5 changes. `gen_theme_art.py recolour --check`,
  `gen_dungeon_banners.py --check` and `gen_sprite_images.py` pass on pair 36.
- Archive (the pair 35 recipe with `--mtime='2026-10-22 00:00:00Z'`, xz 5.4.5): 144,936,852 bytes, over GitHub's
  100 MB, so cut into `things/things-1098.tar.xz.part00` (sha256 496ec81615370085834e9f116883430dbc66da08abd7030c9b022473867974ff)
  and `.part01` (4b5b5d7628bfa22f6cdf62db6bcff59718280beee7ba24bd041c27465a8df7a7) with `split -b 95M -d -a 2`; CI
  and windows-package.yml read `cat things-1098.tar.xz.part* | xz -d | tar -xf -`. The single `things-1098.tar.xz`
  (pair 35) stays on the branch until main reads the parts. Pushed to windows-assets at ab96c012 (on ecdc13e1, the
  first build, on 099b9a20; the owner allowed new pairs without asking).
- A client on pair 35 or older: the appended ids log "invalid effect id", the replaced ids draw the old art, and the
  level-up and loot beams fall back (no level-up effect, the engine pillar). Ship pair 36 with the server.
- Previews: scratchpad only. Not run in a client.

## Owner outfits (pair 37: outfits 2668-2681, `tools/sprites/gen_pack37_looks.py`, `art_import/pack37_looks.csv`; built 2026-10-22, on windows-assets 1020d51c)
Owner, 2026-10-22: "Eu não coloquei uns outfits bem diferente no drive? Tipo de pizza e coisas assim?". **Source:** the
owner's Drive, object-builder exports (.obd, client 1098) in the folders "random" (17 files) and "obd+" (155 files);
supplied by the owner, source pack unnamed (docs/CREDITS.md "set37 outfits"). Treated as untrusted data: each file is
md5-checked against `LOOKS`, then parsed by the tool's own reader (LZMA with an output cap; nothing executed).
Import-only: the sheets (`art_import/pack37_looks/`) are never committed; `style_check.py` is not run on them.
- **Inventory.** "random": monsters and effects (2592-2600, 2641-2659, 2705-2717, 2726-2736, 852-855: no player
  layout), two plush bears (839-840), three crawling hands (841-843) and one full player set 2718-2725 (2x2, colour
  template, two addons, mounted frames, 16 idle and 8 walk frames). "obd+": idle-only looks (one frame per
  direction), mostly characters of other franchises; the one food costume of the Drive is a fry box (5113). No pizza
  outfit was found. Not opened: the folders "obd_all_in_one_folder" and "OBD_o/outfits".
- **Picked** (ids in this order): Starweaver 2668 / 2669, Crescent Oracle 2670 / 2671, Moonblade Mystic 2672 / 2673,
  Moonflame Mystic 2674 / 2675 (the set 2718-2725: even file = male, odd = female; one body, a different second
  addon each), Plush Bear 2676, Snow Plush Bear 2677 (1x1, idle 1 + walk 2), Frost / Grave / Rose Crawling Hand
  2678-2680 (1x1, idle 4 + walk 2), Fry Box Costume 2681 (2x2, one frame group of 1: it glides when walking; the
  fast-food mark on the box is painted over by `delogo`, 41 pixels in the east and south views).
- **Skipped:** the obd+ characters of other franchises and the arcade, robot and aura looks (idle only, not ours to
  ship), the monsters and effects of "random", the item obds of "comidas" (food items, not outfits).
- **Placement.** The files say displacement 8, 8. The moon set stands 9 px left and 10 px higher than look 128. Pair
  37 moved only x (0, 8), believing the outfit displacement also placed the rider on a mount, so the set floated
  about 10 px when standing and walking. Fixed in the sheets and the things file since 2026-10-22 ("Moon outfits on
  the ground" below); pair 37 and 38 still carry the floating art, pair 39 the fixed art. Bears, hands and the fry box stand where 128 stands.

```
python3 -I client/tools/sprites/gen_pack37_looks.py build --src OBD_DIR          # sheets + tables; --check compares
python3 -I client/tools/sprites/import_art_things.py --ours-dat pair36/Tibia.dat --ours-spr pair36/Tibia.spr --out-dir pair37 \
    --things client/tools/sprites/art_import/pack37_looks.csv --first-outfit 2668 --expect-items 38640
python3 -I client/tools/sprites/check_pair.py pair37/Tibia.dat pair37/Tibia.spr --old pair36/Tibia.dat pair36/Tibia.spr [--new-only]
python3 -I client/tools/sprites/gen_outfit_anchors.py pair37/Tibia.dat pair37/Tibia.spr
python3 -I client/tools/sprites/gen_info_lift.py pair37/Tibia.dat pair37/Tibia.spr
```
Input pair 36 (windows-assets ab96c012, dat 9cca9b759ace5be6ab94d2b2ffb124a4, spr 7f27e7d968cbde505a63fe9fd84c9c31).
Output **pair 37**: dat 774c80f15b38b1072e5e677f1611a08b (11,217,695 bytes), spr ba8022fe709d71fe543ee20d6d8858e4
(1,520,789,575 bytes, 1,338,774 sprites: 5,821 appended, 36 reused), 38,640 items, 2,681 outfits, 4101 effects, 250
missiles. The importer verified 14 outfits, 36,976 sprite slots pixel-identical to the sheets and every old thing
byte-identical. Built twice: identical md5s.
- `check_pair.py --old`: `--new-only` 0 errors, 0 warnings; full check 0 errors, 216 warnings (pair 36's).
- `outfit_anchors.lua` (1,988 things) and `info_lifts.lua` regenerated; `gen_theme_art.py recolour --check`,
  `gen_dungeon_banners.py --check`, `check_content.py --pair` and `gen_sprite_images.py` pass on pair 37 (the website
  draws 2668-2681: `website/tools/sprite_owners.csv` tier donor).
- Archive (the pair 35 recipe, `--mtime='2026-10-22 00:00:00Z'`, xz 5.4.5): 145,249,108 bytes, sha256
  cfdf4b4e7ce8395434f5ad6766aed491dba3bf3aad27a671f633bce1afc6ecbc, packed twice with the same sha256; parts
  `things-1098.tar.xz.part00` (f6cf3d23eaab44631a3ff301c3f3824393694dfac9e192a3b8a6f7aa1b153fd3) and `.part01`
  (6c8bc288e7a42041782bc0e64b693373bb807250d9b00428120f175c3b6c27d8). Pushed to windows-assets at 1020d51c (on
  ab96c012; the owner allowed new pairs without asking).
- A client on pair 36 or older: the server's pair 37 outfits draw nothing. Ship pair 37 with the server.
- Server side: server/README.md "Owner outfits (pair 37)". Preview: scratchpad only. Not run in a client.

## Orb looks (pair 38: item 38641, `tools/sprites/gen_orb_items_art.py`, `art_import/orb_items.*`; built 2026-10-22, on windows-assets ee8e82e)
Owner request 2026-10-22 with a screenshot of the Orbs Pouch: "Coloque arte de orb de verdade. Não use as runas para
isso. Deixe os sprites de runa só para as runas." The Orb of Sockets showed a red oval stone, in the pouch and its
tooltip.
- **Cause.** The Orb of Sockets (server 24692) is an unused stackable rune stone of the base data, client 22036, whose
  only sprite (1317) is the great fireball rune's (client 3191): the same picture. Checked for every orb of the loot
  list, the crafting bench and orbs v2 (24688, 24691, 24697, 29851-29859, 32251-32260, 24692) against the 134 rune
  things of pair 37 (base items.xml names with "rune"): sprite ids and the phash of the 32 px render. Only 24692
  shares a sprite with a rune (distance 0); every other orb is 180 or more of 256 bits from its nearest rune.
- **New look.** `gen_orb_items_art.py build` draws the orb per pixel in code (no source image, no pack pixels): blue
  glass lit from the top left with a cyan glow inside and a specular glint, a gold band leaning toward the viewer
  holding three sockets lit violet, cyan and green, a one-pixel near-black outline; snapped to `azurevigil`. Passes
  `style_check.py check`; `build` refuses a failing tile, `build --check` (CI, fx venv) compares atlas and things file.
- Things file `art_import/orb_items.csv`: client 38641 `orb of sockets`, flags `copy:22036` (stackable, multi-use,
  light as before), one phase, mode replace with server id 24692. The server points the node at it
  (`install_gems.py`, `chaos_gems_config.lua` `socketOrb.look` / `useLook`; server/README.md "Gems and sockets").
  22036 and the rune 3191 are unchanged.

```
python3 -I client/tools/sprites/gen_orb_items_art.py build [--preview DIR --dat pair37/Tibia.dat --spr pair37/Tibia.spr]
python3 -I client/tools/sprites/import_art_things.py --ours-dat pair37/Tibia.dat --ours-spr pair37/Tibia.spr --out-dir pair38 \
    --things client/tools/sprites/art_import/orb_items.csv --first-item 38641 --expect-items 38640
python3 -I client/tools/sprites/check_pair.py pair38/Tibia.dat pair38/Tibia.spr --old pair37/Tibia.dat pair37/Tibia.spr [--new-only]
```
Input pair 37 (windows-assets 1020d51c, dat 774c80f15b38b1072e5e677f1611a08b, spr ba8022fe709d71fe543ee20d6d8858e4).
Output **pair 38**: dat fb41c87298d95d9b200352b100af26b4 (11,217,716 bytes), spr ee6c5173682531a2b93d17ff35eea7a4
(1,520,792,224 bytes, 1,338,775 sprites: 1 appended), 38,641 items, 2,681 outfits, 4101 effects, 250 missiles. The
importer verified the sprite slot pixel-identical to the atlas and every old thing byte-identical. Built once (the
disk had no room for a second 1.5 GB copy).
- `check_pair.py --old`: `--new-only` 0 errors, 0 warnings; full check 0 errors, 216 warnings (pair 37's).
  `check_content.py --pair` passes on pair 38.
- `outfit_anchors.lua` and `info_lifts.lua` regenerated on pair 38 after it went to windows-assets (ee8e82e): no new
  creature, only their dat md5 changed.
- Archive (the pair 37 recipe, `--mtime='2026-10-22 00:00:00Z'`, xz 5.4.5, `split -b 95M -d -a 2`): 145,258,588
  bytes, sha256 e16ca9668b6173fcff499ccefd4b72ffa1015bf8895bd27e9675ae66753ccb35; parts `things-1098.tar.xz.part00`
  (057e7ae366554fcf527a1451798c01818d6e41d4b7cc3402b567b9fa1cf51622) and `.part01`
  (648fee2eb4c657d218e5697231b43d94ab504fbc05b1c3d7d60c5ccbf44be986); unpacks to the md5s above. Pushed to
  windows-assets at ee8e82eb (on 1020d51c).
- A client on pair 37 or older draws nothing for the Orb of Sockets once the server has the new look: ship pair 38
  before the server step, or set `useLook = false` and run `install_gems.py` again.
- Previews (old look and new, the orbs of the pouch in a row): scratchpad only. Not run in a client.

## Moon outfits on the ground (next pair after 38: outfits 2668-2675 in place, `tools/sprites/gen_pack37_looks.py` STAND_SHIFT, `art_import/pack37_moon_fix.csv`; pair 39, built 2026-10-22, on windows-assets 1102087c)
Reported 2026-10-22 by the agent that built pair 37: "The moon set floats about 10 px when standing still."
- **Measured** on pair 37 (lowest opaque row of the body, base layer and addon, screen rows from the tile top,
  displacement applied, every frame): look 128 idle 23 in all four directions (walk 20..23). The moon set before:
  idle N 14, E 14..15, S 13, W 13..15, walk 12..16. Idle and walk float alike (8-10 px), mounted frames are fine.
- **Cause.** The art is drawn about 10 px higher than stock for the standing frames, and 9 px left; the mounted
  frames are drawn at stock seat height. Pair 37 kept dy 8 because one displacement seemed to serve both states,
  but on a mount the client draws the rider by the mount's displacement (outfit.cpp adds the outfit's own back
  before the rider is drawn), so the outfit displacement places only the standing look. A negative displacement
  is not an option: it switches the client to its negative-offset paths (tile order, light, the rider on the mount).
- **Fix** at the import: displacement 0, 0 for the eight looks (8 px down and right on screen) and `STAND_SHIFT`:
  every standing cell (pattern z 0: both frame groups, every frame, addon and layer) of a direction moves down by
  whole pixels until the body's lowest idle row lands on `STOCK_FEET` 23, clamped to the free room of the 64 px cell
  (`shift_rows` refuses to cut art). Shifts N/E/S/W: Starweaver, Crescent Oracle, Moonflame Mystic male 1/0/2/0,
  female 1/1/2/2; Moonblade Mystic male 1/0/0/0, female 1/1/1/2 (its blade addon reaches the cell bottom facing south).
  Mounted cells are untouched. After (rendered from the new sheets through the importer's own reader): idle 23 in
  every direction, walk 21..25, except Moonblade Mystic facing south, idle 21 (male) and 22 (female). x stays as in
  pair 37 (dx 0 there too): the feet 1 px left of 128 facing south, 2-7 px in the other directions, as drawn.
- `build` writes `art_import/pack37_moon_fix.csv`: the eight rows of `pack37_looks.csv` with mode=replace and look=id
  (the import rewrites the looks in place; ids, outfits.xml and the store stay). `build --check` compares it with
  `pack37_looks.csv`; `gen_pack37_looks_test.py` covers the shift, the clamp, the refusal and the fix rows.
  Pair 37's own recipe (`pack37_looks.csv` on pair 36) now gives the fixed art too, so it no longer rebuilds pair
  37's md5s.

```
python3 -I client/tools/sprites/gen_pack37_looks.py build --src OBD_DIR          # the sheets (git-ignored)
python3 -I client/tools/sprites/import_art_things.py --ours-dat pair38/Tibia.dat --ours-spr pair38/Tibia.spr --out-dir pair39 \
    --things client/tools/sprites/art_import/pack37_moon_fix.csv --expect-items 38641
python3 -I client/tools/sprites/check_pair.py pair39/Tibia.dat pair39/Tibia.spr --old pair38/Tibia.dat pair38/Tibia.spr \
    --allow-changed 'outfit:2668,2669,2670,2671,2672,2673,2674,2675'
python3 -I client/tools/sprites/gen_outfit_anchors.py pair39/Tibia.dat pair39/Tibia.spr
python3 -I client/tools/sprites/gen_info_lift.py pair39/Tibia.dat pair39/Tibia.spr
```
Input pair 38 (windows-assets ee8e82eb, dat fb41c87298d95d9b200352b100af26b4, spr ee6c5173682531a2b93d17ff35eea7a4;
the live pair when built). `gen_pack37_looks.py build` on the owner's .obd folder rewrote the committed tables
unchanged.
Output **pair 39**: dat 9d0c474ef9202a93117e910d465c7efc (11,217,716 bytes), spr 968b604ee9b6b6f9666549da880ce1d2
(1,522,489,704 bytes, 1,341,043 sprites: 2,268 appended, 3,738 reused), 38,641 items, 2,681 outfits (8 replaced in
place), 4101 effects, 250 missiles. The importer verified 36,864 sprite slots pixel-identical to the sheets and every
other old thing byte-identical. Built twice: identical md5s.
- `check_pair.py --old --allow-changed 'outfit:2668,...,2675'`: `--new-only` 0 errors, 0 warnings; full check 0
  errors, 216 warnings (pair 38's).
- `outfit_anchors.lua` (the dat md5 and rows 2668-2675: ground row 9-11 -> 18-21) and `info_lifts.lua` (the dat md5,
  the female looks' lift 14 -> 12) regenerated. `gen_theme_art.py recolour --check`, `gen_dungeon_banners.py
  --check`, `check_content.py --pair` and `gen_sprite_images.py` pass on pair 39.
- Measured on pair 39 (lowest opaque row of the body, layer 0 and addon pattern 0, every idle frame, screen rows from
  the tile top, displacement applied): look 128 23 in all four directions; every moon look 23 in all four, except
  Moonblade Mystic facing south, 21 (male 2672) and 22 (female 2673). Pair 38: 13-15. With both addons the lowest row
  is the robe or weapon tip, 23-30.
- Archive (the pair 37 recipe, `--mtime='2026-10-22 00:00:00Z'`, xz 5.4.5; the recipe rebuilds pair 38's sha256):
  145,285,152 bytes, sha256 a55e9ad74b80b0e3344c36c14c89660a4b7a475ff257a8c47cd101fbb83dd9e3; parts
  `things-1098.tar.xz.part00` (4a006a862561a71cfbaec97780dd797919c1548f703cc9189a9dbdc2b50a5b12) and `.part01`
  (0be5499cc4b17c9e0b495b31e30561a29164019d5df96b06243a62fcc19d9709); unpacks to the md5s above. Pushed to
  windows-assets at 1102087c (on ee8e82eb; the owner allowed new pairs without asking). No server change.
- A client on pair 38 or older keeps drawing the set floating. Renders: scratchpad only. Not run in a client.

## Creature palette pass (pair 40: 48 creature looks in place, `tools/sprites/gen_creature_palette.py`, `monster_looks/creature_palette.csv`; built 2026-10-23)
Owner approved 2026-10-23: variant A of the style study of 2026-10-22 (one palette per look and a despeckle; the
study's reference sprites were for comparison only, none of their pixels is used). Prototype: monster 2125 from 646
colours and speckle 0.57 to 24 and 0.16. Not approved: variant B's tinted outline and rim light (the outline rule is open).
- **Pass** (docs/SPRITE_STYLE.md "Palette pass on donor creatures"): one palette per look for every frame group,
  phase, direction, addon, mount and art layer, 32 colours, k-means in CIE Lab with a fixed seed, each entry a real
  colour (the weighted medoid of its cluster). Near-black, neutral greys, accents (vivid hue families under 6% of the
  pixels, and vivid colours used in small spots: eyes, runes, sparks) and the rest get separate entries and never mix.
  Then two despeckle passes on body pixels (not the rim, not accents, not across luma 24). A look of 32 colours or
  fewer keeps its palette (despeckle only). Alpha is untouched; a colour mask layer and the base pixels under it are
  kept (none of the targets has one). Near-black pixels stay near-black and no other pixel becomes near-black, so the outline
  keeps its shape.
- **Accent guard:** a look is left as it was when more than 10% of its vivid pixels or of its spot pixels move more
  than 20 in Lab, or the vivid pixels move more than 10 on average. Checked by eye on before / after sheets as well.
- **Targets:** donor looks 2100-2139 (things_custom11, 13, 14), the theme recolours 2188-2193 (`theme_recolour.py`)
  and the rift rank variants 2200-2207 (`rift_variants.py`). Not the owner's art, import-only packs or player looks.
- **Changed (48):** 2100-2113, 2115-2129, 2131-2135, 2188-2193, 2200-2207. Colours of the look before -> after, e.g.
  2106 8,255 -> 32, 2111 5,479 -> 32, 2128 13,168 -> 32, 2125 932 -> 32; speckle (body pixels no neighbour shares)
  2106 0.88 -> 0.15, 2124 0.77 -> 0.07, 2125 0.54 -> 0.17, 2128 0.89 -> 0.08; the most colours in one 32 px cell
  2128 905 -> 28, 2106 775 -> 29. Every look's numbers: `monster_looks/creature_palette.csv`.
- **Left as they were (6):** 2114 Forsaken Sanctum elite (692 of 3,872 vivid pixels would move: the green glyph
  glow), 2130 Vhoss the Hexmaw (37 colours, 484 of 2,872 vivid pixels would move: its blue spots), the auras
  2136-2139 (soft glow effects, 70-100% semi-transparent, not creature pixel art).
- **Theme recolours** are remade from their passed source, not passed on their own: the build first checks that the
  recolour of pair 39's 2108 / 2104 is exactly pair 39's 2188-2193, then recolours the passed source.
  `gen_theme_art.py recolour` on pair 40 rewrote the six `art_import/theme_recolour/*.png` sheets; they equal pair 40's
  2188-2193 cell for cell (300 cells). The rift variant sheets in `art_import/rift_variants/` stay pair 24's import
  source; pair 40 holds their passed form.

```
python3 -I client/tools/sprites/gen_creature_palette.py build --dat pair39/Tibia.dat --spr pair39/Tibia.spr \
    --expect-dat-md5 9d0c474ef9202a93117e910d465c7efc --out-dir pair40 [--sheets DIR]
python3 -I client/tools/sprites/gen_creature_palette.py build --dat pair39/Tibia.dat --spr pair39/Tibia.spr --check
python3 -I client/tools/sprites/check_pair.py pair40/Tibia.dat pair40/Tibia.spr --old pair39/Tibia.dat pair39/Tibia.spr \
    --allow-changed 'outfit:2100-2113,2115-2129,2131-2135,2188-2193,2200-2207'   # as a comma list of ids
python3 -I client/tools/sprites/gen_theme_art.py recolour --dat pair40/Tibia.dat --spr pair40/Tibia.spr
python3 -I client/tools/sprites/gen_outfit_anchors.py pair40/Tibia.dat pair40/Tibia.spr
python3 -I client/tools/sprites/gen_info_lift.py pair40/Tibia.dat pair40/Tibia.spr
```
Input pair 39 (windows-assets 1102087c, dat 9d0c474ef9202a93117e910d465c7efc, spr 968b604ee9b6b6f9666549da880ce1d2).
Output **pair 40**: dat 5f9edac3d6424155a96c95bef6691d18 (11,217,716 bytes, same size: only sprite ids change), spr
2b157338e1664c58d3c07b8899ed5938 (1,536,990,834 bytes, 1,349,517 sprites: 8,474 appended, 1 reused; 10,920 sprite
slots rewritten), 38,641 items, 2,681 outfits, 4101 effects, 250 missiles. The build verified 1,984 frames of the 48
looks decode to the pass, every other thing byte-identical and 2,999 sampled old sprites unchanged. Built twice:
identical md5s and report.
- `check_pair.py --old --allow-changed` (the 48 looks): `--new-only` 0 errors, 0 warnings; full check 0 errors, 216
  warnings (pair 39's). With only one look allowed it reports the other 47 (47 errors): the guard sees every change.
- `outfit_anchors.lua` and `info_lifts.lua`: only the dat md5 changes (alpha untouched, so no anchor or lift moves).
  `gen_theme_art.py recolour --check`, `gen_dungeon_banners.py --check`, `check_content.py --pair` and
  `gen_sprite_images.py --publish own,donor` pass on pair 40.
- Archive (the pair 37 recipe, `--mtime='2026-10-22 00:00:00Z'`, xz 5.4.5, `split -b 95M -d -a 2`; it rebuilds pair 39's sha256 a55e9ad7...):
  146,658,260 bytes, sha256 0a08dd219f0df19256b5dbd87e377bf532c8a89f1b9aedba99ed18d0402dd4d7; parts `things-1098.tar.xz.part00` (99,614,720 bytes, sha256 1c69150f6e94d1ce1593cbe5965ecef240520c9a167180e43e6f6978dc930f76) and `.part01`
  (47,043,540 bytes, sha256 a6f42a6b2c4c2c2de6a99c6b2f69a04a4c2e87afe7ba2b899bd038a1a84bf255). Pushed to windows-assets at e662cd24 (on 1102087c; the owner allowed new pairs without asking). No
  server change.
- A client on pair 39 or older keeps the old art; nothing breaks. Before / after sheets: scratchpad only. Not run in a
  client.

## Projectile pack, native 32 px (pair 41: 50 missiles redrawn in place, 3 appended: 251-253; `tools/sprites/gen_pack41_missiles.py`, `art_import/pack41_missiles.csv`; built 2026-10-25, on windows-assets 7f1b7a08)
Owner allowed new pairs without asking. Pair 36 built its projectile missiles from the 64 px renders of the purchased
projectile pack, halved. The pack also ships hand-tuned renders made at 32 px (frames of 64 x 64, pivot at the centre,
8 frames at 12 fps, rows E SE S SW W NW N NE); pair 41 redraws the same ids from those, nothing halved. **Licence: the
art may reach players only inside the pair** (docs/CREDITS.md "Projectiles"). No strip, frame or sheet is committed:
`art_import/pack41_fx/` is git-ignored; the repo holds the tool, `pack41_missiles.csv` (the spec),
`pack41_fx_sources.csv`, `pack41_fx.sums` and the Lua / catalog tables.
- **Redrawn (50 ids, 49 variants; ice_lance/frost twice):** stock and procedural 4 5 11 12 13 15 25 28 29 30 31 32 33
  36 37 38 39 41 56 57 60 84 85 86 104 116-125, and pair 36's appended 189-203. Same pattern layout as pair 36: the
  rows map to the client's 3 x 3 cells as the engine's `Missile::draw` reads them (NW 0,0; N 1,0; NE 2,0; W 0,1; E 2,1;
  SW 0,2; S 1,2; SE 2,2; the centre cell repeats S); the pivot lands on (13, 13) of the tile; alpha 0 / 255 with the 4x4
  dither (the cut pairs 27 and 29 used on the same native renders); 8 frames, 83 ms. The stock ids keep send offset
  0, 0 and the art is moved up and left as a whole when it reaches past the bottom-right tile (pair 36's rule, at most
  2 x 2 tiles; 26 ids moved 1 to 9 px, none cut); ids 189-203 keep their `dx`, `dy` of `chaos_pack36_fx_ids.lua`. Row order checked on the
  art (every variant's mass trails opposite to its row's direction) and by the synthetic test.
- **Does the art fit the centre 32 px?** `gen_pack41_missiles.py measure`: of 76 variants only 4 lie wholly inside the
  centre 32 x 32 of their frame (energy_disc x2, frost_shard x2); by pixels 0-11 % lies outside it (arrows, spears and
  the piercing arrow 6-11 %, the orbs 0-1 %). So the whole 64 x 64 frame is placed (nothing is cropped) and the tile
  canvas follows the art: 1x1 (ids 13, 37), 2x2, 3x3 as before; id 37 shrinks from 1x2 to 1x1.
- **Not redrawn:** the 12 projectile missiles of pairs 27 and 29 (ids 154-165) were already cut from these native
  32 px renders: rebuilt from the pack they match `pack27_fx.sums` / `pack29_fx.sums` byte for byte, so they stay.
  The 47 missiles of the other effect set (204-250) are native already.
- **Appended:** 251 `proj_arrow_fire`, 252 `proj_arrow_frost`, 253 `proj_piercing_arrow_holy` (3x3, send offset 1, 1),
  `server/data/lib/chaos_pack41_fx_ids.lua`, `server/data/spells/pack41_fx_catalog.csv`. No spell is wired. 254 is
  the server's `CONST_ANI_WEAPONTYPE` (a combat's "use the weapon's missile", never sent) and `check_pair.py` warns above
  254, so 254 and 255 stay free.
- **Proposed swaps** (remaining 19 unused variants; made in pair 42, next section, with ids 62-76 replaced where in use). In use, so only on the owner's word: id 1 spear <-
  spear/steel; 22 sniper arrow <- piercing_arrow/steel; 34 flaming arrow <- arrow/fire and 35 shiver arrow <-
  arrow/frost (251 and 252 are the same art, appended); 7 burst arrow <- split_arrow/fire; 6 poison arrow <-
  split_arrow/poison. Not sent by anything in the repo (ids 62-76 are stock ids with no engine name and no script
  or monster of the repo sending them; base data is not in the repo, so check the installed server first): 62
  ball_lightning/thunder, 63 blood_spike/necrotic, 64 boulder/magma, 65 flame_lance/spirit, 66 poison_dart/necrotic,
  67 razor_leaf/sakura, 68 shadow_bolt/blood, 69 soul_skull/spirit, 70 spirit_arrow/blood, 71 spirit_arrow/gold, 72
  spirit_wisp/arcane, 73 venom_glob/necrotic, 74 void_orb/abyss, 75 water_bolt/abyss, 76 wind_blade/storm.

```
python3 -I client/tools/sprites/gen_pack41_missiles.py build --src PACK_DIR      # strips + spec; --check compares
python3 -I client/tools/sprites/gen_pack41_missiles.py build --check             # CI, no pack
python3 -I client/tools/sprites/gen_pack41_missiles.py measure --src PACK_DIR
python3 -I client/tools/sprites/import_fx_art.py --ours-dat pair40/Tibia.dat --ours-spr pair40/Tibia.spr --out-dir pair41 \
    --expect-first-effect 4102 --expect-first-missile 251 --spec client/tools/sprites/art_import/pack41_missiles.csv \
    --lua-out server/data/lib/chaos_pack41_fx_ids.lua --catalog-out server/data/spells/pack41_fx_catalog.csv
python3 -I client/tools/sprites/check_pair.py pair41/Tibia.dat pair41/Tibia.spr --old pair40/Tibia.dat pair40/Tibia.spr \
    --allow-changed 'missile:4,5,11,12,13,15,25,28-33,36-39,41,56,57,60,84-86,104,116-125,189-203' [--new-only]
python3 -I client/tools/sprites/gen_outfit_anchors.py pair41/Tibia.dat pair41/Tibia.spr
python3 -I client/tools/sprites/gen_info_lift.py pair41/Tibia.dat pair41/Tibia.spr
```
Input pair 40 (dat 5f9edac3d6424155a96c95bef6691d18, spr 2b157338e1664c58d3c07b8899ed5938).
Output **pair 41**: dat 6a8e1a8db5144459d2544a0e2070fb3b (11,225,440 bytes), spr 78c5fec6822a288c780f53a893d94de4
(1,539,762,967 bytes, 1,355,354 sprites: 5,837 appended), 38,641 items, 2,681 outfits, 4101 effects, 253 missiles.
- `check_pair.py --old --allow-changed` (the 50 ids): `--new-only` 0 errors, 0 warnings; full check 0 errors, 216
  warnings (pair 40's). `gen_fx_send_offsets.py --check` and `--pair` agree (no effect changed);
  `outfit_anchors.lua`, `info_lifts.lua`: only the dat md5 changes. `gen_theme_art.py recolour --check`,
  `gen_dungeon_banners.py --check` and `gen_sprite_images.py` pass on pair 41; the importer verified 3,816 frames
  pixel-identical and every other thing byte-identical.
- Archive (the pair 37 recipe, `--mtime='2026-10-22 00:00:00Z'`, xz 5.4.5, `split -b 95M -d -a 2`): 146,911,036 bytes,
  sha256 de164c17618445c3bf6caf6ae24650ca79eee2ecadefb08bfc10283af0c85624; parts `things-1098.tar.xz.part00` (99,614,720
  bytes, sha256 7b666eeb48ed01947eee5604e01cd4710582af65ae8d3e29b9202111ca9f64cc) and `.part01` (47,296,316 bytes,
  sha256 cdcb8241462dd6261436adebc9cb7b9f720bb904b2ad11149868b3db4a61d74b). Pushed to windows-assets at 7f1b7a08 (on e662cd24; the owner allowed new pairs without asking).
- A client on pair 40 or older keeps the halved art; ids 251-253 are sent by nothing. Previews: scratchpad only. Not
  run in a client.

## Projectile pack, remaining swaps (pair 42: 21 missiles redrawn in place, 15 of them named; `tools/sprites/gen_pack41_missiles.py` second set, `art_import/pack42_missiles.csv`; built 2026-10-25, on windows-assets b6c7709e)
Owner approved the swaps pair 41 proposed. Same tool, a second spec (`pack42_missiles.csv`, `pack42_fx_sources.csv`,
`pack42_fx.sums`; the strips go to the git-ignored `art_import/pack41_fx/`, nothing of the pack is committed), same
placement rules as pair 41: the whole 64 x 64 frame, pivot on (13, 13), alpha 0 / 255 with the 4x4 dither, 8 frames at
83 ms, art past the bottom-right tile moved up and left as a whole, nothing cut (the build asserts it).
- **Six in-use stock ids, unnamed** (the engine and the base data send them by name; send offset 0, 0, 2 x 2): 1 spear
  <- spear/steel, 22 sniper arrow <- piercing_arrow/steel, 34 flaming arrow <- arrow/fire, 35 shiver arrow <-
  arrow/frost, 7 burst arrow <- split_arrow/fire, 6 poison arrow <- split_arrow/poison. Art moved 3 to 10 px on 1 22 34 35 6.
  (251 and 252 keep the same fire and frost arrow art.)
- **Fifteen named swaps** (`ChaosVfxMissile.proj_<effect>_<variant>` in `server/data/lib/chaos_pack41_fx_ids.lua`, the
  catalog `server/data/spells/pack41_fx_catalog.csv`; send offset from the art, at most 3 x 3; no spell is wired):
  ball_lightning/thunder 100, blood_spike/necrotic 108, boulder/magma 111, flame_lance/spirit 115, poison_dart/necrotic
  137, razor_leaf/sakura 138, shadow_bolt/blood 139, soul_skull/spirit 140, spirit_arrow/blood 141, spirit_arrow/gold
  142, spirit_wisp/arcane 143, venom_glob/necrotic 144, void_orb/abyss 145, water_bolt/abyss 75, wind_blade/storm 146.
- **Ids 62-76 were checked before use, and 14 of 15 are taken.** The owner asked for 62-76 in the order above and
  "if an id is in use, skip it and use the next unused one".
  - Base server (the windows-assets `server/base-server.tar.xz`): the engine names none of 62-76 (`ShootType_t` in
    `const.h`, `shootTypeNames` in `tools.cpp`: names reach 61, then 85 89 92-96). Its monster files send them by number
    (`shootEffect = N`): 62 x1, 63 x2, 64 x4, 65 x4, 66 x2, 67 x4, 68 x5, 69 x6, 70 x9, 71 x15, 72 x1, 73 x1, 74 x1, 76 x1
    (expedition monsters). Only **75** is unused. No spell, script, weapon or item sends 62-76.
  - This repo: no Lua send, `ChaosVfxMissile` / `ChaosFxMissile` name, monster file or `CONST_ANI_*` number uses 62-76.
  - Pair 41 held the base's own stock art there (1 x 1, one phase), not empty slots.
  - Skipped (in use): 62 63 64 65 66 67 68 69 70 71 72 73 74 76. They took, in order, the next unused ids: 100 108 111 115
    (stock art no base file and no repo table sends) and 137-146 (ten missiles of the pair that held one 1 x 1 pattern
    instead of the 3 x 3 directions: `check_pair.py` warned about them, 216 warnings -> 206). Not free, so not used:
    77-99, 101-107, 109, 110, 112-114 (the base data sends them by number), 116-136 and 153-253 (named in our Lua
    tables). The census is only as good as the grep: a base script that builds an id at run time would not show.
```
python3 -I client/tools/sprites/gen_pack41_missiles.py build --src PACK_DIR      # both sets; --check compares
python3 -I client/tools/sprites/import_fx_art.py --ours-dat pair41/Tibia.dat --ours-spr pair41/Tibia.spr --out-dir pair42 \
    --expect-first-effect 4102 --expect-first-missile 254 --spec client/tools/sprites/art_import/pack42_missiles.csv \
    --lua-out server/data/lib/chaos_pack41_fx_ids.lua --catalog-out server/data/spells/pack41_fx_catalog.csv --merge
python3 -I client/tools/sprites/check_pair.py pair42/Tibia.dat pair42/Tibia.spr --old pair41/Tibia.dat pair41/Tibia.spr \
    --allow-changed 'missile:1,6,7,22,34,35,75,100,108,111,115,137-146' [--new-only]
python3 -I client/tools/sprites/gen_outfit_anchors.py pair42/Tibia.dat pair42/Tibia.spr
python3 -I client/tools/sprites/gen_info_lift.py pair42/Tibia.dat pair42/Tibia.spr
```
Input pair 41 (windows-assets 7f1b7a08, dat 6a8e1a8db5144459d2544a0e2070fb3b, spr 78c5fec6822a288c780f53a893d94de4).
Output **pair 42**: dat 6a7cba691029a95689e23426de75b225 (11,260,478 bytes), spr 358da3065f83d2610e43c7a74f045472
(1,541,015,197 bytes, 1,357,828 sprites: 2,474 appended), 38,641 items, 2,681 outfits, 4101 effects, 253 missiles
(no new id: 251-253 are as in pair 41).
- `check_pair.py --old --allow-changed` (the 21 ids): `--new-only` 0 errors, 0 warnings; full check 0 errors, 206
  warnings (pair 41's 216 without the ten single-pattern missiles 137-146). `gen_fx_send_offsets.py --check` and
  `--pair` agree; `outfit_anchors.lua`, `info_lifts.lua`: only the dat md5 changes. `gen_theme_art.py recolour
  --check`, `gen_dungeon_banners.py --check` and `gen_sprite_images.py` pass on pair 42; the importer verified 1,512
  frames pixel-identical and every other thing byte-identical.
- Archive (the pair 41 recipe: `tar --owner=0 --group=0 --numeric-owner --mtime='2026-10-22 00:00:00Z' --format=gnu`, `xz -9 -T0`
  (xz 5.4.5), `split -b 95M -d -a 2`): 147,029,728 bytes, sha256
  9bccacb23bd3bed955eb40a6b979eb9e2152f07fd6556f7dc9b740da668b810d; parts `things-1098.tar.xz.part00` (99,614,720 bytes,
  sha256 d797cee0ad0001bf2ff84367742b6a134ad35237090c52d17d029c0fb813a694) and `.part01` (47,415,008 bytes, sha256
  bc839549983772db0f358aca3bffc8197b1881bff2668e5525e3778ac64f2225); stream-extracted from the parts, the md5s above
  match. On windows-assets b6c7709e.
- A client on pair 41 or older keeps the old art on these ids (the spear and arrows redraw only with pair 42); the 15
  names are sent by nothing. Ship pair 42 with the server. Previews: scratchpad only. Not run in a client.

## Cursed Chest looks (pair 43: items 38642-38644, `tools/sprites/gen_cursed_chest_art.py`, `art_import/cursed_chest.*`; built 2026-10-25, on windows-assets f7a4e023)
Pair 53 (2026-10-27) redraws 38642 in place as one 32 x 32 still (K3) and a chest rolls only that look: see "Pair 53". 38643 / 38644 stay in the pair for chests already on a map.
Owner request 2026-10-25: the Cursed Chest borrowed the Sealed Coffer's chest (server 12664, client 4073); it gets art of
its own. The owner picked three PixelLab results (64 x 64 RGBA, alpha 0 / 255): A (lava cracks and chains, the main
look), B (purple flame, faces on the lid), C (open maw with iron teeth). Each chest that spawns wears one at random.
Later the same day the owner approved an idle animation (PixelLab animate-with-text, 64 x 64 frames): **A** 5 phases (its
original sprite is frame 0, the loop), **B** a still (1 phase), **C** 8 phases as a ping-pong, frames 0 1 2 3 4 3 2 1
(a mimic chewing).
- **Pixels.** PixelLab's, owner approved: not repainted, snapped or recoloured. Credit: docs/CREDITS.md "Tools"
  (PixelLab; `art_import/cursed_chest_sources.csv`). The raw folder is git-ignored; `build --src DIR` copies the three
  files to `art_import/cursed_chest/` (`cursed_chest_a_f0..4.png`, `cursed_chest_b.png`, `cursed_chest_c_f0..4.png`:
  the 11 committed sources, about 70 KB), so CI and later rebuilds need no PixelLab folder. The colour under fully
  transparent pixels is cleared (PixelLab leaves noise there; nothing visible changes).
- **Style.** The art is lava, purple and blood red, none of the seven theme palettes (`style_check.py` against each
  theme: only the palette rule fails, mean distance 7-17 against the allowed 4.5). Snapping is not the standard step
  for PixelLab art here (the themed icons take a per-item palette, not a theme), so nothing was snapped. `build` runs
  the check on each 64 x 64 canvas (cell 64) against the canvas's own colours: outline, light, noise, colour count (58-60),
  alpha and scale all pass, and `build` refuses otherwise, except the colour count: frame C 3 has 69 colours (limit 68),
  reported as a warning, since the frames are owner approved and cannot be repainted. Checked as four 32 px cells, look B fails the outline rule
  (the purple flame has no dark rim); as the one 2 x 2 item it is, it passes.
- **Things.** `art_import/cursed_chest.csv`: client 38642 / 38643 / 38644 `cursed chest`, 2 x 2, 5 / 1 / 8 phases at 250 / - / 200 ms (the dat takes a
  duration per item: min = max = ms), flags `copy:4073` (container, notwalkable, notmoveable, light 3 / 29, elevation 8, usable), mode new. The importer cuts each
  canvas into the four 32 px tiles of a 2 x 2 item (`tiles()` in the tool is the same cut, tested). The atlas holds one cell per
  phase (896 x 64, 14 cells); C's repeated frames are the same pixels, so the importer stores them once: 44 sprites
  appended (A 20, B 4, C 20), not 56.
- **Server.** `server/tools/install_cursed_chest.py` (step `cursedchest`): items.otb copies of node 12664 with server ids
  32281-32283 and these client ids (A and C also carry FLAG_ANIMATION, so the server sends the phase byte), items.xml entries; `cursedchest_config.lua` `chest.itemIds`, fallback 12664
  (server/README.md "Cursed Chest").

```
python3 -I client/tools/sprites/gen_cursed_chest_art.py build [--src PIXELLAB_DIR] [--preview DIR --dat pair43/Tibia.dat --spr pair43/Tibia.spr]
python3 -I client/tools/sprites/import_art_things.py --ours-dat pair42/Tibia.dat --ours-spr pair42/Tibia.spr --out-dir pair43 \
    --things client/tools/sprites/art_import/cursed_chest.csv --first-item 38642 --expect-items 38641
python3 -I client/tools/sprites/check_pair.py pair43/Tibia.dat pair43/Tibia.spr --old pair42/Tibia.dat pair42/Tibia.spr [--new-only]
python3 -I client/tools/sprites/gen_outfit_anchors.py pair43/Tibia.dat pair43/Tibia.spr
python3 -I client/tools/sprites/gen_info_lift.py pair43/Tibia.dat pair43/Tibia.spr
```
Input pair 42 (windows-assets b6c7709e, dat 6a7cba691029a95689e23426de75b225, spr 358da3065f83d2610e43c7a74f045472).
Output **pair 43**: dat 2cb2321ef0dffd58bc4d52411bca5a89 (11,260,881 bytes), spr 078b92ec8672792748999425de5e0743
(1,541,120,045 bytes, 1,357,872 sprites: 44 appended), 38,644 items (3 appended), 2,681 outfits, 4101 effects, 253
missiles. The importer verified the 56 sprite slots pixel-identical to the atlas and every old thing byte-identical.
Built once.
- `check_pair.py --old`: `--new-only` 0 errors, 0 warnings; full check 0 errors, 206 warnings (pair 42's).
  `outfit_anchors.lua` and `info_lifts.lua`: only the dat md5 changes.
- Archive (the pair 41 recipe: `tar --owner=0 --group=0 --numeric-owner --mtime='2026-10-22 00:00:00Z' --format=gnu`,
  `xz -9 -T0` (xz 5.4.5), `split -b 95M -d -a 2`): 147,073,436 bytes, sha256
  d435d1f05622d77456ff716745bbb59a2eb17ed69002b668f9d3673668d0f2e6; parts `things-1098.tar.xz.part00` (99,614,720
  bytes, sha256 6e61b55becbe49a5567f162ee2a94374a3bf3fe0b370360e05eeec0161437642) and `.part01` (47,458,716 bytes,
  sha256 1ea1d3dc5a1cb509221d50feb71cb3873008076894ee6fe9e28dc8424098b06a); stream-extracted from the parts, the md5s
  above match. Pushed to windows-assets at f7a4e023 (on b6c7709e; the owner allowed new pairs without asking).
- A client on pair 42 or older draws nothing for the new ids: ship pair 43 before the `cursedchest` install step.
  Previews (the three looks at 1x and 4x, and every phase of each at 4x, rendered from pair 43): scratchpad only. Not run in a client.

## Everfull potion looks (pair 44: items 38645-38656, `tools/sprites/gen_everfull_art.py`, `art_import/everfull*`; built 2026-10-25; on windows-assets a8d61566)
Owner request 2026-10-25: the Everfull potions wore the stock potions' looks (266 / 268 and the great, ultimate, supreme ones);
they get art of their own, and every line gets four tiers (server/README.md "Potions", "Own art and four tiers a line", O247).
Twelve PixelLab results (32 x 32 RGBA, alpha 0 / 255), owner approved: health, mana, spirit, tiers 1 to 4. One flask shape per
tier, the same in the three colours (a small flask, a round one with a neck ring, a round one in a gold cradle, a gold-winged one).
- **Pixels.** PixelLab's: not repainted, snapped or recoloured (only the colour under fully transparent pixels is cleared).
  Credit: docs/CREDITS.md "Tools" (PixelLab; `art_import/everfull_sources.csv`). The raw folder is git-ignored; `build --src DIR`
  copies the twelve files to `art_import/everfull/` (about 25 KB), so CI and later rebuilds need no PixelLab folder.
- **Style.** Red, blue, purple and gold, none of the seven theme palettes, so nothing is snapped. `build` runs `style_check.py`
  on each canvas against its own colours: outline, noise, colour count, alpha and scale pass; the light rule is
  a warning (the gold cradles of tier 3 catch the light from below). `build --check` (CI) rebuilds from the committed sources.
- **Things.** `art_import/everfull.csv`: twelve 1 x 1 flasks, one phase, kind flask, mode new, flags `copy:<stock client id>`
  (the potion each server item was made from: 266 / 268 for tier 1, the stock great, ultimate and supreme ones above; stackable,
  multi-use, as the stock potion was; engine patch 0043 relies on a stackable item that is never used up). Atlas
  `art_import/everfull.png`: 12 cells of 32 px side by side (384 x 32).

| Client id | Look | Server id | | Client id | Look | Server id |
|---|---|---|---|---|---|---|
| 38645 | health tier 1 | 32085 | | 38651 | mana tier 3 (ultimate) | 32265 |
| 38646 | health tier 2 (great) | 32261 | | 38652 | mana tier 4 (supreme) | 32269 |
| 38647 | health tier 3 (ultimate) | 32264 | | 38653 | spirit tier 1 | 32268 |
| 38648 | health tier 4 (supreme) | 32267 | | 38654 | spirit tier 2 (great) | 32263 |
| 38649 | mana tier 1 | 32086 | | 38655 | spirit tier 3 (ultimate) | 32266 |
| 38650 | mana tier 2 (great) | 32262 | | 38656 | spirit tier 4 (supreme) | 32270 |

- **Server.** `potions_config.lua` `clientId` on every entry; `tools/install_potions.py` (step `potions`) writes it into each
  item node, on new and on existing nodes (idempotent), and clears the ANIMATION flag (the art has one phase; the server sends a
  phase byte for the flag and the client reads it only for a thing with more than one phase). Helper: `EVERFULL_ITEMS` in
  `game_helper/helper_potions.lua` (the test compares it with `potions_config.lua`).

```
python3 -I client/tools/sprites/gen_everfull_art.py build [--src PIXELLAB_DIR] [--preview DIR --dat pair44/Tibia.dat --spr pair44/Tibia.spr]
python3 -I client/tools/sprites/import_art_things.py --ours-dat pair43/Tibia.dat --ours-spr pair43/Tibia.spr --out-dir pair44 \
    --things client/tools/sprites/art_import/everfull.csv --first-item 38645 --expect-items 38644
python3 -I client/tools/sprites/check_pair.py pair44/Tibia.dat pair44/Tibia.spr --old pair43/Tibia.dat pair43/Tibia.spr [--new-only]
python3 -I client/tools/sprites/gen_outfit_anchors.py pair44/Tibia.dat pair44/Tibia.spr
python3 -I client/tools/sprites/gen_info_lift.py pair44/Tibia.dat pair44/Tibia.spr
```
Input pair 43 (dat 2cb2321ef0dffd58bc4d52411bca5a89, spr 078b92ec8672792748999425de5e0743).
Output **pair 44**: dat 0b80ccae36490b8dd4a03f2627b2f85e (11,261,073 bytes), spr 8cbcc5370f74045323e2f8f27aae51a3
(1,541,138,573 bytes, 1,357,884 sprites: 12 appended), 38,656 items (12 appended), 2,681 outfits, 4101 effects, 253 missiles.
The importer verified the 12 sprite slots pixel-identical to the atlas and every old thing byte-identical. Built once.
- `check_pair.py --old`: `--new-only` 0 errors, 0 warnings (45,580 old things and 1,357,872 old sprites compared).
  `outfit_anchors.lua` and `info_lifts.lua`: only the dat md5 changes.
- Archive (the pair 41 recipe: `tar --owner=0 --group=0 --numeric-owner --mtime='2026-10-22 00:00:00Z' --format=gnu`,
  `xz -9 -T0`, `split -b 95M -d -a 2`): 147,050,148 bytes, sha256
  de1841459bed5970acbccd5f477ee19875b5c7f5422369b736ad62b8ac3a3637; parts `things-1098.tar.xz.part00` (99,614,720
  bytes, sha256 c0be978e46069045015b6ed405380083f9c357c8c6fa5dc894b27b8913adf3f5) and `.part01` (47,435,428 bytes,
  sha256 5e106b88edfc9abaf39147c86bfe827acd1526f748a322b0c812d48804c08d9d); the parts joined equal the archive, and
  stream-extracted from it the md5s above match. Not pushed to windows-assets by the builder: the lead pushes the pair.
- **Ship order.** A client on pair 43 or older draws nothing for the new ids: ship pair 44 and a client build before the
  server's `potions` install step. Preview (the twelve looks at 1x and 4x, rendered from pair 44): scratchpad only. Not run in a client.

## Reward Chest look (pair 45: item 38657, `tools/sprites/gen_reward_chest_art.py`, `art_import/reward_chest*`; built 2026-10-26; shipped inside pair 46, windows-assets 4553b922; the first pick went up alone as eac7e96f)
Owner request 2026-10-26: "make a reward chest and give every quest chest this sprite". Every chest a player takes a reward
from (the rift's, the Descent's, the planned areas' and the base server's quest chests; server/README.md "Reward chests") wore the
stock reward chest (server 21584, client 19250: a gold chest on a stone plinth). One PixelLab result (64 x 64 RGBA, alpha 0 / 255,
our own prompts, `generate-image-v2`): a gold chest overflowing with coins and gems, the lid open. The first pick (dark wood, gold bands, ember red) was too plain for the owner (2026-10-26: "far more eye-catching, gold and jewels, golden and shiny"); the second (gem-studded gold, `f_14`) gave way to the runner-up with coins spilling out, which the owner asked to have mirrored left-right: `gen_reward_chest_art.py` flips the committed source in `build` (`MIRROR`, a lossless flip; `build --check` reproduces it).
- **Pixels.** PixelLab's: not repainted, snapped or recoloured (only the colour under fully transparent pixels is cleared).
  128 candidates from eight prompt variants; the pick is the 6th of the "lid open, coins and jewels spilling" variant (`reward_chest_f_6.png`, committed unflipped; the raw
  folder `pixellab-pip-generations/reward-chest/` is git-ignored). Credit: docs/CREDITS.md "Tools" (PixelLab;
  `art_import/reward_chest_sources.csv`). `build --src DIR` copies the file to `art_import/reward_chest/` (about 4 KB), so CI and
  later rebuilds need no PixelLab folder.
- **Still, no idle loop.** PixelLab's `animate-with-text-v3` on the pick (4 frames, sparkle glints) lifted the lid and moved the outline
  in two frames; a chest that stands on the map for good should not shimmer, so one phase (the Cursed Chest's looks, which
  come and go, keep their loops).
- **Style.** Gold, wood and ember red, none of the seven theme palettes, so nothing is snapped. `build` runs `style_check.py`
  on the canvas against its own colours: outline, light, noise, colour count, alpha and scale pass (31 colours); the noise rule gives a warning (2 lone pixels and 2 specks: the sparkle glints and the spilled coins), as the colour count did for earlier owner-approved looks.
  `build --check` (CI) rebuilds from the committed source.
- **Things.** `art_import/reward_chest.csv`: one 2 x 2 item, one phase, kind chest, mode new, flags `copy:19250` (the stock reward
  chest: container, blocks, not moveable). Atlas `art_import/reward_chest.png`: one 64 px cell.

| Client id | Look | Server id |
|---|---|---|
| 38657 | reward chest | 32310 |

- **Server.** `tools/install_reward_chest.py` (step `rewardchest`, before `rewardchests`): items.otb node copied from 21584 with
  the new ids, items.xml entry; `rift_config.lua` `chest`, `descent_config.lua` `objects` use 32310 with 21584 as fallback;
  `tools/patch_reward_chests.py` swaps the quest chests on the map.

```
python3 -I client/tools/sprites/gen_reward_chest_art.py build [--src PIXELLAB_DIR] [--preview DIR --dat pair45/Tibia.dat --spr pair45/Tibia.spr]
python3 -I client/tools/sprites/import_art_things.py --ours-dat pair44/Tibia.dat --ours-spr pair44/Tibia.spr --out-dir pair45 \
    --things client/tools/sprites/art_import/reward_chest.csv --first-item 38657 --expect-items 38656
python3 -I client/tools/sprites/check_pair.py pair45/Tibia.dat pair45/Tibia.spr --old pair44/Tibia.dat pair44/Tibia.spr [--new-only]
python3 -I client/tools/sprites/gen_outfit_anchors.py pair45/Tibia.dat pair45/Tibia.spr
python3 -I client/tools/sprites/gen_info_lift.py pair45/Tibia.dat pair45/Tibia.spr
```
Input pair 44 (dat 0b80ccae36490b8dd4a03f2627b2f85e, spr 8cbcc5370f74045323e2f8f27aae51a3).
Output **pair 45**: dat 24bfad917c9c8c47630fbcdc7f718098 (11,261,105 bytes), spr 72aec17d22c02fb08875a22c36440662
(1,541,150,037 bytes, 1,357,888 sprites: 4 appended), 38,657 items (1 appended), 2,681 outfits, 4101 effects, 253 missiles.
The importer verified the 4 sprite slots pixel-identical to the atlas and every old thing byte-identical. Built once.
- `check_pair.py --old`: `--new-only` 0 errors, 0 warnings (45,592 old things and 1,357,884 old sprites compared).
  `outfit_anchors.lua` and `info_lifts.lua`: only the dat md5 changes.
- Archive (the pair 41 recipe: `tar --owner=0 --group=0 --numeric-owner --mtime='2026-10-22 00:00:00Z' --format=gnu`,
  `xz -9 -T0`, `split -b 95M -d -a 2`): 147,085,420 bytes, sha256
  cd5e2d702af0294beb0c96484cc57370bc62b4b279933d2d482fb00df6bad894; parts `things-1098.tar.xz.part00` (99,614,720
  bytes, sha256 dc3ea0efa6e9d4b696e77c968aeda58540b9bfa3a0f9c9979bc935298b3b70c8) and `.part01` (47,470,700 bytes,
  sha256 0e9c114b342997737ca0e9e92a90df2cfcffac61a78be9230580aec1bfba75de); the parts joined equal the archive, and
  stream-extracted from it the md5s above match. This archive was not pushed: pair 46 (below) carries it.
- **Ship order.** A client on pair 44 or older draws nothing for the new id: ship pair 45 (or later) and a client build before the
  server's `rewardchest` install step. Preview (the new look and the stock chest at 1x and 4x, rendered from pair 45):
  scratchpad only. Not run in a client.

## Support rune looks (pair 46: items 38658-38757, `tools/sprites/gen_support_runes_art.py`, `art_import/support_runes*`; built 2026-10-26; on windows-assets 4553b922)
Owner request 2026-10-26: "Gere novas runas. Vamos usar as artes das runas como icones tambem". The 100 support rune items (server ids
32101-32200, server/data/scripts/chaos/SUPPORTS.md "The runes") wore the stock rune stones and the window drew procedural icons.
- **Art.** One carved dark stone per support, 32 x 32, the support's glowing sigil in its theme colour (ember sunburst orange, rime
  crystal ice-blue, dawn cross pale gold, grave skull green, storm bolt blue, quickening spiral yellow, thrift drop teal, keen edge
  sword silver, echo rings blue, fork trident yellow, breadth waves orange, shatter starburst cyan, deathburst red burst, surge bolt
  yellow, reprisal shield silver, bloodthirst drop red, siphon drop in a ring blue, sunder hammer orange, hex eye purple, mercy leaf
  green). One stone shape for all 20: PixelLab `generate-image-v2` with the first stone as `style_image` and one seed, 64 candidates per
  support, one pick each. **Levels:** the five levels are the same picture with the stone's rim in the level colour of the game
  (`chaos_supports_config.lua` `levelColors`: grey-brown Common = the pick, green Rare, red Epic, yellow Legendary, purple Mythic),
  made with PixelLab `edit-images-v2` (text edit of the pick, 10 images per call, seed 2026); no local overlay, every pixel is
  PixelLab's. Two Mythic rims (dawnbrand, hex) failed `style_check` (outline share, colour count) and were redone with a prompt
  that keeps the black outline. Raw output: `pixellab-pip-generations/support-runes/` (git-ignored, with `calls.jsonl`).
  Credits spent: 40 calls, USD 2.90 plus 1 included generation (21 Pro image batches 1.68 with the base stone, 15 Pro edit calls
  1.20 with one test and the redos, 4 cheap Pixen edit tests 0.03 that were not used); credit: docs/CREDITS.md "Tools", `art_import/support_runes_sources.csv`.
- **Committed.** `art_import/support_runes/<key>_<level>.png` (100 sources), `support_runes.png` (atlas 160 x 640, a row per support),
  `support_runes.csv` (things: 1 x 1, one phase, kind rune, mode new, flags `copy:<stock client id>` = server id of the stock stone
  - 2656, 22029-22042: stackable, use-with), `support_runes.sums`. `build --check` (CI) rebuilds; `build` runs `style_check` on each
  look against its own colours (outline, noise, colour count, alpha, scale pass; not snapped to a theme palette).
- **Icons.** `gen_support_runes_art.py icons` writes `client/overlay/data/images/game/supports/<key>.png` (32 x 32) = the Common look;
  the window (`spellsupports.lua`), the action bar and the wiki (`gen_wiki_art.py`, regenerated) read those files. 32 x 32 is the
  only size the client uses. `tools/gen_support_icons.py` (procedural) is removed.
- **Server.** `chaos_supports_config.lua` `clientFirstId = 38658` (client id = clientFirstId + server id - 32101);
  `install_supports.py` (step `supports`) writes it into each node, refuses a client id another item owns, is idempotent and turns
  nodes still on the stock look. **Fallback:** `clientFirstId = nil` and run the step again: the nodes go back to the stock stones.
- **Pair step.** `tools/sprites/build_support_runes_pair.sh IN_DIR OUT_DIR [LAST_ITEM_OF_IN]` (art check, `import_art_things.py
  --first-item LAST+1 --expect-items LAST`, `check_pair.py --old --new-only`, md5s); then `gen_outfit_anchors.py` and `gen_info_lift.py`
  on the output. Runs on any input pair whose last item is 38657 (the ids must equal `clientFirstId`).
  Input the final pair 45 (dat 24bfad917c9c8c47630fbcdc7f718098, spr 72aec17d22c02fb08875a22c36440662).
  Output **pair 46**: dat 58062a1ed9dc6f0e5323752a4d1fd896 (11,263,055 bytes), spr 71b147590afcc0561f7bfcf3dfdc1301 (1,541,350,017
  bytes, 1,357,988 sprites: 100 appended), 38,757 items (100 appended); importer: 100 slots pixel-identical, every old thing
  byte-identical; `check_pair --new-only` 0 errors, 0 warnings; the full check 0 errors, 206 warnings (the same as pair 45).
  `outfit_anchors.lua` and `info_lifts.lua`: only the dat md5 changes.
- Archive (the pair 41 recipe): 147,062,448 bytes, sha256 2d529ea91f9dfdc0c6d7cf50161d1c4ab13a129189656eece3ca46bfcebb7a54;
  parts `things-1098.tar.xz.part00` (99,614,720 bytes, sha256 bc3b9ca801f750f629eae8aa8b11599134e84d34f69671b8b17d00d2ff002ecf)
  and `.part01` (47,447,728 bytes, sha256 9b0c4580a90daf4ff6ef1560be9e96901a7f24883b7bb743059cc38835adb81a); the joined parts
  extract to the md5s above. Preview (all 100 looks, 4x, names under each): scratchpad only. Not run in a client.
- **Ship order.** A client on pair 45 or older draws nothing for the new ids: ship pair 46 and a client build (the new icons) before the
  server's `supports` install step, or keep `clientFirstId = nil` until then.

## Reward Chest look, one tile (pair 47: item 38758, `tools/sprites/gen_reward_chest_art.py build-small`, `art_import/reward_chest_small*`; built 2026-10-26; on windows-assets ba3a1e01)
Owner request 2026-10-26: the base map's quest chests were one tile big, and a 2 x 2 chest overlaps walls and neighbouring chests in tight
quest rooms (31 of about 297 sit next to another chest). The owner picked a one-tile version of the Reward Chest look ("use o 15", candidate
15 of the 32 x 32 sheet). Quest chests and quest boxes of the base map wear it; server/README.md "Reward chests".
- **Pixels.** PixelLab's: `generate-image-v2` (Pro), 32 x 32, no background, style image = the approved 64 art scaled down 2x, reference =
  the 64 art (raw file `pro_style32_13.png` of the git-ignored `pixellab-pip-generations/reward-chest-32/`). Not repainted, snapped or
  recoloured: the colour under fully transparent pixels is cleared, and the picture is **mirrored left-right** (`MIRROR_SMALL`, lossless).
  Compared side by side, the raw 32 px file leans like the big look's unflipped source (the big look is mirrored by `build`), so without
  the flip the two looks would face opposite ways. The committed source `art_import/reward_chest/reward_chest_small.png` is the unflipped
  PixelLab file. Credit: docs/CREDITS.md "Tools" (PixelLab; `art_import/reward_chest_sources.csv`).
- **Style.** `build-small` runs `style_check.py` on the 32 px cell against its own colours (61 colours): outline, light, noise, colour
  count, alpha and scale pass, no warnings. `build-small --check` (CI) rebuilds from the committed source.
- **Things.** `art_import/reward_chest_small.csv`: one 1 x 1 item, one phase, kind chest, mode new, flags `copy:19250` (container, blocks,
  not moveable). Atlas `art_import/reward_chest_small.png`: one 32 px cell.

| Client id | Look | Server id |
|---|---|---|
| 38758 | reward chest, one tile | 32311 |

Pair 53 (2026-10-27) redraws 38758 in place from a purchased prop, and the one-tile look is now the only reward chest look: see "Pair 53". The PixelLab pixels above are no longer drawn.

- **Server.** `tools/install_reward_chest.py` installs it beside 32310 (same node copy of 21584, same items.xml attributes);
  `rift_config.lua` `chest.smallItemId`; `tools/patch_reward_chests.py` gives it to the base map's quest chests and boxes.

```
python3 -I client/tools/sprites/gen_reward_chest_art.py build-small [--src PIXELLAB_DIR/pro_style32_13.png]
python3 -I client/tools/sprites/import_art_things.py --ours-dat pair46/Tibia.dat --ours-spr pair46/Tibia.spr --out-dir pair47 \
    --things client/tools/sprites/art_import/reward_chest_small.csv --first-item 38758 --expect-items 38757
python3 -I client/tools/sprites/check_pair.py pair47/Tibia.dat pair47/Tibia.spr --old pair46/Tibia.dat pair46/Tibia.spr --new-only
python3 -I client/tools/sprites/gen_outfit_anchors.py pair47/Tibia.dat pair47/Tibia.spr
python3 -I client/tools/sprites/gen_info_lift.py pair47/Tibia.dat pair47/Tibia.spr
```
Input pair 46 (dat 58062a1ed9dc6f0e5323752a4d1fd896, spr 71b147590afcc0561f7bfcf3dfdc1301).
Output **pair 47**: dat e0c1c929361d17242446e39f978dbe02 (11,263,074 bytes), spr ec61b71c52447b6f22e0dd0ddd5f3815
(1,541,352,814 bytes, 1,357,989 sprites: 1 appended), 38,758 items (1 appended), 2,681 outfits, 4101 effects, 253 missiles.
The importer verified the sprite slot pixel-identical to the atlas and every old thing byte-identical. Built once.
- `check_pair.py --old`: `--new-only` 0 errors, 0 warnings (45,693 old things and 1,357,988 old sprites compared); the full check
  gives 0 errors and the same 206 warnings as pair 46. `outfit_anchors.lua` and `info_lifts.lua`: only the dat md5 changes (the
  "Live sprite pair" CI job checks both against the pair on windows-assets).
- Archive (the pair 41 recipe: `tar --owner=0 --group=0 --numeric-owner --mtime='2026-10-22 00:00:00Z' --format=gnu`, `xz -9 -T3`,
  `split -b 95M -d -a 2`): 147,077,004 bytes, sha256 5f436e96cbfe182252936574c00069fbf1a63f731ac6189088d10c527ce996ea; parts
  `things-1098.tar.xz.part00` (99,614,720 bytes, sha256 f00d4c5fb7dfcc25cdc5852b7ede493a60dac60e6601cb67f91c96f7086385e6) and `.part01`
  (47,462,284 bytes, sha256 8d2060c017fd1f36b0de9cf5dd992572c36389eca8e92b22ae6d76acb0e1aa7c); the joined parts extract to the md5s
  above. Pushed to windows-assets as **ba3a1e01** (parent 4553b922, "Pair 47 (1-tile reward chest)"; `SHA256SUMS.parts` and the two
  part files changed, the part count stays two).
- **Ship order.** A client on pair 46 or older draws nothing for 38758: ship pair 47 (or later) and a client build before the server's
  `rewardchest` install step (then `rewardchests`). Not run in a client.

## Decoration of the ice, swamp, lava and cave biomes (pair 48: items 38759-39110, `tools/sprites/import_donor_things.py import --source v1098w`, `tools/sprites/decor48_selection.csv`; built 2026-10-26; not pushed to windows-assets yet)
Owner request 2026-10-26: more decoration things for the ice, swamp, lava and cave areas, taken from a donor pair ("source B", a
10.98-style pair of 66,026 items whose map was surveyed for what stands on which ground; the owner approved using it). Art only: no
text, logo, store or coin art, no signs.
- **Selection.** Of the 8,258 things source B has that our pair 47 lacks (pixel compare of every sprite, near duplicates of our
  art left out), each biome takes decoration things (no grounds, no walls or stairs, nothing pickupable, usable, hangable or with
  an elevation or default action, nothing that draws above creatures), ranked by how often the map uses them on that biome's
  grounds (ground colour classes ice / swamp / lava / cave; weak where the map shows no ground, then by the thing's own colour).
  Every thing was then looked at on a contact sheet and kept only when it is a static prop: rocks, crystals, trees, bushes, reeds,
  mushrooms, logs, roots, vines, snow piles, ice spikes, lava rocks and ember bits, a few flames. The cave list also holds the
  dead trees, coal and sandstone boulders, blue and red crystals, moss and plants; walls, building and furniture pieces,
  weapons, torches, text, creatures and statues were dropped.

| Biome | Things | Limit | Client ids | Notes |
|---|---|---|---|---|
| ice | 58 | 120 | 38759-38816 | frosted and bare trees, snow piles, ice spikes and crystals, blue grass, rocks (the pool of the ice grounds holds only 127 props, most of them walls and stairs) |
| lava | 16 | 70 | 38817-38832 | lava rocks and crystals, ember bits, flames, a cracked-lava patch (lava grounds are rare on the map: 63 candidates, most of them fire effects, 6 kept; 10 more picked by colour from the cave list) |
| swamp | 150 | 150 | 38833-38982 | trees, bushes, reeds, flowers, mushrooms, logs, roots, vines, cacti (cut from 224 kept things, lowest map use first) |
| cave | 128 | 200 | 38983-39110 | dead trees, logs, roots, crystals, coal and sand rocks, moss, plants (the cave ground class also covers towns, so most of the ranked list is building and furniture pieces; the deeper list was looked at to the point where nothing usable was left) |

  Client ids follow the biome order of the table; sizes: 233 things 2 x 2, 71 1 x 1, 24 2 x 1, 24 1 x 2.
- **Importer.** `import_donor_things.py` got the profile `v1098w` (10.98 flags and layout, a 14 byte header with a u32 last item id:
  source B has more than 65,535 items), `--key-prefix decor48` (manifest key `decor48_<biome>_<client id>`), and an exact size
  under 32 on a bigger-than-1x1 thing is raised to 32 (the client rule of `check_pair.py`; 14 things had 21-29). Test
  `tools/sprites/import_donor_things_test.py` (CI).
- **Server.** `tools/install_decor48_items.py` (install_all step `decor48items`, after `rewardchest`; test
  `install_decor48_items_test.py`): items.otb nodes and items.xml names ("ice prop 1" ... "cave prop 128") from
  `server/data/items/decor48_items.csv` (the importer's `donor_items.csv`). Server id = client id + **4000** (42759-43110): client id
  + 3000 would cover the Waystone Tier items 41951-41959. Trees, rocks and the like block (otb solid), plants and snow piles do not;
  `--kit-json` writes the biome lists for the map studio kits.

```
python3 -I client/tools/sprites/import_donor_things.py import --source v1098w --src-dat B/Tibia.dat --src-spr B/Tibia.spr \
    --ours-dat pair47/Tibia.dat --ours-spr pair47/Tibia.spr --select client/tools/sprites/decor48_selection.csv \
    --out-dir pair48 --server-id-offset 4000 --key-prefix decor48 --expect item=38759
python3 -I client/tools/sprites/check_pair.py pair48/Tibia.dat pair48/Tibia.spr --old pair47/Tibia.dat pair47/Tibia.spr --new-only
cp pair48/donor_items.csv server/data/items/decor48_items.csv
```
Input pair 47 (dat e0c1c929361d17242446e39f978dbe02, spr ec61b71c52447b6f22e0dd0ddd5f3815).
Output **pair 48**: dat e0ffc626657cfa0f70545442aa427f41 (11,280,609 bytes), spr ce361ab67bbd8897f5332e9db0f2b95e
(1,544,505,855 bytes, 1,359,878 sprites: 1,889 appended, 107 records of the new things were already in the pair and reused), 39,110
items (352 appended), 2,681 outfits, 4101 effects, 253 missiles. The importer verified 2,493 sprite slots pixel-identical to
the source and every old thing byte-identical; the build is deterministic (run twice, same md5s).
- `check_pair.py --old`: `--new-only` 0 errors, 0 warnings (45,694 old things and 1,357,989 old sprites compared; 55 info lines
  about empty slots of big things); the full check 0 errors, 206 warnings (the same as pair 47). `style_check.py` not run: it
  measures our own art against our palette, and these are another pair's pixels.
- Archive (the pair 41 recipe: `tar --owner=0 --group=0 --numeric-owner --mtime='2026-10-22 00:00:00Z' --format=gnu`, `xz -9 -T3`,
  `split -b 95M -d -a 2`): 147,547,852 bytes, sha256 fa1c26382ea4865ece8d13ff29366b0d662e487c12bd4e691fcc59bb08be0fcd; parts
  `things-1098.tar.xz.part00` (99,614,720 bytes, sha256 226bc8cd231ab95fe67d8786c6c13725cf1a4d0e8622be8474fd7ea8f5bb7cad) and `.part01`
  (47,933,132 bytes, sha256 58ad98450dad34a054612f8f016f0aa61dcbaec48fa8c8aea9879bb2e2634be1); the joined parts extract to the md5s
  above. Pushed to windows-assets as **afc57d34** (parent ba3a1e01); 90555d38 restores the sum line of the old unsplit
  `things/things-1098.tar.xz` (still in the tree, unused) that afc57d34 had overwritten. `outfit_anchors.lua` and `info_lifts.lua` regenerated on
  pair 48 (only the dat md5 changes). Install `decor48items` on the server only together with a client on pair 48 or newer.
- **Ship order.** A client on pair 47 or older draws nothing for 38759-39110: ship pair 48 and a client build before placing
  the items on a map.

## Decoration of the celestial and cursed biomes (pair 49: items 39111-39197, `tools/sprites/gen_decor49.py` + `import_art_things.py`, `tools/sprites/art_import/decor49*`; built 2026-10-26; on windows-assets 4fcb48ff)
Owner request 2026-10-26 ("pair 49"): decoration things for the two Map Studio biomes celestial and cursed. Art only: no text,
logo, store or coin art, no signs.
- **Art.** Own drawn art (clouds, glowing rune circles, starlight, marble pillars, taint pools, pumpkins) and prepared single
  objects of three decoration sources (C, D, E in docs/CREDITS.md), recoloured to marble / gold where the spec says, padded to
  whole tiles, never scaled. The atlas `art_import/decor49.png` holds third-party pixels and is git-ignored; `gen_decor49.py
  build --src DIR` rebuilds it, `decor49.csv` (things file), `decor49.sums`, `decor49_sources.csv` (neutral source letter, file and
  pixel sha256 of each object), `decor49_selection.csv` and `server/data/items/decor49_items.csv`. `build --check` (CI) compares
  the tables with each other and the sums with the atlas when it is on disk; `gen_decor49_test.py` (CI).

| Biome | Things | Client ids | Notes |
|---|---|---|---|
| celestial | 36 | 39111-39146 | crystal clusters, marble statues, stelae, a shrine, a fountain, pillars, golden lamps and braziers, doves, clouds, glowing rune circles, starlight |
| cursed | 51 | 39147-39197 | 12 dead trees, tombstones, coffins, an open grave, a crypt, scarecrows, altars, cauldrons, bones, pumpkins, taint pools, a violet sigil |

  Sizes: 39 things 1 x 1, 31 2 x 2, 9 1 x 2, 8 2 x 1. 22 carry a light, 7 are animated (4 phases), 55 block.
- **Server.** `tools/install_decor49_items.py` (install_all step `decor49items`, after `decor48items`; test
  `install_decor49_items_test.py`): items.otb nodes and items.xml names from `decor49_items.csv`, server id = client id + **4000**
  (43111-43197, directly after pair 48's block). `--kit-json` writes the biome lists for the map studio kits.

```
python3 -I client/tools/sprites/gen_decor49.py build --src DIR
python3 -I client/tools/sprites/import_art_things.py --ours-dat pair48/Tibia.dat --ours-spr pair48/Tibia.spr --out-dir pair49 \
    --things client/tools/sprites/art_import/decor49.csv --first-item 39111 --expect-items 39110
python3 -I client/tools/sprites/check_pair.py pair49/Tibia.dat pair49/Tibia.spr --old pair48/Tibia.dat pair48/Tibia.spr --new-only
```
Input pair 48 (dat e0ffc626657cfa0f70545442aa427f41, spr ce361ab67bbd8897f5332e9db0f2b95e).
Output **pair 49**: dat 546d0c6099c8a40505b8f32b7e6ca381 (11,282,963 bytes), spr f241c7a5a4a9784da19d5ade105544d9
(1,544,792,351 bytes, 1,360,082 sprites: 204 appended), 39,197 items (87 appended), 2,681 outfits, 4101 effects, 253 missiles.
- `check_pair.py --old` (46,046 old things and 1,359,878 old sprites compared): `--new-only` 0 errors, 0 warnings (3 info lines
  about empty slots of big things); the full check 0 errors, 206 warnings (the same as pair 48). The dat flags of all 87 items
  were compared with the manifest. `gen_outfit_anchors.py --check` and `gen_info_lift.py --check` pass on pair 49 (only the dat md5
  changed in `outfit_anchors.lua` and `info_lifts.lua`). Not run in a client.
- Archive (the pair 41 recipe: `tar --owner=0 --group=0 --numeric-owner --mtime='2026-10-22 00:00:00Z' --format=gnu`, `xz -9 -T3`,
  `split -b 95M -d -a 2`): 147,615,964 bytes, sha256 1b18181d88da9f72671db71e6f31a6bf562648f56594fce838507f75ae6bd1f7; parts
  `things-1098.tar.xz.part00` (99,614,720 bytes, sha256 ebbe6bc723020072f5de40f2a62064e79152940073b92c7fbd6a03738997f3cf) and `.part01`
  (48,001,244 bytes, sha256 d749e4e49f30043fecd0c0c7c0c8ce48d8248dab05d59071f92c834692254e01); the joined parts extract to the md5s
  above. Pushed to windows-assets as **4fcb48ff** (parent 90555d38); only the two part lines of SHA256SUMS.parts changed.
- **Ship order.** Install `decor49items` on the server only together with a client on pair 49 or newer: a client on pair 48 or older
  draws nothing for 39111-39197. Ship pair 49 and a client build before placing the items on a map.

## Ground, walls, stairs, decoration, monsters and effects of two purchased sources (pair 50: items 39198-44395, outfits 2682-3360, effects 4102-4701, `tools/sprites/import_pair50.py`; built 2026-10-27; on windows-assets 87c4b09c)
Owner request 2026-10-27: "take everything we can use, floor, wall, stairs, decoration and monsters" from two purchased sprite
sources, called **source G** and **source F** in docs/CREDITS.md. Pair 50 is pair 49 plus this art. No archive or server names in
the repo: the selections are `tools/sprites/pair50_G_selection.csv` and `pair50_F_selection.csv` (category, source id, name,
biome, size, notes), one row per chosen thing; no pixels are committed.
- **Tool.** `import_pair50.py` reads both sources and both selections in one pass (no intermediate pair), maps their sprites onto
  pair 49's records (identical records are reused by md5, the rest are appended, the spr offset table grows by 4 bytes per new
  sprite), appends the things to the dat and checks the result with the append-only guard. A thing selected twice (eight source F
  skull step pieces listed as wall and as stairs) is kept once, as stairs. Output tables: `pair50_import.csv` (one row per selected
  thing: imported or skipped, new id, reason), `server/data/items/pair50_items.csv`, `pair50_outfits.csv`, `pair50_effects.csv`.
  `import_pair50_test.py` (CI) tests the helpers and that the tables agree.
- **Items (5198).** Client ids 39198-44395, server ids 43198-48395 (client id + 4000). The dat flags are copied from the source
  (market, wrappable and unwrappable dropped). Counts: ground 1786, wall 1113, stairs 139, decoration 2021, corpses 139.
- **Stairs.** Source F has roles: up stairs 73 (floor change north for horizontal treads, west for vertical treads, a guess from the art, which
  climbs up and to the left), down stairs and holes 15 (down), ladders 2. Source G has no role in its selection: 8 ladders get the
  ladder use (script `pair50_items.lua`), its other 41 steps and pits carry no floor change.
- **Monsters (679).** Outfits 2682-3360 (G 282, F 397), four directions, frame groups kept. Corpses are container items.
- **Effects (600).** Ids 4102-4701 (G 53, F 547). Effects above 255 work (u16 effect ids). Big ones carry a send offset (width / 2,
  height / 2 tiles) in `server/data/lib/chaos_pair50_fx_ids.lua`, written by `gen_pair50_fx_ids.py` (`--check`, test in CI).
- **Missiles: none.** The protocol sends the missile id in one byte, 254 is the weapon-type constant and the pair already holds 253
  missiles. The 169 selected missiles (G 43, F 126) are skipped. An engine patch would be needed (not made).

```
python3 -I client/tools/sprites/import_pair50.py --help
python3 -I client/tools/sprites/check_pair.py pair50/Tibia.dat pair50/Tibia.spr --old pair49/Tibia.dat pair49/Tibia.spr --new-only
```
Input pair 49 (dat 546d0c6099c8a40505b8f32b7e6ca381, spr f241c7a5a4a9784da19d5ade105544d9).
Output **pair 50**: dat f424805d2d93d1cb4fed89b342a418fc (12,906,936 bytes), spr 30c6c17595f648683ea8b70a25b129d3
(1,831,845,070 bytes, 1,530,465 sprites: 170,383 appended), 44,395 items (5198 appended), 3,360 outfits (679), 4,701 effects (600),
253 missiles (0).
- `check_pair.py --old --new-only`: 0 errors, 34 warnings. The full check: 0 errors, 240 warnings (size-large 122, exact-size 65,
  thing-empty 34, missile-patterns 8, mask-empty 5, mask-not-mask 3, outfit-directions 2, displacement-range 1). `gen_outfit_anchors.py
  --check` and `gen_info_lift.py --check` pass on pair 50 (md5 only changed in `outfit_anchors.lua` and `info_lifts.lua`). Not run in a client.
- **Ship order.** Install `pair50items` (README "Pair 50 items") only together with a client on pair 50 or newer. Outfits and
  effects need the same client.
- Archive (the pair 41 recipe: `tar --owner=0 --group=0 --numeric-owner --mtime='2026-10-22 00:00:00Z' --format=gnu`, `xz -9 -T3`,
  `split -b 95M -d -a 2`): 186,713,348 bytes, sha256 c51565a31fcffc14310deb2258b75b9a0f2345adc6172f61206ad8150d3716d3; parts
  `things-1098.tar.xz.part00` (99,614,720 bytes, sha256 4704d407ee9646b119682bfdf910188418195080bf728a6d248ff47d8dbf7a33) and `.part01`
  (87,098,628 bytes, sha256 7954857b4b5cadf646ca1d95f25bf5c236d018eb73005db882a364a94d17b16b); the joined parts extract to the md5s
  above. Pushed to windows-assets as **87c4b09c** (parent 4fcb48ff); only the two part lines of SHA256SUMS.parts changed.

## Retired art: unused items, outfits, effects and missiles of pair 50 (pair 51: `tools/sprites/prune_pair.py`; built 2026-10-27)
Owner request 2026-10-27: "retire o que a gente nao usa dos nossos pares". Pair 51 is pair 50 minus the art nothing uses. No id moves:
a retired thing is blanked (one 1x1 frame, sprite 0, flag bytes kept) and the spr is compacted. Items.otb, the Lua tables and the
client id tables stay valid. The list is `tools/sprites/pair51_removed.csv` (kind,id,reason; 6,838 rows).
- **Rules.** Kept: every pickupable, moveable, container, door, key, house, corpse, fluid, field, rune and light item; every item id on a
  map (installed base map, the large test map, 7 small base maps); everything of pairs 49 and 50 that a script, kit, list or map names; outfits of
  players, NPCs, monsters and client lists; every effect and missile a script, spell or catalog name uses, and the whole base protocol
  range (effects 1-187, missiles 1-96). Retired: 3,803 items (base scenery 973, art_items 502, pack30 art about 1,700, ...), 42 outfits,
  2,929 effects, 62 missiles above the base range.
- **Tool.** `prune_pair.py prune` (streams the spr, pure Python), `restore` (puts archive things back at their ids, sprites appended),
  `stats`, `check-map` (blanked item ids that stand on a given map; needs numpy). `--archive-dir` writes an archive pair with the original ids.
  `prune_pair_test.py` (CI) runs on a synthetic pair.
- **Missile slots.** 62 missile ids are blank and free: 147-152, 189-199, 201-204, 206, 207, 209-227, 230-248, 250 (limit 254, 254 is the weapon-type
  constant). Refilled in place, see "Pair 51 missiles" below.

```
python3 -I client/tools/sprites/prune_pair.py prune --dat pair50/Tibia.dat --spr pair50/Tibia.spr \
    --removed client/tools/sprites/pair51_removed.csv --out-dir pair51 --archive-dir pair51/removed
python3 -I client/tools/sprites/check_pair.py pair51/Tibia.dat pair51/Tibia.spr
```
Input pair 50 (dat f424805d2d93d1cb4fed89b342a418fc, spr 30c6c17595f648683ea8b70a25b129d3).
Output **pair 51**: dat a4d59922593fb779e00d4bfda34f5282 (8,822,068 bytes), spr a7acc5b88b310fa6984960a1553c4501 (1,126,785,830 bytes,
943,002 sprites; pair 50 had 1,530,465), the same counts of things (44,395 items, 3,360 outfits, 4,701 effects, 253 missiles).
Archive pair: dat a19ebfdf56b9970d4a3fafc7993bf125 (4,737,560 bytes), spr b54054364807a62cde4ae93635fa0f6a (658,187,234 bytes, 388,134 sprites).
- `check_pair.py` (full): 0 errors, 4,045 warnings (thing-empty 3,868 are the blanks; the rest were in pair 50). `--old pair 50` fails by
  design, the append-only guard sees the compaction. `gen_outfit_anchors.py` and `gen_info_lift.py` regenerated (md5, and 42 outfits fewer).
  Not run in a client.
- **Names.** Effects and missiles that scripts use by name are kept: a quoted catalog name (swap tables such as `chaos_pack27_fx.lua`
  and `chaos_pack29_vfx.lua`, `CONST_ANI_` / `CONST_ME_` / `fx` keyed values), its base without a direction or number suffix, or a
  prefix used in a concatenation. `prune_pair.py keep-names` applies it and `prune` refuses a list that breaks it (test in CI).
  The first build missed this and blanked 127 effects and 29 missiles; the list was corrected and the pair rebuilt. A review then kept 105 more things (101 effects, 4 missiles: pack 36 names reserved for spells not written yet, and effect 560), listed with reasons in `pair51_keep.csv`. The removed-things
  backup on windows-assets (`backup/removed-pair51.tar.xz`) was made from the first list: it is a superset and also holds those restored things.
- **Ship order.** Server ids and items.otb do not change. Run `prune_pair.py check-map` on the live map first; a blanked item that stands
  on it shows as an invisible tile object. Ship the client with pair 51 and its regenerated `outfit_anchors.lua` and `info_lifts.lua` together.
- **Roofs put back (2026-10-27, owner "Trocar por telhado bonito").** Items 38477-38487 (the rusty tin roof pieces of the pair 33 kit:
  interior 1-3, n, s, e, w, nw, ne, sw, se) stand on the installed map now (server/README.md "Hunt roofs", install step `huntroofs`), so
  their 11 rows left `pair51_removed.csv` and are in `pair51_keep.csv`. The built pair 51 still has them blank: `prune_pair.py restore ...
  --ids item:38477-38487` on it (command in the README section) before the server step runs. Done: see "Pair 52" below.
- **Rift looks put back (O309, 2026-10-29, open).** The scan did not see looks that `rift_config.lua` sets at runtime: 13 outfits
  of the rifts were retired and are blank in pairs 51-56 (2101, 2102, 2105, 2106, 2109, 2110, 2112, 2113 and the big guardians
  2208-2212), so rift monsters of those ranks were invisible. Their rows moved to `pair51_keep.csv`. Until a pair 57 restores them
  (`prune_pair.py restore --ids outfit:2101,2102,2105,2106,2109,2110,2112,2113,2208-2212` on the pair 56, archive on windows-assets),
  the server wears replacements (`rift_config.lua` `looks.undrawn`, `bigGuardiansOn = false`). Then drop the 13 ids from `PAIR_BLANK`
  in `tools/ci/check_content.py`.

### Pair 51 missiles (`tools/sprites/import_pair51_missiles.py`; built 2026-10-27, on the 62-id list)
The 62 freed missile ids hold the best 62 of the 169 missiles of the two purchased sprite sources (source G 43, source F 126) that
pair 50 had to skip. Choice and names: `tools/sprites/pair51_missiles.csv` (missile_id, source, src_id, name, element, size, phases;
23 from source G, 39 from source F). Picked by looking at all 169 (candidate sheet, then the 8 directions of the final set): faint,
tiny, broken, off-direction and near-duplicate missiles are out. Each blank entry is replaced entirely: flags light and displacement
only, the source's 3x3 direction patterns, phases and animator; 2,170 new sprite records appended (8 slots reuse records of the input).
No other entry changes (byte-identical, checked), no id moves. Counts: fire 12, ice 11, physical 9, energy 8, death 8, earth 6,
holy 6, water 2. `pair51_removed.csv` keeps its 62 missile rows (what `prune_pair.py` blanks from pair 50); their reason says the slot is
refilled. Run order: `prune_pair.py prune` (pair 50 -> pair 51 without missiles), then this importer.
- **Names.** `tools/sprites/gen_pair51_missile_ids.py` (`--check` and test in CI) writes `server/data/lib/chaos_pair51_missile_ids.lua`:
  `ChaosPair51Missile.<name> = id` and `ChaosVfxMissile.p51_<name> = {id, dx, dy}` (VfxShoot; dx, dy are half the size, untested for
  the 2x2 ones in a client). Nothing in the game sends them yet.
- **Old names on the same ids.** 56 of the 62 ids still carry a catalog name in the older pack libs (proj_* 189-203, mega_* 204-250:
  names reserved for spells not written yet, kept by the name rule of the prune; no spell sends them today). A spell that sends one of
  those names later draws the new missile of that id, so give that spell its own name or one of the p51_ names.
- **Preview.** Every missile in its 8 directions (client mapping NW N NE E SE S SW W) was rendered from the new pair and looked at.
```
python3 -I client/tools/sprites/import_pair51_missiles.py --dat pair51/Tibia.dat --spr pair51/Tibia.spr --out-dir out \
    --src-g-dat G.dat --src-g-spr G.spr --src-f-dat F.dat --src-f-spr F.spr
python3 -I client/tools/sprites/check_pair.py out/Tibia.dat out/Tibia.spr
```
Input pair 51 without missiles (dat a4d59922593fb779e00d4bfda34f5282, spr a7acc5b88b310fa6984960a1553c4501).
Output **pair 51 with missiles**: dat 603d31cdfca53e6a59d048fda262a8f5 (8,835,366 bytes), spr c4a23ac902a79dc0dd1307b7759ec409
(1,129,930,429 bytes, 945,525 sprites: 2,170 appended for the missiles, 353 for the two restored recolour source looks), the same counts of things (44,395 items, 3,360 outfits, 4,701 effects, 253 missiles).
- `check_pair.py` (full): 0 errors, 3,977 warnings (thing-empty 3,861 blanks, size-large 38, exact-size 63, missile-patterns 4 base ids, the rest as before).
  `gen_outfit_anchors.py` and `gen_info_lift.py` regenerated against this pair (`--check` passes); `gen_fx_send_offsets.py --check` passes. Not run in a client.
- **Archive parts** (windows-assets recipe: `tar --owner=0 --group=0 --numeric-owner --mtime='2026-10-22 00:00:00Z' --format=gnu` of
  Tibia.dat + Tibia.spr as `things-1098.tar`, `xz -9 -T3`, `split -b 95M -d -a 2` to `things-1098.tar.xz.partNN`; pushed to windows-assets as **d7abd80b** (first push 17f43b1d without looks 2104 and 2108)):
  - part00 99,614,720 bytes, sha256 `892d6b38cb3be597bac245791eafabf0aec9bc859da8f10bd02c66412b198a7a`
  - part01 28,999,336 bytes, sha256 `7127091c06456c4e658cb913498d2f64dc23f780091f6895be0784cfcb54ec93`
  - joined `things-1098.tar.xz` (128,614,056 bytes) sha256 `3c7ad78cdb379f7a49f2e31dda50ac37ee87638f03d55c101eb89f0b4ce6bca4`;
    `things-1098.tar` sha256 `3f18fb2b7553fc80797735338a5fa73a02c7aa2706086529fb19dd6de9c8fd9b`.
    Extracting gives the dat and spr md5 above.

### Pair 52: pair 51 with missiles plus the hunt roofs (`prune_pair.py restore`; built 2026-10-27)
Items 38477-38487 (rusty tin roof, server/README.md "Hunt roofs") were blank in pair 51. Pair 52 puts them back from the pair 51
archive pair; nothing else changes.
```
python3 -I client/tools/sprites/prune_pair.py restore --dat pair51r/Tibia.dat --spr pair51r/Tibia.spr \
    --archive-dat pair51/removed/Tibia.dat --archive-spr pair51/removed/Tibia.spr --ids item:38477-38487 --out-dir pair52
```
Input pair 51 with missiles (dat 603d31cdfca53e6a59d048fda262a8f5, spr c4a23ac902a79dc0dd1307b7759ec409).
Output **pair 52**: dat 7046ab6e35a08b2289699f95323fd506 (8,835,509 bytes), spr d12d3c2ee3a4f4c0424a4e0aa10f339d
(1,129,942,570 bytes, 945,534 sprites: 9 appended for the 11 roof pieces, which share records), the same counts of things (44,395 items, 3,360 outfits, 4,701 effects, 253 missiles).
- **Checked.** `check_pair.py` (full): 0 errors, 3,966 warnings (11 fewer than pair 51, the roofs are no longer `thing-empty`).
  Every dat entry other than the 11 is byte for byte the same as pair 51, and so are the 945,525 sprite records that pair 51 had. The 11 items
  draw the same records as in pair 50 (nonblank sprites per item 1, 1, 1, 1, 2, 2, 1, 1, 2, 2, 4). `gen_outfit_anchors.py` and
  `gen_info_lift.py` regenerated against pair 52 (only the dat md5 line changed; `--check` passes), `gen_fx_send_offsets.py --check` passes.
  Not run in a client. Ship the client with pair 52 and these two regenerated files together.
- **Tool change.** `prune_pair.py restore` wrote the spr twice (a copy, then a rewrite with the grown offset table), which needs
  about 2.3 GiB of free disk. It now writes the final file in one pass (head, grown table, old records, new records): same bytes, about 1.1 GiB.
- **Archive parts** (same recipe as pair 51; pushed to windows-assets as **1db4ab09**, parent d7abd80b, only the two part files and their lines of `SHA256SUMS.parts` changed):
  - part00 99,614,720 bytes, sha256 `efce22ec94e0affd6a600d062bd6c3ef837eee6aa3a8bbc34b3eb81cea838efd`
  - part01 29,008,688 bytes, sha256 `accbbabe723dec098884bde2682043770b85f6426154caec6c91c6447c1d6474`
  - joined `things-1098.tar.xz` (128,623,408 bytes) sha256 `e843f4be939e5358b17c320168e9aef71ba71d1bb47b7da29cb93e609d0dd5e1`;
    `things-1098.tar` sha256 `9d4d2245e34ae184cab0f07d569b1e66d0769b5e8d6bcc0f7a51d92d0599fcf3`.
    Extracting the parts gives the dat and spr md5 above (checked).

### Pair 53: pair 52 with two items redrawn in place (`redraw_items.py`; built 2026-10-27)
Owner request 2026-10-27 (O280): every reward chest wears one one-tile look, and the cursed chest gets a one-tile look too.
Pair 53 redraws two existing items; no id moves, no thing is added.
- **Item 38758 (server 32311), the reward chest.** Was the PixelLab one-tile look of pair 47 (candidate 15). Now a chest of a purchased
  prop sheet set (docs/CREDITS.md): the 64 px canvas file is cut out by alpha to 35 x 38 px and fitted
  to 32 x 32 by taking out the 6 rows and 3 columns that differ least from a neighbour (no resampling, no recolouring; `fit_front` in `gen_reward_chest_art.py`; the options tried are previewed in the git-ignored scratch folder, not committed). **The pixels are not in git**: `art_import/reward_chest_front.png` is git-ignored, and `art_import/reward_chest_front.csv`
  and `.sums` hold only the recipe and the sha256 sums. `build-front --check` (CI) checks them against themselves, and against the atlas when it is on disk.
- **Item 38642 (server 32281), the cursed chest.** Was look A, a 2 x 2 with a 5 phase loop. Now K3, a 32 x 32 PixelLab picture of ours
  (`art_import/cursed_chest/cursed_chest_k3.png`, committed): 1 x 1, one phase, no animation. `build-k3 --check` (CI) rebuilds the atlas,
  things file and sums from the committed source. Items 38643 / 38644 (server 32282 / 32283) stay in the pair for chests already on a map.
- **How.** `redraw_items.py` keeps the item's flag bytes, replaces its frame group with one 1 x 1 still and appends the sprite record
  (the offset table grows by 4 bytes per new sprite; the old sprites stay in the file, unused). Every other dat entry is byte for byte the same.
```
python3 -I client/tools/sprites/redraw_items.py --dat pair52/Tibia.dat --spr pair52/Tibia.spr --out-dir pair53 \
    --item 38758=client/tools/sprites/art_import/reward_chest_front.png --item 38642=client/tools/sprites/art_import/cursed_chest_k3.png
python3 -I client/tools/sprites/check_pair.py pair53/Tibia.dat pair53/Tibia.spr --old pair52/Tibia.dat pair52/Tibia.spr --allow-changed 'item:38758,38642'
python3 -I client/tools/sprites/gen_outfit_anchors.py pair53/Tibia.dat pair53/Tibia.spr
python3 -I client/tools/sprites/gen_info_lift.py pair53/Tibia.dat pair53/Tibia.spr
```
Input pair 52 (dat 7046ab6e35a08b2289699f95323fd506, spr d12d3c2ee3a4f4c0424a4e0aa10f339d).
Output **pair 53**: dat ed39f8452177e0ef503c97fd5f7df764 (8,835,386 bytes), spr 971ba1f67b7a07cd05a5416ad285ba0c
(1,129,950,436 bytes, 945,536 sprites: 2 appended), the same counts of things (44,395 items, 3,360 outfits, 4,701 effects, 253 missiles).
- **Checked.** `check_pair.py` against pair 52: 0 errors, 3,966 warnings (the same as pair 52); append-only: 52,610 old things and 945,534 old sprites
  compared, 2 allowed entry changes, 2 new sprites (ids 945,535 and 945,536). `redraw_items.py` verifies its own output (re-parse, flags, new sprites
  pixel-identical to the PNGs, 3,000 sampled old sprites unchanged). `gen_outfit_anchors.py` and `gen_info_lift.py` regenerated against pair 53
  (only the dat md5 line changed), `gen_fx_send_offsets.py --check` passes. Not run in a client. Ship the client with pair 53 and these two regenerated files together.
- **Archive parts** (same recipe as pair 52; pushed to windows-assets as **dbe0410a**, only the two part files and their lines of `SHA256SUMS.parts` changed):
  - part00 99,614,720 bytes, sha256 `ccf17e53f2832d2071ecec9110fa6b0871f6e8675d20204aab3646f999ac6250`
  - part01 29,009,040 bytes, sha256 `44959c5c33719fabffdd956b5ad1fbf761356be0f9eae2ae72d5929d24105355`
  - joined `things-1098.tar.xz` (128,623,760 bytes) sha256 `50668667915e2fa6373308ff1c4a021543a82a4fc612db43b496822d9f003e99`; `things-1098.tar` sha256 `8f8621f7a10613b52f47c132a587379add5c077d941e266b8e1e2783646620e5`.
    Extracting the parts gives the dat and spr md5 above (checked).


### Pair 54: pair 53 with three AutoSprite looks (`gen_autosprite_art.py`; built 2026-10-28, shipped inside pair 56)
Owner requests 2026-10-28: the owner's AutoSprite character "Verdant Eye Demon" in the game as the boss Vharzul the Verdant Eye,
then "mais 2 monstros ... pra hunt" that fit the game: the Ashbound Thrall and the Slagback Hound (server/README.md "AutoSprite
looks (pair 54)"). Three outfits are appended; nothing else changes.
- **Art.** Our AutoSprite characters (pixel art), each with AutoSprite's eight-direction walk (one render, 25 frames of 256 px per
  direction). `gen_autosprite_art.py` takes all eight directions (owner request 2026-10-28, O283: the looks have 8 x patterns, north,
  east, south, west, then north-east, south-east, south-west, north-west; client base patch 0160 draws the diagonals, a client
  without it the first four), shrinks each frame to the look's
  cell (block mean in premultiplied alpha, numpy only), moves each direction as a whole so the walk does not jitter (4x4: feet x 96,
  lowest row 125, where the 4x4 lions of pair 26 stand; 2x2: feet x 44, lowest row 62, where the 2x2 looks of pair 26 stand) and
  picks 8 walk phases evenly from the 25 (idle = frame 0). Every frame stands on the bottom tile row and every idle frame reaches
  the creature's own tile (a diagonal stride of the 4x4 demon leaves it in two walk frames). The four straight columns are the
  same pixels as the first build. The render's PNGs are pinned by md5 (`LOOKS`); they are not in git.
  Committed: `art_import/autosprite/<key>.png`, `art_import/autosprite.csv` (layers 1, patterns 8, idle 1 phase + walk 8 phases at
  100 ms; `import_art_things.py` takes outfit rows with patterns 4 or 8),
  `art_import/autosprite_sources.csv`, `monster_looks/autosprite_picks.csv`. `build --check` (CI) checks them against the spec.
  - 3361 `eye_demon`, 4x4: Vharzul the Verdant Eye (family `lairboss`).
  - 3362 `ashbound_thrall`, 2x2: the Ashbound Thrall (family `hunt`).
  - 3363 `slagback_hound`, 2x2: the Slagback Hound (family `hunt`).
```
python3 -I client/tools/sprites/gen_autosprite_art.py build --src RENDER_DIR      # RENDER_DIR/<key>/ the eight PNGs of FILES
python3 -I client/tools/sprites/import_art_things.py --ours-dat pair53/Tibia.dat --ours-spr pair53/Tibia.spr --out-dir pair54 \
    --things client/tools/sprites/art_import/autosprite.csv --first-item 44396 --first-outfit 3361 --expect-items 44395
python3 -I client/tools/sprites/check_pair.py pair54/Tibia.dat pair54/Tibia.spr --old pair53/Tibia.dat pair53/Tibia.spr
```
Input pair 53 (dat ed39f8452177e0ef503c97fd5f7df764, spr 971ba1f67b7a07cd05a5416ad285ba0c).
Output **pair 54** (8 directions; rebuilt 2026-10-28): dat bd8d87f8b4950e01e65ee1ed288c4998 (8,842,568 bytes), spr
222435122aba68d77f8a1772aa69ddf6 (1,131,883,560 bytes, 946,728 sprites: 1,192 appended), 44,395 items, 3,363 outfits.
- **Checked.** The importer: the output parses, 1,728 sprite slots pixel-identical to the art, every other thing byte-identical,
  3,000 sampled old sprites unchanged, append-only guard passed. `check_pair.py --old pair53`: 0 errors, 3,964 warnings (the same
  as pair 53; `outfit-directions` accepts 8). `gen_outfit_anchors.py` and `gen_info_lift.py` against pair 54 change only the dat
  md5 line (not committed yet: CI checks them against the pair on windows-assets). Not run in a client.
- **Archive parts** (same recipe as pair 53; built, never pushed: pair 56 holds pair 54 and went up instead):
  - part00 99,614,720 bytes, sha256 `2f0d08946c9a91db611e7931e9dd24c08cf8cb2734c0ab796885088f933adfcd`
  - part01 30,155,764 bytes, sha256 `5136b1ae07bbe2a1f553cc40fa53f88c3f511829345f47bec18ec090d8b246d3`
  - joined `things-1098.tar.xz` (129,770,484 bytes) sha256 `e0ec06cdf8834789ae2016993ee40a1666c0f78bdf297471fc1ff351198b23d2`;
    `things-1098.tar` sha256 `ec9bb5cbed28f3b0e9f0a472873d890b732be5a46cde581449ab7f668ece061a`.
- **To ship** (one change, after the push): `ChaosAutospriteArt.PAIR54 = true` (server/data/lib/chaos_autosprite_art.lua), the rows of
  `monster_looks/autosprite_picks.csv` appended to `picks.csv` and `server/tools/apply_monster_looks.py` run (looks 3361-3363 into
  the three files), `tools/ci/check_content.py` `PAIR_NAME, PAIR_OUTFITS` to pair 54 / 3363, `outfit_anchors.lua` and
  `info_lifts.lua` regenerated from pair 54. Until then the three wear stock looks and a client on pair 53 needs nothing new.

### Pair 55: pair 54 with the pickup looks, Ember portal and health / mana globes (`gen_portal_art.py`; built 2026-10-28, shipped inside pair 56)
Owner requests 2026-10-28: the Ember Blessing ground pickup (server 32090) wore the Ember Orb sprite (client id 25045); it gets a
violet arcane portal in a carved stone ring. Then the health and mana globes (server 32088 / 32089, they wore the stock potion
looks 7618 / 7620) get looks of their own (option 3 of the owner's pick). Three items are appended; nothing else changes. The Ember Orb
item (server 32258) keeps 25045.
- **Art.** Three PixelLab pictures, owner approved (32 x 32 RGBA, alpha 0 / 255). Pixels are PixelLab's: not repainted or snapped
  (only the colour under fully transparent pixels is cleared). `gen_portal_art.py build --src KEY=FILE` (repeatable) copies each to
  `art_import/portal/<key>.png`; committed too: `art_import/portal.png` (atlas, 96 x 32, three cells), `portal.csv` (things file),
  `portal.sums`, `portal_sources.csv` (credit: docs/CREDITS.md "Tools", PixelLab). `build --check` and `gen_portal_art_test.py` (CI)
  rebuild from the committed sources; each look passes `style_check.py` on its own colours (not snapped to a theme palette).
  - `ember_portal`: `create_image_pro` job 66b816c8-5244-4cc7-b765-b7903d98ba81, index 11 (a violet / magenta arcane rift in a stone
    ring, style reference the old ember sprite).
  - `health_globe`: job 453273cc-5c1c-4f4e-862d-4a30a4e27ef1, index 0 (a red glass globe on a dark base, style reference the portal).
  - `mana_globe`: the health globe with its red hues turned to blue, owner approved so both globes match: per pixel HLS, hue + 0.62
    where saturation > 0.25 and hue < 0.08 or > 0.9 (`recolour_blue`; the committed picture is within 1 per channel of it, the test checks).
- **Items**, each 1 x 1, one phase, flags `stackable` only (not copied from the stock looks: those are also multi-use and pickupable; the
  pickup nodes are stackable and neither pickupable nor moveable): **44396** ember portal, **44397** health globe, **44398** mana globe.
- **Server.** `pickups_config.lua`: ember `clientId = 44396`, `stockClientId = 25045`; health_globe `clientId = 44397`, `stockClientId = 7618`;
  mana_globe `clientId = 44398`, `stockClientId = 7620` (no stock node has those client ids: `install_pickups.py` copies the lowest stock
  node of the stock client id and writes the new one; an older node on the stock look is rewritten; a client id of another server id stops it),
  all `stackable = true`, ember glow `CONST_ME_PURPLEENERGY` (was `CONST_ME_FIREAREA`). Install `pickups` only with a client on pair 55 or newer.
```
python3 -I client/tools/sprites/gen_portal_art.py build [--src health_globe=pick3_hp.png --src mana_globe=pick3_mp.png] [--preview DIR --dat pair55/Tibia.dat --spr pair55/Tibia.spr]
python3 -I client/tools/sprites/import_art_things.py --ours-dat pair54/Tibia.dat --ours-spr pair54/Tibia.spr --out-dir pair55 \
    --things client/tools/sprites/art_import/portal.csv --first-item 44396 --expect-items 44395
python3 -I client/tools/sprites/check_pair.py pair55/Tibia.dat pair55/Tibia.spr --old pair54/Tibia.dat pair54/Tibia.spr
python3 -I client/tools/sprites/gen_outfit_anchors.py pair55/Tibia.dat pair55/Tibia.spr
python3 -I client/tools/sprites/gen_info_lift.py pair55/Tibia.dat pair55/Tibia.spr
```
Input pair 54 (dat bd8d87f8b4950e01e65ee1ed288c4998, spr 222435122aba68d77f8a1772aa69ddf6).
Output **pair 55**: dat 26670034d86dab36a59ecd955bb158c7 (8,842,607 bytes), spr c0b3de1122ca4db658915ca077ae9d6f
(1,131,891,475 bytes, 946,731 sprites: 3 appended), 44,398 items (3 appended), 3,363 outfits, 4,701 effects, 253 missiles. Built, not pushed yet.
- **Checked.** The importer: the output parses, the 3 sprite slots are pixel-identical to the art, every other thing byte-identical, 3,000
  sampled old sprites unchanged, append-only guard passed. `check_pair.py --old pair54`: 0 errors, 3,964 warnings (the same as pair 54).
  `gen_outfit_anchors.py` and `gen_info_lift.py` against pair 55 change only the dat md5 line (not committed yet, as for pair 54: CI checks
  them against the pair on windows-assets). `gen_fx_send_offsets.py --check`: up to date. Not run in a client.
- **Archive parts.** Not built: pair 56 holds pair 55 and went up instead (owner approved 2026-10-28).

### Pair 56: pair 55 with the Monk fist weapon looks and the 34 weapons above level 800 (`gen_fist2_art.py`, `gen_weapons800_art.py`; built 2026-10-28, on windows-assets 79be63dc)
Owner 2026-10-28 ("me mande fotos das armas do monk", approved all with "aprovo todas"): redraws of the six claws and the four
uniques of the Monk line, and three new fist weapons. 13 items are appended (client ids 44399-44411); then, owner 2026-10-28
("pode criar mais armas pros levels acima de 800"), 34 weapons above level 800 (client ids 44412-44445, below). 47 items in all; nothing else changes.
- **Art.** Thirteen PixelLab pictures, owner approved (32 x 32 RGBA, alpha 0 / 255), the top picks of the phase 1 sheets (the 8 x 8
  `create_image_pro` sheets re-cut over the cell seam; the job ids were not kept, the candidate set and tile number are in
  `art_import/fist2_sources.csv`). Pixels are PixelLab's: not repainted or snapped (only the colour under fully transparent
  pixels is cleared). `gen_fist2_art.py build --src KEY=FILE` (repeatable) copies each to `art_import/fist2/<key>.png`; committed
  too: `art_import/fist2.png` (atlas, 416 x 32, 13 cells), `fist2.csv` (things file, 1 x 1, one phase, flags `copy:3412` like
  `fist_weapons.csv`, mode new), `fist2.sums`, `fist2_sources.csv` (credit: docs/CREDITS.md "Tools", PixelLab). `build --check`
  and `gen_fist2_art_test.py` (CI) rebuild from the committed sources; each look passes `style_check.py` on its own colours (not
  snapped to a theme palette); two rules are waived, listed in `WAIVED` and printed: stormforged claws (8 one-pixel holes, max 6)
  and gravewind talons (27% near-black rim, min 30%). The generator is table driven (`LOOKS`, `NAME`): a later look set copies it.

  | Client id | Key | Item | Server id | Look (candidate set, tile) |
  |---|---|---|---|---|
  | 44399 | fist_c4 | pair of emberhide claws (800) | 40003 | scorched hide mitt, horn claws, lava seams (ember2, 27) |
  | 44400 | fist_c5 | pair of voidglass claws (1000) | 40004 | black glass shards, violet crystal (void2, 18) |
  | 44401 | fist_c6 | pair of stormforged claws (1250) | 40005 | blue steel gauntlet, yellow lightning (storm, 21) |
  | 44402 | fist_c7 | pair of wyrmbone claws (1500) | 40006 | ivory ribbed dragon-bone, fangs (wyrm, 4) |
  | 44403 | fist_c8 | pair of gravewrought claws (1800) | 40007 | moss-green grave iron, one big claw (grave, 33) |
  | 44404 | fist_c9 | pair of last-dawn claws (2200) | 40008 | white-gold gauntlet, golden claws (dawn, 21) |
  | 44405 | fist_u1 | vigil-knot wraps (14, unique) | 40009 | knotted linen, red sigil, candle flame (vigil, 12) |
  | 44406 | fist_u2 | chapel-iron knuckles (26, unique) | 40010 | iron knuckle-duster, white-gold cross (chapel2, 56) |
  | 44407 | fist_u3 | gravewind talons (1400, unique) | 40011 | bone-grey gauntlet, teal wind claws (gwind, 21) |
  | 44408 | fist_u4 | dawnless gauntlets (2000, unique) | 40012 | black plate, gold trim, eclipse ring (dawnless, 18) |
  | 44409 | fist_t6 | gravetooth cestus (750, new) | 48409 | grey-green iron cestus, bone teeth (cestus, 0) |
  | 44410 | fist_t7 | pair of hollowfang katars (950, new) | 48410 | two steel punch daggers, red edge (katar2, 0) |
  | 44411 | fist_t8 | wardenplate gauntlet (1150, new) | 48411 | teal steel gauntlet, bronze-bossed plate (war, 5) |
- **Server.** `server/data/items/fist_claws.csv`: rows 40003-40012 mode `repoint` (their server ids stay, the client ids move off the
  donor looks 28003-28012, which stay in the pair untouched), three new rows mode `new4` (server id = client id + 4000, the pair 50
  rule). `install_fist_weapons.py` writes the nodes (an older node on the donor look is rewritten), `install_donor_items.py` skips the
  repointed ids, `install_fist_weapons.py --lua` regenerates `chaos_fist_weapons.lua`. The `fistweapons` and `weapons800` steps
  wait for `config.lua` `chaosClientPair >= 56` (the client pair guard, server/README.md "Client pair guard"): until the owner
  records the pair they keep the claws on the donor looks and install none of the new items.
- **Weapons above level 800 (`gen_weapons800_art.py`, `art_import/weapons800*`).** 34 PixelLab pictures, owner approved the
  top picks of the phase 1 sheets on 2026-10-28 (32 x 32 RGBA, alpha 0 / 255, `create_image_pro` 8 x 8 sheets re-cut over the cell
  seam; candidate set and tile of each in `art_import/weapons800_sources.csv`; pixels not repainted, snapped or mirrored; the two-handed
  melee looks keep the grip bottom-left). Appended after the fist looks: client ids 44412-44445, server ids = client id + 4000
  (48412-48445, free: checked against every csv of `server/data/items`, the `chaos_*.lua` libs and the id tables of server/README.md).
  Committed: `art_import/weapons800/<key>.png` (sources), `weapons800.png` (atlas, 1088 x 32, 34 cells), `weapons800.csv` (things file,
  flags copied from the stock item of the kind as for the gear sets: sword 3264, axe 3274, club 3270, bow 3350, crossbow 3349,
  wand and rod 3066; `extra` = type, level, element, loot, description), `weapons800.sums`, `weapons800_sources.csv`.
  `build --check` and `gen_weapons800_art_test.py` (CI) rebuild from the committed sources; every look passes `style_check.py` on its
  own colours, one rule is waived and printed (`WAIVED`: mirrorbark staff, 28% near-black rim, min 30%). The server manifest
  `server/data/items/weapons800.csv` is the importer's `--manifest-out` of the things file with `--server-offset 4000`.

| Client id | Key | Item | Server id | Type, level, element |
|---|---|---|---|---|
| 44412 | w800_gravesong_bow | gravesong bow | 48412 | bow, 820, death |
| 44413 | w800_emberthorn_longbow | emberthorn longbow | 48413 | bow, 885, fire |
| 44414 | w800_hollowreed_recurve | hollowreed recurve | 48414 | bow, 950, earth |
| 44415 | w800_stormlace_bow | stormlace bow | 48415 | bow, 1120, energy |
| 44416 | w800_veilpiercer_bow | veilpiercer bow | 48416 | bow, 1235, holy |
| 44417 | w800_duskpetal_longbow | duskpetal longbow | 48417 | bow, 1420, earth |
| 44418 | w800_ashen_halo_bow | ashen halo bow | 48418 | bow, 1580, holy |
| 44419 | w800_throneseeker_bow | throneseeker bow | 48419 | bow, 1850, energy |
| 44420 | w800_last_ember_recurve | last-ember recurve | 48420 | bow, 2150, fire |
| 44421 | w800_bonehinge_arbalest | bonehinge arbalest | 48421 | crossbow, 840, death |
| 44422 | w800_cindergut_crossbow | cindergut crossbow | 48422 | crossbow, 930, fire |
| 44423 | w800_frostlatch_arbalest | frostlatch arbalest | 48423 | crossbow, 1150, ice |
| 44424 | w800_thornwarden_crossbow | thornwarden crossbow | 48424 | crossbow, 1480, earth |
| 44425 | w800_cinderbloom_wand | cinderbloom wand | 48425 | wand, 830, fire |
| 44426 | w800_mirewhisper_spire | mirewhisper spire | 48426 | wand, 890, earth |
| 44427 | w800_stormglass_scepter | stormglass scepter | 48427 | wand, 960, energy |
| 44428 | w800_hoarwick_wand | hoarwick wand | 48428 | wand, 1080, ice |
| 44429 | w800_sunscar_focus | sunscar focus | 48429 | wand, 1200, holy |
| 44430 | w800_thunderwake_scepter | thunderwake scepter | 48430 | wand, 1400, energy |
| 44431 | w800_emberveil_spire | emberveil spire | 48431 | wand, 1560, fire |
| 44432 | w800_rotcrown_wand | rotcrown wand | 48432 | wand, 1780, death |
| 44433 | w800_wyrmtongue_focus | wyrmtongue focus | 48433 | wand, 2100, energy |
| 44434 | w800_hushwood_rod | hushwood rod | 48434 | rod, 825, death |
| 44435 | w800_mirrorbark_staff | mirrorbark staff | 48435 | rod, 885, ice |
| 44436 | w800_dreamthorn_branch | dreamthorn branch | 48436 | rod, 955, earth |
| 44437 | w800_veilhollow_crook | veilhollow crook | 48437 | rod, 1100, death |
| 44438 | w800_glimmerbough_rod | glimmerbough rod | 48438 | rod, 1210, holy |
| 44439 | w800_gloamroot_staff | gloamroot staff | 48439 | rod, 1390, earth |
| 44440 | w800_wraithwillow_rod | wraithwillow rod | 48440 | rod, 1590, ice |
| 44441 | w800_nightbloom_crook | nightbloom crook | 48441 | rod, 1820, death |
| 44442 | w800_eventide_branch | eventide branch | 48442 | rod, 2080, holy |
| 44443 | w800_gravewrought_greatsword | gravewrought greatsword | 48443 | sword2, 850, death |
| 44444 | w800_ashmaw_greataxe | ashmaw greataxe | 48444 | axe2, 910, fire |
| 44445 | w800_dirgebell_maul | dirgebell maul | 48445 | club2, 975, holy |
- **Rebuild** (the steps are reproducible; later look sets append after client id 44445 the same way, `--first-item` the next id and
  `--expect-items` the last id of the pair before):
```
python3 -I client/tools/sprites/gen_fist2_art.py build [--src fist_c4=PICK.png ...] [--preview DIR --dat pair55/Tibia.dat --spr pair55/Tibia.spr]
python3 -I client/tools/sprites/import_art_things.py --ours-dat pair55/Tibia.dat --ours-spr pair55/Tibia.spr --out-dir pair56 \
    --things client/tools/sprites/art_import/fist2.csv --first-item 44399 --expect-items 44398
# then the 34 weapons above level 800, appended to that output (a different out-dir; the result is the final pair 56):
python3 -I client/tools/sprites/gen_weapons800_art.py build [--src KEY=FILE ...] [--preview DIR --dat pair56/Tibia.dat --spr pair56/Tibia.spr]
python3 -I client/tools/sprites/import_art_things.py --ours-dat pair56/Tibia.dat --ours-spr pair56/Tibia.spr --out-dir pair56final \
    --things client/tools/sprites/art_import/weapons800.csv --first-item 44412 --expect-items 44411 --server-offset 4000 \
    --manifest-out server/data/items/weapons800.csv
python3 -I client/tools/sprites/check_pair.py pair56final/Tibia.dat pair56final/Tibia.spr --old pair55/Tibia.dat pair55/Tibia.spr
python3 -I client/tools/sprites/gen_outfit_anchors.py --out /scratch/anch56.lua pair56final/Tibia.dat pair56final/Tibia.spr
python3 -I client/tools/sprites/gen_info_lift.py --out /scratch/lift56.lua pair56final/Tibia.dat pair56final/Tibia.spr
python3 -I client/tools/sprites/gen_fx_send_offsets.py --check
```
Input pair 55 (dat 26670034d86dab36a59ecd955bb158c7, spr c0b3de1122ca4db658915ca077ae9d6f).
Output after the fist looks (the first build of pair 56): dat ade572a4b128115ee41a1793dec130e9 (8,842,815 bytes), spr
4747b22003e4782d7901212be6e93e39 (1,131,917,248 bytes, 946,744 sprites: 13 appended), 44,411 items. Superseded by the final pair below.
Output **pair 56** (final, with the 34 weapons): dat cafd10c030c87eeab28ec4ca0e4806b8 (8,843,365 bytes), spr
875ead25023f579ba30e925f3d3b608d (1,131,969,510 bytes, 946,778 sprites: 47 appended to pair 55), 44,445 items (47 appended), 3,363
outfits, 4,701 effects, 253 missiles. Built, not pushed yet.
- **Checked.** The importer: the output parses, the 13 sprite slots are pixel-identical to the art, every other thing byte-identical,
  3,000 sampled old sprites unchanged, append-only guard passed. `check_pair.py --old pair55`: 0 errors, 3,964 warnings (the same as
  pair 55). `gen_outfit_anchors.py` and `gen_info_lift.py` against pair 56 change only the dat md5 line (written to the scratchpad,
  not committed, as for pairs 54 and 55). `gen_fx_send_offsets.py --check`: up to date. Rendered from the pair
  (`gen_fist2_art.py --preview`, `gen_weapons800_art.py --preview`): all 47 draw as in the tables. The second import (34 items, 34 sprites
  appended): output parses, the 34 slots are pixel-identical to the art, every other thing byte-identical, append-only guard passed;
  `check_pair.py --old pair55` again 0 errors and 3,964 warnings; `gen_fx_send_offsets.py --check` up to date. Not run in a client.
- **Archive parts** (same recipe as pair 53; owner approved 2026-10-28, pushed to windows-assets as **79be63dc**, only the two part
  files and their lines of `SHA256SUMS.parts` changed):
  - part00 99,614,720 bytes, sha256 `6d403b3f7c12a775432db340ddc78b497f4147f08713f36191d5f5c6bd10eed5`
  - part01 30,170,616 bytes, sha256 `f7e358eab54ed39b9d94c3a508400ff3f511c1ed490758a295d1d856ab0a35ae`
  - joined `things-1098.tar.xz` (129,785,336 bytes) sha256 `0241527e754920b6c93a168c4ca2f8bbc5f7feb5ba89ff6ba20e25ce13dbed33`;
    `things-1098.tar` sha256 `4e4b9d586c36566dc947bf0fd31bce5f7b08ef6ab8da7fafcd38b3f62e5cb58b`. Extracting the parts gives the dat and spr md5 above (checked).
- **Switched on** with the push: `ChaosAutospriteArt.PAIR54 = true`, the AutoSprite rows in `picks.csv` (looks 3361-3363 in the three
  monster files), `check_content.py` at pair 56 / 3363 outfits (blank set recounted), `outfit_anchors.lua` and `info_lifts.lua` from pair 56.
  Against pair 56: `check_pair.py` 0 errors, recolour, anchors, lifts, dungeon banners and site images pass. The pickups, fist weapons and
  weapons above 800 still wait for `chaosClientPair` 56 (server/README.md "Client pair guard"): record it once the client update is out.

## Owner art (things_custom26: outfits 2213-2233, items 33940-33985, `tools/sprites/gen_owner_art.py`, `art_import/owner_art.csv`; on windows-assets 50645056, switch on since 2026-10-15)
**Source and licence.** The owner's Google Drive folder "ots", files added 2026-10-15. The owner confirmed the art is
their own or commissioned and free to use for monsters and variants, outfits and wings as cosmetics, decoration and map
items. `gen_owner_art.py` names each file by a neutral name, its Drive file id and md5 (`SOURCES`); the Drive titles
are not copied. Not used: two .aseprite spell / aura effects (zombie hands, tentacles: effects, not an approved use),
the FX and aura zips, one duplicate sheet, and seven small files the download tool could not save (a fire medusa
sheet, three outfit sheets, a second moth wings sheet, two "filth" sheets).
- Monster looks 2213-2224 (layers 1, frame groups idle 1 phase + walk, 100 ms): four 4x4 lion beasts (128 px, 3 walk
  phases), two 2x2 drakes (3 walk phases), six 2x2 creatures with an 8-phase walk and an idle frame per direction.
  Server use: server/README.md "Owner art (pair 26)" (the four deep dungeon bosses and eight 1300-2000 hunt monsters).
- Wings 2225-2233 (3x3, one group, animateAlways): six feathered wings (9 phases, 110 ms; the sheets repeat the east
  column as the west one, so west is east mirrored about the wearer's axis), two ornate wings (8 phases, 120 ms,
  displacement -6,-12: the scan put their art 6 px left and 12 px above the other wings; re-centred per direction in
  pair 32, -12,-12: "Ornate wings re-centred"), moth wings (5 phases).
  `fix_pair_warnings.py --scan-aura-displacement --wings 2225-2233`: art centres x -19.6..-22.5, y -18.9..-21.3 px;
  the wings already in the pair (1486, 2140-2142, 2187) span x -14.5..-20.2, y -17.8..-22.5, so ours sit up to 2.3 px
  further left, which looks right in the previews.
- Items 33940-33985 (server 36940-36985, `server/data/items/owner_decor.csv`): 45 desert plants cut as blobs from one
  sheet, 2x2 each with the pot on the item's tile (27 block a tile: kind stump, `bottom notwalkable notmoveable`; 18
  do not: kind decor, `notmoveable`) and a 3x3 waypoint seal (60 phases at 100 ms, light 3 colour 35, walkable).
  New importer kind `decor` (otb group 0, no flags).
- `python3 -I gen_owner_art.py build --src DIR` writes `art_import/owner_art/*.png` (23 sheets, 3.4 MB),
  `art_import/owner_art.csv` and `monster_looks/owner_art_picks.csv`; `build --check` (CI) compares the committed sheets,
  things file and picks with the spec; `gen_owner_art_test.py` (CI) runs the pure parts on synthetic sheets;
  `preview --out DIR --dat P --spr S [--before-dat --before-spr]` draws each look on a tile floor (four directions, the
  walk, the monster's current look beside it), the wings on a player by the wings rule, and the decoration.
- Append to things_custom25:
  ```
  python3 -I client/tools/sprites/import_art_things.py --ours-dat things_custom25/Tibia.dat --ours-spr things_custom25/Tibia.spr \
      --out-dir things_custom26 --things client/tools/sprites/art_import/owner_art.csv --first-item 33940 --first-outfit 2213 \
      --expect-items 33939 --manifest-out server/data/items/owner_decor.csv
  python3 -I client/tools/sprites/check_pair.py things_custom26/Tibia.dat things_custom26/Tibia.spr --old things_custom25/Tibia.dat things_custom25/Tibia.spr
  ```
- Output **things_custom26** (2026-10-15; input the windows-assets archive at ebe1b2b2, dat dc1613e4..., spr d970b1cb...):
  dat 4a019fecaeb837a64c71f068bc243b14 (5,075,890 bytes), spr 800cd7cead2187257091b2f12e8ed547 (643,478,418 bytes,
  767,949 sprites: 3,603 appended), 33,985 items, 2,233 outfits, 673 effects, 153 missiles. Built twice with identical
  md5s and manifest; the importer verified 5,436 sprite slots pixel-identical to the art. `check_pair.py --old`:
  append-only (36,878 old things and 764,346 old sprites compared), 0 errors, 124 warnings, line for line those of
  things_custom25 (INFO `sprite-zero-slots` 4,064 -> 4,080).
- `things-1098.tar.xz` packed like things_custom25's: sha256 77e72d63611e27732342ca1d84339f62911509b1e482f99d28c9b3df47a7dbcf
  (74,109,736 bytes); it unpacks to the md5s above. Pushed to windows-assets at 50645056 (owner approved 2026-10-15).
- Published in one change (2026-10-15): `ChaosOwnerArt.PAIR26 = true` (server/data/lib/chaos_owner_art.lua), the rows
  of `monster_looks/owner_art_picks.csv` appended to `picks.csv` and `server/tools/apply_monster_looks.py` run (12
  monster files), `tools/ci/check_content.py --pair` names things_custom26 (2,233 outfits, no new blank outfit),
  `outfit_anchors.lua` regenerated from this pair, the dungeon banners of the Marrow Crypts, Iron Crucible, Fallen
  Sanctum and Pyre Throne drawn again with the new looks (`gen_dungeon_banners.py build`), the wiki data again (21 store
  wings). Server side: server/README.md "Owner art (pair 26)".
- Checked offline only (importer checks, check_pair, the previews). Not run in a live client. A client on pair 25 or
  older draws nothing for 2213-2233 and 33940-33985.

## Sprite style checker (new, `tools/sprites/style_check.py`, `tools/sprites/style_palettes.json`, docs/SPRITE_STYLE.md)
A style guide and an automatic check for new sprites, so they match the game. Measured only on art we may use as a
reference: the owner's seven gear set sheets (`art_import/gear_sets/`), the owner art of pair 26
(`art_import/owner_art/`) and our generated effects. No purchased pack and nothing else from the Drive is read until the
licence audit allows it.
- docs/SPRITE_STYLE.md: grid and anchors, the oblique view and the light (from the top, a little left: 94 degrees on
  the sheets), the outline (one pixel, near-black tinted toward the theme, 98% of the rim), the palette of each theme
  (56 to 87 colours, a fixed palette per sheet) with its ramps, shading, transparency (alpha 0 or 255), item
  silhouettes per slot, creature and wing frames, effect frame counts, a checklist and the import steps.
- `style_check.py check FILE... --theme NAME | --palette PAL [--cell 32] [--soft] [--key RRGGBB]`: cuts each PNG into
  cells and reports PASS or FAIL per image and the reasons per cell; exit 1 on any failure. Checks: size and grid,
  background (transparent or one clean key colour), upscaled art, semi-transparent pixels (`--soft`: none below alpha
  12), colour count, palette distance (CIE76 mean and far share), outline darkness and thickness, rim light against the
  theme's reference, lone pixels, specks, pinholes, luma spikes and speckle.
- `style_check.py snap IN OUT --theme NAME` moves every pixel to the nearest theme colour; `report` prints the measured
  facts of the guide.
- `style_palettes.json` is made by `build-palettes` from the seven sheets: palettes, outline colours, light vectors, the
  owners' ranges and the thresholds (each owner range with a margin). CI runs `build-palettes --check` and
  `style_check_test.py` (synthetic sprites pass or fail for the right reason; the seven sheets pass their own themes,
  the frost sheet fails the fire palette) with the pinned fx venv.

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
| | | `chaos-splash-20px` (outline + shadow, glyphs 32..255) | `splash` | the login "PRESS ANY KEY TO START" |
| | | `chaos-display-16px` (antialiased border + shadow, glyphs space..~) | `display` | the login scene's place name |
| Alegreya SC | AlegreyaSC-Bold.ttf (2.003) | `chaos-subtitle-16px` (shadow) | `subtitle` | Codex page title, the item on the crafting bench |
| | | `chaos-heading-14px` (shadow) | `heading` | Codex section headings, the NPC's name in the dialogue bubble |
| IM Fell English | IMFeENrm28P.ttf (3.00) | `chaos-dialogue-15px` | `dialogue` | what NPCs say in the dialogue bubble (`game_npctalk`) |
| Alegreya Sans | AlegreyaSans-Medium.ttf (2.004) | `chaos-body-13px`, `chaos-body-12px` | `body` (off) | trial body font: Codex paragraphs, only when switched on |
| | | `chaos-outline-11px` (antialiased border) | `outline`, `outlineSmall` | text straight over the game picture: the login scene's monster names, the modifier line over monsters (`game_monsterbar`) (the 12 px size, unused, was dropped 2026-10-14 for the splash's room) |

| PT Sans | PT_Sans-Web-Regular.ttf (2.003) | `chaos-ui-10px`, `chaos-ui-bold-9px`, `chaos-ui-rounded-8px` / `-10px` / `-11px` (hinted monochrome, pixel accents) | none: they replace stock fonts by name | `verdana-9px`, `verdana-9px-bold`, `verdana-9px-rounded`, `verdana-11px-rounded` (the main button and panel font), `verdana-11px-rounded-lowspace`, `verdana-8px-rounded` |

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

**pt-BR splash and glyph tails** (2026-10-14): the pt-BR login showed "APERTE Q UALQ UER TECLA PARA COMEAR". Two
causes. (1) The splash held glyphs space..Z only, so "Ç" was not drawn; it now holds 32..255 (a 512 slot; the room is
that of `chaos-outline-12px`, which nothing used: the `outline` role now names the 11 px font). `login.lua` upper-cases
with `ChaosLocaleCore.upper` (cp1252: "ç" -> "Ç"; Lua's `string.upper` leaves bytes over 127 alone). (2) The client
measures a glyph by its last painted column and draws nothing past it, so a Cinzel "Q" tail (8-9 px past its advance,
IM Fell's 11 px) became a gap after the Q. `make_fonts.py --max-overhang N` (default 1, the antialiased edge) cuts ink
further past the advance (`clip_width`); the cut glyphs are printed per sheet (Q q & and a few more). `--atlas-check`
on the assembled client: everything fits, no slot left. `make_fonts_test.py` checks every shipped sheet: each pt-BR
letter (á à â ã é ê í ó ô õ ú ü ç and capitals) drawn and advancing like its plain letter, Q about as wide as O.

**Stock UI fonts for pt-BR** (2026-10-14): six small stock fonts the base client and our UI draw with do not hold
the pt-BR letters: `verdana-9px`, `verdana-9px-bold` and `verdana-9px-rounded` are cp1250 sheets ("Português" drew
"Portugueş", "ã" "ă", "à" "ŕ", "õ" "ő": the login's top-right lines), `verdana-11px-rounded` (the buttons, 300+ uses)
and its `-lowspace` twin squash the accented capitals to lower-case height ("CRéDITOS", "OPçõES"), and
`verdana-8px-rounded` (action bar keys, notification timers) has its own glyph order past "~". The atlas has no room
for more fonts (`--atlas-check`: 100% used), so `make_ofl_fonts.sh` replaces them in place: an `.otfont` of the stock
file's name in `overlay/data/fonts/` (copied over the stock one, so the stock sheet is never loaded) with the stock
name, glyph cell, baseline row, height, y-offset, line advance and space width, and its own sheet
`chaos/chaos-ui-*.png` made from PT Sans Regular (OFL, google/fonts, `fonts-src/PTSans/`) in the same 256 slot. No
style, layout or text box changes; text is a few percent narrower or wider than before. `make_fonts.py` options for
it: `--mono` (hinted monochrome: crisp pixels like the stock sheets), `--pixel-accents` (grave, acute, circumflex,
tilde and diaeresis drawn as 2-row pixel marks one empty row above the plain letter; hinted 7 px capitals turn them
all into the same dash; ç keeps the font's cedilla), `--embolden 1` (a pixel bold: hinted bold at 9 px keeps 1 px
stems), `--cross-outline` (the stock "rounded" rim: side neighbours only), `--font-name`, `--otfont-out`, `--cell`,
`--baseline`, `--height`, `--y-offset`, `--line` (a stock font's geometry; ink outside the cell is cut and listed:
only the top row of the dark rim over the marks of the accented capitals of the 8/10 px rounded sheets) and
`--letter-spacing` (the lowspace font: the 11 px sheet with 1 px less spacing). The digit-only `verdana-cap-bold`
(item counts) stays stock; so does `Verdana Bold-11px-wheel`, which puts wheel icons on a few Latin-1 bytes (ú, Ü)
on purpose. `--atlas-check` on the assembled client: 34 fonts, everything fits, no slot left (as before). Tests
(`make_fonts_test.py`): `StockReplacements` (stock geometry, 256 slot, each pt-BR letter drawn and advancing like
its plain letter), `PixelAccents`. Run in the Linux client: the pt-BR login screen draws "Versão", "Idioma:
Português (Brasil)", "OPÇÕES", "CRÉDITOS" right; the English one keeps its layout. The login panels' English words
are base patch 0054 (`BASE.md`).

**Licence.** The OFL allows bundling the fonts and fonts made from them with the game (free or sold) if every copy
carries the copyright notice and the licence, the fonts are never sold by themselves and stay under the OFL. So
`data/fonts/chaos/OFL-<Family>.txt` (PT Sans included) ships with the client, the login screen's Credits box and the README name the
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
the display font (space..~: place and character names, ASCII; the whole range would need a 512 slot). Accented capitals reaching above a font's
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

## Phone data (new, `client_chaos_firststart`, base patch 0167, O313)

The Android client has no sprite pair in its APK. On first start it downloads the game data through the same signed
manifest as the desktop updater (docs/ANDROID_CLIENT.md section 3). Desktop clients are unchanged.

**Manifest key `android`.** `make_update_manifest.py build` writes it into the signed payload next to `files` (and `native`):
`{"version": 1, "files": [paths], "count": N, "bytes": B}`. `files` lists, sorted, every path of the update except
`layouts/mobile/` (the APK leaves that folder out on purpose) and the prefixes given with `--android-exclude` (desktop-only
art; none is set today). The paths refer to the `files` entries, so hashes and sizes stay under the same signature and
nothing is listed twice. `bytes` is the size of the distinct encrypted blobs (the download), `count` the number of paths.
`--no-android` leaves the section out. Old clients and the launcher ignore the key. `check_payload` (publisher) and
`firststart_core.lua androidEntries` (phone) apply the same rules: an object of version 1, a non-empty list of strings that
are files of the update, no duplicate, nothing under `layouts/mobile/`; the publisher also checks `count` and `bytes`.
A publish with no `data/things/*.dat` in the list warns.

**Flow.** `init.lua` Services.update (manifest URL and public key, set by `android-client.yml` with
`set_update_config.py`, same production defaults as the Windows package) gives the manifest. On Android:
1. `bootstrap.lua` calls `boot.lua`: a finished apply (`chaos_update/android_state.txt` `status=ok`) is mounted through
   `g_resources.mountDataFolder` in front of `data.zip`; a new APK removes the old APK's Lua and art in that folder first
   (data/things stays). `cleanup_boot.lua` keeps `chaos_update` on a phone. The desktop updater (`updater.lua`) is off.
2. After the module loads, `firststart.lua` fetches the manifest, checks the Ed25519 signature and the payload with the
   desktop code (`ChaosUpdateCore`), refuses a `min_package` above the APK's build ("A new client download is required"),
   takes the phone list and compares it with the phone: a file placed in the tree is compared by
   `chaos_update/android_index.txt` (path, SHA-256, size; no hashing of a gigabyte), any other by the SHA-256 of what the client
   sees (`data.zip`). A manifest older than the APK's baseline brings only `data/things` (the APK's Lua is newer).
3. Game data missing (no `data/things/1098/Tibia.dat`): a screen blocks the login. It shows the size of the download, a Wi-Fi
   advice, the free space against the need (the data plus 0.5 GB staging, less what is already staged) and a Download button;
   not enough space shows how much to free and a Retry. An update over 100 MB asks too; a smaller one starts by itself.
4. Download: `ChaosUpdateCore.download` (at most 4 parallel requests on a phone, 8 MB ranged parts, retries, blob and plaintext
   hash checks, finished parts kept). Pause cancels the requests and keeps what is on disk; Resume goes on. A failure shows
   Retry (and Play when the game data is already there).
5. Unpack: each verified blob goes through `g_resources.unpackUpdateBlob` into `chaos_update/android/<path>` (the GCM tag
   and the signed plaintext hash are checked, the file gets its name only when complete), the index line is appended, the
   staged blob is removed after its last path. State `applying` then `ok`; a stop in between resumes from the index.
6. `g_app.restart()` restarts through the Java shell; the next start mounts the folder.
Logcat lines start with `firststart:`; `firststart: screen shown (...)` is what the emulator smoke test of
`android-client.yml` waits for.

**Files.** `firststart_core.lua` (phone list, index, decide, summary, space check, phases, prune on a new APK, unpack; tests
`firststart_core_test.lua`, 219 checks), `boot.lua` (+ `boot_test.lua`, 42 checks, also runs `bootstrap.lua` on a fake phone and
a fake desktop), `firststart.lua` + `firststart.otui` (screen), `client_chaos_firststart.otmod`.

**Not checked.** Everything on a real phone: the download over a mobile network, the free-space call on Android, the PhysFS
mount of the folder, the unpack time of 1 GB on a phone, the restart helper.

## APK updater (new, base patch 0169, `client_chaos_firststart`, O313 step 8)

The Android client updates its own APK when the signed manifest says a newer one exists (docs/ANDROID_CLIENT.md section 4,
"Step 8 status"). Desktop clients and the launcher ignore all of it.

**Manifest key `android_apk`.** `{"version_code", "version_name", "min_version_code", "url", "sha256", "size", "signer_sha256"}`
in the signed payload, next to `android`. `version_code` 1 to 65535 is the APK versionCode, equal to the client build and to
`Services.update.package` of that APK. `version_name` is 1 to 32 characters of `A-Za-z0-9._+-`. `min_version_code` is 0 to
`version_code`: a phone with a package below it cannot play until it updates. `sha256` and `signer_sha256` are 64 lowercase
hex digits, the second the SHA-256 of the DER signing certificate. `size` is 1 byte to 1 GiB. `url` is exactly
`apk/<sha[:2]>/<sha>.apk`, relative to the manifest. Exactly these seven keys. `make_update_manifest.py check_apk` and
`firststart_core.lua apkEntry` apply the same rules; a broken entry is ignored by the phone (log line, no offer).

**Publisher.** `build --apk FILE --apk-info JSON [--apk-min-version-code N] [--no-apk]`; `set-apk PUBLISH_DIR (--apk ... |
--remove | --apk-min-version-code N)` changes only the entry of the published manifest and signs it again, same version and
files. The JSON is `CindersOfChaos-Android.json` of `android-client.yml`: `version_code`, `version_name`, `signer_sha256`, and
optional `sha256`, `size` and `min_version_code`; sha256 and size must match the file. The APK is published plain, because it
carries its own signature, under `apk/` of the publish folder; older APK files are removed. A publish without `--apk` keeps the
published entry while its file is intact. A lower version code than the published one, or the same code with another file, is
refused. `verify` checks the file. `server/deploy/publish_client_update.sh --apk android-31` and `chaos-ctl.sh publish-apk`.

**Screen** (`firststart_core.lua apkDecision`). Entry code above the running package: an offer ("New app version", Update app,
Later; Later goes on with the game data check). Required, with only Update app: the running package is below the entry's
`min_version_code`, or below the manifest's `min_package` and the entry reaches `min_package` (without a reaching entry the old
"A new client download is required" screen stays). Equal or lower: nothing. The status text of the shell
(`state TAB done TAB total TAB message`) is parsed by `parseApkStatus`: downloading, verifying, permission, installing, confirm,
failed (message is a code the screen turns into text: net, size, hash, signer, package, storage, aborted, blocked, other), done.

**Shell checks, in order.** Permission "install unknown apps" granted; size and SHA-256 of the download; the file is a package
of this app's name with a higher version code; exactly one signing certificate with the SHA-256 of `signer_sha256`; the
`PackageInstaller` session. `ApkFetcherTest` (plain JVM, `client/android/tests`) covers the download part.

**Files.** `firststart_core_test.lua` has 97 more checks for the entry, the decision, the url, the status text and the phases.
`make_update_manifest_test.py` class `AndroidApk`, `publish_client_update_test.py`, `chaos_ctl_test.py`.

**Not checked.** The Java installer on a real phone, the NDK build of `0169`, the permission page on each Android version.

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
  Since pair 37 (2026-10-22) both clients of `windows-package.yml` (Windows and Linux) ship the shard set inside
  `chaos.pack`, not the single file: pair 37's `Tibia.spr` is over 1 GiB, and the updater of every client build out
  (`updater_core.lua` `M.MAX_FILE_SIZE`, the same in `make_update_manifest.py`) refuses a whole manifest that lists a
  bigger file, so that limit can never grow for the builds already out. The workflow unpacks the pair beside the
  client tree, copies the dat, splits and verifies the spr into the tree, and moves the single `Tibia.spr` (with the
  dat) to the map editor only (`mapeditor\client`): it cannot read shards. This replaces the owner decision of
  2026-10-13 (single file in the Windows package for the map editor), whose reason the editor's own copy now covers.
  Shards inside the pack load like loose ones: 0048 opens them by PhysFS path, and the pack is a PhysFS memory mount
  (base patch 0102); the Linux start test of the workflow starts a packed, sharded client.
- **Loading**: the index wins over `Tibia.spr` when both are there; a broken set (missing or short shard, bad index)
  falls back to `Tibia.spr`. Measurements: client/BASE.md 0048 (load already took only milliseconds, since the engine
  streams sprite records; sharded it blocks for about 1.6 ms against 6.4 ms cold).
- **Updates**: `make_update_manifest.py` lists every shard as its own file and checks the set before publishing (index,
  sizes, headers, each shard's SHA-256 against the index). It refuses a shard set next to the single `Tibia.spr`
  (players would download both; `--with-single-spr` ships both on purpose) and a shard set without `--min-package`
  (a client built before 0048 ignores the shards and would draw a new dat with its old spr). It warns when it publishes
  a single `Tibia.spr` with no shard set: a client whose install has an index keeps loading its shards. A file over
  1 GiB is refused (a `.spr` with the hint to split it), and so is a file set over the engine's update overlay (one
  in-memory ZIP without ZIP64, base patch 0103: below 4 GiB). `server/deploy/publish_client_update.sh` always
  publishes shards: a single `data/things/*/<name>.spr` in the package is split and verified in its work folder (a
  broken one stops the publish), and one next to its shard set is left out.
- **Existing clients (build 14, pair 36 in the pack)**: the update of a sharded package lists `Tibia.sprshards` and
  the shards, not `Tibia.spr`. Their updater downloads the index and every shard (none is in their pack), mounts them
  in front of the pack, and 0048 loads the index before the pack's old single `Tibia.spr`, so they draw pair 37 with
  no new download of the client. The first sharded update is about the size of the spr once; after that a sprite
  change downloads only the shards that hold it. That needs a `min_package` they meet: the publish script's default
  is the package's own build (15), and then their updater (which now accepts the manifest) tells them to download
  the new client instead; `--min-package 14` lets them apply it, which is right only when the update's Lua needs
  nothing of the newer exe (an owner check per release). A manifest with a file over 1 GiB would instead be refused
  whole by their updater, so they would never even see the new-client message.

## Client pack (new, base patch 0102, `tools/pack_client.py`)

From build 13 the client ships the whole tree (`init.lua`, `data/` with the dat/spr, `layouts/`, `modules/`, `mods/`)
in one encrypted file, `chaos.pack`, beside the exe; nothing in the shipped folder opens in a text or sprite editor.
`tools/pack_client.py build GAME_DIR OUT.pack` makes it (pack format 2: deterministic store-only ZIP, compressed as
one zlib stream, then AES-256-GCM, key from the client guard secret via HKDF-SHA256; `unpack` / `verify` too), the
engine streams it through decrypt + inflate into one buffer of the ZIP's size and mounts it (base patch 0102), and
`tools/pack_client_test.py` + `tools/chaospack_test.cpp` check the format both ways in CI. Compressing before
encrypting keeps the download near the size of a plain zip. Full description,
removed-files list and owner steps: `client/BASE.md` "Client packs". The signed updater below is unchanged in shape:
it still lists and downloads individual logical files into the write-dir overlay, so an update never re-downloads the
whole pack.

## Slim client (new, `tools/slim_client.py`, `tools/slim_prune.txt`, 2026-10-21)

`assemble_client.sh` prunes the files of the assembled tree that nothing uses before the pack is built: the base
battle pass and ranked queue art, the base world minimaps (`data/default.otmm`, `data/minimap/minimap.otmm`), unused
boss bar and shader pictures, `hunting_places.json`, six base modules that are never loaded (`game_tutorial`,
`dev_otui`, `game_realcreaturebutton`, `game_healthbars`, `game_item_action`, `game_prey_hunting`) and the unit tests
and notes. 258.0 MB -> 84.6 MB without the sprite pair (173.4 MB, 402 files). Then `slim_client.py check` makes
every static file reference of the tree resolve (or be one of `tools/slim_known_missing.txt`), so the assembly, and
with it both client jobs of `windows-package.yml`, fails when a prune rule breaks a picture. Test:
`tools/slim_client_test.py` (CI). Groups, sizes, reasons: `client/BASE.md` "Slim client".

## Signed updater (new, `client_chaos_updater`, base patches 0031, 0101 and 0103)

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
Files are fetched by hash (`files/<xx>/<blob sha256>`) and each one's SHA-256 must match before it counts. The C++
helpers write only inside `chaos_update/` of the write dir (`chaosupdate::isSafeUpdatePath`).

**Encrypted files (build 13, base patch 0103; client/BASE.md "Encrypted updates").** Every file is published as one
AES-256-GCM blob (`tools/update_crypt.py`: magic `CHUB`, key = HKDF of the client guard secret `CHAOS_CLIENT_KEY` with
its own labels, nonce = HMAC of the content, so one file always gives one blob). The payload carries
`"encryption": "chaos-blob-1"` and per file `sha256` / `size` (plaintext) and `blob` / `blob_size` (the encrypted
bytes, 44 more); the client refuses a manifest without the marker. The Ed25519 signature covers both hashes: a download
counts only when its bytes hash to `blob` (transit) and `g_resources.updateBlobSha256` (the engine decrypts in 1 MB
blocks and checks the GCM tag) gives `sha256` (content). Downloads stay encrypted: staging and `chaos_update/files/`
hold only `CHUB` files; `bootstrap.lua` has the engine decrypt them into one in-memory ZIP mounted in front of the pack
(`g_resources.mountUpdateOverlay`). A tree file is compared with the manifest by its encrypted hash, a pack file by
its plain one. A file that does not decrypt at start (changed by hand) refuses the overlay: the client starts on the
pack and the updater removes the tree and fetches the update again. A plain tree of an older client (state without
`enc=chaos-blob-1`) is never mounted and is removed at the next check. The publisher refuses to run without
`CHAOS_CLIENT_KEY` (no plain fallback; `--dev` for tests uses the public development key) and needs `--min-package`
13 or more. The hash cache (`hashcache.txt`) now starts with a stamp of the client package and the applied update, so
a hash is never reused across packages (the pack's files all carry the same ZIP date).

**Never older than the package (baseline).** `Services.update.baseline` in `init.lua` (base patch 0101) is the update
version of the package's own files: the release number it was built as (`windows-package.yml` writes
`winpkg-N -> N` with `tools/set_update_config.py --baseline`). A manifest with a lower version is skipped ("Your client
is up to date", log `update N is older than this client package (B): not applied`), never applied: a package built
after an update went live has newer files than that update (winpkg-47 applied the live winpkg-46 files, 2026-10-21).
An equal version is compared as usual (the same files: nothing to download). The other side keeps the numbers in
step: `make_update_manifest.py build` publishes a package with a baseline as exactly that version (`--version` must
match) and `publish_client_update.sh` uses it (a tag of another number is refused), so the files of release N are
update N. A package without the field (built before 0101) keeps the old rule (`baseline` 0). The offline verdict
counts the baseline as an applied version against `min_version`.

**Off for test runs.** `CHAOS_UPDATE_OFF=1` in the environment (anything but empty or `0`): `bootstrap.lua` mounts no
update folder and `updater.lua` makes no request (log `updater: off (CHAOS_UPDATE_OFF is set)`). The package start test
in `windows-package.yml` sets it and checks that log line, so a package never depends on what the live server publishes.

**The game never downloads native code.** The in-game updater refuses native files. Binary (exe/DLL) updates used to
go only through the Windows package (`windows-package.yml`). Since 2026-10-29 the separate launcher ("Game launcher"
below) does that job on purpose (owner's call, O314). The old reasons are the risks the launcher has to meet: a
launcher that replaces the running exe is new native code that itself cannot be updated safely, Windows locks the
running exe and DLLs (swap logic and rollback on a half-written exe are where updaters brick installs), antivirus
tools flag self-replacing executables, and the signing key can now make every launcher PC run native code, not only
the Lua the client sandboxes to its modules (keep that key offline). An update that needs a new exe sets `min_package`: older packages show "A new client
download is required" (with `Services.update.download`) and cannot log in.

**Flow.**
1. `init.lua` (patch 0031) runs `bootstrap.lua` before `g_modules.discoverModules()`: when `chaos_update/state.txt` says
   `status=ok` for this client package (hash of `init.lua` and the build date/commit) with `enc=chaos-blob-1`, the
   encrypted `chaos_update/files` is decrypted into memory and mounted in front of the client's own files (base patch
   0103). A half-applied update (`status=applying`) or a tree made for another package
   is not mounted: the client starts with its own, consistent install files.
2. On the login screen (`autoload-priority` 1110, after `client_chaos_login`) a Chaos-styled panel over a dimmed screen
   blocks the login (`EnterGame.doLogin` is guarded) while it: fetches the manifest (`?t=` against caches), checks the
   signature and the payload, hashes the files the client sees (time-sliced, 12 ms per frame, with a cache of
   real dir + path, mtime and size in `chaos_update/hashcache.txt`), and decides per file: keep, download, or drop a stale
   tree copy that hides a right install file.
3. Download pool (`updater_core.lua` `M.download`): N requests at once (`parallel` in the manifest, default 8 since 2026-10-21, before 4; the client
   setting `chaos-update-parallel` wins, 1..8); one blob per distinct hash, largest first; a blob over 8 MB goes in
   8 MB `Range` parts that run in parallel too (the 570 MB `Tibia.spr` does not sit on one connection), each part a
   file `<sha>.c<i>`, so an interrupted run resumes with the parts it has; a server ignoring `Range` answers 200 with
   the whole file (up to 512 MB, the engine's body limit). Each request retries 5 times with backoff 0.5, 1, 2, 4,
   8 s; a blob's SHA-256 is checked as soon as its last part is on disk, then the SHA-256 of what it decrypts to; a
   mismatch deletes it and refetches it (5 tries), then the update is refused. Progress: files done / total, bytes done / total across all requests (parts
   in flight counted by their percent), speed, parallel count.
4. Apply only when every blob is in and verified: `state.txt` `status=applying`, stale and dropped tree files removed,
   staged blobs renamed into `chaos_update/files/<path>` (copied for a second path with the same content), then
   `status=ok` with the new version. Then the client restarts: on an exe with base patch 0101 (`g_app.canRestart()`)
   `g_app.restart()` asks for a relaunch and closes the client the normal way; `main()` starts it again after the
   whole runtime is shut down. On an older exe (`g_app.canRestart` missing; its restart left from inside the Lua call
   with `::exit` while the HTTP and async threads ran: `std::terminate`, abort 134 on Linux) the panel says "Close the
   client and start it again to load the update." with a "Close and start again" button (`g_app.exit`). Build-11
   clients run the Lua of their current files when an update is applied, so their first update after this change
   still calls the old restart (the update is already in place and loads at the next start); from then on the new
   `updater.lua` asks the player instead.
5. Fallback: server unreachable, or the update refused: "You can play with the current files" with Retry and Play,
   unless `Services.update.required`, a `min_version` above the applied version, or a `min_package` above this package.

**Files.** `updater_core.lua` (no client API: a linear JSON decoder (corelib's `json.decode` builds strings by
repeated concatenation and took minutes and gigabytes on the 0.8 MB manifest), paths, envelope, manifest, diff,
pool, apply, baseline, the `CHAOS_UPDATE_OFF` switch, the restart mode, the encryption fields, the plaintext check,
the hash cache stamp; `updater_core_test.lua`, 252 checks, LuaJIT and Lua 5.3, fake HTTP server, fake cipher and disk),
`bootstrap.lua`, `updater.lua` + `updater.otui` (panel),
`signature_vectors.lua` (`ChaosUpdater.selfTest()` runs them through `g_crypt` in the client).
Tools: `tools/make_update_manifest.py` (keygen / pubkey / build / verify / unpack; Ed25519 with `cryptography` when
installed, else `tools/ed25519_ref.py`, the RFC 8032 reference code; the blob encryption needs `cryptography`),
`tools/update_crypt.py` (the blob format), `tools/make_update_manifest_test.py` (also round trip, wrong key, determinism,
tamper, the fixed vector, key rotation, old plain blobs removed, unpacking a packed client), `tools/chaosupdate_test.cpp`
(native vectors), `tools/chaosblob_test.cpp` and `tools/chaosblob_mount_test.cpp` (the engine's blob format and the
overlay mounted by PhysFS), `tools/set_update_config.py` (writes `Services.update` into an assembled `init.lua`, `--baseline`
included; tested in `make_update_manifest_test.py`),
`tools/serve_updates.py` (local test server: ranges, per-connection rate, latency, dropped connections; tests only).
On the VPS: `server/deploy/publish_client_update.sh` / `chaos-ctl.sh publish-update winpkg-N` publishes a release's
client zip (docs/LAUNCH.md "Publishing a client update").
CI (`ci.yml`): the Python tests, an unsigned dry run over the overlay, the C++ vectors, the Lua tests;
`windows-package.yml` dry-runs the real package folder (dat/spr included).

**Tested in the Linux client before the encryption** (base patches 0001-0029 + 0031, 1280x720, `tools/serve_updates.py` over plain HTTP on
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

## Game launcher (O314, `launcher/`, `crates/selfupdate/`)

Owner, 2026-10-29: "vira e mexe eu preciso atualizar baixando de novo no site". Every release with a new engine patch
set `min_package`, and players downloaded the client again. The launcher is a small Rust program (egui window,
`CindersLauncher.exe`) that runs before the game, updates the exe, the DLLs and `chaos.pack`, and starts the game.
The in-game Lua updater stays for module-only updates. Release steps and open items: `launcher/README.md`.
Status: done in code and tests on Linux, not run on Windows.

**Trust.** The same envelope and key as the in-game updater: `manifest.json` `{format, key, signature, payload}`,
Ed25519 over the exact payload bytes, the public key from `launcher.json` (written from `Services.update.publicKey` by
`tools/set_launcher_config.py`). The launcher refuses a bad or missing signature, another key, another product, a
version below the package `baseline` or below the last one it applied, and every native entry that breaks the rules
below. It downloads nothing before the signature is good, and replaces nothing before every file hashed right.

**The `native` section.** A new key of the signed payload, built by `tools/make_update_manifest.py build
--native-dir DIR --native-package N [--native-game NAME] [--native-launcher NAME]`:
`"native": {"package": N, "game": "Chaos.exe", "launcher": "CindersLauncher.exe", "files_url": "native/",
"files": [{"path", "sha256", "size"}]}`. Paths are plain file names (no folder) ending in `.exe`, `.dll` or `.pack`,
at most 64 files of at most 2 GiB; `game` and `launcher` must be `.exe` files of the list. The files are plain blobs in
`updates/live/native/<sha[:2]>/<sha>` (the package ships the exe and DLLs plain; `chaos.pack` is already ciphertext).
**Old clients keep working:** their updater reads `files` and validates only the keys it knows, so `native` is ignored
(`updater_core.lua validateManifest`), `files` is byte for byte what it was without the section (test
`test_old_clients_see_the_same_files`), and the Lua path rules still refuse native names in `files`.
`publish_client_update.sh` adds the section by itself when the client zip holds `CindersLauncher.exe` (the exe, DLLs and
pack beside `chaos.pack`, `--native-package` = the package's `Services.update.package`); a package without the launcher
publishes no section and prunes the old native blobs. `verify` checks the native blobs too.

**Update.** Hash each native file of the install (cache by size and mtime), download the changed ones to
`.cinders_launcher/stage/` (resumable `Range` parts, 5 retries with backoff, the system `curl`), check size and SHA-256,
then the swap: a journal, the old file to `backup/`, the staged file in place (`.exe` last), the journal removed. Any
failure puts the old files back; a crash is undone from the journal at the next start. The launcher itself is staged as
`NAME.new` with a `.sha256` file and swapped in by a rename at its next start (old one kept as `NAME.old`).

**Package.** The client job of `windows-package.yml` builds the launcher (`cargo build --locked --release`, static C
runtime) and puts it in the client folder as `CindersLauncher.exe`; the separate client download gets `launcher.json`
before the pack is built; the full local package keeps `start-client.bat` and `Chaos.exe` (no live update site).
`windows-client.yml` (exe only) is unchanged.

**News and Changelog (owner request 2026-10-29).** Under the status and Play button the window has two tabs, "Notícias" /
"News" and "Changelog", from the website's launcher feed (`chaos_launcher_feed.php`, website/README.md "Launcher feed":
the site's news and the weekly patch notes, pt-BR and en, no second source). `launcher.json` gets the key `feed`
(`set_launcher_config.py` writes `https://<site>/chaos_launcher_feed.php` from the manifest's site; `--feed URL`,
`--no-feed`; an old file without the key derives the same address, or shows no panels). `src/feed.rs`: the system `curl`
with a short limit (5 s connect, 10 s, 128 KiB) on a thread of its own, so it never gates the update or Play; the last good
copy in `.cinders_launcher/feed.json` for an offline start; feed text shown as plain text (control and direction characters
out, counts and lengths capped); links open in the browser only when `https://` without spaces; a broken, missing or
oversize feed shows one short line, never a dialog. Texts in pt-BR and en in `i18n.rs` (`FeedText`). The window is 560x520.

**Tests.** `launcher/tests/mass_update.rs` (fake server on 127.0.0.1, fake install, the real `curl`): 120 rounds with
random trouble and a launcher update every few rounds, plus interrupted download (resume from the byte held), bad hash
(nothing installed, the good files kept staged), bad signature (no download at all), bad path, rollback at every swap
position, crash recovery, older manifest and baseline, unreachable server, launcher self-update, the feed (fresh, 404, server down, oversize, HTML, dead feed beside an update). `launcher/tests/vector.rs`
reads a manifest signed by the Python tool. Python: `make_update_manifest_test.py` (class `Native`),
`set_launcher_config_test.py`, `publish_client_update_test.py`; website `tests/chaos_launcher_feed_test.php`. CI: "Native checks" job, step "Game launcher (O314)".

**Open.** A code-signing certificate (antivirus and SmartScreen), the install path (the folder needs write rights; no
per-user installer yet), a run on Windows (renaming a loaded exe and DLL, `curl.exe`), no delta for `chaos.pack`.

## Display scale (new, `game_chaosscale`; server/README.md "Display scale", server src-patch 0037)
Every combat number a player sees is the internal number x the factor of the player's own level (x1 up to level 100,
x1000 at level 1000, x10000 from level 1500; a whole number). The server sends those numbers already scaled: the damage
and heal numbers above the map and in the Server Log, the own health (HUD plate, health info, top bar), the energy
shield bar, the DPS meter and combat log, the death recap, party frames (health), the hunt tracker, damage boards and the
bestiary's monster health. **Mana is never scaled** (owner 2026-10-21, server/README.md "Fixed spell costs", server
src-patch 0052): the own mana, the mana numbers, party members' mana, item mana rows and every spell's mana cost arrive
as they are, so a spell shows one fixed cost at every level. `game_chaosscale` keeps the factor (opcode 157) for the
modules that work numbers out themselves and no longer touches `SpellInfo` (until 2026-10-21 it multiplied every flat
cost by the factor: Colossus Fall read 400,000 at level 1000). The module is sandboxed and puts `ChaosScale`,
`chaosDisplayFactor()` and `chaosDisplayValue(n)` in `_G`. A client from before this change against the new server
still multiplies the action bar costs and greys out spells from level 153: ship the client update with the server.
- Item tooltips (`game_itemtooltip`): the server scales an item's flat health / damage / heal rows (not mana) by the factor
  of the item's level requirement and sends it as `ds`; the stats rows it scaled carry `sc`. The Ctrl compare view
  (`tooltiplogic.lua` `L.diff`, `L.toScale`) brings the worn item's `sc` rows to the hovered item's `ds` before taking
  the difference, so items of different levels compare by their real numbers (`tooltiplogic_test.lua`).
- Units: the short numbers of `client_chaos_numbers` already write k / M / B / T (2.6M, 4.29B; `numbers_test.lua` has the
  scale's range). The DPS meter (`dpsmath.lua` `DpsMath.short`) and the hunt tracker (`huntmath.lua` `HuntMath.short`)
  wrote "kk" / "kkk"; they now write M / B / T like every other number (73.4M, 4.2B).
- Checked in the Linux client against a live server (src-patches 0001-0037): at level 1000 "2.6M" / "1.8M" above the
  target, "A rat loses 2.6M hitpoints due to your attack." in the Server Log, health 15.9M, the DPS meter at 3.5M DPS; at
  level 100 the internal numbers (260, 180, health 2.47k); a lost level and a reattach brought the factor back.

## Localization (new, `client_chaos_locale`, base patch 0053, `tools/ci/check_locales.py`)
Every Chaos overlay text goes through `tr()`: `tr('English %s', x)` in Lua, `!text: tr('English')` (also `!tooltip:`,
`!placeholder:`) in OTUI. The key is the English text; `client_chaos_locale/pt_br.lua` maps it to Brazilian Portuguese
(UTF-8 in the file, turned into cp1252 at load by `locale_core.lua`; proper names of classes, spells, items, bosses,
orbs, systems and the top menu stay in English, as in the wiki's pt-BR guides). `client_chaos_locale`
(autoload-priority 5, not sandboxed, not reloadable) serves the global `tr` through a hook on `_G`'s metatable: our
table first, then the base client's own `tr` (its locale files translate the base windows), then the English; a
later `tr = f` (client_locales) becomes the base one. The language is `g_settings` `chaos-language` (`pt-BR` | `en`);
the first run takes pt-BR when the system locale is Portuguese (LANG / LC_ALL / LC_MESSAGES / LANGUAGE or the C
locale name, e.g. `Portuguese_Brazil.1252`), else English; the base client's locale follows (`setLocale` pt / en).
Where to choose: Options > Interface > Language (base patch 0053), the login screen (link under Background) and the
character list (button next to the account status), all `ChaosLocale.showMenu`. Out of the game a change reloads the
modules; in game new windows and the server messages switch at once and the rest at the next login. The language goes
to the server with the display scale hello (opcode 157, `{action = 'hello', lang}`) at every game start and at a change
(server/README.md "Server texts in pt-BR (Chaos.t)"). Pure helpers that tests load without the client carry a one-line
local `tr` that uses the global one when it exists and English otherwise. Run-time keys (`tr(row.name)` of a data
table) are listed at the end of `pt_br.lua`. The top menu entries, rarity names and board names stay English on
purpose (the guides use them). The bilingual donation notice (`payview.lua`) stays as it is.
Check: `python3 -I tools/ci/check_locales.py` fails on a `tr()` key without pt-BR, a translation whose % conversions
differ from its key, or a hard-coded UI text (an OTUI `text:` / `tooltip:` / `placeholder:` / `title:` value with
letters; a Lua literal given straight to `setText`, `setTooltip`, `setTitle`, `setPlaceholder`, `display*Box` or a
PopupMenu `addOption` without `tr()`); `--missing` prints the lines to fill in, `--stats` the coverage, `--fix FILE...`
wraps the hard-coded texts of these files. It also fails on `string.format('English ...')` that is not an argument of `tr()`
(a sentence built by format must be one `tr('... %d ...', n)` key); a line marked `-- i18n-ok` is exempt (not UI text).
Coverage: 3,327 literal keys in 4,115 `tr()` calls, all translated; 152
`tr()` with a run-time key. Not run in a client yet (no client build or server in the session).

## Look preview (new, `game_lookpreview`; owner: "show a simple character with the effect applied")

One panel, `LookPreviewPanel`, in every window where a look or a visual effect is picked: a dark stage with the
character drawn large on a `UICreature`, the zoom under it (always 2x for a look; an effect scene 2x, 1.5x or 1x),
`<` and `>` to turn, "Turn slowly" (one direction every 1.6 s), "Walk" (walking in place, `setStaticWalking`, as
the Outfit window's Movement box) and "Simple figure" (the plain figure, "boneco simples": citizen look 128 in greys,
no addons, mount, wings, aura or shader, so the effect reads on its own; off for a pet). The three boxes are one
setting for every panel (g_settings node `chaosLookPreview`). By default the character is the player's own outfit as
worn, with the row under the mouse applied, else the row picked.

**The effect is the engine's.** The option becomes outfit fields on the preview creature (look and addons, mount,
wings, aura, the outfit shader's name) or the outline call (`game_cosmeticfx.applyOutline`, base patch `0038`, which
draws on a widget's own preview creature), the same paths as the map. The feet stand where `CharSelectCore.figure` and
`placeRect` put them (the feet anchors of "Where a character stands"). A shader the client has not registered is left
off with a note (the engine would draw nothing). No pictures stand in for an effect: spell and kill effects are the
client's own effect sprites ("Cosmetics effect previews").

**Size and centring (owner beta report, 2026-10-20: "some outfit previews are still very big and off-centre", Prince
of Lands at 4x, cut and shifted left; "make them all the size of this one", Astral Fire at 2x).** Every look is drawn
at 2x and the box of everything the engine draws is centred in the stage (`LookPreviewCore.lookBox`, `layout`). The
old layout picked 4x / 3x / 2x from the figure's height and put the feet (`CharSelectCore.figure`) under the middle:
Prince of Lands (1221) is a low, wide look whose feet (x 17) are 11 sprite px right of its picture's centre (x -12 to
24), so at 4x it stood 44 px left and its bottom, 5 px below the feet, was cut. The box is per part, placed by the rules
of `Outfit::draw` (1098 profile, facing south): the pixel bounds of `CharSelectAnchors` (left, top, right; the bottom
5 px under its ground row) cut down to the tiles of the frame that hold a sprite for the addons worn (`ThingType:
getSprites`, displacement applied); a thing the table lacks by those tiles alone; the body, mount and aura 6 px up and
left of the wings (`GameWingOffset`); a positive mount's extra shift and the rider seated on it; a big aura's centring;
an aura with two layers (`GameAuraFrontAndBack`: the pair 33 head accessories and capes) by the tiles of both layers,
not the anchors (they measure layer 0 only; 2026-10-21, `lookpreview_core_test.lua`). Checked offline against the pixel bounds drawn by those rules from the pair 30 dat and spr (1221, 1213, 128, 2161 with
addons, mounts 1338 / 1236 / 901, wings 937 / 941 / 1185 / 1179): within 2 sprite px. The shadow is centred under
the feet, wider for a mount (60% of the body, 22 to 60 px), also under a mounted look.

**Mounts.** A look without a mounted pattern (pattern Z 1) rides standing, lifted onto the mount (base patch
`0088`, `client/BASE.md`), in the preview as on the map. The preview no longer swaps such a rider for the plain
figure (`LookPreviewCore.compose` keeps the optional `canRide` check for an engine without `0088`; the window passes
none).

**Wings.** The engine places wings the same way in the preview and on the map (one `Outfit::draw`; the UICreature only
scales the result): the body 6 px up and left of the wings, each part moved by its own displacement. The wings that
look out of place are so by their own data, on the map too: 1185 has displacement 8,8 where the other 2x2 wings have
0,0 and sits 12 px left and 7 px up of the body (the likely "Bride Wings to the left"); 941 and 938 are drawn at the waist; the 3x3 wings 1178
/ 1179 / 2141 reach 19-22 px above the body. Not changed here (a pair fix of the wings' displacement, as done for the
Scarlet Glimmer aura, needs the owner's approval of a new pair).

**Effect scenes (owner, 2026-10-20).** A spell skin plays on a scene: the player on the stage's tile facing east and a
troll (look 15) two tiles east facing west; a missile flies from the player to the troll, the other effects of a row
with a missile land on the troll, else an effect whose name says it hits (explosion, lightning, strike, bolt, ...) on
the troll and the others (war cries, novas, auras, portals) around the player (`LookPreviewCore.landsOn`: the server
sends no spell geometry with a skin). A kill effect plays on a troll alone: it stands 0.6 s, the effect plays on its
tile and it fades out in 0.35 s, then the loop starts again with it standing. The scene (both creatures' boxes and
every effect's tiles) is centred in the stage. "Compare with default" works in the spell scene as before.

**API** (`modules.game_lookpreview`): `create(placeholder)` fills a fixed column the window keeps for it and returns
a handle with `setOption(opt)`, `setHover(opt)` / `clearHover()`, `setOwnOutfit(outfit)`, `refresh()`, `destroy()`;
nil without the module. Options and their sources are in `lookpreview_core.lua` (`fromShopOffer`, `fromCosmeticRow`,
`fromOutfitButton`, `outfitWindowState`, `compose`, `layout`, `dockFixes`; `lookpreview_core_test.lua`, which also
checks the placement against `CharSelectCore` and the notes against pt_br.lua).

**Windows.**
- Outfit window (base `game_outfit`, no patch): when it opens, the module widens it by the panel's column and gives
  the children the widening moved their place back (right margins, in rounds until nothing moves), then follows what
  the window shows every 120 ms: its own preview creature, the row checked and the list button under the mouse or
  focused (outfits, mounts, auras, shaders). On the Mount row the window shows the mount alone; the panel seats the
  last look on it. Only the window's width and those margins are written.
- Cosmetics (930 x 480): outlines and the Collection's outfits, addons, mounts, wings, auras and shaders; spell skins
  and kill effects play their effects; a footprint walks the character east over four fading prints (the ground art
  the map uses). The small sample creature and the Collection's 72 px creature are gone. The glow picture of old
  engines is no longer shown in the window; such a client gets a note.
- Store (960 x 530): every look offer (outfit, addons, mount, wings, aura, shader; a pet drawn alone) on hover and
  once picked. None on the small mobile layout (500 x 380), where the column folds to nothing.
- Pets (870 x 470): the selected or hovered pet, alone.

**Not previewed, and why.** Transmog: an item look is drawn on the item (slots, the ground), never on the outfit, so a
character shows nothing of it; the Transmog window keeps its own item preview. Name plate frames and name shaders:
the engine draws names, plates and bars only on the map (`Creature::drawInformation`), not on a `UICreature`; the
name shaders module (`game_nameshaders`) is not wired to the server either. Item rarity outlines are an item's
outline (base patch `0044`), shown in the slots already. Level-up wings play by themselves and are not picked. The battle pass and season reward cells show rewards,
not a pick, and the character select's Create window has its own dais preview of the class look.

Not run in a client yet (no client build here): the core is tested, the windows' Lua and OTUI parse and pass the
module and locale checks.

## Cosmetics effect previews (`game_lookpreview` effect stage, `game_cosmetics`; owner 2026-10-16: "show what the effects look like")

The Spell Effects tab showed each skin by a store item a few pixels big, and the preview only a note. Now:

- **The stage plays the effects.** Each Cosmetics row of a spell skin or kill effect carries `play` from the server
  (`cosmetics_core.lua` `C.playRows`): one step per swap, `a` the stock effect, `b` the skin's, each `{id, dx, dy, ms,
  m, n}` (client id, the offset the server sends it at, its length, missile, icon name). The panel plays the steps one
  after the other (250 ms apart, 0.9 s pause, then again): an effect is its thing type's frames drawn tile by tile
  with `UISprite` widgets (no `UIMap`, no engine patch: `ThingType:getSprites`, the size, patterns and frames), placed
  as the map places it (bottom-right tile on the target tile + (dx, dy), each tile w x T left and h x T up, minus the
  displacement); a missile flies from the player to the troll of the scene ("Effect scenes" above) with the direction
  pattern the client would pick. Frame length: the server's `ms` / frames, else 100 ms a frame (the animator's own durations are
  not in Lua). The scale is the largest of 2x, 1.5x and 1x at which the scene fits the stage, so an effect
  keeps its size against the character as in the game (a 6 x 4 dome plays at 1x). "Compare with default" (shown when
  a row has stock effects) plays the stock effects first, captioned "Default effects", then "With this skin".
- **Draw order.** An effect that `g_map.isGroundEffect` reports (base patch `0055`), or that `game_groundfx`'s list
  holds when the engine has no such call, goes in the layer under the creature; every other effect and every missile
  over it, as the map draws them.
- **List icons.** The row's main effect (the longest non-missile skin effect): its fullest frame, cropped to its
  pixels and fitted into 32 x 32 (`images/fx/<type>_<name>.png`, made from the pair by
  `tools/sprites/gen_cosmetic_fx_icons.py --pair DIR`, 51 pictures from pair 28; `--check` compares). A missing picture
  falls back to the sprites: the fullest frame's non-empty tiles fitted into the box (`LookPreviewCore.iconLayout`).
  The detail shows the same at 64 px. Footprints show their print; outlines, loot labels and chat colours keep their
  swatch.
- **Other tabs.** Kill effects play on a troll that dies ("Effect scenes"); footprints walk the character over its prints; outlines
  are drawn on the preview character (`0038`); loot labels and chat colours keep their text samples in the detail.
- **Preview button** unchanged: spell skins and kill effects ask the server, which sends the effects to this player
  only around the character (1.5 s cooldown); footprints and outlines are drawn by `game_cosmeticfx`.

A mock of the panel was made from the pair 28 frames (GIFs, not in git). Not run in a client yet.

## Owned and locked lists (`game_unlocks`, base patch `0060`, server `wardrobe.lua`; owner 2026-10-16)

One rule (`unlocks_core.lua`) for every list where a look or cosmetic is picked: the Customise Character window's
outfits, mounts, auras, shaders and presets, and every Cosmetics tab (spell effects, kill effects, loot labels, chat
colours, footprints, outlines, the Collection).

- Everything the game has is listed. What the character does not own is greyed (45 % opacity), its tooltip says
  "Not unlocked yet. How to get it: <source>" (Store, Free, Class: <name>, Achievement: ..., Boss: ..., rare drop),
  and it cannot be used: Use (Cosmetics) and Ok (Outfit window) stay disabled while a locked entry is picked, and
  `accept()` sends nothing then. It can still be looked at in the preview. The server refuses anyway
  (`Game::playerChangeOutfit`, `cosmetics_core.lua` `C.choose`).
- "Only mine" hides the locked entries. One setting per character and list (g_settings node `chaosOnlyMine`).
- The Outfit window's packet lists only what is owned, so the rest comes from the server's wardrobe catalogue
  (`wardrobe.lua`, `wardrobe_core.lua`, `server/README.md` "Wardrobe catalogue"): asked on the cosmetics opcode 225
  (action `wardrobe`) at game start and each time the outfit window opens, answered in chunks
  (`Chaos.sendChunked`), merged on the client (`UnlocksCore.display`): the packet's entries stay as they are (owned),
  the others are appended as locked entries of the same shape. An entry the packet lacks is locked even when the
  catalogue says owned. The window redraws when the answer arrives (`game_outfit.onUnlocksChanged`).
- Cards (base patch `0060`): the look faces south and fills the card's picture part (108 x 80) at 3x, 2x, 1.5x or 1x,
  body centred (`LookPreviewCore.cardLayout`, `game_lookpreview.fitCard`).
- Not covered: wings (the 10.98 window has no wings row), familiars (10.98 has none; the row is the Shader row),
  name plate frames (the name plate window, not these lists).

Not run in a client yet: the cores are tested, the Lua and OTUI parse and pass the module, layout and locale checks,
and patch `0060` applies after `0001`-`0059`.

## Customise Character extras (`game_outfitextras`, base patches `0075`, `0090`; owner 2026-10-17, 2026-10-20)

The window showed outfit, mount, aura, shader and presets only. 2026-10-17 added a panel of dropdowns under the lower
panels; on 2026-10-20 the owner found the window bad and asked for every option inside Change Appearance, so the panel
is gone and each cosmetic is a row of Change Appearance, under Preset, in the style of the Aura and Preset rows (a radio
and a box with the current choice): Wings, Outline, Footprints, Kill effect, Loot label, Chat colour, Spell effect (the
skin of the character's class line), Plate frame (the name plate frame) and Pet.

- Selecting a row lists its choices in the right-hand area, where Outfit and Mount list theirs (a text list: most of
  these have no look to draw; wings show on the preview when picked). "Default / None" and the owned ones can be
  picked; the ones not owned follow `game_unlocks`: greyed out, their source in the tooltip, not selectable, hidden by
  "Only mine" (one setting per character and list, shared with Character > Cosmetics). The search box filters the list.
  The colour palette is covered while a cosmetic row is selected. A row whose data has not come yet is off.
- Changes are kept while the window is open and sent with Ok; Cancel throws them away.
- Sources: the cosmetics rows of `game_cosmetics` (`state`, asked for without opening that window with the action
  `state`, server `cosmetics.lua`), the pets of `game_pets` (`get`; the catalogue gives the locked ones), the Services
  state of `game_chaosinfo` (owned and shown frames, `services`; frames have no catalogue, so no locked ones), and the
  outfit packet's wing list (the wardrobe catalogue of `game_unlocks` gives the locked ones; wings travel with the
  outfit and are sent by `g_game.changeOutfit`). Choices go out the way the other windows send them: `select {kind, id,
  line}`, the command `plateframe <name | off>`, `summon {species}` / `dismiss`. No protocol change.
- Layout (`0090`): window 796 x 720 (it was 729 tall with the old panel, whose "Name plate frame" label was cut);
  preview 517 x 180; Configure 145 x 456 and Change Appearance 367 x 456 from y 214; value boxes at x 130; right-hand list
  240 x 585. Show Familiar is hidden on 10.98 (no familiars in the outfit packet; the server's "familiar" is a summon
  command), Show Floor takes its place. Aura, Shader and Show Aura stay: auras and shaders are sold on this server
  (`server/README.md`, `install_auras.py`, `0036-outfit-shader-storage`); they are greyed out while the character owns none.
- Base patch `0075` makes the guarded calls attach / refresh / apply / detach from `outfit.lua`; `0090` moves attach
  after the radio group and adds `rowKey`, `show`, `activeKey`, `leave` (with `addRow`, `prepareList`, `syncOnlyMine`
  in the attach context). The exports of the other modules are `getState` / `requestState` / `selectCosmetic`,
  `getState` / `requestState` / `summonSpecies`, `getServices` / `requestServices` / `usePlateFrame`. Rules:
  `outfitextrascore.lua` (`outfitextrascore_test.lua`).
- Not covered: familiars (10.98 has none), the "Collection" exclusives (not choices).

Not run in a client yet: the core is tested, the Lua and OTUI parse and pass the module and locale checks, and the full
patch chain to `0090` applies to the base archive. To check live: nothing cut at 796 x 720, the rows' radios switch the
right-hand list and back, a locked entry cannot be picked, Ok with only a cosmetic changed, wings on the preview.

## Owner debug items of 2026-10-17 (party invitation, floor items)

- **Party invitation window** (`game_partyframes`): the stock server's line "<Leader> has invited you to join his party."
  now opens a window (inviter, Accept, Decline; Enter / Esc). Accept joins by the leader's creature in view
  (`g_game.partyJoin` takes a creature id); a leader out of sight gets a message. The 10.98 protocol has no decline, so
  Decline only closes the window. A "has revoked" line, joining a party, 5 minutes and leaving the game close it.
  `PartyMath.inviterOf` / `revokerOf` / `findLeader` (`partymath_test.lua`). Check live: the exact wording of the
  server's invite line (the pattern is "<name> has invited you to ").
- **Floor items could not be dragged**: `game_groundlabels` connected a mouse press handler in front of the map's own and
  returned true for a press on a label, so `UIGameMap:onMousePress` never ran, `dragTile` stayed unset and
  `onDragEnter` refused (every item under a label). A left press now goes on to the map; the click is told from a drag on
  release (`GroundLabelsLogic.isDrag`, 4 pixels like the engine); the right button is unchanged. A pile's lower items
  still need the label click (the engine drags the top item).

## Client fixes of winpkg-35 (base patch 0056, `game_helperhud`, `game_chatpanel`, `game_chaosview`)

From the owner's test of release winpkg-35 (screenshots 14-31). Not run in a client yet: the cores are tested, the
Lua and OTUI parse and pass the module, layout and locale checks, and the patch chain applies to the base archive.

### Map zoom (`game_chaosview`)
The server sends a 17 x 13 tile area unless the client asks for more, and `game_interface` keeps the zoom (rows of
tiles) inside what it got: on a 2000 x 1340 window that was 11 rows, 122 px per tile. At game start the module asks for
the server's largest area (`g_game.changeMapAwareRange(29, 21)`, `protocolgame.cpp` updateAwareRange) and sets the zoom
to the character's saved one or a default of about 72 px per tile, 11 rows (the classic height) to 15 rows: 15 on
2000 x 1340. A zoom the player picks (Ctrl+= / Ctrl+-) is kept per character (client settings node `chaos_view`); a
window resize is not taken for a choice. `chaosview_logic.lua`, `chaosview_test.lua`.

### Chat panel (`game_chatpanel`)
- Place: the group life orb + chat + mana orb is centred in the game window by default and re-centred when the window
  or the side panels change. The grip on the chat's left edge moves it sideways (clamped to the room between the side
  panels); double-click on it, or a drag that ends within 8 px of the centre, makes it centred again. The splitter's
  left and right margins place it (`ChaosChatLogic.layout`); base patch `0065` hands game_interface's left margin to
  `ChaosChatPanel.relayout`.
- Width: the grip on the right edge (double-click: default width). The action bar shows fewer empty slots (width /
  36). Default 760 px, at least 420, never more than the room.
- Height: the base splitter above the action bars, minimum 96 px plus the action bars (was 118); a new character
  starts 40 px above the minimum, at most 55% of the window. Build 5 "the splitter does not work": the base splitter
  set its orientation only on hover and skipped that while another cursor was pushed (the width grip could leave one
  pushed), so the drag changed the right margin; fixed in `0065`, and the grips pop their cursor once.
- Orbs (`game_shaderfx`): children of the game root panel anchored to the chat's edges (life past the move grip, mana
  past the width grip, `ChaosChatLogic.orbMargins`), bottom-aligned with the chat, so they follow a resize or a move.
  On a window too narrow for orbs and a 420 px chat they are hidden; with orbs on, the group also keeps off the side
  action bars (an orb is taller than a small chat).
- Width, height and place kept per character (client settings node `chaos_chatpanel`).
- Enter / Shift+Enter (`ChaosChatLogic.enterAction`, read by `game_console`): an empty line closes the chat in "Chat
  On" and "Chat On*" and walking works again; with text it sends, "Chat On*" closes after.
- `chatpanel_logic.lua`, `chatpanel_test.lua`.

### Helper onboarding (`game_helperrotation/onboarding.lua`, owner design 2026-10-16)

A new character starts at level 8 in Cinderhold (no tutorial island). Its welcome toast (`game_chaosnotify`, action
`newplayer`) carries `openHelper = true` and a hint: `ChaosHelperOnboarding.open` opens the Helper window
(`modules.game_helper.toggle`, only when it is hidden), adds the Auto setup button and blinks it gold for 12 s with the
hint above it; a click on it ends the blink and runs Auto setup as usual. Nothing is set up without the click. Pure
helpers `O.plan` / `O.blinkFrames`, `onboarding_test.lua`. Server side: `newplayer.lua` `NP.showWelcome`,
`newplayer_config.lua` `welcome.helper`.

### Helper spell lists (`game_helper/spellinfo_logic.lua`, O311)
The helper's spell pickers (shooter slots, healing rows, mana training, haste) list a spell as `Name   120 mana | AOE circle 3 | 4 s`
(mana or its share of the maximum, single target / AOE with the shape and size / self, cooldown) and show the whole data in a
tooltip: mana, target (`Area (circle 3)`, shapes circle, around, line, wave `3x3`), cooldown, group cooldown, range, level,
element, kind. The tooltip is on each popup row, on the closed box (the chosen spell) and on the slot icon. The closed box keeps
the plain name (it is 170 wide); `helper.lua` `decoratePopup` widens the combo box's own popup after it opens and sets each row's
text and tooltip. A field the spell entry lacks (a stock spell has no shape or element) is left out without a word.
`spellinfo_logic.lua` (`ChaosHelperSpellInfo`: `compact`, `lines`, `tooltip`, `optionText`, `area`) is pure Lua with `tr` passed in;
`spellinfo_logic_test.lua` covers single target, every shape, missing fields, pt-BR and every spell of `spelldata.lua`.
Data: `gen_spell_data.py` writes `areaShape` (single, self, circle, around, wave, line), `areaSize` (radius, length or depth),
`areaWidth` (a wave's tiles across) and `element` per spell, from the attack kit (`attack_kit_config.lua`), the Spellbook's area
rows (`spellbook_areas_config.lua`), the area the spell script creates and its damage type; `game_chaosspells/chaosspells.lua` copies
them into the spell entries. The popup is as wide as its widest row (text width plus 24, kept on the screen). Not run live.

### Helper Auto setup (`game_helperrotation/autosetup.lua`, `autosetup_ui.lua`)
The "Auto setup" button sits in the top row of the helper window (`autoSetupHost`). One click,
for the character's class and level (`ChaosAutoSetup.plan`, tested per class in `autosetup_test.lua`):
- Healing: the class heals (`ChaosAutoRotation.heals`) at 80 %, 60 / 80 or 50 / 65 / 80 (the strongest lowest); the
  best health potion at 50 % and mana potion at 40 % (Mystic and Necromancer lines) or 30 %. A potion counts when the
  class may drink it at its level (the server's potion lists, docs/CLASSES.md) and the character carries it; else
  the Health / Mana Potion, the look of the Everfull potions every character has.
- Tools: eat food on (the Everfull Ration counts), the best haste it can cast kept up (Haste; Strong Haste was retired).
  The helper has no auto-loot switch (the loot list is `game_autoloot`, per item), so Auto setup leaves loot alone.
- Shooter: the class rotation, the same as Auto rotation (which stays on the Targeting tab), and the targeting
  (owner 2026-10-22, `ChaosAutoSetup.TARGETING`): Target Monsters "*", Auto Target on, Always Chase Opponent off,
  Follow Friend off with no name, Enable Shooter on, Disable in Protect Zone on. Written into the helper's config,
  redrawn at once (the loader's boxes, the target list input, the shortcut buttons) and saved, so a relog shows it
  (`helperconfig_test.lua` keeps it through the check on load). Undo puts the old targeting back.
- Timers: the class's fight buffs on their cooldown (the longer of the spell's cooldown and its effect, + 1 s), out of
  protection zones and while attacking, now chosen from the spell data (`ChaosHelperSupport.autoPlan`, see "Helper
  Support spells") instead of a hand-written list of one to three per class: Red Frenzy, Lightward, Ironbark Hide,
  Poison Blades, Bushido Focus, Counter Stance, Zealotry, Mantra of Stone, Iron Bellow, Rebuke, Hall of Mirrors,
  Banner Call, Tautstring, Ironhold, and the stock Blood Rage, for the lines that have them. Limit
  `TIMER_MAX` = 6 rules (the old list never went past three; it is the largest fight-buff kit of a line). The timer
  rules do not wait for the server's answer and all support spells share one group cooldown (2 s) on the server, so the
  first casts are staggered `TIMER_STAGGER_MS` = 2.5 s apart (the first at once) and the rest follow their own
  cooldowns. The timer switch is turned on when there are rules.
- Support spells: the rest of the class's support spells (a shield, the summons, the Vigil of Clarity ...) fill the
  Support spells tab, up to `SUPPORT_MAX` = 8 rows, and the tab is switched on. Every class gets the vigil (from level 35)
  and Soulward (from level 80); the Bone Lord, the Necromancer line, the Illusionist and the Beastmaster get their minions too.
  Hastes stay in Tools; spells that cost health, need a shield, a party or a typed name, and the 2 h avatars are left
  out (they can be picked by hand in the tab where the data allows).
Spells pass the same check as Auto rotation (class, level, learned). Where the player has set something of their own
(healing slots, another haste, own shooter rules, own timer rules, own Support spells rows) one question covers the whole setup: Add (their
settings stay, the empty slots and missing buffs are filled) / Replace / Cancel. Undo, in the result box or by
right-click on the button, puts every tab back. The timer rules it wrote are remembered by their words (client settings
node `chaos_helper_autosetup`), so a later Auto setup replaces them without asking. No base patch: the helper's own
tables and functions are used.

### Helper assembly check (`tools/ci/check_assembled.py`, 2026-10-24)
`assemble_client.sh` ends with `check_assembled.py <out>`: no two modules of one name (the engine merges them and `/mods`, read last, overwrites `/modules`) and `game_helper` is only `modules/game_helper/game_helper.otmod`, the overlay's. A fresh assembly passes. An installed client updated over an old pack keeps the pack's `mods/game_helper` (the updater cannot hide pack files): install a full new package. Test: `check_assembled_test.py` (CI).

### Helper Support spells (`game_helpersupport`: `supportspells.lua`, `supportspells_ui.lua`, `supportspells.otui`)
Owner, 2026-10-18: "O auto setup coloca poucas magias no timer. Acho que seria bom a gente ter um espaço no helper só
pra spells de suporte pra serem castadas off the CD." The helper's Timer is blind (it sends the words when a fixed time
has passed) and only holds what Auto setup put there, so the helper gets a **Support** tab (right of Settings in its tab
bar; the panel sits where the Timer panel does). No base patch: the tab button and the panel are created once the helper
window exists (polled every second, like the Auto setup button), and any other helper tab hides the panel again.
- The list: up to 8 rows, each a dropdown of the support spells the character can cast, a switch and a status text
  (Casting, On, On cooldown, Not enough mana, Waits for a fight ...). The first row that may go out goes first. Beside
  the list: a switch for the whole tab, the mana reserve (dropdown 0 to 50 %, default 20 %: a spell is cast only if that
  share of the maximum mana is left after it) and the buttons Fill for my class (adds what Auto setup would) and Clear
  list. Saved per character in the client settings node `chaos_helper_support` (`{enabled, reserve, slots}`), like the
  other helper additions; Auto setup fills it (Undo restores it).
- What may stand in the list comes from the spell data, not from a class list (`ChaosHelperSupport.eligible`): a
  support spell (group 3 without the attack group 1) with no typed name and no target, on the server, and not a utility
  (stock light, rope, food, find, challenge ... by words, the stock words and their Chaos words from
  `ChaosSpellNames`, e.g. Lantern "vael lyss", Ghost Rope "ash gor"; a saved list loses those rows at load,
  `H.dropUtilities`; the teleport home, Detonate Mines, Flickerdash and Mistborne
  Step by id). A support spell added to the data later shows up in the dropdown by itself, and Auto setup takes it
  (unless its cooldown is over 30 min). `ChaosHelperSupport.KINDS` (by spell id) only says how to treat the known ones:
  `auto` (`timer`, `support` or `false`), `kind` (buff, shield, summon, switch, party), `fight` (only while attacking a
  monster), `dur` (seconds the effect lasts) and `bar` (the buff bar's name when it is not the spell's name).
- The cast (`supportspells_ui.lua` every 250 ms, `ChaosHelperSupport.pick`): nothing while offline, the helper's
  automatic functions are off, in a protection zone, or the attack rotation charges a cast-time spell
  (`ChaosHelperRotation.channeling` / `game_castbar`). Per row: the spell's and its group's cooldown
  (`_Helper.isSpellOnCooldown`, the server's cooldown packets), level and mana (`ChaosHelperRotation.castable`), the
  mana reserve, the pending / back-off bookkeeping of a cast the server did not answer (`ChaosHelperRotation.blockedWhy`
  and `cast`, so a refused spell backs off 2 / 4 / 8 / 16 s and the rotation sees the group held), a rate guard of the
  support channel (`ChaosHelperTimers.castAllowed`, 3 a second, the same words not within 0.5 s), a pause of 2.5 s after
  a cast (6 s for a vigil) for the answer, and 10 s between two casts of a summon. One cast per turn; summons and
  Banner of Bones only while attacking a monster.
- "Buff not active": `game_buffbar` now exports `activeBuffs()` (the lowercase names of the buffs on the character, from
  the server's list; `nil` while the list has not come, e.g. with the Buff Bar hidden, which then does not ask the
  server). A buff is skipped while the bar shows a buff of the spell's name (the class buffs and the vigils carry their
  spell's name; Ward of the Mind is "Magic Shield" there). The bar's "not shown" counts only for a buff it has shown
  before (`seen`); otherwise (no bar data, or a spell the server's bar does not list: a summon, Hunter's Instinct,
  Smoke Bomb, a stock buff listed as "Spell Buff") the spell's own `dur` since our last cast stands in, else at least
  `RECAST_MIN_MS` (60 s) or its cooldown if longer. A vigil is a switch (a second cast turns it off) and needs bar
  data, else it is not cast; one the bar has not shown after our cast is not cast again within that gap. Only one
  vigil is set up by Auto setup (Clarity).
- Fix of 2026-10-24 (owner, O156): Auto setup still planned Greater Lantern, Ghost Rope and Lantern. The client's spell
  table is a map name -> entry whose entries often have no `name`, so the name check saw nothing. `S.entries` gives
  every entry its name (the key), `S.isUtility` is the one classifier of Auto setup, the dropdown, the cast and the
  helper's pickers, Auto setup plans no utility and no unnamed spell, and `setSlots` drops utilities.
- Fixes of 2026-10-22 (owner): (1) light, rope and the other stock utilities went into Support by themselves: the
  client says them in their Chaos words, which the stock word list missed (above). (2) "after dying the list is gone":
  every buff drops at death, which read as the player switching the vigils off, so their rows were unticked and
  saved. While the character is dead the tab casts and tracks nothing (`S.reset`), and a switch-off unticks its row
  only once it is `USEROFF_CONFIRM_MS` (2 s) old.
- Fixes of 2026-10-20 (owner beta): (1) "the Support tab does not open": `U.init` imported `supportspells.otui` while
  the module loads (autoload priority 100), before `client_styles` (loaded with `client`) defines `Panel`, `Label`,
  `CheckBox`, `ComboBox`, `Button`. The import stopped at `ChaosSupportRow < Panel`, so only `ChaosSupportTab <
  UIButton` existed: the tab was made, `createWidget('ChaosSupportPanel')` gave nil, and every later poll saw the tab
  and returned, so the click found no panel. The styles are now imported by the poll once `Panel` exists, the tab is
  made only together with its panel (a tab left without one is replaced), the helper refits its tab buttons
  (`onHelperViewportChange`) so the new tab lies inside the bar, and the tab's base style sets `border-color`.
  (2) "Support keeps casting nonstop, the cloud all the time": Wild Bond went out every 10 s and Bone Golem every 30 s
  (a recast with them out calls them back and heals them, with its effect), and any spell the bar does not list was
  cast whenever it came off cooldown. Now the rule above, Bone Golem / Wild Bond count their creatures (`minions`,
  `keep`: 1 golem; 1 companion, 2 from level 400), and a spell the server refused `REFUSE_LIMIT` (3) times in a row
  (ChaosHelperRotation's unanswered casts, base patch `0052`: the module uses the same pending / back-off) rests 30 s
  after the last try. `supportspells_ui_test.lua` checks the tab against a mock helper window and style table.
- Fix of 2026-10-22 (player report: "Vigil of Clarity turns itself on with the Helper off; turning it off does not
  help, it comes back right away; the Timer tab shows nothing"): Auto setup puts Clarity in this Support tab, not in the
  Timer, and the tab casts while the helper's automatic functions are on, whatever the Timer or the shooter show. A
  vigil the player switched off by hand (the bar showed it on, then off, with no cast of ours settling) was cast again on
  the next turn. Now `active()` reads that change (`st.barOn`, `st.userOff`), the row's status is "You switched it off",
  and `ChaosHelperSupport.takeUserOff` unticks the row; the glue saves it (no recast after a relog either) and the status
  line says to tick the row to let the helper keep the vigil on. A vigil the player switches on again clears the mark.
  Tests in `supportspells_test.lua` (switched off by hand, unticked once, still off later, on again, our own cast's bar
  lag within the settle time is not a hand switch, no bar data reads nothing).
- Capped summons (2026-10-18): the Necromancer line has a total cap of summons (3 for the Necromancer, 1 Lich, 6 / 7 Bone Lord);
  the next summon kills the oldest, so a summon spell marked `capped` in `KINDS` (Raise Dead 180, Raise Bone Warrior 192, Archer
  193, Mage 176) is cast only while the character has fewer summons than `ChaosHelperSupport.summonCap(vocation, level)`, and one
  with a `minion` name (the three new ones) only while none of that name is out: Auto setup builds a mixed army. The UI counts
  the creatures whose `getMasterId()` is the player (`ctx.summonCount`, `ctx.summonCap`); without a count nothing is cast
  (status "Cannot count summons"). Row statuses `full` ("Summons at the limit"), `have` ("Already out"), `nocount`. Needs a live
  check that `getMasterId()` is set for own summons on 10.98.
- Tests: `supportspells_test.lua` (eligibility on the generated spell data, the plan per class, the limits, the saved list,
  every refusal reason of the cycle, the recast gap, the counted summons, the refusal rest), `supportspells_ui_test.lua`
  (the tab and its panel against the load order of the styles, open / close, a tab left without its panel), `autosetup_test.lua` (the plan's timer and support lists), `buffmath_test.lua`
  (`activeNames`). Needs a live check: the tab in the helper window (button position, panel size at 960 x 580, the
  dropdown contents per class, the buff names the server sends against the spell names), the cast cycle against the
  server, Auto setup's staggered timer casts.
- Fix of 2026-10-27 (owner, "continua limpando a lista de magias de support quando o personagem morre"; the third
  report after 2026-10-22 and 2026-10-24). **Root cause**: a death in this client is a fast relog (`game_playerdeath`
  Ok -> logout and login), and the state of the cast cycle is made new at both. The death's mark (`st.clearAt`, 2026-10-24)
  lived in that state, so after the login nothing told `H.takeUserOff` that the buffs going and coming back are not the
  player's: one vigil that dropped from the bar a few seconds into the new session (two or more in one tick were
  already ignored) was read as a hand switch-off, unticked and saved. **Fix**: `H.noteClear(st, now, graceMs)` also
  sets `st.graceUntil`; `onGameStart`, `onDeath` and the dead tick note `H.SESSION_GRACE_MS` (10 s), a teleport the
  old 2 s. A bar drop inside the grace makes no mark and a mark inside it is dropped. The saved list is also checked
  against the spell table (`U.prune`: retired spells, utilities) only once the table is non-empty, and again at every
  tick until it ran; `ChaosAutoRotation.classKeeps` makes the class-change cleanup (`dropOldClass`) keep a spell the
  client does not know yet and cut nothing while the class id is 0. Lists are filtered at use time everywhere else
  (the pickers keep the saved id, `canCastFor` only gates the cast). Tests: `supportspells_test.lua` (a relog after a
  death), `supportspells_ui_test.lua` (empty table, then the full one), `autorotation_test.lua` (`classKeeps`).

### Helper settings survive death (`game_helperrotation/helpersave.lua`, base patch `0067`)
Owner: the helper's settings reset when the character died. The helper unblocked its saves at the end of every UI
reload (`onLoadHelperData`), whether its `helper.json` had been read or not, and a file it could not read (missing,
cut short when the client is closed on the death screen, not JSON) gave defaults that the next save wrote over it.
Now (`ChaosHelperSave`, tested with a death and relogin in `helpersave_test.lua`):
- a save is allowed only after this character's file was read; login, logout and character change block saves until
  then (`canSave`);
- a write goes through a checked `.tmp`, the last good file is kept as `.bak`; a broken file is read from `.bak` /
  `.tmp`, or kept aside as `.broken` before defaults may be saved;
- `saveSettings` is debounced (500 ms, the last change wins); death (`g_game.onDeath`), logout and unload write at once.
- Auto-update and Auto setup state (client settings nodes) are written to disk at once (`g_settings.save`).
- Auto rotation no longer treats the login's first level packet (old level 0) as a level-up.

### Helper settings checked on load (`game_helperrotation/helperconfig.lua`, 2026-10-21)
Players can edit the files the helper reads: the per-character `helper.json` and `config.otml` (`g_settings`). A
hand-edited value could drive the automation out of range (a 0 s timer rule casting every tick, a 1000 % heal
threshold, 500 rows, a text where a number belongs). `ChaosHelperConfig` (pure, `helperconfig_test.lua`, 127 checks,
LuaJIT and Lua 5.3) checks what is read, before the helper uses it:
- `helper.json`: `ChaosHelperSave.read` (the helper's reader since base patch 0067) runs `ChaosHelperConfig.sanitizeHelper`
  on what it decoded (a failing check never loses the file). Every number that drives the automation is a whole
  number clamped to the range of the helper's own control: heal / potion / training / food / vocation-heal / named sio
  percents (0..100, 1..100 or 1..99), potion priority 0..2, vocation priority 1..5, food priority 1..4, stamina
  minutes 0..2520, target mode 1..8, magic shooter mana percent 0..100 and creatures 1..10, equip conditions 0..100 (%)
  or 0..10,000,000 (points) with their resource / operator / logic / action from the dropdowns' lists, timer rule
  cooldown 1..86400 in `sec` / `min` / `hr`; ids 0..1,000,000. Wrong types fall back to the helper's defaults; rows are
  capped at 10, rules at 100, profiles at 50; rules of an unknown type are dropped; fields it does not know stay. The
  helper's own fill-in of missing fields still runs after it.
- `config.otml` nodes of the overlay: Auto rotation's `chaos_helper_spells` (`ChaosHelperConfig.spellPrefs`: a boolean
  and up to 500 whole spell ids), Auto setup's `chaos_helper_autosetup` (`autosetupWords`: up to 64 non-empty words of
  at most 128 characters), Support spells' `chaos_helper_support` (`supportspells.lua` `sanitize`, now also whole ids
  only); a node that is not a table is treated as empty. The updater's `chaos-update-parallel` (1..8) also refuses
  NaN.
- Settings of options the compact Helper window (base patch `0105`) dropped are cleared from an old `helper.json`
  (`HC.DROPPED`: `paralyzeCure`, `autoQuillSell`, `autoQuillSellBelowCap`, `autoQuillSellCapacity`, `quiverRefill`;
  `HC.DROPPED_FIELDS`: `magicShield.exanaEnabled` / `exanaHpPercent`, `botHud.showCavebot` / `showWaypoints`), so
  an old save still loads and nothing acts on them.

### Compact Helper window (base patch `0105`, owner request 2026-10-22)
The Helper window is 936x540 (was 960x580): narrower sidebar, lower tab bar with smaller icons (the Support tab of
`game_helpersupport` matches: 114x32, 28 px icon), a smaller profile box, gold sidebar headings. Removed because
nothing on this server uses them: Cure Paralyze, Auto Sell Loot (Summon Quill), Quiver Refill, Exana Vita, the Full
Dust alarm, the bot HUD's Cavebot and Waypoint rows (the HUD's "Sell loot" text went with them). Auto Stamina and
Magic Shield share the Tools tab's top box; Magic Shield shows only for a class with Ward of the Mind. The sidebar,
Tools, Settings and Alarm Settings texts have pt-BR and fit their widgets in both languages. `client/BASE.md` 69c.
Base patch `0106` puts the other tabs and sub-windows through `tr()` as well (264 pt-BR entries; `client/BASE.md` 69d).

### Helper and the Everfull tiers (`game_helperrotation/everfullheld.lua`, `game_helper/helper_potions.lua`, O246)
The Everfull upgrades (server 32261-32267) show under the great, ultimate and supreme potions' looks, so the helper could not
tell which Everfull a character carries, and its Health / Mana Potion rows (266 / 268, also what Auto setup set for the
Everfull) stopped reaching the flask after an upgrade. The server now tells the client (extended opcode 116, `held`, per slot:
the stock look the carried Everfull shows under, tier, level, line health / mana / spirit, `ready` when the charges a drink needs
are there; server `potions_helper.lua`, `server/README.md` "The helper and the tiers (O246)"). `ChaosEverfullHeld`
(`everfullheld.lua`, not sandboxed, `everfullheld_test.lua`) keeps the cleaned view and asks `sync` at game start.
`ChaosHelperPotions.EVERFULL_ITEMS` is the one table of the Everfull (server id, look, slot, line, kind, tier, level; the test
reads the server's config and compares): a row on the Health / Mana Potion look drinks the carried Everfull's look
(`P.resolve`: only a plain flask of the slot, ready, within the level); a row on any other look keeps its look, and the server's
engine (patch 0043) already prefers the Everfull of that look, the spirit flasks included. Auto setup counts the carried
Everfull as carried (`S.potion` with `held`). When the Everfull get looks of their own, change `look` in that table.
Auto setup (`autosetup.lua`) picks a carried Everfull from the held message and from the open containers (own looks), asking `sync` first when no message has come (`E.received()`, `E.ask()`); `P.sortOptions` sorts the helper's potion and rune dropdowns alphabetically.

### Helper potions in closed backpacks (`game_helperrotation/potiongate.lua`, base patch `0070`)
The Everfull potions (server 32085 / 32086) have the client look of the Health / Mana Potion (266 / 268), so the
helper's potion slots, the item picker and the use by id treat them as those; the bound lock (custom attribute 3 = 2)
is not checked by the helper. The blocker was the count: on this server the client counts only equipped items and
open containers, and the helper used a potion only with a count above 0, so a potion in a closed backpack (where the
Everfull ones usually sit) was never used. `ChaosPotionGate` allows a probe every 3 s for an uncounted potion and waits
30 s when the server answers "Sorry, not possible."; `potiongate_test.lua`. Server side the use by id of look 266 / 268
finds the Everfull potions only with server patch `0043`.

Runes (base patch `0082`, 2026-10-20: "o helper nao esta usando runas"): the same count blocked them. The magic shooter's
rune branch and Auto UH used a rune only with a count above 0, so a rune in a closed backpack was never used.
`ChaosPotionGate.canUse(id, count, now)` / `noteUse(id, count, now)` (shared session, `reset()`) gate runes like potions:
a probe every 3 s for an uncounted rune, 30 s back-off after "Sorry, not possible."; a counted rune is used as before.
Tests in `potiongate_test.lua`.

Fix of 2026-10-20 (owner beta, client build 9: "the helper stopped using the potion", a Ranger at 21 mana with the
log "[helper] spell 16 held 6.1 s: backoff (refused 6 times in a row ...)"). The gate backed off every probe of the
last 1.5 s at the first failure-like text, and its texts included "you do not have", the start of the server's "You do
not have enough mana." The health check sends the heal spell and the potion probe in the same tick; with the mana gone
the server refused the spell, and each refusal put the Everfull health and mana potions on a 30 s wait, so no potion
went out while the character ran dry. Now: "You do not have ..." is not a failure (only "Sorry, not possible." and
"You cannot use this object.", the answers of a use by id that finds nothing); the answers are matched to the probes in
the order they were sent; a failure waits `SETTLE_MS` (500 ms) and is taken back when the probe's own "Using ..." (the
server's hotkey message, "Using an everfull mana potion (never runs out).") follows; and an item whose probe answered
"Using ..." is used like a counted one (no 3 s probe wait) until a probe of it fails. The gate is reset at logout. Not
from the 0052 rotation back-off (it holds spells only), base patch `0086` (death) or the Support changes (no potion
code). No base patch: `helper.lua` calls the gate's same `allowed` / `used` / `canUse` / `noteUse`.

### Horizontal panels (`game_sidepanelfit`)

Owner report: with Options > Interface > "Show Right Horizontal Panel" on, the right column showed the map view, the
inventory, a gap of about 300 px where the map shows through, then the Skills window. Cause: the base gives a shown
horizontal panel a fixed height (200, or the saved `contentHeight`) whatever it holds. Base patch `0077` only paints the
panel `alpha` in the extended view, so an empty panel was a tall transparent gap and the side panels sat below it. The
left panel does the same.

`game_sidepanelfit` checks both panels every 250 ms in game. No shown child: height 0. A window is being dragged: an
empty panel opens as an 80 px strip so a window can still be dropped in. A window arrives: the last height the panel had
with a window (default 200) and the normal white panel image. The size the player sets is remembered and never
changed. Switching the option off is still the base's (height 0, windows moved out); on again, an empty panel closes at
the next check, so there is no gap either way. Other modules that anchor to the panels (`game_goals`) see ordinary
geometry changes. Rules in `sidepanelfit_logic.lua`, tested by `sidepanelfit_logic_test.lua` (luajit and lua5.3).
Update, no rebuild. Not run in a client: in a client, switch the option on with nothing in the panel (no gap), drag a
window into the strip, close it again.

### Minimap after a death (`game_minimapsync`, base patch `0096`)
Owner beta report 2026-10-20 ("O mapa ainda some do nada depois de morrer"), with the owner's answers: after the
character dies and respawns in the temple the whole minimap window ("Map View", the base `game_minimap`) is gone (no
window, no centre button; walking does not bring it back; no full map view or expanded minimap at the death); a
logout and login brings it back. A death in this client is a fast relog: Ok in the death window (`game_playerdeath`)
calls `CharacterList.doLogin`, whose `LoginEvent:tryLogin` logs out (`safeLogout`) and logs in again at once,
without the character list; the engine ends the game (`onGameEnd`) and starts it again.
At every login `game_interface.onPlayerLoad` (from `game_sidebars`) closes every side panel window that is not
primordial (the minimap is not) and reopens the saved ones, in order, in one `addEvent` through each module's
`move`; the minimap is always in the saved layout (`onPlayerUnload` keeps it even when closed) and `game_minimap`
puts it in the rightmost side panel, the last one restored. Those `move` calls had no error isolation: one failing
window ended the event and every window after it stayed closed. That matches the report: closed for that session, and
the next logout saves it again (as a closed `miniMap` entry) so the next login's restore opens it. Base patch `0096`
restores each window in a `pcall` and logs `[game_interface] restoring window <n> (<type>) failed: <error>`. Which
window failed in the owner's client after a death is not known (no client log; not reproduced), so this is the most
likely cause read from the code, not a seen one; the warning names it in the next beta log.
`game_minimapsync` puts the window back whatever closed it. It remembers the window (shown or not, its panel, place
and height) at the death and at the end of a session; when the map of the new session is known (`g_game.onMapKnown`,
then again at 0.4, 1.2 and 3 s, after the layout restore, the minimap's expansion restore and `game_chaoslayout`) a
window that was open and is now closed or in no shown side panel goes back to its panel (or the rightmost one) through
`game_minimap.move`, the call the layout restore uses, and logs `[minimapsync] minimap window ... back in <panel>`.
Once the window is seen open, or after the last pass, it is left alone (a close by the player stays). The same
passes and every teleport put the camera and cross on the character's tile and close a full map view left from the
last session. The explored map is never cleaned or reloaded (`g_minimap`, `minimap.otmm`).
`MinimapSyncLogic` (`minimapsync_logic.lua`: `remember`, `pickPanel`, `plan`), `minimapsync_logic_test.lua`.
Not run in a client.

### Window layout per character (`game_chaoslayout`)
The base client's `UIMiniWindow:setup` restores from a global `MiniWindows` node that no module writes (and skips it
past 50 entries), so the layout was never kept. Now per character (world/name, client settings node `chaos_layout`):
side panel miniwindows (panel and side, order, height, collapsed, open, locked) and the side panel count; the
position of Spellbook, Cosmetics, Info & Services, Leaderboards, Bank, Loot Bag, Loot Filter and Auto Seller (the size
too for a window with a resize border; these are fixed-size), clamped to the game window. Restored 0.8 s after login;
a window created later is placed when it appears. Saved within a second of a change, never before the restore (a
fresh login's defaults never replace it); logout and death need no save of their own. Owner beta 2026-10-24 (panels closed after a death, only the minimap and the
equipment stayed; O173): a layout is written only when two 1 s checks agree (`L.settle`), saving freezes 15 s from
`g_game.onDeath` (`L.freeze`), two more passes at 2.0 s and 4.5 s after login open again every window saved as open
that is hidden (`L.reopenIds`; a window the player closes in the first 4.5 s is opened once more), saving waits for the
last pass (`L.hold` / `L.release`), and the last layout written is also kept in memory. The cause in the stock client
is assumed, not seen (base tree not in the repo). Container windows are not kept
(their ids are slots). The chat panel's size and place are kept by `game_chatpanel`; the orb size is a client option
(all characters). `layout_logic.lua`, `layout_test.lua`. Not tried in a client run.

### Helper item slots (`game_helperrotation/itempicker.lua`)
A click on a helper slot that takes an item (Healing: potions; Tools: quiver ammo, special food, stamina; Timers;
Shooter runes; Equipment; supply alarm) switches to the target ("+") cursor like "Use with": `ChaosItemPicker.begin`
sets the grabber cursor (`g_mouse.setGrabber`, the system cursor) and pushes the software one, `finish` undoes both
once. Right-click or Escape cancels (nothing picked, the helper window comes back). Spell slots open the spell list,
not a pick. Base patch `0066`; `itempicker_test.lua`.
Base patch `0083` (`corelib/mouse.lua`, `cursorowner_test.lua`): with the system cursor, `applyNativeCursor` / `restoreNativeCursor` keep the cursor of the active grabber, so the target "+" of Use with and of this picker is not replaced by the resize arrow of a border, splitter or chat link the pointer crosses.

### Target guard (`game_targetguard`)
Owner report 2026-10-21: the Necromancer's minions got targeted and then stood idle. `ChaosTargetGuard` (pure, global)
decides for base patch 0112: the helper's locked target is dropped when it is the player's own summon (creature type 3)
or when the server refused it 3 times within 3 s, and the battle list's attack next / previous skip own summons.
Another player's summon stays a valid target (PvP). `targetguard.lua`, `targetguard_test.lua`; client/BASE.md `0112`.

### Helper (`game_helper`: `helper.lua`, `helper_*.lua`, `styles/helper.otui`)
Owner 2026-10-23: the helper module the owner supplied replaces the base helper. Its window and loop were rebuilt
for Chaos (R!ck, ZLukSrT#8740, Christianlb and worthdavi are credited in `docs/CREDITS.md`; the licence is unknown and the
owner supplied the file). `assemble_client.sh` applies the base patches to `mods/game_helper` (old patches never change,
`0117` still applies) and then removes that folder; `modules/game_helper` is the helper. It is sandboxed and named
`game_helper`, so `game_interface`'s load-later list, the key bindings and the battle list reach it unchanged.
- **Pure files, each with a test.** `helper_config.lua` (the settings, `sanitize`, the rotation view), `helper_logic.lua`
  (areas, hits, target modes A to H, heal, training, haste, slots), `helper_spells.lua` (which spells each picker offers,
  from `SpellInfo.Default`, vocation ids 1 to 25), `helper_potions.lua` (all 12 stock potions with client and server ids and levels, offered to every class: health, then mana, then the spirit potions as a health and a mana entry, the strongest first; saved rows keep their key `id` or `id:1` / `id:2`; the test compares the list with the Apothecary's table in `apothecary_config.lua` so it cannot drift; the Everfull flasks
  266 and 268 with their fixed roll plus a percent), `helper_cycle.lua` (the 50 ms tick without replay), and the four of "Runes, Auto sell, Follow and ally heals". `helper.lua` is
  the engine glue; `helper_test.lua` runs it against a mock engine.
- **Window.** Six tabs, 640 px wide. Healing (3 heal rows, 3 potion rows, mana training, Auto Haste), Combat (presets,
  five spell slots with mana percent, monster count, Force and Self, Magic shooter, Auto Target with modes A to H,
  Priority targets, Only reachable), Runes (2 healing rune rows, 3 attack rune rows of the preset), Allies (party and
  friends heals, Follow), Support (the `game_helpersupport` panel in `supportHost`), Tools (auto eat, exercise training,
  Auto sell, Bot HUD and its sections). The master switch and the Auto setup button are in the top row. Spell icons take drops from the
  spell list: their ids are `spellButtonN`, `attackSpellButtonN`, `spellTrainingButton`, `hasteButton`.
- **Casting.** Every cast goes through `ChaosHelperRotation` (the server's answer first) and `ChaosHelperTimers` (the
  server channels heal, attack, support, potion, move, action). Heals are not blocked by a charging cast, other casts are.
  Utility spells (lanterns, rope, town portal, toggles) are never auto-cast (`ChaosHelperSupport.NEVER_*`).
- **Auto Target** uses `ChaosAutoTargetEngine` (`game_autotarget`): reachable monsters, goblins, bosses and special
  monsters first, default mode F (nearest, then lowest health). Own summons are never locked (`ChaosTargetGuard`).
- **Pauses.** A protection zone or following pauses both systems without touching the settings (at the entry the lock and
  attack drop once). A death drops the lock and the attack and saves. The helper switch (`botStatus`) pauses everything.
- **Settings** are saved per character in `/characterdata/characters/<name>/helper.json` through `ChaosHelperSave`
  (read before write, checked write, `.bak`, save on death and logout). An old file loads: its shooter rules become
  slots (at most five), its rune rules rune rows (at most three), its follow friend, party and Sio heals and Auto Sell
  Loot the new sections (see "Runes, Auto sell, Follow and ally heals"), unknown fields stay, and
  `helper.json.pre-newhelper.bak` is copied once first.
  Timed casts by words of the old Timers tab move once into the Support slots.
- **Not carried over** (the module has no UI or logic for them): equipment, supplies, special foods, stamina food, magic
  shield, alarms, the shortcut bar, target-name, ignore and priority lists, modes I and J, chase, the Timers tab and
  custom timer rules, anti-idle, auto party, look item id, change gold, the files and settings folder, custom hotkey
  buttons, the tracker mini-window (`move()` gives nothing back), icon pickers for items (combo boxes instead), the
  cast-on-foot opcode. The old settings stay on disk. Runes, Auto sell, Follow and the party and friend heals came back
  on 2026-10-23, below.
- Not seen in a client: the mock tests cover the loop, the widgets were not drawn.

#### Runes, Auto sell, Follow and ally heals (`helper_runes.lua`, `helper_sell.lua`, `helper_follow.lua`, `helper_ally.lua`)
Owner request 2026-10-23: "coloque o auto sell, runes, follow e cura de pt e amigos". Each has a pure file with a test; the
engine glue is in `helper.lua` (`healTick`, `runesTick`, `allyTick`, `followTick`, `sellTick`) and runs in the 50 ms tick
under the same pauses: the helper switch and a frozen connection stop all of it; a protection zone stops runes, ally heals
and Follow; following stops the fight systems (attack runes included); Auto sell does not care about zones (a sale is a
request to the server).
- **Runes** (`helper_runes.lua`, `helper_runes_test.lua`). Client ids (the server's id plus 887; Faint Dart and Pebblestorm
  have their own looks), checked against `server/data/lib/chaos_rune_supply.lua` (names, offset). Healing: Mending and
  Grand Mending on yourself, 2 rows `runeHeal { id, percent }`, lowest threshold first, channel `healRune`. Attack: only the
  17 damage runes (no fields, walls, bombs, Purge, Beastbond, Unmaking, Mimic, Gravecall, Thicket, Bastion), 3 rows per
  preset `shooterProfiles[name].runes { id, creatures, hpMin, hpMax, priority }`, used on the attacked monster while Magic
  shooter is on when enough monsters would be hit (area runes count round the target, single runes the monsters within 6
  tiles) and the health of the target is inside the row's range, in line of sight, channel `attackRune`. Both go through
  `ChaosHelperTimers.useReady` / `used` (1 s per channel) and `ChaosPotionGate.canUse` / `noteUse`, so a rune in a closed
  backpack is probed (not counted by the client) and a refusal backs off. Dawnshard is offered to the Paladin line only;
  there is no rune level on the server (every rune is level 1), the server refuses a class that may not use a rune.
- **Auto sell** (`helper_sell.lua`, `helper_sell_test.lua`). No sell NPC is faked and no item is touched: the helper asks
  the store's **Auto Seller** (server `autosell.lua`, opcode 226 `sell`, through `game_pouches` `sellAll()`) to sell the
  Loot Bag. The server sells at the NPC price into the bank, at most once in 30 s, and keeps locked items, uniques, store
  items, orbs / gems / keys, named items, locked containers and the rarities the player did not tick; it refuses without
  the Auto Seller (store unlock or Pact). Equipped items are not in the Loot Bag. `autoSell { enabled, minutes (5, 10, 15,
  30, 60), belowCap, capacity }`: ask every N minutes after the last ask (no ask at login), and optionally when the free
  capacity is at or below `capacity` oz, at most once a minute. It asks only when the server said the Auto Seller is
  unlocked and its cooldown is over (`game_pouches` got `getAutoSeller()` and `syncAutoSeller()`, which sends `as_sync`;
  the answer opens no window). Off by default. The window's own "Sell every X minutes" (server side, `asevery`) is separate.
- **Follow** (`helper_follow.lua`, `helper_follow_test.lua`). `follow { enabled, mode = 'name' | 'leader', name, distance }`:
  a friend by name (cleaned, case-blind) or the party leader (yellow shield). `g_game.follow` at most every 250 ms; after 5
  asks that start no follow, 5 s of rest. Distance 1 is a plain follow; 2 to 5 lets go once the leader is that near and
  follows again one tile farther. Nothing in a protection zone; when the leader is out of the 15 x 11 view or on another
  floor the helper lets its own follow go (never a follow the player chose by hand) and asks nothing. Switching the
  helper off lets its follow go.
- **Party and friend heals** (`helper_ally.lua`, `helper_ally_test.lua`). `allies { party { enabled, percent }, friends
  { enabled, percent, names (5) }, spell, group { id, count }, rune { id } }`. A single-target spell from the picker
  (Kindred Mend 84 and Heartwood Embrace 101 take a name; Mirror Mend 96 and Lay on Hands 253 heal only you and your party;
  Kindled Breath 66 heals the most hurt party member, Iron Sage only), a group spell cast when `count` hurt players are in its
  reach (Circle of Mending 82, 3 tiles round you; Mending Communion 128 and Lucid Reverie 97, the party), and an optional
  Mending or Grand Mending rune on the player. Who: party members (shield) below the party percent and the listed friends
  below the friend percent, in the 7 x 5 window, same floor, line of sight; most hurt first. Priority: yourself first (a heal
  row, potion row or healing rune row due by the numbers stops all ally heals), then allies. No spam: the same player not
  within 1.2 s, at most 8 ally heals in 10 s, none under 10 % mana, plus `ChaosHelperRotation` and the heal channel guard.
  Names are cleaned (letters, spaces, ' and -; 2 to 29 characters) before they go into the spell words in quotes, so typed
  text can never add chat text. The pickers list only spells the class can cast and never a utility (`Spl.castable` with
  `allowParameter`, which still applies the `NEVER_*` lists).
- **Settings and migration.** `helper_config.lua` `sanitize` clamps the new sections; `C.migrateOld` reads, once and only
  while the new section is missing, `followFriendEnabled` / `followFriendName`, `namedSio` (names, percent, spell),
  `friendhealing` / `gransiohealing` / `masreshealing` (highest enabled percent; Heal Friend becomes Kindred Mend, Nature's
  Embrace Heartwood Embrace, Mass Healing Circle of Mending), `autoQuillSell*`, and the rune rules (`type = 'rune'`) and old rune
  list of each preset. The old keys stay in the file. `game_helperrotation/helperconfig.lua` no longer drops `autoQuillSell*`
  (its clean-up runs on read, before the migration). Texts: pt-BR in `client_chaos_locale/pt_br.lua`, the rune names too.
- Tests: the four `*_test.lua`, `helper_config_test.lua` (sections, migration), `helper_test.lua` (a mock engine: an old file
  at login, a friend healed with the name in quotes and not spammed, self before ally, no heal in a protection zone or behind a
  wall, a healing rune on yourself, an attack rune on the target, Follow and its release on another floor, Auto sell asked
  once and never when locked). Not seen in a client.

### Auto Target priority and reach (`game_autotarget`)
Owner request 2026-10-23: the Auto Target only attacks monsters it can reach, by default the nearest and the one with the
least health, with loot goblins, bosses and special monsters first. Before, mode F (the default) took the nearest by
straight distance in the 7 x 5 window and kept the lock on it, even behind a wall or across water.
- **Reach** (`ChaosAutoTargetEngine`, the only engine calls): melee needs a path (`g_map.findPath` with the
  ignore-creatures flag, at most 16 steps, so a long detour does not count); a ranged class (Ranger, Mystic and
  Necromancer lines, server vocation ids in `RANGED_VOCATIONS`) also takes a clear line of sight (`g_map.isSightClear`),
  so it shoots across water. Another floor never counts. At most 4 new path searches per tick, nearest first; an answer
  is reused for 0.6 s (3 s when the budget is spent); a monster not asked yet waits one tick.
- **Order** (`ChaosAutoTarget`, pure): class (goblin, boss, special, normal), then the way to walk (steps for melee, the
  straight distance for a ranged class with sight), then the lowest health percent, then the lowest id. Mode F takes
  this order; the other modes A to I keep their own pick, from the reachable monsters, and the priority class replaces it
  when it exists; mode J (the player's own list) only gets the reach rule.
- **No flapping:** the lock stays while the monster is alive, in reach and reachable; it goes when the way is shut or a
  reachable monster of a better class appears (a goblin while fighting a normal monster). When nothing else can be
  reached the attack on the cut-off monster is cancelled.
- **How the client knows the class.** Loot goblins by name (`GOBLINS`: Treasure, Gem and Shard Goblin, the variants of
  `server/data/scripts/chaos/treasure_goblin_config.lua`, checked by the test; the stock "Goblin" is a normal monster).
  Bosses and special monsters from the server's monster bar messages (`game_monsterbar`, opcode 125: `tier` normal,
  magic, rare, legendary or boss; `role` guardian or omen for rift and Omen guardians), cached per creature id. The
  server pushes them for tiered monsters every 15 s and answers a `query` for any monster within 15 tiles, so the engine
  asks (3 per tick, a creature again after 5 s) for a creature nobody named yet. `game_monsterbar` got two small
  functions for it, `tierInfo(cid)` and `requestInfo(cid)`. World, pocket and waystone bosses are bosses of the server
  (`isBoss` flag), waystone elites get a magic or rare tier, so all of them arrive as tiers.
- **Options** in the helper's Targeting panel, under Always Chase Opponent (base patch 0117; both on by default, kept in
  `g_settings`): **Priority targets** (`chaosAutoTargetPriority`; pt-BR "Alvos prioritários") and **Only reachable**
  (`chaosAutoTargetReachable`; "Só alcançáveis"). Off restores the old pick for that rule. The panel grew by two 22 px rows.
- Tests: `autotarget_core_test.lua` (rules: unreachable skipped even when nearest, goblin / boss / special before a nearer
  normal monster, nearest, equal distance lowest health, the lock kept until a better class shows up),
  `autotarget_engine_test.lua` (a mocked map: paths, sight, floors, budgets, options, tier questions). Not run in a client.
  To check live: a monster behind a wall or across a river is not attacked; a Treasure Goblin pulls the character off a
  nearer rat; a rare monster before a normal one; the two boxes are visible and the panel fits at 936 x 540.

### Helper bot HUD (`game_helperhud`)
`tools/assemble_client.sh` leaves the helper's cavebot file out, and the bot HUD lived there, so Tools > Bot HUD > "Show
Bot HUD" did nothing. `ChaosBotHud` draws it again at the top centre of the map: Combat, Equip, Timers, Support,
Player and Auto rows (dimmed when off), Compact / Normal / Wide. The helper refreshes it every 250 ms while online;
on/off and the sections are in the helper's character save (`botHud`), so it comes back after a relog.
`helperhud_logic.lua`, `helperhud_test.lua`.

### Other fixes
- Liquid orbs (`game_shaderfx`): size option Orb size (small 76 px, medium 150 px by default, large 190 px; Options >
  Graphics, beside the orb box: the Interface page is full); the orbs sit beside the chat panel (see "Chat panel").
- Toasts (`game_chaosnotify`): the toast grows to its wrapped text, up to 260 px, the full text in a tooltip past that;
  the timer bar stays under the text; stacked toasts use each one's own height (`ChaosNotifyView.heightFor`).
- Auto rotation (`game_helperrotation`): with the player's own rules the button asks "Add to my rules" (the default:
  their rules stay on top, class spells not in the list go below) or "Replace"; Undo (beside the button and in the
  result box) puts the list back for the session. A click tops the rotation up to 5 castable spells (from level 8 to
  11 the Mystic preset is one spell, so the button wrote one rule).
- The helper never changes the spells unasked (owner, 2026-10-16): a level-up used to replace a rotation the button had
  written. Now a new attack spell gets "New spell available: X. Add to rotation?" (Add / Ignore; Ignore is kept per
  character). "Auto-update my spells" (on the presets row, left of Rename: in the title row it covered "RULES" of the
  centred title; the label shortens to "Auto-update", then the box alone, when the row has no room,
  `ChaosAutoRotation.autoBoxLabel`; off by default, per character, client settings node
  `chaos_helper_spells`) lets a level-up update a rotation the button wrote, without the top-up and never the
  player's own rules (`ChaosAutoRotation.levelUpAction`, tested).
- Candlemarks: the "week" label was anchored to `next.bottom`, its next sibling, not the label with id "next"
  (anchor cycle logged about 50 times); `tools/ci/check_layouts.py` now follows prev / next.
- Options menu labels are `tr()` text over tab images whose baked words are erased (`tools/gen_ui_reskin.py`
  TEXT_FREE, regenerated for `optionstab/`). The sub-entries (115 px, no icon) use `verdana-9px-bold` (base patch
  0104): in `$var-cip-font` "General / Action Bar / Custom Hotkeys" were clipped at both edges (owner screenshot
  2026-10-21). `tools/check_text_fit.py` (CI) measures every sub-entry name, English and pt-BR, in that sheet:
  widest "Action Bar Hotkeys" 91 of 107 px.
- Fixed widths that cut pt-BR labels sized to their text: hideout, market (3), shop, party finder (2), player inspect,
  map overlay, guild war, achievements.

## Client icon (owner debug item 15, 2026-10-18)

The window icon (`g_window.setIcon('/images/clienticon')` in the stock `client` and `updater` modules) and the Windows
executable icon (`src/otcicon.rc` names `otcicon.ico`) were the stock pictures. Both are now the Cinders of Chaos icon
`docs/brand/cinders_logo_icon.png` (made by `gen_login_art.py brand`): `python3 -I client/tools/gen_client_icon.py`
copies it to `overlay/data/images/clienticon.png` and builds `overlay/src/otcicon.ico` (16 to 256 px, PNG frames);
`tools/assemble_client.sh` copies `overlay/src/` over the base client's `src/`. `--check` verifies both. Not seen in a
built client (the resource compiler must accept PNG frames in the .ico; MSVC `rc.exe` does).

## Level-gated top menu (`client_chaos_topbar`, O259)

The top menu shows a system when the character reaches its level. The server (`unlocks.lua`, extended opcode **115**,
server/README.md "The top menu reveals systems by level (O259)") sends `state {entries, unlocked, seen, next, all}` at login and
on every level change, and `new {key, level, menu, title, why}` one entry at a time (75 s apart); the client keeps no table.
- `topbarunlockslogic.lua` (pure, tested by `topbarunlockslogic_test.lua`): status of an entry by its menu text (`open`,
  `locked` = the next one, `hidden`), the "New" badge (unlocked, not opened), the level that blocks a hotkey, the row and screen
  texts. Before the first `state` (an older server, a login in progress) every entry is open; an entry the table does not name
  is always open.
- `topbar_unlocks.lua`: the opcode (`registerExtendedJSONOpcode`), `hello` and `seen {key}` out, the big text "New: <title>!"
  (`ChaosUnlockText`, fades after 4.2 s) and the small window (`ChaosUnlockWindow` in `topbar.otui`: name, two lines, Go, Close;
  closes by itself after 30 s). Go runs the entry of the menu (`ChaosTopBar.run`).
- `chaos_topbar.lua`: `availableEntries` hides the entries that are not open; the next one is a grey row with a padlock
  (`/images/game/depot/lock`) and "Level N", clicking it says "Unlocks at level N"; an entry opened from the menu, a hotkey or Go
  loses its gold "New" badge (and tells the server); a category with an unopened new entry is gold; a locked hotkey says
  "Unlocks at level N" instead of opening. `ChaosTopBar.available()` and `ChaosTopBar.run(text)` skip locked rows.
- Option "Show the whole menu" (System > Options > Interface, `showWholeMenu`, off by default): base patch `0154` (dataset option
  plus a checkbox; its apply calls `client_chaos_topbar.onOption`); the module also reads it with `getOption` at load. Without the
  patch the filter stays on. Staff and a switched-off server module get the whole menu (`all`).
- Texts through `tr()`, pt-BR in `client_chaos_locale/pt_br.lua` ("Go", "New: %s!", "Show the whole menu" and its tooltip; "Level %d",
  "Unlocks at level %d", "New", "Close" existed). Not run in a client.

## Drop feed option and personal records (O260)

- **game_dropfeed** (new; extended opcode 229, action `feedopt {mode}`, client to server; server `retention_loot.lua`): System > Drop Feed opens a small window with one drop-down, Off / Unique and Divine only / Legendary and better (default). The choice is kept in the client settings (node `chaosDropFeed`) and sent at login and on a change; the server filters the drop lines of other players (Default tab and the channel Drops). Logic `dropfeed_logic.lua`, tested by `dropfeed_logic_test.lua`. Not run in a client.
- **game_playerinspect**: a `records` packet after the result (`{name, rows = [{key, name, value}]}`, text in the viewer's language) and a Records button next to Passive Tree that swaps the equipment panel for the rows (`L.onRecords`, `L.recordsButtonText`, tested). Not run in a client.
- **game_leaderboard**: the Records view has a client category **My Records** (`rmine` on opcode 229, `rmine {rows}` back; `recordsview.lua` adds the category, tested). Not run in a client.
- **client_chaos_topbar**: the System menu has the entry Drop Feed.

## Interface skins (`client_chaos_theme`, base patch 0159, O281)

Three looks the player chooses in Options > Interface > Interface skin (Classic, Forge and Embers, Abyssal Arcane; pt-BR
Clássico, Forja e Brasas, Arcano Abissal). The choice is saved in g_settings `chaos-skin` and applies **at the next client start**
(the option tooltip and a message after the choice say so). A live switch is not reliable in this engine: textures are cached by
path and a style reads its images when a widget is built, so windows already open would keep the old look.

- **classic**: the client's own art (`gen_skin.py`, `gen_ui_reskin.py`), nothing copied, byte-identical to a client without skins. The default, and what an unknown value, a missing skin folder or a failed copy falls back to.
- **forge** (theme A, Forged Iron and Embers): void `#0b0908`, iron `#2f2a26` / `#5c544b`, ash text `#d8ccb8`, ember `#ff7a1a` / `#ffb347`, health `#c2260f`, mana `#2d68b8`. 4 px iron frames with riveted corner plates, an ember crack line under titles, iron slab buttons (hover hotter with an ember underline, pressed dark with an ember outline, primary solid ember), notched tabs with an ember cap, a spiked iron orb ring with rivets and an ember inner rim.
- **abyss** (theme C, Abyssal Arcane): void `#06070b`, obsidian `#0d1019`, gold line `#c9a45a` / `#e8cf8a`, violet `#8a5cf0`, teal `#2fd0c0`, health `#d23a5a`, mana `#25b5c8`. Flat obsidian with 1 px gold hairlines, filigree only at the corners, chamfered buttons (hover teal inner line, pressed teal, primary violet), underline tabs, thin violet scroll bars, a thin gold orb ring with teal ticks and four diamond studs.

**Mechanism.** A skin is a folder `overlay/data/skins/<id>/` of 144 PNGs that mirror the client's virtual paths (`images/chaos/skin/window.png`, `images/ui/scrollbar.png`, `modules/game_shaderfx/images/orb_ring_150.png`, ...) plus `manifest.lua` (the file list and a revision, the hash of the bytes). The engine mounts the write folder before its own files, so a file copied there at the same virtual path is found first by every `image-source`. `skin_boot.lua` (run from `init.lua` before any module, base patch 0159) calls `skin_core.lua` `sync`: it reads the state file `chaos_skin_state.txt` of the write folder (skin, revision, files written), copies the chosen skin's files with `g_resources.copyFile` (only when the choice or the revision changed), removes the previous skin's files, and undoes a half copy (then classic runs). Every skin image has the size and 9-slice borders of the classic image it shadows (the generator checks it), so no style changes. `CHAOS_SKIN=forge` in the environment overrides the setting (test runs). Logic and tests: `skin_core.lua`, `skin_core_test.lua`, `chaos_theme_test.lua`.

**Fix, the picker row.** `client_chaos_theme` is a sandboxed module, so its `ChaosTheme` table was local to it and the row of Options (`ChaosTheme and ChaosTheme.skinName`) saw nil and hid its button. `chaos_theme.lua` now also sets the real global `_G.ChaosTheme` (cleared on unload). Lua only, ships as a normal client update.

**Art.** `client/tools/gen_skin_variants.py` draws everything with Pillow, flat colours, 1 px bevels and hairlines, no source images; the orb rings are drawn here at 1x and doubled (a ring is 2x its orb size; classic rings come from the purchased pack through `import_hud_kit.py`, which this tool never reads). `--check` (CI, checks job) compares pixels, sizes against the classic images, the manifests and the ring concentricity (`gen_orb_art.opening`); `--preview DIR` writes `skins_preview_<classic|forge|abyss>.png`; `gen_skin_variants_test.py` is its test. Without a flag it writes the images, the manifests and `images/chaos/skin/button_primary.png` of classic (a byte copy of `button.png`, so the new style `ChaosPrimaryButton` looks like Button there).

**Covered (both skins).** Window frames and title bars (`chaos/skin/window`, `chaos/window`, `ui/window`, `ui/popupwindow`, `ui/map-borderimage`, `ui/window_headless`) with corner plates / filigree and crest; buttons (`chaos/skin/button` and `button_primary`, `chaos/button_*`, `ui/button*`), tabs (`chaos/skin/tab`, `chaos/tab_*`, `ui/tabbutton_*`, chat channel tabs); panels and frames (`chaos/panel*`, the `ui/*pixel*` frames, `ui/panel_*`, `ui/menubox`); text fields, check boxes, combo box; scroll bars (`chaos/scroll_*` and the stock `ui/scrollbar` sheet); item slots (inventory, container, action bar, charm slots); progress frame; tooltip, menu bar, top bar, title plate, separator; the HUD plate, portrait cover, bar fills and level badge (`game_chaoshud`); the three orb rings (76, 150, 190); the chat frame `ui/console` (its two panels, the rest of that sheet stays classic). Stock sheets of the base client (mini window buttons, arrows, check box sheets, combo boxes, common buttons, action bar arrows) are recoloured from the classic images through two colour ramps; saturated non-gold pixels keep their colour.

**Colours in Lua.** `ChaosTheme.palette` is the active skin's table (`skin_core.lua` `PALETTES`): window titles, mini window titles, the tooltip text and the menu bar colours (new / locked / normal) read it.

**Still classic or fixed (the honest list).** OTUI has no variables, so text and state colours written in `.otui` files stay as they are: the gold button hover text of `Button` (`#ffe7a6`), `ChaosButton` and `ChaosPrimaryButton` text, the `ChaosProgressBar` / `ChaosHealthBar` / `ChaosManaBar` fills, the colours in `topbar.otui` and `chaoshud.otui` (HUD name and numbers), and about 230 more gold literals of module `.otui` / `.lua` files. Not redrawn: equipment slot silhouettes (`game/slots/*`), the ~500 other images of `RESKIN_FILES.txt` (stock icons, bars, flags), the login screen, character list, map markers, monster bars, top bar icons and every module's own art. An update that replaces a file a skin also draws shows the classic file until the skin files are copied again (the next start with a changed choice or revision). Not run in a client.

## Clean start after an update (`client_chaos_updater/cleanup_*.lua`, Lua only, 2026-10-29)

Owner report: after the new client the health and mana globes and the buff icons still showed the old sprites. The engine
searches the per-user write folder before the client's own files (`setupWriteDir` mounts it in front; Windows:
`%APPDATA%\CindersOfChaos\CindersOfChaos`). A file there at the same virtual path hides the shipped one. Three things put
or left such files there: the update tree `chaos_update/files`, mounted in front of the pack, where a tree older than the pack stayed
mounted while the check said "older than this package: not applied", the interface skin copies, left behind when the state file was lost
or from an older revision, and files of older mechanisms such as downloads and copies of earlier clients. Nothing removed them on a
new package. Not reproduced on Windows here; the fix removes every one of these paths.

**What a start does.** `skin_boot.lua` first runs `cleanup_boot.lua`. It
reads the stamp `chaos_clean_stamp.txt` of the write folder, the client package id and the applied update, and sweeps when the
package id changed because the launcher or a fresh download installed new files, the applied update changed, there is no
stamp yet, or the update tree is stale, meaning older than `Services.update.baseline` or made for another package. The skin sync runs
right after, so the chosen skin is copied fresh. A stale tree that `bootstrap.lua` already mounted is unmounted
(`g_resources.unmountUpdateOverlay`) before the sweep. `bootstrap.lua` itself no longer mounts a tree older than the
baseline. That part ships with the next package; the sweep covers older packages.

**Kept, by an explicit list** (`cleanup_core.lua` `KEEP_NAMES` and `keepName`, top-level names of the write folder, case
blind): `config.otml` and every `config.otml*` (all options, hotkeys, action bars, remembered accounts and characters, chat
and console settings, the skin and language choice, every `chaos-*` setting), `characterdata/`, `settings/`,
`settings.json`, `minimap.otmm` and `minimap.otmm*`, `bot/`, `screenshots/`, `*.log`, `*.log.old`, any file named `chaos-*`
with a hyphen, and the stamp. `chaos_update/` is kept only when its tree is current: a finished apply for this package at or
above the baseline, or a half applied update of this package that the updater finishes. **Wiped:** everything else in
the write folder, among it old update trees and staging, `chaos_skin_state.txt` and the skin image copies, `downloads/`,
`sounds/`, loose `data/`, `modules/`, `mods/`, `layouts/`, `images/` copies.

**Safety.** Only virtual paths of the engine are used and the engine deletes inside its write folder only. A node counts
only when `g_resources.getRealDir` says it is in the write folder, so the client's own files are never touched, even in a
folder that exists in both. A listed name must be one plain path segment. Depth 24, 400000 removals at most. A file that
cannot be removed stays and is counted; the stamp is written anyway. If the write folder is unknown nothing is removed.
`CHAOS_CLEAN_OFF=1` turns it off in tests. Known limit: the engine allows symbolic links, and a link to a folder inside the
write folder would be followed; none is made by the client. The log line `clean start in <folder>: ...` says what ran.

**Launcher** (`launcher/src/install.rs` `remove_stale`): `.cinders_launcher/owned.json` lists the native files of the last
manifest applied. After a good update every name that list holds and the new manifest leaves out is removed from the install
folder, so no old DLL or pack of an earlier release stays. Only plain names ending `.exe`, `.dll` or `.pack`, only names an
earlier manifest listed, never the game, the launcher or the running program, only a regular file directly in the install
folder; a folder, a link or a missing file is left alone; a file in use stays on the list for the next run. The first run
of this version has no list and removes nothing. Test `old_files_of_an_earlier_release_are_removed` in
`launcher/tests/mass_update.rs`.

**Tests.** `cleanup_core_test.lua` covers the keep-list, the decision, the sweep on a fake folder and the limits, `cleanup_boot_test.lua` (the boot
step against a fake `g_resources`). Both run under LuaJIT and Lua 5.3 in the client test loop of CI.

**One-time manual fix until the update arrives.** Close the client, delete the folder `chaos_update` and the file
`chaos_skin_state.txt` in `%APPDATA%\CindersOfChaos\CindersOfChaos`, then start the client. To also drop skin copies delete
the folders `images`, `modules` and `data` in that folder if they exist. Keep `config.otml`, `characterdata`, `minimap.otmm`.

## Spell lists by class (O307)

`ChaosSpellFix.allowsVocation` (game_chaosspells/spellfix.lua) is the one class rule of the action bar, the hotkey pickers
and Auto setup. Chaos spells match their exact server ids; only stock entries also match the folded id of
`translateVocation`, which put the Beastmaster on the Deadeye's spells.

## RmlUi spike (`client_chaos_rmltest`, base patch 0172, 2026-10-30)
One test window in HTML and RCSS, to measure what RmlUi costs. Report and recommendation: `docs/RMLUI_SPIKE.md`.
- `client_chaos_rmltest`: `rmltest.rml`, `rmltest.rcss` (dark theme, flex, percent widths, a scrolling list of 30 rows, two
  buttons plus a close button), `rmltest.lua` (opens it, fills it with `g_rml`, texts through `tr()`), `fonts/` (Alegreya
  Sans Medium and Alegreya SC Bold TTF with their OFL texts). Open: `ChaosRmlTest.open()` or Ctrl+Alt+F10. In a client
  built without `-DCHAOS_RMLUI=ON` there is no `g_rml` and the module does nothing.
- Engine side: overlay `src/framework/rml/rmlmanager.{h,cpp}` (render, system and file interfaces, input mapping, the
  `g_rml` Lua binding), hooked in by base patch 0172. Test: `rmltest_test.lua` (fake `g_rml`).
