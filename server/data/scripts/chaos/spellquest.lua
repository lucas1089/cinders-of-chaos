-- spellquest.lua: the line spell quests (server/README.md "Line spell quests"). Three quests per class line: level 500 an
-- attack, 800 a buff or utility, 1200 an ultimate attack. Settings: spellquest_config.lua (Chaos.spellQuest); pure rules:
-- spellquest_core.lua; tracker: spellquest_tracker.lua; the NPC: Archivist Ysolde (data/npc/Archivist Ysolde.xml,
-- data/npc/scripts/archivist_ysolde.lua), placed at startup in her stall in the hub (npc_booths_config.lua).
--
--   step 1 the hunt    counted kills and fragments in storage (a death event on the monsters; party members who dealt damage
--                      count; hunt monsters of the quest's level only, bosses count 25 kills and drop a fragment for sure)
--   step 2 the trial   alone in a runtime-built room of the Trials engine (trials.lua, trials_config.lua spellTiers); this file
--                      sets ChaosTrials.spellHook, so a win completes the quest and a failed run closes the door 60 s
--   step 3 done        the spell is learned, the gold is paid once (the bank), the done flag is kept per line
--
-- The NPC script runs in its own Lua state: it starts the quest and opens the trial question; the answer (and everything
-- else) is handled and checked again here. Staff (the testers' commands): /spellquest set | show | reset.
-- Storage: Chaos.storage.spellQuest (+10 per quest). No opcode: the tracker rows use the goals channel (178).

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
if not ChaosNpcPlace then
	dofile("data/scripts/chaos/npc_place.lua")
end
if not ChaosSpellQuestCore or not ChaosSpellQuestCore.sendTrialModal then
	dofile("data/scripts/chaos/spellquest_core.lua")
end
if not ChaosTrialsCore then
	dofile("data/scripts/chaos/trials_core.lua")
end

local Q = ChaosSpellQuestCore
ChaosSpellQuest = ChaosSpellQuest or {}
local S = ChaosSpellQuest
ChaosTrials = ChaosTrials or {}

local function C()
	return Q.cfg()
end

local function log(text)
	print("[Chaos spell quest] " .. text)
end

local function getS(player, key)
	return player:getStorageValue(key)
end

local function toast(player, message)
	if ChaosOpcodes and ChaosOpcodes.notifications and json then
		player:sendExtendedOpcode(ChaosOpcodes.notifications, json.encode({action = "spellquest", message = message}))
	end
end

-- ======================================================================== state
-- {[n] = {step, kills, fragments, pity, mask, cooldown, attempts, doneAt}} raw storage values of every quest
function S.read(player)
	local q = {}
	for n = 1, Q.count() do
		local k = Q.keys(n)
		q[n] = {step = getS(player, k.step), kills = getS(player, k.kills), fragments = getS(player, k.fragments),
			pity = getS(player, k.pity), mask = getS(player, k.lines), cooldown = getS(player, k.cooldown),
			attempts = getS(player, k.attempts), doneAt = getS(player, k.doneAt)}
	end
	return q
end

-- n, effective step, code (spellquest_core.lua M.current) for a character
function S.current(player)
	return Q.current(player:getVocation():getId(), player:getLevel(), S.read(player))
end

-- the Archivist within `range` tiles (the trial question only counts at her)
function S.archivistNear(player)
	local pos = player:getPosition()
	local r = C().npc.range or 6
	local name = C().npc.name:lower()
	for _, c in ipairs(Game.getSpectators(pos, false, false, r, r, r, r) or {}) do
		if c:isNpc() and c:getName():lower() == name then
			return c
		end
	end
	return nil
end

-- ======================================================================== spells
-- the quest spell names of the unlocked set: used by class_spells.lua so a class change leaves them alone
function S.isQuestSpell(name)
	return Q.spellInfo(name) ~= nil
end

-- is this quest spell unlocked for the character's line (the done flag of its quest)
function S.unlocked(player, name)
	local info = Q.spellInfo(name)
	if not info then
		return false
	end
	local idx = Q.lineOf(player:getVocation():getId())
	if idx ~= info.line then
		return false
	end
	return Q.lineDone(getS(player, Q.keys(info.quest).lines), idx)
end

-- teaches the done spells of the character's line again and forgets the quest spells of other lines (free); returns the
-- numbers {learn, forget}. Needs the spells in the spellbook (spells_chaos.xml): a missing one is skipped.
function S.sync(player)
	local result = {learn = 0, forget = 0}
	local plan = Q.spellPlan(player:getVocation():getId(), S.read(player), function(name)
		local ok, has = pcall(player.hasLearnedSpell, player, name)
		return ok and has
	end)
	for _, name in ipairs(plan.forget) do
		if pcall(player.forgetSpell, player, name) then
			result.forget = result.forget + 1
		end
	end
	for _, name in ipairs(plan.learn) do
		local ok, done = pcall(player.learnSpell, player, name)
		if ok and done ~= false then
			result.learn = result.learn + 1
		end
	end
	return result
end

-- ======================================================================== the hunt
local function typeNameOf(creature)
	return Chaos.monsterTypeName and Chaos.monsterTypeName(creature) or creature:getName()
end

local function isBoss(creature)
	local mt = creature:getType()
	local ok, boss = pcall(function() return mt and mt:isBoss() end)
	return ok and boss == true
end

-- monsters of rifts, trials and dungeons, and husks of dense rifts: no credit
local function excluded(creature)
	local id = creature:getId()
	local RF = ChaosRift
	if RF and ((RF.monsterRun and RF.monsterRun[id]) or (RF.isHusk and RF.isHusk(creature))) then
		return true
	end
	if ChaosTrials and ChaosTrials.isTrialMonster and ChaosTrials.isTrialMonster(creature) then
		return true
	end
	if ChaosDungeons and ChaosDungeons.runAt and ChaosDungeons.runAt(creature:getPosition()) then
		return true
	end
	if ChaosAscensionQuest and ChaosAscensionQuest.guardianOf and ChaosAscensionQuest.guardianOf[id] then
		return true
	end
	return false
end

-- a protection zone tile within `radius` of the position
local function nearProtection(pos, radius)
	for dx = -radius, radius do
		for dy = -radius, radius do
			local tile = Tile(Position(pos.x + dx, pos.y + dy, pos.z))
			if tile and tile:hasFlag(TILESTATE_PROTECTIONZONE) then
				return true
			end
		end
	end
	return false
end

-- the hunting level of a monster (the Proof of Strength's measure: pace.lua covers level-scaled monsters and generated areas)
local function monsterLevel(monster)
	local mt = monster:getType()
	local fallback = 0
	if mt and ChaosAscensionQuestCore and ChaosAscensionQuestCore.estimateLevel then
		fallback = Chaos.huntingLevel(ChaosAscensionQuestCore.estimateLevel(mt:experience(), mt:maxHealth()))
	end
	return Chaos.monsterHuntingLevel(monster, fallback)
end

-- the facts of a death every credited player is judged by (nil: nothing counts)
local function describe(creature)
	if creature:getMaster() then
		return nil
	end
	local boss = isBoss(creature)
	local info = {boss = boss, excluded = excluded(creature), monsterLevel = monsterLevel(creature)}
	info.hunt = not ChaosPace or not ChaosPace.paced or ChaosPace.paced[creature:getId()] ~= nil
	local dead = ChaosTierDead and ChaosTierDead[creature:getId()]
	info.tier = dead and dead.tier or (ChaosTierOf and ChaosTierOf(creature)) or "normal"
	if info.excluded then
		return info
	end
	info.nearProtection = nearProtection(creature:getPosition(), C().hunt.protectionRadius or 4)
	return info
end

-- credits one character with a death: counts, rolls a fragment, writes the storages, tells the player
function S.credit(player, info, rand)
	local n, step, code = S.current(player)
	if code ~= "ok" or step ~= Q.STEP.HUNT then
		return 0
	end
	local weight = Q.killWeight(n, {playerLevel = player:getLevel(), monsterLevel = info.monsterLevel, boss = info.boss,
		excluded = info.excluded, nearProtection = info.nearProtection, hunt = info.hunt})
	if weight <= 0 then
		return 0
	end
	local k = Q.keys(n)
	local cur = {step = step, kills = getS(player, k.kills), fragments = getS(player, k.fragments), pity = getS(player, k.pity)}
	local new, res = Q.applyKill(cur, n, weight, info.tier, info.boss, rand or math.random)
	if new.kills ~= Q.count0(cur.kills) then
		player:setStorageValue(k.kills, new.kills)
	end
	if new.pity ~= Q.count0(cur.pity) then
		player:setStorageValue(k.pity, new.pity)
	end
	local qc = Q.quest(n)
	if res.fragment then
		player:setStorageValue(k.fragments, new.fragments)
		player:sendTextMessage(MESSAGE_LOOT or MESSAGE_INFO_DESCR, Chaos.t(player, "Quest fragment found: %d of %d.",
			new.fragments, qc.fragments))
	end
	if res.huntDone then
		player:setStorageValue(k.step, new.step)
		local npc = C().npc.name
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "The hunt is done. Return to %s and ask for the trial.", npc))
		toast(player, Chaos.t(player, "The hunt is done: the trial awaits."))
	end
	return weight
end

local function playerOf(creature)
	if not creature then
		return nil
	end
	if creature:isPlayer() then
		return creature
	end
	local master = creature:getMaster()
	if master and master:isPlayer() then
		return master
	end
	return nil
end

function S.onDeath(creature, killer, mostDamageKiller)
	if not C().enabled then
		return
	end
	local info = describe(creature)
	if not info or info.excluded then
		return
	end
	local damagers = {}
	for id in pairs(creature:getDamageMap() or {}) do
		local p = playerOf(Creature(id))
		if p then
			damagers[#damagers + 1] = p
		end
	end
	local killers, seen = {}, {}
	for _, p in ipairs({playerOf(killer), playerOf(mostDamageKiller)}) do
		if p and not seen[p:getId()] then
			seen[p:getId()] = true
			killers[#killers + 1] = p
		end
	end
	local range = C().hunt.partyRange or 30
	local credited = Q.credited(killers, damagers, function(p)
		local party = p:getParty()
		if not party then
			return nil
		end
		local members = party:getMembers()
		members[#members + 1] = party:getLeader()
		return members
	end, function(p) return p:getPosition() end, function(p) return p:getId() end, function(a, b)
		return a.z == b.z and math.abs(a.x - b.x) <= range and math.abs(a.y - b.y) <= range
	end)
	for _, p in ipairs(credited) do
		local ok, err = pcall(S.credit, p, info)
		if not ok then
			log("kill: " .. tostring(err))
		end
	end
end

local death = CreatureEvent("ChaosSpellQuestDeath")
function death.onDeath(creature, corpse, killer, mostDamageKiller)
	local ok, err = pcall(S.onDeath, creature, killer, mostDamageKiller)
	if not ok then
		log("death: " .. tostring(err))
	end
	return true
end
death:register()

-- every monster that is not a summon gets the death event (the checks run at the death: the pace layer knows the hunt monsters)
local spawn = EventCallback
spawn.onSpawn = function(self, position, startup, artificial)
	if C().enabled and not self:getMaster() then
		self:registerEvent("ChaosSpellQuestDeath")
	end
	return true
end
spawn:register()

-- ======================================================================== the trial
-- the quest whose trial key this is
local function questOfTrial(key)
	for n, qc in ipairs(C().quests) do
		if qc.trial == key then
			return n
		end
	end
	return nil
end

-- ok, text. Everything is checked again here: the NPC script and the modal only ask.
function S.enterTrial(player)
	local n, step, code = S.current(player)
	local lang = Chaos.lang(player)
	if code ~= "ok" then
		return false, Chaos.t(player, "You have no trial to enter.")
	end
	if not S.archivistNear(player) then
		return false, Chaos.t(player, "The trial is entered at %s.", C().npc.name)
	end
	local k = Q.keys(n)
	local busy = ChaosTrials.runs and ChaosTrials.runs[player:getId()] ~= nil
	local ok, text = Q.canEnterTrial(n, step, player:getLevel(), os.time(), getS(player, k.cooldown), busy, lang)
	if not ok then
		return false, text
	end
	if not ChaosTrials.enter then
		return false, Chaos.t(player, "The trial chambers cannot be opened. Please tell the staff.")
	end
	local entered, why = ChaosTrials.enter(player, nil, {spell = C().quests[n].trial})
	if not entered then
		return false, why
	end
	player:setStorageValue(k.attempts, Q.count0(getS(player, k.attempts)) + 1)
	return true
end

-- completes quest n for the character's line: the flag, the spell, the gold (once per quest); returns the message lines
function S.complete(player, n)
	local voc = player:getVocation():getId()
	local idx = Q.lineOf(voc)
	local k = Q.keys(n)
	local lines = {}
	if not idx then
		return lines
	end
	local reward = Q.reward(n, idx, player:getLevel(), getS(player, k.doneAt))
	player:setStorageValue(k.step, Q.STEP.DONE)
	player:setStorageValue(k.lines, Q.markLine(getS(player, k.lines), idx))
	if Q.count0(getS(player, k.doneAt)) == 0 then
		player:setStorageValue(k.doneAt, os.time())
	end
	if reward.gold > 0 then
		player:setBankBalance(player:getBankBalance() + reward.gold)
	end
	local okLearn, learned = false, false
	if reward.spell then
		okLearn, learned = pcall(player.learnSpell, player, reward.spell)
	end
	if not (okLearn and learned ~= false) then
		log(string.format("%s: could not teach %s (is it in spells_chaos.xml?)", player:getName(), tostring(reward.spell)))
	end
	lines[#lines + 1] = Chaos.t(player, "Trial passed. You have learned %s.", reward.spell or "?")
	if reward.gold > 0 then
		lines[#lines + 1] = Chaos.t(player, "%d gold coins to your bank.", reward.gold)
	end
	if ChaosSpellbook and ChaosSpellbook.refresh then
		pcall(ChaosSpellbook.refresh, player)
	end
	toast(player, Chaos.t(player, "New spell: %s", reward.spell or "?"))
	return lines
end

ChaosTrials.spellHook = {
	-- the guardian is down: only a character still on that quest's trial step is paid
	won = function(player, tr)
		local n = questOfTrial(tr.spell)
		if not n then
			return {}
		end
		local cur, step = S.current(player)
		if cur ~= n or step ~= Q.STEP.TRIAL then
			return {Chaos.t(player, "The trial is not yours to finish.")}
		end
		return S.complete(player, n)
	end,
	-- a run that failed: the door stays shut for failCooldownSeconds, unless it was cut short (error, logout, abort)
	failed = function(player, tr, how)
		if how == "error" or how == "logout" or how == "abort" then
			return
		end
		local n = questOfTrial(tr.spell)
		if n then
			player:setStorageValue(Q.keys(n).cooldown, os.time() + C().trial.failCooldownSeconds)
		end
	end
}

local modal = CreatureEvent("ChaosSpellQuestModal")
function modal.onModalWindow(player, modalWindowId, buttonId, choiceId)
	if modalWindowId ~= C().modal.trial then
		return true
	end
	if buttonId ~= 1 then
		return true
	end
	local ok, text = S.enterTrial(player)
	if not ok then
		player:sendTextMessage(MESSAGE_INFO_DESCR, text)
	end
	return true
end
modal:register()

-- ======================================================================== login
local login = CreatureEvent("ChaosSpellQuestLogin")
function login.onLogin(player)
	player:registerEvent("ChaosSpellQuestModal")
	-- spells of done quests that were not taught (the spell was not in the book then) or lost: free
	local ok, err = pcall(S.sync, player)
	if not ok then
		log("login sync: " .. tostring(err))
	end
	return true
end
login:register()

-- ======================================================================== staff: /spellquest
local function describeState(target)
	local parts = {}
	for n, e in ipairs(S.read(target)) do
		parts[#parts + 1] = string.format("Q%d step %d kills %d fragments %d pity %d lines %d attempts %d",
			n, Q.step(e.step), Q.count0(e.kills), Q.count0(e.fragments), Q.count0(e.pity), Q.count0(e.mask), Q.count0(e.attempts))
	end
	return target:getName() .. ": " .. table.concat(parts, "; ")
end

local cmd = TalkAction("/spellquest")
function cmd.onSay(player, words, param)
	if not Chaos.isStaff(player) then
		return true
	end
	local action, name, args = Q.parseCommand(param)
	if not action then
		player:sendTextMessage(MESSAGE_INFO_DESCR, name)
		return false
	end
	local target = Player(name)
	if not target then
		player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, "Player %s is not online.", name))
		return false
	end
	if action == "show" then
		player:sendTextMessage(MESSAGE_INFO_DESCR, describeState(target))
		return false
	end
	if action == "reset" then
		for n = 1, Q.count() do
			for _, key in pairs(Q.keys(n)) do
				target:setStorageValue(key, -1)
			end
		end
		S.sync(target)
		player:sendTextMessage(MESSAGE_INFO_DESCR, target:getName() .. ": spell quests reset.")
		log(string.format("%s reset the spell quests of %s", player:getName(), target:getName()))
		return false
	end
	local idx = Q.lineOf(target:getVocation():getId())
	if not idx then
		player:sendTextMessage(MESSAGE_INFO_DESCR, target:getName() .. " has no class line.")
		return false
	end
	local k = Q.keys(args.quest)
	local out = Q.applySet({mask = getS(target, k.lines), pity = getS(target, k.pity)}, idx, args.quest, args.step, args.kills, args.fragments)
	target:setStorageValue(k.step, out.step)
	target:setStorageValue(k.kills, out.kills)
	target:setStorageValue(k.fragments, out.fragments)
	target:setStorageValue(k.pity, out.pity)
	target:setStorageValue(k.lines, out.mask)
	target:setStorageValue(k.cooldown, 0)
	S.sync(target)
	player:sendTextMessage(MESSAGE_INFO_DESCR, describeState(target))
	log(string.format("%s set quest %d of %s to step %d", player:getName(), args.quest, target:getName(), args.step))
	return false
end
cmd:separator(" ")
cmd:register()

-- ======================================================================== startup: Archivist Ysolde
local function placed(pos)
	local name = C().npc.name
	for _, c in ipairs(Game.getSpectators(pos, false, false, 8, 8, 8, 8) or {}) do
		if c:isNpc() and c:getName():lower() == name:lower() then
			return c
		end
	end
	return Game.createNpc(name, pos)
end

function S.placeArchivists()
	local n = C().npc
	local count = 0
	for _, p in ipairs(n.positions or {}) do
		if placed(Position(p.x or p[1], p.y or p[2], p.z or p[3])) then
			count = count + 1
		end
	end
	if #(n.positions or {}) == 0 then
		for _, townId in ipairs(n.townIds or {}) do
			local town = Town(townId)
			local temple = town and town:getTemplePosition()
			-- npc_place.lua: her stall in the hub for the main city, else the offsets, then any free tile near the temple
			local ok, npc = pcall(function() return temple and ChaosNpcPlace.place(n.name, temple, n.offsets, n.place) end)
			if ok and npc then
				count = count + 1
			else
				log("could not place " .. n.name .. " in town " .. tostring(townId)
					.. " (no free tile near the temple, or data/npc/" .. n.name .. ".xml is missing)")
			end
		end
	end
	return count
end

local startup = GlobalEvent("ChaosSpellQuestStartup")
function startup.onStartup()
	if C().enabled and C().npc.spawn then
		addEvent(function()
			log(S.placeArchivists() .. " " .. C().npc.name .. " placed")
		end, 1100)
	end
	return true
end
startup:register()
