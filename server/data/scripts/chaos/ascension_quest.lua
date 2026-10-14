-- ascension_quest.lua: the quest that replaces !ascend for players (docs/CLASSES.md "Ascension quest").
-- Settings: ascension_quest_config.lua (Chaos.ascensionQuest); pure rules: ascension_quest_core.lua; the NPC: the
-- Ascendant Oracle (data/npc/Ascendant Oracle.xml, data/npc/scripts/ascendant_oracle.lua), placed in the temple at
-- startup.
--
--   1 the Calling      talk to the Oracle at level 100 (Chaos.classes.ascension.minLevel) as a base class: it tells you
--                      the two paths of your class (Chaos.classes.ascension.choices, read at run time)
--   2 Proof of Strength kill rare / legendary monsters at your level (ChaosTierOf, monster_tiers.lua; the level of the
--                      monster from bounty_pool.lua or estimated from its experience and health)
--   3 the Trial        alone in a runtime-built room: a class-themed guardian (an existing look, health and damage scaled
--                      to levels 100-130) with mechanics per class ("stillness", "adds", "zones", "enrage"). A lethal hit
--                      is caught (no death, no experience or item loss); death, the time limit, leaving or logging out
--                      fail the attempt: retry after a cooldown
--   4 the Choice       back at the Oracle: one of the two ascended classes, then a confirmation (modal windows). The
--                      ascension itself is ChaosAscension.ascend (below): the class lock, then the vocation change of
--                      ascension.lua (ChaosClasses.applyVocation: health / mana / capacity, the vocation resent to the
--                      client, dual wield sync), a title, a toast and a broadcast
--
-- !ascend: players are sent to the Oracle (ascension.lua asks ChaosAscensionQuest.commandAllowed); staff keeps it, and a
-- migrated character's one free switch still works. Staff: /ascendset <player>, <ascended class> (restores a class,
-- e.g. a character demoted by the old login bug; the class lock still applies). !ascension shows a character's progress.
--
-- The NPC script runs in its own Lua state: it reads the storages and opens the modal windows; every answer arrives
-- here (CreatureEvent modalwindow) and is checked again.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end

-- the type behind a shown name (chaos_constants.lua "Monster names"; a renamed rift monster or invader is still its type)
local function typeNameOf(creature)
	return Chaos.monsterTypeName and Chaos.monsterTypeName(creature) or creature:getName()
end
if not ChaosCommands then
	dofile("data/scripts/chaos/commands_ui_core.lua")
end
if not ChaosAscensionQuestCore or not ChaosAscensionQuestCore.sendConfirmModal then
	dofile("data/scripts/chaos/ascension_quest_core.lua")
end
if not ChaosClasses then
	dofile("data/scripts/chaos/classes.lua")
end
dofile("data/lib/chaos_dark_paint.lua")

local Q = ChaosAscensionQuestCore
ChaosAscensionQuest = ChaosAscensionQuest or {}
local S = ChaosAscensionQuest
ChaosAscension = ChaosAscension or {}

S.trials = S.trials or {} -- player id -> trial
S.slotBusy = S.slotBusy or {} -- slot -> player id
S.built = S.built or {} -- slot -> true
S.bad = S.bad or {} -- slot -> reason
S.guardianOf = S.guardianOf or {} -- monster id -> player id (guardian and adds)

Chaos.registerInstance("ascension", {label = "an ascension trial", inside = function(player)
	return S.trials[player:getId()] ~= nil
end, at = function(pos)
	return Q.slotAt(pos) ~= nil
end, runs = function() -- /instances (instance_limits.lua)
	local out, ms = {}, os.mtime and os.mtime() or os.time() * 1000
	for pid, tr in pairs(S.trials) do
		local p = Player(pid)
		out[#out + 1] = {id = pid, what = string.format("%s, slot %d, %s", p and p:getName() or "?", tr.slot,
			tr.over and "ending" or tr.phase), left = tr.deadline and not tr.over and math.max(0, math.floor((tr.deadline - ms) / 1000))
			or nil, players = p and 1 or 0}
	end
	return out
end, close = function(id) -- ended without a cooldown ("Nothing is lost"), back to the Oracle
	if S.trials[id] and not S.trials[id].over and S.finish then
		S.finish(id, "error", "A gamemaster closed the Trial. Nothing is lost.")
		return true, "Ascension trial of player " .. id .. " closed."
	end
	return false, "No running ascension trial " .. tostring(id) .. "."
end})

local function C()
	return Q.cfg()
end
local function K()
	return C().storage
end
local function P(t)
	return Position(t.x, t.y, t.z)
end
local function log(text)
	print("[Chaos ascension quest] " .. text)
end
local function now()
	return os.time()
end
local function mnow()
	return os.mtime and os.mtime() or os.time() * 1000
end

local function getS(player, key)
	return player:getStorageValue(key)
end
local function stageOf(player)
	return Q.stage(getS(player, K().stage))
end
local function setStage(player, s)
	player:setStorageValue(K().stage, s)
end

local function vocName(id)
	local v = Vocation(id)
	return v and v:getName() or tostring(id)
end

local function isStaff(player)
	local g = player:getGroup()
	return g ~= nil and g:getAccess() and g:getId() >= (C().staffGroup or 4)
end

-- only the PvP lock counts: the fight condition of a hunt (or of the Trial itself) does not keep anyone from the Oracle
local function inCombat(player)
	return player:isPzLocked()
end

local function toast(player, message)
	if ChaosOpcodes and ChaosOpcodes.notifications and json then
		player:sendExtendedOpcode(ChaosOpcodes.notifications, json.encode({action = "ascension", message = message}))
	end
end

-- the Oracle within `range` tiles (the confirmations only count at the Oracle)
function S.oracleNear(player)
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

-- ======================================================================== the ascension
-- ChaosAscension.ascend(player, word[, opts]): the Choice. word = an ascended class word of the character's line
-- (Chaos.classes.ascension.choices). opts.staff = true skips the quest rules (stage, level, the Oracle, combat) and
-- takes opts.vocId (any ascended id); the class lock is checked either way. Returns true, or false and the reason.
function ChaosAscension.ascend(player, word, opts)
	opts = opts or {}
	local voc = player:getVocation()
	local id, reason
	if opts.staff then
		id = opts.vocId or (Q.baseOf(voc:getId()) and Chaos.classes.ascension.choices[Q.baseOf(voc:getId())]
			and Chaos.classes.ascension.choices[Q.baseOf(voc:getId())][tostring(word or ""):lower()])
		if not id or not Q.isAscendedId(id) then
			return false, "That is no ascended class."
		end
	else
		local ok, _, text = Q.eligibility(voc:getId(), player:getLevel())
		if not ok then
			return false, text
		end
		id, reason = Q.validateChoice(voc:getId(), word, stageOf(player))
		if not id then
			return false, reason
		end
	end
	-- the class lock (class_unlocks.lua), for staff too: the Monk, the Necromancer and the Templar need the account's
	-- unlock. Checked before the rest so a locked character learns why at once.
	if ChaosClassUnlocks and ChaosClassUnlocks.canUseVocation then
		local allowed, lockMessage = ChaosClassUnlocks.canUseVocation(player, id)
		if not allowed then
			return false, lockMessage or "That class is locked. Unlock it in the store."
		end
	end
	if not opts.staff then
		if inCombat(player) then
			return false, "You cannot ascend in combat."
		end
		if not S.oracleNear(player) then
			return false, "Ascend before the " .. C().npc.name .. "."
		end
	end
	local newVoc = Vocation(id)
	if not newVoc then
		return false, "That vocation does not exist on this server."
	end
	if ChaosClasses.applyVocation then
		ChaosClasses.applyVocation(player, newVoc)
	else
		player:setVocation(newVoc)
	end
	player:setStorageValue(Chaos.classes.storage.ascended, now())
	setStage(player, Q.STAGE.DONE)
	player:save()
	local pos = player:getPosition()
	pos:sendMagicEffect(CONST_ME_HOLYAREA)
	pos:sendMagicEffect(CONST_ME_FIREWORK_YELLOW or CONST_ME_GROUNDSHAKER)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format(
		"You have ascended: you are now %s. The choice is final; only the store's Vocation Change can undo it.",
		newVoc:getDescription()))
	toast(player, string.format("You have ascended: %s.", newVoc:getName()))
	if not opts.quiet then
		Game.broadcastMessage(string.format(C().broadcast, player:getName(), newVoc:getName()), MESSAGE_EVENT_ADVANCE)
	end
	if ChaosNameplate and ChaosNameplate.refresh then
		pcall(ChaosNameplate.refresh, player)
	end
	return true
end

-- !ascend (ascension.lua): true when the old command may run, else the player is told to see the Oracle
function S.commandAllowed(player)
	if not C().enabled then
		return true
	end
	local free = player:getStorageValue(Chaos.classes.storage.freeSwitch)
	local ok, text = Q.commandGate(C().command, isStaff(player), free and free > 0)
	if not ok then
		player:sendTextMessage(MESSAGE_INFO_DESCR, text)
	end
	return ok
end

-- ======================================================================== Proof of Strength
local poolLevels
local function monsterLevel(monster)
	if not poolLevels then
		poolLevels = {}
		local ok, pool = pcall(dofile, "data/scripts/chaos/bounty_pool.lua")
		if ok and type(pool) == "table" then
			for _, list in pairs(pool) do
				for _, e in ipairs(type(list) == "table" and list or {}) do
					if type(e) == "table" and e.name and e.level then
						poolLevels[e.name:lower()] = e.level
					end
				end
			end
		end
	end
	local lvl = poolLevels[typeNameOf(monster):lower()]
	if lvl then
		return lvl
	end
	local mt = monster:getType()
	if not mt then
		return 0
	end
	return Q.estimateLevel(mt:experience(), mt:maxHealth())
end

function S.creditProof(player, tier, level)
	if stageOf(player) ~= Q.STAGE.PROOF then
		return 0
	end
	local pts = Q.proofPoints(tier, level, player:getLevel())
	if pts <= 0 then
		return 0
	end
	local n, done = Q.addProof(getS(player, K().proof), pts)
	player:setStorageValue(K().proof, n)
	if done then
		setStage(player, Q.STAGE.TRIAL)
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE,
			"Proof of Strength: complete. Return to the " .. C().npc.name .. " and ask for the trial.")
		toast(player, "Proof of Strength complete: the Trial awaits.")
	else
		player:sendTextMessage(MESSAGE_STATUS_CONSOLE_ORANGE or MESSAGE_INFO_DESCR, string.format(
			"Proof of Strength: %d / %d.", n, C().proof.needed))
	end
	return pts
end

local kill = CreatureEvent("ChaosAscensionKill")
function kill.onKill(player, target)
	if not player:isPlayer() or not target or not target:isMonster() or target:getMaster() then
		return true
	end
	if stageOf(player) ~= Q.STAGE.PROOF then
		return true
	end
	local ok, err = pcall(function()
		local tier = ChaosTierOf and ChaosTierOf(target) or "normal"
		if tier == "rare" or tier == "legendary" then
			S.creditProof(player, tier, monsterLevel(target))
		end
	end)
	if not ok then
		log("kill: " .. tostring(err))
	end
	return true
end
kill:register()

-- ======================================================================== the Trial
local function groundId(tile)
	local g = tile:getGround()
	if type(g) == "number" then
		return g
	end
	return g and g:getId() or nil
end

local function placeItem(pos, id)
	local tile = Tile(pos)
	if tile and not tile:getItemById(id) then
		return Game.createItem(id, 1, pos)
	end
	return tile and tile:getItemById(id)
end

-- the dark tile set (ascension_quest_config.lua trial.dark): walls and lights switch to it and the room is painted
-- by ChaosDarkPaint when it is installed; otherwise the stock ids of the config are used unchanged
local function darkTrial()
	local t = C().trial
	if t.darkActive ~= nil then
		return t.darkActive
	end
	t.darkActive = false
	local d = t.dark
	if d and d.enabled and ChaosDarkPaint and ChaosDarkTiles and ChaosDarkPaint.ready(d.style) then
		local wall, basin = ChaosDarkTiles.id(d.wall), ChaosDarkTiles.id(d.basin)
		if wall and basin then
			t.wallId, t.basinId, t.darkActive = wall, basin, true
		end
	end
	return t.darkActive
end

-- builds a slot on first use (refused when a tile of the footprint exists and is not ours)
function S.buildSlot(slot)
	local dark = darkTrial()
	local L = Q.layout(slot)
	if S.built[slot] then
		return L
	end
	if S.bad[slot] then
		return nil, S.bad[slot]
	end
	if not Game.createTile then
		return nil, "Game.createTile is missing"
	end
	local t = C().trial
	for _, list in ipairs({L.floor, L.walls}) do
		for _, f in ipairs(list) do
			local tile = Tile(P(f))
			local gid = tile and groundId(tile)
			if tile and ((gid ~= t.groundId and not (dark and ChaosDarkPaint.isDark(gid))) or (tile.getHouse and tile:getHouse())) then
				S.bad[slot] = string.format("tile %d,%d,%d already exists in the map", f.x, f.y, f.z)
				log("slot " .. slot .. ": " .. S.bad[slot])
				return nil, S.bad[slot]
			end
		end
	end
	for _, list in ipairs({L.floor, L.walls}) do
		for _, f in ipairs(list) do
			local pos = P(f)
			local tile = Tile(pos) or Game.createTile(pos, true)
			if tile and not tile:getGround() then
				Game.createItem(t.groundId, 1, pos)
			end
		end
	end
	for _, f in ipairs(L.walls) do
		placeItem(P(f), t.wallId)
	end
	for _, f in ipairs(L.basins) do
		placeItem(P(f), t.basinId)
	end
	if dark then
		local walls = {}
		for _, f in ipairs(L.walls) do
			walls[f.x .. "," .. f.y] = true
		end
		local reserved = {L.center, L.playerStart, L.guardianStart}
		for _, b in ipairs(L.basins) do
			reserved[#reserved + 1] = b
		end
		ChaosDarkPaint.apply(ChaosDarkPaint.plan(L.floor, t.dark.style, math.random, {walls = walls, reserved = reserved}), L.z)
	end
	S.built[slot] = true
	return L
end

-- monsters and loose items (corpses, fields) of the room
local function cleanSlot(L)
	local t = C().trial
	local keep = {[t.groundId] = true, [t.wallId] = true, [t.basinId] = true}
	for _, f in ipairs(L.floor) do
		local tile = Tile(P(f))
		if tile then
			for _, c in ipairs(tile:getCreatures() or {}) do
				if c:isMonster() then
					S.guardianOf[c:getId()] = nil
					c:remove()
				end
			end
			for _, item in ipairs(tile:getItems() or {}) do
				local id = item:getId()
				if not keep[id] and not (t.darkActive and ChaosDarkPaint.isDark(id)) then
					item:remove()
				end
			end
		end
	end
end

local function freeSlot()
	for slot = 1, C().trial.grid.slots do
		if not S.slotBusy[slot] and not S.bad[slot] then
			return slot
		end
	end
	return nil
end

local function heal(player)
	Chaos.heal(player, player:getMaxHealth() - player:getHealth())
	player:addMana(player:getMaxMana() - player:getMana())
end

local function dropFight(player)
	player:removeCondition(CONDITION_INFIGHT)
end

local function eventsOn(player)
	player:registerEvent("ChaosAscensionHealth")
	player:registerEvent("ChaosAscensionPrepareDeath")
end

local function eventsOff(player)
	player:unregisterEvent("ChaosAscensionHealth")
	player:unregisterEvent("ChaosAscensionPrepareDeath")
end

local function removeMonsters(tr)
	for _, id in ipairs({tr.guardianId}) do
		local m = id and Monster(id)
		if m then
			m:remove()
		end
	end
	for id in pairs(tr.adds or {}) do
		local m = Monster(id)
		if m then
			m:remove()
		end
	end
	for id, pid in pairs(S.guardianOf) do
		if pid == tr.pid then
			S.guardianOf[id] = nil
		end
	end
end

-- end a trial: how = "won" | "death" | "time" | "left" | "logout" | "error"
function S.finish(pid, how, text)
	local tr = S.trials[pid]
	if not tr or tr.over then
		return
	end
	tr.over = true
	local player = Player(pid)
	removeMonsters(tr)
	local t = C().trial
	if player then
		eventsOff(player)
		heal(player)
		dropFight(player)
		if how == "won" then
			setStage(player, Q.STAGE.CHOICE)
			player:setStorageValue(K().trialWon, now())
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format(
				"The %s falls. You have passed the Trial. The Oracle calls you back in %d seconds: make your choice.",
				tr.guardian.name, t.winExitSeconds))
			toast(player, "Trial passed: return to the Oracle and make your choice.")
			player:getPosition():sendMagicEffect(CONST_ME_HOLYAREA)
		elseif how ~= "error" then
			player:setStorageValue(K().cooldown, now() + t.cooldownSeconds)
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, (text or "You have failed the Trial.") .. string.format(
				" Nothing is lost. You may try again in %s.", Q.formatWait(t.cooldownSeconds)))
			toast(player, "Trial failed: try again in " .. Q.formatWait(t.cooldownSeconds) .. ".")
		else
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, text or "The Trial could not begin. Nothing is lost.")
		end
	end
	local delay = (how == "won") and t.winExitSeconds * 1000 or 0
	local back = tr.back
	local slot = tr.slot
	addEvent(function()
		local p = Player(pid)
		if p and Q.slotAt(p:getPosition()) == slot then
			p:teleportTo(back)
			back:sendMagicEffect(CONST_ME_TELEPORT)
			dropFight(p)
		end
		S.trials[pid] = nil
		if S.slotBusy[slot] == pid then
			S.slotBusy[slot] = nil
		end
		cleanSlot(tr.L)
		if ChaosInstanceLimits then
			ChaosInstanceLimits.freed("ascension", "the ascension trial rooms")
		end
	end, delay)
end

local function dress(monster, look, name)
	if name and monster.rename then
		monster:rename(name, "the " .. name)
	end
	if look then
		local o = monster:getOutfit()
		for k, v in pairs(look) do
			o[k] = v
		end
		monster:setOutfit(o)
	end
end

local function setHealth(monster, hp)
	monster:setMaxHealth(hp)
	local missing = hp - monster:getHealth()
	if missing > 0 then
		Chaos.heal(monster, missing)
	end
end

local function spawnGuardian(pid)
	local tr = S.trials[pid]
	local player = Player(pid)
	if not tr or tr.over or not player then
		return
	end
	local t = C().trial
	local m = Game.createMonster(t.guardianMonster, P(tr.L.guardianStart), false, true)
	if not m then
		log("cannot create " .. t.guardianMonster .. " (is data/monster/monsters/chaos/ascension registered?)")
		S.finish(pid, "error", "The guardian did not answer the call. Nothing is lost; please tell the staff.")
		return
	end
	dress(m, tr.guardian.look, tr.guardian.name)
	setHealth(m, tr.scale.health)
	m:registerEvent("ChaosAscensionGuardianDeath")
	S.guardianOf[m:getId()] = pid
	tr.guardianId = m:getId()
	m:getPosition():sendMagicEffect(CONST_ME_MORTAREA)
	if m.selectTarget then
		m:selectTarget(player)
	end
	tr.phase = "fight"
	tr.started = mnow()
	tr.deadline = tr.started + t.timeLimitSeconds * 1000
	tr.nextAdd = tr.started + t.addEvery
	tr.nextZone = tr.started + t.zoneEvery
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("The %s awakens. %s", tr.guardian.name, tr.guardian.hint or ""))
end

-- a share of the maximum health; a Hollow Vessel counts health + maximum energy shield (Chaos.percentBase)
local function hurt(tr, player, share, effect)
	local g = tr.guardianId and Monster(tr.guardianId)
	local dmg = math.max(1, math.floor(Chaos.percentBase(player) * share))
	-- a share of the max health already: not scaled again by the health event (doTargetCombat runs it at once)
	tr.raw = true
	pcall(doTargetCombat, g or 0, player, COMBAT_PHYSICALDAMAGE, -dmg, -dmg, effect or CONST_ME_GROUNDSHAKER, ORIGIN_SPELL)
	tr.raw = false
end
S.hurt = hurt -- tests

local function spawnAdds(tr, player)
	local t = C().trial
	local alive = 0
	for id in pairs(tr.adds) do
		if Monster(id) then
			alive = alive + 1
		else
			tr.adds[id] = nil
		end
	end
	local g = tr.guardianId and Monster(tr.guardianId)
	local at = g and g:getPosition() or P(tr.L.guardianStart)
	for _ = 1, math.min(t.addCount, t.addMax - alive) do
		local pos = Position(at.x + math.random(-2, 2), at.y + math.random(-2, 2), at.z)
		if not Q.inRoom(tr.L, pos) then
			pos = P(tr.L.center)
		end
		local m = Game.createMonster(t.addMonster, pos, true, true)
		if m then
			dress(m, tr.guardian.add and tr.guardian.add.look, tr.guardian.add and tr.guardian.add.name)
			setHealth(m, tr.scale.addHealth)
			tr.adds[m:getId()] = true
			S.guardianOf[m:getId()] = tr.pid
			m:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
			if m.selectTarget then
				m:selectTarget(player)
			end
		end
	end
	player:sendTextMessage(MESSAGE_STATUS_CONSOLE_ORANGE or MESSAGE_INFO_DESCR, "The " .. tr.guardian.name .. " calls for aid!")
end

local function zones(tr, player)
	local t = C().trial
	local center = player:getPosition()
	local list = Q.zoneTiles({x = center.x, y = center.y, z = center.z}, t.zoneCount, t.zoneRadius, math.random)
	local marked = {}
	for _, z in ipairs(list) do
		if Q.inRoom(tr.L, z) then
			local pos = P(z)
			pos:sendMagicEffect(CONST_ME_MAGIC_RED or CONST_ME_FIREAREA)
			marked[#marked + 1] = pos
		end
	end
	local pid = tr.pid
	addEvent(function()
		local cur = S.trials[pid]
		local p = Player(pid)
		if cur ~= tr or tr.over or not p then
			return
		end
		local here = p:getPosition()
		for _, pos in ipairs(marked) do
			pos:sendMagicEffect(CONST_ME_FIREAREA)
			if pos.x == here.x and pos.y == here.y and pos.z == here.z then
				hurt(tr, p, t.zoneShare, CONST_ME_FIREAREA)
			end
		end
	end, t.zoneDelay)
end

local function tick(pid)
	local tr = S.trials[pid]
	if not tr or tr.over then
		return
	end
	local t = C().trial
	local player = Player(pid)
	if not player then
		S.finish(pid, "logout")
		return
	end
	local pos = player:getPosition()
	if not Q.inRoom(tr.L, pos) then
		S.finish(pid, "left", "You left the Trial.")
		return
	end
	local ms = mnow()
	if tr.phase == "fight" then
		if ms >= tr.deadline then
			S.finish(pid, "time", "Time is up: the " .. tr.guardian.name .. " still stands.")
			return
		end
		local g = tr.guardianId and Monster(tr.guardianId)
		if g and g.getTarget and not g:getTarget() and g.selectTarget then
			g:selectTarget(player)
		end
		local left = math.floor((tr.deadline - ms) / 1000)
		if left > 0 and left % 30 == 0 and left ~= tr.lastAnnounce then
			tr.lastAnnounce = left
			player:sendTextMessage(MESSAGE_STATUS_CONSOLE_ORANGE or MESSAGE_INFO_DESCR, string.format("Trial: %d seconds left.", left))
		end
		if Q.hasMechanic(tr.guardian, "stillness") then
			local r = Q.stillness(tr.still, pos.x .. ":" .. pos.y, ms)
			if r == "warn" then
				pos:sendMagicEffect(CONST_ME_STONES or CONST_ME_POFF)
				player:sendTextMessage(MESSAGE_STATUS_CONSOLE_ORANGE or MESSAGE_INFO_DESCR, "The ground trembles under you. Move!")
			elseif r == "slam" then
				hurt(tr, player, t.stillShare, CONST_ME_GROUNDSHAKER)
			end
		end
		if Q.hasMechanic(tr.guardian, "adds") and ms >= tr.nextAdd then
			tr.nextAdd = ms + t.addEvery
			spawnAdds(tr, player)
		end
		if Q.hasMechanic(tr.guardian, "zones") and ms >= tr.nextZone then
			tr.nextZone = ms + t.zoneEvery
			zones(tr, player)
		end
	end
	addEvent(tick, t.tickMs, pid)
end

-- enter the Trial (from the modal window the Oracle opened): ok, reason
function S.enterTrial(player)
	local t = C().trial
	local voc = player:getVocation():getId()
	local ok, _, text = Q.eligibility(voc, player:getLevel())
	if not ok then
		return false, text
	end
	local pid = player:getId()
	ok, text = Q.canEnterTrial(stageOf(player), now(), getS(player, K().cooldown), S.trials[pid] ~= nil)
	if not ok then
		return false, text
	end
	if inCombat(player) then
		return false, "You cannot enter the Trial in combat."
	end
	local oracle = S.oracleNear(player)
	if not oracle then
		return false, "The Trial is entered at the " .. C().npc.name .. "."
	end
	local running = 0
	for _ in pairs(S.trials) do
		running = running + 1
	end
	local IL = ChaosInstanceLimits
	local lim = C().trial.limits
	local slot = not (IL and IL.capped("ascension", running, lim)) and freeSlot() or nil
	if not slot then
		if IL then
			local lefts, ms = {}, os.mtime and os.mtime() or os.time() * 1000
			for _, tr in pairs(S.trials) do
				lefts[#lefts + 1] = tr.deadline and math.max(0, math.floor((tr.deadline - ms) / 1000)) or C().trial.timeLimitSeconds
			end
			return false, IL.busy(player, "ascension", "trial chambers", lefts, lim)
		end
		return false, "Every trial chamber is in use. Try again in a moment."
	end
	local L, err = S.buildSlot(slot)
	if not L then
		log("slot " .. slot .. ": " .. tostring(err))
		slot = freeSlot()
		L = slot and S.buildSlot(slot)
		if not L then
			return false, "The trial chambers cannot be opened. Please tell the staff."
		end
	end
	cleanSlot(L)
	local base = Q.baseOf(voc)
	local tr = {pid = pid, slot = slot, L = L, guardian = Q.guardianFor(base), scale = Q.trialScale(player:getLevel()),
		adds = {}, still = {}, phase = "countdown", back = player:getPosition()}
	S.trials[pid] = tr
	S.slotBusy[slot] = pid
	player:setStorageValue(K().attempts, math.max(0, getS(player, K().attempts)) + 1)
	player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
	player:teleportTo(P(L.playerStart))
	P(L.playerStart):sendMagicEffect(CONST_ME_TELEPORT)
	heal(player)
	eventsOn(player)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("The Trial of Ascension: the %s comes in %d seconds. You have %d seconds to defeat it.",
		tr.guardian.name, t.countdownSeconds, t.timeLimitSeconds))
	addEvent(spawnGuardian, t.countdownSeconds * 1000, pid)
	addEvent(tick, t.tickMs, pid)
	return true
end

-- the guardian's death: the Trial is won
local gdeath = CreatureEvent("ChaosAscensionGuardianDeath")
function gdeath.onDeath(creature)
	local pid = S.guardianOf[creature:getId()]
	S.guardianOf[creature:getId()] = nil
	local tr = pid and S.trials[pid]
	if tr and not tr.over and tr.guardianId == creature:getId() then
		tr.guardianId = nil
		addEvent(S.finish, 0, pid, "won")
	end
	return true
end
gdeath:register()

-- the player's side: the guardian's hits scaled, a lethal hit caught (no death)
local health = CreatureEvent("ChaosAscensionHealth")
function health.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if primaryType == COMBAT_HEALING then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local tr = S.trials[creature:getId()]
	if not tr or tr.over then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local sign = primaryDamage < 0 and -1 or 1
	local p, s = math.abs(primaryDamage), secondaryType == COMBAT_HEALING and 0 or math.abs(secondaryDamage)
	if attacker and attacker:isMonster() and S.guardianOf[attacker:getId()] == tr.pid and not tr.raw then
		local mult = tr.scale.damage
		if attacker:getId() == tr.guardianId then
			mult = Q.guardianMultiplier(tr.guardian, tr.scale, attacker:getHealth(), attacker:getMaxHealth())
		end
		p, s = math.floor(p * mult + 0.5), math.floor(s * mult + 0.5)
	end
	-- the energy shield (engine patch 0015) takes its part after this event: a hit is lethal past health + shield
	local cp, cs, caught = Q.catchDamage(creature:getHealth() + (creature.getEnergyShield and creature:getEnergyShield() or 0), p, s)
	if caught then
		addEvent(S.finish, 0, tr.pid, "death", "You have fallen in the Trial. The Oracle pulls you back.")
	end
	return sign * cp, primaryType, secondaryType == COMBAT_HEALING and secondaryDamage or sign * cs, secondaryType
end
health:register()

-- the safety net: whatever got past the health event
local prepare = CreatureEvent("ChaosAscensionPrepareDeath")
function prepare.onPrepareDeath(creature, killer)
	local tr = S.trials[creature:getId()]
	if not tr then
		return true
	end
	if creature:getHealth() < 1 then
		Chaos.heal(creature, 1)
	end
	addEvent(S.finish, 0, tr.pid, "death", "You have fallen in the Trial. The Oracle pulls you back.")
	return false
end
prepare:register()

-- ======================================================================== modal windows (the Oracle's questions)
local modal = CreatureEvent("ChaosAscensionModal")
function modal.onModalWindow(player, modalWindowId, buttonId, choiceId)
	local m = C().modal
	local voc = player:getVocation():getId()
	if modalWindowId == m.trial then
		if buttonId ~= 1 then
			return true
		end
		local ok, text = S.enterTrial(player)
		if not ok then
			player:sendTextMessage(MESSAGE_INFO_DESCR, text)
		end
	elseif modalWindowId == m.choice then
		if buttonId ~= 1 then
			return true
		end
		local list = Q.choicesOf(voc) or {}
		local c = list[choiceId]
		if not c then
			return true
		end
		local id, reason = Q.validateChoice(voc, c.word, stageOf(player))
		if not id then
			player:sendTextMessage(MESSAGE_INFO_DESCR, reason)
			return true
		end
		Q.sendConfirmModal(player, id, c.word, vocName(id))
	elseif modalWindowId > m.confirmBase and modalWindowId <= m.confirmBase + 255 then
		if buttonId ~= 1 then
			player:sendTextMessage(MESSAGE_INFO_DESCR, "The Oracle waits. Say 'choice' when you are ready.")
			return true
		end
		local id = modalWindowId - m.confirmBase
		local word
		for _, c in ipairs(Q.choicesOf(voc) or {}) do
			if c.id == id then
				word = c.word
			end
		end
		if not word then
			player:sendTextMessage(MESSAGE_INFO_DESCR, "That path is not yours to walk.")
			return true
		end
		local ok, text = ChaosAscension.ascend(player, word)
		if not ok then
			player:sendTextMessage(MESSAGE_INFO_DESCR, text)
		end
	end
	return true
end
modal:register()

-- ======================================================================== login / logout
local login = CreatureEvent("ChaosAscensionLogin")
function login.onLogin(player)
	player:registerEvent("ChaosAscensionKill")
	player:registerEvent("ChaosAscensionModal")
	player:registerEvent("ChaosAscensionLogout")
	-- a character saved inside a trial room (a crash, a restart): back to its temple
	if Q.slotAt(player:getPosition()) and not S.trials[player:getId()] then
		local temple = player:getTown() and player:getTown():getTemplePosition()
		if temple then
			player:teleportTo(temple)
		end
	end
	return true
end
login:register()

local logout = CreatureEvent("ChaosAscensionLogout")
function logout.onLogout(player)
	local tr = S.trials[player:getId()]
	if tr and not tr.over then
		player:teleportTo(tr.back)
		S.finish(player:getId(), "logout", "You left the Trial.")
	end
	return true
end
logout:register()

-- ======================================================================== talkactions
local status = {} -- reached from the menu: Info & Services window (commands_ui.lua, id "ascension")
function status.onSay(player, words, param)
	local voc = player:getVocation():getId()
	local ok, code, text = Q.eligibility(voc, player:getLevel())
	if not ok then
		player:sendTextMessage(MESSAGE_INFO_DESCR, "Ascension: " .. text)
		return false
	end
	local st = stageOf(player)
	local lines = {
		[0] = "not begun. Speak with the " .. C().npc.name .. " in the temple.",
		[1] = string.format("Proof of Strength, %d / %d (rare and legendary monsters of level %d+).",
			math.max(0, getS(player, K().proof)), C().proof.needed, Q.minMonsterLevel(player:getLevel())),
		[2] = "the Trial. Ask the " .. C().npc.name .. " for the trial.",
		[3] = "the Choice. Tell the " .. C().npc.name .. " your choice.",
		[4] = "complete."
	}
	local extra = ""
	local wait = getS(player, K().cooldown) - now()
	if st == 2 and wait > 0 then
		extra = " You may try again in " .. Q.formatWait(wait) .. "."
	end
	player:sendTextMessage(MESSAGE_INFO_DESCR, "Ascension: " .. lines[st] .. extra)
	return false
end
ChaosCommands.register("ascension", function(player, param) return status.onSay(player, "", param) end)

local set = TalkAction("/ascendset")
function set.onSay(player, words, param)
	if not isStaff(player) then
		return true
	end
	local name, id, err = Q.parseAscendSet(param)
	if not id then
		player:sendTextMessage(MESSAGE_INFO_DESCR, err)
		return false
	end
	local target = Player(name)
	if not target then
		player:sendTextMessage(MESSAGE_INFO_DESCR, "Player " .. name .. " is not online.")
		return false
	end
	local base = Q.baseOf(target:getVocation():getId())
	if base ~= Q.baseOf(id) then
		player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("%s is %s; %s belongs to another line (use the store's Vocation Change).",
			target:getName(), target:getVocation():getName(), vocName(id)))
		return false
	end
	local ok, text = ChaosAscension.ascend(target, nil, {staff = true, vocId = id, quiet = true})
	if not ok then
		player:sendTextMessage(MESSAGE_INFO_DESCR, "Not changed: " .. tostring(text))
		return false
	end
	player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("%s is now %s.", target:getName(), vocName(id)))
	log(string.format("%s set %s to %s", player:getName(), target:getName(), vocName(id)))
	return false
end
set:separator(" ")
set:register()

-- ======================================================================== startup: the Oracle, titles, tier skip
local function placeOracle(pos)
	local name = C().npc.name
	for _, c in ipairs(Game.getSpectators(pos, false, false, 8, 8, 8, 8) or {}) do
		if c:isNpc() and c:getName():lower() == name:lower() then
			return c
		end
	end
	return Game.createNpc(name, pos)
end

local function freeTileNear(temple, offsets)
	for _, o in ipairs(offsets) do
		local pos = Position(temple.x + o[1], temple.y + o[2], temple.z)
		local tile = Tile(pos)
		if tile and tile:getGround() and not tile:hasProperty(CONST_PROP_BLOCKSOLID) and not tile:getTopCreature()
				and not tile:hasFlag(TILESTATE_TELEPORT) and not tile:hasFlag(TILESTATE_FLOORCHANGE) then
			return pos
		end
	end
	return nil
end

function S.placeOracles()
	local n = C().npc
	local placed = 0
	for _, p in ipairs(n.positions or {}) do
		if placeOracle(Position(p.x or p[1], p.y or p[2], p.z or p[3])) then
			placed = placed + 1
		end
	end
	if #(n.positions or {}) == 0 then
		for _, townId in ipairs(n.townIds or {}) do
			local town = Town(townId)
			local temple = town and town:getTemplePosition()
			local pos = temple and freeTileNear(temple, n.offsets)
			if pos and placeOracle(pos) then
				placed = placed + 1
			else
				log("could not place the " .. n.name .. " in town " .. tostring(townId)
					.. " (no free tile next to the temple, or data/npc/" .. n.name .. ".xml is missing)")
			end
		end
	end
	return placed
end

function S.registerTitles()
	if not ChaosTitles or not ChaosTitles.register then
		return false
	end
	ChaosTitles.register("ascension", function(player)
		local v = player:getVocation()
		return Q.titleFor(v:getId(), v:getName(), player:getStorageValue(Chaos.classes.storage.ascended))
	end)
	return true
end

local function skipTiers()
	if ChaosTierConfig and ChaosTierConfig.skip then
		ChaosTierConfig.skip[C().trial.guardianMonster:lower()] = true
		ChaosTierConfig.skip[C().trial.addMonster:lower()] = true
	end
end

S.registerTitles()
skipTiers()

local startup = GlobalEvent("ChaosAscensionStartup")
function startup.onStartup()
	skipTiers()
	S.registerTitles()
	if C().enabled and C().npc.spawn then
		addEvent(function()
			local n = S.placeOracles()
			log(n .. " " .. C().npc.name .. " placed")
		end, 1000)
	end
	return true
end
startup:register()
