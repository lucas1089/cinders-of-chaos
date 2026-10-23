-- Ascension tracker (engine side; rules in ascension_tracker_core.lua, client game_goals, extended opcode
-- ChaosOpcodes.goals = 178, the Next Goals channel; no new opcode). Sends  ascension {rows = [{key, title, progress,
-- target, state}]}  (rows = [] hides the section) at login, when the client asks for the tracker, and whenever what it
-- shows changes: a sweep every 3 s compares a signature per online character (a few storage reads), so the Oracle's
-- NPC state, the quest script, the level, a Vocation Change and the staff commands all reach it without hooks.
-- server/README.md "Ascension tracker".

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosAscensionTrackerCore then
	dofile("data/scripts/chaos/ascension_tracker_core.lua")
end

ChaosAscensionTracker = ChaosAscensionTracker or {}
local A = ChaosAscensionTracker
local K = ChaosAscensionTrackerCore
local Q = ChaosAscensionQuestCore
local OPCODE = ChaosOpcodes.goals
local SWEEP_MS = 3000

A.sent = A.sent or {} -- player id -> the signature the client has

local function langOf(player)
	return Chaos.lang and Chaos.lang(player) or "en"
end

local function rowsOf(player)
	local st = Q.cfg().storage
	return K.rows({
		vocId = player:getVocation():getId(),
		level = player:getLevel(),
		stage = player:getStorageValue(st.stage),
		proof = player:getStorageValue(st.proof)
	}, langOf(player))
end

-- sends the rows when they differ from what the client has
function A.refresh(player)
	local pid = player:getId()
	local rows = rowsOf(player)
	local sig = #rows == 0 and "hidden" or K.sig(rows, langOf(player))
	if A.sent[pid] == sig then
		return false
	end
	local first = A.sent[pid] == nil
	A.sent[pid] = sig
	if #rows == 0 and first then
		return false -- never shown: the client's section is hidden already
	end
	Chaos.send(player, OPCODE, "ascension", {rows = rows})
	return true
end

local login = CreatureEvent("ChaosAscensionTrackerLogin")
function login.onLogin(player)
	A.sent[player:getId()] = nil
	player:registerEvent("ChaosAscensionTrackerLogout")
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosAscensionTrackerLogout")
function logout.onLogout(player)
	A.sent[player:getId()] = nil
	return true
end
logout:type("logout")
logout:register()

-- the client asks for "tracker" when it shows the panel again: goals.lua (the one handler of opcode 178) clears
-- A.sent, so the next sweep sends the ascension rows too

local think = GlobalEvent("ChaosAscensionTrackerThink")
function think.onThink(interval)
	for _, player in ipairs(Game.getPlayers()) do
		local ok, err = pcall(A.refresh, player)
		if not ok then
			print("[Chaos ascension tracker] " .. tostring(err))
		end
	end
	return true
end
think:interval(SWEEP_MS)
think:register()
