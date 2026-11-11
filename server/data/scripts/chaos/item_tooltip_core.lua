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
--   corrupted                                      true on an item a Void Orb corrupted: no orb changes it any more
--   unique = {name, set = {key, name, have, total, pieces, bonuses}}  uniques only; set: a set piece (T.setInfo)
--   passive = {name, text, flavor, fit, warn}      a unique's power as a block (T.splitPassive); fit = the line "Works for your
--                                                  class." / "Asleep: ..." (item_tooltip.lua, O467), warn = it sleeps
--   codex = "unique:<id>" | "set:<key>"            the Codex page of a unique or set piece (T.codexId, O467)
--   set = {..., tier, tiers}  a plain item that is a piece of an open set (pair 28): the same block, the active tier
--   base = [{k, l, v, fmt}]                        attack, defense, armour, hit chance, range, attack speed, element,
--                                                  the item type's own bonuses (skills, protections, speed, ...)
--   mods = [{k, l, t, v, g, lo, hi, l2, v2, tr, sd, bd, pw, cap, over}]  every modifier, the corrupted implicit first, then the
--                                                  prefixes: attribute key, label, text, value, group, the value range of
--                                                  its tier, tier (1..8), side "i" (a Void Orb's implicit) / "p" / "s",
--                                                  bd = bound (Orb of Binding), pw = a legendary power; O471: cap = the most a
--                                                  character gets from all sources of a critical chance (45), critical damage
--                                                  (150) or penetration (20), over = true when the viewer's total is above it
--   sockets = {count, max, list = [{name, text, color}]}   empty sockets have no name
--   veil = {s = "veiled"} | {s = "open", n, t, tr, tn, lo, hi, h}   the veiled slot (chaos_veiled.lua V.tooltip): name,
--                                                  text, veiled tier 1..4 and its name, its range, h = an effect of its own
--   req = {level, magic, voc}, weight (oz), desc (flavour text), locked
--   charges = {n, max} | {unlimited = true}           items with charges (T.chargeInfo)
--   note                                           a line of its own (quivers: they work only with a bow or crossbow)
--   gem = {rows = [{place, label, value, label2, value2, text}], combine}   a gem item (T.gemInfo): its effect per place
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
-- the inventory the client shows: head .. ring (1-9) and the badge slot (13, engine patch 0058). Slot 10 (the old
-- ammunition slot, a second ring slot until 0058) takes nothing; 11 is the store inbox, 12 and 14-16 are retired.
T.SLOTS = {1, 2, 3, 4, 5, 6, 7, 8, 9, 13}
T.SLOT_SET = {}
for _, s in ipairs(T.SLOTS) do
	T.SLOT_SET[s] = true
end
T.QUIVER_NOTE = "Works only while you hold a bow or crossbow."

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
		if T.SLOT_SET[y] and z == 0 then
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

-- the item the client means. A plain item (no per-item id) is named by its slot only, and a container's slots shift
-- whenever an item goes in at the front (loot, a stack split): a request sent before the client saw the shift found
-- the neighbour, and the client kept that tooltip under the hovered item (live test winpkg-35: a Rope showed "Cheese
-- 62", a Training Wand "Gold coin 100"). The client now sends what it hovers: cid = its client id, n = its count
-- (stackables only). infoAt(i) -> client id, count of the item at index i (0-based) or nil. Returns the index whose
-- item matches: `index` itself, else the nearest one (the shifted copy), else nil. No cid (an older client): index.
function T.matchIndex(index, size, infoAt, cid, n)
	cid, n = tonumber(cid), tonumber(n)
	if not cid or cid <= 0 then
		return index
	end
	local function same(i)
		if i < 0 or i >= size then
			return false
		end
		local c, count = infoAt(i)
		return c == cid and (not n or n <= 0 or count == n)
	end
	if same(index) then
		return index
	end
	for d = 1, math.max(index + 1, size) do
		if same(index - d) then
			return index - d
		elseif same(index + d) then
			return index + d
		end
		if index - d < 0 and index + d >= size then
			break
		end
	end
	return nil
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
	twohand = 2048, deck = 4096, badge = 8192}
local INV = {head = 1, necklace = 2, backpack = 3, armor = 4, right = 5, left = 6, legs = 7, feet = 8, ring = 9, badge = 13}

local function hasBit(value, b)
	return floor((value or 0) / b) % 2 == 1
end

-- what kind of weapon it is (owner 2026-11-02: "Two-handed sword", not "Two-handed weapon"; every weapon names its
-- kind). w = {weaponType (engine number), twoHanded, name, fist (a Monk fist weapon), launcher ("bow" / "crossbow")}.
-- Daggers are one-handed swords in the engine (the Thief dual wields any of them, classes.lua): the name tells them.
T.DAGGER_WORDS = {"dagger", "knife", "dirk", "stiletto", "kris", "shiv", "kunai", "sai"}
function T.weaponLabel(w)
	w = w or {}
	local wt, two = int(w.weaponType), w.twoHanded == true
	local name = tostring(w.name or ""):lower()
	local function hands(what)
		return (two and "Two-handed " or "One-handed ") .. what
	end
	if w.fist then
		return "Fist weapon"
	elseif wt == int(WEAPON_SWORD or 1) then
		if not two then
			for _, word in ipairs(T.DAGGER_WORDS) do
				if name:find("%f[%a]" .. word .. "%f[%A]") then
					return "Dagger"
				end
			end
		end
		return hands("sword")
	elseif wt == int(WEAPON_CLUB or 2) then
		return hands("club")
	elseif wt == int(WEAPON_AXE or 3) then
		return hands("axe")
	elseif wt == int(WEAPON_DISTANCE or 5) then
		if w.launcher == "crossbow" then
			return "Crossbow"
		elseif w.launcher == "bow" then
			return "Bow"
		end
		return "Throwing weapon"
	elseif wt == int(WEAPON_WAND or 6) then
		return name:find("%f[%a]rod%f[%A]") and "Rod" or "Wand"
	end
	return two and "Two-handed weapon" or "Weapon"
end

-- inventory slots an item of this type is worn in (the compare view looks there) and what it is worn as. weapon: the
-- T.weaponLabel input (without it a weapon is "Weapon" / "Two-handed weapon")
function T.slotsOf(slotPosition, kind, weapon)
	local sp = int(slotPosition)
	-- every item may be held in the hands (the engine's default slot position), so the hands count only for weapons
	-- and shields
	if kind == "weapon" or kind == "shield" then
		local name
		if kind == "shield" then
			name = "Shield"
		elseif weapon then
			weapon.twoHanded = hasBit(sp, SLOTP.twohand)
			name = T.weaponLabel(weapon)
		else
			name = hasBit(sp, SLOTP.twohand) and "Two-handed weapon" or "Weapon"
		end
		return {INV.left, INV.right}, name
	end
	-- a quiver is worn in the off-hand (the shield hand) next to a bow or crossbow (engine patch 0023)
	if kind == "quiver" then
		return {INV.right}, "Off-hand: Quiver"
	end
	local order = {
		{SLOTP.head, INV.head, "Helmet"}, {SLOTP.necklace, INV.necklace, "Amulet"}, {SLOTP.armor, INV.armor, "Armour"},
		{SLOTP.legs, INV.legs, "Legs"}, {SLOTP.feet, INV.feet, "Boots"}, {SLOTP.ring, INV.ring, "Ring"},
		{SLOTP.backpack, INV.backpack, "Container"}
	}
	for _, o in ipairs(order) do
		if hasBit(sp, o[1]) then
			return {o[2]}, o[3]
		end
	end
	-- a badge (slotType "badge", engine patch 0058) in the badge slot; a deck carries the deck bit and is worn nowhere
	if hasBit(sp, SLOTP.badge) and not hasBit(sp, SLOTP.deck) then
		return {INV.badge}, "Badge"
	end
	return {}, nil
end

-- ---------------------------------------------------------------------------------------------------------------
-- base stats
-- ---------------------------------------------------------------------------------------------------------------
-- engine combat index (bit number of the combat type) -> label; arrays from ItemType:getAbilities() are 1-based
T.COMBAT_LABELS = {[1] = "Physical", [2] = "Energy", [3] = "Earth", [4] = "Fire", [6] = "Life Drain", [7] = "Mana Drain",
	[9] = "Drown", [10] = "Ice", [11] = "Holy", [12] = "Death", [13] = "Water", [14] = "Arcane"}
-- one melee skill (server/README.md "One melee skill"): club, sword and axe (2-4) are one "Melee" row with the highest of
-- the three (tools/patch_melee_skill.py gives a stock item all three at that number); distance is "Ranged"
T.MELEE_SKILLS = {[2] = true, [3] = true, [4] = true}
T.SKILL_LABELS = {"Fist", "Melee", "Melee", "Melee", "Ranged", "Shielding", "Fishing", "Crafting", "Woodcutting", "Mining",
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
			local melee = 0
			for i in pairs(T.MELEE_SKILLS) do
				melee = math.max(melee, int(ab.skills[i]))
			end
			for i, label in ipairs(T.SKILL_LABELS) do
				if not T.MELEE_SKILLS[i] then
					add("skill" .. i, label, int(ab.skills[i]))
				elseif i == 2 then
					add("skill" .. i, label, melee)
				end
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

-- Who may use the item (O307). The engine's vocation string hides an ascended class whose base class is listed, so a
-- crossbow (Ranger, Deadeye; not the Beastmaster, a bow class) read "rangers" and a Beastmaster did not know why it was
-- refused ("You don't have the required profession"). The text names the classes of the rule that
-- server/tools/add_vocations.py applied: a listed base class stands for itself and its ascensions, except the ones the
-- item kind leaves out (the Beastmaster takes bows and arrows only of the launchers, the Berserker two-handed melee
-- weapons only and no shield). Names the table does not know ("knights") stay as the engine wrote them.
T.VOC_FAMILY = {
	{base = "Ranger", ascended = {"Deadeye", "Beastmaster"}},
	{base = "Warrior", ascended = {"Juggernaut", "Berserker"}}
}
local VOC_PLURAL = {thieves = "Thief", thiefs = "Thief"}
for _, name in ipairs({"Mystic", "Ranger", "Warrior", "Elementalist", "Deadeye", "Juggernaut", "Illusionist", "Thief",
	"Ninja", "Samurai", "Berserker", "Beastmaster", "Monk", "Shadowfist", "Iron Sage", "Necromancer", "Lich", "Bone Lord",
	"Templar", "Inquisitor", "Sentinel"}) do
	VOC_PLURAL[name:lower() .. "s"] = name
end

-- does the item kind leave the ascended class out of the base class's list. info = {weaponType, slot, ammoType}
local function leavesOut(ascended, info)
	info = info or {}
	local slot = int(info.slot)
	local function has(bit)
		return floor(slot / bit) % 2 == 1
	end
	local twoHand = has(2048)
	local hand = has(16) or has(32) or twoHand
	local wt = int(info.weaponType)
	local ammo = int(info.ammoType)
	local distance = wt == int(WEAPON_DISTANCE or 5)
	if ascended == "Beastmaster" then
		-- weapons, hand items and ammunition: bows and arrows only (crossbows, bolts, throwing weapons and shields not)
		if distance or hand or has(512) then
			return ammo ~= int(AMMO_ARROW or 2)
		end
		return false
	elseif ascended == "Berserker" then
		-- weapons and hand items: two-handed swords, axes and clubs only, never a shield
		local melee = wt == int(WEAPON_SWORD or 1) or wt == int(WEAPON_CLUB or 2) or wt == int(WEAPON_AXE or 3)
		if melee or hand or distance or wt == int(WEAPON_SHIELD or 4) then
			return not (melee and twoHand)
		end
		return false
	end
	return false
end

function T.vocationText(text, info)
	local names, seen = {}, {}
	local function add(n)
		if not seen[n] then
			seen[n] = true
			names[#names + 1] = n
		end
	end
	local known = false
	for part in (tostring(text):gsub(" and ", ", ")):gmatch("[^,]+") do
		local raw = part:match("^%s*(.-)%s*$")
		local name = VOC_PLURAL[raw:lower()]
		if name then
			known = true
			add(name)
		elseif raw ~= "" then
			add(raw)
		end
	end
	if not known then
		return tostring(text)
	end
	for _, fam in ipairs(T.VOC_FAMILY) do
		if seen[fam.base] then
			for _, a in ipairs(fam.ascended) do
				if not leavesOut(a, info) then
					add(a)
				end
			end
		end
	end
	return table.concat(names, ", ")
end

-- O489: the class text of a STOCK equip rule (install_unique_equip.py records it when a base id is also a unique with an
-- equip rule of its own; movements.xml then carries the looser of the two rules, so the engine's level and vocation
-- string are not what a stock copy is held to). vocations = the stock list of vocation names (nil or empty: everyone,
-- returns ""). A line whose three classes are all listed is named by its base class; any other name is kept, so the
-- text names exactly the classes ChaosUniqueEquip.onEquip lets through.
T.CLASS_LINES = {
	{base = "Warrior", ascended = {"Juggernaut", "Berserker"}},
	{base = "Ranger", ascended = {"Deadeye", "Beastmaster"}},
	{base = "Mystic", ascended = {"Elementalist", "Illusionist"}},
	{base = "Thief", ascended = {"Ninja", "Samurai"}},
	{base = "Necromancer", ascended = {"Lich", "Bone Lord"}},
	{base = "Monk", ascended = {"Shadowfist", "Iron Sage"}},
	{base = "Templar", ascended = {"Inquisitor", "Sentinel"}}
}
function T.stockClassText(vocations)
	if type(vocations) ~= "table" or #vocations == 0 then
		return ""
	end
	local has, covered, count = {}, {}, 0
	for _, v in ipairs(vocations) do
		has[tostring(v)] = true
	end
	for _, fam in ipairs(T.CLASS_LINES) do
		if has[fam.base] and has[fam.ascended[1]] and has[fam.ascended[2]] then
			covered[fam.ascended[1]], covered[fam.ascended[2]] = true, true
			count = count + 1
		end
	end
	if count == #T.CLASS_LINES then
		return "" -- every class: the row says "all classes"
	end
	local names, seen = {}, {}
	for _, v in ipairs(vocations) do
		v = tostring(v)
		if not covered[v] and not seen[v] then
			seen[v] = true
			names[#names + 1] = v
		end
	end
	-- O490: a base class named alone reads as its whole line, so a base class allowed without any of its ascended classes
	-- is "Name only"
	for _, fam in ipairs(T.CLASS_LINES) do
		if seen[fam.base] and not has[fam.ascended[1]] and not has[fam.ascended[2]] then
			for i, n in ipairs(names) do
				if n == fam.base then
					names[i] = fam.base .. " only"
				end
			end
		end
	end
	if #names == 1 and names[1] == "None" then
		return "no class" -- only the vocation None (id 0) is listed: no class of the game meets the rule
	end
	-- the Ranger and Warrior lines are named class by class even when whole, as the engine's text is (T.VOC_FAMILY, O307):
	-- a crossbow says "Ranger, Deadeye", so a bow that takes the Beastmaster says so and does not read just "Ranger"
	local out = {}
	for _, n in ipairs(names) do
		out[#out + 1] = n
		for _, fam in ipairs(T.VOC_FAMILY) do
			if n == fam.base and has[fam.ascended[1]] and has[fam.ascended[2]] then
				out[#out + 1] = fam.ascended[1]
				out[#out + 1] = fam.ascended[2]
			end
		end
	end
	return table.concat(out, ", ")
end

-- O490: the classes a class text stands for, the reading the audit (tools/audit_equip_tooltips.py) holds the tooltip to:
-- a base class named alone is its whole line (the class and its two ascended classes), "Name only" is that class alone, a
-- line named class by class is those classes, "all classes" (or no text) is every class. Returns {name = true}.
function T.readClasses(text)
	local out = {}
	text = tostring(text or ""):match("^%s*(.-)%s*$")
	if text == "" or text:lower() == "all classes" then
		for _, fam in ipairs(T.CLASS_LINES) do
			out[fam.base], out[fam.ascended[1]], out[fam.ascended[2]] = true, true, true
		end
		return out
	end
	if text:lower() == "no class" then
		out.None = true
		return out
	end
	local named = {}
	for part in text:gmatch("[^,]+") do
		part = part:match("^%s*(.-)%s*$")
		local alone = part:match("^(.-) only$")
		if alone then
			out[alone] = true
		elseif part ~= "" then
			named[part] = true
		end
	end
	local known = {}
	for _, fam in ipairs(T.CLASS_LINES) do
		local names = {fam.base, fam.ascended[1], fam.ascended[2]}
		for _, n in ipairs(names) do
			known[n] = true
		end
		if named[fam.base] and not named[fam.ascended[1]] and not named[fam.ascended[2]] then
			for _, n in ipairs(names) do
				out[n] = true
			end
		else
			for _, n in ipairs(names) do
				if named[n] then
					out[n] = true
				end
			end
		end
	end
	for n in pairs(named) do
		if not known[n] then
			out[n] = true
		end
	end
	return out
end

-- O490: the rule each item is held to, from data/lib/chaos_equip_rules.lua (tools/install_equip_rules.py writes it from the
-- installed movements.xml and weapons.xml: {level, class list index (0 = every class), magic level}). The engine's item
-- type holds only the SHOWN vocations (an ascended class of a line is hidden, so a wand for the Mystic and the Illusionist
-- reads "mystics and necromancers" and the Elementalist was refused after the tooltip said yes) and the numbers of one of
-- the two entries an item can have (an Equip entry and a weapon entry). Nil without the file: the engine's values stand.
T.equipRulesPath = "data/lib/chaos_equip_rules.lua"
local equipRules -- nil: not read yet, false: none
function T.setEquipRules(tbl)
	equipRules = type(tbl) == "table" and type(tbl.rules) == "table" and tbl or false
end
function T.equipRuleOf(id)
	if equipRules == nil then
		local ok, tbl = pcall(dofile, T.equipRulesPath)
		T.setEquipRules(ok and tbl or nil)
	end
	local r = equipRules and equipRules.rules[id]
	if type(r) ~= "table" then
		return nil
	end
	local set = int(r[2]) > 0 and equipRules.sets and equipRules.sets[int(r[2])] or nil
	return {level = int(r[1]), magic = int(r[3]), vocations = set}
end

-- the vocation string for a rule's class list: the engine's own text when it already reads as exactly those classes (the
-- texts that were right do not change), else the names of the list (T.stockClassText)
function T.ruleVocString(vocString, vocations, info)
	local old = (type(vocString) == "string" and vocString ~= "") and T.vocationText(vocString, info) or ""
	local want = {}
	local list = (type(vocations) == "table" and #vocations > 0) and vocations or nil
	if list then
		for _, v in ipairs(list) do
			want[tostring(v)] = true
		end
	else
		want = T.readClasses("")
	end
	local have, same = T.readClasses(old), true
	for n in pairs(want) do
		same = same and have[n] == true
	end
	for n in pairs(have) do
		same = same and want[n] == true
	end
	if same then
		return vocString
	end
	return T.stockClassText(list)
end

-- The class line of an item worn on the body or held in the hands (the "For ..." row of the tooltip). The owner saw
-- armour with no line: the engine's vocation string is empty when the item's equip event lists no class (a stock
-- Warrior Helmet is worn by everybody), and an empty string printed nothing. Now every worn item says who may use it:
--   1. a unique with an own equip rule (spec.equip.lines) names those class lines, the rule onEquip enforces;
--   2. else the engine's vocation string, named as T.vocationText does;
--   3. else, for an item with a worn slot (helmet, armour, legs, boots, ring, amulet, weapon, shield, quiver), "all
--      classes": the equip event lets every class wear it. A container (backpack) and a badge show nothing.
-- slotName = tip.slot (T.slotsOf); returns nil for any other item.
T.ALL_CLASSES = "all classes"
T.CLASS_ROW_MAX = 120
-- O490: the row is cut between two names, never in the middle of one (the longest row of the installed rules is 103)
local function clipRow(s)
	if #s <= T.CLASS_ROW_MAX then
		return s
	end
	local cut = s:sub(1, T.CLASS_ROW_MAX + 1):match("^(.*),[^,]*$")
	return cut or s:sub(1, T.CLASS_ROW_MAX)
end
function T.classLine(vocString, info, slotName, equip)
	if type(equip) == "table" and type(equip.lines) == "table" and #equip.lines > 0 then
		return clipRow(table.concat(equip.lines, ", "))
	end
	if type(vocString) == "string" and vocString ~= "" then
		return clipRow(T.vocationText(vocString, info))
	end
	if slotName and slotName ~= "Container" and slotName ~= "Badge" then
		return T.ALL_CLASSES
	end
	return nil
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

-- charges of an item that has them (exercise and training weapons, rings, runes with charges): {n, max} (max = the
-- item type's full charges, when more than n), {unlimited = true} for a type with charges whose item carries none (it is
-- never used up), or nil (no charges). charges = the item's ITEM_ATTRIBUTE_CHARGES (nil: the attribute is missing);
-- typeCharges = ItemType:getCharges(). Live test winpkg-35: a Lasting Exercise Wand showed only its name and weight.
function T.chargeInfo(charges, typeCharges)
	typeCharges = tonumber(typeCharges) or 0
	charges = tonumber(charges)
	if not charges then
		return typeCharges > 0 and {unlimited = true} or nil
	end
	if charges <= 0 and typeCharges <= 0 then
		return nil
	end
	return {n = math.max(0, floor(charges)), max = typeCharges > charges and floor(typeCharges) or nil}
end

-- a unique's passive as a block of its own (owner 2026-11-01: "deixe esse texto especial mais em evidência"): the
-- O475 (2026-11-10): the passive line of a unique from the CURRENT config, whatever the stored description says. The line is written
-- into the description when the item is made (tools/gen_unique_specs.py), so an owned copy keeps the numbers of its day (O473
-- repriced 28 passives: the exact text is no longer in it). The line starts at "<Name>: " and ends before " (Requires level N" (or
-- " (Requer nivel N") or at the end. `en` is the current English line (ChaosUniquePassivesCore.text), `name` the passive's English
-- name. Returns the description with the current line in the place of the stored one, and true when a line was replaced; the
-- description as it was and false when the exact line is in it already (nothing to do) or no "<Name>: " is in it (then the
-- caller keeps the old behaviour: no block). A name that appears twice is left alone (the first "<Name>: " would be a guess).
function T.refreshPassive(desc, en, name)
	if type(desc) ~= "string" or type(en) ~= "string" or en == "" or type(name) ~= "string" or name == "" then
		return desc, false
	end
	if desc:find(en, 1, true) then
		return desc, false
	end
	local key = name .. ": "
	local from = desc:find(key, 1, true)
	if not from or desc:find(key, from + 1, true) then
		return desc, false
	end
	local to = #desc
	for _, req in ipairs({" (Requires level ", " (Requer n\195\173vel "}) do
		local r = desc:find(req, from, true)
		if r and r - 1 < to then
			to = r - 1
		end
	end
	return desc:sub(1, from - 1) .. en .. desc:sub(to + 1), true
end

-- passive text (texts = its line in each language, "Name: rule. For: ...") found in the description -> {name, text
-- (the rule without the name), flavor (the rest of the description)}; nil when no text is in it. tip.desc keeps the
-- whole text for a client that does not know the block.
function T.splitPassive(desc, texts, name)
	if type(desc) ~= "string" or type(name) ~= "string" or name == "" then
		return nil
	end
	for _, t in ipairs(texts or {}) do
		local from, to
		if type(t) == "string" and t ~= "" then
			from, to = desc:find(t, 1, true)
		end
		if from then
			local rule = t:sub(1, #name + 1) == name .. ":" and t:sub(#name + 2):gsub("^%s+", "") or t
			local flavor = (desc:sub(1, from - 1) .. " " .. desc:sub(to + 1)):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
			return {name = name, text = rule, flavor = flavor}
		end
	end
	return nil
end

-- the Codex page that explains a unique (O467; right-click > Open in Codex in client game_codex): "unique:<item id>" when
-- the Codex has a page for it (byId = ChaosUniqueById, the list tools/gen_codex_data.lua builds the Uniques tab from), else
-- "set:<set key>" for a set piece (set = tip.unique.set), else nil
function T.codexId(id, byId, set)
	if type(byId) == "table" and byId[id] then
		return "unique:" .. tostring(id)
	end
	if type(set) == "table" and type(set.key) == "string" and set.key ~= "" then
		return "set:" .. set.key
	end
	return nil
end

-- a Monk fist weapon's "Estimated DPS" row (owner 2026-11-01 "sem dps" on a pair of ember knuckles): the engine hits
-- with fists, and monk_combat.lua scales the hit to the fist attack (ChaosMonk.fistAttack: the item's attack or the
-- level value, the higher), the vocation's meleeDamage (the base Monk's for another viewer) and the weapon power of the
-- fist skill. Mean hit = max / 2 (melee). false when the item is no fist weapon (the other rows decide), nil when it is
-- one but cannot be worked out.
function T.fistDps(item, it, w, ms)
	local MK = ChaosMonk
	local u = MK and MK.cfg and MK.cfg.unarmed
	if not (u and u.fistWeapons and MK.fistAttack and MK.maxWeaponDamage) then
		return false
	end
	local id, found = int(call(item, "getId")), false
	for _, f in ipairs(u.fistWeapons) do
		if f == id then
			found = true
			break
		end
	end
	if not found then
		return false
	end
	local level, skill = int(w.level), int(w.fist)
	if level < 1 or not ms or ms <= 0 then
		return nil
	end
	local attack = attrOr(item, ITEM_ATTRIBUTE_ATTACK, call(it, "getAttack"))
	local max = MK.maxWeaponDamage(level, skill, MK.fistAttack(level, attack), 1)
		* ((u.meleeDamage or {})[int(w.vocId)] or (u.meleeDamage or {})[17] or 1)
	local WP = ChaosWeaponPower
	local power = WP and WP.hitFactor and WP.hitFactor("fist", level, skill) or 1
	local dps = ChaosWeaponDps.round(max / 2 * power / (ms / 1000))
	if not dps then
		return nil
	end
	local DS = ChaosDisplayScale
	if DS and DS.factor then
		dps = dps * DS.factor(level)
	end
	return {k = "dps", l = "Estimated DPS", v = dps, fmt = "est"}
end

-- "Estimated DPS" row of a weapon (weapon_dps_core.lua). w = the wielder {level, melee (best melee skill), distance};
-- ms = the interval the viewer swings it at. Melee swords, axes, clubs and distance weapons only; nil otherwise.
-- The number is x the display scale of the wielder's level, like every combat number (display_scale_core.lua).
function T.dpsRow(item, it, w, ms)
	local D = ChaosWeaponDps
	if not (D and w and w.level) then
		return nil
	end
	local fist = T.fistDps(item, it, w, ms)
	if fist ~= false then
		return fist
	end
	local wt = int(call(it, "getWeaponType"))
	local melee = {[int(WEAPON_SWORD or 1)] = "sword", [int(WEAPON_CLUB or 2)] = "club", [int(WEAPON_AXE or 3)] = "axe"}
	local typeName = melee[wt]
	local isDistance = wt == int(WEAPON_DISTANCE or 5)
	if not typeName and not isDistance then
		return nil
	end
	local launcher = isDistance and ChaosArchery and ChaosArchery.kindOfType and ChaosArchery.kindOfType(it) or nil
	local hasBit = bit and bit.band and bit.band(int(call(it, "getSlotPosition")), int(SLOTP_TWO_HAND or 2048)) ~= 0
	-- the price of the weapon's family for a wielder that gets the traits (weapon_families_core.lua, O454)
	local FM = ChaosWeaponFamilies
	local familyFactor = typeName and FM and FM.affected and w.vocId and FM.affected(w.vocId) and FM.single(typeName) or nil
	local dps = D.round(D.estimate({
		familyFactor = familyFactor,
		level = w.level, skill = typeName and w.melee or w.distance,
		attack = attrOr(item, ITEM_ATTRIBUTE_ATTACK, call(it, "getAttack")), interval = ms,
		launcher = launcher, twoHanded = hasBit or false, weaponType = typeName,
		hitChance = attrOr(item, ITEM_ATTRIBUTE_HITCHANCE, call(it, "getHitChance"))}))
	if not dps then
		return nil
	end
	local DS = ChaosDisplayScale
	if DS and DS.factor then
		dps = dps * DS.factor(w.level)
	end
	return {k = "dps", l = "Estimated DPS", v = dps, fmt = "est"}
end

-- a wand's or rod's "Attack" (the viewer's hit range) and "Estimated DPS" rows (O353). w = the wielder {level, magic};
-- ms = the interval the viewer shoots it at. The flat min..max comes from ChaosWeaponDps.wands (item_tooltip.lua builds
-- it at startup with D.collectWands); the factor is the one weapon_styles.lua puts on every wand hit. Both rows x the
-- display scale of the wielder's level. Returns attack row, dps row (nil, nil when the item is no known wand).
function T.wandRows(item, it, w, ms)
	local D = ChaosWeaponDps
	if not (D and D.wands and w and w.level) or int(call(it, "getWeaponType")) ~= int(WEAPON_WAND or 6) then
		return nil, nil
	end
	local entry = D.wands[int(call(item, "getId"))]
	if not entry then
		return nil, nil
	end
	local WS, WP = ChaosWeaponSkill, ChaosWeaponPower
	local factor = (WS and WS.wandFactor and WS.wandFactor(w.level, w.magic or 0) or 1)
		* (WP and WP.levelFactor and WP.levelFactor("wand", w.level) or 1)
	local DS = ChaosDisplayScale
	local scale = DS and DS.factor and DS.factor(w.level) or 1
	local lo, hi = D.wandHit(entry.min, entry.max, factor * scale)
	if not lo then
		return nil, nil
	end
	local attack = {k = "attack", l = "Attack", v = floor((lo + hi) / 2 + 0.5), lo = lo, hi = hi, fmt = "range"}
	local dps = D.round(D.wandEstimate({min = entry.min, max = entry.max, factor = factor * scale, interval = ms}))
	return attack, dps and {k = "dps", l = "Estimated DPS", v = dps, fmt = "est"} or nil
end

-- everything the tooltip shows. opts = {equippedIds = {[server id] = true}, attrs = item:getClientAttributes()}
-- O471: the character cap of the modifier of a row (ChaosItemMods.config.crit / .penetration), and which of the viewer's
-- totals it is compared with (opts.over = {chance, amount}, set by item_tooltip.lua from the engine's totals): cap, kind
function T.capOf(m)
	local M = ChaosItemMods
	if not M or not M.config or not M.config.crit then
		return nil
	end
	local k = tostring(m.chaosKey or m.key or ""):lower()
	if k == "rarity_criticalhitchance" then
		return M.config.crit.chanceCap, "chance"
	elseif k == "rarity_criticalhitamount" then
		return M.config.crit.amountCap, "amount"
	elseif k == "physpen" or k == "elepen" then
		return M.config.penetration.cap, "pen"
	end
	return nil
end

-- O479: the effects of a gem item as data, one row per place: {rows = {{place = "weapon" | "armour" | "jewel", label,
-- value, label2, value2, text}}, combine = true | false}. label / value are the effect name and its number ("Holy Damage",
-- "+2%"; a pair effect adds label2 / value2), text the same as one English line. The client writes the name in its own
-- language and the number in its own colour; a client without this field shows tip.desc. nil for an item that is no gem.
function T.gemInfo(G, id)
	if not (G and G.isGem and G.isGem(id)) then
		return nil
	end
	local rows = {}
	for _, place in ipairs({"weapon", "armour", "jewel"}) do
		local e = G.effectOf(id, place)
		if e then
			local p = G.effectParts(e.key, e.value, e.value2)
			rows[#rows + 1] = {place = place, label = p.label, value = p.value, label2 = p.label2, value2 = p.value2,
				text = G.effectText(e.key, e.value, e.value2)}
		end
	end
	if #rows == 0 then
		return nil
	end
	return {rows = rows, combine = G.gemOf(id).tier < G.TIERS}
end

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
	local weapon = nil
	if kind == "weapon" then
		local MK = ChaosMonk
		local fists = MK and MK.cfg and MK.cfg.unarmed and MK.cfg.unarmed.fistWeapons or {}
		local fist = false
		for _, f in ipairs(fists) do
			if f == int(id) then
				fist = true
				break
			end
		end
		local wt = int(call(it, "getWeaponType"))
		local A = ChaosArchery
		weapon = {weaponType = wt, name = call(it, "getName") or "", fist = fist,
			launcher = wt == int(WEAPON_DISTANCE or 5) and A and A.kindOfType and A.kindOfType(it) or nil}
	end
	local slots, slotName = T.slotsOf(call(it, "getSlotPosition"), kind, weapon)
	tip.slot = slotName
	if kind then
		tip.cmp = slots
	end

	local rarity = C and C.rarityOf(item) or 0
	local level = M and M.itemLevelOf(item) or 0
	-- a plain item that is no gear has no item level: drops before 2026-10-22 stamped one on catalysts and trophies
	if level > 0 and rarity == 0 and C and C.isGear and not C.isGear(item) then
		level = 0
	end
	tip.rarity = rarity
	tip.rarityName = rarity > 0 and C.rarityName(rarity) or nil
	tip.level = level > 0 and level or nil
	tip.maxTier = (level > 0 and M) and M.maxTierFor(level) or nil

	local unique = C and C.isUnique(item) or false
	local uniqueEntry = ChaosUniqueById and ChaosUniqueById[id] or nil
	if unique then
		tip.unique = {name = tip.name, set = T.setInfo(item, opts)}
	else
		tip.set = T.setInfo(item, opts) -- a piece of an open set (pair 28, data/lib/chaos_gear_sets.lua): plain gear
	end

	tip.base = T.baseStats(item, it)
	-- a quiver (data/lib/chaos_archery_core.lua): its base's implicit modifiers, and that it works only with a bow or
	-- crossbow in the hands
	if kind == "quiver" and ChaosArchery and M then
		for _, r in ipairs(ChaosArchery.implicitRows(id, M)) do
			-- the key of the modifier attribute, so the compare view adds an implicit and a rolled one together
			tip.base[#tip.base + 1] = {k = M.attr(r.key), l = r.def.label, v = r.value,
				fmt = r.def.fmt ~= "flat" and "pct" or nil, imp = true}
		end
		tip.note = T.QUIVER_NOTE
	end
	-- a sword, axe or club: its family's trait (weapon_families_core.lua, O454), for a viewer whose class gets the traits (not
	-- the Monk line); the server turns the line into the player's language (item_tooltip.lua)
	if kind == "weapon" and weapon and not weapon.fist and not weapon.launcher and ChaosWeaponFamilies then
		local FM = ChaosWeaponFamilies
		local names = {[int(WEAPON_SWORD or 1)] = "sword", [int(WEAPON_CLUB or 2)] = "club", [int(WEAPON_AXE or 3)] = "axe"}
		local family = FM.familyOf(names[weapon.weaponType])
		local viewer = opts.wielder
		if family and FM.config.enabled and (not (viewer and viewer.vocId) or FM.affected(viewer.vocId)) then
			tip.note = FM.note(family)
		end
	end
	-- weapons: the interval the viewer swings this one at (vocation, dexterity), with the attack speed cap of engine
	-- patch 0011; "(capped)" when the cap raised it. opts.wielder = {voc = vocation attackspeed, dex = dexterity, bonus = player attack speed bonus %}
	local w = opts.wielder
	if w and kind == "weapon" and M and M.effectiveInterval then
		local own = attrOr(item, ITEM_ATTRIBUTE_ATTACK_SPEED, call(it, "getAttackSpeed"))
		local ms, capped = M.effectiveInterval(int(call(it, "getAttackSpeed")), own, w.voc, w.dex, w.cap, w.bonus)
		tip.base[#tip.base + 1] = {k = "yourinterval", l = capped and "Your Attack Interval (capped)" or
			"Your Attack Interval", v = floor(ms / 10 + 0.5) / 100, fmt = "sec", low = true}
		-- the estimated damage per second of the auto attack with this weapon (weapon_dps_core.lua; an estimate)
		local est = T.dpsRow(item, it, w, ms)
		if est then
			tip.base[#tip.base + 1] = est
		end
		-- a wand or rod: its hit and its damage per second for the viewer (O353)
		local wandAttack, wandDps = T.wandRows(item, it, w, ms)
		if wandAttack then
			table.insert(tip.base, 1, wandAttack)
		end
		if wandDps then
			tip.base[#tip.base + 1] = wandDps
		end
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
		for _, side in ipairs({"implicit", "prefix", "suffix"}) do
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
			if M.isCorrupted(item) then
				tip.corrupted = true
			end
		end
		for _, m in ipairs(ordered) do
			local row = {k = m.key, l = m.label, t = C.modText(m), v = m.value, g = m.group, l2 = m.label2, v2 = m.value2}
			row.lo, row.hi = T.modRange(m, unique and 0 or rarity)
			if not unique then
				row.tr = m.tier
				row.sd = m.side == "prefix" and "p" or (m.side == "implicit" and "i" or "s")
				row.bd = m.bound or nil
			end
			row.pw = m.power or nil -- a unique's built-in legendary power shows in the power colour too
			local cap, capKind = T.capOf(m)
			if cap then
				row.cap = cap
				row.over = opts.over and opts.over[capKind] or nil
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
					if e and G.effectParts then -- O479: the name and the number apart, so the client can translate the name
						local pp = G.effectParts(e.key, e.value, e.value2)
						list[i].l, list[i].v, list[i].l2, list[i].v2 = pp.label, pp.value, pp.label2, pp.value2
					end
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
	tip.gem = T.gemInfo(G, id) -- a gem item: its three effects as rows (O479)

	local req = {}
	local reqLevel = int(call(it, "getMinReqLevel"))
	local vocString = call(it, "getVocationString")
	-- O489 (owner 2026-11-11: a rolled ring said "level 30, all classes" and could not be worn): a stock copy of a base id
	-- that is also a unique with its own equip rule is held to the STOCK rule (chaos_unique_equip.lua), not to the looser
	-- entry of movements.xml the engine reads. The generated movement script publishes the stock rules.
	local stockRule = not unique and ChaosUniqueEquip and type(ChaosUniqueEquip.stock) == "table" and ChaosUniqueEquip.stock[id]
	local weaponInfo = {
		weaponType = int(call(it, "getWeaponType")), slot = int(call(it, "getSlotPosition")),
		ammoType = int(call(it, "getAmmoType"))
	}
	-- O490 (the same bug on other items): the generated rules table is what the server holds the item to (Equip entry and
	-- weapon entry, every class of the list); a unique copy with a rule of its own shows that rule below
	local ownEquip = unique and uniqueEntry and ChaosUniqueSpecs and ChaosUniqueSpecs[id] and ChaosUniqueSpecs[id].equip or nil
	local rule = not ownEquip and T.equipRuleOf(id) or nil
	local magic = int(call(it, "getMinReqMagicLevel"))
	if rule then
		reqLevel, magic = rule.level, rule.magic
		vocString = T.ruleVocString(vocString, rule.vocations, weaponInfo)
	elseif type(stockRule) == "table" then
		reqLevel = int(stockRule.level)
		vocString = T.stockClassText(stockRule.vocations)
	end
	if uniqueEntry and unique and int(uniqueEntry.level) > reqLevel then
		reqLevel = int(uniqueEntry.level)
	end
	if reqLevel > 0 then
		req.level = reqLevel
	end
	if magic > 0 then
		req.magic = magic
	end
	req.voc = T.classLine(vocString, weaponInfo, tip.slot, unique and uniqueEntry and ChaosUniqueSpecs and ChaosUniqueSpecs[id] and ChaosUniqueSpecs[id].equip or nil)
	if next(req) then
		tip.req = req
	end

	-- charges (T.chargeInfo): the item's charges attribute against its type's
	if ITEM_ATTRIBUTE_CHARGES and not call(it, "isStackable") then
		local has = call(item, "hasAttribute", ITEM_ATTRIBUTE_CHARGES) == true
		tip.charges = T.chargeInfo(has and int(call(item, "getAttribute", ITEM_ATTRIBUTE_CHARGES)) or nil,
			int(call(it, "getCharges")))
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
	elseif rarity == 0 and kind ~= "quiver" then -- a quiver's type text repeats its implicits and the note above
		desc = call(it, "getDescription")
	end
	-- an Ember / Crown Shard: where it becomes an orb (salvage.lua S.shardHint)
	local SV = rawget(_G, "ChaosSalvage")
	if SV and SV.shardHint then
		local okH, hint = pcall(SV.shardHint, id)
		if okH and hint then
			desc = (type(desc) == "string" and desc ~= "") and (desc .. " " .. hint) or hint
		end
	end
	if type(desc) == "string" and desc ~= "" then
		-- a unique's description carries its passive line (O278): room for it
		tip.desc = clip(desc, unique and 600 or 300)
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
	local rec = R.warnLevel and R.warnLevel(cfg, key.tier) -- O476: the recommended solo level, as in the look text
	tip.desc = clip(string.format("Rewards: %s. Opens a rift of tier %d.%s Use it in a protection zone; your party within %d sqm comes along.",
		#bonus > 0 and table.concat(bonus, ", ") or "normal", key.tier,
		rec and string.format(" Recommended: level %d alone, or a party.", rec) or "", cfg.partyRange or 8), 300)
	return true
end

return T
