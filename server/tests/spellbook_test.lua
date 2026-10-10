-- Run from the server/ folder: lua5.3 tests/spellbook_test.lua (mock engine API; CI runs it with luajit and lua5.3)
-- Fixtures: tests/fixtures/spellbook/spells.xml and scripts/ (small fake spells.xml and spell scripts).

-- area tables the server's spell library defines globally
AREA_WAVE4 = {
	{1, 1, 1, 1, 1},
	{0, 1, 1, 1, 0},
	{0, 1, 1, 1, 0},
	{0, 0, 3, 0, 0}
}
AREA_SQUARE1X1 = {
	{1, 1, 1},
	{1, 3, 1},
	{1, 1, 1}
}
AREA_CIRCLE3X3 = {
	{0, 0, 1, 1, 1, 0, 0},
	{0, 1, 1, 1, 1, 1, 0},
	{1, 1, 1, 1, 1, 1, 1},
	{1, 1, 1, 3, 1, 1, 1},
	{1, 1, 1, 1, 1, 1, 1},
	{0, 1, 1, 1, 1, 1, 0},
	{0, 0, 1, 1, 1, 0, 0}
}
MESSAGE_STATUS_CONSOLE_BLUE = 4

local registry, talks = {}, {}
function CreatureEvent(name) local o = {}; function o:register() registry[name] = o end; function o:type() end; return o end
function TalkAction(words) local o = {}; function o:separator() end; function o:register() talks[words] = o end; return o end
local VOCATIONS = {[0] = "None", "Sorcerer", "Druid", "Paladin", "Knight", "Master Sorcerer", "Elder Druid", "Royal Paladin", "Elite Knight"}
Vocation = setmetatable({}, {__call = function(_, id)
	if VOCATIONS[id] then return {getName = function() return VOCATIONS[id] end, getId = function() return id end} end
end})
ItemType = setmetatable({}, {__call = function(_, id)
	return {getName = function() return id == 2304 and "searing orb rune" or "item" .. id end, getClientId = function() return id + 1000 end}
end})

-- minimal JSON encoder (sorted keys, enough for sizes and round trips in this test)
local function encode(v)
	local t = type(v)
	if t == "table" then
		if #v > 0 or next(v) == nil then
			local parts = {}
			for i = 1, #v do parts[i] = encode(v[i]) end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		local keys = {}
		for k in pairs(v) do keys[#keys + 1] = k end
		table.sort(keys)
		local parts = {}
		for _, k in ipairs(keys) do parts[#parts + 1] = encode(tostring(k)) .. ":" .. encode(v[k]) end
		return "{" .. table.concat(parts, ",") .. "}"
	elseif t == "string" then
		return '"' .. v:gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end) .. '"'
	elseif t == "number" or t == "boolean" then
		return tostring(v)
	end
	return "null"
end
json = {encode = encode}

ChaosSpellbook = {spellsXml = "tests/fixtures/spellbook/spells.xml", scriptsDir = "tests/fixtures/spellbook/scripts/"}
dofile("data/scripts/chaos/chaos_constants.lua")
local sent = {}
Chaos.send = function(_, opcode, action, data) sent[#sent + 1] = {opcode = opcode, action = action, data = data} end
Chaos.decode = function(b) return b end
dofile("data/scripts/chaos/spellbook.lua")
local B = ChaosSpellbook

local function eq(a, b, m) if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end end
local function sameMatrix(a, b, m)
	eq(type(a), "table", m)
	eq(#a, #b, m .. " rows")
	for r = 1, #b do
		eq(#a[r], #b[r], m .. " width")
		for c = 1, #b[r] do eq(a[r][c], b[r][c], m .. " cell " .. r .. "," .. c) end
	end
end

eq(ChaosOpcodes.spellbook, 219, "opcode")
-- AREA_CIRCLE3X3 exists, so the list was parsed at load
assert(B.spells, "parsed at load")

-- ---------------------------------------------------------------- XML parsing
local f = io.open(B.spellsXml); local xml = f:read("*a"); f:close()
local entries = B.parseXml(xml)
local names = {}
for _, e in ipairs(entries) do names[#names + 1] = e.attrs.name end
eq(#entries, 14, "entries (the commented-out one is skipped)")
eq(entries[1].tag, "instant", "tag")
eq(entries[1].attrs.words, "exevo flam hur", "words attr")
eq(entries[1].attrs.direction, "1", "direction attr")
eq(#entries[1].vocations, 2, "vocations of entry 1")
eq(entries[1].vocations[2], "Master Sorcerer", "vocation name")
local rune
for _, e in ipairs(entries) do if e.tag == "rune" then rune = e end end
eq(rune.attrs.id, "2304", "rune item id")
eq(rune.attrs.magiclevel, "4", "rune magic level")
eq(#rune.vocations, 0, "self-closing rune has no vocations")
-- the self-closing rune must not swallow the next entry
eq(entries[11].attrs.name, "Frost Bloom", "entry after the rune")

local player, skipped = 0, {}
for _, e in ipairs(entries) do
	if B.isPlayerSpell(e) then player = player + 1 else skipped[e.attrs.name] = true end
end
eq(player, 12, "player spells")
assert(skipped["Monster Breath"] and skipped["House Kick"], "monster and house spells skipped")

-- ---------------------------------------------------------------- areas
sameMatrix(B.findArea("combat:setArea(createCombatArea(AREA_WAVE4))"), AREA_WAVE4, "named area")
sameMatrix(B.findArea("x = createCombatArea( {{0, 1, 0}, {1, 3, 1}} )"), {{0, 1, 0}, {1, 3, 1}}, "inline area")
sameMatrix(B.findArea("local a = createCombatArea(AREA_SQUARE1X1)\nlocal b = createCombatArea(AREA_CIRCLE3X3)"), AREA_CIRCLE3X3, "largest of two")
eq(B.findArea("createCombatArea({{1, os.exit(1), 1}})"), nil, "code in an inline table is refused")
eq(B.findArea("createCombatArea(AREA_DOES_NOT_EXIST)"), nil, "unknown name")
eq(B.findArea("createCombatArea({{1, 7, 1}})"), nil, "cell values above 3 refused")
eq(B.findArea("createCombatArea({{1, 1}, {1}})"), nil, "ragged rows refused")
eq(B.findArea("no area here"), nil, "no area")

-- ---------------------------------------------------------------- built spells
local byName = {}
for _, s in ipairs(B.spells) do byName[s.name .. (s.rune and " (rune)" or "")] = s end
eq(#B.spells, 12, "spells built")
for i = 2, #B.spells do assert(B.spells[i - 1].level <= B.spells[i].level, "sorted by level") end

local wave = byName["Ember Fan"]
eq(wave.type, "damage", "wave type"); eq(wave.element, "fire", "wave element")
eq(wave.target, "front", "wave target"); eq(wave.center, "caster", "wave center")
sameMatrix(wave.area, AREA_WAVE4, "wave area")
eq(wave.description, "Fire damage in front of you (wave).", "wave description")
eq(wave.scaling, "magic level", "wave scaling")
eq(wave.cooldown, 4000, "cooldown ms"); eq(wave.groupCooldown, 2000, "group cooldown")
eq(wave.vocations[1], 1, "sorcerer id"); eq(wave.vocations[2], 5, "master sorcerer id")
eq(wave.premium, false, "premium 0")

local strike = byName["Ember Lash"]
eq(strike.target, "single", "strike target"); eq(strike.area, nil, "no area for single target")
eq(strike.element, "fire", "commented element ignored")
eq(strike.description, "Single-target fire damage.", "stock header not used")
eq(strike.premium, true, "premium 1"); eq(strike.range, 3, "range")

local ring = byName["Bone Ring"]
sameMatrix(ring.area, AREA_SQUARE1X1, "inline area spell")
eq(ring.target, "area", "self area target"); eq(ring.center, "caster", "self area center")
eq(ring.description, "Physical damage around you.", "around you")
eq(ring.scaling, "skill x weapon attack", "skill scaling")

local twin = byName["Twin Burst"]
sameMatrix(twin.area, AREA_CIRCLE3X3, "largest area picked")
eq(twin.element, "earth", "element from doAreaCombat")

local cross = byName["Cross Shot"]
sameMatrix(cross.area, {{0, 1, 0}, {1, 3, 1}, {0, 1, 0}}, "local table area")
eq(cross.center, "target", "needtarget area is centred on the target")
eq(cross.description, "Area holy damage at the target.", "target area description")
eq(cross.scaling, "distance skill x weapon attack", "distance scaling")

local trap = byName["Trap Area"]
eq(trap.area, nil, "unsafe inline area dropped"); eq(trap.target, "self", "falls back to self")

local heal = byName["Minor Mending"]
eq(heal.type, "heal", "heal type"); eq(heal.element, "healing", "heal element"); eq(heal.target, "self", "heal target")
eq(heal.description, "Heals you and cures paralysis.", "heal description")

local haste = byName["Fleetfoot"]
eq(haste.type, "buff", "buff type"); eq(haste.description, "Increases your speed.", "haste description")

local conj = byName["Searing Orb Rune"]
eq(conj.type, "conjure", "conjure type"); eq(conj.soul, 3, "soul")
eq(conj.description, "Conjures 4 x 'searing orb rune'.", "conjure description")

local orb = byName["Searing Orb Rune (rune)"]
eq(orb.rune, 2304, "rune id"); eq(orb.runeClientId, 3304, "rune client id")
eq(orb.maglevel, 4, "rune magic level"); eq(orb.target, "area", "rune area"); eq(orb.center, "target", "rune centre")
eq(#orb.vocations, 0, "rune without vocations")

local chaos = byName["Frost Bloom"]
eq(chaos.description, "Ice burst around the caster, chills everything it hits.", "chaos description joins comment lines")
eq(#chaos.vocations, 1, "unknown vocation names are dropped")
eq(chaos.scaling, "magic level", "mlValues scaling")

local none = byName["No Script"]
eq(none.target, "single", "no script: needtarget -> single"); eq(none.type, "utility", "no script type")

-- ---------------------------------------------------------------- description of the analysed pieces
local info = B.analyzeScript("-- Name Here: does a thing\nlocal x = 1\n")
eq(info.description, "Does a thing", "header description")
eq(B.analyzeScript("").description, nil, "empty script")

-- ---------------------------------------------------------------- chunking
local items = {}
for i = 1, 50 do items[i] = {name = "spell" .. i, description = string.rep("x", 100)} end
local chunks = B.chunk(items, 1000, encode)
local count = 0
for _, c in ipairs(chunks) do
	assert(#encode(c) <= 1000, "chunk within budget: " .. #encode(c))
	count = count + #c
end
eq(count, 50, "every item in a chunk")
assert(#chunks > 5, "split into several chunks")
eq(#B.chunk({{name = string.rep("y", 5000)}}, 1000, encode), 1, "an oversized item still goes alone")
eq(#B.chunk({}, 1000, encode), 0, "empty list")

-- ---------------------------------------------------------------- protocol
local p = {id = 7, msgs = {}}
function p:getId() return self.id end
function p:getLevel() return 120 end
function p:getMagicLevel() return 60 end
function p:getVocation() return Vocation(5) end
function p:getGroup() return {getAccess = function() return false end} end
function p:sendCancelMessage(t) self.cancel = t end
function p:sendTextMessage(_, t) self.msgs[#self.msgs + 1] = t end

B.chunkBytes = 1500 -- force several packets
-- chunks go out one per tick: run the scheduled sends right away, in order
function addEvent(fn, delay, ...) fn(...) end
function Player(id) return id == p.id and p or nil end
assert(talks["/spells"] and not talks["!spells"], "only the staff talkaction (players: the menu)")
eq(talks["/spells"].onSay(p, "/spells", ""), false, "players: said as chat, nothing sent")
eq(#sent, 0, "nothing sent to a player")
local gmGroup = p.getGroup
function p:getGroup() return {getAccess = function() return true end} end
eq(talks["/spells"].onSay(p, "/spells", ""), false, "talkaction returns false")
p.getGroup = gmGroup
eq(sent[1].action, "open", "open first"); eq(sent[1].opcode, 219, "opcode on the wire")
eq(sent[1].data.vocation, 5, "player vocation"); eq(sent[1].data.level, 120, "level"); eq(sent[1].data.magicLevel, 60, "magic level")
eq(sent[1].data.total, 12, "total")
eq(sent[1].data.vocationNames[6].id, 5, "vocation list id"); eq(sent[1].data.vocationNames[6].name, "Master Sorcerer", "vocation list name")
local got = 0
for i = 2, #sent - 1 do
	eq(sent[i].action, "spells", "chunk action"); eq(sent[i].data.index, i - 1, "chunk index")
	got = got + #sent[i].data.spells
	assert(#encode({action = "spells", data = sent[i].data}) < 2500, "packet size")
end
eq(got, 12, "all spells sent"); eq(sent[1].data.chunks, #sent - 2, "chunk count announced")
assert(#sent - 2 > 1, "more than one chunk")
eq(sent[#sent].action, "done", "done last")

-- a second open right away is throttled; the opcode path reaches the same sender
local before = #sent
p.getGroup = function() return {getAccess = function() return true end} end
talks["/spells"].onSay(p, "/spells", "")
p.getGroup = gmGroup
eq(#sent, before, "throttled"); assert(p.cancel, "throttle message")
registry["ChaosSpellbookLogout"].onLogout(p)
registry["ChaosSpellbookExtended"].onExtendedOpcode(p, 219, {action = "open"})
assert(#sent > before, "open over the opcode after the throttle reset")
local n = #sent
registry["ChaosSpellbookExtended"].onExtendedOpcode(p, 218, {action = "open"})
eq(#sent, n, "other opcodes ignored")

-- reload is staff only
local gm = {id = 8, msgs = {}}
for k, v in pairs(p) do if type(v) == "function" then gm[k] = v end end
function gm:getGroup() return {getAccess = function() return true end} end
talks["/spells"].onSay(gm, "/spells", "reload")
assert(gm.msgs[1] and gm.msgs[1]:find("12 spells"), "reload message")

-- control characters from script files (CR, tabs, NUL) never reach the client
assert(ChaosSpellbook.clean("Heals\r\nyou\0 and\tfriends") == "Heals you and friends", "clean control characters")
assert(ChaosSpellbook.clean({a = {"x\0y"}}).a[1] == "x y", "clean nested")
-- the class helpers deal the damage: their element and kind come from the helper call (Monk, Templar, Necromancer)
local monk = B.analyzeScript("dofile('data/spells/scripts/chaos/_monk.lua')\nfunction onCastSpell(c, v)\n\tMonkSpell.strike(p, t, f, 1)\nend\n")
eq(monk.damage[1], "physical", "Monk strike: physical")
eq(monk.scaling, "fist skill x fist attack (or a staff)", "Monk strike: scaling")
eq(B.analyzeScript("TemplarSpell.holyStrike(player, target, min, max)\n").damage[1], "holy", "Templar strike: holy")
eq(B.analyzeScript("NecroSpell.curse(player, classKey, target)\n").damage[1], "death", "Necromancer curse: death")
eq(B.analyzeScript("local m = L.raise(player, kind, pos)\n").summon, true, "Necromancer minions: a summon")
print("spellbook: all asserts passed")
