-- Tutorial island (roadmap item 22): brand-new characters start on a small island built at runtime and walk through
-- five stations, west to east, before they reach the temple with their starter kit (newplayer.lua).
--   1 moving and fighting: kill 3 rats in the first pen (CreatureEvent kill)
--   2 spells: open !spells (ChaosSpellbook.sendTo, wrapped) and cast the class spell (spell group cooldown)
--   3 the passive tree: one free point, allocate it (ChaosPassiveTree.listeners)
--   4 orbs: an Orb of Upheaval and a Common leather armor; use the orb on it (stock action or the crafting bench)
--   5 keystones, !bounty and the store: information, then the exit forcefield
-- Divider walls with a gate keep a player in its station until the task is done; a lesson (modal window + toast)
-- opens on entering a station, on its white marble tile and on its angel statue. !skiptutorial or the goblin statue in
-- the first pen leaves at once with the kit.
-- Layout, coordinates and texts: newplayer_config.lua `tutorial`; geometry: newplayer_core.lua NP.layout.
--
-- Safety: no PvP on the island (EventCallback onTargetCombat; runtime tiles cannot get the protection-zone flag), the
-- island is water-bound and walled so monsters stay in the first pen; a character that logs out or dies on the
-- island is put back at its station when it logs in (a death sends it to the temple, the login brings it back).
-- Multi-client characters may do the tutorial like anyone.
--
-- Assumed engine API (TFS 1.4): Game.createTile/createItem/createMonster, Tile:getGround/getItemById/getCreatures,
-- Item:setActionId, MoveEvent stepin with aid, Action with aid, CreatureEvent kill/modalwindow, EventCallback
-- onTargetCombat, Player:getCondition(CONDITION_SPELLGROUPCOOLDOWN, CONDITIONID_DEFAULT, group), setMaxMana.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosCommands then
	dofile("data/scripts/chaos/commands_ui_core.lua")
end
if not ChaosNewPlayer or not ChaosNewPlayer.layout then
	dofile("data/scripts/chaos/newplayer_core.lua")
end

local NP = ChaosNewPlayer
local function C()
	return NP.cfg()
end
local function T()
	return NP.cfg().tutorial
end
local function P(t)
	return Position(t.x, t.y, t.z)
end
local function getS(player, name)
	return player:getStorageValue(NP.key(name))
end
local function setS(player, name, value)
	player:setStorageValue(NP.key(name), value)
end

NP.island = NP.island -- nil = not tried yet, {ok = bool, reason}

-- ------------------------------------------------------------------------------------------------ building
local function groundId(tile)
	local g = tile:getGround()
	if type(g) == "number" then
		return g
	end
	return g and g:getId() or nil
end

local function placeItem(pos, id, aid)
	local tile = Tile(pos)
	if not tile then
		return nil
	end
	local item = tile:getItemById(id)
	if not item then
		item = Game.createItem(id, 1, pos)
	end
	if item and aid then
		item:setActionId(aid)
	end
	return item
end

local GROUND_OF = {}
local function groundOf(kind)
	local t = T()
	GROUND_OF.water, GROUND_OF.ground, GROUND_OF.wall = t.water, t.ground, t.ground
	GROUND_OF.gate, GROUND_OF.marker = t.gateGround, t.markerGround
	return GROUND_OF[kind]
end

-- returns true, or false + reason (nothing is built then)
function NP.buildIsland()
	local t = T()
	if not t.enabled then
		return false, "the tutorial is switched off"
	end
	if not Game.createTile then
		return false, "Game.createTile is missing"
	end
	local L = NP.layout()
	local foot = NP.footprint(L)
	local ours = {[t.water] = true, [t.ground] = true, [t.gateGround] = true, [t.markerGround] = true}
	for _, f in ipairs(foot) do
		local tile = Tile(P(f))
		if tile then
			local gid = groundId(tile)
			if not ours[gid] or (tile.getHouse and tile:getHouse()) then
				return false, string.format("tile %d,%d,%d already exists in the map", f.x, f.y, f.z)
			end
		end
	end
	for _, f in ipairs(foot) do
		local pos = P(f)
		local tile = Tile(pos) or Game.createTile(pos, true)
		if tile then
			local g = tile:getGround()
			if not g then
				g = Game.createItem(groundOf(f.kind), 1, pos)
			end
			if f.kind == "wall" then
				placeItem(pos, t.wall)
			elseif f.kind == "gate" and g and type(g) ~= "number" then
				g:setActionId(t.aid.gate)
			elseif f.kind == "marker" and g and type(g) ~= "number" then
				g:setActionId(t.aid.marker)
			end
		end
	end
	for i, r in ipairs(L.rooms) do
		placeItem(P(r.statue), t.statue, t.aid.statue)
		for _, b in ipairs(r.basins) do
			placeItem(P(b), t.basin)
		end
		for k, d in ipairs(r.decor) do
			placeItem(P(d), t.decor[(i + k) % #t.decor + 1])
		end
	end
	placeItem(P(L.skipStatue), t.skipStatue, t.aid.skip)
	placeItem(P(L.exit), t.portal, t.aid.exit)
	return true
end

function NP.islandReady()
	if NP.island == nil then
		local ok, reason = NP.buildIsland()
		NP.island = {ok = ok, reason = reason}
		print(ok and "[newplayer] tutorial island built" or ("[newplayer] tutorial island not built: " .. tostring(reason) ..
			"; new characters get their kit at the first login"))
	end
	return NP.island.ok
end

-- ------------------------------------------------------------------------------------------------ lessons and tasks
local function stageOf(player)
	return tonumber(getS(player, "stage")) or -1
end

local function doneOf(player)
	return math.max(0, tonumber(getS(player, "done")) or 0)
end

local function flagsOf(player)
	return math.max(0, tonumber(getS(player, "flags")) or 0)
end

local function setFlag(player, bit)
	setS(player, "flags", NP.setBit(flagsOf(player), bit))
end

local function spellOf(player)
	return NP.tutorialSpellFor(player:getVocation():getId())
end

local function lessonText(player, i)
	local t = T()
	local lesson = t.lessons[i]
	if i == 1 then
		return string.format(lesson.text, t.kills), string.format(lesson.toast, t.kills)
	elseif i == 2 then
		local spell = spellOf(player)
		local extra = spell and string.format(", then cast %s: say \"%s\" (it heals you).", spell.name, spell.words)
			or ". Your class learns its first spell at level 20 (Shuriken Toss)."
		return string.format(lesson.text, extra), string.format(lesson.toast, spell and (" and say \"" .. spell.words .. "\"") or "")
	elseif i == 4 then
		return string.format(lesson.text, ChaosCrafting and lesson.craftHint or ""), lesson.toast
	end
	return lesson.text, lesson.toast
end

function NP.showLesson(player, i)
	local t = T()
	local text, toast = lessonText(player, i)
	local buttons = {{1, "Ok"}}
	if i == 1 then
		buttons = {{1, "Ok"}, {2, "Skip tutorial"}}
	end
	NP.modal(player, t.modalBase + i, t.lessons[i].title, text, buttons)
	NP.toast(player, toast)
end

local function monstersInRoom(L, room)
	local n = 0
	for x = room.x1, room.x2 do
		for y = room.y1, room.y2 do
			local tile = Tile(Position(x, y, L.z))
			for _, c in ipairs(tile and tile:getCreatures() or {}) do
				if c:isMonster() then
					n = n + 1
				end
			end
		end
	end
	return n
end

local function monsterName()
	for _, name in ipairs(T().monsters) do
		if MonsterType(name) then
			return name
		end
	end
	return nil
end

local function spawnMonsters()
	local L = NP.layout()
	local name = monsterName()
	if not name then
		return
	end
	local have = monstersInRoom(L, L.rooms[1])
	for i = 1, T().maxMonsters - have do
		local spot = L.spawns[(i - 1) % #L.spawns + 1]
		local m = Game.createMonster(name, P(spot), false, true)
		if m then
			m:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
		end
	end
end

local polls = {} -- player id -> true while a poll runs

local function complete(player, i)
	local done = doneOf(player)
	if NP.hasBit(done, NP.stationBit(i)) then
		return
	end
	setS(player, "done", NP.setBit(done, NP.stationBit(i)))
	local t = T()
	local text
	if i < t.rooms then
		text = string.format("Station %d done! The gate to the east is open.", i)
	else
		text = "Step into the forcefield to leave the island."
	end
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, text)
	NP.toast(player, text)
	player:getPosition():sendMagicEffect(CONST_ME_MAGIC_GREEN)
end
NP.tutorialComplete = complete

local SPELL_GROUPS = {SPELLGROUP_ATTACK or 1, SPELLGROUP_HEALING or 2, SPELLGROUP_SUPPORT or 3}

local function castSpell(player)
	for _, g in ipairs(SPELL_GROUPS) do
		if player:getCondition(CONDITION_SPELLGROUPCOOLDOWN, CONDITIONID_DEFAULT, g) then
			return true
		end
	end
	return false
end

-- spell (station 2) and orb (station 4) tasks: checked every pollMs while the player is on them
local function poll(pid)
	local player = Player(pid)
	if not player then
		polls[pid] = nil
		return
	end
	local stage = stageOf(player)
	local done = doneOf(player)
	if stage == 2 and not NP.hasBit(done, NP.stationBit(2)) then
		if castSpell(player) and not NP.hasBit(flagsOf(player), 2) then
			setFlag(player, 2)
			if not NP.hasBit(flagsOf(player), 1) then
				player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Well cast! Now open your spellbook: Character > Spellbook (Alt+S).")
			end
		end
		if NP.spellTaskDone(flagsOf(player), spellOf(player) ~= nil) then
			complete(player, 2)
		end
	elseif stage == 4 and not NP.hasBit(done, NP.stationBit(4)) then
		local base = tonumber(getS(player, "orbBase")) or 0
		if player:getItemCount(C().orbId) < base then
			complete(player, 4)
		end
	else
		polls[pid] = nil
		return
	end
	addEvent(poll, T().pollMs, pid)
end

local function startPoll(player)
	local pid = player:getId()
	if not polls[pid] then
		polls[pid] = true
		addEvent(poll, T().pollMs, pid)
	end
end

local function hasBackpack(player)
	local bp = player:getSlotItem(CONST_SLOT_BACKPACK)
	return bp and bp:isContainer() and bp or nil
end

-- start (or restart after a relog) the task of station i
local function startTask(player, i)
	local t = T()
	local done = doneOf(player)
	if NP.hasBit(done, NP.stationBit(i)) then
		return
	end
	if i == 1 then
		-- the rats come when the player closes the lesson (Ok), steps on the lesson tile, or after spawnDelayMs
		local pid = player:getId()
		addEvent(function()
			local p = Player(pid)
			if p and stageOf(p) == 1 and NP.onIsland(p:getPosition()) then
				spawnMonsters()
			end
		end, t.spawnDelayMs or 20000)
	elseif i == 2 then
		local spell = spellOf(player)
		if spell and not NP.hasBit(flagsOf(player), 16) then
			-- a level 1 character may have too little mana for its first spell: top it up once
			if player:getMaxMana() < spell.mana and player.setMaxMana then
				player:setMaxMana(spell.mana)
			end
			player:addMana(player:getMaxMana())
			setFlag(player, 16)
		end
		startPoll(player)
	elseif i == 3 then
		if not NP.hasBit(flagsOf(player), 4) then
			local key = Chaos.storage.passiveExtraPoints
			player:setStorageValue(key, math.max(0, player:getStorageValue(key)) + 1)
			setFlag(player, 4)
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "You received a free passive point.")
		end
		if ChaosPassiveTree and ChaosPassiveTree.hasAllocation and ChaosPassiveTree.hasAllocation(player) then
			complete(player, 3)
		end
	elseif i == 4 then
		if not NP.hasBit(flagsOf(player), 8) then
			local container = hasBackpack(player)
			if not container then
				container = player:addItem(C().common.backpackId, 1, false, 1, CONST_SLOT_BACKPACK)
			end
			local o = t.orbItem
			-- the tutorial's fixed item level (chaos_item_mods.lua itemLevel.tutorial); rolled by ChaosCrafting.forge
			local item = ChaosCrafting and ChaosCrafting.createItem
				and ChaosCrafting.createItem(o.id, o.rarity or 0, ChaosItemMods.config.itemLevel.tutorial)
				or Game.createItem(o.id, 1)
			if item then
				if not (container and container:addItemEx(item) == RETURNVALUE_NOERROR) then
					player:addItemEx(item, true)
				end
			end
			NP.giveStack(player, container, C().orbId, 1)
			setS(player, "orbBase", player:getItemCount(C().orbId))
			setFlag(player, 8)
		end
		startPoll(player)
	elseif i == 5 then
		complete(player, 5)
	end
end

-- show station i's lesson and start its task (only the station the player is on)
local function enterStation(player, i)
	NP.showLesson(player, i)
	if stageOf(player) == i then
		startTask(player, i)
	end
end

-- ------------------------------------------------------------------------------------------------ start, resume, end
local function registerEvents(player)
	player:registerEvent("ChaosTutorialKill")
	player:registerEvent("ChaosTutorialModal")
	player:registerEvent("ChaosTutorialHealth")
end

-- ------------------------------------------------------------------ the island's time limit (instance limits)
NP.islandSince = NP.islandSince or {} -- [guid] = os.time this session on the island began
NP.islandWarn = NP.islandWarn or {} -- [guid] = warning state of this session

-- seconds left on the island (nil without a limit)
function NP.islandLeft(player, now)
	local limit = (T().timeLimitMinutes or 0) * 60
	if limit <= 0 then
		return nil
	end
	now = now or os.time()
	local used = math.max(0, getS(player, "islandUsed"))
	local since = NP.islandSince[player:getGuid()] or now
	return math.max(0, limit - used - (now - since))
end

local function islandWatch(name, guid, since)
	local p = Player(name)
	if not p or p:getGuid() ~= guid or NP.islandSince[guid] ~= since or not NP.inTutorial(stageOf(p)) then
		return
	end
	local left = NP.islandLeft(p)
	if not left then
		return
	end
	if left <= 0 then
		NP.tutorialFinish(p, "time")
		return
	end
	if ChaosInstanceLimits then
		NP.islandWarn[guid] = NP.islandWarn[guid] or {}
		ChaosInstanceLimits.warn(NP.islandWarn[guid], left, {p}, "Tutorial", T().limits)
	end
	addEvent(islandWatch, 5000, name, guid, since)
end
NP._islandWatch = islandWatch

local function islandClock(player)
	local guid, now = player:getGuid(), os.time()
	NP.islandSince[guid] = now
	NP.islandWarn[guid] = {}
	addEvent(islandWatch, 5000, player:getName(), guid, now)
end

-- logout: the session's time is kept
function NP.islandLogout(player)
	local guid = player:getGuid()
	local since = NP.islandSince[guid]
	if since then
		NP.islandSince[guid] = nil
		NP.islandWarn[guid] = nil
		if NP.inTutorial(stageOf(player)) then
			setS(player, "islandUsed", math.max(0, getS(player, "islandUsed")) + math.max(0, os.time() - since))
		end
	end
end

function NP.tutorialStart(player)
	if not NP.islandReady() then
		return false
	end
	setS(player, "stage", 1)
	setS(player, "done", 0)
	setS(player, "kills", 0)
	setS(player, "flags", 0)
	setS(player, "islandUsed", 0)
	islandClock(player)
	registerEvents(player)
	local L = NP.layout()
	player:teleportTo(P(L.rooms[1].arrival))
	player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
	local name = player:getName()
	addEvent(function()
		local p = Player(name)
		if p and stageOf(p) == 1 then
			enterStation(p, 1)
		end
	end, C().welcome.delayMs)
	return true
end

-- leave the island: kit if not given yet, temple, welcome. how = "done" | "skipped" | "time" (the time limit; counts
-- as skipped)
function NP.tutorialFinish(player, how)
	setS(player, "stage", how == "done" and C().stageDone or C().stageSkipped)
	NP.islandSince[player:getGuid()] = nil
	local temple = player:getTown():getTemplePosition()
	player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
	player:teleportTo(temple)
	temple:sendMagicEffect(CONST_ME_TELEPORT)
	if how == "time" then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Your time on the tutorial island is up: here is your kit. " ..
			"Everything the island shows is also in the menu at the top.")
	elseif how == "skipped" then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "You skipped the tutorial.")
	else
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "You finished the tutorial. Good hunting!")
	end
	NP.kitAndWelcome(player, 1000)
	-- the login windows (Daily Reward, patch notes) waited for the island; the client shows them after the welcome
	if ChaosLoginWindows and ChaosLoginWindows.start then
		ChaosLoginWindows.start(player)
	end
end

-- true while the character is on the tutorial island (stations 1..rooms)
function NP.onTutorial(player)
	return NP.inTutorial(stageOf(player))
end

-- called by newplayer.lua's login event; true when the tutorial handled the login
function NP.tutorialLogin(player, first)
	local stage = stageOf(player)
	if NP.inTutorial(stage) then
		if not NP.islandReady() then
			NP.tutorialFinish(player, "skipped")
			return true
		end
		local limit = (T().timeLimitMinutes or 0) * 60
		if limit > 0 and math.max(0, getS(player, "islandUsed")) >= limit then
			NP.tutorialFinish(player, "time")
			return true
		end
		registerEvents(player)
		islandClock(player)
		local L = NP.layout()
		if not NP.onIsland(player:getPosition(), L) then
			player:teleportTo(P(NP.resumeSpot(stage, L)))
		end
		local name = player:getName()
		addEvent(function()
			local p = Player(name)
			if p and NP.inTutorial(stageOf(p)) then
				local s = stageOf(p)
				local _, toast = lessonText(p, s)
				NP.toast(p, toast)
				p:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Tutorial: " .. toast .. " Use the angel statue to read the lesson again.")
				startTask(p, s)
			end
		end, C().welcome.delayMs)
		return true
	end
	if (stage == C().stageDone or stage == C().stageSkipped) and NP.onIsland(player:getPosition()) then
		player:teleportTo(player:getTown():getTemplePosition())
	end
	if first and T().enabled and not NP.isSet(getS(player, "kit")) and stage < 1
			and NP.kitFor(player:getVocation():getId()) and NP.islandReady() then
		return NP.tutorialStart(player)
	end
	return false
end

-- ------------------------------------------------------------------------------------------------ engine hooks
-- station 1: kills
local kill = CreatureEvent("ChaosTutorialKill")
function kill.onKill(creature, target)
	local player = creature and creature:getPlayer()
	if not player or not target or not target:isMonster() or stageOf(player) ~= 1 then
		return true
	end
	if not NP.onIsland(target:getPosition()) then
		return true
	end
	local kills = math.max(0, tonumber(getS(player, "kills")) or 0) + 1
	setS(player, "kills", kills)
	if kills >= T().kills then
		complete(player, 1)
	else
		player:sendTextMessage(MESSAGE_STATUS_SMALL or MESSAGE_EVENT_ADVANCE, string.format("Rats killed: %d / %d", kills, T().kills))
		local pid = player:getId()
		addEvent(function()
			local p = Player(pid)
			if p and stageOf(p) == 1 then
				spawnMonsters()
			end
		end, 2000)
	end
	return true
end
kill:register()

-- modal buttons: Skip tutorial (lesson 1 button 2, or the skip statue's Yes)
local modal = CreatureEvent("ChaosTutorialModal")
function modal.onModalWindow(player, modalWindowId, buttonId, choiceId)
	local t = T()
	if not NP.inTutorial(stageOf(player)) then
		return true
	end
	if (modalWindowId == t.modalBase + 1 and buttonId == 2) or (modalWindowId == t.modalBase + 9 and buttonId == 1) then
		NP.tutorialFinish(player, "skipped")
	elseif modalWindowId == t.modalBase + 1 and buttonId == 1 and stageOf(player) == 1 then
		spawnMonsters()
	end
	return true
end
modal:register()

-- nobody dies on the island: a hit that would kill leaves 1 health and the island heals the character
-- (a death elsewhere during the tutorial is handled by the login: back to the station)
local health = CreatureEvent("ChaosTutorialHealth")
function health.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if primaryType == COMBAT_HEALING or not creature:isPlayer() or not NP.inTutorial(stageOf(creature))
			or not NP.onIsland(creature:getPosition()) then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local total = math.abs(primaryDamage) + (secondaryType ~= COMBAT_HEALING and math.abs(secondaryDamage) or 0)
	local lethal = creature:getHealth() + (creature.getEnergyShield and creature:getEnergyShield() or 0) -- energy shield (patch 0015) after this event
	if total < lethal then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local keep = math.max(0, lethal - 1)
	local cid = creature:getId()
	addEvent(function()
		local p = Player(cid)
		if p then
			Chaos.heal(p, p:getMaxHealth() - p:getHealth())
			p:getPosition():sendMagicEffect(CONST_ME_MAGIC_BLUE)
			p:sendTextMessage(MESSAGE_EVENT_ADVANCE, "The island will not let you die: you are healed. Use your potions and spells in the real world!")
		end
	end, 100)
	return primaryDamage < 0 and -keep or keep, primaryType, 0, secondaryType
end
health:register()

-- station 3: a passive tree save
ChaosPassiveTree = ChaosPassiveTree or {}
ChaosPassiveTree.listeners = ChaosPassiveTree.listeners or {}
if not NP.passiveListener then
	NP.passiveListener = function(player)
		if stageOf(player) == 3 and NP.hasBit(flagsOf(player), 4) and ChaosPassiveTree.hasAllocation
				and ChaosPassiveTree.hasAllocation(player) then
			complete(player, 3)
		end
	end
	table.insert(ChaosPassiveTree.listeners, function(player, bonuses)
		return NP.passiveListener(player, bonuses)
	end)
end

-- station 2: the spellbook was opened (!spells or the client button both end in ChaosSpellbook.sendTo)
local function hookSpellbook()
	local Book = ChaosSpellbook
	if not Book or not Book.sendTo or Book.newPlayerHooked then
		return
	end
	local original = Book.sendTo
	Book.sendTo = function(player, ...)
		if player and stageOf(player) == 2 and not NP.hasBit(flagsOf(player), 1) then
			setFlag(player, 1)
			if spellOf(player) and not NP.hasBit(flagsOf(player), 2) then
				local spell = spellOf(player)
				player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("Now cast %s: say \"%s\".", spell.name, spell.words))
			end
			if NP.spellTaskDone(flagsOf(player), spellOf(player) ~= nil) then
				complete(player, 2)
			end
		end
		return original(player, ...)
	end
	Book.newPlayerHooked = true
end
hookSpellbook()

-- no PvP on the island
local guard = EventCallback
guard.onTargetCombat = function(creature, target)
	if not creature or not target or not target:isPlayer() or not NP.onIsland(target:getPosition()) then
		return RETURNVALUE_NOERROR
	end
	local attacker = creature:isPlayer() and creature or (creature:getMaster() and creature:getMaster():getPlayer())
	if attacker and attacker ~= target then
		return RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER
	end
	return RETURNVALUE_NOERROR
end
guard:register()

local function pushBack(creature, fromPosition, text)
	if text and creature:isPlayer() then
		creature:sendCancelMessage(text)
	end
	creature:teleportTo(fromPosition, true)
end

-- the lesson tile of a station
local marker = MoveEvent()
function marker.onStepIn(creature, item, position, fromPosition)
	local player = creature:getPlayer()
	if not player then
		return true
	end
	local room = NP.roomOf(position)
	if room and NP.inTutorial(stageOf(player)) and room <= stageOf(player) then
		enterStation(player, room)
		if room == 1 and stageOf(player) == 1 then
			spawnMonsters()
		end
	end
	return true
end
marker:type("stepin")
marker:aid(NP.cfg().tutorial.aid.marker)
marker:register()

-- gates between the stations: east only once the station is done; monsters never pass
local gate = MoveEvent()
function gate.onStepIn(creature, item, position, fromPosition)
	local player = creature:getPlayer()
	if not player then
		pushBack(creature, fromPosition)
		return true
	end
	local L = NP.layout()
	local index
	for i, g in ipairs(L.gates) do
		if g.x == position.x and g.y == position.y and g.z == position.z then
			index = i
		end
	end
	local stage = stageOf(player)
	if not index or not NP.inTutorial(stage) or fromPosition.x >= position.x then
		return true -- going back west is always fine
	end
	if not NP.gateOpen(index, doneOf(player)) then
		pushBack(player, fromPosition, "Finish this station first. Use the angel statue to read the lesson again.")
		return true
	end
	if stage <= index then
		setS(player, "stage", NP.stageAfterGate(index, stage))
		local name = player:getName()
		addEvent(function()
			local p = Player(name)
			if p then
				enterStation(p, index + 1)
			end
		end, 300)
	end
	return true
end
gate:type("stepin")
gate:aid(NP.cfg().tutorial.aid.gate)
gate:register()

-- the exit forcefield
local exit = MoveEvent()
function exit.onStepIn(creature, item, position, fromPosition)
	local player = creature:getPlayer()
	if not player then
		pushBack(creature, fromPosition)
		return true
	end
	if not NP.exitOpen(stageOf(player), doneOf(player)) then
		pushBack(player, fromPosition, "Finish the stations first.")
		return true
	end
	NP.tutorialFinish(player, "done")
	return true
end
exit:type("stepin")
exit:aid(NP.cfg().tutorial.aid.exit)
exit:register()

-- the angel statues: read the lesson again
local statue = Action()
function statue.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	local room = NP.roomOf(item:getPosition())
	if room and NP.inTutorial(stageOf(player)) then
		enterStation(player, math.min(room, stageOf(player)))
	end
	return true
end
statue:aid(NP.cfg().tutorial.aid.statue)
statue:register()

-- the goblin statue: skip
local skip = Action()
function skip.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	if NP.inTutorial(stageOf(player)) then
		NP.modal(player, T().modalBase + 9, "Skip the tutorial?",
			"You leave the island at once and get your starter kit at the temple. You cannot come back.",
			{{1, "Skip"}, {2, "Stay"}})
	end
	return true
end
skip:aid(NP.cfg().tutorial.aid.skip)
skip:register()

local skipTalk = {} -- reached from the menu: Info & Services window (commands_ui.lua, id "skiptutorial")
function skipTalk.onSay(player, words, param)
	if not NP.inTutorial(stageOf(player)) then
		player:sendCancelMessage("You are not in the tutorial.")
		return false
	end
	NP.tutorialFinish(player, "skipped")
	return false
end
ChaosCommands.register("skiptutorial", function(player, param) return skipTalk.onSay(player, "", param) end)

local islandLogout = CreatureEvent("ChaosTutorialLogout")
function islandLogout.onLogout(player)
	NP.islandLogout(player)
	return true
end
islandLogout:type("logout")
islandLogout:register()

-- /instances (instance_limits.lua): the characters on the island and their time left (staff view; no area rules)
Chaos.registerInstance("tutorial", {label = "the tutorial island", runs = function()
	local out = {}
	for guid in pairs(NP.islandSince) do
		for _, p in ipairs(Game.getPlayers()) do
			if p:getGuid() == guid then
				out[#out + 1] = {id = p:getName(), what = "station " .. stageOf(p), left = NP.islandLeft(p), players = 1}
			end
		end
	end
	return out
end, close = function(id) -- the character leaves as with "Skip tutorial" (kit, welcome, temple)
	local p = Player(tostring(id))
	if not p or not NP.inTutorial(stageOf(p)) then
		return false, "No character " .. tostring(id) .. " on the tutorial island."
	end
	NP.tutorialFinish(p, "skipped")
	return true, tostring(id) .. " left the tutorial island."
end})

local startup = GlobalEvent("ChaosTutorialStartup")
function startup.onStartup()
	hookSpellbook()
	NP.islandReady()
	return true
end
startup:register()
