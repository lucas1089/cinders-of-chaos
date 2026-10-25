-- mana_flow.lua: the engine glue of the mana flow (server/README.md "Mana flow"). Rules: mana_flow_core.lua (pure,
-- tested), numbers: mana_flow_config.lua.
--   * a think every regen.thinkMs over the online players: addMana by level (none under the rift's Parched Veins).
-- No spell cost hook: a spell costs its fixed number (server/README.md "Fixed spell costs").

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosManaFlow then
	dofile("data/scripts/chaos/mana_flow_core.lua")
end

local F = ChaosManaFlow

local function parched(pid)
	local run = ChaosRift and ChaosRift.runOf and ChaosRift.runOf[pid]
	return run ~= nil and run.fx ~= nil and run.fx.noMana == true
end

function F.think()
	for _, player in ipairs(Game.getPlayers()) do
		local give = F.thinkPlayer(player, parched)
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

-- the cost cap of 2026-10-20 registered a "cost" handler under this key; handlers survive a /reload, so a server that
-- ran the old script drops it here (fixed spell costs: nothing but percentages may change a cost)
if ChaosSpellEvents and ChaosSpellEvents.remove then
	ChaosSpellEvents.remove("cost", "manaflow")
end
