-- Crafting orbs v2 (ChaosOrbs): the orbs that come on top of the first set of data/lib/chaos_crafting.lua, registered with
-- ChaosCrafting.addOrb (use-with action, bench row, previews and the log follow). chaos_crafting.lua loads this file at its
-- end, so every script that loads it has the orbs before crafting.lua registers the use-with actions.
--
--   Orb of Tempering   new values inside the current tiers for every modifier that is not bound (Rift Keys too)
--   Orb of Binding     binds one modifier: Tempering, Unmaking, Excision, Reforging and Upheaval leave it alone (at most
--                      ChaosItemMods.config.bind.max per item); only an Orb of Erasure frees it (and wipes the item)
--   Orb of Excision    removes the modifier you choose on the bench (a random one that is not bound by use-with; Rift Keys too)
--   Orb of Reforging   rolls the tier (by the item level) and the value of one modifier you choose again
--   Orb of Ruin        the gamble: improve / nothing (ruined only while ChaosOrbsConfig.ruin.ruin > 0; 0 since 2026-10-15)
--   Ember Orb          raises the modifier you choose by exactly one tier (a new value inside the new tier)
--   Crown Orb          lifts the item one rarity (up to Legendary): every modifier stays, the base bonus is the new rarity's
--                      and the item gets one more modifier
--   Whetstone          +1% quality up to 20% (30% from Divine rarity): every modifier value is multiplied
--   Void Orb           corrupts a Rare or better item for good (no orb changes it after), then one weighted outcome:
--                      nothing else, a tier up, a corrupted implicit, quality 30%, a socket, a reroll, a rarity up or a
--                      tier loss (ChaosOrbsConfig.void; O.corrupt)
-- The orbs that take a modifier (`pick`) are aimed with opts.mod = the modifier's attribute key (the bench's picker);
-- without one they pick at random among the modifiers they may act on. Tested by server/tests/crafting_test.lua.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosOrbs = ChaosOrbs or {}
local O = ChaosOrbs
local C = ChaosCrafting
local M = ChaosItemMods
if not ChaosOrbsConfig then
	ChaosOrbsConfig = dofile("data/lib/chaos_orbs_config.lua")
end
O.config = ChaosOrbsConfig

-- test hook: a string makes the Orb of Ruin roll that outcome ("improve", "nothing", "ruin"), O.forceImprove = "tiers" or
-- "slot" the kind of improvement, O.forceVoid an outcome of the Void Orb ("sealed", "tier", ...). nil in the game.
O.forceRuin = nil
O.forceImprove = nil
O.forceVoid = nil

local function itemOf(key)
	for _, it in ipairs(O.config.items) do
		if it.key == key then
			return it
		end
	end
	error("no orb item " .. tostring(key))
end

-- the modifiers an orb may act on: not bound (an orb that picks one may be aimed at any of these)
local function freeMods(item)
	local out = {}
	for _, m in ipairs(C.readMods(item)) do
		if not m.bound then
			out[#out + 1] = m
		end
	end
	return out
end

local function keysOf(mods)
	local out = {}
	for _, m in ipairs(mods) do
		out[#out + 1] = m.key
	end
	return out
end

-- the target of an orb that picks a modifier: the one named by opts.mod (it must be one the orb may act on), else one of
-- `candidates` at random. Returns the modifier or nil, reasonCode.
local function target(item, opts, candidates)
	if #candidates == 0 then
		return nil, "allBound"
	end
	if opts and opts.mod and opts.mod ~= "" then
		for _, m in ipairs(candidates) do
			if m.key:lower() == tostring(opts.mod):lower() then
				return m
			end
		end
		return nil, "badMod"
	end
	return candidates[C.random(1, #candidates)]
end

local function needRarity(item)
	if C.rarityOf(item) == 0 then
		return false, "needRarity"
	end
	return true
end

-- ---------------------------------------------------------------------------------------------------------------
-- Rift Keys: the orbs that work on them (values, one modifier out)
-- ---------------------------------------------------------------------------------------------------------------
local function keyMods(item)
	local R, cfg = C.rift()
	local key = C.readKey(item)
	local out = {}
	for i, m in ipairs(key.mods) do
		out[i] = {key = tostring(m.key), text = R.modText(cfg, m)}
	end
	return key, out
end

local function keyNeedMods(item)
	local key = C.readKey(item)
	if #key.mods == 0 then
		return false, "keyNoMods"
	end
	return true
end

-- ---------------------------------------------------------------------------------------------------------------
-- the orbs
-- ---------------------------------------------------------------------------------------------------------------
local function register()
	local R = O.config.ruin

	-- Orb of Tempering
	local it = itemOf("tempering")
	C.addOrb({key = "tempering", id = it.id, name = it.name,
		text = "Rolls the values of every modifier that is not bound again, inside their current tiers.",
		keyText = "Rolls the values of a Rift Key's modifiers again inside their ranges.",
		check = function(item)
			local ok, why = needRarity(item)
			if not ok then
				return false, why
			end
			local mods = C.readMods(item)
			if #mods == 0 then
				return false, "noMods"
			end
			if #freeMods(item) == 0 then
				return false, "allBound"
			end
			return true
		end,
		apply = function(item)
			local n = #freeMods(item)
			C.rerollValues(item, C.random)
			return true, {item = item, text = string.format("%s: %d modifier%s got new values (%s).", C.itemName(item), n,
				n == 1 and "" or "s", C.modsText(C.readMods(item))), tempered = n}
		end,
		preview = function(item)
			local mods = C.readMods(item)
			local bound = C.bindCount(mods)
			return string.format("%d modifier%s new values inside their tiers%s", #mods - bound, #mods - bound == 1 and "" or "s",
				bound > 0 and string.format(", %d bound stay", bound) or "")
		end,
		keyCheck = keyNeedMods,
		keyApply = function(item)
			return C.keyApply("divine", item) -- a Rift Key's values: new values inside the tier window of the key
		end})

	-- Orb of Binding
	it = itemOf("binding")
	C.addOrb({key = "binding", id = it.id, name = it.name,
		text = "Binds one modifier: the orbs that change modifiers leave it alone. Pick it on the bench (used directly: a random one).",
		pick = function(item)
			return keysOf(freeMods(item))
		end,
		check = function(item, opts)
			local ok, why = needRarity(item)
			if not ok then
				return false, why
			end
			local mods = C.readMods(item)
			if #mods == 0 then
				return false, "noMods"
			end
			if C.bindCount(mods) >= M.maxBinds(C.rarityOf(item)) then
				return false, "tooManyBinds"
			end
			local _, bad = target(item, opts, freeMods(item))
			return bad == nil, bad
		end,
		apply = function(item, opts)
			local m = target(item, opts, freeMods(item))
			C.setBound(item, m, true)
			C.rewriteDescription(item)
			return true, {item = item, text = string.format("%s: %s is bound.", C.itemName(item), C.modText(m)), bound = m}
		end,
		preview = function(item)
			local mods = C.readMods(item)
			return string.format("binds one modifier (%d of %d bound)", C.bindCount(mods), M.maxBinds(C.rarityOf(item)))
		end})

	-- Orb of Excision
	it = itemOf("excision")
	C.addOrb({key = "excision", id = it.id, name = it.name,
		text = "Removes the modifier you pick on the bench (used directly: a random one that is not bound).",
		keyText = "Removes one modifier of a Rift Key.",
		pick = function(item)
			return keysOf(freeMods(item))
		end,
		check = function(item, opts)
			local ok, why = needRarity(item)
			if not ok then
				return false, why
			end
			if #C.readMods(item) == 0 then
				return false, "noMods"
			end
			local _, bad = target(item, opts, freeMods(item))
			return bad == nil, bad
		end,
		apply = function(item, opts)
			local m = target(item, opts, freeMods(item))
			C.removeMod(item, m)
			C.rewriteDescription(item)
			return true, {item = item, text = string.format("%s lost %s.", C.itemName(item), C.modTierText(m)), removed = m}
		end,
		preview = function(item)
			local mods = C.readMods(item)
			return string.format("removes one of %d modifiers (the one you choose)", #mods - C.bindCount(mods))
		end,
		keyCheck = keyNeedMods,
		keyPick = function(item)
			local _, list = keyMods(item)
			local out = {}
			for _, m in ipairs(list) do
				out[#out + 1] = m.key
			end
			return out
		end,
		keyApply = function(item, opts)
			local Rk, cfg = C.rift()
			local key = C.readKey(item)
			local at = C.random(1, #key.mods)
			if opts and opts.mod then
				for i, m in ipairs(key.mods) do
					if tostring(m.key):lower() == tostring(opts.mod):lower() then
						at = i
					end
				end
			end
			local m = table.remove(key.mods, at)
			C.writeKey(item, key)
			local b = Rk.bonuses(cfg, key.mods, key.tier)
			return true, {item = item, key = key, text = string.format("%s lost \"%s\". Rewards: +%d%% quantity, +%d%% rarity, +%d%% experience.",
				Rk.keyName(cfg, key.tier), Rk.modText(cfg, m), b.quantity, b.rarity, b.experience)}
		end})

	-- Orb of Reforging
	it = itemOf("reforging")
	C.addOrb({key = "reforging", id = it.id, name = it.name,
		text = "Rolls the tier (by item level) and value of the modifier you pick again (used directly: a random unbound one).",
		pick = function(item)
			return keysOf(freeMods(item))
		end,
		check = function(item, opts)
			local ok, why = needRarity(item)
			if not ok then
				return false, why
			end
			if #C.readMods(item) == 0 then
				return false, "noMods"
			end
			local _, bad = target(item, opts, freeMods(item))
			return bad == nil, bad
		end,
		apply = function(item, opts)
			local m = target(item, opts, freeMods(item))
			local before = m.tier
			C.rerollTiers(item, C.random, m.key)
			local now = C.modByKey(item, m.key)
			return true, {item = item, text = string.format("%s: %s is now %s (was T%d).", C.itemName(item), now.label, C.modTierText(now),
				before), reforged = now}
		end,
		preview = function(item)
			return string.format("one modifier rolls a new tier (%s) and value", C.tierSpan(C.orbLevel(item)))
		end})

	-- Orb of Ruin
	it = itemOf("ruin")
	C.addOrb({key = "ruin", id = it.id, name = it.name,
		text = R.ruin > 0 and string.format("A gamble: %d%% it improves (a tier more on every unbound modifier, or an extra one), %d%% nothing, %d%% ruined for good.",
			R.improve, R.nothing, R.ruin) or string.format("A gamble: %d%% it improves (a tier more on every unbound modifier, or an extra one), %d%% nothing happens. It never ruins the item.",
			R.improve, R.nothing),
		check = function(item)
			local ok, why = needRarity(item)
			if not ok then
				return false, why
			end
			if #C.readMods(item) == 0 then
				return false, "noMods"
			end
			return true
		end,
		apply = function(item)
			return O.ruin(item)
		end,
		preview = function(item)
			if R.ruin > 0 then
				return string.format("%d%% improves, %d%% nothing, %d%% ruined", R.improve, R.nothing, R.ruin)
			end
			return string.format("%d%% improves, %d%% nothing", R.improve, R.nothing)
		end})

	-- Whetstone
	it = itemOf("whetstone")
	C.addOrb({key = "whetstone", id = it.id, name = it.name,
		text = string.format("+%d%% quality: every modifier value is multiplied by the quality, up to %d%% (%d%% from Divine rarity).",
			M.config.quality.perStone, M.config.quality.cap, M.config.quality.capHigh),
		check = function(item)
			local ok, why = needRarity(item)
			if not ok then
				return false, why
			end
			if #C.readMods(item) == 0 then
				return false, "needMods"
			end
			if M.qualityOf(item) >= M.qualityCap(C.rarityOf(item)) then
				return false, "qualityFull"
			end
			return true
		end,
		apply = function(item)
			local q, old = C.addQuality(item, 1)
			return true, {item = item, text = string.format("%s: quality %d%% -> %d%%.", C.itemName(item), old, q), quality = q}
		end,
		preview = function(item)
			local q = M.qualityOf(item)
			return string.format("quality %d%% -> %d%% (up to %d%%)", q, math.min(q + M.config.quality.perStone,
				M.qualityCap(C.rarityOf(item))), M.qualityCap(C.rarityOf(item)))
		end})

	-- Ember Orb: one modifier up exactly one tier
	it = itemOf("ember")
	C.addOrb({key = "ember", id = it.id, name = it.name,
		text = "Raises the modifier you pick on the bench by one tier, with a new value in that tier (used directly: a random unbound one that can still rise).",
		pick = function(item)
			return keysOf(O.raisable(item))
		end,
		check = function(item, opts)
			local ok, why = needRarity(item)
			if not ok then
				return false, why
			end
			if #C.readMods(item) == 0 then
				return false, "noMods"
			end
			if #O.raisable(item) == 0 then
				return false, "nothingToRaise"
			end
			local _, bad = target(item, opts, O.raisable(item))
			return bad == nil, bad
		end,
		apply = function(item, opts)
			local m = target(item, opts, O.raisable(item))
			local before = m.tier
			C.writeAffix(item, m.affix, before + 1, nil, C.random)
			C.rewriteDescription(item)
			local now = C.modByKey(item, m.key)
			return true, {item = item, text = string.format("%s: %s rose from T%d to %s.", C.itemName(item), now.label, before,
				C.modTierText(now)), raised = now}
		end,
		preview = function(item)
			return string.format("one modifier up one tier (%d can still rise)", #O.raisable(item))
		end})

	-- Crown Orb: one rarity up, in place
	it = itemOf("crown")
	C.addOrb({key = "crown", id = it.id, name = it.name,
		text = string.format("Lifts the item one rarity, up to %s. Every modifier stays, the base bonus becomes the new rarity's and the item gets %d more.",
			C.rarityName(ChaosRarity.idOfRank(O.config.crown.maxRank)), O.config.crown.add),
		check = function(item)
			local ok, why = needRarity(item)
			if not ok then
				return false, why
			end
			if ChaosRarity.rank(C.rarityOf(item)) >= O.config.crown.maxRank then
				return false, "crownTop"
			end
			return true
		end,
		apply = function(item)
			return O.crown(item)
		end,
		preview = function(item)
			local rank = ChaosRarity.rank(C.rarityOf(item))
			return string.format("%s -> %s, +%d modifier", C.rarityName(C.rarityOf(item)),
				C.rarityName(ChaosRarity.idOfRank(rank + 1)), O.config.crown.add)
		end})

	-- Void Orb: corruption
	it = itemOf("void")
	C.addOrb({key = "void", id = it.id, name = it.name,
		text = "Corrupts a " .. C.rarityName(ChaosRarity.idOfRank(O.config.void.minRank)) ..
			" or better item for good: no orb can change it afterwards. Then " .. O.voidOdds() .. ".",
		check = function(item)
			return O.voidCheck(item)
		end,
		apply = function(item)
			return O.corrupt(item)
		end,
		preview = function()
			return "corrupted for good: " .. O.voidOdds(true)
		end})
end

-- the modifiers an Ember Orb may raise: not bound, below the top tier
function O.raisable(item)
	local out = {}
	for _, m in ipairs(freeMods(item)) do
		if m.affix and m.tier < M.config.maxTier then
			out[#out + 1] = m
		end
	end
	return out
end

-- the Crown Orb on an item: the rarity goes one rank up (the base bonus is written again for it; quality, sockets and
-- the old modifiers stay) and the item gets `add` modifiers (as far as its new side limits and candidates allow).
-- Returns ok, {item, text, rarity}
function O.crown(item)
	local from = C.rarityOf(item)
	local to = ChaosRarity.idOfRank(ChaosRarity.rank(from) + 1)
	local level = C.orbLevel(item)
	item:setCustomAttribute("rarity", to)
	C.applyBaseBonus(item, to, level)
	local added = C.rollAffixes(item, to, level, O.config.crown.add, C.random)
	C.rewriteDescription(item)
	local text = string.format("%s is now %s", C.itemName(item), C.rarityName(to))
	if #added > 0 then
		text = text .. ", and gained " .. C.modsText(added)
	end
	return true, {item = item, text = text .. ".", rarity = to, added = added}
end

-- ---------------------------------------------------------------------------------------------------------------
-- the Void Orb: corruption
-- ---------------------------------------------------------------------------------------------------------------
-- what each outcome does, in words (the orb's text, the bench preview, the codex)
O.VOID_TEXT = {sealed = "nothing else happens", tier = "a modifier rises one tier",
	implicit = "a corrupted implicit modifier", quality = "quality %d%%", socket = "one more socket (up to %d)",
	reroll = "every modifier rolls again", rarity = "one rarity up (up to Divine)", decay = "a modifier falls %d tiers"}
O.VOID_SHORT = {sealed = "nothing else", tier = "a tier up", implicit = "an implicit", quality = "quality %d%%",
	socket = "a socket", reroll = "a reroll", rarity = "a rarity up", decay = "a tier loss"}

local function voidWords(key, short)
	local V = O.config.void
	local f = (short and O.VOID_SHORT or O.VOID_TEXT)[key] or key
	if key == "quality" then
		return string.format(f, V.quality)
	elseif key == "socket" and not short then
		return string.format(f, V.sockets)
	elseif key == "decay" and not short then
		return string.format(f, V.decay)
	end
	return f
end
O.voidWords = voidWords

-- "28% nothing else happens, 20% a modifier rises one tier, ..." in the config's order
function O.voidOdds(short)
	local parts = {}
	for _, row in ipairs(O.config.void.outcomes) do
		parts[#parts + 1] = string.format("%d%% %s", row[2], voidWords(row[1], short))
	end
	return table.concat(parts, ", ")
end

local function rawCustom(item, key)
	local ok, v = pcall(function() return item:getCustomAttribute(key) end)
	return ok and v or nil
end

-- can a Void Orb corrupt this item? (ChaosCrafting.check refuses before it: no gear, ruined, corrupted, unique, a stack).
-- The item lock (the bench's Lock button) and store items refuse it too: corruption cannot be undone.
function O.voidCheck(item)
	if C.customNumber(item, "chaos_locked") ~= 0 then
		return false, "locked"
	end
	local okS, store = pcall(function() return item.isStoreItem ~= nil and item:isStoreItem() end)
	if rawCustom(item, "chaos_storebound") ~= nil or (okS and store == true) then
		return false, "storeItem"
	end
	if ChaosRarity.rank(C.rarityOf(item)) < O.config.void.minRank then
		return false, "voidRarity"
	end
	return true
end

-- the outcome of a Void Orb (the config's weights)
function O.rollVoid()
	if O.forceVoid then
		return O.forceVoid
	end
	local rows = {}
	for _, row in ipairs(O.config.void.outcomes) do
		rows[#rows + 1] = {row[1], row[2]}
	end
	return C.weighted(rows)
end

local function pickOne(list)
	return list[C.random(1, #list)]
end

-- the outcomes: each changes the item and returns a text, or nil when it cannot happen on this item (the fallback runs)
local VOID = {}
O.VOID = VOID

function VOID.sealed()
	return "nothing else happened"
end

function VOID.tier(item)
	local list = O.raisable(item)
	if #list == 0 then
		return nil
	end
	local m = pickOne(list)
	local before = m.tier
	C.writeAffix(item, m.affix, before + 1, nil, C.random)
	local now = C.modByKey(item, m.key)
	return string.format("%s rose from T%d to %s", now.label, before, C.modTierText(now))
end

-- the implicit pool of an item: the affixes of its kind's list (config.void.implicits) it may roll and does not have
function O.implicitPool(item)
	local kind = M.kindOf(item)
	local mods = C.readMods(item)
	local out = {}
	for _, key in ipairs(O.config.void.implicits[kind or ""] or {}) do
		local a = C.affixOf(M.attr(key))
		if a and a.def and M.allowed(a.def, kind) and not C.modByKey(item, a.key, mods) then
			out[#out + 1] = a
		end
	end
	return out
end

function VOID.implicit(item)
	local pool = O.implicitPool(item)
	if #pool == 0 then
		return nil
	end
	local a = pickOne(pool)
	local top = M.config.maxTier
	local tier = C.random(math.min(O.config.void.implicitTier, top), top)
	item:setCustomAttribute(M.IMPLICIT, a.key:lower())
	C.writeAffix(item, a, tier, nil, C.random)
	return "a corrupted implicit " .. C.modTierText(C.modByKey(item, a.key))
end

function VOID.quality(item)
	local old = M.qualityOf(item)
	if old >= O.config.void.quality then
		return nil
	end
	local q = C.setQuality(item, O.config.void.quality)
	return string.format("quality %d%% -> %d%%", old, q)
end

function VOID.socket(item)
	local G = ChaosGems
	local n = G.count(item)
	if n >= math.min(O.config.void.sockets, G.MAX_SOCKETS) then
		return nil
	end
	G.setCount(item, n + 1)
	return string.format("%d -> %d sockets", n, n + 1)
end

function VOID.reroll(item)
	if #freeMods(item) == 0 then
		return nil
	end
	C.rerollTiers(item, C.random)
	return "every unbound modifier rolled again (" .. C.modsText(C.readMods(item)) .. ")"
end

function VOID.rarity(item)
	local from = C.rarityOf(item)
	local rank = ChaosRarity.rank(from)
	if rank < 1 or rank >= ChaosRarity.STORED then
		return nil
	end
	local to = ChaosRarity.idOfRank(rank + 1)
	local level = C.orbLevel(item)
	item:setCustomAttribute("rarity", to)
	C.applyBaseBonus(item, to, level)
	local added = C.rollAffixes(item, to, level, O.config.void.add, C.random)
	local text = string.format("%s -> %s", C.rarityName(from), C.rarityName(to))
	if #added > 0 then
		text = text .. ", gained " .. C.modsText(added)
	end
	return text
end

function VOID.decay(item)
	local list = {}
	for _, m in ipairs(freeMods(item)) do
		if m.affix and m.tier > 1 then
			list[#list + 1] = m
		end
	end
	if #list == 0 then
		return nil
	end
	local m = pickOne(list)
	local before = m.tier
	C.writeAffix(item, m.affix, math.max(1, before - O.config.void.decay), nil, C.random)
	local now = C.modByKey(item, m.key)
	return string.format("%s fell from T%d to %s", now.label, before, C.modTierText(now))
end

-- the Void Orb on an item (O.voidCheck passed): corrupted for good, then one outcome (`outcome`, else rolled); one that
-- cannot happen on the item falls back along config.void.fallback ("sealed" at the end). Returns ok, {item, text,
-- outcome (what happened), rolled (what was rolled), corrupted = true}
function O.corrupt(item, outcome)
	local V = O.config.void
	local rolled = outcome or O.rollVoid()
	outcome = rolled
	local name = C.itemName(item)
	item:setCustomAttribute(M.CORRUPTED, 1)
	local tried, text = {}, nil
	while true do
		tried[outcome] = true
		text = (VOID[outcome] or VOID.sealed)(item)
		if text then
			break
		end
		local nextOutcome = V.fallback[outcome] or "sealed"
		if tried[nextOutcome] then
			nextOutcome = "sealed"
		end
		outcome = nextOutcome
	end
	C.rewriteDescription(item)
	return true, {item = item, outcome = outcome, rolled = rolled, corrupted = true,
		text = string.format("%s is corrupted: %s.", name, text)}
end

-- ---------------------------------------------------------------------------------------------------------------
-- the Orb of Ruin
-- ---------------------------------------------------------------------------------------------------------------
-- the outcome of the gamble: "improve", "nothing" or "ruin"
function O.rollRuin()
	local R = O.config.ruin
	if O.forceRuin then
		return O.forceRuin
	end
	return C.weighted({{"improve", R.improve}, {"nothing", R.nothing}, {"ruin", R.ruin}})
end

-- an improvement of an item: every modifier that is not bound one tier up (T8 stays; a new value inside the new tier),
-- or one extra modifier above the side limit (once per item). Returns a text, or nil when nothing could be improved.
function O.improve(item)
	local R = O.config.ruin
	local mods = C.readMods(item)
	local rarity = C.rarityOf(item)
	local raisable = {}
	for _, m in ipairs(mods) do
		if not m.bound and m.affix and m.tier < M.config.maxTier then
			raisable[#raisable + 1] = m
		end
	end
	local extraCandidates = {}
	if not M.extraSide(item) then
		extraCandidates = C.candidates(item, rarity, mods, {extra = true})
	end
	local kind = O.forceImprove
	if not kind then
		kind = (C.random(1, 100) <= R.tiers) and "tiers" or "slot"
	end
	if kind == "tiers" and #raisable == 0 then
		kind = "slot"
	elseif kind == "slot" and #extraCandidates == 0 then
		kind = "tiers"
	end
	if kind == "tiers" and #raisable > 0 then
		for _, m in ipairs(raisable) do
			C.writeAffix(item, m.affix, m.tier + 1, nil, C.random)
		end
		C.rewriteDescription(item)
		return string.format("%d modifier%s one tier higher", #raisable, #raisable == 1 and "" or "s"), "tiers"
	end
	if #extraCandidates > 0 then
		local affix = M.pick(extraCandidates, C.random)
		local p, s = C.sideCounts(mods)
		local atLimit = (affix.side == "prefix" and p >= M.sideLimitOf(item, "prefix", rarity))
			or (affix.side == "suffix" and s >= M.sideLimitOf(item, "suffix", rarity))
		local m = C.rollAffix(item, affix, C.orbLevel(item), C.random)
		if atLimit then
			item:setCustomAttribute(M.EXTRA, affix.side == "prefix" and 1 or 2)
		end
		C.rewriteDescription(item)
		return string.format("an extra %s: %s", affix.side, C.modTierText(m)), "slot", m
	end
	return nil
end

-- the Orb of Ruin on an item: returns ok, {item, text, outcome}
function O.ruin(item)
	local outcome = O.rollRuin()
	local name = C.itemName(item)
	if outcome == "improve" then
		local text, kind = O.improve(item)
		if text then
			return true, {item = item, outcome = "improve", kind = kind, text = string.format("%s improved: %s.", name, text)}
		end
		return true, {item = item, outcome = "nothing", text = string.format("%s: nothing left to improve, nothing happened.", name)}
	elseif outcome == "ruin" and (O.config.ruin.ruin or 0) > 0 then
		item:setCustomAttribute(M.RUINED, 1)
		C.rewriteDescription(item)
		return true, {item = item, outcome = "ruin", text = string.format("%s is ruined: no orb can change it any more.", name)}
	end
	return true, {item = item, outcome = "nothing", text = string.format("%s: nothing happened.", name)}
end

register()

return O
