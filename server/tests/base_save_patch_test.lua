-- Run from the server/ folder: luajit tests/base_save_patch_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- tools/patch_base_save.py on copies of the stock lines it changes (written here), then the patched scripts run
-- against a mocked engine:
--   save.lua           the three warnings keep their text and timing (5 min, +2 min, +2 min, +1 min save); the save is
--                      Game.saveIncremental() (saveServer() without the engine patch); the game state is never set
--   login / logout     the outfit UPDATE runs only when the columns differ from what the login read
--   player_history     the logout's history row only when what it records changed since the login; deaths unchanged
-- and: a second run changes nothing, --dry-run writes nothing, a file without the stock lines is an error.
local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end

local python = io.popen and io.popen("python3 -V 2>/dev/null")
local hasPython = python and (python:read("*a") or ""):find("Python 3")
if python then
	python:close()
end
if not hasPython then
	print("base_save_patch_test: python3 not found, skipped")
	return
end

local function readFile(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local s = f:read("*a")
	f:close()
	return s
end
local function writeFile(path, text)
	local f = assert(io.open(path, "wb"))
	f:write(text)
	f:close()
end
local function sh(cmd)
	local h = io.popen(cmd .. " 2>&1")
	local out = h:read("*a")
	h:close()
	return out
end

local root = os.tmpname()
os.remove(root)
local data = root .. "/data"
os.execute("mkdir -p '" .. data .. "/globalevents/scripts' '" .. data .. "/creaturescripts/scripts' '" .. data
	.. "/scripts/customs/znote'")

-- the stock lines (as the base server has them; the rest of each file trimmed)
local SAVE = [[
local shutdownAtServerSave = false
local cleanMapAtServerSave = false

local function serverSave()
    if shutdownAtServerSave then
        Game.setGameState(GAME_STATE_SHUTDOWN)
    end

    if cleanMapAtServerSave then
        cleanMap()
    end

    saveServer()
    Game.setGameState(GAME_STATE_NORMAL)
end

local function secondServerSaveWarning()
    broadcastMessage("Server is saving game in one minute, you can continue playing.", MESSAGE_STATUS_WARNING)
    addEvent(serverSave, 60000)
end

local function firstServerSaveWarning()
    broadcastMessage("Server is saving game in 3 minutes, you can continue playing.", MESSAGE_STATUS_WARNING)
    addEvent(secondServerSaveWarning, 120000)
end

function onThink(interval)
    broadcastMessage("Server is saving game in 5 minutes, you can continue playing.", MESSAGE_STATUS_WARNING)
    addEvent(firstServerSaveWarning, 120000)
    return not shutdownAtServerSave
end]]

local LOGIN = [[
function onLogin(player)
	local playerId = player:getGuid()
	local resultId = db.storeQuery("SELECT wings_id, shader_id, aura_id FROM players WHERE id = " .. playerId)
    if resultId ~= false then
        local wingsId = result.getDataInt(resultId, "wings_id")
        local shaderId = result.getDataInt(resultId, "shader_id")
        local auraId = result.getDataInt(resultId, "aura_id")
        result.free(resultId)

        local outfit = player:getOutfit()
        outfit.lookWings = wingsId or outfit.lookWings --check wings
        outfit.lookShader = shaderId or outfit.lookShader -- check lookShader
        outfit.lookAura = auraId or outfit.lookAura     -- check lookAura
        player:setOutfit(outfit)
    end
	return true
end
]]

local LOGOUT = [[
function onLogout(player)
	local playerId = player:getGuid() -- get playerid
    local outfit = player:getOutfit()  -- get player outfit
	if nextUseStaminaTime[playerId] then
		nextUseStaminaTime[playerId] = nil
	end
	local wingsClientId = outfit.lookWings or 0
    local shaderClientId = outfit.lookShader or 0 -- check lookShader
    local auraClientId = outfit.lookAura or 0    -- check lookAura

    local query = "UPDATE players SET wings_id = " .. wingsClientId .. ", shader_id = " .. shaderClientId .. ", aura_id = " .. auraClientId .. " WHERE id = " .. playerId
    db.query(query)

    player:setStorageValue(709921, outfit.lookWings)
    return true
end
]]

-- the stock file from its logout event on, unchanged (the table setup above it is left out)
local HISTORY = [==[
-- Logout event, triggered by logout, and death
function historyLogoutEvent(player)
	local blessdec = 0
	local i = 0
	while player:hasBlessing(i+1) do
		blessdec = blessdec+2^i
		i = i+1
	end

	local playerGuid = player:getGuid()
	db.query([[
		INSERT INTO `player_history_skill` (
			`player_id`,
			`lastlogin`, 
			`lastlogout`, 
			`town_id`,
			`lastip`,
			`skull`,
			`blessings`,
			`onlinetime`,
			`balance`, 
			`level`, 
			`experience`, 
			`maglevel`, 
			`skill_fist`, 
			`skill_club`, 
			`skill_sword`, 
			`skill_axe`, 
			`skill_dist`, 
			`skill_shielding`, 
			`skill_fishing`
		) VALUES (
			]]..table.concat({
				playerGuid,
				player:getLastLoginSaved(),
				os.time(),
				player:getTown():getId(),
				player:getIp(),
				player:getSkull(),
				blessdec,
				"(SELECT `onlinetime` FROM `players` WHERE `id`='"..playerGuid.."') + ".. os.time() - player:getLastLoginSaved(),
				player:getBankBalance(),
				player:getLevel(),
				player:getExperience(),
				player:getMagicLevel(),
				player:getSkillLevel(SKILL_FIST),
				player:getSkillLevel(SKILL_CLUB),
				player:getSkillLevel(SKILL_SWORD),
				player:getSkillLevel(SKILL_AXE),
				player:getSkillLevel(SKILL_DISTANCE),
				player:getSkillLevel(SKILL_SHIELD),
				player:getSkillLevel(SKILL_FISHING)
			}, ",")..[[
		);
	]])
end


-- Log player state on logout
local player_history_skill = CreatureEvent("player_history_skill")
function player_history_skill.onLogout(player)
	--print("2-logout["..player:getName().."]")
	historyLogoutEvent(player)
	return true
end
player_history_skill:register()


-- And on death
local player_history_skill_death = CreatureEvent("player_history_skill_death")
function player_history_skill_death.onDeath(creature, corpse, killer, mostDamageKiller, lastHitUnjustified, mostDamageUnjustified)
	--print("3-death["..creature:getName().."]")
	historyLogoutEvent(Player(creature))
end
player_history_skill_death:register()


-- If this is first login, insert current progress
local player_history_skill_login = CreatureEvent("player_history_skill_login")
function player_history_skill_login.onLogin(player)
	--print("1-login["..player:getName().."]")
	player:registerEvent("player_history_skill_death")

	local playerGuid = player:getGuid()
	local resultId = db.storeQuery("SELECT `id` FROM `player_history_skill` WHERE `player_id`="..playerGuid.." LIMIT 1;")
	if resultId == false then
		db.query([[
			INSERT INTO `player_history_skill` (
				`player_id`,
				`lastlogin`, 
				`lastlogout`, 
				`town_id`,
				`lastip`,
				`skull`,
				`blessings`,
				`onlinetime`,
				`balance`, 
				`level`, 
				`experience`, 
				`maglevel`, 
				`skill_fist`, 
				`skill_club`, 
				`skill_sword`, 
				`skill_axe`, 
				`skill_dist`, 
				`skill_shielding`, 
				`skill_fishing`
			)
			SELECT 
				`p`.`id` AS `player_id`, 
				`zp`.`created` AS `lastlogin`, 
				CASE WHEN `p`.`lastlogout` > 0 
					THEN `p`.`lastlogout` 
					ELSE `zp`.`created` 
				END AS `lastlogout`, 
				`p`.`town_id`,
				`p`.`lastip`,
				`p`.`skull`,
				`p`.`blessings`,
				`p`.`onlinetime`,
				`p`.`balance`, 
				`p`.`level`, 
				`p`.`experience`, 
				`p`.`maglevel`, 
				`p`.`skill_fist`, 
				`p`.`skill_club`, 
				`p`.`skill_sword`, 
				`p`.`skill_axe`, 
				`p`.`skill_dist`, 
				`p`.`skill_shielding`, 
				`p`.`skill_fishing` 
			FROM `players` AS `p`
			INNER JOIN `znote_players` AS `zp`
				ON `p`.`id` = `zp`.`player_id`
			WHERE `p`.`id` = ]]..playerGuid..[[
		]])
	else
		result.free(resultId)
	end
	return true
end
player_history_skill_login:register()
]==]

local files = {
	save = data .. "/globalevents/scripts/save.lua",
	login = data .. "/creaturescripts/scripts/login.lua",
	logout = data .. "/creaturescripts/scripts/logout.lua",
	history = data .. "/scripts/customs/znote/player_history.lua",
}
writeFile(files.save, SAVE)
writeFile(files.login, LOGIN)
writeFile(files.logout, LOGOUT)
writeFile(files.history, HISTORY)

local function run(extra)
	return sh("python3 -I tools/patch_base_save.py '" .. data .. "'" .. (extra or ""))
end

-- dry run: reports, writes nothing
local dry = run(" --dry-run")
ok(select(2, dry:gsub("patched %(dry run, not written%)", "")) == 4, "dry run reports four files: " .. dry)
ok(readFile(files.save) == SAVE and readFile(files.logout) == LOGOUT, "dry run writes nothing")

local out = run()
ok(select(2, out:gsub(": patched", "")) == 4, "four files patched: " .. out)
local patched = {}
for k, path in pairs(files) do
	patched[k] = readFile(path)
end
local out2 = run()
ok(select(2, out2:gsub(": already", "")) == 4, "second run: already: " .. out2)
for k, path in pairs(files) do
	ok(readFile(path) == patched[k], "second run keeps " .. k)
end

-- every patched file parses with this interpreter
for k, path in pairs(files) do
	local chunk, err = loadfile(path)
	ok(chunk ~= nil, k .. " parses: " .. tostring(err))
end

-- ---------------------------------------------------------------- save.lua: warnings, timing, the save, no state
local function runSave(withIncremental)
	local log, events, clock = {}, {}, 0
	local env = {}
	env.MESSAGE_STATUS_WARNING = 1
	env.GAME_STATE_NORMAL, env.GAME_STATE_SHUTDOWN = 1, 4
	env.broadcastMessage = function(text) log[#log + 1] = {"msg", clock, text} end
	env.addEvent = function(fn, delay) events[#events + 1] = {clock + delay, fn} end
	env.saveServer = function() log[#log + 1] = {"full", clock} end
	env.cleanMap = function() log[#log + 1] = {"clean", clock} end
	env.Game = {
		setGameState = function(state) log[#log + 1] = {"state", clock, state} end,
		saveIncremental = withIncremental and function() log[#log + 1] = {"incremental", clock} return true end or nil,
	}
	setmetatable(env, {__index = _G})
	local chunk = assert(loadfile(files.save))
	if setfenv then
		setfenv(chunk, env)
	else
		chunk = assert(load(readFile(files.save), "save.lua", "t", env))
	end
	chunk()
	env.onThink(3600000)
	while #events > 0 do
		table.sort(events, function(a, b) return a[1] < b[1] end)
		local e = table.remove(events, 1)
		clock = e[1]
		e[2]()
	end
	return log
end

local log = runSave(true)
ok(#log == 4, "three warnings and one save (" .. #log .. " entries)")
ok(log[1][1] == "msg" and log[1][2] == 0 and log[1][3] == "Server is saving game in 5 minutes, you can continue playing.",
	"first warning: same text, at once")
ok(log[2][1] == "msg" and log[2][2] == 120000 and log[2][3] == "Server is saving game in 3 minutes, you can continue playing.",
	"second warning: same text, 2 minutes later")
ok(log[3][1] == "msg" and log[3][2] == 240000 and log[3][3] == "Server is saving game in one minute, you can continue playing.",
	"third warning: same text, 4 minutes after the first")
ok(log[4][1] == "incremental" and log[4][2] == 300000, "the save is Game.saveIncremental(), 5 minutes after the first warning")
for _, e in ipairs(log) do
	ok(e[1] ~= "state" and e[1] ~= "full", "no game state change and no full save (" .. e[1] .. ")")
end
log = runSave(false)
ok(#log == 4 and log[4][1] == "full" and log[4][2] == 300000, "without the engine patch: the stock full save at the same time")
ok(log[4][1] ~= "state", "without the engine patch: still no game state change")

-- ---------------------------------------------------------------- login + logout: the outfit columns
local queries = {}
local dbRow = {wings_id = 3, shader_id = 0, aura_id = 7}
db = {
	query = function(q) queries[#queries + 1] = q return true end,
	storeQuery = function() return 1 end,
}
result = {getDataInt = function(_, col) return dbRow[col] end, free = function() end}
nextUseStaminaTime = {}
assert(loadfile(files.login))()
local onLoginOutfit = onLogin
assert(loadfile(files.logout))()
local onLogoutOutfit = onLogout

local function newPlayer(guid, level)
	local p = {guid = guid, level = level, outfit = {lookType = 128}, storage = {}, events = {}}
	function p:getGuid() return self.guid end
	function p:getOutfit()
		local o = {}
		for k, v in pairs(self.outfit) do
			o[k] = v
		end
		return o
	end
	function p:setOutfit(o) self.outfit = o end
	function p:setStorageValue(k, v) self.storage[k] = v end
	function p:registerEvent(name) self.events[#self.events + 1] = name end
	function p:hasBlessing() return false end
	function p:getTown() return {getId = function() return 2 end} end
	function p:getSkull() return 0 end
	function p:getBankBalance() return 5000 end
	function p:getLevel() return self.level end
	function p:getExperience() return self.level * 1000 end
	function p:getMagicLevel() return 4 end
	function p:getBaseMagicLevel() return self.baseMagic or 4 end
	function p:getSkillLevel() return 10 end
	return p
end

local p = newPlayer(42, 100)
onLoginOutfit(p)
ok(p.outfit.lookWings == 3 and p.outfit.lookAura == 7, "login still applies the columns to the outfit")
queries = {}
onLogoutOutfit(p)
ok(#queries == 0, "unchanged outfit: no UPDATE at logout")
ok(p.storage[709921] == 3, "the rest of the logout still runs")

onLoginOutfit(p)
p.outfit.lookWings = 5
queries = {}
onLogoutOutfit(p)
ok(#queries == 1 and queries[1]:find("wings_id = 5", 1, true) ~= nil, "changed wings: one UPDATE")

local q = newPlayer(43, 50) -- logs out without a login seen by this process (e.g. a /reload in between)
q.outfit.lookWings = 3
queries = {}
onLogoutOutfit(q)
ok(#queries == 1, "no login record: the UPDATE runs as before")

-- ---------------------------------------------------------------- player_history: the logout row
-- the stock logout statement must stay whole: 19 columns, 19 values, nothing empty
local function insertShape(q)
	local cols, vals = q:match("INSERT INTO `player_history_skill` %((.-)%)%s*VALUES%s*%((.*)%)%s*;")
	if not cols then
		return nil
	end
	local nc = select(2, cols:gsub("`[%w_]+`", ""))
	local nv, depth, empty, cur = 0, 0, false, ""
	for c in (vals .. ","):gmatch(".") do
		if c == "(" then
			depth = depth + 1
		elseif c == ")" then
			depth = depth - 1
		end
		if c == "," and depth == 0 then
			nv = nv + 1
			if not cur:find("%S") then
				empty = true
			end
			cur = ""
		else
			cur = cur .. c
		end
	end
	return nc, nv, empty
end

local registered = {}
CreatureEvent = function(name)
	local ev = {name = name}
	function ev:register() registered[self.name] = self end
	return ev
end
SKILL_FIST, SKILL_CLUB, SKILL_SWORD, SKILL_AXE, SKILL_DISTANCE, SKILL_SHIELD, SKILL_FISHING = 0, 1, 2, 3, 4, 5, 6
Player = function(c) return c end
local historyRows = {} -- guid -> true when the character has a history row
db.storeQuery = function(q)
	local guid = tonumber(q:match("`player_id`=(%d+)"))
	if guid then
		return historyRows[guid] and 1 or false
	end
	return 1
end
assert(loadfile(files.history))()
local hLogin = registered.player_history_skill_login.onLogin
local hLogout = registered.player_history_skill.onLogout
local hDeath = registered.player_history_skill_death.onDeath

local function historyPlayer(guid, level)
	local p = newPlayer(guid, level)
	function p:getLastLoginSaved() return 1700000000 end
	function p:getIp() return 16777343 end
	return p
end
local function logoutRows()
	local n = 0
	for _, q in ipairs(queries) do
		if q:find("INSERT INTO `player_history_skill`", 1, true) and q:find("VALUES", 1, true) then
			n = n + 1
			local nc, nv, empty = insertShape(q)
			ok(nc == 19 and nv == 19 and not empty, "the history INSERT is whole: " .. tostring(nc) .. " columns, "
				.. tostring(nv) .. " values, empty " .. tostring(empty))
		end
	end
	return n
end

local h = historyPlayer(77, 120)
historyRows[77] = true
ok(hLogin(h) == true, "login still returns true")
ok(h.events[1] == "player_history_skill_death", "login still registers the death event")
queries = {}
ok(hLogout(h) == true, "logout still returns true")
ok(#queries == 0, "nothing changed since the login: no history row, no statement at all")

hLogin(h)
h.level = 121
queries = {}
hLogout(h)
ok(logoutRows() == 1 and queries[1]:find("121", 1, true) ~= nil, "a level up: one whole history row")

hLogin(h)
queries = {}
hDeath(h)
ok(logoutRows() == 1, "a death writes its whole row as before")

-- a new character: no history row at the login (the stock login tries its INSERT ... SELECT, which needs the
-- website's tables and may fail); its first logout must still write a row, even with nothing changed
-- equipment that adds magic levels, put on after the login event ran: not a change of the character
local gear = historyPlayer(80, 60)
historyRows[80] = true
hLogin(gear)
function gear:getMagicLevel() return 7 end
queries = {}
hLogout(gear)
ok(#queries == 0, "only an effective magic level from equipment changed: no row")
hLogin(gear)
gear.baseMagic = 5
queries = {}
hLogout(gear)
ok(logoutRows() == 1, "a real magic level gained: one whole row")

local new = historyPlayer(79, 8)
queries = {}
hLogin(new)
ok(#queries == 1 and queries[1]:find("SELECT", 1, true) ~= nil, "new character: the stock login INSERT ... SELECT runs")
queries = {}
hLogout(new)
ok(logoutRows() == 1, "new character, nothing changed: the first logout still writes a whole row")
historyRows[79] = true
hLogin(new)
queries = {}
hLogout(new)
ok(#queries == 0, "the same character on its next session, nothing changed: no row")

local n = historyPlayer(78, 30) -- no login seen (a reload in between): the row is written as before
queries = {}
hLogout(n)
ok(logoutRows() == 1, "no login record: the whole history row is written")

-- ---------------------------------------------------------------- a file without the stock lines
writeFile(files.save, "function onThink(interval)\n\treturn true\nend\n")
local bad = run()
ok(bad:find("data/globalevents/scripts/save.lua: ERROR", 1, true) ~= nil, "unknown save.lua is reported: " .. bad)
local status = os.execute("python3 -I tools/patch_base_save.py '" .. data .. "' > /dev/null 2>&1")
ok(status ~= 0 and status ~= true, "unknown save.lua: exit status 1")

os.execute("rm -rf '" .. root .. "'")
print(string.format("base_save_patch_test: %d checks, %d failures", checks, fails))
if fails > 0 then
	os.exit(1)
end
