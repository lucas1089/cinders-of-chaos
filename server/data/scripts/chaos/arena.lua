-- Ranked PvP arena: 1v1, 2v2 and 3v3 with Elo ratings per mode (client game_arena, extended opcode 236); the PvP
-- season rating of each mode is kept by arena_season.lua (called from finish()).
-- Settings: arena_config.lua. Pure part (ratings, matchmaking, level rule, death catch, timeout): arena_core.lua,
-- tested by tests/arena_test.lua. Overview and numbers: server/README.md "Arena".
--
-- Flow
--   !arena queue 1v1 | 2v2 | 3v3 (or the window): only in a protection zone, out of combat, not multi-clienting, not inside
--   a dungeon / the tower / a rift / the world boss rooms / a siege / the battleground; 2v2 = a party of exactly two,
--   3v3 = a party of exactly three, everyone checked.
--   -> every matchmakeSeconds the queue is paired by rating (window widens with the wait) and the level rule
--   -> a free slot of the instance grid is built at runtime (Game.createTile, footprint checked as worldboss.lua does),
--      everyone is checked again, teleported in, healed to full; countdown (no damage), then the fight
--   -> a hit that would kill is cut to leave 1 health: that player is defeated and moved to the gallery
--   -> one side down, or the timer: the higher health share wins (equal = draw); logout / leaving = defeated + a loss
--   -> ratings (DB), history (DB), rewards, leaderboard, result to the client; after endDelaySeconds everyone goes back
--      to where they stood when the match started, healed, without skull / fight lock
-- No skull, frag or death loss: no player ever dies inside, the white skull and the fight lock of the fight are
-- removed at the end (removeCondition(CONDITION_INFIGHT) clears both).

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
Chaos.arenaConfig = dofile("data/scripts/chaos/arena_config.lua")
if not (ChaosArenaCore and ChaosArenaCore.rateMatch) then
	dofile("data/scripts/chaos/arena_core.lua")
end

ChaosArena = ChaosArena or {}
local S = ChaosArena
local A = ChaosArenaCore
local OPCODE = (ChaosOpcodes and ChaosOpcodes.arena) or 236

local function C()
	return Chaos.arenaConfig
end

S.queue = S.queue or {} -- list of entries
S.matches = S.matches or {} -- slot -> match
S.matchOf = S.matchOf or {} -- creature id -> match
S.queued = S.queued or {} -- creature id -> entry
S.built = S.built or {} -- slot -> true
S.bad = S.bad or {} -- slot -> reason (footprint not free)
S.ratings = S.ratings or {} -- guid -> mode -> {rating, wins, losses, draws, matches, best}
S.seq = S.seq or 0
S.lastMatchmake = S.lastMatchmake or 0

local function P(t)
	return Position(t.x, t.y, t.z)
end

local function log(text)
	print("[Chaos arena] " .. text)
end

local function playerOf(creature)
	if not creature then
		return nil
	end
	if creature:isPlayer() then
		return creature
	end
	local master = creature:getMaster()
	return master and master:isPlayer() and master or nil
end

local function msg(player, text)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, text)
end

-- ======================================================================== ratings (DB)
local function T(k)
	return C().tables[k]
end

local function emptyRating()
	return {rating = C().rating.start, wins = 0, losses = 0, draws = 0, matches = 0, best = C().rating.start}
end

function S.loadRatings(guid, force)
	if S.ratings[guid] and not force then
		return S.ratings[guid]
	end
	local r = {}
	for mode in pairs(C().modes) do
		r[mode] = emptyRating()
	end
	local rows = Chaos.select(string.format("SELECT `mode`, `rating`, `wins`, `losses`, `draws`, `best` FROM `%s` WHERE `player_id` = %d",
		T("ratings"), guid), {{"mode", "s"}, {"rating", "n"}, {"wins", "n"}, {"losses", "n"}, {"draws", "n"}, {"best", "n"}})
	for _, row in ipairs(rows) do
		if r[row.mode] then
			r[row.mode] = {rating = row.rating, wins = row.wins, losses = row.losses, draws = row.draws,
				matches = row.wins + row.losses + row.draws, best = row.best}
		end
	end
	S.ratings[guid] = r
	return r
end

function S.ratingOf(guid, mode)
	return S.loadRatings(guid)[mode]
end

local function saveRating(guid, mode, e)
	db.query(string.format("INSERT INTO `%s` (`player_id`, `mode`, `rating`, `wins`, `losses`, `draws`, `best`, `updated_at`) " ..
		"VALUES (%d, %s, %d, %d, %d, %d, %d, %d) ON DUPLICATE KEY UPDATE `rating` = VALUES(`rating`), `wins` = VALUES(`wins`), " ..
		"`losses` = VALUES(`losses`), `draws` = VALUES(`draws`), `best` = VALUES(`best`), `updated_at` = VALUES(`updated_at`)",
		T("ratings"), guid, db.escapeString(mode), e.rating, e.wins, e.losses, e.draws, e.best, os.time()))
end

function S.recent(guid, limit)
	return Chaos.select(string.format("SELECT `mode`, `result`, `rating_before`, `rating_after`, `opponents`, `partner`, `reason`, " ..
		"`ended_at` FROM `%s` WHERE `player_id` = %d ORDER BY `match_id` DESC LIMIT %d", T("players"), guid, limit or C().historyRows),
		{{"mode", "s"}, {"result", "s"}, {"rating_before", "n"}, {"rating_after", "n"}, {"opponents", "s"}, {"partner", "s"},
			{"reason", "s"}, {"ended_at", "n"}})
end

-- ======================================================================== where a player is
local function inProtectionZone(player)
	if Game.getStorageValue(C().testNoPzStorage) == 1 then
		return true -- TEST ONLY (arena_config.lua testNoPzStorage)
	end
	local tile = Tile(player:getPosition())
	return tile ~= nil and tile:hasFlag(TILESTATE_PROTECTIONZONE)
end

local function inCombat(player)
	return player:isPzLocked() or player:hasCondition(CONDITION_INFIGHT)
end

-- the instance helpers of the other systems; the ones that do not exist (yet) are skipped
local function insideOther(player)
	if ChaosDungeonIsInside and ChaosDungeonIsInside(player) then
		return "a dungeon"
	end
	if ChaosTowerRun and ChaosTowerRun.isInside and ChaosTowerRun.isInside(player) then
		return "the Infinity Tower"
	end
	if ChaosWorldBoss and ChaosWorldBoss.inside and ChaosWorldBoss.layout and ChaosWorldBoss.inside(player:getPosition()) then
		return "the world boss arena"
	end
	if ChaosRift and ChaosRift.isInside and ChaosRift.isInside(player) then
		return "a rift"
	end
	if ChaosSiege and ChaosSiege.isInside and ChaosSiege.isInside(player) then
		return "a siege"
	end
	if ChaosBattleground and ChaosBattleground.isBusy and ChaosBattleground.isBusy(player) then
		return "the battleground (queue or match)"
	end
	return nil
end

function S.isInside(player)
	return S.matchOf[player:getId()] ~= nil
end

function S.isQueued(player)
	return S.queued[player:getId()] ~= nil
end

-- nil when the player may queue / start a match, else the reason
local function refusal(player, ignoreQueue)
	if player:getLevel() < C().minLevel then
		return string.format("You need level %d to fight in the arena.", C().minLevel)
	end
	if S.matchOf[player:getId()] then
		return "You are already in an arena match."
	end
	if not ignoreQueue and S.queued[player:getId()] then
		return "You are already in the arena queue (leave it in the Arena window)."
	end
	if Chaos.isMultiClient and Chaos.isMultiClient(player) then
		return "You cannot fight in the arena while another character from your connection is online."
	end
	local where = insideOther(player)
	if where then
		return "You cannot queue for the arena while inside " .. where .. "."
	end
	if inCombat(player) then
		return "You cannot queue for the arena while in combat."
	end
	if not inProtectionZone(player) then
		return "You can only queue for the arena in a protection zone."
	end
	return nil
end

-- ======================================================================== client
local function queueCounts()
	local n = {}
	for mode in pairs(C().modes) do
		n[mode] = 0
	end
	for _, e in ipairs(S.queue) do
		n[e.mode] = (n[e.mode] or 0) + 1
	end
	return n
end

function S.sendState(player, open)
	local guid = player:getGuid()
	local ratings = S.loadRatings(guid)
	local data = {open = open and true or false, ratings = {}, modes = C().modeOrder, queueCount = queueCounts()}
	for _, mode in ipairs(C().modeOrder) do
		local r = ratings[mode]
		data.ratings[mode] = {rating = r.rating, wins = r.wins, losses = r.losses, draws = r.draws, best = r.best}
	end
	local e = S.queued[player:getId()]
	if e then
		local waited = os.time() - e.joined
		data.queue = {mode = e.mode, waited = waited, window = A.window(C(), waited), rating = math.floor(e.rating)}
	end
	local m = S.matchOf[player:getId()]
	if m then
		data.match = {mode = m.mode, phase = m.phase}
	end
	local lo, hi = A.levelRange(C(), player:getLevel())
	data.rules = {minLevel = C().minLevel, levelLow = lo, levelHigh = hi, countdown = C().countdownSeconds,
		fight = C().fightSeconds}
	local st = player:getStorageValue(C().storage.firstWinDay)
	data.firstWinDone = st == Chaos.dayKey()
	data.recent = {}
	for _, row in ipairs(S.recent(guid)) do
		data.recent[#data.recent + 1] = {mode = row.mode, result = row.result, before = row.rating_before,
			after = row.rating_after, opponents = row.opponents, partner = row.partner, reason = row.reason, at = row.ended_at}
	end
	data.now = os.time()
	-- PvP seasons (arena_season.lua): the season rating, tier and placement per bracket
	if ChaosPvpSeason and ChaosPvpSeason.viewOf then
		local ok, view = pcall(ChaosPvpSeason.viewOf, guid)
		if ok then
			data.season = {id = (ChaosPvpSeason.current()), brackets = view}
		end
	end
	Chaos.send(player, OPCODE, "state", data)
end

local function stateLater(cid)
	addEvent(function(id)
		local p = Player(id)
		if p then
			S.sendState(p, false)
		end
	end, 100, cid)
end

-- ======================================================================== queue
local function removeEntry(entry)
	for i, e in ipairs(S.queue) do
		if e == entry then
			table.remove(S.queue, i)
			break
		end
	end
	for _, cid in ipairs(entry.members) do
		if S.queued[cid] == entry then
			S.queued[cid] = nil
		end
	end
end

-- members of a team mode party (2v2: two, 3v3: three), the player included; nil + reason otherwise
local function partyPair(player, size)
	size = size or 2
	local mode = size .. "v" .. size
	local party = player:getParty()
	if not party then
		return nil, string.format("%s is played as a party of %d: invite your partner%s first.", mode, size, size > 2 and "s" or "")
	end
	local list = {party:getLeader()}
	for _, m in ipairs(party:getMembers() or {}) do
		list[#list + 1] = m
	end
	if #list ~= size then
		return nil, string.format("%s is played as a party of exactly %d players.", mode, size)
	end
	return list
end

function S.join(player, mode)
	local cfg = C()
	if not cfg.modes[mode] then
		player:sendCancelMessage("Arena modes: " .. table.concat(cfg.modeOrder, ", ") .. ".")
		return false
	end
	local members = {player}
	if cfg.modes[mode].size > 1 then
		local list, err = partyPair(player, cfg.modes[mode].size)
		if not list then
			player:sendCancelMessage(err)
			return false
		end
		members = list
	end
	for _, m in ipairs(members) do
		local why = refusal(m)
		if why then
			if m ~= player then
				why = m:getName() .. ": " .. why
			end
			player:sendCancelMessage(why)
			if #members > 1 then
				msg(player, "Arena: " .. why)
			end
			return false
		end
	end
	local entry = {mode = mode, members = {}, guids = {}, names = {}, joined = os.time()}
	S.seq = S.seq + 1
	entry.id = S.seq
	local sum = 0
	for _, m in ipairs(members) do
		entry.members[#entry.members + 1] = m:getId()
		entry.guids[#entry.guids + 1] = m:getGuid()
		entry.names[#entry.names + 1] = m:getName()
		sum = sum + S.ratingOf(m:getGuid(), mode).rating
	end
	entry.rating = sum / #members
	S.queue[#S.queue + 1] = entry
	for _, cid in ipairs(entry.members) do
		S.queued[cid] = entry
		local m = Player(cid)
		if m then
			msg(m, string.format("Arena: you joined the %s queue (rating %d). Stay in a protection zone; the Arena window leaves the queue.",
				mode, math.floor(entry.rating)))
			stateLater(cid)
		end
	end
	return true
end

function S.leaveQueue(player, silent)
	local e = S.queued[player:getId()]
	if not e then
		if not silent then
			player:sendCancelMessage("You are not in the arena queue.")
		end
		return false
	end
	removeEntry(e)
	for _, cid in ipairs(e.members) do
		local m = Player(cid)
		if m then
			msg(m, m == player and "Arena: you left the queue." or ("Arena: " .. player:getName() .. " left the queue, so did your party."))
			stateLater(cid)
		end
	end
	return true
end

-- ======================================================================== instance
local function placeItem(pos, id)
	local tile = Tile(pos)
	if tile and not tile:getItemById(id) then
		return Game.createItem(id, 1, pos)
	end
end

function S.buildSlot(slot)
	if S.built[slot] then
		return true
	end
	local cfg = C()
	local L = A.layout(cfg, slot)
	local foot = A.footprint(L)
	-- runtime tiles are gone after a restart and S.built survives a script reload, so any tile already there
	-- belongs to the map (or to another system): never build over it, whatever its ground
	for _, t in ipairs(foot) do
		if Tile(P(t)) then
			return false, string.format("tile %d,%d,%d already exists in the map", t.x, t.y, t.z)
		end
	end
	for _, t in ipairs(foot) do
		local pos = P(t)
		local tile = Game.createTile(pos, true)
		if tile then
			if not tile:getGround() then
				Game.createItem(t.gallery and cfg.galleryGroundId or cfg.groundId, 1, pos)
			end
			if t.wall and not tile:getItemById(cfg.wallId) then
				Game.createItem(cfg.wallId, 1, pos)
			end
		end
	end
	for _, p in ipairs(L.pillars) do
		placeItem(P(p), cfg.pillarId)
	end
	for _, p in ipairs(L.basins) do
		placeItem(P(p), cfg.basinId)
	end
	S.built[slot] = true
	return true
end

local function cleanSlot(slot)
	local cfg = C()
	local keep = {[cfg.wallId] = true, [cfg.pillarId] = true, [cfg.basinId] = true}
	for _, t in ipairs(A.footprint(A.layout(cfg, slot))) do
		if not t.wall then
			local tile = Tile(P(t))
			if tile then
				for _, c in ipairs(tile:getCreatures() or {}) do
					if c:isMonster() then
						c:remove()
					end
				end
				for _, item in ipairs(tile:getItems() or {}) do
					if not keep[item:getId()] then
						item:remove()
					end
				end
			end
		end
	end
end

local function freeSlot()
	local busy = {}
	for slot in pairs(S.matches) do
		busy[slot] = true
	end
	while true do
		local slot = A.allocSlot(C(), busy, S.bad)
		if not slot then
			return nil
		end
		local ok, err = S.buildSlot(slot)
		if ok then
			return slot
		end
		S.bad[slot] = err
		log(string.format("slot %d not usable: %s", slot, tostring(err)))
	end
end

-- ======================================================================== match helpers
local HARMFUL = {"CONDITION_POISON", "CONDITION_FIRE", "CONDITION_ENERGY", "CONDITION_BLEEDING", "CONDITION_CURSED",
	"CONDITION_DROWN", "CONDITION_FREEZING", "CONDITION_DAZZLED", "CONDITION_PARALYZE"}

local function cleanse(player)
	for _, name in ipairs(HARMFUL) do
		local t = _G[name]
		if t then
			player:removeCondition(t)
		end
	end
end

-- full health. setHealth clamps to the base maximum (without item / buff bonuses) on this engine, so Chaos.heal tops
-- up the rest.
local function heal(player)
	player:setHealth(player:getMaxHealth())
	Chaos.heal(player, player:getMaxHealth() - player:getHealth())
	player:addMana(player:getMaxMana() - player:getMana())
end

local EVENTS = {"ChaosArenaHealth", "ChaosArenaMana", "ChaosArenaPrepareDeath"}

-- back to where the player stood, healed, no fight lock / white skull, events off
local function release(player, entry)
	S.matchOf[player:getId()] = nil
	player:setTarget(nil) -- or the attack goes on outside (the client cancels it too)
	for _, name in ipairs(EVENTS) do
		player:unregisterEvent(name)
	end
	cleanse(player)
	player:removeCondition(CONDITION_INFIGHT, CONDITIONID_DEFAULT)
	if player:getSkull() == SKULL_WHITE or player:getSkull() == SKULL_YELLOW then
		player:setSkull(SKULL_NONE)
	end
	heal(player)
	local dest = entry and entry.ret and P(entry.ret) or player:getTown():getTemplePosition()
	player:teleportTo(dest)
	player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
	player:removeCondition(CONDITION_INFIGHT, CONDITIONID_DEFAULT)
end

local function sides(m)
	local out = {{}, {}}
	for _, cid in ipairs(m.order) do
		local e = m.players[cid]
		local p = Player(cid)
		if p and not e.gone then
			e.health, e.maxHealth = p:getHealth(), p:getMaxHealth()
		elseif not e.defeated then
			e.health = 0
		end
		table.insert(out[e.team], e)
	end
	return out
end

local function eachOnline(m, fn)
	for _, cid in ipairs(m.order) do
		local e = m.players[cid]
		local p = Player(cid)
		if p and not e.gone then
			fn(p, e)
		end
	end
end

local function hud(m)
	local list = sides(m)
	local now = os.time()
	local left = m.phase == "countdown" and (m.fightAt - now) or (m.phase == "fight" and (m.endAt - now) or 0)
	local out = {phase = m.phase, mode = m.mode, left = math.max(0, left), sides = {{}, {}}}
	for side = 1, 2 do
		for _, e in ipairs(list[side]) do
			local pct = e.maxHealth and e.maxHealth > 0 and math.floor((e.health or 0) * 100 / e.maxHealth + 0.5) or 0
			out.sides[side][#out.sides[side] + 1] = {name = e.name, hp = e.defeated and 0 or pct, defeated = e.defeated or false,
				cid = e.cid}
		end
	end
	eachOnline(m, function(p, e)
		out.team = e.team
		Chaos.send(p, OPCODE, "hud", out)
	end)
end

-- a fighter is out of the fight (killing blow caught, left, refused to fight)
function S.defeat(m, e, reason, by)
	if e.defeated or m.phase == "done" then
		return
	end
	e.defeated = true
	e.reason = reason
	local cid = e.cid
	local text
	if reason == "defeated" then
		text = string.format("%s was defeated%s.", e.name, by and (" by " .. by) or "")
	elseif reason == "secure" then
		text = string.format("%s kept secure mode on and is out of the fight.", e.name)
	elseif reason == "mc" then
		text = string.format("%s left the fight (another character from the same connection logged in).", e.name)
	else
		text = string.format("%s left the arena.", e.name)
	end
	eachOnline(m, function(p)
		p:sendTextMessage(MESSAGE_STATUS_WARNING, "Arena: " .. text)
	end)
	if reason == "defeated" or reason == "secure" or reason == "mc" then
		-- moved out of the fight after the hit is done (never inside the combat handler)
		addEvent(function(id, matchId)
			local p = Player(id)
			if p and S.matchOf[id] and S.matchOf[id].id == matchId and S.matchOf[id].phase ~= "done" then
				local L = A.layout(C(), m.slot)
				local spots = L.galleryspots[e.team]
				m.galleryUsed[e.team] = (m.galleryUsed[e.team] or 0) + 1
				local spot = spots[math.min(#spots, m.galleryUsed[e.team])]
				p:getPosition():sendMagicEffect(CONST_ME_MORTAREA)
				p:teleportTo(P(spot), true)
				p:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
				if p:getHealth() < 1 then
					p:setHealth(1)
				end
			end
		end, 50, cid, m.id)
	end
end

-- ======================================================================== match start / end
local function teamOf(entry)
	local list = {}
	for i, cid in ipairs(entry.members) do
		list[#list + 1] = {cid = cid, guid = entry.guids[i], name = entry.names[i]}
	end
	return list
end

local finish

-- a, b = queue entries. Returns true, or false when an entry was dropped (or no slot is free).
local function startMatch(a, b)
	local cfg = C()
	-- check everyone again (they may have walked out of the protection zone, fought, logged out...)
	for _, entry in ipairs({a, b}) do
		for _, cid in ipairs(entry.members) do
			local p = Player(cid)
			local why = "a player of the group logged out."
			if p then
				why = refusal(p, true)
			end
			if why then
				removeEntry(entry)
				for _, other in ipairs(entry.members) do
					local o = Player(other)
					if o then
						msg(o, "Arena: a match was found but could not start, you were removed from the queue: " ..
							(o == p and why or ((p and p:getName() or "your partner") .. ": " .. why)))
						stateLater(other)
					end
				end
				return false
			end
		end
	end
	if cfg.modes[a.mode].size == 1 then
		local pa, pb = Player(a.members[1]), Player(b.members[1])
		if pa:getParty() and pa:getParty() == pb:getParty() then
			return false -- the base PvP rules forbid hitting a party member; they are paired with someone else
		end
	end
	local slot = freeSlot()
	if not slot then
		return false
	end
	removeEntry(a)
	removeEntry(b)
	S.seq = S.seq + 1
	local now = os.time()
	local m = {id = S.seq, slot = slot, mode = a.mode, phase = "countdown", startedAt = now,
		fightAt = now + cfg.countdownSeconds, endAt = now + cfg.countdownSeconds + cfg.fightSeconds,
		players = {}, order = {}, galleryUsed = {}}
	local L = A.layout(cfg, slot)
	for side, entry in ipairs({a, b}) do
		for i, e in ipairs(teamOf(entry)) do
			local p = Player(e.cid)
			local r = S.ratingOf(e.guid, m.mode)
			e.team = side
			e.level = p:getLevel()
			e.rating = r.rating
			e.matches = r.matches
			local pos = p:getPosition()
			e.ret = {x = pos.x, y = pos.y, z = pos.z}
			m.players[e.cid] = e
			m.order[#m.order + 1] = e.cid
			S.matchOf[e.cid] = m
			p:setTarget(nil)
			cleanse(p)
			heal(p)
			p:teleportTo(P(L.spawns[side][i]))
			p:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
			for _, name in ipairs(EVENTS) do
				p:registerEvent(name)
			end
		end
	end
	S.matches[slot] = m
	local names = {{}, {}}
	for _, cid in ipairs(m.order) do
		local e = m.players[cid]
		table.insert(names[e.team], string.format("%s (%d)", e.name, e.rating))
	end
	eachOnline(m, function(p, e)
		local opp = table.concat(names[3 - e.team], ", ")
		msg(p, string.format("Arena %s against %s. The fight starts in %d seconds; secure mode must be off (the client turns it off for you).",
			m.mode, opp, cfg.countdownSeconds))
		Chaos.send(p, OPCODE, "start", {mode = m.mode, team = e.team, countdown = cfg.countdownSeconds, fight = cfg.fightSeconds})
	end)
	log(string.format("match %d (%s) in slot %d: %s vs %s", m.id, m.mode, slot, table.concat(names[1], ", "),
		table.concat(names[2], ", ")))
	hud(m)
	return true
end

local function itemName(id)
	local it = ItemType(id)
	return it and it:getName() or tostring(id)
end

local function giveReward(player)
	local cfg = C()
	local st = {firstWinDay = player:getStorageValue(cfg.storage.firstWinDay),
		winsDay = player:getStorageValue(cfg.storage.winsDay), winsCount = math.max(0, player:getStorageValue(cfg.storage.winsCount))}
	local items, first, new = A.reward(cfg, Chaos.dayKey(), st)
	player:setStorageValue(cfg.storage.firstWinDay, new.firstWinDay)
	player:setStorageValue(cfg.storage.winsDay, new.winsDay)
	player:setStorageValue(cfg.storage.winsCount, new.winsCount)
	local parts = {}
	for _, it in ipairs(items) do
		local added = Chaos.giveItem(player, it.id, it.count)
		local rest = it.count - added
		if rest > 0 then
			local inbox = player:getInbox()
			if inbox then
				inbox:addItem(it.id, rest, INDEX_WHEREEVER or -1, FLAG_NOLIMIT)
			end
		end
		parts[#parts + 1] = it.count .. "x " .. itemName(it.id)
	end
	return table.concat(parts, ", "), first
end

local RESULT = {[1] = "win", [0.5] = "draw", [0] = "loss"}

local function names(list, except)
	local out = {}
	for _, e in ipairs(list) do
		if e ~= except then
			out[#out + 1] = e.name
		end
	end
	return table.concat(out, ", ")
end

-- winner: 1 / 2 / 0 (draw). reason: "defeat", "timeout", "stop"
finish = function(m, winner, reason)
	if m.phase == "done" then
		return
	end
	local cfg = C()
	m.phase = "done"
	m.winner = winner
	local now = os.time()
	local list = sides(m)
	local rated = reason ~= "stop"
	if rated then
		A.rateMatch(cfg, list, winner)
	end
	-- history
	local matchId = 0
	if rated then
		db.query(string.format("INSERT INTO `%s` (`mode`, `slot`, `winner`, `reason`, `started_at`, `ended_at`) VALUES (%s, %d, %d, %s, %d, %d)",
			T("matches"), db.escapeString(m.mode), m.slot, winner, db.escapeString(reason), m.startedAt, now))
		matchId = db.lastInsertId and db.lastInsertId() or 0
	end
	local board = cfg.modes[m.mode].board
	for side = 1, 2 do
		for _, e in ipairs(list[side]) do
			local result = rated and RESULT[e.score] or "draw"
			e.result = result
			if rated then
				local r = S.ratingOf(e.guid, m.mode)
				r.rating = e.after
				r.matches = r.matches + 1
				if result == "win" then
					r.wins = r.wins + 1
				elseif result == "loss" then
					r.losses = r.losses + 1
				else
					r.draws = r.draws + 1
				end
				r.best = math.max(r.best or r.rating, r.rating)
				saveRating(e.guid, m.mode, r)
				db.query(string.format("INSERT INTO `%s` (`match_id`, `player_id`, `mode`, `team`, `result`, `rating_before`, " ..
					"`rating_after`, `opponents`, `partner`, `reason`, `ended_at`) VALUES (%d, %d, %s, %d, %s, %d, %d, %s, %s, %s, %d)",
					T("players"), matchId, e.guid, db.escapeString(m.mode), side, db.escapeString(result), e.before, e.after,
					db.escapeString(names(list[3 - side]):sub(1, 100)), db.escapeString(names(list[side], e):sub(1, 64)),
					db.escapeString(e.reason or reason), now))
				if ChaosLeaderboard and ChaosLeaderboard.record then
					local ok, err = pcall(ChaosLeaderboard.record, board, {guid = e.guid, name = e.name}, r.rating, "max")
					if not ok then
						log("leaderboard: " .. tostring(err))
					end
				end
			end
		end
	end
	-- PvP seasons (arena_season.lua): the season rating of the mode's bracket
	if rated and ChaosPvpSeason and ChaosPvpSeason.recordArena then
		local ok, res = pcall(ChaosPvpSeason.recordArena, m.mode, list, winner)
		if ok and res then
			for side = 1, 2 do
				for _, e in ipairs(list[side]) do
					e.season = res[e.guid]
				end
			end
		elseif not ok then
			log("season: " .. tostring(res))
		end
	end
	-- tell everyone, rewards
	local title = winner == 0 and "Draw" or nil
	eachOnline(m, function(p, e)
		local text, reward, first = "", nil, false
		if rated and e.result == "win" then
			reward, first = giveReward(p)
		end
		local how = reason == "timeout" and " (time ran out: remaining health decided)" or (reason == "stop" and " (stopped by the staff, not rated)" or "")
		if rated then
			text = string.format("Arena %s: %s%s. Rating %d -> %d (%s%d).%s", m.mode, e.result == "win" and "victory" or
				(e.result == "loss" and "defeat" or "draw"), how, e.before, e.after, e.delta >= 0 and "+" or "", e.delta,
				(reward and reward ~= "") and (" Reward: " .. reward .. (first and " (first win of the day)" or "") .. ".") or "")
		else
			text = "Arena: the match was stopped by the staff and is not rated."
		end
		msg(p, text)
		Chaos.send(p, OPCODE, "end", {mode = m.mode, result = e.result, before = e.before or e.rating, after = e.after or e.rating,
			delta = e.delta or 0, reason = reason, reward = reward, firstWin = first, rated = rated,
			opponents = names(list[3 - e.team]), title = title, season = e.season})
	end)
	log(string.format("match %d ended: winner %d (%s)", m.id, winner, reason))
	hud(m)
	addEvent(function(slot, id)
		local mm = S.matches[slot]
		if not mm or mm.id ~= id then
			return
		end
		eachOnline(mm, function(p, e)
			if S.matchOf[p:getId()] == mm then
				release(p, e)
				stateLater(p:getId())
			end
		end)
		for cid in pairs(mm.players) do
			if S.matchOf[cid] == mm then
				S.matchOf[cid] = nil
			end
		end
		cleanSlot(slot)
		S.matches[slot] = nil
	end, cfg.endDelaySeconds * 1000, m.slot, m.id)
end

-- a fighter logged out or lost the connection: out of the fight (a loss), sent back at once
local function leave(m, e, p, reason)
	S.defeat(m, e, reason or "left")
	e.left = true
	if p then
		release(p, e)
	end
	e.gone = true
end

-- ======================================================================== the tick
local function tickMatch(m)
	if m.phase == "done" then
		return
	end
	local cfg = C()
	local now = os.time()
	local L = A.layout(cfg, m.slot)
	for _, cid in ipairs(m.order) do
		local e = m.players[cid]
		if not e.gone then
			local p = Player(cid)
			if not p then
				leave(m, e, nil, "left")
			elseif not A.inSlot(L, p:getPosition()) then
				leave(m, e, p, "left") -- teleported out somehow (scroll, staff)
			elseif p:getIp() == 0 then
				e.offSince = e.offSince or now
				if now - e.offSince >= cfg.disconnectSeconds then
					leave(m, e, p, "left")
				end
			else
				e.offSince = nil
				if not e.defeated then
					if Chaos.isMultiClient and Chaos.isMultiClient(p) then
						S.defeat(m, e, "mc")
						e.left = true
					elseif m.phase == "fight" and now >= m.fightAt + cfg.secureGraceSeconds and p:hasSecureMode() then
						S.defeat(m, e, "secure")
					end
				end
			end
		end
	end
	if m.phase == "countdown" and now >= m.fightAt then
		m.phase = "fight"
		eachOnline(m, function(p)
			p:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Arena: FIGHT!")
			p:getPosition():sendMagicEffect(CONST_ME_FIREAREA)
		end)
	end
	local list = sides(m)
	local winner = A.decided(list)
	if winner then
		finish(m, winner, "defeat")
		return
	end
	if m.phase == "fight" and now >= m.endAt then
		finish(m, (A.timeoutWinner(list)), "timeout")
		return
	end
	hud(m)
end

local function matchmake()
	local now = os.time()
	local cfg = C()
	local entries = {}
	for _, e in ipairs(S.queue) do
		e.levels, e.parties, e.ips = {}, {}, {}
		local ok = true
		for _, cid in ipairs(e.members) do
			local p = Player(cid)
			if not p then
				ok = false
				break
			end
			e.levels[#e.levels + 1] = p:getLevel()
			local party = p:getParty()
			if party and cfg.modes[e.mode].size == 1 then
				e.parties[party:getLeader():getId()] = true
			end
			local ip = p:getIp()
			if ip ~= 0 and p:getGroup():getId() < Chaos.multiClient.exemptGroup and Game.getStorageValue(Chaos.multiClient.offStorage) ~= 1 then
				e.ips[ip] = true
			end
		end
		if ok then
			entries[#entries + 1] = e
		end
	end
	for _, pair in ipairs(A.findMatches(cfg, entries, now)) do
		if not startMatch(pair[1], pair[2]) and not freeSlot() then
			break
		end
	end
end

function S.tick()
	for _, m in pairs(S.matches) do
		local ok, err = pcall(tickMatch, m)
		if not ok then
			log("tick error: " .. tostring(err))
		end
	end
	local now = os.time()
	if now - S.lastMatchmake >= C().matchmakeSeconds and #S.queue >= 2 then
		S.lastMatchmake = now
		local ok, err = pcall(matchmake)
		if not ok then
			log("matchmaking error: " .. tostring(err))
		end
	end
end

function S.stopAll()
	local n = 0
	for _, m in pairs(S.matches) do
		if m.phase ~= "done" then
			finish(m, 0, "stop")
			n = n + 1
		end
	end
	return n
end

local tick = GlobalEvent("ChaosArenaTick")
function tick.onThink(interval)
	S.tick()
	return true
end
tick:interval(1000)
tick:register()

-- ======================================================================== combat hooks (fighters only)
local function verdict(creature, attacker)
	local m = S.matchOf[creature:getId()]
	if not m then
		return nil
	end
	local t = m.players[creature:getId()]
	local a = playerOf(attacker)
	local self = a and a:getId() == creature:getId()
	local ae = a and m.players[a:getId()] or nil
	if a and not ae and not self then
		return m, t, false -- a player from outside the match
	end
	return m, t, A.canHit(m.phase, ae, t, self)
end

local health = CreatureEvent("ChaosArenaHealth")
function health.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if primaryType == COMBAT_HEALING then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local m, t, allowed = verdict(creature, attacker)
	if not m then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	if not allowed then
		return 0, primaryType, 0, secondaryType
	end
	local sd = secondaryType == COMBAT_HEALING and 0 or math.abs(secondaryDamage)
	-- the energy shield (engine patch 0015) takes its part after this event: a hit is lethal past health + shield
	local p, s, caught = A.catchDamage(creature:getHealth() + (creature.getEnergyShield and creature:getEnergyShield() or 0), math.abs(primaryDamage), sd)
	if caught then
		local a = playerOf(attacker)
		S.defeat(m, t, "defeated", a and a:getId() ~= creature:getId() and a:getName() or nil)
	end
	return p, primaryType, secondaryType == COMBAT_HEALING and secondaryDamage or s, secondaryType
end
health:register()

local mana = CreatureEvent("ChaosArenaMana")
function mana.onManaChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	-- only mana taken by another player (mana shield hits, mana drain); potions and own spells pass
	local a = playerOf(attacker)
	if primaryType == COMBAT_HEALING or not a or a:getId() == creature:getId() then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local m, _, allowed = verdict(creature, attacker)
	if m and not allowed then
		return 0, primaryType, 0, secondaryType
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
mana:register()

-- the safety net: whatever got past the health event (another script raising the damage, ORIGIN_NONE hits)
local prepare = CreatureEvent("ChaosArenaPrepareDeath")
function prepare.onPrepareDeath(creature, killer)
	local m = S.matchOf[creature:getId()]
	if not m then
		return true
	end
	local t = m.players[creature:getId()]
	local a = playerOf(killer)
	S.defeat(m, t, "defeated", a and a:getId() ~= creature:getId() and a:getName() or nil)
	if creature:getHealth() < 1 then
		creature:setHealth(1)
	end
	return false -- the hit is cancelled: nobody dies in the arena
end
prepare:register()

-- no attacks before the fight, none on team mates or the defeated, none from or into a match from outside
local guard = EventCallback
guard.onTargetCombat = function(creature, target)
	if not creature or not target or not target:isPlayer() then
		return RETURNVALUE_NOERROR
	end
	local a = playerOf(creature)
	local tm = S.matchOf[target:getId()]
	local am = a and S.matchOf[a:getId()]
	if not tm and not am then
		return RETURNVALUE_NOERROR
	end
	if a and a:getId() == target:getId() then
		return RETURNVALUE_NOERROR
	end
	if tm ~= am then
		return RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER
	end
	local ae, te = tm.players[a:getId()], tm.players[target:getId()]
	if tm.phase == "countdown" then
		a:sendCancelMessage(string.format("The fight starts in %d seconds.", math.max(0, tm.fightAt - os.time())))
		return RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER
	end
	if not A.canHit(tm.phase, ae, te, false) then
		return RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER
	end
	return RETURNVALUE_NOERROR
end
guard:register()

-- ======================================================================== login / logout / opcode
local login = CreatureEvent("ChaosArenaLogin")
function login.onLogin(player)
	player:registerEvent("ChaosArenaLogout")
	player:registerEvent("ChaosArenaExtended")
	-- a crash or restart during a match: never log in inside an arena slot
	if A.slotOfPos(C(), player:getPosition()) then
		player:teleportTo(player:getTown():getTemplePosition())
	end
	S.loadRatings(player:getGuid(), true)
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosArenaLogout")
function logout.onLogout(player)
	local cid = player:getId()
	if S.queued[cid] then
		S.leaveQueue(player, true)
	end
	local m = S.matchOf[cid]
	if m and m.phase ~= "done" then
		-- kicked by a closing server (shutdown / server save): no loss for anyone, every match stops unrated
		local state = Game.getGameState and Game.getGameState()
		if state ~= nil and (state == GAME_STATE_SHUTDOWN or state == GAME_STATE_CLOSED) then
			S.stopAll()
		end
	end
	if m then
		local e = m.players[cid]
		if m.phase == "done" then
			release(player, e)
			e.gone = true
		else
			leave(m, e, player, "left")
			log(string.format("%s logged out during match %d (a loss)", player:getName(), m.id))
		end
	end
	return true
end
logout:type("logout")
logout:register()

-- a clean shutdown: the matches stop unrated before the players are kicked (the logout above then sends them out)
local shutdown = GlobalEvent("ChaosArenaShutdown")
function shutdown.onShutdown()
	S.stopAll()
	return true
end
shutdown:register()

local ext = CreatureEvent("ChaosArenaExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local m = Chaos.decode(buffer)
	if not m then
		return
	end
	local data = type(m.data) == "table" and m.data or {}
	if m.action == "open" then
		S.sendState(player, true)
	elseif m.action == "queue" then
		local mode = A.parseMode(C(), data.mode)
		if mode then
			S.join(player, mode)
		end
		S.sendState(player, false)
	elseif m.action == "leave" then
		S.leaveQueue(player)
		S.sendState(player, false)
	end
end
ext:type("extendedopcode")
ext:register()

-- ======================================================================== commands
local function statusText(player)
	local r = S.loadRatings(player:getGuid())
	local parts = {}
	for _, mode in ipairs(C().modeOrder) do
		local e = r[mode]
		parts[#parts + 1] = string.format("%s %d (%d-%d-%d)", mode, e.rating, e.wins, e.losses, e.draws)
	end
	local text = "Arena ratings: " .. table.concat(parts, ", ") .. "."
	local q = S.queued[player:getId()]
	if q then
		local waited = os.time() - q.joined
		text = text .. string.format(" In the %s queue for %ds (rating window +/-%d).", q.mode, waited, A.window(C(), waited))
	elseif S.matchOf[player:getId()] then
		text = text .. " You are in a match."
	else
		text = text .. " Queue for 1v1, 2v2 (party of two) or 3v3 (party of three) in the Arena window (Adventure > Arena)."
	end
	return text
end

local function onArena(player, words, param)
	local cmd, arg = tostring(param or ""):match("^%s*(%S*)%s*(.-)%s*$")
	cmd = (cmd or ""):lower()
	if cmd == "queue" or cmd == "join" then
		local mode = A.parseMode(C(), arg)
		if not mode then
			player:sendCancelMessage("Choose 1v1, 2v2 or 3v3.")
			return false
		end
		S.join(player, mode)
	elseif cmd == "leave" then
		local m = S.matchOf[player:getId()]
		if m and m.phase ~= "done" then
			local e = m.players[player:getId()]
			leave(m, e, player, "left")
			msg(player, "Arena: you left the match (a loss).")
		else
			S.leaveQueue(player)
		end
	else
		player:sendTextMessage(MESSAGE_INFO_DESCR, statusText(player))
		S.sendState(player, true)
	end
	return false
end

for _, words in ipairs({"/arena"}) do -- staff only (players open the window from the menu)
	local talk = TalkAction(words)
	talk.onSay = function(player, w, param)
		if not player:getGroup():getAccess() then
			return false
		end
		-- staff: /arena stop | slots
		if w == "/arena" then
			local cmd = tostring(param or ""):match("^%s*(%S*)")
			if cmd == "stop" then
				player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("Arena: %d match(es) stopped (not rated).", S.stopAll()))
				return false
			elseif cmd == "slots" then
				local busy = 0
				for _ in pairs(S.matches) do
					busy = busy + 1
				end
				local bad = {}
				for slot, why in pairs(S.bad) do
					bad[#bad + 1] = slot .. ": " .. why
				end
				player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("Arena: %d match(es) running, %d in queue, bad slots: %s",
					busy, #S.queue, #bad > 0 and table.concat(bad, "; ") or "none"))
				return false
			end
		end
		return onArena(player, w, param)
	end
	talk:separator(" ")
	talk:register()
end
