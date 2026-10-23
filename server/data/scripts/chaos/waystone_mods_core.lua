-- Waystone modifiers: the pure part (no engine calls), shared by waystone_mods.lua, data/lib/chaos_crafting.lua (the orbs)
-- and tests/waystone_mods_test.lua. server/README.md "Waystone modifiers"; numbers in waystone_mods_config.lua.
--   rarity     Normal / Magic / Rare by the prefixes and suffixes a waystone carries
--   rolls      new modifiers within the rarity's room, gated by the waystone's tier (minTier, tier windows I-V)
--   orbs       what each crafting orb does to a waystone (the map way of Path of Exile)
--   rewards    quantity, rarity, experience (the modifiers' own rewards) and waystone drop chance
--   effects    rift_core.lua R.effects on the modifiers (what rift.lua does with them, waystone_mods.lua does in a map)
-- A waystone here is {tier = 1..15, mods = {{key, value}, ...}}. Every random number comes from `rand(a, b)`.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
if not ChaosRiftCore then
	dofile("data/scripts/chaos/rift_core.lua")
end

ChaosWaystoneModsCore = ChaosWaystoneModsCore or {}
local W = ChaosWaystoneModsCore
local R = ChaosRiftCore
local floor = math.floor

W.ROMAN = {"I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII", "XIII", "XIV", "XV"}

local function weighted(rows, rand)
	local total = 0
	for _, r in ipairs(rows) do
		total = total + r[2]
	end
	if total <= 0 then
		return rows[1] and rows[1][1]
	end
	local roll, acc = rand(1, total), 0
	for _, r in ipairs(rows) do
		acc = acc + r[2]
		if roll <= acc then
			return r[1]
		end
	end
	return rows[#rows][1]
end
W.weighted = weighted

function W.clampTier(cfg, t)
	t = floor(tonumber(t) or 1)
	return math.max(1, math.min(t, cfg.maxTier or 15))
end

-- ===================================================================== rarity
-- prefixes, suffixes of a list of modifiers
function W.sides(cfg, mods)
	local p, s = 0, 0
	for _, m in ipairs(mods or {}) do
		local def = R.modDef(cfg, m.key)
		if def and def.side == "suffix" then
			s = s + 1
		elseif def then
			p = p + 1
		end
	end
	return p, s
end

-- the rarity index (1 Normal, 2 Magic, 3 Rare) of a list of modifiers
function W.rarityOf(cfg, mods)
	local p, s = W.sides(cfg, mods)
	if p == 0 and s == 0 then
		return 1
	end
	for i, r in ipairs(cfg.rarities) do
		if i > 1 and p <= r.prefix and s <= r.suffix then
			return i
		end
	end
	return #cfg.rarities
end

function W.rarityName(cfg, i)
	local r = cfg.rarities[i]
	return r and r.name or "Normal"
end

function W.rarityIndex(cfg, name)
	for i, r in ipairs(cfg.rarities) do
		if r.name == name then
			return i
		end
	end
	return 1
end

-- the attribute text -> modifiers: R.decodeMods (known keys, ranges, groups, at most key.maxMods), then at most the
-- Rare room of each side (the first ones in config order stay)
function W.decode(cfg, text)
	local mods = R.decodeMods(cfg, text)
	local top = cfg.rarities[#cfg.rarities]
	local out, p, s = {}, 0, 0
	for _, m in ipairs(mods) do
		local def = R.modDef(cfg, m.key)
		if def.side == "suffix" then
			if s < top.suffix then
				s = s + 1
				out[#out + 1] = m
			end
		elseif p < top.prefix then
			p = p + 1
			out[#out + 1] = m
		end
	end
	return out
end

function W.encode(mods)
	return R.encodeMods(mods)
end

-- ===================================================================== rolls
-- indexes of cfg.mods a waystone of `tier` may still get with rarity `rarity` (index): not held, no conflict, its side
-- has room
local function pool(cfg, tier, mods, rarity, side)
	local room = cfg.rarities[rarity] or cfg.rarities[#cfg.rarities]
	local p, s = W.sides(cfg, mods)
	local have = {}
	for _, m in ipairs(mods) do
		have[m.key] = true
	end
	local out = {}
	for i, def in ipairs(cfg.mods) do
		local open = def.side == "suffix" and s < room.suffix or def.side ~= "suffix" and p < room.prefix
		local sideOk = not side or (side == "suffix") == (def.side == "suffix")
		if open and sideOk and not have[def.key] and R.modAllowed(def, tier) and R.modWeight(def) > 0 then
			local clash = false
			for k in pairs(have) do
				if R.modConflict(def, R.modDef(cfg, k)) then
					clash = true
					break
				end
			end
			if not clash then
				out[#out + 1] = i
			end
		end
	end
	return out
end
W.pool = pool

local function sortMods(cfg, mods)
	table.sort(mods, function(a, b)
		local _, ia = R.modDef(cfg, a.key)
		local _, ib = R.modDef(cfg, b.key)
		return ia < ib
	end)
	return mods
end

-- adds up to `count` modifiers within the room of rarity `rarity` (weighted, gated by the tier; side: only "prefix" or
-- "suffix"); returns the added ones
function W.add(cfg, ws, count, rarity, rand, side)
	local added = {}
	for _ = 1, count do
		local list = pool(cfg, ws.tier, ws.mods, rarity, side)
		if #list == 0 then
			break
		end
		local rows = {}
		for _, i in ipairs(list) do
			rows[#rows + 1] = {i, R.modWeight(cfg.mods[i])}
		end
		local def = cfg.mods[weighted(rows, rand)]
		local m = {key = def.key, value = R.rollValue(def, rand, ws.tier, cfg)}
		ws.mods[#ws.mods + 1] = m
		added[#added + 1] = m
	end
	sortMods(cfg, ws.mods)
	return added
end

-- a new set of modifiers of a rarity name ("Normal", "Magic", "Rare"); countRows: {count, weight} (default by rarity)
function W.roll(cfg, tier, rarityName, rand, countRows)
	local ws = {tier = W.clampTier(cfg, tier), mods = {}}
	local ri = W.rarityIndex(cfg, rarityName)
	if ri == 1 then
		return ws
	end
	local rows = countRows or (ri == 2 and cfg.count.magic or cfg.count.rare)
	W.add(cfg, ws, weighted(rows, rand), ri, rand)
	return ws
end

-- the rarity of a dropped waystone (cfg.dropRarity), then its modifiers
function W.rollDrop(cfg, tier, rand)
	return W.roll(cfg, tier, weighted(cfg.dropRarity, rand), rand)
end

-- ===================================================================== rewards and effects
-- {quantity, rarity, experience, waystone} in percent: the modifiers' rewards (R.bonuses, capped, tier IV / V raise the
-- caps) and perMod.waystone a modifier
function W.bonuses(cfg, mods, tier)
	local b = R.bonuses(cfg, mods, tier)
	local caps = R.bonusCaps(cfg, mods)
	local n = #(mods or {})
	b.waystone = floor((cfg.perMod and cfg.perMod.waystone or 0) * n + 0.5)
	if caps.waystone and b.waystone > caps.waystone then
		b.waystone = caps.waystone
	end
	return b
end

-- rift_core.lua R.effects reads the rift's tiers (its own health / damage steps): a waystone map's level is the run's
-- tier already (waystone_tiers.lua), so a flat table stands in for them
local function fxCfg(cfg)
	if not cfg._fx then
		cfg._fx = {tiers = {{minLevel = 0, pick = {0, 0}}}, beyond = {minLevelStep = 0, health = 0, damage = 0, reward = 0},
			maxTier = cfg.maxTier or 15, brands = cfg.brands, ground = cfg.ground}
	end
	return cfg._fx
end

function W.effects(cfg, mods, tier)
	return R.effects(fxCfg(cfg), mods, W.clampTier(cfg, tier))
end

-- R.monsterHit / R.cinderDamage want the rift's blocks: the same ones live in this config
function W.hit(cfg, fx, hit, T, rand)
	return R.monsterHit(cfg, fx, hit, T, rand)
end

function W.cinderDamage(cfg, maxHealth, share, tier)
	return R.cinderDamage(cfg, maxHealth, share, tier)
end

-- the chance (percent) a map monster comes as an elite with Elites at `elite` (fx.elite, 1 = none); 0 without
function W.eliteChance(cfg, elite)
	local e = (tonumber(elite) or 1) - 1
	if e <= 0 then
		return 0
	end
	return math.min(100, floor((cfg.elites and cfg.elites.base or 8) * e * 100 + 0.5) / 100)
end

-- ===================================================================== texts
function W.modText(cfg, m)
	local def = R.modDef(cfg, m.key)
	local t = def and R.modTier(def, m.value)
	return R.modText(cfg, m) .. (t and (" (" .. R.tierName(cfg, t) .. ")") or "")
end

-- "Rare Waystone Tier IV" ("Waystone Tier IV" for a Normal one)
function W.itemName(cfg, ws)
	local r = W.rarityOf(cfg, ws.mods)
	local base = "Waystone Tier " .. (W.ROMAN[ws.tier] or tostring(ws.tier))
	return r == 1 and base or (W.rarityName(cfg, r) .. " " .. base)
end

function W.rewardText(b)
	local parts = {}
	for _, k in ipairs({{"quantity", "item quantity"}, {"rarity", "item rarity"}, {"experience", "experience"},
			{"waystone", "waystone drops"}}) do
		if (b[k[1]] or 0) > 0 then
			parts[#parts + 1] = "+" .. b[k[1]] .. "% " .. k[2]
		end
	end
	return #parts > 0 and table.concat(parts, ", ") or "none"
end

-- the look text: the map's level, prefixes, suffixes, rewards, how to use it
function W.describe(cfg, ws, level)
	local pre, suf = {}, {}
	for _, m in ipairs(ws.mods) do
		local def = R.modDef(cfg, m.key)
		local list = def and def.side == "suffix" and suf or pre
		list[#list + 1] = W.modText(cfg, m)
	end
	local out = string.format("%s. Opens a map of monster level %d.", W.rarityName(cfg, W.rarityOf(cfg, ws.mods)),
		level or 0)
	if #pre > 0 then
		out = out .. " Prefixes: " .. table.concat(pre, "; ") .. "."
	end
	if #suf > 0 then
		out = out .. " Suffixes: " .. table.concat(suf, "; ") .. "."
	end
	if #ws.mods > 0 then
		out = out .. " Rewards: " .. W.rewardText(W.bonuses(cfg, ws.mods, ws.tier)) .. "."
	end
	return out .. " Use it on the waystone device in your hideout or house."
end

-- ===================================================================== orbs (chaos_crafting.lua keys)
-- PoE's map crafting with this server's orbs: Awakening = transmutation (Normal -> Magic, one modifier), Gilding =
-- alchemy (Normal -> Rare, 4-6), Grafting = exaltation / augmentation (one more on an open side of its rarity), Fate =
-- regal on a Magic one (Rare, one more) and divine on a Rare one (new values), Upheaval = chaos / alteration (new
-- modifiers of the same rarity), Unmaking = annulment (one off), Erasure = scouring (Normal again).
-- Returns ok, reason code (chaos_crafting.lua C.reasons)
function W.orbCheck(cfg, orb, ws)
	local n = #ws.mods
	local r = W.rarityOf(cfg, ws.mods)
	if orb == "transmutation" or orb == "alchemy" then
		if n > 0 then
			return false, "wsNeedNormal"
		end
	elseif orb == "exalted" then
		if r == 1 then
			return false, "wsNoMods"
		end
		if #pool(cfg, ws.tier, ws.mods, r) == 0 then
			return false, r == #cfg.rarities and "wsFull" or "wsMagicFull"
		end
	elseif orb == "divine" or orb == "chaos" or orb == "annulment" or orb == "scouring" then
		if n == 0 then
			return false, "wsNoMods"
		end
	elseif orb == "sockets" then
		return false, "wsSockets"
	else
		return false, "wsOrb"
	end
	return true
end

-- applies an orb (checked first); returns ok, ws or reason code
function W.orbApply(cfg, orb, ws, rand)
	local ok, reason = W.orbCheck(cfg, orb, ws)
	if not ok then
		return false, reason
	end
	local r = W.rarityOf(cfg, ws.mods)
	if orb == "transmutation" then
		W.add(cfg, ws, 1, 2, rand)
	elseif orb == "alchemy" then
		W.add(cfg, ws, weighted(cfg.count.gilding, rand), #cfg.rarities, rand)
	elseif orb == "exalted" then
		W.add(cfg, ws, 1, r, rand)
	elseif orb == "divine" then
		if r == 2 then
			-- Magic -> Rare: the new one goes on a side the Magic room has filled, so the waystone really is Rare
			local p, sx = W.sides(cfg, ws.mods)
			local m = cfg.rarities[2]
			local side = p >= m.prefix and (sx < m.suffix and "prefix" or nil) or "suffix"
			if p >= m.prefix and sx >= m.suffix then
				side = nil
			end
			W.add(cfg, ws, 1, #cfg.rarities, rand, side)
		else
			for _, m in ipairs(ws.mods) do
				m.value = R.rollValue(R.modDef(cfg, m.key), rand, ws.tier, cfg)
			end
		end
	elseif orb == "chaos" then
		ws.mods = {}
		W.add(cfg, ws, weighted(r == 2 and cfg.count.magic or cfg.count.rare, rand), r, rand)
	elseif orb == "annulment" then
		table.remove(ws.mods, rand(1, #ws.mods))
	elseif orb == "scouring" then
		ws.mods = {}
	end
	return true, ws
end

-- what an orb would do (the crafting bench)
function W.orbPreview(cfg, orb, ws)
	local r = W.rarityOf(cfg, ws.mods)
	if orb == "transmutation" then
		return "Normal -> Magic, 1 modifier"
	elseif orb == "alchemy" then
		return "Normal -> Rare, 4-6 modifiers"
	elseif orb == "exalted" then
		return string.format("%d -> %d modifiers", #ws.mods, #ws.mods + 1)
	elseif orb == "divine" then
		return r == 2 and "Magic -> Rare, 1 more modifier" or "new values for every modifier"
	elseif orb == "chaos" then
		return r == 2 and "new modifiers (Magic, 1-2)" or "new modifiers (Rare, 3-6)"
	elseif orb == "annulment" then
		return string.format("%d -> %d modifiers", #ws.mods, #ws.mods - 1)
	elseif orb == "scouring" then
		return "-> Normal, no modifiers"
	end
	return ""
end

return W
