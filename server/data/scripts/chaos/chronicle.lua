-- The Ashen Chronicle (client game_chronicle, extended opcode ChaosOpcodes.chronicle = 171): a server-wide story per
-- season that advances with what the whole realm does. Rules and numbers: chronicle_config.lua; pure logic:
-- chronicle_core.lua (tests: server/tests/chronicle_test.lua); story: chronicle_text.lua (EN and PT-BR). Overview:
-- server/README.md "The Ashen Chronicle". Tables: chaos_chronicle_state, _chapters, _progress, _contrib, _record, _levels
-- (server/sql/chaos_chronicle.sql; also created at startup). No player storages; global storages 7102100-7102119.
--
-- Each season with an arc (chronicle_config.lua `arcs`) has 4-6 chapters; one is open at a time and is written when
-- every goal is met. A written chapter changes the world: an area's gate portal appears (and its global flag is set,
-- for NPC scripts), the NPC lines of chronicle_text.lua move on (global storage `done`), decoration is placed in or
-- taken away from the capital, a broadcast (in each player's language) and a Discord row (ChaosDiscord.queue) go out.
-- The world is replayed from the written chapters (ChaosChronicleCore.worldOf) at every start, so it is reversible: a
-- new season starts from nothing. At a season's end the top contributors of every chapter are written to
-- chaos_chronicle_record (website, client Record tab).
--
-- Sources (no content script was edited; every hook is guarded and wrapped once through ChaosWrapChain):
--   ChaosRecords.submit(run)          runs the competitive records accepted (staff, multi-client and debug runs are
--                                     refused there): world boss kills, sealed rifts (by tier band), Omen guardians,
--                                     the Ascended and the Cinderheart
--   ChaosAchievements.progress(p, "raid_clears")  an Ashen Sepulchre clear (raid.lua, every player present), once per
--                                     raid run (ChaosRaid.runOf); wrapped once at load, under season_journey.lua's wrapper
--   ChaosInvasion.deliver(player, r)  an invasion repelled (not a liberation), once per invasion
--   advance event                     a character reaching a goal's level (once per character and season)
--   ChaosChronicle.event(key, players)  any other script: a world event done
-- Privacy: names in the top lists follow the Memorial's "records" choice (memorial.lua; on unless the player turned it off).
--
-- Protocol (JSON {action, data}; the state goes out with Chaos.sendChunked):
--   client -> server  open | close
--   server -> client  state {...} (chronicle_core.lua K.payload)
-- memorial.lua answers its own actions on the same opcode (mem, memset).
-- Staff: /chronicle [status | world | complete | reset] (complete and reset: group 5, logged)
-- Lua 5.1 / LuaJIT.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
dofile("data/scripts/chaos/chronicle_core.lua")
dofile("data/scripts/chaos/chronicle_text.lua")
ChaosChronicleCore.ensureWrapChain()

Chaos.chronicleConfig = dofile("data/scripts/chaos/chronicle_config.lua")
local cfg = Chaos.chronicleConfig
-- server/README.md "Extended opcodes in use": 171 (chaos_constants.lua names it too once its line is in)
ChaosOpcodes.chronicle = ChaosOpcodes.chronicle or cfg.opcode
local K = ChaosChronicleCore
local TXT = ChaosChronicleText
local OPCODE = ChaosOpcodes.chronicle or cfg.opcode
local T = cfg.tables
local GS = cfg.globalStorage

ChaosChronicle = ChaosChronicle or {}
local X = ChaosChronicle
X.state = X.state -- the running season's state (K.newState shape), or nil
X.idle = X.idle -- {arc, done} of the last finished season while no season runs (its world stays until the next start)
X.world = X.world or {open = {}, town = {}} -- what is placed now
X.placed = X.placed or {} -- set key -> {{pos, id}} decoration placed
X.swapped = X.swapped or {} -- set key -> {{pos, from, to}} grounds turned
X.levels = X.levels or {} -- "guid:level" -> true (counted this season)
X.raidRuns = X.raidRuns or setmetatable({}, {__mode = "k"}) -- raid run -> the chapter its clear counted for (false: none)
X.invasions = X.invasions or {} -- invasion key -> the chapter it counted for (false: none)
X.watch = X.watch or {} -- player id -> true while the window is open
X.record = X.record or {} -- cached past seasons for the Record tab
X.dirty = X.dirty or false
X.changed = X.changed or false

local function now()
	return os.time()
end

local function log(text)
	print("[Chaos chronicle] " .. text)
end

local function try(what, fn, ...)
	local ok, a, b = pcall(fn, ...)
	if not ok then
		log(what .. ": " .. tostring(a))
		return nil
	end
	return a, b
end

local function q(text)
	return db.escapeString(tostring(text or ""))
end

local function isStaff(player)
	local ok, id = pcall(function() return player:getGroup():getId() end)
	return ok and (id or 1) >= (cfg.staffGroup or 4)
end

local function isPlayer(x)
	return type(x) == "userdata" and x.isPlayer ~= nil and x:isPlayer() or (type(x) == "table" and type(x.getGuid) == "function")
end

-- the player's language for our texts: "pt" or "en" (i18n.lua's Chaos.lang when it is loaded)
local function langOf(player)
	if Chaos.lang then
		local ok, l = pcall(Chaos.lang, player)
		if ok and type(l) == "string" and l:sub(1, 2) == "pt" then
			return "pt"
		end
	end
	return "en"
end

-- a broadcast of a text in both languages ({en, pt} or function(lang) -> text): each player reads their own
-- (Chaos.broadcast of i18n.lua), else the English one
local function broadcast(field)
	if not cfg.broadcast or not field then
		return
	end
	local function textIn(lang)
		if type(field) == "function" then
			return field(lang)
		end
		return TXT.pick(field, lang)
	end
	if Chaos.broadcast then
		local ok = pcall(Chaos.broadcast, MESSAGE_EVENT_ADVANCE, function(lang)
			return textIn((type(lang) == "string" and lang:sub(1, 2) == "pt") and "pt" or "en")
		end)
		if ok then
			return
		end
	end
	if Game and Game.broadcastMessage then
		Game.broadcastMessage(textIn("en"), MESSAGE_EVENT_ADVANCE)
	end
end

local function seasonNow()
	local S = ChaosSeason
	if not (S and S.current) then
		return nil
	end
	local ok, s = pcall(S.current)
	return ok and type(s) == "table" and s or nil
end

-- the Discord queue (discord.lua's ChaosDiscord.queue, when it is loaded; it drops kinds its config does not switch
-- on: discord_config.lua needs events.chronicle = true and a channel)
local function discord(row)
	local D = ChaosDiscord
	if not (D and row and type(D.queue) == "function") then
		return
	end
	local dc = ChaosDiscordConfig
	row.channel = dc and dc.channels and dc.channels[row.kind] or row.channel
	try("discord", D.queue, row)
end

-- ---------------------------------------------------------------- tables
function X.ensureTables()
	db.query(string.format("CREATE TABLE IF NOT EXISTS `%s` (`season` smallint(5) unsigned NOT NULL, `arc` varchar(16) NOT NULL DEFAULT '', " ..
		"`chapter` tinyint(3) unsigned NOT NULL DEFAULT 1, `done` tinyint(3) unsigned NOT NULL DEFAULT 0, " ..
		"`started_at` int(10) unsigned NOT NULL DEFAULT 0, `finished_at` int(10) unsigned NOT NULL DEFAULT 0, " ..
		"`updated_at` int(10) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`season`)) ENGINE=InnoDB DEFAULT CHARSET=utf8", T.state))
	db.query(string.format("CREATE TABLE IF NOT EXISTS `%s` (`season` smallint(5) unsigned NOT NULL, `chapter` tinyint(3) unsigned NOT NULL, " ..
		"`chapter_key` varchar(32) NOT NULL DEFAULT '', `title` varchar(96) NOT NULL DEFAULT '', `title_pt` varchar(96) NOT NULL DEFAULT '', " ..
		"`world` varchar(255) NOT NULL DEFAULT '', `world_pt` varchar(255) NOT NULL DEFAULT '', `done_at` int(10) unsigned NOT NULL DEFAULT 0, " ..
		"PRIMARY KEY (`season`, `chapter`)) ENGINE=InnoDB DEFAULT CHARSET=utf8", T.chapters))
	db.query(string.format("CREATE TABLE IF NOT EXISTS `%s` (`season` smallint(5) unsigned NOT NULL, `chapter` tinyint(3) unsigned NOT NULL, " ..
		"`goal` tinyint(3) unsigned NOT NULL, `label` varchar(64) NOT NULL DEFAULT '', `progress` int(11) NOT NULL DEFAULT 0, " ..
		"`target` int(11) NOT NULL DEFAULT 0, `done_at` int(10) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`season`, `chapter`, `goal`)) " ..
		"ENGINE=InnoDB DEFAULT CHARSET=utf8", T.progress))
	db.query(string.format("CREATE TABLE IF NOT EXISTS `%s` (`season` smallint(5) unsigned NOT NULL, `chapter` tinyint(3) unsigned NOT NULL, " ..
		"`player_id` int(11) NOT NULL, `name` varchar(255) NOT NULL DEFAULT '', `points` int(11) NOT NULL DEFAULT 0, " ..
		"`updated_at` int(10) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`season`, `chapter`, `player_id`), " ..
		"KEY `rank` (`season`, `chapter`, `points`), FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE) " ..
		"ENGINE=InnoDB DEFAULT CHARSET=utf8", T.contrib))
	db.query(string.format("CREATE TABLE IF NOT EXISTS `%s` (`season` smallint(5) unsigned NOT NULL, `chapter` tinyint(3) unsigned NOT NULL, " ..
		"`place` tinyint(3) unsigned NOT NULL, `player_id` int(11) NOT NULL, `name` varchar(255) NOT NULL DEFAULT '', " ..
		"`points` int(11) NOT NULL DEFAULT 0, `recorded_at` int(10) unsigned NOT NULL DEFAULT 0, " ..
		"PRIMARY KEY (`season`, `chapter`, `place`), KEY `player` (`player_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8", T.record))
	db.query(string.format("CREATE TABLE IF NOT EXISTS `%s` (`season` smallint(5) unsigned NOT NULL, `player_id` int(11) NOT NULL, " ..
		"`level` smallint(5) unsigned NOT NULL, PRIMARY KEY (`season`, `player_id`, `level`), FOREIGN KEY (`player_id`) " ..
		"REFERENCES `players` (`id`) ON DELETE CASCADE) ENGINE=InnoDB DEFAULT CHARSET=utf8", T.levels))
end

-- ---------------------------------------------------------------- persistence
function X.saveState(st)
	if not st then
		return
	end
	db.asyncQuery(string.format("INSERT INTO `%s` (`season`, `arc`, `chapter`, `done`, `started_at`, `finished_at`, `updated_at`) " ..
		"VALUES (%d, %s, %d, %d, %d, %d, %d) ON DUPLICATE KEY UPDATE `chapter` = VALUES(`chapter`), `done` = VALUES(`done`), " ..
		"`finished_at` = VALUES(`finished_at`), `updated_at` = VALUES(`updated_at`)", T.state, st.season, q(st.arc), st.chapter,
		K.doneCount(cfg, st), st.startedAt or 0, st.finishedAt or 0, now()))
	local tarc = TXT.arcs[st.arc]
	for ci, ch in ipairs(K.chapters(cfg, st.arc)) do
		local tch = tarc and tarc.chapters[ci] or {}
		local done = st.doneAt[ci] and true or false
		db.asyncQuery(string.format("INSERT INTO `%s` (`season`, `chapter`, `chapter_key`, `title`, `title_pt`, `world`, `world_pt`, `done_at`) " ..
			"VALUES (%d, %d, %s, %s, %s, %s, %s, %d) ON DUPLICATE KEY UPDATE `chapter_key` = VALUES(`chapter_key`), `title` = VALUES(`title`), " ..
			"`title_pt` = VALUES(`title_pt`), `world` = VALUES(`world`), `world_pt` = VALUES(`world_pt`), `done_at` = VALUES(`done_at`)",
			T.chapters, st.season, ci, q(ch.key), q(TXT.pick(tch.title, "en")), q(TXT.pick(tch.title, "pt")),
			q(done and TXT.pick(tch.world, "en") or ""), q(done and TXT.pick(tch.world, "pt") or ""), st.doneAt[ci] or 0))
		for gi, g in ipairs(ch.goals) do
			db.asyncQuery(string.format("INSERT INTO `%s` (`season`, `chapter`, `goal`, `label`, `progress`, `target`, `done_at`) VALUES " ..
				"(%d, %d, %d, %s, %d, %d, %d) ON DUPLICATE KEY UPDATE `label` = VALUES(`label`), `progress` = VALUES(`progress`), " ..
				"`target` = VALUES(`target`), `done_at` = VALUES(`done_at`)", T.progress, st.season, ci, gi, q(K.goalLabel(cfg, g)),
				st.progress[ci][gi] or 0, g.target, st.doneAt[ci] or 0))
		end
	end
end

function X.flush()
	local st = X.state
	if not st then
		return
	end
	if X.dirty then
		X.saveState(st)
		X.dirty = false
	end
	for ci, book in pairs(st.contrib) do
		for guid, e in pairs(book) do
			if e.dirty then
				db.asyncQuery(string.format("INSERT INTO `%s` (`season`, `chapter`, `player_id`, `name`, `points`, `updated_at`) VALUES " ..
					"(%d, %d, %d, %s, %d, %d) ON DUPLICATE KEY UPDATE `points` = VALUES(`points`), `name` = VALUES(`name`), " ..
					"`updated_at` = VALUES(`updated_at`)", T.contrib, st.season, ci, guid, q(e.name), e.points, e.at or now()))
				e.dirty = false
			end
		end
	end
end

-- the state of a season from the tables (nil when it has none)
function X.loadState(seasonId)
	local row = Chaos.select(string.format("SELECT `arc`, `chapter`, `started_at`, `finished_at` FROM `%s` WHERE `season` = %d",
		T.state, seasonId), {{"arc", "s"}, {"chapter", "n"}, {"started_at", "n"}, {"finished_at", "n"}})[1]
	if not row or not cfg.chapters[row.arc] then
		return nil
	end
	local st = K.newState(cfg, row.arc, seasonId, row.started_at)
	st.chapter = math.max(1, row.chapter)
	st.finishedAt = row.finished_at
	for _, r in ipairs(Chaos.select(string.format("SELECT `chapter`, `goal`, `progress`, `done_at` FROM `%s` WHERE `season` = %d",
		T.progress, seasonId), {{"chapter", "n"}, {"goal", "n"}, {"progress", "n"}, {"done_at", "n"}})) do
		if st.progress[r.chapter] and st.progress[r.chapter][r.goal] then
			st.progress[r.chapter][r.goal] = r.progress
			if r.done_at > 0 then
				st.doneAt[r.chapter] = r.done_at
			end
		end
	end
	for _, r in ipairs(Chaos.select(string.format("SELECT `chapter`, `player_id`, `name`, `points`, `updated_at` FROM `%s` WHERE `season` = %d",
		T.contrib, seasonId), {{"chapter", "n"}, {"player_id", "n"}, {"name", "s"}, {"points", "n"}, {"updated_at", "n"}})) do
		if st.contrib[r.chapter] then
			st.contrib[r.chapter][r.player_id] = {name = r.name, points = r.points, at = r.updated_at}
		end
	end
	return st
end

function X.loadLevels(seasonId)
	X.levels = {}
	for _, r in ipairs(Chaos.select(string.format("SELECT `player_id`, `level` FROM `%s` WHERE `season` = %d", T.levels, seasonId),
		{{"player_id", "n"}, {"level", "n"}})) do
		X.levels[r.player_id .. ":" .. r.level] = true
	end
end

-- the past seasons of the Record tab (privacy: the Memorial's records choice, read when the window asks)
function X.loadRecord()
	local out = {}
	local seasons = Chaos.select(string.format("SELECT `season`, `arc` FROM `%s` WHERE `finished_at` > 0 ORDER BY `season` DESC LIMIT %d",
		T.state, cfg.recordSeasons or 3), {{"season", "n"}, {"arc", "s"}})
	for _, s in ipairs(seasons) do
		local tarc = TXT.arcs[s.arc]
		local entry = {season = s.season, name = "", title = tarc and {en = TXT.pick(tarc.title, "en"), pt = TXT.pick(tarc.title, "pt")},
			chapters = {}}
		local cfgSeason = Chaos.seasonConfig and Chaos.seasonConfig.seasons or {}
		for _, def in ipairs(cfgSeason) do
			if def.id == s.season then
				entry.name = def.name
			end
		end
		for _, r in ipairs(Chaos.select(string.format("SELECT `chapter`, `place`, `player_id`, `name`, `points` FROM `%s` WHERE `season` = %d " ..
			"ORDER BY `chapter` ASC, `place` ASC", T.record, s.season), {{"chapter", "n"}, {"place", "n"}, {"player_id", "n"},
			{"name", "s"}, {"points", "n"}})) do
			local c = entry.chapters[r.chapter]
			if not c then
				local tch = tarc and tarc.chapters[r.chapter]
				c = {i = r.chapter, title = tch and {en = TXT.pick(tch.title, "en"), pt = TXT.pick(tch.title, "pt")}, top = {}}
				entry.chapters[r.chapter] = c
			end
			c.top[#c.top + 1] = {guid = r.player_id, n = r.name, p = r.points}
		end
		local list = {}
		for i = 1, #K.chapters(cfg, s.arc) do
			if entry.chapters[i] then
				list[#list + 1] = entry.chapters[i]
			end
		end
		entry.chapters = list
		out[#out + 1] = entry
	end
	X.record = out
	return out
end

-- ---------------------------------------------------------------- privacy (the Memorial's records choice)
local function shown(guid)
	local M = ChaosMemorial
	if M and M.showsRecords then
		local ok, v = pcall(M.showsRecords, guid)
		if ok then
			return v ~= false
		end
	end
	return true
end

local HIDDEN = "A hero who keeps their name"

local function topFor(ci, n)
	local list = {}
	for _, e in ipairs(K.top(X.state.contrib[ci], n)) do
		list[#list + 1] = {name = shown(e.guid) and e.name or HIDDEN, points = e.points}
	end
	return list
end

-- ---------------------------------------------------------------- the world
local function P(t)
	return Position(t.x, t.y, t.z)
end

local function anchor()
	local a = cfg.town and cfg.town.anchor
	if type(a) == "table" and a.x then
		return {x = a.x, y = a.y, z = a.z}
	end
	local town = Town and Town(cfg.townId or 1)
	local temple = town and town:getTemplePosition()
	return temple and {x = temple.x, y = temple.y, z = temple.z} or nil
end

local function freeTile(pos)
	local tile = Tile(P(pos))
	if not tile or not tile:getGround() then
		return nil
	end
	if tile:hasProperty(CONST_PROP_BLOCKSOLID) or tile:getTopCreature() or tile:hasFlag(TILESTATE_TELEPORT)
		or tile:hasFlag(TILESTATE_FLOORCHANGE) then
		return nil
	end
	return tile
end

local function townAid()
	return (cfg.gateAid or 47920) + 9 -- 47929: town decoration (found again after a /reload)
end

local function removeAidItems(pos, aid, id)
	local tile = Tile(P(pos))
	for _, it in ipairs(tile and tile:getItems() or {}) do
		if it:getActionId() == aid and (not id or it:getId() == id) then
			it:remove()
			return true
		end
	end
	return false
end

function X.placeSet(key)
	local set = cfg.town.sets[key]
	local a = anchor()
	if not set or not a then
		return 0
	end
	local placed, swapped = {}, {}
	for _, piece in ipairs(set.pieces or {}) do
		for _, o in ipairs(piece.at) do
			local pos = {x = a.x + o[1], y = a.y + o[2], z = a.z}
			if freeTile(pos) then
				local it = Game.createItem(piece.id, 1, P(pos))
				if it then
					it:setActionId(townAid())
					placed[#placed + 1] = {pos = pos, id = piece.id}
				end
				break
			end
		end
	end
	for _, s in ipairs(set.swaps or {}) do
		local pos = {x = a.x + s[1], y = a.y + s[2], z = a.z}
		local tile = Tile(P(pos))
		local g = tile and tile:getGround()
		if g and g:getId() == s.from then
			g:transform(s.to)
			swapped[#swapped + 1] = {pos = pos, from = s.from, to = s.to}
		end
	end
	X.placed[key], X.swapped[key] = placed, swapped
	return #placed + #swapped
end

function X.removeSet(key)
	local set = cfg.town.sets[key]
	local a = anchor()
	local n = 0
	for _, p in ipairs(X.placed[key] or {}) do
		if removeAidItems(p.pos, townAid(), p.id) then
			n = n + 1
		end
	end
	-- after a /reload the list is gone: look at every offset of the set
	if not X.placed[key] and set and a then
		for _, piece in ipairs(set.pieces or {}) do
			for _, o in ipairs(piece.at) do
				if removeAidItems({x = a.x + o[1], y = a.y + o[2], z = a.z}, townAid(), piece.id) then
					n = n + 1
				end
			end
		end
	end
	for _, s in ipairs(X.swapped[key] or {}) do
		local tile = Tile(P(s.pos))
		local g = tile and tile:getGround()
		if g and g:getId() == s.to then
			g:transform(s.from)
			n = n + 1
		end
	end
	X.placed[key], X.swapped[key] = nil, nil
	return n
end

local function areaReady(area)
	return K.gateOf(area) ~= nil and K.arrivalOf(area) ~= nil
end

function X.openArea(key)
	local area, index = K.areaByKey(cfg, key)
	if not area then
		return false
	end
	if not areaReady(area) then
		log(string.format("%s is open in the story but not placed: set at and gate in chronicle_config.lua areas", area.name))
		return false
	end
	local gate = K.gateOf(area)
	local aid = cfg.gateAid + index - 1
	local tile = Tile(P(gate))
	for _, it in ipairs(tile and tile:getItems() or {}) do
		if it:getActionId() == aid then
			return true -- already there (a /reload)
		end
	end
	local it = Game.createItem(cfg.gateItem, 1, P(gate))
	if it then
		it:setActionId(aid)
		return true
	end
	return false
end

function X.closeArea(key)
	local area, index = K.areaByKey(cfg, key)
	local gate = area and K.gateOf(area)
	if gate then
		return removeAidItems(gate, cfg.gateAid + index - 1)
	end
	return false
end

function X.setFlags(arc, done, seasonId)
	if not (Game and Game.setStorageValue) then
		return
	end
	for n = 1, 9 do
		Game.setStorageValue(GS.base + n, (arc and n <= done) and 1 or 0)
	end
	Game.setStorageValue(GS.done, done or 0)
	Game.setStorageValue(GS.season, seasonId or -1)
end

-- place / take away what differs from the written chapters (a start, a written chapter, a new season)
function X.applyWorld()
	local arc, done, seasonId
	if X.state then
		arc, done, seasonId = X.state.arc, K.doneCount(cfg, X.state), X.state.season
	elseif X.idle then
		arc, done, seasonId = X.idle.arc, X.idle.done, X.idle.season
	end
	local want = arc and K.worldOf(cfg, arc, done) or {open = {}, town = {}, flags = 0}
	local d = K.worldDiff(X.world, want)
	for _, key in ipairs(d.closeAreas) do
		try("close " .. key, X.closeArea, key)
	end
	for _, key in ipairs(d.removeSets) do
		try("remove " .. key, X.removeSet, key)
	end
	for _, key in ipairs(d.addSets) do
		try("place " .. key, X.placeSet, key)
	end
	local open = {}
	for key in pairs(want.open) do
		open[key] = true
		try("open " .. key, X.openArea, key) -- again every tick: an area placed later appears without a restart
	end
	X.world = {open = open, town = want.town}
	try("flags", X.setFlags, arc, done or 0, seasonId)
	return d
end

-- the gate portals: a player goes to the area's arrival while it is open
local step = MoveEvent()
step:type("stepin")
function step.onStepIn(creature, item, position, fromPosition)
	local player = creature and creature:getPlayer()
	if not player then
		return true
	end
	local index = item:getActionId() - cfg.gateAid + 1
	local area = cfg.areas[index]
	if not area or not X.world.open[area.key] or not K.arrivalOf(area) then
		player:teleportTo(fromPosition, true)
		player:sendCancelMessage("The way is sealed.")
		return true
	end
	if player:getLevel() < (area.minLevel or 1) then
		player:teleportTo(fromPosition, true)
		player:sendCancelMessage(string.format("%s is for level %d and above.", area.name, area.minLevel))
		return true
	end
	player:teleportTo(P(K.arrivalOf(area)))
	player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("%s. The portal beside you leads back to the temple.", area.name))
	return true
end
do
	local aids = {}
	for i = 1, #cfg.areas do
		aids[#aids + 1] = cfg.gateAid + i - 1
	end
	if #aids > 0 then
		step:aid((unpack or table.unpack)(aids))
	end
end
step:register()

-- ---------------------------------------------------------------- events into the open chapter
-- members: Player userdata, guids or {guid, name}; staff are left out
local function memberList(list)
	local out = {}
	for _, m in ipairs(list or {}) do
		if isPlayer(m) then
			if not isStaff(m) then
				out[#out + 1] = {guid = m:getGuid(), name = m:getName()}
			end
		elseif type(m) == "table" and tonumber(m.guid) then
			out[#out + 1] = {guid = tonumber(m.guid), name = m.name}
		elseif tonumber(m) then
			out[#out + 1] = {guid = tonumber(m), name = nil}
		end
	end
	return out
end

-- the names of members known by guid only
local function fillNames(members)
	local missing = {}
	for _, m in ipairs(members) do
		if not m.name or m.name == "" then
			local P_ = Player and Player(m.guid)
			if P_ and P_.getName then
				m.name = P_:getName()
			else
				missing[#missing + 1] = math.floor(m.guid)
			end
		end
	end
	if #missing > 0 then
		local byId = {}
		for _, r in ipairs(Chaos.select(string.format("SELECT `id`, `name` FROM `players` WHERE `id` IN (%s)",
			table.concat(missing, ",")), {{"id", "n"}, {"name", "s"}})) do
			byId[r.id] = r.name
		end
		for _, m in ipairs(members) do
			if not m.name or m.name == "" then
				m.name = byId[m.guid] or ""
			end
		end
	end
	return members
end

local function sendAll()
	for id in pairs(X.watch) do
		local p = Player(id)
		if p then
			try("send", X.send, p)
		else
			X.watch[id] = nil
		end
	end
end

function X.chapterWritten(ci)
	local st = X.state
	broadcast(function(lang)
		return K.chapterText(TXT, st.arc, ci, lang)
	end)
	local top = K.top(st.contrib[ci], 3)
	local shownTop = {}
	for _, e in ipairs(top) do
		shownTop[#shownTop + 1] = {name = shown(e.guid) and e.name or HIDDEN, points = e.points}
	end
	discord(K.discordRow(cfg, TXT, st, ci, shownTop))
	log(string.format("season %d: chapter %d written", st.season, ci))
	X.saveState(st)
	X.applyWorld()
	if K.allDone(cfg, st) then
		local tarc = TXT.arcs[st.arc]
		broadcast(tarc and tarc.ending)
	end
end

-- one event into the open chapter. opts.progress = false: contributions only
function X.add(ev, members, opts)
	local st = X.state
	if not (cfg.enabled and st) then
		return nil
	end
	local list = fillNames(memberList(members))
	local res = K.addEvent(cfg, st, ev, list, now(), opts)
	if res.matched then
		X.dirty, X.changed = true, true
	end
	if res.completed then
		X.chapterWritten(res.completed)
		sendAll()
	end
	return res
end

-- points for the other members of a run already counted (into the chapter that run counted for)
function X.credit(ci, ev, members)
	if not (cfg.enabled and X.state and ci) then
		return 0
	end
	local pts = K.credit(cfg, X.state, ci, ev, fillNames(memberList(members)), now())
	X.dirty, X.changed = true, true
	return pts
end

-- the API of other scripts: a world event done (dedupe is the caller's); players: Player | guid | {guid, name}
function X.event(key, players)
	return X.add({kind = "event", event = tostring(key)}, players)
end

-- ---------------------------------------------------------------- hooks
local function onSubmit(res, run)
	if not res[1] or type(run) ~= "table" then
		return -- the records refused it (staff, multi-client, debug, size)
	end
	for _, ev in ipairs(K.eventsOfRun(cfg, run)) do
		if ev.kind ~= "raid" then -- the raid comes through its clear (onRaidProgress), once per run
			X.add(ev, run.members)
		end
	end
end

local function raidRunOf(player)
	local runs = ChaosRaid and ChaosRaid.runOf
	if type(runs) == "table" then
		return runs[player:getId()]
	elseif type(runs) == "function" then
		local ok, r = pcall(runs, player)
		return ok and r or nil
	end
	return nil
end

local function onAchievementProgress(res, who, key)
	if key ~= "raid_clears" or not isPlayer(who) or isStaff(who) then
		return
	end
	local run = raidRunOf(who)
	local seen = type(run) == "table" and X.raidRuns[run]
	if seen ~= nil then
		if seen then
			X.credit(seen, {kind = "raid"}, {who})
		end
		return
	end
	local res = X.add({kind = "raid"}, {who})
	if type(run) == "table" then
		X.raidRuns[run] = res and res.matched and res.chapter or false
	end
end

local function onInvasionDeliver(res, player, r)
	if type(r) ~= "table" or r.liberation or not isPlayer(player) or isStaff(player) then
		return
	end
	local key = tostring(r.areaName or "?") .. ":" .. math.floor(now() / 1800)
	local ev = {kind = "event", event = "invasion"}
	local seen = X.invasions[key]
	if seen ~= nil then
		if seen then
			X.credit(seen, ev, {player})
		end
		return
	end
	local res = X.add(ev, {player})
	X.invasions[key] = res and res.matched and res.chapter or false
end

function X.installHooks()
	local WC = ChaosWrapChain
	WC.wrap(ChaosRecords, "submit", "chronicle", onSubmit, log)
	WC.wrap(ChaosInvasion, "deliver", "chronicle", onInvasionDeliver, log)
end
-- the raid clear: once, at load (achievements.lua is loaded already; season_journey.lua wraps on top of us at its
-- startup and keeps its own check stable)
ChaosWrapChain.wrap(ChaosAchievements, "progress", "chronicle", onAchievementProgress, log)
X.installHooks()

-- ---------------------------------------------------------------- the season
function X.finalize(st)
	X.flush()
	local rows = K.recordRows(cfg, st, cfg.topRecorded)
	for _, r in ipairs(rows) do
		db.asyncQuery(string.format("INSERT IGNORE INTO `%s` (`season`, `chapter`, `place`, `player_id`, `name`, `points`, `recorded_at`) " ..
			"VALUES (%d, %d, %d, %d, %s, %d, %d)", T.record, st.season, r.chapter, r.place, r.guid, q(r.name), r.points, now()))
	end
	st.finishedAt = now()
	X.saveState(st)
	broadcast(function(lang)
		return K.closingText(cfg, st, lang)
	end)
	discord(K.discordSeasonRow(cfg, TXT, st, true))
	log(string.format("season %d finished: %d record rows", st.season, #rows))
	return rows
end

function X.startSeason(season, arc)
	local st = K.newState(cfg, arc, season.id, now())
	X.state = st
	X.idle = nil
	X.levels = {}
	X.dirty = true
	X.saveState(st)
	local tarc = TXT.arcs[arc]
	if tarc then
		broadcast(function(lang)
			return TXT.pick(tarc.title, lang) .. ": " .. TXT.pick(tarc.intro, lang)
		end)
		discord(K.discordSeasonRow(cfg, TXT, st, false))
	end
	log(string.format("season %d: the Chronicle (%s) begins", season.id, arc))
end

-- a season that ended while the server was down: its record is written now
function X.finishOld()
	local season = seasonNow()
	local id = season and season.id or -1
	for _, r in ipairs(Chaos.select(string.format("SELECT `season` FROM `%s` WHERE `finished_at` = 0 AND `season` <> %d", T.state, id),
		{{"season", "n"}})) do
		local st = X.loadState(r.season)
		if st then
			local keep = X.state
			X.state = st
			try("finalize " .. r.season, X.finalize, st)
			X.state = keep
		end
	end
end

-- the idle world: the last finished season's written chapters stay until the next season starts
function X.loadIdle()
	local row = Chaos.select(string.format("SELECT `season`, `arc`, `done` FROM `%s` WHERE `finished_at` > 0 ORDER BY `season` DESC LIMIT 1",
		T.state), {{"season", "n"}, {"arc", "s"}, {"done", "n"}})[1]
	X.idle = row and cfg.chapters[row.arc] and {season = row.season, arc = row.arc, done = row.done} or nil
end

function X.check()
	local season = seasonNow()
	local id = season and season.id or nil
	if X.state and X.state.season ~= id then
		local st = X.state
		try("finalize", X.finalize, st)
		X.state = nil
		X.idle = {season = st.season, arc = st.arc, done = K.doneCount(cfg, st)}
		X.loadRecord()
	end
	if id and not X.state then
		local arc = K.arcOf(cfg, id)
		if arc then
			local st = X.loadState(id)
			if st and (st.finishedAt or 0) == 0 then
				X.state = st
				X.idle = nil
				X.loadLevels(id)
			elseif not st then
				X.startSeason(season, arc)
			end
		end
	end
	X.applyWorld()
end

-- ---------------------------------------------------------------- the window
function X.payload(player)
	local st = X.state
	local opts = {now = now(), record = {}, tops = {}, mine = {}, areaReady = {}}
	local season = seasonNow()
	opts.seasonName = season and season.name or ""
	for _, area in ipairs(cfg.areas) do
		opts.areaReady[area.key] = areaReady(area)
	end
	if st then
		local guid = player:getGuid()
		for ci = 1, #K.chapters(cfg, st.arc) do
			opts.tops[ci] = topFor(ci, cfg.topShown)
			local e = st.contrib[ci][guid]
			opts.mine[ci] = e and e.points or 0
		end
	end
	for _, s in ipairs(X.record) do
		local copy = {season = s.season, name = s.name, title = s.title, chapters = {}}
		for _, c in ipairs(s.chapters) do
			local top = {}
			for _, e in ipairs(c.top) do
				if #top < (cfg.topShown or 5) then
					top[#top + 1] = {n = shown(e.guid) and e.n or HIDDEN, p = e.p}
				end
			end
			copy.chapters[#copy.chapters + 1] = {i = c.i, title = c.title, top = top}
		end
		opts.record[#opts.record + 1] = copy
	end
	return K.payload(cfg, TXT, st, opts)
end

function X.send(player)
	Chaos.sendChunked(player, OPCODE, json.encode({action = "state", data = X.payload(player)}))
end

local ext = CreatureEvent("ChaosChronicleExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local m = Chaos.decode(buffer)
	if not m or Chaos.limited(player, "chronicle." .. tostring(m.action), 300) then
		return
	end
	if m.action == "open" then
		X.watch[player:getId()] = true
		try("open", X.send, player)
	elseif m.action == "close" then
		X.watch[player:getId()] = nil
	end
end
ext:type("extendedopcode")
ext:register()

local advance = CreatureEvent("ChaosChronicleAdvance")
function advance.onAdvance(player, skill, oldLevel, newLevel)
	if skill ~= SKILL_LEVEL or not X.state or isStaff(player) then
		return true
	end
	for _, level in ipairs(K.levelsCrossed(cfg, X.state, oldLevel, newLevel)) do
		local key = player:getGuid() .. ":" .. level
		if not X.levels[key] then
			X.levels[key] = true
			db.asyncQuery(string.format("INSERT IGNORE INTO `%s` (`season`, `player_id`, `level`) VALUES (%d, %d, %d)", T.levels,
				X.state.season, player:getGuid(), level))
			try("level", X.add, {kind = "level", level = level}, {player})
		end
	end
	return true
end
advance:type("advance")
advance:register()

local login = CreatureEvent("ChaosChronicleLogin")
function login.onLogin(player)
	player:registerEvent("ChaosChronicleExtended")
	player:registerEvent("ChaosChronicleAdvance")
	local line = X.state and K.loginLine(cfg, TXT, X.state, langOf(player))
	if line then
		player:sendTextMessage(MESSAGE_EVENT_ORANGE or MESSAGE_EVENT_ADVANCE, line)
	end
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosChronicleLogout")
function logout.onLogout(player)
	X.watch[player:getId()] = nil
	return true
end
logout:type("logout")
logout:register()

local think = GlobalEvent("ChaosChronicleTick")
function think.onThink(interval)
	if not cfg.enabled then
		return true
	end
	X.installHooks() -- again after a /reload of a wrapped script
	try("check", X.check)
	try("flush", X.flush)
	if X.changed then
		X.changed = false
		sendAll()
	end
	return true
end
think:interval((cfg.tickSeconds or 60) * 1000)
think:register()

local startup = GlobalEvent("ChaosChronicleStartup")
function startup.onStartup()
	if not cfg.enabled then
		return true
	end
	for _, problem in ipairs(K.validate(cfg, TXT)) do
		log("config: " .. problem)
	end
	X.ensureTables()
	X.installHooks()
	try("finish old", X.finishOld)
	try("idle", X.loadIdle)
	try("record", X.loadRecord)
	try("check", X.check)
	local st = X.state
	log(st and string.format("season %d: chapter %d of %d open", st.season, st.chapter, #K.chapters(cfg, st.arc)) or
		"no Chronicle running")
	return true
end
startup:register()

local shutdown = GlobalEvent("ChaosChronicleShutdown")
function shutdown.onShutdown()
	try("flush", X.flush)
	return true
end
shutdown:register()

-- staff: /chronicle [status | world | complete | reset]
local talk = TalkAction("/chronicle")
function talk.onSay(player, words, param)
	if not player:getGroup():getAccess() then
		return true
	end
	local cmd = tostring(param or ""):match("^%s*(%S*)") or ""
	local function reply(text)
		player:sendTextMessage(MESSAGE_INFO_DESCR, "[chronicle] " .. text)
	end
	local st = X.state
	if cmd == "" or cmd == "status" then
		if not st then
			reply("no Chronicle running" .. (X.idle and string.format(" (season %d's world stays: %d chapters)", X.idle.season, X.idle.done) or ""))
			return false
		end
		reply(string.format("season %d, arc %s: chapter %d of %d (%s%%)", st.season, st.arc, st.chapter, #K.chapters(cfg, st.arc),
			tostring(K.chapterPct(cfg, st, st.chapter))))
		for _, area in ipairs(cfg.areas) do
			reply(string.format("%s: %s, %s", area.name, X.world.open[area.key] and "open" or "closed",
				areaReady(area) and "placed" or "NOT PLACED (chronicle_config.lua areas at / gate)"))
		end
	elseif cmd == "world" then
		X.applyWorld()
		reply("world applied")
	elseif cmd == "complete" or cmd == "reset" then
		if player:getGroup():getId() < 5 then
			reply("needs group 5")
			return false
		end
		if ChaosAdmin and ChaosAdmin.log then
			pcall(ChaosAdmin.log, player, "chronicle." .. cmd, "", {}, "ok", "")
		end
		if cmd == "complete" and st and not K.allDone(cfg, st) then
			local ci = st.chapter
			for gi, g in ipairs(K.chapters(cfg, st.arc)[ci].goals) do
				st.progress[ci][gi] = g.target
			end
			st.doneAt[ci] = now()
			st.chapter = ci + 1
			X.dirty = true
			X.chapterWritten(ci)
			reply("chapter " .. ci .. " written")
		elseif cmd == "reset" then
			X.idle = nil
			if st then
				X.state = K.newState(cfg, st.arc, st.season, now())
				X.dirty = true
				db.asyncQuery(string.format("DELETE FROM `%s` WHERE `season` = %d", T.contrib, st.season))
				db.asyncQuery(string.format("DELETE FROM `%s` WHERE `season` = %d", T.levels, st.season))
				X.levels = {}
				X.saveState(X.state)
			end
			X.applyWorld()
			reply("the Chronicle of this season starts again; the world is reset")
		end
	end
	return false
end
talk:separator(" ")
talk:register()
