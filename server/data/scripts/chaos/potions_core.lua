-- Potions: pure rules (no engine calls), shared by potions.lua, data/lib/chaos_potions.lua and
-- server/tests/potions_test.lua. README "Potions".
--   ChaosPotionsCore.everfull(cfg, id)        the Everfull entry of a server id, or nil
--   ChaosPotionsCore.isFlask(cfg, id)          an old empty flask id
--   ChaosPotionsCore.drink(cfg, s)             s = {id, exhausted, target[, level]} -> {ok, health, mana, consume} | {ok = false, why, text}
--                                              The flasks never empty (O273): a drink spends and needs nothing but the level and the wait.
--   ChaosPotionsCore.amount(cfg, range, level, max, bonusPct[, rand, tier])  one drink: fixed roll + percent of max
--   ChaosPotionsCore.grantDue(cfg, s)          s = {granted, lastLogin} -> true when a login grant is due
--   O245 tiers (README "Potions", "Higher tiers"): an entry has tier, level, line (health | mana | spirit), from (the
--   server ids it is made from) and pools (the potion waits a drink sets, default its key).
--   ChaosPotionsCore.poolsOf(cfg, entry)          the waits a drink of this entry sets and honours
--   ChaosPotionsCore.upgradeTargets(cfg)           the entries made from another one (`from`: tier 2 and up, and the
--                                                  tier 1 spirit potion), in config order = the order of their flags
--   ChaosPotionsCore.materialOf(cfg, e)            {id, count, name}: what Veyra's task takes for an entry
--   ChaosPotionsCore.upgradeStorage(cfg, id)       the player storage key that says "this tier was earned"
--   ChaosPotionsCore.upgradeCoins(cfg, id)         the store price of a tier
--   ChaosPotionsCore.upgradeCheck(cfg, s)          s = {id, level, installed, done, held = {ids}, mode, materials}
--                                                  -> {ok, from, materials} | {ok = false, why, text, args}
--   ChaosPotionsCore.restoreFor(cfg, slot, held, earned, granted)  the entry a character that lost its flask gets back, or nil
--   O246 (client helper, opcode ChaosOpcodes.everfull): ChaosPotionsCore.heldView(cfg, s) / heldKey(view) / heldPayload(view):
--                                                  the Everfull potion each slot carries, by its stock look, for the helper
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
ChaosPotionsCore = ChaosPotionsCore or {}
local K = ChaosPotionsCore

function K.everfull(cfg, id)
	for _, e in ipairs(cfg.everfull or {}) do
		if e.id == id then
			return e
		end
	end
	return nil
end

function K.isFlask(cfg, id)
	for _, f in ipairs(cfg.flasks or {}) do
		if f == id then
			return true
		end
	end
	return false
end

-- the waits (health, mana) a drink of this entry sets and honours; a spirit potion has both
function K.poolsOf(cfg, e)
	return e.pools or {e.key}
end

-- one drink of an Everfull potion. target: "self" (no target, an item, the drinker), "player" (another player) or
-- "creature" (a monster or an NPC: refused like the stock potion, the use goes on to the engine). The potion is never
-- consumed, spends nothing (the flasks never empty, O273) and never leaves a flask; the level gate and the exhaust
-- are the stock potions' ones.
function K.drink(cfg, s)
	local e = K.everfull(cfg, s.id)
	if not e then
		return {ok = false, why = "unknown"}
	end
	if s.target == "creature" then
		return {ok = false, why = "target"}
	end
	-- the stock potion's level (a tier of O245): the drinker's, whoever is healed
	if (e.level or 0) > 0 and s.level ~= nil and (tonumber(s.level) or 0) < e.level then
		return {ok = false, why = "level", level = e.level,
			text = "Only characters of level %d or above may drink this fluid.", args = {e.level}}
	end
	if s.exhausted then
		return {ok = false, why = "exhausted", text = "You are exhausted."}
	end
	return {ok = true, kind = e.key, pools = K.poolsOf(cfg, e), health = e.health, mana = e.mana, consume = false}
end

-- the amount of one potion drink: a roll inside range (the fixed part) + percent(level) of max, then x (1 + bonusPct)
-- tier: an Everfull potion's tier (amount.everfullPct gives its percent, the same at every character level); nil for
-- a stock potion, which uses the level curve
function K.percent(cfg, level, tier)
	local a = cfg.amount or {}
	local own = tier and (a.everfullPct or {})[tier]
	if own then
		return own
	end
	return math.min(a.cap or 0, (a.base or 0) + (a.perLevel or 0) * math.max(0, tonumber(level) or 0))
end

function K.amount(cfg, range, level, max, bonusPct, rand, tier)
	rand = rand or math.random
	local lo, hi = math.floor(range[1] or 0), math.floor(range[2] or range[1] or 0)
	local v = (hi > lo and rand(lo, hi) or lo) + math.max(0, max or 0) * K.percent(cfg, level, tier) / 100
	return math.floor(v * (1 + math.max(0, bonusPct or 0) / 100) + 0.5)
end

-- the lock value an Everfull potion carries (cfg.bindLock: bound, not drawn grey), and whether an item's current value
-- must change to it (a potion given before 2026-10-16 carries 1, the grey player lock)
function K.bindLock(cfg)
	return cfg.bindLock or 1
end

function K.needsRebind(cfg, value)
	return tonumber(value) ~= K.bindLock(cfg)
end

-- the one-time grant at login: characters made before the Everfull potions (a new character gets them with its
-- starter kit, which sets the flag; lastLogin 0 = brand new, the kit comes a moment later)
function K.grantDue(cfg, s)
	if s.granted then
		return false
	end
	return (s.lastLogin or 0) > 0
end

-- ---------------------------------------------------------------- higher tiers (README "Potions", "Higher tiers", O245)
-- An entry made from another one (`from`) is an upgrade: tier 2 and up, and the tier 1 spirit potion (O247, made from the
-- tier 1 health potion). Only the others (the tier 1 health and mana potions) are given: nothing is sold (O273).
function K.isUpgrade(e)
	return e ~= nil and type(e.from) == "table" and #e.from > 0
end

function K.upgradeTargets(cfg)
	local out = {}
	for _, e in ipairs(cfg.everfull or {}) do
		if K.isUpgrade(e) then
			out[#out + 1] = e
		end
	end
	return out
end

-- the storage key of a tier 2+ entry (its place among the tiers 2+), nil for any other id
function K.upgradeStorage(cfg, id)
	for i, e in ipairs(K.upgradeTargets(cfg)) do
		if e.id == id then
			return cfg.storage.upgradeBase + i - 1
		end
	end
	return nil
end

function K.upgradeCoins(cfg, id)
	local e = K.everfull(cfg, id)
	return e and K.isUpgrade(e) and ((cfg.upgrade or {}).coins or {})[e.tier or 1] or nil
end

-- what Veyra's task takes for an entry: the stock potion it copies (sourceId) x upgrade.materials, unless the entry names
-- its own (materialId / materialCount / materialName: the tier 1 spirit potion has no stock potion of its tier, the
-- supreme mana and spirit potions none at all). name: the plural, what she says ("great health potions").
function K.materialOf(cfg, e)
	local name = e.materialName or (tostring(e.name):gsub("^everfull ", "") .. "s")
	return {id = e.materialId or e.sourceId, count = e.materialCount or (cfg.upgrade or {}).materials or 0, name = name}
end

local function isFrom(e, id)
	for _, f in ipairs(e.from or {}) do
		if f == id then
			return true
		end
	end
	return false
end

-- Whether a character may swap its flask for the entry s.id (a tier, or the tier 1 spirit potion). mode "quest" (Veyra: needs s.materials stock potions, the
-- count the character carries) or "store" (coins). Same level gate, same previous tier, same once per tier in both.
-- s.held: the server ids of every Everfull item the character has (a tier it holds twice is listed twice); only the
-- ones of the same slot count. The previous tier must be the ONLY item of the slot: none (lost, or not carried in
-- the backpack, inbox or a depot) and more than one are refused. Nothing is taken here.
function K.upgradeCheck(cfg, s)
	local e = K.everfull(cfg, s.id)
	if not e or not K.isUpgrade(e) then
		return {ok = false, why = "unknown", text = "This offer cannot be bought."}
	end
	if not s.installed then
		return {ok = false, why = "installed", text = "This offer is not available."}
	end
	if s.done then
		return {ok = false, why = "done", text = "You already have this upgrade."}
	end
	local count, heldId = 0, nil
	for _, id in ipairs(s.held or {}) do
		local x = K.everfull(cfg, id)
		if x and x.key == e.key then
			count = count + 1
			heldId = id
		end
	end
	if count == 0 then
		return {ok = false, why = "missing",
			text = "Carry your Everfull potion in your backpack, your inbox or a depot: the upgrade replaces it."}
	end
	if count > 1 then
		return {ok = false, why = "duplicate", text = "You hold more than one Everfull potion of this kind. Keep only one."}
	end
	if not isFrom(e, heldId) then
		return {ok = false, why = "tier", text = "This upgrade needs a different flask than the one you hold."}
	end
	if (tonumber(s.level) or 0) < (e.level or 0) then
		return {ok = false, why = "level", text = "This flask is for level %d and up, and you are not there yet.", args = {e.level}}
	end
	local need = s.mode == "quest" and K.materialOf(cfg, e).count or 0
	if need > 0 and (tonumber(s.materials) or 0) < need then
		return {ok = false, why = "materials", need = need,
			text = "Bring me %d %s and your flask.", args = {need, tostring(s.materialName or "potions")}}
	end
	return {ok = true, from = heldId, materials = need}
end

-- The tier 1 potion of a slot (the one the starter kit and the login grant give), or nil.
function K.baseFor(cfg, slot)
	for _, e in ipairs(cfg.everfull or {}) do
		if e.key == slot and (e.tier or 1) == 1 and not K.isUpgrade(e) then
			return e
		end
	end
	return nil
end

-- A character that no longer has any Everfull item of a slot (held: the server ids of every Everfull item it has) gets
-- back the highest tier it earned (earned: the entries whose storage flag is set); without an earned tier, the tier 1
-- potion of the slot when it was given in the first place (granted: the grant flag, set by the starter kit and by the
-- login grant). A tier 1 potion is no longer sold (O273), so this is the way back when one is lost (a GM delete, a bug).
function K.restoreFor(cfg, slot, held, earned, granted)
	for _, id in ipairs(held or {}) do
		local x = K.everfull(cfg, id)
		if x and x.key == slot then
			return nil
		end
	end
	local best
	for _, e in ipairs(earned or {}) do
		if e.key == slot and (not best or (e.tier or 1) > (best.tier or 1)) then
			best = e
		end
	end
	if not best and granted then
		best = K.baseFor(cfg, slot)
	end
	return best
end

-- ---------------------------------------------------------------- what the helper is told (README "Potions", O246)
-- The client sees every tier under the stock potion's look, so the helper cannot tell which Everfull a character carries.
-- The server tells it: per slot (health, mana) the carried Everfull's look, tier, level, line and whether a drink would
-- work now. s.counts: server id -> how many the character carries (inventory and backpacks, as Player:getItemCount);
-- s.clientId(serverId) -> the client id (the look). A slot holding two items (a GM gift) reports the highest tier: the
-- engine's use by look picks one of them. `ready` is always true since O273 (no charges to run out); the field stays
-- so the client's rule ("follow a ready, plain, allowed Everfull") needs no change.
-- Returns { health = {look, tier, level, line, ready}, mana = {...} }, a slot with no Everfull left out.
function K.heldView(cfg, s)
	local view = {}
	for _, e in ipairs(cfg.everfull or {}) do
		local n = tonumber((s.counts or {})[e.id]) or 0
		local look = n > 0 and s.clientId and tonumber(s.clientId(e.id)) or nil
		if look and look > 0 then
			local slot = e.key
			local best = view[slot]
			if not best or (e.tier or 1) > best.tier then
				view[slot] = {look = look, tier = e.tier or 1, level = e.level or 0, line = e.line or e.key, ready = true}
			end
		end
	end
	return view
end

-- a string that changes when anything the client is told changes (a push is sent only then)
function K.heldKey(view)
	local parts = {}
	for _, slot in ipairs({"health", "mana"}) do
		local v = view[slot]
		parts[#parts + 1] = v and string.format("%s:%d:%d:%d:%s:%d", slot, v.look, v.tier, v.level, v.line, v.ready and 1 or 0) or (slot .. ":-")
	end
	return table.concat(parts, "|")
end

-- the message data: v is a version, so an empty view still encodes as an object
function K.heldPayload(view)
	local out = {v = 1}
	for _, slot in ipairs({"health", "mana"}) do
		local x = view[slot]
		if x then
			out[slot] = {look = x.look, tier = x.tier, level = x.level, line = x.line, ready = x.ready}
		end
	end
	return out
end
