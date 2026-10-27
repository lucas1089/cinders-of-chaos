-- Potions: pure rules (no engine calls), shared by potions.lua, data/lib/chaos_potions.lua and
-- server/tests/potions_test.lua. README "Potions".
--   ChaosPotionsCore.everfull(cfg, id)        the Everfull entry of a server id, or nil
--   ChaosPotionsCore.isFlask(cfg, id)          an old empty flask id
--   ChaosPotionsCore.drink(cfg, s)             s = {id, exhausted, target[, charges]} -> {ok, health, mana, consume, flask}
--                                              | {ok = false, why, text}
--   ChaosPotionsCore.npcBuy(cfg, s)            s = {id, owned, money} -> {ok, price} | {ok = false, why, text}
--   ChaosPotionsCore.amount(cfg, range, level, max, bonusPct[, rand, tier])  one drink: fixed roll + percent of max
--   ChaosPotionsCore.grantDue(cfg, s)          s = {granted, lastLogin} -> true when a login grant is due
--   Flask charges (cfg.flask; hundredths of a charge, an unset storage value is a full flask):
--   ChaosPotionsCore.maxCharges(cfg, kind, treeExtra)      whole charges the flask holds
--   ChaosPotionsCore.read(cfg, kind, raw, treeExtra)       raw storage value -> hundredths (unset / bad = full)
--   ChaosPotionsCore.clampStored(cfg, kind, raw, extra)    the value to write back when a refund lowered the maximum, else nil
--   ChaosPotionsCore.canDrink(cfg, hundredths)             enough for one drink
--   ChaosPotionsCore.spend(cfg, hundredths)                after a drink
--   ChaosPotionsCore.killGain(cfg, s)                      s = {tier, xp, treeGainPct, kind} -> hundredths per kill
--   ChaosPotionsCore.add(cfg, kind, hundredths, gain, treeExtra)  capped at the maximum
--   ChaosPotionsCore.whole(hundredths) / K.label(...)      whole charges, "3/5"
--   ChaosPotionsCore.eligibleKill(cfg, s)                  s = {name, summon, husk, player} -> bool
--   ChaosPotionsCore.safeRefill(cfg, s)                    s = {safe, fighting} -> bool
--   ChaosPotionsCore.treeValues(cfg, bonuses)              the tree's extra charges and gain percent (capped)
--   ChaosPotionsCore.noticeDue(cfg, last, now)             at most one refill notice per noticeMs
--   O245 tiers (README "Potions", "Higher tiers"): an entry has tier, level, line (health | mana | spirit), from (the
--   server ids it is made from) and pools (the charge pools a drink spends, default its key).
--   ChaosPotionsCore.poolsOf(cfg, entry)          the pools a drink of this entry spends
--   ChaosPotionsCore.upgradeTargets(cfg)           the entries made from another one (`from`: tier 2 and up, and the
--                                                  tier 1 spirit potion), in config order = the order of their flags
--   ChaosPotionsCore.materialOf(cfg, e)            {id, count, name}: what Veyra's task takes for an entry
--   ChaosPotionsCore.upgradeStorage(cfg, id)       the player storage key that says "this tier was earned"
--   ChaosPotionsCore.upgradeCoins(cfg, id)         the store price of a tier
--   ChaosPotionsCore.upgradeCheck(cfg, s)          s = {id, level, installed, done, held = {ids}, mode, materials}
--                                                  -> {ok, from, materials} | {ok = false, why, text, args}
--   ChaosPotionsCore.restoreFor(cfg, slot, held, earned)  the entry a character that lost its flask gets back, or nil
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

-- one drink of an Everfull potion. target: "self" (no target, an item, the drinker), "player" (another player) or
-- "creature" (a monster or an NPC: refused like the stock potion, the use goes on to the engine). The potion is never
-- consumed and never leaves a flask; the exhaust is the stock potions' one.
function K.poolsOf(cfg, e)
	return e.pools or {e.key}
end

-- s.charges: hundredths of a charge, one number for every pool of the entry, or a table pool -> hundredths
local function chargeOf(s, pool)
	if type(s.charges) == "table" then
		return s.charges[pool]
	end
	return s.charges
end

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
	-- every pool the drink spends needs a whole charge (a spirit potion spends one of each)
	for _, pool in ipairs(K.poolsOf(cfg, e)) do
		local have = chargeOf(s, pool)
		if have ~= nil and not K.canDrink(cfg, have) then
			return {ok = false, why = "empty", kind = pool}
		end
	end
	if s.exhausted then
		return {ok = false, why = "exhausted", text = "You are exhausted."}
	end
	return {ok = true, kind = e.key, pools = K.poolsOf(cfg, e), health = e.health, mana = e.mana, consume = false, flask = nil}
end

-- the amount of one potion drink: a roll inside range (the fixed part) + percent(level) of max, then x (1 + bonusPct)
-- tier: an Everfull potion's tier (amount.everfullPct gives its percent, the same at every character level); nil for
-- a stock potion (and for a stock potion an empty flask drinks), which uses the level curve
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

-- a potion seller's replacement: tier 1 only, one at a time, refused while the character has an Everfull potion of the
-- same slot in any tier (backpack, inbox or depot: s.owned) and while it earned a better one (s.better: Veyra gives
-- that one back, K.restoreFor)
function K.npcBuy(cfg, s)
	local e = K.everfull(cfg, s.id)
	if not e or (e.tier or 1) > 1 or K.isUpgrade(e) then
		return {ok = false, why = "unknown"}
	end
	if s.owned then
		return {ok = false, why = "owned", text = "You already have an Everfull flask of that kind, in your backpack, inbox or depot. It refills as you kill monsters. For a better one, ask Veyra for an {upgrade}."}
	end
	if s.better then
		return {ok = false, why = "better",
			text = "You earned a better flask than that. Ask Veyra the Apothecary to give it back."}
	end
	if (s.money or 0) < e.price then
		return {ok = false, why = "money", text = "You do not have enough money."}
	end
	return {ok = true, price = e.price}
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

-- ---------------------------------------------------------------- flask charges (README "Potions", "Flask charges")
local function flaskOf(cfg, kind)
	return (cfg.flask or {})[kind]
end

function K.maxCharges(cfg, kind, treeExtra)
	local f = flaskOf(cfg, kind)
	if not f then
		return 0
	end
	local cap = (cfg.flask.tree or {}).maxExtra or 0
	local extra = math.max(0, math.min(cap, math.floor(tonumber(treeExtra) or 0)))
	return (f.max or 0) + extra
end

-- the raw storage value (-1 / nil: never set) -> hundredths of a charge, 0 .. max * 100. A value outside the range
-- (an old maximum, a hand edit) is clamped, never trusted.
function K.read(cfg, kind, raw, treeExtra)
	local top = K.maxCharges(cfg, kind, treeExtra) * 100
	raw = tonumber(raw)
	if raw == nil or raw < 0 or raw ~= raw then
		return top
	end
	return math.min(top, math.floor(raw))
end

-- a stored value above the flask's maximum (the tree's extra charges were refunded or respecced away) is cut to the
-- maximum, so a later re-buy of the node cannot bring the lost charges back. Returns the new raw value, or nil when
-- nothing has to change (unset, in range).
function K.clampStored(cfg, kind, raw, treeExtra)
	raw = tonumber(raw)
	if raw == nil or raw < 0 or raw ~= raw then
		return nil
	end
	local top = K.maxCharges(cfg, kind, treeExtra) * 100
	if math.floor(raw) > top then
		return top
	end
	return nil
end

function K.canDrink(cfg, hundredths)
	return (tonumber(hundredths) or 0) >= (cfg.flask.cost or 1) * 100
end

function K.spend(cfg, hundredths)
	return math.max(0, (tonumber(hundredths) or 0) - (cfg.flask.cost or 1) * 100)
end

-- the refill of one kill for one flask, in whole hundredths of a charge. Zero for an unknown tier.
function K.killGain(cfg, s)
	local f = cfg.flask
	local base = f.perKill[s.tier or "normal"]
	local fl = flaskOf(cfg, s.kind)
	if not base or not fl then
		return 0
	end
	local factor = 1
	if s.tier ~= "boss" then
		local x = f.xp or {}
		factor = (tonumber(s.xp) or 0) / math.max(1, x.ref or 1)
		factor = math.max(x.min or 0, math.min(x.max or 1, factor))
	end
	local pct = math.max(0, math.min((f.tree or {}).gainPctCap or 0, tonumber(s.treeGainPct) or 0))
	local v = base * factor * (fl.gain or 1) * (1 + pct / 100)
	return math.max(0, math.min(f.killCap or v, math.floor(v + 0.5)))
end

function K.add(cfg, kind, hundredths, gain, treeExtra)
	local top = K.maxCharges(cfg, kind, treeExtra) * 100
	return math.min(top, math.max(0, math.floor(tonumber(hundredths) or 0)) + math.max(0, math.floor(tonumber(gain) or 0)))
end

function K.whole(hundredths)
	return math.floor((tonumber(hundredths) or 0) / 100)
end

function K.label(cfg, kind, hundredths, treeExtra)
	return K.whole(hundredths) .. "/" .. K.maxCharges(cfg, kind, treeExtra)
end

-- a kill that refills: a monster with a name, not a summon of a player or a dissolved rift husk, not a training dummy.
-- A player never refills anything (no PvP refill): the death event is only put on monsters, and this refuses one.
function K.eligibleKill(cfg, s)
	if s.player or s.summon or s.husk then
		return false
	end
	local name = tostring(s.name or ""):lower()
	if name == "" then
		return false
	end
	for _, w in ipairs(cfg.flask.skipWords or {}) do
		if name:find(w, 1, true) then
			return false
		end
	end
	return true
end

function K.safeRefill(cfg, s)
	if not s.safe then
		return false
	end
	return not (cfg.flask.safeNeedsNoFight and s.fighting)
end

function K.treeValues(cfg, bonuses)
	local t = cfg.flask.tree or {}
	bonuses = bonuses or {}
	local extra = math.max(0, math.min(t.maxExtra or 0, math.floor(tonumber(bonuses[t.maxStat or ""]) or 0)))
	local gain = math.max(0, math.min(t.gainPctCap or 0, math.floor(tonumber(bonuses[t.gainStat or ""]) or 0)))
	return extra, gain
end

function K.noticeDue(cfg, last, now)
	return last == nil or now - last >= (cfg.flask.noticeMs or 0)
end

-- ---------------------------------------------------------------- higher tiers (README "Potions", "Higher tiers", O245)
-- An entry made from another one (`from`) is an upgrade: tier 2 and up, and the tier 1 spirit potion (O247, made from the
-- tier 1 health potion). Only the others (the tier 1 health and mana potions) are sold and given.
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

-- A character that has earned a tier (earned: the entries whose storage flag is set) and no longer has any Everfull
-- item of that slot gets the highest tier it earned back. held: the server ids of every Everfull item it has.
function K.restoreFor(cfg, slot, held, earned)
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
	return best
end

-- ---------------------------------------------------------------- what the helper is told (README "Potions", O246)
-- The client sees every tier under the stock potion's look, so the helper cannot tell which Everfull a character carries.
-- The server tells it: per slot (health, mana) the carried Everfull's look, tier, level, line and whether a drink would
-- work now. s.counts: server id -> how many the character carries (inventory and backpacks, as Player:getItemCount);
-- s.charges: pool -> hundredths; s.clientId(serverId) -> the client id (the look). A slot holding two items (a GM gift)
-- reports the highest tier: the engine's use by look picks one of them, and both are the same slot's pool anyway.
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
				local ready = true
				for _, pool in ipairs(K.poolsOf(cfg, e)) do
					local have = s.charges and s.charges[pool]
					if have ~= nil and not K.canDrink(cfg, have) then
						ready = false
					end
				end
				view[slot] = {look = look, tier = e.tier or 1, level = e.level or 0, line = e.line or e.key, ready = ready}
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
