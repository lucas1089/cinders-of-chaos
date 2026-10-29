-- Hunt warnings (server/README.md "Hunt warnings (O323)"): a caution effect on, and a red message near, every hole, stairs,
-- ladder or teleport that leads from a weak hunt to much stronger, denser monsters (the list is written by
-- server/tools/audit_hunt_transitions.py into hunt_warnings_config.lua; docs/HUNT_TRANSITIONS.md). Nobody is blocked.
-- The rules are in hunt_warnings_core.lua (tests/hunt_warnings_test.lua), the numbers in hunt_warnings_config.lua.
-- Assumed engine API (TFS 1.4): GlobalEvent onThink / onStartup, Game.getPlayers, Player:getPosition/getId/isInGhostMode/
-- getStorageValue/setStorageValue/sendTextMessage, Position:sendMagicEffect, MESSAGE_STATUS_WARNING.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
dofile("data/scripts/chaos/hunt_warnings_core.lua")

ChaosHuntWarnings = ChaosHuntWarnings or {}
local HW = ChaosHuntWarnings
local W = ChaosHuntWarningsCore
HW.cfg = dofile("data/scripts/chaos/hunt_warnings_config.lua")
HW.index = W.index(HW.cfg.places)
HW.state = HW.state or W.newState()

local function effectId(name, fallback)
	local v = name and rawget(_G, "CONST_ME_" .. name)
	return v or fallback
end

local function text(player, m)
	if m.kind == "arrive" then
		return Chaos.t(player, "Caution: you are in an area of level %d+. Its monsters are much stronger.", m.level)
	end
	return Chaos.t(player, "Danger: much stronger monsters ahead (level %d+).", m.level)
end

function HW.pass()
	local cfg = HW.cfg
	local list = {}
	for _, player in ipairs(Game.getPlayers()) do
		local pos = player:getPosition()
		list[#list + 1] = {id = player:getId(), pos = {x = pos.x, y = pos.y, z = pos.z},
			lastWarn = math.max(0, player:getStorageValue(Chaos.storage.huntWarnLast)), ghost = player:isInGhostMode(),
			player = player}
	end
	local out = W.tick(HW.index, cfg, HW.state, list, os.time())
	local main, second = effectId(cfg.effect, cfg.effectId), effectId(cfg.effectExtreme, cfg.effectExtremeId)
	for _, e in ipairs(out.effects) do
		local at = Position(e.pos.x, e.pos.y, e.pos.z)
		at:sendMagicEffect(main)
		if e.extreme and second then
			at:sendMagicEffect(second)
		end
	end
	local byId = {}
	for _, pl in ipairs(list) do
		byId[pl.id] = pl.player
	end
	for _, m in ipairs(out.messages) do
		local player = byId[m.id]
		if player then
			player:sendTextMessage(MESSAGE_STATUS_WARNING, text(player, m))
			player:setStorageValue(Chaos.storage.huntWarnLast, os.time())
		end
	end
end

local ticker = GlobalEvent("ChaosHuntWarningsTick")
function ticker.onThink(interval)
	if HW.cfg.enabled and HW.index.count > 0 then
		local ok, err = pcall(HW.pass)
		if not ok then
			print("[hunt warnings] " .. tostring(err))
		end
	end
	return true
end
ticker:interval(HW.cfg.tickMs)
ticker:register()

local startup = GlobalEvent("ChaosHuntWarningsStartup")
function startup.onStartup()
	for _, problem in ipairs(W.validate(HW.cfg)) do
		print("[hunt warnings] hunt_warnings_config.lua: " .. problem)
	end
	return true
end
startup:register()
