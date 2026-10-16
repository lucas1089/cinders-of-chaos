-- The Capital Memorial: a plaza in the capital with statues and memorial stones for the season's realm firsts, its top
-- records and the fallen Hardcore characters, each only with the character's consent (client game_chronicle Memorial
-- tab; extended opcode ChaosOpcodes.chronicle = 171, actions mem / memset, shared with chronicle.lua; website
-- page.php?plugin=chaos&p=memorial with the past seasons). Numbers: memorial_config.lua; pure logic: memorial_core.lua
-- (tests: server/tests/memorial_test.lua); the plaza's plan: server/tools/areaplan/chronicle/capital_memorial.json.
-- Overview: server/README.md "The Capital Memorial". Tables: chaos_memorial_optin, chaos_memorial_entries
-- (server/sql/chaos_memorial.sql; also created at startup). No player storages.
--
-- Sources (read only): chaos_records_firsts and chaos_records (records.lua: the season's realm firsts and the best of
-- each board), chaos_season_modes (season_modes.lua: the Hardcore falls of the season). Every refreshSeconds the
-- season's rows are written again; the rows of past seasons stay (the website's archive). The plaza's items are placed
-- at runtime on the plan's slots (memorial_config.lua plaza.at + slots), each with its entry as the look text; with
-- more entries than statues the pages turn every rotateSeconds. The way in: a portal (plaza.portal, action id
-- aid.portal) in the upper hall of the capital's temple leads to the plaza's arrival.
-- Consent (chaos_memorial_optin; memorial_core.lua M.choiceOf): records and realm firsts are shown unless the character
-- turned them off; a Hardcore fall only after a yes. ChaosSeason.modesFall is wrapped (once, ChaosWrapChain): the fall
-- asks at the next login (a modal window; the client's Memorial tab shows the question too). Turning a choice off hides the rows of every season
-- at once (column `shown`); nothing else reads them.
--
-- Protocol (JSON {action, data} on the chronicle opcode):
--   client -> server  mem | memset {records = bool, fallen = bool}
--   server -> client  mem {...} (memorial_core.lua M.payload; `ask` while a fall waits for its answer: the client's
--                     Memorial tab answers it too, beside the modal window of the next login)
-- Staff: /memorial [status | refresh]
-- Lua 5.1 / LuaJIT.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
dofile("data/scripts/chaos/memorial_core.lua")
if not ChaosCityPortals then
	dofile("data/scripts/chaos/cityportals.lua")
end
if not (ChaosChronicleCore and ChaosChronicleCore.ensureWrapChain) then
	dofile("data/scripts/chaos/chronicle_core.lua")
end
ChaosChronicleCore.ensureWrapChain()

Chaos.memorialConfig = dofile("data/scripts/chaos/memorial_config.lua")
local cfg = Chaos.memorialConfig
-- server/README.md "Extended opcodes in use": 171 (chaos_constants.lua names it too once its line is in)
ChaosOpcodes.chronicle = ChaosOpcodes.chronicle or cfg.opcode
local M = ChaosMemorialCore
local OPCODE = ChaosOpcodes.chronicle or cfg.opcode
local T = cfg.tables

ChaosMemorial = ChaosMemorial or {}
local X = ChaosMemorial
X.rows = X.rows or {} -- guid -> {records, fallen, asked} (every row of chaos_memorial_optin)
X.entries = X.entries or {} -- the season's entries (M shape)
X.seasonKey = X.seasonKey or nil
X.seasonName = X.seasonName or ""
X.page = X.page or 0
X.refreshedAt = X.refreshedAt or 0

local function now()
	return os.time()
end

local function log(text)
	print("[Chaos memorial] " .. text)
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

local function seasonNow()
	local S = ChaosSeason
	if not (S and S.current) then
		return nil
	end
	local ok, s = pcall(S.current)
	return ok and type(s) == "table" and s or nil
end

local function className(voc)
	if Vocation then
		local ok, v = pcall(Vocation, tonumber(voc) or 0)
		if ok and v and v.getName then
			local ok2, name = pcall(v.getName, v)
			if ok2 and type(name) == "string" then
				return name
			end
		end
	end
	return ""
end

-- ---------------------------------------------------------------- tables and choices
function X.ensureTables()
	db.query(string.format("CREATE TABLE IF NOT EXISTS `%s` (`player_id` int(11) NOT NULL, `records` tinyint(1) NOT NULL DEFAULT 1, " ..
		"`fallen` tinyint(1) NOT NULL DEFAULT 0, `asked` tinyint(1) NOT NULL DEFAULT 1, `updated_at` int(10) unsigned NOT NULL DEFAULT 0, " ..
		"PRIMARY KEY (`player_id`), FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE) ENGINE=InnoDB " ..
		"DEFAULT CHARSET=utf8", T.optin))
	db.query(string.format("CREATE TABLE IF NOT EXISTS `%s` (`season` varchar(16) NOT NULL, `kind` varchar(8) NOT NULL, " ..
		"`entry_key` varchar(64) NOT NULL, `player_id` int(11) NOT NULL, `name` varchar(255) NOT NULL DEFAULT '', " ..
		"`title` varchar(96) NOT NULL DEFAULT '', `detail` varchar(160) NOT NULL DEFAULT '', `level` int(10) unsigned NOT NULL DEFAULT 0, " ..
		"`class` varchar(32) NOT NULL DEFAULT '', `at` int(10) unsigned NOT NULL DEFAULT 0, `ord` smallint(5) unsigned NOT NULL DEFAULT 0, " ..
		"`shown` tinyint(1) NOT NULL DEFAULT 0, `season_name` varchar(64) NOT NULL DEFAULT '', PRIMARY KEY (`season`, `kind`, `entry_key`, `player_id`), " ..
		"KEY `player` (`player_id`), FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE) ENGINE=InnoDB " ..
		"DEFAULT CHARSET=utf8", T.entries))
end

function X.loadChoices()
	local rows = {}
	for _, r in ipairs(Chaos.select(string.format("SELECT `player_id`, `records`, `fallen`, `asked` FROM `%s`", T.optin),
		{{"player_id", "n"}, {"records", "n"}, {"fallen", "n"}, {"asked", "n"}})) do
		rows[r.player_id] = {records = r.records, fallen = r.fallen, asked = r.asked}
	end
	X.rows = rows
end

function X.choiceOf(guid)
	return M.choiceOf(X.rows[tonumber(guid) or 0], cfg.defaults)
end

-- chronicle.lua: may this character's name stand in the top lists?
function X.showsRecords(guid)
	return X.choiceOf(guid).records
end

local function writeChoice(guid, row)
	db.asyncQuery(string.format("INSERT INTO `%s` (`player_id`, `records`, `fallen`, `asked`, `updated_at`) VALUES (%d, %d, %d, %d, %d) " ..
		"ON DUPLICATE KEY UPDATE `records` = VALUES(`records`), `fallen` = VALUES(`fallen`), `asked` = VALUES(`asked`), " ..
		"`updated_at` = VALUES(`updated_at`)", T.optin, guid, row.records, row.fallen, row.asked, now()))
end

-- the character's choice; every season's rows follow at once
function X.setChoice(guid, records, fallen)
	guid = math.floor(tonumber(guid) or 0)
	local old = X.rows[guid] or {}
	local row = {records = records and 1 or 0, fallen = fallen and 1 or 0, asked = 1}
	X.rows[guid] = row
	writeChoice(guid, row)
	db.asyncQuery(string.format("UPDATE `%s` SET `shown` = %d WHERE `player_id` = %d AND `kind` IN ('first', 'record')", T.entries,
		row.records, guid))
	db.asyncQuery(string.format("UPDATE `%s` SET `shown` = %d WHERE `player_id` = %d AND `kind` = 'fallen'", T.entries, row.fallen, guid))
	local changed = false
	for _, e in ipairs(X.entries) do
		if e.guid == guid then
			local s = M.shownFor(e.kind, X.choiceOf(guid))
			changed = changed or s ~= e.shown
			e.shown = s
		end
	end
	if changed or old.records ~= row.records or old.fallen ~= row.fallen then
		try("place", X.placePlaza, true)
	end
	return row
end

-- a Hardcore fall: the question waits for the next login (the modal window; the client's Memorial tab shows it too)
function X.onFall(guid)
	guid = math.floor(tonumber(guid) or 0)
	local row = X.rows[guid] or {records = cfg.defaults.records ~= false and 1 or 0, fallen = cfg.defaults.fallen and 1 or 0}
	row.asked = 0
	X.rows[guid] = row
	writeChoice(guid, row)
	X.refreshedAt = 0 -- the next tick reads the season again
end

-- ---------------------------------------------------------------- the entries
local function recordsTables()
	local rc = Chaos.recordsConfig
	return rc and rc.tables
end

local function boardDefs()
	local defs = {}
	local R = ChaosRecords
	for _, key in ipairs(cfg.boards) do
		local b = R and R.byKey and R.byKey[key]
		local tpl
		for _, t in ipairs(Chaos.recordsConfig and Chaos.recordsConfig.boards or {}) do
			if t.key == key then
				tpl = t
			end
		end
		if b or tpl then
			local name = (b and b.name) or tpl.name
			local variantRank = {}
			for i, v in ipairs(b and b.variants or {}) do
				variantRank[v.key] = i
			end
			defs[key] = {mode = (b and b.mode) or tpl.mode, format = (b and b.format) or tpl.format, variantRank = variantRank,
				title = function(variant)
					local v = b and b.variantByKey and b.variantByKey[variant]
					if variant == "-" or not variant then
						return name
					end
					return name .. ", " .. (v and v.name or variant)
				end}
		end
	end
	return defs
end

-- the people of a list of guids: {guid -> {name, class, level, staff}}
local function people(guids)
	local out, list = {}, {}
	for g in pairs(guids) do
		list[#list + 1] = math.floor(g)
	end
	table.sort(list)
	for i = 1, #list, 200 do
		local part = {}
		for k = i, math.min(#list, i + 199) do
			part[#part + 1] = list[k]
		end
		for _, r in ipairs(Chaos.select(string.format("SELECT `id`, `name`, `vocation`, `level`, `group_id` FROM `players` WHERE `id` IN (%s)",
			table.concat(part, ",")), {{"id", "n"}, {"name", "s"}, {"vocation", "n"}, {"level", "n"}, {"group_id", "n"}})) do
			out[r.id] = {name = r.name, class = className(r.vocation), level = r.level, staff = r.group_id >= (cfg.staffGroup or 4)}
		end
	end
	return out
end

function X.build(season, key)
	local entries = {}
	local rt = recordsTables()
	if rt then
		local rows = Chaos.select(string.format("SELECT `target`, `board`, `name`, `guids`, `value`, `at` FROM `%s` WHERE `season` = %s",
			rt.firsts, q(key)), {{"target", "s"}, {"board", "s"}, {"name", "s"}, {"guids", "s"}, {"value", "n"}, {"at", "n"}})
		local guids = {}
		for _, r in ipairs(rows) do
			for g in r.guids:gmatch("%d+") do
				guids[tonumber(g)] = true
			end
		end
		local byKey = ChaosRecords and ChaosRecords.byKey or {}
		for _, e in ipairs(M.firstEntries(rows, people(guids), function(r)
			local b = byKey[r.board]
			return b and r.name ~= b.name and (r.name .. " (" .. b.name .. ")") or r.name
		end)) do
			entries[#entries + 1] = e
		end
		local defs = boardDefs()
		local likes = {}
		for k in pairs(defs) do
			likes[#likes + 1] = "r.`slot` LIKE " .. q(k .. "|%")
		end
		table.sort(likes)
		if #likes > 0 then
			local recs = Chaos.select(string.format("SELECT r.`slot`, r.`player_id`, r.`value`, r.`at`, p.`name`, p.`vocation`, p.`level` " ..
				"FROM `%s` r JOIN `players` p ON p.`id` = r.`player_id` WHERE r.`period` = %s AND p.`group_id` < %d AND (%s)%s", rt.best,
				q(key), cfg.staffGroup or 4, table.concat(likes, " OR "),
				ChaosAntibot and ChaosAntibot.heldClause and ChaosAntibot.heldClause("p.") or ""),
				{{"slot", "s"}, {"player_id", "n"}, {"value", "n"}, {"at", "n"}, {"name", "s"}, {"vocation", "n"}, {"level", "n"}})
			local rows2 = {}
			for _, r in ipairs(recs) do
				rows2[#rows2 + 1] = {slot = r.slot, guid = r.player_id, value = r.value, at = r.at, name = r.name,
					class = className(r.vocation), level = r.level}
			end
			for _, e in ipairs(M.recordEntries(rows2, defs, cfg.boards)) do
				entries[#entries + 1] = e
			end
		end
	end
	local sc = Chaos.seasonConfig
	local modesTable = sc and sc.modes and sc.modes.table
	if season and modesTable then
		local rows = {}
		for _, r in ipairs(Chaos.select(string.format("SELECT sm.`player_id`, p.`name`, p.`vocation`, sm.`fallen_level`, sm.`fallen_cause`, " ..
			"sm.`fallen_at` FROM `%s` sm JOIN `players` p ON p.`id` = sm.`player_id` WHERE sm.`season` = %d AND sm.`fallen_at` > 0 " ..
			"AND p.`group_id` < %d", modesTable, season.id, cfg.staffGroup or 4), {{"player_id", "n"}, {"name", "s"}, {"vocation", "n"},
			{"fallen_level", "n"}, {"fallen_cause", "s"}, {"fallen_at", "n"}})) do
			rows[#rows + 1] = {guid = r.player_id, name = r.name, class = className(r.vocation), level = r.fallen_level,
				cause = r.fallen_cause, at = r.fallen_at}
		end
		for _, e in ipairs(M.fallenEntries(rows)) do
			entries[#entries + 1] = e
		end
	end
	return M.applyChoices(entries, X.choiceOf, cfg.maxEntries)
end

function X.write(key, name, entries)
	db.asyncQuery(string.format("DELETE FROM `%s` WHERE `season` = %s", T.entries, q(key)))
	local values = {}
	local function flushValues()
		if #values > 0 then
			db.asyncQuery(string.format("INSERT IGNORE INTO `%s` (`season`, `kind`, `entry_key`, `player_id`, `name`, `title`, `detail`, " ..
				"`level`, `class`, `at`, `ord`, `shown`, `season_name`) VALUES %s", T.entries, table.concat(values, ", ")))
			values = {}
		end
	end
	for _, e in ipairs(entries) do
		values[#values + 1] = string.format("(%s, %s, %s, %d, %s, %s, %s, %d, %s, %d, %d, %d, %s)", q(key), q(e.kind), q(M.cut(e.key, 64)),
			e.guid, q(e.name), q(M.cut(e.title, 96)), q(M.cut(e.detail, 160)), math.floor(tonumber(e.level) or 0), q(M.cut(e.class, 32)),
			math.floor(tonumber(e.at) or 0), math.min(65535, e.ord or 0), e.shown and 1 or 0, q(M.cut(name, 64)))
		if #values >= 50 then
			flushValues()
		end
	end
	flushValues()
end

function X.refresh()
	local season = seasonNow()
	local key = M.seasonKey(season, now())
	X.loadChoices()
	local entries = X.build(season, key)
	X.seasonKey, X.seasonName = key, M.seasonName(key, season)
	X.entries = entries
	X.write(key, X.seasonName, entries)
	X.refreshedAt = now()
	try("place", X.placePlaza, true)
	return #entries
end

-- ---------------------------------------------------------------- the plaza
local function P(t)
	return Position(t.x, t.y, t.z)
end

local function itemAt(pos, aid)
	local tile = Tile(P(pos))
	for _, it in ipairs(tile and tile:getItems() or {}) do
		if it:getActionId() == aid then
			return it, tile
		end
	end
	return nil, tile
end

local function put(kind, slot, pos, text)
	local aid = cfg.aid[kind]
	local it, tile = itemAt(pos, aid)
	if not text then
		if it then
			it:remove()
		end
		return
	end
	if not it then
		if not tile or not tile:getGround() or tile:getTopCreature() then
			return -- no floor yet (the plaza is not on the map) or someone stands there: the next tick tries again
		end
		local ids = cfg.items[kind]
		local id = type(ids) == "table" and ids[(slot - 1) % #ids + 1] or ids
		it = Game.createItem(id, 1, P(pos))
		if not it then
			return
		end
		it:setActionId(aid)
	end
	if ITEM_ATTRIBUTE_DESCRIPTION then
		it:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, text)
	end
end

-- every statue, stone and the Memorial stone of the plaza for the page now (force: also when the page did not turn)
function X.placePlaza(force)
	local at = cfg.plaza and cfg.plaza.at
	if type(at) ~= "table" then
		return false
	end
	local plan, page, pages = M.plan(cfg, X.entries, X.seasonName, now())
	if not force and page == X.page then
		return false
	end
	X.page = page
	for _, p in ipairs(plan) do
		local off = p.kind == "stone" and cfg.slots.stone or cfg.slots[p.kind][p.slot]
		local pos = M.slotPos(at, off)
		if pos then
			put(p.kind, p.slot, pos, p.text)
		end
	end
	return true, page, pages
end

-- the way in: a portal in the capital (plaza.portal, action id aid.portal) to the plaza's arrival (plaza.at +
-- plaza.arrival). Placed at startup and checked every tick (found again after a /reload); nothing until both are set.
function X.arrival()
	local pl = cfg.plaza or {}
	return M.slotPos(pl.at, pl.arrival)
end

function X.placePortal()
	local pl = cfg.plaza or {}
	if not X.arrival() then
		return false
	end
	if type(pl.portal) ~= "table" then
		-- the Memorial Portal of each town of portalTowns (cityportals.lua: the Hall of Services' portal room, else beside
		-- the temple; look text and effect by cityportals_fx.lua)
		local _, positions = ChaosCityPortals.place({kind = "memorial", aid = cfg.aid.portal, item = cfg.portalItem or 1387,
			towns = cfg.portalTowns or {2}})
		return #positions > 0
	end
	local it, tile = itemAt(pl.portal, cfg.aid.portal)
	if it then
		ChaosCityPortals.register("memorial", cfg.aid.portal, pl.portal)
		return true
	end
	if not tile or not tile:getGround() then
		log(string.format("no tile for the portal at %d,%d,%d (memorial_config.lua plaza.portal)", pl.portal.x, pl.portal.y,
			pl.portal.z))
		return false
	end
	it = Game.createItem(cfg.portalItem or 1387, 1, P(pl.portal))
	if not it then
		return false
	end
	it:setActionId(cfg.aid.portal)
	ChaosCityPortals.register("memorial", cfg.aid.portal, pl.portal) -- look text and effect (cityportals_fx.lua)
	return true
end

local step = MoveEvent()
step:type("stepin")
function step.onStepIn(creature, item, position, fromPosition)
	local player = creature and creature:getPlayer()
	if not player then
		return true
	end
	local to = X.arrival()
	if not to then
		player:teleportTo(fromPosition, true)
		return true
	end
	player:teleportTo(P(to))
	player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "%s. The portal beside you leads back to the temple.",
		"The Ember Memorial"))
	return true
end
step:aid(cfg.aid.portal)
step:register()

-- ---------------------------------------------------------------- the window and the question
function X.payload(player)
	local guid = player:getGuid()
	local row = X.rows[guid]
	return M.payload(X.seasonName, X.choiceOf(guid), row and row.asked == 0 or nil, X.entries)
end

function X.send(player)
	Chaos.sendChunked(player, OPCODE, json.encode({action = "mem", data = X.payload(player)}))
end

local function fallOf(guid)
	local S = ChaosSeason
	local f = S and S.fallenByGuid and S.fallenByGuid[guid]
	if f then
		return f.level, f.cause
	end
	return 0, "fallen"
end

local function langOf(player)
	if Chaos.lang then
		local ok, l = pcall(Chaos.lang, player)
		if ok and type(l) == "string" and l:sub(1, 2) == "pt" then
			return "pt"
		end
	end
	return "en"
end

function X.ask(player)
	local guid = player:getGuid()
	local level, cause = fallOf(guid)
	local q = M.ask(player:getName(), level, cause, langOf(player))
	if ModalWindow then
		local w = ModalWindow(cfg.modalId, q.title, q.text)
		w:addButton(1, q.yes)
		w:addButton(2, q.no)
		w:setDefaultEnterButton(1)
		w:setDefaultEscapeButton(2)
		w:sendToPlayer(player)
	end
end

local ext = CreatureEvent("ChaosMemorialExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local m = Chaos.decode(buffer)
	if not m or (m.action ~= "mem" and m.action ~= "memset") then
		return
	end
	if Chaos.limited(player, "memorial." .. m.action, m.action == "memset" and 1000 or 300) then
		return
	end
	local d = type(m.data) == "table" and m.data or {}
	if m.action == "memset" then
		if isStaff(player) or type(d.records) ~= "boolean" or type(d.fallen) ~= "boolean" then
			return
		end
		X.setChoice(player:getGuid(), d.records, d.fallen)
		player:sendTextMessage(MESSAGE_INFO_DESCR or MESSAGE_EVENT_ADVANCE, M.savedText("saved", langOf(player)))
	end
	try("send", X.send, player)
end
ext:type("extendedopcode")
ext:register()

local modal = CreatureEvent("ChaosMemorialModal")
function modal.onModalWindow(player, modalWindowId, buttonId, choiceId)
	if modalWindowId ~= cfg.modalId then
		return true
	end
	local guid = player:getGuid()
	local c = X.choiceOf(guid)
	X.setChoice(guid, c.records, buttonId == 1)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, M.savedText(buttonId == 1 and "yes" or "no", langOf(player)))
	return true
end
modal:type("modalwindow")
modal:register()

local login = CreatureEvent("ChaosMemorialLogin")
function login.onLogin(player)
	player:registerEvent("ChaosMemorialExtended")
	player:registerEvent("ChaosMemorialModal")
	local row = X.rows[player:getGuid()]
	if row and row.asked == 0 and not isStaff(player) then
		addEvent(function(cid)
			local p = Player(cid)
			if p then
				try("ask", X.ask, p)
			end
		end, 3000, player:getId())
	end
	return true
end
login:type("login")
login:register()

-- ---------------------------------------------------------------- hooks and ticks
local function onFall(res, player)
	if player and player.getGuid then
		X.onFall(player:getGuid())
	end
end

function X.installHooks()
	ChaosWrapChain.wrap(ChaosSeason, "modesFall", "memorial", onFall, log)
end
X.installHooks()

local think = GlobalEvent("ChaosMemorialTick")
function think.onThink(interval)
	if not cfg.enabled then
		return true
	end
	X.installHooks()
	try("portal", X.placePortal)
	if now() - X.refreshedAt >= (cfg.refreshSeconds or 600) then
		try("refresh", X.refresh)
	else
		try("rotate", X.placePlaza, false)
	end
	return true
end
think:interval((cfg.tickSeconds or 60) * 1000)
think:register()

local startup = GlobalEvent("ChaosMemorialStartup")
function startup.onStartup()
	if not cfg.enabled then
		return true
	end
	X.ensureTables()
	X.installHooks()
	local n = try("refresh", X.refresh)
	try("portal", X.placePortal)
	log(string.format("%s entries for %s%s", tostring(n or 0), tostring(X.seasonName),
		type(cfg.plaza.at) == "table" and "" or "; the plaza is not placed yet (memorial_config.lua plaza.at)"))
	return true
end
startup:register()

-- staff: /memorial [status | refresh]
local talk = TalkAction("/memorial")
function talk.onSay(player, words, param)
	if not player:getGroup():getAccess() then
		return true
	end
	local cmd = tostring(param or ""):match("^%s*(%S*)") or ""
	local function reply(text)
		player:sendTextMessage(MESSAGE_INFO_DESCR, "[memorial] " .. text)
	end
	if cmd == "refresh" then
		reply(string.format("%d entries", try("refresh", X.refresh) or 0))
	else
		local counts = {}
		for _, kind in ipairs(M.KINDS) do
			counts[#counts + 1] = kind .. " " .. #M.displayList(X.entries, kind)
		end
		reply(string.format("%s (%s): %s; plaza %s, page %d", X.seasonName, tostring(X.seasonKey), table.concat(counts, ", "),
			type(cfg.plaza.at) == "table" and "placed" or "NOT PLACED", X.page or 0))
	end
	return false
end
talk:separator(" ")
talk:register()
