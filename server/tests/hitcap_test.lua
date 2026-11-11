-- Run from the server/ folder: luajit tests/hitcap_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- O483: the pure rules of hitcap_core.lua: the pool, the cut of one hit (the rule of the rift guardian cap, O478), the registry
-- of cap sources, the Reflective amount with its per-hit and per-second caps and the one second window. The configs that
-- carry the numbers (rift_config.lua guardian.hitCap, nemesis_config.lua hitCap, monster_tiers.lua reflectCap) are read as well.
local checks, fails = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. tostring(what))
	end
end
local function eq(a, b, what)
	ok(a == b, tostring(what) .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

dofile("data/scripts/chaos/hitcap_core.lua")
local H, S = ChaosHitCapCore, ChaosHitCap

-- ------------------------------------------------------------------ pool
eq(H.pool(1000, 500, false), 1000, "no mana shield: the health")
eq(H.pool(1000, 500, true), 1500, "a mana shield up: health plus mana")
eq(H.pool(nil, nil, true), 0, "nothing known: 0")
eq(H.pool(-5, 100, true), 100, "a negative health counts as 0")

-- ------------------------------------------------------------------ cut (the O478 cases, with the share given)
do
	local p, s, limit, capped = H.cut(0.6, -500, 0, 1000, 0)
	ok(not capped and p == -500 and s == 0 and limit == 600, "under: untouched, limit 600")
	p, s, limit, capped = H.cut(0.6, -600, 0, 1000, 0)
	ok(not capped and p == -600, "exactly at the limit: untouched")
	p, s, limit, capped = H.cut(0.6, -601, 0, 1000, 0)
	ok(capped and p == -600 and s == 0, "one over: cut to 600")
	p, s, limit, capped = H.cut(0.6, -3000, -1000, 1000, 0)
	ok(capped and p == -450 and s == -150 and math.abs(p) + math.abs(s) <= 600, "two parts keep their ratio")
	p, s, limit, capped = H.cut(0.6, 4000, 0, 1000, 0)
	ok(capped and p == 600, "a positive magnitude is cut the same")
	p, s, limit, capped = H.cut(0.6, -400, 0, 1000, 300)
	ok(capped and p == -300 and limit == 300, "what an earlier part took counts: 600 - 300")
	p, s, limit, capped = H.cut(0.6, -100, 0, 1000, 700)
	ok(capped and p == 0 and limit == 0, "an earlier part over the ceiling leaves nothing")
	p, s, limit, capped = H.cut(0.6, -9999, 0, 0, 0)
	ok(not capped and p == -9999 and limit == nil, "no pool known: untouched")
	p, s, limit, capped = H.cut(nil, -9999, 0, 1000, 0)
	ok(not capped and p == -9999, "no share: untouched")
	p, s = H.cut(0.6, nil, nil, 1000, nil)
	ok(p == 0 and s == 0, "nil parts are 0")
	-- never raised
	p, s, limit, capped = H.cut(0.6, -1, 0, 1000, 0)
	ok(not capped and p == -1, "a small hit is never raised")
	-- the sum is at most the limit for odd numbers
	for _, v in ipairs({{-1001, -777}, {-99999, -1}, {-3, -999}}) do
		local a, b, lim = H.cut(0.6, v[1], v[2], 1234, 11)
		ok(math.abs(a) + math.abs(b) <= lim, "odd numbers: the sum is at most the limit " .. v[1] .. "/" .. v[2])
	end
end

-- ------------------------------------------------------------------ the numbers of the configs
do
	local rift = dofile("data/scripts/chaos/rift_config.lua")
	eq(rift.guardian.hitCap.share, 0.60, "the guardian share stays 0.60")
	ok(rift.guardian.hitCap.enabled == true, "the guardian cap is on")
	local nem = dofile("data/scripts/chaos/nemesis_config.lua")
	ok(nem.hitCap and nem.hitCap.enabled == true, "the Nemesis cap is on")
	eq(nem.hitCap.share, 0.60, "the Nemesis share is 0.60")
end

-- ------------------------------------------------------------------ sources
do
	local a, b, c = {name = "a"}, {name = "b"}, {name = "c"}
	S.setSource("zz_one", function(att) if att == a then return 0.6 end end)
	S.setSource("zz_two", function(att) if att == b then return 0.4 end if att == a then return 0.5 end end)
	S.setSource("zz_bad", function() error("boom") end)
	eq(S.shareOf(a, nil), 0.5, "the smallest share wins")
	eq(S.shareOf(b, nil), 0.4, "a source of its own")
	eq(S.shareOf(c, nil), nil, "nobody caps an unknown attacker")
	local n = #S.order
	S.setSource("zz_one", function(att) if att == a then return 0.3 end end)
	eq(#S.order, n, "a second registration with the same key replaces it (a reload adds nothing)")
	eq(S.shareOf(a, nil), 0.3, "the replaced function is the one asked")
	-- the victim is passed on
	local seen
	S.setSource("zz_two", function(att, victim) seen = victim return nil end)
	S.shareOf(a, "victim")
	eq(seen, "victim", "the victim is handed to the source")
	-- a second load of the core keeps the registry
	dofile("data/scripts/chaos/hitcap_core.lua")
	eq(#S.order, n, "a second dofile keeps the registry")
	for _, k in ipairs({"zz_one", "zz_two", "zz_bad"}) do
		S.sources[k] = nil
	end
	for i = #S.order, 1, -1 do
		if S.order[i]:find("^zz_") then table.remove(S.order, i) end
	end
end

-- ------------------------------------------------------------------ reflect
do
	local cap = {enabled = true, perHit = 0.10, perSecond = 0.25}
	local R = H.reflectAmount
	eq(R(0.15, cap, 400, 1000, 10000, 0), 60, "15% of a 400 hit, far under the caps")
	eq(R(0.15, cap, 30000, 1000, 10000, 0), 150, "overkill is not reflected: 15% of the 1000 health that was left")
	eq(R(0.15, cap, 30000, 100000, 10000, 0), 1000, "per hit: 10% of a 10000 pool, not 15% of 30000")
	eq(R(0.15, cap, 100000, 100000, 10000, 0), 1000, "a 100k hit comes back as the same 1000")
	eq(R(0.15, cap, 100000, 100000, 3035, 0), 303, "a 3035 pool: 303 back for one hit")
	eq(R(0.15, cap, 30000, 100000, 10000, 1500), 1000, "under the per second room (2500 - 1500 = 1000)")
	eq(R(0.15, cap, 30000, 100000, 10000, 2000), 500, "per second: 2500 - 2000 left")
	eq(R(0.15, cap, 30000, 100000, 10000, 2500), 0, "per second: the room is spent")
	eq(R(0.15, cap, 30000, 100000, 10000, 9000), 0, "per second: never below 0")
	eq(R(0.15, cap, 6, 1000, 10000, 0), 0, "a hit that rounds to nothing")
	eq(R(0.15, cap, -400, 1000, 10000, 0), 60, "a negative hit is counted by its size")
	eq(R(0.15, cap, 400, -50, 10000, 0), 0, "a monster with no health left reflects nothing")
	eq(R(0.15, cap, 30000, 100000, 0, 0), 4500, "no pool known: not cut")
	eq(R(0.15, nil, 30000, 100000, 10000, 0), 4500, "no cap table: not cut")
	eq(R(0.15, {enabled = false, perHit = 0.1, perSecond = 0.25}, 30000, 100000, 10000, 0), 4500, "switched off: not cut")
	eq(R(0, cap, 30000, 100000, 10000, 0), 0, "a share of 0 reflects nothing")
	-- the cap is a ceiling only: it never raises
	for _, landed in ipairs({1, 50, 399, 400, 5000, 70000}) do
		local raw = R(0.15, {enabled = false}, landed, 60000, 10000, 0)
		ok(R(0.15, cap, landed, 60000, 10000, 0) <= raw, "never above the plain amount at " .. landed)
	end
	-- a pool with a mana shield is bigger: the same hit comes back bigger, up to the ceiling
	eq(R(0.15, cap, 100000, 100000, H.pool(10000, 5000, true), 0), 1500, "mana shield up: 10% of 15000")
end

-- ------------------------------------------------------------------ the one second window
do
	local list = {}
	eq(H.spentIn(list, 1000, 1000), 0, "empty: 0")
	H.spend(list, 1000, 300)
	H.spend(list, 1400, 200)
	H.spend(list, 1500, 0)
	eq(#list, 2, "a 0 is not recorded")
	eq(H.spentIn(list, 1500, 1000), 500, "both inside the second")
	eq(H.spentIn(list, 1999, 1000), 500, "the first one is 999 ms old: still in")
	eq(H.spentIn(list, 2000, 1000), 200, "the first one is 1000 ms old: out")
	eq(#list, 1, "and dropped")
	eq(H.spentIn(list, 2401, 1000), 0, "all out")
	eq(#list, 0, "the list is empty")
	-- the rule over a burst of hits: at most perSecond x pool in the second, however many hits
	local cap = {enabled = true, perHit = 0.10, perSecond = 0.25}
	local pool, total = 10000, 0
	local l2 = {}
	for i = 0, 19 do
		local now = 5000 + i * 40 -- 20 hits in 760 ms
		local back = H.reflectAmount(0.15, cap, 100000, 100000, pool, H.spentIn(l2, now, 1000))
		H.spend(l2, now, back)
		total = total + back
	end
	eq(total, 2500, "20 big hits in under a second: 25% of the pool in all")
	-- a second later the room is back
	local now = 5000 + 20 * 40 + 300
	eq(H.reflectAmount(0.15, cap, 100000, 100000, pool, H.spentIn(l2, now, 1000)), 1000, "a second later: a full per hit amount again")
end

print(string.format("hitcap_test: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end
