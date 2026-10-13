-- Run from the server/ folder: luajit tests/theme_art_test.lua (and lua5.3; CI runs both)
-- The themed art of client pair things_custom24 (data/lib/chaos_theme_art.lua, chaos_theme_items.lua): the switch is
-- off and then nothing changes for players (no set, no exclusive, the item ids out of the transmog catalogue, grounds
-- fall back); the generated ids match the manifest; with the switch on, the transmog sets and the exclusives validate
-- with the real configs and their cores, and the ground helper gives the installed ids.
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

local M = dofile("data/lib/chaos_theme_art.lua")
eq(M.PAIR24, false, "the pair 24 switch is off until things_custom24 is on windows-assets")

-- ---------------------------------------------------------------- the generated ids against the manifest
local rows = {}
local f = assert(io.open("data/items/theme_items.csv", "r"))
local header = true
for line in f:lines() do
	if header then
		header = false
	else
		local cid, sid, key, kind = line:match("^(%d+),(%d+),([%w_]+),([%w_]+),")
		rows[#rows + 1] = {cid = tonumber(cid), sid = tonumber(sid), key = key, kind = kind}
	end
end
f:close()
eq(#rows, 244, "244 themed items in the manifest")
local byKey = {}
for _, r in ipairs(rows) do
	eq(r.sid, r.cid + 3000, r.key .. ": server id = client id + 3000")
	eq(r.sid >= M.items.first and r.sid <= M.items.last, true, r.key .. " inside first..last")
	byKey[r.key] = r
end
local nPieces = 0
for _, p in ipairs(M.items.pieces) do
	eq(byKey[p.key] and byKey[p.key].sid, p.id, p.key .. ": id as in the manifest")
	eq(byKey[p.key].kind, p.kind, p.key .. ": kind")
	nPieces = nPieces + 1
end
eq(nPieces, 6 * 18 + 4 * 21, "six full sets of 18 and four kit sets of 21 pieces")
local nGround = 0
for fam, g in pairs(M.items.grounds) do
	eq(byKey["ground_" .. fam].sid, g.ground, fam .. " ground")
	for _, piece in ipairs({"n", "e", "s", "w", "outer_ne", "outer_nw", "outer_se", "outer_sw", "inner_ne", "inner_nw",
		"inner_se", "inner_sw"}) do
		eq(byKey["border_" .. fam .. "_" .. piece].sid, g[piece], fam .. " " .. piece)
	end
	nGround = nGround + 1
end
eq(nGround, 4, "four ground families")

-- ---------------------------------------------------------------- switch off: nothing for players
local transmog = dofile("data/scripts/chaos/transmog_config.lua")
for _, s in ipairs(transmog.sets) do
	eq(s.key:find("^theme_") == nil, true, "no themed transmog set while off")
end
local last = transmog.excludeRanges[#transmog.excludeRanges]
eq(last[1] == M.items.first and last[2] == M.items.last, true, "the item ids are out of the transmog catalogue while off")
eq(ChaosTransmogCore.isExcluded(transmog, 36700), true, "an installed themed item unlocks nothing while off")
local excl = dofile("data/scripts/chaos/exclusives_config.lua")
for _, e in ipairs(excl.exclusives) do
	eq(e.look == nil or e.look < 2185, true, "no exclusive names a pair 24 look while off")
end
eq(M.ground("lava", nil, 598), 598, "grounds fall back while off")
eq(M.ground("water", "n", 4644), 4644, "border pieces fall back while off")

-- ---------------------------------------------------------------- switch on: the sets and exclusives validate
M.PAIR24 = true
transmog.excludeRanges[#transmog.excludeRanges] = nil
M.addTransmog(transmog)
local themed = {}
for _, s in ipairs(transmog.sets) do
	if s.key:find("^theme_") then
		themed[#themed + 1] = s
	end
end
eq(#themed, 6 + 4 * 3, "a set per full set and per class kit")
local kindOf = {sword = "sword", axe = "axe", club = "club", bow = "distance", crossbow = "distance", wand = "wand",
	rod = "wand", shield = "shield", spellbook = "shield", helmet = "helmet", armor = "armor", legs = "legs",
	boots = "boots"}
local pieceById = {}
for _, p in ipairs(M.items.pieces) do
	pieceById[p.id] = p
end
local function describe(id)
	local p = pieceById[id]
	if p then
		return kindOf[p.kind] and {name = p.name, kind = kindOf[p.kind]} or {name = p.name}
	end
	return {name = "base item " .. id, kind = "helmet"}
end
local shop = dofile("data/scripts/chaos/shop_config.lua")
local achievements = dofile("data/scripts/chaos/achievements_data.lua")
local problems = ChaosTransmogCore.validate(transmog, describe, shop, achievements)
eq(#problems, 0, "transmog with the themed sets validates: " .. table.concat(problems, "; "))
for _, s in ipairs(themed) do
	for _, id in ipairs(s.looks) do
		eq(kindOf[pieceById[id].kind] ~= nil, true, s.key .. ": only pieces with a transmog kind")
	end
end
eq(#themed[1].looks, 13, "a full set has 13 transmog looks")

M.addExclusives(excl)
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
problems = ChaosExclusivesCore.validate(excl, opts)
eq(#problems, 0, "exclusives with the auras and wings validate: " .. table.concat(problems, "; "))
local found = 0
for _, e in ipairs(excl.exclusives) do
	if e.look and e.look >= 2185 then
		found = found + 1
	end
end
eq(found, 3, "two auras and the wings")

eq(M.ground("lava", nil, 598), M.items.grounds.lava.ground, "the lava ground when on")
eq(M.ground("water", "inner_se", 4644), M.items.grounds.water.inner_se, "a water border piece when on")
eq(M.ground("tar", nil, 1), 1, "an unknown family falls back")

print("theme_art_test: " .. n .. " checks passed")
