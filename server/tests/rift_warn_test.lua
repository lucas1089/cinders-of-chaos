-- Run from the server/ folder: luajit tests/rift_warn_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- O476: the level warning of the rifts (rift_core.lua R.warnLevel / R.warnEntry / R.warnTip / R.describe, rift.lua
-- RF._warnEntry / RF._warnTip, rift_config.lua `warn`) and the mana shield rule of the run's hit scaling (a hit a mana
-- shield took is scaled once, not again on the part the health pays). rift.lua against a mocked engine.
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

-- ------------------------------------------------------------------ engine mocks
local events = {}
local function eventMock(kind)
	return function(name)
		local e = setmetatable({name = name, kind = kind}, {__index = function() return function() end end})
		e.register = function() events[name or (kind .. "#" .. tostring(e))] = e end
		return e
	end
end
CreatureEvent, GlobalEvent, TalkAction, Action, MoveEvent = eventMock("creature"), eventMock("global"), eventMock("talk"),
	eventMock("action"), eventMock("move")
EventCallback = setmetatable({}, {__index = function() return function() end end})
GAME_STATE_NORMAL = 1
db = {query = function() return true end, storeQuery = function() return false end, escapeString = function(s) return "'" .. s .. "'" end}
result = {free = function() end}
local function pos(x, y, z)
	return {x = x, y = y, z = z, sendMagicEffect = function() end}
end
Position = pos
local timers = {}
addEvent = function(f, ms, ...)
	timers[#timers + 1] = {f = f, args = {...}}
	return #timers
end
local function flush() -- the dispatcher: what addEvent queued runs after the engine call
	local list = timers
	timers = {}
	for _, t in ipairs(list) do
		t.f((table.unpack or unpack)(t.args))
	end
end
doTargetCombatHealth = function() end
Condition = function(kind)
	local c = {kind = kind}
	function c:setParameter() end
	function c:addDamage() end
	return c
end
local monsters, nextMid = {}, 5000
local function newMonster(name, p)
	nextMid = nextMid + 1
	local m = {id = nextMid, name = name, at = pos(p.x, p.y, p.z)}
	function m:getId() return self.id end
	function m:getName() return self.name end
	function m:isMonster() return true end
	function m:isPlayer() return false end
	function m:getPosition() return self.at end
	monsters[m.id] = m
	return m
end
Game = {
	getGameState = function() return 1 end,
	createItem = function() return nil end,
	getPlayers = function() return {} end,
	getSpectators = function() return {} end,
	getExperienceStage = function() return 1 end,
	createMonster = function(name, p) return newMonster(name, p) end,
}
ItemType = function(id) return {getId = function() return id end, getName = function() return "item" .. id end} end
local players = {}
Player = function(id)
	if type(id) == "table" then return id end
	return players[id]
end
Monster = function(id) return monsters[id] end
json = {encode = function() return "{}" end, decode = function() return {} end}
Tile = function() return nil end

dofile("data/scripts/chaos/rift.lua")
local RF, R = ChaosRift, ChaosRiftCore
local cfg = ChaosRiftConfig
local I = ChaosI18n

local nextPid = 0
local function newPlayer(name, level, lang, mana)
	nextPid = nextPid + 1
	local p = {id = 100 + nextPid, guid = nextPid, name = name, level = level, mana = mana or 0, msgs = {}}
	p.getId = function() return p.id end
	p.getGuid = function() return p.guid end
	p.getName = function() return p.name end
	p.getLevel = function() return p.level end
	p.getMana = function() return p.mana end
	p.getPosition = function() return pos(0, 0, 7) end
	p.sendTextMessage = function(_, kind, t) p.msgs[#p.msgs + 1] = {kind = kind, text = t} end
	p.isPlayer = function() return true end
	players[p.id] = p
	I.players[p.id] = lang or "en"
	return p
end

local function texts(p)
	local out = {}
	for _, m in ipairs(p.msgs) do
		out[#out + 1] = m.text
	end
	return out
end

-- ------------------------------------------------------------------ the config and the rule's shape
do
	local w = cfg.warn
	ok(w and w.enabled, "the warning is on")
	eq(#w.levels, cfg.maxTier, "a level for every tier")
	for t = 1, cfg.maxTier do
		local info = R.tierInfo(cfg, t)
		ok(w.levels[t] >= info.minLevel, "tier " .. t .. ": recommended " .. w.levels[t] .. " is not under the entry level " .. info.minLevel)
		ok(t == 1 or w.levels[t] >= w.levels[t - 1], "tier " .. t .. ": never below the tier under it")
		eq(R.warnLevel(cfg, t), w.levels[t], "R.warnLevel of tier " .. t)
	end
	ok(w.partySize >= 2 and w.partySize <= cfg.maxPlayers, "a party size a party can reach: " .. tostring(w.partySize))
	eq(R.warnLevel(cfg, 99), w.levels[#w.levels], "a tier past the table takes the last level")
	local off = setmetatable({warn = {enabled = false, levels = w.levels}}, {__index = cfg})
	eq(R.warnLevel(off, 3), nil, "switched off: no level")
	eq(R.warnLevel({}, 3), nil, "no block: no level")
	local brut
	for _, d in ipairs(cfg.mods) do
		if d.key == "brutality" then brut = d end
	end
	ok(R.warnHot(cfg, {{key = "brutality", value = brut.range[1]}}), "Brutality raises the damage")
	ok(R.warnHot(cfg, {{key = "dread", value = 50}}), "Dread Guardian raises the damage")
	ok(not R.warnHot(cfg, {{key = "vitality", value = 30}, {key = "haste", value = 40}}), "health and speed do not")
	ok(not R.warnHot(cfg, {}), "no modifiers")
end

-- ------------------------------------------------------------------ the key's line
do
	local rec = cfg.warn.levels[3]
	local d = R.describe(cfg, {tier = 3, mods = {}})
	ok(d:find(string.format("Recommended: level %d alone, or a party.", rec), 1, true), "the key says the level: " .. d)
	ok(d:find("Opens a rift of tier 3 (level 200+). Recommended", 1, true), "right after the tier line")
	local off = setmetatable({warn = {enabled = false}}, {__index = cfg})
	ok(not R.describe(off, {tier = 3, mods = {}}):find("Recommended", 1, true), "no line when the warning is off")
	-- the pt-BR text of the sentence exists (the look text goes sentence by sentence through the table)
	dofile("data/scripts/chaos/itemdesc_i18n_core.lua")
	local tr = function(text) return I.text("pt-BR", text) end
	local pt = ChaosItemDescI18n.translate(d, tr)
	ok(pt:find(string.format("Recomendado: nível %d sozinho, ou em grupo.", rec), 1, true), "the key line in pt-BR: " .. pt)
	ok(not pt:find("Recommended", 1, true), "no English left on the key line")
end

-- ------------------------------------------------------------------ who is warned at the start
do
	local key3 = {tier = 3, mods = {}}
	local rec = cfg.warn.levels[3]
	local ps = cfg.warn.partySize
	eq(R.warnEntry(cfg, key3, rec - 1, 1), rec, "solo below: warned")
	eq(R.warnEntry(cfg, key3, rec, 1), nil, "solo at the level: nothing")
	eq(R.warnEntry(cfg, key3, rec + 100, 1), nil, "solo above: nothing")
	eq(R.warnEntry(cfg, key3, 200, ps - 1), rec, "a party below the size: warned")
	eq(R.warnEntry(cfg, key3, 200, ps), nil, "a party at the size: nothing")
	eq(R.warnEntry(cfg, key3, 200, cfg.maxPlayers), nil, "a full party: nothing")
	eq(R.warnEntry(cfg, {tier = 3, mods = {}, omen = "x"}, 1, 1), nil, "an Omen key has no warning")
	eq(R.warnEntry(cfg, nil, 1, 1), nil, "no key")
	local _, hot = R.warnEntry(cfg, {tier = 3, mods = {{key = "brutality", value = 20}}}, 200, 1)
	eq(hot, true, "a key with Brutality: the damage sentence")
	_, hot = R.warnEntry(cfg, key3, 200, 1)
	eq(hot, false, "a plain key: none")

	-- the lines a player gets, in both languages
	local solo = newPlayer("Solo", rec - 10, "en")
	local soloPt = newPlayer("SoloPt", rec - 10, "pt-BR")
	local strong = newPlayer("Strong", rec + 10, "en")
	local run = {key = key3}
	RF._warnEntry(run, {solo})
	eq(#solo.msgs, 1, "one warning line")
	eq(solo.msgs[1].kind, MESSAGE_EVENT_ADVANCE, "in the type of the run's other lines")
	eq(solo.msgs[1].text, string.format("Warning: this rift is above your level (recommended %d alone). Its guardian hits very hard: two hits can kill. Bring a party or use a lower tier key.", rec), "the warning text")
	RF._warnEntry(run, {soloPt})
	eq(soloPt.msgs[1].text, string.format("Aviso: este rift está acima do seu nível (recomendado: %d sozinho). O guardião bate muito forte: dois golpes podem matar. Leve um grupo ou use uma chave de tier menor.", rec), "the warning in pt-BR")
	RF._warnEntry(run, {strong})
	eq(#strong.msgs, 0, "above the level: nothing")
	-- a party of two with one below: the size rule counts the players who entered
	local a, b = newPlayer("A", rec - 10, "en"), newPlayer("B", rec + 10, "en")
	RF._warnEntry(run, {a, b})
	eq(#a.msgs + #b.msgs, ps <= 2 and 0 or 1, "a party of two against warn.partySize " .. ps)
	-- the modifiers that raise the damage: the same line with one more sentence, not a second line
	local hotRun = {key = {tier = 3, mods = {{key = "brutality", value = 20}}}}
	local h = newPlayer("Hot", rec - 10, "en")
	RF._warnEntry(hotRun, {h})
	eq(#h.msgs, 1, "one line, not two, with a hot modifier")
	ok(h.msgs[1].text:find("Its modifiers make monsters hit harder.", 1, true), "the damage sentence is in it: " .. h.msgs[1].text)
	local hp = newPlayer("HotPt", rec - 10, "pt-BR")
	RF._warnEntry(hotRun, {hp})
	ok(hp.msgs[1].text:find("Os modificadores fazem os monstros baterem mais forte.", 1, true), "and in pt-BR: " .. hp.msgs[1].text)
	-- an Omen run: nothing
	local o = newPlayer("Omen", 1, "en")
	RF._warnEntry({key = {tier = 15, mods = {}, omen = "bloodmoon"}}, {o})
	eq(#o.msgs, 0, "an Omen arena has no warning")
end

-- ------------------------------------------------------------------ the tip after a death to a guardian
do
	local rec = cfg.warn.levels[3]
	local g = newMonster("Guardian", pos(0, 0, 7))
	local pack = newMonster("Pack", pos(0, 0, 7))
	local run = {key = {tier = 3, mods = {}}, players = {}, bossIds = {[g.id] = true}}
	local p = newPlayer("Fallen", rec - 20, "en")
	run.players[p.id] = {id = p.id, level = rec - 20}
	RF._warnTip(run, p, pack, nil)
	eq(#p.msgs, 0, "killed by a pack monster: no tip")
	RF._warnTip(run, p, nil, nil)
	eq(#p.msgs, 0, "no killer known: no tip")
	RF._warnTip(run, p, g, nil)
	eq(#p.msgs, 1, "killed by the guardian below the level: one tip")
	eq(p.msgs[1].text, string.format("Tip: a guardian hits very hard below the recommended level (%d alone): two hits can kill. Bring a party or use a lower tier key next time.", rec), "the tip text")
	RF._warnTip(run, p, g, nil)
	eq(#p.msgs, 1, "once a run and player")
	-- the most damage killer counts too; another player gets its own tip
	local q = newPlayer("Fallen2", rec - 20, "pt-BR")
	run.players[q.id] = {id = q.id, level = rec - 20}
	RF._warnTip(run, q, pack, g)
	eq(#q.msgs, 1, "the guardian did the most damage: a tip")
	eq(q.msgs[1].text, string.format("Dica: um guardião bate muito forte abaixo do nível recomendado (%d sozinho): dois golpes podem matar. Da próxima vez, leve um grupo ou use uma chave de tier menor.", rec), "the tip in pt-BR")
	-- at or above the level: nothing (the level of the entry counts, not the one after the death's loss)
	local r = newPlayer("Strong", rec - 50, "en")
	run.players[r.id] = {id = r.id, level = rec}
	RF._warnTip(run, r, g, nil)
	eq(#r.msgs, 0, "at the level: no tip")
	-- an Omen run: nothing
	local o = newPlayer("OmenFallen", 1, "en")
	local orun = {key = {tier = 15, mods = {}, omen = "x"}, players = {}, bossIds = {[g.id] = true}}
	orun.players[o.id] = {id = o.id, level = 1}
	RF._warnTip(orun, o, g, nil)
	eq(#o.msgs, 0, "an Omen arena has no tip")
end

-- ------------------------------------------------------------------ a hit a mana shield took is scaled once
do
	local tier = 3
	local fx = R.applyParty(cfg, R.effects(cfg, {}, tier), 1, tier)
	local run = {fx = fx, players = {}, bossIds = {}, key = {tier = tier, mods = {}}}
	local g = newMonster("Guardian", pos(0, 0, 7))
	local pk = newMonster("Pack", pos(0, 0, 7))
	run.bossIds[g.id] = true
	RF.monsterRun[g.id], RF.monsterRun[pk.id] = run, run
	local mult = fx.damage * (fx.boss or 1) * fx.guardian
	ok(mult > 3, "the tier 3 guardian multiplier is the curve's: " .. mult)
	local mage = newPlayer("Mage", 264, "en", 2910)
	run.players[mage.id] = {id = mage.id}
	local onMana = events.ChaosRiftPlayerMana.onManaChange
	local onHealth = events.ChaosRiftPlayerHit.onHealthChange
	-- the engine's order (Game::combatChangeHealth): the mana events on the whole hit, the mana pays, the health events on
	-- the rest. Returns what the player lost in all.
	local function engine(attacker, raw)
		local p1 = onMana(mage, attacker, raw, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, 1)
		local total = math.abs(p1)
		local manaPaid = math.min(mage.mana, total)
		mage.mana = mage.mana - manaPaid
		local rest = total - manaPaid
		local healthPaid = 0
		if rest > 0 then
			local p2 = onHealth(mage, attacker, rest, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, 1)
			healthPaid = math.abs(p2)
		end
		flush()
		return manaPaid, healthPaid, total
	end
	local raw = 1000
	local scaled = math.floor(raw * mult)
	local manaPaid, healthPaid = engine(g, raw)
	eq(manaPaid, 2910 > scaled and scaled or 2910, "the mana pays")
	eq(manaPaid + healthPaid, scaled, "the guardian's hit is its multiplier once in all: " .. manaPaid .. " + " .. healthPaid .. " = " .. (manaPaid + healthPaid))
	-- a hit the mana cannot take whole: the part the health pays is not scaled again
	mage.mana = 1000
	manaPaid, healthPaid = engine(g, raw)
	eq(manaPaid, 1000, "the mana runs out")
	eq(healthPaid, scaled - 1000, "the rest is not scaled again: " .. healthPaid)
	-- a hit the mana takes whole: no health event, nothing marked that can leak into the next hit
	mage.mana = 100000
	manaPaid, healthPaid = engine(g, raw)
	eq(manaPaid + healthPaid, scaled, "the mana takes it all")
	ok(next(RF._manaScaled) == nil, "the mark is gone when the engine call ends")
	mage.mana = 0
	local p = onHealth(mage, g, -raw, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, 1)
	eq(p, math.floor(-raw * mult), "with the mana gone the next hit is scaled by the health event once")
	-- the same for a pack monster and with no mana shield at all (health events only)
	mage.mana = 500
	manaPaid, healthPaid = engine(pk, raw)
	local packMult = fx.damage * (fx.packDamage or 1)
	eq(manaPaid + healthPaid, math.floor(raw * packMult), "a pack monster's hit: once")
	local plain = onHealth(mage, pk, -raw, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, 1)
	eq(plain, math.floor(-raw * packMult), "no mana shield: scaled once by the health event")
	-- another attacker after a marked hit is never skipped
	mage.mana = 500
	engine(g, raw)
	mage.mana = 0
	local other = onHealth(mage, pk, -raw, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, 1)
	eq(other, math.floor(-raw * packMult), "a different attacker is scaled")
end

print(string.format("rift_warn_test: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end
