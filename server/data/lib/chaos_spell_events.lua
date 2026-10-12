-- ChaosSpellEvents: the one table the spell event stubs call (engine patch 0008; data/events/scripts/player.lua stubs
-- written by server/tools/patch_base_events.py, switched on with --enable-spell-events). Every script that wants a
-- hook registers a handler here by kind and key; this table chains them:
--   cost      fn(player, name, id, group, aggressive, mana, health) -> mana, health   each gets the previous result
--   precast   fn(player, name, id, group, aggressive, mana, health) -> false cancels
--   cast      fn(player, name, id, group, aggressive, mana, health)
--   cooldown  fn(player, name, id, group, aggressive, cooldownType, ms) -> ms         each gets the previous result
-- Users: data/spells/chaos/_supports.lua (Thrift, Quickening, and the Mana Cost Reduction / Cooldown Reduction item
-- modifiers of data/lib/chaos_item_mods.lua, under one cap). ChaosSpellEvents.live turns true at the first event the
-- engine sends, so a script can keep its fallback for an engine (or events.xml) without the events.
-- Every Lua interface of the engine shares one Lua state (LuaScriptInterface::initState), so the spell scripts, the
-- revscripts and the event scripts all see this table. Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosSpellEvents = ChaosSpellEvents or {}
local E = ChaosSpellEvents

E.KINDS = {"cost", "precast", "cast", "cooldown"}
E.handlers = E.handlers or {}
for _, kind in ipairs(E.KINDS) do
	E.handlers[kind] = E.handlers[kind] or {}
end
E.live = E.live or false

-- register (or replace, same key: a /reload) a handler; handlers run in the order of their first registration
function E.set(kind, key, fn)
	local list = E.handlers[kind]
	assert(list, "unknown spell event kind " .. tostring(kind))
	for _, h in ipairs(list) do
		if h.key == key then
			h.fn = fn
			return
		end
	end
	list[#list + 1] = {key = key, fn = fn}
end

function E.remove(kind, key)
	local list = E.handlers[kind] or {}
	for i, h in ipairs(list) do
		if h.key == key then
			table.remove(list, i)
			return true
		end
	end
	return false
end

local function report(kind, key, err)
	print(string.format("[ChaosSpellEvents] %s handler %s: %s", kind, tostring(key), tostring(err)))
end

function E.onSpellCost(player, name, id, group, aggressive, mana, health)
	E.live = true
	mana, health = tonumber(mana) or 0, tonumber(health) or 0
	for _, h in ipairs(E.handlers.cost) do
		local ok, m, hp = pcall(h.fn, player, name, id, group, aggressive, mana, health)
		if ok then
			mana, health = tonumber(m) or mana, tonumber(hp) or health
		else
			report("cost", h.key, m)
		end
	end
	return math.max(0, math.floor(mana)), math.max(0, math.floor(health))
end

function E.onSpellPreCast(player, name, id, group, aggressive, mana, health)
	E.live = true
	for _, h in ipairs(E.handlers.precast) do
		local ok, res = pcall(h.fn, player, name, id, group, aggressive, mana, health)
		if not ok then
			report("precast", h.key, res)
		elseif res == false then
			return false
		end
	end
	return true
end

function E.onSpellCast(player, name, id, group, aggressive, mana, health)
	E.live = true
	for _, h in ipairs(E.handlers.cast) do
		local ok, err = pcall(h.fn, player, name, id, group, aggressive, mana, health)
		if not ok then
			report("cast", h.key, err)
		end
	end
end

function E.onSpellCooldown(player, name, id, group, aggressive, cooldownType, ms)
	E.live = true
	ms = tonumber(ms) or 0
	for _, h in ipairs(E.handlers.cooldown) do
		local ok, v = pcall(h.fn, player, name, id, group, aggressive, cooldownType, ms)
		if ok then
			ms = tonumber(v) or ms
		else
			report("cooldown", h.key, v)
		end
	end
	return math.max(0, math.floor(ms))
end

-- the discounts both the event path and the fallback use: mana after a pct discount, a cooldown after a pct cut
-- (never below minMs, unless it was shorter to begin with)
function E.discount(mana, pct)
	mana = tonumber(mana) or 0
	return mana - math.floor(mana * (tonumber(pct) or 0) / 100)
end

function E.shorten(ms, pct, minMs)
	ms, pct = tonumber(ms) or 0, tonumber(pct) or 0
	if ms <= 0 or pct <= 0 then
		return ms
	end
	return math.max(math.min(ms, minMs or 0), ms - math.floor(ms * pct / 100))
end

return E
