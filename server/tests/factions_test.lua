-- Run from the server/ folder: luajit tests/factions_test.lua (or lua5.3; CI runs both)
-- Factions: the config against chaos_item_mods.lua (gear rules), ranks and the bar, the daily diminishing returns, the
-- weekly cap, rivalry (floor, sworn at Exalted), the reputation ceiling, contract generation by seed (the same in both
-- interpreters, per character / period / faction / slot), matching and progress, quartermaster states, gear values,
-- titles and the window payload; then factions.lua against a mocked engine (kills with party credit and tokens,
-- contracts, the rift / bounty / world boss / invasion hooks, token turn-in, buying gear and orbs, the opcode).
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
loadstring = loadstring or load
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/lib/chaos_item_mods.lua")
local cfg = dofile("data/scripts/chaos/factions_config.lua")
dofile("data/scripts/chaos/factions_core.lua")
local K = ChaosFactionsCore
local M = ChaosItemMods

local failures, count = 0, 0
local function check(cond, label)
	count = count + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, label .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

-- ---------------------------------------------------------------- the config
local problems = K.validate(cfg, M)
eq(#problems, 0, "config problems (" .. table.concat(problems, "; ") .. ")")
eq(ChaosOpcodes.factions, 215, "opcode registered in chaos_constants.lua")
eq(cfg.opcode, ChaosOpcodes.factions, "config opcode")
local used = {}
for name, op in pairs(ChaosOpcodes) do
	if name ~= "factions" then
		used[op] = name
	end
end
eq(used[215], nil, "opcode 215 used by nothing else")
for _, op in ipairs({1, 67, 73, 89, 91, 92, 99, 106, 107, 136, 181, 201, 202}) do
	check(op ~= 215, "not a reference server opcode")
end
local idx = K.index(cfg)
eq(#idx.list, 4, "four factions")
eq(#cfg.ranks, 7, "seven ranks")
-- the bestiary categories, rift themes and invaders the factions name exist
local bcfg = dofile("data/scripts/chaos/bestiary_config.lua")
local cats = {}
for _, c in ipairs(bcfg.categories) do cats[c.key] = true end
local rcfg = dofile("data/scripts/chaos/rift_config.lua")
local themes = {}
for _, t in ipairs(rcfg.themes) do themes[t.name] = true end
local icfg = dofile("data/scripts/chaos/invasion_config.lua")
local seenCat = {}
for _, f in ipairs(cfg.factions) do
	for _, c in ipairs(f.categories) do
		check(cats[c], f.key .. ": bestiary category " .. c)
		check(not seenCat[c], "category " .. c .. " belongs to one faction")
		seenCat[c] = true
	end
	check(themes[f.theme], f.key .. ": rift theme " .. tostring(f.theme))
	for _, inv in ipairs(f.invaders) do
		check(icfg.factions[inv] ~= nil, f.key .. ": invader " .. inv)
	end
	for _, b in ipairs(f.bosses) do
		local found = false
		for _, wb in ipairs(Chaos.worldBoss.bosses) do
			if wb.name:lower():find(b, 1, true) then found = true end
		end
		check(found, f.key .. ": world boss " .. b)
	end
	-- every rank title of the plate fits (titles.lua: 24 characters)
	for _, t in pairs(f.titles) do
		check(#t <= 24, f.key .. " title length " .. t)
	end
	-- the NPC files exist and name a script that exists
	local x = io.open("data/npc/" .. f.npc.name .. ".xml")
	check(x ~= nil, f.key .. ": data/npc/" .. f.npc.name .. ".xml")
	if x then
		local text = x:read("*a")
		x:close()
		check(text:find('name="' .. f.npc.name .. '"', 1, true) ~= nil, f.key .. ": NPC name in its XML")
		local script = text:match('script="([^"]+)"')
		local sf = script and io.open("data/npc/scripts/" .. script)
		check(sf ~= nil, f.key .. ": NPC script " .. tostring(script))
		if sf then
			local s = sf:read("*a")
			sf:close()
			check(s:find('FACTION_KEY = "' .. f.key .. '"', 1, true) ~= nil, f.key .. ": script sets its faction")
		end
	end
end
-- the rival pairs: vigil <-> choir, compact <-> circle
eq(idx.byKey.vigil.rival, "choir", "vigil rival")
eq(idx.byKey.compact.rival, "circle", "compact rival")
-- gear: never above the faction limits (catch-up path, not better than top drops)
local gearN = 0
for _, o in ipairs(idx.offerList) do
	if o.kind == "gear" then
		gearN = gearN + 1
		check(o.level <= cfg.gearLimits.maxLevel and o.rarity <= cfg.gearLimits.maxRarity, o.key .. " within limits")
		check(o.level < M.config.itemLevel.worldBoss, o.key .. " below world boss drops")
	end
end
eq(gearN, 12, "three gear offers per faction")
-- a broken gear offer is caught
local bad = K.gearProblems({key = "x", id = 1, itemKind = "boots", rarity = 1, level = 20,
	mods = {{"bossdamage", 3}, {"dodge", 4}, {"nope", 1}}}, M, cfg.gearLimits)
check(#bad >= 3, "gear checks: kind, tier level, unknown modifier, count (" .. #bad .. ")")

-- ---------------------------------------------------------------- ranks
local i, r = K.rankAt(cfg, 0)
eq(r.key, "neutral", "0 is Neutral")
eq((select(2, K.rankAt(cfg, -1))).key, "wary", "-1 is Wary")
eq((select(2, K.rankAt(cfg, -6000))).key, "hostile", "floor is Hostile")
eq((select(2, K.rankAt(cfg, 2499))).key, "neutral", "below Trusted")
eq((select(2, K.rankAt(cfg, 2500))).key, "trusted", "Trusted")
eq((select(2, K.rankAt(cfg, 36000))).key, "exalted", "Exalted")
local b = K.bar(cfg, 5250)
eq(b.name, "Trusted", "bar rank")
eq(b.pct, 50, "bar halfway Trusted -> Honored")
eq(b.next, "Honored", "bar next")
eq(K.bar(cfg, 36000).pct, 100, "Exalted bar full")

-- ---------------------------------------------------------------- diminishing returns
eq(K.dr(cfg, 0, 600), 600, "first band full")
eq(K.dr(cfg, 600, 600), 300, "second band half")
eq(K.dr(cfg, 1200, 100), 20, "third band a fifth")
eq(K.dr(cfg, 500, 200), 100 + 50, "spans two bands")
eq(K.drMult(cfg, 0), 1.0, "mult now")
eq(K.drMult(cfg, 700), 0.5, "mult second band")

-- ---------------------------------------------------------------- gains, caps, rivalry
local D, W = 20261010, 20261005
local st = {}
local res = K.gain(cfg, idx, st, "vigil", 400, {day = D, week = W})
eq(res.gained, 400, "full gain")
eq(st.vigil.rep, 400, "rep")
eq(res.rival, "choir", "rival named")
eq(res.rivalLoss, 100, "rival loses a quarter")
eq(st.choir.rep, -100, "rival rep")
res = K.gain(cfg, idx, st, "vigil", 400, {day = D, week = W})
eq(res.gained, 200 + 100, "200 at full, 200 at half")
eq(st.vigil.dayGain, 800, "raw day sum")
res = K.gain(cfg, idx, st, "vigil", 1000, {day = D, week = W})
eq(res.gained, 200 + 120, "400 at half, 600 at a fifth")
-- the next day the bands start over
res = K.gain(cfg, idx, st, "vigil", 600, {day = D + 1, week = W})
eq(res.gained, 600, "new day, full value")
-- contracts skip the bands but not the weekly cap
local st2 = {}
for _ = 1, 30 do
	K.gain(cfg, idx, st2, "compact", 300, {day = D, week = W, contract = true})
end
eq(st2.compact.weekGain, cfg.weeklyCap, "weekly cap holds")
eq(st2.compact.rep, cfg.weeklyCap, "rep at cap")
res = K.gain(cfg, idx, st2, "compact", 300, {day = D, week = W, contract = true})
eq(res.gained, 0, "nothing past the cap")
check(res.capped, "capped flag")
res = K.gain(cfg, idx, st2, "compact", 300, {day = D + 7, week = W + 7, contract = true})
eq(res.gained, 300, "new week, cap reset")
eq(st2.compact.bank, 0, "a capped week leaves nothing to carry")
-- the weekly cap rolls over (rolloverWeeks): unused cap and skipped weeks, at most rolloverWeeks weeks' worth
eq(cfg.rolloverWeeks, 3, "three weeks of cap at most")
eq(K.weeksBetween(20261005, 20261019), 2, "two weeks between Mondays")
eq(K.weeksBetween(202641, 20261019), nil, "an old YYYYWW key is not a date")
local stR = {}
K.gain(cfg, idx, stR, "choir", 2500, {day = D, week = W, contract = true})
K.roll(stR.choir, D + 7, 20261012, cfg)
eq(stR.choir.bank, cfg.weeklyCap - 2500, "the unused 5000 carry over")
eq(K.weekCap(cfg, stR.choir), 2 * cfg.weeklyCap - 2500, "this week's cap")
res = K.gain(cfg, idx, stR, "choir", 20000, {day = D + 7, week = 20261012, contract = true})
eq(res.gained, 2 * cfg.weeklyCap - 2500, "the banked cap is usable")
local stS = {}
K.gain(cfg, idx, stS, "circle", 100, {day = D, week = W, contract = true})
K.roll(stS.circle, D + 35, 20261109, cfg)
eq(stS.circle.bank, 2 * cfg.weeklyCap, "five weeks away: capped at two extra weeks")
local stN = {circle = K.newEntry(cfg)}
K.roll(stN.circle, D, W, cfg)
eq(stN.circle.bank, 0, "a fresh entry has no bank")
local stO = {}
K.gain(cfg, idx, stO, "circle", 100, {day = D, week = W, contract = true})
K.roll(stO.circle, D + 7, 20261012)
eq(stO.circle.bank, 0, "without cfg nothing rolls over")
check(K.payload(cfg, idx, stR, {now = os.time(), day = D + 7, week = 20261012}).factions ~= nil, "payload with a bank")
for _, f in ipairs(K.payload(cfg, idx, stR, {now = os.time(), day = D + 7, week = 20261012}).factions) do
	if f.k == "choir" then
		eq(f.wc, 2 * cfg.weeklyCap - 2500, "the window gets the faction's own cap")
	end
end
-- rivalry floor: the rival never drops below the floor through rivalry
eq(st2.circle.rep, -1950, "rival lost a quarter of 7800")
K.gain(cfg, idx, st2, "compact", 1000, {day = D + 7, week = W + 7, contract = true})
eq(st2.circle.rep, cfg.rivalry.floor, "rival stops at the floor")
-- rivalry stops at the floor even from below
local st3 = {circle = K.newEntry(cfg)}
st3.circle.rep = -3000
K.gain(cfg, idx, st3, "compact", 1000, {day = D, week = W, contract = true})
eq(st3.circle.rep, -3000, "a rival below the floor is not lowered further")
-- sworn: an Exalted rival is not lowered
local st4 = {}
K.set(cfg, st4, "choir", 36000, 1)
check(st4.choir.exalted > 0, "set to Exalted marks it")
res = K.gain(cfg, idx, st4, "vigil", 1000, {day = D, week = W, contract = true})
eq(res.rivalLoss, 0, "Exalted rival sworn")
eq(st4.choir.rep, 36000, "Exalted rival keeps its rep")
-- the ceiling: Exalted is the top, reached once
local st5 = {}
K.set(cfg, st5, "circle", 35900, nil)
eq(st5.circle.exalted, 0, "not Exalted yet")
res = K.gain(cfg, idx, st5, "circle", 500, {day = D, week = W, contract = true, now = 77})
eq(res.gained, 100, "only up to the ceiling")
check(res.exaltedNow, "Exalted now")
eq(st5.circle.exalted, 77, "Exalted time")
res = K.gain(cfg, idx, st5, "circle", 500, {day = D, week = W, contract = true, now = 78})
eq(res.gained, 0, "no more at the ceiling")
check(not res.exaltedNow, "Exalted only once")
eq(K.gain(cfg, idx, {}, "nope", 10, {}).gained, 0, "unknown faction")
eq(K.gain(cfg, idx, {}, "vigil", -5, {}).gained, 0, "negative amount")
-- kill-sized gains keep their fractions (carry)
local st6 = {}
local total = 0
for _ = 1, 50 do
	total = total + K.gain(cfg, idx, st6, "vigil", 1, {day = D, week = W}).gained
end
eq(total, 50, "single points at full value")
st6.vigil.dayGain = 1300
total = 0
for _ = 1, 10 do
	total = total + K.gain(cfg, idx, st6, "vigil", 1, {day = D, week = W}).gained
end
eq(total, 2, "ten points at a fifth: 2")

-- ---------------------------------------------------------------- days and weeks
local sat = os.time({year = 2026, month = 10, day = 10, hour = 14})
eq(K.day(sat, cfg), 20261010, "day")
eq(K.day(os.time({year = 2026, month = 10, day = 10, hour = 5}), cfg), 20261009, "before 06:00: the day before")
eq(K.week(sat, cfg), 20261005, "week of Monday 5th")
eq(K.week(os.time({year = 2026, month = 10, day = 5, hour = 5}), cfg), 20260928, "Monday before 06:00: last week")
eq(K.nextDay(sat, cfg) - sat, 16 * 3600, "next day at 06:00")
eq(K.nextWeek(sat, cfg), os.time({year = 2026, month = 10, day = 12, hour = 6, min = 0, sec = 0}), "next Monday 06:00")

-- ---------------------------------------------------------------- seeds and contracts
eq(K.hash("faction", 1234, "daily", 20261010, "vigil", 1), 840941837, "hash is the same in every interpreter")
local rnd = K.rng(K.hash("x"))
eq(rnd(1, 100), 98, "rng 1")
eq(rnd(1, 100), 63, "rng 2")
local ctx = {families = function(cat) return cat == "humans" and 0 or 5 end, riftCfg = rcfg,
	itemName = function(id, nn) return nn == 1 and "rune shard" or "rune shards" end}
local function levelAt(lv) return function() return lv end end
local a1 = K.contracts(cfg, idx, "daily", D, 1234, levelAt(300), ctx)
local a2 = K.contracts(cfg, idx, "daily", D, 1234, levelAt(300), ctx)
eq(#a1, 8, "two daily contracts per faction")
local same = true
for k, c in ipairs(a1) do
	if c.key ~= a2[k].key or c.kind ~= a2[k].kind or c.count ~= a2[k].count or c.label ~= a2[k].label then same = false end
end
check(same, "same character, same day: same contracts")
local differs = false
for _, other in ipairs({{1235, D}, {1234, D + 1}}) do
	local b2 = K.contracts(cfg, idx, "daily", other[2], other[1], levelAt(300), ctx)
	for k, c in ipairs(a1) do
		if c.kind ~= b2[k].kind or c.count ~= b2[k].count or c.label ~= b2[k].label then differs = true end
	end
end
check(differs, "other character or day: other contracts")
local perFaction = {}
for _, c in ipairs(a1) do
	perFaction[c.faction] = perFaction[c.faction] or {}
	check(not perFaction[c.faction][c.kind], c.key .. ": kinds differ within a faction's day")
	perFaction[c.faction][c.kind] = true
	eq(c.rep, cfg.contracts.rep.daily, c.key .. " rep")
	if c.kind == "kill" then
		check(c.cat ~= "humans", "a family without monsters in the window is not offered")
		eq(c.minLevel, 120, "kill window from 40% of the level")
		eq(c.count % 10, 0, "kill count in steps")
		local f = idx.byKey[c.faction]
		local inFaction = false
		for _, cc in ipairs(f.categories) do if cc == c.cat then inFaction = true end end
		check(inFaction, c.key .. ": family of the faction")
	elseif c.kind == "rift" then
		eq(c.tier, 3, "rift tier: level 300 opens tier 4, minus one")
		eq(c.theme, idx.byKey[c.faction].theme, "rift theme of the faction")
	elseif c.kind == "deliver" then
		eq(c.gold, 45000, "deliver gold at level 300")
		check(c.items[1].count >= 15 and c.items[1].count <= 25, "deliver shards")
	end
end
local wk = K.contracts(cfg, idx, "weekly", W, 1234, levelAt(300), ctx)
eq(#wk, 4, "one weekly contract per faction")
for _, c in ipairs(wk) do
	eq(c.rep, cfg.contracts.rep.weekly, c.key .. " weekly rep")
	check(c.key:sub(1, 2) == "w:", "weekly key")
end
-- a level-1 character gets no rift contracts (no tier to open), everything still fills
local low = K.contracts(cfg, idx, "daily", D, 99, levelAt(10), {families = function() return 3 end, riftCfg = rcfg})
for _, c in ipairs(low) do
	check(c.kind ~= "rift", "no rift below tier 1")
end
eq(#low, 8, "low level still two per faction")
eq(K.riftTierFor(99, rcfg), 0, "level 99: no rift")
eq(K.riftTierFor(100, rcfg), 1, "level 100: tier 1")
eq(K.riftTierFor(950, rcfg), 12, "beyond the table: +1 per 25 levels")
-- matching and progress
local kc = {kind = "kill", cat = "undead", minLevel = 100, count = 3}
check(K.matchKill(kc, {cat = "undead", level = 120}), "kill matches")
check(not K.matchKill(kc, {cat = "undead", level = 90}), "too low")
check(not K.matchKill(kc, {cat = "demons", level = 120}), "other family")
local rc = {kind = "rift", theme = "Ashen Crypt", tier = 5, count = 1}
check(K.matchRift(rc, "Ashen Crypt", 6), "rift matches")
check(not K.matchRift(rc, "Ashen Crypt", 4), "rift tier too low")
check(not K.matchRift(rc, "Obsidian Hall", 9), "other theme")
check(K.matchEvent({kind = "invasion"}, "invasion"), "event")
local p, done = K.advance(kc, 2, 1)
check(p == 3 and done, "advance completes")
p, done = K.advance(kc, 3, 1)
check(p == 3 and not done, "complete stays")

-- ---------------------------------------------------------------- quartermaster
local helm = idx.offers.vigil_helm
eq((K.offerState(cfg, idx, helm, {ranks = {vigil = 4}})), "locked", "Trusted cannot buy Honored")
local s1, why = K.offerState(cfg, idx, helm, {ranks = {vigil = 5}})
eq(s1, "ok", "Honored can")
check(why == nil, "no reason")
local orbsOffer = idx.offers.vigil_ash5
eq((K.offerState(cfg, idx, orbsOffer, {ranks = {vigil = 4}, weekly = {vigil_ash5 = 3}})), "soldout", "weekly limit")
eq((K.offerState(cfg, idx, idx.offers.vigil_recipe, {ranks = {vigil = 5}, owned = {vigil_recipe = true}})), "owned", "recipe owned")
local gm = K.gearMods(helm, M)
eq(#gm, 3, "three modifiers")
eq(gm[1].key, "monsterreduction", "first modifier")
eq(gm[1].tier, 5, "its tier")
eq(gm[1].value, 2, "middle of T5 2-3")
eq(K.modText(gm[1]), "Damage Taken from Monsters -2%", "text")
local axe = K.gearMods(idx.offers.compact_axe, M)
eq(axe[1].value, 12, "bossdamage T7 10-14 -> 12")
eq(K.tokenChance(cfg, "rare"), 120, "token chance")

-- ---------------------------------------------------------------- titles and payload
local st7 = {}
K.set(cfg, st7, "vigil", 18000, nil)
local titles = K.titlesOf(cfg, idx, st7)
eq(#titles, 2, "Honored and Revered titles")
eq(titles[1].text, "Pyrewarden", "Honored title")
K.set(cfg, st7, "circle", 36000, 5)
titles = K.titlesOf(cfg, idx, st7)
eq(#titles, 5, "plus three of the Circle")
eq(titles[5].frame, "verdant", "Exalted title brings the frame")
K.set(cfg, st7, "circle", 20000, 5)
eq(#K.titlesOf(cfg, idx, st7), 5, "an Exalted title stays once earned")
local pl = K.payload(cfg, idx, st7, {now = sat, day = D, week = W, contracts = a1, owned = {}, weekly = {},
	near = "vigil", tokens = {vigil = 7}, itemMods = M, itemName = function(id) return "item" end})
eq(#pl.factions, 4, "payload factions")
eq(pl.factions[1].near, true, "near the Vigil NPC")
eq(pl.factions[1].tok, 7, "tokens carried")
eq(pl.factions[1].rn, "Revered", "rank name")
eq(#pl.contracts, 8, "payload contracts")
eq(#pl.offers, 32, "payload offers")
eq(#pl.ranks, 7, "payload ranks")
local helmRow
for _, o in ipairs(pl.offers) do
	if o.key == "vigil_helm" then helmRow = o end
end
eq(helmRow.st, "ok", "helm buyable at Revered")
eq(#helmRow.mods, 3, "helm modifier lines")
eq(helmRow.mods[1], "T5 Damage Taken from Monsters -2%", "helm line")

-- ---------------------------------------------------------------- factions.lua against a mocked engine
local registry, globals, spawnCb, talks = {}, {}, nil, {}
function CreatureEvent(name)
	local o = {}
	function o:type() end
	function o:register() registry[name] = o end
	return o
end
function GlobalEvent(name)
	local o = {}
	function o:register() globals[name] = o end
	function o:interval() end
	return o
end
function TalkAction(words)
	local o = {}
	function o:separator() end
	function o:register() talks[words] = o end
	return o
end
EventCallback = setmetatable({register = function() end}, {__newindex = function(_, k, v) if k == "onSpawn" then spawnCb = v end end})
local queue = {}
function addEvent(fn, delay, ...) queue[#queue + 1] = {fn = fn, args = {...}} return #queue end
local function runEvents()
	while #queue > 0 do
		local e = table.remove(queue, 1)
		e.fn((table.unpack or unpack)(e.args))
	end
end
local queries = {}
db = {query = function(q) queries[#queries + 1] = q return true end, escapeString = function(s) return "'" .. tostring(s) .. "'" end,
	storeQuery = function() return false end}
db.asyncQuery = db.query
local sent = {}
json = {encode = function(t) sent[#sent + 1] = t return "{}" end, decode = function(s) return s end}
Chaos.decode = function(buffer) return buffer end
local realTime = os.time
os.time = function(tt) if tt then return realTime(tt) end return sat end
math.random = function(a, b) return a end -- every roll succeeds (token chance)
local creatures, nextId, players = {}, 1000, {}
Position = function(x, y, z) return {x = x, y = y, z = z, sendMagicEffect = function() end} end
local function mkPlayer(name, guid, level, pos)
	local pl2 = {name = name, guid = guid, level = level, pos = pos, items = {}, msgs = {}, ops = {}, money = 5000000,
		auras = {}, mounts = {}, events = {}}
	nextId = nextId + 1
	pl2.id = nextId
	function pl2:getId() return self.id end
	function pl2:getGuid() return self.guid end
	function pl2:getName() return self.name end
	function pl2:getLevel() return self.level end
	function pl2:isPlayer() return true end
	function pl2:isMonster() return false end
	function pl2:isNpc() return false end
	function pl2:getMaster() return nil end
	function pl2:getParty() return self.party end
	function pl2:getPosition() return self.pos end
	function pl2:getItemCount(id) return self.items[id] or 0 end
	function pl2:addItem(id, nn) self.items[id] = (self.items[id] or 0) + (nn or 1) return true end
	function pl2:removeItem(id, nn) if (self.items[id] or 0) < nn then return false end self.items[id] = self.items[id] - nn return true end
	function pl2:addItemEx(item) self.gear = self.gear or {} table.insert(self.gear, item) return RETURNVALUE_NOERROR end
	function pl2:getInbox() return nil end
	function pl2:getMoney() return self.money end
	function pl2:getBankBalance() return 0 end
	function pl2:removeTotalMoney(g) if self.money < g then return false end self.money = self.money - g return true end
	function pl2:sendTextMessage(_, text) self.msgs[#self.msgs + 1] = text end
	function pl2:sendExtendedOpcode(op, data) self.ops[#self.ops + 1] = {op, data} return true end
	function pl2:registerEvent(e) self.events[e] = true end
	function pl2:getGroup() return {getId = function() return self.group or 1 end, getAccess = function() return (self.group or 1) >= 4 end} end
	function pl2:addAura(id) self.auras[id] = true end
	function pl2:addMount(id) self.mounts[id] = true end
	function pl2:getVocation() return {getId = function() return 4 end} end
	creatures[pl2.id] = pl2
	players[#players + 1] = pl2
	return pl2
end
Player = function(x)
	if type(x) == "table" then return x end
	for _, p2 in ipairs(players) do
		if p2.id == x or p2.name == x then return p2 end
	end
	return nil
end
local function mkNpc(name, pos)
	nextId = nextId + 1
	local c = {id = nextId, name = name, pos = pos}
	function c:isNpc() return true end
	function c:getName() return self.name end
	creatures[c.id] = c
	return c
end
Game = {
	getSpectators = function(pos, _, _, r)
		local out = {}
		for _, c in pairs(creatures) do
			if c.pos and c.pos.z == pos.z and math.abs(c.pos.x - pos.x) <= r and math.abs(c.pos.y - pos.y) <= r then out[#out + 1] = c end
		end
		return out
	end,
	getPlayers = function() return players end,
	createNpc = function(name, pos) return mkNpc(name, pos) end,
	createItem = function(id, nn)
		local item = {id = id, attrs = {}, custom = {}, removed = false}
		function item:setAttribute(k, v) self.attrs[k] = v end
		function item:setCustomAttribute(k, v) self.custom[k] = v end
		function item:remove() self.removed = true end
		return item
	end
}
ItemType = function(id)
	return {getId = function() return id end, getName = function() return "item" .. id end,
		getPluralName = function() return "items" .. id end}
end
local temples = {Cinderhold = {x = 100, y = 100, z = 7}, Thornmere = {x = 300, y = 100, z = 7}, Bellwatch = {x = 500, y = 100, z = 7}}
Town = function(x)
	local t = temples[x] or (x == 1 and {x = 700, y = 100, z = 7}) or nil
	return t and {getTemplePosition = function() return t end} or nil
end
Tile = function(pos)
	return {getGround = function() return true end, hasProperty = function() return false end,
		getTopCreature = function() return nil end, hasFlag = function() return false end}
end
-- the bestiary catalogue and the other systems the hooks read
ChaosBestiary = {cat = function()
	return {byKey = {
		["skeleton warrior"] = {name = "Skeleton Warrior", cat = "undead", level = 200, spawns = 10},
		["dragon"] = {name = "Dragon", cat = "dragons", level = 150, spawns = 10},
		["rat"] = {name = "Rat", cat = "beasts", level = 4, spawns = 10},
		["ghoul"] = {name = "Ghoul", cat = "undead", level = 15, spawns = 10}}}
end, catNames = {undead = "Undead"}}
ChaosTierDead = {}
local recorded = {}
ChaosLeaderboard = {record = function(board, who, value, mode)
	recorded[#recorded + 1] = {board = board, who = who, value = value}
	return {}
end}
local wbOriginal = 0
ChaosWorldBoss = {computeRewards = function() wbOriginal = wbOriginal + 1 return {} end}
local invDelivered = 0
ChaosInvasion = {state = {factionKey = "undead"}, deliver = function() invDelivered = invDelivered + 1 end}
ChaosRift = {runOf = {}}
ChaosRiftConfig = rcfg
local titleSources = {}
ChaosTitles = {register = function(source, fn) titleSources[source] = fn end}
local ach = {}
ChaosAchievements = {set = function(who, key, v) ach[key] = v end}
Chaos.isMultiClient = function() return false end
-- crafting: the real item modifier library, a recording ChaosCrafting
local written = {}
ChaosCrafting = {
	isGear = function() return true end, clearMods = function() end, applyBaseBonus = function() end,
	affixOf = function(key) return {key = key} end,
	writeAffix = function(item, affix, tier, value) written[#written + 1] = {affix.key, tier, value} end,
	rewriteDescription = function() end}
M.kindOf = function(item) return ({[2491] = "helmet"})[item.id] end
local logged = {}
local print_ = print
print = function(s) logged[#logged + 1] = s end
dofile("data/scripts/chaos/bestiary_core.lua") -- the party credit
dofile("data/scripts/chaos/factions.lua")
local F = ChaosFactions
check(registry.ChaosFactionsDeath and registry.ChaosFactionsExtended and registry.ChaosFactionsLogin, "events registered")
check(spawnCb ~= nil and talks["/faction"] ~= nil, "spawn callback and staff command")
check(titleSources.faction ~= nil, "titles registered")
check(ChaosLeaderboard.factionsWrapped and ChaosWorldBoss.factionsWrapped and ChaosInvasion.factionsWrapped, "hooks installed")
-- startup: NPCs next to their temples
globals.ChaosFactionsStartup.onStartup()
runEvents()
local npcs = {}
for _, c in pairs(creatures) do if c.isNpc and c:isNpc() then npcs[c.name] = c end end
check(npcs["Warden Ysolde"] and npcs["Warden Ysolde"].pos.x == 104, "Vigil NPC in Cinderhold")
check(npcs["Cantor Velith"] and npcs["Cantor Velith"].pos.x == 504, "Choir NPC in Bellwatch")
check(npcs["Forgemaster Brannoc"] and npcs["Elder Bramwyn"], "all four placed")
-- a player at level 300 next to the Vigil NPC, partied with a friend
local hero = mkPlayer("Hero", 501, 300, Position(104, 98, 7))
local friend = mkPlayer("Friend", 502, 300, Position(106, 98, 7))
local party = {getMembers = function() return {friend} end, getLeader = function() return hero end}
hero.party, friend.party = party, party
registry.ChaosFactionsLogin.onLogin(hero)
registry.ChaosFactionsLogin.onLogin(friend)
check(hero.events.ChaosFactionsExtended, "opcode event at login")
-- a monster spawns and gets the death event
nextId = nextId + 1
local mob = {id = nextId, typeName = "Skeleton Warrior", events = {}}
function mob:getId() return self.id end
function mob:getMaster() return nil end
function mob:getName() return self.typeName end
function mob:isMonster() return true end
function mob:isPlayer() return false end
function mob:registerEvent(e) self.events[e] = true end
function mob:getType() local tn = self.typeName return {name = function() return tn end} end
check(spawnCb(mob) == true and mob.events.ChaosFactionsDeath, "death event on spawned monsters")
-- ten rare kills: 8 points each -> 8 reputation per 10 points; every kill drops a token (math.random = 1)
local corpseItems = {}
local corpse = {isContainer = function() return true end, addItem = function(_, id, nn) corpseItems[id] = (corpseItems[id] or 0) + nn return {} end}
for _ = 1, 10 do
	ChaosTierDead[mob.id] = {tier = "rare"}
	registry.ChaosFactionsDeath.onDeath(mob, corpse, hero, hero)
end
local P = F.players[501]
eq(P.st.vigil.rep, 8, "kills: 80 points -> 8 reputation")
eq(F.players[502].st.vigil.rep, 8, "the party member in range is credited")
eq(P.st.choir.rep, -2, "rival lost a quarter (fractions carried)")
eq(corpseItems[cfg.tokens.vigil.id], 10, "tokens into the corpse")
-- a low monster gives nothing
local before = P.st.vigil.rep
mob.typeName = "Ghoul"
for _ = 1, 20 do registry.ChaosFactionsDeath.onDeath(mob, corpse, hero, hero) end
eq(P.st.vigil.rep, before, "monsters under 40% of the level give no reputation")
-- contracts: a kill contract of the Vigil progresses with the right kills
local contracts = F.contractsOf(hero)
eq(#contracts, 12, "8 daily + 4 weekly contracts")
local killC
for _, c in ipairs(contracts) do
	if c.kind == "kill" and c.faction == "vigil" then killC = c end
end
if killC then
	mob.typeName = "Skeleton Warrior"
	killC.cat = "undead"
	local p0 = killC.progress
	registry.ChaosFactionsDeath.onDeath(mob, nil, hero, hero)
	eq(killC.progress, p0 + 1, "kill contract progress")
	killC.progress = killC.count - 1
	local repBefore = P.st.vigil.rep
	registry.ChaosFactionsDeath.onDeath(mob, nil, hero, hero)
	check(killC.done, "kill contract done")
	check(P.st.vigil.rep >= repBefore + cfg.contracts.rep.daily, "contract reputation paid")
end
-- the contract rows were written with the level of the first look
local inserted = 0
for _, q in ipairs(queries) do
	if q:find("INSERT INTO `chaos_faction_contracts`", 1, true) then inserted = inserted + 1 end
end
check(inserted >= 12, "contract rows written (" .. inserted .. ")")
-- rift seal through the wrapped leaderboard (theme Ashen Crypt, tier 6), counted once even when called twice
local run = {themeName = "Ashen Crypt", key = {tier = 6}}
ChaosRift.runOf[hero.id] = run
local repR = P.st.vigil.rep
local tokR = hero.items[cfg.tokens.vigil.id] or 0
local riftC
for _, c in ipairs(F.contractsOf(hero)) do
	if c.kind == "rift" and c.faction == "vigil" and not c.done then riftC = c end
end
ChaosLeaderboard.record("rift", hero, 6)
local afterFirst = P.st.vigil.rep
ChaosLeaderboard.record("rift", hero, 6)
eq(afterFirst - repR, cfg.sources.rift.base + 6 * cfg.sources.rift.perTier + (riftC and riftC.count == 1 and riftC.tier <= 6
	and cfg.contracts.rep[riftC.period] or 0), "rift seal reputation (and a rift contract of the Vigil)")
eq(P.st.vigil.rep, afterFirst, "a second record of the same run counts nothing")
eq((hero.items[cfg.tokens.vigil.id] or 0) - tokR, 2, "rift seal tokens (1 + tier 6 / 5)")
check(recorded[1] and recorded[1].board == "rift", "the original record still runs")
-- bounty: the finished contract's monster names the faction
ChaosBounty = {players = {[501] = {entries = {c1 = {status = 1, day = 1, monster = "Dragon"}}}}}
local repC = P.st.choir.rep
ChaosLeaderboard.record("bounty", hero, 1)
ChaosLeaderboard.record("bounty", hero, 1)
eq(P.st.choir.rep - repC, cfg.sources.bounty, "bounty reputation once")
-- world boss: Vharok -> Vigil, and the world boss contract
local repW = P.st.vigil.total
ChaosWorldBoss.computeRewards({{guid = 501, name = "Hero"}}, {}, {name = "Vharok the Blood Colossus"})
eq(wbOriginal, 1, "world boss original ran")
eq(P.st.vigil.total - repW, cfg.sources.worldBoss, "world boss reputation (rivalry from a Choir contract may lower the rep itself)")
-- invasion: an Undead Legion reward -> Vigil
local repI = P.st.vigil.total
local invBonus = 0
for _, c in ipairs(F.contractsOf(hero)) do
	if c.kind == "invasion" and c.faction == "vigil" and not c.done then invBonus = c.rep end
end
local reward = {guid = 501}
ChaosInvasion.deliver(hero, reward)
ChaosInvasion.deliver(hero, reward)
eq(invDelivered, 2, "invasion original ran")
eq(P.st.vigil.total - repI, cfg.sources.invasion + invBonus, "invasion reputation once (and a Vigil invasion contract)")
-- token turn-in at the NPC
hero.items[cfg.tokens.vigil.id] = 5
local repT = P.st.vigil.rep
registry.ChaosFactionsExtended.onExtendedOpcode(hero, 215, {action = "turnin", data = {f = "vigil"}})
eq(hero.items[cfg.tokens.vigil.id], 0, "tokens taken")
check(P.st.vigil.rep > repT, "tokens give reputation")
-- away from the Choir NPC: refused
hero.items[cfg.tokens.choir.id] = 3
registry.ChaosFactionsExtended.onExtendedOpcode(hero, 215, {action = "turnin", data = {f = "choir"}})
eq(hero.items[cfg.tokens.choir.id], 3, "turn-in needs the faction's NPC")
-- buying: the helm needs Honored
registry.ChaosFactionsExtended.onExtendedOpcode(hero, 215, {action = "buy", data = {key = "vigil_helm"}})
check(hero.gear == nil, "locked offer refused")
K.set(cfg, P.st, "vigil", 9000, nil)
hero.items[cfg.tokens.vigil.id] = 12
local gold0 = hero.money
registry.ChaosFactionsExtended.onExtendedOpcode(hero, 215, {action = "buy", data = {key = "vigil_helm"}})
check(hero.gear and #hero.gear == 1, "gear bought")
eq(gold0 - hero.money, idx.offers.vigil_helm.price, "gold taken")
eq(hero.items[cfg.tokens.vigil.id], 2, "tokens taken for gear")
local g = hero.gear[1]
eq(g.custom.rarity, 4, "gear rarity")
eq(g.custom[M.ILVL], 100, "gear item level")
eq(#written, 3, "three modifiers written")
eq(written[1][1], M.attr("monsterreduction"), "modifier key")
eq(written[1][2], 5, "fixed tier")
eq(written[1][3], 2, "fixed value")
-- orbs with a weekly limit (Trusted)
local before2 = hero.items[29856] or 0
for _ = 1, 4 do
	registry.ChaosFactionsExtended.onExtendedOpcode(hero, 215, {action = "buy", data = {key = "vigil_ash5"}})
end
eq((hero.items[29856] or 0) - before2, 15, "three bundles a week")
-- the window payload goes out
sent = {}
registry.ChaosFactionsExtended.onExtendedOpcode(hero, 215, {action = "open", data = {f = "vigil"}})
local state
for _, s in ipairs(sent) do if s.action == "state" then state = s.data end end
check(state ~= nil and #state.factions == 4 and state.sel == "vigil", "state sent")
eq(state and state.factions[1].near, true, "near flag")
-- titles
local t = titleSources.faction(hero)
check(#t >= 1 and t[1].text == "Pyrewarden", "Honored title")
-- staff command sets Exalted and the achievement stats
hero.group = 5
talks["/faction"].onSay(hero, "/faction", "Friend, circle, 36000")
eq(F.players[502].st.circle.rep, 36000, "staff set")
eq(ach.faction_exalted_circle, 1, "achievement stat")
eq(ach.faction_exalted, 1, "achievement count")
-- logout flushes the board
registry.ChaosFactionsLogout.onLogout(hero)
local board
for _, rr in ipairs(recorded) do if rr.board == "factions" then board = rr end end
check(board ~= nil and board.value > 0, "weekly Reputation board fed at logout")
check(F.players[501] == nil, "state dropped at logout")

print = print_
check(#logged >= 1 and logged[1]:find("4 faction NPC", 1, true) ~= nil, "startup log")
print(string.format("factions_test: %s (%d checks)", failures == 0 and "OK" or (failures .. " FAILED"), count))
if failures > 0 then
	os.exit(1)
end
