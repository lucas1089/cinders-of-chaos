-- Trainer DPS meter (O573; client game_trainerdps, extended opcode ChaosOpcodes.trainerMeter = 147; rules:
-- trainer_meter_core.lua, numbers: trainer_meter_config.lua; server/README.md "Trainers as DPS meters (O573)").
--
-- Every training monster (a name with "train" or "dummy", trainer_meter_config.lua) measures the damage that the players
-- who hit it deal. Nothing about the training changes: no skill try is added or removed, the trainer never dies.
--   attribution  the combat log's (combatlog.lua `dealt`): every hit that reaches a monster of a character, its summons,
--                minions, wolves and pets counted for their owner, with the combat log's source (spell, rune, weapon attack,
--                damage over time, proc, summon) and element. combatlog.lua calls ChaosCombatLog.trainerHook for a hit on a
--                trainer and counts the whole hit there (no cap at the trainer's health)
--   session      one player's hits on one trainer (trainer_meter_core.lua): DPS now (the last windowMs), the average since
--                the first hit, total, time, biggest hit, rows by source and by element. It ends endAfterMs after the last
--                hit and its result stays until the next session; hitting another trainer starts another one
--   target       ChaosMonsterDefence.trainerProfile: the trainer defends like a normal / elite / boss monster of the
--                hitting player's level (or of a fixed level), see trainer_meter_config.lua `profile`
--
-- Protocol (JSON {action, data}):
--   client -> server  watch {on}   send me the summaries (the client's panel is on, or opens by itself)
--                     open         send the last result now (a state with `none` when there is none)
--                     reset        the session starts over (empty, on the same trainer)
--   server -> client  state {tn, tid, sid, act, end, empty, cur, avg, tot, hits, crits, max, mxn, dur, w, e, rows, el, prof,
--                     party?} or {none = 1}  (trainer_meter_core.lua M.view). Once a second while the session runs, once
--                     when it began, ended or was reset, never per hit.
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosTrainerMeterCore or not ChaosTrainerMeterCore.record then
	dofile("data/scripts/chaos/trainer_meter_core.lua")
end

Chaos.trainerMeterConfig = dofile("data/scripts/chaos/trainer_meter_config.lua")
local M = ChaosTrainerMeterCore
local cfg = M.configure(Chaos.trainerMeterConfig)
local OPCODE = ChaosOpcodes.trainerMeter or 147

ChaosTrainerMeter = ChaosTrainerMeter or {}
local T = ChaosTrainerMeter
T.cfg = cfg
T.reg = T.reg or M.newRegistry() -- player id -> session (kept over /reload)
T.watch = T.watch or {} -- player id -> {sig}

local function nowMs()
	return os.mtime and os.mtime() or os.time() * 1000
end

-- ---------------------------------------------------------------- who is a trainer
local trainerNames = {} -- monster name -> bool
local function isTrainer(creature)
	if not cfg.enabled or not creature or not creature:isMonster() then
		return false
	end
	local name = creature:getName()
	local r = trainerNames[name]
	if r == nil then
		r = M.isTrainerName(cfg, name)
		trainerNames[name] = r
	end
	return r
end
T.isTrainer = isTrainer

-- ---------------------------------------------------------------- the state sent
local function partyList(player, s, now)
	if not cfg.party then
		return nil
	end
	local party = player:getParty()
	if not party then
		return nil
	end
	local members = party:getMembers() or {}
	table.insert(members, 1, party:getLeader())
	local out = {}
	local pid = player:getId()
	for _, m in ipairs(members) do
		if m then
			local id = m:getId()
			local ms = T.reg.sess[id]
			if id == pid or (ms and ms.tid == s.tid and M.active(ms)) then
				local b = M.brief(cfg, ms or s, now)
				out[#out + 1] = {n = m:getName(), cur = b.cur, tot = b.tot, me = id == pid and 1 or nil}
			end
		end
	end
	if #out < 2 then
		return nil
	end
	table.sort(out, function(a, b)
		if a.tot ~= b.tot then
			return a.tot > b.tot
		end
		return a.n < b.n
	end)
	while #out > cfg.maxPartySent do
		out[#out] = nil
	end
	return out
end

local function send(player)
	local pid = player:getId()
	local s = T.reg.sess[pid]
	local w = T.watch[pid]
	local data
	if s then
		local now = nowMs()
		data = M.view(cfg, s, now, M.profileFor(cfg, s.name))
		data.party = partyList(player, s, now)
		local DS = ChaosDisplayScale
		if DS and DS.apply then
			data = DS.apply("trainerState", player, data)
		end
	else
		data = {none = 1}
	end
	if w then
		w.sig = M.signature(s)
	end
	Chaos.send(player, OPCODE, "state", data)
end
T.send = send

-- ---------------------------------------------------------------- the combat log's hook
-- a hit that reached a trainer: owner (the player, or the master of a summon), creature (the trainer), src (the combat log's
-- source), amount (whole hit), el (element name), crit (boolean), now (ms)
function T.onHit(owner, creature, src, amount, el, crit, now)
	local s, fresh = M.hit(cfg, T.reg, owner:getId(), creature:getId(), creature:getName(), now, amount, src, el, crit)
	if fresh and T.watch[owner:getId()] then
		send(owner)
	end
	return s
end

ChaosCombatLog = ChaosCombatLog or {}
ChaosCombatLog.isTrainer = isTrainer
ChaosCombatLog.trainerHook = T.onHit

-- ---------------------------------------------------------------- the target profile (monster_defence.lua)
ChaosMonsterDefence = ChaosMonsterDefence or {}
-- the profile of a trainer: {class, level}, level nil = the level of the player that hits; nil for every other monster
function ChaosMonsterDefence.trainerProfile(monster)
	if not isTrainer(monster) then
		return nil
	end
	return M.profileFor(cfg, monster:getName())
end
-- the level the trainer's armour is computed for when this player hits it
function ChaosMonsterDefence.trainerLevel(profile, player)
	local ok, level = pcall(function() return player:getLevel() end)
	return M.levelFor(cfg, profile, ok and level or 1)
end

-- ---------------------------------------------------------------- the clock: end a session, send the summary
local think = GlobalEvent("ChaosTrainerMeterThink")
function think.onThink(interval)
	local now = nowMs()
	for pid, s in pairs(T.reg.sess) do
		local player = Player(pid)
		if not player then
			T.reg.sess[pid] = nil
			T.watch[pid] = nil
		else
			if M.active(s) then
				if not Creature(s.tid) then
					s.ended = true -- the trainer is gone
					s.ver = s.ver + 1
				else
					M.tick(cfg, s, now)
				end
			end
			local w = T.watch[pid]
			if w and (M.active(s) or M.signature(s) ~= w.sig) then
				send(player)
			end
		end
	end
	return true
end
think:interval(cfg.sendMs)
think:register()

-- ---------------------------------------------------------------- login, logout, opcode
local login = CreatureEvent("ChaosTrainerMeterLogin")
function login.onLogin(player)
	player:registerEvent("ChaosTrainerMeterLogout")
	player:registerEvent("ChaosTrainerMeterExtended")
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosTrainerMeterLogout")
function logout.onLogout(player)
	local pid = player:getId()
	T.reg.sess[pid] = nil
	T.watch[pid] = nil
	return true
end
logout:type("logout")
logout:register()

-- a request that sends something at most every cfg.requestMs; a refused one is not lost: a watcher whose signature is unknown
-- (watch / open just set it) gets its state with the next tick
local function allowed(player)
	return not ChaosRateLimit or ChaosRateLimit.allow(player, "trainermeter", cfg.requestMs)
end

local ext = CreatureEvent("ChaosTrainerMeterExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE or not cfg.enabled then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg or type(msg.action) ~= "string" then
		return
	end
	local d = type(msg.data) == "table" and msg.data or {}
	local pid = player:getId()
	local action = msg.action
	if action == "watch" then
		if d.on == true then
			T.watch[pid] = {}
			if T.reg.sess[pid] and allowed(player) then
				send(player)
			end
		else
			T.watch[pid] = nil
		end
	elseif action == "open" then
		T.watch[pid] = T.watch[pid] or {}
		if allowed(player) then
			send(player)
		end
	elseif action == "reset" then
		if allowed(player) and M.reset(T.reg, pid) then
			send(player)
		end
	end
end
ext:type("extendedopcode")
ext:register()
