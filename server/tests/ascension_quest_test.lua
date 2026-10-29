-- Run from the server/ folder: luajit tests/ascension_quest_test.lua (CI runs it with luajit and lua5.3)
-- Covers the pure rules of the ascension quest (ascension_quest_core.lua): stages, eligibility, the choices read from
-- Chaos.classes.ascension at run time (a new line works without code changes), choice validation, the Proof's points
-- and monster levels, the Trial's entry rule, scaling, mechanics, geometry and the lethal-hit catch, !ascend's gate,
-- /ascendset's parsing, the title and the modal windows. The Trial's percent hits (ascension_quest.lua against a
-- mocked engine) take Chaos.percentBase.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})

local function eq(a, b, m) if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end end

dofile("data/scripts/chaos/ascension_quest_core.lua")
local Q = ChaosAscensionQuestCore
local cfg = Q.cfg()
local S = Q.STAGE

-- ------------------------------------------------------------------ config
eq(type(cfg), "table", "config loaded into Chaos.ascensionQuest")
eq(cfg.npc.name, "Ascendant Oracle")
eq(cfg.storage.stage, 7101000); eq(cfg.storage.proof, 7101001); eq(cfg.storage.cooldown, 7101002)
local seen = {}
for _, k in pairs(cfg.storage) do
	assert(not seen[k], "storage keys are distinct"); seen[k] = true
	assert(k >= 7101000 and k < 7101020, "storage in the quest's range")
end
for base, g in pairs(cfg.guardians) do
	assert(g.name and g.look and g.look.lookType and g.add and g.add.name, "guardian " .. tostring(base))
	for _, m in ipairs(g.mechanics) do
		assert(m == "stillness" or m == "adds" or m == "zones" or m == "enrage", "known mechanic " .. m)
	end
end
-- every ascended word of every line has an Oracle text
for _, map in pairs(Chaos.classes.ascension.choices) do
	for word in pairs(map) do
		assert(cfg.paths[word], "path text for " .. word)
	end
end

-- ------------------------------------------------------------------ stages
eq(Q.stage(-1), 0, "never set"); eq(Q.stage(nil), 0); eq(Q.stage(2), 2); eq(Q.stage(9), 4, "clamped"); eq(Q.stage("3"), 3)

-- ------------------------------------------------------------------ choices and eligibility
local w = Q.choicesOf(4)
eq(#w, 2); eq(w[1].word, "berserker"); eq(w[1].id, 14); eq(w[2].word, "juggernaut"); eq(w[2].id, 8)
eq(Q.choicesOf(11)[1].word, "ninja"); eq(Q.choicesOf(11)[2].id, 13)
eq(Q.choicesOf(8), nil, "an ascended class has no choices")
for _, base in ipairs({1, 3, 4, 11, 17, 20, 23}) do
	assert(Q.choicesOf(base) and #Q.choicesOf(base) == 2, "base " .. base .. " has two ascensions")
end
local ok, code = Q.eligibility(4, 100); eq(ok, true, "warrior 100"); eq(code, "ok")
ok, code = Q.eligibility(4, 99); eq(ok, false); eq(code, "level")
ok, code = Q.eligibility(14, 300); eq(ok, false); eq(code, "ascended", "berserker")
ok, code = Q.eligibility(0, 300); eq(code, "noline", "no vocation")
ok, code = Q.eligibility(2, 300); eq(code, "noline", "retired id")
eq(Q.eligibility(11, 150), true, "thief")
eq(Q.isAscendedId(12), true); eq(Q.isAscendedId(11), false); eq(Q.isAscendedId(0), false)

-- the minimum level follows Chaos.classes.ascension at run time
Chaos.classes.ascension.minLevel = 120
eq(Q.eligibility(4, 110), false, "minLevel read at run time"); eq(Q.eligibility(4, 120), true)
Chaos.classes.ascension.minLevel = 100

-- a new line without code changes
Chaos.classes.baseOf[30], Chaos.classes.baseOf[31], Chaos.classes.baseOf[32] = 30, 30, 30
Chaos.classes.ascension.choices[30] = {stormcaller = 31, tidebinder = 32}
eq(Q.eligibility(30, 100), true, "new line eligible")
eq(Q.validateChoice(30, "tidebinder", S.CHOICE), 32, "new line choice")
eq(Q.guardianFor(30), cfg.guardians.default, "new line gets the default guardian")
assert(Q.pathText("stormcaller", 31, function() return "Stormcaller" end):find("Stormcaller"), "path text falls back to the name")
Chaos.classes.baseOf[30], Chaos.classes.baseOf[31], Chaos.classes.baseOf[32] = nil, nil, nil
Chaos.classes.ascension.choices[30] = nil

-- ------------------------------------------------------------------ the Choice
eq(Q.validateChoice(4, "berserker", S.CHOICE), 14, "warrior -> berserker")
eq(Q.validateChoice(4, " Juggernaut ", S.CHOICE), 8, "trimmed, any case")
eq(Q.validateChoice(11, "ninja", S.CHOICE), 12, "thief -> ninja")
eq(Q.validateChoice(4, "berserker", S.DONE), 14, "a base class after the store's change may choose again")
local id, why, c = Q.validateChoice(4, "berserker", S.TRIAL); eq(id, nil); eq(c, "stage", "before the Trial")
id, why, c = Q.validateChoice(4, "ninja", S.CHOICE); eq(id, nil, "another line's class"); eq(c, "word")
assert(why:find("berserker") and why:find("juggernaut"), "lists the choices: " .. why)
id, why, c = Q.validateChoice(14, "juggernaut", S.CHOICE); eq(id, nil, "already ascended"); eq(c, "ascended")
eq(Q.choiceInText(4, "I choose the BERSERKER path"), "berserker")
eq(select(2, Q.choiceInText(11, "samurai please")), 13)
eq(Q.choiceInText(4, "ninja"), nil, "not of this line")
eq(Q.choiceInText(14, "juggernaut"), "juggernaut", "an ascended character's line")

-- ------------------------------------------------------------------ texts
local function nameOf(vid) return ({[8] = "Juggernaut", [14] = "Berserker", [4] = "Warrior"})[vid] or tostring(vid) end
local calling = Q.callingText("Warrior", 4, nameOf)
assert(calling:find("Warrior") and calling:find("{berserker}") and calling:find("{juggernaut}"), calling)
assert(Q.proofText(3):find("3 of 10"), Q.proofText(3))

-- ------------------------------------------------------------------ Proof of Strength
eq(Q.estimateLevel(700, 1000), 42, "dragon"); eq(Q.estimateLevel(2100, 1450), 73, "hydra"); eq(Q.estimateLevel(6000, 7000), 124, "demon"); eq(Q.estimateLevel(6000, 8200), 137, "raised by health")
eq(Q.estimateLevel(0, 0), 2, "nothing"); eq(Q.estimateLevel(10, 6000), 8, "health raises at most x1.5")
eq(Q.minHuntingLevel(100), 60); eq(Q.minHuntingLevel(50), 40, "floor"); eq(Q.minHuntingLevel(500), 300)
-- hunting levels (O284): the owner's level 202 Monk was asked for 242, the pool level (half) against 0.6 x its level
eq(Q.minHuntingLevel(202), 121, "level 202: hunting 121")
eq(Q.proofPoints("rare", 121, 202), 1, "hunting 121 counts at 202"); eq(Q.proofPoints("rare", 120, 202), 0)
eq(Q.proofPoints("rare", 73, 100), 1, "rare hydra"); eq(Q.proofPoints("legendary", 60, 100), 3, "legendary at the bar")
eq(Q.proofPoints("rare", 59, 100), 0, "too weak"); eq(select(2, Q.proofPoints("rare", 59, 100)), "level")
-- the hunting level of a kill: its own level (pace.lua) wins over the pool level x the multiplier
local savedLoot = ChaosLoot
ChaosLoot = {huntLevel = function(m, fallback) return m.own or fallback end}
eq(Chaos.monsterHuntingLevel({own = 700}, 300), 700, "own level"); eq(Chaos.monsterHuntingLevel({}, 300), 300, "fallback")
ChaosLoot = savedLoot
eq(Chaos.entryHuntingLevel({level = 60}), 60 * Chaos.huntingMult(), "pool entry x mult")
eq(Chaos.entryHuntingLevel({level = 600, minLevel = 590}), 600, "level range: as is")
eq(Q.proofPoints("magic", 200, 100), 0, "magic does not count"); eq(Q.proofPoints("normal", 200, 100), 0)
eq(Q.proofPoints("boss", 200, 100), 0, "bosses do not count")
local pts, done = Q.addProof(-1, 1); eq(pts, 1); eq(done, false)
pts, done = Q.addProof(8, 3); eq(pts, 10, "capped"); eq(done, true)
pts, done = Q.addProof(9, 1); eq(done, true)

-- ------------------------------------------------------------------ the Trial
ok, why = Q.canEnterTrial(S.TRIAL, 1000, -1, false); eq(ok, true, "open")
ok, why = Q.canEnterTrial(S.PROOF, 1000, -1, false); eq(ok, false); assert(why:find("proven"))
ok, why = Q.canEnterTrial(S.CHOICE, 1000, -1, false); eq(ok, false); assert(why:find("already"))
ok, why = Q.canEnterTrial(S.TRIAL, 1000, 1300, false); eq(ok, false, "cooldown"); assert(why:find("5 minutes"), why)
ok, why = Q.canEnterTrial(S.TRIAL, 1000, 1030, false); assert(why:find("30 seconds"), why)
ok, why = Q.canEnterTrial(S.TRIAL, 1000, 1061, false); assert(why:find("2 minutes"), why)
eq(Q.canEnterTrial(S.TRIAL, 1000, 1000, false), true, "cooldown over")
eq(Q.canEnterTrial(S.TRIAL, 1000, -1, true), false, "busy")
eq(Q.formatWait(45), "45 seconds"); eq(Q.formatWait(1), "1 second"); eq(Q.formatWait(600), "10 minutes")

local s100 = Q.trialScale(100)
eq(s100.level, 100); eq(s100.health, 6000); eq(s100.factor, 1); eq(s100.addHealth, 600)
local s130 = Q.trialScale(130)
eq(s130.health, 7800); eq(s130.addHealth, 780); assert(math.abs(s130.damage - 1.3) < 1e-9)
eq(Q.trialScale(500).health, 7800, "clamped above"); eq(Q.trialScale(90).health, 6000, "clamped below")
eq(Q.trialScale(115).health, 6900)

local gw = Q.guardianFor(4)
eq(gw.name, "Warden of Iron"); eq(Q.hasMechanic(gw, "stillness"), true); eq(Q.hasMechanic(gw, "adds"), false)
eq(Q.guardianFor(11).name, "Warden of Shadows"); eq(Q.guardianFor(99), cfg.guardians.default)
assert(math.abs(Q.guardianMultiplier(gw, s100, 5000, 6000) - 1.0) < 1e-9, "no enrage above 30%")
assert(math.abs(Q.guardianMultiplier(gw, s100, 1000, 6000) - 1.5) < 1e-9, "enraged")
assert(math.abs(Q.guardianMultiplier(Q.guardianFor(3), s100, 1000, 6000) - 1.0) < 1e-9, "the Ranger's has no enrage")

-- stillness: move resets, warn once at 2 s, slam at 3 s, then the timer starts again
local st = {}
eq(Q.stillness(st, "1:1", 0), "move"); eq(Q.stillness(st, "1:1", 1000), "wait"); eq(Q.stillness(st, "1:1", 2000), "warn")
eq(Q.stillness(st, "1:1", 2500), "wait", "warned once"); eq(Q.stillness(st, "1:1", 3000), "slam")
eq(Q.stillness(st, "1:1", 4000), "wait", "timer restarted"); eq(Q.stillness(st, "2:1", 4500), "move")
eq(Q.stillness(st, "2:1", 7400), "warn"); eq(Q.stillness(st, "2:1", 7500), "slam")

-- zones: the centre first, distinct tiles, within the radius
local seq = 0
local list = Q.zoneTiles({x = 10, y = 10, z = 7}, 5, 2, function(k) seq = seq + 1; return (seq * 7) % k + 1 end)
eq(#list, 5); eq(list[1].x, 10); eq(list[1].y, 10)
local keys = {}
for _, t in ipairs(list) do
	assert(math.abs(t.x - 10) <= 2 and math.abs(t.y - 10) <= 2 and t.z == 7, "in radius")
	assert(not keys[t.x .. ":" .. t.y], "distinct"); keys[t.x .. ":" .. t.y] = true
end
eq(#Q.zoneTiles({x = 1, y = 1, z = 7}, 50, 1, function(k) return 1 end), 9, "no more tiles than the area")

-- lethal hits are caught
local p, s2, caught = Q.catchDamage(500, 200, 100); eq(p, 200); eq(s2, 100); eq(caught, false)
p, s2, caught = Q.catchDamage(500, 450, 100); eq(p, 450); eq(s2, 49); eq(caught, true)
p, s2, caught = Q.catchDamage(1, 10, 0); eq(p, 0); eq(caught, true)

-- geometry
local L1 = Q.layout(1)
eq(L1.x1, 7001); eq(L1.y1, 7001); eq(L1.x2, 7013); eq(L1.y2, 7013); eq(#L1.floor, 13 * 13); eq(#L1.walls, 15 * 15 - 13 * 13)
eq(L1.center.x, 7007); eq(L1.center.y, 7007); eq(Q.inRoom(L1, L1.playerStart), true); eq(Q.inRoom(L1, L1.guardianStart), true)
eq(Q.inRoom(L1, {x = 7000, y = 7005, z = 7}), false, "the wall")
local L6 = Q.layout(6)
eq(L6.x1, 7000 + 24 + 1); eq(L6.y1, 7000 + 24 + 1, "second row")
eq(Q.slotAt({x = 7005, y = 7005, z = 7}), 1); eq(Q.slotAt({x = 7000, y = 7000, z = 7}), 1, "wall corner")
eq(Q.slotAt({x = 7030, y = 7030, z = 7}), 6); eq(Q.slotAt({x = 7020, y = 7005, z = 7}), nil, "between slots")
eq(Q.slotAt({x = 7005, y = 7005, z = 8}), nil, "other floor"); eq(Q.slotAt({x = 6999, y = 7005, z = 7}), nil)
eq(Q.slotAt({x = 7005, y = 7005 + 48, z = 7}), nil, "past the last slot")
-- the slots do not touch the other runtime-built areas (tutorial 4600, world boss 5000, siege 5100, arena 6000, rifts 8192)
local g = cfg.trial.grid
local last = Q.layout(g.slots)
assert(g.origin.x >= 7000 and last.x2 < 8192 and last.y2 < 8192, "inside 7000..8191")

-- ------------------------------------------------------------------ !ascend and /ascendset
eq(Q.commandGate("oracle", false, false), false, "players go to the Oracle")
assert(select(2, Q.commandGate("oracle", false, false)):find("Ascendant Oracle"))
eq(Q.commandGate("oracle", true, false), true, "staff keeps it")
eq(Q.commandGate("oracle", false, true), true, "the migration's free switch keeps working")
eq(Q.commandGate("open", false, false), true, "open mode")
local name, vid, err, base = Q.parseAscendSet("Np Warrior, Berserker")
eq(name, "Np Warrior"); eq(vid, 14); eq(err, nil); eq(base, 4)
name, vid = Q.parseAscendSet("  Some Thief ,ninja ")
eq(name, "Some Thief"); eq(vid, 12)
name, vid, err = Q.parseAscendSet("Bob, warrior"); eq(vid, nil, "a base class is no ascension"); assert(err:find("Unknown"))
name, vid, err = Q.parseAscendSet("berserker"); eq(name, nil); assert(err:find("Usage"))

-- ------------------------------------------------------------------ title
local t = Q.titleFor(14, "Berserker", 12345)
eq(t.text, "Ascended Berserker"); eq(t.key, "ascension:berserker"); eq(t.at, 12345); eq(t.color, "#c9a24a")
eq(Q.titleFor(4, "Warrior", 1), nil, "base classes have no title")
eq(Q.titleFor(14, "Berserker", -1).at, nil, "no time stored")
assert(#Q.titleFor(5, "Elementalist", 1).text <= 24, "fits the plate")

-- ------------------------------------------------------------------ modal windows (mock ModalWindow)
local sent = {}
ModalWindow = function(mid, title, text)
	local w = {id = mid, title = title, text = text, buttons = {}, choices = {}}
	function w:addButton(b, label) self.buttons[#self.buttons + 1] = {b, label} end
	function w:addChoice(cid, label) self.choices[#self.choices + 1] = {cid, label} end
	function w:setDefaultEnterButton(b) self.enter = b end
	function w:setDefaultEscapeButton(b) self.escape = b end
	function w:sendToPlayer(pl) sent[#sent + 1] = self end
	return w
end
Q.sendTrialModal({}, 4)
eq(sent[1].id, cfg.modal.trial); assert(sent[1].text:find("Warden of Iron") and sent[1].text:find("180 seconds"), sent[1].text)
eq(sent[1].buttons[1][2], "Enter"); eq(sent[1].enter, 1); eq(sent[1].escape, 2)
Q.sendChoiceModal({}, 4, nameOf)
eq(sent[2].id, cfg.modal.choice); eq(#sent[2].choices, 2); eq(sent[2].choices[1][2], "Berserker"); eq(sent[2].choices[2][2], "Juggernaut")
Q.sendConfirmModal({}, 14, "berserker", "Berserker")
eq(sent[3].id, cfg.modal.confirmBase + 14); assert(sent[3].text:find("final"), sent[3].text)
assert(cfg.modal.confirmBase > cfg.modal.choice and cfg.modal.confirmBase > cfg.modal.trial, "ids do not overlap")

-- ------------------------------------------------------------------ the Trial's percent hits (ascension_quest.lua)
-- the chamber's telegraphs take Chaos.percentBase: a Hollow Vessel counts health + maximum energy shield
do
	local registered = {}
	local function eventMock(name)
		local e = setmetatable({name = name}, {__index = function() return function() end end})
		e.register = function() registered[name] = e end
		return e
	end
	CreatureEvent, GlobalEvent, TalkAction = eventMock, eventMock, eventMock
	EventCallback = setmetatable({}, {__index = function() return function() end end})
	Game = Game or {}
	addEvent = function() return 0 end
	dofile("data/lib/chaos_spell_events.lua")
	dofile("data/scripts/chaos/chaos_constants.lua")
	dofile("data/scripts/chaos/ascension_quest.lua")
	local AQ = ChaosAscensionQuest
	ChaosArchetypes = {percentBase = function(pl) return pl:getMaxHealth() + (pl.shield or 0) end}
	Monster = function() return nil end
	local hits = {}
	doTargetCombat = function(_, target, _, mn) hits[#hits + 1] = {id = target:getId(), mn = mn} end
	local vessel = {getId = function() return 1 end, getMaxHealth = function() return 100 end, shield = 2000}
	local other = {getId = function() return 2 end, getMaxHealth = function() return 5000 end}
	local tr = {raw = false}
	AQ.hurt(tr, vessel, 0.2)
	AQ.hurt(tr, other, 0.2)
	eq(hits[1] and hits[1].mn, -420, "ascension trial: 20% of 100 health + 2000 shield")
	eq(hits[2] and hits[2].mn, -1000, "ascension trial: 20% of 5000 health")
	eq(tr.raw, false, "raw flag cleared after the hit")
	ChaosArchetypes = nil
	hits = {}
	AQ.hurt(tr, vessel, 0.2)
	eq(hits[1] and hits[1].mn, -20, "without the archetypes module: the health alone")

	-- Proof of Strength kill counting, with cursed chest monsters (owner 2026-10-29: "os monstros que spawnam do cursed
	-- chest nao estao contando pro ascension"). The chest scales its monsters to 0.9 x the opener's level, but their
	-- own hunting level stays the type's (a level 30 Rotworm in a chest for a level 200 player).
	local stores = {}
	local function mkPlayer(level)
		local p = {_level = level}
		function p:isPlayer() return true end
		function p:getLevel() return self._level end
		function p:getStorageValue(k) return stores[k] or -1 end
		function p:setStorageValue(k, v) stores[k] = v end
		function p:sendTextMessage() end
		function p:sendExtendedOpcode() end
		return p
	end
	local function mkMonster(id, name, native)
		local m = {_id = id, _native = native}
		function m:isPlayer() return false end
		function m:isMonster() return true end
		function m:getId() return self._id end
		function m:getName() return name end
		function m:getMaster() return self._master end
		function m:getType() return {name = function() return name end, experience = function() return 10 end,
			maxHealth = function() return 100 end} end
		return m
	end
	local cfgQ = ChaosAscensionQuestCore.cfg()
	local sk = cfgQ.storage
	local tierOf = {}
	ChaosTierOf = function(m) return tierOf[m:getId()] or "normal" end
	-- the monster's own hunting level (pace.lua): native for every monster here
	ChaosLoot = {huntLevel = function(m, fallback) return m._native or fallback end}
	local kill = registered.ChaosAscensionKill
	assert(kill and kill.onKill, "kill event registered")
	local player = mkPlayer(200) -- needs hunting level 120
	stores[sk.stage] = ChaosAscensionQuestCore.STAGE.PROOF
	stores[sk.proof] = 0
	local function kills(m) kill.onKill(player, m) return stores[sk.proof] end

	tierOf[1] = "rare"
	eq(kills(mkMonster(1, "Rotworm", 30)), 0, "a rare level 30 map monster is under the bar")
	tierOf[2] = "rare"
	eq(kills(mkMonster(2, "Demon", 700)), 1, "a rare level 700 counts")

	-- cursed chest monster: native level 30, scaled to 180 by the chest
	ChaosCursedChest = {levelOf = function(m) return m._chestLevel end}
	tierOf[3] = "rare"
	local husk = mkMonster(3, "Rotworm", 30)
	husk._chestLevel = 180
	eq(kills(husk), 2, "a rare cursed chest monster scaled to 180 counts 1")
	tierOf[4] = "legendary"
	local legend = mkMonster(4, "Rotworm", 30)
	legend._chestLevel = 180
	eq(kills(legend), 5, "a legendary cursed chest monster counts 3")
	tierOf[5] = "magic"
	local magic = mkMonster(5, "Rotworm", 30)
	magic._chestLevel = 180
	eq(kills(magic), 5, "a magic one does not count")
	local normal = mkMonster(6, "Rotworm", 30)
	normal._chestLevel = 180
	eq(kills(normal), 5, "a normal one does not count")
	tierOf[7] = "rare"
	local low = mkMonster(7, "Rotworm", 30)
	low._chestLevel = 100 -- scaled to a level under the bar (a lower level opener's chest)
	eq(kills(low), 5, "a chest monster scaled under the bar does not count")
	tierOf[8] = "rare"
	local minion = mkMonster(8, "Rotworm", 30)
	minion._chestLevel = 180
	minion._master = {}
	eq(kills(minion), 5, "a summon of a chest monster does not count")
	ChaosCursedChest = nil
	tierOf[9] = "rare"
	eq(kills(mkMonster(9, "Rotworm", 30)), 5, "without the cursed chest module: the own level")

	-- The guardian shows the level the Trial scaled it to (beta 2026-10-29: "Warden of Dawn [2]" for a level 600
	-- player: the estimate of the type's experience and health). Chaos.createMonsterNamed passes the level to
	-- monster_levels.lua as Chaos.spawnLevel. Every class' guardian goes through the same call.
	do
		local shown = {}
		local origCreate = Chaos.createMonsterNamed
		Chaos.createMonsterNamed = function(typeName, pos, ext, force, name, level)
			shown[#shown + 1] = {type = typeName, level = level}
			local m = {_id = #shown + 100}
			function m:getId() return self._id end
			function m:getPosition() return {x = 1, y = 1, z = 7, sendMagicEffect = function() end} end
			function m:getOutfit() return {} end
			function m:setOutfit() end
			function m:rename() end
			function m:setMaxHealth() end
			function m:setHealth() end
			function m:getMaxHealth() return 1 end
			function m:getHealth() return 1 end
			function m:registerEvent() end
			return m
		end
		Position = Position or function(x, y, z) return {x = x, y = y, z = z, sendMagicEffect = function() end} end
		local pl = mkPlayer(600)
		function pl:getPosition() return {x = 0, y = 0, z = 0} end
		Player = function() return pl end
		local Q = ChaosAscensionQuestCore
		local L = {guardianStart = {x = 1, y = 1, z = 7}, center = {x = 1, y = 1, z = 7}}
		for _, base in ipairs({4, 3, 1, 11, 17, 20, 23, 0}) do
			shown = {}
			local g = Q.guardianFor(base)
			local scale = Q.trialScale(600)
			AQ.trials[77] = {pid = 77, L = L, guardian = g, scale = scale, adds = {}}
			AQ.spawnGuardian(77)
			eq(shown[1] and shown[1].type, cfgQ.trial.guardianMonster, g.name .. ": the guardian was spawned")
			eq(shown[1] and shown[1].level, scale.level, g.name .. ": shows the Trial's level")
			assert(shown[1].level >= cfgQ.trial.scaleMin, g.name .. ": at least the ascension level")
			AQ.trials[77] = nil
		end
		eq(Q.trialScale(600).level, cfgQ.trial.scaleMax, "a level 600 player meets the level cap guardian")
		eq(Q.trialScale(110).level, 110, "a level 110 player meets a level 110 guardian")
		Chaos.createMonsterNamed = origCreate
		Player = nil
	end
end

print("ascension_quest_test: OK")
