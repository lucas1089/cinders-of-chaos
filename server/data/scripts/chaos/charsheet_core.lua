-- The character sheet, the pure part (ChaosCharSheet; tests: server/tests/charsheet_test.lua and inspect_test.lua).
-- One sheet of numbers built once from what charsheet.lua read off a character, shown in two places:
--   * Inspect Player (inspect.lua, client game_playerinspect): K.clean(raw) is the `combat` block of the result packet
--     (public by owner decision 2026-11-06, O423: attack, hit, highest hit, speeds, crit, leech, damage bonus, defence,
--     armour, damage reduction, resistances, maximum health and mana, movement speed)
--   * Info & Services > Character Info (commands_ui.lua command `sheet`): K.text(sheet, character, tx) is the text of the
--     sections [ Offense ], [ Defense ], [ Resistances ] and, for the own character, [ Character ]
-- Nothing here calls the engine. Lua 5.1 / LuaJIT and 5.3.

ChaosCharSheet = ChaosCharSheet or {}
local K = ChaosCharSheet

-- the damage and resistance types shown, in this order: key -> name
K.TYPES = {physical = "Physical", fire = "Fire", energy = "Energy", earth = "Earth", ice = "Ice", holy = "Holy", death = "Death",
	water = "Water", arcane = "Arcane", drown = "Drowning", lifedrain = "Life drain", manadrain = "Mana drain",
	cold = "Cold", lightning = "Lightning", chaos = "Chaos"}
K.ORDER = {"physical", "fire", "cold", "lightning", "chaos", "energy", "earth", "ice", "holy", "death", "water", "arcane", "drown",
	"lifedrain", "manadrain"}

-- raw = what charsheet.lua read: attack, hit, maxHit, attackSpeed (percent), critChance, critAmount (percent),
-- lifeLeech / manaLeech = {chance, amount}, damage = [{k, pct}] (damage bonus per type), defense, armor, mitigation (share
-- 0 .. 1; O464: the physical total against a typical hit), resist = [{k, pct}] (per element, may be negative; O464: the four
-- groups fire, cold, lightning, chaos, each with sum and penalty), defence = {armourShare, reduction, dodge, block, suppress,
-- penalty, cap} (O464, percent), maxHealth, maxMana, moveSpeed.
-- Numbers only (one decimal), type keys plain words, no zero offence rows; nil when nothing is left. A new table.
function K.clean(raw)
	raw = type(raw) == "table" and raw or {}
	local function n(v, lo, hi)
		v = tonumber(v)
		if not v or v ~= v or v == math.huge or v == -math.huge then
			return nil
		end
		return math.floor(math.max(lo or 0, math.min(hi or 1e9, v)) * 10 + 0.5) / 10
	end
	local function pos(v, hi)
		local x = n(v, 0, hi)
		return x and x > 0 and x or nil
	end
	local function pair(t)
		t = type(t) == "table" and t or {}
		local c, a = pos(t.chance, 100), pos(t.amount, 10000)
		if c or a then
			return {chance = c or 0, amount = a or 0}
		end
	end
	local function list(t, lo)
		local out = {}
		for _, row in ipairs(type(t) == "table" and t or {}) do
			local k = type(row) == "table" and type(row.k) == "string" and row.k:match("^%a+$") or nil
			local v = n(row.pct, lo, 1000)
			if k and v and v ~= 0 and #out < 12 then
				local r = {k = k, pct = v}
				if row.sum ~= nil then
					r.sum, r.penalty = n(row.sum, -1000, 1000) or 0, n(row.penalty, 0, 1000) or 0
				end
				out[#out + 1] = r
			end
		end
		return #out > 0 and out or nil
	end
	local out = {
		attack = pos(raw.attack), hit = pos(raw.hit), maxHit = pos(raw.maxHit), attackSpeed = pos(raw.attackSpeed, 100),
		critChance = pos(raw.critChance, 100), critAmount = pos(raw.critAmount, 10000),
		critChanceRaw = pos(raw.critChanceRaw, 1000), critAmountRaw = pos(raw.critAmountRaw, 100000), lifeLeech = pair(raw.lifeLeech),
		manaLeech = pair(raw.manaLeech), damage = list(raw.damage, 0), defense = pos(raw.defense), armor = pos(raw.armor),
		mitigation = raw.mitigation and pos(tonumber(raw.mitigation) * 100, 100) or nil, resist = list(raw.resist, -1000),
		maxHealth = pos(raw.maxHealth), maxMana = pos(raw.maxMana), moveSpeed = pos(raw.moveSpeed)
	}
	if type(raw.defence) == "table" then
		local d = raw.defence
		out.defence = {armourShare = n(d.armourShare, 0, 100) or 0, reduction = n(d.reduction, -100, 1000) or 0,
			dodge = n(d.dodge, 0, 100) or 0, block = n(d.block, 0, 100) or 0, suppress = n(d.suppress, 0, 100) or 0,
			penalty = n(d.penalty, 0, 1000) or 0, cap = n(d.cap, 0, 1000) or 75}
	end
	if next(out) == nil then
		return nil
	end
	return out
end

function K.number(v)
	v = math.floor((tonumber(v) or 0) + 0.5)
	local s = tostring(math.abs(v)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return (v < 0 and "-" or "") .. s
end

local function pct(v)
	v = tonumber(v) or 0
	if v == math.floor(v) then
		return string.format("%d", v)
	end
	return string.format("%.1f", v)
end
K.percent = pct

local function typeName(tx, key)
	return tx(K.TYPES[key] or key)
end

-- one "[ Title ]" block: title and lines, nothing when there are no lines
local function block(tx, title, lines)
	if #lines == 0 then
		return nil
	end
	return "[ " .. tx(title) .. " ]\n" .. table.concat(lines, "\n")
end

local function byType(list)
	local map = {}
	for _, row in ipairs(list or {}) do
		map[row.k] = row.pct
	end
	return map
end

-- the text of the sheet in sections. sheet = K.clean(raw); character = nil (Inspect never shows it) or the own
-- character's rows {level, vocation, health, maxHealth, mana, maxMana, capacity, speed, expToNext, expPercent,
-- skills = [{name, level, percent}], magic = {level, percent}, soul, stamina (minutes)}; tx(format, ...) translates and
-- formats. Returns the text, sections joined by an empty line ("" when there is nothing).
function K.text(sheet, character, tx)
	sheet = sheet or {}
	tx = tx or function(f, ...) return select("#", ...) > 0 and string.format(f, ...) or f end
	local parts = {}
	local off = {}
	if sheet.attack then
		off[#off + 1] = tx("Weapon attack: %s", K.number(sheet.attack))
	end
	if sheet.hit then
		off[#off + 1] = tx("Average hit: %s", K.number(sheet.hit))
	end
	if sheet.maxHit then
		off[#off + 1] = tx("Highest hit: %s", K.number(sheet.maxHit))
	end
	if sheet.attackSpeed then
		off[#off + 1] = tx("Attack speed: +%s%%", pct(sheet.attackSpeed))
	end
	-- O471: the caps (chance 45, damage 150, ChaosItemMods.config.crit): a total that was cut says so, with what the sources give
	if sheet.critChance then
		if sheet.critChanceRaw and sheet.critChanceRaw > sheet.critChance then
			off[#off + 1] = tx("Critical chance: %s%% (cap; your sources give %s%%)", pct(sheet.critChance), pct(sheet.critChanceRaw))
		else
			off[#off + 1] = tx("Critical chance: %s%%", pct(sheet.critChance))
		end
	end
	if sheet.critAmount then
		if sheet.critAmountRaw and sheet.critAmountRaw > sheet.critAmount then
			off[#off + 1] = tx("Critical damage: +%s%% (cap; your sources give +%s%%)", pct(sheet.critAmount), pct(sheet.critAmountRaw))
		else
			off[#off + 1] = tx("Critical damage: +%s%%", pct(sheet.critAmount))
		end
	end
	if sheet.lifeLeech then
		off[#off + 1] = tx("Life leech: %s%% chance, %s%% of the hit", pct(sheet.lifeLeech.chance), pct(sheet.lifeLeech.amount))
	end
	if sheet.manaLeech then
		off[#off + 1] = tx("Mana leech: %s%% chance, %s%% of the hit", pct(sheet.manaLeech.chance), pct(sheet.manaLeech.amount))
	end
	local dmg = byType(sheet.damage)
	for _, key in ipairs(K.ORDER) do
		if dmg[key] then
			off[#off + 1] = tx("%s damage: +%s%%", typeName(tx, key), pct(dmg[key]))
		end
	end
	parts[#parts + 1] = block(tx, "Offense", off)

	local def = {}
	if sheet.defense then
		def[#def + 1] = tx("Defense: %s", K.number(sheet.defense))
	end
	if sheet.armor then
		def[#def + 1] = tx("Armor: %s", K.number(sheet.armor))
	end
	if sheet.mitigation then
		def[#def + 1] = tx("Physical damage taken from monsters: -%s%%", pct(sheet.mitigation))
	end
	if sheet.defence then
		local d = sheet.defence
		def[#def + 1] = tx("Armor share against a typical hit: %s%%", pct(d.armourShare))
		def[#def + 1] = tx("Physical reduction: %s%%", pct(d.reduction))
		def[#def + 1] = tx("Dodge: %s%%", pct(d.dodge))
		def[#def + 1] = tx("Block: %s%%", pct(d.block))
		def[#def + 1] = tx("Spell suppression: %s%%", pct(d.suppress))
	end
	if sheet.maxHealth then
		def[#def + 1] = tx("Maximum health: %s", K.number(sheet.maxHealth))
	end
	if sheet.maxMana then
		def[#def + 1] = tx("Maximum mana: %s", K.number(sheet.maxMana))
	end
	if sheet.moveSpeed then
		def[#def + 1] = tx("Movement speed: %s", K.number(sheet.moveSpeed))
	end
	parts[#parts + 1] = block(tx, "Defense", def)

	local res = {}
	local rmap = byType(sheet.resist)
	local rows = {}
	for _, row in ipairs(sheet.resist or {}) do
		rows[row.k] = row
	end
	for _, key in ipairs(K.ORDER) do
		if rmap[key] then
			local row = rows[key]
			if row and row.sum ~= nil then
				-- O464: the sum of the sources, the penalty of the level, the result (at most the cap)
				res[#res + 1] = tx("%s: %s%% (sources %s%%, level penalty -%s%%)", typeName(tx, key), pct(rmap[key]), pct(row.sum),
					pct(row.penalty))
			else
				res[#res + 1] = tx("%s: %s%%", typeName(tx, key), pct(rmap[key]))
			end
		end
	end
	if sheet.defence and (sheet.defence.cap or 75) ~= 75 then
		res[#res + 1] = tx("Maximum resistance: %s%%", pct(sheet.defence.cap))
	end
	parts[#parts + 1] = block(tx, "Resistances", res)

	if character then
		local c = {}
		local function add(...)
			c[#c + 1] = tx(...)
		end
		if character.level then
			add("Level: %s", K.number(character.level))
		end
		if character.vocation and character.vocation ~= "" then
			add("Class: %s", character.vocation)
		end
		if character.health and character.maxHealth then
			add("Health: %s / %s", K.number(character.health), K.number(character.maxHealth))
		end
		if character.mana and character.maxMana then
			add("Mana: %s / %s", K.number(character.mana), K.number(character.maxMana))
		end
		if character.capacity then
			add("Capacity: %s", K.number(character.capacity))
		end
		if character.speed then
			add("Speed: %s", K.number(character.speed))
		end
		if character.expToNext then
			add("Experience to next level: %s (%s%% done)", K.number(character.expToNext), pct(character.expPercent or 0))
		end
		if type(character.magic) == "table" and character.magic.level then
			add("Magic level: %s (%s%%)", K.number(character.magic.level), pct(character.magic.percent or 0))
		end
		for _, s in ipairs(type(character.skills) == "table" and character.skills or {}) do
			if type(s.name) == "string" and tonumber(s.level) then
				add("%s: %s (%s%%)", tx(s.name), K.number(s.level), pct(s.percent or 0))
			end
		end
		if character.soul then
			add("Soul: %s", K.number(character.soul))
		end
		if character.stamina then
			local m = math.floor(character.stamina)
			add("Stamina: %dh %02dmin", math.floor(m / 60), m % 60)
		end
		parts[#parts + 1] = block(tx, "Character", c)
	end
	local out = {}
	for _, p in ipairs(parts) do
		if p then
			out[#out + 1] = p
		end
	end
	return table.concat(out, "\n\n")
end

return K
