-- Run from the server/ folder: luajit tests/pack36_fx_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- Pair 36 effects (data/lib/chaos_pack36_fx.lua): the switch is one plain line; every swap names a spell of
-- spells_chaos.xml (by id and name) whose script sends the swapped name and that pair 27 has no swap for; every new
-- name is in the client specs (art_import/pack36_*.csv) and in the ids file; the ids file lists every appended spec row
-- (and no replaced one) with ids in order after pair 35; off, nothing is swapped; on, the pair 36 names; _common.lua
-- is wired.
local failures = 0
local function ok(c, msg)
	if not c then
		failures = failures + 1
		print("FAIL " .. msg)
	end
end
local function eq(a, b, msg)
	ok(a == b, msg .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")")
end
local function readFile(p)
	local f = io.open(p, "r")
	if not f then return nil end
	local s = f:read("*a")
	f:close()
	return s
end

dofile("data/lib/chaos_pack27_fx.lua")
dofile("data/lib/chaos_pack36_fx.lua")
local C = ChaosPack36Fx

local src = readFile("data/lib/chaos_pack36_fx.lua") or ""
eq(src:match("\nC%.PAIR36_FX = (%a+)\n"), "true", "the switch is one plain line, on")

-- the client specs, in import order (the groups of gen_pack36_fx.py)
local groups = {"replace", "missiles", "tile", "field", "area", "cone", "mega", "impact", "circle", "aura", "trap",
	"ui", "beam"}
local spec, order, replaced = {}, {effect = {}, missile = {}}, 0
for _, g in ipairs(groups) do
	local text = readFile("../client/tools/sprites/art_import/pack36_" .. g .. ".csv")
	ok(text ~= nil, "spec pack36_" .. g .. ".csv")
	local first = true
	for line in (text or ""):gmatch("[^\n]+") do
		if first then
			first = false
		else
			local a, b, c = line:match("^([^,]*),([^,]*),([^,]*),")
			local kind, name = a, b
			if g == "replace" then
				kind, name = b, c
				replaced = replaced + 1
				ok(tonumber(a) ~= nil, name .. ": a replaced id")
			else
				order[kind][#order[kind] + 1] = name
			end
			spec[kind .. ":" .. name] = true
		end
	end
end
ok(replaced > 150, "the replaced ids are in the spec (" .. replaced .. ")")
local dirs = {"n", "ne", "e", "se", "s", "sw", "w", "nw"}

-- the ids file: every appended row, in spec order, effects from 855 and missiles from 189 (pair 35: 854 / 188)
local ids = readFile("data/lib/chaos_pack36_fx_ids.lua") or ""
local got = {effect = {}, missile = {}}
for kind, name, id in ids:gmatch("\n(ChaosVfx%a*)%.([%w_]+) = {id = (%d+)") do
	local k = kind == "ChaosVfxMissile" and "missile" or "effect"
	got[k][#got[k] + 1] = {name = name, id = tonumber(id)}
end
for _, k in ipairs({"effect", "missile"}) do
	eq(#got[k], #order[k], "the ids file lists every appended " .. k)
	local base = k == "effect" and 854 or 188
	for i, name in ipairs(order[k]) do
		local e = got[k][i]
		if not e or e.name ~= name or e.id ~= base + i then
			ok(false, k .. " " .. name .. " is id " .. (base + i) .. " in the ids file")
			break
		end
	end
end
ok(#order.missile == 0 or 188 + #order.missile <= 255, "missiles stay uint8")
ok(not ids:find("ChaosVfx.rep_", 1, true), "the replaced ids get no Lua name")

-- the spells
local xml = readFile("data/spells/chaos/spells_chaos.xml") or ""
local n = 0
for id, kinds in pairs(C.spells) do
	n = n + 1
	local name = C.names[id]
	ok(name ~= nil, "spell " .. id .. " has a name")
	ok(ChaosPack27Fx.spells[id] == nil, "spell " .. id .. " has no pair 27 swap")
	local script = xml:match('spellid="' .. id .. '" name="' .. (name or "?") .. '"[^>]-script="([^"]+)"')
	ok(script ~= nil, "spells_chaos.xml has spell " .. id .. " named " .. tostring(name))
	local body = script and readFile("data/spells/" .. script) or ""
	for kind, swaps in pairs(kinds) do
		ok(kind == "fx" or kind == "missile" or kind == "dir" or kind == "fxdir", id .. ": kind " .. kind)
		for from, to in pairs(swaps) do
			ok(body:find('"' .. from .. '"', 1, true) ~= nil, tostring(name) .. " sends " .. from)
			if kind == "dir" or kind == "fxdir" then
				for _, d in ipairs(dirs) do
					ok(spec["effect:" .. to .. "_" .. d], to .. "_" .. d .. " in the client spec")
				end
			else
				ok(spec[(kind == "missile" and "missile:" or "effect:") .. to], to .. " in the client spec")
			end
			eq(C.pick(id, kind, from), to, "pick " .. id .. " " .. from)
		end
	end
end
eq(n, 42, "the spells with pair 36 effects")
for id in pairs(C.names) do
	ok(C.spells[id] ~= nil, "name " .. id .. " has swaps")
end

-- off: nothing; on: the names (the ids file loaded once)
eq(C.pick(214, "fx", "holy_hit"), "w_impact_holy_strike", "pick")
eq(C.pick(214, "fx", "nothing"), nil, "no pick")
C.PAIR36_FX = false
C.loaded = nil
eq(C.swapFor(214, "fx", "holy_hit"), nil, "off: no swap")
ChaosVfx, ChaosVfxMissile = nil, nil
C.PAIR36_FX = true
C.loaded = nil
ChaosVfx, ChaosVfxMissile = {}, {}
eq(C.live(), true, "on: the ids file loads")
eq(C.swapFor(214, "fx", "holy_hit"), "w_impact_holy_strike", "on: the pair 36 name")
eq(C.swapFor(244, "dir", "sword_slash"), "cone_steel_crescent", "on: a directional base")
eq(C.swapFor(214, "missile", "holy_hit"), nil, "a kind without a swap")

-- _common.lua asks it inside the pair 27 lookup
local common = readFile("data/spells/chaos/_common.lua") or ""
ok(common:find("data/lib/chaos_pack36_fx.lua", 1, true) ~= nil, "_common.lua loads the module")
ok(common:find("local p36 = pack36(kind, name)", 1, true) ~= nil, "_common.lua asks it in pack27()")

if failures > 0 then
	print(failures .. " failure(s)")
	os.exit(1)
end
print("pack36_fx_test: OK")
