-- Spell supports, the spell side (the Lua state of the spells). Loaded once by _common.lua (the Chaos spells) or, when
-- server/tools/install_supports.py added its line, by data/spells/lib/spells.lua before any spell script, so stock
-- spells get it too. Overview: data/scripts/chaos/SUPPORTS.md.
--
-- How a spell is wrapped: a spell script defines the global onCastSpell; the engine reads it right after loading the
-- file and clears the global again. A __newindex on _G sees that definition, finds the script's path
-- (debug.getinfo of the defining chunk: "@data/spells/scripts/<script>"), looks up the spell id of that script in
-- data/spells/spells.xml and stores a wrapper instead. The wrapper, for players only:
--   * writes the cast context (serial * 1000 + spell id) into a player storage while the script runs, and while every
--     addEvent callback the script starts runs (the global addEvent is swapped for the duration), so the scripts
--     state (data/scripts/chaos/supports.lua, onHealthChange) knows which spell a hit came from;
--   * after a cast that went through (the script returned true), one tick later when the engine has taken the mana
--     and set the cooldown: Thrift gives back part of the mana, Quickening shortens the spell's cooldown condition;
--     the Mana Cost Reduction and Cooldown Reduction item modifiers of the equipped items (data/lib/chaos_item_mods.lua)
--     add to them, both together under the support's cap. That is the fallback: with the spell events of engine patch
--     0008 switched on (patch_base_events.py --enable-spell-events) the same numbers go through ChaosSpellEvents
--     (data/lib/chaos_spell_events.lua) instead: onSpellCost makes Thrift / Mana Cost Reduction a real discount (the
--     "enough mana" check sees it) and onSpellCooldown shortens the spell's own cooldown as it is set; the wrapper then
--     skips its after-cast step;
--   * Reprisal: remembers spell and time in two storages for the hit-taken side.
-- A script whose spell has no id (or shares it) is left as it is. Nothing here changes what a spell does by itself.

if ChaosSupportsSpell then
	return
end
ChaosSupportsSpell = {wrapped = 0}
local W = ChaosSupportsSpell

if not ChaosSupports then
	dofile("data/lib/chaos_supports.lua")
end
local S = ChaosSupports
local cfg = S.config

local SCRIPTS = "data/spells/scripts/"
local rawAddEvent = addEvent
-- the engine's addEvent without the cast context: for schedulers that outlive a cast (the snares, _snares.lua)
W.rawAddEvent = rawAddEvent
local serials = {} -- player id -> last cast serial

-- ---------------------------------------------------------------- spells.xml: script -> spell
local byScript
local function spellsByScript()
	if byScript then
		return byScript
	end
	byScript = {}
	local f = io.open("data/spells/spells.xml", "r")
	if f then
		local text = f:read("*a")
		f:close()
		for id, e in pairs(S.eligible(S.parseSpellsXml(text))) do
			if e.script then
				byScript[e.script:lower()] = e
			end
		end
	end
	return byScript
end
W.spellsByScript = spellsByScript

-- ---------------------------------------------------------------- context
local current -- context value of the code running now (nil outside a supported cast)

local function setCtx(player, value)
	if player then
		pcall(function() player:setStorageValue(cfg.storageContext, value or -1) end)
	end
end

local ctxAddEvent
local unpackFn = unpack or table.unpack
local function pack(...)
	return {n = select("#", ...), ...}
end

-- run fn(...) with context `ctx` for player `pid`; nested runs restore the outer context
local function runWith(pid, ctx, fn, ...)
	local outer = current
	local outerAdd = addEvent
	current = ctx
	addEvent = ctxAddEvent
	local player = Player(pid)
	setCtx(player, ctx and ctx.value)
	local res = pack(pcall(fn, ...))
	current = outer
	addEvent = outerAdd
	player = Player(pid)
	setCtx(player, outer and outer.value or nil)
	if not res[1] then
		error(res[2], 0)
	end
	return unpackFn(res, 2, res.n)
end

-- addEvent while a supported cast runs: the callback runs with the same context
ctxAddEvent = function(callback, delay, ...)
	local ctx = current
	if type(callback) ~= "function" or not ctx then
		return rawAddEvent(callback, delay, ...)
	end
	return rawAddEvent(function(...)
		return runWith(ctx.pid, ctx, callback, ...)
	end, delay, ...)
end

-- >>> Cosmetics (cosmetics.lua): the cast running now, for the spell effect skins of _common.lua
-- player id and spell id of the supported cast whose code (or addEvent callback) runs now; nil outside a cast
function W.cast()
	if current then
		return current.pid, current.spell
	end
	return nil
end
-- <<< Cosmetics

-- ---------------------------------------------------------------- item modifiers
-- the capped Cooldown Reduction and Mana Cost Reduction of the equipped items: {cdr, manacost}. Every engine Lua
-- interface shares one state, so the totals item_mods.lua keeps per player are read first; without them (tests, a
-- player the equipment check has not seen yet) the items are read.
function W.itemBonus(player)
	if not ChaosItemMods then
		pcall(dofile, "data/lib/chaos_item_mods.lua")
	end
	local M = ChaosItemMods
	if M and M.playerBonus and ChaosItemModsCache then
		local okId, id = pcall(function() return player:getId() end)
		if okId and ChaosItemModsCache[id] then
			return {cdr = M.playerBonus(player, "cdr"), manacost = M.playerBonus(player, "manacost")}
		end
	end
	if not M or not M.equippedItems then
		return {cdr = 0, manacost = 0}
	end
	local ok, t = pcall(function() return M.totals(M.equippedItems(player)) end)
	if not ok or type(t) ~= "table" then
		return {cdr = 0, manacost = 0}
	end
	return {cdr = t.cdr or 0, manacost = t.manacost or 0}
end

-- what the after-cast step gives: thrift / quickening percent (supports + item modifiers, under the supports' caps)
function W.castBonus(fx, items)
	local caps = cfg.caps or {}
	local thrift = (fx.thrift and fx.thrift.value or 0) + (items and items.manacost or 0)
	local quick = (fx.quickening and fx.quickening.value or 0) + (items and items.cdr or 0)
	return math.min(caps.thrift or 30, thrift), math.min(caps.quickening or 30, quick)
end

-- ---------------------------------------------------------------- spell events (engine patch 0008)
if not ChaosSpellEvents or not ChaosSpellEvents.set then
	dofile("data/lib/chaos_spell_events.lua")
end
local E = ChaosSpellEvents

-- the catalogue entry of a spell id (level for the socket count), nil for spells without supports
local byId
function W.spellById(id)
	if not byId then
		byId = {}
		for _, e in pairs(W.spellsByScript()) do
			if e.id then
				byId[e.id] = e
			end
		end
	end
	return byId[tonumber(id) or -1]
end

-- thrift and quickening percent of a cast: the spell's runes plus the item modifiers, under the supports' caps
function W.bonusOf(player, spellId)
	local spell = W.spellById(spellId)
	local fx = spell and S.spellEffects(player, spell.id, spell.level) or {}
	return W.castBonus(fx, W.itemBonus(player))
end

E.set("cost", "supports", function(player, name, id, group, aggressive, mana, health)
	local thrift = W.bonusOf(player, id)
	if thrift > 0 and mana > 0 then
		mana = E.discount(mana, thrift)
	end
	return mana, health
end)

E.set("cooldown", "supports", function(player, name, id, group, aggressive, cooldownType, ms)
	if cooldownType ~= "spell" then
		return ms -- the spell's own cooldown only; the group cooldowns stay
	end
	local _, quick = W.bonusOf(player, id)
	return E.shorten(ms, quick, cfg.effect.cooldownMinMs)
end)

-- ---------------------------------------------------------------- after the cast (fallback without the events)
local function afterCast(pid, spell, thrift, quick)
	local player = Player(pid)
	if not player then
		return
	end
	if thrift > 0 then
		local mana = spell.mana or 0
		if spell.manaPercent and spell.manaPercent > 0 then
			mana = math.floor(player:getMaxMana() * spell.manaPercent / 100)
		end
		local back = math.floor(mana * thrift / 100)
		if back > 0 then
			player:addMana(back)
		end
	end
	if quick > 0 and (spell.cooldown or 0) > 0 then
		local c = player:getCondition(CONDITION_SPELLCOOLDOWN, CONDITIONID_DEFAULT, spell.id)
		if c then
			local left = c:getTicks()
			local cut = math.floor(spell.cooldown * quick / 100)
			local ticks = math.max(math.min(left, cfg.effect.cooldownMinMs), left - cut)
			if ticks < left then
				player:removeCondition(CONDITION_SPELLCOOLDOWN, CONDITIONID_DEFAULT, spell.id, true)
				if ticks > 0 then
					local n = Condition(CONDITION_SPELLCOOLDOWN, CONDITIONID_DEFAULT)
					n:setParameter(CONDITION_PARAM_SUBID, spell.id)
					n:setParameter(CONDITION_PARAM_TICKS, ticks)
					player:addCondition(n)
				end
			end
		end
	end
end

-- ---------------------------------------------------------------- the wrapper
local function wrap(spell, original)
	return function(creature, variant, ...)
		local player = creature and creature.isPlayer and creature:isPlayer() and creature or nil
		if not player then
			return original(creature, variant, ...)
		end
		local pid = player:getId()
		local fx = S.spellEffects(player, spell.id, spell.level)
		local serial = (serials[pid] or 0) + 1
		serials[pid] = serial % 1000000
		local ctx = {pid = pid, value = S.ctxEncode(serial, spell.id), spell = spell.id}
		local result = runWith(pid, ctx, original, creature, variant, ...)
		if result then
			local thrift, quick = 0, 0
			if not E.live then -- the engine's spell events did it already
				thrift, quick = W.castBonus(fx, W.itemBonus(player))
			end
			if thrift > 0 or quick > 0 then
				rawAddEvent(afterCast, 0, pid, spell, thrift, quick)
			end
			if fx.reprisal then
				player:setStorageValue(cfg.storageReprisal, spell.id)
				player:setStorageValue(cfg.storageReprisalUntil, os.time() + cfg.effect.reprisalWindow)
			end
		end
		return result
	end
end
W.wrap = wrap

-- the path of a spell script relative to data/spells/scripts, from the chunk that defines onCastSpell
local function scriptOf(level)
	if not debug or not debug.getinfo then
		return nil
	end
	local info = debug.getinfo(level, "S")
	local src = info and info.source or ""
	local i = src:find(SCRIPTS, 1, true)
	if not i then
		return nil
	end
	return src:sub(i + #SCRIPTS):lower()
end
W.scriptOf = scriptOf

function W.install(G)
	G = G or _G
	local mt = getmetatable(G) or {}
	if mt.chaosSupports then
		return
	end
	local old = mt.__newindex
	mt.chaosSupports = true
	mt.__newindex = function(t, k, v)
		if k == "onCastSpell" and type(v) == "function" then
			local script = scriptOf(3)
			local spell = script and W.spellsByScript()[script]
			if spell then
				v = wrap(spell, v)
				W.wrapped = W.wrapped + 1
			end
		end
		if old then
			return old(t, k, v)
		end
		rawset(t, k, v)
	end
	setmetatable(G, mt)
end

W.install()
