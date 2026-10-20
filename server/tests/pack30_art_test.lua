-- Run from the server/ folder: luajit tests/pack30_art_test.lua (and lua5.3; CI runs both)
-- Pair 30 monsters: the look ids of client/tools/sprites/monster_looks/pack30_picks.csv are the outfits of the build
-- lists (art_import/pack30_looks.csv, pack30_strips.csv) in order from 2237; the ten new monster files carry the pick
-- look and the first tint scheme; the gallery dummy is inert; the switch file (data/lib/chaos_pack30_art.lua, if
-- present) keeps the current look while the pair 30 switch is off.

local n = 0
local function eq(a, b, m)
	n = n + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

local function slurp(p)
	local f = assert(io.open(p, "r"))
	local s = f:read("*a")
	f:close()
	return s
end

local function splitCsv(line)
	local out, i, len = {}, 1, #line
	while i <= len + 1 do
		if line:sub(i, i) == '"' then
			local j = i + 1
			local buf = {}
			while j <= len do
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
			out[#out + 1] = table.concat(buf)
			i = j + 2
		else
			local j = line:find(",", i, true) or (len + 1)
			out[#out + 1] = line:sub(i, j - 1)
			i = j + 1
		end
	end
	return out
end

local function rows(path)
	local list, head = {}, nil
	for line in slurp(path):gmatch("[^\r\n]+") do
		local c = splitCsv(line)
		if not head then
			head = c
		else
			local r = {}
			for i, k in ipairs(head) do
				r[k] = c[i]
			end
			list[#list + 1] = r
		end
	end
	return list
end

local ART = "../client/tools/sprites/art_import/"
local PICKS = "../client/tools/sprites/monster_looks/"
local MON = "data/monster/monsters/chaos/pack30/"

-- ---------------------------------------------------------------- picks against the build lists
local looks = rows(ART .. "pack30_looks.csv")
local outfits = {}
for _, r in ipairs(looks) do
	if r.cat == "outfit" then
		outfits[#outfits + 1] = r.key
	end
end
local strips = 0
for _, r in ipairs(rows(ART .. "pack30_strips.csv")) do
	if r.cat == "outfit" then
		strips = strips + 1
	end
end
eq(#outfits, 75, "75 sheet outfits in the build list")
eq(2236 + #outfits + strips, 2384, "the pair ends at outfit 2384")

local picks = rows(PICKS .. "pack30_picks.csv")
eq(#picks, #outfits, "one pick per sheet outfit")
local lookOf = {}
for i, p in ipairs(picks) do
	eq(tonumber(p.look), 2236 + i, p.key .. ": look id in build order")
	eq(p.key, outfits[i], p.key .. ": same key as the build list")
	eq(p.lib, "pack30", p.key .. ": lib")
	lookOf[p.key] = tonumber(p.look)
end

-- picks.csv (the integrator's list) agrees where it holds the rows
local all = {}
for _, p in ipairs(rows(PICKS .. "picks.csv")) do
	if p.lib == "pack30" then
		all[p.key] = p
	end
end
for key, p in pairs(all) do
	eq(tonumber(p.look), lookOf[key], key .. ": picks.csv look")
end

-- first tint scheme per key
local tint = {}
for _, r in ipairs(rows(ART .. "pack30_tints.csv")) do
	if not tint[r.key] then
		tint[r.key] = r
	end
end

-- ---------------------------------------------------------------- the ten monsters
local MONSTERS = {
	gibbet_fledgling = "Gallows Fledgling", doomcrow_flock = "Doomcrow Flock", mound_haunt = "Barrow Haunt",
	gibbetwing = "Gibbetwing", ashmaw_raider = "Ashmaw Raider", ashmaw_bonecaller = "Ashmaw Bonecaller",
	mange_hound = "Mange Hound", ashmaw_warlord = "Ashmaw Warlord", slagborer = "Slagborer",
	slagborer_queen = "Slagborer Queen",
}
local count = 0
for key, name in pairs(MONSTERS) do
	count = count + 1
	local xml = slurp(MON .. key .. ".xml")
	eq(xml:match('<monster name="([^"]+)"'), name, key .. ": name")
	local look = xml:match('<look type="(%d+)"')
	eq(tonumber(look), lookOf[key], key .. ": lookType is the pick look")
	assert(tonumber(look) > 2236 and tonumber(look) <= 2311, key .. ": a pair 30 sheet outfit")
	local t = tint[key]
	for _, c in ipairs({"head", "body", "legs", "feet"}) do
		eq(xml:match('<look [^>]*%f[%w]' .. c .. '="(%d+)"'), t[c], key .. ": " .. c .. " is the first tint scheme")
	end
	assert(not xml:match("addons"), key .. ": no addons on a sheet look")
	eq(xml:match('corpse="(%d+)"'), "6068", key .. ": template corpse (the pack corpse items have no server id yet)")
	local lo, hi = xml:match('<level min="(%d+)" max="(%d+)"')
	assert(tonumber(lo) >= 420 and tonumber(hi) <= 660 and tonumber(lo) < tonumber(hi), key .. ": level band 420-660")
	assert(not xml:match("<summon "), key .. ": no summons")
	local picked = all[key]
	if picked then
		eq(picked.family, "hunt", key .. ": hunt row in picks.csv")
		eq(picked.monsters, name, key .. ": picks.csv names the monster")
	end
end
eq(count, 10, "ten monsters")

-- ---------------------------------------------------------------- the gallery dummy
local g = slurp(MON .. "pack30_gallery.xml")
eq(g:match('<monster name="([^"]+)"'), "Look Model", "dummy name")
eq(g:match('experience="(%d+)"'), "0", "no experience")
eq(g:match('<flag attackable="(%d)"'), "0", "not attackable")
eq(g:match('<flag hostile="(%d)"'), "0", "not hostile")
eq(g:match('speed="(%d+)"'), "0", "does not walk")
eq(g:match('<health now="(%d+)" max="(%d+)"'), "1000", "health 1000")
assert(not g:match("<loot"), "no loot")

-- ---------------------------------------------------------------- the switch file (written by the items helper)
local f = io.open("data/lib/chaos_pack30_art.lua", "r")
if f then
	f:close()
	local M = dofile("data/lib/chaos_pack30_art.lua")
	local was = M.PAIR30
	M.PAIR30 = false
	eq(M.lookOf("Gibbetwing", 1074), 1074, "off: lookOf keeps the current look")
	eq(M.lookOf("No Such Monster", 77), 77, "off: unknown name")
	M.PAIR30 = true
	eq(M.lookOf("No Such Monster", 77), 77, "on: unknown name keeps the look")
	for name, look in pairs(M.monsters) do
		assert(type(look) == "number" and look > 2236 and look <= 2384, name .. ": a pair 30 outfit")
		eq(M.lookOf(name, 1), look, name .. ": on gives the pack look")
		M.PAIR30 = false
		eq(M.lookOf(name, 1), 1, name .. ": off keeps the look")
		M.PAIR30 = true
	end
	M.PAIR30 = was
end

print("pack30_art_test: " .. n .. " checks ok")
