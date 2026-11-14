-- mainquest.lua: the main quest "The Ember Oath" (O551; rules mainquest_core.lua, steps, texts and rewards mainquest_config.lua;
-- server/README.md "Main quest (O551)"; the pt-BR script docs/ROTEIRO_QUEST_PRINCIPAL.md). A walk for a new character from level 8
-- to 500, one step at a time, each step teaching one system: hunt a named monster, collect a quest drop, walk to a place, bring
-- the drops to Warden Ysolde, use a window or a system, mind the resistance penalty. It REPLACES the welcome path (welcomepath.lua,
-- O370: its state is imported at the first look) in the Next Goals tracker, on the same channel (goals opcode 178, no new opcode).
--
-- Channel (goals.lua is the one handler of 178 and calls in here):
--   client -> server  mqOpen (the whole quest) | mqSkip {scope = "quest" | "chapter"} | mqGo {step} (the Go button: opens the
--                     window; for the steps that only ask to see something it also marks the step's flags) | tracker | welcomeSkip
--   server -> client  welcome {title, step, count, chapter, chapterName, rows = [{key, title, progress, target, state, hint, where,
--                     detail}]} (rows = [] hides the section) | mq {state, step, chapters, steps, epilogue} (chunked)
-- Facts, read with no edits of the other systems: the achievement counters and Next Goals own stats, the welcome path's spell and
-- gear probes, the character's position (visit steps), the defence sheet (ChaosPlayerDefence.sheet) and the flags the hooks set
-- (ChaosMainQuest.emit(player, key); mainquest_config.lua `flags`). Kills of a step are counted in its own storage. A quest drop
-- is a real item (O553): a stock item made a quest item by custom attributes (the lock of src-patch 0009 among them), put into the
-- loot bag of the kill for the one who owns the bag, else into the backpack; the step counts the ones the character holds and the
-- bring step lets Warden Ysolde take them. A kill counts for the killer and for the party members around (mainquest_core.lua
-- credited), each rolling the drop for itself. A character mid-step before O553 has its old counter honoured once (W.migrate).
-- Storage: block 7101110-7101139 (Chaos.storage.mainQuest). Once per character. Staff walk no quest.
-- Assumed engine API (TFS 1.4): CreatureEvent login/logout/kill, GlobalEvent think, Player storage, slots, bank, getInbox, getCondition.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosMainQuestCore or not ChaosMainQuestCore.view then
	dofile("data/scripts/chaos/mainquest_core.lua")
end

local K = ChaosMainQuestCore
ChaosMainQuest = ChaosMainQuest or {}
local W = ChaosMainQuest
W.sent = W.sent or {} -- player id -> the signature the client has
W.ready = W.ready or {} -- player id -> true once the first look is done
W.sweep = W.sweep or 0

local function C()
	return K.cfg()
end

local function log(text)
	print("[Chaos main quest] " .. tostring(text))
end

do
	local c = C()
	for _, p in ipairs(c and K.validate(c) or {"mainquest_config.lua did not load"}) do
		log("mainquest_config.lua: " .. p)
	end
end

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

-- the step index, with the step the real items rule opened on (a legacy step: M.legacy in the core)
local function setStep(player, i)
	set(player, "step", i)
	set(player, "items", i)
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

-- ---------------------------------------------------------------- configs of the other systems (the numbers of the texts)
local other = {}
local function load(path)
	if other[path] == nil then
		local ok, t = pcall(dofile, path)
		other[path] = ok and type(t) == "table" and t or false
	end
	return other[path] or nil
end

local function playerDefenceCfg()
	return load("data/scripts/chaos/player_defence_config.lua")
end

local function vars(lang)
	return K.vars(C(), playerDefenceCfg(), load("data/scripts/chaos/defence_config.lua"),
		load("data/scripts/chaos/gentledeath_config.lua"), lang)
end
W.vars = vars

-- ---------------------------------------------------------------- facts
local SPELL_GROUPS = {SPELLGROUP_ATTACK or 1, SPELLGROUP_HEALING or 2, SPELLGROUP_SUPPORT or 3}
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
	local WP = ChaosWelcomePathCore
	if not (WP and WP.gearNew) then
		pcall(dofile, "data/scripts/chaos/welcomepath_core.lua")
		WP = ChaosWelcomePathCore
	end
	local worn = {}
	for _, slot in ipairs(WORN) do
		local item = player:getSlotItem(slot)
		if item then
			worn[#worn + 1] = item:getId()
		end
	end
	return WP and WP.gearNew(worn, WP.kitSet(kitOf(player))) or false
end

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

-- the storages of other systems a `storage` condition names, and the flags read from them
local function storageKey(name)
	if name == "spark" then
		local e = load("data/scripts/chaos/embercache_config.lua")
		return e and e.storage and e.storage.base + e.storage.spark or nil
	elseif name == "weekly" then
		local e = load("data/scripts/chaos/weeklychest_config.lua")
		return e and e.storage and e.storage.base + e.storage.done or nil
	end
	return nil
end

local function autolootSet(player)
	local base = Chaos.storage and Chaos.storage.autolootBase or 80000
	for n = 0, 9 do
		if player:getStorageValue(base + n) > 0 then
			return true
		end
	end
	return false
end

local function near(player, cond)
	local p = player:getPosition()
	local t = cond.pos
	return p.z == t.z and math.max(math.abs(p.x - t.x), math.abs(p.y - t.y)) <= cond.radius
end

local function flagsOf(player)
	local c = C()
	local f = {}
	local masks = {flags = math.max(0, get(player, "flags")), flags2 = math.max(0, get(player, "flags2"))}
	local function look(k)
		local name, bit = K.flagPlace(c, k)
		f[k] = name and K.hasBit(masks[name], bit) or false
	end
	look("talk")
	for _, k in ipairs(c.flags) do
		look(k)
	end
	return f
end

-- the facts of step i (only what that step needs is looked at)
function W.facts(player, i)
	local c = C()
	local step = c.steps[i]
	local pd = playerDefenceCfg()
	local f = {level = player:getLevel(), count = math.max(0, get(player, "count")), flags = flagsOf(player), stats = {},
		storage = {}, marks = pd and pd.penalty and pd.penalty.marks or {}, safeMin = (c.resist or {}).safeMin or 0}
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
	for _, cond in ipairs(step.conds) do
		if cond.c == "stat" then
			f.stats[cond.stat] = statOf(player, cond.stat)
		elseif cond.c == "storage" then
			local k = storageKey(cond.key)
			f.storage[cond.key] = k and player:getStorageValue(k) or 0
		elseif cond.c == "visit" then
			f.visit = near(player, cond)
		elseif cond.c == "resist" and ChaosPlayerDefence and ChaosPlayerDefence.sheet then
			local ok, sheet = pcall(ChaosPlayerDefence.sheet, player)
			f.sheet = ok and sheet or nil
		elseif cond.c == "flag" and cond.key == "autoloot" and not f.flags.autoloot then
			f.flags.autoloot = autolootSet(player)
		elseif cond.c == "flag" and cond.key == "weekly" and not f.flags.weekly then
			local k = storageKey("weekly")
			f.flags.weekly = k and player:getStorageValue(k) > 0 or false
		end
	end
	f.boss = get(player, "won") == 1
	-- a drop step, or the bring step of one: what the character holds (a legacy step counts its old counter, W.migrate)
	local rule = K.killRule(c, i)
	if rule and rule.cond.item and not K.legacy(i, get(player, "items")) then
		f.held = K.heldCount(c, player, rule.step.key)
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
	if (w.k == "hunts" or w.k == "npc" or w.k == "room") and ChaosGoals and ChaosGoals.resolver then
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
	local v = K.view(C(), get(player, "state"), i, W.facts(player, i), lang, vars(lang))
	return v, lang
end

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
		return false
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

local function income()
	local e = load(C().reward.incomeFrom)
	return e and e.income or {{8, 21000}}
end

function W.reward(player, step, lang)
	local rw = K.rewardOf(C(), income(), step)
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
		local v = vars(lang)
		tell(player, string.format(K.text(C().texts.next, lang), K.fill(K.text(step.title, lang), v), K.fill(K.text(step.hint, lang), v)))
		local ch = C().chapters[step.ch]
		local prev = C().steps[i - 1]
		if ch and (not prev or prev.ch ~= step.ch) then
			tell(player, string.format(K.text(C().texts.chapter, lang), tostring(ch.n), K.text(ch.name, lang)) .. ": " .. K.text(ch.intro, lang))
		end
	end
end

local function clearStepState(player)
	set(player, "count", 0)
	set(player, "pity", 0)
	local name, bit = K.flagPlace(C(), "talk")
	set(player, name, K.clearBit(math.max(0, get(player, name)), bit))
end

-- ---------------------------------------------------------------- the quest items (O553)
local NOERR = RETURNVALUE_NOERROR or 0

-- the items of the step that was just done go with it: a drop step no bring step takes (the Vigil takes them) or what is left
-- after a bring step (a lost item that fell again: the extras)
function W.settleItems(player, i, lang)
	local c = C()
	local rule = K.killRule(c, i)
	if not rule or not rule.cond.item then
		return
	end
	if rule.mode == "drop" and not K.bringIndex(c, i) then
		local n = K.takeQuestItems(c, player, rule.step.key)
		if n > 0 then
			tell(player, string.format(K.text(c.texts.takenAuto, lang), n, K.text(rule.cond.item, lang)))
		end
	elseif rule.mode == "refill" then
		K.takeQuestItems(c, player, rule.step.key)
	end
end

-- one quest item into the world of a character: the loot bag of the kill when the character owns it, else the backpack, else the
-- inbox. The item is created and marked first, then placed (a plain copy of the stock id never takes it into its stack).
-- Returns "bag" | "pack" | "inbox" | nil
function W.giveQuestItem(player, step, cond, corpse, lang)
	local c = C()
	local item = Game.createItem(cond.itemId, 1)
	if not item then
		return nil
	end
	K.markItem(c, item, step, cond, player, lang)
	local where
	if corpse and corpse.addItemEx then
		local okO, owner = pcall(function() return corpse:getCorpseOwner() end)
		if okO and owner == player:getId() then
			local okA, ret = pcall(function() return corpse:addItemEx(item) end)
			if okA and ret == NOERR then
				where = "bag"
			end
		end
	end
	if not where and player:addItemEx(item, false) == NOERR then
		where = "pack"
	end
	if not where then
		local okI, inbox = pcall(function() return player:getInbox() end)
		if okI and inbox and inbox:addItemEx(item, INDEX_WHEREEVER or -1, FLAG_NOLIMIT or 1) == NOERR then
			where = "inbox"
		end
	end
	if not where then
		pcall(function() item:remove() end)
	end
	return where
end

-- a character whose step opened before the real items: the counter it earned becomes the items (once), so nothing is lost. A
-- bring step of that kind stays legacy until it is done: Warden Ysolde takes no items there (mainquest_core.lua M.talk).
function W.migrate(player)
	local c = C()
	local i = get(player, "step")
	local rule = K.killRule(c, i)
	if not rule or not rule.cond.item or not K.legacy(i, get(player, "items")) then
		return false
	end
	if rule.mode == "drop" then
		local lang = langOf(player)
		local owed = K.legacyOwed(rule.cond, math.max(0, get(player, "count")), K.heldCount(c, player, rule.step.key))
		local given = 0
		for _ = 1, owed do
			if W.giveQuestItem(player, rule.step, rule.cond, nil, lang) then
				given = given + 1
			end
		end
		if given < owed then
			return false -- no room anywhere: try again at the next look
		end
		set(player, "items", i)
		if given > 0 then
			tell(player, string.format(K.text(c.texts.migrated, lang), given, K.text(rule.cond.item, lang)))
		end
		return true
	end
	return false
end

-- ---------------------------------------------------------------- kill credit (O553)
-- one kill of a monster named `name` for a character: the counter of a kill step, or the roll of the quest item of a drop step
-- (and of its bring step while items are missing). corpse = the loot bag of the kill.
function W.creditKill(player, name, corpse)
	local c = C()
	if not c or not c.enabled or staff(player) or get(player, "state") ~= c.states.active then
		return false
	end
	pcall(W.migrate, player)
	local i = get(player, "step")
	local step = c.steps[i]
	if not step or player:getLevel() < step.level then
		return false
	end
	local rule = K.killRule(c, i)
	if not rule then
		return false
	end
	local cond = rule.cond
	local target = math.max(1, math.floor(cond.target))
	if rule.mode == "kill" then
		local counted = K.onKill(c, step, cond, name, 0, 1)
		if counted then
			set(player, "count", math.min(target, math.max(0, get(player, "count")) + 1))
		end
		return counted
	end
	if K.legacy(i, get(player, "items")) then
		return false -- a step of before the real items: an old counter has no drop to roll (W.migrate gives the items)
	end
	local held = K.heldCount(c, player, rule.step.key)
	if held >= target then
		return false
	end
	local _, dropped, pity = K.onKill(c, rule.step, cond, name, math.max(0, get(player, "pity")), math.random())
	set(player, "pity", pity)
	if not dropped then
		return false
	end
	local lang = langOf(player)
	local where = W.giveQuestItem(player, rule.step, cond, corpse, lang)
	if not where then
		return false
	end
	set(player, "count", math.min(target, math.max(0, get(player, "count")) + 1))
	local key = where == "bag" and "drop" or (where == "pack" and "inPack" or "inInbox")
	local shown = where == "bag" and held or math.min(target, held + 1) -- in the bag it is not held yet
	player:sendTextMessage(MESSAGE_LOOT or MESSAGE_INFO_DESCR,
		string.format(K.text(c.texts[key], lang), K.text(cond.item, lang), shown, target))
	return true
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

local function partyMembers(p)
	local party = p:getParty()
	if not party then
		return nil
	end
	local members = party:getMembers()
	members[#members + 1] = party:getLeader()
	return members
end

-- the party's shared experience works (the engine's own rule: every member in range, level range and fighting)
local function sharedOn(p)
	local party = p:getParty()
	if not party then
		return false
	end
	local ok, v = pcall(function() return party:isSharedExperienceEnabled() end)
	if ok and v ~= nil then
		return v == true
	end
	ok, v = pcall(function() return party:isSharedExperienceActive() end)
	return ok and v == true
end

local CREDIT_API = {partyOf = partyMembers, posOf = function(p) return p:getPosition() end, idOf = function(p) return p:getId() end,
	sharedOn = sharedOn}

-- a monster of the quest died: the killers and the party members around them (K.credited), each on its own
function W.onDeath(creature, corpse, killer, mostDamageKiller)
	local c = C()
	if not c or not c.enabled or not creature or creature:getMaster() then
		return
	end
	if ChaosRift and ChaosRift.isHusk and ChaosRift.isHusk(creature) then
		return -- a husk of a dense rift gives no kill credit
	end
	local name = creature:getName()
	local killers, seen = {}, {}
	for _, k in ipairs({playerOf(killer), playerOf(mostDamageKiller)}) do
		if k and not seen[k:getId()] then
			seen[k:getId()] = true
			killers[#killers + 1] = k
		end
	end
	if #killers == 0 then
		return
	end
	local damagers = {}
	if creature.getDamageMap then
		for id in pairs(creature:getDamageMap() or {}) do
			local p = playerOf(Creature(id))
			if p then
				damagers[#damagers + 1] = p
			end
		end
	end
	local credited = K.credited(killers, damagers, CREDIT_API, (c.party or {}).range)
	for _, p in ipairs(credited) do
		local ok, err = pcall(W.creditKill, p, name, corpse)
		if not ok then
			log("kill: " .. tostring(err))
		end
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
	setStep(player, i + 1)
	clearStepState(player)
	W.settleItems(player, i, lang)
	local got = W.reward(player, step, lang)
	local who = lang == "pt" and "Guardiã Ysolde" or "Warden Ysolde"
	tell(player, who .. ": " .. K.text(step.done, lang))
	tell(player, string.format(K.text(c.texts.stepDone, lang), i, #c.steps, K.fill(K.text(step.title, lang), vars(lang)), got))
	toast(player, string.format("%s %d/%d: %s", K.text(c.texts.title, lang), i, #c.steps, K.fill(K.text(step.title, lang), vars(lang))))
	if i >= #c.steps then
		set(player, "state", c.states.done)
		tell(player, K.text(c.texts.finished, lang))
	else
		announceStep(player, i + 1, lang)
	end
	return true
end

-- one look at a character on the quest: a done step moves on (one per look), the rows follow
function W.check(player)
	local c = C()
	if not c.enabled then
		W.ready[player:getId()] = nil
		return
	end
	if ChaosMainQuestBoss and ChaosMainQuestBoss.sweepDoor then
		pcall(ChaosMainQuestBoss.sweepDoor, player) -- the door flag Ysolde's script sets (any state)
	end
	if get(player, "state") ~= c.states.active then
		return
	end
	pcall(W.migrate, player)
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

local function welcomeKey()
	local w = load("data/scripts/chaos/welcomepath_config.lua")
	return w and w.storage and (w.storage.base + w.storage.state) or nil
end

-- the first look (after the counters loaded): start, stay quiet, or carry on
function W.firstLook(player)
	local c = C()
	local pid = player:getId()
	W.ready[pid] = true
	if not c.enabled or staff(player) then
		return
	end
	local state = get(player, "state")
	if state == c.states.fresh or state < 0 then
		state = K.firstState(c, player:getLevel())
		set(player, "state", state)
		set(player, "count", 0)
		set(player, "flags", 0)
		set(player, "flags2", 0)
		if state ~= c.states.active then
			return
		end
		-- the welcome path (O370) is retired: a character on it plays its first steps here, silently where done
		local wk = welcomeKey()
		local wstate = wk and player:getStorageValue(wk) or -1
		local played = W.played(player) or wstate == 0 or wstate == 1
		local start = K.skipDone(c, 1, function(i) return W.facts(player, i) end, played)
		setStep(player, start)
		if wk and wstate == 0 then
			player:setStorageValue(wk, 2) -- the old path rests
		end
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

-- a flag set by a hook of another system: ChaosMainQuest.emit(player, "potion")
function W.emit(who, flag)
	local player = who
	if type(who) == "number" then
		player = Player(who)
	end
	if not player or not player.getStorageValue then
		return false
	end
	local c = C()
	if not c or not c.enabled or get(player, "state") < 0 then
		return false
	end
	return K.emitFlag(c, player, flag)
end

-- a step whose flags the client's Go button marks (windows to see, info to read): server side the step must be the current one
function W.go(player, stepKey)
	local c = C()
	if get(player, "state") ~= c.states.active then
		return false
	end
	local step = c.steps[get(player, "step")]
	if not step or step.key ~= stepKey or player:getLevel() < step.level then
		return false
	end
	local acks = {}
	for _, a in ipairs(c.acks or {}) do
		acks[a] = true
	end
	local marked = false
	for _, cond in ipairs(step.conds) do
		if cond.c == "flag" and acks[cond.key] then
			W.emit(player, cond.key)
			marked = true
		end
	end
	if marked then
		W.refresh(player)
	end
	return marked
end

-- ---------------------------------------------------------------- skip
local function endSkipped(player)
	local c = C()
	set(player, "state", c.states.skipped)
	tell(player, K.text(c.texts.skipped, langOf(player)))
end

function W.skip(player, scope)
	local c = C()
	if get(player, "state") ~= c.states.active then
		return false
	end
	if scope == "chapter" then
		local nxt = K.nextChapterStart(c, get(player, "step"))
		if nxt > #c.steps then
			endSkipped(player)
		else
			setStep(player, nxt)
			clearStepState(player)
		end
	else
		endSkipped(player)
	end
	pcall(K.takeQuestItems, c, player) -- a quest item has no use outside the quest
	W.refresh(player, true)
	return true
end

function W.forget(player)
	W.sent[player:getId()] = nil
end

-- ---------------------------------------------------------------- the whole quest (the chapter window)
function W.state(player)
	local c = C()
	local lang = langOf(player)
	local v = vars(lang)
	local i = math.max(1, get(player, "step"))
	local state = get(player, "state")
	local out = {state = state, step = i, count = #c.steps, chapters = {}, steps = {}, epilogue = {}}
	local counts = K.chapterCounts(c, state == c.states.done and #c.steps + 1 or i)
	for _, ch in ipairs(c.chapters) do
		local cc = counts[ch.n] or {done = 0, total = 0}
		out.chapters[#out.chapters + 1] = {n = ch.n, name = K.text(ch.name, lang), intro = K.text(ch.intro, lang), from = ch.from,
			to = ch.to, done = cc.done, total = cc.total}
	end
	for n, st in ipairs(c.steps) do
		local s = (state == c.states.done or n < i) and "done" or (n == i and "open" or "todo")
		out.steps[#out.steps + 1] = {i = n, key = st.key, ch = st.ch, level = st.level, title = K.fill(K.text(st.title, lang), v),
			hint = K.fill(K.text(st.hint, lang), v), state = s}
		if s == "open" and state == c.states.active then
			local rule = K.killRule(c, n)
			if rule and rule.cond.item and not K.legacy(n, get(player, "items")) then
				out.steps[#out.steps].item = {name = K.text(rule.cond.item, lang), held = K.heldCount(c, player, rule.step.key),
					target = rule.cond.target}
			end
		end
	end
	for _, e in ipairs(c.epilogue) do
		out.epilogue[#out.epilogue + 1] = {key = e.key, level = e.level, title = K.text(e.title, lang), text = K.text(e.text, lang)}
	end
	return out
end

function W.sendState(player)
	local ok, text = pcall(json.encode, {action = "mq", data = W.state(player)})
	if ok then
		Chaos.sendChunked(player, opcode(), text)
	end
end

-- the actions of the goals channel (goals.lua calls this for every `mq...` action)
function W.onAction(player, msg)
	local a = msg.action
	if a == "mqOpen" then
		W.sendState(player)
	elseif a == "mqSkip" then
		local scope = type(msg.data) == "table" and msg.data.scope or msg.scope
		pcall(W.skip, player, scope == "chapter" and "chapter" or "quest")
	elseif a == "mqGo" then
		local d = type(msg.data) == "table" and msg.data or msg
		if type(d.step) == "string" then
			pcall(W.go, player, d.step)
		end
	end
end

-- ---------------------------------------------------------------- the mark over Ysolde's head (poi.lua O415)
-- "ready" (gold "?") while the open step wants a talk (or the door of the last page is open to a skipped / veteran character),
-- "new" (gold "!") while the quest waits to be taken again after a skip
function W.npcMarks(player)
	local c = C()
	if not c or not c.enabled or staff(player) then
		return {}
	end
	local name = c.boss.keeper
	local state = get(player, "state")
	if state == c.states.active then
		local step = c.steps[get(player, "step")]
		if step and player:getLevel() >= step.level then
			for _, cond in ipairs(step.conds) do
				if cond.c == "talk" then
					return {{npc = name, mark = "ready"}}
				end
			end
		end
	elseif state == c.states.skipped then
		return {{npc = name, mark = "new"}}
	end
	return {}
end
ChaosPoi = ChaosPoi or {}
ChaosPoi.markSources = ChaosPoi.markSources or {}
ChaosPoi.markSources.mainquest = W.npcMarks

-- ---------------------------------------------------------------- events
if CreatureEvent then
	local login = CreatureEvent("ChaosMainQuestLogin")
	function login.onLogin(player)
		local pid = player:getId()
		W.sent[pid], W.ready[pid] = nil, nil
		if not C() or not C().enabled then
			return true
		end
		player:registerEvent("ChaosMainQuestLogout")
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

	local logout = CreatureEvent("ChaosMainQuestLogout")
	function logout.onLogout(player)
		local pid = player:getId()
		W.sent[pid], W.ready[pid] = nil, nil
		return true
	end
	logout:type("logout")
	logout:register()

	-- a monster of a count step died (O553: the death event of the monster, not the kill event of the player, so the loot bag
	-- exists and the party members around the killer are credited too)
	local death = CreatureEvent("ChaosMainQuestDeath")
	function death.onDeath(creature, corpse, killer, mostDamageKiller)
		local ok, err = pcall(W.onDeath, creature, corpse, killer, mostDamageKiller)
		if not ok then
			log("death: " .. tostring(err))
		end
		return true
	end
	death:register()
end

-- the monsters of the quest get that event when they spawn (only the names of the count steps)
if EventCallback then
	local names = {}
	for _, st in ipairs(C() and C().steps or {}) do
		for _, cond in ipairs(st.conds) do
			if cond.c == "count" then
				for _, m in ipairs(cond.mons) do
					names[m:lower()] = true
				end
			end
		end
	end
	W.monsterNames = names
	local spawn = EventCallback
	spawn.onSpawn = function(self, position, startup, artificial)
		if C() and C().enabled and names[self:getName():lower()] and not self:getMaster() then
			self:registerEvent("ChaosMainQuestDeath")
		end
		return true
	end
	spawn:register()
end

if GlobalEvent then
	local think = GlobalEvent("ChaosMainQuestThink")
	function think.onThink(interval)
		if not C() or not C().enabled then
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
