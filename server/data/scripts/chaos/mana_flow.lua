-- mana_flow.lua: the engine glue of the mana flow (server/README.md "Mana flow"). Rules: mana_flow_core.lua (pure,
-- tested), numbers: mana_flow_config.lua.
--   * a think every regen.thinkMs over the online players: addMana by level (none under the rift's Parched Veins);
--   * ChaosSpellEvents "cost" (engine patch 0008): the cap of a cast's cost against the maximum mana.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosManaFlow then
	dofile("data/scripts/chaos/mana_flow_core.lua")
end

local F = ChaosManaFlow

local function reservedOf(pid)
	local a = ChaosVigils and ChaosVigils.applied and ChaosVigils.applied[pid]
	return a and a.mana or 0
end

local function parched(pid)
	local run = ChaosRift and ChaosRift.runOf and ChaosRift.runOf[pid]
	return run ~= nil and run.fx ~= nil and run.fx.noMana == true
end

function F.think()
	for _, player in ipairs(Game.getPlayers()) do
		local pid = player:getId()
		local give = F.regenAmount(player:getLevel(), player:getMana(), player:getMaxMana(), parched(pid),
			player:getHealth() <= 0)
		if give > 0 then
			player:addMana(give)
		end
	end
end

local thinkEvent = GlobalEvent("ChaosManaFlowThink")
function thinkEvent.onThink(interval)
	local ok, err = pcall(F.think)
	if not ok then
		print("[ChaosManaFlow] think: " .. tostring(err))
	end
	return true
end
thinkEvent:interval(ChaosManaFlowConfig.regen.thinkMs)
thinkEvent:register()

if ChaosSpellEvents and ChaosSpellEvents.set then
	ChaosSpellEvents.set("cost", "manaflow", function(player, name, id, group, aggressive, mana, health)
		return F.capCost(mana, player:getLevel(), player:getMaxMana(), reservedOf(player:getId())), health
	end)
end
