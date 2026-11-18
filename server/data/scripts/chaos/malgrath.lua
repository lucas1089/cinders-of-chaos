-- Malgrath, the Drowned Crown (O637): the arrival and the death of the boss as effects that carry its body (data/lib/chaos_malgrath_fx.lua,
-- client pair 74). Its attacks are played by boss_mechanics.lua (the `pose` of the profile rows). Overview: server/README.md
-- "Malgrath, the Drowned Crown (O637)". Engine API used: EventCallback onSpawn, Monster:registerEvent / unregisterEvent,
-- CreatureEvent onThink / onDeath. Below client pair 74 nothing is registered: the lib's gate is closed and the boss does not spawn.

local function lib()
	if ChaosMalgrathFx == nil then
		ChaosMalgrathFx = false
		pcall(dofile, "data/lib/chaos_malgrath_fx.lua")
	end
	return ChaosMalgrathFx
end

-- its first think: the rise plays, the boss hidden until it ends
local rise = CreatureEvent("ChaosMalgrathRise")
function rise.onThink(creature, interval)
	creature:unregisterEvent("ChaosMalgrathRise")
	local L = lib()
	if L and creature:isMonster() and creature:getId() ~= 0 then
		pcall(L.rise, creature)
	end
	return true
end
rise:register()

-- its death: the collapse on its tile
local death = CreatureEvent("ChaosMalgrathDeath")
function death.onDeath(creature, corpse, killer, mostDamageKiller, lastHitUnjustified, mostDamageUnjustified)
	local L = lib()
	if L then
		pcall(L.death, creature:getPosition())
	end
	return true
end
death:register()

local spawnCb = EventCallback
spawnCb.onSpawn = function(self, position, startup, artificial)
	local L = lib()
	if L and L.live() and self:getName() == L.MONSTER then
		self:registerEvent("ChaosMalgrathRise")
		self:registerEvent("ChaosMalgrathDeath")
	end
	return true
end
spawnCb:register(11)
