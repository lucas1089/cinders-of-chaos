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
--   * "!tester bag": empties the tester's own backpack of loot (everything but the potions) and tops the potions up
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
local LOCKER_SEARCH = 45 -- tiles around the temple for a depot locker (its floor and the ones above and below)
-- NPCs with a trade window, tried first by "shop": the NPC nearest the temple may only talk
local TRADERS = {"Material Broker", "Loot Buyer", "Wandering Merchant"}

-- chaos-ctl.sh reads this line: a server that still runs an older copy (no "v" or another number in its "running" line)
-- counts as "helper not loaded", so `testers start` restarts it. Raise it with every change of the helper files.
HELPER_VERSION = 9
TesterHelper = TesterHelper or {ids = {}, step = 0, hits = {}, loginAt = {}}
local T = TesterHelper
T.hits, T.loginAt = T.hits or {}, T.loginAt or {} -- a reload keeps the table of an older version

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
	player:sendTextMessage(MESSAGE_INFO_DESCR, H.encode(kind, data))
end

local function posOf(p)
	return {x = p.x, y = p.y, z = p.z}
end

local function info(player)
	local hp, mp = ItemType(7618), ItemType(7620)
	local data = {cid = player:getId(), level = player:getLevel(), pos = posOf(player:getPosition()),
		potions = {health = hp and hp:getClientId() or 0, mana = mp and mp:getClientId() or 0}}
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
for dx = -2, 2 do
	for dy = -2, 2 do
		if math.max(math.abs(dx), math.abs(dy)) == 2 then
			RINGS[#RINGS + 1] = {dx, dy}
		end
	end
end

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

function commands.hunt(player)
	local p = huntPos(player)
	if not p then
		tell(player, "hunt", {err = "no hunt spot"})
		return
	end
	local near = {}
	for _, c in ipairs(Game.getSpectators(p, false, false, HUNT_CHECK, HUNT_CHECK, HUNT_CHECK, HUNT_CHECK) or {}) do
		if c:isMonster() and not c:getMaster() then
			near[#near + 1] = {c:getName(), Chaos.monsterHuntingLevel(c, 0)}
		end
	end
	local hot = H.hotSpot(player:getLevel(), near)
	if hot then -- stale spot from before the safe-spawn fix: stay in the temple, the report shows it
		tell(player, "hunt", {err = "hunt spot too high: " .. hot[1] .. " level " .. hot[2]})
		return
	end
	player:teleportTo(p)
	tell(player, "hunt", {pos = posOf(player:getPosition())})
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

function commands.shop(player)
	local npc = findTrader(temple(player))
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
		player:teleportTo(temple(player))
		tell(player, "enter", {kind = "rift", tier = place.tier, keyClientId = it and it:getClientId() or 0, held = held,
			bagFull = bagFull or nil, pos = posOf(player:getPosition())})
		return
	end
	if place.kind == "npc" then
		local npc = Creature(place.name)
		if not npc or not npc:isNpc() then
			tell(player, "enter", {kind = "npc", err = "no such NPC", name = place.name})
			return
		end
		local spot = freeNear(npc:getPosition())
		if not spot then
			tell(player, "enter", {kind = "npc", err = "no free tile", name = place.name})
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
	local cmd, arg = H.parseCommand(param)
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

-- TEST ONLY: empties the backpack of loot (every slot of it that is not a supply; a bag goes with what it holds) and
-- tops up the potions. Only this tester's own backpack. The bots loot and never sell, so the bag fills and every
-- pickup says "There is not enough room."
function commands.bag(player)
	local bag = player:getSlotItem(CONST_SLOT_BACKPACK)
	if not bag then
		tell(player, "bag", {err = "no backpack"})
		return
	end
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
	tell(player, "bag", {removed = #remove, topped = ok and added or 0})
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
-- ends the event and removes the chest. Answers {state, left (chests of the tester still known), monsters}
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
			ch = CC.spawnChest(player, player:getPosition(), {name = "Tester Monster",
				pool = Kc.buildPool(C, "Rotworm", {"Rotworm"}, level, {}), gear = {}, monsterLevel = level, tier = "normal"})
			if not ch then
				-- the rift and spell quest checks leave the tester in the temple: the chest goes to its hunt spot
				local tile = Tile(player:getPosition())
				local spot = tile and tile:hasFlag(TILESTATE_PROTECTIONZONE) and huntPos(player)
				if spot then
					player:teleportTo(spot)
					ch = CC.spawnChest(player, player:getPosition(), {name = "Tester Monster",
						pool = Kc.buildPool(C, "Rotworm", {"Rotworm"}, level, {}), gear = {}, monsterLevel = level, tier = "normal"})
				end
			end
			if ch then
				ch.level = level
			else
				-- the game puts no chest in a protection zone (cursedchest.lua usableTile): the temple after a death
				local tile = Tile(player:getPosition())
				if tile and tile:hasFlag(TILESTATE_PROTECTIONZONE) then
					tell(player, "chest", {err = "the tester stands in a protection zone: no chest there by design"})
					return
				end
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
		horde = ch and ch.ev and ch.ev.horde or 0, made = ch and ch.ev and ch.ev.made or 0})
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
-- class's per-hit state, then one hit of a tenth of a fresh monster's health before it is worn, one on a second fresh monster after; the multiplier the glue's
-- own ChaosUniquePassivesCore.dealt returned on the second hit is caught. Item and monsters are removed again.
-- Answers {id, family, line, slot, active = {families}, m, crit, lostBefore, lostAfter, hit} or {err}
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
	capture.m, capture.crit = nil, nil
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
	local real = C.dealt
	C.dealt = function(cfg, S, act, ctx)
		local m = real(cfg, S, act, ctx)
		capture.m, capture.crit = m, ctx and ctx.crit
		return m
	end
	local out = {line = line}
	local capWas
	local ok, err = pcall(function()
		-- the first hit of a character reads other than the ones after it for classes with state per hit (Beastmaster 159 then 87, Thief 234 then 304 in the Unity live check of phase 30:
		-- the plain hit twice, the passive explained the third exactly): the baseline is a second plain hit on a fresh monster
		out.lostFirst, out.hit = probeHit(player, spot, capture)
		out.lostBefore = probeHit(player, spot, capture)
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
		local worn = player:getSlotItem(slot)
		if worn and worn:getId() == pick.id then
			worn:remove()
		end
		UP.refresh(player)
	end)
	C.dealt = real
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
-- Answer kind "fists": {able (Monk line), left, right (return codes; 0 = worn), melee, off, meleeSum, offSum, err}
local FIST_IDS, FIST_WATCH_MS = {36656, 36657}, 10000
-- monster id -> {player id, counts}; a global, so the doTargetCombat wrapper below (made once) sees it after a reload
TesterFistWatch = TesterFistWatch or {}
local fistWatch = TesterFistWatch
local fistEvent = CreatureEvent("TesterHelperDualFist")
function fistEvent.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	local w = fistWatch[creature:getId()]
	if w and attacker and attacker:getId() == w.pid and primaryType ~= COMBAT_HEALING then
		local dmg = math.abs(primaryDamage) + math.abs(secondaryDamage)
		if origin == ORIGIN_MELEE then
			w.melee, w.meleeSum = w.melee + 1, w.meleeSum + dmg
		end
	end
	-- the probe's Demon never dies: a kill would pay experience to the bot's party (live run 2026-11-01: party_xp read
	-- the share of a Monk's probe kill; the monster level scaling can undo a raised maximum health)
	if w and creature:getHealth() - (math.abs(primaryDamage) + math.abs(secondaryDamage)) < creature:getMaxHealth() / 2 then
		creature:addHealth(creature:getMaxHealth())
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
	local w = {pid = player:getId(), melee = 0, off = 0, meleeSum = 0, offSum = 0}
	fistWatch[m:getId()] = w
	m:registerEvent("TesterHelperDualFist")
	pcall(function() m:setMaxHealth(10000000) m:addHealth(10000000) end)
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
		restore()
		tell(p, spec.kind, out)
	end, FIST_WATCH_MS)
end

function commands.fists(player)
	local voc = player:getVocation()
	local monk = ChaosMonk and ChaosMonk.isMonkLine and voc and ChaosMonk.isMonkLine(voc:getId()) or false
	dualProbe(player, {kind = "fists", ids = FIST_IDS, able = monk, event = "ChaosMonkCombat"})
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

local function step()
	T.step = T.step + 1
	local g = T.step % GROUPS
	for id in pairs(T.ids) do
		if id % GROUPS == g then
			local player = Player(id)
			if not player or not eligible(player) then
				T.ids[id] = nil -- gone, or not a tester: never acted on
			else
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
		return
	end
	addEvent(step, STEP_MS)
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
