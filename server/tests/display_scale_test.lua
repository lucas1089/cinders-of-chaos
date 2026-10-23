-- Run from the server/ folder: luajit tests/display_scale_test.lua (and lua5.3; CI runs both)
-- The display scale (server/README.md "Display scale"). Part 1, the pure core (display_scale_core.lua): the curve
-- against the config (1 up to level 100, 1000 at 1000, the cap), whole factors, monotony and smoothness, the rounding
-- and the clamps (2^53, uint32), the text rule, the engine table. Part 2, every site function on payloads made by
-- the real cores (combat log, death recap, party frames, hunt) or shaped like the real ones (boards, battleground,
-- guild boss, bestiary, spellbook, item tooltips): what is scaled, what never is, copies (shared payloads untouched),
-- factor 1 returns the payload itself, and the sums still add up. Part 3, the engine glue display_scale.lua against a
-- mocked engine (the engine table, the opcode at login and at a level change that changes the factor), and every hook
-- site calls its site function right before it sends (a scan of the sources: a hook that is lost fails here).

local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end
local function ok(v, m)
	checks = checks + 1
	if not v then
		error(m or "expected true", 2)
	end
end

dofile("data/scripts/chaos/display_scale_core.lua")
local DS = ChaosDisplayScale
local cfg = dofile("data/scripts/chaos/display_scale_config.lua")
-- owner 2026-10-23: the scale is off, every level sees the internal numbers
DS.configure(cfg)
for _, level in ipairs({1, 100, 300, 1000, 1500, 2500}) do
	if DS.factor(level) ~= 1 then
		error("the shipped curve is not x1 at level " .. level)
	end
end
-- the code stays: it is tested on the old curve (the engine glue display_scale.lua reads it from this file too)
local realDofile = dofile
dofile = function(path)
	if path == "data/scripts/chaos/display_scale_config.lua" then
		return cfg
	end
	return realDofile(path)
end
cfg.curve = {{100, 1}, {1000, 1000}, {1500, 10000}}
DS.configure(cfg)

-- ============================================================================ part 1: the curve and the numbers
eq(cfg.curve[1][1], 100, "the rise starts at level 100")
eq(DS.factor(1), 1, "level 1")
eq(DS.factor(50), 1, "level 50")
eq(DS.factor(100), 1, "level 100")
eq(DS.factor(1000), 1000, "level 1000: x1000")
eq(DS.factor(1500), 10000, "level 1500: the cap")
eq(DS.factor(5000), 10000, "past the cap")
eq(DS.factor(0), 1, "level 0")
eq(DS.factor(-3), 1, "a negative level")
eq(DS.factor(nil), 1, "no level")
eq(DS.factor("700"), 100, "a level as text")
eq(DS.factor(700.9), 100, "a fraction of a level is the level")
-- the documented table (server/README.md "Display scale")
local documented = {[50] = 1, [100] = 1, [200] = 2, [300] = 5, [500] = 22, [700] = 100, [1000] = 1000, [1500] = 10000}
for level, f in pairs(documented) do
	eq(DS.factor(level), f, "documented factor at level " .. level)
end
-- whole, never falling, never jumping more than x2 (only the first step 1 -> 2 does), under 10% per level from 400 on
local prev, firstTwo = 1, nil
for level = 1, 2000 do
	local f = DS.factor(level)
	ok(f >= 1 and f == math.floor(f), "a whole factor at " .. level)
	ok(f >= prev, "never falls at " .. level)
	ok(f <= prev * 2, "at most a doubling at " .. level)
	if level >= 400 then
		ok(f <= prev * 1.1 + 1, "smooth from level 400 at " .. level)
	end
	if f == 2 and not firstTwo then
		firstTwo = level
	end
	prev = f
end
eq(firstTwo, 153, "the first step (1 -> 2) at level 153")
-- the raw curve is exponential between the points
local r1, r2 = DS.rawFactor(400), DS.rawFactor(700)
ok(math.abs(r1 - 10) < 1e-9, "x10 at level 400 (a third of the way in log)")
ok(math.abs(r2 - 100) < 1e-9, "x100 at level 700")
ok(math.abs(DS.rawFactor(1250) - math.sqrt(1000 * 10000)) < 1e-6, "between 1000 and 1500: log-linear too")

-- scale: exact, rounded, clamped, never touches what is not a number
eq(DS.scale(2600, 1000), 2600000, "2600 x1000")
eq(DS.scale(2600, 1), 2600, "factor 1")
eq(DS.scale(0, 1000), 0, "zero")
eq(DS.scale(-40, 5), -200, "a negative number keeps its sign")
eq(DS.scale(2.5, 3), 8, "a fraction (a rate) is rounded: 7.5 -> 8")
eq(DS.scale(2.4, 3), 7, "7.2 -> 7")
eq(DS.scale(2 ^ 52, 10000), cfg.jsonMax, "clamped to 2^53")
eq(DS.scale(-(2 ^ 52), 10000), -cfg.jsonMax, "and to -2^53")
eq(DS.scale("12", 5), "12", "text stays")
eq(DS.scale(nil, 5), nil, "nil stays")
local nan = 0 / 0
ok(DS.scale(nan, 5) ~= DS.scale(nan, 5), "NaN stays NaN")
eq(DS.scale(math.huge, 5), math.huge, "inf stays")
eq(DS.u32(4294967, 1000), 4294967000, "uint32: below the limit")
eq(DS.u32(4294968, 1000), 4294967295, "uint32: clamped")
eq(DS.u32(-5, 1000), 0, "uint32: no negatives")
eq(DS.u32("x", 5), 0, "uint32: not a number")
-- additivity: a whole factor keeps sums exact (the consistency rule)
for _, f in ipairs({1, 2, 5, 22, 464, 1000, 10000}) do
	local parts, sum, shownSum = {97, 31, 4005, 1, 77777}, 0, 0
	for _, p in ipairs(parts) do
		sum = sum + p
		shownSum = shownSum + DS.scale(p, f)
	end
	eq(shownSum, DS.scale(sum, f), "parts add up at x" .. f)
	-- a boss bar: shown health - the shown hits = the shown health after them
	local hp, maxHp = 1234567, 2000000
	local after = hp - sum
	eq(DS.scale(hp, f) - shownSum, DS.scale(after, f), "boss bar minus the hits at x" .. f)
	ok(DS.scale(maxHp, f) >= DS.scale(hp, f), "max stays above at x" .. f)
end
-- text
eq(DS.scaleNumbersIn("Health on Hit +20", 1000), "Health on Hit +20000", "a modifier line")
eq(DS.scaleNumbersIn("Health Regeneration +5 per Second", 22), "Health Regeneration +110 per Second", "every number")
eq(DS.scaleNumbersIn("1.5 and 12.25", 10), "1.5 and 12.25", "decimals stay")
eq(DS.scaleNumbersIn("+20", 1), "+20", "factor 1")
eq(DS.scaleNumbersIn(nil, 5), nil, "nil")
-- the engine table
local t = DS.table()
eq(#t, cfg.tableLevels, "one factor per level up to tableLevels")
eq(t[1], 1, "table: level 1")
eq(t[1000], 1000, "table: level 1000")
eq(t[#t], 10000, "table: the cap at the end (the engine uses it past the end)")
eq(#DS.table(10), 10, "a shorter table")
-- forPlayer
eq(DS.forPlayer(nil), 1, "no player")
eq(DS.forPlayer({getLevel = function() return 1000 end}), 1000, "a player's level")
eq(DS.forPlayer({getLevel = function() error("gone") end}), 1, "a removed player")
eq(DS.forPlayer({}), 1, "no getLevel")
eq(DS.apply("nope", nil, 5), 5, "an unknown site")

-- ============================================================================ part 2: the sites
local function deepEq(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	for k, v in pairs(a) do
		if not deepEq(v, b[k]) then
			return false
		end
	end
	for k in pairs(b) do
		if a[k] == nil then
			return false
		end
	end
	return true
end
local L1000 = {getLevel = function() return 1000 end}

-- combat log: a real state from combatlog_core.lua
dofile("data/scripts/chaos/combatlog_core.lua")
local CL = ChaosCombatLog
CL.configure(dofile("data/scripts/chaos/combatlog_config.lua"))
local actor = CL.newActor(0)
local src = {k = "spell:Witchfire Bolt", t = "spell", n = "Witchfire Bolt", i = 201}
CL.add(actor, 1000, CL.DMG, src, 300, false, 0, "fire", "Dragon")
CL.add(actor, 1500, CL.DMG, src, 120, true, 0, "fire", "Dragon")
CL.add(actor, 1600, CL.HEAL, {k = "spell:Mend", t = "spell", n = "Mend", i = 202}, 50, false, 10)
CL.flush(actor)
local st = CL.state(actor, "s")
st.party = {CL.brief(actor)}
local before = DS.clone(st)
local sst = DS.combatLogState(st, 1000)
ok(deepEq(st, before), "the state it was given is untouched (a copy is scaled)")
eq(DS.combatLogState(st, 1), st, "factor 1: the payload itself")
local tab, stab = st.v.t[CL.DMG], sst.v.t[CL.DMG]
ok(tab.tot > 0, "the combat log has damage")
eq(stab.tot, tab.tot * 1000, "total")
eq(stab.ov, tab.ov * 1000, "overkill / overheal")
eq(stab.el.fire, tab.el.fire * 1000, "element")
eq(stab.r[1][5], tab.r[1][5] * 1000, "row total")
eq(stab.r[1][8], tab.r[1][8] * 1000, "row max")
eq(stab.r[1][6], tab.r[1][6], "row hits stay")
eq(stab.r[1][7], tab.r[1][7], "row crits stay")
eq(stab.r[1][3], tab.r[1][3], "names stay")
eq(sst.segs[1][4], st.segs[1][4] * 1000, "segment damage")
eq(sst.segs[1][5], st.segs[1][5] * 1000, "segment healing")
eq(sst.segs[1][3], st.segs[1][3], "segment duration stays")
eq(sst.segs[1][1], st.segs[1][1], "segment id stays")
eq(sst.party[1].sd, st.party[1].sd * 1000, "party totals")
eq(sst.party[1].sdur, st.party[1].sdur, "party duration stays")
eq(DS.combatLogBrief(st.party[1], 22).sh, st.party[1].sh * 22, "a brief alone")

-- death recap: a real recap from deathrecap_core.lua, scaled by the level at that death
dofile("data/scripts/chaos/deathrecap_core.lua")
local R = ChaosDeathRecap
R.configure(dofile("data/scripts/chaos/deathrecap_config.lua"))
local log = R.newLog()
R.record(log, 1000, {k = R.key("c", "Dragon"), n = "Dragon", kind = "c", el = "fire", a = 400})
R.record(log, 1500, {k = R.key("c", "Dragon"), n = "Dragon", kind = "c", el = "physical", a = 250, c = true})
R.record(log, 1700, {k = R.key("c", "Demon"), n = "Demon", kind = "c", el = "death", a = 90, mp = true})
local recap = R.build(log, 2000, {at = 1, real = true, level = 700, exp = 123456789})
local srec = DS.deathRecap(recap, 100)
eq(srec.tot, recap.tot * 100, "recap total")
eq(srec.hp, recap.hp * 100, "recap health part")
eq(srec.mp, recap.mp * 100, "recap mana part")
eq(srec.kb.a, recap.kb.a * 100, "killing blow")
eq(srec.att[1].tot, recap.att[1].tot * 100, "attacker total")
eq(srec.att[1].x, recap.att[1].x * 100, "attacker max hit")
eq(srec.att[1].h, recap.att[1].h, "attacker hits stay")
eq(srec.el.fire, recap.el.fire * 100, "element split")
eq(srec.last[1].a, recap.last[1].a * 100, "last hits")
eq(srec.last[1].dt, recap.last[1].dt, "last hit times stay")
eq(srec.exp, recap.exp, "experience stays")
eq(srec.lvl, recap.lvl, "level stays")
local data = DS.deathRecapData({recap = recap, list = {R.summary(1, recap), R.summary(2, {tot = 50, lvl = 50})}}, 1000)
eq(data.recap.tot, recap.tot * 100, "a message: the recap at the factor of its own level (700: x100), not the viewer's")
eq(data.list[1].tot, recap.tot * 100, "history: each summary at its own level")
eq(data.list[2].tot, 50, "history: a level-50 death stays")
eq(DS.deathRecapData({recap = {tot = 10}}, 22).recap.tot, 220, "an old recap without a level: the viewer's factor")
eq(recap.tot > 0 and R.summary(1, recap).tot, recap.tot, "the stored recap is untouched")

-- party frames: a real state from partyframes_core.lua
dofile("data/scripts/chaos/partyframes_core.lua")
local P = ChaosPartyFrames
local viewer = {id = 1, name = "A", level = 1000, hp = 15000, hpMax = 15065, mp = 500, mpMax = 5145, x = 100, y = 100, z = 7}
local other = {id = 2, name = "B", level = 300, hp = 4000, hpMax = 4565, mp = 100, mpMax = 900, x = 101, y = 100, z = 7}
local far = {id = 3, name = "C", level = 200, hp = 10, hpMax = 100, mp = 0, mpMax = 0, x = 900, y = 100, z = 7}
local pst = P.state(viewer, {viewer, other, far}, 1)
local spst = DS.partyState(pst, 1000)
local byId = {}
for _, m in ipairs(spst.members) do byId[m.i] = m end
eq(byId[1].h, 15000 * 1000, "own health in own scale")
eq(byId[2].H, 4565 * 1000, "a member's max health in the VIEWER's scale")
eq(byId[2].m, 100, "a member's mana stays (mana is never scaled)")
eq(byId[2].M, 900, "its max mana stays")
eq(byId[2].p, pst.members[2].p or byId[2].p, "the percent stays")
eq(byId[2].lv, 300, "levels stay")
eq(byId[3].h, nil, "a member out of range has no numbers")
ok(byId[3].p ~= nil, "only its percent")

-- hunt tracker: a real state from hunt_core.lua
dofile("data/scripts/chaos/hunt_core.lua")
local H = ChaosHunt
local hs = H.new(0)
H.addDamage(hs, 26000)
H.addHealing(hs, 3100)
local hst = H.state(hs, 10, {exp = 0, level = 1000, minRateSeconds = 5})
local shst = DS.huntState(hst, 1000)
eq(shst.dmg, 26000000, "hunt damage")
eq(shst.dps, hst.dps * 1000, "hunt DPS")
eq(shst.heal, 3100000, "hunt healing")
eq(shst.hps, hst.hps * 1000, "hunt healing per second")
eq(shst.xp, hst.xp, "experience stays")
eq(shst.lv, hst.lv, "loot value (gold) stays")
eq(shst.pf, hst.pf, "profit stays")
eq(shst.t, hst.t, "time stays")

-- leaderboards: only the damage / healing boards
local board = {key = "worldboss", rows = {{rank = 1, name = "A", value = 50000, count = 3}}, champions = {{rank = 1, value = 9}},
	own = {rank = 4, value = 700, count = 1}, total = 10}
local sboard = DS.leaderboard(board, 22)
eq(sboard.rows[1].value, 1100000, "world boss damage")
eq(sboard.rows[1].count, 3, "kills stay")
eq(sboard.rows[1].rank, 1, "ranks stay")
eq(sboard.champions[1].value, 198, "last week's champion")
eq(sboard.own.value, 15400, "own value")
eq(board.rows[1].value, 50000, "the board itself untouched")
for _, key in ipairs({"bosshealer", "bosstank"}) do
	eq(DS.leaderboard({key = key, rows = {{value = 3}}}, 5).rows[1].value, 15, key .. " is scaled")
end
for _, key in ipairs({"bounty", "rift", "goblin", "siege", "arena1v1", "battleground", "defender", "factions", "cinder_solo", "ladder"}) do
	eq(DS.leaderboard({key = key, rows = {{value = 3}}}, 5).rows[1].value, 3, key .. " is never scaled")
end
-- every scaled board exists in leaderboard_config.lua and is a damage / healing / tanked one
local lbc = dofile("data/scripts/chaos/leaderboard_config.lua")
local boards = {}
for _, b in ipairs(lbc.boards) do boards[b.key] = b end
for key in pairs(cfg.leaderboardBoards) do
	ok(boards[key], "scaled board " .. key .. " exists")
	ok(({Damage = true, Healing = true, Tanked = true})[boards[key].value], key .. " counts damage or healing")
end
for key, b in pairs(boards) do
	if ({Damage = true, Healing = true, Tanked = true})[b.value] then
		ok(cfg.leaderboardBoards[key], "a damage / healing board is scaled: " .. key)
	end
end

-- battleground scoreboard: one board table goes to every player; each gets its own scaled copy
local bg = {rows = {{name = "A", damage = 1000, healing = 20, kills = 3, honor = 50}}, teams = {"x", "y"}, score = {700, 300}}
local bgA, bgB = DS.battleground(bg, 1000), DS.battleground(bg, 2)
eq(bgA.rows[1].damage, 1000000, "bg damage, viewer A")
eq(bgB.rows[1].damage, 2000, "bg damage, viewer B: its own scale (PvP)")
eq(bgA.rows[1].healing, 20000, "bg healing")
eq(bgA.rows[1].kills, 3, "kills stay")
eq(bgA.rows[1].honor, 50, "honor stays")
eq(bgA.score[1], 700, "the score (brazier points) stays")
eq(bg.rows[1].damage, 1000, "the shared board untouched")
eq(DS.battleground({text = "hi"}, 5).text, "hi", "a message without rows")

-- guild window: the guild boss board
local gst = {wars = {}, boss = {damage = 100, board = {{rank = 1, name = "G", damage = 5000, seconds = 300, players = 9}},
	contributors = {{name = "A", gold = 7}}}}
local sg = DS.guildState(gst, 5)
eq(sg.boss.damage, 500, "the guild's damage this week")
eq(sg.boss.board[1].damage, 25000, "board damage")
eq(sg.boss.board[1].seconds, 300, "seconds stay")
eq(sg.boss.contributors[1].gold, 7, "gold stays")
eq(DS.guildState({wars = {}}, 5).boss, nil, "no guild boss view")

-- bestiary entry: health, never experience
local be = DS.bestiaryEntry({health = 4000, exp = 3000, kills = 10}, 100)
eq(be.health, 400000, "monster health in the viewer's scale")
eq(be.exp, 3000, "experience stays")
eq(be.kills, 10, "kills stay")

-- spellbook: a spell's mana cost is one fixed number at every level (owner 2026-10-21): no site scales it
eq(DS.spellList, nil, "no spell list site: mana costs are never scaled")
eq(DS.apply("spellList", {getLevel = function() return 1000 end}, {{mana = 70}})[1].mana, 70, "an unknown site: as it is")

-- item tooltips: the factor of the item's level requirement, the flat rows only
local tip = {name = "Ashen Helm", kind = "helmet", req = {level = 700},
	base = {{k = "armor", l = "Armour", v = 12}, {k = "maxhealth", l = "Max Health", v = 200}},
	mods = {{k = "chaos_mod_lifeonkill", l = "Life on Kill", t = "Life on Kill +40", v = 40, lo = 35, hi = 60, tr = 5},
		{k = "chaos_mod_itemfind", l = "Item Find", t = "Item Find +5%", v = 5, lo = 3, hi = 6},
		{k = "chaos_mod_regen", l = "Health Regeneration", t = "Health Regeneration +9 per Second", v = 9, lo = 9, hi = 15},
		{k = "chaos_mod_thorns", l = "Thorns", t = "Thorns +30", v = 30, lo = 25, hi = 50}},
	stats = {{k = "armor", l = "Armour", v = 12}, {k = "maxhealth", l = "Max Health", v = 200},
		{k = "chaos_mod_lifeonkill", l = "Life on Kill", v = 40}, {k = "chaos_mod_itemfind", l = "Item Find", v = 5, fmt = "pct"}},
	sockets = {count = 2, list = {{name = "Ruby", text = "+150 Max Health"}, {name = "Topaz", text = "+4% Fire Protection"}}},
	weight = 25.5}
local stip = DS.itemTip(tip)
eq(stip.ds, 100, "the item's factor: its level requirement (700: x100)")
eq(stip.base[1].v, 12, "armour stays")
eq(stip.base[2].v, 20000, "max health x100")
eq(stip.mods[1].v, 4000, "life on kill")
eq(stip.mods[1].lo, 3500, "its range low")
eq(stip.mods[1].hi, 6000, "its range high")
eq(stip.mods[1].t, "Life on Kill +4000", "its text")
eq(stip.mods[1].tr, 5, "the tier stays")
eq(stip.mods[2].v, 5, "a percent modifier stays")
eq(stip.mods[2].t, "Item Find +5%", "its text stays")
eq(stip.mods[3].t, "Health Regeneration +900 per Second", "regeneration (a heal)")
eq(stip.mods[4].v, 3000, "thorns (damage)")
eq(stip.stats[2].v, 20000, "compare stats: max health")
eq(stip.stats[2].sc, 1, "marked for the compare view")
eq(stip.stats[1].sc, nil, "armour not marked")
eq(stip.stats[4].sc, nil, "a percent not marked")
eq(stip.sockets.list[1].text, "+15000 Max Health", "a flat gem")
eq(stip.sockets.list[2].text, "+4% Fire Protection", "a percent gem stays")
eq(stip.weight, 25.5, "weight stays")
eq(tip.base[2].v, 200, "the built tooltip untouched (snapshots in the market and chat links stay raw)")
local low = DS.itemTip({req = {level = 80}, stats = {{k = "maxhealth", v = 50}}, base = {{k = "maxhealth", v = 50}}})
eq(low.ds, 1, "a low item: x1")
eq(low.base[1].v, 50, "a low item: as it is")
eq(low.stats[1].sc, 1, "but marked, so a worn high item compares right")
eq(DS.itemTip({stats = {}}).ds, 1, "no requirement: x1")
-- a tooltip's factor does not depend on who looks
eq(DS.itemTip(tip).base[2].v, DS.itemTip(tip).base[2].v, "the same for every viewer")
ok(DS.isItemFlatKey("chaos_mod_lifeonhit") and DS.isItemFlatKey("gem_maxhealth") and not DS.isItemFlatKey("chaos_mod_attackspeed"),
	"flat keys")
for _, k in ipairs({"maxmana", "chaos_mod_manaonhit", "chaos_mod_manaonkill", "gem_maxmana"}) do
	ok(not DS.isItemFlatKey(k), "a mana row is never scaled: " .. k)
end
local mtip = DS.itemTip({req = {level = 1000}, base = {{k = "maxmana", v = 300}},
	mods = {{k = "chaos_mod_manaonhit", t = "Mana on Hit +4", v = 4, lo = 2, hi = 6}},
	sockets = {count = 1, list = {{name = "Sapphire", text = "+150 Max Mana"}}}})
eq(mtip.base[1].v, 300, "item max mana stays")
eq(mtip.mods[1].t, "Mana on Hit +4", "mana on hit stays")
eq(mtip.sockets.list[1].text, "+150 Max Mana", "a mana gem stays")
-- every flat key names a real modifier / stat (a renamed modifier would silently stop being scaled)
dofile("data/lib/chaos_item_mods.lua")
local known = {maxhealth = true, gem_maxhealth = true}
for key in pairs(ChaosItemMods.byKey or {}) do
	known[key] = true
end
pcall(dofile, "data/lib/chaos_powers.lua") -- the legendary powers (smolderaura)
for key in pairs(ChaosItemMods.byKey or {}) do
	known[key] = true
end
for key in pairs(cfg.itemFlatKeys) do
	ok(known[key], "flat key " .. key .. " is a known modifier or stat")
end

-- ============================================================================ part 3: the engine glue
local registered, sentMsgs, engineTable = {}, {}, nil
function CreatureEvent(name)
	local ev = {name = name}
	function ev:type(t) self.kind = t end
	function ev:register() registered[name] = self end
	return ev
end
Game = {setDisplayScale = function(t) engineTable = t return #t end}
SKILL_LEVEL = 8
json = {encode = function(t) return t end}
dofile("data/scripts/chaos/chaos_constants.lua")
Chaos.send = function(player, opcode, action, payload)
	sentMsgs[#sentMsgs + 1] = {p = player, op = opcode, action = action, data = payload}
	return true
end
dofile("data/scripts/chaos/display_scale.lua")
eq(ChaosOpcodes.displayScale, 157, "opcode 157")
eq(cfg.opcode, ChaosOpcodes.displayScale, "the config names the same opcode")
ok(DS.engine, "the engine got its table")
eq(#engineTable, cfg.tableLevels, "the whole table")
eq(engineTable[1000], 1000, "engine table: level 1000")
local hero = {level = 1000, events = {}}
function hero:getLevel() return self.level end
function hero:registerEvent(n) self.events[#self.events + 1] = n end
ok(registered.ChaosDisplayScaleLogin.onLogin(hero), "login goes on")
eq(hero.events[1], "ChaosDisplayScaleAdvance", "the advance event is registered at login")
eq(hero.events[2], "ChaosDisplayScaleOpcode", "and the hello handler")
eq(registered.ChaosDisplayScaleLogin.kind, "login", "login event type")
eq(registered.ChaosDisplayScaleAdvance.kind, "advance", "advance event type")
eq(registered.ChaosDisplayScaleOpcode.kind, "extendedopcode", "opcode event type")
eq(#sentMsgs, 1, "the factor goes out at login")
eq(sentMsgs[1].op, 157, "on its opcode")
eq(sentMsgs[1].action, "scale", "action scale")
eq(sentMsgs[1].data.f, 1000, "the factor")
eq(sentMsgs[1].data.level, 1000, "the level")
local adv = registered.ChaosDisplayScaleAdvance.onAdvance
hero.level = 1001
ok(adv(hero, SKILL_LEVEL, 1000, 1001), "advance goes on")
eq(#sentMsgs, 2, "a level up that changes the factor: sent")
eq(sentMsgs[2].data.f, DS.factor(1001), "the new factor")
hero.level = 60
adv(hero, SKILL_LEVEL, 50, 60)
eq(#sentMsgs, 2, "a level up within factor 1: nothing")
adv(hero, 2, 50, 60)
eq(#sentMsgs, 2, "a skill: nothing")
hero.level = 900
adv(hero, SKILL_LEVEL, 1000, 900)
eq(#sentMsgs, 3, "a level lost: sent")
eq(sentMsgs[3].data.f, 464, "level 900: x464")
-- the client's hello (a reattach to a lingering character runs no onLogin): the factor again; other opcodes and
-- other actions nothing
local hello = registered.ChaosDisplayScaleOpcode.onExtendedOpcode
Chaos.decode = function(b) return b end
hello(hero, 157, {action = "hello"})
eq(#sentMsgs, 4, "hello: the factor again")
eq(sentMsgs[4].data.f, 464, "the current factor")
hello(hero, 156, {action = "hello"})
hello(hero, 157, {action = "other"})
hello(hero, 157, nil)
eq(#sentMsgs, 4, "another opcode, another action, nothing: nothing")
-- the dispatch finds the handler's opcode guard (chaos_constants.lua Chaos.opcodeDispatch: the upvalue OPCODE)
eq(Chaos.opcodeDispatch.opcodeOf(hello), 157, "the dispatch reads the guard's opcode")
-- without the engine patch: no error, the Lua sites still scale
Game = {}
dofile("data/scripts/chaos/display_scale.lua")
eq(DS.engine, false, "an engine without src-patch 0037")
eq(DS.forPlayer(hero), 464, "the Lua sites still have the factor")

-- every hook site calls its site function right before it sends (a scan of the sources)
local function source(path)
	local f = assert(io.open(path, "r"))
	local s = f:read("*a")
	f:close()
	return s
end
local hooks = {
	{"combatlog.lua", 'DS.apply("combatLogState", player, st)', 'Chaos.sendChunked(player, OPCODE, json.encode({action = "state", data = st}))'},
	{"deathrecap.lua", "DS.deathRecapData(data, DS.forPlayer(player))", "Chaos.sendChunked(player, OPCODE, json.encode({action = action, data = data}))"},
	{"partyframes.lua", 'ChaosDisplayScale.apply("partyState", player, data)', "Chaos.send(player, OPCODE, action, data)"},
	{"hunt.lua", 'ChaosDisplayScale.apply("huntState", player, st)', 'Chaos.send(player, OPCODE, "state", st)'},
	{"leaderboard.lua", 'ChaosDisplayScale.apply("leaderboard", player, data)', 'Chaos.send(player, OPCODE, "board", data)'},
	{"season.lua", 'ChaosDisplayScale.apply("leaderboard", player, data)', 'Chaos.send(player, ChaosOpcodes.leaderboard or 229, "board", data)'},
	{"season_modes.lua", 'ChaosDisplayScale.apply("leaderboard", player, data)', 'Chaos.send(player, ChaosOpcodes.leaderboard or 229, "board", data)'},
	{"battleground.lua", 'ChaosDisplayScale.apply("battleground", player, data)', "Chaos.sendChunked(player, OPCODE, json.encode({action = action, data = data or {}}))"},
	{"guildwar.lua", 'ChaosDisplayScale.apply("guildState", player, data)', 'Chaos.sendChunked(player, OPCODE, json.encode({action = "state", data = data}))'},
	{"bestiary.lua", 'ChaosDisplayScale.apply("bestiaryEntry", player, data)', 'Chaos.send(player, OPCODE, "entry", data)'},
	{"item_tooltip.lua", "ChaosDisplayScale.itemTip(tip)", 'Chaos.send(player, OPCODE, "tips", {items = out})'},
	{"inspect.lua", "ChaosDisplayScale.itemTip(tip)", "return rows"}, -- the rows go to I.equipPackets (equip packets)
	{"itemlink.lua", "ChaosDisplayScale.itemTip(tip)", 'reply(player, "link", {id = entry.id, tip = '},
	{"groundloot.lua", "ChaosDisplayScale.itemTip(tip)", 'Chaos.send(player, OPCODE, "tip", reply)'},
	{"market.lua", "ChaosDisplayScale.itemTip(tip)", 'send(player, "tip", {id = id, tip = tip, seller = r.seller_name})'},
	{"pets.lua", "ChaosDisplayScale.scale(healed, ChaosDisplayScale.forPlayer(player))", 'Chaos.t(player, "Your pet mends you (+%.0f).", shown)'},
}
for _, h in ipairs(hooks) do
	local s = source("data/scripts/chaos/" .. h[1])
	local at = s:find(h[2], 1, true)
	-- the send right after the hook (or the hook inside the send's own line)
	local sendAt = at and s:find(h[3], math.max(1, at - 120), true)
	ok(at, h[1] .. ": the display scale hook is there")
	ok(sendAt and sendAt - at < 600, h[1] .. ": the hook comes right before the send")
end
-- fixed spell costs (owner 2026-10-21): the spellbook sends the costs as they are, one packed list for every viewer
local book = source("data/scripts/chaos/spellbook.lua")
ok(not book:find("ChaosDisplayScale", 1, true), "spellbook.lua: no display scale on the mana costs")

print("display_scale_test: OK (" .. checks .. " checks)")
