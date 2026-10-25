-- Run from the server/ folder: luajit tests/pack41_fx_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- Pair 41 (client/tools/sprites/gen_pack41_missiles.py): the projectile pack's missiles redrawn in place from the native
-- 32 px renders, and three of its unused variants appended as missiles 251-253 (data/lib/chaos_pack41_fx_ids.lua).
-- Checks: the ids file lists exactly the appended rows of the client spec, in order after pair 36's 250, with the spec's
-- send offsets; ids 254 (CONST_ANI_WEAPONTYPE in the server) and 255 stay free; a redrawn row gets no Lua name and its id
-- is one pair 36 built, once; the names are free in the other tables; nothing sends the new names yet (no spell is
-- wired); the pair 36 loader brings the ids in.
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

-- the client spec: replace,kind,name,file,w,h,phases,ms,dx,dy,note (the note holds commas, so read ten fields only)
local text = readFile("../client/tools/sprites/art_import/pack41_missiles.csv")
ok(text ~= nil, "spec pack41_missiles.csv")
local rows, first = {}, true
for line in (text or ""):gmatch("[^\n]+") do
	if first then
		first = false
	else
		local f = {}
		for v in (line .. ","):gmatch("([^,]*),") do f[#f + 1] = v end
		rows[#rows + 1] = {replace = tonumber(f[1]), kind = f[2], name = f[3], w = tonumber(f[5]), h = tonumber(f[6]),
			dx = tonumber(f[9]), dy = tonumber(f[10])}
	end
end
ok(#rows > 50, "the spec lists the redrawn and the new missiles (" .. #rows .. ")")

-- the ids pair 36 built: stock ids from its replace spec, 189 and on from its missiles spec
local built = {}
local firstLine = true
for line in (readFile("../client/tools/sprites/art_import/pack36_replace.csv") or ""):gmatch("[^\n]+") do
	if firstLine then
		firstLine = false
	else
		local id, kind = line:match("^(%d+),(%a+),")
		if kind == "missile" then built[tonumber(id)] = true end
	end
end
local nApp = 0
for line in (readFile("../client/tools/sprites/art_import/pack36_missiles.csv") or ""):gmatch("[^\n]+") do
	if line:sub(1, 8) == "missile," then
		nApp = nApp + 1
		built[188 + nApp] = true
	end
end
eq(nApp, 62, "pair 36 appended 62 missiles (189-250)")

local seen, new = {}, {}
for _, r in ipairs(rows) do
	eq(r.kind, "missile", r.name .. ": a missile")
	if r.replace then
		ok(built[r.replace], r.name .. ": id " .. r.replace .. " is a missile pair 36 built")
		ok(not seen[r.replace], r.name .. ": id redrawn once")
		seen[r.replace] = true
		ok(r.w <= 3 and r.h <= 3 and r.dx < r.w and r.dy < r.h, r.name .. ": size and offset")
		if r.replace <= 188 then
			ok(r.dx == 0 and r.dy == 0, r.name .. ": a stock id is sent at offset 0, 0")
		end
	else
		new[#new + 1] = r
	end
end
eq(#new, 3, "three new missiles")

-- the ids file
local ids = readFile("data/lib/chaos_pack41_fx_ids.lua") or ""
ok(ids ~= "", "the ids file exists")
local got = {}
for name, id, dx, dy in ids:gmatch("\nChaosVfxMissile%.([%w_]+) = {id = (%d+), dx = (%d+), dy = (%d+)}") do
	got[#got + 1] = {name = name, id = tonumber(id), dx = tonumber(dx), dy = tonumber(dy)}
end
eq(#got, #new, "the ids file lists every new row")
for i, r in ipairs(new) do
	local e = got[i]
	ok(e ~= nil and e.name == r.name and e.id == 250 + i and e.dx == r.dx and e.dy == r.dy,
		r.name .. " is id " .. (250 + i) .. " with the spec's offset in the ids file")
end
ok(not ids:find("\nChaosVfx.", 1, true) and not ids:find("rep41_", 1, true), "no effect and no redrawn row has a Lua name")
for _, e in ipairs(got) do
	ok(e.id >= 251 and e.id <= 253, e.name .. ": id inside 251-253 (254 is the server's weapon-type marker, 255 stays free)")
end

-- the names and ids are free in the other tables
local others = {"chaos_vfx", "chaos_vfx_art", "chaos_pack_fx_ids", "chaos_pack27_fx_ids", "chaos_pack29_fx_ids",
	"chaos_pack29_vfx_ids", "chaos_pack30_fx_ids", "chaos_pack36_fx_ids", "chaos_class_fx_ids", "chaos_big_fx_ids",
	"chaos_status_fx_ids"}
ChaosVfx, ChaosVfxMissile = nil, nil
for _, f in ipairs(others) do
	pcall(dofile, "data/lib/" .. f .. ".lua")
end
ok(ChaosVfxMissile ~= nil, "the other tables load")
for _, e in ipairs(got) do
	ok(ChaosVfxMissile and ChaosVfxMissile[e.name] == nil, e.name .. ": name free in the other tables")
	for _, other in pairs(ChaosVfxMissile or {}) do
		ok(other.id ~= e.id, e.name .. ": id " .. e.id .. " is free")
	end
end

-- nothing sends the new names yet: no spell, script or monster file mentions them
local function scan(dir)
	local n = 0
	local h = io.popen("find " .. dir .. " -name '*.lua' -o -name '*.xml' 2>/dev/null")
	if h then
		for path in h:lines() do
			local body = readFile(path) or ""
			for _, e in ipairs(got) do
				if body:find(e.name, 1, true) then
					n = n + 1
					print("sent by " .. path .. ": " .. e.name)
				end
			end
		end
		h:close()
	end
	return n
end
eq(scan("data/scripts") + scan("data/spells") + scan("data/monster") + scan("data/XML"), 0,
	"no script sends the new names yet")

-- the loader of pair 36 brings the ids in
dofile("data/lib/chaos_pack27_fx.lua")
dofile("data/lib/chaos_pack36_fx.lua")
local C = ChaosPack36Fx
ChaosVfx, ChaosVfxMissile = {}, {}
C.PAIR36_FX = true
C.loaded = nil
eq(C.live(), true, "the pair 36 ids load")
for _, e in ipairs(got) do
	ok(ChaosVfxMissile[e.name] ~= nil and ChaosVfxMissile[e.name].id == e.id, e.name .. ": known after C.live()")
end

if failures > 0 then
	print(failures .. " failure(s)")
	os.exit(1)
end
print("pack41_fx_test: OK")
