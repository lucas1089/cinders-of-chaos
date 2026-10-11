-- Rich item tooltips, the pure part (ChaosItemTooltip): what a tooltip says about an item, which equipped items it is
-- compared with, which client positions a request may name, and the request budget per player. No engine calls apart
-- from reading the item and its ItemType; data/scripts/chaos/item_tooltip.lua does the protocol and finds the items.
-- Tested by server/tests/item_tooltip_test.lua. Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
-- The tooltip reuses the item readers of data/lib/chaos_crafting.lua (rarity, item level, the engine's modifiers and
-- the Chaos modifiers with their roll ranges, uniques), data/lib/chaos_item_mods.lua (ranges and tiers) and
-- data/lib/chaos_gems.lua (sockets and the effect of each gem in this item).
--
-- One tooltip (JSON object, see item_tooltip.lua for the protocol):
--   key        "<item id>:<version>" from the item's client attributes (Chaos.itemAttr ID / VERSION), nil without them
--   id, name, count, kind ("weapon", "shield", "helmet", ...), slot (what it is worn as, "Two-handed weapon")
--   rarity, rarityName, level                    rarity 0 = normal item; level = item level (plain drops have one too)
--   maxTier                                        the best modifier tier the item level allows (1..8)
--   sides = {p, s, max, mp, ms}                    prefixes and suffixes on the item, the rarity's limit of each (mp / ms:
--                                                  the limit of that side when an Orb of Ruin gave it an extra slot)
--   quality = {q, cap}                             item quality in percent (every modifier value is multiplied by it)
--   ruined                                         true on an item an Orb of Ruin ruined: no orb changes it any more
--   unique = {name, set = {key, name, have, total, pieces, bonuses}}  uniques only; set: a set piece (T.setInfo)
--   base = [{k, l, v, fmt}]                        attack, defense, armour, hit chance, range, attack speed, element,
--                                                  the item type's own bonuses (skills, protections, speed, ...)
--   mods = [{k, l, t, v, g, lo, hi, l2, v2, tr, sd, bd, pw}]  every modifier, prefixes first: attribute key, label,
--                                                  text, value, group, the value range of its tier, tier (1..8), side "p" /
--                                                  "s", bd = bound (Orb of Binding), pw = a legendary power
--   sockets = {count, max, list = [{name, text, color}]}   empty sockets have no name
--   veil = {s = "veiled"} | {s = "open", n, t, tr, tn, lo, hi, h}   the veiled slot (chaos_veiled.lua V.tooltip): name,
--                                                  text, veiled tier 1..4 and its name, its range, h = an effect of its own
--   req = {level, magic, voc}, weight (oz), desc (flavour text), locked
--   store, collects                                a store pouch (pouches.lua): its two lines, no desc and no lock line
--   stats = [{k, l, v, fmt, low}]                  every number the compare view adds up (low = lower is better)
--   cmp = [slot, ...]                              inventory slots worn the same way (the client compares with them)

ChaosItemTooltip = ChaosItemTooltip or {}
local T = ChaosItemTooltip

T.config = {
	maxItems = 3, -- items per request: the hovered one and up to two equipped ones to compare
	bucketSize = 12, -- request budget per player: up to 12 at once, then 6 per second
	bucketPerSecond = 6,
	mapRangeX = 8, -- map items: same floor, at most this far from the player, and visible
	mapRangeY = 6,
	maxNameLength = 64
}

local floor = math.floor

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

local function call(obj, method, ...)
	if not obj then
		return nil
	end
	local fn = obj[method]
	if type(fn) ~= "function" then
		return nil
	end
	local ok, v = pcall(fn, obj, ...)
	if ok then
		return v
	end
	return nil
end

local function int(v)
	return floor(num(v) or 0)
end

-- ---------------------------------------------------------------------------------------------------------------
-- positions: what a client may ask about
-- ---------------------------------------------------------------------------------------------------------------
T.SLOT_FIRST, T.SLOT_LAST = 1, 10 -- head .. ammo: the inventory the 10.98 client shows

-- a position from the client -> {kind = "slot", slot} | {kind = "container", cid, index} | {kind = "map", x, y, z,
-- stackpos} or nil (malformed). Only the shape is checked here; item_tooltip.lua checks access.
function T.decodePos(p)
	if type(p) ~= "table" then
		return nil
	end
	local x, y, z = tonumber(p.x), tonumber(p.y), tonumber(p.z)
	if not x or not y or not z or x ~= floor(x) or y ~= floor(y) or z ~= floor(z) then
		return nil
	end
	if x == 0xFFFF then
		if y >= 0x40 and y < 0x50 then
			if z < 0 or z > 255 then
				return nil
			end
			return {kind = "container", cid = y - 0x40, index = z}
		end
		if y >= T.SLOT_FIRST and y <= T.SLOT_LAST and z == 0 then
			return {kind = "slot", slot = y}
		end
		return nil
	end
	local s = tonumber(p.s) or 0
	if x < 0 or x > 0xFFFE or y < 0 or y > 0xFFFE or z < 0 or z > 15 or s < 0 or s > 9 or s ~= floor(s) then
		return nil
	end
	return {kind = "map", x = x, y = y, z = z, stackpos = s}
end

-- a map position the player may ask about: same floor, near, and the player can see it (canSee = engine answer)
function T.mapAllowed(playerPos, pos, canSee)
	if not playerPos or not pos then
		return false
	end
	if playerPos.z ~= pos.z then
		return false
	end
	if math.abs(playerPos.x - pos.x) > T.config.mapRangeX or math.abs(playerPos.y - pos.y) > T.config.mapRangeY then
		return false
	end
	return canSee == true
end

-- ---------------------------------------------------------------------------------------------------------------
-- request budget (token bucket per player)
-- ---------------------------------------------------------------------------------------------------------------
-- state = {tokens, at} (kept by the caller per player); cost = items in the request. true when allowed.
function T.allow(state, now, cost)
	local size, rate = T.config.bucketSize, T.config.bucketPerSecond
	cost = cost or 1
	if state.at == nil then
		state.tokens, state.at = size, now
	end
	if now > state.at then
		state.tokens = math.min(size, state.tokens + (now - state.at) * rate / 1000)
	end
	state.at = now
	if state.tokens < cost then
		return false
	end
	state.tokens = state.tokens - cost
	return true
end

-- ---------------------------------------------------------------------------------------------------------------
-- slots
-- ---------------------------------------------------------------------------------------------------------------
local SLOTP = {head = 1, necklace = 2, backpack = 4, armor = 8, right = 16, left = 32, legs = 64, feet = 128, ring = 256,
	ammo = 512, twohand = 2048}
local INV = {head = 1, necklace = 2, backpack = 3, armor = 4, right = 5, left = 6, legs = 7, feet = 8, ring = 9, ammo = 10}

local function hasBit(value, b)
	return floor((value or 0) / b) % 2 == 1
end

-- inventory slots an item of this type is worn in (the compare view looks there) and what it is worn as
function T.slotsOf(slotPosition, kind)
	local sp = int(slotPosition)
	-- every item may be held in the hands (the engine's default slot position), so the hands count only for weapons
	-- and shields
	if kind == "weapon" or kind == "shield" then
		local name = kind == "shield" and "Shield" or (hasBit(sp, SLOTP.twohand) and "Two-handed weapon" or "Weapon")
		return {INV.left, INV.right}, name
	end
	local order = {
		{SLOTP.head, INV.head, "Helmet"}, {SLOTP.necklace, INV.necklace, "Amulet"}, {SLOTP.armor, INV.armor, "Armour"},
		{SLOTP.legs, INV.legs, "Legs"}, {SLOTP.feet, INV.feet, "Boots"}, {SLOTP.ring, INV.ring, "Ring"},
		{SLOTP.ammo, INV.ammo, "Ammunition"}, {SLOTP.backpack, INV.backpack, "Container"}
	}
	for _, o in ipairs(order) do
		if hasBit(sp, o[1]) then
			return {o[2]}, o[3]
		end
	end
	return {}, nil
end

-- ---------------------------------------------------------------------------------------------------------------
-- base stats
-- ---------------------------------------------------------------------------------------------------------------
-- engine combat index (bit number of the combat type) -> label; arrays from ItemType:getAbilities() are 1-based
T.COMBAT_LABELS = {[1] = "Physical", [2] = "Energy", [3] = "Earth", [4] = "Fire", [6] = "Life Drain", [7] = "Mana Drain",
	[9] = "Drown", [10] = "Ice", [11] = "Holy", [12] = "Death", [13] = "Water", [14] = "Arcane"}
T.SKILL_LABELS = {"Fist", "Club", "Sword", "Axe", "Distance", "Shielding", "Fishing", "Crafting", "Woodcutting", "Mining",
	"Herbalism", "Armorsmithing", "Weaponsmithing", "Jewelsmithing"}
-- element bit -> label (ItemType:getElementType returns the combat type value)
T.ELEMENT_LABELS = {[2] = "Energy", [4] = "Earth", [8] = "Fire", [512] = "Ice", [1024] = "Holy", [2048] = "Death",
	[4096] = "Water", [8192] = "Arcane"}

local function attrOr(item, attrType, fallback)
	if attrType and call(item, "hasAttribute", attrType) then
		return int(call(item, "getAttribute", attrType))
	end
	return int(fallback)
end

-- the base numbers of an item: its attributes (the rarity roll raises them) over its ItemType
function T.baseStats(item, it)
	local out = {}
	local function add(k, l, v, fmt, low)
		if v and v ~= 0 then
			out[#out + 1] = {k = k, l = l, v = v, fmt = fmt, low = low}
		end
	end
	add("attack", "Attack", attrOr(item, ITEM_ATTRIBUTE_ATTACK, call(it, "getAttack")))
	add("defense", "Defense", attrOr(item, ITEM_ATTRIBUTE_DEFENSE, call(it, "getDefense")))
	add("extradefense", "Extra Defense", attrOr(item, ITEM_ATTRIBUTE_EXTRADEFENSE, call(it, "getExtraDefense")))
	add("armor", "Armour", attrOr(item, ITEM_ATTRIBUTE_ARMOR, call(it, "getArmor")))
	add("hitchance", "Hit Chance", attrOr(item, ITEM_ATTRIBUTE_HITCHANCE, call(it, "getHitChance")), "pct")
	local range = attrOr(item, ITEM_ATTRIBUTE_SHOOTRANGE, call(it, "getShootRange"))
	if range > 1 then -- melee weapons have range 1
		add("range", "Range", range)
	end
	local speed = attrOr(item, ITEM_ATTRIBUTE_ATTACK_SPEED, call(it, "getAttackSpeed"))
	if speed > 0 then
		add("attackspeed", "Attack Interval", floor(speed / 10 + 0.5) / 100, "sec", true)
	end
	local elementDamage = int(call(it, "getElementDamage"))
	if elementDamage > 0 then
		local label = T.ELEMENT_LABELS[int(call(it, "getElementType"))] or "Element"
		add("element", label .. " Damage", elementDamage)
	end
	local ab = call(it, "getAbilities")
	if type(ab) == "table" then
		if type(ab.skills) == "table" then
			for i, label in ipairs(T.SKILL_LABELS) do
				add("skill" .. i, label, int(ab.skills[i]))
			end
		end
		if type(ab.stats) == "table" then
			add("maxhealth", "Max Health", int(ab.stats[1]))
			add("maxmana", "Max Mana", int(ab.stats[2]))
			add("maglevel", "Magic Level", int(ab.stats[4]))
		end
		if type(ab.absorbPercent) == "table" then
			for i = 1, 14 do
				local label = T.COMBAT_LABELS[i]
				if label then
					add("protect" .. i, label .. " Protection", int(ab.absorbPercent[i]), "pct")
				end
			end
		end
		add("speed", "Speed", int(ab.speed))
	end
	return out
end

-- ---------------------------------------------------------------------------------------------------------------
-- modifiers with tiers and roll ranges
-- ---------------------------------------------------------------------------------------------------------------
-- the range of a modifier at its tier (nil for uniques / items without a rarity)
function T.modRange(m, rarity)
	if (rarity or 0) <= 0 or not m.lo then
		return nil
	end
	return m.lo, m.hi
end

local function modFmt(m)
	if m.group == "skill" then
		return nil
	elseif m.group == "chaos" then
		local def = ChaosItemMods and ChaosItemMods.byKey[m.chaosKey]
		return def and def.fmt ~= "flat" and "pct" or nil
	end
	return "pct"
end

-- ---------------------------------------------------------------------------------------------------------------
-- the tooltip
-- ---------------------------------------------------------------------------------------------------------------
-- set info of a set piece (data/lib/chaos_item_sets.lua S.tooltip): {key, name, have, total, pieces = [{n, eq, lv, low,
-- h}], bonuses = [{n, t, on}]} for the viewer. opts.setState = the viewer's counted sets (ChaosItemSets.stateOf);
-- without it opts.equippedIds = {[server id] = true} counts the pieces worn (every level). nil for other items.
function T.setInfo(item, opts)
	local S = ChaosItemSets
	if type(S) ~= "table" or not S.pieceOf then
		return nil
	end
	local set = S.pieceOf(item)
	if not set then
		return nil
	end
	opts = opts or {}
	local state = opts.setState
	if not state and opts.equippedIds then
		local entries = {}
		for _, p in ipairs(set.pieces) do
			if opts.equippedIds[p.id] then
				entries[#entries + 1] = {id = p.id, set = set.key}
			end
		end
		state = S.count(entries, math.huge)
	end
	return S.tooltip(set.key, state)
end

local function clip(s, n)
	s = tostring(s or "")
	if #s > n then
		return s:sub(1, n)
	end
	return s
end

-- the key the client caches a tooltip under: "<item id>:<version>" from item:getClientAttributes() (engine patch
-- 0003); nil when the item has none (plain items) or the engine lacks the method
function T.cacheKey(attrs)
	if type(attrs) ~= "table" then
		return nil
	end
	local A = Chaos and Chaos.itemAttr or {}
	local iid, ver = num(attrs[A.id or 6]), num(attrs[A.version or 7])
	if not iid or iid <= 0 or not ver then
		return nil
	end
	return string.format("%.0f:%.0f", iid, ver)
end

-- everything the tooltip shows. opts = {equippedIds = {[server id] = true}, attrs = item:getClientAttributes()}
function T.build(item, opts)
	opts = opts or {}
	local C, M, G = ChaosCrafting, ChaosItemMods, ChaosGems
	local id = item:getId()
	local it = ItemType and ItemType(id) or nil
	local tip = {id = int(call(it, "getClientId")), count = math.max(1, int(call(item, "getCount")))}
	tip.key = T.cacheKey(opts.attrs)
	tip.name = clip(C and C.itemName(item) or call(item, "getName") or "item", T.config.maxNameLength)

	local kind = M and M.kindOf(item) or nil
	tip.kind = kind
	local slots, slotName = T.slotsOf(call(it, "getSlotPosition"), kind)
	tip.slot = slotName
	if kind then
		tip.cmp = slots
	end

	local rarity = C and C.rarityOf(item) or 0
	local level = M and M.itemLevelOf(item) or 0
	tip.rarity = rarity
	tip.rarityName = rarity > 0 and C.rarityName(rarity) or nil
	tip.level = level > 0 and level or nil
	tip.maxTier = (level > 0 and M) and M.maxTierFor(level) or nil

	local unique = C and C.isUnique(item) or false
	local uniqueEntry = ChaosUniqueById and ChaosUniqueById[id] or nil
	if unique then
		tip.unique = {name = tip.name, set = T.setInfo(item, opts)}
	end

	tip.base = T.baseStats(item, it)
	-- weapons: the interval the viewer swings this one at (vocation, dexterity), with the attack speed cap of engine
	-- patch 0011; "(capped)" when the cap raised it. opts.wielder = {voc = vocation attackspeed, dex = dexterity}
	local w = opts.wielder
	if w and kind == "weapon" and M and M.effectiveInterval then
		local own = attrOr(item, ITEM_ATTRIBUTE_ATTACK_SPEED, call(it, "getAttackSpeed"))
		local ms, capped = M.effectiveInterval(int(call(it, "getAttackSpeed")), own, w.voc, w.dex, w.cap)
		tip.base[#tip.base + 1] = {k = "yourinterval", l = capped and "Your Attack Interval (capped)" or
			"Your Attack Interval", v = floor(ms / 10 + 0.5) / 100, fmt = "sec", low = true}
	end

	local stats = {}
	local function stat(k, l, v, fmt, low)
		for _, s in ipairs(stats) do
			if s.k == k then
				s.v = s.v + v
				return
			end
		end
		stats[#stats + 1] = {k = k, l = l, v = v, fmt = fmt, low = low}
	end
	for _, b in ipairs(tip.base) do
		stat(b.k, b.l, b.v, b.fmt, b.low)
	end

	tip.mods = {}
	if C then
		local mods = C.readMods(item)
		local ordered = {}
		for _, side in ipairs({"prefix", "suffix"}) do
			for _, m in ipairs(mods) do
				if m.side == side then
					ordered[#ordered + 1] = m
				end
			end
		end
		if rarity > 0 and M then
			local p, sx = C.sideCounts(mods)
			tip.sides = {p = p, s = sx, max = M.sideLimit(rarity), mp = M.sideLimitOf(item, "prefix", rarity),
				ms = M.sideLimitOf(item, "suffix", rarity)}
			local q = M.qualityOf(item)
			if q > 0 then
				tip.quality = {q = q, cap = M.qualityCap(rarity)}
			end
			if M.isRuined(item) then
				tip.ruined = true
			end
		end
		for _, m in ipairs(ordered) do
			local row = {k = m.key, l = m.label, t = C.modText(m), v = m.value, g = m.group, l2 = m.label2, v2 = m.value2}
			row.lo, row.hi = T.modRange(m, unique and 0 or rarity)
			if not unique then
				row.tr = m.tier
				row.sd = m.side == "prefix" and "p" or "s"
				row.bd = m.bound or nil
				row.pw = m.power or nil
			end
			tip.mods[#tip.mods + 1] = row
			local fmt = modFmt(m)
			if m.group == "special" then
				stat(m.key, m.label, m.value, "pct")
				stat(m.key2, m.label2, m.value2 or 0, "pct")
			elseif m.group == "element" then
				stat(m.key, m.label .. " Damage", m.value, "pct")
			elseif m.group == "absorb" then
				stat(m.key, m.label .. " Protection", m.value, "pct")
			else
				stat(m.key, m.label, m.value, fmt)
			end
		end
	end
	-- the veiled slot (data/lib/chaos_veiled.lua): veil = {s = "veiled"} | {s = "open", n, t, tr, tn, lo, hi, h}
	local veil = ChaosVeiled and not unique and ChaosVeiled.tooltip(item) or nil
	if veil then
		for _, st in ipairs(veil.st or {}) do
			stat(st.k, st.l, st.v, st.fmt)
		end
		veil.st = nil
		tip.veil = veil
	end

	if G then
		local s = G.read(item)
		if s.count > 0 then
			local group = G.groupOf(item)
			local list = {}
			for i = 1, s.count do
				local gid = s.gems[i]
				if gid and gid > 0 then
					local g = G.gemOf(gid)
					local e = G.effectOf(gid, group)
					list[i] = {name = G.gemName(gid), text = e and G.effectText(e.key, e.value, e.value2) or "",
						color = g and g.type.color or nil}
					if e and e.def then
						stat("gem_" .. e.key, e.def.label, e.value, e.def.fmt ~= "flat" and "pct" or nil)
						if e.value2 and e.def.label2 then
							stat("gem_" .. e.key .. "2", e.def.label2, e.value2, "pct")
						end
					end
				else
					list[i] = {}
				end
			end
			tip.sockets = {count = s.count, max = G.maxSockets(item), list = list}
		end
	end
	tip.stats = stats

	local req = {}
	local reqLevel = int(call(it, "getMinReqLevel"))
	if uniqueEntry and unique and int(uniqueEntry.level) > reqLevel then
		reqLevel = int(uniqueEntry.level)
	end
	if reqLevel > 0 then
		req.level = reqLevel
	end
	local magic = int(call(it, "getMinReqMagicLevel"))
	if magic > 0 then
		req.magic = magic
	end
	local voc = call(it, "getVocationString")
	if type(voc) == "string" and voc ~= "" then
		req.voc = clip(voc, 120)
	end
	if next(req) then
		tip.req = req
	end

	local weight = num(call(item, "getWeight"))
	if weight and weight > 0 then
		tip.weight = floor(weight + 0.5) / 100
	end

	-- flavour text: a unique's own text (its spec), else the item type's; a rolled item's description is its modifiers
	local desc
	if unique and ChaosUniqueSpecs and ChaosUniqueSpecs[id] then
		desc = ChaosUniqueSpecs[id].description
		if G and G.strip then
			desc = G.strip(desc)
		end
	elseif rarity == 0 then
		desc = call(it, "getDescription")
	end
	if type(desc) == "string" and desc ~= "" then
		tip.desc = clip(desc, 300)
	end

	local locked = C and C.customNumber(item, "chaos_locked") or 0
	if locked ~= 0 then
		tip.locked = true
	end
	-- a store pouch (pouches.lua): "Store item: cannot be traded" and what it collects, instead of the lock line
	local P = rawget(_G, "ChaosPouches")
	if P and P.tooltipLines then
		local okP, store, collects = pcall(P.tooltipLines, item)
		if okP and store then
			tip.locked, tip.desc, tip.store, tip.collects = nil, nil, store, collects
			tip.cmp, tip.stats = nil, nil -- a pouch is not compared with worn items
		end
	end
	T.riftKey(item, tip)
	-- a transmog look (transmog.lua): the item is drawn as another item; the tooltip stays the item's own and names
	-- the look (look = {cid, name}: windows that draw the item from this data draw the look, e.g. Inspect Player)
	local lookId = tonumber(call(item, "getCustomAttribute", "chaos_tmog")) or 0
	local lookType = lookId > 0 and ItemType and ItemType(lookId) or nil
	if lookType and int(call(lookType, "getId")) ~= 0 then
		tip.look = {cid = int(call(lookType, "getClientId")), name = clip(call(lookType, "getName") or "?", T.config.maxNameLength)}
	end
	return tip
end

-- a Rift Key (rift.lua RF.applyKey: custom attributes rift_tier / rift_mods, rift_core.lua and rift_config.lua loaded
-- by rift.lua): its map modifiers with their tiers, the reward bonuses, the level it needs and how it is used, the
-- same facts as its look text. A key is not worn, so it has no kind and nothing to compare (M.kindOf calls a shadow
-- orb "other" gear). true when the item is a key.
function T.riftKey(item, tip)
	local R, cfg = ChaosRiftCore, ChaosRiftConfig
	local tier = num(call(item, "getCustomAttribute", "rift_tier"))
	if not tier or tier < 1 or not (R and cfg and R.decodeMods and R.modText and R.bonuses and R.tierInfo) then
		return false
	end
	local ok, key = pcall(function()
		local mods = call(item, "getCustomAttribute", "rift_mods")
		return {tier = floor(tier), mods = R.decodeMods(cfg, type(mods) == "string" and mods or "")}
	end)
	if not ok or type(key) ~= "table" then
		return false
	end
	tip.kind, tip.cmp, tip.slot, tip.stats, tip.sides = nil, nil, nil, nil, nil
	tip.mods = {}
	for _, m in ipairs(key.mods) do
		local def = R.modDef and R.modDef(cfg, m.key) or nil
		local t = def and R.modTier and R.modTier(def, m.value) or nil
		local name = t and R.tierName and R.tierName(cfg, t) or nil
		tip.mods[#tip.mods + 1] = {k = m.key, l = def and def.name or m.key, v = m.value,
			t = clip(R.modText(cfg, m) .. (name and (" (" .. name .. ")") or ""), 120),
			g = def and def.boon and "chaos" or nil} -- boons (pure rewards) in the Chaos colour
	end
	local b = R.bonuses(cfg, key.mods, key.tier)
	local bonus = {}
	for _, k in ipairs({"quantity", "rarity", "experience"}) do
		if (b[k] or 0) > 0 then
			bonus[#bonus + 1] = "+" .. b[k] .. "% " .. (k == "experience" and "experience" or ("item " .. k))
		end
	end
	local info = R.tierInfo(cfg, key.tier)
	tip.req = {level = info.minLevel}
	tip.desc = clip(string.format("Rewards: %s. Opens a rift of tier %d. Use it in a protection zone; your party within %d sqm comes along.",
		#bonus > 0 and table.concat(bonus, ", ") or "normal", key.tier, cfg.partyRange or 8), 300)
	return true
end

return T
