-- vigils.lua: the engine glue of the vigils (ChaosVigils; docs/BUILDS.md "Vigils", server/README.md "Vigils"). Rules:
-- vigils_core.lua (pure, tested), numbers: vigils_config.lua. The toggle spells write the storage
-- (data/spells/chaos/_vigils.lua); this file does the rest:
--   * a think every thinkMs over the online players: who holds vigils (the storage), the reservation of each holder (a
--     CONDITION_ATTRIBUTES with a negative maximum mana, or health with Iron Tithe, sized from the unreserved maximum
--     and refreshed whenever it changes: level, items, tree, Aether Edge), whom each holder covers (itself and its party
--     members within the radius on its floor; Iron Tithe and a multi-client holder: itself only), Haste as a haste
--     condition, Clarity's mana (none under the rift's Parched Veins);
--   * ChaosVigils.dealt / ChaosVigils.taken: the hit multipliers archetypes.lua applies in its onHealthChange (Wrath:
--     not on top of Inspiring Illusion; Iron: not on top of the Templar defence aura);
--   * ChaosVigils.buffItem: the buff bar rows (data/lib/chaos_buffs.lua source "vigils", texts in vigils_core.lua).
-- Vigils that no longer fit (a unique taken off) are switched off, the last first, with a message.

if not (Chaos and Chaos.t) then
	if not Chaos then
		dofile("data/scripts/chaos/chaos_constants.lua")
	end
	dofile("data/scripts/chaos/i18n_core.lua")
end
if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosVigilsCore then
	dofile("data/scripts/chaos/vigils_core.lua")
end
if not ChaosArchetypesCore then
	dofile("data/scripts/chaos/archetypes_core.lua")
end

ChaosVigils = ChaosVigils or {}
local M = ChaosVigils
local V = ChaosVigilsCore
local A = ChaosArchetypesCore
local function cfg()
	return ChaosVigilsConfig
end

local function now()
	return os.mtime and os.mtime() or os.time() * 1000
end

M.applied = M.applied or {} -- player id -> {mana = reserved, health = reserved}
M.covered = M.covered or {} -- player id -> {entry = {wrath, iron, haste, clarity}, untilTime}
M.holders = M.holders or {} -- player id -> mask (the holders of the last think)
M.holderMods = M.holderMods or {} -- player id -> mods (the holders of the last think; the buff bar reads them)

local function isMultiClient(player)
	return Chaos and Chaos.isMultiClient and Chaos.isMultiClient(player) or false
end

-- the mods of a player: the archetype keystones and uniques the scripts already know (archetypes.lua), else the
-- storage and the worn items
function M.mods(player)
	local pid = player:getId()
	local flags = ChaosArchetypes and ChaosArchetypes.flags and ChaosArchetypes.flags[pid]
	if not flags and ChaosArchetypesConfig then
		flags = A.flagsOfMask(player:getStorageValue(ChaosArchetypesConfig.storage))
	end
	local uniques = ChaosArchetypes and ChaosArchetypes.uniques and ChaosArchetypes.uniques[pid] or A.wornUniques(player)
	return V.modsOf(flags or {}, uniques or {}, isMultiClient(player))
end

local function partyKey(player)
	local party = player:getParty()
	local leader = party and party:getLeader()
	return leader and leader:getId() or nil
end

local function copyPos(p)
	return {x = p.x, y = p.y, z = p.z}
end

-- ------------------------------------------------------------------------------------------------ the reservation
local KINDS = {
	mana = {get = "getMaxMana", stat = "CONDITION_PARAM_STAT_MAXMANAPOINTS"},
	health = {get = "getMaxHealth", stat = "CONDITION_PARAM_STAT_MAXHITPOINTS"},
}

local function syncPool(player, kind, share)
	local pid = player:getId()
	local a = M.applied[pid] or {}
	M.applied[pid] = a
	local cur = a[kind] or 0
	local subId = cfg().subIds[kind]
	local has = player:getCondition(CONDITION_ATTRIBUTES, CONDITIONID_COMBAT, subId) ~= nil
	if cur > 0 and not has then
		cur = 0 -- the condition went (death): the maximum is unreserved again
	end
	local base = player[KINDS[kind].get](player) + cur
	local want = math.min(V.reserved(base, share), math.max(0, base - 1))
	if want == cur and (want == 0) == not has then
		a[kind] = cur
		return
	end
	if has then
		player:removeCondition(CONDITION_ATTRIBUTES, CONDITIONID_COMBAT, subId)
	end
	if want > 0 and Condition then
		local c = Condition(CONDITION_ATTRIBUTES, CONDITIONID_COMBAT)
		c:setParameter(CONDITION_PARAM_SUBID, subId)
		c:setParameter(CONDITION_PARAM_TICKS, -1)
		c:setParameter(_G[KINDS[kind].stat], -want)
		player:addCondition(c)
	end
	a[kind] = want
end

-- the reservation of a player for its mask (0 removes it)
function M.syncReserve(player, mask, mods)
	local share = mask > 0 and V.totalReserve(mask, mods) or 0
	local tithe = mods and mods.tithe
	syncPool(player, "mana", tithe and 0 or share)
	syncPool(player, "health", tithe and share or 0)
end

-- ------------------------------------------------------------------------------------------------ the effects
local function parched(pid)
	local run = ChaosRift and ChaosRift.runOf and ChaosRift.runOf[pid]
	return run ~= nil and run.fx ~= nil and run.fx.noMana == true
end
M.parched = parched

local function applyEffects(player, entry)
	local haste = V.haste(entry)
	if haste > 0 and Condition then
		local c = Condition(CONDITION_HASTE, CONDITIONID_COMBAT)
		c:setParameter(CONDITION_PARAM_SUBID, cfg().subIds.haste)
		c:setParameter(CONDITION_PARAM_TICKS, cfg().holdMs)
		c:setFormula(haste, 0, haste, 0)
		player:addCondition(c)
	end
	local mana = V.clarityMana(entry, player:getMaxMana(), parched(player:getId()))
	if mana > 0 and player:getMana() < player:getMaxMana() then
		player:addMana(mana)
	end
end

-- ------------------------------------------------------------------------------------------------ the think
local function holderOf(player, t)
	local storage = cfg().storage
	local mask = math.max(0, tonumber(player:getStorageValue(storage)) or 0)
	local pid = player:getId()
	if mask == 0 then
		if M.applied[pid] then
			M.syncReserve(player, 0, nil)
			M.applied[pid] = nil
		end
		return nil
	end
	local mods = M.mods(player)
	local fitted = V.fit(mask, mods)
	if fitted ~= mask then
		player:setStorageValue(storage, fitted)
		for _, key in ipairs(V.keys(mask)) do
			if not V.has(fitted, key) then
				player:sendTextMessage(MESSAGE_INFO_DESCR or 1, Chaos.t(player, "%s ends: your vigils would reserve more than all of your %s",
					V.byKey[key].def.name, mods.tithe and Chaos.t(player, "health.") or Chaos.t(player, "mana.")))
			end
		end
		mask = fitted
	end
	M.syncReserve(player, mask, mods)
	if mask == 0 then
		return nil
	end
	return {id = pid, pos = copyPos(player:getPosition()), party = partyKey(player), mask = mask, mods = mods,
		player = player}
end

function M.think()
	local t = now()
	local holders, candidates, seen = {}, {}, {}
	local fresh, freshMods = {}, {}
	for _, player in ipairs(Game.getPlayers() or {}) do
		local ok, h = pcall(holderOf, player, t)
		if not ok then
			print("[ChaosVigils] " .. tostring(h))
		elseif h then
			holders[#holders + 1] = h
			fresh[h.id] = h.mask
			freshMods[h.id] = h.mods
			-- the holder and its party members are the only players it can cover
			local list = {h.player}
			local party = h.player:getParty()
			if party then
				for _, m in ipairs(party:getMembers() or {}) do
					list[#list + 1] = m
				end
				list[#list + 1] = party:getLeader()
			end
			for _, p in ipairs(list) do
				if p and not seen[p:getId()] then
					seen[p:getId()] = true
					candidates[#candidates + 1] = {id = p:getId(), pos = copyPos(p:getPosition()), party = partyKey(p),
						dead = p:getHealth() <= 0, player = p}
				end
			end
		end
	end
	M.holders, M.holderMods = fresh, freshMods
	-- the players who left: their reservation memory
	for pid in pairs(M.applied) do
		if not Player(pid) then
			M.applied[pid] = nil
		end
	end
	local covered = V.coverage(holders, candidates)
	for _, c in ipairs(candidates) do
		local entry = covered[c.id]
		if entry then
			M.covered[c.id] = {entry = entry, untilTime = t + cfg().holdMs}
			local ok, err = pcall(applyEffects, c.player, entry)
			if not ok then
				print("[ChaosVigils] effects: " .. tostring(err))
			end
		end
	end
	for pid, c in pairs(M.covered) do
		if c.untilTime < t or not Player(pid) then
			M.covered[pid] = nil
		end
	end
end

-- a toggle from the spells (same Lua state): the next think at once
function M.refresh(player)
	M.think()
end

local thinkEvent = GlobalEvent("ChaosVigilsThink")
function thinkEvent.onThink(interval)
	local ok, err = pcall(M.think)
	if not ok then
		print("[ChaosVigils] think: " .. tostring(err))
	end
	return true
end
thinkEvent:interval(ChaosVigilsConfig.thinkMs)
thinkEvent:register()

-- ------------------------------------------------------------------------------------------------ the hit rules
local function entryOf(pid, t)
	local c = M.covered[pid]
	if c and c.untilTime >= t then
		return c.entry
	end
	return nil
end

-- the Inspiring Illusion bonus a party member's hit gets (passivetree_keystones.lua: a giver within range, not the
-- attacker, no multi-client)
local function inspireBonus(attacker)
	local party = attacker:getParty()
	if not party or isMultiClient(attacker) then
		return 0
	end
	local members = party:getMembers() or {}
	members[#members + 1] = party:getLeader()
	local apos = attacker:getPosition()
	for _, m in ipairs(members) do
		local b = m and ChaosPassiveCache and ChaosPassiveCache[m:getId()]
		if b and b.ksInspiringIllusion and m:getId() ~= attacker:getId() and not isMultiClient(m)
				and V.distance(m:getPosition(), apos) <= cfg().inspire.range then
			return cfg().inspire.bonus
		end
	end
	return 0
end

-- the multiplier of a hit dealt by a covered player (1 when not covered)
function M.dealt(attacker)
	local entry = entryOf(attacker:getId(), now())
	if not entry or not entry.wrath then
		return 1
	end
	return V.dealtFactor(entry, inspireBonus(attacker))
end

-- the multiplier of a hit taken by a covered player
function M.taken(player)
	local t = now()
	local entry = entryOf(player:getId(), t)
	if not entry or not entry.iron then
		return 1
	end
	local aura = ChaosTemplar and ChaosTemplar.activeAura and ChaosTemplar.activeAura(player:getId(), t)
	return V.takenFactor(entry, aura and aura.reduction or 0)
end

-- a row of the buff bar (data/lib/chaos_buffs.lua source "vigils"): key = a vigil's key or "tithe"; nil when it does
-- not apply. Reads what the last think saw (the cover, the holder's mask and mods): no engine call.
function M.buffItem(player, key, t)
	local pid = player:getId()
	local entry = entryOf(pid, t or now())
	local mask = M.holders[pid]
	if not entry and not mask then
		return nil
	end
	return V.buffItem(key, entry, mask, mask and M.holderMods[pid] or nil, parched(pid), Chaos.lang and Chaos.lang(player))
end

-- is anyone covered at all (archetypes.lua skips the work otherwise)
function M.any(pid)
	return M.covered[pid] ~= nil
end

return M
