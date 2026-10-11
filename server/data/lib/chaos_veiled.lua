-- Veiled modifiers (ChaosVeiled): a hidden modifier slot that rare and better drops of the high content may roll, shown
-- as "Veiled modifier" until an Orb of Unveiling reveals it. The orb offers three modifiers of the veiled pool (stronger
-- numbers, paired modifiers, a few effects of their own), tier gated by the item level; the player picks one, for good.
--
-- This file is the pure part (no engine calls apart from reading and writing item attributes): the roll of a veiled
-- slot by source and rarity, the orb drop chance, the pool and its tier gates, the offered choices (rolled once and kept
-- on the item, so opening the window again shows the same three), the unveiling, the per-player totals (catalogue keys
-- under the catalogue's caps, the pool's own keys under hookCaps), the maths of the hook effects, the tooltip and look
-- text, and the Orb of Unveiling (ChaosCrafting.addOrb). data/scripts/chaos/veiled.lua is the engine side (drops, the
-- Unveil window on extended opcode 196); item_mods.lua applies the totals. Numbers: data/lib/chaos_veiled_config.lua.
-- Loaded by data/lib/chaos_crafting.lua after the orbs v2. Tested by server/tests/veiled_test.lua. Lua 5.1 / LuaJIT and
-- Lua 5.3 compatible. Overview: server/README.md "Veiled modifiers".
--
-- The veiled slot is not a prefix or a suffix and no other orb touches it: it survives every orb that makes a new copy
-- (ChaosCrafting.recreate copies it), Upheaval, Erasure and Fate included. Uniques and set pieces never carry one.

ChaosVeiled = ChaosVeiled or {}
local V = ChaosVeiled
if not ChaosVeiledConfig then
	ChaosVeiledConfig = dofile("data/lib/chaos_veiled_config.lua")
end
V.config = ChaosVeiledConfig
local CFG = V.config
local A = CFG.attrs
local floor = math.floor

V.byKey = {}
for i, def in ipairs(CFG.pool) do
	def.index = i
	V.byKey[def.key] = def
end

-- random source; tests replace it
V.random = function(a, b)
	return math.random(a, b)
end

-- ---------------------------------------------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------------------------------------------
local function num(v)
	if type(v) == "number" then
		return v
	end
	if type(v) == "userdata" or type(v) == "table" then
		local ok, n = pcall(function() return tonumber(v.value) end)
		return ok and n or nil
	end
	return tonumber(v)
end

local function custom(item, key)
	local ok, v = pcall(function() return item:getCustomAttribute(key) end)
	if ok then
		return v
	end
	return nil
end

local function removeCustom(item, key)
	pcall(function() item:removeCustomAttribute(key) end)
end

local function M()
	return ChaosItemMods
end

local function C()
	return ChaosCrafting
end

-- every custom attribute key of the system (ChaosCrafting.attributeKeys adds them: guild depot, market key list)
V.ATTRS = {A.state, A.offer, A.key, A.tier, A.value}

-- ---------------------------------------------------------------------------------------------------------------
-- the item
-- ---------------------------------------------------------------------------------------------------------------
-- 0 = no veiled slot, 1 = veiled, 2 = unveiled
function V.stateOf(item)
	local s = floor(num(custom(item, A.state)) or 0)
	if s == 1 or s == 2 then
		return s
	end
	return 0
end

-- uniques, set pieces and Rift Keys never carry a veiled slot
function V.excluded(item)
	local Cr = C()
	if Cr and Cr.isUnique and Cr.isUnique(item) then
		return true
	end
	if custom(item, "chaos_unique") ~= nil or custom(item, "chaos_set") ~= nil then
		return true
	end
	if Cr and Cr.isRiftKey and Cr.isRiftKey(item) then
		return true
	end
	return false
end

function V.isVeiled(item)
	return V.stateOf(item) == 1 and not V.excluded(item)
end

function V.isUnveiled(item)
	return V.stateOf(item) == 2 and not V.excluded(item)
end

-- may this item roll a veiled slot? gear, rarity minRarity or better, not excluded, none yet
function V.eligible(item)
	local Cr = C()
	if not item or not Cr then
		return false
	end
	if not Cr.isGear(item) or V.excluded(item) or V.stateOf(item) ~= 0 then
		return false
	end
	return Cr.rarityOf(item) >= CFG.minRarity
end

-- ---------------------------------------------------------------------------------------------------------------
-- sources and chances
-- ---------------------------------------------------------------------------------------------------------------
-- the source of a drop: ctx = {riftTier, omen, raid, ascended, descentDepth} -> "raid" | "ascended" | "omen" |
-- "descent" | "rift" | nil (no high content)
function V.sourceOf(ctx)
	if type(ctx) ~= "table" then
		return nil
	end
	local S = CFG.sources
	local applies = {
		raid = ctx.raid == true,
		ascended = ctx.ascended == true,
		omen = ctx.omen == true,
		descent = (tonumber(ctx.descentDepth) or 0) >= S.descent.minDepth,
		rift = (tonumber(ctx.riftTier) or 0) >= S.rift.minTier
	}
	for _, k in ipairs(CFG.sourceOrder) do
		if applies[k] then
			return k
		end
	end
	return nil
end

-- chance (per 10000) of a veiled slot on an item of this rarity from this source
function V.chance(source, rarity)
	local s = source and CFG.sources[source]
	rarity = tonumber(rarity) or 0
	if not s or rarity < CFG.minRarity then
		return 0
	end
	return rarity >= CFG.highRarity and s.high or s.chance
end

-- roll a veiled slot on a freshly made item; ctx as V.sourceOf. Returns true when the item is veiled now.
function V.rollItem(item, ctx, rand)
	if not V.eligible(item) then
		return false
	end
	local c = V.chance(V.sourceOf(ctx), C().rarityOf(item))
	if c <= 0 or (rand or V.random)(1, 10000) > c then
		return false
	end
	item:setCustomAttribute(A.state, 1)
	return true
end

-- chance (per 10000) of an Orb of Unveiling from a kill of a monster of this tier ("normal" .. "legendary", "boss")
function V.orbChance(source, tier)
	local o = CFG.orbDrop
	local base = source and o.perKill[source] or 0
	return base * (o.tierMult[tier or "normal"] or 1)
end

function V.rollOrb(ctx, tier, rand)
	local c = V.orbChance(V.sourceOf(ctx), tier)
	return c > 0 and (rand or V.random)(1, 10000) <= c
end

-- ---------------------------------------------------------------------------------------------------------------
-- tiers and the pool
-- ---------------------------------------------------------------------------------------------------------------
function V.maxTier(level)
	level = tonumber(level) or 0
	local best = 1
	for t, need in ipairs(CFG.tiers.levels) do
		if level >= need then
			best = t
		end
	end
	return best
end

-- the veiled tiers an item level may roll, best first: {{tier, weight}, ...}
function V.tierRows(level)
	local top, rows = V.maxTier(level), {}
	for t = top, math.max(1, top - CFG.tiers.window + 1), -1 do
		rows[#rows + 1] = {t, CFG.tiers.weights[t] or 1}
	end
	return rows
end

local function weighted(rows, rand)
	local total = 0
	for _, r in ipairs(rows) do
		total = total + r[2]
	end
	if total <= 0 then
		return nil
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

function V.rollTier(level, rand)
	return weighted(V.tierRows(level), rand or V.random) or 1
end

-- the pool modifiers an item of this kind and item level may be offered
function V.pool(kind, level)
	local out = {}
	level = tonumber(level) or 0
	for _, def in ipairs(CFG.pool) do
		if kind and def.kinds[kind] and level >= (def.minLevel or 1) then
			out[#out + 1] = def
		end
	end
	return out
end

function V.range(def, tier)
	local t = math.max(1, math.min(#def.tiers, floor(tonumber(tier) or 1)))
	return def.tiers[t]
end

-- the numbers of each effect of a modifier rolled at `value`: {{k, v}, ...}
function V.effectValues(def, value)
	local out = {}
	value = floor(tonumber(value) or 0)
	for _, e in ipairs(def.effects) do
		local v = value
		if e.mul and e.mul ~= 1 then
			v = math.max(1, floor(value * e.mul + 1e-9))
		end
		out[#out + 1] = {k = e.k, v = v}
	end
	return out
end

function V.text(def, value)
	local vals = {}
	for i, e in ipairs(V.effectValues(def, value)) do
		vals[i] = e.v
	end
	return string.format(def.text, vals[1] or 0, vals[2] or 0, vals[3] or 0)
end

-- the text with each number as a range ("Movement Speed +5-10%, Dodge +2-5%"): the values at lo and at hi
function V.rangeText(def, lo, hi)
	local a, b = V.effectValues(def, lo), V.effectValues(def, hi)
	local vals = {}
	for i = 1, #a do
		vals[i] = a[i].v == b[i].v and tostring(a[i].v) or (a[i].v .. "-" .. b[i].v)
	end
	return (string.format((def.text:gsub("%%d", "%%s")), vals[1] or "", vals[2] or "", vals[3] or ""))
end

function V.tierName(t)
	return "V" .. tostring(floor(tonumber(t) or 1))
end

-- a hook modifier: an effect of its own (not a catalogue modifier)
function V.isHook(def)
	for _, e in ipairs(def.effects) do
		if CFG.hookCaps[e.k] then
			return true
		end
	end
	return false
end

-- ---------------------------------------------------------------------------------------------------------------
-- offered choices
-- ---------------------------------------------------------------------------------------------------------------
function V.encodeOffer(list)
	local parts = {}
	for _, o in ipairs(list) do
		parts[#parts + 1] = string.format("%s:%d:%d", o.key, o.tier, o.value)
	end
	return table.concat(parts, ";")
end

-- the offered choices of a stored text; nil when it is missing or not valid for this kind and item level (every entry
-- in the pool, no key twice, tier and value inside the gates)
function V.decodeOffer(s, kind, level)
	if type(s) ~= "string" or s == "" then
		return nil
	end
	local allowed = {}
	for _, def in ipairs(V.pool(kind, level)) do
		allowed[def.key] = def
	end
	local out, seen = {}, {}
	for key, t, v in s:gmatch("([%w_]+):(%d+):(%d+)") do
		local def = allowed[key]
		t, v = tonumber(t), tonumber(v)
		if not def or seen[key] or t < 1 or t > V.maxTier(level) then
			return nil
		end
		local r = def.tiers[t]
		if not r or v < r[1] or v > r[2] then
			return nil
		end
		seen[key] = true
		out[#out + 1] = {key = key, tier = t, value = v, def = def}
	end
	if #out == 0 then
		return nil
	end
	return out
end

-- roll `n` distinct choices for this kind and item level
function V.rollOffer(kind, level, rand, n)
	rand = rand or V.random
	local rows = {}
	for _, def in ipairs(V.pool(kind, level)) do
		rows[#rows + 1] = {def, def.weight or 10}
	end
	local out = {}
	for _ = 1, n or CFG.offers do
		if #rows == 0 then
			break
		end
		local total = 0
		for _, r in ipairs(rows) do
			total = total + r[2]
		end
		local roll, acc, at = rand(1, total), 0, #rows
		for i, r in ipairs(rows) do
			acc = acc + r[2]
			if roll <= acc then
				at = i
				break
			end
		end
		local def = table.remove(rows, at)[1]
		local tier = V.rollTier(level, rand)
		local r = def.tiers[tier]
		out[#out + 1] = {key = def.key, tier = tier, value = rand(r[1], r[2]), def = def}
	end
	return out
end

-- the item's offered choices: the stored ones, else rolled now and stored (the same three every time the window
-- opens; no reroll by closing it). nil when the item is not veiled.
function V.offers(item, rand)
	if not V.isVeiled(item) then
		return nil
	end
	local Mo = M()
	local kind = Mo and Mo.kindOf(item)
	local level = Mo and Mo.itemLevelOf(item) or 0
	local stored = V.decodeOffer(custom(item, A.offer), kind, level)
	if stored then
		return stored
	end
	local list = V.rollOffer(kind, level, rand)
	if #list == 0 then
		return nil
	end
	item:setCustomAttribute(A.offer, V.encodeOffer(list))
	return list
end

-- the offered choices as the Unveil window shows them
function V.offerView(list)
	local out = {}
	for i, o in ipairs(list or {}) do
		local r = o.def.tiers[o.tier]
		out[#out + 1] = {i = i, key = o.key, name = o.def.name, text = V.text(o.def, o.value), tier = o.tier,
			tn = V.tierName(o.tier), lo = r[1], hi = r[2], value = o.value, hook = V.isHook(o.def) or nil}
	end
	return out
end

-- ---------------------------------------------------------------------------------------------------------------
-- reading and unveiling
-- ---------------------------------------------------------------------------------------------------------------
-- the veiled slot of an item: nil | {state = "veiled"} | {state = "open", key, def, tier, value, text}
function V.read(item)
	local s = V.stateOf(item)
	if s == 0 or V.excluded(item) then
		return nil
	end
	if s == 1 then
		return {state = "veiled"}
	end
	local key = custom(item, A.key)
	local def = type(key) == "string" and V.byKey[key] or nil
	if not def then
		return nil
	end
	local tier = math.max(1, math.min(#def.tiers, floor(num(custom(item, A.tier)) or 1)))
	local value = floor(num(custom(item, A.value)) or 0)
	return {state = "open", key = def.key, def = def, tier = tier, value = value, text = V.text(def, value)}
end

-- reveal choice `n` (1..offers) of a veiled item: the choice is final. Returns ok, entry | false, reason code.
function V.unveil(item, n)
	if V.excluded(item) then
		return false, "unique"
	end
	local s = V.stateOf(item)
	if s == 2 then
		return false, "alreadyUnveiled"
	end
	if s ~= 1 then
		return false, "notVeiled"
	end
	local Mo = M()
	local list = V.decodeOffer(custom(item, A.offer), Mo.kindOf(item), Mo.itemLevelOf(item))
	if not list then
		return false, "noOffer"
	end
	n = tonumber(n)
	local o = n and list[n]
	if not o or n ~= floor(n) then
		return false, "badChoice"
	end
	item:setCustomAttribute(A.key, o.key)
	item:setCustomAttribute(A.tier, o.tier)
	item:setCustomAttribute(A.value, o.value)
	item:setCustomAttribute(A.state, 2)
	removeCustom(item, A.offer)
	return true, V.read(item)
end

-- copy the veiled slot to a new copy of the item (ChaosCrafting.recreate: every orb that makes a new copy keeps it)
function V.copy(from, to)
	for _, k in ipairs(V.ATTRS) do
		local v = custom(from, k)
		if v ~= nil then
			to:setCustomAttribute(k, v)
		end
	end
end

-- a short signature of the slot (the window refuses a choice for an item that changed in between)
function V.signature(item)
	local Cr = C()
	return string.format("%s;v%d;%s", Cr and Cr.signature(item) or "", V.stateOf(item), tostring(custom(item, A.offer) or ""))
end

-- ---------------------------------------------------------------------------------------------------------------
-- totals and the hook effects
-- ---------------------------------------------------------------------------------------------------------------
-- the veiled modifiers of the given items: catalogue = {key -> sum} (the caller adds them to ChaosItemMods.totals'
-- `extra`, under the catalogue's caps), own = {hook key -> capped sum} (every hook key present)
function V.totals(items)
	local catalogue, own = {}, {}
	for k in pairs(CFG.hookCaps) do
		own[k] = 0
	end
	for _, item in ipairs(items or {}) do
		local v = V.read(item)
		if v and v.state == "open" then
			for _, e in ipairs(V.effectValues(v.def, v.value)) do
				if own[e.k] then
					own[e.k] = own[e.k] + e.v
				else
					catalogue[e.k] = (catalogue[e.k] or 0) + e.v
				end
			end
		end
	end
	for k, cap in pairs(CFG.hookCaps) do
		own[k] = math.max(0, math.min(cap, own[k]))
	end
	return catalogue, own
end

-- two {key -> number} tables added up (nil when both are nil)
function V.merge(a, b)
	if not a and not b then
		return nil
	end
	local out = {}
	for _, t in ipairs({a or {}, b or {}}) do
		for k, v in pairs(t) do
			out[k] = (out[k] or 0) + (tonumber(v) or 0)
		end
	end
	return out
end

-- true when any hook key is above 0 (the hit event on the target is needed for the damage hooks)
function V.offensive(totals)
	return totals ~= nil and ((totals.veil_firststrike or 0) > 0 or (totals.veil_desperation or 0) > 0)
end

local function below(hp, maxHp, pct)
	hp, maxHp = tonumber(hp) or 0, tonumber(maxHp) or 0
	return maxHp > 0 and hp * 100 < maxHp * pct
end

-- percent more damage of a hit: ctx = {targetHp, targetMax, ownHp, ownMax}
function V.dealtPct(totals, ctx)
	if not totals or not ctx then
		return 0
	end
	local H, pct = CFG.hook, 0
	local th, tm = tonumber(ctx.targetHp) or 0, tonumber(ctx.targetMax) or 0
	if (totals.veil_firststrike or 0) > 0 and tm > 0 and th * 100 > tm * H.firstStrikeAbove then
		pct = pct + totals.veil_firststrike
	end
	if (totals.veil_desperation or 0) > 0 and below(ctx.ownHp, ctx.ownMax, H.desperationBelow) then
		pct = pct + totals.veil_desperation
	end
	return pct
end

-- percent less damage of a hit taken: ctx = {hp, maxHp, monster (the attacker is a monster), boss, elemental}
function V.takenPct(totals, ctx)
	if not totals or not ctx then
		return 0
	end
	local H, pct = CFG.hook, 0
	if ctx.monster and (totals.veil_gravebound or 0) > 0 and below(ctx.hp, ctx.maxHp, H.graveboundBelow) then
		pct = pct + totals.veil_gravebound
	end
	if ctx.boss and (totals.veil_hexbreaker or 0) > 0 then
		pct = pct + totals.veil_hexbreaker
	end
	if ctx.monster and ctx.elemental and (totals.veil_ashenward or 0) > 0 then
		pct = pct + totals.veil_ashenward
	end
	return math.min(H.maxReduction, pct)
end

-- health and mana a kill restores: heal, mana (whole points)
function V.killRestore(totals, maxHealth, maxMana)
	if not totals then
		return 0, 0
	end
	local h = floor((tonumber(maxHealth) or 0) * (totals.veil_bloodharvest or 0) / 100 + 1e-9)
	local m = floor((tonumber(maxMana) or 0) * (totals.veil_soulharvest or 0) / 100 + 1e-9)
	return h, m
end

-- ---------------------------------------------------------------------------------------------------------------
-- tooltip and look text
-- ---------------------------------------------------------------------------------------------------------------
-- the tooltip's veil block (item_tooltip_core.lua tip.veil): {s = "veiled"} | {s = "open", n = name, t = text, tr = tier,
-- tn = "V3", lo, hi, h = hook}, plus st = [{k, l, v, fmt}] for the compare numbers (the builder takes them out)
function V.tooltip(item)
	local v = V.read(item)
	if not v then
		return nil
	end
	if v.state == "veiled" then
		return {s = "veiled"}
	end
	local r = v.def.tiers[v.tier]
	local out = {s = "open", n = v.def.name, t = v.text, tr = v.tier, tn = V.tierName(v.tier), lo = r[1], hi = r[2],
		h = V.isHook(v.def) or nil, st = {}}
	local Mo = M()
	for _, e in ipairs(V.effectValues(v.def, v.value)) do
		local def = Mo and Mo.byKey[e.k]
		-- a catalogue modifier adds up with the same modifier rolled on the item (its attribute key)
		out.st[#out.st + 1] = {k = def and Mo.attr(e.k) or e.k, l = def and def.label or v.def.name, v = e.v,
			fmt = (not def or def.fmt ~= "flat") and "pct" or nil}
	end
	return out
end

-- the veiled part of the look text ("Veiled modifier: not revealed" / "Veiled: Wraithstride, Movement Speed +9%, ...")
function V.descText(item)
	local v = V.read(item)
	if not v then
		return nil
	end
	if v.state == "veiled" then
		return "Veiled modifier: not revealed (Orb of Unveiling)"
	end
	return string.format("Veiled: %s, %s (%s)", v.def.name, v.text, V.tierName(v.tier))
end

-- ---------------------------------------------------------------------------------------------------------------
-- the Orb of Unveiling
-- ---------------------------------------------------------------------------------------------------------------
local function register()
	local Cr = C()
	if not (Cr and Cr.addOrb and ChaosOrbsConfig) then
		return
	end
	local it
	for _, row in ipairs(ChaosOrbsConfig.items) do
		if row.key == CFG.orbKey then
			it = row
		end
	end
	if not it then
		return
	end
	V.orbId = it.id
	Cr.reasons.notVeiled = "This item has no veiled modifier."
	Cr.reasons.alreadyUnveiled = "The veiled modifier of this item is revealed already."
	Cr.reasons.noOffer = "Use the Orb of Unveiling on the item to see the three choices first."
	Cr.reasons.badChoice = "Choose one of the three veiled modifiers."
	Cr.addOrb({key = CFG.orbKey, id = it.id, name = it.name,
		text = "Reveals the veiled modifier of an item: choose one of three modifiers of the veiled pool (tier by the item level). The choice is final.",
		check = function(item, opts)
			if V.excluded(item) then
				return false, "unique"
			end
			local s = V.stateOf(item)
			if s == 2 then
				return false, "alreadyUnveiled"
			end
			if s ~= 1 then
				return false, "notVeiled"
			end
			if opts and opts.choice ~= nil then
				local Mo = M()
				local list = V.decodeOffer(custom(item, A.offer), Mo.kindOf(item), Mo.itemLevelOf(item))
				if not list then
					return false, "noOffer"
				end
				local n = tonumber(opts.choice)
				if not n or not list[n] then
					return false, "badChoice"
				end
			end
			return true
		end,
		apply = function(item, opts)
			local ok, v = V.unveil(item, opts and opts.choice)
			if not ok then
				return false, Cr.reasons[v] or v
			end
			Cr.rewriteDescription(item)
			return true, {item = item, veil = v, text = string.format("%s: the veil lifts, %s %s (%s).", Cr.itemName(item),
				v.def.name, v.text, V.tierName(v.tier))}
		end,
		preview = function(item)
			local level = M().itemLevelOf(item)
			local rows = V.tierRows(level)
			return string.format("choose 1 of %d veiled modifiers (%s-%s at item level %d)", CFG.offers,
				V.tierName(rows[#rows][1]), V.tierName(rows[1][1]), level)
		end})
end

register()

return V
