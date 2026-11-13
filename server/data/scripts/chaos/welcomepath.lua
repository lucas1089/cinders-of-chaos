-- welcomepath.lua: the welcome path of a new character (O370; rules welcomepath_core.lua, steps and rewards
-- welcomepath_config.lua; docs/CONTENT.md "Welcome path", server/README.md "Welcome path (O370)").
-- A short chain of first steps, one at a time, each with a small reward: cast a spell, slay 20 monsters, wear a new
-- piece of gear, spend the first passive point (level 12), finish a Bounty contract, use an orb at the Crafting Bench
-- (level 20), open Next Goals. The current step shows in the Next Goals tracker (client game_goals, section "Welcome Path"), with a "Skip
-- welcome path" line under it.
--
-- Channel: the Next Goals opcode (ChaosOpcodes.goals = 178; no new opcode). goals.lua is the one handler of 178 and
-- calls in here: "open" -> ChaosWelcomePath.mark(player, "goals"), "tracker" -> the rows go again, "welcomeSkip" ->
-- ChaosWelcomePath.skip(player).
--   server -> client  welcome {title, step, count, rows = [{key, title, progress, target, state, hint, where}]}
--                     (rows = [] hides the section)
-- Facts, read with no edits of the other systems: a spell group cooldown on the character (a cast), a kill event of
-- this module (kills while the kill step is open), the worn items against the starter kit (newplayer_config.lua),
-- the Next Goals own stats and the achievement counters (orbs_used, bounty_done, passive_spent), the level.
-- Once per character: storage block 7101070-7101079 (Chaos.storage.welcomePath). A character first seen above
-- cfg.quietAbove never gets it; one first seen below passes the steps it has already done silently.
-- Assumed engine API (TFS 1.4): CreatureEvent login/logout/kill, GlobalEvent think, Player storage, slots, bank,
-- getCondition(CONDITION_SPELLGROUPCOOLDOWN, CONDITIONID_DEFAULT, group), getInbox. Lua 5.1 / LuaJIT and 5.3.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosWelcomePathCore or not ChaosWelcomePathCore.view then
	dofile("data/scripts/chaos/welcomepath_core.lua")
end

local K = ChaosWelcomePathCore
ChaosWelcomePath = ChaosWelcomePath or {}
local W = ChaosWelcomePath
W.sent = W.sent or {} -- player id -> the signature the client has
W.ready = W.ready or {} -- player id -> true once the first look is done (the sweep only looks at those)

local function C()
	return K.cfg()
end

local function log(text)
	print("[Chaos welcome path] " .. tostring(text))
end

do
	local c = C()
	for _, p in ipairs(c and K.validate(c) or {"welcomepath_config.lua did not load"}) do
		log("welcomepath_config.lua: " .. p)
	end
end

-- O551: the main quest (mainquest.lua) replaces the welcome path in the tracker and imports its state; while it runs this module
-- stays quiet (no rows, no rewards). Off with mainquest_config.lua enabled = false.
local function replaced()
	local q = ChaosMainQuest ~= nil and ChaosMainQuestCore ~= nil and ChaosMainQuestCore.cfg and ChaosMainQuestCore.cfg()
	return q and q.enabled == true or false
end
W.replaced = replaced

local function opcode()
	return (ChaosOpcodes and ChaosOpcodes.goals) or C().opcode
end

local function key(name)
	local s = C().storage
	return s.base + s[name]
end

local function get(player, name)
	return player:getStorageValue(key(name))
end

local function set(player, name, value)
	player:setStorageValue(key(name), value)
end

local function staff(player)
	local g = player:getGroup()
	return g and g:getId() >= (C().staffGroup or 4)
end

local function langOf(player)
	if ChaosFirstHour and ChaosFirstHour.langOf then
		local ok, l = pcall(ChaosFirstHour.langOf, player)
		if ok and l then
			return K.lang(l)
		end
	end
	if Chaos.lang then
		local ok, l = pcall(Chaos.lang, player)
		if ok then
			return K.lang(l)
		end
	end
	return "en"
end

local MSG = MESSAGE_EVENT_ADVANCE or MESSAGE_INFO_DESCR

local function tell(player, text)
	player:sendTextMessage(MSG, text)
end

local function toast(player, text)
	if ChaosOpcodes and ChaosOpcodes.notifications and json then
		player:sendExtendedOpcode(ChaosOpcodes.notifications, json.encode({action = "journey", message = text}))
	end
end

-- ---------------------------------------------------------------- facts
local SPELL_GROUPS = {SPELLGROUP_ATTACK or 1, SPELLGROUP_HEALING or 2, SPELLGROUP_SUPPORT or 3}
-- the equipment slots (TFS: head 1, necklace 2, backpack 3, armor 4, right 5, left 6, legs 7, feet 8, ring 9, ammo 10);
-- the backpack slot is the kit's own bag
local WORN = {1, 2, 4, 5, 6, 7, 8, 9, 10}

local function castSpell(player)
	if not CONDITION_SPELLGROUPCOOLDOWN then
		return false
	end
	for _, g in ipairs(SPELL_GROUPS) do
		if player:getCondition(CONDITION_SPELLGROUPCOOLDOWN, CONDITIONID_DEFAULT, g) then
			return true
		end
	end
	return false
end

local function kitOf(player)
	local NP = ChaosNewPlayer
	if NP and NP.kitFor then
		local ok, kit = pcall(NP.kitFor, player:getVocation():getId())
		if ok then
			return kit
		end
	end
	return nil
end

local function newGear(player)
	local worn = {}
	for _, slot in ipairs(WORN) do
		local item = player:getSlotItem(slot)
		if item then
			worn[#worn + 1] = item:getId()
		end
	end
	return K.gearNew(worn, K.kitSet(kitOf(player)))
end

-- a counter of the Next Goals (own stats) or the achievements; passive_spent is probed too
local function statOf(player, stat)
	local guid = player:getGuid()
	local best = 0
	local G = ChaosGoals
	local gs = G and G.st and G.st[guid]
	if gs and gs.stats then
		best = math.max(best, tonumber(rawget(gs.stats, stat)) or 0)
	end
	local A = ChaosAchievements
	local a = A and A.stats and A.stats[guid]
	if a then
		best = math.max(best, tonumber(a[stat]) or 0)
	end
	if stat == "passive_spent" and best < 1 and ChaosPassiveTree and ChaosPassiveTree.hasAllocation then
		local ok, has = pcall(ChaosPassiveTree.hasAllocation, player)
		if ok and has then
			best = 1
		end
	end
	return best
end

-- the facts of step i (only what that step needs is looked at)
function W.facts(player, i)
	local step = C().steps[i]
	local f = {level = player:getLevel(), kills = math.max(0, get(player, "kills")), flags = math.max(0, get(player, "flags")),
		stats = {}}
	if not step then
		return f
	end
	local need = K.needs(step)
	if need.spell then
		f.spell = castSpell(player)
	end
	if need.gear then
		f.gear = newGear(player)
	end
	if step.check == "stat" then
		f.stats[step.stat] = statOf(player, step.stat)
	end
	return f
end

-- ---------------------------------------------------------------- the tracker rows
local function resolveWhere(player, where, lang)
	if type(where) ~= "table" then
		return nil
	end
	local w = {}
	for k, v in pairs(where) do
		w[k] = v
	end
	if (w.k == "hunts" or w.k == "npc") and ChaosGoals and ChaosGoals.resolver then
		local ok, pos, label = pcall(function() return ChaosGoals.resolver(player, lang)(w) end)
		if ok and pos then
			w.pos, w.label = pos, label
		end
	end
	return w
end

function W.view(player)
	local lang = langOf(player)
	local i = get(player, "step")
	local v = K.view(C(), get(player, "state"), i, W.facts(player, i), lang)
	return v, lang
end

-- sends the rows when they differ from what the client has (force: always)
function W.refresh(player, force)
	local pid = player:getId()
	local v, lang = W.view(player)
	local sig = K.sig(v, lang)
	if not force and W.sent[pid] == sig then
		return false
	end
	local first = W.sent[pid] == nil
	W.sent[pid] = sig
	if sig == "hidden" and first and not force then
		return false -- never shown: the client's section is hidden already
	end
	if v.rows[1] then
		v.rows[1].where = resolveWhere(player, v.rows[1].where, lang)
	end
	Chaos.send(player, opcode(), "welcome", v)
	return true
end

-- ---------------------------------------------------------------- rewards
local function roleOf(player)
	local kit = kitOf(player)
	return kit and kit.role or "default"
end

local function itemName(id)
	local ok, name = pcall(function()
		local it = ItemType(id)
		return it and it:getName() or nil
	end)
	return ok and name and name ~= "" and name or ("item " .. tostring(id))
end

local function giveItems(player, id, count)
	local given = Chaos.giveItem and Chaos.giveItem(player, id, count) or 0
	local left = count - (tonumber(given) or 0)
	if left > 0 then
		local ok, inbox = pcall(function() return player:getInbox() end)
		if ok and inbox then
			inbox:addItem(id, left)
		end
	end
end

function W.reward(player, step, lang)
	local rw = K.rewardOf(C(), step, roleOf(player))
	if rw.gold > 0 then
		player:setBankBalance(player:getBankBalance() + rw.gold)
	end
	for _, it in ipairs(rw.items) do
		giveItems(player, it[1], it[2])
	end
	return K.rewardText(C(), rw, lang, itemName)
end

-- ---------------------------------------------------------------- progress
local function announceStep(player, i, lang)
	local step = C().steps[i]
	if step then
		tell(player, string.format(K.text(C().texts.next, lang), K.text(step.title, lang), K.text(step.hint, lang)))
	end
end

-- the current step done: the next one (the step first: a crash after it loses the reward rather than paying twice)
function W.advance(player)
	local c = C()
	local i = get(player, "step")
	local step = c.steps[i]
	if not step then
		return false
	end
	local lang = langOf(player)
	set(player, "step", i + 1)
	set(player, "kills", 0)
	local got = W.reward(player, step, lang)
	tell(player, string.format(K.text(c.texts.stepDone, lang), i, #c.steps, K.text(step.title, lang), got))
	toast(player, string.format("%s %d/%d: %s", K.text(c.texts.title, lang), i, #c.steps, K.text(step.title, lang)))
	if i >= #c.steps then
		set(player, "state", c.states.done)
		tell(player, K.text(c.texts.finished, lang))
	else
		announceStep(player, i + 1, lang)
	end
	return true
end

-- one look at a character on the path: a done step moves on (one per look), the rows follow
function W.check(player)
	local c = C()
	if not c.enabled or get(player, "state") ~= c.states.active then
		W.ready[player:getId()] = nil -- off the path: the sweep stops looking (a skip or the end sent the empty rows)
		return
	end
	local i = get(player, "step")
	if c.steps[i] and K.isDone(c.steps[i], W.facts(player, i)) then
		W.advance(player)
	end
	W.refresh(player)
end

-- the character played before this module saw it: above the start level, or its kit is older than playedAfterSec
function W.played(player)
	local c = C()
	if player:getLevel() > (c.startLevel or 8) then
		return true
	end
	local base = Chaos.storage and Chaos.storage.newPlayer
	local kitAt = base and player:getStorageValue(base) or -1
	return kitAt > 0 and os.time() - kitAt > (c.playedAfterSec or 3600)
end

-- the first look (after the counters loaded): start, stay quiet, or carry on
function W.firstLook(player)
	local c = C()
	local pid = player:getId()
	W.ready[pid] = true
	if not c.enabled or staff(player) or replaced() then
		return
	end
	local state = get(player, "state")
	if state == c.states.fresh or state < 0 then
		state = K.firstState(c, player:getLevel())
		set(player, "state", state)
		set(player, "kills", 0)
		set(player, "flags", 0)
		if state ~= c.states.active then
			return
		end
		-- the steps a character below quietAbove has already done pass silently
		local start = K.skipDone(c, 1, function(i) return W.facts(player, i) end, W.played(player))
		set(player, "step", start)
		if start > #c.steps then
			set(player, "state", c.states.done)
			return
		end
		local lang = langOf(player)
		tell(player, K.text(c.texts.start, lang))
		announceStep(player, start, lang)
	end
	W.refresh(player, true)
end

-- a fact this module cannot read by itself: "goals" (the Next Goals window was opened; goals.lua "open")
function W.mark(player, what)
	if what == "goals" and get(player, "state") >= 0 then
		set(player, "flags", K.setBit(get(player, "flags"), K.FLAG_GOALS))
	end
end

-- the client's "Skip welcome path" (goals.lua "welcomeSkip")
function W.skip(player)
	local c = C()
	if get(player, "state") ~= c.states.active then
		return false
	end
	set(player, "state", c.states.skipped)
	tell(player, K.text(c.texts.skipped, langOf(player)))
	W.refresh(player, true)
	return true
end

-- the client asked for its tracker again: the rows go out at the next look
function W.forget(player)
	W.sent[player:getId()] = nil
end

-- ---------------------------------------------------------------- events
if CreatureEvent then
	local login = CreatureEvent("ChaosWelcomePathLogin")
	function login.onLogin(player)
		local pid = player:getId()
		W.sent[pid], W.ready[pid] = nil, nil
		if not C() or not C().enabled or replaced() then
			return true
		end
		player:registerEvent("ChaosWelcomePathKill")
		player:registerEvent("ChaosWelcomePathLogout")
		addEvent(function()
			local p = Player(pid)
			if p then
				local ok, err = pcall(W.firstLook, p)
				if not ok then
					log("first look: " .. tostring(err))
				end
			end
		end, C().firstLookMs or 12000)
		return true
	end
	login:type("login")
	login:register()

	local logout = CreatureEvent("ChaosWelcomePathLogout")
	function logout.onLogout(player)
		local pid = player:getId()
		W.sent[pid], W.ready[pid] = nil, nil
		return true
	end
	logout:type("logout")
	logout:register()

	local kill = CreatureEvent("ChaosWelcomePathKill")
	function kill.onKill(player, target)
		local c = C()
		if not c or not c.enabled or not player:isPlayer() or not target or not target:isMonster() or target:getMaster() then
			return true
		end
		if get(player, "state") ~= c.states.active then
			return true
		end
		local step = c.steps[get(player, "step")]
		if step and step.check == "kills" then
			set(player, "kills", math.max(0, get(player, "kills")) + 1)
		end
		return true
	end
	kill:type("kill")
	kill:register()
end

if GlobalEvent then
	local think = GlobalEvent("ChaosWelcomePathThink")
	function think.onThink(interval)
		if not C() or not C().enabled or replaced() then
			return true
		end
		for _, player in ipairs(Game.getPlayers()) do
			if W.ready[player:getId()] then
				local ok, err = pcall(W.check, player)
				if not ok then
					log("check: " .. tostring(err))
				end
			end
		end
		return true
	end
	think:interval(C() and C().sweepMs or 1000)
	think:register()
end
