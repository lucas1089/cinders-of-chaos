-- Pair 29 VFX packs, the engine glue (data/lib/chaos_pack29_vfx.lua; server/README.md "Condition auras, blasts and
-- fireworks (pair 29)"). Switch: ChaosPack29Fx.PAIR29 (off: no override is set, no aura, the stock level-up).
--   * startup: the engine overrides of src-patch 0045 (condition ticks, hit splashes, element blasts, missiles);
--   * every C.scanMs: the auras of the online players' engine states that no Lua call site knows (a monster's or a
--     rune's paralyze, drunkenness, a spell regeneration);
--   * a new level: the level-up firework over the character. The base advance_save.lua sends no effect
--     (config.effect = false); the level-up wings (levelwings.lua) and the pair 27 rise stay.
-- Lua 5.1 / LuaJIT / 5.3.

if not ChaosPack29Vfx then
	dofile("data/lib/chaos_pack29_vfx.lua")
end
local V = ChaosPack29Vfx

local startup = GlobalEvent("ChaosPack29VfxStartup")
function startup.onStartup()
	local ok, n = pcall(V.applyEngine)
	if not ok then
		print("[ChaosPack29Vfx] engine overrides: " .. tostring(n))
	elseif n > 0 then
		print("[ChaosPack29Vfx] " .. n .. " hit effect and missile overrides set")
	end
	return true
end
startup:register()

-- engine state -> aura, for the players' scan (condition type name, condition id name or nil = any, state)
V.scan = V.scan or {
	{"CONDITION_PARALYZE", nil, "slowed"},
	{"CONDITION_DRUNK", nil, "confused"},
	{"CONDITION_REGENERATION", "CONDITIONID_COMBAT", "regeneration"}, -- a spell's regeneration, not the food one
}

local function scanPlayer(player)
	for _, row in ipairs(V.scan) do
		local ctype = _G[row[1]]
		if ctype then
			local cond
			if row[2] then
				cond = _G[row[2]] and player:getCondition(ctype, _G[row[2]])
			else
				cond = player:hasCondition(ctype)
			end
			if cond then
				V.show(player, row[3])
			end
		end
	end
end

local scan = GlobalEvent("ChaosPack29VfxScan")
function scan.onThink(interval)
	if not V.live() then
		return true
	end
	for _, player in ipairs(Game.getPlayers()) do
		pcall(scanPlayer, player)
	end
	return true
end
scan:interval(V.scanMs)
scan:register()

local login = CreatureEvent("ChaosPack29VfxLogin")
function login.onLogin(player)
	player:registerEvent("ChaosPack29VfxAdvance")
	return true
end
login:register()

local advance = CreatureEvent("ChaosPack29VfxAdvance")
function advance.onAdvance(player, skill, oldLevel, newLevel)
	if skill == SKILL_LEVEL and newLevel > oldLevel then
		pcall(V.celebrate, player:getPosition(), "levelup")
	end
	return true
end
advance:register()
