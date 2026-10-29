-- Run from the server/ folder: luajit tests/nemesis_test.lua (or lua5.3; CI runs both)
-- Nemesis: the constants and the opcode collision check, the birth rules and the chance with the soft cap, names and
-- epithets (en / pt-BR), level and growth, traits, appearing, who it may hurt, rewards and the anti-farm rules,
-- expiry, the SQL, the client view, then nemesis.lua against a mocked engine (birth on a death, the kill that calls it,
-- the warning and the spawn, growth, the guard, the avenge with the trophy, the party's bounty, logout, the opcode).
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
dofile("data/scripts/chaos/chaos_constants.lua")
local cfg = dofile("data/scripts/chaos/nemesis_config.lua")
dofile("data/scripts/chaos/nemesis_core.lua")
local K = ChaosNemesisCore

local checks, fails = 0, 0
local function ok(cond, label)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. tostring(label))
	end
end
local function eq(a, b, label)
	ok(a == b, tostring(label or ("line " .. debug.getinfo(2, "l").currentline)) .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
-- Park-Miller: the same sequence in LuaJIT and Lua 5.3
local function rng(seed)
	local s = seed
	return function(a, b)
		s = (s * 16807) % 2147483647
		return a + s % (b - a + 1)
	end
end
local function fixed(v)
	return function(a, b)
		if v == "min" then return a end
		if v == "max" then return b end
		return math.max(a, math.min(b, v))
	end
end

-- ---------------------------------------------------------------- constants, opcode collision check
eq(ChaosOpcodes.nemesis, 163, "opcode constant")
eq(cfg.opcode, ChaosOpcodes.nemesis, "config opcode = constant")
eq(Chaos.tables.nemesis, "chaos_nemesis", "table constant")
eq(cfg.table, Chaos.tables.nemesis, "config table = constant")
eq(Chaos.storage.nemesis, cfg.storage, "storage block")
for _, taken in ipairs({1, 67, 73, 89, 91, 92, 99, 106, 107, 136, 181, 201, 202, 140, 144, 145, 146, 210, 212, 213, 230, 246}) do
	ok(taken ~= ChaosOpcodes.nemesis, "opcode free of base " .. taken)
end
for name, v in pairs(ChaosOpcodes) do
	ok(name == "nemesis" or v ~= ChaosOpcodes.nemesis, "opcode not shared with " .. name)
end
do
	local p = io.popen("grep -rlE '(OPCODE|Opcode|opcode)[^0-9]{0,12}163\\b' ../client/overlay/modules data/scripts 2>/dev/null")
	local out = p and p:read("*a") or ""
	if p then p:close() end
	for line in out:gmatch("[^\n]+") do
		ok(line:find("nemesis", 1, true) ~= nil or line:find("chaos_constants", 1, true) ~= nil, "163 only for the nemesis: " .. line)
	end
end
-- the storage block is free: no other Chaos.storage value and no other config names 7102300 - 7102309
for name, v in pairs(Chaos.storage) do
	if type(v) == "number" and name ~= "nemesis" then
		ok(v < 7102300 or v > 7102309, "storage block free of Chaos.storage." .. name)
	end
end
do
	local p = io.popen("grep -rlE '\\b710230[0-9]\\b' data/scripts data/lib 2>/dev/null")
	local out = p and p:read("*a") or ""
	if p then p:close() end
	for line in out:gmatch("[^\n]+") do
		ok(line:find("nemesis", 1, true) ~= nil or line:find("chaos_constants", 1, true) ~= nil, "7102300 only for the nemesis: " .. line)
	end
end
-- the SQL file and the core's CREATE TABLE describe the same columns
do
	local f = io.open("sql/chaos_nemesis.sql")
	local sql = f and f:read("*a") or ""
	if f then f:close() end
	ok(sql:find("CREATE TABLE IF NOT EXISTS `chaos_nemesis`", 1, true) ~= nil, "sql file")
	for _, c in ipairs(K.SELECT_COLUMNS) do
		ok(sql:find("`" .. c .. "`", 1, true) ~= nil, "sql file column " .. c)
		ok(K.sqlCreate("chaos_nemesis"):find("`" .. c .. "`", 1, true) ~= nil, "core create column " .. c)
	end
end

-- ---------------------------------------------------------------- texts
eq(K.lang("pt-BR"), "pt"); eq(K.lang("pt"), "pt"); eq(K.lang("en"), "en"); eq(K.lang(nil), "en")
for key in pairs(cfg.texts.en) do
	ok(cfg.texts.pt[key] ~= nil, "pt-BR text for " .. key)
	local _, nEn = cfg.texts.en[key]:gsub("%%[sd]", "")
	local _, nPt = cfg.texts.pt[key]:gsub("%%[sd]", "")
	eq(nPt, nEn, "same placeholders in " .. key)
end
for key in pairs(cfg.texts.pt) do
	ok(cfg.texts.en[key] ~= nil, "English text for " .. key)
end
eq(K.text(cfg, "en", "warning"), "You feel a familiar hatred watching you...", "the warning")
eq(K.text(cfg, "pt-BR", "warning"), "Você sente um ódio familiar observando você...", "the warning in pt-BR")
eq(K.text(cfg, "en", "hunted", "Ana", "Varkh", 500), "Ana slew Varkh and claims the Nemesis Hunter bounty of 500 gold.")
eq(K.text(cfg, "en", "nope"), "nope", "an unknown key stays the key")
eq(K.text(cfg, "en", "appear"), cfg.texts.en.appear, "missing arguments: the raw text, no error")

-- ---------------------------------------------------------------- names and epithets
do
	local seen, rand = {}, rng(7)
	for _ = 1, 2000 do
		local name = K.genName(cfg, rand)
		ok(#name >= 3 and #name <= 12, "name length " .. name)
		ok(name:match("^[A-Z][a-z]+$") ~= nil, "one capitalised word " .. name)
		ok(not name:find("(%a)%1%1"), "no tripled letter " .. name)
		seen[name] = true
	end
	local distinct = 0
	for _ in pairs(seen) do distinct = distinct + 1 end
	ok(distinct >= 300, "many distinct names: " .. distinct)
	eq(K.genName(cfg, fixed("min")), "Varkh", "the first syllables")
end
local rec0 = {name = "Varkh", kills = 1}
eq(K.fullName(cfg, "en", rec0, "Varek"), "Varkh, Bane of Varek", "EN name")
eq(K.fullName(cfg, "pt", rec0, "Varek"), "Varkh, Flagelo de Varek", "PT-BR name")
rec0.kills = 2
eq(K.fullName(cfg, "en", rec0, "Varek"), "Varkh, Twice-Slayer of Varek", "second kill")
eq(K.fullName(cfg, "pt", rec0, "Varek"), "Varkh, Duas Vezes Algoz de Varek", "second kill in pt-BR")
rec0.kills = 3
eq(K.epithet(cfg, "en", "Varek", 3), "Thrice-Slayer of Varek")
eq(K.epithet(cfg, "en", "Varek", 9), "Doom of Varek", "more kills: the last epithet")
eq(K.epithet(cfg, "en", "Varek", 0), "Bane of Varek", "kills below 1 clamp")
eq(#cfg.epithets.en, #cfg.epithets.pt, "as many epithets in both languages")
eq(K.fullName(cfg, "en", {name = "Varkh", kills = 2}, "Abcdefghijklmnopqrstuvwxyzab"), "Varkh", "a long name drops the epithet")

-- ---------------------------------------------------------------- birth
local function killer(over)
	local k = {monster = true, name = "Ghoul", shown = "Ghoul", maxHealth = 400}
	for a, b in pairs(over or {}) do k[a] = b end
	return k
end
local function info(over)
	local i = {victimLevel = 80, killer = killer(), active = 0, serverActive = 0, endedAt = 0}
	for a, b in pairs(over or {}) do i[a] = b end
	return i
end
local NOW = 1800000000
ok(K.eligible(cfg, info(), NOW), "a regular monster, level 80: eligible")
ok(SKULL_BLACK ~= nil, "engine constant") -- the mocked globals get their numbers on first use
local function why(i) local _, r = K.eligible(cfg, i, NOW) return r end
eq(why(info({victimLevel = 49})), "level", "level 49 is too low")
ok(K.eligible(cfg, info({victimLevel = 50})), "level 50 is enough")
eq(why(info({killer = killer({boss = true})})), "boss")
eq(why(info({killer = killer({master = true})})), "summon")
eq(why(info({killer = killer({goblin = true})})), "goblin")
eq(why(info({killer = killer({nemesis = true})})), "nemesis")
eq(why(info({killer = killer({shown = "Rift Ghoul"})})), "event monster", "a renamed monster")
eq(why(info({killer = killer({maxHealth = 20})})), "weak")
eq(why(info({killer = {monster = false}})), "not a monster")
do
	local i = info()
	i.killer = nil
	eq(why(i), "not a monster", "no killer")
end
eq(why(info({pvp = true})), "pvp", "a player took part")
eq(why(info({instance = "rift"})), "instance")
eq(why(info({active = 1})), "has one", "at most one per character")
eq(why(info({endedAt = NOW - 3600})), "cooldown", "a nemesis ended an hour ago")
ok(K.eligible(cfg, info({endedAt = NOW - cfg.birth.cooldownSeconds}), NOW), "cooldown over")
eq(why(info({serverActive = cfg.birth.serverCap})), "server cap", "the hard cap")
cfg.birth.skipNames.ghoul = true
eq(why(info()), "skipped"); cfg.birth.skipNames.ghoul = nil
cfg.enabled = false
eq(why(info()), "disabled"); cfg.enabled = true
-- the chance and the soft cap
eq(K.birthChance(cfg, 0), 25, "25% below the soft cap")
eq(K.birthChance(cfg, cfg.birth.softCap), 25, "25% at the soft cap")
eq(K.birthChance(cfg, (cfg.birth.softCap + cfg.birth.serverCap) / 2), 12.5, "half way: half the chance")
eq(K.birthChance(cfg, cfg.birth.serverCap), 0, "0 at the hard cap")
eq(K.birthChance(cfg, cfg.birth.serverCap + 50), 0, "0 above")
do
	local rand, hits, N = rng(11), 0, 200000
	for _ = 1, N do
		if K.rollBirth(cfg, info(), NOW, rand) then hits = hits + 1 end
	end
	ok(math.abs(hits / N - 0.25) < 0.01, "25% per death: " .. hits / N)
	rand, hits = rng(12), 0
	for _ = 1, N do
		if K.rollBirth(cfg, info({serverActive = 250}), NOW, rand) then hits = hits + 1 end
	end
	ok(math.abs(hits / N - 0.125) < 0.01, "soft cap half way: " .. hits / N)
	eq(select(2, K.rollBirth(cfg, info({victimLevel = 10}), NOW, rand)), "level", "a refused death reports why")
	eq(select(2, K.rollBirth(cfg, info(), NOW, fixed(2501))), "roll", "the dice")
	ok(K.rollBirth(cfg, info(), NOW, fixed(2500)), "2500 of 10000 hits")
end

-- ---------------------------------------------------------------- level, growth, traits
eq(K.baseLevel(cfg, 120, 9999), 120, "the monster's level")
eq(K.baseLevel(cfg, 0, 2000), 100, "else max health / 20")
eq(K.baseLevel(cfg, 0, 0), 1, "at least 1")
eq(K.baseLevel(cfg, 99999, 0), 1500, "at most 1500")
eq(K.levelFor(cfg, 100, 10, 1), 110, "+10%")
eq(K.levelFor(cfg, 100, 20, 1), 120, "+20%")
eq(K.levelFor(cfg, 100, 15, 2), 125, "second kill +10% of the base")
eq(K.levelFor(cfg, 100, 15, 4), 145, "fourth kill")
eq(K.levelFor(cfg, 100, 15, 9), 145, "kills capped")
do
	local rand = rng(21)
	for _ = 1, 500 do
		local r = K.newRecord(cfg, {victim = 5, monster = "Ghoul", monsterLevel = 100, maxHealth = 400}, NOW, rand)
		ok(r.level >= 110 and r.level <= 120, "+10-20%: " .. r.level)
		eq(#r.traits, 1, "one trait at birth")
		ok(K.trait(cfg, r.traits[1]) ~= nil, "a known trait")
		eq(r.kills, 1); eq(r.created, NOW); eq(r.lastSeen, NOW); eq(r.victim, 5); eq(r.monster, "Ghoul")
	end
	-- trait weights
	local count = {}
	for _ = 1, 50000 do
		local t = K.pickTrait(cfg, {}, rand)
		count[t] = (count[t] or 0) + 1
	end
	for _, t in ipairs(cfg.traits) do
		ok(math.abs(count[t.key] / 50000 * 100 - t.weight) < 1.5, "trait weight " .. t.key)
	end
	ok(K.pickTrait(cfg, {"vengeful"}, rand) ~= "vengeful", "never a trait it holds")
	local all = {}
	for _, t in ipairs(cfg.traits) do all[#all + 1] = t.key end
	eq(K.pickTrait(cfg, all, rand), nil, "nothing left")
	-- every trait works through a monster_tiers.lua modifier or the stalker
	local tierSrc = io.open("data/scripts/chaos/monster_tiers.lua"):read("*a")
	for _, t in ipairs(cfg.traits) do
		ok(t.pt and t.desc and t.descPt, "trait texts in both languages: " .. t.key)
		if t.mod then
			ok(tierSrc:find("\n\t" .. t.mod .. " = {", 1, true) ~= nil, "modifier " .. t.mod .. " exists in monster_tiers.lua")
		else
			eq(t.key, "stalker", "only the stalker has no modifier")
		end
	end
end
do
	local rec = {baseLevel = 100, bump = 15, level = 115, kills = 1, traits = {"swift"}, lastSeen = 0}
	ok(K.grow(cfg, rec, NOW, rng(3)), "grows")
	eq(rec.kills, 2); eq(rec.level, 125); eq(#rec.traits, 2, "a second trait"); ok(rec.traits[2] ~= "swift", "a new one")
	eq(rec.lastSeen, NOW, "seen")
	ok(K.grow(cfg, rec, NOW + 1, rng(4)), "grows again")
	eq(#rec.traits, 2, "at most two traits"); eq(rec.kills, 3)
	ok(K.grow(cfg, rec, NOW + 2, rng(5)), "fourth kill"); eq(rec.kills, 4); eq(rec.level, 145)
	ok(not K.grow(cfg, rec, NOW + 3, rng(6)), "capped"); eq(rec.kills, 4); eq(rec.level, 145); eq(rec.lastSeen, NOW + 3)
	local st = K.stats(cfg, rec, 1000)
	eq(st.maxHealth, math.floor(1000 * cfg.stats.healthMult * 145 / 100), "health x mult x level ratio")
	eq(st.damage, cfg.stats.damageMult); eq(st.xp, cfg.stats.xpMult)
	local sp = K.stats(cfg, {baseLevel = 100, level = 110, traits = {"stalker"}}, 1000).speed
	eq(sp, cfg.stats.speed + 20, "the stalker is faster")
	eq(#K.modKeys(cfg, {traits = {"vengeful", "stalker"}}), 1, "stalker has no modifier")
	eq(K.modKeys(cfg, {traits = {"thorned"}})[1], "reflective")
end

-- ---------------------------------------------------------------- expiry
do
	local rec = {lastSeen = NOW}
	ok(not K.expired(cfg, rec, NOW + 13 * 86400), "13 days: still here")
	ok(K.expired(cfg, rec, NOW + 14 * 86400), "14 days without contact: gone")
	eq(K.sqlExpire(cfg, "chaos_nemesis", NOW), "DELETE FROM `chaos_nemesis` WHERE `last_seen` < " .. (NOW - 14 * 86400))
end

-- ---------------------------------------------------------------- appearing
do
	local rec = {monster = "Ghoul", baseLevel = 100}
	ok(K.matchesHunt(cfg, rec, "ghoul", 0), "same type (any case)")
	ok(K.matchesHunt(cfg, rec, "Mummy", 80), "level band low end")
	ok(K.matchesHunt(cfg, rec, "Mummy", 125), "level band high end")
	ok(not K.matchesHunt(cfg, rec, "Mummy", 74), "below the band")
	ok(not K.matchesHunt(cfg, rec, "Mummy", 126), "above the band")
	ok(not K.matchesHunt(cfg, rec, "Mummy", 0), "unknown level, other type")
	local kill = {name = "Ghoul", level = 100}
	local st = {}
	ok(K.appearRoll(cfg, rec, kill, st, NOW, fixed(1)), "a hit")
	eq(select(2, K.appearRoll(cfg, rec, kill, st, NOW, fixed(401))), "roll", "4%: 401 misses")
	ok(K.appearRoll(cfg, rec, kill, st, NOW, fixed(400)), "4%: 400 hits")
	eq(select(2, K.appearRoll(cfg, rec, kill, {alive = true}, NOW, fixed(1))), "already here")
	eq(select(2, K.appearRoll(cfg, rec, kill, {pending = true}, NOW, fixed(1))), "already here", "warning running")
	eq(select(2, K.appearRoll(cfg, rec, kill, {lastAppear = NOW - 60}, NOW, fixed(1))), "cooldown")
	ok(K.appearRoll(cfg, rec, kill, {lastAppear = NOW - cfg.appear.cooldownSeconds}, NOW, fixed(1)), "cooldown over")
	eq(select(2, K.appearRoll(cfg, rec, {name = "Ghoul", instance = "rift"}, st, NOW, fixed(1))), "area")
	eq(select(2, K.appearRoll(cfg, rec, {name = "Ghoul", pz = true}, st, NOW, fixed(1))), "area")
	eq(select(2, K.appearRoll(cfg, rec, {name = "Dragon", level = 300}, st, NOW, fixed(1))), "elsewhere")
	eq(select(2, K.appearRoll(cfg, nil, kill, st, NOW, fixed(1))), "none")
	local rand, hits = rng(31), 0
	for _ = 1, 100000 do
		if K.appearRoll(cfg, rec, kill, {}, NOW, rand) then hits = hits + 1 end
	end
	ok(math.abs(hits / 100000 - 0.04) < 0.004, "4% per kill: " .. hits / 100000)
	-- the ring: 3 to 6 tiles away, same floor, nearest ring first, every tile once
	local ring = K.ringPositions(cfg, {x = 100, y = 100, z = 7}, rng(32))
	local seen, last = {}, 0
	for _, p in ipairs(ring) do
		local d = math.max(math.abs(p.x - 100), math.abs(p.y - 100))
		ok(d >= 3 and d <= 6 and p.z == 7, "ring distance")
		ok(d >= last, "nearest ring first")
		last = d
		local key = p.x .. ":" .. p.y
		ok(not seen[key], "each tile once")
		seen[key] = true
	end
	eq(#ring, 24 + 32 + 40 + 48, "every tile of the rings")
end

-- ---------------------------------------------------------------- no griefing
ok(K.canHurt(5, 5, {}), "its victim")
ok(K.canHurt(5, 6, {5, 6, 7}), "the victim's party")
ok(not K.canHurt(5, 8, {5, 6, 7}), "a stranger")
ok(not K.canHurt(5, 8, nil), "a stranger, no party")

-- ---------------------------------------------------------------- rewards and anti-farm
do
	local rec = {level = 120, created = NOW - 3600, rewarded = false}
	local v = {guid = 5, account = 50, ip = 1111}
	local r = K.reward(cfg, rec, {guid = 5, account = 50, ip = 1111, isVictim = true, inParty = true}, v, NOW)
	eq(r.kind, "avenge"); ok(r.trophy, "trophy"); eq(r.title, "Avenger of Self")
	eq(r.gold, cfg.rewards.avenge.goldBase + cfg.rewards.avenge.goldPerLevel * 120, "loot bonus"); eq(r.goldTo, "corpse")
	r = K.reward(cfg, rec, {guid = 5, isVictim = true, lastAvenge = NOW - 3600}, v, NOW)
	eq(r.kind, "avenge"); ok(r.trophy, "the trophy even on the loot cooldown"); eq(r.gold, 0, "no loot bonus twice a day")
	eq(r.reason, "cooldown")
	r = K.reward(cfg, rec, {guid = 5, isVictim = true, lastAvenge = NOW - cfg.rewards.avenge.cooldownSeconds}, v, NOW)
	ok(r.gold > 0, "loot cooldown over")
	r = K.reward(cfg, rec, {guid = 5, isVictim = true, hc = true}, v, NOW)
	ok(r.trophy and r.gold == 0, "Hardcore: the trophy only"); eq(r.reason, "hardcore")
	-- the party's hunter
	r = K.reward(cfg, rec, {guid = 6, account = 60, ip = 2222, inParty = true}, v, NOW)
	eq(r.kind, "hunt"); ok(not r.trophy, "no trophy for the hunter")
	eq(r.gold, cfg.rewards.bounty.goldBase + cfg.rewards.bounty.goldPerLevel * 120, "bounty"); eq(r.goldTo, "bank")
	r = K.reward(cfg, rec, {guid = 6, account = 50, ip = 2222, inParty = true}, v, NOW)
	eq(r.gold, 0, "the victim's own account: no bounty"); eq(r.reason, "same owner")
	r = K.reward(cfg, rec, {guid = 6, account = 60, ip = 1111, inParty = true}, v, NOW)
	eq(r.gold, 0, "the victim's connection: no bounty"); eq(r.reason, "same owner")
	r = K.reward(cfg, rec, {guid = 6, account = 60, ip = 0, inParty = true}, {guid = 5, account = 50, ip = 0}, NOW)
	ok(r.gold > 0, "ip 0 (no connection) never matches")
	r = K.reward(cfg, {level = 120, created = NOW - 60}, {guid = 6, account = 60, ip = 2222, inParty = true}, v, NOW)
	eq(r.gold, 0, "a nemesis born a minute ago pays nothing"); eq(r.reason, "too young")
	r = K.reward(cfg, rec, {guid = 6, account = 60, ip = 2222, inParty = true, lastBounty = NOW - 600}, v, NOW)
	eq(r.gold, 0, "bounty cooldown"); eq(r.reason, "cooldown")
	r = K.reward(cfg, rec, {guid = 6, account = 60, ip = 2222, inParty = true, hc = true}, v, NOW)
	eq(r.gold, 0, "a Hardcore hunter: nothing to trade"); eq(r.reason, "hardcore")
	r = K.reward(cfg, rec, {guid = 9, account = 90, ip = 3333, inParty = false}, v, NOW)
	eq(r.kind, "none"); eq(r.reason, "stranger")
	rec.rewarded = true
	r = K.reward(cfg, rec, {guid = 5, isVictim = true}, v, NOW)
	eq(r.kind, "none", "the trophy only once per nemesis"); eq(r.reason, "rewarded")
	-- titles
	eq(#K.titles(cfg, 0, 0), 0)
	eq(K.titles(cfg, 1, 0)[1].text, "Avenger of Self")
	eq(#K.titles(cfg, 0, 2), 0, "two hunts: not yet")
	eq(K.titles(cfg, 0, 3)[1].text, "Nemesis Hunter")
	eq(#K.titles(cfg, 2, 5), 2)
	for _, t in ipairs(K.titles(cfg, 2, 5)) do ok(#t.text <= 24, "title fits the plate") end
	-- coins
	local total = 0
	for _, c in ipairs(K.coins(23456)) do
		total = total + c.count * ({[2160] = 10000, [2152] = 100, [2148] = 1})[c.id]
		ok(c.count >= 1 and c.count <= 100, "stack size")
	end
	eq(total, 23456, "coins add up")
	eq(#K.coins(0), 0)
end

-- ---------------------------------------------------------------- persistence
do
	local function esc(s) return "'" .. tostring(s):gsub("'", "''") .. "'" end
	local rec = {victim = 5, monster = "Ghoul", name = "Varkh", baseLevel = 100, level = 115, bump = 15, kills = 1,
		traits = {"swift", "thorned"}, created = NOW, lastSeen = NOW, appearances = 0, hc = true}
	local q = K.sqlInsert("chaos_nemesis", rec, esc)
	ok(q:find("VALUES (5, 'Ghoul', 'Varkh', 100, 115, 15, 1, 'swift,thorned', " .. NOW .. ", " .. NOW .. ", 0, 1)", 1, true) ~= nil, q)
	rec.id = 7
	q = K.sqlUpdate("chaos_nemesis", rec, esc)
	ok(q:find("WHERE `id` = 7 AND `player_id` = 5", 1, true) ~= nil, "update own row only")
	eq(K.sqlDelete("chaos_nemesis", rec), "DELETE FROM `chaos_nemesis` WHERE `id` = 7 AND `player_id` = 5")
	ok(K.sqlSelectVictim("chaos_nemesis", 5):find("WHERE `player_id` = 5", 1, true) ~= nil, "select by victim")
	local r2 = K.fromRow(cfg, {id = 7, player_id = 5, monster = "Ghoul", name = "Varkh", base_level = 100, level = 115,
		bump = 15, kills = 9, traits = "swift,bogus,thorned,regenerating,swift", created = NOW, last_seen = NOW, hc = 1})
	eq(r2.kills, cfg.level.maxKills, "kills clamped")
	eq(#r2.traits, 2, "unknown traits dropped, at most maxTraits"); eq(r2.traits[2], "thorned")
	ok(r2.hc, "hc flag")
	eq(K.fromRow(cfg, {id = 1, player_id = 5, monster = ""}), nil, "broken row")
	eq(K.fromRow(cfg, {id = "x", player_id = 5, monster = "Ghoul"}), nil, "broken id")
	eq(K.encodeTraits({"a", "b"}), "a,b")
end

-- ---------------------------------------------------------------- client view
do
	local v = K.view(cfg, nil, "Varek", NOW, "en", {avenged = 2, hunted = 1})
	eq(v.has, false); eq(v.avenged, 2); eq(v.hunted, 1)
	local rec = {name = "Varkh", monster = "Ghoul", level = 115, kills = 2, traits = {"swift", "thorned"},
		created = NOW - 100, lastSeen = NOW - 86400, baseLevel = 100}
	v = K.view(cfg, rec, "Varek", NOW, "en")
	eq(v.has, true); eq(v.shown, "Varkh, Twice-Slayer of Varek"); eq(v.monster, "Ghoul"); eq(v.level, 115)
	eq(#v.traits, 2); eq(v.traits[1].name, "Swift"); eq(v.traits[2].desc, "Reflects 15% of the damage it takes.")
	eq(v.expiresIn, 13 * 86400, "expires 14 days after last seen")
	v = K.view(cfg, rec, "Varek", NOW, "pt-BR")
	eq(v.traits[1].name, "Veloz", "pt-BR trait"); eq(v.shown, "Varkh, Duas Vezes Algoz de Varek")
	rec.lastSeen = NOW - 30 * 86400
	eq(K.view(cfg, rec, "Varek", NOW, "en").expiresIn, 0, "never negative")
end

-- ================================================================ nemesis.lua against a mocked engine
local registry, globals = {}, {}
function CreatureEvent(name)
	local o = {name = name}
	function o:type(t) self.t = t end
	function o:register() registry[name] = self end
	return o
end
function GlobalEvent(name)
	local o = {name = name}
	function o:type() end
	function o:interval() end
	function o:register() globals[name] = self end
	return o
end
local queue = {}
function addEvent(fn, delay, ...)
	queue[#queue + 1] = {fn = fn, delay = delay, args = {n = select("#", ...), ...}}
	return #queue
end
local function runEvents(limit)
	local ran = 0
	while #queue > 0 and ran < (limit or 100) do
		local e = table.remove(queue, 1)
		ran = ran + 1
		e.fn((table.unpack or unpack)(e.args, 1, e.args.n))
	end
end
local clock = NOW
os.time = function() return clock end
local mclock = 1000000
os.mtime = function() return mclock end
math.randomseed(1)

local sent = {}
json = {encode = function(t) sent[#sent + 1] = t return "#" .. #sent end,
	decode = function(s) if s == "get" then return {action = "get"} end error("bad json") end}

-- database: one table, parsed back from the core's SQL
local rows, nextId, queries = {}, 0, {}
db = {}
function db.escapeString(s) return "'" .. tostring(s):gsub("'", "''") .. "'" end
function db.query(q)
	queries[#queries + 1] = q
	if q:find("^CREATE TABLE") then return true end
	local vals = q:match("^INSERT INTO `chaos_nemesis` %(.-%) VALUES %((.*)%)$")
	if vals then
		local f = {}
		for part in (vals .. ","):gmatch("%s*('?[^,]*'?)%s*,") do f[#f + 1] = part:gsub("^'(.*)'$", "%1") end
		-- the traits field may hold a comma: join fields 8 .. #f - 4
		local traits = table.concat(f, ",", 8, #f - 4)
		nextId = nextId + 1
		rows[#rows + 1] = {id = nextId, player_id = tonumber(f[1]), monster = f[2], name = f[3], base_level = tonumber(f[4]),
			level = tonumber(f[5]), bump = tonumber(f[6]), kills = tonumber(f[7]), traits = traits,
			created = tonumber(f[#f - 3]), last_seen = tonumber(f[#f - 2]), appearances = tonumber(f[#f - 1]),
			hc = tonumber(f[#f])}
		return true
	end
	local cut = q:match("^DELETE FROM `chaos_nemesis` WHERE `last_seen` < (%d+)$")
	if cut then
		for i = #rows, 1, -1 do if rows[i].last_seen < tonumber(cut) then table.remove(rows, i) end end
		return true
	end
	return true
end
function db.asyncQuery(q)
	queries[#queries + 1] = q
	local id, pid = q:match("^DELETE FROM `chaos_nemesis` WHERE `id` = (%d+) AND `player_id` = (%d+)$")
	if id then
		for i = #rows, 1, -1 do
			if rows[i].id == tonumber(id) and rows[i].player_id == tonumber(pid) then table.remove(rows, i) end
		end
		return true
	end
	local level, kills, traits, seen, app, uid, upid = q:match("^UPDATE `chaos_nemesis` SET `level` = (%d+), `kills` = (%d+), `traits` = '(.-)', `last_seen` = (%d+), `appearances` = (%d+) WHERE `id` = (%d+) AND `player_id` = (%d+)$")
	if level then
		for _, r in ipairs(rows) do
			if r.id == tonumber(uid) and r.player_id == tonumber(upid) then
				r.level, r.kills, r.traits, r.last_seen, r.appearances = tonumber(level), tonumber(kills), traits, tonumber(seen), tonumber(app)
			end
		end
	end
	return true
end
function db.lastInsertId() return nextId end
-- Chaos.select over the rows (the two queries the module makes)
function Chaos.select(q, columns)
	if q:find("COUNT%(%*%)") then return {{n = #rows}} end
	local pid = tonumber(q:match("WHERE `player_id` = (%d+)"))
	local out = {}
	for i = #rows, 1, -1 do
		if rows[i].player_id == pid then
			local copy = {}
			for k, v in pairs(rows[i]) do copy[k] = v end
			out[#out + 1] = copy
		end
	end
	return out
end

-- positions, tiles, creatures
local PosMT = {}
PosMT.__index = PosMT
function Position(x, y, z) return setmetatable({x = x, y = y, z = z}, PosMT) end
local effects = {}
function PosMT:sendMagicEffect(e) effects[#effects + 1] = e end
function PosMT:getDistance(o) return math.max(math.abs(self.x - o.x), math.abs(self.y - o.y)) end
dofile("data/scripts/chaos/spawn_tile_core.lua")
local blockedTiles, pzTiles, occupied, waterTiles = {}, {}, {}, {}
local function key(p) return p.x .. ":" .. p.y .. ":" .. p.z end
function Tile(p)
	if blockedTiles[key(p)] then return nil end
	return {
		getGround = function() return {getType = function() return {getFluidSource = function() return waterTiles[key(p)] and 1 or 0 end} end} end,
		getTopCreature = function() return occupied[key(p)] end,
		hasFlag = function(_, f) return pzTiles[key(p)] == true and f == TILESTATE_PROTECTIONZONE end,
		getHouse = function() return nil end,
		isWalkable = function() return true end
	}
end

local creatures, nextCid = {}, 0x10000000
local Creature = {}
Creature.__index = Creature
local function newCreature(kind, t)
	nextCid = nextCid + 1
	t.id = t.id or nextCid
	t.kind = kind
	t.events = {}
	t.storage = t.storage or {}
	t.msgs = {}
	t.health = t.health or t.maxHealth or 100
	t.outfit = {lookType = 10}
	creatures[t.id] = setmetatable(t, Creature)
	return t
end
function Creature:getId() return self.id end
function Creature:isPlayer() return self.kind == "player" end
function Creature:isMonster() return self.kind == "monster" end
function Creature:getName() return self.name end
function Creature:getPosition() return Position(self.pos.x, self.pos.y, self.pos.z) end
function Creature:getMaster() return self.master end
function Creature:getMaxHealth() return self.maxHealth end
function Creature:setMaxHealth(v) self.maxHealth = v end
function Creature:setHealth(v) self.health = v end
function Creature:getHealth() return self.health end
function Creature:changeSpeed(d) self.speedDelta = (self.speedDelta or 0) + d end
function Creature:getOutfit() local o = {} for k, v in pairs(self.outfit) do o[k] = v end return o end
function Creature:setOutfit(o) self.outfit = o end
function Creature:setSkull(s) self.skull = s end
function Creature:registerEvent(n) self.events[n] = true end
function Creature:unregisterEvent(n) self.events[n] = nil end
function Creature:remove() creatures[self.id] = nil self.removed = true end
function Creature:teleportTo(p) self.pos = {x = p.x, y = p.y, z = p.z} end
function Creature:getTarget() return self.target end
function Creature:selectTarget(c) self.target = c end
function Creature:getType()
	local me = self
	return {isBoss = function() return me.boss == true end, name = function() return me.typeName or me.name end}
end
-- players
function Creature:getGuid() return self.guid end
function Creature:getLevel() return self.level end
function Creature:getAccountId() return self.account end
function Creature:getIp() return self.ip end
function Creature:getParty() return self.party end
function Creature:getStorageValue(k) return self.storage[k] or -1 end
function Creature:setStorageValue(k, v) self.storage[k] = v end
function Creature:sendTextMessage(t, s) self.msgs[#self.msgs + 1] = s end
function Creature:sendExtendedOpcode(op, s) self.ext = self.ext or {} self.ext[#self.ext + 1] = {op = op, s = s} return true end
function Creature:getBankBalance() return self.bank or 0 end
function Creature:setBankBalance(v) self.bank = v end
local trophies = {}
function Creature:addItemEx(item) if self.fullBag then return 1 end trophies[#trophies + 1] = {to = self, item = item} return 0 end
function Creature:getInbox() return nil end
function Player(x)
	local c = type(x) == "table" and x or creatures[x]
	return c and c.kind == "player" and c or nil
end
function Monster(x)
	local c = type(x) == "table" and x or creatures[x]
	return c and c.kind == "monster" and c or nil
end
local created = {}
Game = {}
function Game.createMonster(typeName, pos, extended, force)
	local m = newCreature("monster", {name = Chaos.spawnName or typeName, typeName = typeName,
		pos = {x = pos.x, y = pos.y, z = pos.z}, maxHealth = 400})
	created[#created + 1] = m
	return m
end
local ItemMT = {}
ItemMT.__index = ItemMT
function ItemMT:setAttribute(k, v) self.attr[k] = v end
function ItemMT:setCustomAttribute(k, v) self.custom[k] = v end
function Game.createItem(id, count) return setmetatable({id = id, count = count, attr = {}, custom = {}}, ItemMT) end

-- a minimal monster_tiers.lua surface (the module wraps it)
ChaosTiers = {rare = {label = "Rare", damage = 1.5, xp = 4}}
ChaosTierState = {}
ChaosTierConfig = {maxChain = 2, bosses = {}}
local regenTicks = 0
ChaosMods = {berserker = {}, swift = {}, reflective = {}, regenerating = {onTick = function() regenTicks = regenTicks + 1 end}}
function ChaosTierOf(c) local s = ChaosTierState[c:getId()] return s and s.tier or (c.boss and "boss" or "normal") end
ChaosLoot = {monsterLevel = function(m) return m.monsterLevel or 0 end}
local progress = {}
ChaosAchievements = {progress = function(p, k, n) progress[#progress + 1] = {p = p:getName(), k = k, n = n} end}
local titleSources = {}
ChaosTitles = {register = function(src, fn) titleSources[src] = fn end}
local refreshed = 0
ChaosNameplate = {refresh = function() refreshed = refreshed + 1 end}
local instances = {}
function Chaos.inAnyInstance(p) return instances[p:getGuid()] end
function Chaos.instanceAt() return nil end
local limited = false
function Chaos.limited() return limited end

dofile("data/scripts/chaos/nemesis.lua")
local NE = ChaosNemesis
local R = registry
ok(R.ChaosNemesisDeath and R.ChaosNemesisKill and R.ChaosNemesisLogin and R.ChaosNemesisLogout and R.ChaosNemesisGuard
	and R.ChaosNemesisTaken and R.ChaosNemesisMonsterDeath and R.ChaosNemesisExtended, "every event registered")
ok(globals.ChaosNemesisStartup and globals.ChaosNemesisHourly, "startup and hourly")
eq(ChaosTiers.nemesis.label, "Nemesis", "the tier is added to monster_tiers.lua's table")
eq(ChaosTiers.nemesis.damage, cfg.stats.damageMult); eq(ChaosTiers.nemesis.xp, cfg.stats.xpMult)
eq(ChaosTiers.rare.label, "Rare", "other tiers untouched")
ok(titleSources.nemesis ~= nil, "title source registered")
globals.ChaosNemesisStartup.onStartup()
ok(queries[1]:find("CREATE TABLE IF NOT EXISTS `chaos_nemesis`", 1, true) ~= nil, "table created at startup")
eq(NE.serverActive, 0, "nobody has one")

local cfgLive = ChaosNemesisConfig
local function player(name, guid, over)
	local p = newCreature("player", {name = name, guid = guid, level = 100, account = guid * 10, ip = guid * 1000,
		pos = {x = 100, y = 100, z = 7}})
	for k, v in pairs(over or {}) do p[k] = v end
	R.ChaosNemesisLogin.onLogin(p)
	return p
end
local function monster(name, over)
	local m = newCreature("monster", {name = name, typeName = name, maxHealth = 1000, monsterLevel = 100,
		pos = {x = 101, y = 100, z = 7}})
	for k, v in pairs(over or {}) do m[k] = v end
	return m
end
local function lastMsg(p) return p.msgs[#p.msgs] end
-- the victim kills a ghoul and the scheduled appearance runs (old ticks of earlier nemeses are dropped)
local function callIt(p)
	queue = {}
	R.ChaosNemesisKill.onKill(p, monster("Ghoul"))
	local e = table.remove(queue, 1)
	ok(e ~= nil and e.fn == NE.appear, "the appearance is scheduled")
	if e then e.fn((table.unpack or unpack)(e.args, 1, e.args.n)) end
	return created[#created]
end

local varek = player("Varek", 5)
ok(varek.events.ChaosNemesisDeath and varek.events.ChaosNemesisGuard and varek.events.ChaosNemesisGuardMana
	and varek.events.ChaosNemesisExtended,
	"death, guard and opcode events at login")
ok(not varek.events.ChaosNemesisKill, "no kill event without a nemesis (no cost)")

-- deaths that never make one (chance 100% for the test)
cfgLive.birth.chance = 100
local boss = monster("Ghoul", {boss = true})
R.ChaosNemesisDeath.onDeath(varek, nil, boss, boss)
eq(#rows, 0, "a boss: none")
local rifty = monster("Ghoul", {name = "Rift Ghoul"})
R.ChaosNemesisDeath.onDeath(varek, nil, rifty, rifty)
eq(#rows, 0, "a renamed event monster: none")
local pk = player("Killer", 99)
local ghoul = monster("Ghoul")
R.ChaosNemesisDeath.onDeath(varek, nil, ghoul, pk)
eq(#rows, 0, "PvP: none")
instances[5] = "rift"
R.ChaosNemesisDeath.onDeath(varek, nil, ghoul, ghoul)
eq(#rows, 0, "in an instance: none")
instances[5] = nil
local summon = monster("Ghoul", {master = pk})
R.ChaosNemesisDeath.onDeath(varek, nil, summon, summon)
eq(#rows, 0, "a summon: none")
local low = player("Lowbie", 6, {level = 30})
R.ChaosNemesisDeath.onDeath(low, nil, ghoul, ghoul)
eq(#rows, 0, "level 30: none")

-- the birth
R.ChaosNemesisDeath.onDeath(varek, nil, ghoul, ghoul)
eq(#rows, 1, "a row")
local rec = NE.records[5]
ok(rec ~= nil and rec.id == 1, "cached with its id")
eq(rec.monster, "Ghoul"); ok(rec.level >= 110 and rec.level <= 120, "level bump"); eq(rec.baseLevel, 100)
eq(NE.serverActive, 1, "counted")
ok(varek.events.ChaosNemesisKill, "the kill event now")
ok(lastMsg(varek):find("A Nemesis is born: " .. rec.name .. ", Bane of Varek", 1, true) ~= nil, lastMsg(varek))
eq(progress[#progress].k, "nemesis_marked", "achievement stat fed")
-- a second death: at most one
R.ChaosNemesisDeath.onDeath(varek, nil, monster("Mummy"), nil)
eq(#rows, 1, "one per character")

-- logout and login: loaded from the row
R.ChaosNemesisLogout.onLogout(varek)
eq(NE.records[5], nil, "forgotten at logout")
varek.events = {}
R.ChaosNemesisLogin.onLogin(varek)
ok(NE.records[5] and NE.records[5].name == rec.name, "loaded at login")
ok(varek.events.ChaosNemesisKill, "kill event again")
rec = NE.records[5]

-- the opcode
sent = {}
R.ChaosNemesisExtended.onExtendedOpcode(varek, 162, "get")
eq(#sent, 0, "another opcode: nothing")
R.ChaosNemesisExtended.onExtendedOpcode(varek, 163, "nonsense")
eq(#sent, 0, "bad JSON: nothing")
limited = true
R.ChaosNemesisExtended.onExtendedOpcode(varek, 163, "get")
eq(#sent, 0, "rate limited: nothing")
limited = false
R.ChaosNemesisExtended.onExtendedOpcode(varek, 163, "get")
eq(#sent, 1, "state sent")
eq(sent[1].action, "state"); eq(sent[1].data.has, true); eq(sent[1].data.monster, "Ghoul")
eq(varek.ext[#varek.ext].op, 163, "on the nemesis opcode")

-- the victim's kills call it: chance 100%, a different type far off the band does not
cfgLive.appear.chance = 100
NE.onVictimKill(varek, monster("Dragon", {monsterLevel = 400}))
eq(#queue, 0, "another kind of hunt: nothing")
local before = #created
R.ChaosNemesisKill.onKill(varek, monster("Ghoul"))
eq(lastMsg(varek), "You feel a familiar hatred watching you...", "the warning")
eq(#queue, 1, "the spawn is scheduled")
eq(queue[1].delay, cfgLive.appear.delayMs)
R.ChaosNemesisKill.onKill(varek, monster("Ghoul"))
eq(#queue, 1, "no second call while one is pending")
local spawnEvent = table.remove(queue, 1)
spawnEvent.fn((table.unpack or unpack)(spawnEvent.args, 1, spawnEvent.args.n))
eq(#created, before + 1, "the nemesis is created")
local nem = created[#created]
local shown = rec.name .. ", Bane of Varek"
eq(nem.name, shown, "with its shown name")
local d = math.max(math.abs(nem.pos.x - 100), math.abs(nem.pos.y - 100))
ok(d >= 3 and d <= 6, "3-6 tiles away: " .. d)
eq(nem.outfit.lookShader, cfgLive.look.shader, "the Heartblood shader")
eq(nem.skull, SKULL_BLACK, "a black skull")
eq(nem.maxHealth, math.floor(400 * cfgLive.stats.healthMult * rec.level / rec.baseLevel), "health")
eq(ChaosTierState[nem.id].tier, "nemesis", "monster_tiers.lua state: tier nemesis")
eq(ChaosTierState[nem.id].depth, ChaosTierConfig.maxChain, "never an ambush copy")
ok(nem.events.ChaosTierDeath and nem.events.ChaosModTaken and nem.events.ChaosNemesisMonsterDeath, "events on it")
eq(nem.target, varek, "it targets its victim")
eq(lastMsg(varek), shown .. " has found you!")
eq(NE.byVictim[5], nem.id)
eq(rec.appearances, 1)
R.ChaosNemesisKill.onKill(varek, monster("Ghoul"))
eq(#queue, 1, "while it is here only its tick runs")
-- the kill of the nemesis itself never calls another
ok(not NE.onVictimKill(varek, nem), "its own death is no call")

-- no griefing: a stranger takes no damage from it, the victim and the party do
local stranger = player("Stranger", 7, {pos = {x = 102, y = 100, z = 7}})
local a, _, b = R.ChaosNemesisGuard.onHealthChange(stranger, nem, -100, 1, -20, 2, 0)
eq(a, 0, "stranger: no damage"); eq(b, 0)
a = R.ChaosNemesisGuard.onHealthChange(varek, nem, -100, 1, 0, 2, 0)
eq(a, -100, "victim: damage")
local friend = player("Friend", 8, {pos = {x = 99, y = 100, z = 7}})
local party = {getMembers = function() return {friend} end, getLeader = function() return varek end}
varek.party, friend.party = party, party
a = R.ChaosNemesisGuard.onHealthChange(friend, nem, -100, 1, 0, 2, 0)
eq(a, -100, "party member: damage")
a = R.ChaosNemesisGuardMana.onManaChange(stranger, nem, -100, 1, 0, 2, 0)
eq(a, 0, "stranger: no mana damage either")
a = R.ChaosNemesisGuardMana.onManaChange(friend, nem, -100, 1, 0, 2, 0)
eq(a, -100, "party member: mana damage")
a = R.ChaosNemesisGuard.onHealthChange(stranger, ghoul, -100, 1, 0, 2, 0)
eq(a, -100, "other monsters are not touched")
-- nobody steals the revenge: a stranger deals it no damage, the party does
a = R.ChaosNemesisTaken.onHealthChange(nem, stranger, -500, 1, 0, 2, 0)
eq(a, 0, "a stranger cannot hurt it")
a = R.ChaosNemesisTaken.onHealthChange(nem, friend, -500, 1, 0, 2, 0)
eq(a, -500, "the party can")
local strangerPet = monster("Wolf", {master = stranger})
a = R.ChaosNemesisTaken.onHealthChange(nem, strangerPet, -500, 1, 0, 2, 0)
eq(a, 0, "nor a stranger's summon")
-- a stranger killing the victim's nemesis by a last hit gets nothing either way: credit check below

-- the tick: regeneration through the modifier, lifetime
rec.traits = {"regenerating"}
local tickEvent = table.remove(queue, 1)
tickEvent.fn((table.unpack or unpack)(tickEvent.args, 1, tickEvent.args.n))
eq(regenTicks, 1, "Regenerating heals on the tick")
eq(#queue, 1, "the tick goes on")
-- growth: it kills its victim again
local lvl = rec.level
R.ChaosNemesisDeath.onDeath(varek, nil, nem, nem)
eq(rec.kills, 2, "a second kill"); eq(rec.level, lvl + 10, "more level")
eq(#rec.traits, 2, "a second trait")
eq(rows[1].kills, 2, "saved"); ok(lastMsg(varek):find("Twice-Slayer of Varek", 1, true) ~= nil, lastMsg(varek))
eq(#rows, 1, "no new nemesis from its own kill")
-- the victim moves to another floor: it vanishes and comes back another time
varek.pos = {x = 100, y = 100, z = 8}
tickEvent = table.remove(queue, 1)
tickEvent.fn((table.unpack or unpack)(tickEvent.args, 1, tickEvent.args.n))
ok(nem.removed, "vanished"); eq(NE.byVictim[5], nil)
ok(lastMsg(varek):find("fades back into the shadows", 1, true) ~= nil, lastMsg(varek))
eq(#rows, 1, "the row stays")
varek.pos = {x = 100, y = 100, z = 7}

-- the appearance cooldown
R.ChaosNemesisKill.onKill(varek, monster("Ghoul"))
eq(#queue, 0, "cooldown after an appearance")
clock = clock + cfgLive.appear.cooldownSeconds
mclock = mclock + cfgLive.appear.cooldownSeconds * 1000
R.ChaosNemesisKill.onKill(varek, monster("Ghoul"))
eq(#queue, 1, "after the cooldown")
spawnEvent = table.remove(queue, 1)
spawnEvent.fn((table.unpack or unpack)(spawnEvent.args, 1, spawnEvent.args.n))
nem = created[#created]
ok(nem.name:find("Twice-Slayer", 1, true) ~= nil, "the new epithet: " .. nem.name)

-- the victim slays it: trophy, title, loot bonus
local corpse = {items = {}}
function corpse:addItem(id, count) self.items[#self.items + 1] = {id = id, count = count} return true end
local kind = NE.onNemesisDeath(nem, corpse, varek, varek)
eq(kind, "avenge", "avenged")
eq(#rows, 0, "the row is deleted"); eq(NE.records[5], nil); eq(NE.serverActive, 0)
eq(#trophies, 1, "one trophy")
local tr0 = trophies[1].item
eq(tr0.id, cfgLive.rewards.trophy.id, "a stock trophy item")
eq(tr0.custom.chaos_storebound, 1, "store-bound"); eq(tr0.custom.chaos_locked, 1, "locked")
eq(tr0.custom.chaos_nemesis_owner, 5, "owner")
ok(tr0.custom.chaos_nemesis_name:find(rec.name, 1, true) == 1, "engraved name: " .. tostring(tr0.custom.chaos_nemesis_name))
ok(tostring(tr0.attr[ITEM_ATTRIBUTE_DESCRIPTION]):find("Engraved:", 1, true) == 1, "description")
local gold = 0
for _, c in ipairs(corpse.items) do gold = gold + c.count * ({[2160] = 10000, [2152] = 100, [2148] = 1})[c.id] end
eq(gold, cfgLive.rewards.avenge.goldBase + cfgLive.rewards.avenge.goldPerLevel * rec.level, "loot bonus in the corpse")
eq(varek.storage[7102300], 1, "avenged counter")
ok(varek.storage[7102304] == clock, "the birth cooldown starts")
ok(not varek.events.ChaosNemesisKill, "the kill event is gone")
eq(titleSources.nemesis(varek)[1].text, "Avenger of Self", "the title")
ok(refreshed >= 1, "name plate refreshed")
eq(progress[#progress].k, "nemesis_avenged")
eq(select(1, NE.onNemesisDeath(nem, corpse, varek, varek)), "unknown", "a second death event pays nothing")
eq(#trophies, 1, "still one trophy")
eq(sent[#sent].action, "state"); eq(sent[#sent].data.has, false, "the window is told"); eq(sent[#sent].data.avenged, 1)

-- anti-farm: a new death right away makes no new nemesis (cooldown)
R.ChaosNemesisDeath.onDeath(varek, nil, ghoul, ghoul)
eq(#rows, 0, "birth cooldown after the end")
clock = clock + cfgLive.birth.cooldownSeconds
R.ChaosNemesisDeath.onDeath(varek, nil, ghoul, ghoul)
eq(#rows, 1, "after the cooldown a new one")
rec = NE.records[5]

-- a party member slays it: the Nemesis Hunter bounty, a notice to the victim, no trophy
-- too young: born less than minAgeSeconds ago (the last appearance was long ago: no appearance cooldown)
clock = clock + 60
nem = callIt(varek)
kind = NE.onNemesisDeath(nem, corpse, friend, friend)
eq(kind, "hunt"); eq(friend.bank, nil, "too young: no bounty")
eq(lastMsg(friend), "No bounty for this Nemesis.")
eq(lastMsg(varek), "Friend slew your Nemesis, " .. nem.name .. ".", "the victim is told")
eq(#trophies, 1, "no trophy for anybody")
eq(friend.storage[7102301], 1, "hunted counter")
-- another one, old enough
clock = clock + cfgLive.birth.cooldownSeconds
R.ChaosNemesisDeath.onDeath(varek, nil, ghoul, ghoul)
rec = NE.records[5]
clock = clock + cfgLive.rewards.bounty.minAgeSeconds + cfgLive.appear.cooldownSeconds
nem = callIt(varek)
kind = NE.onNemesisDeath(nem, corpse, friend, friend)
eq(kind, "hunt")
eq(friend.bank, cfgLive.rewards.bounty.goldBase + cfgLive.rewards.bounty.goldPerLevel * rec.level, "bounty to the bank")
ok(lastMsg(friend):find("Nemesis Hunter bounty", 1, true) ~= nil, lastMsg(friend))
eq(progress[#progress].k, "nemesis_hunted")
-- a third one within 6 h: the hunter's bounty cooldown (the victim's birth cooldown is cleared for the test)
varek.storage[7102304] = 0
R.ChaosNemesisDeath.onDeath(varek, nil, ghoul, ghoul)
clock = clock + cfgLive.rewards.bounty.minAgeSeconds + cfgLive.appear.cooldownSeconds
nem = callIt(varek)
local bank = friend.bank
clock = clock + 60
NE.onNemesisDeath(nem, corpse, friend, friend)
eq(friend.bank, bank, "bounty cooldown: once per 6 h")
eq(friend.storage[7102301], 3, "three hunts")
eq(titleSources.nemesis(friend)[1].text, "Nemesis Hunter", "the hunter title after 3")

-- logout while it is out: it vanishes with its victim
clock = clock + cfgLive.birth.cooldownSeconds
R.ChaosNemesisDeath.onDeath(varek, nil, ghoul, ghoul)
clock = clock + cfgLive.appear.cooldownSeconds
nem = callIt(varek)
R.ChaosNemesisLogout.onLogout(varek)
ok(nem.removed, "removed at logout"); eq(#rows, 1, "the row stays")
-- the spawn never lands in a protection zone or an instance
queue = {}
varek.events = {}
R.ChaosNemesisLogin.onLogin(varek)
for dx = -6, 6 do for dy = -6, 6 do pzTiles[(100 + dx) .. ":" .. (100 + dy) .. ":7"] = true end end
clock = clock + cfgLive.appear.cooldownSeconds
before = #created
R.ChaosNemesisKill.onKill(varek, monster("Ghoul"))
spawnEvent = table.remove(queue, 1)
spawnEvent.fn((table.unpack or unpack)(spawnEvent.args, 1, spawnEvent.args.n))
eq(#created, before, "all tiles protection zone: no spawn")
pzTiles = {}

-- expiry at login
R.ChaosNemesisLogout.onLogout(varek)
clock = clock + 15 * 86400
varek.events = {}
R.ChaosNemesisLogin.onLogin(varek)
eq(NE.records[5], nil, "expired")
eq(#rows, 0, "row deleted")
ok(lastMsg(varek):find("lost your trail", 1, true) ~= nil, lastMsg(varek))
ok(not varek.events.ChaosNemesisKill, "no kill event")

-- the hourly expiry and count
rows[#rows + 1] = {id = 99, player_id = 77, monster = "Ghoul", name = "Mok", base_level = 1, level = 1, bump = 0,
	kills = 1, traits = "", created = 0, last_seen = clock - 20 * 86400, appearances = 0, hc = 0}
globals.ChaosNemesisHourly.onThink(3600000)
eq(#rows, 0, "hourly expiry"); eq(NE.serverActive, 0, "hourly count")

-- Hardcore: the trophy only
ChaosSeason = {modesOf = function(p) return {hc = p.guid == 5} end}
clock = clock + cfgLive.birth.cooldownSeconds
R.ChaosNemesisDeath.onDeath(varek, nil, ghoul, ghoul)
eq(NE.records[5].hc, true, "born on a Hardcore character")
clock = clock + cfgLive.appear.cooldownSeconds
nem = callIt(varek)
corpse.items = {}
eq(NE.onNemesisDeath(nem, corpse, varek, varek), "avenge")
eq(#trophies, 2, "the trophy"); eq(#corpse.items, 0, "no gold for Hardcore")
ChaosSeason = nil

-- the localization helper: Chaos.t (English text as the key) wins when it has a translation; without one a pt-BR
-- player reads this module's own pt-BR text
local lang = "pt-BR"
Chaos.lang = function() return lang end
Chaos.t = function(p, k, ...)
	if k == "You feel a familiar hatred watching you..." then return "PT: ódio" end
	return string.format(k, ...)
end
eq(NE.tr(varek, "warning"), "PT: ódio", "Chaos.t translation used")
eq(NE.tr(varek, "vanish", "X"), "X volta para as sombras. Ele vai voltar.", "no translation: the module's pt-BR")
lang = "en"
eq(NE.tr(varek, "vanish", "X"), "X fades back into the shadows. It will return.", "English player")
Chaos.t = nil
lang = "pt-BR"
eq(NE.tr(varek, "warning"), "Você sente um ódio familiar observando você...", "no Chaos.t: pt-BR by Chaos.lang")
Chaos.lang = nil
eq(NE.tr(varek, "warning"), "You feel a familiar hatred watching you...", "nothing known: English")

print(string.format("nemesis_test: %d checks, %d failures", checks, fails))
if fails > 0 then
	os.exit(1)
end
