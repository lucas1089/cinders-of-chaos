-- Run from the server/ folder: luajit tests/season_journey_test.lua (and lua5.3; CI runs both)
-- The Seasonal Journey: the shipped journey (chapters, objectives, rewards) is valid; the pure rules (gating by chapter
-- and level, the mode objectives, a chapter returned once, the window view, the preview); then season_journey.lua with
-- a mocked engine: counters from the wrapped achievement API and the other hooks, objectives and chapters done in
-- order, the rewards of a chapter given once (also after a relog), offline counters written to SQL, standard
-- characters seeing a preview.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z][A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then fails = fails + 1; print("FAIL " .. what) end
end
local function eq(a, b, what) ok(a == b, what .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end

dofile("data/scripts/chaos/season_journey_core.lua")
local K = ChaosSeasonJourneyCore
local cfg = dofile("data/scripts/chaos/season_journey_config.lua")
local seasonCfg = dofile("data/scripts/chaos/season_config.lua")

-- ---------------------------------------------------------------- the shipped journey
local problems = K.validate(cfg)
eq(#problems, 0, "shipped config valid " .. table.concat(problems, "; "))
for _, s in ipairs(seasonCfg.seasons) do
	ok(K.journeyOf(cfg, s.id) ~= nil, "season " .. s.id .. " has a journey")
end
local J1 = K.journeyOf(cfg, 1)
ok(#J1.chapters >= 6 and #J1.chapters <= 8, "6-8 chapters: " .. #J1.chapters)
local modes = {standard = {}, ssf = {ssf = true}, hc = {hc = true}, hcssf = {ssf = true, hc = true}}
for name, flags in pairs(modes) do
	for _, ch in ipairs(J1.chapters) do
		local c = #K.objectivesOf(ch, flags)
		ok(c >= 6 and c <= 10, name .. " " .. ch.key .. ": 6-10 objectives (" .. c .. ")")
	end
end
-- the brief: chapter 1 basics, final chapters the endgame
local keysOf = function(ch) local s = {} for _, o in ipairs(ch.objectives) do s[o.stat .. ":" .. o.target] = true end return s end
local first, last = keysOf(J1.chapters[1]), {}
for i = #J1.chapters - 2, #J1.chapters do for k in pairs(keysOf(J1.chapters[i])) do last[k] = true end end
ok(first["level:100"] and first["rift_tier:1"] and first["wb_kills:1"], "chapter 1: level 100, tier 1 rift, a world boss")
ok(last["ascended_kills:1"] or last["ascended_kills:3"], "final chapters: an Ascended Omen")
ok(last["raid_clears:1"] or last["raid_clears:3"], "final chapters: a full raid clear")
ok(last["atlas_points:50"] or last["atlas_points:75"], "final chapters: Rift Atlas points")
-- every chapter: pass XP, orbs and a piece of the set; titles at the end
local have, total = K.pieces(J1, nil)
eq(have, 0, "no pieces without claims")
ok(total >= #J1.chapters, "a set piece per chapter: " .. total)
for i, ch in ipairs(J1.chapters) do
	local kinds = {}
	for _, r in ipairs(ch.rewards) do kinds[r.kind] = (kinds[r.kind] or 0) + 1 end
	ok(kinds.passxp == 1 and kinds.items == 1, ch.key .. ": pass XP and orbs")
	local piece = false
	for _, r in ipairs(ch.rewards) do piece = piece or r.piece == true end
	ok(piece, ch.key .. ": a set piece")
	eq(kinds.title ~= nil, i == #J1.chapters, ch.key .. ": a title only at the end")
end
-- mode objectives exist for Hardcore and Self-Found, and the Orb Exchange is not asked of Self-Found
local seen = {}
for _, ch in ipairs(J1.chapters) do
	for _, o in ipairs(ch.objectives) do
		seen[o.only or "all"] = true
		if o.stat == "orbx_orders" then eq(o.only, "nossf", "Orb Exchange objective skips Self-Found") end
	end
end
ok(seen.hc and seen.ssf, "Hardcore and Self-Found objectives")
-- the validator catches mistakes
local broken = {stats = {a = "add", b = "sum"}, journeys = {[1] = {name = "x", chapters = {
	{key = "c1", name = "C1", level = 10, objectives = {{key = "o1", text = "t", stat = "a", target = 1},
		{key = "o1", text = "t", stat = "zzz", target = 0, only = "pvp"}}, rewards = {{kind = "gems"}, {kind = "passxp"}}},
	{key = "c1", name = "", level = 5, objectives = {}}}}}}
local bp = table.concat(K.validate(broken), "\n")
for _, needle in ipairs({"mode must be add or max", "duplicate", "unknown stat", "target", "unknown only", "unknown reward",
	"incomplete passxp", "level lower", "no objectives", "no name"}) do
	ok(bp:find(needle, 1, true) ~= nil, "validator: " .. needle)
end

-- ---------------------------------------------------------------- pure rules
eq(K.merge({}, "add", "x", 0), false, "add 0: no change")
local st = {}
eq(K.merge(st, "add", "x", 3), true, "add")
K.merge(st, "add", "x", 2)
eq(st.x, 5, "add sums")
eq(K.merge(st, "max", "x", 4), false, "max lower: no change")
K.merge(st, "max", "x", 9)
eq(st.x, 9, "max keeps the best")
eq(K.value(st, "level", 77), 77, "level is the character's level")

-- gating: chapter 1 open at level 1; a stat that is already high does not complete a locked chapter
local ctx = {level = 60, stats = {rift_tier = 10, wb_kills = 5}, flags = {}, now = 100}
local objs, chs = K.evaluate(J1, ctx)
eq(#chs, 0, "level 60: chapter 1 not complete")
local names = {}
for _, e in ipairs(objs) do names[e.obj.key] = true end
ok(names.rift1 and names.boss1, "chapter 1 objectives done from stats")
ok(not names.rift4, "chapter 2 objective (tier 4 rift) not done while chapter 2 is locked")
eq(select(2, K.chapterOpen(J1, 2, ctx)), "Finish First Embers first.", "chapter 2 locked by chapter 1")
-- finish chapter 1 below chapter 2's level: chapter 1 completes once, chapter 2 stays locked by level
ctx.level = 120
ctx.stats.bounty_done, ctx.stats.bestiary_tasks, ctx.stats.kills_tiered, ctx.stats.orbs_used = 5, 1, 50, 5
objs, chs = K.evaluate(J1, ctx)
eq(#chs, 1, "chapter 1 complete")
eq(chs[1].chapter.key, "embers", "the first chapter")
eq(ctx.claimed.embers, 100, "claimed at now")
eq(select(2, K.chapterOpen(J1, 2, ctx)), "Reach level 150.", "chapter 2 needs level 150")
objs, chs = K.evaluate(J1, ctx)
eq(#objs + #chs, 0, "nothing again: each objective and chapter once")
-- level 150: chapter 2 opens and the tier 4 rift counts at once (stats count while locked)
ctx.level = 150
objs = K.evaluate(J1, ctx)
names = {}
for _, e in ipairs(objs) do names[e.obj.key] = true end
ok(names.rift4 and not names.lvl200, "chapter 2: tier 4 rift done at the unlock, level 200 not yet")

-- mode objectives: Hardcore needs its flawless rift for chapter 2; Self-Found skips the Orb Exchange
local function finishAll(flags, level)
	local c = {level = level or 2000, flags = flags, now = 1, stats = {}}
	for stat in pairs(cfg.stats) do c.stats[stat] = 100000 end
	return c
end
local std = finishAll({})
local _, all = K.evaluate(J1, std)
eq(#all, #J1.chapters, "standard: every chapter with every stat high")
eq(std.done.hcflawless, nil, "standard: no Hardcore objective")
ok(std.done.orbx1 ~= nil, "standard: Orb Exchange objective")
local hcCtx = finishAll({hc = true})
hcCtx.stats.rift_flawless = 0
_, all = K.evaluate(J1, hcCtx)
eq(#all, 1, "Hardcore without a flawless rift: stops after chapter 1")
eq(hcCtx.claimed.ironash, nil, "Hardcore: chapter 2 waits for its Hardcore objective")
local ssfCtx = finishAll({ssf = true})
ssfCtx.stats.orbx_orders = 0
_, all = K.evaluate(J1, ssfCtx)
eq(#all, #J1.chapters, "Self-Found finishes without the Orb Exchange")
eq(ssfCtx.done.orbx1, nil, "Self-Found: no Orb Exchange objective")
ok(ssfCtx.done.ssforbs150 ~= nil, "Self-Found objective done")

-- the window view
local header, chapters = K.view(J1, {level = 120, stats = {rift_tier = 2}, flags = {}, done = {rift1 = 1},
	claimed = {}}, {clientId = function(id) return id + 1 end})
eq(header.name, "The Ashen Pilgrimage", "view name")
eq(header.current, 1, "current chapter")
eq(chapters[1].state, "open", "chapter 1 open")
eq(chapters[2].state, "locked", "chapter 2 locked")
eq(chapters[2].lockedWhy, "Finish First Embers first.", "locked reason")
eq(chapters[1].done, 1, "one objective done")
eq(chapters[1].objectives[2].progress, 1, "progress capped at the target")
eq(chapters[1].objectives[1].progress, 100, "level progress capped")
eq(chapters[1].rewards[2].clientId, 29857, "client id of the orb")
eq(chapters[1].rewards[3].clientId, 7901, "client id of the look")
eq(header.pieces, 0, "no pieces yet")
local _, rc = K.view(J1, {level = 200, stats = {faction_rank = 4}, flags = {}, done = {}, claimed = {embers = 1}}, {})
for _, o in ipairs(rc[2].objectives) do
	if o.key == "trusted" then eq(o.target .. "/" .. o.progress, "1/1", "rank objective shown as done / not done") end
end
local ph, pc = K.view(J1, {level = 1}, {preview = true})
eq(ph.preview, true, "preview flag")
eq(pc[1].state, "preview", "preview chapter state")
eq(pc[2].objectives[1].progress, nil, "preview: no progress")
eq(#pc[2].objectives, #J1.chapters[2].objectives, "preview lists the mode objectives too")
eq(K.rewardsText(J1.chapters[1].rewards), "1500 pass XP, 3 Orb of Upheaval, Magma Monocle appearance", "rewards text")
local d, c = K.entriesToMaps({{entry = "o:rift1", at = 5}, {entry = "c:embers", at = 6}, {entry = "junk"}})
eq(d.rift1, 5, "entry o:")
eq(c.embers, 6, "entry c:")

-- ---------------------------------------------------------------- season_journey.lua with a mocked engine
local sql = {stats = {}, entries = {}} -- stats["s:pid:stat"] = value; entries["s:pid:entry"] = at
local queries = {}
db = {}
function db.escapeString(s) return "'" .. tostring(s):gsub("'", "''") .. "'" end
function db.query(q)
	queries[#queries + 1] = q
	local s, p, stat, v = q:match("INSERT INTO `chaos_season_journey_stats` .-VALUES %((%d+), (%d+), '([%w_]+)', (%-?%d+)")
	if s then
		local key = s .. ":" .. p .. ":" .. stat
		local old, new = sql.stats[key], tonumber(v)
		if old then
			if q:find("GREATEST", 1, true) then new = math.max(old, new)
			elseif q:find("`value` + VALUES", 1, true) then new = old + new end
		end
		sql.stats[key] = new
		return true
	end
	local s2, p2, entry, at = q:match("INSERT IGNORE INTO `chaos_season_journey` .-VALUES %((%d+), (%d+), '([^']+)', (%d+)")
	if s2 then
		local key = s2 .. ":" .. p2 .. ":" .. entry
		if not sql.entries[key] then sql.entries[key] = tonumber(at) end
		return true
	end
	return true
end
local sends, toasts = {}, {}
json = {encode = function(t) return t end}

dofile("data/scripts/chaos/chaos_constants.lua")
local registered = {}
local function eventMock(kind)
	return function(name)
		local e = setmetatable({name = name, kind = kind}, {__index = function() return function() end end})
		e.register = function() registered[name] = e end
		return e
	end
end
CreatureEvent, GlobalEvent, TalkAction = eventMock("creature"), eventMock("global"), eventMock("talk")
function addEvent(fn, ms, ...) fn(...) end
function ItemType(id) return {getClientId = function() return id + 1 end} end

function Chaos.select(q, cols)
	local out = {}
	local s, p = q:match("FROM `chaos_season_journey_stats` WHERE `season` = (%d+) AND `player_id` = (%d+)")
	if s then
		for key, v in pairs(sql.stats) do
			local ks, kp, stat = key:match("^(%d+):(%d+):(.+)$")
			if ks == s and kp == p then out[#out + 1] = {stat = stat, value = v} end
		end
		return out
	end
	s, p = q:match("FROM `chaos_season_journey` WHERE `season` = (%d+) AND `player_id` = (%d+)")
	if s then
		for key, at in pairs(sql.entries) do
			local ks, kp, entry = key:match("^(%d+):(%d+):(.+)$")
			if ks == s and kp == p then out[#out + 1] = {entry = entry, done_at = at} end
		end
		return out
	end
	p = q:match("FROM `chaos_season_journey` WHERE `player_id` = (%d+) AND `entry` LIKE 'c:%%'")
	if p then
		for key, at in pairs(sql.entries) do
			local ks, kp, entry = key:match("^(%d+):(%d+):(.+)$")
			if kp == p and entry:sub(1, 2) == "c:" then out[#out + 1] = {season = tonumber(ks), entry = entry, done_at = at} end
		end
	end
	return out
end
function Chaos.send(player, opcode, action, data)
	sends[#sends + 1] = {to = player:getName(), opcode = opcode, action = action, data = data}
end

-- the season (season.lua and season_modes.lua): guid 1 Hardcore season character, guid 2 standard, guid 3 offline
-- season character
local SEASON = seasonCfg.seasons[1]
Chaos.seasonConfig = seasonCfg
local realms = {[1] = 1, [2] = 0, [3] = 1, [4] = 1}
ChaosSeason = {ov = {}, current = function() return SEASON end, upcoming = function() return nil end,
	realmOf = function(p) return realms[p:getGuid()] or 0 end,
	realmOfGuid = function(g) return realms[g] or 0 end,
	modeFlagsOfGuid = function(g) return {ssf = false, hc = g == 1} end}
dofile("data/scripts/chaos/season_core.lua") -- K.* of season.lua not needed; keeps ChaosSeason.status etc.

local players = {}
local function makePlayer(guid, name, level)
	local p = {guid = guid, name = name, level = level, items = {}, outfits = {}, mounts = {}, msgs = {}, events = {}}
	function p:getGuid() return self.guid end
	function p:getId() return 1000 + self.guid end
	function p:getName() return self.name end
	function p:getLevel() return self.level end
	function p:getAccountId() return 50 + self.guid end
	function p:getSex() return 1 end
	function p:getGroup() return {getId = function() return 1 end} end
	function p:sendTextMessage(_, text) self.msgs[#self.msgs + 1] = text end
	function p:sendExtendedOpcode(op, payload) toasts[#toasts + 1] = {to = self.name, op = op, payload = payload} end
	function p:registerEvent(e) self.events[e] = true end
	function p:getPosition() return {sendMagicEffect = function() end} end
	function p:getItemCount(id) return self.items[id] or 0 end
	function p:addItem(id, count) self.items[id] = (self.items[id] or 0) + count end
	function p:getInbox() return nil end
	function p:addOutfit(look) self.outfits[look] = 0 end
	function p:addOutfitAddon(look, a) self.outfits[look] = a end
	function p:addMount(id) self.mounts[id] = true end
	players[guid] = p
	return p
end
Game = {getPlayers = function() local l = {} for _, p in pairs(players) do l[#l + 1] = p end return l end}
function Player(x)
	if type(x) == "number" then return players[x - 1000] end
	for _, p in pairs(players) do if p.name == x then return p end end
	return nil
end

-- the systems the journey hooks into
local passXp = {}
ChaosSeasonPass = {active = function() return SEASON end,
	account = function(id) return {id = id, season = SEASON.id} end,
	addXp = function(acc, amount, why) passXp[#passXp + 1] = {acc = acc.id, amount = amount, why = why} end}
local looks = {}
ChaosTransmog = {unlockLook = function(acc, id) looks[#looks + 1] = id return true end}
local achCalls = 0
ChaosAchievements = {stats = {}, progress = function() achCalls = achCalls + 1 end, set = function() achCalls = achCalls + 1 end}
local facRes = {gained = 300, rankAfter = 4}
ChaosFactions = {gain = function() return facRes end}
ChaosTower = {recordRun = function() return "tower" end}
ChaosOrbExchange = {place = function(p, d) return d.good == true end}

local okLoad, errLoad = pcall(dofile, "data/scripts/chaos/season_journey.lua")
ok(okLoad, "season_journey.lua loads: " .. tostring(errLoad))
local J = ChaosSeasonJourney
ok(registered.ChaosSeasonJourneyLogin and registered.ChaosSeasonJourneyExtended and registered.ChaosSeasonJourneyAdvance,
	"events registered")
registered.ChaosSeasonJourneyStartup.onStartup()

-- login: the season character walks the journey; the standard one does not
local hero = makePlayer(1, "Ash Hero", 90)
local std2 = makePlayer(2, "Old Guard", 300)
ChaosAchievements.stats[1] = {rift_runs = 2, bounty_done = 4, unrelated = 9}
registered.ChaosSeasonJourneyLogin.onLogin(hero)
registered.ChaosSeasonJourneyLogin.onLogin(std2)
ok(J.st[1] ~= nil, "season character loaded")
eq(J.st[2], nil, "standard character walks no journey")
eq(J.st[1].stats.bounty_done, 4, "login: raised to the achievement counter")
eq(J.st[1].stats.unrelated, nil, "only journey stats")
ok(hero.events.ChaosSeasonJourneyAdvance, "advance event registered")

-- progress from events: the wrapped achievement API (the original still runs)
ChaosAchievements.progress(hero, "bounty_done", 1)
eq(achCalls, 1, "the achievement API still runs")
eq(J.st[1].stats.bounty_done, 5, "bounty counted")
ok(J.st[1].done.bounty5 ~= nil, "objective done at 5 contracts")
local toastSeen = false
for _, t in ipairs(toasts) do
	if t.to == "Ash Hero" and t.op == 79 and t.payload.action == "journey" then toastSeen = true end
end
ok(toastSeen, "toast on the notifications opcode")
ChaosAchievements.set(hero, "rift_tier", 1)
ChaosAchievements.progress(hero, "wb_kills")
ChaosAchievements.progress(hero, "bestiary_tasks", 1)
ChaosAchievements.progress(hero, "kills_tiered", 50)
ChaosAchievements.progress(hero, "orbs_used", 5)
ChaosAchievements.progress(hero, "ambush_kills", 3) -- not a journey stat
eq(J.st[1].stats.ambush_kills, nil, "other counters ignored")
eq(J.st[1].claimed.embers, nil, "level 90: chapter 1 not complete")
-- the last objective (level 100) by a level up
hero.level = 100
registered.ChaosSeasonJourneyAdvance.onAdvance(hero, SKILL_LEVEL, 99, 100)
ok(J.st[1].claimed.embers ~= nil, "chapter 1 complete at level 100")
eq(#passXp, 1, "pass XP given")
eq(passXp[1].amount, 1500, "pass XP amount")
eq(hero.items[29856], 3, "orbs given")
eq(looks[1], 7900, "set piece unlocked")
eq(sql.entries["1:1:c:embers"] ~= nil, true, "chapter row written")
-- once: more events, another level up, a relog
ChaosAchievements.progress(hero, "bounty_done", 1)
registered.ChaosSeasonJourneyAdvance.onAdvance(hero, SKILL_LEVEL, 100, 101)
hero.level = 101
registered.ChaosSeasonJourneyLogout.onLogout(hero)
eq(J.st[1], nil, "logout clears")
eq(sql.stats["1:1:bounty_done"], 6, "counters flushed at logout")
registered.ChaosSeasonJourneyLogin.onLogin(hero)
eq(J.st[1].stats.bounty_done, 6, "counters back after the relog")
ok(J.st[1].claimed.embers ~= nil, "chapter 1 still claimed after the relog")
J.check(hero)
eq(#passXp, 1, "rewards given once (also after a relog)")
eq(hero.items[29856], 3, "orbs given once")

-- the other hooks: factions, the tower, the Orb Exchange, the emit API (descent, dungeons, atlas)
ChaosFactions.gain(hero, "vigil", 300, "kill")
eq(J.st[1].stats.faction_rep, 300, "faction reputation")
eq(J.st[1].stats.faction_rank, 4, "faction rank")
eq(ChaosTower.recordRun(hero, 12, 300), "tower", "tower original result")
eq(J.st[1].stats.tower_floor, 12, "tower floors")
ChaosTower.recordRun(hero, 5, 100)
eq(J.st[1].stats.tower_floor, 12, "tower floors keep the best")
ChaosOrbExchange.place(hero, {good = false})
eq(J.st[1].stats.orbx_orders, nil, "a refused order counts nothing")
ChaosOrbExchange.place(hero, {good = true})
eq(J.st[1].stats.orbx_orders, 1, "an order placed")
J.emit(hero, "dungeon_clears", 1)
J.emit(1, "atlas_points", 12, "max")
J.emit(hero, "descent_depth", 4, "max")
eq(J.st[1].stats.dungeon_clears, 1, "dungeon emit")
eq(J.st[1].stats.atlas_points, 12, "atlas emit by guid")
eq(J.emit(hero, "no_such_stat", 1), false, "unknown stat ignored")
J.installHooks()
ChaosAchievements.progress(hero, "goblin_kills", 1)
eq(J.st[1].stats.goblin_kills, 1, "hooks installed once (no double count after a second install)")

-- Hardcore objective: the flawless rift is asked of this Hardcore character in chapter 2
hero.level = 200
ChaosAchievements.progress(hero, "invasion_fought", 1)
ChaosAchievements.progress(hero, "party_kills", 500)
ChaosAchievements.set(hero, "rift_tier", 4)
J.emit(1, "atlas_points", 10, "max")
J.check(hero)
eq(J.st[1].claimed.ironash, nil, "Hardcore: chapter 2 waits for the flawless rift")
ChaosAchievements.progress(hero, "rift_flawless", 1)
ok(J.st[1].claimed.ironash ~= nil, "Hardcore: chapter 2 complete with the flawless rift")
eq(#passXp, 2, "chapter 2 pass XP")
eq(looks[2], 7899, "second set piece")

-- offline: written to SQL (add and max), counted at the next login
ChaosAchievements.progress({guid = 3, name = "Away"}, "bounty_done", 2)
ChaosAchievements.progress({guid = 3, name = "Away"}, "bounty_done", 1)
ChaosAchievements.set(3, "rift_tier", 6)
ChaosAchievements.set(3, "rift_tier", 2)
eq(sql.stats["1:3:bounty_done"], 3, "offline add")
eq(sql.stats["1:3:rift_tier"], 6, "offline max")
ChaosAchievements.progress(2, "bounty_done", 1)
eq(sql.stats["1:2:bounty_done"], nil, "an offline standard character writes nothing")

-- the window: a season character gets the header and every chapter; a standard one the preview
sends = {}
registered.ChaosSeasonJourneyExtended.onExtendedOpcode(hero, 246, "x")
Chaos.decode = function() return {action = "journey", data = {}} end
registered.ChaosSeasonJourneyExtended.onExtendedOpcode(hero, 246, "x")
eq(sends[1].action, "journey", "header first")
eq(sends[1].data.mode, "Hardcore", "mode in the header")
eq(#sends[1].data.chapters, #J1.chapters, "chapter summaries")
eq(sends[1].data.chapters[1].state, "done", "chapter 1 done")
eq(sends[1].data.pieces, 2, "two pieces")
eq(#sends, 1 + #J1.chapters, "one message per chapter")
eq(sends[2].action, "journeyChapter", "chapter message")
eq(sends[2].data.objectives[1].done, true, "objective done flag")
sends = {}
registered.ChaosSeasonJourneyExtended.onExtendedOpcode(std2, 246, "x")
eq(sends[1].data.preview, true, "standard character: preview")
ok(tostring(sends[1].data.why):find("Season of Ash", 1, true) ~= nil, "preview text names the season")
-- a rank objective shows done / not done, not the rank number
for _, o in ipairs(sends[3].data.objectives) do if o.key == "trusted" then eq(o.target, 1, "rank objective: target 1") end end
eq(sends[2].data.objectives[1].progress, nil, "preview: no progress")

-- titles at the end: a finished last chapter gives its title (name plate source "journey")
local titles
ChaosTitles = {register = function(src, fn) if src == "journey" then titles = fn end end}
registered.ChaosSeasonJourneyStartup.onStartup()
local champ = makePlayer(4, "Last Light", 2000)
for stat in pairs(cfg.stats) do ChaosAchievements.stats[4] = ChaosAchievements.stats[4] or {}; ChaosAchievements.stats[4][stat] = 1e6 end
ChaosSeasonJourney.st[4] = nil
registered.ChaosSeasonJourneyLogin.onLogin(champ)
eq(#K.objectivesOf(J1.chapters[#J1.chapters], {}) > 0, true, "last chapter has objectives")
ok(J.st[4].claimed[J1.chapters[#J1.chapters].key] ~= nil, "every chapter at once for a character that did it all")
local tl = titles and titles(champ) or {}
eq(tl[1] and tl[1].text, "Ashen Pilgrim", "title of the last chapter")
eq(champ.mounts[122], true, "mount of the last chapter")
eq(champ.outfits[1248], 0, "outfit of chapter 7 (male look)")
eq(champ.outfits[1249], 0, "outfit of chapter 7 (female look)")

-- records.lua and season_journey.lua both hook ChaosAchievements.set and install their hooks again every minute: in
-- any order, also after a /reload of achievements.lua, one set call runs the original and each hook exactly once
do
	local rawSets = 0
	ChaosAchievements.set = function() rawSets = rawSets + 1 end
	ChaosAchievements.progress = function() end
	ChaosWorldBoss = {state = {}, computeRewards = function() end}
	ChaosRiftCore = {atlasSealed = function() end}
	ChaosExclusives = {bossKill = function() end}
	ChaosAscended = {runs = {}}
	Chaos.trials = dofile("data/scripts/chaos/trials_config.lua")
	ChaosTrials = {runs = {}}
	Vocation = function() return {getName = function() return "Knight" end} end
	result = {}
	ChaosTitles.registerFrame = function() end
	DUNGEON_SYSTEM = false -- not the auto-numbered constant of this test
	db.storeQuery = function() return nil end
	db.asyncQuery = db.query
	local okR, errR = pcall(dofile, "data/scripts/chaos/records.lua")
	ok(okR, "records.lua loads: " .. tostring(errR))
	local R = ChaosRecords
	ChaosTrials.runs[hero:getId()] = {tierDef = {time = 600}, deadline = 0, famKey = "fam"}
	local submits, journeyRecords = 0, 0
	local realSubmit, realRecord = R.submit, J.record
	R.submit = function() submits = submits + 1 return true end
	J.record = function(...) journeyRecords = journeyRecords + 1 return realRecord(...) end
	local function once(what)
		rawSets, submits, journeyRecords = 0, 0, 0
		ChaosAchievements.set(hero, "trial_tier_1", 1)
		ChaosAchievements.set(hero, "rift_tier", 9)
		eq(rawSets, 2, what .. ": the original set runs once per call")
		eq(submits, 1, what .. ": the trial record submitted once")
		eq(journeyRecords, 1, what .. ": the journey stat counted once")
	end
	for i = 1, 5 do
		R.installHooks()
		J.installHooks()
		registered.ChaosSeasonJourneyFlush.onThink(60000)
		R.installHooks()
		once("alternating installs, round " .. i)
	end
	-- a /reload of achievements.lua: a new set, hooked again by whichever script installs first
	ChaosAchievements.set = function() rawSets = rawSets + 1 end
	J.installHooks()
	once("reload, journey first")
	R.installHooks()
	J.installHooks()
	once("reload, then both")
	R.submit, J.record = realSubmit, realRecord
end

print(string.format("season_journey_test: %d checks, %d failed", checks, fails))
if fails > 0 then os.exit(1) end
print("season_journey_test: OK")
