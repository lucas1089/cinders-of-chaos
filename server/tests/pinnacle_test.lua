-- Run from the server/ folder: luajit tests/pinnacle_test.lua (and lua5.3; CI runs both)
-- Pinnacle bosses (O667): the pure rules (pinnacle_core.lua) with the real pinnacle_config.lua (the four bosses, the fragments and where
-- they come from, the set, the party and damage curves, the exclusive unique and its bad-luck count, the season bits and the titles), the
-- storage block, the modal ids and the arena grid clear of the other runtime areas; the monsters and the profiles of the four bosses;
-- then pinnacle.lua against a mocked engine: the hooks (a sealed rift, an Omen guardian, the waystone tiers' hook, read from a guarded
-- call), the Keeper's window answers (Open spends the set before anyone moves, Focus), a solo fight and a party fight (members pay no
-- set), the boss's health and its mechanics factor, the damage curve, a lethal hit (caught, the fight is no longer deathless), the kill
-- (tokens, orbs, the unique, the titles), a logout (no refund), a restart and a crash (the set comes back), the pt-BR texts.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
loadstring = loadstring or load
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/uber_core.lua")
dofile("data/scripts/chaos/pinnacle_core.lua")
local K = ChaosPinnacleCore
local U = ChaosUberCore
local cfg = dofile("data/scripts/chaos/pinnacle_config.lua")
local pt = dofile("data/scripts/chaos/i18n_strings.lua")["pt-BR"]
dofile("data/lib/chaos_unique_specs.lua")
dofile("data/lib/chaos_unique_items.lua")

local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end
local function ok(v, m)
	eq(not not v, true, m)
end
-- a fixed random source: rand(a, b) -> a..b from a list of fractions
local function fixed(list)
	local i = 0
	return function(a, b)
		i = i % #list + 1
		local f = list[i]
		if b == nil then
			a, b = 1, a
		end
		return math.min(b, a + math.floor(f * (b - a + 1)))
	end
end
local function readFile(path)
	local f = assert(io.open(path, "rb"))
	local t = f:read("*a")
	f:close()
	return t
end

-- ====================================================================== the bosses
eq(#cfg.bosses, 4, "four bosses")
local levels, names, uniqueIds = {}, {}, {}
for i, b in ipairs(cfg.bosses) do
	levels[i] = b.level
	names[b.name] = true
	eq(#b.fragments, 4, b.key .. ": four fragment kinds")
	ok(b.minLevel <= b.refLevel, b.key .. ": the level that opens it is not above the planned one")
	ok(b.health > 0 and b.perExtra > 0, b.key .. ": health and a party curve")
	ok(not uniqueIds[b.unique.id], b.key .. ": its own unique base")
	uniqueIds[b.unique.id] = true
	-- the monster file and the profile of its name
	local xml = readFile("data/monster/monsters/chaos/pinnacle/" .. b.name:lower():gsub(" ", "_") .. ".xml")
	eq(xml:match('<monster name="([^"]+)"'), b.name, b.key .. ": the monster file is named after the boss")
	eq(tonumber(xml:match('<health now="(%d+)"')), b.health, b.key .. ": the XML health is the fight's")
	ok(xml:find('isboss="1"', 1, true), b.key .. ": a boss")
	ok(not xml:find("<loot>", 1, true), b.key .. ": no loot of its own")
	-- the unique: in the drop table, listing the boss
	local found
	for _, e in ipairs(ChaosUniqueItems) do
		if e.name == b.unique.name then
			found = e
		end
	end
	ok(found, b.key .. ": the unique is in the drop table")
	if found then
		eq(found.id, b.unique.id, b.key .. ": the unique's base id")
		eq(found.monsters[1], b.name, b.key .. ": the unique lists the boss")
		ok(found.bossOnly, b.key .. ": boss only")
		ok(found.pinnacle, b.key .. ": marked")
	end
end
eq(table.concat(levels, ","), "1900,2100,2300,2500", "shown at 1900 / 2100 / 2300 / 2500 (the player cap is 2500, O672)")
for _, b in ipairs(cfg.bosses) do
	ok(b.level <= 2500 and b.refLevel <= 2500 and b.minLevel <= 2500, b.key .. ": no level above the player cap 2500 (O672)")
end
local mech = dofile("data/scripts/chaos/boss_mechanics_config.lua")
for _, b in ipairs(cfg.bosses) do
	local p = mech.profiles[b.name:lower()]
	ok(p and p.ref, b.key .. ": a mechanics profile with a ref")
	if p then
		ok(#(p.telegraphs or {}) >= 2, b.key .. ": telegraphs")
		eq(p.ref.health, b.health, b.key .. ": the profile's ref is the fight's health")
	end
end
-- titles stay inside the plate's 24 characters, whatever the season
for _, b in ipairs(cfg.bosses) do
	for _, t in ipairs(K.titleList(cfg, b, 2 ^ 30 - 1, 1, nil, 0)) do
		ok(#t.text <= 24, t.text .. " fits the plate")
	end
end

-- ====================================================================== storage, modal ids, the arena grid
local lo, hi = cfg.storage.base, cfg.storage.base + 59
eq(lo, 7106400, "the block starts at 7106400")
for off = 0, 38 do
	ok(cfg.storage.base + off >= lo and cfg.storage.base + off <= hi, "offset " .. off .. " inside the block")
end
ok(cfg.storage.base + cfg.storage.deathless + 3 < cfg.storage.base + cfg.storage.kills, "rows do not overlap")
ok(cfg.storage.base + cfg.storage.frag + 15 < cfg.storage.base + cfg.storage.focus, "fragments end before the focus")
-- no other config or constant uses a number of the block, nor the modal ids
local function scan(v, seen, found)
	if type(v) == "number" then
		if v >= lo and v <= hi then
			found[#found + 1] = v
		end
	elseif type(v) == "table" and not seen[v] then
		seen[v] = true
		for _, x in pairs(v) do
			scan(x, seen, found)
		end
	end
end
local found = {}
scan(Chaos.storage, {}, found)
eq(#found, 0, "no Chaos.storage key inside 7106400-7106459")
local modalIds = {[cfg.modal.list] = true}
local f = io.popen("ls data/scripts/chaos/*_config.lua")
for path in f:lines() do
	if not path:find("pinnacle_config", 1, true) then
		local text = readFile(path)
		for line in text:gmatch("[^\n]+") do
			if line:lower():find("modal", 1, true) then
				for id in pairs(modalIds) do
					ok(not line:find("%f[%w]" .. id .. "%f[%W]"), path .. " names a modal window with the number " .. id)
				end
			end
		end
		ok(not text:find("7106[4-5]%d%d"), path .. " does not use a storage key of the block")
	end
end
f:close()
ok(not readFile("data/scripts/chaos/chaos_constants.lua"):find("7106[4-5]%d%d"), "chaos_constants.lua does not use the block")

local g = cfg.grid
local x1, y1 = g.origin.x, g.origin.y
local x2, y2 = x1 + g.cols * g.spacing - 1, y1 + math.ceil(g.slots / g.cols) * g.spacing - 1
local others = {
	{"guild boss", dofile("data/scripts/chaos/guildboss_config.lua").grid},
	{"pocket boss", dofile("data/scripts/chaos/pocketboss_config.lua").grid},
	{"raid", {origin = {x = 10400, y = 10000}, cols = 2, slots = 4, spacing = 256}},
	{"descent", {origin = {x = 10000, y = 10000}, cols = 4, slots = 8, spacing = 64}},
	{"battleground", dofile("data/scripts/chaos/battleground_config.lua").grid},
	{"hideouts", {origin = {x = 12288, y = 12288}, cols = 16, slots = 256, spacing = 32}}
}
for _, o in ipairs(others) do
	local og = o[2]
	local ox1, oy1 = og.origin.x, og.origin.y
	local ox2 = ox1 + og.cols * og.spacing - 1
	local oy2 = oy1 + math.ceil((og.slots or (og.cols * (og.rows or 1))) / og.cols) * og.spacing - 1
	ok(x2 < ox1 or x1 > ox2 or y2 < oy1 or y1 > oy2, "grid clear of the " .. o[1])
end
for slot = 1, g.slots do
	local L = U.layout(cfg, slot)
	for _, list in ipairs({L.floorList, L.anteList, L.wallList}) do
		for _, t in ipairs(list) do
			if U.slotAt(cfg, t) ~= slot then
				error("slot " .. slot .. ": tile " .. t.x .. "," .. t.y .. " outside its cell")
			end
		end
	end
end
checks = checks + 1
local aids = {}
for _, p in ipairs({"pocketboss", "guildboss", "uber"}) do
	aids[dofile("data/scripts/chaos/" .. p .. "_config.lua").portalActionId] = true
end
ok(not aids[cfg.portalActionId], "the way out has an action id of its own")
ok(cfg.portalActionId >= 47630 and cfg.portalActionId <= 47639, "47630-47639")

-- ====================================================================== fragments: have, sources, drops
local index = K.index(cfg)
eq(#index.list, 4, "index")
eq(index.byKey.talath.index, 3, "index of Talath")
local store = {}
local function read(key)
	return store[key] or -1
end
eq(K.fragKey(cfg, 1, 1), 7106400, "first fragment key")
eq(K.fragKey(cfg, 4, 4), 7106415, "last fragment key")
local have = K.have(cfg, read, 2)
eq(have[1] + have[2] + have[3] + have[4], 0, "an unset storage (-1) is none")
ok(not K.setReady(have), "no set")
eq(#K.missing(have), 4, "four missing")
store[K.fragKey(cfg, 2, 1)] = 2
store[K.fragKey(cfg, 2, 2)] = 1
store[K.fragKey(cfg, 2, 3)] = 1
store[K.fragKey(cfg, 2, 4)] = 1
ok(K.setReady(K.have(cfg, read, 2)), "a whole set")
eq(K.have(cfg, read, 2)[1], 2, "counts")
eq(K.addFragment(cfg, 5, 1), 6, "added")
local capped, added = K.addFragment(cfg, cfg.fragments.cap, 1)
eq(capped, cfg.fragments.cap, "the cap holds")
eq(added, false, "not added over the cap")

-- the sources
local src = cfg.fragments.sources
eq(K.sourceOf(cfg, "waystone", {tier = src.waystone.minTier - 1}), nil, "a waystone tier under the minimum")
ok(K.sourceOf(cfg, "waystone", {tier = src.waystone.minTier}), "a waystone tier at the minimum")
ok(K.sourceOf(cfg, "waystone", {tier = 15}), "the top waystone tier")
eq(K.sourceOf(cfg, "rift", {tier = 14}), nil, "a rift of tier 14")
ok(K.sourceOf(cfg, "rift", {tier = 15}), "a rift of tier 15")
eq(K.sourceOf(cfg, "rift", {tier = 15, omen = true}), nil, "an Omen guardian is no rift source")
ok(K.sourceOf(cfg, "omen", {omen = true}), "an Omen guardian")
eq(K.sourceOf(cfg, "omen", {}), nil, "no omen, no source")
eq(K.sourceOf(cfg, "nothing", {}), nil, "an unknown source")
eq(src.waystone.kind, 1, "waystone drops kind 1")
eq(src.rift.kind, 2, "rift drops kind 2")
eq(src.omen.kind, 3, "omen drops kind 3")

-- which boss a level opens
eq(#K.openBosses(cfg, 1000), 0, "a low level opens none")
eq(#K.openBosses(cfg, 1800), 1, "1800 opens the first")
eq(#K.openBosses(cfg, 2500), 4, "2500 opens all four")
eq(K.dropBoss(cfg, 1000, 0, fixed({0})), nil, "no fragment under every minimum")
eq(K.dropBoss(cfg, 2500, 3, fixed({0})), 3, "the focus when it is open")
eq(K.dropBoss(cfg, 1950, 3, fixed({0})), 1, "a focus the level does not open: a boss it opens")
eq(K.dropBoss(cfg, 2500, 0, fixed({0.99})), 4, "no focus: at random")
-- a clear: each roll on its own
local r = K.rollClear(cfg, "rift", {tier = 15}, 2500, 2, fixed({0, 0}))
eq(#r, 2, "both rolls hit")
eq(r[1].kind, 2, "the rift's own kind")
eq(r[1].boss, 2, "of the focus")
eq(r[2].kind, 4, "and the keystone")
r = K.rollClear(cfg, "rift", {tier = 15}, 2500, 2, fixed({0.5, 0.5}))
eq(#r, 0, "both rolls miss")
r = K.rollClear(cfg, "omen", {omen = true}, 2500, 1, fixed({0.1, 0.9}))
eq(#r, 1, "only the own kind")
eq(r[1].kind, 3, "the Omen kind")
eq(#K.rollClear(cfg, "waystone", {tier = 5}, 2500, 1, fixed({0})), 0, "a low waystone tier gives nothing")
-- O671: the opener's Endgame Atlas rank (fragmentChance, percent points) adds to the waystone's own kind and to no other source
local base = src.waystone.chance
eq(#K.rollClear(cfg, "waystone", {tier = 15}, 2500, 2, fixed({(base + 1) / 100 + 0.0001, 0.99})), 0, "just over the waystone's chance: a miss")
eq(#K.rollClear(cfg, "waystone", {tier = 15, fragmentChance = 8}, 2500, 2, fixed({(base + 1) / 100 + 0.0001, 0.99})), 1, "the atlas rank lifts the same roll to a hit")
eq(#K.rollClear(cfg, "rift", {tier = 15, fragmentChance = 8}, 2500, 2, fixed({(src.rift.chance + 1) / 100 + 0.0001, 0.99})), 0, "and no other source")
eq(#K.rollClear(cfg, "rift", {tier = 15}, 800, 0, fixed({0})), 0, "a low level gives nothing")
-- the rates over many clears
math.randomseed(7)
local sample = function(source, info)
	local own, any = 0, 0
	for _ = 1, 20000 do
		for _, x in ipairs(K.rollClear(cfg, source, info, 2500, 1, math.random)) do
			if x.kind == 4 then
				any = any + 1
			else
				own = own + 1
			end
		end
	end
	return own / 20000, any / 20000
end
local own, any = sample("rift", {tier = 15})
ok(math.abs(own - src.rift.chance / 100) < 0.02, "the rift kind comes at its chance: " .. own)
ok(math.abs(any - src.rift.anyChance / 100) < 0.01, "the keystone comes at its chance: " .. any)

-- ====================================================================== scaling and entering
eq(K.scale(cfg.damage, 1), 1, "solo damage")
ok(math.abs(K.scale(cfg.damage, 5) - 1.24) < 1e-9, "five: x1.24")
eq(K.scale({solo = 1, perExtra = 1, max = 2}, 5), 2, "the max")
for _, b in ipairs(cfg.bosses) do
	eq(K.bossHealth(b, 1), b.health, b.key .. ": solo health")
	eq(K.bossHealth(b, 5), math.floor(b.health * (1 + 4 * b.perExtra) + 0.5), b.key .. ": health for five")
	ok(K.bossHealth(b, 5) > 3 * K.bossHealth(b, 1), b.key .. ": a party fight is a bigger bar")
end
local boss = index.list[1]
local info = {enabled = true, boss = boss, level = 2000, needPz = true, pz = true, inFight = false, cooldown = 0, have = {1, 1, 1, 1}}
eq(K.enterError(info), nil, "a whole set opens it")
local function why(mod)
	local i = {}
	for k, v in pairs(info) do
		i[k] = v
	end
	for k, v in pairs(mod) do
		i[k] = v
	end
	if mod.boss == false then
		i.boss = nil
	end
	return K.enterError(i)
end
eq(why({enabled = false})[1], "The pinnacle bosses are closed for now.", "closed")
eq(why({boss = false})[1], "There is no such pinnacle boss.", "no such boss")
eq(why({level = 100})[1], "%s opens from level %d.", "level")
eq(why({instance = "a rift"})[1], "You are in %s already.", "in an instance")
eq(why({pz = false})[1], "Open it from a protection zone.", "protection zone")
eq(why({inFight = true})[1], "You cannot open it in a fight.", "in a fight")
eq(why({cooldown = 4})[1], "Wait %d seconds before you open another.", "cooldown")
local miss = why({have = {1, 0, 1, 0}})
eq(miss[1], "The set is not whole. Missing: %s.", "an incomplete set")
eq(miss[2], boss.fragments[2] .. ", " .. boss.fragments[4], "names the missing kinds")
eq(K.memberError({boss = boss, level = 2000}), nil, "a member")
eq(K.memberError({boss = boss, level = 100})[1], "level %d is needed", "member level")
eq(K.memberError({boss = boss, level = 2000, far = true})[1], "too far", "member far")
eq(K.memberError({boss = boss, level = 2000, inFight = true})[1], "in a fight", "member fight")
eq(K.memberError({boss = boss, level = 2000, instance = "a rift"})[1], "in %s", "member instance")
-- every reason has a pt-BR text
for _, w in ipairs({why({enabled = false}), why({level = 1}), why({instance = "x"}), why({pz = false}), why({inFight = true}),
		why({cooldown = 1}), miss, K.T("in a fight"), K.T("too far"), K.T("level %d is needed", 1), K.T("in %s", "x"), K.T("the arena is full")}) do
	ok(pt[w[1]], "pt-BR for: " .. w[1])
end

-- ====================================================================== seasons, titles, the unique
eq(K.seasonBit(1), 1, "season 1 is bit 1")
eq(K.seasonBit(31), 1, "bits wrap at 30")
eq(K.seasonBit(nil), 0, "no season is bit 0")
local mask = 0
ok(not K.hasBit(mask, 3), "no bit")
mask = K.setBit(mask, 3)
ok(K.hasBit(mask, 3) and not K.hasBit(mask, 2), "bit 3")
eq(K.setBit(mask, 3), mask, "setting again changes nothing")
mask = K.setBit(mask, 29)
ok(K.hasBit(mask, 29) and K.hasBit(mask, 3), "bit 29 too")
ok(mask < 2 ^ 31, "a signed 32 bit storage holds it")
eq(math.type and math.type(mask) or "integer", "integer", "an integer for the storage")
local tl = K.titleList(cfg, index.list[2], K.setBit(0, 2), 0, nil, 5)
eq(#tl, 1, "one season title")
eq(tl[1].text, "Vhoss Bane [S2]", "the first-kill title")
eq(tl[1].key, "pinnacle:vhoss:s2", "its key")
tl = K.titleList(cfg, index.list[2], K.setBit(K.setBit(0, 2), 3), 1, {[3] = "[S3b]"}, 5)
eq(#tl, 3, "two seasons and the deathless title")
eq(tl[3].text, "Deathless Vhoss", "the deathless title")
eq(K.titleList(cfg, index.list[2], 0, 0, nil, 0)[1], nil, "nothing before a kill")
-- the unique: a roll, then the bad-luck count
local drop, pity = K.uniqueRoll(cfg, 0, 1, fixed({0}))
eq(drop, true, "a good roll drops it")
eq(pity, 0, "and resets the count")
drop, pity = K.uniqueRoll(cfg, 0, 1, fixed({0.99}))
eq(drop, false, "a bad roll")
eq(pity, 1, "counts one")
drop, pity = K.uniqueRoll(cfg, cfg.unique.pity - 1, 1, fixed({0.99}))
eq(drop, true, "the kill the bad-luck count names always drops it")
eq(pity, 0, "reset")
drop = K.uniqueRoll(cfg, cfg.unique.pity - 2, 1, fixed({0.99}))
eq(drop, false, "one kill earlier it does not")
-- the item find raises the chance, capped
local hits = 0
math.randomseed(3)
for _ = 1, 20000 do
	if K.uniqueRoll(cfg, 0, 10, math.random) then
		hits = hits + 1
	end
end
ok(math.abs(hits / 20000 - cfg.unique.chance * cfg.unique.itemFindCap / 100) < 0.02, "the item find is capped: " .. hits / 20000)
-- the expected kills match the model's formula
local total, kills = 0, 20000
math.randomseed(5)
for _ = 1, kills do
	local k, p = 0, 0
	repeat
		k = k + 1
		local d
		d, p = K.uniqueRoll(cfg, p, 1, math.random)
	until d
	total = total + k
end
local p0 = cfg.unique.chance / 100
local expect = (1 - (1 - p0) ^ cfg.unique.pity) / p0
ok(math.abs(total / kills - expect) < 0.1, string.format("kills to the unique: %.2f, the model says %.2f", total / kills, expect))
local rw = K.reward(cfg, boss)
eq(rw.tokens, boss.tokens, "tokens")
eq(rw.chaos, boss.orbs.chaos, "orbs")
ok(K.clockText(125) == "2:05", "clock")

-- ====================================================================== pinnacle.lua against a mocked engine
local NOW = 1700000000
os.time = (function(orig)
	return function(t)
		if t then
			return orig(t)
		end
		return NOW
	end
end)(os.time)
os.mtime = function() return NOW * 1000 end
local registry = {}
local function event(kind)
	return function(name)
		local ev = {name = name}
		function ev.register() registry[name or kind] = ev end
		function ev.separator() end
		function ev.aid() end
		function ev.type() end
		return ev
	end
end
CreatureEvent, GlobalEvent, TalkAction, MoveEvent = event("c"), event("g"), event("t"), event("m")
local events = {}
function addEvent(fn, ms, ...)
	events[#events + 1] = {fn = fn, ms = ms, args = {...}, at = NOW * 1000 + (ms or 0)}
end
local function runEvents(untilMs)
	local guard = 0
	while true do
		local best, bi
		for i, e in ipairs(events) do
			if e.at <= untilMs and (not best or e.at < best.at) then
				best, bi = e, i
			end
		end
		if not best then
			return
		end
		table.remove(events, bi)
		guard = guard + 1
		if guard > 100000 then
			error("event loop")
		end
		NOW = math.max(NOW, math.floor(best.at / 1000))
		best.fn((table.unpack or unpack)(best.args))
	end
end
local function advance(secs)
	NOW = NOW + secs
	runEvents(NOW * 1000)
end
local function pos(x, y, z)
	return {x = x, y = y, z = z, sendMagicEffect = function() end}
end
Position = pos
local tiles = {}
Tile = function(p)
	return tiles[p.x .. "," .. p.y .. "," .. p.z]
end
local monsters = {}
local nextMid = 5000
local function newMonster(name, p)
	nextMid = nextMid + 1
	-- the spawn registers the natural tier roll of monster_tiers.lua (a boss rolls 4-5 modifiers, Regenerating and Vampiric heal it)
	local m = {id = nextMid, name = name, hp = 1000000, maxHp = 1000000, pos = p,
		events = {ChaosTierRollMagic = true, ChaosTierRollRare = true, ChaosTierRollLegendary = true, ChaosTierRollBoss = true}}
	function m:unregisterEvent(e) self.events[e] = nil end
	function m:getId() return self.id end
	function m:getName() return self.name end
	function m:isMonster() return true end
	function m:isPlayer() return false end
	function m:getMaster() return nil end
	function m:getHealth() return self.hp end
	function m:getMaxHealth() return self.maxHp end
	function m:setMaxHealth(v) self.maxHp = v end
	function m:addHealth(kind, v)   -- this engine: (damage type, amount); a one-argument addHealth(amount) does nothing (chaos_constants.lua Chaos.heal)
		if type(kind) == "string" and type(v) == "number" then
			self.hp = math.min(self.maxHp, self.hp + v)
		end
	end
	function m:getPosition() return self.pos end
	function m:registerEvent(e) self.events[e] = true end
	function m:getTarget() return {} end
	function m:teleportTo(p2) self.pos = p2 end
	function m:remove() monsters[self.id] = nil end
	monsters[m.id] = m
	return m
end
Monster = function(id) return monsters[id] end
local created = {}
local madeUniques = {}
Game = {
	createTile = function(p)
		local t = {items = {}, creatures = {}}
		function t:getGround() return self.ground end
		function t:getItemById() return nil end
		function t:getItems() return {} end
		function t:getCreatures() return {} end
		function t:hasFlag() return false end
		tiles[p.x .. "," .. p.y .. "," .. p.z] = t
		return t
	end,
	createItem = function(id, count, p)
		if p then
			local t = tiles[p.x .. "," .. p.y .. "," .. p.z]
			if t and not t.ground then
				t.ground = id
			end
		end
		return {setActionId = function() end, getId = function() return id end}
	end,
	createMonster = function(name, p)
		local m = newMonster(name, p)
		m.spawnLevel = Chaos.spawnLevel
		created[#created + 1] = m
		return m
	end,
	getPlayers = function() return {} end,
	getSpectators = function() return {} end,
	getGameState = function() return 1 end,
	broadcastMessage = function() end
}
GAME_STATE_SHUTDOWN, GAME_STATE_CLOSED = 99, 98
Town = function() return nil end
local sent = {}
Chaos.send = function(p, op, action, data)
	sent[#sent + 1] = {p = p, op = op, action = action, data = data}
	return true
end
Chaos.giveItem = function(player, id, count)
	player.items[id] = (player.items[id] or 0) + count
	return count
end
Chaos.heal = function(c, amount) c.hp = math.min(c.maxHp, c.hp + amount) end
local tokens = {}
-- O678: the real source table of conquest.lua: a source it does not list pays nothing (the call named "pinnacle:<boss>" and no kill ever paid a token)
local conquestCfg = dofile("data/scripts/chaos/conquest_config.lua")
local refused = {}
ChaosConquest = {grant = function(p, source, amount, detail)
	if not conquestCfg.sources[source] then
		refused[#refused + 1] = source
		return 0
	end
	tokens[#tokens + 1] = {name = p:getName(), source = source, amount = amount, detail = detail}
	return amount
end}
ChaosMakeUnique = function(item) item.unique = true end
local titleSources = {}
ChaosTitles = {register = function(source, fn) titleSources[source] = fn end}
ChaosNameplate = {refresh = function() end}
-- the mechanics glue: the factor the profile keeps the kill time with (G.balance)
local attached = {}
local dangerAsked, dangerAnswer, addsAnswer, tallyAnswer = {}, nil, nil, nil
ChaosBossMech = {attach = function(m, key, opts)
	attached[#attached + 1] = {monster = m, opts = opts}
	return {hpMult = 0.8}
end, scriptedHit = function(attacker)   -- O690: a marked attack of the boss is being dealt (boss_mechanics.lua M.scriptedHit)
	return attacker and attacker.scripted == true
end, dangerFor = function(bossId, at, who)   -- O681: the marks a person sees (boss_mechanics.lua M.dangerFor; O684: and who asks)
	dangerAsked[#dangerAsked + 1] = {bossId, at, who}
	return dangerAnswer
end, addsFor = function(bossId)   -- O681: the adds and the totem of the phases (boss_mechanics.lua M.addsFor)
	return addsAnswer
end, tallyFor = function(bossId)   -- O683: what the telegraphs did so far (boss_mechanics.lua M.tallyFor)
	return tallyAnswer
end}
local capLastCalls = {}
ChaosRift = {capLast = function(p) capLastCalls[#capLastCalls + 1] = p:getId() end}   -- O690: rift.lua RF.capLast, the cap events go last
local riftCalls, waystoneCalls = {}, {}
ChaosAscended = {onRiftSealed = function(info) riftCalls[#riftCalls + 1] = info end}
ChaosWaystoneTiers = {}

local players = {}
local function newPlayer(id, level)
	local p = {id = id, level = level, pos = pos(100, 100, 7), msgs = {}, events = {}, items = {}, hp = 20000, maxHp = 20000, store = {}}
	function p:getId() return self.id end
	function p:getGuid() return 100 + self.id end
	function p:getName() return "P" .. self.id end
	function p:getLevel() return self.level end
	function p:getPosition() return self.pos end
	function p:teleportTo(p2) self.pos = pos(p2.x, p2.y, p2.z) end
	function p:registerEvent(e) self.events[e] = true end
	function p:unregisterEvent(e) self.events[e] = nil end
	function p:removeCondition() end
	function p:hasCondition() return false end
	function p:isPzLocked() return false end
	function p:getParty() return self.party end
	function p:getTown() return {getTemplePosition = function() return pos(100, 100, 7) end} end
	function p:sendTextMessage(_, t) self.msgs[#self.msgs + 1] = t end
	function p:isPlayer() return true end
	function p:isMonster() return false end
	function p:getMaster() return nil end
	function p:getHealth() return self.hp end
	function p:getMaxHealth() return self.maxHp end
	function p:getInbox() return nil end
	function p:addItemEx(item) self.items["ex" .. (item.unique and "u" or "")] = item return 0 end
	function p:getStorageValue(k) return self.store[k] or -1 end
	function p:setStorageValue(k, v) self.store[k] = v end
	function p:save() self.saved = (self.saved or 0) + 1 end
	function p:getPosition2() return self.pos end
	players[id] = p
	return p
end
Player = function(id)
	if type(id) == "string" then
		for _, p in pairs(players) do
			if p:getName() == id then
				return p
			end
		end
		return nil
	end
	return players[id]
end
tiles["100,100,7"] = {hasFlag = function() return true end, getGround = function() return 1 end}
tiles["200,200,7"] = {hasFlag = function() return false end, getGround = function() return 1 end}
dofile("data/scripts/chaos/pinnacle.lua")
local PN = ChaosPinnacle
Chaos.pinnacleConfig.darkActive = false
local pcfg = Chaos.pinnacleConfig
local S = pcfg.storage
local function stor(p, off)
	return p.store[S.base + off] or -1
end
local function fragOf(p, boss, kind)
	return p.store[K.fragKey(pcfg, boss, kind)] or 0
end
local function giveSet(p, boss)
	for kind = 1, 4 do
		p.store[K.fragKey(pcfg, boss, kind)] = 1
	end
end

eq(#PN.bosses(), 4, "bosses()")
ok(registry.ChaosPinnacleStartup and registry.ChaosPinnacleLogin and registry.ChaosPinnacleModal, "events registered")
ok(titleSources.pinnacle, "the title source is registered")

-- ---- the hooks: a sealed rift and an Omen guardian through the wrap of ChaosAscended.onRiftSealed
local a = newPlayer(1, 2500)
registry.ChaosPinnacleLogin.onLogin(a)
ok(a.events.ChaosPinnacleLogout and a.events.ChaosPinnacleModal, "login registers the logout and the modal events")
ok(PN._wrapRift ~= nil and ChaosAscended.onRiftSealed == PN._wrapRift, "the rift hook is wrapped")
local plain = {}
PN.setFocus(a, 2)
eq(PN.focus(a), 2, "the focus is stored")
math.randomseed(11)
local gotRift = 0
for _ = 1, 60 do
	ChaosAscended.onRiftSealed({tier = 15, omen = nil, finishers = {[a:getGuid()] = {name = a:getName()}}, players = 1})
end
eq(#riftCalls, 60, "the original still runs")
for kind = 1, 4 do
	gotRift = gotRift + fragOf(a, 2, kind)
end
ok(fragOf(a, 2, 2) > 0, "a rift of tier 15 dropped its kind (of the focus)")
eq(fragOf(a, 2, 1) + fragOf(a, 2, 3), 0, "and no other source's kind")
ok(fragOf(a, 2, 2) <= pcfg.fragments.cap, "the cap holds")
for k = 1, 4 do
	eq(fragOf(a, 1, k) + fragOf(a, 3, k) + fragOf(a, 4, k), 0, "nothing for the other bosses")
end
local before = fragOf(a, 2, 2)
ChaosAscended.onRiftSealed({tier = 14, finishers = {[a:getGuid()] = {name = a:getName()}}, players = 1})
eq(fragOf(a, 2, 2), before, "a rift of tier 14 gives nothing")
for _ = 1, 80 do
	ChaosAscended.onRiftSealed({tier = 15, omen = "dreadful", finishers = {[a:getGuid()] = {name = a:getName()}}, players = 1})
end
ok(fragOf(a, 2, 3) > 0, "an Omen guardian dropped kind 3")
eq(fragOf(a, 2, 2), before, "and not kind 2")
-- a finisher that is offline or whose guid does not match gets nothing
local none = newPlayer(2, 2500)
ChaosAscended.onRiftSealed({tier = 15, finishers = {[999] = {name = none:getName()}}, players = 1})
eq(fragOf(none, 1, 2) + fragOf(none, 2, 2) + fragOf(none, 3, 2) + fragOf(none, 4, 2), 0, "a wrong guid gets nothing")

-- ---- the waystone hook (O666): a guarded call, nothing without it
eq(PN.wrapHooks() and 1 or 0, 0, "nothing new to wrap yet")
ok(PN._wrapWaystone == nil, "no waystone hook without ChaosWaystoneTiers.onRunCleared")
ChaosWaystoneTiers.onRunCleared = function(...) waystoneCalls[#waystoneCalls + 1] = {...} return "kept" end
local _, wrapped = PN.wrapHooks()
ok(wrapped, "the waystone hook is wrapped once it exists")
eq(select(2, PN.wrapHooks()), false, "wrapped once")
eq(ChaosWaystoneTiers.onRunCleared({tier = 12}), "kept", "the original's result is kept")
local c = newPlayer(3, 2500)
local wsBefore = 0
for _ = 1, 80 do
	ChaosWaystoneTiers.onRunCleared({tier = 15, players = {c}})
end
eq(#waystoneCalls, 81, "the original runs every time")
ok(fragOf(c, 1, 1) + fragOf(c, 2, 1) + fragOf(c, 3, 1) + fragOf(c, 4, 1) > 0, "a top waystone map dropped kind 1 for a level 2500 character")
for b = 1, 4 do
	eq(fragOf(c, b, 2) + fragOf(c, b, 3), 0, "the waystone drops no rift or omen kind")
end
local d = newPlayer(4, 2500)
for _ = 1, 40 do
	ChaosWaystoneTiers.onRunCleared({tier = 5, players = {d}})
end
for b = 1, 4 do
	eq(fragOf(d, b, 1) + fragOf(d, b, 4), 0, "a low tier drops nothing")
end
-- a call it cannot read gives nothing and breaks nothing
eq(PN.onWaystoneCleared("nonsense"), 0, "an unreadable call")
eq(PN.onWaystoneCleared({tier = 15}), 0, "a call with no players")
-- the finishers as a guid -> {name} map, as the rift's
local e = newPlayer(5, 2500)
local got = 0
for _ = 1, 80 do
	got = got + PN.onWaystoneCleared({tier = 15, finishers = {[e:getGuid()] = {name = e:getName()}}})
end
ok(got > 0, "finishers as a map")
-- O671: the call the waystone endgame really makes (waystone_endgame.lua `fire`, read live): a map, the opener, the percent of its rank and the players in
-- the map (info.players); the rank adds to the chance of the fragment
local realInfo = function(extra)
	local i = {map = 9, tier = 25, level = 3500, band = false, boss = "Hollow Colossus", opener = 105, fragmentChance = 8, corrupted = false, firstClears = 0, chest = false,
		bandBoss = true, players = {e}}
	for k, v in pairs(extra or {}) do i[k] = v end
	return i
end
local viaReal = 0
for _ = 1, 80 do
	viaReal = viaReal + PN.onWaystoneCleared(realInfo())
end
ok(viaReal > 0, "the real call hands a fragment to a character standing in the map (" .. viaReal .. " of 80 clears)")
eq(PN.onWaystoneCleared(realInfo({tier = 5})), 0, "a tier under the waystone minimum: nothing")
eq(PN.onWaystoneCleared(realInfo({players = {}})), 0, "an empty map: nothing")
-- a level under every boss gets none
local low = newPlayer(6, 1500)
for _ = 1, 40 do
	PN.grantClear(low, "rift", {tier = 15})
end
for b = 1, 4 do
	for k = 1, 4 do
		eq(fragOf(low, b, k), 0, "a level 1500 character earns no fragment")
	end
end

-- ---- the Keeper's window
local pb = newPlayer(10, 2500)
registry.ChaosPinnacleLogin.onLogin(pb)
giveSet(pb, 1)
pb.store[K.fragKey(pcfg, 1, 1)] = 2
local ok1, why1 = PN.enter(newPlayer(11, 2500), "malgrath")
eq(ok1, false, "no set, no fight")
ok(why1:find("not whole", 1, true), why1)
pb.pos = pos(200, 200, 7)
ok1, why1 = PN.enter(pb, "malgrath")
eq(ok1, false, "not from outside a protection zone")
ok(why1:find("protection zone", 1, true), why1)
eq(fragOf(pb, 1, 1), 2, "a refusal spends nothing")
pb.pos = pos(100, 100, 7)
local lowpb = newPlayer(12, 1000)
giveSet(lowpb, 1)
eq((PN.enter(lowpb, "malgrath")), false, "the level opens it")
eq((PN.enter(pb, "nope")), false, "an unknown boss")
ok(PN.modalAnswer(pb, pcfg.modal.list, 2, 3), "the Focus button answers")
eq(PN.focus(pb), 3, "the focus is Talath")
PN.modalAnswer(pb, pcfg.modal.list, 2, 4)
eq(PN.focus(pb), 4, "the focus is Varkhul")
eq(PN.modalAnswer(pb, 1, 1, 1), false, "another window is not ours")
-- Open spends the set and takes the player in
local okE, text = PN.enter(pb, "malgrath")
eq(okE, true, "opened: " .. tostring(text))
eq(fragOf(pb, 1, 1), 1, "one of the two spent")
eq(fragOf(pb, 1, 2), 0, "the set is spent before the fight starts")
eq(stor(pb, S.marker), 1, "the run marker names the boss")
ok(PN.isInside(pb), "inside")
ok(U.slotAt(pcfg, pb.pos), "standing in a pinnacle slot")
ok(pb.events.ChaosPinnacleHit and pb.events.ChaosPinnaclePrepareDeath, "fight events on")
eq((PN.enter(pb, "malgrath")), false, "no second fight from inside")
local run = PN.runOf[pb:getId()]
eq(run.size, 1, "solo")
eq(run.falls, 0, "deathless so far")
advance(pcfg.startDelay + 1)
local bossM = Monster(run.bossId)
ok(bossM, "the boss appeared")
eq(bossM.spawnLevel, 1900, "shown at the boss's level")
eq(bossM.name, "Ascended Malgrath", "the type of its name")
local function H(b, v) return Chaos.scaleHealth(v, b.refLevel or b.level) end -- O709: the ranks are live, so x H at the boss's planned level
eq(bossM.maxHp, H(pcfg.bosses[1], math.floor(pcfg.bosses[1].health * 0.8 + 0)), "the health is the fight's x the mechanics factor x H")
eq(bossM.hp, bossM.maxHp, "O681: a solo boss starts at its full health")
ok(bossM.events.ChaosPinnacleDeath, "death event")
-- O694: the boss climbed from 79% back to 100% in a party run: the natural boss modifiers (Regenerating 1% of the maximum every 2.5 s) healed it
ok(not (bossM.events.ChaosTierRollBoss or bossM.events.ChaosTierRollMagic or bossM.events.ChaosTierRollRare or bossM.events.ChaosTierRollLegendary),
	"O694: the pinnacle boss rolls no tier or boss modifiers")
eq(attached[#attached].opts.solo, true, "the mechanics know it is a solo fight")
-- O698: the factor is worked out for the fight's size: the mechanics are told the health of this size over the monster's own
eq(attached[#attached].opts.partySize, 1, "O698: the mechanics are told the size of the fight")
eq(attached[#attached].opts.size, nil, "O703: the party size is not the boss footprint (the shapes keep the profile size)")
ok(attached[#attached].opts.healthScale > 0, "O698: the mechanics are told the health scale of the fight")
-- its hits x the damage curve
local hit = registry.ChaosPinnacleHit.onHealthChange
local dmg = hit(pb, bossM, -1000, 1, 0, 1, 0)
eq(dmg, -1000, "a solo fight: the boss hits at x1")
local norm = hit(pb, newMonster("Rat", pos(50, 50, 7)), -100, 1, 0, 1, 0)
eq(norm, -100, "other monsters untouched")
local msp = ChaosManaShield.providers.pinnacle
eq(msp.hit(pb, bossM, 1000), 1000, "mana shield part: the same curve")
-- the kill: tokens, orbs, the unique roll, counts, the titles
math.randomseed(2)
local realRandom = math.random
pb.store[S.base + S.pity] = 7 -- the kill after seven without: the bad-luck count names it
-- O686 phase 7: the Pinnacle Seals hook (spell_awakening.lua): every member of the party at the kill, once
local sealCalls = {}
_G.ChaosSpellAwakening = {onPinnacleKill = function(p) sealCalls[#sealCalls + 1] = p:getId() return 2 end}
registry.ChaosPinnacleDeath.onDeath(bossM)
advance(0)
eq(run.state, "success", "success")
eq(#sealCalls, 1, "seals: the hook runs once for the one member")
eq(sealCalls[1], pb:getId(), "seals: for the member")
_G.ChaosSpellAwakening = nil
eq(#tokens, 1, "Conquest Tokens")
eq(tokens[1].source, "pinnacle", "the token source is one the Conquest table lists")
eq(tokens[1].detail, "malgrath", "the log row names the boss")
eq(#refused, 0, "the Conquest table refused no source")
ok(conquestCfg.sources.pinnacle.cap >= 5 * 14 and conquestCfg.sources.pinnacle.amount >= 14, "the daily cap pays five kills of the dearest boss")
eq(tokens[1].amount, pcfg.bosses[1].tokens, "the token amount")
eq(pb.items[pcfg.orbs.chaos], pcfg.bosses[1].orbs.chaos, "orbs of upheaval")
eq(pb.items[pcfg.orbs.divine], pcfg.bosses[1].orbs.divine, "orbs of fate")
eq(pb.items[pcfg.orbs.exalted], pcfg.bosses[1].orbs.exalted, "exalted orbs")
ok(pb.items.exu and pb.items.exu.unique, "the unique was given (the bad-luck count): a made unique copy")
eq(stor(pb, S.pity), 0, "the count is reset")
eq(stor(pb, S.kills), 1, "the kill is counted")
eq(stor(pb, S.deathless), 1, "deathless: nobody fell")
ok(stor(pb, S.first) > 0, "the first kill of the season is stored")
local titles = titleSources.pinnacle(pb)
eq(#titles, 2, "a season title and the deathless title")
eq(titles[1].text, "Malgrath Bane [S0]", "with no season: season 0")
eq(titles[2].text, "Deathless Malgrath", "deathless")
eq(stor(pb, S.marker), 1, "the marker stays while inside (cleared when the fight closes)")
ok(PN.isInside(pb), "still inside to leave")
advance(pcfg.exitDelay + 1)
ok(not PN.isInside(pb), "sent back after exitDelay")
eq(stor(pb, S.marker), 0, "the marker is cleared")
eq(pb.pos.x, 100, "back where they came from")
eq(PN.runs[run.slot], nil, "the slot is free")
eq(fragOf(pb, 1, 1), 1, "the spare fragment of kind 1 is kept")

-- a second kill the same season: no new first-kill title; the bad-luck count counts
tokens = {}
NOW = NOW + pcfg.enterCooldown + 1
giveSet(pb, 1)
okE = PN.enter(pb, "malgrath")
eq(okE, true, "again")
run = PN.runOf[pb:getId()]
advance(pcfg.startDelay + 1)
bossM = Monster(run.bossId)
-- a lethal hit: caught, out, healed, and the fight is not deathless any more (a party member falls, the opener fights on)
registry.ChaosPinnacleDeath.onDeath(bossM)
advance(0)
eq(stor(pb, S.kills), 2, "two kills")
eq(#K.titleList(pcfg, PN.index().list[1], stor(pb, S.first), stor(pb, S.deathless), nil, 0), 2, "no second first-kill title the same season")
advance(pcfg.exitDelay + 1)

-- ---- a party: the opener pays the set, the members come along free and are rewarded
tokens = {}
local b2, c2, far = newPlayer(20, 2500), newPlayer(21, 2500), newPlayer(22, 2500)
local weak = newPlayer(23, 1000)
local lead = newPlayer(24, 1900)
registry.ChaosPinnacleLogin.onLogin(lead)
local party = {getLeader = function() return lead end, getMembers = function() return {b2, c2, far, weak} end}
lead.party, b2.party, c2.party, far.party, weak.party = party, party, party, party, party
b2.pos, c2.pos, far.pos, weak.pos = pos(102, 100, 7), pos(103, 101, 7), pos(300, 300, 7), pos(101, 100, 7)
giveSet(lead, 2)
NOW = NOW + pcfg.enterCooldown + 1
okE, text = PN.enter(lead, "vhoss")
eq(okE, false, "level 1900 for Vhoss")
lead.level = 2100
okE, text = PN.enter(lead, "vhoss")
eq(okE, true, "party fight: " .. tostring(text))
run = PN.runOf[lead:getId()]
eq(run.size, 3, "the opener and two members came (one too far, one too low)")
ok(PN.isInside(b2) and PN.isInside(c2) and not PN.isInside(far) and not PN.isInside(weak), "who came")
ok(weak.msgs[#weak.msgs]:find("level", 1, true), "told why")
eq(fragOf(lead, 2, 1), 0, "the opener spent a set")
eq(fragOf(b2, 2, 1), 0, "the members spent none (and had none)")
eq(stor(b2, S.marker), -1, "only the opener has the marker")
advance(pcfg.startDelay + 1)
bossM = Monster(run.bossId)
eq(bossM.maxHp, H(pcfg.bosses[2], K.bossHealth(pcfg.bosses[2], 3) * 0.8), "health for three x the mechanics factor x H")
eq(bossM.hp, bossM.maxHp, "O681: the party's boss starts at its full health (the engine's addHealth takes a damage type: the one-argument call healed nothing and the boss stood at the solo value)")
eq(attached[#attached].opts.solo, false, "the mechanics know it is a party fight")
eq(attached[#attached].opts.partySize, 3, "O698: the mechanics are told the party size")
eq(attached[#attached].opts.size, nil, "O703: a party of three does not grow the telegraphs")
ok(attached[#attached].opts.healthScale > 1, "O698: a party's boss is told its party health (" .. tostring(attached[#attached].opts.healthScale) .. ")")
local hit2 = hit(b2, bossM, -1000, 1, 0, 1, 0)
eq(hit2, math.floor(-1000 * K.scale(pcfg.damage, 3)), "the damage curve for three")
-- O678: the probe inside a fight: the run, the boss's health and the guide of the walk to it (the tester bots' `!tester pinnacle`)
do
	local inside = PN.probe(lead)
	eq(inside.inside, "vhoss", "probe: the boss of the fight")
	eq(inside.run.boss, "alive", "probe: the boss is up")
	eq(inside.run.kind, "vhoss", "probe: the run's boss")
	eq(inside.run.size, 3, "probe: the size of the party")
	eq(inside.run.players, 3, "probe: the players in it")
	eq(inside.run.bossHp, 100, "probe: the boss's health percent")
	eq(inside.run.bossMax, bossM.maxHp, "probe: the boss's maximum health")
	eq(inside.run.falls, 0, "probe: no fall yet")
	ok(inside.run.left > 0 and inside.run.sinceBoss ~= nil, "probe: the clock and the seconds since the boss came")
	eq(inside.guide.mode, "walk", "probe: far from the boss, the guide walks")
	eq(inside.guide.goal.x, bossM.pos.x, "probe: to the boss")
	ok(inside.free >= 0 and inside.reserve == pcfg.tester.reserve, "probe: the arenas free and kept for players")
	lead.pos = pos(bossM.pos.x + 2, bossM.pos.y, bossM.pos.z)
	eq(PN.probe(lead).guide.mode, "fight", "probe: in reach, the guide fights")
	bossM.hp = bossM.maxHp * 25 / 100
	eq(PN.probe(lead).run.bossHp, 25, "probe: the health follows the boss")
	-- O681: the telegraphs: a mark on the bot's tile turns the guide into a dodge to the safe tile; a mark elsewhere changes nothing but `danger`
	local lp = lead:getPosition()
	dangerAnswer = {marked = {[(lp.x + 5) .. "," .. lp.y] = true}, left = 1400, labels = {"Tidal Surge"}, count = 1}
	local far = PN.probe(lead)
	eq(far.guide.mode, "fight", "probe: a mark away from the bot leaves the guide alone")
	eq(far.danger.here, false, "probe: the mark is not on the bot's tile")
	eq(far.danger.labels[1], "Tidal Surge", "probe: the mark's name")
	eq(dangerAsked[#dangerAsked][1], run.bossId, "probe: the danger is asked for the run's boss")
	dangerAnswer = {marked = {[lp.x .. "," .. lp.y] = true}, left = 900, labels = {"Tidal Surge"}, count = 1, goal = {x = lp.x - 3, y = lp.y, z = lp.z}}
	local on = PN.probe(lead)
	eq(on.guide.mode, "dodge", "probe: a mark on the bot's tile: dodge")
	eq(on.guide.goal.x, lp.x - 3, "probe: to the safe tile the mechanics name")
	eq(on.danger.here, true, "probe: the bot stands in the mark")
	ok(on.guide.why:find("Tidal Surge", 1, true) ~= nil, "probe: the guide says which mark")
	-- O684: the probe asks with the player's id (a party's bots get different goals) and turns the planned route into (dx, dy) steps from the bot's tile
	eq(dangerAsked[#dangerAsked][3], lead:getId(), "probe: the danger is asked with the player's id")
	dangerAnswer = {marked = {[lp.x .. "," .. lp.y] = true}, left = 900, labels = {"Tidal Surge"}, count = 1, goal = {x = lp.x - 2, y = lp.y + 1, z = lp.z},
		route = {{x = lp.x - 1, y = lp.y + 1, z = lp.z}, {x = lp.x - 2, y = lp.y + 1, z = lp.z}}}
	local rt = PN.probe(lead)
	eq(#rt.danger.steps, 2, "probe: the route is two steps")
	ok(rt.danger.steps[1][1] == -1 and rt.danger.steps[1][2] == 1 and rt.danger.steps[2][1] == -1 and rt.danger.steps[2][2] == 0,
		"probe: the steps are (dx, dy) from the tile before")
	dangerAnswer = nil
	eq(PN.probe(lead).guide.mode, "fight", "probe: no mark, no dodge")
	eq(PN.probe(lead).danger, nil, "probe: no danger field without a mark")
	-- O681: the adds of a phase (the anchors that shield the boss): the guide goes to the nearest one, a target for the helper's loop
	local made = {}
	local function addAt(id, dx)
		local a = {id = id, pos = pos(lp.x + dx, lp.y, lp.z)}
		function a:getId() return self.id end
		function a:getPosition() return self.pos end
		made[id] = a
		return a
	end
	addAt(777001, 12)
	addAt(777002, 3)
	local realMonster = Monster
	Monster = function(id) return made[id] or realMonster(id) end
	addsAnswer = {777001, 777002}
	local ga = PN.probe(lead)
	eq(ga.guide.mode, "fight", "probe: an add within reach of the bot: fight it")
	eq(ga.guide.goal.x, lp.x + 3, "probe: the nearest add of two")
	eq(ga.guide.area, "adds", "probe: the guide's area is the adds")
	eq(ga.adds.id, 777002, "probe: the add's id for the helper")
	eq(PN.priorityTarget(lead):getId(), 777002, "priorityTarget: the nearest add")
	made[777002] = nil
	local gb = PN.probe(lead)
	eq(gb.guide.mode, "walk", "probe: only a far add left: walk to it")
	eq(gb.guide.goal.x, lp.x + 12, "probe: to the far add")
	-- O683: a mark on or next to the tile the walk ends on, the bot off it: it holds until the hit (the walk went back into the mark it had left)
	dangerAnswer = {marked = {[(lp.x + 13) .. "," .. (lp.y + 1)] = true}, left = 1200, labels = {"Tidal Surge"}, count = 1}
	local held = PN.probe(lead)
	eq(held.guide.mode, "hold", "probe: the walk would end next to a mark: hold")
	eq(held.guide.goal.x, lp.x + 12, "probe: the hold keeps the goal")
	eq(held.danger.here, false, "probe: the bot is not on the mark it holds for")
	dangerAnswer = {marked = {[(lp.x + 20) .. "," .. lp.y] = true}, left = 1200, labels = {"Tidal Surge"}, count = 1}
	eq(PN.probe(lead).guide.mode, "walk", "probe: a mark far from the goal does not hold the walk")
	dangerAnswer = nil
	tallyAnswer = {fired = 3, exposed = 5, taken = 1, by = {["Tidal Surge"] = {fired = 3, exposed = 5, taken = 1}}}
	local ty = PN.probe(lead).tally
	eq(ty.taken, 1, "probe: the tally of the telegraphs (O683)")
	eq(ty.by["Tidal Surge"].exposed, 5, "probe: the tally by name")
	tallyAnswer = nil
	eq(PN.probe(lead).tally, nil, "probe: no tally without a telegraph")
	dangerAnswer = {marked = {[lp.x .. "," .. lp.y] = true}, left = 900, labels = {"Tidal Surge"}, count = 1, goal = {x = lp.x - 3, y = lp.y, z = lp.z}}
	eq(PN.probe(lead).guide.mode, "dodge", "probe: a mark on the bot's tile comes before the adds")
	eq(PN.probe(lead).adds.id, 777001, "probe: the add is still named while it dodges")
	dangerAnswer = nil
	addsAnswer = nil
	eq(PN.priorityTarget(lead), nil, "priorityTarget: no add up, no priority (the helper aims at the boss)")
	eq(PN.probe(lead).adds, nil, "probe: no adds field without an add")
	eq(PN.probe(lead).guide.mode, "fight", "probe: the guide is the boss's again")
	-- O695: the boss of the player's fight and the test of a creature (the helper aims at it and tallies the damage on it)
	local lb = PN.bossOf(lead)
	eq(lb ~= nil, true, "bossOf: the live boss of the fight the player is in")
	eq(PN.isBoss(lb), true, "isBoss: the boss of the fight")
	eq(PN.isBoss(made[777002]), false, "isBoss: an add is not the boss")
	eq(PN.bossOf({getId = function() return 424242 end}), nil, "bossOf: a player in no fight")
	Monster = realMonster
	eq(PN.nearestAdd({getId = function() return 424242 end}), nil, "nearestAdd: a player in no fight")
end
-- ---- O690: the hit cap (pinnacle_config.lua hitCap; the rule is the guardian's, hitcap_core.lua; the cap events: rift.lua RF.capLast)
do
	COMBAT_HEALING = 128
	local hc = pcfg.hitCap
	ok(hc and hc.enabled, "O690: the cap is on")
	ok(hc.share > 0 and hc.share < 0.5, "O690: under half, so a character of full health survives two plain hits")
	ok(hc.telegraph > hc.share and hc.telegraph < 1, "O690: a marked attack is cut at a higher share, never at the whole pool")
	-- the core: which share a hit gets
	eq(K.hitCapShare(pcfg, false), hc.share, "O690: core: a plain hit")
	eq(K.hitCapShare(pcfg, true), hc.telegraph, "O690: core: a marked attack")
	eq(K.hitCapShare({hitCap = {enabled = false, share = 0.4, telegraph = 0.6}}, false), nil, "O690: core: off")
	eq(K.hitCapShare({}, false), nil, "O690: core: no block")
	eq(K.hitCapShare({hitCap = {enabled = true, share = 0, telegraph = 0.6}}, false), nil, "O690: core: 0 is no share")
	eq(K.hitCapShare({hitCap = {enabled = true, share = 1.5, telegraph = 0.6}}, false), nil, "O690: core: over the pool is no share")
	eq(K.hitCapShare({hitCap = {enabled = true, share = "x", telegraph = 0.6}}, false), nil, "O690: core: not a number")
	ok(#capLastCalls >= 2, "O690: every player who enters has the cap events moved last (ChaosRift.capLast)")
	local mult = K.scale(pcfg.damage, 3)
	local pool = b2:getMaxHealth()
	local limit = math.floor(hc.share * pool)
	local tlimit = math.floor(hc.telegraph * pool)
	-- the source, as the cap events ask it
	eq(ChaosHitCap.shareOf(bossM, b2), hc.share, "O690: the boss on a player of the run: the plain share")
	bossM.scripted = true
	eq(ChaosHitCap.shareOf(bossM, b2), hc.telegraph, "O690: a marked attack of the boss: the telegraph share")
	bossM.scripted = nil
	local add = newMonster("Hex Idol", pos(bossM.pos.x + 1, bossM.pos.y, bossM.pos.z))
	eq(ChaosHitCap.shareOf(add, b2), hc.share, "O690: an add standing in the arena is capped too")
	eq(ChaosHitCap.shareOf(newMonster("Rat", pos(50, 50, 7)), b2), nil, "O690: a monster outside the run is not")
	eq(ChaosHitCap.shareOf(bossM, newMonster("Rat2", pos(50, 50, 7))), nil, "O690: monsters are not capped")
	eq(ChaosHitCap.shareOf(bossM, newPlayer(90, 2500)), nil, "O690: a player of no run is not")
	eq(ChaosHitCap.shareOf(c2, b2), nil, "O690: a player's hit (PvP) is not")
	local summon = newMonster("Summon", pos(bossM.pos.x + 1, bossM.pos.y, bossM.pos.z))
	function summon:getMaster() return b2 end
	eq(ChaosHitCap.shareOf(summon, b2), nil, "O690: a summon of a player is not")
	-- the hit event: above the cap cut, below untouched
	local big = hit(b2, bossM, -30000, 1, 0, 1, 0)
	eq(big, -limit, "O690: a hit over the cap (after the party curve) is cut to share x pool")
	local small = hit(b2, bossM, -1000, 1, 0, 1, 0)
	eq(small, math.floor(-1000 * mult), "O690: a hit under the cap is only scaled")
	local p2, _, s2 = hit(b2, bossM, -30000, 1, -10000, 1, 0)
	ok(math.abs(p2) + math.abs(s2) <= limit, "O690: primary and secondary together at most the ceiling")
	local heal2, _, sec = hit(b2, bossM, -30000, 1, 500, 128, 0)
	eq(sec, 500, "O690: a healing secondary part is left alone")
	eq(heal2, -limit, "O690: and the damage part is cut")
	-- a marked attack: the higher share
	bossM.scripted = true
	local tbig = hit(b2, bossM, -40000, 1, 0, 1, 0)
	eq(tbig, -tlimit, "O690: a marked attack over the telegraph cap is cut to it")
	ok(tlimit > limit, "O690: and the cap of a marked attack is the higher one")
	local tmid = hit(b2, bossM, -9000, 1, 0, 1, 0)
	eq(tmid, math.floor(-9000 * mult), "O690: a marked attack between the two shares is not touched (only the plain cap would cut it)")
	bossM.scripted = nil
	-- an add
	eq(hit(b2, add, -30000, 1, 0, 1, 0), -limit, "O690: an add's hit is cut")
	-- not capped: a player's own summon, another monster, a player
	eq(hit(b2, summon, -15000, 1, 0, 1, 0), math.floor(-15000 * mult), "O690: a summon of a player is scaled as before, never capped")
	eq(hit(b2, newMonster("Rat3", pos(50, 50, 7)), -15000, 1, 0, 1, 0), -15000, "O690: a monster outside the run: untouched")
	eq(hit(b2, c2, -15000, 1, 0, 1, 0), -15000, "O690: a player's hit: untouched")
	eq(hit(b2, bossM, 5000, 128, 0, 1, 0), 5000, "O690: healing is not a hit")
	-- under a mana shield the pre-cut leaves the hit to the cap events (their mana event sees it first)
	local plain = b2.hasCondition
	function b2:hasCondition() return true end
	eq(hit(b2, bossM, -15000, 1, 0, 1, 0), math.floor(-15000 * mult), "O690: under a mana shield the cap events cut")
	b2.hasCondition = plain
	-- what the cap events do with the same number (rift.lua's cap, hitcap_core.lua)
	local cp, _, climit, cut = ChaosHitCapCore.cut(ChaosHitCap.shareOf(bossM, b2), -50000, 0, ChaosHitCapCore.pool(b2:getMaxHealth(), 9000, false), 0)
	eq(cp, -limit, "O690: the cap events cut the same hit to the same ceiling")
	eq(climit, limit, "O690: the ceiling")
	ok(cut, "O690: and say it was cut")
	eq(ChaosHitCapCore.pool(b2:getMaxHealth(), 9000, true), pool + 9000, "O690: a mana shield adds the maximum mana to the pool the cap is a share of")
	-- off: nothing is capped
	hc.enabled = false
	eq(ChaosHitCap.shareOf(bossM, b2), nil, "O690: switched off: no source")
	eq(hit(b2, bossM, -15000, 1, 0, 1, 0), math.floor(-15000 * mult), "O690: switched off: scaled only")
	hc.enabled = true
	eq(ChaosHitCap.shareOf(bossM, newPlayer(91, 2500)), nil, "O690: a player who is not in the fight")
	COMBAT_HEALING = nil
end
-- a lethal hit: caught, out, healed; the fight is no longer deathless
b2.hp = 100
local p1 = hit(b2, bossM, -50000, 1, 0, 1, 0)
eq(p1 < 0 and p1 > -100, true, "the lethal hit is caught")
advance(0)
ok(not PN.isInside(b2), "the fallen player is out")
eq(b2.hp, b2.maxHp, "healed")
eq(run.falls, 1, "a fall")
-- a logout inside: out, no refund
registry.ChaosPinnacleLogout.onLogout(c2)
ok(not PN.isInside(c2), "logout: out")
-- the kill with a fall: no deathless title for anyone
registry.ChaosPinnacleDeath.onDeath(bossM)
advance(0)
eq(run.state, "success", "success")
eq(stor(lead, S.deathless + 1), -1, "a fight with a fall is not deathless")
ok(stor(lead, S.first + 1) > 0, "the first kill title still comes")
eq(stor(lead, S.kills + 1), 1, "the kill counted for the right boss")
ok(#tokens >= 1, "the survivors are rewarded")
for _, t in ipairs(tokens) do
	eq(t.source, "pinnacle", "token source")
	eq(t.detail, "vhoss", "token detail")
end
advance(pcfg.exitDelay + 1)
eq(PN.runs[run.slot], nil, "closed")

-- ---- a restart gives the set back; a crash gives it back at the next login
NOW = NOW + pcfg.enterCooldown + 1
giveSet(lead, 3)
lead.level = 2500
lead.party = nil
lead.pos = pos(100, 100, 7)
okE = PN.enter(lead, "talath")
eq(okE, true, "Talath's fight")
eq(fragOf(lead, 3, 1), 0, "spent")
registry.ChaosPinnacleShutdown.onShutdown()
eq(fragOf(lead, 3, 1), 1, "given back at the restart")
eq(fragOf(lead, 3, 4), 1, "every kind")
ok(not PN.isInside(lead), "out")
eq(stor(lead, S.marker), 0, "marker cleared")
-- a crash: the marker survives, the set is given back once at the next login
NOW = NOW + pcfg.enterCooldown + 1
giveSet(lead, 4)
okE = PN.enter(lead, "varkhul")
eq(okE, true, "Varkhul's fight")
eq(fragOf(lead, 4, 2), 0, "spent")
eq(stor(lead, S.marker), 4, "the marker names Varkhul")
PN.runOf[lead:getId()] = nil -- the server died: no run, the storage is what is left
for slot in pairs(PN.runs) do
	PN.runs[slot] = nil
end
registry.ChaosPinnacleLogin.onLogin(lead)
eq(fragOf(lead, 4, 2), 1, "the set is back after a crash")
eq(stor(lead, S.marker), 0, "once")
registry.ChaosPinnacleLogin.onLogin(lead)
eq(fragOf(lead, 4, 2), 1, "not twice")
-- a boss that does not come: the set is back
NOW = NOW + pcfg.enterCooldown + 1
giveSet(lead, 1)
local createOld = Game.createMonster
Game.createMonster = function() return nil end
okE = PN.enter(lead, "malgrath")
eq(okE, true, "opened")
advance(pcfg.startDelay + 1)
eq(fragOf(lead, 1, 1), 1, "the boss did not come: the set is back")
ok(not PN.isInside(lead), "the fight is over")
Game.createMonster = createOld
-- logging in inside the grid (after a crash) sends the character to its temple
local L1 = U.layout(pcfg, 1)
lead.pos = pos(L1.entry.x, L1.entry.y, L1.entry.z)
registry.ChaosPinnacleLogin.onLogin(lead)
eq(lead.pos.x, 100, "a login inside the grid goes to the temple")
-- the cooldown
NOW = NOW + 100
giveSet(lead, 1)
okE = PN.enter(lead, "malgrath")
eq(okE, true, "opens")
PN._fail(PN.runOf[lead:getId()], "Test.")
giveSet(lead, 1)
okE, text = PN.enter(lead, "malgrath")
eq(okE, false, "the cooldown")
ok(text:find("Wait", 1, true), text)
-- the probe: what a bot sees
local pr = PN.probe(pb)
eq(#pr.bosses, 4, "four rows")
eq(pr.bosses[1].key, "malgrath", "first row")
ok(pr.bosses[1].open, "open at level 2500")
eq(pr.bosses[1].kills, 2, "kills")

-- O678: the TEST ONLY set of a tester (`!tester pinnacle set`): a whole set of the boss the level opens, never for a player, never inside a fight
do
	Chaos.isTester = function(p) return p.tester == true end
	local tb = newPlayer(70, 2150)
	tb.tester = true
	local plain = newPlayer(71, 2150)
	eq(select(2, PN.testerSet(plain)), "not a tester", "a player gets no set")
	for kind = 1, 4 do
		eq(fragOf(plain, 2, kind), 0, "nothing was written for the player")
	end
	local key = PN.testerSet(tb)
	eq(key, "vhoss", "the highest boss the level opens (level 2150 opens Vhoss, 2000)")
	for kind = 1, 4 do
		eq(fragOf(tb, 2, kind), 1, "one fragment of kind " .. kind)
	end
	PN.testerSet(tb)
	eq(fragOf(tb, 2, 1), 1, "asked again: a kind that is held is not given twice")
	eq(PN.testerSet(tb, "malgrath"), "malgrath", "a named boss the level opens")
	eq(fragOf(tb, 1, 4), 1, "its set")
	local nk, why = PN.testerSet(tb, "talath")
	ok(nk == nil and why:find("opens from level 2200", 1, true), "a boss above the level: the reason " .. tostring(why))
	nk, why = PN.testerSet(tb, "nonsense")
	ok(nk == nil and why:find("no pinnacle boss named nonsense", 1, true), "an unknown boss: the reason")
	local low = newPlayer(72, 1500)
	low.tester = true
	nk, why = PN.testerSet(low)
	ok(nk == nil and why:find("opens no pinnacle boss", 1, true), "a level that opens none: the reason " .. tostring(why))
	ok(PN.probe(tb).bosses[2].ready, "the probe says the set is ready")
	local okO, textO = PN.enter(tb, "vhoss")
	eq(okO, true, "the set opens the fight through the Keeper's own call: " .. tostring(textO))
	local n2, why2 = PN.testerSet(tb)
	ok(n2 == nil and why2:find("already inside", 1, true), "never inside a fight")
	ok(PN.testerClose(tb) == true and not PN.isInside(tb), "the bot's own way out")
end

-- every text the engine says has a pt-BR entry
local src2 = readFile("data/scripts/chaos/pinnacle.lua")
local skip = {["Health: %d%%"] = true, ["Deathless so far"] = true, ["Falls: %d"] = true}
local seen = 0
for _, pat in ipairs({'Chaos%.t%(player, "([^"]+)"', 'Chaos%.t%(p, "([^"]+)"', 'Chaos%.t%(l%.player, "([^"]+)"', 'Chaos%.tx%(player, "([^"]+)"'}) do
	for key in src2:gmatch(pat) do
		seen = seen + 1
		ok(pt[key] or skip[key], "pt-BR for: " .. key)
	end
end
for key in src2:gmatch('tell%(run, "([^"]+)"') do
	seen = seen + 1
	ok(pt[key], "pt-BR for the run text: " .. key)
end
for key in src2:gmatch('fail%(run, "([^"]+)"') do
	seen = seen + 1
	ok(pt[key], "pt-BR for the failure text: " .. key)
end
ok(seen >= 15, "the texts were read (" .. seen .. ")")
local npc = readFile("data/npc/scripts/keeper_of_the_pinnacle.lua")
for key in npc:gmatch('t%(cid, "([^"]+)"') do
	key = loadstring('return "' .. key .. '"')() -- the escapes of the source (\n)
	ok(pt[key], "pt-BR for the Keeper: " .. key:sub(1, 50))
end
local xml = readFile("data/npc/Keeper of the Pinnacle.xml")
for key in xml:gmatch('message_[a-z]+" value="([^"]+)"') do
	ok(pt[key], "pt-BR for the Keeper's XML line: " .. key:sub(1, 50))
end

print(string.format("pinnacle_test: %d checks ok", checks))
