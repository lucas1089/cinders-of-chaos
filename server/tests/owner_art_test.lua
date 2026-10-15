-- Run from the server/ folder: luajit tests/owner_art_test.lua (and lua5.3; CI runs both)
-- The owner's art of client pair 26 (data/lib/chaos_owner_art.lua, chaos_owner_decor.lua): the switch is on (pair 26,
-- things_custom26, is on windows-assets at 50645056), so the shipped configs carry the store wings and the boss-drop
-- wings and validate with the real cores; the generated decoration ids match the manifest; the monster looks match the
-- picks file and the twelve monster files carry them; forced off, no config names a pair 26 look and the decoration
-- helper falls back.
CONST_ME_FIREWORK_YELLOW = CONST_ME_FIREWORK_YELLOW or 29 -- shop_config.lua reads it
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/transmog_core.lua")
dofile("data/scripts/chaos/exclusives_core.lua")
dofile("data/scripts/chaos/shop_core.lua")
dofile("data/scripts/chaos/nameplate_core.lua")

local n = 0
local function eq(a, b, m)
	n = n + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

local M = dofile("data/lib/chaos_owner_art.lua")
eq(M.PAIR26, true, "the pair 26 switch is on: things_custom26 is on windows-assets")

-- ---------------------------------------------------------------- decoration ids against the manifest
local rows = {}
local f = assert(io.open("data/items/owner_decor.csv", "r"))
local header = true
for line in f:lines() do
	if header then
		header = false
	else
		local cid, sid, key, kind = line:match("^(%d+),(%d+),([%w_]+),([%w_]+),")
		rows[#rows + 1] = {cid = tonumber(cid), sid = tonumber(sid), key = key, kind = kind,
			block = line:find("block=1", 1, true) ~= nil}
	end
end
f:close()
eq(#rows, 46, "46 decoration items in the manifest")
local byKey = {}
for _, r in ipairs(rows) do
	eq(r.sid, r.cid + 3000, r.key .. ": server id = client id + 3000")
	eq(r.sid >= M.decor.first and r.sid <= M.decor.last, true, r.key .. " inside first..last")
	byKey[r.key] = r
end
eq(#M.decor.plants, 45, "45 plants")
for _, p in ipairs(M.decor.plants) do
	eq(byKey[p.key].sid, p.id, p.key .. ": id as in the manifest")
	eq(byKey[p.key].block, p.block, p.key .. ": blocks as in the manifest")
	eq(byKey[p.key].kind, p.block and "stump" or "decor", p.key .. ": kind")
end
eq(M.decor.waypoint, byKey.waypoint_seal.sid, "the waypoint seal")

-- ---------------------------------------------------------------- monster looks against the picks file
local picks = {}
f = assert(io.open("../client/tools/sprites/monster_looks/owner_art_picks.csv", "r"))
header = true
for line in f:lines() do
	if header then
		header = false
	else
		local key, look, family, monster = line:match("^([%w_]+),(%d+),[^,]*,[^,]*,[^,]*,([%w]+),[^,]*,([^,]*),")
		picks[#picks + 1] = {key = key, look = tonumber(look), family = family, monster = monster}
	end
end
f:close()
eq(#picks, 21, "21 looks: 12 monsters and 9 wings")
local nMon = 0
for i, p in ipairs(picks) do
	eq(p.look, 2212 + i, p.key .. ": looks in order after pair 25's 2212 outfits")
	if p.family == "hunt" or p.family == "dungeonboss" then
		eq(M.monsters[p.monster], p.look, p.monster .. ": look as in the picks")
		nMon = nMon + 1
	end
end
eq(nMon, 12, "12 monster looks")
-- the twelve monster files carry their pair 26 look (apply_monster_looks.py with the rows in picks.csv), and no other
-- monster file names a pair 26 look
local fileLook, name = {}, nil
local p = io.popen('grep -rhoE "<monster name=\\"[^\\"]+\\"|<look type=\\"[0-9]+\\"" data/monster/monsters/chaos 2>/dev/null')
for line in p:lines() do
	local nm = line:match('^<monster name="([^"]+)"')
	if nm then
		name = nm
	elseif name then
		fileLook[name] = tonumber(line:match("(%d+)"))
		local look = fileLook[name]
		eq(look < 2213 or look > 2233 or M.monsters[name] == look, true,
			name .. ": look " .. look .. " of pair 26 only on its own monster")
		name = nil
	end
end
p:close()
for monster, look in pairs(M.monsters) do
	eq(fileLook[monster], look, monster .. ": the monster file has its pair 26 look")
end

-- wings: every pick of family storewings / exclusive is a wings entry with that look
local wingLook = {}
for _, w in ipairs(M.storeWings) do
	wingLook[w.key] = w.look
end
for _, e in ipairs(M.exclusives) do
	wingLook[e.key] = e.look
end
local nWings = 0
for _, pk in ipairs(picks) do
	if pk.family == "storewings" or pk.family == "exclusive" then
		eq(wingLook[pk.key], pk.look, pk.key .. ": wings look as in the picks")
		nWings = nWings + 1
	end
end
eq(nWings, 9, "nine wings")

-- ---------------------------------------------------------------- forced off: no config names pair 26
M.PAIR26 = false
local realDofile = dofile
dofile = function(path, ...)
	if path == "data/lib/chaos_owner_art.lua" then
		return M
	end
	return realDofile(path, ...)
end
local offExcl = dofile("data/scripts/chaos/exclusives_config.lua")
local offShop = dofile("data/scripts/chaos/shop_config.lua")
dofile = realDofile
for _, e in ipairs(offExcl.exclusives) do
	eq(e.look == nil or e.look < 2213, true, "no exclusive names a pair 26 look while off")
end
for _, c in ipairs(offShop.categories) do
	for _, o in ipairs(c.offers or {}) do
		eq(o.kind ~= "wings" or o.id < 21, true, "no store offer of the pair 26 wings while off")
	end
end
eq(#M.storeOffers(), 0, "no store offers while off")
eq(M.decorId("cactus_01", 7), 7, "decoration falls back while off")
M.PAIR26 = true

-- ---------------------------------------------------------------- switch on: the shipped configs validate
local shop = dofile("data/scripts/chaos/shop_config.lua")
local excl = dofile("data/scripts/chaos/exclusives_config.lua")
eq(#M.storeOffers(), #M.storeWings, "a store offer per sold wings while on")
local wingsCat
for _, c in ipairs(shop.categories) do
	if c.name == "Wings" then
		wingsCat = c
	end
end
local sold = {}
for _, o in ipairs(wingsCat.offers) do
	sold[o.id] = o.cost
end
for _, w in ipairs(M.storeWings) do
	eq(sold[w.id], w.cost, w.key .. ": sold in the Wings category when on")
end
local found = {}
for _, e in ipairs(excl.exclusives) do
	if e.look and e.look >= 2213 then
		found[e.key] = true
	end
end
for _, e in ipairs(M.exclusives) do
	eq(found[e.key], true, e.key .. ": an exclusive when on")
	eq(sold[e.id], nil, e.key .. ": a boss exclusive is not sold")
end
local rolled = {}
for _, b in ipairs(excl.bosses) do
	for _, r in ipairs(b.rewards) do
		rolled[r] = b.key
	end
end
for boss, key in pairs(M.bossRewards) do
	eq(rolled[key], boss, key .. ": rolled by " .. boss)
end
local achievements = dofile("data/scripts/chaos/achievements_data.lua")
local transmog = dofile("data/scripts/chaos/transmog_config.lua")
local cosmetics = dofile("data/scripts/chaos/cosmetics_config.lua")
local pets = dofile("data/scripts/chaos/pets_config.lua")
local portal = dofile("data/scripts/chaos/townportal_config.lua")
local storeList = dofile("data/scripts/chaos/shop_cosmetics.lua")
local storeLooks = {looks = {}, mounts = {}}
for _, e in ipairs(storeList.outfits) do
	storeLooks.looks[e.looktype], storeLooks.looks[e.lookfemale] = true, true
end
for _, e in ipairs(storeList.addons) do
	storeLooks.looks[e.looktype], storeLooks.looks[e.lookfemale] = true, true
end
for _, e in ipairs(storeList.mounts) do
	storeLooks.mounts[e.id] = true
end
local opts = {achievements = achievements, shop = shop, storeLooks = storeLooks, cosmetics = cosmetics, transmog = transmog,
	pets = pets, portal = portal, frames = ChaosNameplate.FRAMES}
local problems = ChaosExclusivesCore.validate(excl, opts)
eq(#problems, 0, "exclusives with the pair 26 wings validate: " .. table.concat(problems, "; "))
dofile("data/scripts/chaos/class_looks_core.lua")
local EX = ChaosShopCore.exclusions({classLooks = ChaosClassLooks.looks, classOutfits = Chaos.classes.outfits,
	achievements = achievements, season = dofile("data/scripts/chaos/season_config.lua"),
	seasonpass = dofile("data/scripts/chaos/seasonpass_config.lua"), exclusives = excl})
problems = ChaosShopCore.validate(shop, EX)
eq(#problems, 0, "the store with the pair 26 wings validates: " .. table.concat(problems, "; "))
eq(M.decorId("cactus_01", 7), M.decor.plants[1].id, "a plant id when on")
eq(M.decorId("waypoint_seal", 7), M.decor.waypoint, "the seal id when on")
eq(M.decorId("nothing", 7), 7, "an unknown key falls back")

print("owner_art_test: " .. n .. " checks passed")
