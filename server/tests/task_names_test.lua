-- Run from the server/ folder: luajit tests/task_names_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- The task NPC (Mermod) and its kills (beta report 2026-10-22; server/README.md "Task NPC names"):
--   data/lib/chaos_task_names.lua   normalize, same, route, killCounts
--   tools/patch_task_npc.py         on copies of the stock lines it changes (a reduced NPC and kill script written
--                                   here with made-up task names), then the patched scripts run against a mocked NPC
--                                   system: every listed name registers (bare, any case, in brackets, after "normal" /
--                                   "daily", in one line or two), a kill counts by type name and any case, and a party
--                                   member counts their own task
-- and: a second run changes nothing, --dry-run writes nothing, a file without the stock lines is left alone.
-- TASK_NPC_DATA=<installed data dir>: the same checks on that server's real NPC and kill scripts (patched copies).
local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end
local function eq(a, b, what) ok(a == b, what .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end

dofile("data/lib/chaos_task_names.lua")
local N = ChaosTaskNames

-- ---------------------------------------------------------------- the pure rules
eq(N.normalize("  [Raging-Demons]. "), "raging demons", "normalize: brackets, hyphen, case, end dot")
eq(N.normalize("Seldar's Folly task"), "seldars folly", "normalize: apostrophe out, trailing task word")
eq(N.normalize("{Grim  reaper}"), "grim reaper", "normalize: braces and double spaces")
ok(N.same("Raging Demon", "raging demons"), "same: singular and plural")
ok(N.same("CHOKING FEAR", "choking Fear"), "same: any case on both sides")
ok(not N.same("demon", "demon lord"), "same: another name")
ok(not N.same("", ""), "same: empty never matches")

local NORMAL = {
	{name = "raging demons", mons_list = {"demon"}, storage = 900001, amount = 3},
	{name = "fear valley", mons_list = {"retching horror", "choking Fear"}, storage = 900002, amount = 3},
	{name = "rot crawlers", mons_list = {"bloated corpse-grub", "rot crawler"}, storage = 900003, amount = 3},
	{name = "sea serpents", mons_list = {"sea serpent"}, storage = 900004, amount = 3}
}
local DAILY = {
	{name = "gloomfang", mons_list = {"gloomfang"}, storage = 900101, amount = 1},
	{name = "seldar's folly", mons_list = {"seldar's folly"}, storage = 900102, amount = 1},
	{name = "sea serpents", mons_list = {"sea serpent"}, storage = 900103, amount = 1}
}
local function same2(a, b, c, d, what)
	eq(a, c, what .. " (kind)")
	eq(b, d, what .. " (index)")
end
local k, i = N.route("Raging Demons", NORMAL, DAILY)
same2(k, i, "normal", 1, "route: a bare normal name")
k, i = N.route("gloomfang", NORMAL, DAILY)
same2(k, i, "daily", 1, "route: a bare daily name")
k, i = N.route("daily sea serpents", NORMAL, DAILY)
same2(k, i, "daily", 3, "route: daily first when said")
k, i = N.route("sea serpents", NORMAL, DAILY)
same2(k, i, "normal", 4, "route: a name on both lists is the normal task")
eq(N.route("normal", NORMAL, DAILY), nil, "route: the bare word normal is no task")
eq(N.route("normal ancestral task list", NORMAL, DAILY), nil, "route: the list command is no task")
eq(N.route("daily gloomfangs", NORMAL, {}), nil, "route: daily of a missing list")
ok(N.killCounts(NORMAL[2], "Choking Fear", nil), "killCounts: a list entry with a capital letter")
ok(N.killCounts(NORMAL[1], "Elite Demon", "Demon"), "killCounts: by the type name")
ok(N.killCounts(NORMAL[3], "Bloated Corpse Grub", nil), "killCounts: hyphen or space")
ok(not N.killCounts(NORMAL[1], "Demon Lord", "Demon Lord"), "killCounts: another monster")

-- ---------------------------------------------------------------- the patch tool
local python = io.popen and io.popen("python3 -V 2>/dev/null")
local hasPython = python and (python:read("*a") or ""):find("Python 3")
if python then
	python:close()
end
if not hasPython then
	print(string.format("task_names_test: %d checks, %d failures (python3 not found, patch part skipped)", checks, fails))
	os.exit(fails > 0 and 1 or 0)
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
	local p = io.popen(cmd .. " 2>&1")
	local out = p:read("*a")
	p:close()
	return out
end

-- the stock structure of the two scripts (the lines the patch changes are the stock lines; the rest reduced)
local NPC_SCRIPT = [[
local keywordHandler = KeywordHandler:new()
local npcHandler = NpcHandler:new(keywordHandler)

function creatureSayCallback(cid, type, msg)
    if(not npcHandler:isFocused(cid)) then
        return false
    end
local player = Player(cid)
local msg = msg:lower()
if npcHandler.topic[cid] == 0 and msg == 'normal' then
    npcHandler:say("Which monster task would you like to do?", cid)
    npcHandler.topic[cid] = 1
elseif npcHandler.topic[cid] == 1 then
    if player:getStorageValue(task_storage) == -1 then
        for mon, l in ipairs(task_monsters) do
            if msg == l.name then
                npcHandler:say("You're now doing the " .. l.name .. " task.", cid)
                player:setStorageValue(task_storage, mon)
                player:setStorageValue(l.storage, 0)
                npcHandler.topic[cid] = 0
                break
            elseif mon == #task_monsters then
                npcHandler:say("Sorry but we don't have this task.", cid)
                npcHandler.topic[cid] = 0
            end
        end
    else
        npcHandler:say("You're already doing a task.", cid)
        npcHandler.topic[cid] = 0
    end
elseif npcHandler.topic[cid] == 0 and msg == 'daily' then
    if player:getStorageValue(time_daySto) < os.time() then
        npcHandler:say("Which daily task would you like to do?", cid)
        npcHandler.topic[cid] = 2
    else
        npcHandler:say('You have completed a daily task today.', cid)
        npcHandler.topic[cid] = 0
    end
elseif npcHandler.topic[cid] == 2 then
    if player:getStorageValue(taskd_storage) == -1 then
        for mon, l in ipairs(task_daily) do
            if msg == l.name then
                npcHandler:say("You're now doing the daily " .. l.name .. " task.", cid)
                player:setStorageValue(taskd_storage, mon)
                player:setStorageValue(l.storage, 0)
                npcHandler.topic[cid] = 0
                break
            elseif mon == #task_daily then
                npcHandler:say("Sorry we don't have this daily task.", cid)
                npcHandler.topic[cid] = 0
            end
        end
    else
        npcHandler:say("You're already doing a daily task.", cid)
        npcHandler.topic[cid] = 0
    end
end
end

npcHandler:setCallback(CALLBACK_MESSAGE_DEFAULT, creatureSayCallback)
]]

local KILL_SCRIPT = [[
local taskKills = CreatureEvent("taskKills")

function taskKills.onKill(player, target)
    if target:isPlayer() or target:getMaster() then
        return true
    end

    local mon_name = target:getName():lower()

	function updateTaskProgress(player, taskInfo)
		if taskInfo and (mon_name == taskInfo.name or isInArray(taskInfo.mons_list, mon_name)) then
			local sto_value = player:getStorageValue(taskInfo.storage)
			if sto_value < taskInfo.amount then
				player:setStorageValue(taskInfo.storage, sto_value + 1)
			end
		end
	end
    updateTaskProgress(player, getTaskInfos(player))
    updateTaskProgress(player, getTaskDailyInfo(player))

    local party = player:getParty()
    if party then
        local members = party:getMembers()
        for _, member in ipairs(members) do
            if member:getId() ~= player:getId() then
                updateTaskProgress(member, getTaskInfos(player))
                updateTaskProgress(member, getTaskDailyInfo(player))
            end
        end
    end

    return true
end

taskKills:register()
]]

local tmp = os.tmpname()
os.remove(tmp)
local root = tmp .. "_tasknpc"
sh("mkdir -p '" .. root .. "/npc/scripts' '" .. root .. "/scripts/customs/tasks'")
local npcPath = root .. "/npc/scripts/taskgiver.lua"
local killPath = root .. "/scripts/customs/tasks/task_kills.lua"
local otherPath = root .. "/npc/scripts/other.lua"
writeFile(npcPath, NPC_SCRIPT)
writeFile(killPath, KILL_SCRIPT)
writeFile(otherPath, "local msg = msg:lower()\n")
local tool = "python3 -I tools/patch_task_npc.py '" .. root .. "'"

local out = sh(tool .. " --dry-run")
ok(out:find("2 file%(s%) would change") ~= nil, "dry run reports both files (" .. out .. ")")
eq(readFile(npcPath), NPC_SCRIPT, "dry run writes nothing")
out = sh(tool)
ok(out:find("2 file%(s%) changed") ~= nil, "patch changes both files (" .. out .. ")")
local patchedNpc, patchedKill = readFile(npcPath), readFile(killPath)
ok(patchedNpc ~= NPC_SCRIPT and patchedKill ~= KILL_SCRIPT, "both files patched")
eq(readFile(otherPath), "local msg = msg:lower()\n", "an unrelated NPC script is left alone")
out = sh(tool)
ok(out:find("nothing to change") ~= nil, "a second run changes nothing (" .. out .. ")")
eq(readFile(npcPath), patchedNpc, "second run: NPC script unchanged")
eq(readFile(killPath), patchedKill, "second run: kill script unchanged")

-- ---------------------------------------------------------------- the mocked NPC and kill engine
local function newPlayer(id)
	local p = {id = id, sto = {}}
	function p:getStorageValue(key) return self.sto[key] or -1 end
	function p:setStorageValue(key, v) self.sto[key] = v end
	function p:getId() return self.id end
	function p:getParty() return self.party end
	function p:isPlayer() return true end
	return p
end
local players = {}
local function setup(normal, daily)
	task_monsters, task_daily = normal, daily
	task_storage, taskd_storage, time_daySto = 480000, 480004, 480005
	isInArray = function(t, v)
		for _, x in ipairs(t) do
			if x == v then return true end
		end
		return false
	end
	Player = function(cid) return players[cid] end
	getTaskInfos = function(p) return task_monsters[p:getStorageValue(task_storage)] or false end
	getTaskDailyInfo = function(p) return task_daily[p:getStorageValue(taskd_storage)] or false end
end

local function loadNpc(path)
	local said = {}
	local handler = {topic = {}}
	function handler:isFocused() return true end
	function handler:say(text) said[#said + 1] = text end
	function handler:setCallback(_, fn) self.cb = fn end
	KeywordHandler = {new = function() return {} end}
	NpcHandler = {new = function() return handler end}
	NpcSystem = {parseParameters = function() end}
	FocusModule = {new = function() return {} end}
	handler.addModule = function() end
	handler.onCreatureAppear, handler.onCreatureDisappear, handler.onCreatureSay = function() end, function() end,
		function() end
	handler.onThink, handler.onPlayerCloseChannel = function() end, function() end
	CALLBACK_MESSAGE_DEFAULT = 1
	creatureSayCallback = nil
	dofile(path)
	return handler, said
end

local function loadKill(path)
	local ev = {}
	CreatureEvent = function() return ev end
	ev.register = function() end
	dofile(path)
	return ev
end

local function monster(shown, typeName)
	return {getName = function() return shown end, isPlayer = function() return false end,
		getMaster = function() return nil end, isMonster = function() return true end,
		getType = function() return {name = function() return typeName or shown end} end}
end

-- every listed name registers: each way of saying it, a fresh player each time
local function checkNpc(npcFile, normal, daily, label)
	setup(normal, daily)
	local handler = loadNpc(npcFile)
	local cid = 0
	local function talk(lines, kind, index, what)
		cid = cid + 1
		players[cid] = newPlayer(cid)
		handler.topic[cid] = 0
		for _, line in ipairs(lines) do
			handler.cb(cid, 1, line)
		end
		local p = players[cid]
		if kind == "normal" then
			eq(p:getStorageValue(task_storage), index, label .. ": " .. what)
		else
			eq(p:getStorageValue(taskd_storage), index, label .. ": " .. what)
		end
	end
	local function first(list, name)
		for j, e in ipairs(list) do
			if e.name == name then return j end
		end
	end
	for j, e in ipairs(normal) do
		if first(normal, e.name) == j then
			local up = e.name:upper()
			talk({e.name}, "normal", j, "normal '" .. e.name .. "' bare")
			talk({"[" .. up .. "]"}, "normal", j, "normal '" .. e.name .. "' in brackets, upper case")
			talk({"normal " .. e.name}, "normal", j, "normal '" .. e.name .. "' in one line")
			talk({"normal", up}, "normal", j, "normal '" .. e.name .. "' after normal, upper case")
		end
	end
	for j, e in ipairs(daily) do
		if first(daily, e.name) == j then
			if not first(normal, e.name) then
				talk({e.name}, "daily", j, "daily '" .. e.name .. "' bare")
			end
			talk({"daily " .. e.name:upper()}, "daily", j, "daily '" .. e.name .. "' in one line")
			talk({"daily", e.name}, "daily", j, "daily '" .. e.name .. "' after daily")
		end
	end
	-- a daily name on the daily cooldown: the stock cooldown reply, no task
	if daily[1] then
		cid = cid + 1
		players[cid] = newPlayer(cid)
		players[cid].sto[time_daySto] = os.time() + 3600
		handler.topic[cid] = 0
		handler.cb(cid, 1, "daily " .. daily[1].name)
		eq(players[cid]:getStorageValue(taskd_storage), -1, label .. ": no daily task on the cooldown")
		eq(handler.topic[cid], 0, label .. ": the cooldown reply leaves the topic at 0")
	end
	-- not a task name: nothing starts
	cid = cid + 1
	players[cid] = newPlayer(cid)
	handler.topic[cid] = 0
	handler.cb(cid, 1, "hello there")
	eq(players[cid]:getStorageValue(task_storage), -1, label .. ": small talk starts no task")
end

checkNpc(npcPath, NORMAL, DAILY, "synthetic NPC")

do
	setup(NORMAL, DAILY)
	local ev = loadKill(killPath)
	Chaos = {monsterTypeName = function(m) return m:getType():name() end}
	local killer, mate = newPlayer(1), newPlayer(2)
	players[1], players[2] = killer, mate
	local party = {getMembers = function() return {mate} end}
	killer.party, mate.party = party, party
	killer.sto[task_storage], killer.sto[NORMAL[2].storage] = 2, 0
	mate.sto[task_storage], mate.sto[NORMAL[1].storage] = 1, 0
	ev.onKill(killer, monster("Choking Fear"))
	eq(killer:getStorageValue(NORMAL[2].storage), 1, "kill: a list entry with a capital letter counts")
	eq(mate:getStorageValue(NORMAL[1].storage), 0, "kill: the party member's own task does not count it")
	eq(mate:getStorageValue(NORMAL[2].storage), -1, "kill: the party member gets no progress on the killer's task")
	ev.onKill(killer, monster("Elite Demon", "Demon"))
	eq(mate:getStorageValue(NORMAL[1].storage), 1, "kill: a party member counts their own task by the type name")
	ev.onKill(killer, monster("Retching Horror"))
	eq(killer:getStorageValue(NORMAL[2].storage), 2, "kill: any case")
end

-- the real scripts of an installed server (optional)
local real = os.getenv("TASK_NPC_DATA")
if real and real ~= "" then
	local function findFile(dir, needle)
		local p = io.popen("grep -rl --include=*.lua -e '" .. needle .. "' '" .. dir .. "' 2>/dev/null")
		local f = p:read("*l")
		p:close()
		return f
	end
	local npcReal = findFile(real .. "/npc/scripts", "task_daily")
	local killReal = findFile(real .. "/scripts", "updateTaskProgress")
	local libReal = findFile(real .. "/lib", "^ *task_monsters = ")
	ok(npcReal and killReal and libReal, "real data: NPC, kill script and task lists found")
	if npcReal and killReal and libReal then
		local rroot = tmp .. "_tasknpc_real"
		sh("mkdir -p '" .. rroot .. "/npc/scripts' '" .. rroot .. "/scripts'")
		writeFile(rroot .. "/npc/scripts/npc.lua", readFile(npcReal))
		writeFile(rroot .. "/scripts/kill.lua", readFile(killReal))
		sh("python3 -I tools/patch_task_npc.py '" .. rroot .. "'")
		-- the task lists: the two table constructors of the lib file
		local text = readFile(libReal)
		local function list(name)
			local body = text:match(name .. "%s*=%s*(%b{})")
			local fn = body and (loadstring or load)("return " .. body)
			return fn and fn() or {}
		end
		local env = {task_monsters = list("task_monsters"), task_daily = list("task_daily")}
		ok(#env.task_monsters > 0 and #env.task_daily > 0, "real data: both lists")
		do
			-- the real dialogue needs a few more globals
			task_time, task_sto_time = 1, 480002
			msgcontains = function(a, b) return a:find(b, 1, true) ~= nil end
			checkNpc(rroot .. "/npc/scripts/npc.lua", env.task_monsters, env.task_daily, "real NPC")
			setup(env.task_monsters, env.task_daily)
			local ev = loadKill(rroot .. "/scripts/kill.lua")
			MESSAGE_EVENT_ADVANCE = 1
			for j, e in ipairs(env.task_monsters) do
				local p = newPlayer(100 + j)
				function p:sendTextMessage() end
				players[p.id] = p
				p.sto[task_storage], p.sto[e.storage] = j, 0
				e.taskType = "Normal"
				local name = e.mons_list[1]
				ev.onKill(p, monster(name:gsub("^%l", string.upper)))
				eq(p:getStorageValue(e.storage), 1, "real kill: '" .. e.name .. "' counts " .. name)
			end
		end
		sh("rm -rf '" .. rroot .. "'")
	end
end

sh("rm -rf '" .. root .. "'")
print(string.format("task_names_test: %d checks, %d failures", checks, fails))
if fails > 0 then
	os.exit(1)
end
