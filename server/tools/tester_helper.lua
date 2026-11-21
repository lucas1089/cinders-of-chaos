-- TEST ONLY: never ship this file. It is not under server/data, so install_all.py never copies it.
-- The helper of the tester bots (server/tools/testers.py; server/README.md "Tester bots"). chaos-ctl.sh testers start
-- copies it to data/scripts/zz_tester_helper.lua (and tester_helper_core.lua to zz_tester_helper_core.lua);
-- testers stop and cleanup remove both.
--
-- SAFETY: every action below runs ONLY for a character that has BOTH the tester storage 7102900 = 1 AND a name
-- "Tester Xxx" (ChaosTesterHelperCore.eligible). No other character is ever targeted, moved, given anything or read.
-- The helper never heals and never prevents a death: testers take real damage and really die.
--
-- What it does for a tester:
--   * targets: a tester without a target gets the nearest monster within 5 tiles as its target and faces it (the bots
--     do not parse the map); with chase on the bot walks to it
--   * supplies once (storage +1): a backpack, the plain weapon of its class kit (ChaosTestKit, no unique roll), stock
--     health and mana potions and some gold, so the potion and shop paths run
--   * its hunt spot: the first login position (storage +2/+3/+4, testers.py setup puts it on a hunt)
--   * "!tester town | depot | shop | hunt | info" (the bot says it): teleports to the temple, next to a depot locker,
--     next to an NPC of the town, back to the hunt spot; each answer is a text line
--     "[tester-helper] <kind> <json>" with the client ids and positions the bot needs (its own creature id, the potion
--     client ids, the locker, the NPC's name)
--   * "!tester spellquest <state | reset | set | kill | trial | leave | complete>": the line spell quests of the tester (the
--     checks of tools/tester_checks.py spell_quest; the staff command /spellquest is closed to testers)
--   * "!tester waystone <1-15> [loot]" and "!tester riftrun <layout | loot>": a waystone run of that tier on the device's own
--     functions, a real rift run opened as a player does; the facts the checks waystone_run, rift_layout and content_rewards
--     assert (both clean up: the map is put back, the rift closed); "!tester party" also reports the shared experience, "!tester party kill" adds a real shared kill and a solo kill; "!tester unique" wears a unique and
--     measures its passive on a real hit
--   * "!tester bag": tops the potions up and reports the backpack (O584: it removes nothing; "bag wipe" is the last resort); "!tester shop Loot Buyer" goes to that trader; "!tester give item | orb KEY | gem | rune | charm | card" gives the crafting checks their items
--   * "!tester gold [to N]" (O658): the bank balance and the gold in the backpack; `to N` is the TEST ONLY top-up of the bank (3,000,000 a call, 16,000,000 a
--     bot) that the gear-up of tester_checks.py counts as a fallback when a bot cannot pay for its potions and basic pieces; "bag" also reports the potions held
--   * "!tester path <kind> [N] | npc <name> | pos X Y Z" (O589): the way on foot to a map mark, an NPC or a position, the engine's own
--     pathfinding (Creature:getPathTo) as directions the bot walks; the helper's teleport (`enter`) stays only as the fallback
--     when there is no path, and the bot's report counts it
--   * "!tester dungeon [state | path | close]" (O589, closed test mode): the dungeons as a person sees them (ChaosDungeons.probe), the
--     path to the guide's goal inside a run and the close of the testers' own run; the walk and the fights are the bot's own
--   * "!tester siege [state | start | path | portal | close]", "!tester guildboss [state | path | hall | close]" (O592, closed test mode): the
--     guild siege and the weekly guild boss as a person sees them (ChaosSiege.probe, ChaosGuildBoss.probe), the TEST ONLY start of the testers'
--     own siege, the path on foot to the portal, the stone or the next goal inside, the step next to a portal (the hall) when there is no
--     path, and the close of the testers' own run; the walk, the fights, the donation and the summon are the bot's own
--   * "!tester rift [state | key [tier] | path | close]" (O592): a rift opened and walked like a person's (the key into the backpack where the
--     bot stands, in a protection zone; what the screen shows inside; the path on foot to the guardian or the nearest pack monster; the close)
--   * "!tester tower [state | path | close]", "!tester descent [state | path | close | sigil]", "!tester trial [state | path | close]" (O595): the
--     Infinity Tower, the Ember Descent and the Vocation Trials as a
--     person sees them (ChaosTowerRun.probe, ChaosDescent.probe, ChaosTrials.probe: the level rule, how a run is paid, the floor or room, the monsters, the guide),
--     the path on foot to the guide's goal and the close of the bot's own run; `descent sigil` gives an Ember Sigil when the free descent of
--     the day is used. The window's requests (enter, start, pick a boon, Continue, Next floor now) and the fights are the bot's own
--   * "!tester ascended [state | sigil [kind] | path | close]", "!tester omen [state | key [kind] | path | close]" (O599): the Ascended Omen
--     arenas and the Omen Key arenas as a person sees them (ChaosAscended.probe, ChaosRift.probe); `sigil` / `key` is the TEST ONLY grant
--     (a tester only, logged), the path on foot to the guide's goal inside and the close of the bot's own run; the bot uses the sigil or
--     key itself and fights the boss itself
--   * "!tester pinnacle [state | set [boss] | path | close]" (O678): the four Ascended pinnacle bosses as a person sees them (ChaosPinnacle.probe: the
--     fragments held, inside a fight the boss's health, the clock, the guide); `set` is the TEST ONLY grant of a whole set of fragments (a tester
--     only, logged: the top content that drops them is hours of play), the Keeper's window opens the fight (the bot presses Open itself), `path` is
--     the engine's path to the guide's goal inside, `close` the bot's own way out
--   * "!tester gear [state | set]" (O681): the helmet, armour, legs and weapon of the equipment sets that fit the bot's class and level (`state` reads,
--     `set` is the TEST ONLY grant of a Rare piece of item level = the level for each slot, worn at once, a tester only, logged, never inside a pinnacle
--     fight): the gear the pinnacle checks need, which the Gambler's stock and a bot's own drops do not give at level 1900 to 2500
--   * v31 (O683): `!tester pinnacle state` inside a fight also answers `danger` (ms to the first pending mark, its names, whether the bot stands on it) and
--     `tally` (telegraphs fired, players they could have hit, those standing on a marked tile at the hit: the share of marks taken), and the guide says
--     `hold` when the walk would end on or next to a pending mark (the bot stays and fights until the hit)
--   * v32 (O684): in a pinnacle fight `danger.steps` is the way the server planned to the safe tile the bot's dodge names ((dx, dy) from the bot's
--     tile, at most 12), and the bots of a party get different tiles and ways (ChaosBossMech.dangerFor with the player's id: no two take one goal)
--   * "!tester bounty [state | where NAME | path]" (O599): the bounty board as a person sees it (ChaosBounty.probe: the contracts held, the ones a
--     hunt mark lists, "where does monster X spawn" from the hunt marks) and the path on foot to the contract's monster or hunt
--   * "!tester mainquest [state]" (O599): the open step of the main quest, its condition, progress, where to go and what a bot can play of it
--     (ChaosMainQuest.probe); the bot walks, talks and kills itself
--   * "!tester nemesis [state | born | appear | path | close]", "!tester daily", "!tester chronicle", "!tester vael [state | enter | path | close]",
--     "!tester goblin [state | spawn | path | close]", "!tester invasion [state | path]" (O650): the Nemesis, the daily reward, the Ashen Chronicle,
--     Vael Ashmourn, the treasure goblin and the invasions as a person sees them (ChaosNemesis.probe, ChaosDaily.probe, ChaosChronicle.probe,
--     ChaosMainQuestBoss.probe, ChaosTreasureGoblin.probe, ChaosInvasion.probe); `nemesis born | appear`, `vael enter` and `goblin spawn` are the
--     TEST ONLY grants (a tester only, logged), `path` the way on foot to the guide's goal, `close` the end of the bot's own run; the fights and the
--     claim are the bot's own
--   * "!tester found" (O653): what the bot's own drops can do (read only): the orbs, whetstones, sockets orbs, gems, runes, charms and cards in its
--     backpack, the pieces it could wear with a score that knows sets, uniques and jewelry (H.chaseScore), what it wears. Nothing is given or moved;
--     the crafting, the socketing and the wearing are the bot's own packets (tester_checks.py craft_found, gear_chase)
--   * "!tester ascend [state | proof | path | close]", "!tester gather [state | path]" (O655): the Ascendant Oracle's quest (stage, Proof of Strength,
--     the Trial, the Choice and the class lock: ChaosAscensionQuest.probe) and the gathering with a pick or a sickle (the tools carried, the nearest node
--     that is ready for the bot: ChaosProfessions.probe) as a person sees them; `ascend proof` is the TEST ONLY credit of the proof (a tester only,
--     logged), `path` the way on foot to the guardian inside the trial / next to the node, `ascend close` the end of the bot's own trial. The talk with
--     the Oracle (the modal windows), the fight, the choice, the use of the node and the buying of a tool are the bot's own
--   * "!tester dummy [state | path | give | clear]", "!tester mount [state | give | clear]", "!tester task [state | where NAME | path]", and "!tester gather
--     corpse | water" (O657): the exercise weapon and the nearest training dummy (ChaosExercise.probe), the mount and the speed, the Bestiary's kill tasks
--     with the monster to hunt (ChaosBestiary.probe) and the nearest fresh corpse for the knife / fishable water for the rod; `dummy give` and `mount give`
--     are TEST ONLY grants (a tester only, logged), `clear` takes them back. The use of the weapon, the mount toggle (0xD4), the walk and the fight are
--     the bot's own
--   * "!tester explode [state | run | set | bag | join NAME]" (O669; O678: `set` puts a set piece among the loot, `bag` leaves a bag with a set piece and a Legendary on the tile) (O669): the loot explosion (loot_explosion.lua): `run` puts a loot bag of the bot's own on its tile with known
--     loot and explodes it by the real rule, `state` reads what lies within 4 tiles (owner, ring, tiles, the bag) and whether a stranger would be
--     refused; Loot all is the bot's own packet (opcode 230 `lootall`; tester_checks.py loot_explosion). TEST ONLY, a tester only
--   * "!tester journey [state | jump | hall] [keep ID] [skip ID,ID]" (O654): the levelling journey on foot: the next hunt of the level from the
--     teleport room (hunt_teleports.lua ports, the window of progression_config.lua), the temple's great teleport, the stairs of the hall, the town
--     portal beside the bot, the depot locker and the nearest monster, as a person sees them; the walk is `path pos`, the steps onto a teleport are
--     the bot's; `jump` / `hall` are the TEST ONLY teleports of the counted fallback
--   * "!tester pvp [state | path]", "!tester boss [state | spawn | path | close]" (O652): PvP among the testers (ChaosTesters.pvpProbe: the PvP place,
--     the foe the rules allow, the hits a rule cancelled, the arena, battleground and Marches views, the season rows of testers: 0) and the tester
--     copy of a key boss (ChaosTestersBoss.probe: the copy, its telegraph marks and the safe tile, the kills, the boss points, the boards: no
--     tester); `boss spawn` is the TEST ONLY grant (a tester only, logged, only while no player is near); inside a PvP place the helper's loop aims
--     a tester without a target at a foe tester (ChaosTesters.pvpFoe: both testers, the switch on, one place, the place's own rule), never at a player
--   * "!tester raid [state | path | portal | close]" (O588, closed test mode): the raid as a person sees it (position, entrance, the next
--     goal and what to do there), the path on foot to the entrance (the engine's own pathfinding), the step next to the entrance
--     portal when there is none (the bot walks the last step into it itself) and the close of the testers' own raid; the walk,
--     the fights, the potions and the loot are the bot's own (tester_checks.py closed_raid)
--   * once a minute it counts the testers in game; the server console gets "[tester-helper] testers online: N" when
--     the count changed, and every 5 minutes anyway
--   * anomalies (one console line each, "[tester-anomaly] <json>", testers.py report reads the server log): a hit taken
--     or dealt far above the level, one hit from full health to death, a negative or absurd experience gain, an item
--     with an impossible count or attribute in the tester's backpack (checked once a minute)
-- Assumed engine API (TFS 1.4.2): CreatureEvent login/logout/healthchange/death, EventCallback onGainExperience,
-- TalkAction, addEvent, Game.getSpectators, Creature:setTarget/setDirection/teleportTo,
-- Player:getStorageValue/setStorageValue/addItem/getBankBalance/setBankBalance, ItemType:getClientId, Tile.
if not ChaosTesterHelperCore or not ChaosTesterHelperCore.eligible then
	dofile("data/scripts/zz_tester_helper_core.lua")
end
local H = ChaosTesterHelperCore

local STORE = H.STORAGE
local GROUPS, STEP_MS, RANGE = 4, 500, 5
local SUPPLIES = {{7618, 100}, {7620, 100}} -- stock health / mana potion
local GOLD = 20000 -- into the bank: NPC purchases pay from it (Chaos.pay)
local LOCKERS = {2589, 2590, 2591, 2592} -- depot_config.lua lockerIds
local HUNT_CHECK = 7 -- tiles round the hunt spot checked for monsters above the tester's level
local SEARCH = 30 -- tiles around the temple for an NPC
local NPC_REACH = 4 -- tiles round an NPC that `enter npc` looks for a free one
local HALL_SEARCH = 30 -- tiles around the temple for the Guild Hall Portal
local LOCKER_SEARCH = 45 -- tiles around the temple for a depot locker (its floor and the ones above and below)
-- NPCs with a trade window, tried first by "shop": the NPC nearest the temple may only talk
local TRADERS = {"Material Broker", "Loot Buyer", "Wandering Merchant"}

-- chaos-ctl.sh reads this line: a server that still runs an older copy (no "v" or another number in its "running" line)
-- counts as "helper not loaded", so `testers start` restarts it. Raise it with every change of the helper files.
HELPER_VERSION = 37
TesterHelper = TesterHelper or {ids = {}, step = 0, hits = {}, loginAt = {}}
local T = TesterHelper
T.hits, T.loginAt = T.hits or {}, T.loginAt or {} -- a reload keeps the table of an older version
T.seq = T.seq or {} -- player id -> the number of the bot's newest numbered command ("!tester <cmd> #N"): the answers carry it (O579)

local function storageOf(player)
	local ok, v = pcall(function() return player:getStorageValue(STORE) end)
	return ok and v or nil
end

-- THE guard: every function below starts with it
local function eligible(creature)
	if not creature or not creature:isPlayer() then
		return false
	end
	return H.eligible(creature:getName(), storageOf(creature))
end
T.eligible = eligible

local function anomaly(rule, data)
	data.rule = rule
	data.t = os.time()
	print(H.ANOMALY .. " " .. H.json(data))
end

local function tell(player, kind, data)
	data = data or {}
	local seq = T.seq[player:getId()]
	if seq and data.seq == nil then
		data.seq = seq -- the bot matches an answer to its command by this number, a late answer is never the next one's
	end
	player:sendTextMessage(MESSAGE_INFO_DESCR, H.encode(kind, data))
end

local function posOf(p)
	return {x = p.x, y = p.y, z = p.z}
end

-- O681: the Everfull potions of the tier the survival model plans with (survival_balance_config.lua potionTier 4: the supreme health and mana potion)
local POTION_TIER = 4
local function tierPotions()
	local out = {}
	for _, e in ipairs(ChaosPotionsConfig and ChaosPotionsConfig.everfull or {}) do
		if e.tier == POTION_TIER and (e.line == "health" or e.line == "mana") then
			out[e.line] = e
		end
	end
	return out
end

local function info(player)
	local hp, mp = ItemType(7618), ItemType(7620)
	local voc = player:getVocation()
	local data = {cid = player:getId(), level = player:getLevel(), voc = voc and voc:getId() or nil, pos = posOf(player:getPosition()), -- O685: the class changes in a run (ascension)
		potions = {health = hp and hp:getClientId() or 0, mana = mp and mp:getClientId() or 0}}
	for line, e in pairs(tierPotions()) do -- O681: a flask of the model's tier that the bot carries is the potion it drinks
		local okC, n = pcall(function() return player:getItemCount(e.id) end)
		local it = okC and n and n > 0 and ItemType(e.id) or nil
		if it then
			data.potions[line] = it:getClientId()
		end
	end
	local ever = ChaosPotionsConfig and ChaosPotionsConfig.everfull or {}
	for _, e in ipairs(ever) do
		if (e.tier or 1) <= 1 then -- the starting flasks; the O245 tiers share their key
			local it = ItemType(e.id)
			data.potions["everfull_" .. e.key] = it and it:getClientId() or 0
		end
	end
	tell(player, "info", data)
end

local function temple(player)
	local town = player:getTown()
	return town and town:getTemplePosition() or player:getPosition()
end

-- a free tile next to `center`: the four straight neighbours first, then the corners, then two tiles out; never a
-- floor change or a teleport (the tester would land elsewhere). With `npc`: only a tile where that NPC is the one that
-- answers (no other NPC within talk range as near or nearer: data/lib/chaos_npc_focus.lua lets only the nearest answer)
local RINGS = {{0, -1}, {1, 0}, {0, 1}, {-1, 0}, {-1, -1}, {1, -1}, {1, 1}, {-1, 1}}
for ring = 2, 4 do -- two tiles out, then three and four (a crowd round a stall: `enter npc` asks for four)
	for dx = -ring, ring do
		for dy = -ring, ring do
			if math.max(math.abs(dx), math.abs(dy)) == ring then
				RINGS[#RINGS + 1] = {dx, dy}
			end
		end
	end
end
T.RINGS = RINGS

local function nearestNpc(npc, p)
	local mine = math.max(math.abs(npc:getPosition().x - p.x), math.abs(npc:getPosition().y - p.y))
	for _, c in ipairs(Game.getSpectators(p, false, false, 3, 3, 3, 3) or {}) do
		if c:isNpc() and c:getId() ~= npc:getId() then
			local o = c:getPosition()
			if o.z == p.z and math.max(math.abs(o.x - p.x), math.abs(o.y - p.y)) <= mine then
				return false
			end
		end
	end
	return true
end

local function freeNear(center, npc, reach)
	for _, d in ipairs(RINGS) do
		if math.max(math.abs(d[1]), math.abs(d[2])) <= (reach or 2) then
			local p = Position(center.x + d[1], center.y + d[2], center.z)
			local tile = Tile(p)
			if tile and tile:getGround() and not tile:hasFlag(TILESTATE_BLOCKSOLID) and not tile:getTopCreature()
				and not tile:hasFlag(TILESTATE_FLOORCHANGE) and not tile:hasFlag(TILESTATE_TELEPORT)
				and (not npc or nearestNpc(npc, p)) then
				return p
			end
		end
	end
	return nil
end

-- did the teleport put the tester on the tile? (a tile that refuses it leaves the tester where it was, far from the
-- locker or the NPC it is to use: the bot's "There is no way.")
local function landed(player, spot)
	local here = player:getPosition()
	return here.x == spot.x and here.y == spot.y and here.z == spot.z
end

-- the nearest locker round the temple with a free tile next to it: {pos, id, stackpos, spot}
local function findLocker(origin)
	local found = {}
	for dz = -1, 1 do -- the depot is often a floor up or down from the temple
		for dx = -LOCKER_SEARCH, LOCKER_SEARCH do
			for dy = -LOCKER_SEARCH, LOCKER_SEARCH do
				local z = origin.z + dz
				local tile = z >= 0 and z <= 15 and Tile(Position(origin.x + dx, origin.y + dy, z))
				if tile then
					for _, id in ipairs(LOCKERS) do
						local item = tile:getItemById(id)
						if item then
							local ok, index = pcall(function() return tile:getThingIndex(item) end)
							found[#found + 1] = {pos = tile:getPosition(), id = id,
								d = math.max(math.abs(dx), math.abs(dy)) + 10 * math.abs(dz),
								stackpos = ok and type(index) == "number" and index >= 0 and index or 1}
						end
					end
				end
			end
		end
	end
	table.sort(found, function(x, y) return x.d < y.d end)
	for _, l in ipairs(found) do
		l.spot = freeNear(l.pos, nil, 1) -- next to it: a locker opens from an adjacent tile
		if l.spot then
			return l
		end
	end
	return nil
end

local function findNpc(origin)
	local best, bestD
	for _, c in ipairs(Game.getSpectators(origin, false, false, SEARCH, SEARCH, SEARCH, SEARCH)) do
		if c:isNpc() then
			local p = c:getPosition()
			local d = math.max(math.abs(p.x - origin.x), math.abs(p.y - origin.y))
			if not bestD or d < bestD then
				best, bestD = c, d
			end
		end
	end
	return best
end

local function huntPos(player)
	local x, y, z = player:getStorageValue(STORE + 2), player:getStorageValue(STORE + 3), player:getStorageValue(STORE + 4)
	if x > 0 and y > 0 and z >= 0 then
		return Position(x, y, z)
	end
	return nil
end

-- ---------------------------------------------------------------- the commands
local commands = {}

function commands.info(player)
	info(player)
end

function commands.town(player)
	player:teleportTo(temple(player))
	tell(player, "town", {pos = posOf(player:getPosition())})
end

-- the wild monsters within `radius` tiles of a position on its floor: {{name, hunting level}}
local function monstersNear(pos, radius)
	local near = {}
	for _, c in ipairs(Game.getSpectators(pos, false, false, radius, radius, radius, radius) or {}) do
		if c:isMonster() and not c:getMaster() then
			near[#near + 1] = {c:getName(), Chaos.monsterHuntingLevel(c, 0)}
		end
	end
	return near
end

-- a hunt for this level that has no monster above it (O580): the marks of H.huntCandidates (the hunts whose band is at or
-- under the level, rule of tester_core.safe_hunts) with a free tile and no monster within HUNT_CLEAR tiles above the
-- level (the same margin as H.hotSpot), the first one of at most HUNT_TRIES. Live run 2026-11-15: 314 of 522 town visits
-- ended in "hunt spot too high: <monster> level N" and the bot stayed in the temple for the rest of the hour, because the
-- spot setup chose (the pool level of the spawn file) was not what the live monsters were (their own level).
local HUNT_CLEAR, HUNT_TRIES = 12, 60
local function safeHunt(player)
	local level = player:getLevel()
	local tries = 0
	for _, m in ipairs(H.huntCandidates(ChaosPoi and ChaosPoi.all, level, player.getGuid and player:getGuid() or player:getId())) do
		tries = tries + 1
		if tries > HUNT_TRIES then
			break
		end
		local spot = freeNear(Position(m.x, m.y, m.z), nil, 3)
		if spot and not H.hotSpot(level, monstersNear(spot, HUNT_CLEAR)) then
			return spot, m
		end
	end
	return nil
end

local function setHuntPos(player, p)
	player:setStorageValue(STORE + 2, p.x)
	player:setStorageValue(STORE + 3, p.y)
	player:setStorageValue(STORE + 4, p.z)
end

function commands.hunt(player)
	local p = huntPos(player)
	if not p then
		tell(player, "hunt", {err = "no hunt spot"})
		return
	end
	local hot = H.hotSpot(player:getLevel(), monstersNear(p, HUNT_CHECK))
	local moved
	if hot then
		-- the spot is above the bot (setup chose it from the pool levels, the monsters here are what they are): a hunt of
		-- its level, kept as its spot from now on; none: stay in the temple, the report shows it
		local spot, mark = safeHunt(player)
		if not spot then
			tell(player, "hunt", {err = "hunt spot too high: " .. hot[1] .. " level " .. hot[2]})
			return
		end
		moved = {from = hot[1], level = hot[2], to = mark.n}
		p = spot
		setHuntPos(player, p)
	end
	player:teleportTo(p)
	tell(player, "hunt", {pos = posOf(player:getPosition()), moved = moved})
end

function commands.depot(player)
	local locker = findLocker(temple(player))
	local spot = locker and locker.spot
	if not spot then
		tell(player, "depot", {err = "no depot locker near the temple"})
		return
	end
	player:teleportTo(spot)
	if not landed(player, spot) then
		tell(player, "depot", {err = "the teleport next to the locker was refused", pos = posOf(player:getPosition())})
		return
	end
	local it = ItemType(locker.id)
	tell(player, "depot", {pos = posOf(player:getPosition()), locker = posOf(locker.pos), clientId = it:getClientId(),
		stackpos = locker.stackpos})
end

local function findTrader(origin)
	for _, name in ipairs(TRADERS) do
		local npc = Creature(name)
		if npc and npc:isNpc() and freeNear(npc:getPosition(), npc) then
			return npc
		end
	end
	return findNpc(origin)
end

function commands.shop(player, arg)
	local want = H.parseShop(arg) -- `shop Loot Buyer`: that trader (the sell trip of the bag keeping, O584)
	local npc = want and Creature(want)
	if not (npc and npc:isNpc() and freeNear(npc:getPosition(), npc)) then
		if want then
			tell(player, "shop", {err = "no free tile next to " .. want})
			return
		end
		npc = nil
	end
	npc = npc or findTrader(temple(player))
	local spot = npc and freeNear(npc:getPosition(), npc)
	if not spot then
		tell(player, "shop", {err = "no NPC near the temple"})
		return
	end
	player:teleportTo(spot)
	if not landed(player, spot) then
		tell(player, "shop", {err = "the teleport next to the NPC was refused", pos = posOf(player:getPosition())})
		return
	end
	tell(player, "shop", {pos = posOf(player:getPosition()), npc = npc:getName(), npcPos = posOf(npc:getPosition())})
end

local function marks()
	return ChaosPoi and ChaosPoi.all or {}
end

-- the counts of the places `enter` knows (map marks by kind)
function commands.places(player)
	tell(player, "places", {counts = H.placeCounts(marks())})
end

-- TEST ONLY: bring this tester to a place, or give it a rift key. Only the tester itself moves and receives; an NPC
-- target must be an NPC (a player's name is refused)
function commands.enter(player, arg)
	local place = H.parsePlace(arg)
	if not place then
		tell(player, "enter", {err = "unknown place", arg = tostring(arg)})
		return
	end
	if place.kind == "rift" then
		local rift, cfg = ChaosRift, ChaosRiftConfig
		if not (rift and rift.giveKey and cfg and cfg.key) then
			tell(player, "enter", {kind = "rift", err = "no rifts on this server"})
			return
		end
		local inbox = rift.giveKey(player, {tier = place.tier, mods = {}}, "Tester key")
		local it = ItemType(cfg.key.itemId)
		-- the key is read back and taken again: one key per check filled the testers' bags over a long run
		local key = player:getItemById(cfg.key.itemId, true)
		local held = key ~= nil
		local bagFull = false
		if key then
			pcall(key.remove, key, 1)
		elseif inbox == true then
			-- a full bag: RF.giveKey sends the key to the inbox (live run 2026-11-01); taken from there again
			bagFull = true
			pcall(function()
				for _, i in ipairs(player:getInbox():getItems(true) or {}) do
					if i:getId() == cfg.key.itemId then
						i:remove(1)
						break
					end
				end
			end)
		else
			-- a full bag: player:addItem puts the key on the ground under the player (the engine's rule, no bug)
			local tile = Tile(player:getPosition())
			local dropped = tile and tile:getItemById(cfg.key.itemId)
			if dropped then
				bagFull = true
				pcall(dropped.remove, dropped)
			end
		end
		-- a rift is opened in a protection zone: a bot that walked to one (O592) stays; otherwise the temple, counted as a teleport
		local okZone, inZone = pcall(function()
			local tile = Tile(player:getPosition())
			return tile ~= nil and tile:hasFlag(TILESTATE_PROTECTIONZONE)
		end)
		local teleported = not (okZone and inZone)
		if teleported then
			player:teleportTo(temple(player))
		end
		tell(player, "enter", {kind = "rift", tier = place.tier, keyClientId = it and it:getClientId() or 0, held = held,
			bagFull = bagFull or nil, pos = posOf(player:getPosition()), teleported = teleported})
		return
	end
	if place.kind == "npc" then
		local npc = Creature(place.name)
		if not npc or not npc:isNpc() then
			tell(player, "enter", {kind = "npc", err = "no such NPC", name = place.name})
			return
		end
		-- four tiles out: an NPC with a stall in the hub (Archivist Odrenna's trial question counts within her range) has the
		-- 24 tiles round it taken by the other testers at times (live run 2026-11-15: 4 checks read "not in the game")
		local spot = freeNear(npc:getPosition(), nil, NPC_REACH)
		if not spot then
			tell(player, "enter", {kind = "npc", err = "no free tile", name = place.name, crowd = true,
				npcPos = posOf(npc:getPosition())})
			return
		end
		player:teleportTo(spot)
		tell(player, "enter", {kind = "npc", npc = npc:getName(), npcPos = posOf(npc:getPosition()),
			pos = posOf(player:getPosition())})
		return
	end
	local mark, count = H.pickMark(marks(), place.kind, place.n)
	local spot = mark and freeNear(Position(mark.x, mark.y, mark.z))
	if not spot then
		tell(player, "enter", {kind = place.kind, err = mark and "no free tile" or "no such place", count = count})
		return
	end
	player:teleportTo(spot)
	tell(player, "enter", {kind = place.kind, name = mark.n, count = count, pos = posOf(player:getPosition())})
end

-- !tester spellquest <state | reset | set | kill | trial | leave | complete> (H.parseSpellQuest): the line spell quests
-- (spellquest.lua) for the tester itself, on the same code the game runs: the same storages as the staff's /spellquest, a
-- credited death through ChaosSpellQuest.credit, the trial question through ChaosSpellQuest.enterTrial (needs Archivist
-- Odrenna within range: `!tester enter npc Archivist Odrenna` first), the reward through ChaosSpellQuest.complete.
-- Answers {quest, step, code, kills, fragments, need = {kills, fragments, level}, spell, learned, ...}.
-- a trial run of the tester that is not over: trials.lua finish marks it over at once and takes the player out (and
-- drops the run) in a later event, so a run still listed right after a leave is not running any more
local function trialRunning(player)
	local tr = ChaosTrials and ChaosTrials.runs and ChaosTrials.runs[player:getId()]
	return tr ~= nil and not tr.over
end

local function spellQuestState(player, extra)
	local S, Q = ChaosSpellQuest, ChaosSpellQuestCore
	local n, step, code = S.current(player)
	local data = {level = player:getLevel(), quest = n, step = step, code = code}
	local idx = Q.lineOf(player:getVocation():getId())
	if n and idx then
		local k = Q.keys(n)
		local qc = Q.quest(n)
		data.kills, data.fragments = Q.count0(player:getStorageValue(k.kills)), Q.count0(player:getStorageValue(k.fragments))
		data.pity = Q.count0(player:getStorageValue(k.pity))
		data.need = {kills = qc.kills, fragments = qc.fragments, level = qc.level}
		data.spell = Q.spellName(idx, n)
		data.learned = data.spell and player:hasLearnedSpell(data.spell) and true or false
	end
	for key, v in pairs(extra or {}) do
		data[key] = v
	end
	return data
end

function commands.spellquest(player, arg)
	local S, Q = ChaosSpellQuest, ChaosSpellQuestCore
	if not (S and Q and S.credit and S.complete and S.enterTrial) then
		tell(player, "spellquest", {err = "no spell quest system"})
		return
	end
	local a, why = H.parseSpellQuest(arg)
	if not a then
		tell(player, "spellquest", {err = why})
		return
	end
	local idx = Q.lineOf(player:getVocation():getId())
	if not idx then
		tell(player, "spellquest", {err = "no class line", code = "noline"})
		return
	end
	if a.sub == "state" then
		tell(player, "spellquest", spellQuestState(player))
	elseif a.sub == "reset" then
		for n = 1, Q.count() do
			for _, key in pairs(Q.keys(n)) do
				player:setStorageValue(key, -1)
			end
		end
		S.sync(player)
		tell(player, "spellquest", spellQuestState(player))
	elseif a.sub == "set" then
		if not Q.quest(a.quest) then
			tell(player, "spellquest", {err = "no such quest", quest = a.quest})
			return
		end
		local k = Q.keys(a.quest)
		local out = Q.applySet({mask = player:getStorageValue(k.lines), pity = player:getStorageValue(k.pity)}, idx, a.quest,
			a.step, a.kills, a.fragments)
		player:setStorageValue(k.step, out.step)
		player:setStorageValue(k.kills, out.kills)
		player:setStorageValue(k.fragments, out.fragments)
		player:setStorageValue(k.pity, out.pity)
		player:setStorageValue(k.lines, out.mask)
		player:setStorageValue(k.cooldown, 0)
		S.sync(player)
		tell(player, "spellquest", spellQuestState(player))
	elseif a.sub == "kill" then
		local weight, counted = 0, 0
		local fragments = {}
		for _ = 1, a.n do
			local before = spellQuestState(player)
			local w = S.credit(player, {boss = a.boss, monsterLevel = player:getLevel(), hunt = true, tier = "normal"})
			if w > 0 then
				counted = counted + 1
				weight = weight + w
			end
			local after = spellQuestState(player)
			if after.quest == before.quest and (after.fragments or 0) > (before.fragments or 0) then
				fragments[#fragments + 1] = after.fragments
			end
		end
		tell(player, "spellquest", spellQuestState(player, {counted = counted, weight = weight, rolled = #fragments}))
	elseif a.sub == "trial" then
		-- near before the entry: a trial that opens takes the tester into its chamber, away from Odrenna
		local near = S.archivistNear(player) ~= nil
		-- the bot comes from its hunt: the fight mark of its last hit outlives the teleport (live run 2026-11-01: "You
		-- cannot enter a trial in combat"). The rule is the game's own; the tester only waits it out at once
		if CONDITION_INFIGHT and not player:isPzLocked() then
			player:removeCondition(CONDITION_INFIGHT)
		end
		local ok, text = S.enterTrial(player)
		local running = trialRunning(player)
		tell(player, "spellquest", spellQuestState(player, {entered = ok and true or false, text = text, running = running,
			near = near}))
	elseif a.sub == "leave" then
		local left = ChaosTrials and ChaosTrials.leave and ChaosTrials.leave(player) or false
		tell(player, "spellquest", spellQuestState(player, {left = left, running = trialRunning(player)}))
	elseif a.sub == "complete" then
		local n, step, code = S.current(player)
		if code ~= "ok" or step ~= Q.STEP.TRIAL then
			tell(player, "spellquest", spellQuestState(player, {err = "the quest is not on its trial step"}))
			return
		end
		local spell = Q.spellName(idx, n)
		local gold = player:getBankBalance()
		local lines = S.complete(player, n)
		tell(player, "spellquest", spellQuestState(player, {completed = n, taught = spell,
			taughtKnown = player:hasLearnedSpell(spell) and true or false, gold = player:getBankBalance() - gold, lines = #lines}))
	end
end

T.commands = commands

local talk = TalkAction("!tester")
function talk.onSay(player, words, param)
	if not eligible(player) or not T.present() then
		return true -- a player's words are left alone (and a stopped helper does nothing)
	end
	local cmd, arg, seq = H.parseCommand(param)
	T.seq[player:getId()] = seq -- nil for a command with no number: its answers carry none
	if not cmd or not commands[cmd] then
		tell(player, "error", {err = "unknown command", param = tostring(param)})
		return false
	end
	local ok, err = pcall(commands[cmd], player, arg)
	if not ok then
		print("[tester-helper] " .. cmd .. ": " .. tostring(err))
		tell(player, "error", {err = tostring(err), cmd = cmd})
	end
	return false
end
talk:separator(" ")
talk:register()

-- the supplies a tester keeps: id -> number (SUPPLIES)
local WANT = {}
for _, s in ipairs(SUPPLIES) do
	WANT[s[1]] = s[2]
end

local WANT_SUPPLY = {}
for id in pairs(WANT) do
	WANT_SUPPLY[id] = true
end

-- potions topped up to their number when under half of it (a tester dies about thirty times an hour and loses some)
local function topUp(player)
	local bag = player:getSlotItem(CONST_SLOT_BACKPACK)
	if not bag then
		return 0
	end
	local held = {}
	for id in pairs(WANT) do
		held[id] = player:getItemCount(id)
	end
	local _, add = H.bagPlan({}, WANT, held)
	for _, a in ipairs(add) do
		bag:addItem(a.id, a.count)
	end
	return #add
end

-- O584: `!tester bag` keeps the drops. It tops the potions up and REPORTS the backpack (the slots, what each is worth to the Loot
-- Buyer, a piece better than the worn one, the junk to drop); the bot sells, wears and drops by the game's own packets.
-- `!tester bag wipe` is the old emptying of the loot, the last resort when the bot could not keep the bag open (a counted failure).
local BAG_SLOTS = { -- ItemType:getSlotPosition() bit -> CONST_SLOT_*; the hands stay as they are (the tester's weapon)
	{1, CONST_SLOT_HEAD}, {2, CONST_SLOT_NECKLACE}, {8, CONST_SLOT_ARMOR}, {64, CONST_SLOT_LEGS},
	{128, CONST_SLOT_FEET}, {256, CONST_SLOT_RING},
}
local COINS = {[2148] = true, [2152] = true, [2160] = true}

local function bagSlotOf(itemType)
	local bits = itemType:getSlotPosition() or 0
	for _, e in ipairs(BAG_SLOTS) do
		if math.floor(bits / e[1]) % 2 == 1 then
			return e[2]
		end
	end
	return nil
end

local function pieceScore(item, itemType)
	local function num(f)
		local ok, v = pcall(f)
		return ok and tonumber(v) or 0
	end
	local ilvl = 0
	if ChaosCrafting and ChaosCrafting.levelOf then
		ilvl = num(function() return ChaosCrafting.levelOf(item) end)
	end
	return num(function() return itemType:getArmor() end) * 10 + num(function() return itemType:getDefense() end) * 4
		+ num(function() return itemType:getAttack() end) * 2 + ilvl
end

local function priceInfo(item)
	local P = ChaosItemPrices
	if not (P and P.basePrice) then
		return 0, false
	end
	local okP, price = pcall(P.basePrice, item:getId())
	local blocked = false
	if P.saleBlock then
		local okB, why = pcall(P.saleBlock, item)
		blocked = okB and why and true or false
	end
	return okP and tonumber(price) or 0, blocked
end

local function bagRows(player, bag)
	local rows = {}
	for i = 0, bag:getSize() - 1 do
		local item = bag:getItem(i)
		if item then
			local it = ItemType(item:getId())
			local price, blocked = priceInfo(item)
			local slot = bagSlotOf(it)
			rows[#rows + 1] = {i = i, id = item:getId(), clientId = it:getClientId(), count = item:getCount(),
				price = price, blocked = blocked, container = item:isContainer(), slot = slot,
				score = slot and pieceScore(item, it) or 0}
		end
	end
	local ctx = {want = WANT_SUPPLY, currency = COINS}
	for _, r in ipairs(rows) do
		r.kind = H.itemKind(r, ctx)
	end
	return rows
end

local function wornScores(player)
	local worn = {}
	for _, e in ipairs(BAG_SLOTS) do
		local item = player:getSlotItem(e[2])
		worn[e[2]] = item and pieceScore(item, ItemType(item:getId())) or 0
	end
	return worn
end

function commands.bag(player, arg)
	local mode = H.parseBag(arg)
	local bag = player:getSlotItem(CONST_SLOT_BACKPACK)
	if not mode then
		tell(player, "bag", {err = "bag takes nothing or wipe"})
		return
	end
	if not bag then
		tell(player, "bag", {err = "no backpack"})
		return
	end
	if mode == "wipe" then
		local list, rows = {}, {}
		for _, item in ipairs(bag:getItems() or {}) do
			list[#list + 1] = {id = item:getId(), count = item:getCount()}
			rows[#rows + 1] = item
		end
		local remove = H.bagPlan(list, WANT, {})
		for _, i in ipairs(remove) do
			rows[i]:remove()
		end
		local ok, added = pcall(topUp, player)
		tell(player, "bag", {wiped = #remove, topped = ok and added or 0})
		return
	end
	local ok, added = pcall(topUp, player)
	local rows = bagRows(player, bag)
	local report = H.bagReport(rows, wornScores(player), bag:getCapacity(), nil)
	report.topped = ok and added or 0
	report.pos = posOf(player:getPosition())
	report.bagClientId = ItemType(bag:getId()):getClientId()
	report.gold = player:getMoney()
	local okP, hp, mp = pcall(function() return player:getItemCount(7618), player:getItemCount(7620) end)
	report.potions = okP and {health = hp, mana = mp} or nil -- O658: the gear-up buys what it is short of
	tell(player, "bag", report)
end

-- O584: `!tester give item | orb <key> [n] | gem | rune | charm | card`: what the crafting checks (tester_checks.py check_craft_*) work
-- on. The item is marked with a custom attribute so its backpack slot is found again; the answer names the slot, the ids and the
-- backpack's client id (to open it as container 0). Plain items: no rarity, no unique roll.
local function slotOfMarked(bag, mark)
	for i = 0, bag:getSize() - 1 do
		local item = bag:getItem(i)
		if item then
			local ok, v = pcall(function() return item:getCustomAttribute("tester_give") end)
			if ok and v == mark then
				return i, item
			end
		end
	end
	return nil
end

local giveSeq = 0

function commands.give(player, arg)
	local g = H.parseGive(arg)
	if not g then
		tell(player, "give", {err = "give takes item | orb <key> [n] | gem | rune | charm | card"})
		return
	end
	local bag = player:getSlotItem(CONST_SLOT_BACKPACK)
	if not bag then
		tell(player, "give", {err = "no backpack"})
		return
	end
	local ok, ans = pcall(function()
		local id, count, item
		if g.what == "item" then
			local K = ChaosTestKit
			local kit = K and K.kits and K.kindFor and K.kits[K.kindFor(player:getVocation():getId())]
			id = kit and kit.slots and (kit.slots[CONST_SLOT_LEFT] or kit.slots[CONST_SLOT_RIGHT])
			if not id then
				return {err = "no kit item for this class"}
			end
			local level = math.max(1, math.min(150, player:getLevel()))
			item = ChaosCrafting.createItem(id, 0, level)
		elseif g.what == "orb" then
			local orb = ChaosCrafting.orbByKey and ChaosCrafting.orbByKey[g.key]
			if not orb then
				return {err = "no orb " .. tostring(g.key)}
			end
			id, count = orb.id, g.n
		elseif g.what == "gem" then
			id, count = ChaosGems.gemId(1, 1), g.n
		elseif g.what == "rune" then
			id, count = ChaosSupports.runeId(1, 1), g.n
		elseif g.what == "charm" then
			local CH, CC, cfg = ChaosCharms, ChaosCharmsCore, ChaosCharmsConfig
			if not (CH and CH.makeItem and CC and cfg) then
				return {err = "the charm system is not loaded"}
			end
			item = CH.makeItem(CC.rollCharm(cfg, {shape = "small", rarity = 3, ilvl = 100}))
		else
			local cards = ChaosCardsCore and ChaosCardsCore.cardIds and ChaosCardsCore.cardIds()
			id, count = cards and cards[1], 1
			if not id then
				return {err = "the card system is not loaded"}
			end
		end
		if not item then
			item = Game.createItem(id, count or 1)
			if not item then
				return {err = "the item could not be made"}
			end
		end
		id = item:getId()
		local stackable = ItemType(id):isStackable()
		giveSeq = giveSeq + 1
		local mark = "m" .. giveSeq .. "_" .. tostring(player:getId())
		if not stackable then
			item:setCustomAttribute("tester_give", mark) -- a stack merges: it is found by its id instead
		end
		local rc = player:addItemEx(item, false)
		if rc ~= nil and rc ~= RETURNVALUE_NOERROR then
			return {err = "no room for the item"}
		end
		local index, put
		if stackable then
			for i = 0, bag:getSize() - 1 do
				local c = bag:getItem(i)
				if c and c:getId() == id then
					index, put = i, c
					break
				end
			end
		else
			index, put = slotOfMarked(bag, mark)
		end
		if not index then
			return {err = "the item went somewhere else than the backpack"}
		end
		local it = ItemType(put:getId())
		return {what = g.what, key = g.key, id = put:getId(), clientId = it:getClientId(), index = index, path = tostring(index),
			count = put:getCount(), bagClientId = ItemType(bag:getId()):getClientId(), level = player:getLevel()}
	end)
	tell(player, "give", ok and ans or {err = tostring(ans):sub(1, 120)})
end

-- ---------------------------------------------------------------- O582 closed test mode
-- "!tester closed": the facts the closed-mode checks read, about the tester that asks and the deployed rules: the switch, the
-- guards of every closed system (a tester against a player is refused, testers together only with the mode on), the tester's
-- guild and its side, its market realm, its arena queue and match. Reads only; nothing is changed.
function commands.closed(player)
	local K = ChaosTestersCore
	local data = {loaded = K ~= nil, on = K and K.closedOn() or false, guards = H.closedGuards(K), realm = K and K.REALM or 0}
	local okG, gid, gname = pcall(function() return ChaosGuild and ChaosGuild.guildOf(player) end)
	if okG and gid then
		data.guild = {id = gid, name = gname, level = player:getGuildLevel(), side = ChaosTesters and ChaosTesters.guildSide and ChaosTesters.guildSide(gid, gname) or nil}
	end
	if ChaosBazaar and ChaosBazaar.lockOf then
		local okB, row = pcall(ChaosBazaar.lockOf, player:getGuid())
		data.bazaar = {locked = okB and row ~= nil or false} -- a listing of the character locks it (bazaar.lua)
	end
	if ChaosArena then
		data.arena = {queued = ChaosArena.isQueued(player) and true or false, inMatch = ChaosArena.isInside(player) and true or false}
	end
	if ChaosBattleground then
		data.battleground = {queued = ChaosBattleground.isQueued(player) and true or false,
			inMatch = ChaosBattleground.isInside(player) and true or false}
	end
	if ChaosPvpZone then
		data.pvp = {inside = ChaosPvpZone.isInside(player) and true or false}
	end
	tell(player, "closed", data)
end

-- ---------------------------------------------------------------- O589 the way on foot
-- the engine's own pathfinding from the tester to a position, as directions 0-7 the bot walks (a player's auto walk). minD / maxD:
-- how near to the target the walk may end (0, 1: on it or next to it; 1, 3: within reach of a monster). nil + the reason when the
-- engine has no call, no path (a wall, another floor) or an empty one
local function pathTo(player, pos, minD, maxD)
	if player:getPosition().z ~= pos.z then
		return nil, "another floor"
	end
	local ok, path = pcall(function()
		return player:getPathTo(Position(pos.x, pos.y, pos.z), minD or 0, maxD or 1, true, true, 0)
	end)
	local dirs = ok and H.pathDirections(path) or {}
	if #dirs == 0 then
		return nil, "no path"
	end
	return dirs
end

-- "!tester path <kind> [N] | npc <name> | pos X Y Z": the mark (the n-th of its kind, as `enter` takes it), the NPC or the position;
-- `here` when the tester stands next to it already. Nothing moves.
function commands.path(player, arg)
	local place, usage = H.parsePath(arg)
	if not place then
		tell(player, "path", {err = usage})
		return
	end
	local dest, name
	if place.kind == "pos" then
		dest = {x = place.x, y = place.y, z = place.z}
	elseif place.kind == "npc" then
		local npc = Creature(place.name)
		if not npc or not npc:isNpc() then
			tell(player, "path", {err = "no such NPC", name = place.name})
			return
		end
		dest, name = posOf(npc:getPosition()), npc:getName()
	else
		local mark, count = H.pickMark(marks(), place.kind, place.n)
		if not mark then
			tell(player, "path", {err = "no such place", kind = place.kind, count = count})
			return
		end
		dest, name = {x = mark.x, y = mark.y, z = mark.z}, mark.n
	end
	local here = posOf(player:getPosition())
	if here.z == dest.z and math.max(math.abs(here.x - dest.x), math.abs(here.y - dest.y)) <= 1 then
		tell(player, "path", H.pathAnswer(here, dest, {}, {here = true, name = name}))
		return
	end
	local dirs, why = pathTo(player, dest, 0, 1)
	if not dirs then
		tell(player, "path", H.pathAnswer(here, dest, {}, {err = why, name = name}))
		return
	end
	tell(player, "path", H.pathAnswer(here, dest, dirs, {name = name}))
end

-- ---------------------------------------------------------------- O589 the dungeons in closed test mode
-- "!tester dungeon [state | path | close]": reads ChaosDungeons.probe (what a person sees of the dungeons); `path` is the way on foot to
-- the guide's goal inside a run (the nearest monster or the boss: within reach of it); `close` ends the testers' own run of the
-- asker so the dungeon is free. Nothing here queues, moves inside or fights.
function commands.dungeon(player, arg)
	local what, usage = H.parseDungeon(arg)
	if not what then
		tell(player, "dungeon", {err = usage})
		return
	end
	local D = ChaosDungeons
	if not (D and D.probe) then
		tell(player, "dungeon", {err = "no dungeon system"})
		return
	end
	if what == "close" then
		local closed = D.testerClose and D.testerClose(player) or false
		tell(player, "dungeon", H.dungeonAnswer(D.probe(player), {closed = closed and true or false}))
		return
	end
	local probe = D.probe(player)
	if type(what) == "table" then -- O651: the TEST ONLY unlocked difficulty (a person earns it by clearing the one before)
		local got, why = nil, "no dungeon system"
		if D.testerUnlock then
			got, why = D.testerUnlock(player, what.id, what.difficulty)
		end
		tell(player, "dungeon", H.dungeonAnswer(D.probe(player), got and {unlocked = got} or {err = why}))
		return
	end
	if what == "weekly" then -- O651: the Weekly Challenge as a person sees it: the week, the theme, the boards (no tester on them)
		local WCH = ChaosWeeklyChallenge
		if not (WCH and WCH.probe) then
			tell(player, "dungeon", H.dungeonAnswer(probe, {err = "no weekly challenge"}))
			return
		end
		tell(player, "dungeon", H.dungeonAnswer(probe, {weekly = H.cutValue(WCH.probe(player), 2)}))
		return
	end
	if what == "path" then
		local goal = probe.guide and probe.guide.goal
		if not probe.inside or not goal then
			tell(player, "dungeon", H.dungeonAnswer(probe, {err = probe.inside and "no goal" or "not inside a dungeon run"}))
			return
		end
		local here = posOf(player:getPosition())
		local dirs, why = pathTo(player, goal, 1, 3)
		if not dirs then
			tell(player, "dungeon", H.dungeonAnswer(probe, {err = why}))
			return
		end
		tell(player, "dungeon", H.dungeonAnswer(probe, {path = dirs, dist = here.z == goal.z and math.max(math.abs(here.x - goal.x),
			math.abs(here.y - goal.y)) or nil}))
		return
	end
	tell(player, "dungeon", H.dungeonAnswer(probe))
end

-- ---------------------------------------------------------------- O588 the raid in closed test mode
-- "!tester raid [state | path | portal | close]": reads ChaosRaid.probe (what a person sees of the raid); `path` is the way on foot to
-- a tile next to the entrance portal (Creature:getPathTo, the engine's own pathfinding: the bot walks it step by step); `portal` puts
-- the tester on a free tile next to the portal, as `enter` does for an NPC or a locker (when no path is found; the bot steps onto
-- the portal itself and starts the raid from its window); `close` ends the testers' own empty raid so the slot is free. Nothing
-- here opens, moves inside or fights.
function commands.raid(player, arg)
	local what, usage = H.parseRaid(arg)
	if not what then
		tell(player, "raid", {err = usage})
		return
	end
	local R = ChaosRaid
	if not (R and R.probe) then
		tell(player, "raid", {err = "no raid system"})
		return
	end
	if what == "close" then
		local closed = R.testerClose and R.testerClose(player) or false
		tell(player, "raid", H.raidAnswer(R.probe(player), {closed = closed and true or false}))
		return
	end
	if what == "path" then
		local probe = R.probe(player)
		local portal = probe.portal
		if probe.inside or not portal then
			tell(player, "raid", {err = probe.inside and "already inside the raid" or "no raid portal"})
			return
		end
		local ok, path = pcall(function()
			return player:getPathTo(Position(portal.x, portal.y, portal.z), 0, 1, true, true, 0)
		end)
		local dirs = ok and H.pathDirections(path) or {}
		if #dirs == 0 then
			tell(player, "raid", {err = "no path to the raid portal"})
			return
		end
		tell(player, "raid", H.raidAnswer(probe, {path = dirs}))
		return
	end
	if what == "portal" then
		local probe = R.probe(player)
		local portal = probe.portal
		if probe.inside then
			tell(player, "raid", {err = "already inside the raid"})
			return
		end
		local spot = portal and freeNear(Position(portal.x, portal.y, portal.z), nil, 1)
		if not spot then
			tell(player, "raid", {err = "no free tile next to the raid portal"})
			return
		end
		player:teleportTo(spot)
		if not landed(player, spot) then
			tell(player, "raid", {err = "the teleport next to the raid portal was refused"})
			return
		end
	end
	tell(player, "raid", H.raidAnswer(R.probe(player)))
end

-- ---------------------------------------------------------------- O592 the siege, the guild boss and the rift
-- the way on foot to the guide's goal of a probe (mode "walk" with a goal): the answer to merge, or nil + the reason
local function goalPath(player, probe)
	local g = probe.guide
	if type(g) ~= "table" or g.mode ~= "walk" or type(g.goal) ~= "table" then
		return nil, "no goal"
	end
	local here = posOf(player:getPosition())
	local reach = type(g.reach) == "table" and g.reach or {1, 3}
	if here.z == g.goal.z and math.max(math.abs(here.x - g.goal.x), math.abs(here.y - g.goal.y)) <= math.max(reach[2] or 0, 0)
		and (reach[2] or 0) > 0 then
		return H.pathAnswer(here, g.goal, {}, {here = true})
	end
	local dirs, why = pathTo(player, g.goal, reach[1] or 0, reach[2] or 1)
	if not dirs then
		return nil, why
	end
	return H.pathAnswer(here, g.goal, dirs, nil)
end

-- the way on foot to a fixed tile (a portal, the stone): next to it
local function tilePath(player, dest)
	local here = posOf(player:getPosition())
	if here.z == dest.z and math.max(math.abs(here.x - dest.x), math.abs(here.y - dest.y)) <= 1 then
		return H.pathAnswer(here, dest, {}, {here = true})
	end
	local dirs, why = pathTo(player, dest, 0, 1)
	if not dirs then
		return nil, why
	end
	return H.pathAnswer(here, dest, dirs, nil)
end

-- a free tile next to a portal, the bot put there when no path is found (the bot steps onto the portal itself)
local function stepNext(player, dest)
	local spot = freeNear(Position(dest.x, dest.y, dest.z), nil, 1)
	if not spot then
		return nil, "no free tile next to the portal"
	end
	player:teleportTo(spot)
	if not landed(player, spot) then
		return nil, "the teleport next to the portal was refused"
	end
	return true
end

-- "!tester siege [state | start | path | portal | close]": reads ChaosSiege.probe (what a person sees of the siege). `start` is the TEST ONLY
-- start of the testers' own siege of the two tester guilds (never the weekly schedule's, only with the switch on, never ahead of players:
-- ChaosSiege.startTester asks); `path` the way on foot to the portal, or inside to the gate or the obelisk; `portal` the step next to the
-- portal when there is no path; `close` ends the testers' own siege (standings and rewards, nothing stored)
function commands.siege(player, arg)
	local what, usage = H.parseSiege(arg)
	if not what then
		tell(player, "siege", {err = usage})
		return
	end
	local S = ChaosSiege
	if not (S and S.probe and S.startTester) then
		tell(player, "siege", {err = "no siege system"})
		return
	end
	if what == "start" then
		local started, why = S.startTester()
		tell(player, "siege", H.siegeAnswer(S.probe(player), {started = started and true or false,
			why = (not started) and tostring(why):sub(1, 90) or nil}))
		return
	end
	if what == "close" then
		local closed = S.testerClose and S.testerClose(player) or false
		tell(player, "siege", H.siegeAnswer(S.probe(player), {closed = closed and true or false}))
		return
	end
	local probe = S.probe(player)
	if what == "path" then
		local got, why
		if probe.inside then
			got, why = goalPath(player, probe)
		elseif probe.portal then
			got, why = tilePath(player, probe.portal)
		else
			why = probe.running and "no siege portal" or "no siege running"
		end
		tell(player, "siege", H.siegeAnswer(probe, got or {err = why}))
		return
	end
	if what == "portal" then
		if probe.inside or not probe.portal then
			tell(player, "siege", H.siegeAnswer(probe, {err = probe.inside and "already inside the siege" or "no siege portal"}))
			return
		end
		local done, why = stepNext(player, probe.portal)
		tell(player, "siege", H.siegeAnswer(S.probe(player), done and {} or {err = why}))
		return
	end
	tell(player, "siege", H.siegeAnswer(probe))
end

-- the Guild Hall Portal next to a temple (a forcefield with the hall's action id, cityportals.lua): the nearest one on the temple's floor
local function hallPortalNear(origin)
	local cfg = Chaos.guildConfig and Chaos.guildConfig.hall
	if not (cfg and cfg.ids and cfg.aid) then
		return nil
	end
	local best, bd
	for dx = -HALL_SEARCH, HALL_SEARCH do
		for dy = -HALL_SEARCH, HALL_SEARCH do
			local tile = Tile(Position(origin.x + dx, origin.y + dy, origin.z))
			local item = tile and tile:getItemById(cfg.ids.portal)
			if item and item:getActionId() == cfg.aid.enter then
				local d = math.max(math.abs(dx), math.abs(dy))
				if not bd or d < bd then
					best, bd = {x = origin.x + dx, y = origin.y + dy, z = origin.z}, d
				end
			end
		end
	end
	return best
end

-- "!tester guildboss [state | path | hall | close]": reads ChaosGuildBoss.probe. `path` is the way on foot to the guild hall portal (outside),
-- to the Summoning Stone (in the hall) or to the guide's goal (in the arena); `hall` brings the tester into its hall as the portal does
-- (when there is no path); `close` ends the testers' own run. The window requests (buy the hall, feed the stone, summon) are the bot's own.
function commands.guildboss(player, arg)
	local what, usage = H.parseGuildBoss(arg)
	if not what then
		tell(player, "guildboss", {err = usage})
		return
	end
	local B = ChaosGuildBoss
	if not (B and B.probe) then
		tell(player, "guildboss", {err = "no guild boss system"})
		return
	end
	if what == "close" then
		local closed = B.testerClose and B.testerClose(player) or false
		tell(player, "guildboss", H.guildBossAnswer(B.probe(player), {closed = closed and true or false}))
		return
	end
	local probe = B.probe(player)
	if what == "path" then
		local got, why
		if probe.inside then
			got, why = goalPath(player, probe)
		elseif probe.hasHall and probe.inHall and probe.stone then
			got, why = tilePath(player, probe.stone)
			if got then
				got.target = "stone"
			end
		elseif probe.hasHall then
			local portal = hallPortalNear(temple(player))
			if portal then
				got, why = tilePath(player, portal)
				if got then
					got.target = "hall"
				end
			else
				why = "no guild hall portal near the temple"
			end
		else
			why = "the guild has no hall"
		end
		tell(player, "guildboss", H.guildBossAnswer(probe, got or {err = why}))
		return
	end
	if what == "hall" then
		local G = ChaosGuild
		if probe.inside or not probe.hasHall then
			tell(player, "guildboss", H.guildBossAnswer(probe, {err = probe.inside and "already inside the arena" or "the guild has no hall"}))
			return
		end
		local entered = G and G.enterHall and G.enterHall(player, true) or false
		tell(player, "guildboss", H.guildBossAnswer(B.probe(player), entered and {} or {err = "the hall could not be entered"}))
		return
	end
	tell(player, "guildboss", H.guildBossAnswer(probe))
end

-- "!tester rift [state | key [tier] | greater [g] | seal | fail | path | close]": reads ChaosRift.probe. `key` puts a key into the backpack where the bot stands (the
-- highest tier its level opens when none is named): it must be in a protection zone, as a player opening a rift must; the bot uses the key
-- itself. `path` is the way on foot to the guide's goal inside (the guardian, else the nearest pack monster of the floor); `close` ends the
-- bot's own run and takes a refunded key out of the backpack again.
function commands.rift(player, arg)
	local want, usage = H.parseRift(arg)
	if not want then
		tell(player, "rift", {err = usage})
		return
	end
	local RF, cfg, R = ChaosRift, ChaosRiftConfig, ChaosRiftCore
	if not (RF and RF.probe and RF.giveKey and cfg and cfg.key and R) then
		tell(player, "rift", {err = "no rifts on this server"})
		return
	end
	local function tierOf()
		return H.riftTierFor(player:getLevel(), cfg.maxTier or 15, function(t) return R.tierInfo(cfg, t).minLevel end)
	end
	if want.what == "close" then
		local closed = RF.testerClose and RF.testerClose(player) or false
		for _ = 1, 5 do -- the refunded key (a run whose guardian lived) is no loot of the bot's: out again
			local key = player:getItemById(cfg.key.itemId, true)
			if not key then
				break
			end
			pcall(key.remove, key, 1)
		end
		tell(player, "rift", H.riftAnswer(RF.probe(player), {closed = closed and true or false, tier = tierOf()}))
		return
	end
	local probe = RF.probe(player)
	if want.what == "key" then
		local tier = want.tier or tierOf()
		if not tier then
			tell(player, "rift", H.riftAnswer(probe, {err = "level too low for a rift", level = player:getLevel()}))
			return
		end
		if probe.inside then
			tell(player, "rift", H.riftAnswer(probe, {err = "already inside a rift"}))
			return
		end
		if not probe.pz then
			tell(player, "rift", H.riftAnswer(probe, {err = "not in a protection zone", tier = tier}))
			return
		end
		local inbox = RF.giveKey(player, {tier = tier, mods = {}}, "Tester key")
		local key = player:getItemById(cfg.key.itemId, true)
		local it = ItemType(cfg.key.itemId)
		tell(player, "rift", H.riftAnswer(RF.probe(player), {tier = tier, held = key ~= nil, keyClientId = it and it:getClientId() or 0,
			bagFull = (key == nil and inbox == true) or nil}))
		return
	end
	if want.what == "greater" then -- O671: a Greater Rift Key (tier 15 + g), used by the bot like any key
		if probe.inside then
			tell(player, "rift", H.riftAnswer(probe, {err = "already inside a rift"}))
			return
		end
		if not probe.pz then
			tell(player, "rift", H.riftAnswer(probe, {err = "not in a protection zone", greater = want.greater}))
			return
		end
		local shown, inbox
		if RF.testerGreaterKey then -- two results: no `a and f()` here, it keeps one
			shown, inbox = RF.testerGreaterKey(player, want.greater)
		end
		if not shown then
			tell(player, "rift", H.riftAnswer(probe, {err = tostring(inbox or "no Greater Rift on this server")}))
			return
		end
		local key = player:getItemById(cfg.key.itemId, true)
		local it = ItemType(cfg.key.itemId)
		tell(player, "rift", H.riftAnswer(RF.probe(player), {tier = shown, greater = want.greater, held = key ~= nil, keyClientId = it and it:getClientId() or 0,
			bagFull = (key == nil and inbox == true) or nil}))
		return
	end
	if want.what == "seal" then
		local ok, why = false, "no such helper"
		if RF.testerSeal then
			ok, why = RF.testerSeal(player)
		end
		tell(player, "rift", H.riftAnswer(RF.probe(player), ok and {sealing = true} or {err = tostring(why)}))
		return
	end
	if want.what == "fail" then
		local ok = RF.testerFail and RF.testerFail(player) or false
		tell(player, "rift", H.riftAnswer(RF.probe(player), ok and {failed = true} or {err = "not inside a running rift"}))
		return
	end
	if want.what == "path" then
		local got, why
		if probe.inside then
			got, why = goalPath(player, probe)
		else
			why = "not inside a rift"
		end
		tell(player, "rift", H.riftAnswer(probe, got or {err = why}))
		return
	end
	local itk = ItemType(cfg.key.itemId)
	tell(player, "rift", H.riftAnswer(probe, {tier = tierOf(), keyClientId = itk and itk:getClientId() or 0})) -- O671: the key the bag holds is used by its client id
end

-- ---------------------------------------------------------------- O651 the pocket bosses
-- "!tester pocket [state | path | close]": reads ChaosPocketBoss.probe (the Boss Spawns window's pocket rows with their charges and boss points, the
-- arenas free against the ones kept for the players; inside the run, the boss and the guide); `path` is the engine's path to the boss; `close` is
-- the bot's own Leave button. The window's `pocketEnter` and the fight are the bot's own.
function commands.pocket(player, arg)
	local what, usage = H.parsePocket(arg)
	if not what then
		tell(player, "pocket", {err = usage})
		return
	end
	local PB = ChaosPocketBoss
	if not (PB and PB.probe) then
		tell(player, "pocket", {err = "no pocket boss system"})
		return
	end
	if what == "close" then
		local closed = PB.testerClose and PB.testerClose(player) or false
		tell(player, "pocket", H.pocketAnswer(PB.probe(player), {closed = closed and true or false}))
		return
	end
	local probe = PB.probe(player)
	if what == "path" then
		local got, why
		if probe.inside then
			got, why = goalPath(player, probe)
		else
			why = "not inside a pocket"
		end
		tell(player, "pocket", H.pocketAnswer(probe, got or {err = why}))
		return
	end
	tell(player, "pocket", H.pocketAnswer(probe))
end

-- ---------------------------------------------------------------- O651 the waystone maps walked
-- "!tester wsmap [state | enter [tier] | path | close]": reads ChaosWaystoneTiers.probe (whether a map of the band is free, inside the run, the
-- level of the monsters against the tier, the guide); `enter` is the TEST ONLY stand-in of the base device's pads and teleport (a plain run on a
-- free map, the bot on its arrival tile: a tester only, logged); `path` the engine's path to the guide's goal; `close` the bot's own way out.
function commands.wsmap(player, arg)
	local want, usage = H.parseWsMap(arg)
	if not want then
		tell(player, "wsmap", {err = usage})
		return
	end
	local WT = ChaosWaystoneTiers
	if not (WT and WT.probe and WT.testerEnter) then
		tell(player, "wsmap", {err = "no waystone system"})
		return
	end
	if want.what == "close" then
		local closed = WT.testerClose(player)
		tell(player, "wsmap", H.wsmapAnswer(WT.probe(player), {closed = closed and true or false}))
		return
	end
	if want.what == "enter" then
		local got, why = WT.testerEnter(player, want.tier)
		if not got then
			tell(player, "wsmap", H.wsmapAnswer(WT.probe(player), {err = why}))
			return
		end
		tell(player, "wsmap", H.wsmapAnswer(WT.probe(player), {entered = true, map = got.map, tier = got.tier}))
		return
	end
	local probe = WT.probe(player)
	if want.what == "path" then
		local got, why
		if probe.inside then
			got, why = goalPath(player, probe)
		else
			why = "not inside a waystone map"
		end
		tell(player, "wsmap", H.wsmapAnswer(probe, got or {err = why}))
		return
	end
	tell(player, "wsmap", H.wsmapAnswer(probe))
end

-- ---------------------------------------------------------------- O666 the waystone endgame (closed mode)
-- "!tester wsendgame": reads ChaosWaystoneEndgame.probe (tiers, the band bosses' monster types loaded, the corruption pool, the asker's atlas,
-- the onRunCleared hook). Nothing is changed.
function commands.wsendgame(player, arg)
	local EG = ChaosWaystoneEndgame
	if not (EG and EG.probe) then
		tell(player, "wsendgame", {err = "no waystone endgame"})
		return
	end
	local ok, got = pcall(EG.probe, player)
	tell(player, "wsendgame", ok and got or {err = tostring(got)})
end

-- ---------------------------------------------------------------- O595 the Infinity Tower and the Ember Descent
-- "!tester tower [state | path | close]": reads ChaosTowerRun.probe; `path` is the engine's path to the guide's goal (the nearest monster of the
-- floor, within reach of it); `close` is the Leave button without the countdown. Nothing here enters, moves inside or fights.
function commands.tower(player, arg)
	local what, usage = H.parseTower(arg)
	if not what then
		tell(player, "tower", {err = usage})
		return
	end
	local TR = ChaosTowerRun
	if not (TR and TR.probe) then
		tell(player, "tower", {err = "no tower system"})
		return
	end
	if what == "close" then
		local closed = TR.testerClose and TR.testerClose(player) or false
		tell(player, "tower", H.towerAnswer(TR.probe(player), {closed = closed and true or false}))
		return
	end
	local probe = TR.probe(player)
	if what == "path" then
		local got, why
		if probe.inside then
			got, why = goalPath(player, probe)
		else
			why = "not inside the tower"
		end
		tell(player, "tower", H.towerAnswer(probe, got or {err = why}))
		return
	end
	tell(player, "tower", H.towerAnswer(probe))
end

-- "!tester trial [state | path | close | clear [N]]" (`clear` O685, TEST ONLY: the cleared tier of a family whose trial is a puzzle the bots do not play): reads ChaosTrials.probe (the family of the vocation, the next tier and its stages, inside the stage, the
-- kills, the lives, the guardian); `path` and `close` as for the tower (`close` is the Leave button: a failed run with no cooldown)
function commands.trial(player, arg)
	local what, usage = H.parseTrial(arg)
	if not what then
		tell(player, "trial", {err = usage})
		return
	end
	local TT = ChaosTrials
	if not (TT and TT.probe) then
		tell(player, "trial", {err = "no trial system"})
		return
	end
	if what == "clear" then
		-- O685, TEST ONLY: the cleared tier of the family whose trial the bots cannot play (seals, marks), through the trials' own storage, logged
		local n = select(2, H.parseTrial(arg))
		local tier, why = nil, "no trial system"
		if TT.testerClear then
			tier, why = TT.testerClear(player, n)
		end
		if tier then
			print(string.format("[tester-helper] trial clear: %s tier %d (TEST ONLY)", player:getName(), tier))
		end
		tell(player, "trial", H.trialAnswer(TT.probe(player), tier and {set = tier} or {err = why or "refused"}))
		return
	end
	if what == "close" then
		local closed = TT.testerClose and TT.testerClose(player) or false
		tell(player, "trial", H.trialAnswer(TT.probe(player), {closed = closed and true or false}))
		return
	end
	local probe = TT.probe(player)
	if what == "path" then
		local got, why
		if probe.inside then
			got, why = goalPath(player, probe)
		else
			why = "not inside a trial"
		end
		tell(player, "trial", H.trialAnswer(probe, got or {err = why}))
		return
	end
	tell(player, "trial", H.trialAnswer(probe))
end

-- "!tester descent [state | path | close | sigil]": reads ChaosDescent.probe; `path` and `close` as for the tower; `sigil` puts an Ember Sigil
-- into the bag (outside a run only: the bot pays a second run of the day with it, as a player who bought or forged one does)
function commands.descent(player, arg)
	local what, usage = H.parseDescent(arg)
	if not what then
		tell(player, "descent", {err = usage})
		return
	end
	local D = ChaosDescent
	if not (D and D.probe) then
		tell(player, "descent", {err = "no descent system"})
		return
	end
	if what == "close" then
		local closed = D.testerClose and D.testerClose(player) or false
		tell(player, "descent", H.descentAnswer(D.probe(player), {closed = closed and true or false}))
		return
	end
	local probe = D.probe(player)
	if what == "sigil" then
		if probe.inside then
			tell(player, "descent", H.descentAnswer(probe, {err = "already inside the descent"}))
			return
		end
		local given = D.testerSigil and D.testerSigil(player) or false
		tell(player, "descent", H.descentAnswer(D.probe(player), {given = given and true or false, err = (not given) and "the sigil could not be made" or nil}))
		return
	end
	if what == "path" then
		local got, why
		if probe.inside then
			got, why = goalPath(player, probe)
		else
			why = "not inside the descent"
		end
		tell(player, "descent", H.descentAnswer(probe, got or {err = why}))
		return
	end
	tell(player, "descent", H.descentAnswer(probe))
end

-- ---------------------------------------------------------------- O599 the Ascended arenas and the Omen arenas
-- "!tester ascended [state | sigil [kind] | path | close]": reads ChaosAscended.probe; `sigil` is the TEST ONLY grant of a sigil (the highest
-- Omen the level opens, or the named kind; a tester only, logged; the bot uses it itself in a protection zone); `path` the engine's path to
-- the guide's goal inside; `close` the bot's own run (the sigil is spent, as when the time runs out).
function commands.ascended(player, arg)
	local want, usage = H.parseAscended(arg)
	if not want then
		tell(player, "ascended", {err = usage})
		return
	end
	local A = ChaosAscended
	if not (A and A.probe) then
		tell(player, "ascended", {err = "no ascended system"})
		return
	end
	if want.what == "close" then
		local closed = A.testerClose and A.testerClose(player) or false
		tell(player, "ascended", H.ascendedAnswer(A.probe(player), {closed = closed and true or false}))
		return
	end
	local probe = A.probe(player)
	if want.what == "sigil" then
		if probe.inside then
			tell(player, "ascended", H.ascendedAnswer(probe, {err = "already inside an arena"}))
			return
		end
		local inbox, kind = nil, nil
		if A.testerSigil then
			inbox, kind = A.testerSigil(player, want.kind)
		end
		if inbox == nil then
			tell(player, "ascended", H.ascendedAnswer(probe, {err = kind or "the sigil could not be made"}))
			return
		end
		tell(player, "ascended", H.ascendedAnswer(A.probe(player), {given = true, kind = kind, bagFull = inbox == true or nil}))
		return
	end
	if want.what == "path" then
		local got, why
		if probe.inside then
			got, why = goalPath(player, probe)
		else
			why = "not inside an arena"
		end
		tell(player, "ascended", H.ascendedAnswer(probe, got or {err = why}))
		return
	end
	tell(player, "ascended", H.ascendedAnswer(probe))
end

-- "!tester omen [state | key [kind] | path | close]": the omen arena is a rift slot, so it reads ChaosRift.probe (`run.omen` names the
-- kind); `key` is the TEST ONLY grant of an Omen Key (a tester only, logged; used by the bot itself in a protection zone); `close` ends the
-- bot's own run and takes a refunded key out of the backpack again.
function commands.omen(player, arg)
	local want, usage = H.parseOmen(arg)
	if not want then
		tell(player, "omen", {err = usage})
		return
	end
	local RF, cfg = ChaosRift, ChaosRiftConfig
	if not (RF and RF.probe and RF.testerOmenKey and cfg and cfg.omen) then
		tell(player, "omen", {err = "no omen arenas on this server"})
		return
	end
	local function held()
		return player:getItemById(cfg.omen.key.id, true)
	end
	if want.what == "close" then
		local closed = RF.testerClose and RF.testerClose(player) or false
		for _ = 1, 5 do
			local key = held()
			if not key then
				break
			end
			pcall(key.remove, key, 1)
		end
		tell(player, "omen", H.omenAnswer(RF.probe(player), {closed = closed and true or false}))
		return
	end
	local probe = RF.probe(player)
	if want.what == "key" then
		if probe.inside then
			tell(player, "omen", H.omenAnswer(probe, {err = "already inside a run"}))
			return
		end
		if not probe.pz then
			tell(player, "omen", H.omenAnswer(probe, {err = "not in a protection zone"}))
			return
		end
		local kind, why = RF.testerOmenKey(player, want.kind)
		if not kind then
			tell(player, "omen", H.omenAnswer(probe, {err = why}))
			return
		end
		local key = held()
		local it = ItemType(cfg.omen.key.id)
		tell(player, "omen", H.omenAnswer(RF.probe(player), {kind = kind, held = key ~= nil, keyClientId = it and it:getClientId() or 0,
			bagFull = key == nil or nil}))
		return
	end
	if want.what == "path" then
		local got, why
		if probe.inside then
			got, why = goalPath(player, probe)
		else
			why = "not inside an omen arena"
		end
		tell(player, "omen", H.omenAnswer(probe, got or {err = why}))
		return
	end
	tell(player, "omen", H.omenAnswer(probe, {level = player:getLevel(), minLevel = cfg.omen.minLevel}))
end

-- ---------------------------------------------------------------- O678 the pinnacle bosses
-- "!tester pinnacle [state | set [boss] | path | close]": reads ChaosPinnacle.probe; `set` is the TEST ONLY grant of a whole set of fragments (the highest
-- boss the level opens, or the named one; a tester only, logged); `path` the engine's path to the guide's goal inside the arena; `close` the bot's own
-- way out (the set stays spent, as when a person leaves). The Keeper's Open button is the bot's own.
function commands.pinnacle(player, arg)
	local want, usage = H.parsePinnacle(arg)
	if not want then
		tell(player, "pinnacle", {err = usage})
		return
	end
	local PN = ChaosPinnacle
	if not (PN and PN.probe) then
		tell(player, "pinnacle", {err = "no pinnacle system"})
		return
	end
	if want.what == "close" then
		local closed = PN.testerClose and PN.testerClose(player) or false
		tell(player, "pinnacle", H.pinnacleAnswer(PN.probe(player), {closed = closed and true or false}))
		return
	end
	local probe = PN.probe(player)
	if want.what == "set" then
		if probe.inside then
			tell(player, "pinnacle", H.pinnacleAnswer(probe, {err = "already inside a fight"}))
			return
		end
		local kind, why = nil, nil
		if PN.testerSet then
			kind, why = PN.testerSet(player, want.kind)
		end
		if not kind then
			tell(player, "pinnacle", H.pinnacleAnswer(probe, {err = why or "the set could not be made"}))
			return
		end
		tell(player, "pinnacle", H.pinnacleAnswer(PN.probe(player), {given = true, kind = kind}))
		return
	end
	if want.what == "path" then
		local got, why
		if probe.inside then
			got, why = goalPath(player, probe)
		else
			why = "not inside a pinnacle fight"
		end
		tell(player, "pinnacle", H.pinnacleAnswer(probe, got or {err = why}))
		return
	end
	tell(player, "pinnacle", H.pinnacleAnswer(probe))
end

-- ---------------------------------------------------------------- O681 the gear of the level
-- "!tester gear [state | set]": the pieces of the equipment sets (ChaosGearSets.items.pieces) that fit the bot's class and level (H.gearPlan). `state`
-- reads what is worn and the plan. `set` is the TEST ONLY grant of the pinnacle checks (a tester only, one console line, never inside a fight): a Rare
-- piece of item level = the level for each slot of the plan, worn at once (the old piece goes to the backpack; a piece the Equip event refuses is
-- removed and the old one stays). The model's median class wears "the level's set gear" (survival_model.py, install_gear_sets.py CURVES).
local GEAR_SLOTS = {helmet = CONST_SLOT_HEAD, armor = CONST_SLOT_ARMOR, legs = CONST_SLOT_LEGS, weapon = CONST_SLOT_LEFT}
local GEAR_ORDER = {"helmet", "armor", "legs", "weapon"}
local GEAR_RARITY = 3 -- Rare: the drop the model's gear step prices (class_dps_model.py step_gear)

local function gearWorn(player)
	local worn = {}
	for _, name in ipairs(GEAR_ORDER) do
		local item = player:getSlotItem(GEAR_SLOTS[name])
		if item then
			local il = 0
			pcall(function() il = ChaosCrafting.levelOf(item) or 0 end)
			worn[name] = {id = item:getId(), il = il}
		end
	end
	return worn
end

-- "!tester loadout [cards ELEMENT | support KEY,KEY WORDS;WORDS]" (O685, TEST ONLY): what a well-built player of the level carries besides gear.
--   cards ELEMENT      the cards of the best set of the class: per spell family the character casts that has a card of the element, one card (up to
--                      the 5 slots), put in the Deck (the Deck opened: the main quest step is the player's) and turned on by the cards' own toggle
--   support KEY,KEY W  a Mythic rune of each support key socketed (ChaosSupports.socket, the window's own rule: the kind of the spell, the slots) into each
--                      spell whose words are named; a rune that does not fit is taken away again
-- An unknown subcommand answers the state: the cards that are on and the runes of the spells that carry one.
local function loadoutState(player)
	local out = {cards = {}, supports = {}}
	local C = ChaosCardsConfig
	if C and C.cards then
		for id, c in pairs(C.cards) do
			if c.storage and player:getStorageValue(c.storage) == 1 and c.kind ~= "legendary" then
				out.cards[#out.cards + 1] = {id = id, spell = c.spell, element = c.element}
			end
		end
		table.sort(out.cards, function(a, b) return a.id < b.id end)
	end
	local S = ChaosSupports
	if S and S.catalog and S.read then
		for id, info in pairs(S.catalog()) do
			local ok, sock = pcall(S.read, player, id)
			if ok and sock then
				local runes = {}
				for _, r in ipairs(sock.runes or {}) do
					if r and r > 0 then
						runes[#runes + 1] = r
					end
				end
				if #runes > 0 then
					out.supports[#out.supports + 1] = {spell = info.name, words = info.words, runes = runes}
				end
			end
		end
		table.sort(out.supports, function(a, b) return a.words < b.words end)
	end
	return out
end

local function loadoutCards(player, element)
	local C, D, S = ChaosCardsConfig, ChaosCardDeck, ChaosSupports
	if not (C and C.cards and D and D.add and ChaosCards and ChaosCards.toggle) then
		return {err = "no cards system"}
	end
	local voc, level = player:getVocation():getId(), player:getLevel()
	-- O689: a convert line is cast by the classes of ChaosCardsConfig.lineClasses (ChaosCardsCore.castsLine); the Frostfall Rune line is no
	-- attack spell of ChaosSupports.spellInfo and every class casts it, so the old spellInfo test never picked it (4 of 5 O685 bots had 2 cards)
	local Core = ChaosCardsCore
	local className = Core and Core.classNameOf and Core.classNameOf(voc)
	local function castable(card)
		if className and Core.castsLine and C.lineClasses then
			return Core.castsLine(className, card)
		end
		if not (S and S.spellInfo) then
			return false
		end
		for _, sp in ipairs(card.spells or {}) do
			local info = S.spellInfo(sp[2])
			if info and info.level <= level and (info.vocations[voc] or next(info.vocations) == nil) then
				return true
			end
		end
		return false
	end
	local byFamily, order = {}, {}
	for id, c in pairs(C.cards) do
		if c.kind == "convert" and c.element == element and castable(c) and not byFamily[c.family] then
			byFamily[c.family] = id
			order[#order + 1] = c.family
		end
	end
	table.sort(order)
	if D.unlock then
		D.unlock(player)
	end
	local picked = {}
	for _, f in ipairs(order) do
		if #picked < (C.maxActive or 5) then
			picked[#picked + 1] = byFamily[f]
		end
	end
	-- the cards that are on and not wanted go off first (a card per convert line: the highest card on decides the line's element)
	for id, c in pairs(C.cards) do
		if c.kind ~= "legendary" and c.storage and player:getStorageValue(c.storage) == 1 then
			local keep = false
			for _, w in ipairs(picked) do
				keep = keep or w == id
			end
			if not keep then
				ChaosCards.toggle(player, id)
			end
		end
	end
	local on = {}
	for _, id in ipairs(picked) do
		D.add(player, id, 1)
		if player:getStorageValue(C.cards[id].storage) ~= 1 then
			ChaosCards.toggle(player, id)
		end
		if player:getStorageValue(C.cards[id].storage) == 1 then
			on[#on + 1] = {id = id, spell = C.cards[id].spell}
		end
	end
	return {element = element, cards = on, set = #on >= ((C.sets and C.sets.need) or 3)}
end

local function loadoutSupports(player, keys, wordsList)
	local S = ChaosSupports
	local SC = S and (S.config or ChaosSupportsConfig)
	if not (S and S.catalog and S.socket and S.runeId and SC and SC.supports) then
		return {err = "no supports system"}
	end
	local idx = {}
	for i, t in ipairs(SC.supports) do
		idx[t.key] = i
	end
	local byWords = {}
	for _, info in pairs(S.catalog()) do
		byWords[info.words] = info
	end
	local out, capWas = {}, player:getCapacity()
	player:setCapacity(capWas + 1000000)
	for _, words in ipairs(wordsList) do
		local info = byWords[words]
		local row = {words = words, name = info and info.name, kind = info and info.kind, put = {}, refused = {}}
		out[#out + 1] = row
		if info then
			for _, key in ipairs(keys) do
				local typ = idx[key]
				if typ then
					local rune = S.runeId(typ, SC.levels or 5)
					local item = player:addItem(rune, 1)
					local ok, why
					if item then
						ok, why = S.socket(player, info.id, rune)
						if not ok then
							player:removeItem(rune, 1)
						end
					else
						why = "no room"
					end
					if ok then
						row.put[#row.put + 1] = key
					else
						row.refused[#row.refused + 1] = key .. ": " .. tostring(why):sub(1, 50)
					end
				end
			end
		end
	end
	player:setCapacity(capWas)
	return {supports = out}
end

function commands.loadout(player, arg)
	if ChaosPinnacle and ChaosPinnacle.isInside and ChaosPinnacle.isInside(player) then
		tell(player, "loadout", {err = "not inside a fight"})
		return
	end
	local sub, rest = tostring(arg or ""):match("^%s*(%a*)%s*(.-)%s*$")
	local ok, got
	if sub == "cards" and rest ~= "" then
		ok, got = pcall(loadoutCards, player, rest:sub(1, 1):upper() .. rest:sub(2):lower())
	elseif sub == "support" and rest ~= "" then
		local keys, words = rest:match("^([%w,]+)%s+(.+)$")
		if not keys then
			tell(player, "loadout", {err = "usage: loadout support KEY,KEY WORDS;WORDS"})
			return
		end
		local list, kl = {}, {}
		for w in words:gmatch("[^;]+") do
			list[#list + 1] = w:match("^%s*(.-)%s*$")
		end
		for k in keys:gmatch("[^,]+") do
			kl[#kl + 1] = k
		end
		ok, got = pcall(loadoutSupports, player, kl, list)
	else
		ok, got = true, nil
	end
	if not ok then
		tell(player, "loadout", {err = "loadout failed: " .. tostring(got):sub(1, 80)})
		return
	end
	if got and not got.err then
		print(string.format("[tester-helper] loadout %s: %s (TEST ONLY)", player:getName(), tostring(sub)))
	end
	local state = loadoutState(player)
	for k, v in pairs(got or {}) do
		state[k] = v
	end
	tell(player, "loadout", state)
end

-- ---------------------------------------------------------------- O693 the rest of the gear, food and the buff (TEST ONLY)
-- "!tester gear extras [R] | growth | orbs | gems [WORDS;WORDS]", "!tester food", "!tester buffs [state | learn]": what a character of the level wears,
-- carries and keeps up besides the four pieces of `gear set`. Every step is the game's own function on a piece or a spell, called by the helper (the grant
-- is the fallback, a counted one on the bot's side); none runs for a character that is not a tester, outside the closed test mode or inside a fight.
local GEAR_WORN = {
	{"head", CONST_SLOT_HEAD}, {"armor", CONST_SLOT_ARMOR}, {"legs", CONST_SLOT_LEGS}, {"feet", CONST_SLOT_FEET}, {"weapon", CONST_SLOT_LEFT},
	{"offhand", CONST_SLOT_RIGHT}, {"amulet", CONST_SLOT_NECKLACE}, {"ring", CONST_SLOT_RING}}
local EXTRA_SLOTS = {boots = CONST_SLOT_FEET, amulet = CONST_SLOT_NECKLACE, ring = CONST_SLOT_RING, offhand = CONST_SLOT_RIGHT,
	ranged = CONST_SLOT_LEFT, weapon1h = CONST_SLOT_LEFT}
local EXTRA_ORDER = {"weapon1h", "ranged", "boots", "amulet", "ring", "offhand"}

local function closedOn()
	local K = ChaosTestersCore
	local ok, on = pcall(function() return K and K.closedOn and K.closedOn() end)
	return ok and on and true or false
end

-- true when the step may not run (the answer says why): the closed test mode is off, or the tester is inside a pinnacle fight
local function gearRefused(player, kind, extra)
	local why
	if not closedOn() then
		why = "closed test mode is off"
	elseif ChaosPinnacle and ChaosPinnacle.isInside and ChaosPinnacle.isInside(player) then
		why = "not inside a fight"
	end
	if why then
		local out = {err = why}
		for k, v in pairs(extra or {}) do
			out[k] = v
		end
		tell(player, kind, out)
		return true
	end
	return false
end

local function twoHandedItem(item)
	local ok, v = pcall(function() return ItemType(item:getId()):getSlotPosition() end)
	local bit = SLOTP_TWO_HAND or 2048
	return ok and math.floor((tonumber(v) or 0) / bit) % 2 == 1
end

-- one piece of the plan into a slot (the body of the `gear set` loop): the piece at this level and rarity worn already -> "worn"; else a new piece
-- through ChaosCrafting.createItem, the old one into the backpack (a two-handed weapon also empties the off hand); "ok", or the reason
local function grantPiece(player, bag, slot, p, rarity, level, emptyOffHand)
	local ok, why = pcall(function()
		local old = player:getSlotItem(slot)
		if old and old:getId() == p.id then
			local il, rar = 0, rarity
			pcall(function() il = ChaosCrafting.levelOf(old) or 0 end)
			pcall(function() rar = ChaosCrafting.rarityOf(old) or rar end)
			if il >= level and rar == rarity then
				return "worn" -- the piece of the plan, at this level and rarity, is on already
			end
		end
		local item
		if ChaosCrafting and ChaosCrafting.createItem then
			item = ChaosCrafting.createItem(p.id, rarity, level)
		else
			item = Game.createItem(p.id, 1)
		end
		if not item then
			return "the piece could not be made"
		end
		if emptyOffHand then
			local off = player:getSlotItem(CONST_SLOT_RIGHT)
			if off and off:moveTo(bag) == false then
				item:remove()
				return "the off hand could not be emptied"
			end
		end
		if old and old:moveTo(bag) == false then
			item:remove()
			return "the worn piece could not be put away"
		end
		local rv = player:addItemEx(item, false, slot)
		if rv ~= RETURNVALUE_NOERROR then
			item:remove()
			if old and not player:getSlotItem(slot) then
				local c = old:clone()
				if player:addItemEx(c, false, slot) == RETURNVALUE_NOERROR then
					old:remove()
				else
					c:remove()
				end
			end
			return "refused (" .. tostring(rv) .. ")"
		end
		return "ok"
	end)
	return ok and why or tostring(why)
end

local function refreshMods(player)
	if ChaosItemMods and ChaosItemMods.refresh then
		pcall(ChaosItemMods.refresh, player, true)
	end
end

-- gear extras [R]: boots, amulet, ring, the off hand (shield, spellbook or quiver), the bow / crossbow / wand / rod of a class that has none in `gear set`
local function gearExtras(player, want, pieces, className, level)
	local quivers = ChaosArchery and ChaosArchery.config and ChaosArchery.config.quivers
	local plan = H.gearExtrasPlan(pieces, className, level, quivers)
	local base = H.gearPlan(pieces, className, level)
	local bag = player:getSlotItem(CONST_SLOT_BACKPACK)
	if not bag then
		tell(player, "gear", {err = "no backpack", level = level})
		return
	end
	local rarity = want.rarity or GEAR_RARITY
	local capWas = player:getCapacity()
	player:setCapacity(capWas + 10000000)
	local given, refused, skipped, ids = {}, {}, {}, {}
	local launcher = plan.ranged and (plan.ranged.kind == "bow" or plan.ranged.kind == "crossbow")
	for _, name in ipairs(EXTRA_ORDER) do
		local p = plan[name]
		local skip
		if p and name == "weapon1h" then
			local left = player:getSlotItem(CONST_SLOT_LEFT)
			if not (left and twoHandedItem(left)) then
				skip = "the weapon in hand is one-handed"
			end
		elseif p and name == "ranged" and base.weapon then
			skip = "the class has its weapon in gear set"
		elseif p and name == "offhand" and p.kind ~= "quiver" then
			local left = player:getSlotItem(CONST_SLOT_LEFT)
			if left and twoHandedItem(left) then
				skip = "a two-handed weapon is in hand"
			end
		end
		if p and skip then
			skipped[#skipped + 1] = {slot = name, why = skip}
		elseif p then
			local why = grantPiece(player, bag, EXTRA_SLOTS[name], p, rarity, level, false)
			if why == "ok" or why == "worn" then
				given[#given + 1] = name
				ids[name] = p.id
			else
				refused[#refused + 1] = {slot = name, why = tostring(why):sub(1, 60)}
			end
		end
	end
	player:setCapacity(capWas)
	refreshMods(player)
	print(string.format("[tester-helper] gear extras for %s (level %d, %s): %s%s (TEST ONLY)", player:getName(), level, className, table.concat(given, ","),
		#refused > 0 and (" refused " .. #refused) or ""))
	tell(player, "gear", {what = "extras", level = level, class = className, given = given, refused = refused, skipped = skipped, ids = ids,
		launcher = launcher and true or false, rarity = rarity})
end

-- gear growth: the weapon touch the game gives a weapon on every read and move (ChaosCrafting.upgradeItem -> growWeapon: the attack moves by the growth
-- of the item type once, the mark "chaos_wgrow" says it did); a worn weapon the helper made was touched by the equip already, this makes sure
local function gearGrowth(player, level)
	local C = ChaosCrafting
	if not (C and C.upgradeItem) then
		tell(player, "gear", {err = "no crafting system"})
		return
	end
	local rows = {}
	for _, e in ipairs(GEAR_WORN) do
		local item = player:getSlotItem(e[2])
		if item and (e[1] == "weapon" or e[1] == "offhand") then
			local attack = 0
			if ITEM_ATTRIBUTE_ATTACK then
				local okA, a = pcall(function() return item:getAttribute(ITEM_ATTRIBUTE_ATTACK) end)
				attack = okA and tonumber(a) or 0
			end
			if attack > 0 then
				local okT, changed = pcall(C.upgradeItem, item)
				local mark
				pcall(function() mark = item:getCustomAttribute(C.GROWN or "chaos_wgrow") end)
				local after = attack
				pcall(function() after = item:getAttribute(ITEM_ATTRIBUTE_ATTACK) end)
				rows[#rows + 1] = {slot = e[1], id = item:getId(), attack = after, touched = okT and changed and true or false, grown = mark ~= nil}
			end
		end
	end
	refreshMods(player)
	print(string.format("[tester-helper] gear growth for %s (level %d): %d weapon(s) (TEST ONLY)", player:getName(), level, #rows))
	tell(player, "gear", {what = "growth", level = level, weapons = rows})
end

-- gear orbs: the bench results of a geared character, through the orbs' own apply (ChaosCrafting.apply): Whetstones to H.ORB_PLAN.quality, one Orb of
-- Tempering and the Ember Orbs of H.ORB_PLAN on the worn pieces. A refusal (corrupted, nothing to raise) is counted, not an error.
local function gearOrbs(player, level)
	local C = ChaosCrafting
	if not (C and C.apply and C.orbByKey and C.orbByKey.whetstone and C.orbByKey.tempering and C.orbByKey.ember) then
		tell(player, "gear", {err = "no crafting orbs"})
		return
	end
	local plan = H.ORB_PLAN
	local applied = {whetstone = 0, tempering = 0, ember = 0}
	local refused = {}
	local pieces = {}
	for _, e in ipairs(GEAR_WORN) do
		local item = player:getSlotItem(e[2])
		if item then
			local row = {slot = e[1], id = item:getId()}
			local function use(key)
				local ok, res = C.apply(key, item)
				if ok then
					applied[key] = applied[key] + 1
				elseif #refused < 6 then
					refused[#refused + 1] = e[1] .. " " .. key .. ": " .. tostring(res):sub(1, 40)
				end
				return ok
			end
			local tries = 0
			while C.qualityOf and (C.qualityOf(item) or 0) < plan.quality and tries < plan.quality + 5 do
				tries = tries + 1
				if not use("whetstone") then
					break
				end
			end
			for _ = 1, plan.tempering do
				use("tempering")
			end
			local embers = plan.ember[e[1]] or 0
			for _ = 1, embers do
				use("ember")
			end
			row.quality = C.qualityOf and C.qualityOf(item) or nil
			pieces[#pieces + 1] = row
		end
	end
	refreshMods(player)
	print(string.format("[tester-helper] gear orbs for %s (level %d): %d whetstones, %d tempering, %d ember (TEST ONLY)", player:getName(), level,
		applied.whetstone, applied.tempering, applied.ember))
	tell(player, "gear", {what = "orbs", level = level, applied = applied, pieces = pieces, refused = refused})
end

-- the attack spells of the class (the named words, else every attack spell its vocation casts at its level), as {element = ...} rows
local function gemSpells(player, words)
	local S = ChaosSupports
	local out = {}
	if not (S and S.catalog) then
		return out
	end
	local voc, level = player:getVocation():getId(), player:getLevel()
	local want = {}
	for _, w in ipairs(words or {}) do
		want[w] = true
	end
	local named = next(want) ~= nil
	for _, info in pairs(S.catalog()) do
		if named then
			if info.words and want[tostring(info.words):lower()] then
				out[#out + 1] = {element = info.element}
			end
		elseif (info.kind == "single" or info.kind == "area") and (tonumber(info.level) or 0) <= level
			and (info.vocations and (info.vocations[voc] or next(info.vocations) == nil)) then
			out[#out + 1] = {element = info.element}
		end
	end
	return out
end

-- gear gems [WORDS;WORDS]: every worn piece gets its sockets (the most the item may have: H's note; the Orb of Sockets costs 25 coins) and the gems of
-- H.gemPlan at the best tier a drop of the level can be, through the gems' own socket rule (ChaosGems.socket: the gem is a real item, the socket is
-- filled by the game's function and the description is written again)
local function gearGems(player, want, level)
	local G = ChaosGems
	if not (G and G.socket and G.setCount and G.maxSockets and G.config and G.levelWeights and G.groupOf and G.gemId) then
		tell(player, "gear", {err = "no gems system"})
		return
	end
	local tier = H.gemTier(G.levelWeights(level))
	local element = H.gemElement(gemSpells(player, want.words))
	local capWas = player:getCapacity()
	player:setCapacity(capWas + 10000000)
	local pieces, socketed, refused = {}, 0, {}
	for _, e in ipairs(GEAR_WORN) do
		local item = player:getSlotItem(e[2])
		local max = item and G.maxSockets(item) or 0
		if item and max > 0 then
			local group = G.groupOf(item)
			if G.count(item) < max then
				G.setCount(item, max)
				pcall(G.writeDescription, item)
			end
			local plan = H.gemPlan(G.config.types, group, element, max)
			local names = {}
			for i = 1, max do
				if G.gemAt(item, i) == 0 and plan[i] then
					local gemId = G.gemId(plan[i], tier)
					local gem = player:addItem(gemId, 1)
					local ok, why = false, "no room"
					if gem then
						ok, why = G.socket(player, gem, item)
						if not ok then
							player:removeItem(gemId, 1)
						end
					end
					if ok then
						socketed = socketed + 1
					elseif #refused < 6 then
						refused[#refused + 1] = e[1] .. ": " .. tostring(why):sub(1, 50)
					end
				end
				local id = G.gemAt(item, i)
				if id > 0 then
					names[#names + 1] = G.gemName(id)
				end
			end
			pieces[#pieces + 1] = {slot = e[1], id = item:getId(), group = group, sockets = max, gems = names}
		end
	end
	player:setCapacity(capWas)
	refreshMods(player)
	print(string.format("[tester-helper] gear gems for %s (level %d, %s tier %d): %d gems (TEST ONLY)", player:getName(), level, tostring(element), tier, socketed))
	tell(player, "gear", {what = "gems", level = level, element = element, tier = tier, socketed = socketed, pieces = pieces, refused = refused})
end

-- the dispatch of the O693 steps of `!tester gear`; true when `want` was one of them
local function gearMore(player, want, pieces, className, level)
	if want.what ~= "extras" and want.what ~= "growth" and want.what ~= "orbs" and want.what ~= "gems" then
		return false
	end
	if gearRefused(player, "gear", {level = level, what = want.what}) then
		return true
	end
	local ok, err = pcall(function()
		if want.what == "extras" then
			gearExtras(player, want, pieces, className, level)
		elseif want.what == "growth" then
			gearGrowth(player, level)
		elseif want.what == "orbs" then
			gearOrbs(player, level)
		else
			gearGems(player, want, level)
		end
	end)
	if not ok then
		tell(player, "gear", {err = "gear " .. want.what .. " failed: " .. tostring(err):sub(1, 80), what = want.what})
	end
	return true
end

-- "!tester food": the Everfull Ration of the store (the store's own service puts it in the backpack: ChaosStoreFood.give) and its bites until "You are
-- full." (ChaosStoreFoodCore.bite: the ration's own rule; player:feed gives the regeneration). The Action of the ration cannot be called from Lua, so the
-- helper makes the same bites. Ownership, one ration a character, the cap of 1,200 s are the rule's.
function commands.food(player)
	if gearRefused(player, "food") then
		return
	end
	local F, K, C = ChaosStoreFood, ChaosStoreFoodCore, ChaosStoreFoodConfig
	if not (F and K and C and F.installed and F.installed() and F.owned and F.give and player.feed) then
		tell(player, "food", {err = "no ration system"})
		return
	end
	local gave
	if not F.owned(player) then
		local capWas = player:getCapacity()
		player:setCapacity(capWas + 10000)
		gave = F.give(player)
		player:setCapacity(capWas)
		if not gave then
			tell(player, "food", {err = "the ration could not be given"})
			return
		end
	end
	local bites = 0
	while bites < 30 do
		local cond = player:getCondition(CONDITION_REGENERATION, CONDITIONID_DEFAULT)
		local r = K.bite(C, {ticksMs = cond and cond:getTicks() or 0})
		if not r.ok then
			break
		end
		player:feed(r.seconds)
		bites = bites + 1
	end
	local cond = player:getCondition(CONDITION_REGENERATION, CONDITIONID_DEFAULT)
	local seconds = cond and math.floor(cond:getTicks() / 1000) or 0
	print(string.format("[tester-helper] food for %s: %d bites, %d s of regeneration (TEST ONLY)", player:getName(), bites, seconds))
	tell(player, "food", {gave = gave, bites = bites, seconds = seconds, item = C.item and C.item.id or nil})
end

-- "!tester buffs [state | learn]": the level 800 buff of the class's line (quest 2 of the line spell quests: Ironbound Oath, Unblinking Gaze, Veil of
-- Whispers, Shroud of Knives, Dirge of the Legion, Lotus Stance, Mantle of Dawn; 20 s, a cooldown of 90 s). `learn` teaches the spell (the quest is long
-- and the bots do not play it: a TEST ONLY grant); the bot casts it by its words before the fight and again when the cooldown is over.
function commands.buffs(player, arg)
	local Q = ChaosSpellQuestCore
	local sub = tostring(arg or ""):lower():match("^%s*(%a*)%s*$")
	if sub == nil or (sub ~= "" and sub ~= "state" and sub ~= "learn") then
		tell(player, "buffs", {err = "usage: buffs [state | learn]"})
		return
	end
	if sub == "learn" and gearRefused(player, "buffs") then
		return
	end
	if not (Q and Q.lineOf) then
		tell(player, "buffs", {err = "no spell quest system"})
		return
	end
	local idx, line = Q.lineOf(player:getVocation():getId())
	local name = line and line.spells and line.spells[2]
	if not (idx and name and H.isBuffSpell(name)) then
		tell(player, "buffs", {err = "no buff spell for the class", code = "noline"})
		return
	end
	local learned = player:hasLearnedSpell(name) and true or false
	if sub == "learn" then
		if not learned then
			player:learnSpell(name)
			learned = player:hasLearnedSpell(name) and true or false
			print(string.format("[tester-helper] buffs for %s: learned %s (TEST ONLY)", player:getName(), name))
		end
	end
	tell(player, "buffs", {spell = name, learned = learned, level = player:getLevel(), line = line.key})
end

function commands.gear(player, arg)
	local want, usage = H.parseGear(arg)
	if not want then
		tell(player, "gear", {err = usage})
		return
	end
	local G = ChaosGearSets
	local pieces = G and G.items and G.items.pieces
	if type(pieces) ~= "table" then
		tell(player, "gear", {err = "no equipment sets"})
		return
	end
	local level = player:getLevel()
	local className = player:getVocation():getName()
	local plan = H.gearPlan(pieces, className, level)
	local base = {level = level, class = className}
	if want.what == "state" then
		tell(player, "gear", H.gearAnswer(plan, gearWorn(player), base))
		return
	end
	if ChaosPinnacle and ChaosPinnacle.isInside and ChaosPinnacle.isInside(player) then
		tell(player, "gear", H.gearAnswer(plan, gearWorn(player), {err = "not inside a fight", level = level}))
		return
	end
	if gearMore(player, want, pieces, className, level) then
		return
	end
	local bag = player:getSlotItem(CONST_SLOT_BACKPACK)
	if not bag then
		tell(player, "gear", H.gearAnswer(plan, gearWorn(player), {err = "no backpack", level = level}))
		return
	end
	local capWas = player:getCapacity()
	player:setCapacity(capWas + 10000000) -- a piece of the level is heavy: the move is not refused for the weight
	local given, refused = {}, {}
	for _, name in ipairs(GEAR_ORDER) do
		local p = plan[name]
		local slot = GEAR_SLOTS[name]
		if p then
			local why = grantPiece(player, bag, slot, p, want.rarity or GEAR_RARITY, level, name == "weapon" and p.fit == "2")
			if why == "ok" or why == "worn" then
				given[#given + 1] = name
			else
				refused[#refused + 1] = {slot = name, why = tostring(why):sub(1, 60)}
			end
		end
	end
	local flasks, flaskWhy = {}, {}
	for line, e in pairs(tierPotions()) do -- the flask of the model's potion tier (it never empties; one a character)
		local okC, n = pcall(function() return player:getItemCount(e.id) end)
		local added
		if okC and (n or 0) == 0 then
			local okA, got = pcall(function() return player:addItem(e.id, 1) end)
			added = okA and got ~= nil and got ~= false
			okC, n = pcall(function() return player:getItemCount(e.id) end)
		end
		if okC and (n or 0) > 0 then
			local it = ItemType(e.id)
			flasks[line] = it and it:getClientId() or nil
		end
		if not flasks[line] then
			flaskWhy[#flaskWhy + 1] = line .. " " .. tostring(e.id) .. " count " .. tostring(n) .. (added == false and ", addItem refused" or "")
		end
	end
	player:setCapacity(capWas)
	print(string.format("[tester-helper] gear set for %s (level %d, %s): %s%s%s", player:getName(), level, className, table.concat(given, ","),
		#refused > 0 and (" refused " .. #refused) or "", flasks.health and (" + everfull tier " .. POTION_TIER .. " potions") or ""))
	tell(player, "gear", H.gearAnswer(plan, gearWorn(player), {level = level, class = className, given = given, refused = refused,
		potions = flasks.health and {health = flasks.health, mana = flasks.mana} or nil, flaskWhy = #flaskWhy > 0 and table.concat(flaskWhy, "; "):sub(1, 90) or nil}))
end

-- ---------------------------------------------------------------- O599 the bounty board
-- "!tester bounty [state | where NAME | path]": reads ChaosBounty.probe (the contracts held, the ones a hunt mark lists, "where does monster X
-- spawn"); `path` is the engine's path to the guide's goal (the monster of the contract in sight, else its hunt). Nothing here accepts, moves
-- or fights: the window's `accept` / `abandon` and the kills are the bot's own.
function commands.bounty(player, arg)
	local want, usage = H.parseBounty(arg)
	if not want then
		tell(player, "bounty", {err = usage})
		return
	end
	local B = ChaosBounty
	if not (B and B.probe) then
		tell(player, "bounty", {err = "no bounty system"})
		return
	end
	local probe = B.probe(player, want.name)
	if want.what == "path" then
		local got, why = goalPath(player, probe)
		tell(player, "bounty", H.bountyAnswer(probe, got or {err = why}))
		return
	end
	tell(player, "bounty", H.bountyAnswer(probe))
end

-- ---------------------------------------------------------------- O599 the main quest
-- "!tester mainquest [state]": reads ChaosMainQuest.probe (the open step, its condition, progress, where to go, what a bot can play of it). The
-- bot walks (`path npc NAME`, `path pos X Y Z`), talks, kills and reads the progress itself; the quest credits the steps by play
function commands.mainquest(player, arg)
	local what, usage = H.parseMainQuest(arg)
	if not what then
		tell(player, "mainquest", {err = usage})
		return
	end
	local W = ChaosMainQuest
	if not (W and W.probe) then
		tell(player, "mainquest", {err = "no main quest system"})
		return
	end
	tell(player, "mainquest", H.mainQuestAnswer(W.probe(player)))
end

-- ---------------------------------------------------------------- O650 the Nemesis, the daily, the Chronicle, Vael, the goblin, the invasions
-- "!tester nemesis [state | born | appear | path | close]": reads ChaosNemesis.probe. `born` is the TEST ONLY birth (the type of a regular monster in
-- sight, the dice skipped), `appear` the TEST ONLY call (the warning and the arrival of a kill's roll), `path` the engine's path to its Nemesis,
-- `close` takes it and its record away. The fight is the bot's own.
function commands.nemesis(player, arg)
	local what, usage = H.parseNemesis(arg)
	if not what then
		tell(player, "nemesis", {err = usage})
		return
	end
	local NE = ChaosNemesis
	if not (NE and NE.probe) then
		tell(player, "nemesis", {err = "no nemesis system"})
		return
	end
	if what == "close" then
		local closed = NE.testerClose and NE.testerClose(player) or false
		tell(player, "nemesis", H.cutAnswer(NE.probe(player), {closed = closed and true or false}))
	elseif what == "born" or what == "appear" then
		local fn = what == "born" and NE.testerBorn or NE.testerAppear
		local ok, why = nil, "no such grant"
		if fn then
			ok, why = fn(player)
		end
		tell(player, "nemesis", H.cutAnswer(NE.probe(player), ok and {[what] = true} or {err = tostring(why or "refused")}))
	elseif what == "path" then
		local probe = NE.probe(player)
		local got, why = goalPath(player, probe)
		tell(player, "nemesis", H.cutAnswer(probe, got or {err = why}))
	else
		tell(player, "nemesis", H.cutAnswer(NE.probe(player)))
	end
end

-- "!tester daily [state]": reads ChaosDaily.probe: the daily of the account (taken, slot, `value` for the window's own "calim", the reward and how
-- many of it the bot holds). Nothing is claimed here: the claim is the window's request, sent by the bot.
function commands.daily(player, arg)
	local what, usage = H.parseDaily(arg)
	if not what then
		tell(player, "daily", {err = usage})
		return
	end
	local DY = ChaosDaily
	if not (DY and DY.probe) then
		tell(player, "daily", {err = "no daily system"})
		return
	end
	tell(player, "daily", H.cutAnswer(DY.probe(player)))
end

-- "!tester chronicle [state]": reads ChaosChronicle.probe: the season, the open chapter, `counted` (would an event of the bot enter the chapter:
-- false) and `testersListed` (testers in the books: 0). The window's `open` is the bot's own request.
function commands.chronicle(player, arg)
	local what, usage = H.parseChronicle(arg)
	if not what then
		tell(player, "chronicle", {err = usage})
		return
	end
	local X = ChaosChronicle
	if not (X and X.probe) then
		tell(player, "chronicle", {err = "no chronicle system"})
		return
	end
	tell(player, "chronicle", H.cutAnswer(X.probe(player)))
end

-- "!tester vael [state | enter | path | close]": reads ChaosMainQuestBoss.probe (the Trials' probe of the run with the door's facts). `enter` is
-- the TEST ONLY door of Vael's spell trial (a tester from level 500, logged: the quest step and the resistances left out), `path` the engine's
-- path to the guide's goal inside, `close` the Leave button. The fight is the bot's own.
function commands.vael(player, arg)
	local what, usage = H.parseVael(arg)
	if not what then
		tell(player, "vael", {err = usage})
		return
	end
	local B = ChaosMainQuestBoss
	if not (B and B.probe and B.testerEnter) then
		tell(player, "vael", {err = "no main quest boss"})
		return
	end
	local function answer(probe, extra)
		local out = H.trialAnswer(probe, extra)
		out.won, out.tries, out.door = probe.won, probe.tries, probe.door and tostring(probe.door):sub(1, 40) or nil
		return out
	end
	if what == "close" then
		local closed = ChaosTrials and ChaosTrials.testerClose and ChaosTrials.testerClose(player) or false
		tell(player, "vael", answer(B.probe(player), {closed = closed and true or false}))
	elseif what == "enter" then
		local probe = B.probe(player)
		if probe.inside then
			tell(player, "vael", answer(probe, {err = "already inside a trial"}))
			return
		end
		local ok, why = B.testerEnter(player)
		tell(player, "vael", answer(B.probe(player), ok and {entered = true} or {err = tostring(why or "refused"):sub(1, 90)}))
	elseif what == "path" then
		local probe = B.probe(player)
		local got, why
		if probe.inside then
			got, why = goalPath(player, probe)
		else
			why = "not inside the trial"
		end
		tell(player, "vael", answer(probe, got or {err = why}))
	else
		tell(player, "vael", answer(B.probe(player)))
	end
end

-- "!tester goblin [state | spawn | path | close]": reads ChaosTreasureGoblin.probe. `spawn` is a goblin of the bot's own (TEST ONLY, logged, only while
-- no player is near: only the testers can hurt it), `path` the engine's path to it, `close` takes it away. A goblin of the world is the players'.
function commands.goblin(player, arg)
	local what, usage = H.parseGoblin(arg)
	if not what then
		tell(player, "goblin", {err = usage})
		return
	end
	local TG = ChaosTreasureGoblin
	if not (TG and TG.probe and TG.testerSpawn) then
		tell(player, "goblin", {err = "no treasure goblin system"})
		return
	end
	if what == "close" then
		tell(player, "goblin", H.cutAnswer(TG.probe(player), {closed = TG.testerClose(player) and true or false}))
	elseif what == "spawn" then
		local m, why = TG.testerSpawn(player)
		tell(player, "goblin", H.cutAnswer(TG.probe(player), m and {spawned = true} or {err = tostring(why or "refused")}))
	elseif what == "path" then
		local probe = TG.probe(player)
		local got, why = goalPath(player, probe)
		tell(player, "goblin", H.cutAnswer(probe, got or {err = why}))
	else
		tell(player, "goblin", H.cutAnswer(TG.probe(player)))
	end
end

-- "!tester explode [state | run]" (O669, loot_explosion.lua testerRun / testerProbe): `run` puts a loot bag of the bot's own on its tile
-- with known loot and explodes it by the real rule (gold in one stack, the items on free tiles within 2, owned by the bot); `state` reads what lies
-- within 4 tiles (the owner, the farthest ring, the tiles, what is left in a bag) and whether a stranger would be refused. The bot then asks Loot all
-- by opcode 230 and reads `state` again. TEST ONLY, a tester only, as every command of this file.
function commands.explode(player, arg)
	local what, usage = H.parseExplode(arg)
	local who = usage
	if not what then
		tell(player, "explode", {err = usage})
		return
	end
	local LE = ChaosLootExplosion
	if not (LE and LE.testerRun and LE.testerProbe and LE.testerJoin) then
		tell(player, "explode", {err = "no loot explosion"})
		return
	end
	if what == "run" or what == "set" or what == "bag" then
		local r, why = LE.testerRun(player, what ~= "run" and what or nil)
		tell(player, "explode", r or {err = tostring(why or "refused")})
	elseif what == "join" then
		local r, why = LE.testerJoin(player, who)
		tell(player, "explode", r or {err = tostring(why or "refused")})
	else
		tell(player, "explode", LE.testerProbe(player))
	end
end

-- "!tester invasion [state | path]": reads ChaosInvasion.probe (the phase, the area and its target point, the invader nearest, `credited`: false for a
-- tester, the hits of the bot that were cancelled) and the path on foot to the guide's goal. A tester's hits on an invader are cancelled
-- (the invasion is the players'): the bot walks there and proves the rule.
function commands.invasion(player, arg)
	local what, usage = H.parseInvasion(arg)
	if not what then
		tell(player, "invasion", {err = usage})
		return
	end
	local V = ChaosInvasion
	if not (V and V.probe) then
		tell(player, "invasion", {err = "no invasion system"})
		return
	end
	local probe = V.probe(player)
	if what == "path" then
		local got, why = goalPath(player, probe)
		tell(player, "invasion", H.cutAnswer(probe, got or {err = why}))
	else
		tell(player, "invasion", H.cutAnswer(probe))
	end
end

-- ---------------------------------------------------------------- O654 the levelling journey on foot
-- "!tester journey [state | jump | hall] [keep ID] [skip ID,ID]": what a person sees on the way from the temple to the next hunt of the level
-- (H.journeyPick, the hunts of the teleport room): the hunt to go to, the temple's great teleport (`gate`), the stairs of the hall's floors,
-- the town portal beside the bot (`portal`), the depot locker next to the temple and the nearest monster. Nothing moves in `state`; the
-- walk is `!tester path pos X Y Z`. `jump` (the hunt's arrival) and `hall` (the hub next to the gate) are the TEST ONLY teleports of the
-- fallback the bot counts when the walk fails; a tester only, as every command of this file.
T.journeyCache = T.journeyCache or {}

-- the facts of a tile the journey looks for (H.journeyFind): a teleport's destination, a floor change, the action id of the town portal
local function journeyTile(x, y, z, withAid)
	if x < 1 or y < 1 or z < 0 or z > 15 then
		return nil
	end
	local tile = Tile(Position(x, y, z))
	if not tile then
		return nil
	end
	local info
	if ITEM_TYPE_TELEPORT then
		local tp = tile:getItemByType(ITEM_TYPE_TELEPORT)
		if tp and tp.getDestination then
			local ok, d = pcall(tp.getDestination, tp)
			if ok and d then
				info = {dest = posOf(d)}
			end
		end
	end
	if tile:hasFlag(TILESTATE_FLOORCHANGE) then
		info = info or {}
		info.change = (TILESTATE_FLOORCHANGE_DOWN and tile:hasFlag(TILESTATE_FLOORCHANGE_DOWN)) and "down" or "up"
	end
	if withAid then
		for _, item in ipairs(tile:getItems() or {}) do
			if item:getActionId() == H.PORTAL_AID then
				info = info or {}
				info.aid = H.PORTAL_AID
				break
			end
		end
	end
	return info
end

local function journeyKey(kind, p)
	return kind .. ":" .. p.x .. "," .. p.y .. "," .. p.z
end

local function journeyProbe(player, opts)
	local J = H.JOURNEY
	local ppos = player:getPosition()
	local pos, level, tpl = posOf(ppos), player:getLevel(), posOf(temple(player))
	local zone = H.journeyZone(pos, tpl)
	local ports = ChaosHuntTeleports and ChaosHuntTeleports.ports and ChaosHuntTeleports.ports() or {}
	local seed = player.getGuid and player:getGuid() or player:getId()
	local probe = {level = level, pos = pos, zone = zone, pick = H.journeyPick(ports, level, {keep = opts.keep, skip = opts.skip, seed = seed, near = opts.near})}
	probe.stay = probe.pick and probe.pick.stay or nil
	probe.above = probe.pick and probe.pick.above or nil
	local tile = Tile(ppos)
	probe.pz = tile ~= nil and tile:hasFlag(TILESTATE_PROTECTIONZONE) or false
	local cache = T.journeyCache
	if zone == "temple" then
		local key = journeyKey("gate", tpl)
		if cache[key] == nil then
			local found = H.journeyFind(journeyTile, tpl, 14, H.journeyIsGate)
			cache[key] = found and {x = found.x, y = found.y, z = found.z} or false
		end
		probe.gate = cache[key] or nil
		key = journeyKey("locker", tpl)
		if cache[key] == nil then
			local l = findLocker(Position(tpl.x, tpl.y, tpl.z))
			local it = l and ItemType(l.id)
			cache[key] = l and {x = l.pos.x, y = l.pos.y, z = l.pos.z, cid = it and it:getClientId() or 0, sp = l.stackpos, spot = posOf(l.spot)} or false
		end
		probe.locker = cache[key] or nil
	elseif zone == "hall" then
		local key = "stairs:" .. pos.z
		if cache[key] == nil then
			local up = H.journeyFind(journeyTile, pos, 40, function(i) return H.journeyIsStairs(i, "up") end)
			local down = H.journeyFind(journeyTile, pos, 40, function(i) return H.journeyIsStairs(i, "down") end)
			cache[key] = {up = up and {x = up.x, y = up.y, z = up.z} or nil, down = down and {x = down.x, y = down.y, z = down.z} or nil}
		end
		probe.stairs = cache[key]
	end
	local near = H.journeyFind(function(x, y, z) return journeyTile(x, y, z, true) end, pos, 4, H.journeyIsPortal)
	probe.portal = near and {x = near.x, y = near.y, z = near.z} or nil
	if zone == "other" then
		local list, around = {}, 0
		for _, c in ipairs(Game.getSpectators(ppos, false, false, J.sight, J.sight, J.sight, J.sight) or {}) do
			if c:isMonster() and not c:getMaster() then
				list[#list + 1] = {pos = c:getPosition(), health = c:getHealth(), owned = false, id = c:getId(), c = c}
			end
		end
		local best = H.nearest(ppos, list, J.sight)
		if best then
			local p = best.pos
			probe.monster = {name = best.c:getName(), level = Chaos.monsterHuntingLevel(best.c, 0), x = p.x, y = p.y, z = p.z,
				dist = math.max(math.abs(p.x - pos.x), math.abs(p.y - pos.y))}
		end
		for _, m in ipairs(list) do
			if m.pos.z == pos.z and math.max(math.abs(m.pos.x - pos.x), math.abs(m.pos.y - pos.y)) <= J.crowd then
				around = around + 1
			end
		end
		probe.crowd = around
		local hot = H.hotSpot(level, monstersNear(ppos, J.crowd))
		probe.hot = hot and {n = tostring(hot[1]), l = hot[2]} or nil
	end
	return probe
end

function commands.journey(player, arg)
	local opts, usage = H.parseJourney(arg)
	if not opts then
		tell(player, "journey", {err = usage})
		return
	end
	local probe = journeyProbe(player, opts)
	if opts.what == "jump" or opts.what == "hall" then
		local target = opts.what == "hall" and H.HALL_DOOR or (probe.pick and not probe.pick.above and probe.pick.a)
		if not target then
			local why = (probe.pick and not probe.pick.above) and "the hunt has no known arrival (a base hunt: its teleport leads there by the map)"
				or "no hunt the level may enter"
			tell(player, "journey", H.journeyAnswer(probe, {err = why}))
			return
		end
		local spot = freeNear(Position(target.x, target.y, target.z), nil, 3)
		if not spot then
			tell(player, "journey", H.journeyAnswer(probe, {err = "no free tile at the " .. (opts.what == "hall" and "hall" or "hunt")}))
			return
		end
		player:teleportTo(spot)
		if not landed(player, spot) then
			tell(player, "journey", H.journeyAnswer(probe, {err = "the teleport was refused"}))
			return
		end
		tell(player, "journey", H.journeyAnswer(journeyProbe(player, opts), {jumped = opts.what}))
		return
	end
	tell(player, "journey", H.journeyAnswer(probe))
end

-- "!tester pvp [state | path]": reads ChaosTesters.pvpProbe (O652): the PvP place the bot stands in, the closed switch, the foe the rules allow (a tester
-- in a place, the nearest in sight or the nearest a system lists), the hits a rule cancelled (on a player, outside a place, the switch off), the
-- arena / battleground / Marches views and `seasonListed` (testers with a row in the season ratings: 0). `path` is the engine's path to the guide's goal.
function commands.pvp(player, arg)
	local what, usage = H.parsePvp(arg)
	if not what then
		tell(player, "pvp", {err = usage})
		return
	end
	local X = ChaosTesters
	if not (X and X.pvpProbe) then
		tell(player, "pvp", {err = "no PvP rules for the testers"})
		return
	end
	local probe = X.pvpProbe(player)
	if what == "path" then
		local got, why = goalPath(player, probe)
		tell(player, "pvp", H.cutAnswer(probe, got or {err = why}))
	else
		tell(player, "pvp", H.cutAnswer(probe))
	end
end

-- "!tester boss [state | spawn | path | close]": reads ChaosTestersBoss.probe (O652). `spawn` is a copy of a key boss for the bot (TEST ONLY, logged,
-- only while no player is near and no lair's boss spawn is near: only the testers can hurt it, no board, no kill row), `path` the engine's path to
-- it, `close` takes it away. `state` gives its telegraph marks and, when the bot stands in one, the safe tile (guide `dodge`).
function commands.boss(player, arg)
	local what, usage = H.parseBoss(arg)
	if not what then
		tell(player, "boss", {err = usage})
		return
	end
	local B = ChaosTestersBoss
	if not (B and B.probe and B.testerSpawn) then
		tell(player, "boss", {err = "no tester boss system"})
		return
	end
	if what == "close" then
		tell(player, "boss", H.cutAnswer(B.probe(player), {closed = B.testerClose(player) and true or false}))
	elseif what == "spawn" then
		local m, why = B.testerSpawn(player)
		tell(player, "boss", H.cutAnswer(B.probe(player), m and {spawned = true} or {err = tostring(why or "refused")}))
	elseif what == "path" then
		local probe = B.probe(player)
		local got, why = goalPath(player, probe)
		tell(player, "boss", H.cutAnswer(probe, got or {err = why}))
	else
		tell(player, "boss", H.cutAnswer(B.probe(player)))
	end
end

-- ---------------------------------------------------------------- O655 the class ascension and the gathering
-- "!tester ascend [state | proof | path | close]": reads ChaosAscensionQuest.probe (the stage, the proof, the trial, the choices with the class lock,
-- inside the trial the guardian and `guide`). `proof` is the TEST ONLY credit of the Proof of Strength through its own rule (a tester only, logged: a
-- rare monster does not come when a check asks), `path` the engine's path to the guardian inside, `close` the end of the bot's own trial. The talk
-- with the Oracle, the modal windows, the fight and the choice are the bot's own.
function commands.ascend(player, arg)
	local what, usage = H.parseAscend(arg)
	if not what then
		tell(player, "ascend", {err = usage})
		return
	end
	local A = ChaosAscensionQuest
	if not (A and A.probe) then
		tell(player, "ascend", {err = "no ascension quest"})
		return
	end
	if what == "close" then
		local closedNow = A.testerClose(player) and true or false -- the close first: the record shows the bot outside
		tell(player, "ascend", H.cutAnswer(A.probe(player), {closed = closedNow}))
	elseif what == "proof" then
		local ok, why = A.testerProof(player)
		tell(player, "ascend", H.cutAnswer(A.probe(player), ok and {proofed = true} or {err = tostring(why or "refused")}))
	elseif what == "path" then
		local probe = A.probe(player)
		local got, why = goalPath(player, probe)
		tell(player, "ascend", H.cutAnswer(probe, got or {err = why}))
	else
		tell(player, "ascend", H.cutAnswer(A.probe(player)))
	end
end

-- "!tester gather [state | path]": reads ChaosProfessions.probe (the tools, the materials held, the nearest ready node and `guide`) and the engine's path to
-- the node's tile. The use, the channel and the wait are the bot's own.
function commands.gather(player, arg)
	local what, usage = H.parseGather(arg)
	if not what then
		tell(player, "gather", {err = usage})
		return
	end
	local P = ChaosProfessions
	if not (P and P.probe) then
		tell(player, "gather", {err = "no professions"})
		return
	end
	local probe = P.probe(player)
	if what == "corpse" or what == "water" then
		-- O657: the way on foot to the nearest fresh corpse (the knife) or the nearest fishable water (the rod): the guide of that tool answers
		probe.guide = what == "corpse" and probe.flayGuide or probe.angleGuide
		local got, why = goalPath(player, probe)
		tell(player, "gather", H.cutAnswer(probe, got or {err = why}))
	elseif what == "path" then
		local got, why = goalPath(player, probe)
		tell(player, "gather", H.cutAnswer(probe, got or {err = why}))
	else
		tell(player, "gather", H.cutAnswer(probe))
	end
end

-- ---------------------------------------------------------------- O657 the exercise dummy, the mount and the kill task
-- "!tester dummy [state | path | give | clear]": ChaosExercise.probe (the weapon, the dummy, the skill and its tries, `guide`), the engine's path next to the
-- dummy; `give` / `clear` are the TEST ONLY weapon (a tester only, logged). The use of the weapon on the dummy is the bot's own packet.
function commands.dummy(player, arg)
	local what, usage = H.parseDummy(arg)
	if not what then
		tell(player, "dummy", {err = usage})
		return
	end
	local E = ChaosExercise
	if not (E and E.probe and E.testerGive) then
		tell(player, "dummy", {err = "no exercise weapons"})
		return
	end
	if what == "give" then
		local ok, why = E.testerGive(player)
		tell(player, "dummy", H.cutAnswer(E.probe(player), ok and {granted = true} or {err = tostring(why or "refused")}))
	elseif what == "clear" then
		local n = E.testerClear(player)
		tell(player, "dummy", H.cutAnswer(E.probe(player), {cleared = n}))
	elseif what == "path" then
		local probe = E.probe(player)
		local got, why = goalPath(player, probe)
		tell(player, "dummy", H.cutAnswer(probe, got or {err = why}))
	else
		tell(player, "dummy", H.cutAnswer(E.probe(player)))
	end
end

-- "!tester task [state | where NAME | path]": ChaosBestiary.probe (the kill tasks held, the monster to hunt, the guide); `where NAME` is the bounty
-- board's "where does it spawn" (ChaosBounty.probe), `path` the engine's path to the guide's goal. Nothing here accepts, moves or fights.
function commands.task(player, arg)
	local want, usage = H.parseTask(arg)
	if not want then
		tell(player, "task", {err = usage})
		return
	end
	local X = ChaosBestiary
	if not (X and X.probe) then
		tell(player, "task", {err = "no bestiary"})
		return
	end
	if want.what == "where" then
		local B = ChaosBounty
		local probe = B and B.probe and B.probe(player, want.name)
		tell(player, "task", H.bountyAnswer({where = probe and probe.where, pos = player:getPosition(), level = player:getLevel()}))
		return
	end
	local probe = X.probe(player)
	if want.what == "path" then
		local got, why = goalPath(player, probe)
		tell(player, "task", H.cutAnswer(probe, got or {err = why}))
		return
	end
	tell(player, "task", H.cutAnswer(probe))
end

-- "!tester mount [state | give | clear]": the mount as a person sees it: mounted or not (the outfit's mount), the speed, the base speed, whether the
-- tile is a protection zone (a mount is refused there), the mount given. `give` is a TEST ONLY mount (the cheapest free one of the store's list:
-- Player:addMount, set as the current mount; a tester only, logged), `clear` dismounts and takes the given mount back. The toggle is the bot's own
-- packet (0xD4), the same a click on the mount button sends.
local mountGiven = {}
-- O660: this engine (TFS 1.4.2) has Player:addMount / removeMount / hasMount and no setCurrentMount / getCurrentMount / toggleMount in Lua; the
-- current mount is the player storage the engine reads itself (const.h PSTRG_MOUNTS_CURRENTMOUNT = PSTRG_RESERVED_RANGE_START + 2001 + 10)
local MOUNT_CURRENT = 10002011
local function mountState(player)
	local tile = Tile(player:getPosition())
	local out = {pz = tile ~= nil and tile:hasFlag(TILESTATE_PROTECTIONZONE) or false, level = player:getLevel()}
	local okO, outfit = pcall(function() return player:getOutfit() end)
	out.lookMount = okO and type(outfit) == "table" and tonumber(outfit.lookMount) or 0
	out.mounted = out.lookMount ~= 0
	out.speed = player:getSpeed()
	local okB, base = pcall(function() return player:getBaseSpeed() end)
	out.baseSpeed = okB and base or nil
	local okC, cur = pcall(function() return player:getStorageValue(MOUNT_CURRENT) end)
	out.current = okC and tonumber(cur) or nil
	out.granted = mountGiven[player:getId()]
	return out
end

function commands.mount(player, arg)
	local what, usage = H.parseMount(arg)
	if not what then
		tell(player, "mount", {err = usage})
		return
	end
	if what == "give" then
		local okS, shop = pcall(dofile, "data/scripts/chaos/shop_cosmetics.lua")
		local pick = H.pickMount(okS and type(shop) == "table" and shop.mounts or nil)
		if not pick then
			tell(player, "mount", {err = "no mount in the store's list"})
			return
		end
		local ok, err = pcall(function()
			if not player:hasMount(pick.id) then
				player:addMount(pick.id)
			end
			player:setStorageValue(MOUNT_CURRENT, pick.id)
		end)
		if not ok then
			tell(player, "mount", {err = "the engine refused the mount: " .. tostring(err):gsub("^.-:%d+: ", ""):sub(1, 80)}) -- O660: the words of the error, not the script path
			return
		end
		mountGiven[player:getId()] = pick.id
		print(string.format("[tester-helper] %s: TEST ONLY mount %d (%s) given", player:getName(), pick.id, pick.name))
		tell(player, "mount", H.cutAnswer(mountState(player), {name = pick.name}))
	elseif what == "clear" then
		local id = mountGiven[player:getId()]
		pcall(function() player:toggleMount(false) end)
		if id then
			pcall(function() player:removeMount(id) end)
			pcall(function() player:setStorageValue(MOUNT_CURRENT, 0) end)
			mountGiven[player:getId()] = nil
		end
		tell(player, "mount", H.cutAnswer(mountState(player), {cleared = id and true or false}))
	else
		tell(player, "mount", H.cutAnswer(mountState(player)))
	end
end

-- ---------------------------------------------------------------- O86 / O110 probes: summons, party, cursed chest
-- plain tables for H.targetKind / H.summonAnomalies
local function sideOf(c)
	if not c then
		return nil
	end
	local t = {id = c:getId(), isPlayer = c:isPlayer()}
	if not t.isPlayer then
		local m = c.getMaster and c:getMaster()
		if m and m:isPlayer() then
			t.ownerId = m:getId()
			c = m
		end
	end
	local party = c.getParty and c:getParty()
	local leader = party and party.getLeader and party:getLeader()
	if leader then
		t.partyLeaderId = leader:getId()
	end
	return t
end

local function summonSnapshot(player)
	local owner = sideOf(player)
	local snap = {who = player:getName(), ownerTarget = H.targetKind(owner, sideOf(player:getTarget())), summons = {}}
	for _, sm in ipairs(player:getSummons() or {}) do
		local row = {name = sm:getName(), id = sm:getId(), target = H.targetKind(owner, sideOf(sm:getTarget()))}
		local list = sm.getTargetList and sm:getTargetList() or {}
		row.listed = #list
		local allies = 0
		for _, c in ipairs(list) do
			-- the owner's side only: another player outside the party is an opponent in PvP (stock), not an ally
			local kind = H.targetKind(owner, sideOf(c))
			if kind == "owner" or kind == "ally" or kind == "summon" then
				allies = allies + 1
			end
		end
		row.listedAllies = allies
		snap.summons[#snap.summons + 1] = row
	end
	return snap
end

-- !tester pet: the first pet species of pets_config.lua for the tester (ChaosPets.grant, source "staff", quiet), so the
-- pets check has a pet to call out; a pet the tester owns already stays as it is
function commands.pet(player)
	local P, cfg = ChaosPets, ChaosPetsConfig
	local first = cfg and cfg.species and cfg.species[1]
	if not (P and P.grant and P.owns and first) then
		tell(player, "pet", {err = "no pet system"})
		return
	end
	local had = P.owns(player, first.key)
	local ok, why = true, nil
	if not had then
		local okCall, res, msg = pcall(P.grant, player, first.key, "staff", true)
		ok, why = okCall and res ~= false, okCall and msg or res
	end
	-- the live pet (pets.lua P.live: its creature id, or why it rests) and the cooldowns: the check tells "did not
	-- come out" from a rule of the game (pz, a zone, other summons, the death or call cooldown)
	local live = P.live and P.live[player:getId()]
	local pc = live and live.cid and Creature(live.cid)
	local cool = P.cool and P.cool[player:getGuid()] or {}
	local now = os.time()
	tell(player, "pet", {key = first.key, had = had, owns = P.owns(player, first.key), err = (not ok) and tostring(why) or nil,
		live = live and live.species or nil, cid = (pc and not pc:isRemoved()) and live.cid or nil,
		rest = live and live.rest or nil, summonLeft = math.max(0, (tonumber(cool.summon) or 0) - now),
		deathLeft = math.max(0, (tonumber(cool.death) or 0) - now)})
end

function commands.summons(player)
	local snap = summonSnapshot(player)
	snap.count = #snap.summons
	tell(player, "summons", snap)
end

-- the game's Party:onShareExperience lives in the events state (data/events/scripts/party.lua), not in this one: its
-- file is loaded here once in a sandbox (its Party methods go to a table of their own, nothing of this state changes).
-- Before, `party:onShareExperience` was nil here and every live party_xp check read "pays None" (live run 2026-11-01)
local shareFn
local function shareFunction()
	if shareFn ~= nil then
		return shareFn or nil
	end
	shareFn = false
	local env = setmetatable({Party = {}}, {__index = _G})
	local chunk
	if setfenv then
		chunk = loadfile("data/events/scripts/party.lua")
		if chunk then
			setfenv(chunk, env)
		end
	else
		chunk = loadfile("data/events/scripts/party.lua", "t", env)
	end
	if chunk and pcall(chunk) and type(env.Party.onShareExperience) == "function" then
		shareFn = env.Party.onShareExperience
	end
	return shareFn or nil
end

-- the shared experience of the party (O110 party XP): the switch, the engine's verdict, the rules of party_xp_core.lua on
-- the members' facts, the class lines, and what the game's own Party:onShareExperience pays for 1000 experience
local function partyShare(party, data)
	local leader = party:getLeader()
	local okA, active = pcall(function() return party:isSharedExperienceActive() end)
	local okE, enabled = pcall(function() return party:isSharedExperienceEnabled() end)
	data.shareActive, data.shareEnabled = okA and active == true, okE and enabled == true
	local KX = ChaosPartyXpCore
	if not (KX and leader) then
		return
	end
	local function facts(p)
		local pos = p:getPosition()
		local line
		pcall(function() line = p:getVocation():getBase():getId() end)
		return {name = p:getName(), level = p:getLevel(), pos = {x = pos.x, y = pos.y, z = pos.z}, line = line,
			fighting = p:getCondition(CONDITION_INFIGHT, CONDITIONID_DEFAULT) ~= nil}
	end
	local lf, members, all = facts(leader), {}, {}
	all[1] = lf
	-- the engine's own gate of the switch (Game::playerEnableSharedPartyExperience): in a fight outside a protection zone
	local okZ, pz = pcall(function()
		local t = Tile(leader:getPosition())
		return t ~= nil and t:hasFlag(TILESTATE_PROTECTIONZONE)
	end)
	data.leaderPz = okZ and pz == true
	data.leaderBlocked = lf.fighting and not data.leaderPz
	for _, m in ipairs(party:getMembers()) do
		local f = facts(m)
		members[#members + 1], all[#all + 1] = f, f
	end
	-- the rules without the engine's verdict: who fails which one
	local diag = KX.diagnose({active = true, enabled = false, leader = lf, members = members})
	data.problems, data.levels = {}, {}
	for _, p in ipairs(diag.problems or {}) do
		data.problems[#data.problems + 1] = {name = p.name, kind = p.kind}
	end
	local highest = 0
	for _, f in ipairs(all) do
		data.levels[#data.levels + 1] = f.level
		highest = math.max(highest, f.level)
	end
	data.minLevel = KX.minLevel(highest)
	data.lines = KX.lineCount(all)
	data.bonusPct = KX.bonusPercent(data.lines)
	local fn = party.onShareExperience or shareFunction()
	local okS, share = pcall(function() return fn(party, 1000) end)
	if okS then
		data.shareOf1000 = tonumber(share)
	end
end

-- one kill by the leader on the engine's own death path (Creature::onDeath: a party with the share on and working pays
-- through Party:shareExperience, else the attacker alone): a monster made next to the leader and hit by the leader
-- down to 0. The engine runs the death on its next creature check, so the gains are read KILL_READ_MS later.
-- done({leader, partner (experience gained), active, enabled (after the hits), dead, hp, hpLeft, pz, err})
local KILL_MONSTER, KILL_HITS, KILL_READ_MS, KILL_ROUNDS, KILL_STREET = "Demon", 20, 1500, 3, 20
local function hitDown(lid, id, out)
	for _ = 1, KILL_HITS do
		local mon = Monster(id)
		if not mon or mon:getHealth() <= 0 then
			return
		end
		-- twenty times the health left plus one, capped below 2^31 (max health x 10 of a level-scaled monster overflowed): a class that deals a fraction of a physical hit rounds a hit of 3 down to 0 and left the Demon at 2 health after the party kill (Unity live check, phase 30: Beastmaster)
		local hp = math.min((mon:getHealth() + 1) * 20, 2000000000)
		local okH, err = pcall(doTargetCombatHealth, lid, mon, COMBAT_PHYSICALDAMAGE, -hp, -hp, CONST_ME_NONE)
		if not okH then
			out.hitErr = tostring(err)
			return
		end
	end
end

-- experience per test monster and player: the bots go on hunting during a kill, so the change of their experience
-- also held other kills (live run 2026-11-01: a solo kill paid the partner 157408, the leader 6 times a solo kill).
-- The last callback (after every Chaos bonus) adds what the watched monster gives. {[monster id] = {[player id] = exp}}
TesterXpWatch = TesterXpWatch or {}
-- damage per player (summons count for their master) on a watched kill monster: without the share the engine pays
-- every attacker its damage share, so a partner that hit the test monster earns from it (live run 2026-11-03: 26)
TesterKillHits = TesterKillHits or {}
if EventCallback and not TesterXpWatchCb then
	TesterXpWatchCb = true
	local xpCb = EventCallback
	xpCb.onGainExperience = function(self, source, exp, rawExp)
		local w = source and TesterXpWatch[source:getId()]
		if w then
			local id = self:getId()
			w[id] = (w[id] or 0) + exp
		end
		return exp
	end
	xpCb:register(1000)
end

local function oneKill(leader, partner, done)
	local spot = freeNear(leader:getPosition(), nil, 3)
	local out = {leader = 0, partner = 0, dead = false}
	if not spot then
		out.err = "no free tile next to the leader"
		return done(out)
	end
	local tile = Tile(leader:getPosition())
	out.pz = tile and tile:hasFlag(TILESTATE_PROTECTIONZONE) or false
	local lid, pid = leader:getId(), partner:getId()
	local xl, xp = leader:getExperience(), partner:getExperience()
	local okM, m = pcall(Game.createMonster, KILL_MONSTER, spot, false, true)
	if not okM or not m then
		out.err = "the monster could not be made"
		return done(out)
	end
	local id = m:getId()
	out.hp = m:getHealth()
	TesterXpWatch[id] = {}
	TesterKillHits[id] = {}
	m:registerEvent("TesterHelperKillHits")
	hitDown(lid, id, out)
	local party = leader:getParty()
	out.active = party and party:isSharedExperienceActive() == true
	out.enabled = party and party:isSharedExperienceEnabled() == true
	local rounds = 0
	local function read()
		local left = Monster(id)
		-- a monster whose health a Chaos script set after it was made (level scaling) is hit down again
		if left and left:getHealth() > 0 and rounds < KILL_ROUNDS and Player(lid) then
			rounds = rounds + 1
			hitDown(lid, id, out)
			return addEvent(read, KILL_READ_MS)
		end
		out.dead = left == nil
		out.rounds = rounds + 1
		if left then
			out.hpLeft = left:getHealth()
			left:remove()
		end
		local watched = TesterXpWatch[id]
		TesterXpWatch[id] = nil
		local hits = TesterKillHits[id] or {}
		TesterKillHits[id] = nil
		out.partnerHit = (hits[pid] or 0) > 0
		local l, p = Player(lid), Player(pid)
		if not l or not p then
			out.err = "the leader or the partner left the game"
			return done(out)
		end
		-- the whole change too, to tell the other kills of the bots apart in the answer
		out.leaderAll, out.partnerAll = l:getExperience() - xl, p:getExperience() - xp
		if TesterXpWatchCb and watched then
			out.leader, out.partner, out.fromMonster = watched[lid] or 0, watched[pid] or 0, true
		else
			out.leader, out.partner = out.leaderAll, out.partnerAll
		end
		done(out)
	end
	addEvent(read, KILL_READ_MS)
end

-- the nearest free tile outside a protection zone round the leader (the temple's street), else nil
local function outsidePz(center, reach)
	for r = 1, reach do
		for dx = -r, r do
			for dy = -r, r do
				if math.max(math.abs(dx), math.abs(dy)) == r then
					local p = Position(center.x + dx, center.y + dy, center.z)
					local t = Tile(p)
					if t and t:getGround() and not t:hasFlag(TILESTATE_PROTECTIONZONE) and not t:hasFlag(TILESTATE_BLOCKSOLID)
						and not t:hasFlag(TILESTATE_FLOORCHANGE) and not t:hasFlag(TILESTATE_TELEPORT) and not t:getTopCreature()
						and freeNear(p, nil, 3) then
						return p
					end
				end
			end
		end
	end
	return nil
end

-- "party kill": the leader's real shared kill against a solo kill (O110 party XP). A leader in a protection zone (no
-- hunt spot it may use) steps out of it first; the partner, a tester too, is put next to the leader (range). One
-- kill with the share as the leader set it, then the share off and one solo kill; the switch is put back. The checks
-- compare both gains with what Party:onShareExperience pays (shareOf1000). done(kill)
local function sharedKill(player, party, done)
	if party:getLeader() ~= player or #party:getMembers() ~= 1 then
		return done({err = "not the leader of a party of 2"})
	end
	local partner = party:getMembers()[1]
	if not eligible(partner) then
		return done({err = "the partner is no tester"})
	end
	-- no kill in a protection zone: a leader in the temple (no hunt spot it may use) steps out to the street next to it
	local tile = Tile(player:getPosition())
	if tile and tile:hasFlag(TILESTATE_PROTECTIONZONE) then
		local street = outsidePz(player:getPosition(), KILL_STREET)
		if street then
			player:teleportTo(street)
		end
	end
	local spot = freeNear(player:getPosition(), nil, 2)
	if spot then
		partner:teleportTo(spot)
	end
	local lid, pid = player:getId(), partner:getId()
	-- both members active for the engine (Party ticksMap: damage to a hostile monster in the last pzLocked ms): one hit
	-- of a tenth of its health by each on a second monster, removed again before it dies (bots in the temple never hit
	-- anything; a hit of 1 was taken by the armour and counted 0 points)
	local wspot = freeNear(player:getPosition(), nil, 3)
	local okW, w = pcall(Game.createMonster, KILL_MONSTER, wspot or player:getPosition(), false, true)
	if okW and w then
		local hit = math.max(1, math.floor(w:getHealth() / 10))
		pcall(doTargetCombatHealth, lid, w, COMBAT_PHYSICALDAMAGE, -hit, -hit, CONST_ME_NONE)
		pcall(doTargetCombatHealth, pid, w, COMBAT_PHYSICALDAMAGE, -hit, -hit, CONST_ME_NONE)
		w:remove()
	end
	local was = party:isSharedExperienceActive() == true
	local kill = {monster = KILL_MONSTER}
	oneKill(player, partner, function(shared)
		kill.shared = shared
		local l, p = Player(lid), Player(pid)
		local pa = l and l:getParty()
		if not (l and p and pa) then
			kill.err = "the party broke up during the kill"
			return done(kill)
		end
		pa:setSharedExperience(false)
		-- the solo kill: the partner waits in its temple (a protection zone). Next to the leader its bot hit the monster
		-- itself and earned its own damage share (live run 2026-11-01: "a solo kill paid the partner 31 experience")
		local town = p:getTown()
		if town then
			p:teleportTo(town:getTemplePosition())
		end
		oneKill(l, p, function(solo)
			solo.partnerAway = town ~= nil
			kill.solo = solo
			local l2 = Player(lid)
			local pa2 = l2 and l2:getParty()
			if pa2 then
				pa2:setSharedExperience(was)
			end
			done(kill)
		end)
	end)
end

function commands.party(player, arg)
	local party = player:getParty()
	-- "leave": out through Party:removeMember; the client's leave packet is refused in a fight
	-- (Game::playerLeaveParty checks CONDITION_INFIGHT), and hunting bots are always in one
	if party and (arg or ""):lower() == "leave" then
		pcall(party.removeMember, party, player)
		party = player:getParty()
	end
	local data = {size = 0, members = {}}
	if party then
		local leader = party:getLeader()
		data.leader = leader and leader:getName() or nil
		data.size = #party:getMembers() + 1
		for _, m in ipairs(party:getMembers()) do
			data.members[#data.members + 1] = m:getName()
		end
		pcall(partyShare, party, data)
		if (arg or ""):lower() == "kill" then
			-- the answer comes after both kills (about 3 s)
			local pid = player:getId()
			-- its own kind with the kill alone: the party answer and the kill in one line was too long and never came
			local function answer(kill)
				local p = Player(pid)
				if p then
					tell(p, "partykill", kill)
				end
			end
			local ok, err = pcall(sharedKill, player, party, function(kill)
				local okA, errA = pcall(answer, kill)
				if not okA then
					print("[tester-helper] party kill: " .. tostring(errA))
				end
			end)
			if not ok then
				answer({err = tostring(err)})
			end
			return
		end
	end
	tell(player, "party", data)
end

local function ownChests(player)
	local out = {}
	local CC = ChaosCursedChest
	for _, ch in pairs(CC and CC.chests or {}) do
		if ch.ownerId == player:getGuid() then
			out[#out + 1] = ch
		end
	end
	return out
end

local function chestItemOf(ch)
	local tile = Tile(Position(ch.pos.x, ch.pos.y, ch.pos.z))
	return tile and tile:getItemById(ch.itemId)
end

-- !tester chest [spawn | use | state | abort]: a cursed chest next to the tester; use opens it (the horde starts), abort
-- ends the event and removes the chest. Answers {state, left (chests of the tester still known), monsters, horde, made}
-- and, while the chest stands, its tile {cx, cy, cz}: a client check then looks at that tile only, not at every
-- item that showed up near the tester (a corpse of the hunt spot is no chest).
function commands.chest(player, arg)
	local CC = ChaosCursedChest
	if not CC or not CC.spawnChest then
		tell(player, "chest", {err = "no cursed chest system"})
		return
	end
	local what = (arg or "spawn"):lower()
	local mine = ownChests(player)
	local ch = mine[1]
	if what == "spawn" then
		if not ch then
			local C, Kc = ChaosCursedChestConfig, ChaosCursedChestCore
			local level = Kc.areaLevel(C, player:getLevel(), player:getLevel())
			local function spawnAt(center)
				return CC.spawnChest(player, center, {name = "Tester Monster",
					pool = Kc.buildPool(C, "Rotworm", {"Rotworm"}, level, {}), gear = {}, monsterLevel = level, tier = "normal"})
			end
			ch = spawnAt(player:getPosition())
			if not ch then
				-- the rift and spell quest checks leave the tester in the temple: the chest goes to its hunt spot
				local tile = Tile(player:getPosition())
				local spot = tile and tile:hasFlag(TILESTATE_PROTECTIONZONE) and huntPos(player)
				if spot then
					player:teleportTo(spot)
					ch = spawnAt(player:getPosition())
				end
			end
			if not ch then
				-- no usable tile within the game's radius of the tester (a corridor, a doorway, tiles taken by the chests of the
				-- other testers on the same hunt spot: cursedchest.lua placeFor): the nearest free tile up to four away is the
				-- centre of the search instead. The chest then stands a few tiles from the tester, as a kill's would.
				local tile = Tile(player:getPosition())
				if not (tile and tile:hasFlag(TILESTATE_PROTECTIONZONE)) then
					for _, d in ipairs(T.RINGS) do
						local near = Position(player:getPosition().x + d[1], player:getPosition().y + d[2], player:getPosition().z)
						if math.max(math.abs(d[1]), math.abs(d[2])) >= 3 then
							ch = spawnAt(near)
							if ch then
								break
							end
						end
					end
				end
			end
			if ch then
				ch.level = level
			else
				local tile = Tile(player:getPosition())
				if tile and tile:hasFlag(TILESTATE_PROTECTIONZONE) then
					-- the game puts no chest in a protection zone (cursedchest.lua usableTile): the temple after a death
					tell(player, "chest", {err = "the tester stands in a protection zone: no chest there by design"})
				else
					-- before this answer the check read state "none" and called it a failure of the chest (live run 2026-11-15)
					tell(player, "chest", {err = "no tile for a chest near the tester (the game's own rule: not walkable, a house, a protection zone, taken)",
						pos = posOf(player:getPosition())})
				end
				return
			end
		end
	elseif what == "use" and ch then
		local item = chestItemOf(ch)
		if item then
			CC.use(player, item)
		end
	elseif what == "abort" and ch then
		if ch.state == "running" then
			CC.failEvent(ch, "gone")
		else
			local item = chestItemOf(ch)
			if item then
				item:remove()
			end
			CC.chests[ch.key] = nil
		end
	end
	mine = ownChests(player)
	ch = mine[1]
	local monsters = 0
	for _ in pairs(CC.tagged or {}) do
		monsters = monsters + 1
	end
	tell(player, "chest", {state = ch and ch.state or "none", left = #mine, monsters = monsters,
		horde = ch and ch.ev and ch.ev.horde or 0, made = ch and ch.ev and ch.ev.made or 0,
		cx = ch and ch.pos.x or nil, cy = ch and ch.pos.y or nil, cz = ch and ch.pos.z or nil})
end

-- ---------------------------------------------------------------- O110: waystone runs, rift layouts, content rewards
local CORPSE = 1988 -- a plain backpack stands in for a corpse

-- the items of a container, deep: {id, count, rarity}
local function itemsOf(container)
	local out = {}
	local ok, list = pcall(function() return container:getItems(true) end)
	for _, it in ipairs(ok and list or {}) do
		local row = {id = it:getId(), count = it:getCount()}
		local okR, r = pcall(function() return it:getCustomAttribute("rarity") end)
		row.rarity = okR and tonumber(r) or nil
		out[#out + 1] = row
	end
	return out
end

-- a monster as the content rewards see it (name, place, id); there is no real monster, so nothing in the world is spawned
local function standIn(name, pos, id)
	return {isMonster = function() return true end, isPlayer = function() return false end,
		getMaster = function() return nil end, getName = function() return name end,
		getPosition = function() return pos end, getId = function() return id end}
end

-- one kill of a stand-in boss through the game's own ChaosContentRewards.onKill into a backpack on the tester's tile;
-- the items it holds, or nil and the reason. The backpack is removed.
local function standInKill(player, monster, ctx)
	local CR, L = ChaosContentRewards, ChaosLoot
	if not (CR and CR.onKill and L and L.addToCorpse) then
		return nil, "no content rewards or loot system"
	end
	local corpse = Game.createItem(CORPSE, 1, player:getPosition())
	if not corpse then
		return nil, "no corpse"
	end
	ctx.monster, ctx.player, ctx.itemFind = monster, player, 1
	local ok, paid = pcall(CR.onKill, monster, corpse, player, ctx, L, {})
	local items = itemsOf(corpse)
	pcall(function() corpse:remove() end)
	return items, nil, ok and paid == true
end

local function countOf(items, id)
	local n = 0
	for _, it in ipairs(items) do
		if it.id == id then
			n = n + (it.count or 1)
		end
	end
	return n
end

local function areaOf(m)
	local cx, cy = math.floor((m.from.x + m.to.x) / 2), math.floor((m.from.y + m.to.y) / 2)
	local hx, hy = math.ceil(math.abs(m.to.x - m.from.x) / 2), math.ceil(math.abs(m.to.y - m.from.y) / 2)
	return Position(cx, cy, m.from.z), hx, hy
end

-- the creatures of a waystone map: onlyPlayers or monsters of the tier lists (no summons)
local function spectatorsOf(m, onlyPlayers)
	local centre, hx, hy = areaOf(m)
	local ok, list = pcall(Game.getSpectators, centre, false, onlyPlayers, hx, hx, hy, hy)
	return ok and list or {}
end

-- !tester waystone <tier> [loot]: a run of that tier on the game's own code, as the device runs it (tier_maps.lua): a
-- Rare waystone is written (WM.write), used (WM.choose) and taken (WM.take), the run starts (WT.startRun) on a map of the
-- tier's band; then it is read back: the item, the take, the run's modifiers, the level and health of the map's monsters
-- in range. With "loot" a stand-in boss of the map dies through ChaosContentRewards.onKill. The tester is not moved and
-- the pads, the teleport and the map's own device are not walked (base code); the map is put back as it was.
local function waystoneRun(player, arg)
	local WT, WM = ChaosWaystoneTiers, ChaosWaystoneMods
	local WK, KK = ChaosWaystoneModsCore, ChaosWaystoneTiersCore
	if not (WT and WM and WK and KK and WT.startRun and WM.take and WM.write and WM.config) then
		return {err = "no waystone system"}
	end
	local opts, bad = H.parseWaystone(arg)
	if not opts then
		return {err = bad}
	end
	local cfg, mcfg, t = WT.config, WM.config, opts.tier
	local tierRow = cfg.tiers[t]
	local mapIdx
	for _, bt in ipairs(KK.baseTiersOf(cfg, t)) do
		for i, m in ipairs(cfg.maps) do
			if mapIdx == nil and m.tier == bt and not KK.isRetired(cfg, m.from) then
				mapIdx = i
			end
		end
	end
	if not (tierRow and mapIdx) then
		return {err = "no map for tier " .. t}
	end
	local m = cfg.maps[mapIdx]
	if WM.runOf(mapIdx) or #spectatorsOf(m, true) > 0 then
		return {err = "map in use", map = mapIdx}
	end
	local sid = tierRow.item
	local ws = WK.roll(mcfg, t, "Rare", math.random)
	local item = player:addItem(sid, 1)
	-- a full bag puts the new item on the ground (addItem drops it): the device then finds no waystone on the tester
	local okTop, carried = pcall(function()
		local top = item and item:getTopParent()
		return top ~= nil and top.isPlayer ~= nil and top:isPlayer()
	end)
	if not (item and okTop and carried) then
		if item then
			pcall(item.remove, item)
		end
		return {err = "no room for the waystone (the bag is full)"}
	end
	WM.write(item, ws)
	local rd = WM.read(item) or {mods = {}}
	local ans = {tier = t, tierLevel = tierRow.level, map = mapIdx, nrolled = #ws.mods,
		held = {tier = rd.tier, mods = #rd.mods, rarity = WK.rarityName(mcfg, WK.rarityOf(mcfg, rd.mods)),
			expectRarity = WK.rarityName(mcfg, WK.rarityOf(mcfg, ws.mods))}}
	local before = player:getItemCount(sid)
	WM.choose(player, item)
	local ok, mods = WM.take(player, sid)
	ans.take = {ok = ok == true, mods = #(mods or {}), before = before, after = player:getItemCount(sid)}
	if not ok then
		return ans
	end
	-- the map's monsters that went through the init event: their health and level before the run
	local before_ = {}
	for _, c in ipairs(spectatorsOf(m, false)) do
		if #before_ < 8 and c:isMonster() and not c:getMaster() and WT.applied[c:getId()] then
			local e = WT.entryOf(c)
			if e and not e.boss then
				local mon = WM.mon and WM.mon[c:getId()]
				before_[#before_ + 1] = {c = c, id = c:getId(), name = c:getName(), max = c:getMaxHealth(),
					level = WT.applied[c:getId()], hp = mon and mon.hp or 1}
			end
		end
	end
	local prior = WT.active[mapIdx]
	local okRun, n = pcall(WT.startRun, {fromPos = m.from}, sid, mods)
	ans.rescaled = okRun and n or nil
	if not okRun then
		ans.err = "startRun: " .. tostring(n)
	end
	local run = WM.runs and WM.runs[mapIdx]
	ans.run = {active = WT.active[mapIdx], live = run ~= nil}
	if run then
		ans.run.tier, ans.run.mods = run.tier, #run.mods
		ans.run.seconds = (run.untilAt or 0) - os.time()
		ans.run.fxHealth = run.fx and run.fx.health or nil
		ans.run.bonus = run.bonus
	end
	ans.monsters = {}
	for _, b in ipairs(before_) do
		local row = {name = b.name, levelBefore = b.level, level = WT.applied[b.id]}
		local okM, max2 = pcall(function() return b.c:getMaxHealth() end)
		if okM and b.max > 0 then
			row.ratio = max2 / b.max
			local f = KK.scale(cfg, b.level, tierRow.level)
			row.expectRatio = f.health * ((run and run.fx and run.fx.health or 1) / b.hp)
		end
		local e = WT.entryOf(b.c)
		row.expectLevel = e and KK.level(cfg, e) or nil
		ans.monsters[#ans.monsters + 1] = row
	end
	if opts.loot then
		local centre = areaOf(m)
		local boss = standIn(cfg.bosses[m.tier] or "", centre, 2000000000)
		local e = WT.entryOf(boss)
		local CR = ChaosContentRewards
		if not (e and e.boss and CR and CR.config) then
			ans.loot = {err = "the stand-in boss is not a boss of the map"}
		else
			local c = CR.config.waystone
			local items, why, paid = standInKill(player, boss, {tier = "boss", orbLevel = tierRow.level})
			if not items then
				ans.loot = {err = why}
			else
				local allowed = {}
				for _, r in ipairs(c.boss.rarity) do
					allowed[r[1]] = true
				end
				local pieces, badRarity = 0, 0
				for _, it in ipairs(items) do
					if it.rarity and allowed[it.rarity] then
						pieces = pieces + 1
					elseif it.rarity and it.rarity < 5 then
						badRarity = badRarity + 1
					end
				end
				local orbs = {}
				for _, o in ipairs(c.boss.orbs) do
					if o.chance >= 100 then
						orbs[#orbs + 1] = {id = o.id, name = o.name, min = o.min, count = countOf(items, o.id)}
					end
				end
				ans.loot = {paid = paid == true, items = #items, pieces = pieces,
					minPieces = math.floor(c.boss.pieces.base + c.boss.pieces.perTier * (t - 1)), badRarity = badRarity,
					orbs = orbs, waystones = countOf(items, sid), minWaystones = c.boss.waystones.same}
			end
		end
	end
	-- the map back as it was: the run ends, the monsters go to the level they had (the band's first tier, or the last run's)
	pcall(WM.finish, mapIdx)
	local back = prior or (KK.defaultTier(cfg, mapIdx) or 1)
	pcall(WT.startRun, {fromPos = m.from}, cfg.tiers[back].item, {})
	WT.active[mapIdx] = prior
	pcall(WM.finish, mapIdx)
	return ans
end

function commands.waystone(player, arg)
	local ok, ans = pcall(waystoneRun, player, arg)
	tell(player, "waystone", ok and ans or {err = tostring(ans):sub(1, 120)})
end

-- !tester riftrun <layout | loot>: a rift of the highest tier the tester may open, opened as a player does (a tier key
-- into the backpack, ChaosRift.open in the temple's protection zone), then read: the layout of the run (kind, floors,
-- walkable cells, arrival, guardian, a sample of tiles on the ground), or (loot) the guardian's reward through
-- ChaosContentRewards.onKill with a stand-in guardian; then the run is closed (RF.interrupt: the key comes back).
local function riftRun(player, arg)
	local RF, cfg, RL = ChaosRift, ChaosRiftConfig, ChaosRiftLayout
	local R = ChaosRiftCore
	if not (RF and RF.open and RF.giveKey and cfg and cfg.key and R and RL and RF.runOf and RF.interrupt) then
		return {err = "no rifts on this server"}
	end
	local what, bad = H.parseRiftRun(arg)
	if not what then
		return {err = bad}
	end
	if RF.runOf[player:getId()] then
		return {err = "already inside a rift"}
	end
	local tier = H.riftTierFor(player:getLevel(), cfg.maxTier or 15, function(t) return R.tierInfo(cfg, t).minLevel end)
	if not tier then
		return {err = "level too low for a rift", level = player:getLevel()}
	end
	player:teleportTo(temple(player))
	RF.giveKey(player, {tier = tier, mods = {}}, "Tester key")
	local key = player:getItemById(cfg.key.itemId, true)
	if not key then
		return {err = "no key in the backpack"}
	end
	-- ready slots of the tier's band before the open: with none, RF.findReady takes another band by design (a full pool)
	local wantBand = RL.band(cfg, tier)
	local readyOfBand = 0
	for _, st in pairs(RF.slots or {}) do
		if st.state == "ready" and st.band == wantBand then
			readyOfBand = readyOfBand + 1
		end
	end
	local okOpen, opened = pcall(RF.open, player, key)
	local run = RF.runOf[player:getId()]
	if not (okOpen and opened and run and run.L) then
		return {err = "the rift did not open (a slot is busy or being built)", busy = true, tier = tier}
	end
	local ans = {tier = tier, theme = run.L.theme, kind = run.L.kind}
	local okRead, errRead = pcall(function()
		if what == "layout" then
			local L = run.L
			local lay = cfg.layout
			ans.band, ans.bandExpected, ans.readyOfBand = L.band, (RL.band(cfg, tier)), readyOfBand
			ans.floors, ans.side, ans.walkable, ans.route = #L.floors, L.side, L.walkable, L.route
			local th = lay.themes[L.theme]
			ans.kinds, ans.floorCounts = {}, {}
			for _, k in ipairs(th and th.kinds or {}) do
				ans.kinds[#ans.kinds + 1] = k[1]
			end
			for _, f in ipairs(th and th.floors or {}) do
				ans.floorCounts[#ans.floorCounts + 1] = f[1]
			end
			local bal = dofile("data/scripts/chaos/rift_layout_balance_config.lua")
			ans.limits = {walkableMin = bal.limits.walkableMin[L.band], walkableMax = bal.limits.walkableMax[L.band]}
			ans.startWalk = RL.isFloor(L, L.start.x, L.start.y, L.start.z)
			ans.bossWalk = RL.isFloor(L, L.bossSpawn.x, L.bossSpawn.y, L.bossSpawn.z)
			ans.mouthWalk = RL.isFloor(L, L.arenaStart.x, L.arenaStart.y, L.arenaStart.z)
			local p = player:getPosition()
			ans.playerWalk = RL.isFloor(L, p.x, p.y, p.z)
			-- 40 walkable cells spread over the whole list: each must be a tile with a ground that does not block
			local n, bare, blocked = 0, 0, 0
			local total = #L.walkKeys
			for i = 1, 40 do
				local k = L.walkKeys[math.max(1, math.floor(i * total / 40))]
				local x, y, z = RL.unkey(k)
				local tile = Tile(Position(x, y, z))
				n = n + 1
				if not tile or not tile:getGround() then
					bare = bare + 1
				elseif tile:hasFlag(TILESTATE_BLOCKSOLID) then
					blocked = blocked + 1
				end
			end
			ans.sample = {n = n, bare = bare, blocked = blocked}
		else
			local CRC = ChaosContentRewards
			if not (CRC and CRC.config) then
				ans.loot = {err = "no content rewards"}
				return
			end
			local gid = 2000000001
			RF.bossDead[gid] = true
			local items, why, paid = standInKill(player, standIn("Rift Guardian", player:getPosition(), gid),
				{tier = "boss", orbLevel = player:getLevel()})
			RF.bossDead[gid] = nil
			if not items then
				ans.loot = {err = why}
				return
			end
			local g = CRC.config.rift.guardian
			local ids, orbs = {}, 0
			for _, o in ipairs(CRC.config.rift.orbs) do
				ids[o.id] = true
			end
			for _, it in ipairs(items) do
				if ids[it.id] then
					orbs = orbs + (it.count or 1)
				end
			end
			-- the burst is (base + perTier x the run's tier) x the run's quantity (RF.contentOf): both as the game reads them
			local info = RF.contentOf and RF.contentOf(standIn("Rift Guardian", player:getPosition(), gid), player) or {}
			local runTier, quantity = info.tier or tier, info.quantity or 1
			ans.loot = {paid = paid == true, items = #items, orbs = orbs, runTier = runTier, quantity = quantity,
				minOrbs = math.floor((g.orbs.base + g.orbs.perTier * runTier) * quantity)}
		end
	end)
	if not okRead then
		ans.err = "read: " .. tostring(errRead):sub(1, 100)
	end
	-- out again, whatever happened
	pcall(RF.interrupt, run)
	ans.after = {inRun = RF.runOf[player:getId()] ~= nil, slotFree = RF.runs[run.slot] ~= run}
	return ans
end

-- ---------------------------------------------------------------- O278 unique passives, live
-- "!tester unique": a real unique copy (custom attribute chaos_unique) of an item whose passive is a damage multiplier
-- with no state to build (UNIQUE_FAMILIES) and works for the tester's class line goes into an empty slot. A plain hit to settle the
-- class's per-hit state, then one hit of a tenth of a fresh monster's health before it is worn, one on a second fresh monster after; the multiplier the game's
-- own rule gave the second hit is caught. Item and monsters are removed again.
-- O473: a passive's bonus is raw percent of the damage pool now, its price stays a multiplier. Every monster has ChaosPassiveDealt
-- from its spawn, so the pool asks ChaosUniquePassivesCore.dealtSplit first and ChaosUPDealt only applies the multiplier it kept:
-- ChaosUniquePassivesCore.dealt is not called on such a hit. Caught are the split (raw, mult) and the pool factor of the hit
-- before and of the hit after (ChaosDamagePool.part, primary part): m = mult x pool after / pool before. A hit no pool pass saw
-- (the old way) still answers through ChaosUniquePassivesCore.dealt.
-- Answers {id, family, line, slot, active = {families}, m, raw, mult, crit, lostBefore, lostAfter, hit} or {err}
local UNIQUE_FAMILIES = {critrule = true, opener = true, lowlife = true, overflow = true}
local SLOT_OF = { -- ItemType:getSlotPosition() bit -> CONST_SLOT_*; hands are left alone (the tester's weapon)
	{1, CONST_SLOT_HEAD}, {2, CONST_SLOT_NECKLACE}, {8, CONST_SLOT_ARMOR}, {64, CONST_SLOT_LEGS},
	{128, CONST_SLOT_FEET}, {256, CONST_SLOT_RING},
}

local function freeSlotOf(player, id)
	local it = ItemType(id)
	local bits = it and it:getSlotPosition() or 0
	for _, s in ipairs(SLOT_OF) do
		if math.floor(bits / s[1]) % 2 == 1 and not player:getSlotItem(s[2]) then
			return s[2]
		end
	end
	return nil
end

local function probeHit(player, spot, capture)
	local okM, m = pcall(Game.createMonster, KILL_MONSTER, spot, false, true)
	if not okM or not m then
		return nil
	end
	pcall(Chaos.registerOnce, m, "ChaosUPDealt")
	local before = m:getHealth()
	local d = math.max(1, math.floor(m:getMaxHealth() / 10))
	capture.m, capture.crit, capture.raw, capture.mult, capture.pool = nil, nil, nil, nil, nil
	pcall(doTargetCombatHealth, player:getId(), m, COMBAT_ENERGYDAMAGE, -d, -d, CONST_ME_NONE)
	local lost = before - m:getHealth()
	m:remove()
	return lost, d
end

function commands.unique(player)
	local UP, C, CFG = ChaosUniquePassives, ChaosUniquePassivesCore, ChaosUniquePassivesConfig
	if not (UP and UP.refresh and C and C.dealt and CFG and CFG.passives) then
		return tell(player, "unique", {err = "no unique passives on this server"})
	end
	local voc = player:getVocation()
	local line = ChaosClasses and ChaosClasses.lineKey and voc and ChaosClasses.lineKey(voc:getId())
	if not line then
		return tell(player, "unique", {err = "no class line"})
	end
	local cands = {}
	local ids = {}
	for id in pairs(CFG.passives) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local e = C.entry(CFG, id)
		if e and UNIQUE_FAMILIES[e.family] and C.worksFor(CFG, e, line) and freeSlotOf(player, id) then
			cands[#cands + 1] = e
		end
	end
	if #cands == 0 then
		return tell(player, "unique", {err = "no free slot for a unique of the " .. line .. " line"})
	end
	local tile = Tile(player:getPosition())
	if tile and tile:hasFlag(TILESTATE_PROTECTIONZONE) then
		local street = outsidePz(player:getPosition(), KILL_STREET)
		if street then
			player:teleportTo(street)
		end
	end
	local spot = freeNear(player:getPosition(), nil, 3)
	if not spot then
		return tell(player, "unique", {err = "no free tile next to the tester"})
	end
	local capture = {}
	local real, realSplit = C.dealt, C.dealtSplit
	local POOL = ChaosDamagePool
	local realPart = POOL and POOL.part
	C.dealt = function(cfg, S, act, ctx)
		local m = real(cfg, S, act, ctx)
		capture.m, capture.crit = m, ctx and ctx.crit
		return m
	end
	if realSplit then
		C.dealtSplit = function(cfg, S, act, ctx)
			local raw, mult, list = realSplit(cfg, S, act, ctx)
			capture.raw, capture.mult, capture.crit = raw, mult, ctx and ctx.crit
			return raw, mult, list
		end
	end
	if realPart then
		POOL.part = function(hit, combatType, which, treeRaw)
			local factor, sum, list = realPart(hit, combatType, which, treeRaw)
			if which == "primary" and hit and hit.attacker and hit.attacker.getId and hit.attacker:getId() == player:getId() then
				capture.pool = factor
			end
			return factor, sum, list
		end
	end
	local out = {line = line}
	local capWas
	local ok, err = pcall(function()
		-- the first hit of a character reads other than the ones after it for classes with state per hit (Beastmaster 159 then 87, Thief 234 then 304 in the Unity live check of phase 30:
		-- the plain hit twice, the passive explained the third exactly): the baseline is a second plain hit on a fresh monster
		out.lostFirst, out.hit = probeHit(player, spot, capture)
		out.lostBefore = probeHit(player, spot, capture)
		local poolBefore = capture.pool
		-- the first candidate the slot takes (the engine refuses some for the class or a slot rule: live run 2026-11-01)
		local pick, slot, refused = nil, nil, {}
		for _, e in ipairs(cands) do
			local sl = freeSlotOf(player, e.id)
			local item = sl and Game.createItem(e.id, 1)
			if item then
				item:setCustomAttribute("chaos_unique", 1)
				local rv = player:addItemEx(item, false, sl)
				if rv == RETURNVALUE_NOTENOUGHCAPACITY and not capWas then
					-- the potions and loot fill the capacity (the engine's rule takes no flag): the capacity is raised for
					-- the probe and put back at the end (live run 2026-11-01: half the bots, code 21; the inventory can
					-- weigh more than the capacity already, so the item's weight alone was not enough)
					capWas = player:getCapacity()
					player:setCapacity(capWas + 10000000)
					rv = player:addItemEx(item, false, sl)
				end
				if rv == RETURNVALUE_NOERROR then
					pick, slot = e, sl
					break
				end
				refused[#refused + 1] = e.id .. ":" .. tostring(rv)
				if #refused >= 12 then
					break
				end
			end
		end
		if not pick then
			out.err = "no unique went into its slot (" .. table.concat(refused, " ") .. ")"
			return
		end
		out.id, out.family, out.slot, out.tried = pick.id, pick.family, slot, #refused + 1
		local st = UP.refresh(player)
		out.active = {}
		for _, e in ipairs(st and st.act or {}) do
			out.active[#out.active + 1] = e.family
		end
		out.lostAfter = probeHit(player, spot, capture)
		out.m, out.crit = capture.m, capture.crit
		if out.m == nil and capture.mult ~= nil then
			-- the pool way: the multiplier the event applied times what the passive's raw percent moved the pool's factor
			local before, after = poolBefore or 1, capture.pool or 1
			out.m = capture.mult * (before > 0 and after / before or 1)
			out.raw, out.mult = capture.raw, capture.mult
		end
		local worn = player:getSlotItem(slot)
		if worn and worn:getId() == pick.id then
			worn:remove()
		end
		UP.refresh(player)
	end)
	C.dealt, C.dealtSplit = real, realSplit
	if realPart then
		POOL.part = realPart
	end
	if capWas then
		player:setCapacity(capWas)
	end
	if not ok then
		out.err = tostring(err)
	end
	tell(player, "unique", out)
end

-- two fist weapons (engine patch 0087, O360): a Monk-line bot puts one in each hand through the engine's own slot rule
-- (addItemEx runs Player::queryAdd and the Equip event), hits a Demon next to it with the auto attack and counts the
-- melee hits and the off-hand strikes (physical, ORIGIN_NONE) it deals; any other class must be refused the fist weapon.
-- Answer kind "fists": {able (Monk line), left, right (return codes; 0 = worn), melee, off, meleeSum, offSum, gated (off-hand
-- strikes the attack rate gate refused), small (melee hits too small for a strike), err}
local FIST_IDS, FIST_WATCH_MS = {36656, 36657}, 10000
-- a melee hit under this many points may bring an off-hand strike of 0 (O580, see the health event below)
local FIST_TINY_HIT = 4
-- monster id -> {player id, counts}; a global, so the doTargetCombat wrapper below (made once) sees it after a reload
TesterFistWatch = TesterFistWatch or {}
local fistWatch = TesterFistWatch
-- the off-hand strikes are capped at ChaosAttackRate.limits.offhand / fistOffhand a second per player (O426, 1.5): a hit the
-- gate refused brings no strike by rule (live run 2026-11-15: "14 melee hits but 11 off-hand strikes"). The gate is wrapped
-- once (a flag on the table itself, so a reload does not wrap it twice) and counts its refusals for a probe in progress.
local function countGate()
	local R = ChaosAttackRate
	if type(R) ~= "table" or type(R.gate) ~= "function" or R.testerGateWrapped then
		return
	end
	R.testerGateWrapped = true
	local realGate = R.gate
	R.gate = function(pid, key, ...)
		local allowed = realGate(pid, key, ...)
		if not allowed and (key == "offhand" or key == "fistOffhand") then
			for _, w in pairs(TesterFistWatch) do
				if w.pid == pid then
					w.gated = w.gated + 1
				end
			end
		end
		return allowed
	end
end

local fistEvent = CreatureEvent("TesterHelperDualFist")
function fistEvent.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	local w = fistWatch[creature:getId()]
	if w and attacker and attacker:getId() == w.pid and primaryType ~= COMBAT_HEALING then
		local dmg = math.abs(primaryDamage) + math.abs(secondaryDamage)
		if origin == ORIGIN_MELEE then
			w.melee, w.meleeSum = w.melee + 1, w.meleeSum + dmg
			-- a hit this small can round its off-hand strike to 0 after the class's cut (ChaosClasses.offhandDamage floors
			-- hit x share x ratio + 0.5; the Thief's main hit is cut by 1 / (1 + share x ratio) first): no strike is no bug
			if dmg < FIST_TINY_HIT then
				w.small = w.small + 1
			end
		end
	end
	-- the probe's Demon never dies: a kill would pay experience to the bot's party (live run 2026-11-01: party_xp read
	-- the share of a Monk's probe kill; the monster level scaling can undo a raised maximum health)
	if w and creature:getHealth() - (math.abs(primaryDamage) + math.abs(secondaryDamage)) < creature:getMaxHealth() / 2 then
		Chaos.heal(creature, creature:getMaxHealth() - creature:getHealth()) -- O682: a one-argument addHealth heals nothing on this engine
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
fistEvent:type("healthchange")
fistEvent:register()

-- the off-hand strike is ORIGIN_NONE, and the engine runs no onHealthChange event for that origin (Game::combatChangeHealth:
-- it stops scripted hits from recursing; live run 2026-11-01: 0 strikes seen though the strike was dealt), so the strikes
-- are counted where the script deals them: a physical ORIGIN_NONE doTargetCombat from the bot on its probe Demon
if type(doTargetCombat) == "function" and not TesterFistWrapped then
	TesterFistWrapped = true
	local realCombat = doTargetCombat
	-- the arguments go on exactly as given: an explicit nil origin would be read as ORIGIN_NONE, not the default
	-- (live run 2026-11-01: every unique_passive probe hit lost its health events)
	doTargetCombat = function(...)
		local cid, target, ctype, min, _, _, origin = ...
		local ok, tid = pcall(function() return target and target:getId() end)
		local w = ok and tid and fistWatch[tid]
		if w and origin == ORIGIN_NONE and ctype == COMBAT_PHYSICALDAMAGE then
			local okC, pid = pcall(function() return type(cid) == "number" and cid or cid:getId() end)
			if okC and pid == w.pid then
				w.off, w.offSum = w.off + 1, w.offSum + math.abs(tonumber(min) or 0)
			end
		end
		return realCombat(...)
	end
end

-- one probe for both dual wields: spec = {kind (the answer kind), ids (the item of each hand), able (this class may hold
-- both), event (the class's combat event on the target)}. The hands are emptied (the items go back after); the probe
-- items carry the custom attribute tester_probe, so only they are taken off again.
local function dualProbe(player, spec)
	local out = {able = spec.able}
	local hands = {CONST_SLOT_LEFT, CONST_SLOT_RIGHT}
	local held = {}
	for i, slot in ipairs(hands) do
		held[i] = player:getSlotItem(slot)
	end
	local capWas = player:getCapacity()
	player:setCapacity(capWas + 10000000)
	local bag = player:getSlotItem(CONST_SLOT_BACKPACK)
	local function probeItem(item)
		local ok, v = pcall(function() return item:getCustomAttribute("tester_probe") end)
		return ok and v ~= nil
	end
	local function restore()
		for _, slot in ipairs(hands) do
			local worn = player:getSlotItem(slot)
			if worn and probeItem(worn) then
				worn:remove()
			end
		end
		for i, slot in ipairs(hands) do
			local top = held[i] and held[i]:getTopParent()
			-- only an item that left its hand (a failed move leaves it worn) and is still on the player
			if not player:getSlotItem(slot) and top and top.isPlayer and top:isPlayer() and top:getId() == player:getId() then
				if player:addItemEx(held[i]:clone(), false, slot) == RETURNVALUE_NOERROR then
					held[i]:remove()
				end
			end
		end
		player:setCapacity(capWas)
	end
	for i in ipairs(hands) do
		if held[i] and (not bag or held[i]:moveTo(bag) == false) then
			restore()
			out.err = "could not empty the hands"
			return tell(player, spec.kind, out)
		end
	end
	local function wear(i)
		local item = Game.createItem(spec.ids[i], 1)
		if not item then
			return nil
		end
		item:setCustomAttribute("tester_probe", 1)
		local rv = player:addItemEx(item, false, hands[i])
		if rv ~= RETURNVALUE_NOERROR then
			item:remove()
		end
		return rv
	end
	out.left = wear(1)
	if not spec.able then
		-- a class that may not hold both: the second item must be refused in the shield hand (fist weapons: in the weapon
		-- hand already, as no other class wears one at all)
		if spec.kind == "blades" then
			out.right = wear(2)
		end
		restore()
		return tell(player, spec.kind, out)
	end
	out.right = wear(2)
	if out.left ~= RETURNVALUE_NOERROR or out.right ~= RETURNVALUE_NOERROR then
		restore()
		return tell(player, spec.kind, out)
	end
	local tile = Tile(player:getPosition())
	if tile and tile:hasFlag(TILESTATE_PROTECTIONZONE) then
		local street = outsidePz(player:getPosition(), KILL_STREET)
		if street then
			player:teleportTo(street)
		end
	end
	-- next to the tester when a tile is free (a melee hit needs it adjacent), else within 3: the Demon walks in
	local spot = freeNear(player:getPosition(), nil, 1) or freeNear(player:getPosition(), nil, 3)
	local okM, m
	if spot then
		okM, m = pcall(Game.createMonster, KILL_MONSTER, spot, false, true)
	end
	if not okM or not m then
		restore()
		out.err = "no Demon next to the tester"
		return tell(player, spec.kind, out)
	end
	local w = {pid = player:getId(), melee = 0, off = 0, meleeSum = 0, offSum = 0, gated = 0, small = 0}
	pcall(countGate)
	fistWatch[m:getId()] = w
	m:registerEvent("TesterHelperDualFist")
	pcall(function() m:setMaxHealth(10000000) Chaos.heal(m, 10000000) end)
	-- player:setTarget skips the onTargetCombat callback a client attack runs, which registers the class's combat event
	-- on the target (monk_combat.lua, thief_combat.lua); without it the hits are the engine's bare ones (live run
	-- 2026-11-01)
	if Chaos and Chaos.registerOnce then
		Chaos.registerOnce(m, spec.event)
	else
		m:registerEvent(spec.event)
	end
	player:setTarget(m)
	local pid, mid = player:getId(), m:getId()
	addEvent(function()
		local p, mon = Player(pid), Creature(mid)
		fistWatch[mid] = nil
		if mon then
			mon:remove()
		end
		if not p then
			return
		end
		out.melee, out.off, out.meleeSum, out.offSum = w.melee, w.off, w.meleeSum, w.offSum
		out.gated, out.small = w.gated, w.small
		restore()
		tell(p, spec.kind, out)
	end, FIST_WATCH_MS)
end

function commands.fists(player)
	local voc = player:getVocation()
	local monk = ChaosMonk and ChaosMonk.isMonkLine and voc and ChaosMonk.isMonkLine(voc:getId()) or false
	-- the best pair the bot's level may wield (O580: the fixed pair of level 150 and 300 was refused below them, code 33)
	local ids = H.fistPair(player:getLevel(), ChaosFistWeapons and ChaosFistWeapons.items, FIST_IDS)
	dualProbe(player, {kind = "fists", ids = ids, able = monk, event = "ChaosMonkCombat"})
end

-- the Thief and Ninja dual wield (src-patch 0002, thief_combat.lua): a dagger in each hand; every melee hit of the main
-- hand brings an off-hand strike. Every other class (the Samurai too) must be refused the dagger in the shield hand.
-- Answer kind "blades": {able, left, right, melee, off, meleeSum, offSum, err}
local BLADE_IDS = {2379, 2379}

function commands.blades(player)
	local voc = player:getVocation()
	local able = ChaosClasses and ChaosClasses.isDualWielder and voc and ChaosClasses.isDualWielder(voc:getId()) or false
	dualProbe(player, {kind = "blades", ids = BLADE_IDS, able = able, event = "ChaosThiefCombat"})
end

function commands.riftrun(player, arg)
	local ok, ans = pcall(riftRun, player, arg)
	tell(player, "riftrun", ok and ans or {err = tostring(ans):sub(1, 120)})
end

-- ---------------------------------------------------------------- login: supplies once, hunt spot, info
local BACKPACK = 1988

local function supplies(player)
	if player:getStorageValue(STORE + 1) == 1 then
		return
	end
	local bag = player:getSlotItem(CONST_SLOT_BACKPACK)
	if not bag then
		bag = player:addItem(BACKPACK, 1, false, 1, CONST_SLOT_BACKPACK)
	end
	local K = ChaosTestKit
	local kit = K and K.kits and K.kindFor and K.kits[K.kindFor(player:getVocation():getId())]
	for _, slot in ipairs({CONST_SLOT_LEFT, CONST_SLOT_RIGHT}) do
		local id = kit and kit.slots and kit.slots[slot]
		if id and not player:getSlotItem(slot) then
			player:addItem(id, 1, false, 1, slot) -- the plain item: no ChaosMakeUnique
		end
	end
	for _, s in ipairs(SUPPLIES) do
		if bag then
			bag:addItem(s[1], s[2])
		else
			player:addItem(s[1], s[2])
		end
	end
	if player.setBankBalance then
		player:setBankBalance(player:getBankBalance() + GOLD)
	end
	player:setStorageValue(STORE + 1, 1)
end

-- a bot that logs in on ground above its level (a relog loop at a deadly spot: 509 of the 3241 deaths of the live run of
-- 2026-11-15 came within 5 s of the login) goes to the temple at once, outside the protection zones only. The bot then
-- walks back to a hunt of its level through `!tester hunt` (safeHunt), as a player's town portal would take it.
local function loginGuard(id)
	local p = Player(id)
	if not p or not eligible(p) then
		return
	end
	local tile = Tile(p:getPosition())
	if tile and tile:hasFlag(TILESTATE_PROTECTIONZONE) then
		return
	end
	local hot = H.hotSpot(p:getLevel(), monstersNear(p:getPosition(), HUNT_CHECK + 3))
	if hot then
		print(string.format("[tester-helper] %s logged in next to %s (level %s) at level %d: sent to the temple",
			p:getName(), tostring(hot[1]), tostring(hot[2]), p:getLevel()))
		p:teleportTo(temple(p))
	end
end

local login = CreatureEvent("TesterHelperLogin")
function login.onLogin(player)
	if not eligible(player) then
		return true
	end
	player:registerEvent("TesterHelperHealth")
	player:registerEvent("TesterHelperDeath")
	T.ids[player:getId()] = true
	T.hits[player:getId()] = nil
	T.loginAt[player:getId()] = os.time()
	if not huntPos(player) then
		local p = player:getPosition()
		player:setStorageValue(STORE + 2, p.x)
		player:setStorageValue(STORE + 3, p.y)
		player:setStorageValue(STORE + 4, p.z)
	end
	pcall(supplies, player)
	pcall(topUp, player)
	local id = player:getId()
	addEvent(function() pcall(loginGuard, id) end, 300)
	addEvent(function()
		local p = Player(id)
		if p and eligible(p) then
			info(p)
		end
	end, 1500)
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("TesterHelperLogout")
function logout.onLogout(player)
	T.ids[player:getId()] = nil
	T.seq[player:getId()] = nil
	T.hits[player:getId()] = nil
	T.loginAt[player:getId()] = nil
	return true
end
logout:type("logout")
logout:register()

-- ---------------------------------------------------------------- anomalies
local health = CreatureEvent("TesterHelperHealth")
function health.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if primaryType ~= COMBAT_HEALING and eligible(creature) then
		local dmg = H.damageOf(primaryDamage, primaryType, secondaryDamage, secondaryType)
		local hit = {kind = "taken", damage = dmg, health = creature:getHealth(), maxHealth = creature:getMaxHealth(),
			level = creature:getLevel()}
		local id = creature:getId()
		T.hits[id] = T.hits[id] or {}
		H.pushHit(T.hits[id], os.time(), {damage = dmg, by = attacker and attacker:getName() or "?"})
		local rule = H.hitAnomaly(hit)
		if rule then
			hit.who = creature:getName()
			hit.by = attacker and attacker:getName() or "?"
			hit.byLevel = attacker and attacker.getMonsterLevel and attacker:getMonsterLevel() or nil
			anomaly(rule, hit)
		end
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
health:type("healthchange")
health:register()

-- on monsters a tester hits: damage dealt by a tester (or its summon)
local dealt = CreatureEvent("TesterHelperDealt")
function dealt.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if primaryType ~= COMBAT_HEALING and attacker then
		local p = attacker
		if not p:isPlayer() and p:getMaster() then
			p = p:getMaster()
		end
		if eligible(p) then
			local dmg = H.damageOf(primaryDamage, primaryType, secondaryDamage, secondaryType)
			local hit = {kind = "dealt", damage = dmg, level = p:getLevel()}
			local rule = H.hitAnomaly(hit)
			if rule then
				hit.who = p:getName()
				hit.target = creature:getName()
				anomaly(rule, hit)
			end
		end
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
dealt:type("healthchange")
dealt:register()

-- on the party kill check's monster: who hit it (TesterKillHits)
local killHits = CreatureEvent("TesterHelperKillHits")
function killHits.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	local w = TesterKillHits[creature:getId()]
	if w and attacker and primaryType ~= COMBAT_HEALING then
		local p = attacker
		if not p:isPlayer() and p:getMaster() then
			p = p:getMaster()
		end
		if p:isPlayer() then
			w[p:getId()] = (w[p:getId()] or 0) + math.abs(primaryDamage or 0) + math.abs(secondaryDamage or 0)
		end
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
killHits:type("healthchange")
killHits:register()

local death = CreatureEvent("TesterHelperDeath")
function death.onDeath(creature, corpse, killer, mostDamageKiller)
	if eligible(creature) then
		local id = creature:getId()
		local started = T.loginAt[id]
		print("[tester-event] " .. H.json(H.deathRecord(T.hits[id], os.time(), {who = creature:getName(),
			level = creature:getLevel(), killer = killer and killer:getName() or "?", maxHealth = creature:getMaxHealth(),
			secsOnline = started and os.time() - started or nil})))
		T.hits[id] = nil
	end
	return true
end
death:type("death")
death:register()

local xp = EventCallback
xp.onGainExperience = function(self, source, exp, rawExp)
	if eligible(self) then
		local rule = H.xpAnomaly(self:getLevel(), exp)
		if rule then
			anomaly(rule, {who = self:getName(), level = self:getLevel(), gained = exp,
				source = source and source:getName() or "?"})
		end
	end
	return exp
end
xp:register(999)

local function scanItems(player)
	local seen = 0
	local function walk(container, depth)
		for i = 0, container:getSize() - 1 do
			local item = container:getItem(i)
			if item then
				seen = seen + 1
				local it = ItemType(item:getId())
				local attrs = {}
				for _, key in ipairs({"attack", "defense", "armor", "extradefense", "hitchance"}) do
					local ok, v = pcall(function() return item:getAttribute(key) end)
					if ok and type(v) == "number" then
						attrs[key] = v
					end
				end
				local rule = H.itemAnomaly({count = item:getCount(), stackable = it:isStackable(), attrs = attrs})
				if rule then
					anomaly(rule, {who = player:getName(), item = it:getName(), id = item:getId(), count = item:getCount()})
				end
				if depth < 3 and item:isContainer() then
					walk(item, depth + 1)
				end
			end
			if seen > 500 then
				return
			end
		end
	end
	local bp = player:getSlotItem(CONST_SLOT_BACKPACK)
	if bp and bp:isContainer() then
		walk(bp, 0)
	end
end

-- ---------------------------------------------------------------- targets
local function nearestMonster(player)
	local pos = player:getPosition()
	local list = {}
	for _, c in ipairs(Game.getSpectators(pos, false, false, RANGE, RANGE, RANGE, RANGE)) do
		if c:isMonster() then
			list[#list + 1] = {pos = c:getPosition(), health = c:getHealth(), owned = c:getMaster() ~= nil, id = c:getId(), c = c}
		end
	end
	local best = H.nearest(pos, list, RANGE)
	return best and best.c
end

-- O652: inside a PvP place a tester without a target aims at a foe tester (ChaosTesters.pvpFoe: both testers, the closed switch on, one place, the
-- place's own rule: the other team, nobody protected), never at a player and never outside a place. player:setTarget skips the callbacks, so this
-- is the bot's own rule; the server's guard (testers.lua) still cancels any hit the rules refuse.
local function pvpAim(player)
	local X = ChaosTesters
	if not (X and X.pvpFoe and X.pvpPlace and X.pvpPlace(player)) then
		return
	end
	local pos = player:getPosition()
	local list = {}
	for _, c in ipairs(Game.getSpectators(pos, false, true, RANGE, RANGE, RANGE, RANGE)) do
		if c:isPlayer() and c:getId() ~= player:getId() then
			local ok, foe = pcall(X.pvpFoe, player, c)
			list[#list + 1] = {pos = c:getPosition(), tester = eligible(c) and true or false, foe = ok and foe == true, health = c:getHealth(), id = c:getId(), c = c}
		end
	end
	local pick = H.pvpTarget(pos, list, RANGE)
	if pick then
		player:setTarget(pick.c)
		player:setDirection(H.directionTo(pos, pick.pos))
	end
end

-- one round of the loop. Returns true when the loop ends (the helper file is gone)
local function stepBody()
	T.step = T.step + 1
	local g = T.step % GROUPS
	for id in pairs(T.ids) do
		if id % GROUPS == g then
			local player = Player(id)
			if not player or not eligible(player) then
				T.ids[id] = nil -- gone, or not a tester: never acted on
			else
				if ChaosPinnacle and ChaosPinnacle.priorityTarget then
					-- O681: inside a pinnacle fight the add that shields, empowers or channels comes before the boss ("Break them!"), as a person aims
					local okP, add = pcall(ChaosPinnacle.priorityTarget, player)
					local cur = player:getTarget()
					if okP and add and (not cur or cur:getId() ~= add:getId()) then
						add:registerEvent("TesterHelperDealt")
						player:setTarget(add)
						player:setDirection(H.directionTo(player:getPosition(), add:getPosition()))
					end
				end
				if not player:getTarget() then
					pcall(pvpAim, player) -- O652: a foe tester inside a PvP place first
				end
				if not player:getTarget() then
					local monster = nearestMonster(player)
					if monster then
						monster:registerEvent("TesterHelperDealt")
						player:setTarget(monster)
						player:setDirection(H.directionTo(player:getPosition(), monster:getPosition()))
					end
				end
				-- O86: a summon that targets its owner or an ally, or an owner stuck with its own summon
				if player.getSummons and #(player:getSummons() or {}) > 0 then
					local okS, snap = pcall(summonSnapshot, player)
					if okS then
						T.seen = T.seen or {}
						for _, a in ipairs(H.summonAnomalies(snap, os.time(), T.seen)) do
							anomaly(a.rule, {who = a.who, summon = a.summon, kind = a.kind, level = player:getLevel()})
						end
					end
				end
				if T.step % 120 == g then -- every minute
					pcall(scanItems, player)
				end
			end
		end
	end
	if T.step % 120 == 0 then -- once a minute: the testers in game, on the server console
		local n = 0
		for _ in pairs(T.ids) do
			n = n + 1
		end
		local line = H.onlineLine(n, T.lastOnline, T.step / 120)
		if line then
			print(line)
		end
		T.lastOnline = n
	end
	-- testers stop removed this file: the loop ends (the server restart drops the rest of the helper)
	if T.step % 20 == 0 and not T.present() then
		T.started = false
		print("[tester-helper] stopped: " .. T.FILE .. " is gone")
		return true
	end
	return false
end

-- The loop is a timer: an error in a round (a monster that left, a player that logged out between two lines) must neither
-- throw into the engine as "Lua Script Error ... in a timer event" nor end the loop for every tester (O579). A round that
-- fails is printed once a minute at most and the next round runs.
local function step()
	local ok, stopped = pcall(stepBody)
	if not ok then
		local now = os.time()
		if not T.lastStepError or now - T.lastStepError >= 60 then
			T.lastStepError = now
			print("[tester-helper] error in the loop: " .. tostring(stopped))
		end
		stopped = false
	end
	if not stopped then
		addEvent(step, STEP_MS)
	end
end
T.step_fn = step

-- ---------------------------------------------------------------- O653 what the bot's own drops can do
-- "!tester found": reads the backpack and the worn gear (never gives or moves anything). Orbs by key (ChaosCrafting.orbByKey), gems, runes, charms,
-- cards, and the pieces with their set, unique and jewelry facts; H.foundReport scores them (H.chaseScore knows sets). The crafting window, the
-- use-with of a gem and the move to a worn slot are the bot's own packets.
local function flag(f)
	local ok, v = pcall(f)
	return ok and v and true or false
end

local function foundRows(player, bag)
	local orbOf = {}
	for key, orb in pairs((ChaosCrafting and ChaosCrafting.orbByKey) or {}) do
		if type(orb) == "table" and orb.id then
			orbOf[orb.id] = key
		end
	end
	local cardOf = {}
	local okC, cards = pcall(function() return ChaosCardsCore and ChaosCardsCore.cardIds and ChaosCardsCore.cardIds() end)
	for _, id in ipairs(okC and cards or {}) do
		cardOf[id] = true
	end
	local rows = {}
	for i = 0, bag:getSize() - 1 do
		local item = bag:getItem(i)
		if item then
			local id = item:getId()
			local it = ItemType(id)
			local slot = bagSlotOf(it)
			local row = {i = i, id = id, cid = it:getClientId(), n = item:getCount(), slot = slot, orb = orbOf[id],
				gem = flag(function() return ChaosGems and ChaosGems.isGem and ChaosGems.isGem(id) end),
				rune = flag(function() return ChaosSupports and ChaosSupports.isRune and ChaosSupports.isRune(id) end),
				charm = flag(function() return ChaosCharms and ChaosCharms.isCharm and ChaosCharms.isCharm(item) end),
				card = cardOf[id] or nil}
			if slot then
				row.score = pieceScore(item, it)
				local okS, set = pcall(function() return ChaosItemSets and ChaosItemSets.pieceOf and ChaosItemSets.pieceOf(item) end)
				row.set = okS and set and set.key or nil
				row.unique = flag(function() return item:getCustomAttribute("chaos_unique") ~= nil end)
				row.jewelry = slot == CONST_SLOT_NECKLACE or slot == CONST_SLOT_RING
			end
			rows[#rows + 1] = row
		end
	end
	return rows
end

-- O662: the weapon rows of the backpack and of the hands (read only; the weapon type 4 is a shield, 7 an ammunition, 0 no weapon)
local function handRow(item)
	local it = ItemType(item:getId())
	local wt = it:getWeaponType() or 0
	if not H.HAND_WEAPON_TYPES[wt] then
		return nil
	end
	local bits = it:getSlotPosition() or 0
	local ilvl = 0
	if ChaosCrafting and ChaosCrafting.levelOf then
		local ok, v = pcall(function() return ChaosCrafting.levelOf(item) end)
		ilvl = ok and tonumber(v) or 0
	end
	return {id = item:getId(), cid = it:getClientId(), wt = wt, il = ilvl, sc = pieceScore(item, it), two = math.floor(bits / 2048) % 2 == 1}
end

function H.handRows(bag)
	local rows = {}
	for i = 0, bag:getSize() - 1 do
		local item = bag:getItem(i)
		local row = item and handRow(item)
		if row then
			row.i = i
			rows[#rows + 1] = row
		end
	end
	return rows
end

function H.handWorn(player)
	local worn = {}
	for _, slot in ipairs({CONST_SLOT_LEFT, CONST_SLOT_RIGHT}) do
		local item = player:getSlotItem(slot)
		local row = item and handRow(item)
		if row then
			row.s = slot
			worn[#worn + 1] = row
		end
	end
	return worn
end

function commands.found(player, arg)
	local what, usage = H.parseFound(arg)
	if not what then
		tell(player, "found", {err = usage})
		return
	end
	local bag = player:getSlotItem(CONST_SLOT_BACKPACK)
	if not bag then
		tell(player, "found", {err = "no backpack"})
		return
	end
	local worn, state = {}, {sets = {}, size = {}}
	for _, e in ipairs(BAG_SLOTS) do
		local item = player:getSlotItem(e[2])
		if item then
			local okS, set = pcall(function() return ChaosItemSets and ChaosItemSets.pieceOf and ChaosItemSets.pieceOf(item) end)
			worn[e[2]] = {score = pieceScore(item, ItemType(item:getId())), set = okS and set and set.key or nil,
				unique = flag(function() return item:getCustomAttribute("chaos_unique") ~= nil end) or nil}
		end
	end
	local okT, st = pcall(function() return ChaosItemSets and ChaosItemSets.stateOf and ChaosItemSets.stateOf(player) end)
	for key, v in pairs(okT and st and st.sets or {}) do
		state.sets[key] = v.count or 0
	end
	for _, set in pairs((ChaosItemSets and ChaosItemSets.sets) or {}) do
		if type(set) == "table" and set.key and type(set.pieces) == "table" then
			state.size[set.key] = #set.pieces
		end
	end
	local report = H.foundReport(foundRows(player, bag), worn, state)
	report.bagClientId = ItemType(bag:getId()):getClientId()
	report.level = player:getLevel()
	local okB, bagOpen = pcall(function() local c = player:getContainerById(0); return c ~= nil and c:getId() == bag:getId() end)
	report.bagOpen = okB and bagOpen or false -- O662: the move packet names the backpack as container 0: only when it is open does a drag onto a slot find the item
	local okH, hands = pcall(function() return H.handReport(H.handRows(bag), H.handWorn(player)) end) -- O662: the weapons, so the bot can wear what it bought
	report.hands = okH and hands or nil
	tell(player, "found", report)
end

-- O658: `!tester gold [to N]`: the bank balance and the gold in the backpack; `to N` is the TEST ONLY top-up of the bank (H.goldPlan) that the bot
-- counts as a fallback when it cannot pay for the potions and the basic pieces of its gear-up
T.gold = T.gold or {} -- bot name -> gold granted since the helper loaded (a reload starts the allowance again)
function commands.gold(player, arg)
	local g, usage = H.parseGold(arg)
	if not g then
		tell(player, "gold", {err = usage})
		return
	end
	local name = player:getName()
	local bank = player:getBankBalance()
	local okM, money = pcall(function() return player:getMoney() end)
	local data = {bank = bank, money = okM and money or 0, level = player:getLevel(), total = T.gold[name] or 0}
	if g.to then
		local give, why = H.goldPlan(bank, g.to, T.gold[name] or 0)
		if give > 0 then
			player:setBankBalance(bank + give)
			T.gold[name] = (T.gold[name] or 0) + give
			data.bank, data.total = bank + give, T.gold[name]
		end
		data.granted, data.refused = give, why
	end
	tell(player, "gold", data)
end

T.FILE = "data/scripts/zz_tester_helper.lua"
function T.present()
	local f = io.open(T.FILE, "r")
	if f then
		f:close()
		return true
	end
	return false
end

-- the loop starts once, when the script loads (server start, or a reload of the scripts)
if not T.started then
	T.started = true
	addEvent(step, STEP_MS)
end
print("[tester-helper] running v" .. HELPER_VERSION .. " (TEST ONLY: chaos-ctl.sh testers stop removes data/scripts/zz_tester_helper*.lua)")

-- a /reload of the scripts while testers are online: pick them up again
for _, p in ipairs(Game.getPlayers and Game.getPlayers() or {}) do
	if eligible(p) then
		T.ids[p:getId()] = true
		p:registerEvent("TesterHelperHealth")
		p:registerEvent("TesterHelperDeath")
	end
end
