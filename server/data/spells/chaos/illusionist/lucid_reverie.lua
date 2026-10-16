-- Lucid Reverie: a shared waking dream. The Illusionist and every party member within 7 sqm are healed 5 times, every
-- 2 seconds (a heal over time that follows them: a member farther than 10 sqm or on another floor misses the pulse).
-- Numbers: ChaosHealing.cfg.lucidReverie (data/scripts/chaos/healing_rules_core.lua). Weaver's Grace and the PvP
-- healing reduction apply to every pulse through data/scripts/chaos/healing_rules.lua. Stops if the Illusionist dies
-- or logs out.
dofile('data/spells/scripts/chaos/_common.lua')
if not ChaosMysticFx then
	pcall(dofile, 'data/lib/chaos_mystic_fx.lua')
end
if not (ChaosHealing and ChaosHealing.values) then
	dofile('data/scripts/chaos/healing_rules_core.lua')
end

local H = ChaosHealing

local function near(a, b, range)
	return a.z == b.z and math.max(math.abs(a.x - b.x), math.abs(a.y - b.y)) <= range
end

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local cfg = H.cfg.lucidReverie
	local ids = {}
	for _, ally in ipairs(ChaosSpell.alliesAround(player, player:getPosition(), cfg.range, false)) do
		if ally:isPlayer() then
			ids[#ids + 1] = ally:getId()
		end
	end
	local min, max = H.values(player:getLevel(), player:getMagicLevel(), cfg)
	ChaosSpell.vfxOr(player:getPosition(), "starfall_crown", "arcane_aura", CONST_ME_PURPLEENERGY)
	ChaosSpell.pulse(player:getId(), cfg.pulses, cfg.intervalMs, function(caster, step)
		local cpos = caster:getPosition()
		for _, id in ipairs(ids) do
			local ally = Player(id)
			if ally and ally:getHealth() > 0 and near(cpos, ally:getPosition(), cfg.followRange) then
				-- each pulse: the regeneration tick (pack cut tick_regen) on every member instead of the stock sparkle
				-- (server/data/spells/README_FX.md "Mystic line effects")
				local pulseFx = step == 1 and CONST_ME_PURPLEENERGY or CONST_ME_MAGIC_BLUE
				if ChaosMysticFx and ChaosMysticFx.send(ally:getPosition(), "tick_regen") then
					pulseFx = CONST_ME_NONE
				end
				ChaosSpell.healTarget(caster, ally, min, max, pulseFx)
			end
		end
		return true
	end)
	return true
end
