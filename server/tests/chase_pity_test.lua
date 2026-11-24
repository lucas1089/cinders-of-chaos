-- Run from the server/ folder: luajit tests/chase_pity_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- Chase pity (O753): the core rules, the sizing model (tools/chase_pity_model.lua --check: p per source from the configs,
-- n within maxShift), the glue on a mocked player (storage, mult, forced, topUp, record, view) and the hooks of
-- content_rewards.lua (waystone boss, rift guardian) and chaos_item_sets.lua (the forced rift chest) on mocks.
-- server/README.md "Chase pity (O753)".
local checks, fails = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. tostring(what))
	end
end
local function eq(a, b, what)
	ok(a == b, (what or "check") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function near(a, b, tol, what)
	ok(math.abs(a - b) <= tol, (what or "near") .. ": " .. tostring(a) .. " vs " .. tostring(b))
end

dofile("data/scripts/chaos/chase_pity_core.lua")
local K = ChaosChasePityCore
local cfg = dofile("data/scripts/chaos/chase_pity_config.lua")

-- ================================================================ core
local src = {key = "x", n = 10, ramp = 0.5}
eq(K.mult(src, 0), 1, "no miss: x1")
near(K.mult(src, 5), 1.25, 1e-9, "5 of 10 misses: x1.25")
near(K.mult(src, 99), 1 + 0.5 * 9 / 10, 1e-9, "the multiplier stops at the last miss")
ok(not K.forced(src, 8), "the 9th event is not forced")
ok(K.forced(src, 9), "the 10th event is forced")
eq(K.chance(0.2, src, 9), 1, "a forced event is certain")
near(K.chance(0.2, src, 4), 0.2 * 1.2, 1e-9, "the chance rises with the misses")
eq(K.chance(0.9, {n = 10, ramp = 1}, 8), 1, "the chance is capped at 1")
eq(K.nextMisses(src, 4, true), 0, "a drop resets")
eq(K.nextMisses(src, 4, false), 5, "a miss counts")
eq(K.nextMisses(src, 9, false), 9, "the count stops at n - 1")
eq(K.nextMisses(src, -3, false), 1, "a bad count starts at 0")
eq(K.topUp(0.2, src, 0), 0, "no miss: no second roll")
near(K.topUp(0.2, src, 4), (0.24 - 0.2) / 0.8, 1e-9, "the second roll lifts the total to K.chance")
eq(K.topUp(0.2, src, 9), 1, "a forced event: the second roll is certain")
-- the mean: no ramp and n = 1 is one event; a large n is 1 / p
near(K.meanEvents(0.25, 1, 0), 1, 1e-9, "n = 1: one event")
near(K.meanEvents(0.25, 2000, 0), 4, 1e-6, "large n: 1 / p")
near(K.meanEvents(0.25, 4, 0), (1 - 0.75 ^ 4) / 0.25, 1e-9, "a plain guarantee: (1 - q^n) / p")
ok(K.shift(0.25, 4, 0) > K.shift(0.25, 8, 0), "a later guarantee moves the mean less")
ok(K.shift(0.25, 8, 0.5) > K.shift(0.25, 8, 0), "a ramp moves it more")
local n = K.deriveN(0.1, 0.25, 0.10)
ok(n and K.shift(0.1, n, 0.25) <= 0.10 and K.shift(0.1, n - 1, 0.25) > 0.10, "deriveN: the smallest n that holds the limit")
eq(K.deriveN(0, 0.25, 0.1), nil, "no chance: no n")
local pr = K.progress({key = "rift", n = 60}, 37)
eq(pr.text, "37 / 60", "the progress text")
eq(K.progress({key = "rift", n = 60}, 99).done, 60, "the progress stops at n")

-- the config: every source once, a slot inside the block, order names the sources
local slots, keys = {}, {}
for _, s in ipairs(cfg.sources) do
	ok(not keys[s.key], "source " .. s.key .. " once")
	keys[s.key] = true
	ok(not slots[s.slot], "slot " .. s.slot .. " once")
	slots[s.slot] = true
	ok(cfg.storage.base + s.slot <= cfg.storage.last, s.key .. ": the slot is inside the block")
	ok(s.n >= 1 and s.ramp > 0, s.key .. ": n and a ramp (each miss raises the chance)")
	ok(type(s.label) == "string" and s.label ~= "", s.key .. ": a label")
end
eq(#cfg.order, #cfg.sources, "order lists every source")
for _, k in ipairs(cfg.order) do
	ok(keys[k], "order names a source: " .. k)
end
eq(cfg.storage.base, 7106600, "storage block 7106600 - 7106619")

-- ================================================================ the model (the same check as tools/chase_pity_model.lua --check)
local M = dofile("tools/chase_pity_model.lua")
local errors, N = M.check(K, true)
for _, e in ipairs(errors) do
	ok(false, "model: " .. e)
end
ok(N.p.waystone > 0.1 and N.p.guardian > 0.1, "waystone and guardian p from the open uniques")
for _, s in ipairs(cfg.sources) do
	ok(K.shift(N.p[s.key], s.n, s.ramp) <= cfg.maxShift + 1e-9, s.key .. ": the mean chase moves at most 10%")
	ok(K.shift(N.p[s.key], s.n, s.ramp) > 0.05, s.key .. ": and the pity is felt (more than 5%)")
end

-- ================================================================ the glue on a mocked player
Chaos = {t = function(_, k, ...) if select("#", ...) > 0 then return string.format(k, ...) end return k end}
MESSAGE_EVENT_ADVANCE, MESSAGE_INFO_DESCR = 19, 20
local talks = {}
TalkAction = function(words)
	local t = {words = words}
	function t:separator() end
	function t:register() talks[words] = self end
	return t
end
local function newPlayer()
	local p = {st = {}, msgs = {}}
	function p:getStorageValue(k) return self.st[k] or -1 end
	function p:setStorageValue(k, v) self.st[k] = v end
	function p:sendTextMessage(_, text) self.msgs[#self.msgs + 1] = text end
	function p:getGuid() return 7 end
	return p
end
ChaosChasePity = nil
dofile("data/scripts/chaos/chase_pity.lua")
local CP = ChaosChasePity
ok(talks["/chasepity"] ~= nil, "the staff command is registered")
local pl = newPlayer()
local fsrc = K.source(cfg, "fragment")
eq(CP.misses(pl, "fragment"), 0, "a new character has no misses")
eq(CP.mult(pl, "nope"), 1, "an unknown source: x1")
ok(not CP.forced(pl, "nope"), "an unknown source is never forced")
eq(CP.record(pl, "nope", false), 0, "an unknown source records nothing")
for i = 1, fsrc.n - 1 do
	eq(CP.record(pl, "fragment", false, false), i, "miss " .. i)
end
eq(pl.st[cfg.storage.base + fsrc.slot], fsrc.n - 1, "the count is in its storage")
ok(CP.forced(pl, "fragment"), "the n-th clear is forced")
ok(CP.topUp(pl, "fragment", 0.25, function() return 1000000 end), "a forced top-up hits on any roll")
eq(CP.record(pl, "fragment", true, true), 0, "the forced drop resets")
ok(#pl.msgs == 1 and pl.msgs[1]:find("Pinnacle fragment", 1, true), "a forced drop says so")
eq(CP.mult(pl, "fragment"), 1, "after a drop: x1")
ok(not CP.topUp(pl, "fragment", 0.25, function() return 1 end), "no miss: no top-up")
-- the view: every source, then the pinnacle bosses' own count
Chaos.pinnacleConfig = dofile("data/scripts/chaos/pinnacle_config.lua")
local P = Chaos.pinnacleConfig
pl.st[P.storage.base + P.storage.pity + 1] = 3
local view = CP.view(pl)
eq(#view, #cfg.order + #P.bosses, "the view: the sources and the pinnacle bosses")
eq(view[1].k, cfg.order[1], "in the config's order")
eq(view[#cfg.order + 2].d, 3, "the second pinnacle boss: 3 kills without its unique")
eq(view[#cfg.order + 2].n, P.unique.pity, "of its pity")
-- off: nothing changes
cfg.enabled = false
CP.config.enabled = false
eq(CP.mult(pl, "rift"), 1, "off: x1")
eq(CP.record(pl, "rift", false), 0, "off: no count")
eq(pl.st[cfg.storage.base], nil, "off: the storage stays")
CP.config.enabled = true

-- ================================================================ content_rewards.lua: the waystone boss and the rift guardian
do
	local wcfg = dofile("data/scripts/chaos/waystone_tiers_config.lua")
	local G = dofile("data/lib/chaos_gear_sets_items.lua")
	local added, finds = {}, {}
	local L = {
		addToCorpse = function(_, id, n)
			added[#added + 1] = {id = id, n = n}
			local item = {}
			function item:setCustomAttribute() end
			return item, n
		end,
		rollUniques = function(_, _, _, find)
			finds[#finds + 1] = find
			if find >= (CP.config.forceFind or 1000000) then
				return {{id = 4242, name = "Forced Unique"}}
			end
			return {}
		end
	}
	ChaosGearSets = {items = G}
	local entry = {run = 1, boss = true}
	ChaosWaystoneTiers = {config = wcfg, entryOf = function() return entry end, addWaystone = function() end}
	ChaosWaystoneMods = {lootMult = function() return 1 end}
	ChaosContentRewards = nil
	ChaosMakeUnique = nil
	dofile("data/scripts/chaos/content_rewards.lua")
	local CRe = ChaosContentRewards
	local monster = {getMaster = function() return nil end, getName = function() return "Test" end}
	local owner = newPlayer()
	local ctx = {tier = "boss", orbLevel = 1100, itemFind = 1}
	local wsrc = K.source(cfg, "waystone")
	local function forcedCount()
		local c = 0
		for _, a in ipairs(added) do
			if a.id == 4242 then c = c + 1 end
		end
		return c
	end
	for i = 1, wsrc.n - 1 do
		CRe.onKill(monster, {}, owner, ctx, L, {})
		eq(CP.misses(owner, "waystone"), i, "waystone boss " .. i .. " without a unique counts")
	end
	eq(forcedCount(), 0, "no forced unique before the n-th boss")
	local before = #finds
	CRe.onKill(monster, {}, owner, ctx, L, {})
	eq(forcedCount(), 1, "the n-th waystone boss leaves a unique")
	eq(CP.misses(owner, "waystone"), 0, "and the count starts again")
	ok(#finds > before and finds[before + 1] > 3 * 1, "the rolls of a boss after misses carry the raised item find")
	-- the rift guardian has its own count
	ChaosWaystoneTiers.entryOf = function() return nil end
	ChaosRift = {contentOf = function() return {tier = 15, quantity = 1, guardian = true, omen = false} end}
	CRe.onKill(monster, {}, owner, ctx, L, {})
	eq(CP.misses(owner, "guardian"), 1, "a rift guardian without a unique counts on its own source")
	eq(CP.misses(owner, "waystone"), 0, "not on the waystone one")
	-- no owner (a corpse nobody owns): no count, no error
	CRe.onKill(monster, {}, nil, ctx, L, {})
	eq(CP.misses(owner, "guardian"), 1, "no owner: nothing counted")
end

-- ================================================================ chaos_item_sets.lua: a forced chest drops a piece of an eligible set
do
	ChaosItemSets = nil
	dofile("data/lib/chaos_item_sets.lua")
	local S = ChaosItemSets
	S.load()
	local theme, set
	for _, s in ipairs(S.sets) do
		local r = s.sources and s.sources.rift
		if r then
			theme, set = r.theme, s
			break
		end
	end
	ok(theme ~= nil, "a set drops from a rift theme")
	if theme then
		local ctx = {tier = set.sources.rift.minTier, level = set.level, itemFind = 1}
		ok(S.rollChase("rift", theme, ctx, function(a, b) return b end) == nil, "a plain chest at the worst roll: no piece")
		ctx.force = true
		local hit = S.rollChase("rift", theme, ctx, function(a, b) return b end)
		ok(hit ~= nil, "a forced chest at the worst roll: a piece")
		ok(S.rollChase("rift", "no such theme", ctx, function(a, b) return a end) == nil, "forced, no eligible set: nothing")
	end
end

print(string.format("chase_pity_test: %d checks, %d failures", checks, fails))
os.exit(fails == 0 and 0 or 1)
