-- Run from the server/ folder: luajit tests/poi_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- Covers the points of interest (data/scripts/chaos/poi_core.lua): clean marks and keys, loading the generated data
-- (bad entries dropped), static + runtime merge and the version, the reveal index (range, floor, cell borders, once
-- only), the discoveries text round trip, what a character is shown, the Chaos NPC names; and that the committed
-- data/chaos_poi.lua and poi_config.lua load and are sane.
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/poi_core.lua")
local P = ChaosPoi
local cfg = dofile("data/scripts/chaos/poi_config.lua")

local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end
local function eq(a, b, what)
	ok(a == b, what .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

-- ------------------------------------------------------------------ marks and keys
local m = P.mark("hunt", 32091.7, 31154, 2, "Hunting: Penguin (level 1-20)", 1)
eq(m.x, 32091, "integer x"); eq(m.r, 1, "discoverable"); eq(m.n, "Hunting: Penguin (level 1-20)", "name")
eq(P.mark("castle", 1, 1, 7), nil, "unknown kind")
eq(P.mark("temple", 0, 1, 7), nil, "x 0")
eq(P.mark("temple", 1, 1, 16), nil, "floor 16")
eq(P.mark("temple", 70000, 1, 7), nil, "x too big")
eq(P.mark("temple", 10, 10, 7, "T").r, 0, "always by default")
eq(P.key(m), "h7d5b79b22", "key: kind letter and hex position")
eq(#P.key(P.mark("dungeon", 65535, 65535, 15)), 10, "keys are 10 characters")
local letters = {}
for kind, letter in pairs(P.KINDS) do
	ok(not letters[letter], "kind letter " .. letter .. " used twice")
	letters[letter] = kind
end

-- ------------------------------------------------------------------ load and merge
local marks, version = P.load({version = "abc", marks = {
	{k = "temple", x = 100, y = 100, z = 7, n = "Temple of Cinderhold", r = 0},
	{k = "hunt", x = 140, y = 100, z = 7, n = "Hunting: Rat (level 1-10)", r = 1},
	{k = "nope", x = 1, y = 1, z = 7},
	"junk",
	{k = "boss", x = 500, y = 500, z = 8, n = "Dreadscale (island boss)", r = 1}
}})
eq(#marks, 3, "bad entries dropped"); eq(version, "abc", "version")
local none, v0 = P.load(nil)
eq(#none, 0, "no data: no marks"); eq(v0, "", "no data: no version")
local runtime = {P.mark("npc", 103, 100, 7, "Material Broker (professions)"), P.mark("temple", 100, 100, 7, "dup")}
local all, v1 = P.merge(marks, runtime, version)
eq(#all, 4, "merged, one mark per kind and tile")
eq(all[1].n, "Temple of Cinderhold", "the static mark wins")
local _, v2 = P.merge(marks, {}, version)
ok(v1 ~= v2, "the runtime marks change the version")
local _, v3 = P.merge(marks, runtime, version)
eq(v1, v3, "same input, same version")
eq(#P.hash("x"), 8, "hash length")

-- ------------------------------------------------------------------ reveal
local idx = P.index(all)
local seen = {}
eq(#P.near(idx, {x = 100, y = 100, z = 7}, 20, seen), 0, "nothing discoverable within 20")
eq(#P.near(idx, {x = 120, y = 100, z = 7}, 20, seen), 1, "exactly at 20 squares")
eq(#P.near(idx, {x = 119, y = 100, z = 7}, 20, seen), 0, "21 squares: not yet")
eq(#P.near(idx, {x = 140, y = 100, z = 6}, 20, seen), 0, "another floor: no")
eq(#P.near(idx, {x = 140, y = 120, z = 7}, 20, seen), 1, "diagonal (Chebyshev)")
eq(#P.near(idx, {}, 20, seen), 0, "no position")
local found = P.reveal(idx, {x = 150, y = 95, z = 7}, 20, seen)
eq(#found, 1, "revealed"); eq(found[1].k, "hunt", "the hunting area")
eq(#P.reveal(idx, {x = 150, y = 95, z = 7}, 20, seen), 0, "only once")
ok(seen["h008c00647"], "the key is remembered")
-- across cell borders (cells of 32)
local edge = P.index({P.mark("hunt", 64, 64, 7, "edge", 1)})
eq(#P.near(edge, {x = 50, y = 50, z = 7}, 20, {}), 1, "a mark in the next cell")
eq(#P.near(edge, {x = 84, y = 84, z = 7}, 20, {}), 1, "a mark in the cell before")

-- ------------------------------------------------------------------ the discoveries text
local text = P.encodeSeen({h008c00647 = true, B01f401f48 = true})
eq(text, "B01f401f48,h008c00647", "sorted, comma-separated")
local back = P.decodeSeen(text .. ",bad,toolongkey123,,x12")
ok(back.h008c00647 and back.B01f401f48, "round trip"); ok(not back.bad and not back.x12, "junk dropped")
local n = 0
for _ in pairs(back) do
	n = n + 1
end
eq(n, 2, "two keys")
eq(next(P.decodeSeen(nil)), nil, "nothing stored")

-- ------------------------------------------------------------------ the view
local view = P.view(all, {})
eq(#view, 2, "a new character sees the temple and the NPC")
view = P.view(all, seen)
eq(#view, 3, "and what it discovered")
eq(view[1].r, nil, "the view does not tell the reveal flag")
eq(P.npcName(cfg, "Material Broker"), "Material Broker (professions)", "a Chaos NPC, any case")
eq(P.npcName(cfg, "Some Guard"), nil, "not ours")
eq(P.npcName(cfg, "Archivist Odrenna"), "Archivist Odrenna (line spell quests)", "the spell quest NPC is a map mark like the other hub NPCs")

-- ------------------------------------------------------------------ the committed data and the config
local data = dofile("data/chaos_poi.lua")
local loaded, ver = P.load(data)
ok(#loaded > 0 and #loaded == #data.marks, "every committed mark is valid (" .. #loaded .. ")")
ok(#ver == 12, "the committed data has a version")
local kinds, keys, discoverable = {}, {}, 0
for _, mk in ipairs(loaded) do
	kinds[mk.k] = (kinds[mk.k] or 0) + 1
	ok(not keys[P.key(mk)], "one mark per kind and tile: " .. P.key(mk))
	keys[P.key(mk)] = true
	ok(mk.n ~= "", "every mark has a name")
	if mk.r == 1 then
		discoverable = discoverable + 1
	end
	if mk.k == "hunt" or mk.k == "boss" then
		eq(mk.r, 1, "hunting areas and bosses are discovered: " .. mk.n)
	end
	if mk.k == "temple" or mk.k == "depot" or mk.k == "craft" then
		eq(mk.r, 0, "temples, depots, crafting are always shown: " .. mk.n)
	end
end
ok((kinds.temple or 0) > 0 and (kinds.hunt or 0) > 0 and (kinds.depot or 0) > 0, "temples, depots and hunting areas")
ok(#P.encodeSeen(keys) < 16 * 1024, "all discoveries fit in a few KB")
-- the portals' action ids come from the owning systems' configs (no number written twice)
local ids = P.portalIds(cfg.portals, function(file) return dofile("data/scripts/chaos/" .. file) end, _G)
local n = 0
for aid, p in pairs(ids) do
	n = n + 1
	ok(P.KINDS[p.kind] ~= nil, "portal " .. aid .. " has a known kind")
	ok(aid >= 47000 and aid < 48000, "portal " .. aid .. " is a Chaos action id")
end
eq(n, #cfg.portals, "every portal of the config resolves to an action id")
eq(P.dig({a = {b = {c = 5}}}, {"a", "b", "c"}), 5, "dig")
eq(P.dig({a = 1}, {"a", "b"}), nil, "dig through a number")
local partial = P.portalIds({{kind = "portal", name = "x", config = "missing.lua", path = {"aid"}},
	{kind = "nope", name = "y", global = {"G", "id"}}, {kind = "guild", name = "z", global = {"G", "id"}}},
	function() return nil end, {G = {id = 47999}})
ok(partial[47999] and partial[47999].kind == "guild", "a global path; a missing config and an unknown kind are left out")
ok(cfg.revealRange > 0 and cfg.checkMs >= 500, "config")

-- ------------------------------------------------------------------ cost: one reveal check of 1000 characters
local bigIdx = P.index(loaded)
local t0 = os.clock()
local sets = {}
for i = 1, 1000 do
	local mk = loaded[(i % #loaded) + 1]
	sets[i] = sets[i] or {}
	P.reveal(bigIdx, {x = mk.x + 5, y = mk.y, z = mk.z}, cfg.revealRange, sets[i])
end
local ms = (os.clock() - t0) * 1000
print(string.format("reveal check of 1000 characters over %d marks: %.2f ms", #loaded, ms))
ok(ms < 200, "a reveal check stays cheap")

print(string.format("poi_test: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end
