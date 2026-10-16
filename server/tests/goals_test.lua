-- Run from the server/ folder: luajit tests/goals_test.lua (and lua5.3; CI runs both). Next Goals (goals_core.lua,
-- goals_config.lua, goals.lua on a mocked engine): the config (every band, goal and text in both languages, the hunts
-- against the area plans and the hunt teleports, the stats against what the achievements and the other systems count,
-- the windows against the client modules, the NPCs against data/npc), the bands, the retro marking, the evaluation,
-- the rewards, the panel and the tracker, the effort texts; the engine: load, check and reward once, the hooks, the
-- panel request, the opcode.

local checks, failures = 0, 0
local function check(cond, label)
	checks = checks + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, label .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end
local function readFile(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local s = f:read("*a")
	f:close()
	return s
end

dofile("data/scripts/chaos/goals_core.lua")
local K = ChaosGoalsCore
local cfg = dofile("data/scripts/chaos/goals_config.lua")

-- ---------------------------------------------------------------- the config
local problems = K.validate(cfg)
for _, p in ipairs(problems) do
	print("  " .. p)
end
eq(#problems, 0, "goals_config.lua validates")
eq(cfg.bands[1].from, 1, "first band at level 1")
check(cfg.bands[#cfg.bands].from >= 2000, "a band for level 2000 and beyond")
check(#cfg.goals >= 60, "goals for the whole level range (" .. #cfg.goals .. ")")
-- every band has goals
for i, b in ipairs(cfg.bands) do
	local n = 0
	for _, g in ipairs(cfg.goals) do
		if K.bandOf(cfg, g.level) == i then
			n = n + 1
		end
	end
	check(n >= 2, "band " .. b.key .. " has goals (" .. n .. ")")
end
-- the unlock milestones of the brief are goals
local byKey = {}
for _, g in ipairs(cfg.goals) do
	byKey[g.key] = g
end
for key, level in pairs({ascend = 100, wb1 = 300, raid1 = 800, omen1 = 800, ascended1 = 900, cinder1 = 1000, vault = 800,
	marrow = 1000, crucible = 1300, sanctum = 1600, throne = 2000, passive1 = 12, bounty1 = 8, pocket1 = 150,
	tokens100 = 150, trusted = 120}) do
	check(byKey[key] ~= nil, "goal " .. key)
	eq(byKey[key] and byKey[key].level, level, "goal " .. key .. " level")
end

-- the content hunts: the same as the area plans (name and level band) and every plan of the hunt teleports
local planned = {}
for _, h in ipairs(cfg.hunts) do
	local json = readFile("tools/areaplan/plans/" .. h.id .. ".json")
	check(json ~= nil, "plan file of " .. h.id)
	if json then
		local name = json:match('"name"%s*:%s*"([^"]+)"')
		local lo, hi = json:match('"level"%s*:%s*%[%s*(%d+)%s*,%s*(%d+)%s*%]')
		eq(name, h.name, h.id .. " name")
		eq(tonumber(lo), h.level[1], h.id .. " level from")
		eq(tonumber(hi), h.level[2], h.id .. " level to")
	end
	planned[h.id] = true
end
local ht = dofile("data/scripts/chaos/hunt_teleports_config.lua")
for _, p in ipairs(ht.plans) do
	check(planned[p.id], "hunt teleport plan " .. p.id .. " is in goals_config.lua hunts")
end
eq(cfg.room.x, ht.room.back.x, "room x")
eq(cfg.room.y, ht.room.back.y, "room y")
eq(cfg.room.z, ht.room.back.z, "room z")

-- every stat is counted somewhere: the level, an own stat, an achievement stat, or a counter another script feeds
local counted = {level = true}
for k in pairs(cfg.own) do
	counted[k] = true
end
local ach = readFile("data/scripts/chaos/achievements_data.lua")
for s in ach:gmatch('stat = "([%w_]+)"') do
	counted[s] = true
end
local areagen = readFile("data/scripts/chaos/areagen_config.lua")
for _, g in ipairs(cfg.goals) do
	local d = g.stat:match("^dungeon_(%a+)$") or g.stat:match("^dungeon_(%a+)_d6$")
	if d and d ~= "clears" then
		check(areagen:find('id = "' .. d .. '"', 1, true) ~= nil, g.key .. ": a generated dungeon " .. d)
		counted[g.stat] = true
	end
end
check(readFile("data/scripts/chaos/invasion.lua"):find('"invasion_kills"', 1, true) ~= nil, "invasion_kills is counted")
counted.invasion_kills = true
for _, g in ipairs(cfg.goals) do
	check(counted[g.stat], g.key .. ": stat " .. g.stat .. " is counted")
end
-- the journey's emit lines feed the own stats named after them
for _, s in ipairs({"dungeon_clears", "descent_runs", "descent_clears", "atlas_points"}) do
	check(cfg.own[s] ~= nil, "own stat " .. s)
end

-- every window exists as a client module (game_conquest is optional: guarded by `requires`), every NPC has a file
local function eachWhere(fn)
	for _, g in ipairs(cfg.goals) do
		if g.where then
			fn(g.where, g.key, g.requires)
		end
	end
	for _, b in ipairs(cfg.bands) do
		for i, g in ipairs(b.gear) do
			if g.where then
				fn(g.where, b.key .. " gear " .. i, g.requires)
			end
		end
	end
end
eachWhere(function(w, label, requires)
	if w.k == "window" then
		local otmod = io.open("../client/overlay/modules/" .. w.m .. "/" .. w.m .. ".otmod", "r")
			or io.open("../client/overlay/modules/" .. w.m .. "/" .. w.m:gsub("^game_", "") .. ".otmod", "r")
		local any = otmod ~= nil
		if otmod then
			otmod:close()
		else
			local p = io.popen("ls ../client/overlay/modules/" .. w.m .. "/*.otmod 2>/dev/null")
			any = p and p:read("*a") ~= ""
			if p then
				p:close()
			end
		end
		check(any or requires ~= nil, label .. ": client module " .. w.m)
	elseif w.k == "npc" then
		check(readFile("data/npc/" .. w.name .. ".xml") ~= nil, label .. ": NPC " .. w.name)
	elseif w.k == "plan" then
		check(planned[w.id], label .. ": plan " .. w.id)
	end
end)

-- the website's progression guide (wiki guides, EN and pt-BR) has one section per band, named as the panel names it
for lang, word in pairs({en = "Level", ["pt-BR"] = "Nível"}) do
	local md = readFile("../website/overlay/plugins/chaos/wiki/guides/progression." .. lang .. ".md")
	check(md ~= nil, "progression guide " .. lang)
	for i, b in ipairs(cfg.bands) do
		local to = K.bandTo(cfg, i)
		local head = string.format("\n## %s %d%s: %s\n", word, b.from, to and ("-" .. to) or "+",
			K.text(b.name, lang == "en" and "en" or "pt"))
		check(md and md:find(head, 1, true) ~= nil, "progression guide " .. lang .. " has" .. head:gsub("\n", " "))
	end
end

-- ---------------------------------------------------------------- bands
eq(K.bandOf(cfg, 1), 1, "level 1")
eq(select(2, K.bandOf(cfg, 99)).key, "adept", "level 99")
eq(select(2, K.bandOf(cfg, 100)).key, "ascend", "level 100")
eq(select(2, K.bandOf(cfg, 2500)).key, "apex", "level 2500")
eq(K.bandTo(cfg, 1), 19, "first band ends at 19")
eq(K.bandTo(cfg, #cfg.bands), nil, "last band is open")
eq(K.bandEntered(cfg, 99, 100), 4, "entered the ascension band")
eq(K.bandEntered(cfg, 100, 101), nil, "no band entered")
eq(K.bandEntered(cfg, 290, 805), 8, "a jump: the last band entered")
eq(K.lang("pt-BR"), "pt", "pt-BR")
eq(K.lang(nil), "en", "default en")
eq(K.text({en = "a", pt = "b"}, "pt"), "b", "pt text")
eq(K.text("x", "pt"), "x", "plain text")

-- ---------------------------------------------------------------- evaluation
local ctx = {level = 15, stats = {kills_magic = 3, bounty_done = 0}, done = {}, systems = {}, now = 100}
local done = K.evaluate(cfg, ctx)
local names = {}
for _, g in ipairs(done) do
	names[g.key] = true
end
check(names.lvl8 and names.magic1, "level 8 and a magic monster done")
check(not names.bounty1 and not names.passive1, "not the others")
eq(#K.evaluate(cfg, ctx), 0, "never twice")
ctx.stats.passive_spent = 1
eq(K.evaluate(cfg, ctx)[1].key, "passive1", "passive point")
-- a goal above the level is not done even at its target
ctx.stats.bestiary_tasks = 4
check(not ctx.done.task1 and #K.evaluate(cfg, ctx) == 0, "task1 waits for level 20")
ctx.level = 20
check(#K.evaluate(cfg, ctx) >= 2, "level 20: lvl20 and task1")
check(ctx.done.task1 ~= nil, "task1 now")
-- requires: hidden without the system
ctx.level, ctx.stats.pocket_kills = 150, 3
K.evaluate(cfg, ctx)
eq(ctx.done.pocket1, nil, "pocket1 needs ChaosPocketBoss")
ctx.systems.ChaosPocketBoss = true
K.evaluate(cfg, ctx)
check(ctx.done.pocket1 ~= nil, "pocket1 with the system")

-- retro: a level 850 character first seen; what it did below its band is marked, its band's goals are not
local old = {level = 850, stats = {kills_magic = 500, bounty_done = 40, rift_tier = 9, wb_kills = 2, raid_kills = 1},
	done = {}, systems = {}, now = 5}
local marked = {}
for _, key in ipairs(K.retro(cfg, old)) do
	marked[key] = true
end
check(marked.magic1 and marked.bounty25 and marked.rift8 and marked.wb1 and marked.lvl500, "retro marks the past")
check(not marked.raid1 and not marked.omen1, "retro leaves the own band (800-899)")
check(marked.lvl800, "the level goal of the band below")
check(not marked.wb5, "retro leaves what is not done")
local now = K.evaluate(cfg, old)
local nowKeys = {}
for _, g in ipairs(now) do
	nowKeys[g.key] = true
end
check(nowKeys.raid1 and not nowKeys.lvl800, "the own band is rewarded")
check(not nowKeys.magic1, "the past is not rewarded")

-- ---------------------------------------------------------------- rewards
eq(K.needXp(1), 100, "xp to level 2")
eq(K.needXp(2), 100, "xp to level 3 (TFS: 200 - 100)")
eq(K.needXp(100), 50 * 99 * 99 - 50 * 99 + 100, "xp at 100")
local rw = K.reward(cfg, byKey.wb1, 300)
eq(rw.xp, math.floor(K.needXp(300) * cfg.reward.xpPct / 100), "xp share")
eq(rw.gold, 300 * cfg.reward.goldPerLevel, "gold per level")
eq(rw.tokens, cfg.reward.tokens[6], "tokens of the band")
eq(K.reward(cfg, byKey.magic1, 1).gold, cfg.reward.goldMin, "gold minimum")
eq(K.reward(cfg, {key = "x", level = 1, reward = {gold = 7, tokens = 1, xpPct = 0}}, 50).gold, 7, "override")
eq(K.rewardShort({xp = 4000, gold = 2500, tokens = 3}, "en", true), "4,000 XP, 2,500 gold, 3 tokens", "short reward")
eq(K.rewardShort({xp = 0, gold = 5, tokens = 3}, "pt", false), "5 ouro", "short reward pt, no tokens")
-- rewards stay small: below a tenth of a level
for _, g in ipairs(cfg.goals) do
	local r = K.reward(cfg, g, g.level)
	check(r.xp <= K.needXp(g.level) / 10, g.key .. ": xp reward is small")
end

-- ---------------------------------------------------------------- the panel
local function resolve(w)
	if w.k == "npc" then
		return {x = 1, y = 2, z = 7}, w.name
	end
	return nil, "x"
end
local v = K.view(cfg, {level = 305, stats = {wb_kills = 0, rift_tier = 2}, done = {honored = 1, bounty1 = 1},
	systems = {ChaosConquest = true}, now = 1}, "pt-BR", resolve)
eq(v.header.band.key, "bosses", "band of 305")
eq(v.header.band.name, "Chefes mundiais", "band name in pt")
eq(v.header.next, 500, "next band")
eq(v.goals[1].key, "wb1", "first goal of the band")
eq(v.goals[1].state, "open", "open")
eq(v.goals[1].title, "Derrote um chefe mundial", "title in pt")
check(v.goals[1].where and v.goals[1].where.k == "info", "where of wb1")
local seen, states = {}, {}
for _, r in ipairs(v.goals) do
	seen[r.key] = r
	states[r.state] = (states[r.state] or 0) + 1
end
check(seen.honored and seen.honored.state == "done", "the band's done goal is listed as done")
check(seen.rift4 and seen.rift4.state == "open", "catch-up: rift4 of the band below")
check(not seen.pocket10, "pocket10 hidden without ChaosPocketBoss")
check(#v.goals <= 64, "a bounded list")
check(v.header.more >= 0, "more count")
eq(#v.upcoming, cfg.upcoming, "upcoming count")
eq(v.upcoming[1].state, "locked", "upcoming locked")
check(v.upcoming[1].level > 305, "upcoming above the level")
eq(v.upcoming[1].where, nil, "a locked goal has no button")
check(#v.gear >= 2, "gear path")
-- the token vendor gear line with ChaosConquest, without the pocket boss one
local hasTokens, hasPocket = false, false
for _, g in ipairs(v.gear) do
	hasPocket = hasPocket or g.text:find("bolso") ~= nil
end
local v2 = K.view(cfg, {level = 210, stats = {}, done = {}, systems = {ChaosConquest = true}}, "en", resolve)
for _, g in ipairs(v2.gear) do
	hasTokens = hasTokens or g.text:find("Conquest Tokens") ~= nil
	if g.where and g.where.k == "npc" then
		eq(g.where.pos and g.where.pos.z, 7, "resolved NPC position")
	end
end
check(hasTokens, "token vendor line with the system")
check(not hasPocket, "no pocket boss line without the system")
eq(#v2.hunts, 2, "hunts of level 210: Bonechoir and Sulphur")
eq(v2.hunts[1].id, "bonechoir_catacomb", "lowest band first")
eq(v2.hunts[1].where.k, "plan", "hunt where")
local v3 = K.view(cfg, {level = 30, stats = {}, done = {}}, "en", resolve)
eq(#v3.hunts, 0, "no content hunts at 30")
check(v3.hereWhere and v3.hereWhere.k == "hunts", "the nearby hunts instead")
-- level 2500: no next band, no upcoming
local v4 = K.view(cfg, {level = 2500, stats = {}, done = {}}, "en", resolve)
eq(v4.header.next, nil, "no next band")
eq(#v4.upcoming, 0, "nothing locked")
-- flags: a rank shows 0 / 1
local v5 = K.view(cfg, {level = 130, stats = {faction_rank = 3}, done = {}}, "en", resolve)
for _, r in ipairs(v5.goals) do
	if r.key == "trusted" then
		eq(r.target, 1, "flag target")
		eq(r.progress, 0, "flag progress")
	end
end
-- the payload stays a few KB at its largest band (Chaos.sendChunked splits it anyway)
local function size(t)
	local n = 0
	for k, x in pairs(t) do
		n = n + #tostring(k) + 4
		n = n + (type(x) == "table" and size(x) or #tostring(x))
	end
	return n
end
local biggest = 0
for _, b in ipairs(cfg.bands) do
	biggest = math.max(biggest, size(K.view(cfg, {level = b.from, stats = {}, done = {}, systems = {ChaosConquest = true,
		ChaosPocketBoss = true}}, "pt", resolve)))
end
check(biggest < 24000, "panel payload under 24 KB (" .. biggest .. ")")

-- the tracker
local t = K.tracker(cfg, {level = 305, stats = {wb_kills = 0}, done = {}}, "en", 3)
eq(#t, 3, "three tracked goals")
eq(t[1].key, "wb1", "tracker first")
check(t[1].title ~= nil and t[1].target ~= nil, "tracker row")

-- the live refresh: the level goal follows the level, a done goal is replaced by the next one
local ctx8 = {level = 8, stats = {}, done = {lvl8 = 1}}
local t8 = K.tracker(cfg, ctx8, "en", 3)
local function row(rows, key)
	for _, x in ipairs(rows) do
		if x.key == key then
			return x
		end
	end
end
eq(row(t8, "lvl20") and row(t8, "lvl20").progress, 8, "level 8: Reach level 20 at 8")
local t12 = K.tracker(cfg, {level = 12, stats = {passive_spent = 1}, done = {lvl8 = 1, passive1 = 1}}, "en", 3)
eq(row(t12, "lvl20") and row(t12, "lvl20").progress, 12, "level 12: Reach level 20 at 12")
check(K.sig(t8) ~= K.sig(t12), "a level up changes the tracker signature")
eq(K.sig(t12), K.sig(K.tracker(cfg, {level = 12, stats = {passive_spent = 1}, done = {lvl8 = 1, passive1 = 1}}, "en", 3)),
	"same view, same signature")
local tm = K.tracker(cfg, {level = 12, stats = {kills_magic = 1}, done = {lvl8 = 1, passive1 = 1, magic1 = 1}}, "en", 3)
check(not row(tm, "magic1") and row(tm, "bounty1") and row(tm, "lvl20"), "magic1 done: off the tracker")
local tb = K.tracker(cfg, {level = 20, stats = {}, done = {lvl8 = 1, passive1 = 1, magic1 = 1, bounty1 = 1, lvl20 = 1}},
	"en", 3)
eq(#tb, 3, "level 20: the next band's goals fill the tracker")
check(not row(tb, "bounty1") and row(tb, "task1"), "bounty1 replaced by task1")
-- a paced kill can count a fraction: whole numbers on the wire
eq(row(K.tracker(cfg, {level = 20, stats = {kills_tiered = 12.5}, done = {}}, "en", 9), "tiered50").progress, 12,
	"fractional counter floored")
eq(K.trackerOf(K.view(cfg, ctx8, "en"), 3)[1].key, t8[1].key, "trackerOf a view")
local v8 = K.view(cfg, {level = 8, stats = {}, done = {lvl8 = 1}}, "en")
local v9 = K.view(cfg, {level = 9, stats = {}, done = {lvl8 = 1}}, "en")
check(K.panelSig(v8, "en") ~= K.panelSig(v9, "en"), "panel signature follows the level")
check(K.panelSig(v8, "en") ~= K.panelSig(v8, "pt"), "panel signature follows the language")
-- the push queue: one push per minMs, coalesced
local push = {}
eq(K.queuePush(push, 1000, 1000, 250), 250, "first change: the coalesce delay")
eq(K.queuePush(push, 1100, 1000, 250), nil, "a change while queued merges")
K.pushed(push, 1250)
eq(K.queuePush(push, 1300, 1000, 250), 950, "the next push waits for minMs after the last")
eq(K.queuePush(push, 1400, 1000, 250), nil, "merged again")
K.pushed(push, 2250)
eq(K.queuePush(push, 9000, 1000, 250), 250, "idle: only the coalesce delay")

-- ---------------------------------------------------------------- effort
eq(K.oneIn(0), nil, "no chance")
eq(K.oneIn(1), 1, "certain")
eq(K.oneIn(0.1), 10, "1 in 10")
eq(K.oneIn(1 / 67), 65, "rounded to 5")
eq(K.oneIn(1 / 267), 270, "rounded to 10")
eq(K.oneIn(1 / 4321), 4300, "rounded to 50")
eq(K.oneIn(1 / 25000), 25000, "rounded to 100")
eq(K.effortText(1 / 400, "legendary", "en"), "~1 in 400 legendary kills", "effort text")
eq(K.effortText(1 / 1500, "boss", "pt"), "~1 em 1,500 chefes derrotados", "effort text pt")
eq(K.effortText(0), nil, "no text without a chance")

-- ---------------------------------------------------------------- storage helpers
local d, s = K.rowsToState({{entry = "g:wb1", value = 1, at = 9}, {entry = "s:pocket_kills", value = 4}, {entry = "junk"}})
eq(d.wb1, 9, "done row")
eq(s.pocket_kills, 4, "stat row")
local st = {}
eq(K.merge(st, "add", "a", 2), true, "add")
eq(K.merge(st, "add", "a", 0), false, "add 0")
eq(K.merge(st, "max", "a", 1), false, "max lower")
eq(K.merge(st, "max", "a", 5), true, "max higher")
eq(st.a, 5, "merged")

-- ---------------------------------------------------------------- the engine (goals.lua) on a mocked engine
local n = 0
setmetatable(_G, {__index = function(tb, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(tb, k, n); return n end
end})
dofile("data/scripts/chaos/chaos_constants.lua")
eq(ChaosOpcodes.goals, 178, "opcode")
local used = {}
for k, v2o in pairs(ChaosOpcodes) do
	check(not used[v2o] or used[v2o] == k, "opcode " .. v2o .. " used twice (" .. k .. ", " .. tostring(used[v2o]) .. ")")
	used[v2o] = k
end
for _, v2o in ipairs({1, 67, 73, 89, 91, 92, 99, 106, 107, 120, 136, 144, 145, 146, 181, 201, 202, 210, 212, 213, 230, 246}) do
	check(v2o ~= ChaosOpcodes.goals, "goals opcode collides with " .. v2o)
end
eq(Chaos.tables.goals, cfg.table, "table name")

json = {encode = function(x) return x end}
local sent, chunked, queries = {}, {}, {}
Chaos.send = function(player, op, action, data) sent[#sent + 1] = {op = op, action = action, data = data} end
Chaos.sendChunked = function(player, op, payload) chunked[#chunked + 1] = {op = op, payload = payload} end
Chaos.decode = function(b) return b end
Chaos.limited = function() return false end
Chaos.select = function() return {} end
db = {query = function(q) queries[#queries + 1] = q; return true end, escapeString = function(x) return "'" .. x .. "'" end}
local events, globals = {}, {}
function CreatureEvent(name)
	local o = {}
	function o:type() end
	function o:register() events[name] = o end
	return o
end
function GlobalEvent(name)
	local o = {}
	function o:interval() end
	function o:register() globals[name] = o end
	return o
end
local timers = {}
function addEvent(fn, ms, ...)
	timers[#timers + 1] = {fn = fn, args = {...}}
	return #timers
end
local function runTimers()
	while #timers > 0 do
		local list = timers
		timers = {}
		for _, e in ipairs(list) do
			e.fn((table.unpack or unpack)(e.args))
		end
	end
end
local players = {}
function Player(id) return players[id] end
Game = {getPlayers = function() local out = {} for _, p in pairs(players) do out[#out + 1] = p end return out end}
Creature = function(name)
	if name == "Ascendant Oracle" then
		return {isNpc = function() return true end, getPosition = function() return {x = 50, y = 60, z = 7} end}
	end
	return nil
end

local function newPlayer(id, guid, level)
	local p = {id = id, guid = guid, level = level, bank = 0, exp = 0, msgs = {}, ext = {}}
	function p:getId() return self.id end
	function p:getGuid() return self.guid end
	function p:getLevel() return self.level end
	function p:getGroup() return {getId = function() return 1 end} end
	function p:getTown() return {getTemplePosition = function() return {x = 10, y = 20, z = 7} end} end
	function p:getPosition() return {x = 11, y = 21, z = 7} end
	function p:registerEvent() end
	function p:addExperience(n) self.exp = self.exp + n end
	function p:getBankBalance() return self.bank end
	function p:setBankBalance(v) self.bank = v end
	function p:sendTextMessage(t, text) self.msgs[#self.msgs + 1] = text end
	function p:sendExtendedOpcode(op, data) self.ext[#self.ext + 1] = {op = op, data = data} end
	players[id] = p
	return p
end
setmetatable(_G, nil)
MESSAGE_EVENT_ADVANCE = 19
SKILL_LEVEL = 8
userdataType = nil

ChaosAchievements = {stats = {}}
function ChaosAchievements.progress(who, key, amount)
	local s = ChaosAchievements.stats[who:getGuid()]
	s[key] = (s[key] or 0) + (amount or 1)
	return true
end
function ChaosAchievements.set(who, key, value)
	local s = ChaosAchievements.stats[who:getGuid()]
	s[key] = math.max(s[key] or 0, value)
	return true
end
ChaosConquest = {grant = function(player, key, amount) return amount or 4 end}
ChaosConquestConfig = {sources = {goals = {slot = 21, amount = 1, cap = 50}}}
local granted = {}
local realGrant = ChaosConquest.grant
ChaosConquest.grant = function(player, key, amount, detail)
	granted[#granted + 1] = {key = key, amount = amount}
	return realGrant(player, key, amount)
end
ChaosPocketBoss = {}
local hasPassive = true
ChaosPassiveTree = {listeners = {}, hasAllocation = function() return hasPassive end}

-- goals.lua needs userdata players: the mock's tables count as players through this wrapper of `type`
local realType = type
type = function(x)
	if realType(x) == "table" and x.getGuid and x.getLevel then
		return "userdata"
	end
	return realType(x)
end
dofile("data/scripts/chaos/goals.lua")
local Gs = ChaosGoals
globals.ChaosGoalsStartup.onStartup()
check(queries[1] and queries[1]:find("CREATE TABLE IF NOT EXISTS `chaos_goals`", 1, true) ~= nil, "table created")

local p = newPlayer(1, 101, 160)
ChaosAchievements.stats[101] = {kills_magic = 20, bounty_done = 2, ascended = 1, rift_tier = 1, kills_legendary = 1,
	trial_tier_1 = 1}
events.ChaosGoalsLogin.onLogin(p)
runTimers()
local st = Gs.st[101]
check(st ~= nil, "loaded at login")
eq(st.stats.passive_spent, 1, "passive probe")
check(st.done.magic1 and st.done.bounty1 and st.done.ascend and st.done.rift1, "done at login")
check(p.exp > 0 and p.bank > 0, "rewarded")
local bankAfter = p.bank
check(#granted >= 1 and granted[1].key == "goals", "tokens through the goals source")
check(sent[#sent].action == "tracker", "tracker sent after the check")
eq(sent[#sent].op, 178, "on the goals opcode")
local doneMsgs = 0
for _, m in ipairs(p.msgs) do
	if m:find("^Goal done") then
		doneMsgs = doneMsgs + 1
	end
end
check(doneMsgs >= 4, "a message per goal (" .. doneMsgs .. ")")
-- a counter change through the achievements checks again (scheduled), once
ChaosAchievements.progress(p, "dungeon_clears_unused", 1)
eq(#timers, 1, "one scheduled check")
ChaosAchievements.progress(p, "kills_tiered", 60)
eq(#timers, 1, "still one")
runTimers()
check(st.done.tiered50 ~= nil, "tiered50 after the hook")
check(p.bank > bankAfter, "its reward")
-- the conquest hook: a pocket boss grant counts a kill and the tokens
ChaosConquest.grant(p, "pocketboss:kaelgor", 6)
eq(st.stats.pocket_kills, 1, "pocket kill counted")
check((st.stats.conquest_earned or 0) >= 6, "tokens counted")
runTimers()
check(st.done.pocket1 ~= nil, "pocket1 done")
-- the journey emit hook feeds the own stats
ChaosSeasonJourney = {emit = function() return true end}
Gs.installHooks()
ChaosSeasonJourney.emit(p, "dungeon_clears", 1)
eq(st.stats.dungeon_clears, 1, "dungeon clear from the journey emit")
ChaosSeasonJourney.emit(p, "unknown_stat", 1)
eq(st.stats.unknown_stat, nil, "other stats ignored")
-- emit API
eq(Gs.emit(p, "tower_floor", 12), true, "emit")
eq(Gs.emit(p, "nope", 1), false, "emit unknown")
runTimers()
-- the panel
local before = #chunked
events.ChaosGoalsExtended.onExtendedOpcode(p, 178, {action = "open"})
eq(#chunked, before + 1, "panel sent chunked")
local payload = chunked[#chunked].payload
eq(payload.action, "goals", "goals action")
eq(payload.data.header.band.key, "ascend", "band of 160")
eq(Gs.viewing[101], true, "viewing")
local oracle
for _, r in ipairs(payload.data.goals) do
	if r.key == "ascend" then
		oracle = r
	end
end
check(oracle and oracle.state == "done", "ascend done in the panel")
events.ChaosGoalsExtended.onExtendedOpcode(p, 178, {action = "close"})
eq(Gs.viewing[101], nil, "closed")
events.ChaosGoalsExtended.onExtendedOpcode(p, 99, {action = "open"})
eq(#chunked, before + 1, "other opcodes ignored")
-- resolver: an NPC on the map, else the temple
local r = Gs.resolver(p, "en")
local pos, label = r({k = "npc", name = "Ascendant Oracle"})
eq(pos.x, 50, "NPC position")
pos, label = r({k = "npc", name = "Nobody"})
eq(pos.x, 10, "temple fallback")
pos, label = r({k = "room"})
eq(pos.x, cfg.room.x, "room")
pos = r({k = "plan", id = "widowmere"})
eq(pos.x, cfg.room.x, "a plan without placed hunts: the room")
-- band entered message
local msgs = #p.msgs
p.level = 200
events.ChaosGoalsAdvance.onAdvance(p, SKILL_LEVEL, 199, 200)
check(#p.msgs == msgs + 1 and p.msgs[#p.msgs]:find("level 200", 1, true), "new band message")
-- logout flushes the own stats
local q = #queries
events.ChaosGoalsLogout.onLogout(p)
check(#queries > q, "own stats written at logout")
eq(Gs.st[101], nil, "forgotten")

-- the live refresh (the bug: "Reach level 20  8/20" at level 12; the tracker went out only at login and on a goal done)
local function lastTracker()
	for i = #sent, 1, -1 do
		if sent[i].action == "tracker" then
			return sent[i].data.rows, i
		end
	end
end
local function trackerRow(key)
	for _, x in ipairs((lastTracker())) do
		if x.key == key then
			return x
		end
	end
end
local function trackerCount()
	local c = 0
	for _, m in ipairs(sent) do
		if m.action == "tracker" then
			c = c + 1
		end
	end
	return c
end
hasPassive = false
local p2 = newPlayer(2, 202, 8)
ChaosAchievements.stats[202] = {}
events.ChaosGoalsLogin.onLogin(p2)
runTimers()
local st2 = Gs.st[202]
check(st2 and st2.done.lvl8, "level 8 done at login")
eq(trackerRow("lvl20") and trackerRow("lvl20").progress, 8, "login: Reach level 20 at 8")
check(trackerRow("magic1") and trackerRow("bounty1"), "login: magic1 and bounty1 tracked")
-- levels 9 to 12, one advance each: one queued run, one push
local pushes = trackerCount()
for lv = 9, 12 do
	p2.level = lv
	events.ChaosGoalsAdvance.onAdvance(p2, SKILL_LEVEL, lv - 1, lv)
end
eq(#timers, 1, "four level ups: one queued run")
runTimers()
eq(trackerCount(), pushes + 1, "one push for the four level ups")
-- three rows: magic1, bounty1 and passive1 (unlocked at 12, before lvl20 in the config) push out the level goal
check(trackerRow("passive1") ~= nil, "passive1 unlocked at 12 and tracked")
check(trackerRow("lvl20") == nil, "no stale Reach level 20 8/20")
-- a counter that changes nothing shown: no push
pushes = trackerCount()
ChaosAchievements.progress(p2, "party_kills", 1)
runTimers()
eq(trackerCount(), pushes, "no push when nothing shown changed")
-- a spent passive point (the tree's listener), live
check(#ChaosPassiveTree.listeners == 1, "passive listener added once")
Gs.installHooks()
eq(#ChaosPassiveTree.listeners, 1, "and only once")
hasPassive = true
ChaosPassiveTree.listeners[1](p2, {})
runTimers()
check(st2.done.passive1 ~= nil, "passive1 done after the save")
check(trackerRow("passive1") == nil, "passive1 off the tracker")
eq(trackerRow("lvl20") and trackerRow("lvl20").progress, 12, "level 12: Reach level 20 at 12")
-- a magic monster (achievements.lua kill event -> ChaosAchievements.progress)
ChaosAchievements.progress(p2, "kills_magic", 1)
ChaosAchievements.progress(p2, "kills_tiered", 1)
eq(#timers, 1, "one kill: one queued run")
runTimers()
check(st2.done.magic1 ~= nil, "magic1 done")
check(trackerRow("magic1") == nil and trackerRow("bounty1") ~= nil, "magic1 replaced on the tracker")
-- a bounty contract (bounty.lua -> ChaosLeaderboard.record "bounty" -> achievements.lua -> progress bounty_done)
local bountySrc = readFile("data/scripts/chaos/bounty.lua") or ""
check(bountySrc:find('ChaosLeaderboard.record("bounty", player, 1)', 1, true) ~= nil,
	"bounty.lua records a paid contract on the leaderboard")
local achSrc = readFile("data/scripts/chaos/achievements.lua") or ""
check(achSrc:find('A.progress(who, "bounty_done", 1)', 1, true) ~= nil, "achievements.lua counts it as bounty_done")
ChaosAchievements.progress(p2, "bounty_done", 1)
runTimers()
check(st2.done.bounty1 ~= nil, "bounty1 done")
check(trackerRow("bounty1") == nil, "bounty1 off the tracker")
-- the open panel follows too, only when it changed
events.ChaosGoalsExtended.onExtendedOpcode(p2, 178, {action = "open"})
local panels = #chunked
p2.level = 13
events.ChaosGoalsAdvance.onAdvance(p2, SKILL_LEVEL, 12, 13)
runTimers()
eq(#chunked, panels + 1, "open panel pushed on a level up")
ChaosAchievements.progress(p2, "party_kills", 1)
runTimers()
eq(#chunked, panels + 1, "not pushed again without a change")
-- a relog: the old queued run does nothing
ChaosAchievements.progress(p2, "kills_magic", 1)
events.ChaosGoalsLogout.onLogout(p2)
pushes = trackerCount()
runTimers()
eq(trackerCount(), pushes, "a run queued before the logout does nothing")
type = realType

print(string.format("goals_test: %d checks, %d failures", checks, failures))
if failures > 0 then
	os.exit(1)
end
