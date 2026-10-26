-- Run from the server/ folder: luajit tests/pack41_fx_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- Pair 41 (client/tools/sprites/gen_pack41_missiles.py): the projectile pack's missiles redrawn in place from the native
-- 32 px renders, and three of its unused variants appended as missiles 251-253 (data/lib/chaos_pack41_fx_ids.lua).
-- Checks: the ids file lists exactly the appended rows of the client spec, in order after pair 36's 250, with the spec's
-- send offsets; ids 254 (CONST_ANI_WEAPONTYPE in the server) and 255 stay free; a redrawn row gets no Lua name and its id
-- is one pair 36 built, once; the names are free in the other tables; O239 wires every name (see SENT below); the pair 36 loader brings the ids in.
-- Pair 42 (the same tool, art_import/pack42_missiles.csv): six in-use stock ids redrawn without a name (1 22 34 35 7 6) and
-- fifteen named swaps of free ids (100 108 111 115 137-146 and 75; 62-74 and 76 are sent by number in the base data),
-- registered in the same ids file after 251-253 with the spec's send offsets; none is a pair 41 id or a second name.
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

-- a quote-aware CSV line (pair 42's note is quoted and holds commas)
local function csvFields(line)
	local f, i, n = {}, 1, #line
	while i <= n + 1 do
		if line:sub(i, i) == '"' then
			local j = i + 1
			local buf = {}
			while j <= n do
				local c = line:sub(j, j)
				if c == '"' and line:sub(j + 1, j + 1) == '"' then
					buf[#buf + 1] = '"'
					j = j + 2
				elseif c == '"' then
					break
				else
					buf[#buf + 1] = c
					j = j + 1
				end
			end
			f[#f + 1] = table.concat(buf)
			i = j + 2
		else
			local j = line:find(",", i, true) or (n + 1)
			f[#f + 1] = line:sub(i, j - 1)
			i = j + 1
		end
	end
	return f
end

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

-- pair 42's spec: replace,kind,name,file,w,h,phases,ms,dx,dy,note,lua
local text42 = readFile("../client/tools/sprites/art_import/pack42_missiles.csv")
ok(text42 ~= nil, "spec pack42_missiles.csv")
local rows42, named42, first42 = {}, {}, true
for line in (text42 or ""):gmatch("[^\n]+") do
	if first42 then
		first42 = false
	else
		local f = csvFields(line)
		local r = {replace = tonumber(f[1]), kind = f[2], name = f[3], w = tonumber(f[5]), h = tonumber(f[6]),
			dx = tonumber(f[9]), dy = tonumber(f[10]), lua = f[12] or ""}
		rows42[#rows42 + 1] = r
		if r.lua ~= "" then named42[#named42 + 1] = r end
	end
end
eq(#rows42, 21, "pair 42 redraws 21 missiles")
eq(#named42, 15, "pair 42 names 15 of them")
local seen42, redrawn41 = {}, {}
for _, r in ipairs(rows) do
	if r.replace then redrawn41[r.replace] = true end
end
for _, r in ipairs(rows42) do
	eq(r.kind, "missile", r.name .. ": a missile")
	ok(r.replace and r.replace >= 1 and r.replace <= 250, r.name .. ": id inside 1-250 (251-253 are pair 41's)")
	ok(not seen42[r.replace], r.name .. ": id redrawn once")
	ok(not redrawn41[r.replace], r.name .. ": not an id pair 41 redrew")
	seen42[r.replace] = true
	ok(r.w <= 3 and r.h <= 3 and r.dx < r.w and r.dy < r.h, r.name .. ": size and offset")
	if r.lua == "" then
		ok(r.dx == 0 and r.dy == 0 and r.w <= 2 and r.h <= 2, r.name .. ": an unnamed stock swap is sent at offset 0, 0, 2 x 2 at most")
	end
end
for _, id in ipairs({1, 22, 34, 35, 7, 6}) do
	ok(seen42[id], "stock id " .. id .. " is swapped")
end
-- ids 62-74 and 76 are sent by number in the base data (monster files): pair 42 must not draw over them; 75 was free
for id = 62, 76 do
	ok(id == 75 or not seen42[id], "id " .. id .. " is in use by the base data and stays untouched")
end
ok(seen42[75], "id 75 (free) holds the water bolt")

-- the ids file
local ids = readFile("data/lib/chaos_pack41_fx_ids.lua") or ""
ok(ids ~= "", "the ids file exists")
local got = {}
for name, id, dx, dy in ids:gmatch("\nChaosVfxMissile%.([%w_]+) = {id = (%d+), dx = (%d+), dy = (%d+)}") do
	got[#got + 1] = {name = name, id = tonumber(id), dx = tonumber(dx), dy = tonumber(dy)}
end
eq(#got, #new + #named42, "the ids file lists every new row and every named pair 42 row")
for i, r in ipairs(new) do
	local e = got[i]
	ok(e ~= nil and e.name == r.name and e.id == 250 + i and e.dx == r.dx and e.dy == r.dy,
		r.name .. " is id " .. (250 + i) .. " with the spec's offset in the ids file")
end
for i, r in ipairs(named42) do
	local e = got[#new + i]
	ok(e ~= nil and e.name == r.lua and e.id == r.replace and e.dx == r.dx and e.dy == r.dy,
		r.lua .. " is id " .. r.replace .. " with the spec's offset in the ids file")
end
ok(not ids:find("\nChaosVfx.", 1, true) and not ids:find("rep41_", 1, true) and not ids:find("rep42_", 1, true),
	"no effect and no redrawn row has a Lua name")
for i, e in ipairs(got) do
	if i <= #new then
		ok(e.id >= 251 and e.id <= 253, e.name .. ": id inside 251-253 (254 is the server's weapon-type marker, 255 stays free)")
	else
		ok(e.id < 251 and e.id ~= 254 and e.id ~= 255, e.name .. ": a pair 42 id stays below pair 41's appended ones")
	end
end

-- the names and ids are free in the other tables
local others = {"chaos_vfx", "chaos_vfx_art", "chaos_pack_fx_ids", "chaos_pack27_fx_ids", "chaos_pack29_fx_ids",
	"chaos_pack29_vfx_ids", "chaos_pack30_fx_ids", "chaos_pack36_fx_ids", "chaos_class_fx_ids", "chaos_big_fx_ids",
	"chaos_status_fx_ids"}
ChaosVfx, ChaosVfxMissile, ChaosFxMissile = nil, nil, nil
pcall(dofile, "data/lib/chaos_fx.lua")
for _, f in ipairs(others) do
	pcall(dofile, "data/lib/" .. f .. ".lua")
end
ok(ChaosVfxMissile ~= nil, "the other tables load")
for _, e in ipairs(got) do
	ok(ChaosVfxMissile and ChaosVfxMissile[e.name] == nil, e.name .. ": name free in the other tables")
	for _, other in pairs(ChaosVfxMissile or {}) do
		ok(other.id ~= e.id, e.name .. ": id " .. e.id .. " is free")
	end
	for k, v in pairs(ChaosFxMissile or {}) do
		ok(v ~= e.id, e.name .. ": id " .. e.id .. " is not ChaosFxMissile." .. k)
	end
end

-- O239: which scripts send which names. Every name is sent by exactly the files listed (spells through
-- ChaosSpell.pshoot, the bow's elemental extra projectile through chaos_archery_core.lua); the rest stay unsent.
local SENT = {
	proj_arrow_fire = {"chaos_archery_core.lua"},
	proj_arrow_frost = {"chaos_archery_core.lua"},
	proj_piercing_arrow_holy = {"attack_kit_config.lua", "holy_smite.lua", "judgement.lua", "sanctified_barrage.lua",
		"twin_verdict.lua"},
	proj_ball_lightning_thunder = {"chain_lightning.lua"},
	proj_blood_spike_necrotic = {"attack_kit_config.lua"},
	proj_boulder_magma = {"meteor_strike.lua"},
	proj_flame_lance_spirit = {"attack_kit_config.lua"},
	proj_razor_leaf_sakura = {"attack_kit_config.lua"},
	proj_shadow_bolt_blood = {"life_siphon.lua"},
	proj_soul_skull_spirit = {"raise_dead.lua"},
	proj_spirit_wisp_arcane = {"mirror_mend.lua"},
	proj_venom_glob_necrotic = {"attack_kit_config.lua"},
	proj_void_orb_abyss = {"shadow_step.lua"},
	proj_wind_blade_storm = {"iaijutsu.lua"},
	-- the last four (all sent since the O239 follow-up): Soul Rot, Skewering Line (a store skin keeps the blood spear
	-- through pshoot), Radiant Smite, Dreamrot (the kit's pshot)
	proj_poison_dart_necrotic = {"soul_rot.lua"}, proj_spirit_arrow_blood = {"piercing_volley.lua"},
	proj_spirit_arrow_gold = {"radiant_smite.lua"}, proj_water_bolt_abyss = {"attack_kit_config.lua"}
}
local function scan(dir, into)
	local h = io.popen("find " .. dir .. " -name '*.lua' -o -name '*.xml' 2>/dev/null")
	if h then
		for path in h:lines() do
			local body = readFile(path) or ""
			local base = path:match("([^/]+)$")
			for _, e in ipairs(got) do
				if body:find(e.name, 1, true) and not path:find("_ids.lua", 1, true) then
					into[e.name] = into[e.name] or {}
					into[e.name][#into[e.name] + 1] = base
				end
			end
		end
		h:close()
	end
end
local sentBy = {}
for _, d in ipairs({"data/scripts", "data/spells", "data/monster", "data/XML", "data/lib/chaos_archery_core.lua"}) do
	scan(d, sentBy)
end
for _, e in ipairs(got) do
	local have, want = sentBy[e.name] or {}, SENT[e.name]
	ok(want ~= nil, e.name .. ": listed in the test's SENT table")
	table.sort(have)
	local w = {}
	for i, v in ipairs(want or {}) do w[i] = v end
	table.sort(w)
	eq(table.concat(have, ","), table.concat(w, ","), e.name .. " is sent by the expected files")
end

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
