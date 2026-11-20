-- ChaosSpellRanks: the read API of the spell ranks (O686 phase 2) for every Lua state (the spell scripts, the revscripts, the
-- passive tree's hit event). The state itself is written by data/scripts/chaos/spell_ranks.lua; this file only reads the packed
-- storage of a spell and answers the factors, and every answer is 1 while spell_ranks_config.lua `enabled` is false.
-- docs/SPELL_UPGRADES.md 1.5 and 5.3; tests: server/tests/spell_ranks_test.lua. Lua 5.1 / LuaJIT and Lua 5.3 compatible.

if not ChaosSpellRanksCore or not ChaosSpellRanksCore.power then
	dofile("data/scripts/chaos/spell_ranks_core.lua")
end
if not ChaosSpellRanksConfig then
	ChaosSpellRanksConfig = dofile("data/scripts/chaos/spell_ranks_config.lua")
end

ChaosSpellRanks = ChaosSpellRanks or {}
local R = ChaosSpellRanks
local P = ChaosSpellRanksCore

R.healIds = R.healIds or {} -- spell id -> true for the heal spells (filled by spell_ranks.lua from spells.xml)

local function cfg()
	return ChaosSpellRanksConfig
end

function R.enabled()
	return cfg().enabled == true
end

-- the rank of a spell id for a player (0 when none stored)
function R.rankOf(player, spellId)
	spellId = tonumber(spellId)
	local st = cfg().storage
	if not player or not spellId or spellId < 0 or spellId > st.maxSpellId then
		return 0
	end
	local v = player:getStorageValue(st.rankBase + spellId)
	local rank = P.unpack(v)
	return math.min(rank, cfg().maxRank)
end

-- the factor on one hit or heal of a spell: 1 while off, with pvp (the target is a player) at the PvP half rule
function R.factor(player, spellId, isHeal, pvp)
	if cfg().enabled ~= true then
		return 1
	end
	local rank = R.rankOf(player, spellId)
	if rank <= 0 then
		return 1
	end
	return P.power(rank, isHeal and true or false, pvp and true or false, cfg())
end

-- the spell id of the cast running now for this player (ChaosSupportsSpell.cast, the same context the combat log reads)
function R.castSpell(player)
	local W = rawget(_G, "ChaosSupportsSpell")
	if W and W.cast and player and player.getId then
		local pid, spellId = W.cast()
		if pid == player:getId() then
			return spellId
		end
	end
	local S = rawget(_G, "ChaosSupports")
	if S and S.ctxDecode and S.config and player and player.getStorageValue then
		local _, id = S.ctxDecode(player:getStorageValue(S.config.storageContext))
		return id
	end
	return nil
end

-- the factor of one damage or heal value of a player's hit (the hook of ChaosPassiveDealt, passivetree_effects.lua): only the
-- hits of a spell (ORIGIN_SPELL) inside a spell's cast context; a proc, a tick of the engine's own conditions and a weapon hit
-- get 1. ctype = the combat type of the value (COMBAT_HEALING for a heal).
function R.hitFactor(attacker, creature, origin, ctype)
	if cfg().enabled ~= true or origin ~= ORIGIN_SPELL or not ctype or ctype == COMBAT_NONE or ctype == 0 then
		return 1
	end
	if not attacker or not attacker.isPlayer or not attacker:isPlayer() then
		return 1
	end
	local spellId = R.castSpell(attacker)
	if not spellId then
		return 1
	end
	local pvp = creature and creature.isPlayer and creature:isPlayer() and creature ~= attacker
	return R.factor(attacker, spellId, ctype == COMBAT_HEALING, pvp)
end

-- the multiplier of the monster health at a level, 1 while off (read by every system that sizes monster health; phase 3)
function R.healthFactor(level)
	if cfg().enabled ~= true then
		return 1
	end
	return P.healthFactor(level, cfg())
end

-- the mana cost and the cooldown of a ranked cast, the rank's part only (the events of spell_ranks.lua call these)
function R.manaFor(player, spellId, mana)
	if cfg().enabled ~= true then
		return mana
	end
	return P.mana(mana, R.rankOf(player, spellId), R.healIds[spellId] == true, cfg())
end

function R.cooldownFor(player, spellId, ms)
	if cfg().enabled ~= true then
		return ms
	end
	return P.cooldown(ms, R.rankOf(player, spellId), R.healIds[spellId] == true, cfg())
end

return R
