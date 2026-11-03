-- New player survey (O374; server/README.md "New player funnel and survey (O374)"; rules in survey_core.lua, numbers in
-- survey_config.lua; tests/survey_test.lua). At level 20 and at level 50 a small window (client game_chaossurvey) asks
-- "What confused you so far?" (free text, 200 letters), "How fun is it?" (1-5) and "Would you recommend it?" (yes / no).
-- Once per account and stage: an answer or a skip writes the row (chaos_survey, unique account + stage) and the window
-- never comes back for that account. A logout before either offers it again at the next login while the level is in
-- the stage's window. The owner reads the answers with chaos-ctl.sh survey (admin app Painel > Novos jogadores).
--
-- Protocol (JSON {action, data}) on ChaosOpcodes.survey = 122:
--   server -> client  open {s, max}        s = the stage (level), max = letters of the text
--                     done {s}             the row was written (the client thanks and closes)
--   client -> server  answer {s, fun, rec, text} | skip {s}
-- Only the stage the server opened is accepted; one message per requestMs per character, perMinute rows per minute for
-- the server. Staff and tester bots are never asked.
-- Assumed engine API (TFS 1.4.2): CreatureEvent login/logout/advance/extendedopcode, GlobalEvent startup/think,
-- Player:getAccountId/getGuid/getLevel/getGroup/getStorageValue/setStorageValue, db.query/asyncQuery/storeQuery/escapeString.
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosSurveyCore or not ChaosSurveyCore.parse then
	dofile("data/scripts/chaos/survey_core.lua")
end

ChaosSurvey = ChaosSurvey or {}
local V = ChaosSurvey
local S = ChaosSurveyCore
local cfg = dofile("data/scripts/chaos/survey_config.lua")
V.cfg = cfg
local OPCODE = (ChaosOpcodes and ChaosOpcodes.survey) or 122
local T = (Chaos.tables and Chaos.tables.survey) or "chaos_survey"

V.pending = V.pending or {} -- player id -> {stage, at}: to open when out of combat
V.offered = V.offered or {} -- player id -> the stage of the open window
V.sessions = V.sessions or {} -- player id -> {at = login time, base = onlinetime at login or nil}
V.global = V.global or {}

local function log(text)
	print("[Chaos survey] " .. text)
end

local function try(label, fn, ...)
	local ok, a, b = pcall(fn, ...)
	if not ok then
		log(label .. ": " .. tostring(a))
		return nil
	end
	return a, b
end

local tableReady
local function ensureTable()
	if tableReady == nil then
		tableReady = db.query(S.createSql(T)) and true or false
	end
	return tableReady
end

local function counted(player)
	if Chaos.isTester(player) then
		return false
	end
	local ok, g = pcall(function() return player:getGroup():getId() end)
	return (ok and tonumber(g) or 0) <= (cfg.maxGroupId or 1)
end

local function mask(player)
	local v = player:getStorageValue(cfg.storage)
	return (v and v > 0) and v or 0
end

local function markStage(player, stage)
	local i = S.stageIndex(stage, cfg)
	if i then
		local m = mask(player)
		local nm = S.setBit(m, i)
		if nm ~= m then
			player:setStorageValue(cfg.storage, nm)
		end
	end
end

-- the stages this account already has a row for, written into the character's mask
local function syncFromDb(player)
	if not ensureTable() then
		return nil
	end
	local rows = Chaos.select(S.stagesSql(T, player:getAccountId()), {{"stage", "n"}})
	local stages = {}
	for _, r in ipairs(rows) do
		stages[#stages + 1] = r.stage
	end
	local m = mask(player)
	local nm = S.maskFromStages(m, stages, cfg)
	if nm ~= m then
		player:setStorageValue(cfg.storage, nm)
	end
	return nm
end

local function queue(player, stage)
	V.pending[player:getId()] = {stage = stage, at = os.time() + (cfg.delaySeconds or 0)}
end

function V.onLogin(player)
	player:registerEvent("ChaosSurveyAdvance")
	player:registerEvent("ChaosSurveyExtended")
	player:registerEvent("ChaosSurveyLogout")
	local id = player:getId()
	V.pending[id], V.offered[id] = nil, nil
	V.sessions[id] = {at = os.time()}
	if not cfg.enabled or not counted(player) then
		return
	end
	if not S.needsLookup(player:getLevel(), mask(player), cfg) then
		return
	end
	local m = syncFromDb(player)
	local stage = m and S.dueAtLogin(player:getLevel(), m, cfg)
	if stage then
		queue(player, stage)
	end
end

function V.onAdvance(player, oldLevel, newLevel)
	if not cfg.enabled or not counted(player) then
		return
	end
	local stage = S.dueAtAdvance(oldLevel, newLevel, mask(player), cfg)
	if not stage then
		return
	end
	local m = syncFromDb(player)
	if m and S.dueAtAdvance(oldLevel, newLevel, m, cfg) == stage then
		queue(player, stage)
	end
end

function V.onLogout(player)
	local id = player:getId()
	V.pending[id], V.offered[id], V.sessions[id] = nil, nil, nil
end

-- the open windows: out of combat, after the delay
function V.tick(now)
	now = now or os.time()
	for id, p in pairs(V.pending) do
		local player = Player(id)
		if not player then
			V.pending[id] = nil
		elseif now >= p.at and not Chaos.inCombat(player) then
			V.pending[id] = nil
			V.offered[id] = p.stage
			Chaos.send(player, OPCODE, "open", {s = p.stage, max = cfg.textMax})
		end
	end
end

local function playedMinutes(player)
	local s = V.sessions[player:getId()]
	if s and s.base == nil then
		local row = Chaos.select(string.format("SELECT `onlinetime` AS `t` FROM `players` WHERE `id` = %d", player:getGuid()),
			{{"t", "n"}})[1]
		s.base = row and row.t or 0
	end
	local base = s and s.base or 0
	local since = s and (os.time() - s.at) or 0
	return math.floor((base + since) / 60)
end

-- an answer or a skip from the client
function V.receive(player, msg)
	if type(msg) ~= "table" then
		return false
	end
	if ChaosRateLimit and not ChaosRateLimit.allow(player, "survey", cfg.requestMs or 2000) then
		return false
	end
	local id = player:getId()
	local row = S.parse(msg.action, msg.data, V.offered[id], cfg)
	if not row then
		return false
	end
	if not ensureTable() or not S.allowGlobal(V.global, os.time(), cfg) then
		return false
	end
	V.offered[id] = nil
	db.asyncQuery(S.insertSql(T, player:getAccountId(), row, player:getLevel(), playedMinutes(player), os.time(),
		db.escapeString))
	markStage(player, row.stage)
	Chaos.send(player, OPCODE, "done", {s = row.stage})
	return true
end

-- ---------------------------------------------------------------- events
local login = CreatureEvent("ChaosSurveyLogin")
function login.onLogin(player)
	try("login", V.onLogin, player)
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosSurveyLogout")
function logout.onLogout(player)
	try("logout", V.onLogout, player)
	return true
end
logout:type("logout")
logout:register()

local advance = CreatureEvent("ChaosSurveyAdvance")
function advance.onAdvance(player, skill, oldLevel, newLevel)
	if skill == SKILL_LEVEL then
		try("advance", V.onAdvance, player, oldLevel, newLevel)
	end
	return true
end
advance:type("advance")
advance:register()

local ext = CreatureEvent("ChaosSurveyExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	try("opcode", V.receive, player, Chaos.decode(buffer))
end
ext:type("extendedopcode")
ext:register()

local startup = GlobalEvent("ChaosSurveyStartup")
function startup.onStartup()
	ensureTable()
	return true
end
startup:type("startup")
startup:register()

local think = GlobalEvent("ChaosSurveyThink")
function think.onThink(interval)
	if cfg.enabled then
		try("tick", V.tick)
	end
	return true
end
think:interval((cfg.checkSeconds or 5) * 1000)
think:register()
