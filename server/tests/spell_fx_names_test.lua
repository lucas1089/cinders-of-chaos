-- Run from the server/ folder: luajit tests/spell_fx_names_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- Every effect name a spell or script under data/ asks ChaosFx for exists in data/lib/chaos_fx.lua (generated).
-- A missing name does not fail at runtime: Fx() quietly returns the stock fallback, so only this test catches it.
-- Forms checked: Fx("name", ...), ChaosFx.name, ChaosFx["name"], ChaosSpell.fx(pos, "name", ...), the third argument of
-- ChaosSpell.vfxOr(pos, vname, "name", ...) and the cast effect of a chaos_casting spec (fx = {"name", ...}).
local failures, checks = 0, 0
local function ok(c, msg)
	checks = checks + 1
	if not c then
		failures = failures + 1
		print("FAIL: " .. tostring(msg))
	end
end

local function readFile(p)
	local f = io.open(p, "r")
	if not f then return nil end
	local s = f:read("*a")
	f:close()
	return s
end

dofile("data/lib/chaos_fx.lua")
ok(type(ChaosFx) == "table" and ChaosFx.arcane_aura ~= nil, "chaos_fx.lua loads")

local PATTERNS = {
	{"Fx", '%f[%w_.:]Fx%(%s*"([%w_]+)"'},
	{"ChaosFx.", "ChaosFx%.([%a_][%w_]*)"},
	{"ChaosFx[]", 'ChaosFx%[%s*"([%w_]+)"%s*%]'},
	{"ChaosSpell.fx", 'ChaosSpell%.fx%([^,]+,%s*"([%w_]+)"'},
	{"vfxOr", 'ChaosSpell%.vfxOr%([^,]+,[^,]+,%s*"([%w_]+)"'},
	{"the cast effect", 'fx%s*=%s*{%s*"([%w_]+)"'},
}

-- the names a source asks ChaosFx for that it does not have, as "how name" strings; comments are left out
local function unknownNames(src)
	src = src:gsub("%-%-%[(=*)%[.-%]%1%]", ""):gsub("%-%-[^\n]*", "")
	local bad, seen = {}, 0
	for _, p in ipairs(PATTERNS) do
		for name in src:gmatch(p[2]) do
			seen = seen + 1
			if ChaosFx[name] == nil then
				bad[#bad + 1] = p[1] .. " " .. name
			end
		end
	end
	return bad, seen
end

-- the scan itself: it finds each form, skips comments and passes known names
local planted = table.concat({
	'combat:setParameter(COMBAT_PARAM_EFFECT, Fx("no_such_a", 1))',
	'local id = ChaosFx.no_such_b',
	'ChaosSpell.fx(pos, "no_such_c", 2)',
	'ChaosSpell.vfxOr(pos, spin, "no_such_d", 3)',
	'local spec = {fx = {"no_such_e", 4}}',
	'-- Fx("in_a_comment")',
	'FxMissile("blood_spear", 5)',
	'Fx("arcane_aura", 6)',
}, "\n")
local bad, seen = unknownNames(planted)
ok(#bad == 5, "the planted unknown names are found: " .. table.concat(bad, ", "))
ok(seen == 6, "a missile name and a comment are not effect names: " .. seen)

-- every Lua file under data/
local list = io.popen('find data -name "*.lua" -type f | sort')
local files = {}
if list then
	for f in list:lines() do
		files[#files + 1] = f
	end
	list:close()
end
ok(#files > 200, "the Lua files under data/: " .. #files)
local total = 0
for _, f in ipairs(files) do
	local names, n = unknownNames(readFile(f) or "")
	total = total + n
	for _, b in ipairs(names) do
		ok(false, f .. ": " .. b .. " is not a ChaosFx name (Fx() would send the stock fallback)")
	end
end
ok(total > 100, "names checked: " .. total)

print(string.format("spell_fx_names_test: %d checks, %d failed", checks, failures))
if failures > 0 then
	os.exit(1)
end
