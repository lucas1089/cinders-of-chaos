-- unlocks.lua: the top menu reveals systems by level (unlocks_config.lua, unlocks_core.lua; client client_chaos_topbar;
-- extended opcode ChaosOpcodes.unlocks = 115; server/README.md "The top menu reveals systems by level (O259)").
-- The server keeps what a character has unlocked (bits in the storages of the config) and tells the client:
--     state {entries = [{key, level, menu}], unlocked = [key], seen = [key], next = {key, level}?, all = true?}
--     new   {key, level, menu, title, why = [line1, line2]}      one entry just unlocked (screen text, small window)
-- at login, when the client asks (`hello`) and at every level change; `new` comes one entry per cfg.pace.gapMs (75 s, the
-- first hour's pace) when several unlock at once. The client sends `seen {key}` when the player opens an entry (the "New"
-- badge goes). A character above cfg.quietAbove at its first login gets the entries of its level silently; entries added to
-- the config later at a level it already passed are marked silently too. Staff (cfg.staffGroup) get `all = true`.
-- The server does not gate anything: every system keeps its own level check; this only decides what the menu shows.
-- Assumed engine API (TFS 1.4): CreatureEvent login/advance/extendedopcode, Player storage. Lua 5.1 / LuaJIT and 5.3.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosUnlocksCore or not ChaosUnlocksCore.nextLocked then
	dofile("data/scripts/chaos/unlocks_core.lua")
end

local M = ChaosUnlocksCore
ChaosUnlocks = ChaosUnlocks or {}
local U = ChaosUnlocks

local function C()
	return M.cfg()
end

local OPCODE = (ChaosOpcodes and ChaosOpcodes.unlocks) or 115

local function key(name)
	local s = C().storage
	return s.base + s[name]
end

function U.langOf(player)
	if ChaosFirstHour and ChaosFirstHour.langOf then
		return ChaosFirstHour.langOf(player)
	end
	local lang = Chaos.lang and Chaos.lang(player)
	return (lang == "pt" or lang == "pt-BR") and "pt" or "en"
end

local function isStaff(player)
	local ok, id = pcall(function() return player:getGroup():getId() end)
	return ok and type(id) == "number" and id >= (C().staffGroup or 4)
end

-- the whole menu: staff, or the module off
local function wholeMenu(player)
	return not C().enabled or isStaff(player)
end

function U.sendState(player)
	local data = M.state(player:getStorageValue(key("unlocked")), player:getStorageValue(key("seen")), player:getLevel(),
		wholeMenu(player))
	return Chaos.send(player, OPCODE, "state", data)
end

-- unlock what is due at the character's level, one entry per run; the rest after the gap
U.pending = U.pending or {} -- player id -> true while the next announcement waits

function U.later(player)
	local pid = player:getId()
	if U.pending[pid] then
		return
	end
	U.pending[pid] = true
	local _, gapMs = M.pace()
	addEvent(function()
		U.pending[pid] = nil
		local p = Player(pid)
		if p and C() and C().enabled then
			pcall(U.run, p)
		end
	end, gapMs)
end

function U.run(player)
	local mask = player:getStorageValue(key("unlocked"))
	local perRun = M.pace()
	local lang = U.langOf(player)
	for n, i in ipairs(M.due(mask, player:getLevel())) do
		if n > perRun then
			U.later(player)
			break
		end
		-- the bit first: a failed message is not repeated
		mask = M.set(mask, i)
		player:setStorageValue(key("unlocked"), mask)
		Chaos.send(player, OPCODE, "new", M.announcement(i, lang))
	end
	U.sendState(player)
end

-- entries added to the config since the character's last login: the ones of levels it already passed are marked
-- unlocked and seen, silently; the rest come at their level
function U.sync(player)
	local c, level = C(), player:getLevel()
	local known = player:getStorageValue(key("known"))
	if known < 0 then
		known = 0
	end
	if known < #c.entries then
		local function levelOf(i) return c.entries[i].level end
		player:setStorageValue(key("unlocked"), M.sync(player:getStorageValue(key("unlocked")), known, #c.entries, levelOf, level))
		player:setStorageValue(key("seen"), M.sync(player:getStorageValue(key("seen")), known, #c.entries, levelOf, level))
		player:setStorageValue(key("known"), #c.entries)
	end
end

local login = CreatureEvent("ChaosUnlocksLogin")
function login.onLogin(player)
	if not C() or not C().enabled then
		return true
	end
	player:registerEvent("ChaosUnlocksAdvance")
	player:registerEvent("ChaosUnlocksExtended")
	if player:getStorageValue(key("unlocked")) < 0 then
		local unlocked, seen = M.firstMasks(player:getLevel())
		player:setStorageValue(key("unlocked"), unlocked)
		player:setStorageValue(key("seen"), seen)
		player:setStorageValue(key("known"), #C().entries)
	else
		U.sync(player)
	end
	local pid = player:getId()
	-- the client may not listen yet: it also asks with `hello` once its module is up
	addEvent(function()
		local p = Player(pid)
		if p then
			pcall(U.sendState, p)
		end
	end, C().stateDelayMs or 1500)
	-- what is due waits for the welcome and the first hint
	addEvent(function()
		local p = Player(pid)
		if p then
			pcall(U.run, p)
		end
	end, C().delayMs or 20000)
	return true
end
login:register()

local advance = CreatureEvent("ChaosUnlocksAdvance")
function advance.onAdvance(player, skill, oldLevel, newLevel)
	if skill == SKILL_LEVEL and newLevel ~= oldLevel and C() and C().enabled then
		pcall(U.run, player)
	end
	return true
end
advance:register()

local ext = CreatureEvent("ChaosUnlocksExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE or not C() or not C().enabled then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg then
		return
	end
	if msg.action == "hello" then
		if ChaosRateLimit and not ChaosRateLimit.allow(player, "unlocks.hello", 1000) then
			return
		end
		pcall(U.sendState, player)
	elseif msg.action == "seen" then
		local data = type(msg.data) == "table" and msg.data or msg
		local i = type(data.key) == "string" and M.index(data.key) or nil
		if i and M.has(player:getStorageValue(key("unlocked")), i) then
			player:setStorageValue(key("seen"), M.set(player:getStorageValue(key("seen")), i))
		end
	end
end
ext:type("extendedopcode")
ext:register()
