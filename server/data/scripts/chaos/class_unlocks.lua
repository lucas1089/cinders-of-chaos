-- class_unlocks.lua: the class lock. Some classes (now: the Necromancer, the Monk and the Templar) can only be played
-- on an account that has unlocked them; today the unlock is bought in the store (category "Classes", placeholder
-- price 750 Chaos Coins each). The unlock is account-wide: every character of the account.
-- Config and rules: class_unlocks_core.lua (ChaosClassUnlocksCore.config, one table; the unlock methods are
-- pluggable: store, level, quest, achievement, or any kind added with ChaosClassUnlocksCore.registerMethod).
-- Storage: the table chaos_class_unlocks (server/sql/chaos_class_unlocks.sql; created here at startup if missing).
-- Tests: server/tests/class_unlocks_test.lua.
--
-- ============================================================== API (stable; other class modules call it)
--   ChaosClassUnlocks.isUnlocked(playerOrAccountId, classKey) -> bool
--       true when the class is not locked, when the account has unlocked it, or (given a player) when the player is
--       staff (ChaosClassUnlocksCore.config.bypass). classKey: "necromancer" | "monk" | "templar" | ...
--   ChaosClassUnlocks.classOfVocation(vocId) -> classKey or nil (nil: the vocation belongs to no locked class)
--   ChaosClassUnlocks.canUseVocation(player, vocId) -> ok (bool), message (string when not ok)
--       call it before any script sets a vocation (ascension, vocation change, NPCs, admin tools)
--   ChaosClassUnlocks.grant(accountId, classKey, source) -> true, or false + reason   (source: "store", "level", "gm")
--   ChaosClassUnlocks.revoke(accountId, classKey) -> true, or false + reason
--   ChaosClassUnlocks.isRestricted(player) -> bool  (the player is on a locked vocation it may not play)
--   ChaosClassUnlocks.storeUnlock(unlockName) -> the store's unlock entry for a shop_config offer
--       {kind = "unlock", unlock = "unlockTemplar"}: {name, done, owned = fn(player), grant = fn(player)}, or nil
-- ==============================================================
--
-- The gates (every way into a locked vocation):
--   * the store's vocation change (!changevocation <class>) and !ascend call canUseVocation before they change
--     anything (shop_services.lua, ascension.lua);
--   * characters are created on the website (the base server has no account manager and no in-game creation): the
--     website should offer a locked vocation only to accounts with a row in chaos_class_unlocks; whatever it does,
--   * the login check below catches every character on a locked vocation: with mode "restrict" (default) it logs in,
--     goes to its temple, cannot attack and gains no experience or skill until the account unlocks the class (the
--     store works in that state, so it can buy the unlock at once; the restriction ends the moment it is bought);
--     mode "kick" shows the same window and logs it out. Staff (group 4+ or account type 5+) is never locked.
-- Commands: !classes (what the account has unlocked); staff: /classunlock <character>, <class>[, revoke].
if not ChaosCommands then
	dofile("data/scripts/chaos/commands_ui_core.lua")
end

if not ChaosClassUnlocksCore then
	dofile("data/scripts/chaos/class_unlocks_core.lua")
end

ChaosClassUnlocks = ChaosClassUnlocks or {}
local U = ChaosClassUnlocks
local K = ChaosClassUnlocksCore
U.core = K

local function cfg()
	return K.config
end

-- ------------------------------------------------------------------------------------------------ storage
local tableReady = false
local function ensureTable()
	if not tableReady then
		tableReady = db.query(K.sqlCreate()) and true or false
	end
	return tableReady
end

U.cache = U.cache or {} -- [accountId] = set of unlocked class keys

local function loadSet(accountId)
	local set = U.cache[accountId]
	if set then
		return set
	end
	ensureTable()
	local rows = {}
	local id = db.storeQuery(K.sqlSelect(accountId))
	if id then
		repeat
			rows[#rows + 1] = {class_key = result.getString(id, "class_key")}
		until not result.next(id)
		result.free(id)
	end
	set = K.toSet(rows)
	U.cache[accountId] = set
	return set
end

local function isPlayer(x)
	return type(x) == "userdata" and x.getAccountId ~= nil
end

local function staff(player)
	local accountType = player.getAccountType and player:getAccountType() or 0
	return K.isBypass(player:getGroup():getId(), accountType)
end

-- ------------------------------------------------------------------------------------------------ API
function U.classOfVocation(vocId)
	local key = K.classOfVocation(vocId)
	if key and K.isLocked(key) then
		return key
	end
	return nil
end

function U.isUnlocked(who, classKey)
	if not K.isLocked(classKey) then
		return true
	end
	local accountId = who
	if isPlayer(who) then
		if staff(who) then
			return true
		end
		accountId = who:getAccountId()
	end
	accountId = tonumber(accountId)
	if not accountId or accountId <= 0 then
		return false
	end
	return loadSet(accountId)[classKey] == true
end

function U.canUseVocation(player, vocId)
	local key = U.classOfVocation(vocId)
	if not key then
		return true
	end
	if U.isUnlocked(player, key) then
		return true
	end
	return false, K.lockMessage(key)
end

function U.isRestricted(player)
	local ok = U.canUseVocation(player, player:getVocation():getId())
	return not ok
end

local function onlineOfAccount(accountId)
	local list = {}
	for _, p in ipairs(Game.getPlayers()) do
		if p:getAccountId() == accountId then
			list[#list + 1] = p
		end
	end
	return list
end

function U.grant(accountId, classKey, source)
	if not cfg().classes[classKey] then
		return false, "Unknown class."
	end
	ensureTable()
	local q = K.sqlInsert(accountId, classKey, source or "store", os.time())
	if not q or not db.query(q) then
		return false, "Could not save the unlock. Try again."
	end
	U.cache[accountId] = nil
	local name = cfg().classes[classKey].name
	for _, p in ipairs(onlineOfAccount(accountId)) do
		if K.classOfVocation(p:getVocation():getId()) == classKey then
			p:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("The %s is unlocked: you can play this character fully now.", name))
		end
	end
	return true
end

function U.revoke(accountId, classKey)
	local q = K.sqlDelete(accountId, classKey)
	if not q or not db.query(q) then
		return false, "Could not remove the unlock."
	end
	U.cache[accountId] = nil
	return true
end

-- the store (shop_services.lua): an unlock entry for an offer {kind = "unlock", unlock = <offer name>}
function U.storeUnlock(unlockName)
	local key = K.classOfOffer(unlockName)
	if not key then
		return nil
	end
	local class = cfg().classes[key]
	return {
		classKey = key,
		name = "the " .. class.name .. " class",
		done = string.format("Every character of your account can now become %s (and its ascended classes).", class.name),
		owned = function(player)
			return loadSet(player:getAccountId())[key] == true
		end,
		grant = function(player)
			return U.grant(player:getAccountId(), key, "store")
		end
	}
end

-- ------------------------------------------------------------------------------------------------ automatic methods
-- the highest level of any character of the account (the level method counts every character)
local function accountLevel(player)
	local level = player:getLevel()
	local id = db.storeQuery("SELECT MAX(`level`) AS `l` FROM `players` WHERE `account_id` = " .. player:getAccountId())
	if id then
		level = math.max(level, result.getNumber(id, "l") or 0)
		result.free(id)
	end
	return level
end

local function checkAutomatic(player)
	local facts
	for _, key in ipairs(K.lockedClasses()) do
		if not U.isUnlocked(player:getAccountId(), key) then
			facts = facts or {
				level = accountLevel(player),
				storage = function(k) return player:getStorageValue(k) end,
				achievement = function(name)
					return ChaosAchievements ~= nil and ChaosAchievements.has ~= nil and ChaosAchievements.has(player, name) == true
				end
			}
			local kind = K.autoUnlock(key, facts)
			if kind and U.grant(player:getAccountId(), key, kind) then
				player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format(
					"Class unlocked for your account: %s.", cfg().classes[key].name))
			end
		end
	end
end

-- ------------------------------------------------------------------------------------------------ the login check
local function lockText(player)
	local key = K.classOfVocation(player:getVocation():getId())
	return K.lockMessage(key) .. " Until then this character stays in its temple: it cannot attack and gains no "
		.. "experience or skills. Every other character of your account plays as usual."
end

local function kickLater(cid)
	local p = Player(cid)
	if p and U.isRestricted(p) then
		p:remove()
	end
end

local login = CreatureEvent("ChaosClassUnlocksLogin")
function login.onLogin(player)
	player:registerEvent("ChaosClassUnlocksAdvance")
	local ok, err = pcall(checkAutomatic, player)
	if not ok then
		print("[ChaosClassUnlocks] " .. tostring(err))
	end
	if not U.isRestricted(player) then
		return true
	end
	local town = player:getTown()
	if town then
		player:teleportTo(town:getTemplePosition())
	end
	local text = lockText(player)
	if cfg().login.mode == "kick" then
		text = K.lockMessage(K.classOfVocation(player:getVocation():getId())) .. " You will be logged out."
		addEvent(kickLater, cfg().login.kickAfterMs, player:getId())
	end
	player:sendTextMessage(MESSAGE_STATUS_WARNING, text)
	if player.popupFYI then
		-- one sentence per line: the client sizes the window to the longest line (one long line ran off the screen)
		player:popupFYI((text:gsub("%. ", ".\n")))
	end
	return true
end
login:register()

local advance = CreatureEvent("ChaosClassUnlocksAdvance")
function advance.onAdvance(player, skill, oldLevel, newLevel)
	if skill == SKILL_LEVEL then
		pcall(checkAutomatic, player)
	end
	return true
end
advance:register()

-- the restriction: no attacks, no experience, no skills
local lastNotice = {}
local function notice(player)
	local now = os.time()
	if now - (lastNotice[player:getId()] or 0) >= 5 then
		lastNotice[player:getId()] = now
		player:sendCancelMessage(K.lockMessage(K.classOfVocation(player:getVocation():getId())))
	end
end

local targetCb = EventCallback
targetCb.onTargetCombat = function(creature, target)
	if creature and creature:isPlayer() and U.isRestricted(creature) then
		notice(creature)
		return RETURNVALUE_NOTPOSSIBLE
	end
	return RETURNVALUE_NOERROR
end
targetCb:register(1)

local expCb = EventCallback
expCb.onGainExperience = function(self, source, exp, rawExp)
	if U.isRestricted(self) then
		return 0
	end
	return exp
end
expCb:register(1)

local skillCb = EventCallback
skillCb.onGainSkillTries = function(self, skill, tries)
	if U.isRestricted(self) then
		return 0
	end
	return tries
end
skillCb:register(1)

local logout = CreatureEvent("ChaosClassUnlocksLogout")
function logout.onLogout(player)
	lastNotice[player:getId()] = nil
	return true
end
logout:register()
local loginLogout = CreatureEvent("ChaosClassUnlocksLoginLogout")
function loginLogout.onLogin(player)
	player:registerEvent("ChaosClassUnlocksLogout")
	return true
end
loginLogout:register()

local startup = GlobalEvent("ChaosClassUnlocksStartup")
function startup.onStartup()
	ensureTable()
	return true
end
startup:register()

-- ------------------------------------------------------------------------------------------------ commands
local function statusLines(player)
	local lines = {}
	for _, key in ipairs(K.lockedClasses()) do
		local class = cfg().classes[key]
		if U.isUnlocked(player, key) then
			lines[#lines + 1] = class.name .. ": unlocked"
		else
			lines[#lines + 1] = class.name .. ": locked - " .. K.lockMessage(key):gsub("^.-locked on this account%. ", "")
		end
	end
	return lines
end

local classesTalk = {} -- reached from the menu: Info & Services window (commands_ui.lua, id "classes")
function classesTalk.onSay(player, words, param)
	local lines = statusLines(player)
	if #lines == 0 then
		player:sendTextMessage(MESSAGE_INFO_DESCR, "Every class is open to every account.")
	else
		player:sendTextMessage(MESSAGE_INFO_DESCR, "Classes of your account:\n" .. table.concat(lines, "\n"))
	end
	return false
end
ChaosCommands.register("classes", function(player, param) return classesTalk.onSay(player, "", param) end)

-- staff: /classunlock <character>, <class>[, revoke]   (works for offline characters: it is per account)
local gmTalk = TalkAction("/classunlock")
function gmTalk.onSay(player, words, param)
	if not player:getGroup():getAccess() or player:getGroup():getId() < cfg().bypass.minGroup then
		return true
	end
	local name, key, mode = param:match("^%s*([^,]+)%s*,%s*([%w_]+)%s*,?%s*(%w*)%s*$")
	if not name or not cfg().classes[key or ""] then
		player:sendTextMessage(MESSAGE_INFO_DESCR, "Usage: /classunlock <character>, <" .. table.concat(K.lockedClasses(), "|")
			.. ">[, revoke]")
		return false
	end
	local accountId
	local id = db.storeQuery("SELECT `account_id` FROM `players` WHERE `name` = " .. db.escapeString(name))
	if id then
		accountId = result.getNumber(id, "account_id")
		result.free(id)
	end
	if not accountId then
		player:sendTextMessage(MESSAGE_INFO_DESCR, "No character named " .. name .. ".")
		return false
	end
	-- staff never give value (docs/GM_HANDBOOK.md section 2): an unlock needs an administrator, a revoke does not
	if not Chaos.staffCommand(player, words, param, mode ~= "revoke") then
		return false
	end
	local ok, err
	if mode == "revoke" then
		ok, err = U.revoke(accountId, key)
	else
		ok, err = U.grant(accountId, key, "gm")
	end
	player:sendTextMessage(MESSAGE_INFO_DESCR, ok and string.format("%s %s for the account of %s.",
		mode == "revoke" and "Removed" or "Unlocked", cfg().classes[key].name, name) or err)
	return false
end
gmTalk:separator(" ")
gmTalk:register()
