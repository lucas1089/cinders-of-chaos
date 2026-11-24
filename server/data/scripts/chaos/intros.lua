-- intros.lua: the quiet first login and the introductions after it (O761; rules intros_core.lua, table intros_config.lua;
-- server/README.md "Quiet first login (O761)").
-- A character's first login opens the Daily Reward window only. The other systems ask here before they show something by
-- themselves:
--   ChaosIntros.firstSession(player)          this login is the character's first and it is quiet (newplayer.lua: no welcome
--                                             toast and no Helper; mainquest.lua: the quest starts after the login windows)
--   ChaosIntros.loginWindowWanted(player, key) daily.lua's login window queue: on a quiet first login only the Daily Reward
--   ChaosIntros.allowed(player, key)          firsthour.lua ("tips"), unlocks.lua ("unlocks"), goals.lua ("goals"): false while
--                                             that introduction has not come yet (their own bits stay unset, so nothing is lost)
--   ChaosIntros.afterLoginWindows(player, fn) fn(player) once the login window queue is done (the Daily Reward closed)
--   ChaosIntros.onQuestStep(player, key)      mainquest.lua after a step is done or the quest skipped: due introductions come
-- The introductions come one per run (cfg.pace.gapMs between them), when their quest step is done or at their level, on a level
-- up and after a login. Once per character: storage block 7103160-7103169. A character from before O761 (and staff, testers) is
-- "open": nothing changes for it.
-- Assumed engine API (TFS 1.4): CreatureEvent login/advance, Player storage, getLastLoginSaved, sendOutfitWindow. Lua 5.1 / 5.3.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosIntrosCore or not ChaosIntrosCore.due then
	dofile("data/scripts/chaos/intros_core.lua")
end

local M = ChaosIntrosCore
ChaosIntros = ChaosIntros or {}
local I = ChaosIntros
I.pending = I.pending or {} -- player id -> true while the next introduction waits for the gap

function I.cfg()
	return M.cfg()
end

local function C()
	return M.cfg()
end

local function key(name)
	local s = C().storage
	return s.base + s[name]
end

local function log(text)
	print("[Chaos intros] " .. tostring(text))
end

local function isStaff(player)
	local ok, id = pcall(function() return player:getGroup():getId() end)
	return ok and type(id) == "number" and id >= (C().staffGroup or 4)
end

local function isTester(player)
	return Chaos.isTester ~= nil and Chaos.isTester(player) == true
end

-- the state, set the first time this module sees the character
function I.state(player)
	local c = C()
	if not c or not c.enabled then
		return c and c.states.open or 0
	end
	local st = player:getStorageValue(key("state"))
	if st < 0 then
		st = M.firstState(c, player:getLastLoginSaved(), isStaff(player), isTester(player))
		player:setStorageValue(key("state"), st)
	end
	return st
end

function I.quiet(player)
	return C() ~= nil and I.state(player) == C().states.quiet
end

-- this login is the character's first, and quiet
function I.firstSession(player)
	return I.quiet(player) and player:getLastLoginSaved() <= 0
end

function I.loginWindowWanted(player, windowKey)
	return M.loginWindowWanted(C(), windowKey, I.firstSession(player))
end

function I.allowed(player, introKey)
	local c = C()
	if not c or not c.enabled then
		return true
	end
	return M.allowed(c, I.state(player), player:getStorageValue(key("shown")), introKey)
end

-- ---------------------------------------------------------------- the login windows
local function windowsBusy(player)
	local LW = rawget(_G, "ChaosLoginWindows")
	if type(LW) ~= "table" then
		return false
	end
	local pid = player:getId()
	return (LW.state and LW.state[pid] ~= nil) or (LW.starting and LW.starting[pid] ~= nil) or false
end
I.windowsBusy = windowsBusy

function I.afterLoginWindows(player, fn)
	local w = C().wait or {}
	local poll, maxWait = w.pollMs or 1000, w.maxWaitMs or 180000
	local pid = player:getId()
	local function step(waited)
		local p = Player(pid)
		if not p then
			return
		end
		if waited >= maxWait or isTester(p) or not windowsBusy(p) then
			local ok, err = pcall(fn, p)
			if not ok then
				log("after the login windows: " .. tostring(err))
			end
			return
		end
		addEvent(step, poll, waited + poll)
	end
	step(0)
end

-- ---------------------------------------------------------------- the introductions
local function langOf(player)
	if ChaosFirstHour and ChaosFirstHour.langOf then
		local ok, l = pcall(ChaosFirstHour.langOf, player)
		if ok and l then
			return l
		end
	end
	local ok, l = pcall(function() return Chaos.lang and Chaos.lang(player) end)
	return ok and l or "en"
end

-- what the main quest says about the character (the quest's own storages)
function I.ctx(player)
	local ctx = {level = player:getLevel(), questActive = false, questStep = 0}
	local Q = ChaosMainQuestCore
	local q = Q and Q.cfg and Q.cfg()
	if q and q.enabled then
		local base = q.storage.base
		ctx.questActive = player:getStorageValue(base + q.storage.state) == q.states.active
		ctx.questStep = player:getStorageValue(base + q.storage.step)
		ctx.indexOf = function(k) return Q.indexOf(q, k) end
	end
	return ctx
end

local function toast(player, text)
	if ChaosOpcodes and ChaosOpcodes.notifications and json then
		player:sendExtendedOpcode(ChaosOpcodes.notifications, json.encode({action = "newplayer", message = text}))
	end
end

-- let the system of introduction i go (its bit first: a failed run is not repeated)
function I.give(player, i)
	local c = C()
	local it = c.intros[i]
	if not it then
		return false
	end
	player:setStorageValue(key("shown"), M.set(player:getStorageValue(key("shown")), i))
	local text = M.text(it.text, langOf(player))
	if text then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE or MESSAGE_INFO_DESCR, text)
		toast(player, text)
	end
	local ok, err = pcall(function()
		if it.system == "outfit" then
			if player.sendOutfitWindow then
				player:sendOutfitWindow()
			end
		elseif it.system == "firsthour" then
			if ChaosFirstHour and ChaosFirstHour.run then
				ChaosFirstHour.run(player)
			end
		elseif it.system == "unlocks" then
			if ChaosUnlocks and ChaosUnlocks.run then
				ChaosUnlocks.run(player)
			end
		elseif it.system == "goals" then
			if ChaosGoals and ChaosGoals.sendTracker then
				ChaosGoals.sendTracker(player)
			end
		end
	end)
	if not ok then
		log(it.key .. ": " .. tostring(err))
	end
	return true
end

function I.later(player)
	local pid = player:getId()
	if I.pending[pid] then
		return
	end
	I.pending[pid] = true
	addEvent(function()
		I.pending[pid] = nil
		local p = Player(pid)
		if p then
			pcall(I.run, p)
		end
	end, (C().pace or {}).gapMs or 60000)
end

-- one due introduction now, the next after the gap; nothing while one waits for the gap or the login windows are open
function I.run(player)
	local c = C()
	if not c or not c.enabled or I.pending[player:getId()] or windowsBusy(player) then
		return false
	end
	local due = M.due(c, I.state(player), player:getStorageValue(key("shown")), I.ctx(player))
	if #due == 0 then
		return false
	end
	I.give(player, due[1])
	if #due > 1 then
		I.later(player)
	else
		-- a gap after this one too: a level gained in the next minute does not bring the next introduction beside it
		I.pending[player:getId()] = true
		local pid = player:getId()
		addEvent(function()
			I.pending[pid] = nil
			local p = Player(pid)
			if p then
				pcall(I.run, p)
			end
		end, (c.pace or {}).gapMs or 60000)
	end
	return true
end

-- a quest step was done (key) or the quest skipped (nil): the step's done line and the next step first, the introduction after
function I.onQuestStep(player, stepKey)
	if not I.quiet(player) then
		return
	end
	local pid = player:getId()
	addEvent(function()
		local p = Player(pid)
		if p then
			pcall(I.run, p)
		end
	end, 3000)
end

-- ---------------------------------------------------------------- events
if CreatureEvent then
	local login = CreatureEvent("ChaosIntrosLogin")
	function login.onLogin(player)
		if not C() or not C().enabled then
			return true
		end
		player:registerEvent("ChaosIntrosAdvance")
		I.pending[player:getId()] = nil
		if I.state(player) == C().states.quiet and player:getLastLoginSaved() > 0 then
			-- a returning quiet character: the introductions due come after its login windows
			local pid = player:getId()
			addEvent(function()
				local p = Player(pid)
				if p then
					I.afterLoginWindows(p, function(q)
						addEvent(function()
							local r = Player(pid)
							if r then
								pcall(I.run, r)
							end
						end, C().loginDelayMs or 8000)
					end)
				end
			end, 4000)
		end
		return true
	end
	login:type("login")
	login:register()

	local advance = CreatureEvent("ChaosIntrosAdvance")
	function advance.onAdvance(player, skill, oldLevel, newLevel)
		if skill == SKILL_LEVEL and newLevel > oldLevel and C() and C().enabled and I.quiet(player) then
			pcall(I.run, player)
		end
		return true
	end
	advance:register()
end

do
	local c = C()
	local qk
	local Q = ChaosMainQuestCore
	if not Q then
		pcall(dofile, "data/scripts/chaos/mainquest_core.lua")
		Q = ChaosMainQuestCore
	end
	local q = Q and Q.cfg and Q.cfg()
	if q then
		qk = {}
		for _, st in ipairs(q.steps) do
			qk[st.key] = true
		end
	end
	for _, p in ipairs(c and M.validate(c, qk) or {"intros_config.lua did not load"}) do
		log("intros_config.lua: " .. p)
	end
end
