-- Spellbook (client module game_spellbook, extended opcode ChaosOpcodes.spellbook = 219, JSON).
--
-- `!spells` (or `/spells`) opens a window on the client that lists every player spell of the server with its
-- data, a short description and its area of effect. The list is read from the running server's own files:
--   data/spells/spells.xml           <instant>/<rune>/<conjure> entries (monster and house spells are skipped)
--   data/spells/scripts/<script>     text-parsed for element, area (createCombatArea), kind and scaling
-- Parsing happens once (at startup when the spell library is already loaded, otherwise on first use) and is
-- cached; `/spells reload` (gamemasters) parses again. Nothing here runs a spell script: it only reads them.
--
-- server -> client (one JSON message per packet; the list is split so a packet stays under ~7 KB):
--   {"action":"open",   "data":{vocation, level, magicLevel, total, chunks, vocationNames:[{id, name}, ...]}}
--   {"action":"spells", "data":{index, spells:[spell, ...]}}       x chunks
--   {"action":"done",   "data":{total}}
--   spell = {name, words, level, maglevel, mana, manaPercent, soul, cooldown (ms), groupCooldown (ms), group,
--            type ("damage"|"heal"|"buff"|"summon"|"conjure"|"utility"), element, target
--            ("single"|"area"|"self"|"front"), center ("caster"|"target"), area (matrix: 1 hit, 2 centre,
--            3 centre + hit; "front" spells face north), range, description, scaling, vocations [ids], premium,
--            rune (server item id), runeClientId}
-- client -> server:
--   {"action":"open"}   (window opened from the menu: same answer as !spells)

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end

local OPCODE = ChaosOpcodes.spellbook

ChaosSpellbook = ChaosSpellbook or {}
local Book = ChaosSpellbook

Book.spellsXml = Book.spellsXml or "data/spells/spells.xml"
Book.scriptsDir = Book.scriptsDir or "data/spells/scripts/"
Book.chunkBytes = Book.chunkBytes or 6500 -- JSON bytes of spells per packet (the packet limit is far higher)
Book.chunkDelay = Book.chunkDelay or 50 -- ms between chunk packets
Book.maxAreaSize = 21
Book.openCooldown = 2 -- seconds between two full sends to the same player

-- ------------------------------------------------------------------ small helpers
local function readFile(path)
	local ok, f = pcall(io.open, path, "r")
	if not ok or not f then
		return nil
	end
	local content = f:read("*a")
	f:close()
	return content
end

local ENTITIES = {amp = "&", lt = "<", gt = ">", quot = "\"", apos = "'"}

local function unescape(s)
	return (s:gsub("&(%a+);", function(e)
		return ENTITIES[e] or ("&" .. e .. ";")
	end))
end

local function truthy(v)
	if v == nil then
		return false
	end
	v = tostring(v):lower()
	return v == "1" or v == "true" or v == "yes"
end

local function num(v)
	return tonumber(v or "")
end

local function capitalize(s)
	return (s:gsub("^%l", string.upper))
end

-- Loads a table literal made only of digits, commas, braces and whitespace, in an empty environment.
local function loadMatrixLiteral(src)
	if type(src) ~= "string" or #src > 4000 or not src:match("^[%d%s,;{}]+$") then
		return nil
	end
	local chunk
	if setfenv and loadstring then
		chunk = loadstring("return " .. src)
		if chunk then
			setfenv(chunk, {})
		end
	else
		chunk = load("return " .. src, "area", "t", {})
	end
	if not chunk then
		return nil
	end
	local ok, value = pcall(chunk)
	if ok then
		return value
	end
	return nil
end

-- A valid area: array of rows, all the same width, cells 0..3, at most maxAreaSize x maxAreaSize.
local function normalizeMatrix(m)
	if type(m) ~= "table" or #m == 0 or #m > Book.maxAreaSize then
		return nil
	end
	local width = nil
	local out = {}
	for r = 1, #m do
		local row = m[r]
		if type(row) ~= "table" or #row == 0 or #row > Book.maxAreaSize then
			return nil
		end
		width = width or #row
		if #row ~= width then
			return nil
		end
		local copy = {}
		for c = 1, #row do
			local v = row[c]
			if type(v) ~= "number" or v < 0 or v > 3 or v ~= math.floor(v) then
				return nil
			end
			copy[c] = v
		end
		out[r] = copy
	end
	return out
end
Book.normalizeMatrix = normalizeMatrix

local function areaWeight(m)
	local n = 0
	for _, row in ipairs(m) do
		for _, v in ipairs(row) do
			if v == 1 or v == 3 then
				n = n + 1
			end
		end
	end
	return n
end
Book.areaWeight = areaWeight

-- substring of the balanced {...} that starts at `start` (which must point at "{")
local function balancedBraces(text, start)
	local depth = 0
	for i = start, math.min(#text, start + 4000) do
		local ch = text:sub(i, i)
		if ch == "{" then
			depth = depth + 1
		elseif ch == "}" then
			depth = depth - 1
			if depth == 0 then
				return text:sub(start, i)
			end
		end
	end
	return nil
end

-- ------------------------------------------------------------------ spells.xml
-- Returns an array of entries {tag, attrs = {lowercased name = value}, vocations = {names}} for the player spells.
function Book.parseXml(text)
	local list = {}
	if type(text) ~= "string" then
		return list
	end
	text = text:gsub("<!%-%-.-%-%->", "")
	local pos = 1
	while true do
		local s, e, tag, attrText, selfClose = text:find("<(%a+)(%s[^>]-)(/?)>", pos)
		if not s then
			break
		end
		pos = e + 1
		tag = tag:lower()
		if tag == "instant" or tag == "rune" or tag == "conjure" then
			local attrs = {}
			for k, v in attrText:gmatch("([%w_]+)%s*=%s*\"([^\"]*)\"") do
				attrs[k:lower()] = unescape(v)
			end
			for k, v in attrText:gmatch("([%w_]+)%s*=%s*'([^']*)'") do
				attrs[k:lower()] = unescape(v)
			end
			local vocations = {}
			if selfClose == "" then
				local closeS, closeE = text:find("</" .. tag .. "%s*>", pos)
				if closeS then
					local body = text:sub(pos, closeS - 1)
					for name in body:gmatch("<vocation[^>]-name%s*=%s*\"([^\"]*)\"") do
						vocations[#vocations + 1] = unescape(name)
					end
					pos = closeE + 1
				end
			end
			list[#list + 1] = {tag = tag, attrs = attrs, vocations = vocations}
		end
	end
	return list
end

-- monster spells (#words), house spells and entries without a name are not player spells
function Book.isPlayerSpell(entry)
	local a = entry.attrs
	if not a.name or a.name == "" then
		return false
	end
	if a.words and a.words:sub(1, 1) == "#" then
		return false
	end
	local script = (a.script or ""):lower()
	if script:find("^house/") or script:find("^monster/") then
		return false
	end
	return true
end

-- ------------------------------------------------------------------ spell scripts
local ELEMENTS = {
	PHYSICALDAMAGE = "physical", ENERGYDAMAGE = "energy", EARTHDAMAGE = "earth", FIREDAMAGE = "fire",
	ICEDAMAGE = "ice", HOLYDAMAGE = "holy", DEATHDAMAGE = "death", DROWNDAMAGE = "drown",
	LIFEDRAIN = "lifedrain", MANADRAIN = "manadrain", HEALING = "healing"
}

-- spell helpers that deal damage of an element without a COMBAT_ token in the spell script (pattern, element)
Book.HELPER_DAMAGE = {
	{"MonkSpell%.strike%s*%(", "physical"},
	{"TemplarSpell%.holyStrike%s*%(", "holy"},
	{"NecroSpell%.curse%s*%(", "death"}
}

local function elementOf(token)
	local e = ELEMENTS[token]
	if e then
		return e
	end
	local base = token:match("^(%u+)DAMAGE$")
	if base and base ~= "UNDEFINED" then
		return base:lower()
	end
	return nil
end

local function stripComments(src)
	src = src:gsub("%-%-%[(=*)%[.-%]%1%]", "")
	src = src:gsub("%-%-[^\n]*", "")
	return src
end

-- area matrix from one createCombatArea(...) argument
local function resolveArea(src, argStart)
	local rest = src:sub(argStart)
	local lead = rest:match("^%s*()")
	local first = rest:sub(lead, lead)
	if first == "{" then
		local literal = balancedBraces(rest, lead)
		return literal and normalizeMatrix(loadMatrixLiteral(literal))
	end
	local name = rest:match("^%s*([%a_][%w_]*)")
	if not name then
		return nil
	end
	local value = rawget(_G, name)
	if type(value) == "table" then
		return normalizeMatrix(value)
	end
	-- a local defined in the same script: `local arr = { ... }`
	local defStart = src:find("[^%w_]" .. name .. "%s*=%s*{")
	if defStart then
		local brace = src:find("{", defStart, true)
		local literal = brace and balancedBraces(src, brace)
		return literal and normalizeMatrix(loadMatrixLiteral(literal))
	end
	return nil
end

-- {area, areaNamed (bool)} for the largest createCombatArea() in the script
function Book.findArea(src)
	local best, bestWeight = nil, -1
	local pos = 1
	while true do
		local s, e = src:find("createCombatArea%s*%(", pos)
		if not s then
			break
		end
		pos = e + 1
		local ok, m = pcall(resolveArea, src, e + 1)
		if ok and m then
			local w = areaWeight(m)
			if w > bestWeight then
				best, bestWeight = m, w
			end
		end
	end
	return best
end

-- what a granted condition does (first one found in the script wins)
local CONDITION_TEXT = {
	HASTE = "Increases your speed.",
	INVISIBLE = "Makes you invisible.",
	MANASHIELD = "Damage drains your mana before your health.",
	LIGHT = "Creates light around you.",
	PARALYZE = "Slows the target down.",
	REGENERATION = "Regenerates health and mana over time.",
	ATTRIBUTES = "Temporarily raises your skills.",
	PACIFIED = "Prevents the target from attacking."
}

-- names of the conditions a spell can remove
local CURE_NAME = {
	POISON = "poison", FIRE = "burning", ENERGY = "electrification", PARALYZE = "paralysis", CURSED = "curse",
	BLEEDING = "bleeding", DROWN = "drowning", FREEZING = "freezing", DAZZLED = "dazzle", INVISIBLE = "invisibility"
}

-- Everything the script text tells about the spell. Never throws (callers pcall anyway).
function Book.analyzeScript(src)
	local info = {elements = {}}
	if type(src) ~= "string" or src == "" then
		return info
	end
	-- Chaos spells: "-- <Name>: <description>" on the first line, continued by further comment lines
	local firstLine = src:match("^%s*%-%-([^\n]*)")
	if firstLine then
		local name, desc = firstLine:match("^%s*([^:]+):%s*(.+)$")
		if name and desc then
			local lines = {desc}
			local following = src:match("^%s*%-%-[^\n]*\n(.*)$") or ""
			for line in following:gmatch("([^\n]*)\n?") do
				if lines[#lines]:match("[%.!]%s*$") or #lines >= 3 then
					break
				end
				local more = line:match("^%s*%-%-%s*(.+)$")
				if not more or more:match("^%a+%.lua") then
					break
				end
				lines[#lines + 1] = more
			end
			info.header = name:match("^%s*(.-)%s*$")
			info.description = capitalize((table.concat(lines, " "):gsub("%s+$", "")))
		end
	end

	local code = stripComments(src)
	local seen = {}
	for token in code:gmatch("COMBAT_([%u_]+)") do
		local e = elementOf(token)
		if e and not seen[e] then
			seen[e] = true
			info.elements[#info.elements + 1] = e
		end
	end
	-- the class helpers that deal the damage themselves (no COMBAT_ token in the spell's own script)
	for _, h in ipairs(Book.HELPER_DAMAGE) do
		if code:find(h[1]) and not seen[h[2]] then
			seen[h[2]] = true
			info.elements[#info.elements + 1] = h[2]
		end
	end
	-- damage elements, the one set as COMBAT_PARAM_TYPE first
	info.damage = {}
	local primary = code:match("COMBAT_PARAM_TYPE%s*,%s*COMBAT_([%u_]+)")
	primary = primary and elementOf(primary)
	if primary and primary ~= "healing" then
		info.damage[1] = primary
	end
	for _, e in ipairs(info.elements) do
		if e ~= "healing" and e ~= primary then
			info.damage[#info.damage + 1] = e
		end
	end
	info.heals = seen.healing or code:find("healTarget%s*%(") ~= nil or code:find(":addHealth%s*%(") ~= nil

	info.area = Book.findArea(code)

	local itemId, count = code:match("conjureItem%s*%(%s*%d+%s*,%s*(%d+)%s*,?%s*(%d*)")
	if itemId then
		info.conjureItem = tonumber(itemId)
		info.conjureCount = tonumber(count) or 1
	end
	info.summon = code:find("createMonster%s*%(") ~= nil or code:find("summonCreature") ~= nil
		or code:find("addSummon%s*%(") ~= nil or code:find("[%w_]+%.raise%s*%(") ~= nil -- the Necromancer's minions

	if code:find("MonkSpell%.strike%s*%(") or code:find("MonkSpell%.values%s*%(") then
		info.scaling = "fist skill x fist attack (or a staff)"
	elseif code:find("TemplarSpell%.values%s*%(") then
		info.scaling = "skill x weapon attack, magic level"
	elseif code:find("[%w_]+%.values%s*%(%s*player%s*,") and code:find("_necro%.lua") then
		info.scaling = "magic level"
	elseif code:find("distanceAttack") then
		info.scaling = "distance skill x weapon attack"
	elseif code:find("CALLBACK_PARAM_SKILLVALUE") or code:find("skillValues%s*%(") then
		info.scaling = "skill x weapon attack"
	elseif code:find("CALLBACK_PARAM_LEVELMAGICVALUE") or code:find("mlValues%s*%(") then
		info.scaling = "magic level"
	end

	-- conditions the spell gives (Condition(...)) and conditions it removes (dispel / removeCondition)
	info.grants, info.cures = {}, {}
	local granted, cured = {}, {}
	for cond in code:gmatch("Condition%s*%(%s*CONDITION_([%u_]+)") do
		if not granted[cond] then
			granted[cond] = true
			info.grants[#info.grants + 1] = cond
		end
	end
	for cond in code:gmatch("createConditionObject%s*%(%s*CONDITION_([%u_]+)") do
		if not granted[cond] then
			granted[cond] = true
			info.grants[#info.grants + 1] = cond
		end
	end
	local function addCure(cond)
		if CURE_NAME[cond] and not cured[cond] then
			cured[cond] = true
			info.cures[#info.cures + 1] = CURE_NAME[cond]
		end
	end
	for cond in code:gmatch("COMBAT_PARAM_DISPEL%s*,%s*CONDITION_([%u_]+)") do
		addCure(cond)
	end
	for cond in code:gmatch("removeCondition%s*%(%s*CONDITION_([%u_]+)") do
		addCure(cond)
	end
	info.dispels = #info.cures > 0
	info.hasCondition = #info.grants > 0
	info.createsField = code:find("COMBAT_PARAM_CREATEITEM", 1, true) ~= nil
	return info
end

-- ------------------------------------------------------------------ classification and description
local ELEMENT_WORD = {lifedrain = "life drain", manadrain = "mana drain"}

local function elementWord(e)
	return ELEMENT_WORD[e] or e
end

local function joinList(list, max)
	local words = {}
	for i = 1, math.min(max or 2, #list) do
		words[i] = list[i]
	end
	if #words <= 1 then
		return words[1] or ""
	end
	local last = table.remove(words)
	return table.concat(words, ", ") .. " and " .. last
end

-- type, target, center for a parsed entry + script info
function Book.classify(entry, info)
	local a = entry.attrs
	local script = (a.script or ""):lower()
	local needTarget = truthy(a.needtarget)
	local isRune = entry.tag == "rune"

	local kind
	if entry.tag == "conjure" or script:find("^conjuring/") or info.conjureItem then
		kind = "conjure"
	elseif info.summon or script:find("summon") then
		kind = "summon"
	elseif #info.damage > 0 then
		kind = "damage"
	elseif info.heals then
		kind = "heal"
	elseif info.hasCondition or info.dispels or a.group == "support" then
		kind = "buff"
	else
		kind = "utility"
	end

	local target, center
	if info.area then
		if truthy(a.direction) or (truthy(a.castertargetordirection) and not needTarget) then
			target, center = "front", "caster"
		elseif needTarget or (isRune and not truthy(a.selftarget)) then
			target, center = "area", "target"
		else
			target, center = "area", "caster"
		end
	elseif needTarget or truthy(a.castertargetordirection) or (isRune and not truthy(a.selftarget)) then
		target = "single"
	else
		target = "self"
	end
	if kind == "conjure" or kind == "summon" then
		target, center = "self", nil
	end
	return kind, target, center
end

local function areaShape(area)
	return (#area[1] == 1) and "beam" or "wave"
end

-- short generated description of a stock spell
function Book.describe(spell, info, conjureName)
	local kind, target = spell.type, spell.target
	local el = info.damage and info.damage[1] and elementWord(info.damage[1])
	if kind == "conjure" then
		if conjureName and conjureName ~= "" then
			local count = info.conjureCount or 1
			if count > 1 then
				return string.format("Conjures %d x '%s'.", count, conjureName)
			end
			return string.format("Conjures '%s'.", conjureName)
		end
		return "Conjures an item."
	elseif kind == "summon" then
		return "Summons a creature to fight for you."
	end
	if info.createsField then
		local what = el and (el .. " field") or "magic barrier"
		if spell.area and #spell.area > 1 and #spell.area[1] > 1 then
			return "Creates " .. what .. "s around the target."
		elseif spell.area then
			return "Creates a wall of " .. what .. "s."
		end
		return "Creates " .. (what:find("^[aeiou]") and "an " or "a ") .. what .. " on the target tile."
	end
	if kind == "damage" then
		if target == "single" then
			return string.format("Single-target %s damage.", el)
		elseif target == "front" then
			return capitalize(string.format("%s damage in front of you (%s).", el, areaShape(spell.area)))
		elseif target == "area" and spell.center == "caster" then
			return capitalize(string.format("%s damage around you.", el))
		elseif target == "area" then
			return string.format("Area %s damage at the target.", el)
		end
		return capitalize(string.format("%s damage.", el))
	elseif kind == "heal" then
		local text
		if target == "single" then
			text = "Heals the target"
		elseif target == "area" or target == "front" then
			text = "Heals you and allies around you"
		else
			text = "Heals you"
		end
		if #(info.cures or {}) > 0 then
			text = text .. " and cures " .. joinList(info.cures)
		end
		return text .. "."
	elseif kind == "buff" or kind == "utility" then
		for _, cond in ipairs(info.grants or {}) do
			if CONDITION_TEXT[cond] and not (cond == "PARALYZE" and target == "self") then
				return CONDITION_TEXT[cond]
			end
		end
		if #(info.cures or {}) > 0 then
			if info.cures[1] == "invisibility" then
				return "Reveals invisible creatures around you."
			end
			return "Cures " .. joinList(info.cures) .. "."
		end
		return kind == "buff" and "Support spell." or "Utility spell."
	end
	return "Utility spell."
end

-- ------------------------------------------------------------------ building the list
local vocationIds -- lowercased name -> id

local function loadVocations()
	local map = {}
	Book.vocationList = {}
	if Vocation == nil then
		return map
	end
	-- the ids of data/XML/vocations.xml when it can be read (Vocation(id) of a missing id, like the retired 2, 6 and 9
	-- of the class rework, prints an engine warning), else a scan
	local ids
	local f = io and io.open and io.open("data/XML/vocations.xml", "r")
	if f then
		local text = f:read("*a") or ""
		f:close()
		ids = {}
		for tag in text:gsub("<!%-%-.-%-%->", ""):gmatch("<vocation%s[^>]*>") do
			local id = tonumber(tag:match('%sid="(%d+)"'))
			if id then
				ids[#ids + 1] = id
			end
		end
		table.sort(ids)
		if #ids == 0 then
			ids = nil
		end
	end
	if not ids then
		ids = {}
		for id = 0, 30 do -- the class ids go up to 25 (Templar line)
			ids[#ids + 1] = id
		end
	end
	local misses = 0
	for _, id in ipairs(ids) do
		local ok, voc = pcall(Vocation, id)
		if ok and voc then
			misses = 0
			local okName, name = pcall(function()
				return voc:getName()
			end)
			if okName and type(name) == "string" and name ~= "" then
				map[name:lower()] = id
				Book.vocationList[#Book.vocationList + 1] = {id = id, name = name}
			end
		elseif id > 0 then
			misses = misses + 1
			if misses >= 2 then
				break
			end
		end
	end
	return map
end

local function itemName(id)
	if not id or ItemType == nil then
		return nil
	end
	local ok, name = pcall(function()
		return ItemType(id):getName()
	end)
	if ok and type(name) == "string" and name ~= "" then
		return name
	end
	return nil
end

local function itemClientId(id)
	if not id or ItemType == nil then
		return nil
	end
	local ok, cid = pcall(function()
		return ItemType(id):getClientId()
	end)
	if ok and tonumber(cid) and cid > 0 then
		return cid
	end
	return nil
end

-- One client spell from an XML entry; `scriptCache` maps script path -> analyzeScript result.
function Book.buildSpell(entry, scriptCache)
	local a = entry.attrs
	local info
	local script = a.script
	if script and script ~= "" then
		info = scriptCache and scriptCache[script]
		if not info then
			local ok, result = pcall(function()
				return Book.analyzeScript(readFile(Book.scriptsDir .. script) or "")
			end)
			info = ok and result or {elements = {}, damage = {}}
			if scriptCache then
				scriptCache[script] = info
			end
		end
	else
		info = {elements = {}, damage = {}}
	end
	info.damage = info.damage or {}
	info.elements = info.elements or {}

	local spell = {
		name = a.name,
		words = a.words,
		level = num(a.level) or num(a.lvl) or 0,
		maglevel = num(a.magiclevel) or num(a.maglevel) or num(a.maglv) or 0,
		mana = num(a.mana) or 0,
		manaPercent = num(a.manapercent),
		soul = num(a.soul) or 0,
		cooldown = num(a.cooldown) or num(a.exhaustion) or 0,
		groupCooldown = num(a.groupcooldown),
		group = a.group or (entry.tag == "rune" and "attack" or nil),
		range = num(a.range),
		premium = truthy(a.premium),
		scaling = info.scaling
	}
	local kind, target, center = Book.classify(entry, info)
	spell.type, spell.target, spell.center = kind, target, center
	if info.area and (target == "area" or target == "front") then
		spell.area = info.area
	end
	if kind == "heal" then
		spell.element = "healing"
	else
		spell.element = info.damage[1]
	end
	if entry.tag == "rune" then
		spell.rune = num(a.id)
		spell.runeClientId = itemClientId(spell.rune)
	end

	local isChaos = (script or ""):lower():find("^chaos/") ~= nil
	if isChaos and info.description then
		spell.description = info.description
	else
		spell.description = Book.describe(spell, info, itemName(info.conjureItem))
	end

	vocationIds = vocationIds or loadVocations()
	local ids, seen = {}, {}
	for _, name in ipairs(entry.vocations) do
		local id = vocationIds[name:lower()]
		if id and not seen[id] then
			seen[id] = true
			ids[#ids + 1] = id
		end
	end
	table.sort(ids)
	spell.vocations = ids
	return spell
end

local function sortSpells(a, b)
	if a.level ~= b.level then
		return a.level < b.level
	end
	if a.name ~= b.name then
		return a.name < b.name
	end
	return (a.words or "") < (b.words or "")
end

-- Parses everything; returns the spell list (also cached in Book.spells).
function Book.load()
	vocationIds = loadVocations()
	local list = {}
	local ok, err = pcall(function()
		local entries = Book.parseXml(readFile(Book.spellsXml))
		local cache = {}
		for _, entry in ipairs(entries) do
			if Book.isPlayerSpell(entry) then
				local okSpell, spell = pcall(Book.buildSpell, entry, cache)
				if okSpell and spell then
					list[#list + 1] = spell
				end
			end
		end
		table.sort(list, sortSpells)
	end)
	if not ok then
		print("[Chaos spellbook] " .. tostring(err))
	end
	Book.spells = list
	return list
end

function Book.get()
	if not Book.spells or #Book.spells == 0 then
		Book.load()
	end
	return Book.spells
end

-- Splits `list` into arrays whose encoded size stays under `budget` bytes (one spell per chunk at least).
function Book.chunk(list, budget, encode)
	local chunks, current, size = {}, {}, 2
	for _, item in ipairs(list) do
		local len = #encode(item) + 1
		if #current > 0 and size + len > budget then
			chunks[#chunks + 1] = current
			current, size = {}, 2
		end
		current[#current + 1] = item
		size = size + len
	end
	if #current > 0 then
		chunks[#chunks + 1] = current
	end
	return chunks
end

-- ------------------------------------------------------------------ protocol
-- Text read from script files can carry control characters (CR from CRLF files, tabs, even NUL bytes). They break
-- the client's JSON parser, and a NUL cuts the extended opcode string short so the rest of the packet is misread.
local function clean(value)
	if type(value) == "string" then
		return (value:gsub("%c", " "):gsub("  +", " "))
	elseif type(value) == "table" then
		local out = {}
		for k, v in pairs(value) do
			out[k] = clean(v)
		end
		return out
	end
	return value
end
Book.clean = clean

local lastOpen = {}

function Book.sendTo(player)
	local now = os.time()
	local pid = player:getId()
	if lastOpen[pid] and now - lastOpen[pid] < Book.openCooldown then
		return false
	end
	lastOpen[pid] = now

	local list = clean(Book.get())
	if ChaosDisplayScale and ChaosDisplayScale.apply then -- the viewer's display scale: flat mana costs
		list = ChaosDisplayScale.apply("spellList", player, list)
	end
	local chunks = Book.chunk(list, Book.chunkBytes, json.encode)
	local vocation = player:getVocation()
	Chaos.send(player, OPCODE, "open", {
		vocation = vocation and vocation:getId() or 0,
		level = player:getLevel(),
		magicLevel = player:getMagicLevel(),
		total = #list,
		chunks = #chunks,
		vocationNames = Book.vocationList or {}
	})
	-- one chunk per server tick: sent together they end up in a single ~80 KB packet, which the client misreads
	for i, chunk in ipairs(chunks) do
		addEvent(function()
			local p = Player(pid)
			if p then
				Chaos.send(p, OPCODE, "spells", {index = i, spells = chunk})
			end
		end, i * Book.chunkDelay)
	end
	addEvent(function()
		local p = Player(pid)
		if p then
			Chaos.send(p, OPCODE, "done", {total = #list})
		end
	end, (#chunks + 1) * Book.chunkDelay)
	return true
end

-- parse at startup when the spell library (AREA_* tables) is already loaded; otherwise on first use
if rawget(_G, "AREA_CIRCLE3X3") and not Book.spells then
	Book.load()
end

local LoginEvent = CreatureEvent("ChaosSpellbookLogin")

function LoginEvent.onLogin(player)
	player:registerEvent("ChaosSpellbookExtended")
	return true
end

local LogoutEvent = CreatureEvent("ChaosSpellbookLogout")

function LogoutEvent.onLogout(player)
	lastOpen[player:getId()] = nil
	return true
end

local ExtendedEvent = CreatureEvent("ChaosSpellbookExtended")

function ExtendedEvent.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if msg and msg.action == "open" then
		Book.sendTo(player)
	end
end

LoginEvent:type("login")
LoginEvent:register()
LogoutEvent:type("logout")
LogoutEvent:register()
ExtendedEvent:type("extendedopcode")
ExtendedEvent:register()

local function onSpellsCommand(player, words, param)
	if param and param:lower():find("reload") and player:getGroup():getAccess() then
		local list = Book.load()
		player:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, string.format("Spellbook: %d spells parsed.", #list))
		return false
	end
	if not Book.sendTo(player) then
		player:sendCancelMessage("The spellbook is already opening.")
	end
	return false
end

-- staff only (players open the window from the menu)
local talk = TalkAction("/spells")
function talk.onSay(player, words, param)
	if not player:getGroup():getAccess() then
		return false -- players open it from the menu
	end
	return onSpellsCommand(player, words, param)
end
talk:separator(" ")
talk:register()
