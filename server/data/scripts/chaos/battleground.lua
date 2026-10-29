-- PvP battleground "Ember Wells" (client game_battleground, extended opcode 200): 5v5 to 10v10, capture and hold three
-- braziers, the first team to 1000 points wins. Settings: battleground_config.lua. Pure part (matchmaking with role
-- and rating balance, capture, score, waves, AFK, honor, deserter, the map): battleground_core.lua, tested by
-- tests/battleground_test.lua and tests/battleground_flow_test.lua (this file on a mocked engine). Season ratings:
-- arena_season.lua (bracket "bg"). Overview and numbers: server/README.md "Battleground and PvP seasons".
--
-- Flow
--   the window (Adventure > Battleground): Queue (solo, or the party leader queues the party of up to 5) as a role
--   of the class (tank / healer / DPS, party_finder_config.lua classRoles); level 100+, in a protection zone, out of
--   combat, not multi-clienting, not inside another instance or the arena (queue or match), no deserter penalty.
--   -> every matchmakeSeconds the queue forms matches per realm (standard / the running season) and level bracket:
--      5v5 .. 10v10, parties kept whole, tanks and healers spread, team ratings close (battleground_core.lua)
--   -> a free slot of the grid is built at runtime (Game.createTile, footprint checked first), everyone checked again
--      and teleported into the team's base; prepSeconds to get ready (no damage, gates held), then the fight
--   -> braziers: stand in the circle to move it to your side; held braziers score every 2 s; a downed enemy scores 5
--   -> a killing blow leaves 1 health: the player is downed, waits in the team's graveyard and comes back with the next
--      respawn wave; nobody dies, so no item or experience loss, no skull or frag after the match
--   -> 1000 points or the timer: season rating (bracket "bg"), honor, the weekly first win, the summary; after
--      endDelaySeconds everyone goes back to where they stood, healed
--   leaving early (leave, logout, lost connection, AFK) = a deserter: a loss, no rewards, no queue for a while.
-- Damage and healing between players are scaled to the bracket's reference level (normalise in the config).

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
Chaos.battlegroundConfig = dofile("data/scripts/chaos/battleground_config.lua")
if not ChaosArenaLook then
	dofile("data/scripts/chaos/arenalook_core.lua")
end
if not (ChaosBattlegroundCore and ChaosBattlegroundCore.findMatches) then
	dofile("data/scripts/chaos/battleground_core.lua")
end

ChaosBattleground = ChaosBattleground or {}
local B = ChaosBattleground
local K = ChaosBattlegroundCore
local OPCODE = (ChaosOpcodes and ChaosOpcodes.battleground) or 200

local function C()
	return Chaos.battlegroundConfig
end

local function T(k)
	return C().tables[k]
end

B.queue = B.queue or {} -- list of queue entries
B.queued = B.queued or {} -- creature id -> entry
B.matches = B.matches or {} -- slot -> match
B.matchOf = B.matchOf or {} -- creature id -> match
B.built = B.built or {} -- slot -> true
B.bad = B.bad or {} -- slot -> reason
B.players = B.players or {} -- guid -> player row (honor, record, deserter)
B.pref = B.pref or {} -- guid -> preferred role
B.samples = B.samples or {} -- group -> recent waits
B.seq = B.seq or 0
B.lastMatchmake = B.lastMatchmake or 0
B.minOverride = B.minOverride or nil -- staff test: smaller teamMin (memory only)

local function P(t)
	return Position(t.x, t.y, t.z)
end

local function log(text)
	print("[Chaos battleground] " .. text)
end

-- text: a key (Chaos.t) or a deferred text (ChaosI18n.msg): in the player's language
local function msg(player, text)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, text))
end

local function send(player, action, data)
	-- the viewer's display scale (display_scale_core.lua): the scoreboard's damage and healing (a copy: one board
	-- table goes to every player of the match)
	if ChaosDisplayScale and ChaosDisplayScale.apply then
		data = ChaosDisplayScale.apply("battleground", player, data)
	end
	return Chaos.sendChunked(player, OPCODE, json.encode({action = action, data = data or {}}))
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

local function effect(name)
	return _G[name] or CONST_ME_TELEPORT
end

-- the config with the staff test override of teamMin
local function MC()
	local cfg = C()
	if not B.minOverride then
		return cfg
	end
	local copy = {}
	for k, v in pairs(cfg) do
		copy[k] = v
	end
	copy.teamMin = B.minOverride
	copy.fillSeconds = math.min(cfg.fillSeconds, 5)
	return copy
end

-- ======================================================================== the player rows (DB)
local SQL = {
	"CREATE TABLE IF NOT EXISTS `%s` (`player_id` int(11) NOT NULL, `honor` int(10) unsigned NOT NULL DEFAULT 0, " ..
		"`honor_total` int(10) unsigned NOT NULL DEFAULT 0, `matches` int(10) unsigned NOT NULL DEFAULT 0, " ..
		"`wins` int(10) unsigned NOT NULL DEFAULT 0, `losses` int(10) unsigned NOT NULL DEFAULT 0, `draws` int(10) unsigned NOT NULL DEFAULT 0, " ..
		"`kills` int(10) unsigned NOT NULL DEFAULT 0, `downs` int(10) unsigned NOT NULL DEFAULT 0, `captures` int(10) unsigned NOT NULL DEFAULT 0, " ..
		"`week` int(10) unsigned NOT NULL DEFAULT 0, `week_honor` int(10) unsigned NOT NULL DEFAULT 0, `week_win` tinyint(1) unsigned NOT NULL DEFAULT 0, " ..
		"`deserter_until` int(10) unsigned NOT NULL DEFAULT 0, `deserter_log` varchar(255) NOT NULL DEFAULT '', " ..
		"`updated_at` int(10) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`player_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8",
	"CREATE TABLE IF NOT EXISTS `%s` (`id` int(11) NOT NULL AUTO_INCREMENT, `realm` int(11) NOT NULL DEFAULT 0, " ..
		"`bracket` varchar(8) NOT NULL DEFAULT '', `size` tinyint(3) unsigned NOT NULL DEFAULT 0, `slot` tinyint(3) unsigned NOT NULL DEFAULT 0, " ..
		"`winner` tinyint(3) unsigned NOT NULL DEFAULT 0, `score1` int(10) unsigned NOT NULL DEFAULT 0, `score2` int(10) unsigned NOT NULL DEFAULT 0, " ..
		"`reason` varchar(16) NOT NULL DEFAULT '', `started_at` int(10) unsigned NOT NULL DEFAULT 0, `ended_at` int(10) unsigned NOT NULL DEFAULT 0, " ..
		"PRIMARY KEY (`id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8",
	"CREATE TABLE IF NOT EXISTS `%s` (`id` int(11) NOT NULL AUTO_INCREMENT, `player_id` int(11) NOT NULL, `offer` varchar(16) NOT NULL, " ..
		"`cost` int(10) unsigned NOT NULL, `at` int(10) unsigned NOT NULL, PRIMARY KEY (`id`), KEY `chaos_pvp_purchases_player` (`player_id`)) " ..
		"ENGINE=InnoDB DEFAULT CHARSET=utf8"
}

function B.ensureTables()
	db.query(string.format(SQL[1], T("players")))
	db.query(string.format(SQL[2], T("matches")))
	db.query(string.format(SQL[3], T("purchases")))
end

local function emptyRow()
	return {honor = 0, honorTotal = 0, matches = 0, wins = 0, losses = 0, draws = 0, kills = 0, downs = 0, captures = 0,
		week = 0, weekHonor = 0, weekWin = 0, deserterUntil = 0, deserterLog = {}}
end

local function parseLog(s)
	local out = {}
	for t in tostring(s or ""):gmatch("%d+") do
		out[#out + 1] = tonumber(t)
	end
	return out
end

function B.rowOf(guid, force)
	if B.players[guid] and not force then
		return B.players[guid]
	end
	local row = emptyRow()
	local rows = Chaos.select(string.format("SELECT `honor`, `honor_total`, `matches`, `wins`, `losses`, `draws`, `kills`, `downs`, " ..
		"`captures`, `week`, `week_honor`, `week_win`, `deserter_until`, `deserter_log` FROM `%s` WHERE `player_id` = %d", T("players"), guid),
		{{"honor", "n"}, {"honor_total", "n"}, {"matches", "n"}, {"wins", "n"}, {"losses", "n"}, {"draws", "n"}, {"kills", "n"},
			{"downs", "n"}, {"captures", "n"}, {"week", "n"}, {"week_honor", "n"}, {"week_win", "n"}, {"deserter_until", "n"},
			{"deserter_log", "s"}})
	local r = rows[1]
	if r then
		row = {honor = r.honor, honorTotal = r.honor_total, matches = r.matches, wins = r.wins, losses = r.losses, draws = r.draws,
			kills = r.kills, downs = r.downs, captures = r.captures, week = r.week, weekHonor = r.week_honor, weekWin = r.week_win,
			deserterUntil = r.deserter_until, deserterLog = parseLog(r.deserter_log)}
	end
	B.players[guid] = row
	return row
end

local function weekKey(now)
	return K.weekKey(now or os.time(), 6)
end

-- the weekly counters of a row for this week
local function weekly(row)
	local wk = weekKey()
	if row.week ~= wk then
		row.week, row.weekHonor, row.weekWin = wk, 0, 0
	end
	return row
end

function B.saveRow(guid)
	local r = B.players[guid]
	if not r then
		return
	end
	db.query(string.format("INSERT INTO `%s` (`player_id`, `honor`, `honor_total`, `matches`, `wins`, `losses`, `draws`, `kills`, " ..
		"`downs`, `captures`, `week`, `week_honor`, `week_win`, `deserter_until`, `deserter_log`, `updated_at`) VALUES " ..
		"(%d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %s, %d) ON DUPLICATE KEY UPDATE `honor` = VALUES(`honor`), " ..
		"`honor_total` = VALUES(`honor_total`), `matches` = VALUES(`matches`), `wins` = VALUES(`wins`), `losses` = VALUES(`losses`), " ..
		"`draws` = VALUES(`draws`), `kills` = VALUES(`kills`), `downs` = VALUES(`downs`), `captures` = VALUES(`captures`), " ..
		"`week` = VALUES(`week`), `week_honor` = VALUES(`week_honor`), `week_win` = VALUES(`week_win`), " ..
		"`deserter_until` = VALUES(`deserter_until`), `deserter_log` = VALUES(`deserter_log`), `updated_at` = VALUES(`updated_at`)",
		T("players"), guid, r.honor, r.honorTotal, r.matches, r.wins, r.losses, r.draws, r.kills, r.downs, r.captures, r.week,
		r.weekHonor, r.weekWin, r.deserterUntil, db.escapeString(table.concat(r.deserterLog, ",")), os.time()))
end

-- honor from outside a match (the season end): to the balance, capped at honor.max
function B.addHonor(guid, amount, countWeek)
	local r = B.rowOf(guid, true)
	r.honor = math.min(C().honor.max, r.honor + amount)
	r.honorTotal = r.honorTotal + amount
	if countWeek then
		weekly(r).weekHonor = r.weekHonor + amount
	end
	B.saveRow(guid)
	return r.honor
end

-- ======================================================================== where a player is
local function realmOf(player)
	local S = ChaosSeason
	if not S or not S.current or not S.realmOf then
		return 0
	end
	local ok, realm = pcall(function()
		return S.current() and S.realmOf(player) or 0
	end)
	return ok and tonumber(realm) or 0
end

local function inProtectionZone(player)
	if Game.getStorageValue(C().storage.testNoPz) == 1 then
		return true -- TEST ONLY (battleground_config.lua storage.testNoPz)
	end
	local tile = Tile(player:getPosition())
	return tile ~= nil and tile:hasFlag(TILESTATE_PROTECTIONZONE)
end

local function inCombat(player)
	return player:isPzLocked() or player:hasCondition(CONDITION_INFIGHT)
end

local function insideOther(player)
	local checks = {
		{ChaosDungeonIsInside, "a dungeon", true},
		{ChaosTowerRun, "the Infinity Tower"}, {ChaosRift, "a rift"}, {ChaosSiege, "a siege"},
		{ChaosDescent, "the Ember Descent"}, {ChaosRaid, "a raid"}, {ChaosAscended, "an Ascended Omen"}
	}
	for _, c in ipairs(checks) do
		local mod, what, plain = c[1], c[2], c[3]
		if plain and mod and mod(player) then
			return what
		elseif not plain and mod and mod.isInside and mod.isInside(player) then
			return what
		end
	end
	if ChaosWorldBoss and ChaosWorldBoss.inside and ChaosWorldBoss.layout and ChaosWorldBoss.inside(player:getPosition()) then
		return "the world boss arena"
	end
	local A = ChaosArena
	if A and ((A.isInside and A.isInside(player)) or (A.isQueued and A.isQueued(player))) then
		return "the arena (queue or match)"
	end
	return nil
end

function B.isInside(player)
	return B.matchOf[player:getId()] ~= nil
end

function B.isQueued(player)
	return B.queued[player:getId()] ~= nil
end

Chaos.registerInstance("battleground", {label = "a battleground", inside = B.isInside, at = function(pos)
	return K.slotOfPos(C(), pos) ~= nil
end, runs = function() -- /instances (instance_limits.lua)
	local out, now = {}, os.time()
	for slot, m in pairs(B.matches) do
		local n = 0
		for cid, e in pairs(m.players) do
			if not e.gone and Player(cid) then
				n = n + 1
			end
		end
		out[#out + 1] = {id = m.id, what = string.format("%dv%d, slot %d, %s", m.size or 0, m.size or 0, slot, m.phase),
			left = m.phase ~= "done" and math.max(0, m.endAt - now) or nil, players = n}
	end
	return out
end, close = function(id) -- stopped, not rated (as /bg stop)
	for _, m in pairs(B.matches) do
		if m.id == id and m.phase ~= "done" and B._finish then
			B._finish(m, 0, "stop")
			return true, "Battleground match " .. id .. " stopped (not rated)."
		end
	end
	return false, "No running battleground match " .. tostring(id) .. "."
end})

-- queued or in a match (the arena refuses those)
function B.isBusy(player)
	return B.isInside(player) or B.isQueued(player)
end

local function deserterLeft(guid, now)
	local r = B.rowOf(guid)
	return math.max(0, (r.deserterUntil or 0) - (now or os.time()))
end

-- nil when the player may queue / start, else the reason
local function refusal(player, ignoreQueue)
	local cfg = C()
	if not cfg.enabled then
		return "The battleground is closed."
	end
	if player:getLevel() < cfg.minLevel then
		return string.format("You need level %d for the battleground.", cfg.minLevel)
	end
	if B.matchOf[player:getId()] then
		return "You are already in a battleground match."
	end
	if not ignoreQueue and B.queued[player:getId()] then
		return "You are already in the battleground queue."
	end
	local left = deserterLeft(player:getGuid())
	if left > 0 then
		return string.format("Deserter: you left a battleground early and cannot queue for %d more minute(s).", math.ceil(left / 60))
	end
	if Chaos.isMultiClient and Chaos.isMultiClient(player) then
		return "You cannot join the battleground while another character from your connection is online."
	end
	local where = insideOther(player)
	if where then
		return "You cannot queue for the battleground while in " .. where .. "." -- a sentence per place in i18n_strings.lua
	end
	if inCombat(player) then
		return "You cannot queue for the battleground while in combat."
	end
	if not inProtectionZone(player) then
		return "You can only queue for the battleground in a protection zone."
	end
	return nil
end

-- ======================================================================== the queue
-- the roles of the classes: party_finder_config.lua (loaded here when the Party Finder is not, or not yet)
local function pfConfig()
	if not Chaos.partyFinderConfig then
		local ok, cfg = pcall(dofile, "data/scripts/chaos/party_finder_config.lua")
		Chaos.partyFinderConfig = ok and cfg or nil
	end
	return Chaos.partyFinderConfig
end

local function vocId(player)
	local v = player:getVocation()
	return v and v:getId() or 0
end

local function groupKey(realm, bracket)
	return tostring(realm) .. ":" .. bracket.key
end

local function seasonRating(guid)
	if ChaosPvpSeason and ChaosPvpSeason.ratingFor then
		local ok, r = pcall(ChaosPvpSeason.ratingFor, guid, "bg")
		if ok and r then
			return r
		end
	end
	return C().season.start
end

local function removeEntry(entry)
	for i, e in ipairs(B.queue) do
		if e == entry then
			table.remove(B.queue, i)
			break
		end
	end
	for _, m in ipairs(entry.members) do
		if B.queued[m.cid] == entry then
			B.queued[m.cid] = nil
		end
	end
end

local function queueSize(group)
	local n = 0
	for _, e in ipairs(B.queue) do
		if e.group == group then
			n = n + #e.members
		end
	end
	return n
end

local function stateLater(cid)
	addEvent(function(id)
		local p = Player(id)
		if p then
			B.sendState(p, false)
		end
	end, 100, cid)
end

-- the members a queue join takes: the player alone, or the whole party (the leader only), nil + reason
local function membersOf(player)
	local party = player:getParty()
	if not party then
		return {player}
	end
	if party:getLeader() ~= player then
		return nil, "Only the party leader can queue the party for the battleground."
	end
	local list = {player}
	for _, m in ipairs(party:getMembers() or {}) do
		list[#list + 1] = m
	end
	if #list > C().partyMax then
		return nil, string.format("A party of at most %d players can queue together.", C().partyMax)
	end
	return list
end

function B.join(player, role)
	local cfg = C()
	local members, err = membersOf(player)
	if not members then
		player:sendCancelMessage(Chaos.tx(player, err))
		return false
	end
	local bracket = K.bracketOf(cfg, player:getLevel())
	local realm = realmOf(player)
	for _, m in ipairs(members) do
		local why = refusal(m)
		if not why then
			local b = K.bracketOf(cfg, m:getLevel())
			if not b or not bracket or b.key ~= bracket.key then
				why = b and string.format("is in another level bracket (%s).", b.name) or "is in another level bracket (below the minimum)."
			elseif realmOf(m) ~= realm then
				why = "plays in another realm."
			end
		end
		if why then
			why = Chaos.tx(player, why)
			if m ~= player then
				why = m:getName() .. ": " .. why
			end
			player:sendCancelMessage(why)
			msg(player, ChaosI18n.msg("Battleground: %s", why))
			return false
		end
	end
	if ChaosRateLimit and not ChaosRateLimit.allow(player, "bg.join", 1500) then
		return false
	end
	local now = os.time()
	B.seq = B.seq + 1
	local entry = {id = B.seq, joined = now, bracket = bracket.key, realm = realm, group = groupKey(realm, bracket),
		members = {}, leader = player:getId()}
	local sum = 0
	for _, m in ipairs(members) do
		local guid = m:getGuid()
		local wanted = (m == player and role) or B.pref[guid]
		local r = seasonRating(guid)
		entry.members[#entry.members + 1] = {cid = m:getId(), guid = guid, name = m:getName(), level = m:getLevel(),
			voc = vocId(m), role = K.pickRole(pfConfig(), vocId(m), wanted), rating = r}
		sum = sum + r
	end
	entry.rating = sum / #members
	B.queue[#B.queue + 1] = entry
	for _, m in ipairs(entry.members) do
		B.queued[m.cid] = entry
		local p = Player(m.cid)
		if p then
			msg(p, ChaosI18n.msg("Battleground: you joined the queue as %s (%s). Stay in a protection zone.", m.role, bracket.name))
			stateLater(m.cid)
		end
	end
	return true
end

function B.leaveQueue(player, silent)
	local e = B.queued[player:getId()]
	if not e then
		if not silent then
			player:sendCancelMessage(Chaos.t(player, "You are not in the battleground queue."))
		end
		return false
	end
	removeEntry(e)
	for _, m in ipairs(e.members) do
		local p = Player(m.cid)
		if p then
			msg(p, p == player and "Battleground: you left the queue." or
				ChaosI18n.msg("Battleground: %s left the queue, so did your party.", player:getName()))
			stateLater(m.cid)
		end
	end
	return true
end

-- ======================================================================== the map
local function placeItem(pos, id)
	local tile = Tile(pos)
	if tile and not tile:getItemById(id) then
		return Game.createItem(id, 1, pos)
	end
end

function B.buildSlot(slot)
	if B.built[slot] then
		return true
	end
	local cfg = C()
	local L = K.layout(cfg, slot)
	local foot = K.footprint(cfg, L)
	for _, t in ipairs(foot) do
		if Tile(P(t)) then
			return false, string.format("tile %d,%d,%d already exists in the map", t.x, t.y, t.z)
		end
	end
	local ids = cfg.ids
	local grounds = {base = ids.baseGround, ring = ids.ringGround}
	for _, t in ipairs(foot) do
		local pos = P(t)
		local tile = Game.createTile(pos, true)
		if tile then
			-- the field gets its ground from the look (below); bases, graveyards, capture circles and walls keep theirs
			if not tile:getGround() and (grounds[t.ground] or t.wall) then
				Game.createItem(grounds[t.ground] or ids.ground, 1, pos)
			end
			if t.wall and not tile:getItemById(ids.wall) then
				Game.createItem(ids.wall, 1, pos)
			end
		end
	end
	-- O276: the look of the field (arenalook_core.lua), mirrored for the two teams; a theme per slot in turn
	local lk = cfg.look or {}
	local themes = lk.themes or {"ember"}
	local spec = K.lookSpec(cfg, L)
	ChaosArenaLook.dressTiles("battleground" .. slot, spec.tiles, L.z, themes[slot % #themes + 1], {keep = spec.keep,
		roads = spec.roads, plain = spec.plain, seed = lk.seed or 1, cover = lk.cover, lights = lk.lights, keepGap = lk.keepGap,
		mirror = true, groundIds = {[ids.ground] = true}, fallbackGround = ids.ground})
	for _, p in ipairs(L.pillars) do
		placeItem(P(p), ids.pillar)
	end
	for _, p in ipairs(L.flags) do
		placeItem(P(p), ids.flag)
	end
	for _, b in ipairs(L.braziers) do
		placeItem(P(b), ids.brazier)
	end
	B.built[slot] = true
	return true
end

local function cleanSlot(slot)
	local cfg = C()
	local ids = cfg.ids
	local keep = {[ids.wall] = true, [ids.pillar] = true, [ids.brazier] = true, [ids.flag] = true}
	for _, t in ipairs(K.footprint(cfg, K.layout(cfg, slot))) do
		if not t.wall then
			local tile = Tile(P(t))
			if tile then
				for _, c in ipairs(tile:getCreatures() or {}) do
					if c:isMonster() then
						c:remove()
					end
				end
				for _, item in ipairs(tile:getItems() or {}) do
					if not keep[item:getId()] and not ChaosArenaLook.isOwned(item:getId()) then
						item:remove()
					end
				end
			end
		end
	end
end

local function freeSlot()
	local busy = {}
	for slot in pairs(B.matches) do
		busy[slot] = true
	end
	while true do
		local slot = K.allocSlot(C(), busy, B.bad)
		if not slot then
			return nil
		end
		local ok, err = B.buildSlot(slot)
		if ok then
			return slot
		end
		B.bad[slot] = err
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

local function heal(player)
	player:setHealth(player:getMaxHealth())
	Chaos.heal(player, player:getMaxHealth() - player:getHealth())
	player:addMana(player:getMaxMana() - player:getMana())
end

local EVENTS = {"ChaosBgHealth", "ChaosBgMana", "ChaosBgPrepareDeath"}

local function eachOnline(m, fn)
	for _, cid in ipairs(m.order) do
		local e = m.players[cid]
		local p = Player(cid)
		if p and not e.gone then
			fn(p, e)
		end
	end
end

local function teamCount(m, team)
	local n = 0
	for _, cid in ipairs(m.order) do
		local e = m.players[cid]
		if e.team == team and not e.gone then
			n = n + 1
		end
	end
	return n
end

-- back to where the player stood, healed, no fight lock / white skull, events off
local function release(player, e)
	B.matchOf[player:getId()] = nil
	player:setTarget(nil)
	for _, name in ipairs(EVENTS) do
		player:unregisterEvent(name)
	end
	cleanse(player)
	player:removeCondition(CONDITION_INFIGHT, CONDITIONID_DEFAULT)
	if player:getSkull() == SKULL_WHITE or player:getSkull() == SKULL_YELLOW then
		player:setSkull(SKULL_NONE)
	end
	heal(player)
	local dest = e and e.ret and P(e.ret) or player:getTown():getTemplePosition()
	player:teleportTo(dest)
	player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
	player:removeCondition(CONDITION_INFIGHT, CONDITIONID_DEFAULT)
	player:setStorageValue(C().storage.inside, 0)
end

local function spawnOf(m, e)
	local L = K.layout(C(), m.slot)
	local spots = L.spawns[e.team]
	return spots[((e.index or 1) - 1) % #spots + 1]
end

local function toSpawn(p, m, e)
	p:teleportTo(P(spawnOf(m, e)), true)
	p:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
end

local function scoreboardOf(m)
	local list = {}
	for _, cid in ipairs(m.order) do
		local e = m.players[cid]
		list[#list + 1] = {name = e.name, team = e.team, role = e.role, level = e.level, kills = e.kills, assists = e.assists,
			downs = e.downs, captures = e.captures, damage = math.floor(e.damage), healing = math.floor(e.healing),
			honor = e.honorGained, left = e.gone and e.left or nil, voc = e.vocName}
	end
	return K.scoreboard(list)
end

local function hudOf(m, e, now)
	local left = 0
	if m.phase == "prep" then
		left = m.fightAt - now
	elseif m.phase == "fight" then
		left = m.endAt - now
	end
	local braziers = {}
	for i, b in ipairs(m.braziers) do
		braziers[i] = {name = b.name, owner = b.owner, progress = math.floor(b.progress + 0.5), contested = b.contested or false}
	end
	local out = {phase = m.phase, left = math.max(0, left), score = {m.score[1], m.score[2]}, win = C().winScore,
		braziers = braziers, team = e.team, teams = {C().teams[1].name, C().teams[2].name},
		colors = {C().teams[1].color, C().teams[2].color}, players = {teamCount(m, 1), teamCount(m, 2)}}
	if e.down then
		out.respawn = math.max(0, m.nextWave - now)
	end
	if e.afkWarned then
		out.afk = math.max(0, C().afkKickSeconds - (now - e.lastActive))
	end
	return out
end

local function hud(m)
	local now = os.time()
	eachOnline(m, function(p, e)
		send(p, "hud", hudOf(m, e, now))
	end)
end

local function board(m, p)
	local data = {rows = scoreboardOf(m), teams = {C().teams[1].name, C().teams[2].name}, score = {m.score[1], m.score[2]}}
	if p then
		send(p, "board", data)
		return
	end
	eachOnline(m, function(q)
		send(q, "board", data)
	end)
end

-- key and its arguments: every fighter reads the line in their own language (an argument {"key"} is a short text of
-- its own, like a reason, translated for the reader too)
local unpack = unpack or table.unpack
local function announce(m, kind, key, ...)
	local args = {...}
	local n = select("#", ...)
	eachOnline(m, function(p)
		local shown = {}
		for i = 1, n do
			local a = args[i]
			shown[i] = type(a) == "table" and Chaos.t(p, a[1]) or a
		end
		local text = Chaos.t(p, key, unpack(shown, 1, n))
		p:sendTextMessage(MESSAGE_STATUS_WARNING, Chaos.t(p, "Battleground: %s", text))
		send(p, "alert", {text = text, kind = kind or "info"})
	end)
end

-- ======================================================================== down, leave, finish
local finish

-- a fighter is downed (a killing blow caught): to the graveyard until the next wave; the attacker and recent
-- attackers of the other team are credited
function B.down(m, e, by)
	if e.down or m.phase ~= "fight" then
		return
	end
	local now = os.time()
	e.down, e.downs, e.lastActive = true, e.downs + 1, now
	local killer = by and m.players[by:getId()]
	if killer and killer.team ~= e.team then
		killer.kills = killer.kills + 1
		m.score[killer.team] = m.score[killer.team] + C().killPoints
	elseif not killer then
		m.score[3 - e.team] = m.score[3 - e.team] + C().killPoints
	end
	for cid, at in pairs(e.hitBy or {}) do
		local a = m.players[cid]
		if a and a ~= killer and a.team ~= e.team and now - at <= 10 then
			a.assists = a.assists + 1
		end
	end
	e.hitBy = {}
	if killer then
		announce(m, "down", "%s was downed by %s.", e.name, killer.name)
	else
		announce(m, "down", "%s was downed.", e.name)
	end
	addEvent(function(id, matchId)
		local p = Player(id)
		local mm = p and B.matchOf[id]
		if not mm or mm.id ~= matchId or mm.phase ~= "fight" then
			return
		end
		local L = K.layout(C(), mm.slot)
		local spots = L.graveSpots[e.team]
		mm.graveUsed[e.team] = (mm.graveUsed[e.team] or 0) % #spots + 1
		p:getPosition():sendMagicEffect(CONST_ME_MORTAREA)
		p:setTarget(nil)
		p:teleportTo(P(spots[mm.graveUsed[e.team]]), true)
		if p:getHealth() < 1 then
			p:setHealth(1)
		end
	end, 50, e.cid, m.id)
end

-- a fighter leaves the match before its end: a deserter (no rewards, a loss, no queue for a while)
local function leave(m, e, p, reason)
	if e.gone then
		return
	end
	e.left, e.gone, e.reason = true, true, reason
	local now = os.time()
	e.leftAt = now
	if m.phase ~= "done" then
		local row = B.rowOf(e.guid)
		local minutes, hist = K.deserter(C(), row.deserterLog, now)
		row.deserterLog = hist
		row.deserterUntil = now + minutes * 60
		B.saveRow(e.guid)
		if p then
			msg(p, ChaosI18n.msg("Battleground: you left the match early (%s). Deserter: no queue for %d minute(s).",
				reason, minutes))
		end
		announce(m, "left", "%s left the battleground (%s).", e.name, {reason})
	end
	if p then
		release(p, e)
		stateLater(p:getId())
	end
	B.matchOf[e.cid] = nil
end

local RESULT = {[1] = "win", [0.5] = "draw", [0] = "loss"}

finish = function(m, winner, reason)
	if m.phase == "done" then
		return
	end
	local cfg = C()
	m.phase = "done"
	m.winner = winner
	if ChaosTileBars and ChaosTileBars.removePrefix then
		ChaosTileBars.removePrefix("bg:" .. m.id .. ":")
	end
	local now = os.time()
	local rated = reason ~= "stop"
	-- season rating (bracket "bg"); deserters were part of the match and score 0
	local season = {}
	if rated and ChaosPvpSeason and ChaosPvpSeason.record then
		local teams = {{}, {}}
		for _, cid in ipairs(m.order) do
			local e = m.players[cid]
			table.insert(teams[e.team], {guid = e.guid, name = e.name, left = e.left})
		end
		local ok, res = pcall(ChaosPvpSeason.record, "bg", teams, winner)
		if ok and res then
			season = res
		elseif not ok then
			log("season rating: " .. tostring(res))
		end
	end
	local duration = math.max(1, now - m.fightAt)
	for _, cid in ipairs(m.order) do
		local e = m.players[cid]
		local score = e.left and 0 or (winner == 0 and 0.5 or (winner == e.team and 1 or 0))
		e.result = RESULT[score]
		e.season = season[e.guid]
		if rated then
			local row = weekly(B.rowOf(e.guid))
			row.matches = row.matches + 1
			if e.result == "win" then
				row.wins = row.wins + 1
			elseif e.result == "loss" then
				row.losses = row.losses + 1
			else
				row.draws = row.draws + 1
			end
			row.kills, row.downs, row.captures = row.kills + e.kills, row.downs + e.downs, row.captures + e.captures
			local presence = math.min(1, (now - math.max(m.fightAt, e.joinedAt)) / duration)
			local honor, first = K.honorFor(cfg, {result = e.result, kills = e.kills + e.assists, captures = e.captures,
				deserter = e.left, presence = presence}, {earned = row.weekHonor, firstWinDone = row.weekWin == 1})
			e.honorGained, e.firstWin = honor, first
			row.honor = math.min(cfg.honor.max, row.honor + honor)
			row.honorTotal = row.honorTotal + honor
			row.weekHonor = row.weekHonor + honor - (first and cfg.honor.weeklyFirstWin or 0)
			if first then
				row.weekWin = 1
			end
			B.saveRow(e.guid)
			if e.result == "win" and not e.left and ChaosLeaderboard and ChaosLeaderboard.record then
				local ok, err = pcall(ChaosLeaderboard.record, cfg.leaderboard, {guid = e.guid, name = e.name}, 1, "add")
				if not ok then
					log("leaderboard: " .. tostring(err))
				end
			end
		end
	end
	if rated then
		db.query(string.format("INSERT INTO `%s` (`realm`, `bracket`, `size`, `slot`, `winner`, `score1`, `score2`, `reason`, `started_at`, " ..
			"`ended_at`) VALUES (%d, %s, %d, %d, %d, %d, %d, %s, %d, %d)", T("matches"), m.realm, db.escapeString(m.bracket), m.size,
			m.slot, winner, m.score[1], m.score[2], db.escapeString(reason), m.startedAt, now))
	end
	local rows = scoreboardOf(m)
	local teamNames = {cfg.teams[1].name, cfg.teams[2].name}
	eachOnline(m, function(p, e)
		local items = ""
		if rated and e.firstWin then
			local parts = {}
			for _, it in ipairs(cfg.firstWinItems) do
				local added = Chaos.giveItem(p, it.id, it.count)
				if added < it.count then
					local inbox = p:getInbox()
					if inbox then
						inbox:addItem(it.id, it.count - added, INDEX_WHEREEVER or -1, FLAG_NOLIMIT)
					end
				end
				local itype = ItemType(it.id)
				parts[#parts + 1] = it.count .. "x " .. (itype and itype:getName() or tostring(it.id))
			end
			items = table.concat(parts, ", ")
		end
		if rated and ChaosAchievements and ChaosAchievements.progress then
			pcall(ChaosAchievements.progress, p, "bg_matches", 1)
			if e.result == "win" then
				pcall(ChaosAchievements.progress, p, "bg_wins", 1)
			end
		end
		local s = e.season
		local text
		if rated then
			text = Chaos.t(p, "Battleground%s: %s (%d - %d). Honor +%d%s.%s", reason == "time" and Chaos.t(p, " (time)") or "",
				Chaos.t(p, e.result == "win" and "victory" or (e.result == "loss" and "defeat" or "draw")), m.score[e.team],
				m.score[3 - e.team], e.honorGained or 0, e.firstWin and Chaos.t(p, " (first win of the week)") or "",
				s and Chaos.t(p, " Rating %d -> %d (%s%d).", s.before, s.after, s.delta >= 0 and "+" or "", s.delta) or "")
		else
			text = "Battleground: the match was stopped by the staff and is not rated."
		end
		msg(p, text)
		send(p, "end", {result = e.result, reason = reason, rated = rated, team = e.team, teams = teamNames,
			score = {m.score[1], m.score[2]}, winner = winner, honor = e.honorGained or 0, firstWin = e.firstWin or false,
			items = items, season = s, rows = rows, duration = duration})
	end)
	log(string.format("match %d ended: winner %d (%s) %d - %d", m.id, winner, reason, m.score[1], m.score[2]))
	addEvent(function(slot, id)
		local mm = B.matches[slot]
		if not mm or mm.id ~= id then
			return
		end
		eachOnline(mm, function(p, e)
			if B.matchOf[p:getId()] == mm then
				release(p, e)
				stateLater(p:getId())
			end
		end)
		for cid in pairs(mm.players) do
			if B.matchOf[cid] == mm then
				B.matchOf[cid] = nil
			end
		end
		cleanSlot(slot)
		B.matches[slot] = nil
	end, cfg.endDelaySeconds * 1000, m.slot, m.id)
end
B._finish = finish

-- ======================================================================== match start
local function startMatch(found)
	local cfg = C()
	local all = {}
	for side = 1, 2 do
		for _, entry in ipairs(found.teams[side]) do
			all[#all + 1] = entry
		end
	end
	-- everyone again: a member that cannot go drops the entry (the others stay queued)
	for _, entry in ipairs(all) do
		for _, mem in ipairs(entry.members) do
			local p = Player(mem.cid)
			local why = "a player of the group logged out."
			if p then
				why = refusal(p, true)
			end
			local whyKey = why
			if why then
				removeEntry(entry)
				for _, other in ipairs(entry.members) do
					local o = Player(other.cid)
					if o then
						msg(o, ChaosI18n.msg("Battleground: a match was found but could not start, you were removed from the queue: %s",
							o == p and Chaos.tx(o, whyKey) or (mem.name .. ": " .. Chaos.tx(o, whyKey))))
						stateLater(other.cid)
					end
				end
				return false
			end
		end
	end
	local slot = freeSlot()
	if not slot then
		return false
	end
	local now = os.time()
	for _, entry in ipairs(all) do
		removeEntry(entry)
		B.samples[entry.group] = B.samples[entry.group] or {}
		K.addSample(cfg, B.samples[entry.group], now - entry.joined)
	end
	B.seq = B.seq + 1
	local bracket = K.bracketByKey(cfg, all[1].bracket)
	local L = K.layout(cfg, slot)
	local m = {id = B.seq, slot = slot, group = found.group, bracket = bracket.key, ref = bracket.ref, realm = all[1].realm,
		size = found.size, phase = "prep", startedAt = now, fightAt = now + cfg.prepSeconds,
		endAt = now + cfg.prepSeconds + cfg.matchSeconds, score = {0, 0}, players = {}, order = {}, graveUsed = {},
		braziers = {}, nextTick = now + cfg.prepSeconds + cfg.tickSeconds, nextWave = now + cfg.prepSeconds + cfg.waveSeconds,
		lastBoard = 0}
	for i, b in ipairs(L.braziers) do
		m.braziers[i] = {name = b.name, progress = 0, owner = 0}
	end
	local count = {0, 0}
	for side = 1, 2 do
		for _, entry in ipairs(found.teams[side]) do
			for _, mem in ipairs(entry.members) do
				local p = Player(mem.cid)
				count[side] = count[side] + 1
				local pos = p:getPosition()
				local voc = p:getVocation()
				local e = {cid = mem.cid, guid = mem.guid, name = mem.name, level = p:getLevel(), voc = mem.voc,
					vocName = voc and voc:getName() or "", role = mem.role, team = side, index = count[side],
					ret = {x = pos.x, y = pos.y, z = pos.z}, kills = 0, assists = 0, downs = 0, captures = 0, damage = 0,
					healing = 0, lastActive = now, lastPos = nil, joinedAt = now, hitBy = {}}
				m.players[e.cid] = e
				m.order[#m.order + 1] = e.cid
				B.matchOf[e.cid] = m
				p:setStorageValue(cfg.storage.inside, 1)
				p:setStorageValue(cfg.storage.retX, pos.x)
				p:setStorageValue(cfg.storage.retY, pos.y)
				p:setStorageValue(cfg.storage.retZ, pos.z)
				p:setTarget(nil)
				cleanse(p)
				heal(p)
				toSpawn(p, m, e)
				local np = p:getPosition()
				e.lastPos = {x = np.x, y = np.y}
				for _, name in ipairs(EVENTS) do
					p:registerEvent(name)
				end
			end
		end
	end
	B.matches[slot] = m
	eachOnline(m, function(p, e)
		msg(p, ChaosI18n.msg("Battleground: Ember Wells %dv%d. You fight for the %s. The wells open in %d seconds; secure mode must be off (the client turns it off for you).", m.size, m.size, cfg.teams[e.team].name, cfg.prepSeconds))
		send(p, "start", {team = e.team, size = m.size, prep = cfg.prepSeconds, match = cfg.matchSeconds,
			teams = {cfg.teams[1].name, cfg.teams[2].name}, colors = {cfg.teams[1].color, cfg.teams[2].color},
			braziers = {L.braziers[1].name, L.braziers[2].name, L.braziers[3].name}, win = cfg.winScore, bracket = bracket.name})
	end)
	log(string.format("match %d (%dv%d, %s, realm %d) in slot %d", m.id, m.size, m.size, bracket.key, m.realm, slot))
	hud(m)
	board(m)
	return true
end

-- ======================================================================== the tick
local function captureTick(m, L, now)
	local cfg = C()
	local counts = {}
	local inside = {}
	for i = 1, #m.braziers do
		counts[i], inside[i] = {0, 0}, {}
	end
	eachOnline(m, function(p, e)
		if not e.down then
			local i = K.brazierAt(cfg, L, p:getPosition())
			if i then
				counts[i][e.team] = counts[i][e.team] + 1
				table.insert(inside[i], e)
			end
		end
	end)
	for i, b in ipairs(m.braziers) do
		local event, who = K.captureStep(cfg, b, counts[i], 1)
		local spot = L.braziers[i]
		if event == "captured" then
			for _, e in ipairs(inside[i]) do
				if e.team == who then
					e.captures = e.captures + 1
					e.lastActive = now
				end
			end
			announce(m, "capture" .. who, "The %s took the %s!", cfg.teams[who].name, b.name)
			Position(spot.x, spot.y, spot.z):sendMagicEffect(effect(cfg.teams[who].effect))
		elseif event == "lost" then
			announce(m, "lost", "The %s lost the %s.", cfg.teams[who].name, b.name)
		end
		if (counts[i][1] > 0) ~= (counts[i][2] > 0) then
			for _, e in ipairs(inside[i]) do
				e.lastActive = now -- holding a well is playing
			end
		end
		if b.owner ~= 0 and now % 3 == 0 then
			Position(spot.x, spot.y, spot.z):sendMagicEffect(effect(cfg.teams[b.owner].effect))
		end
		-- the capture bar over the brazier for the players near it (tilebars.lua, client game_tileoverlays)
		if ChaosTileBars and ChaosTileBars.set and Chaos.tileBarsConfig and Chaos.tileBarsConfig.battleground then
			ChaosTileBars.set("bg:" .. m.id .. ":" .. i, ChaosTileBarsCore.brazierBar({x = spot.x, y = spot.y, z = spot.z},
				b.name, b.progress, b.owner, b.contested, cfg.teams))
		end
	end
end

local function tickMatch(m)
	if m.phase == "done" then
		return
	end
	local cfg = C()
	local now = os.time()
	local L = K.layout(cfg, m.slot)
	-- strangers on this field (a town portal or a stored hideout spot let them in): out (chaos_constants.lua)
	if Chaos.sweepDue and Chaos.sweepDue(m, now * 1000) then
		Chaos.sweepIntruders(function(pos) return K.inSlot(L, pos) end, function(p)
			local e = m.players[p:getId()]
			return e ~= nil and not e.gone
		end, "You are not playing on this battlefield: you were sent to your temple.") -- sweepIntruders translates it
	end
	for _, cid in ipairs(m.order) do
		local e = m.players[cid]
		if not e.gone then
			local p = Player(cid)
			if not p then
				leave(m, e, nil, "logged out")
			elseif not K.inSlot(L, p:getPosition()) then
				leave(m, e, p, "left the field")
			elseif p:getIp() == 0 then
				e.offSince = e.offSince or now
				if now - e.offSince >= cfg.disconnectSeconds then
					leave(m, e, p, "lost connection")
				end
			else
				e.offSince = nil
				local pos = p:getPosition()
				if not e.lastPos or e.lastPos.x ~= pos.x or e.lastPos.y ~= pos.y then
					e.lastActive = now
					e.lastPos = {x = pos.x, y = pos.y}
				end
				if Chaos.isMultiClient and Chaos.isMultiClient(p) then
					leave(m, e, p, "multi-client")
				elseif m.phase == "prep" then
					if K.baseOf(L, pos) ~= e.team then
						toSpawn(p, m, e)
					end
					e.lastActive = now
				elseif not e.down then
					local base = K.baseOf(L, pos)
					if base and base ~= e.team then
						msg(p, "Battleground: the wards of the enemy base throw you back.")
						toSpawn(p, m, e)
					end
					local afk = K.afk(cfg, now - e.lastActive)
					if afk == "kick" then
						leave(m, e, p, "inactive")
					elseif afk == "warn" and not e.afkWarned then
						e.afkWarned = true
						p:sendTextMessage(MESSAGE_STATUS_WARNING, Chaos.t(p, "Battleground: you seem inactive. Move or fight, or you are removed as a deserter in %d seconds.", cfg.afkKickSeconds - cfg.afkWarnSeconds))
					elseif not afk then
						e.afkWarned = nil
					end
					if now >= m.fightAt + cfg.secureGraceSeconds and p:hasSecureMode() and (now - m.fightAt) % 10 == 0 then
						p:sendTextMessage(MESSAGE_STATUS_WARNING, Chaos.t(p, "Battleground: turn secure mode off to fight back."))
					end
				else
					e.lastActive = now -- waiting for the wave
				end
			end
		end
	end
	if m.phase == "prep" and now >= m.fightAt then
		m.phase = "fight"
		m.nextWave = K.nextWave(cfg, m.fightAt, now)
		announce(m, "start", "The wells are open: take the braziers!")
		eachOnline(m, function(p)
			p:getPosition():sendMagicEffect(CONST_ME_FIREAREA)
		end)
	end
	if m.phase == "fight" then
		-- the respawn wave
		if now >= m.nextWave then
			m.nextWave = K.nextWave(cfg, m.fightAt, now)
			eachOnline(m, function(p, e)
				if e.down then
					e.down = false
					cleanse(p)
					heal(p)
					toSpawn(p, m, e)
				end
			end)
		end
		captureTick(m, L, now)
		while now >= m.nextTick do
			local a, b = K.tickPoints(cfg, m.braziers)
			m.score[1], m.score[2] = m.score[1] + a, m.score[2] + b
			m.nextTick = m.nextTick + cfg.tickSeconds
		end
		local left1, left2 = teamCount(m, 1), teamCount(m, 2)
		if left1 == 0 or left2 == 0 then
			finish(m, left1 == 0 and left2 == 0 and 0 or (left1 == 0 and 2 or 1), "forfeit")
			return
		end
		local winner, why = K.winner(cfg, m.score, now >= m.endAt)
		if winner then
			finish(m, winner, why)
			return
		end
	elseif m.phase == "prep" and (teamCount(m, 1) == 0 or teamCount(m, 2) == 0) then
		finish(m, 0, "stop")
		return
	end
	if m.phase == "fight" and ChaosInstanceLimits then -- warnings before the end (instance_limits.lua)
		local ps = {}
		eachOnline(m, function(p)
			ps[#ps + 1] = p
		end)
		ChaosInstanceLimits.warn(m, m.endAt - now, ps, "Battleground", cfg.limits)
	end
	hud(m)
	if now - m.lastBoard >= 3 then
		m.lastBoard = now
		board(m)
	end
end

local function matchmake()
	local now = os.time()
	local cfg = MC()
	local entries = {}
	for i = #B.queue, 1, -1 do
		local e = B.queue[i]
		local ok = now - e.joined < cfg.queueMinutes * 60
		for _, mem in ipairs(e.members) do
			if not Player(mem.cid) then
				ok = false
			end
		end
		if not ok then
			removeEntry(e)
			for _, mem in ipairs(e.members) do
				local p = Player(mem.cid)
				if p then
					msg(p, "Battleground: you left the queue (time out, or a party member logged out).")
					stateLater(mem.cid)
				end
			end
		end
	end
	for _, e in ipairs(B.queue) do
		entries[#entries + 1] = e
	end
	for _, found in ipairs(K.findMatches(cfg, entries, now)) do
		if not startMatch(found) and not freeSlot() then
			-- every field in use: the found teams hear it once (instance limits), with the wait, and stay queued
			if ChaosInstanceLimits then
				local lefts = {}
				for _, mm in pairs(B.matches) do
					lefts[#lefts + 1] = (mm.phase == "done" and 0 or math.max(0, mm.endAt - now)) + C().endDelaySeconds
				end
				local IK = ChaosInstanceLimits.core
				local text = "Battleground: " .. IK.busyText("battlefields", IK.eta(lefts, 1)) ..
					" Your match starts as soon as one frees up."
				for side = 1, 2 do
					for _, entry in ipairs(found.teams[side] or {}) do
						if not entry.busyTold then
							entry.busyTold = true
							for _, mem in ipairs(entry.members) do
								local p = Player(mem.cid)
								if p then
									msg(p, text)
								end
							end
						end
					end
				end
			end
			break
		end
	end
end

function B.tick()
	for _, m in pairs(B.matches) do
		local ok, err = pcall(tickMatch, m)
		if not ok then
			log("tick error: " .. tostring(err))
		end
	end
	local now = os.time()
	if now - B.lastMatchmake >= C().matchmakeSeconds and #B.queue > 0 then
		B.lastMatchmake = now
		local ok, err = pcall(matchmake)
		if not ok then
			log("matchmaking error: " .. tostring(err))
		end
	end
end

function B.stopAll()
	local n = 0
	for _, m in pairs(B.matches) do
		if m.phase ~= "done" then
			finish(m, 0, "stop")
			n = n + 1
		end
	end
	return n
end

local tick = GlobalEvent("ChaosBgTick")
function tick.onThink(interval)
	B.tick()
	return true
end
tick:interval(1000)
tick:register()

-- ======================================================================== combat hooks (fighters only)
local function verdict(creature, attacker)
	local m = B.matchOf[creature:getId()]
	if not m then
		return nil
	end
	local t = m.players[creature:getId()]
	local a = playerOf(attacker)
	local self = a and a:getId() == creature:getId()
	local ae = a and m.players[a:getId()] or nil
	if a and not ae and not self then
		return m, t, false, a
	end
	return m, t, K.canHit(m.phase, ae, t, self), a, ae
end

local function scaled(m, ae, t, amount)
	if not ae or ae == t then
		return amount
	end
	return math.floor(amount * K.normFactor(C(), ae.level, t.level, m.ref) + 0.5)
end

local health = CreatureEvent("ChaosBgHealth")
function health.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	local m = B.matchOf[creature:getId()]
	if not m then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local t = m.players[creature:getId()]
	if primaryType == COMBAT_HEALING then
		local a = playerOf(attacker)
		local ae = a and m.players[a:getId()]
		if a and not ae then
			return 0, primaryType, 0, secondaryType -- no healing from outside the match
		end
		local amount = scaled(m, ae, t, math.abs(primaryDamage))
		if ae and ae ~= t then
			ae.healing = ae.healing + math.min(amount, creature:getMaxHealth() - creature:getHealth())
			ae.lastActive = os.time()
		end
		return amount, primaryType, secondaryDamage, secondaryType
	end
	local _, _, allowed, a, ae = verdict(creature, attacker)
	if not allowed then
		return 0, primaryType, 0, secondaryType
	end
	local p, s = scaled(m, ae, t, math.abs(primaryDamage)), 0
	if secondaryType ~= COMBAT_HEALING then
		s = scaled(m, ae, t, math.abs(secondaryDamage))
	end
	local caught
	p, s, caught = K.catchDamage(creature:getHealth() + (creature.getEnergyShield and creature:getEnergyShield() or 0), p, s)
	if ae and ae ~= t then
		ae.damage = ae.damage + p + s
		ae.lastActive = os.time()
		t.hitBy[ae.cid] = os.time()
	end
	if caught then
		B.down(m, t, a and a:getId() ~= creature:getId() and a or nil)
	end
	return p, primaryType, secondaryType == COMBAT_HEALING and secondaryDamage or s, secondaryType
end
health:register()

local mana = CreatureEvent("ChaosBgMana")
function mana.onManaChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
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

local prepare = CreatureEvent("ChaosBgPrepareDeath")
function prepare.onPrepareDeath(creature, killer)
	local m = B.matchOf[creature:getId()]
	if not m then
		return true
	end
	local t = m.players[creature:getId()]
	local a = playerOf(killer)
	if m.phase == "fight" then
		B.down(m, t, a and a:getId() ~= creature:getId() and a or nil)
	end
	if creature:getHealth() < 1 then
		creature:setHealth(1)
	end
	return false -- nobody dies in the battleground
end
prepare:register()

local guard = EventCallback
guard.onTargetCombat = function(creature, target)
	if not creature or not target or not target:isPlayer() then
		return RETURNVALUE_NOERROR
	end
	local a = playerOf(creature)
	local tm = B.matchOf[target:getId()]
	local am = a and B.matchOf[a:getId()]
	if not tm and not am then
		return RETURNVALUE_NOERROR
	end
	if a and a:getId() == target:getId() then
		return RETURNVALUE_NOERROR
	end
	if tm ~= am then
		return RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER
	end
	if tm.phase == "prep" then
		a:sendCancelMessage(Chaos.t(a, "The wells open in %d seconds.", math.max(0, tm.fightAt - os.time())))
		return RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER
	end
	if not K.canHit(tm.phase, tm.players[a:getId()], tm.players[target:getId()], false) then
		return RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER
	end
	return RETURNVALUE_NOERROR
end
guard:register()

-- ======================================================================== the window
local function vendorView(player, row)
	local out = {}
	local owns = function(key)
		local CM = ChaosCosmetics
		return CM and CM.owns and CM.owns(player:getAccountId(), key) or false
	end
	for _, o in ipairs(C().vendor) do
		local ok, why = K.vendorCheck(C(), o.key, row.honor, owns)
		local itype = o.kind == "item" and ItemType(o.id) or nil
		out[#out + 1] = {key = o.key, name = o.name, cost = o.cost, kind = o.kind, can = ok ~= nil, why = why and Chaos.tx(player, why),
			owned = o.kind == "cosmetic" and owns(o.cosmetic) or nil,
			item = itype and itype.getClientId and itype:getClientId() or nil}
	end
	return out
end

function B.stateOf(player)
	local cfg = C()
	local guid = player:getGuid()
	local row = weekly(B.rowOf(guid))
	local now = os.time()
	local bracket = K.bracketOf(cfg, player:getLevel())
	local data = {enabled = cfg.enabled, minLevel = cfg.minLevel, level = player:getLevel(), realm = realmOf(player),
		roles = K.rolesOf(pfConfig(), vocId(player)), role = K.pickRole(pfConfig(), vocId(player), B.pref[guid]),
		honor = row.honor, weekHonor = row.weekHonor, weekCap = cfg.honor.weeklyCap, firstWinDone = row.weekWin == 1,
		record = {matches = row.matches, wins = row.wins, losses = row.losses, draws = row.draws, kills = row.kills,
			captures = row.captures}, deserter = deserterLeft(guid, now), now = now,
		rules = {teamMin = MC().teamMin, teamMax = cfg.teamMax, win = cfg.winScore, match = cfg.matchSeconds,
			wave = cfg.waveSeconds, prep = cfg.prepSeconds, partyMax = cfg.partyMax, honor = cfg.honor}}
	if bracket then
		data.bracket = {key = bracket.key, name = bracket.name, ref = bracket.ref}
	end
	local q = B.queued[player:getId()]
	if q then
		local waited = now - q.joined
		local n = queueSize(q.group)
		data.queue = {waited = waited, players = n, size = #q.members, leader = q.leader == player:getId(),
			est = K.estimateWait(MC(), B.samples[q.group], n, waited)}
	elseif bracket then
		local group = groupKey(data.realm, bracket)
		data.waiting = queueSize(group)
		data.est = K.estimateWait(MC(), B.samples[group], data.waiting, 0)
	end
	local m = B.matchOf[player:getId()]
	if m then
		data.match = {phase = m.phase, team = m.players[player:getId()].team}
	end
	if ChaosPvpSeason and ChaosPvpSeason.viewOf then
		local id, _, finish_ = ChaosPvpSeason.current()
		local ok, view = pcall(ChaosPvpSeason.viewOf, guid)
		data.season = {id = id, endsIn = finish_ - now, brackets = ok and view or {}, order = cfg.season.brackets,
			tiers = K.rewardPreview(cfg), placement = cfg.season.placementMatches,
			decay = cfg.season.decay, weeks = cfg.season.weeks}
	end
	data.vendor = vendorView(player, row)
	return data
end

function B.sendState(player, open)
	local data = B.stateOf(player)
	data.open = open and true or false
	send(player, "state", data)
end

local function buy(player, key)
	local row = B.rowOf(player:getGuid())
	local owns = function(k)
		local CM = ChaosCosmetics
		return CM and CM.owns and CM.owns(player:getAccountId(), k) or false
	end
	local offer, why = K.vendorCheck(C(), key, row.honor, owns)
	if not offer then
		send(player, "msg", {text = Chaos.tx(player, why), ok = false})
		return false
	end
	if offer.kind == "cosmetic" then
		local CM = ChaosCosmetics
		if not (CM and CM.grant) then
			send(player, "msg", {text = Chaos.t(player, "Cosmetics are not available on this server."), ok = false})
			return false
		end
		local ok, err = CM.grant(player:getAccountId(), offer.cosmetic, "pvp")
		if not ok then
			send(player, "msg", {text = Chaos.tx(player, err or "Could not unlock it."), ok = false})
			return false
		end
	else
		local added = Chaos.giveItem(player, offer.id, offer.count)
		if added < offer.count then
			local inbox = player:getInbox()
			if inbox then
				inbox:addItem(offer.id, offer.count - added, INDEX_WHEREEVER or -1, FLAG_NOLIMIT)
			end
		end
	end
	row.honor = row.honor - offer.cost
	B.saveRow(player:getGuid())
	db.query(string.format("INSERT INTO `%s` (`player_id`, `offer`, `cost`, `at`) VALUES (%d, %s, %d, %d)", T("purchases"),
		player:getGuid(), db.escapeString(offer.key), offer.cost, os.time()))
	send(player, "msg", {text = Chaos.t(player, "Bought: %s for %d honor.", offer.name, offer.cost), ok = true})
	return true
end
B.buy = buy

-- ======================================================================== login / logout / opcode
local login = CreatureEvent("ChaosBgLogin")
function login.onLogin(player)
	player:registerEvent("ChaosBgLogout")
	player:registerEvent("ChaosBgExtended")
	local st = C().storage
	-- a crash or restart during a match: back to where the match started (or the temple)
	if player:getStorageValue(st.inside) == 1 or K.slotOfPos(C(), player:getPosition()) then
		local x, y, z = player:getStorageValue(st.retX), player:getStorageValue(st.retY), player:getStorageValue(st.retZ)
		player:setStorageValue(st.inside, 0)
		if x > 0 and y > 0 and z >= 0 and Tile(Position(x, y, z)) then
			player:teleportTo(Position(x, y, z))
		else
			player:teleportTo(player:getTown():getTemplePosition())
		end
	end
	B.rowOf(player:getGuid(), true)
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosBgLogout")
function logout.onLogout(player)
	local cid = player:getId()
	if B.queued[cid] then
		B.leaveQueue(player, true)
	end
	local m = B.matchOf[cid]
	if m and m.phase ~= "done" then
		local state = Game.getGameState and Game.getGameState()
		if state ~= nil and (state == GAME_STATE_SHUTDOWN or state == GAME_STATE_CLOSED) then
			B.stopAll()
		end
	end
	if m then
		local e = m.players[cid]
		if m.phase == "done" then
			release(player, e)
			e.gone = true
		else
			leave(m, e, player, "logged out")
		end
	end
	B.players[player:getGuid()] = nil
	return true
end
logout:type("logout")
logout:register()

local shutdown = GlobalEvent("ChaosBgShutdown")
function shutdown.onShutdown()
	B.stopAll()
	return true
end
shutdown:register()

local startup = GlobalEvent("ChaosBgStartup")
function startup.onStartup()
	B.ensureTables()
	return true
end
startup:register()

local ext = CreatureEvent("ChaosBgExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local m = Chaos.decode(buffer)
	if not m then
		return
	end
	if ChaosRateLimit and not ChaosRateLimit.allow(player, "bg." .. tostring(m.action), 300) then
		return
	end
	local data = type(m.data) == "table" and m.data or {}
	if m.action == "open" then
		B.sendState(player, true)
	elseif m.action == "query" then
		B.sendState(player, false)
	elseif m.action == "queue" then
		B.join(player, K.parseRole(data.role))
		B.sendState(player, false)
	elseif m.action == "role" then
		local role = K.parseRole(data.role)
		if role then
			B.pref[player:getGuid()] = K.pickRole(pfConfig(), vocId(player), role)
		end
		B.sendState(player, false)
	elseif m.action == "leave" then
		local mm = B.matchOf[player:getId()]
		if mm and mm.phase ~= "done" then
			leave(mm, mm.players[player:getId()], player, "left")
		else
			B.leaveQueue(player)
			B.sendState(player, false)
		end
	elseif m.action == "board" then
		local mm = B.matchOf[player:getId()]
		if mm then
			board(mm, player)
		end
	elseif m.action == "buy" then
		buy(player, tostring(data.key or ""))
		B.sendState(player, false)
	end
end
ext:type("extendedopcode")
ext:register()

-- ======================================================================== staff: /bg stop | slots | min <n> | off | on
local talk = TalkAction("/bg")
function talk.onSay(player, words, param)
	if not player:getGroup():getAccess() or player:getGroup():getId() < C().staffGroup then
		return false
	end
	local cmd, arg = tostring(param or ""):match("^%s*(%S*)%s*(.-)%s*$")
	if cmd == "stop" then
		player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("Battleground: %d match(es) stopped (not rated).", B.stopAll()))
	elseif cmd == "slots" then
		local busy = 0
		for _ in pairs(B.matches) do
			busy = busy + 1
		end
		local bad = {}
		for slot, why in pairs(B.bad) do
			bad[#bad + 1] = slot .. ": " .. why
		end
		player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("Battleground: %d match(es), %d queue entries, bad slots: %s",
			busy, #B.queue, #bad > 0 and table.concat(bad, "; ") or "none"))
	elseif cmd == "min" then
		local n = tonumber(arg)
		B.minOverride = (n and n >= 1 and n < C().teamMin) and math.floor(n) or nil
		player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, "Battleground: smallest team now %s (TEST ONLY, memory).", MC().teamMin))
	elseif cmd == "off" or cmd == "on" then
		C().enabled = cmd == "on"
		player:sendTextMessage(MESSAGE_INFO_DESCR, "Battleground queue " .. (C().enabled and "open." or "closed."))
	else
		player:sendTextMessage(MESSAGE_INFO_DESCR, "/bg stop | slots | min <n> | off | on")
	end
	return false
end
talk:separator(" ")
talk:register()
