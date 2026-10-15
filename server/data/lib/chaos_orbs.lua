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
--   Whetstone          +1% quality up to 20% (30% from Divine rarity): every modifier value is multiplied
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
-- "slot" the kind of improvement. nil in the game.
O.forceRuin = nil
O.forceImprove = nil

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
