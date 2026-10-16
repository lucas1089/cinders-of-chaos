-- Potions: pure rules (no engine calls), shared by potions.lua, data/lib/chaos_potions.lua and
-- server/tests/potions_test.lua. README "Potions".
--   ChaosPotionsCore.everfull(cfg, id)        the Everfull entry of a server id, or nil
--   ChaosPotionsCore.isFlask(cfg, id)          an old empty flask id
--   ChaosPotionsCore.drink(cfg, s)             s = {id, exhausted, target} -> {ok, health, mana, consume, flask}
--                                              | {ok = false, why, text}
--   ChaosPotionsCore.npcBuy(cfg, s)            s = {id, owned, money} -> {ok, price} | {ok = false, why, text}
--   ChaosPotionsCore.grantDue(cfg, s)          s = {granted, lastLogin} -> true when a login grant is due
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
	if s.exhausted then
		return {ok = false, why = "exhausted", text = "You are exhausted."}
	end
	return {ok = true, health = e.health, mana = e.mana, consume = false, flask = nil}
end

-- a potion seller's replacement: one at a time, refused while the character has one (backpack, inbox or depot)
function K.npcBuy(cfg, s)
	local e = K.everfull(cfg, s.id)
	if not e then
		return {ok = false, why = "unknown"}
	end
	if s.owned then
		return {ok = false, why = "owned", text = "You already have one. It never runs out."}
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
