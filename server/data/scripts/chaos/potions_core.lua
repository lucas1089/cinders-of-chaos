-- Potions: pure rules (no engine calls), shared by potions.lua, data/lib/chaos_potions.lua and
-- server/tests/potions_test.lua. README "Potions".
--   ChaosPotionsCore.everfull(cfg, id)        the Everfull entry of a server id, or nil
--   ChaosPotionsCore.isFlask(cfg, id)          an old empty flask id
--   ChaosPotionsCore.drink(cfg, s)             s = {id, exhausted, target[, charges]} -> {ok, health, mana, consume, flask}
--                                              | {ok = false, why, text}
--   ChaosPotionsCore.npcBuy(cfg, s)            s = {id, owned, money} -> {ok, price} | {ok = false, why, text}
--   ChaosPotionsCore.amount(cfg, range, level, max, bonusPct[, rand])  one drink: fixed roll + percent of max
--   ChaosPotionsCore.grantDue(cfg, s)          s = {granted, lastLogin} -> true when a login grant is due
--   Flask charges (cfg.flask; hundredths of a charge, an unset storage value is a full flask):
--   ChaosPotionsCore.maxCharges(cfg, kind, treeExtra)      whole charges the flask holds
--   ChaosPotionsCore.read(cfg, kind, raw, treeExtra)       raw storage value -> hundredths (unset / bad = full)
--   ChaosPotionsCore.canDrink(cfg, hundredths)             enough for one drink
--   ChaosPotionsCore.spend(cfg, hundredths)                after a drink
--   ChaosPotionsCore.killGain(cfg, s)                      s = {tier, xp, treeGainPct, kind} -> hundredths per kill
--   ChaosPotionsCore.add(cfg, kind, hundredths, gain, treeExtra)  capped at the maximum
--   ChaosPotionsCore.whole(hundredths) / K.label(...)      whole charges, "3/5"
--   ChaosPotionsCore.eligibleKill(cfg, s)                  s = {name, summon, husk, player} -> bool
--   ChaosPotionsCore.safeRefill(cfg, s)                    s = {safe, fighting} -> bool
--   ChaosPotionsCore.treeValues(cfg, bonuses)              the tree's extra charges and gain percent (capped)
--   ChaosPotionsCore.noticeDue(cfg, last, now)             at most one refill notice per noticeMs
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
function K.drink(cfg, s)
	local e = K.everfull(cfg, s.id)
	if not e then
		return {ok = false, why = "unknown"}
	end
	if s.target == "creature" then
		return {ok = false, why = "target"}
	end
	if s.charges ~= nil and not K.canDrink(cfg, s.charges) then
		return {ok = false, why = "empty", kind = e.key}
	end
	if s.exhausted then
		return {ok = false, why = "exhausted", text = "You are exhausted."}
	end
	return {ok = true, kind = e.key, health = e.health, mana = e.mana, consume = false, flask = nil}
end

-- the amount of one potion drink: a roll inside range (the fixed part) + percent(level) of max, then x (1 + bonusPct)
function K.percent(cfg, level)
	local a = cfg.amount or {}
	return math.min(a.cap or 0, (a.base or 0) + (a.perLevel or 0) * math.max(0, tonumber(level) or 0))
end

function K.amount(cfg, range, level, max, bonusPct, rand)
	rand = rand or math.random
	local lo, hi = math.floor(range[1] or 0), math.floor(range[2] or range[1] or 0)
	local v = (hi > lo and rand(lo, hi) or lo) + math.max(0, max or 0) * K.percent(cfg, level) / 100
	return math.floor(v * (1 + math.max(0, bonusPct or 0) / 100) + 0.5)
end

-- a potion seller's replacement: one at a time, refused while the character has one (backpack, inbox or depot)
function K.npcBuy(cfg, s)
	local e = K.everfull(cfg, s.id)
	if not e then
		return {ok = false, why = "unknown"}
	end
	if s.owned then
		return {ok = false, why = "owned", text = "You already have one. It refills as you kill monsters."}
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
