-- Run from the server/ folder: luajit tests/stock_spells_patch_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- The stock utility spells of the Thief, Monk and Templar lines: tools/add_vocations.py converts the vocation lists of a
-- condensed stock spells.xml (convert_file, patch_spells_necro, patch_spells_lines, as main() does) and the client's
-- spelldata.lua (client/tools/gen_spell_data.py, ChaosStockSpellLines) lists the same class ids.
local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end
local function eq(a, b, what)
	ok(a == b, (what or "check") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

local function instant(name, words, script, group, vocs)
	local out = {string.format('\t<instant group="%s" name="%s" words="%s" lvl="8" mana="20" script="%s">',
		group, name, words, script)}
	for _, v in ipairs(vocs) do
		out[#out + 1] = string.format('\t\t<vocation name="%s" />', v)
	end
	out[#out + 1] = "\t</instant>"
	return table.concat(out, "\n")
end
local ALL = {"Sorcerer", "Druid", "Paladin", "Knight", "Master Sorcerer", "Elder Druid", "Royal Paladin", "Elite Knight"}
local MAGE = {"Sorcerer", "Druid", "Master Sorcerer", "Elder Druid"}
local STOCK = table.concat({
	'<?xml version="1.0" encoding="UTF-8"?>',
	"<spells>",
	instant("Light", "utevo lux", "support/light.lua", "support", ALL),
	instant("Great Light", "utevo gran lux", "support/great_light.lua", "support", ALL),
	instant("Haste", "utani hur", "support/haste.lua", "support", ALL),
	instant("Strong Haste", "utani gran hur", "support/strong_haste.lua", "support", MAGE),
	instant("Find Person", "exiva", "support/find_person.lua", "support", ALL),
	instant("Levitate", "exani hur", "support/levitate.lua", "support", ALL),
	instant("Magic Rope", "exani tera", "support/magic_rope.lua", "support", ALL),
	instant("Cure Poison", "exana pox", "healing/cure_poison.lua", "healing", ALL),
	instant("Cure Bleeding", "exana kor", "healing/cure_bleeding.lua", "healing", {"Druid", "Knight", "Elder Druid", "Elite Knight"}),
	instant("Cure Curse", "exana mort", "healing/cure_curse.lua", "healing", {"Paladin", "Royal Paladin"}),
	instant("Food", "exevo pan", "support/food.lua", "support", {"Druid", "Elder Druid"}),
	instant("Energy Strike", "exori vis", "attack/energy_strike.lua", "attack", MAGE),
	"\t<!-- BEGIN chaos spells -->",
	instant("Chaos Light", "vael x", "support/light.lua", "support", {"Warrior"}),
	"\t<!-- END chaos spells -->",
	"</spells>",
	""
}, "\n")

-- ---------------------------------------------------------------- the tool
local python = io.popen and io.popen("python3 -V 2>/dev/null")
local hasPython = python and (python:read("*a") or ""):find("Python 3")
if python then
	python:close()
end
if not hasPython then
	print("stock_spells_patch_test: python3 not found, skipped")
	return
end

local function runPatch(text)
	local path = os.tmpname()
	local f = assert(io.open(path, "wb"))
	f:write(text)
	f:close()
	local cmd = "python3 -I -c \"import sys; sys.path.insert(0, 'tools'); import add_vocations as a; "
		.. "t = a.read(sys.argv[1]); t, n = a.convert_file(t, 'spells', {}); t, nn = a.patch_spells_necro(t); "
		.. "t, nl = a.patch_spells_lines(t); a.write(sys.argv[1], t); print(nl)\" " .. path
	local h = assert(io.popen(cmd))
	local count = tonumber((h:read("*a") or ""):match("%d+"))
	h:close()
	f = assert(io.open(path, "rb"))
	local out = f:read("*a")
	f:close()
	os.remove(path)
	return out, count
end

local patched, n = runPatch(STOCK)
eq(n, 10, "stock utility spells patched")
local again, n2 = runPatch(patched)
eq(n2, 0, "second run: nothing to do")
eq(again, patched, "second run changes nothing")

local function vocationsOf(xml, name)
	local body = xml:match('<instant[^>]-name="' .. name:gsub("%p", "%%%0") .. '"[^>]*>(.-)</instant>')
	local set = {}
	for v in (body or ""):gmatch('<vocation name="([^"]+)"') do
		set[v] = true
	end
	return set, body
end
local function hasLine(set, line)
	local n = 0
	for _, v in ipairs(line) do
		n = n + (set[v] and 1 or 0)
	end
	return n == #line
end
local THIEF, MONK, TEMPLAR = {"Thief", "Ninja", "Samurai"}, {"Monk", "Shadowfist", "Iron Sage"}, {"Templar", "Inquisitor", "Sentinel"}
local expect = {
	["Light"] = {true, true, true}, ["Great Light"] = {true, true, true}, ["Haste"] = {true, true, true},
	["Find Person"] = {true, true, true}, ["Levitate"] = {true, true, true}, ["Magic Rope"] = {true, true, true},
	["Cure Poison"] = {true, true, true}, ["Strong Haste"] = {true, true, false}, ["Cure Bleeding"] = {false, true, true},
	["Cure Curse"] = {false, false, true}, ["Food"] = {false, false, false}, ["Energy Strike"] = {false, false, false},
	["Chaos Light"] = {false, false, false}
}
for name, e in pairs(expect) do
	local set = vocationsOf(patched, name)
	eq(hasLine(set, THIEF), e[1], name .. ": Thief line")
	eq(hasLine(set, MONK), e[2], name .. ": Monk line")
	eq(hasLine(set, TEMPLAR), e[3], name .. ": Templar line")
end
local _, body = vocationsOf(patched, "Haste")
ok(body:find('<vocation name="Thief" />', 1, true) and body:find('<vocation name="Ninja" showInDescription="0" />', 1, true),
	"base class shown, ascended classes hidden in descriptions")
ok(vocationsOf(patched, "Haste")["Warrior"] and vocationsOf(patched, "Haste")["Necromancer"], "the converted lists are kept")

-- ---------------------------------------------------------------- the client's table
local f = io.open("../client/overlay/modules/game_chaosspells/spelldata.lua", "rb")
if f then
	local env = {}
	local chunk = assert((loadstring or load)(f:read("*a"), "spelldata.lua", "t", env))
	f:close()
	if setfenv then
		setfenv(chunk, env)
	end
	chunk()
	local lines = env.ChaosStockSpellLines
	ok(type(lines) == "table", "spelldata.lua has ChaosStockSpellLines")
	local function ids(words)
		local set = {}
		for _, v in ipairs(lines and lines[words] or {}) do
			set[v] = true
		end
		return set
	end
	local light, strong, curse = ids("vael lyss"), ids("ruan gal ul"), ids("puir nyx")
	ok(light[11] and light[13] and light[17] and light[19] and light[23] and light[25], "client: Lantern for the three lines")
	ok(strong[11] and strong[17] and not strong[23], "client: Galeborne Stride for the Thief and Monk lines only")
	ok(curse[23] and not curse[11] and not curse[17], "client: Lift Hex for the Templar line only")
end

print(string.format("stock_spells_patch_test: %d checks, %d failures", checks, fails))
if fails > 0 then
	os.exit(1)
end
