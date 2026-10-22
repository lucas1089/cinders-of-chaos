-- tales.lua: the engine side of the tales (tales_config.lua, tales_core.lua; docs/CONTENT.md "Tales").
-- Archivist Maelis (data/npc/Archivist Maelis.xml) is placed next to the temples at startup and opens the list of
-- tales (a modal window); the answers arrive here (CreatureEvent "ChaosTalesModal") and are checked again: accept and
-- turn in only next to her. Kills count for the killer and the party members within cfg.partyRange on the same floor
-- (CreatureEvent "ChaosTalesKill"). Visit steps: the characters with one in progress are on a watch list (login,
-- accept, every step change) and GlobalEvent "ChaosTalesVisit" checks their position every cfg.visitMs. Talk steps
-- are done in the named NPC's own script (data/npc/scripts/chaos_faction_npc.lua, ChaosTalesCore.talkTo).
-- Rewards: experience (measured at most at the top of the tale's band), gold to the bank, items (the inbox when the
-- backpack is full), faction reputation (ChaosFactions.gain, when loaded) and a written lore book. No spoken command
-- (the project's rule, tests/commands_ui_test.lua): the progress is in the Archivist's window and in the messages.
-- Assumed engine API (TFS 1.4): CreatureEvent kill/modalwindow/login/logout, GlobalEvent startup/think, ModalWindow,
-- Game.createNpc, Town, Tile, Player storage/bank/items, Item:setAttribute. Lua 5.1 / LuaJIT and 5.3.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosTalesCore or not ChaosTalesCore.taleView then
	dofile("data/scripts/chaos/tales_core.lua")
end
if not ChaosNpcPlace then
	dofile("data/scripts/chaos/npc_place.lua")
end

local M = ChaosTalesCore
ChaosTales = ChaosTales or {}
local T = ChaosTales
T.open = T.open or {} -- player id -> the key of the tale shown in its last tale window
T.credited = T.credited or {} -- monster id -> {at = os.time, [player id] = true}: killer and most damage both fire onKill
T.watch = T.watch or {} -- player id -> true while a visit step is in progress

local function C()
	return M.cfg()
end

local function log(msg)
	print("[Chaos tales] " .. tostring(msg))
end

local function getS(player, key)
	return player:getStorageValue(key)
end

local function stateFn(player)
	return function(t)
		return getS(player, M.stateKey(t))
	end
end

-- the hunting marks (data/chaos_poi.lua, poi.lua) at the places the character's visit steps name: put on its map,
-- like the first hour's reveals (firsthour.lua)
function T.revealPlaces(player)
	local P = ChaosPoi
	if not P or not P.all or not P.key or not P.seen then
		return 0
	end
	local set = P.seen[player:getGuid()]
	if not set then
		return 0
	end
	local list = {}
	for _, t in ipairs(M.tales()) do
		local step = M.current(t, getS(player, M.stateKey(t)), "visit")
		if step then
			for _, m in ipairs(P.all) do
				if M.atPlace(step, m) and not set[P.key(m)] then
					set[P.key(m)] = true
					list[#list + 1] = {k = m.k, x = m.x, y = m.y, z = m.z, n = m.n}
				end
			end
		end
	end
	if #list > 0 then
		if P.dirty then
			P.dirty[player:getGuid()] = true
		end
		if P.watch and P.watch[player:getId()] and Chaos.send then
			Chaos.send(player, ChaosOpcodes.mapMarkers or 153, "reveal", {marks = list})
		end
	end
	return #list
end

-- keep the character on the visit watch list while one of its tales waits for a visit; a new wait shows the place
function T.rewatch(player)
	local id = player:getId()
	local was = T.watch[id]
	T.watch[id] = M.visiting(stateFn(player)) or nil
	if T.watch[id] and not was then
		pcall(T.revealPlaces, player)
	end
end

function T.langOf(player)
	local hooked
	if Chaos.lang then
		local ok, l = pcall(Chaos.lang, player)
		hooked = ok and l or nil
	end
	return M.lang(getS(player, M.langKey()), hooked)
end

local function msg(player, text)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE or MESSAGE_INFO_DESCR, text)
end

local function info(player, text)
	player:sendTextMessage(MESSAGE_STATUS_CONSOLE_ORANGE or MESSAGE_INFO_DESCR, text)
end

local function toast(player, text)
	if ChaosOpcodes and ChaosOpcodes.notifications and json then
		player:sendExtendedOpcode(ChaosOpcodes.notifications, json.encode({action = "newplayer", message = text}))
	end
end

-- ======================================================================== the windows
local function sendModal(player, id, title, text, buttons, choices)
	if not ModalWindow then
		return false
	end
	local w = ModalWindow(id, title, text)
	for i, c in ipairs(choices or {}) do
		w:addChoice(i, c)
	end
	for _, b in ipairs(buttons) do
		w:addButton(b[1], b[2])
	end
	w:setDefaultEnterButton(buttons[1][1])
	w:setDefaultEscapeButton(buttons[#buttons][1])
	w:sendToPlayer(player)
	return true
end

-- the list of tales (also opened by the NPC from its own Lua state, with the same core function)
function T.sendList(player)
	local lang = T.langOf(player)
	local v = M.listView(player:getLevel(), function(t) return getS(player, M.stateKey(t)) end, lang)
	local ui = C().ui
	local choices = {}
	for _, c in ipairs(v.choices) do
		choices[#choices + 1] = c.label
	end
	if #choices == 0 then
		return sendModal(player, C().modal.list, v.title, v.text, {{2, M.t(ui.close, lang)}})
	end
	return sendModal(player, C().modal.list, v.title, v.text, {{1, M.t(ui.read, lang)}, {2, M.t(ui.close, lang)}}, choices)
end

function T.sendTale(player, t)
	local lang = T.langOf(player)
	local v = M.taleView(t, getS(player, M.stateKey(t)), getS(player, M.countKey(t)), lang, player:getLevel(),
		stateFn(player))
	local ui = C().ui
	local buttons = {}
	for _, b in ipairs(v.buttons) do
		buttons[#buttons + 1] = b == "accept" and {1, M.t(ui.accept, lang)} or {3, M.t(ui.turnin, lang)}
	end
	buttons[#buttons + 1] = {2, M.t(ui.close, lang)}
	T.open[player:getId()] = t.key
	return sendModal(player, C().modal.tale, v.title, v.text, buttons)
end

-- ======================================================================== the Archivist
local function npcNear(player)
	local name = C().npc.name:lower()
	local r = C().npc.range or 6
	for _, c in ipairs(Game.getSpectators(player:getPosition(), false, false, r, r, r, r) or {}) do
		if c:isNpc() and c:getName():lower() == name then
			return true
		end
	end
	return false
end

local function placeNpc(pos)
	local name = C().npc.name
	for _, c in ipairs(Game.getSpectators(pos, false, false, 8, 8, 8, 8) or {}) do
		if c:isNpc() and c:getName():lower() == name:lower() then
			return c
		end
	end
	return Game.createNpc(name, pos)
end

function T.placeNpcs()
	local n = C().npc
	local placed = 0
	for _, p in ipairs(n.positions or {}) do
		if placeNpc(Position(p.x or p[1], p.y or p[2], p.z or p[3])) then
			placed = placed + 1
		end
	end
	if #(n.positions or {}) == 0 then
		for _, townId in ipairs(n.townIds or {}) do
			local town = Town(townId)
			local temple = town and town:getTemplePosition()
			-- npc_place.lua: the offsets first, then any reachable free tile, away from the other NPCs
			local okp, npc = pcall(function() return temple and ChaosNpcPlace.place(n.name, temple, n.offsets, n.place) end)
			if okp and npc then
				placed = placed + 1
			else
				log("could not place " .. n.name .. " in town " .. tostring(townId)
					.. " (no free tile near the temple, or data/npc/" .. n.name .. ".xml is missing)")
			end
		end
	end
	return placed
end

-- ======================================================================== rewards
local function giveItem(player, id, count)
	local ok, it = pcall(function() return player:addItem(id, count, false) end)
	if ok and it then
		return it
	end
	local okI, inbox = pcall(function() return player:getInbox() end)
	if okI and inbox then
		return inbox:addItem(id, count)
	end
	return nil
end

function T.giveBook(player, loreId, lang)
	local title, text = M.book(loreId, lang)
	if not title then
		return false
	end
	local book = giveItem(player, C().bookItem, 1)
	if book and book.setAttribute and ITEM_ATTRIBUTE_TEXT then
		book:setAttribute(ITEM_ATTRIBUTE_TEXT, text)
		if ITEM_ATTRIBUTE_WRITER then
			book:setAttribute(ITEM_ATTRIBUTE_WRITER, C().npc.name)
		end
		if ITEM_ATTRIBUTE_DESCRIPTION then
			book:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, title)
		end
	end
	return book ~= nil
end

function T.reward(player, t)
	local lang = T.langOf(player)
	local r = t.rewards
	local xp = M.taleXp(t, player:getLevel())
	if xp > 0 then
		player:addExperience(xp, true)
	end
	if (r.gold or 0) > 0 then
		player:setBankBalance(player:getBankBalance() + r.gold)
	end
	for _, it in ipairs(r.items or {}) do
		giveItem(player, it.id, it.count)
	end
	if (r.rep or 0) > 0 and t.faction and ChaosFactions and ChaosFactions.gain then
		pcall(ChaosFactions.gain, player, t.faction, r.rep, "tale")
	end
	if r.book then
		T.giveBook(player, r.book, lang)
	end
	msg(player, string.format(M.t(C().ui.finished, lang), M.t(t.name, lang)) .. " " .. table.concat(M.rewardLines(t, lang,
		player:getLevel()), ", ") .. ".")
	if t.outro then
		info(player, C().npc.name .. ": " .. M.t(t.outro, lang))
	end
	toast(player, string.format(M.t(C().ui.finished, lang), M.t(t.name, lang)))
end

-- ======================================================================== accept, turn in
function T.accept(player, t)
	local lang = T.langOf(player)
	if not npcNear(player) then
		info(player, M.t(C().ui.tooFar, lang))
		return false
	end
	local ok, state = M.accept(t, getS(player, M.stateKey(t)), player:getLevel(), stateFn(player))
	if not ok then
		return false
	end
	player:setStorageValue(M.stateKey(t), state)
	player:setStorageValue(M.countKey(t), 0)
	msg(player, string.format(M.t(C().ui.accepted, lang), M.t(t.name, lang)))
	T.rewatch(player)
	return true
end

-- a field step is done: the message names the next step (another field step) or sends the character back
function T.stepMessage(player, t, newState, lang)
	lang = lang or T.langOf(player)
	local nextStep = t.steps[M.state(t, newState)]
	local text
	if nextStep and M.FIELD[nextStep.kind] then
		text = string.format(M.t(C().ui.stepNext, lang), M.t(t.name, lang), M.t(nextStep.text, lang))
	else
		text = string.format(M.t(C().ui.stepDone, lang), M.t(t.name, lang))
	end
	msg(player, text)
	toast(player, text)
end

function T.turnIn(player, t)
	local lang = T.langOf(player)
	if not npcNear(player) then
		info(player, M.t(C().ui.tooFar, lang))
		return false
	end
	local state = getS(player, M.stateKey(t))
	local ok, a, b, c = M.turnIn(t, state, getS(player, M.countKey(t)), function(id) return player:getItemCount(id) end)
	if not ok then
		if a == "missing" then
			info(player, string.format(M.t(C().ui.missing, lang), c, b.name))
		else
			local step = t.steps[M.state(t, state)]
			info(player, string.format(M.t(C().ui.notYet, lang), step and M.t(step.text, lang) or ""))
		end
		return false
	end
	for _, it in ipairs(b) do
		if not player:removeItem(it[1], it[2]) then
			info(player, string.format(M.t(C().ui.missing, lang), it[2], tostring(it[1])))
			return false
		end
	end
	player:setStorageValue(M.stateKey(t), a)
	player:setStorageValue(M.countKey(t), 0)
	T.rewatch(player)
	if c then
		T.reward(player, t)
	else
		T.sendTale(player, t)
	end
	return true
end

-- ======================================================================== kills
function T.credit(player, typeName, shownName)
	local lang
	for _, t in ipairs(M.tales()) do
		local state = getS(player, M.stateKey(t))
		local count = getS(player, M.countKey(t))
		local ns, nc, ev = M.addKill(t, state, count, typeName, shownName)
		if ev then
			lang = lang or T.langOf(player)
			player:setStorageValue(M.stateKey(t), ns)
			player:setStorageValue(M.countKey(t), nc)
			local step = t.steps[M.state(t, state)]
			if ev == "step" then
				T.stepMessage(player, t, ns, lang)
				T.rewatch(player)
			else
				info(player, string.format(M.t(C().ui.progress, lang), M.t(t.name, lang), nc, step.count))
			end
		end
	end
end

local function playerOf(creature)
	if not creature then
		return nil
	end
	if creature:isPlayer() then
		return creature
	end
	local master = creature:getMaster()
	return master and master:isPlayer() and master or nil
end

local kill = CreatureEvent("ChaosTalesKill")
function kill.onKill(creature, target)
	local player = playerOf(creature)
	if not C().enabled or not player or not target or not target:isMonster() or target:getMaster() then
		return true
	end
	local id, now = target:getId(), os.time()
	local done = T.credited[id]
	if not done or now - done.at > 5 then
		done = {at = now}
		T.credited[id] = done
	end
	local ok, err = pcall(function()
		local typeName = Chaos.monsterTypeName and Chaos.monsterTypeName(target) or target:getName()
		local shown = target:getName()
		local list, seen = {}, {}
		if not done[player:getId()] then
			list[1], seen[player:getId()] = player, true
		end
		local party = player:getParty()
		if party then
			local members = party:getMembers() or {}
			members[#members + 1] = party:getLeader()
			local pos, r = target:getPosition(), C().partyRange or 30
			for _, m in ipairs(members) do
				if m and not seen[m:getId()] and not done[m:getId()] then
					local p = m:getPosition()
					if p.z == pos.z and math.abs(p.x - pos.x) <= r and math.abs(p.y - pos.y) <= r then
						seen[m:getId()] = true
						list[#list + 1] = m
					end
				end
			end
		end
		for _, p in ipairs(list) do
			done[p:getId()] = true
			T.credit(p, typeName, shown)
		end
	end)
	if not ok then
		log("kill: " .. tostring(err))
	end
	-- forget old credits now and then
	if (id % 64) == 0 then
		for k, v in pairs(T.credited) do
			if now - v.at > 60 then
				T.credited[k] = nil
			end
		end
	end
	return true
end
kill:register()

-- ======================================================================== modal answers
local modal = CreatureEvent("ChaosTalesModal")
function modal.onModalWindow(player, modalWindowId, buttonId, choiceId)
	local m = C().modal
	if modalWindowId == m.list then
		if buttonId ~= 1 then
			return true
		end
		local v = M.listView(player:getLevel(), function(t) return getS(player, M.stateKey(t)) end, T.langOf(player))
		local c = v.choices[choiceId]
		local t = c and M.tale(c.key)
		if t then
			T.sendTale(player, t)
		end
	elseif modalWindowId == m.tale then
		local t = M.tale(T.open[player:getId()] or "")
		if not t then
			return true
		end
		if buttonId == 1 then
			if T.accept(player, t) then
				T.sendTale(player, t)
			end
		elseif buttonId == 3 then
			T.turnIn(player, t)
		end
	end
	return true
end
modal:register()

-- ======================================================================== visits
-- one check of a character on the watch list: every tale whose visit step it stands at moves on
function T.checkVisits(player)
	local pos = player:getPosition()
	local lang, moved
	for _, t in ipairs(M.tales()) do
		local state = getS(player, M.stateKey(t))
		local ns, ev = M.visit(t, state, pos)
		if ev then
			lang = lang or T.langOf(player)
			player:setStorageValue(M.stateKey(t), ns)
			player:setStorageValue(M.countKey(t), 0)
			T.stepMessage(player, t, ns, lang)
			moved = true
		end
	end
	T.rewatch(player)
	if moved and T.watch[player:getId()] then
		pcall(T.revealPlaces, player) -- a visit right after a visit
	end
end

local visits = GlobalEvent("ChaosTalesVisit")
function visits.onThink()
	if not C().enabled then
		return true
	end
	-- now and then every online character: a talk step done in an NPC's own Lua state may have started a visit wait
	T.ticks = (T.ticks or 0) + 1
	if T.ticks % (C().visitSweep or 10) == 0 and Game.getPlayers then
		for _, p in ipairs(Game.getPlayers() or {}) do
			pcall(T.rewatch, p)
		end
	end
	for pid in pairs(T.watch) do
		local player = Player and Player(pid)
		if not player then
			T.watch[pid] = nil
		else
			local ok, err = pcall(T.checkVisits, player)
			if not ok then
				T.watch[pid] = nil
				log("visit: " .. tostring(err))
			end
		end
	end
	return true
end
if visits.interval then
	visits:interval(C().visitMs or 3000)
end
visits:register()

-- ======================================================================== login, logout, startup
local login = CreatureEvent("ChaosTalesLogin")
function login.onLogin(player)
	player:registerEvent("ChaosTalesKill")
	player:registerEvent("ChaosTalesModal")
	player:registerEvent("ChaosTalesLogout")
	-- a talk step done in an NPC's own Lua state may have ended a visit wait, or started one
	pcall(T.rewatch, player)
	return true
end
login:register()

local logout = CreatureEvent("ChaosTalesLogout")
function logout.onLogout(player)
	T.watch[player:getId()] = nil
	T.open[player:getId()] = nil
	return true
end
logout:register()

local startup = GlobalEvent("ChaosTalesStartup")
function startup.onStartup()
	for _, p in ipairs(M.problems()) do
		log("config: " .. p)
	end
	if C().enabled and C().npc.spawn then
		-- after the Ascendant Oracle and the Keeper of Trials (1 s), so they keep their tiles
		addEvent(function()
			log(T.placeNpcs() .. " " .. C().npc.name .. " placed")
		end, 2500)
	end
	return true
end
startup:register()
