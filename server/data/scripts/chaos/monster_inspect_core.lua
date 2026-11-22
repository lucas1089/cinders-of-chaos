-- Inspect Monster, the pure part (ChaosMonsterInspect; O721): who may be inspected from where, the request budget, the
-- reading of a monster file's attacks and abilities, the rows of every section of the window, the bestiary stage that
-- opens loot and places, and the payload. No engine calls; monster_inspect.lua reads the monster and sends.
-- Tested by server/tests/monster_inspect_test.lua. Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
--   M.allowed(t, cfg)                          may this player inspect this creature (range, floor, view, monsters only)
--   M.allow(state, now, cfg)                   the request budget (token bucket with a cooldown)
--   M.parseXml(text)                           attacks, defences, summons, flags, armour and speed of a monster file
--   M.attackRows(xml, engine, mult, cfg, f)    {name, kind, element, chance, interval, min, max, range} (f: display scale)
--   M.abilityRows(xml, cfg)                    {kind, name, ...} heals, haste, summons, invisibility, field flags
--   M.resistRows(effective, mask, cond, cfg)   elements (percent, immune) and the conditions it is immune to
--   M.lootView(loot, itemInfo, stage, tier, cfg) the loot section by bestiary stage
--   M.build(info, cfg)                         the whole payload of the window
-- A text in the payload is an English key the client translates (the window's own tr()); the server sends no sentence.

ChaosMonsterInspect = ChaosMonsterInspect or {}
local M = ChaosMonsterInspect
local floor, max, min = math.floor, math.max, math.min

if not ChaosBestiaryCore then
	dofile("data/scripts/chaos/bestiary_core.lua")
end
local B = ChaosBestiaryCore

-- the codes of a refusal (the client maps each to its own text)
M.CODES = {notfound = true, range = true, rate = true, bad = true, hidden = true}

-- ---------------------------------------------------------------- who, how often
-- t = {isMonster, hidden, sameFloor, dx, dy, visible}; a display monster of the hunt teleport room (hidden) and a
-- creature that is no monster answer like a creature that is not there
function M.allowed(t, cfg)
	if type(t) ~= "table" or not t.isMonster or t.hidden then
		return false, "notfound"
	end
	if not t.sameFloor or not t.visible or math.abs(t.dx or 99) > cfg.rangeX or math.abs(t.dy or 99) > cfg.rangeY then
		return false, "range"
	end
	return true
end

-- request budget per player (token bucket, ms): state is kept per player by the caller
function M.allow(state, now, cfg)
	local size, rate = cfg.bucketSize, cfg.bucketPerSecond
	if state.at == nil then
		state.tokens, state.at, state.last = size, now, nil
	end
	if state.last and now >= state.last and now - state.last < cfg.cooldownMs then
		return false
	end
	if now > state.at then
		state.tokens = min(size, state.tokens + (now - state.at) * rate / 1000)
	end
	state.at = now
	if state.tokens < 1 then
		return false
	end
	state.tokens = state.tokens - 1
	state.last = now
	return true
end

-- the creature id of a request: a whole number above 0, else nil
function M.cleanCid(v)
	local n = tonumber(v)
	if not n or n ~= n or n < 1 or n > 4294967295 then
		return nil
	end
	return floor(n)
end

-- ---------------------------------------------------------------- the monster file
local function attributes(tag)
	local a = {}
	for k, v in tag:gmatch('([%w_]+)%s*=%s*"([^"]*)"') do
		a[k] = v
	end
	return a
end

-- every `<name .../>` or `<name ...>` opening tag of a section, as attribute tables
local function tagsOf(section, name)
	local list = {}
	if not section then
		return list
	end
	for tag in section:gmatch("<" .. name .. "%s([^>]*)>") do
		list[#list + 1] = attributes(tag)
	end
	return list
end

local function sectionOf(text, name)
	return text:match("<" .. name .. "[%s>](.-)</" .. name .. ">") or text:match("<" .. name .. "%s([^>]*)/>")
end

-- the maximum of a melee hit of an attack with `skill` and `attack` values (the engine's Weapons::getMaxMeleeDamage)
function M.meleeMax(skill, attack)
	skill, attack = tonumber(skill) or 0, tonumber(attack) or 0
	return math.ceil(skill * (attack * 0.05) + attack * 0.5)
end

-- text of a monster file -> {attacks, defences, summons, maxSummons, armor, defense, speed, flags}
function M.parseXml(text)
	local out = {attacks = {}, defences = {}, summons = {}, flags = {}}
	if type(text) ~= "string" or text == "" then
		return out
	end
	local head = text:match("<monster%s([^>]*)>")
	local h = head and attributes(head) or {}
	out.speed = tonumber(h.speed)
	local speedTag = text:match('<speed%s+value="(%-?%d+)"')
	out.speed = out.speed or tonumber(speedTag)
	for _, a in ipairs(tagsOf(sectionOf(text, "attacks"), "attack")) do
		out.attacks[#out.attacks + 1] = a
	end
	local defs = text:match("<defenses%s([^>]*)>")
	local da = defs and attributes(defs) or {}
	out.armor, out.defense = tonumber(da.armor), tonumber(da.defense)
	for _, d in ipairs(tagsOf(sectionOf(text, "defenses"), "defense")) do
		out.defences[#out.defences + 1] = d
	end
	local sm = text:match("<summons%s([^>]*)>")
	local sa = sm and attributes(sm) or {}
	out.maxSummons = tonumber(sa.maxSummons or sa.maxsummons)
	for _, s in ipairs(tagsOf(sectionOf(text, "summons"), "summon")) do
		out.summons[#out.summons + 1] = s
	end
	local flags = sectionOf(text, "flags")
	for _, f in ipairs(tagsOf(flags, "flag")) do
		for k, v in pairs(f) do
			out.flags[k:lower()] = v
		end
	end
	return out
end

-- ---------------------------------------------------------------- attacks and abilities
local function lower(s)
	return tostring(s or ""):lower()
end

-- the element an attack or a spell shows (cfg.attackElements by words of its name), nil when its name says none
function M.elementOf(name, cfg)
	local n = lower(name)
	for _, e in ipairs(cfg.attackElements) do
		if n:find(e[1], 1, true) then
			return e[2]
		end
	end
	return nil
end

local function scaled(v, f)
	if f and f ~= 1 then
		return floor(v * f + 0.5)
	end
	return v
end

local function span(a, b, mult, f)
	local lo, hi = math.abs(tonumber(a) or 0), math.abs(tonumber(b) or 0)
	if lo > hi then
		lo, hi = hi, lo
	end
	return scaled(floor(lo * mult + 0.5), f), scaled(floor(hi * mult + 0.5), f)
end

-- the attack rows. xml: M.parseXml's result (nil or empty: the engine list answers), engine: MonsterType:getAttackList()
-- rows {chance, isMelee, minCombatValue, maxCombatValue, range, speed}, mult: the damage multiplier of the monster's tier,
-- f: the viewer's display scale. kind: "melee" | "ranged" | "spell"
function M.attackRows(xml, engine, mult, cfg, f)
	mult = tonumber(mult) or 1
	local rows = {}
	for _, a in ipairs(xml and xml.attacks or {}) do
		local name = lower(a.name)
		local interval = tonumber(a.interval) or 2000
		local row = {name = name, interval = interval, chance = tonumber(a.chance) or (name == "melee" and 100 or nil)}
		local lo, hi
		if name == "melee" then
			row.kind = "melee"
			row.element = "physical"
			if tonumber(a.min) or tonumber(a.max) then
				lo, hi = span(a.min, a.max, mult, f)
			else
				lo, hi = scaled(0, f), scaled(floor(M.meleeMax(a.skill, a.attack) * mult + 0.5), f)
			end
			row.range = 1
		else
			row.kind = (name == "physical" or name == "fire" or name == "energy" or name == "earth" or name == "ice" or
				name == "holy" or name == "death" or name == "drown" or name == "lifedrain" or name == "manadrain") and "ranged" or "spell"
			if a.range and tonumber(a.range) and tonumber(a.range) <= 1 and row.kind == "ranged" then
				row.kind = "melee"
			end
			row.element = M.elementOf(name, cfg)
			row.range = tonumber(a.range) or tonumber(a.radius)
			if a.length then
				row.range = tonumber(a.length)
			end
			lo, hi = span(a.min, a.max, mult, f)
		end
		row.min, row.max = lo, hi
		rows[#rows + 1] = row
		if #rows >= cfg.maxAttacks then
			return rows
		end
	end
	if #rows == 0 then
		for _, a in ipairs(engine or {}) do
			local melee = a.isMelee == 1 or a.isMelee == true
			local lo, hi = span(a.minCombatValue, a.maxCombatValue, mult, f)
			rows[#rows + 1] = {name = melee and "melee" or "spell", kind = melee and "melee" or "spell",
				element = melee and "physical" or nil, chance = tonumber(a.chance), interval = tonumber(a.speed),
				min = lo, max = hi, range = melee and 1 or tonumber(a.range)}
			if #rows >= cfg.maxAttacks then
				break
			end
		end
	end
	return rows
end

-- the abilities: its defence spells (heals, haste, invisibility ...), summons, and the behaviour flags worth knowing
local FLAGS = {
	{"runonhealth", "runs"}, {"canpushitems", "pushes items"}, {"canpushcreatures", "pushes creatures"},
	{"hidehealth", "hides its health"}, {"illusionable", nil}, {"convinceable", nil}
}
function M.abilityRows(xml, cfg)
	local rows = {}
	for _, d in ipairs(xml and xml.defences or {}) do
		local name = lower(d.name)
		local row = {kind = "defence", name = name, chance = tonumber(d.chance), interval = tonumber(d.interval)}
		if name == "healing" then
			row.min, row.max = span(d.min, d.max, 1)
		elseif name == "speed" then
			row.value = tonumber(d.speedchange)
			row.seconds = tonumber(d.duration) and floor(tonumber(d.duration) / 1000) or nil
		elseif name == "invisible" or name == "outfit" or name == "drunk" then
			row.seconds = tonumber(d.duration) and floor(tonumber(d.duration) / 1000) or nil
		end
		rows[#rows + 1] = row
	end
	if #(xml and xml.summons or {}) > 0 then
		local names = {}
		for _, s in ipairs(xml.summons) do
			names[#names + 1] = tostring(s.name or "?")
		end
		rows[#rows + 1] = {kind = "summon", name = table.concat(names, ", "), count = xml.maxSummons, chance = tonumber(xml.summons[1].chance)}
	end
	local flags = xml and xml.flags or {}
	for _, f in ipairs(FLAGS) do
		local v = flags[f[1]]
		if f[2] and v and v ~= "0" then
			rows[#rows + 1] = {kind = "flag", name = f[2], value = f[1] == "runonhealth" and tonumber(v) or nil}
		end
	end
	while #rows > cfg.maxAbilities do
		rows[#rows] = nil
	end
	return rows
end

-- ---------------------------------------------------------------- resistances
local function hasBit(mask, bit)
	return floor((tonumber(mask) or 0) / bit) % 2 == 1
end

-- effective(ctype) -> the percent the monster takes less (negative: more) after the defence layer (O462);
-- mask: MonsterType:combatImmunities(); cond: MonsterType:conditionImmunities(); bits: {[constant name] = value}
function M.resistRows(effective, mask, cond, bits, cfg)
	local elements, immune = {}, {}
	for _, el in ipairs(B.ELEMENTS) do
		if hasBit(mask, el[1]) then
			immune[#immune + 1] = el[2]
		else
			local pct = tonumber(effective and effective(el[1])) or 0
			pct = pct >= 0 and floor(pct + 0.5) or -floor(-pct + 0.5)
			if pct ~= 0 then
				elements[#elements + 1] = {name = el[2], pct = pct}
			end
		end
	end
	local conditions = {}
	for _, c in ipairs(cfg.conditionImmunities) do
		local bit = bits and tonumber(bits[c[2]])
		if bit and bit > 0 and hasBit(cond, bit) then
			conditions[#conditions + 1] = c[1]
		end
	end
	return {elements = elements, immune = immune, conditions = conditions}
end

-- ---------------------------------------------------------------- armour
-- armor / defense: the monster file's flat values; layer: the share (percent) of a typical hit of the monster's level that
-- the armour layer of O462 removes (spell, weapon); class: "normal" | "elite" | "boss"
function M.armourView(flatArmor, flatDefense, class, spellPct, weaponPct)
	local function pct(v)
		return v and floor(v * 100 + 0.5) or nil
	end
	return {armor = tonumber(flatArmor), defense = tonumber(flatDefense), class = class, spell = pct(spellPct),
		weapon = pct(weaponPct)}
end

-- ---------------------------------------------------------------- experience
-- base: the monster's experience, mult: its tier's, rate: the viewer's experience stage, bonus: the percent the viewer's
-- completed bestiary entry gives, rank: the percent of the viewer's bestiary rank
function M.expView(base, mult, rate, bonus, rank)
	base = tonumber(base) or 0
	mult, rate = tonumber(mult) or 1, tonumber(rate) or 1
	local own = floor(base * mult + 0.5)
	return {base = floor(base), tier = mult ~= 1 and mult or nil, rate = rate ~= 1 and rate or nil, total = floor(own * rate),
		bonus = (tonumber(bonus) or 0) > 0 and tonumber(bonus) or nil, rank = (tonumber(rank) or 0) > 0 and tonumber(rank) or nil}
end

-- ---------------------------------------------------------------- loot
function M.bandOf(chance, cfg)
	for _, b in ipairs(cfg.lootBands) do
		if chance >= b.min then
			return b.key
		end
	end
	return cfg.lootBands[#cfg.lootBands].key
end

-- loot = MonsterType:getLoot() rows {itemId, chance (of 100000), maxCount}; itemInfo(id) -> name, clientId or nil.
-- stage: the player's bestiary stage for this monster. Below cfg.reveal.lootHighlights nothing is shown (locked = the
-- stage that opens it); from there the rarest rows, from cfg.reveal.lootFull the whole table by chance. bands counts
-- every row of the table by rarity band whatever is shown.
function M.lootView(loot, itemInfo, stage, tier, cfg)
	local list, bands = {}, {}
	for _, b in ipairs(cfg.lootBands) do
		bands[#bands + 1] = {key = b.key, n = 0}
	end
	for _, l in ipairs(loot or {}) do
		local id = tonumber(l.itemId)
		if id and id > 0 then
			local name, cid = itemInfo(id)
			if name and name ~= "" then
				local chance = (tonumber(l.chance) or 0) / 1000
				local band = M.bandOf(chance, cfg)
				for _, b in ipairs(bands) do
					if b.key == band then
						b.n = b.n + 1
					end
				end
				list[#list + 1] = {cid = cid or id, name = name, chance = chance, max = tonumber(l.maxCount) or 1, band = band}
			end
		end
	end
	local view = {total = #list, bands = bands, rows = {}, tierText = tier and cfg.lootTierText[tier] or nil}
	stage = tonumber(stage) or 0
	if stage < cfg.reveal.lootHighlights then
		view.locked = cfg.reveal.lootHighlights
		return view
	end
	local full = stage >= cfg.reveal.lootFull
	if full then
		table.sort(list, function(a, b)
			if a.chance ~= b.chance then
				return a.chance > b.chance
			end
			return a.name < b.name
		end)
	else
		table.sort(list, function(a, b)
			if a.chance ~= b.chance then
				return a.chance < b.chance
			end
			return a.name < b.name
		end)
		view.locked = cfg.reveal.lootFull
	end
	local limit = full and cfg.maxLoot or cfg.lootHighlights
	for i = 1, min(limit, #list) do
		view.rows[i] = list[i]
	end
	return view
end

-- the uniques and set pieces that name this monster (ChaosLoot.uniqueList entries), only from the full-loot stage
function M.uniqueRows(uniques, key, stage, cfg, cidOf)
	local out = {}
	if (tonumber(stage) or 0) < cfg.reveal.lootFull then
		return out
	end
	for _, u in ipairs(B.uniquesOf(uniques, key)) do
		local set
		for _, e in ipairs(uniques or {}) do
			if e.id == u.id then
				set = e.set
				break
			end
		end
		out[#out + 1] = {name = u.name, cid = cidOf and cidOf(u.id) or u.id, boss = u.bossOnly, set = set and true or nil}
		if #out >= cfg.maxUniques then
			break
		end
	end
	return out
end

-- where it lives (bestiary_spawns.lua areas {{x, y, z, n}}), from the stage that opens it
function M.areaRows(areas, towns, stage, cfg)
	if (tonumber(stage) or 0) < cfg.reveal.areas then
		return {}
	end
	return B.areaTexts(areas, towns, cfg.maxAreas)
end

-- ---------------------------------------------------------------- the payload
-- health: {cur, max, hidden}; the numbers are the viewer's display scale (the caller scales them), pct is exact
function M.healthView(cur, maxHealth, hidden)
	cur, maxHealth = tonumber(cur) or 0, tonumber(maxHealth) or 0
	local pct = maxHealth > 0 and max(0, min(100, floor(cur * 100 / maxHealth + 0.5))) or 0
	if hidden then
		return {pct = pct, hidden = true}
	end
	return {cur = floor(cur), max = floor(maxHealth), pct = pct}
end

-- the look of the monster: the outfit fields the window draws (no mount, no shader)
function M.outfitOf(o)
	o = type(o) == "table" and o or {}
	return {lookType = tonumber(o.lookType) or 0, lookTypeEx = tonumber(o.lookTypeEx) or nil, lookHead = tonumber(o.lookHead) or 0,
		lookBody = tonumber(o.lookBody) or 0, lookLegs = tonumber(o.lookLegs) or 0, lookFeet = tonumber(o.lookFeet) or 0,
		lookAddons = tonumber(o.lookAddons) or 0}
end

-- the modifier rows: {key, name, text}; text is the English sentence of cfg.modifiers (nil: none written)
function M.modRows(mods, cfg)
	local out = {}
	for _, m in ipairs(mods or {}) do
		out[#out + 1] = {key = m.key, name = m.name, text = cfg.modifiers[m.key]}
		if #out >= cfg.maxMods then
			break
		end
	end
	return out
end

-- info (the engine file fills it): cid, name, level, tier, tierLabel, role, boss, elite, summon, health, family {race, cat,
-- diff}, mods, exp, resist, armour, attacks, abilities, speed {base, now}, loot, uniques, areas, bestiary {kills, stage, th,
-- next}. Loot, uniques and areas arrive from lootView / uniqueRows / areaRows already cut by the bestiary stage.
function M.build(info, cfg)
	local flags = {}
	if info.tierLabel then
		flags[#flags + 1] = {key = "tier", name = info.tierLabel}
	end
	if info.elite then
		flags[#flags + 1] = {key = "elite"}
	end
	if info.boss then
		flags[#flags + 1] = {key = "boss"}
	end
	if info.role then
		flags[#flags + 1] = {key = info.role}
	end
	if info.summon then
		flags[#flags + 1] = {key = "summon"}
	end
	local p = {
		cid = info.cid, name = info.name, level = info.level, tier = info.tier, flags = flags, health = info.health,
		family = info.family, mods = info.mods or {}, exp = info.exp, resist = info.resist, armour = info.armour,
		attacks = info.attacks or {}, abilities = info.abilities or {}, speed = info.speed, loot = info.loot,
		uniques = info.uniques or {}, areas = info.areas or {}, bestiary = info.bestiary, outfit = M.outfitOf(info.outfit)
	}
	return p
end

return M
