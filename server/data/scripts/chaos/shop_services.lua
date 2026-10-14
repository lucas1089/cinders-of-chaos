-- Store services (offer kinds "service" and "unlock" of shop.lua / shop_config.lua).
--
--   {kind = "service", service = "<handler>", ...}   something done for the character right away (stamina, world
--                                                   buff, name change token, ...); handlers in S.services below
--   {kind = "unlock", unlock = "<name>"}            a permanent flag: per character (a storage, S.unlocks) or, for
--                                                   a class, per account (class_unlocks.lua)
--
-- shop.lua calls ChaosShopServices.check(player, offer) BEFORE taking coins (a text = refused, nothing is taken)
-- and ChaosShopServices.deliver(player, offer) after; deliver returns true or an error text, and shop.lua refunds
-- the coins on an error.
--
-- Also here: the Temple Teleport Scroll (action id), world buffs (experience / Chaos loot / skill training for
-- everybody, !worldbuffs), !changename and !changevocation for the tokens. Auto Seller: autosell.lua; store pouches: pouches.lua.
-- Settings: Chaos.shopServices in chaos_constants.lua. Pure helpers at the top are covered by
-- server/tests/shop_services_test.lua. Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosCommands then
	dofile("data/scripts/chaos/commands_ui_core.lua")
end

ChaosShopServices = ChaosShopServices or {}
local S = ChaosShopServices
local ST = Chaos.storage

local function C()
	return Chaos.shopServices
end

-- ======================================================================== pure helpers (tested)

local function trim(s)
	return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- "lord  of chaos" -> "Lord Of Chaos" (first letter of every word upper, the rest lower). Keeps the
-- spacing as typed so validateName can refuse double spaces.
function S.capitalize(name)
	return (name:gsub("(%a)(%a*)", function(first, rest)
		return first:upper() .. rest:lower()
	end))
end

-- Returns the cleaned name or nil, reason. rules = Chaos.shopServices.name
function S.validateName(raw, rules)
	rules = rules or C().name
	local name = trim(raw)
	if #name < rules.minLength or #name > rules.maxLength then
		return nil, string.format("A name must have %d to %d characters.", rules.minLength, rules.maxLength)
	end
	if name:find("[^%a ]") then
		return nil, "A name may only contain letters and spaces."
	end
	if name:find("  ", 1, true) then
		return nil, "Use single spaces between the words."
	end
	name = S.capitalize(name)
	local words = {}
	for word in name:gmatch("%a+") do
		words[#words + 1] = word
	end
	if #words > rules.maxWords then
		return nil, string.format("A name may have at most %d words.", rules.maxWords)
	end
	local lower = name:lower()
	for _, word in ipairs(words) do
		if #word < rules.minWordLength then
			return nil, string.format("Every word needs at least %d letters.", rules.minWordLength)
		end
		local lw = word:lower()
		for _, staff in ipairs(rules.staffWords) do
			if lw == staff then
				return nil, "Names may not look like a staff member's."
			end
		end
	end
	if lower:find("(%a)%1%1") then
		return nil, "A name may not repeat a letter three times in a row."
	end
	for _, bad in ipairs(rules.forbidden) do
		if lower:find(bad, 1, true) then
			return nil, "That name is not allowed."
		end
	end
	return name
end

-- World buff stacking. Returns the new expiry, or nil + seconds left when the purchase would pass the cap.
function S.stackBuff(now, expiry, addSeconds, capSeconds)
	local left = math.max(0, (tonumber(expiry) or 0) - now)
	if left + addSeconds > capSeconds then
		return nil, left
	end
	return now + left + addSeconds, left
end

-- true when vocation id `id` is the promoted id of an entry of `map` (Chaos.shopServices.vocations)
function S.isPromoted(id, map)
	for _, ids in pairs(map or C().vocations) do
		if ids[2] == id then
			return true
		end
	end
	return false
end

-- Target vocation id for "!changevocation <word>" from vocation `currentId`, or nil + reason.
function S.vocationFor(word, currentId, map)
	map = map or C().vocations
	local ids = map[trim(word):lower()]
	if not ids then
		local names = {}
		for k in pairs(map) do
			names[#names + 1] = k
		end
		table.sort(names)
		return nil, "Choose one of: " .. table.concat(names, ", ") .. "."
	end
	local promoted = S.isPromoted(currentId, map)
	-- a base class with two ascended classes (Thief: Ninja or Samurai): an ascended character names the one it wants
	if promoted and ids.choose then
		return nil, "You have ascended: name the ascended class you want (" .. table.concat(ids.choose, " or ") .. ")."
	end
	if ids[1] == currentId or ids[2] == currentId then
		return nil, "You already are of that vocation."
	end
	return promoted and ids[2] or ids[1]
end

-- Health, mana and capacity after a vocation change, counted like the engine does from level `baseLevel`:
-- health 185 + levels x gain, mana 90 + levels x gain (every vocation has 185 / 90 at level 8). Capacity keeps
-- whatever the character got outside the level gains: cap + levels x (new gain - old gain), never below the
-- level-8 value. old/new = {hp = , mana = , cap = } gains per level (cap in the engine's 1/100 oz units).
function S.recomputeStats(level, baseLevel, cap, old, new)
	local levels = math.max(0, level - baseLevel)
	return {
		health = 185 + levels * new.hp,
		mana = 90 + levels * new.mana,
		cap = math.max(47000, cap + levels * (new.cap - old.cap))
	}
end

-- Gold for `count` items of `itemId` at NPC prices (prices = {[id] = gold}); 0 when no NPC buys it.
function S.sellPrice(itemId, count, prices)
	local p = prices and prices[itemId]
	if type(p) ~= "number" or p <= 0 then
		return 0
	end
	return p * math.max(1, count or 1)
end

-- Why the auto seller must keep an item, or nil when it may sell it.
-- info = {unique = bool, rarity = number, attributes = bool (custom name/description/text/modifiers)}
-- allow = the player's rarity choice: a table {common, uncommon, rare, epic, legendary = bool} (autosell_core.lua
-- tiers, the Auto Seller window), or a boolean (true = every rarity). Uniques are never sold; an item with a custom
-- name, description or text and no rarity is kept ("custom") unless allow is true.
function S.sellBlocked(info, allow)
	if info.locked then
		return "locked" -- the item lock (salvage.lua), whatever the choice
	end
	if info.unique then
		return "unique"
	end
	local rarity = tonumber(info.rarity) or 0
	if rarity > 0 then
		if allow == true then
			return nil
		end
		if type(allow) == "table" and ChaosAutoSellCore and ChaosAutoSellCore.sells(allow, rarity) then
			return nil
		end
		return "rarity"
	end
	if info.attributes and allow ~= true then
		return type(allow) == "table" and "custom" or "rarity"
	end
	return nil
end

function S.formatDuration(seconds)
	seconds = math.max(0, math.floor(seconds))
	local h, m = math.floor(seconds / 3600), math.floor(seconds % 3600 / 60)
	if h > 0 then
		return string.format("%dh %02dm", h, m)
	end
	return string.format("%dm %02ds", m, seconds % 60)
end

-- ======================================================================== engine helpers

local function inCombat(player)
	return player:isPzLocked() or player:hasCondition(CONDITION_INFIGHT)
end

local function inProtectionZone(player)
	local tile = Tile(player:getPosition())
	return tile ~= nil and tile:hasFlag(TILESTATE_PROTECTIONZONE)
end

local function onlineByGuid(guid)
	for _, p in ipairs(Game.getPlayers()) do
		if p:getGuid() == guid then
			return p
		end
	end
	return nil
end

-- ------------------------------------------------------------------------ world buffs
S.worldBuffs = {} -- id -> {index, def}
for i, def in ipairs(C().worldBuffs) do
	S.worldBuffs[def.id] = {index = i, def = def}
end

local function buffKey(id)
	return C().worldBuffStorage + S.worldBuffs[id].index
end

function S.buffExpiry(id)
	if not S.worldBuffs[id] then
		return 0
	end
	return tonumber(Game.getStorageValue(buffKey(id))) or 0
end

function S.buffLeft(id)
	return math.max(0, S.buffExpiry(id) - os.time())
end

-- multiplier of a world buff (1 when it is not running). player (optional): the character it is for
function S.buffMult(id, player)
	if S.buffLeft(id) > 0 then
		-- >>> Seasons: world buffs are bought with account-wide coins, so they never reach season characters
		if player and ChaosSeason and ChaosSeason.realmOf and (ChaosSeason.realmOf(player) or 0) > 0 then
			return 1
		end
		-- <<< Seasons
		return 1 + S.worldBuffs[id].def.bonus
	end
	return 1
end

local function persistBuff(id, expiry)
	Game.setStorageValue(buffKey(id), expiry)
	db.query("INSERT INTO `server_config` (`config`, `value`) VALUES (" .. db.escapeString(C().worldBuffConfigKey .. id) ..
		", " .. db.escapeString(tostring(expiry)) .. ") ON DUPLICATE KEY UPDATE `value` = VALUES(`value`)")
end

-- after a restart the global storages are empty: read the expiries back from server_config
local function loadBuffs()
	for id in pairs(S.worldBuffs) do
		if Game.getStorageValue(buffKey(id)) == nil then
			local rows = Chaos.select("SELECT `value` FROM `server_config` WHERE `config` = " ..
				db.escapeString(C().worldBuffConfigKey .. id), {{"value", "s"}})
			local expiry = rows[1] and tonumber(rows[1].value) or 0
			Game.setStorageValue(buffKey(id), expiry > os.time() and expiry or 0)
		end
	end
end
S.loadBuffs = loadBuffs

function S.describeBuffs()
	local lines = {}
	for _, def in ipairs(C().worldBuffs) do
		local left = S.buffLeft(def.id)
		if left > 0 then
			lines[#lines + 1] = string.format("%s (%s): %s left", def.name, def.text, S.formatDuration(left))
		end
	end
	return lines
end

-- ------------------------------------------------------------------------ temple scroll
local function setScrollUses(item, uses)
	local cfg = C().templeScroll
	item:setCustomAttribute("chaos_uses", uses)
	item:setAttribute(ITEM_ATTRIBUTE_NAME, cfg.name)
	item:setAttribute(ITEM_ATTRIBUTE_ARTICLE, "a")
	item:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, string.format(
		"Use it to return to your temple. Not usable in combat, dungeons, the tower or the world boss arena. %d use%s left.",
		uses, uses == 1 and "" or "s"))
end

-- where the scroll may not be used: a reason, or nil
function S.teleportBlocked(player)
	if inCombat(player) then
		return "You cannot use this while you are in combat."
	end
	if ChaosDungeonIsInside and ChaosDungeonIsInside(player) then
		return "You cannot use this inside a dungeon."
	end
	if ChaosTowerRun and ChaosTowerRun.isInside and ChaosTowerRun.isInside(player) then
		return "You cannot use this inside the Infinity Tower."
	end
	if ChaosWorldBoss and ChaosWorldBoss.inside and ChaosWorldBoss.inside(player:getPosition()) then
		return "You cannot use this inside the world boss arena."
	end
	if ChaosRift and ChaosRift.isInside and ChaosRift.isInside(player) then
		return "You cannot use this inside a rift."
	end
	-- every other registered instance (raid, Descent, battleground, Marches, guild boss, siege, arena, ...); a hideout
	-- stays allowed (a teleport out of it is harmless)
	local label = Chaos.inAnyInstance and select(2, Chaos.inAnyInstance(player, "hideout")) or nil
	if label then
		return "You cannot use this inside " .. label .. "."
	end
	return nil
end

-- ------------------------------------------------------------------------ sex change: outfits by name
local outfitPairs -- [looktype] = looktype of the other sex with the same name
local function counterparts()
	if outfitPairs then
		return outfitPairs
	end
	outfitPairs = {}
	local byName = {[0] = {}, [1] = {}}
	local f = io.open("data/XML/outfits.xml", "r")
	if f then
		for line in f:lines() do
			local t, look, name = line:match('<outfit%s+type="(%d)"%s+looktype="(%d+)"%s+name="([^"]*)"')
			if t and byName[tonumber(t)] then
				byName[tonumber(t)][name] = tonumber(look)
			end
		end
		f:close()
	end
	for name, male in pairs(byName[1]) do
		local female = byName[0][name]
		if female then
			outfitPairs[male], outfitPairs[female] = female, male
		end
	end
	return outfitPairs
end

-- ======================================================================== services

S.unlocks = {
	-- (lootPouch, the Bottomless Loot Pouch, is retired: storage 7100100 stays reserved, pouches.lua gives its owners a
	-- Loot Bag item; the store pouches are the "pouch" service below)
	autoSeller = {storage = ST.shopAutoSeller, name = "the Auto Seller",
		done = "Mark the items to sell in Economy > Auto Seller."},
	rarityAutoloot = {storage = ST.shopRarityAutoloot, name = "Rarity Autoloot",
		done = "Set it in the Loot Filter (Hunt > Loot Filter)."}
}

-- an unlock entry: S.unlocks (per character, a storage) or a class unlock (per account, class_unlocks.lua:
-- {name, done, owned = fn(player), grant = fn(player)})
local function unlockEntry(name)
	local u = S.unlocks[name or ""]
	if not u and ChaosClassUnlocks and ChaosClassUnlocks.storeUnlock then
		u = ChaosClassUnlocks.storeUnlock(name)
	end
	if not u and ChaosPets and ChaosPets.storeUnlock then
		u = ChaosPets.storeUnlock(name) -- a pet (pets.lua), per character
	end
	if not u and ChaosTownPortal and ChaosTownPortal.storeUnlock then
		u = ChaosTownPortal.storeUnlock(name) -- a portal style (townportal.lua), per character
	end
	if not u and ChaosTransmog and ChaosTransmog.storeUnlock then
		u = ChaosTransmog.storeUnlock(name) -- an appearance set (transmog.lua), per account
	end
	if not u and ChaosCosmetics and ChaosCosmetics.storeUnlock then
		u = ChaosCosmetics.storeUnlock(name) -- a cosmetic (cosmetics.lua), per account
	end
	if not u and ChaosHideout and ChaosHideout.storeUnlock then
		u = ChaosHideout.storeUnlock(name) -- a hideout decoration (hideout.lua), per account
	end
	return u
end

local function tokenService(storage, what, command)
	return {
		check = function(player)
			if player:getStorageValue(storage) > 0 then
				return "You already have an unused " .. what .. ". Use it first (" .. command .. ")."
			end
		end,
		apply = function(player)
			player:setStorageValue(storage, 1)
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "You received a " .. what .. ". Use it in " .. command .. ".")
			return true
		end
	}
end

S.services = {
	stamina = {
		check = function(player)
			if player:getStamina() >= C().maxStamina then
				return "Your stamina is already full."
			end
		end,
		apply = function(player)
			player:setStamina(C().maxStamina)
			player:getPosition():sendMagicEffect(CONST_ME_MAGIC_GREEN)
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Your stamina is full again.")
			return true
		end
	},

	templeScroll = {
		apply = function(player, offer)
			local cfg = C().templeScroll
			local item = player:addItem(cfg.itemId, 1, false)
			if not item then
				return "You do not have enough room or capacity."
			end
			item:setActionId(cfg.actionId)
			setScrollUses(item, offer.uses or 1)
			return true
		end
	},

	worldBuff = {
		check = function(player, offer)
			local b = S.worldBuffs[offer.buff]
			if not b then
				return "This offer cannot be bought."
			end
			local _, left = S.stackBuff(os.time(), S.buffExpiry(offer.buff), b.def.minutes * 60, b.def.capMinutes * 60)
			if not _ then
				return string.format("%s is already active for %s; it can run at most %d minutes. Try again later.",
					b.def.name, S.formatDuration(left), b.def.capMinutes)
			end
		end,
		apply = function(player, offer)
			local b = S.worldBuffs[offer.buff]
			local now = os.time()
			local expiry, left = S.stackBuff(now, S.buffExpiry(offer.buff), b.def.minutes * 60, b.def.capMinutes * 60)
			if not expiry then
				return "The world buff is at its limit."
			end
			persistBuff(offer.buff, expiry)
			local text
			if left > 0 then
				text = string.format("%s extended the %s by %d minutes! (%s) %s left. Thank you!",
					player:getName(), b.def.name, b.def.minutes, b.def.text, S.formatDuration(expiry - now))
			else
				text = string.format("%s activated the %s for everyone: %s for %d minutes! Thank you!",
					player:getName(), b.def.name, b.def.text, b.def.minutes)
			end
			Game.broadcastMessage(text, MESSAGE_EVENT_ADVANCE)
			for _, p in ipairs(Game.getPlayers()) do
				p:getPosition():sendMagicEffect(CONST_ME_FIREWORK_YELLOW)
			end
			return true
		end
	},

	nameToken = tokenService(ST.nameChangeTokens, "name change", "Character > Services"),
	vocationToken = tokenService(ST.vocationChangeTokens, "vocation change", "Character > Services"),

	blessings = {
		check = function(player)
			for _, b in ipairs(C().blessings) do
				if not player:hasBlessing(b) then
					return nil
				end
			end
			return "You already have all blessings."
		end,
		apply = function(player)
			for _, b in ipairs(C().blessings) do
				if not player:hasBlessing(b) then
					player:addBlessing(b)
				end
			end
			player:getPosition():sendMagicEffect(CONST_ME_HOLYAREA)
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "The gods bless you: you have all blessings.")
			return true
		end
	},

	skullRemover = {
		check = function(player)
			if inCombat(player) then
				return "Leave combat first (no battle sign or protection zone lock)."
			end
			local skull = player:getSkull()
			if player:getSkullTime() <= 0 and skull ~= SKULL_RED and skull ~= SKULL_BLACK then
				return "You have no unjustified kills or red/black skull to remove."
			end
		end,
		apply = function(player)
			player:setSkullTime(0)
			local skull = player:getSkull()
			if skull == SKULL_RED or skull == SKULL_BLACK then
				player:setSkull(SKULL_NONE)
			end
			player:getPosition():sendMagicEffect(CONST_ME_HOLYDAMAGE)
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Your unjustified kills are forgiven and your skull is gone.")
			return true
		end
	},

	sexChange = {
		check = function(player)
			if inCombat(player) then
				return "Leave combat first."
			end
		end,
		apply = function(player)
			local pairsByLook = counterparts()
			local newSex = player:getSex() == PLAYERSEX_FEMALE and PLAYERSEX_MALE or PLAYERSEX_FEMALE
			-- carry every outfit (and its addons) the character owns over to the other sex
			for look, other in pairs(pairsByLook) do
				if player:hasOutfit(look) and not player:hasOutfit(other) then
					player:addOutfit(other)
				end
				for addon = 1, 2 do
					if player:hasOutfit(look, addon) and not player:hasOutfit(other, addon) then
						player:addOutfitAddon(other, addon)
					end
				end
			end
			local outfit = player:getOutfit()
			player:setSex(newSex)
			local target = pairsByLook[outfit.lookType] or (newSex == PLAYERSEX_FEMALE and 136 or 128)
			outfit.lookType = target
			player:setOutfit(outfit)
			player:getPosition():sendMagicEffect(CONST_ME_MAGIC_BLUE)
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Your character is now " ..
				(newSex == PLAYERSEX_FEMALE and "female" or "male") .. ". Your outfits came with you.")
			return true
		end
	},

	passiveReset = {
		check = function(player)
			if not (ChaosPassiveTree and ChaosPassiveTree.resetAll) then
				return "The passive tree is not available."
			end
			-- the service also resets the Paragon track (paragon.lua): one paid respec for every passive point
			local paragon = ChaosParagon and ChaosParagon.hasAllocation and ChaosParagon.hasAllocation(player)
			if not ChaosPassiveTree.hasAllocation(player) and not paragon then
				return "Your passive tree and Paragon track have no allocated points."
			end
		end,
		apply = function(player)
			if ChaosParagon and ChaosParagon.resetAll then
				ChaosParagon.resetAll(player, true) -- the tree's resetAll below reapplies everything once
			end
			ChaosPassiveTree.resetAll(player)
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE,
				"Your passive tree and Paragon points were reset. All points are free to spend again.")
			return true
		end
	},

	-- the store pouches (pouches.lua): {service = "pouch", pouch = "loot" | "orbs" | "keys"}; one of each per character
	pouch = {
		check = function(player, offer)
			if not ChaosPouches then
				return "This offer is not available."
			end
			return ChaosPouches.storeCheck(player, offer.pouch)
		end,
		apply = function(player, offer)
			return ChaosPouches.storeGive(player, offer.pouch)
		end
	}
}

-- ------------------------------------------------------------------------ entry points for shop.lua
-- an unlock offer the character (or its account) owns already: the store page shows it as owned
function S.owns(player, offer)
	local u = offer and offer.kind == "unlock" and unlockEntry(offer.unlock)
	if not u then
		return false
	end
	if u.owned then
		return u.owned(player) == true
	end
	return u.storage ~= nil and player:getStorageValue(u.storage) > 0
end

function S.check(player, offer)
	if offer.kind == "unlock" then
		local u = unlockEntry(offer.unlock)
		if not u then
			return "This offer cannot be bought."
		end
		local owned
		if u.owned then
			owned = u.owned(player)
		else
			owned = player:getStorageValue(u.storage) > 0
		end
		if owned then
			return "You already own " .. u.name .. "."
		end
		return nil
	end
	local service = S.services[offer.service or ""]
	if not service then
		return "This offer cannot be bought."
	end
	return service.check and service.check(player, offer) or nil
end

function S.deliver(player, offer)
	if offer.kind == "unlock" then
		local u = unlockEntry(offer.unlock)
		if not u then
			return "This offer cannot be bought."
		end
		if u.grant then
			local ok, err = u.grant(player)
			if not ok then
				return err or "Something went wrong. Your coins were refunded."
			end
		else
			player:setStorageValue(u.storage, 1)
		end
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "You unlocked " .. u.name .. ". " .. u.done)
		return true
	end
	local service = S.services[offer.service or ""]
	if not service then
		return "This offer cannot be bought."
	end
	local ok, result = pcall(service.apply, player, offer)
	if not ok then
		print("[Chaos store] service " .. tostring(offer.service) .. " failed: " .. tostring(result))
		return "Something went wrong. Your coins were refunded."
	end
	return result
end

-- ======================================================================== engine registration

-- world buff effects
local xpCb = EventCallback
-- season characters (season.lua realm > 0) get neither World Experience nor the double experience potion: the base
-- player.lua doubled `exp` already while the potion runs (storage 6000), so it is halved back here
local POTION_STORAGE = 6000
xpCb.onGainExperience = function(self, source, exp, rawExp)
	if ChaosSeason and ChaosSeason.realmOf and (ChaosSeason.realmOf(self) or 0) > 0 then
		if self:getStorageValue(POTION_STORAGE) >= os.time() then
			return math.floor(exp / 2)
		end
		return exp
	end
	local mult = S.buffMult("xp")
	if mult ~= 1 and source and source:isMonster() then
		return math.floor(exp * mult)
	end
	return exp
end
xpCb:register(5)

local skillCb = EventCallback
skillCb.onGainSkillTries = function(self, skill, tries)
	local mult = S.buffMult("skill", self) -- not for season characters
	if mult ~= 1 and tries and tries > 0 then
		local scaled = tries * mult
		local whole = math.floor(scaled)
		-- small try counts (1 per hit) would round away the bonus: keep the fraction as a chance
		if math.random() < scaled - whole then
			whole = whole + 1
		end
		return whole
	end
	return tries
end
skillCb:register(5)
-- World Loot: loot_config.lua's rateMult reads ChaosShopServices.buffMult("loot")

loadBuffs()

local startup = GlobalEvent("ChaosWorldBuffsStartup")
function startup.onStartup()
	loadBuffs()
	return true
end
startup:register()

-- announce the end of a buff (in memory: which buffs were running at the last check)
local running = {}
local think = GlobalEvent("ChaosWorldBuffsThink")
function think.onThink(interval)
	for _, def in ipairs(C().worldBuffs) do
		local active = S.buffLeft(def.id) > 0
		if running[def.id] and not active then
			Game.broadcastMessage(def.name .. " has ended.", MESSAGE_STATUS_WARNING)
		end
		running[def.id] = active
	end
	return true
end
think:interval(30000)
think:register()

local login = CreatureEvent("ChaosShopServicesLogin")
function login.onLogin(player)
	for _, line in ipairs(S.describeBuffs()) do
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "World buff active - " .. line)
	end
	if player:getStorageValue(ST.nameChangeTokens) > 0 then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "You have an unused name change: Character > Services.")
	end
	if player:getStorageValue(ST.vocationChangeTokens) > 0 then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE,
			"You have an unused vocation change: Character > Services.")
	end
	return true
end
login:register()

local buffsTalk = {} -- reached from the menu: Info & Services window (commands_ui.lua, id "worldbuffs")
function buffsTalk.onSay(player, words, param)
	local lines = S.describeBuffs()
	if #lines == 0 then
		player:sendTextMessage(MESSAGE_INFO_DESCR, "No world buff is active. Anyone can start one in the store (World Buffs).")
	else
		player:sendTextMessage(MESSAGE_INFO_DESCR, "Active world buffs:\n" .. table.concat(lines, "\n"))
	end
	return false
end
ChaosCommands.register("worldbuffs", function(player, param) return buffsTalk.onSay(player, "", param) end)

-- temple teleport scroll
local exhaust = {}
local scroll = Action()
function scroll.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	local cfg = C().templeScroll
	local now = os.time()
	if (exhaust[player:getId()] or 0) > now then
		player:sendCancelMessage("You are exhausted.")
		return true
	end
	exhaust[player:getId()] = now + cfg.cooldown
	local reason = S.teleportBlocked(player)
	if reason then
		player:sendCancelMessage(reason)
		player:getPosition():sendMagicEffect(CONST_ME_POFF)
		return true
	end
	local temple = player:getTown():getTemplePosition()
	local uses = tonumber(item:getCustomAttribute("chaos_uses")) or 1
	player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
	player:teleportTo(temple)
	temple:sendMagicEffect(CONST_ME_TELEPORT)
	if uses <= 1 then
		item:remove(1)
		player:sendTextMessage(MESSAGE_INFO_DESCR, "The scroll crumbles to dust.")
	else
		setScrollUses(item, uses - 1)
		player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("Your scroll has %d use%s left.", uses - 1, uses - 1 == 1 and "" or "s"))
	end
	return true
end
scroll:aid(C().templeScroll.actionId)
scroll:register()

-- ------------------------------------------------------------------------ !changename
-- tables that keep a character's name as text (the rest of the Chaos tables use the player id)
local function renameReferences(guid, oldName, newName)
	local rows = Chaos.select("SELECT r.`id` AS `id`, r.`names` AS `names` FROM `" .. Chaos.tables.dungeonRuns ..
		"` r JOIN `" .. Chaos.tables.dungeonRunPlayers .. "` p ON p.`run_id` = r.`id` WHERE p.`player_id` = " .. guid,
		{{"id", "n"}, {"names", "s"}})
	for _, row in ipairs(rows) do
		local list = {}
		for line in (row.names .. "\n"):gmatch("([^\n]*)\n") do
			list[#list + 1] = line == oldName and newName or line
		end
		db.query("UPDATE `" .. Chaos.tables.dungeonRuns .. "` SET `names` = " .. db.escapeString(table.concat(list, "\n")) ..
			" WHERE `id` = " .. row.id)
	end
	-- stock tables: death list and guild war kills store killer names
	local o, n = db.escapeString(oldName), db.escapeString(newName)
	db.query("UPDATE `player_deaths` SET `killed_by` = " .. n .. " WHERE `is_player` = 1 AND `killed_by` = " .. o)
	db.query("UPDATE `player_deaths` SET `mostdamage_by` = " .. n .. " WHERE `mostdamage_is_player` = 1 AND `mostdamage_by` = " .. o)
	db.query("UPDATE `guildwar_kills` SET `killer` = " .. n .. " WHERE `killer` = " .. o)
	db.query("UPDATE `guildwar_kills` SET `target` = " .. n .. " WHERE `target` = " .. o)
end

local function nameTaken(name)
	local rows = Chaos.select("SELECT `id` FROM `players` WHERE `name` = " .. db.escapeString(name) .. " LIMIT 1", {{"id", "n"}})
	return rows[1] ~= nil
end

-- give a token back to an offline character (the rename could not be applied)
local function refundTokenOffline(guid, storage)
	db.query("INSERT INTO `player_storage` (`player_id`, `key`, `value`) VALUES (" .. guid .. ", " .. storage ..
		", 1) ON DUPLICATE KEY UPDATE `value` = 1")
end

local function applyRename(guid, oldName, newName, tries)
	if onlineByGuid(guid) then
		if tries < 30 then
			addEvent(applyRename, 1000, guid, oldName, newName, tries + 1)
		else
			print(string.format("[Chaos store] rename %s -> %s not applied: the character stayed online", oldName, newName))
		end
		return
	end
	if nameTaken(newName) then
		refundTokenOffline(guid, ST.nameChangeTokens)
		print(string.format("[Chaos store] rename %s -> %s refused at apply time (name taken); token refunded", oldName, newName))
		return
	end
	db.query("UPDATE `players` SET `name` = " .. db.escapeString(newName) .. " WHERE `id` = " .. guid)
	renameReferences(guid, oldName, newName)
	print(string.format("[Chaos store] renamed %s -> %s (id %d)", oldName, newName, guid))
end
S.applyRename = applyRename

local renameTalk = {} -- reached from the menu: Info & Services window (commands_ui.lua, id "changename")
function renameTalk.onSay(player, words, param)
	if player:getStorageValue(ST.nameChangeTokens) < 1 then
		player:sendCancelMessage("You need a Name Change from the store first.")
		return false
	end
	if trim(param) == "" then
		player:sendTextMessage(MESSAGE_INFO_DESCR, "Type the new name (3-20 letters, single spaces, " ..
			"in a protection zone, out of combat). You will be logged out and log in with the new name.")
		return false
	end
	local name, err = S.validateName(param)
	if not name then
		player:sendCancelMessage(err)
		return false
	end
	if name == player:getName() then
		player:sendCancelMessage("That is already your name.")
		return false
	end
	if nameTaken(name) or MonsterType(name) then
		player:sendCancelMessage("That name is already taken.")
		return false
	end
	if inCombat(player) then
		player:sendCancelMessage("You cannot change your name in combat.")
		return false
	end
	if not inProtectionZone(player) then
		player:sendCancelMessage("Go to a protection zone (a temple or a depot) first.")
		return false
	end
	local guid, oldName = player:getGuid(), player:getName()
	player:setStorageValue(ST.nameChangeTokens, 0)
	player:save()
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Your name is now " .. name .. ". You will be logged out: log in as " .. name .. ".")
	player:popupFYI("Your name is now " .. name .. ".\nYou will be logged out now. Log in again with the new name.")
	player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
	addEvent(function(cid)
		local p = Player(cid)
		if p then
			p:remove() -- kicks and saves the character (storage included)
		end
		addEvent(applyRename, 500, guid, oldName, name, 0)
	end, 1500, player:getId())
	return false
end
ChaosCommands.register("changename", function(player, param) return renameTalk.onSay(player, "", param) end)

-- ------------------------------------------------------------------------ !changevocation
local vocTalk = {} -- reached from the menu: Info & Services window (commands_ui.lua, id "changevocation")
function vocTalk.onSay(player, words, param)
	if player:getStorageValue(ST.vocationChangeTokens) < 1 then
		player:sendCancelMessage("You need a Vocation Change from the store first.")
		return false
	end
	local current = player:getVocation()
	local newId, err = S.vocationFor(param, current:getId())
	if not newId then
		player:sendTextMessage(MESSAGE_INFO_DESCR, "Choose one of: " .. C().vocationWords:gsub("|", ", ") .. ". " .. err)
		return false
	end
	local newVoc = Vocation(newId)
	if not newVoc then
		player:sendCancelMessage("That vocation does not exist on this server.")
		return false
	end
	-- the class lock (class_unlocks.lua): a locked class needs the account's unlock; the token is kept
	if ChaosClassUnlocks and ChaosClassUnlocks.canUseVocation then
		local allowed, lockMessage = ChaosClassUnlocks.canUseVocation(player, newId)
		if not allowed then
			player:sendTextMessage(MESSAGE_INFO_DESCR, (lockMessage or "That class is locked. Unlock it in the store.")
				.. " Your Vocation Change is kept.")
			return false
		end
	end
	if inCombat(player) then
		player:sendCancelMessage("You cannot change your vocation in combat.")
		return false
	end
	if not inProtectionZone(player) then
		player:sendCancelMessage("Go to a protection zone (a temple or a depot) first.")
		return false
	end
	local stats = S.recomputeStats(player:getLevel(), C().vocationBaseLevel, player:getCapacity(),
		{hp = current:getHealthGain(), mana = current:getManaGain(), cap = current:getCapacityGain()},
		{hp = newVoc:getHealthGain(), mana = newVoc:getManaGain(), cap = newVoc:getCapacityGain()})
	player:setStorageValue(ST.vocationChangeTokens, 0)
	player:setVocation(newVoc)
	player:setMaxHealth(stats.health)
	player:setMaxMana(stats.mana)
	player:setCapacity(stats.cap)
	-- setHealth stops at the base maximum (without vitality bonuses); this engine's addHealth takes
	-- (damage type, amount) and heals up to the full maximum (stock TFS reads a string there as 0: no-op)
	player:setHealth(player:getMaxHealth())
	local missing = player:getMaxHealth() - player:getHealth()
	if missing > 0 then
		pcall(player.addHealth, player, "healing", missing)
	end
	player:addMana(player:getMaxMana())
	if ChaosPassiveTree and ChaosPassiveTree.resetAll then
		ChaosPassiveTree.resetAll(player)
	end
	-- classes.lua: the Ninja's off-hand rule, a pending free switch of the migration is spent, and the client learns
	-- the vocation without a relog
	player:setStorageValue(Chaos.classes.storage.freeSwitch, -1)
	if ChaosClasses then
		if ChaosClasses.afterVocationChange then
			ChaosClasses.afterVocationChange(player)
		else
			ChaosClasses.syncDualWield(player)
		end
	end
	player:save()
	player:getPosition():sendMagicEffect(CONST_ME_HOLYAREA)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format(
		"You are now %s. Health, mana and capacity follow the new vocation; skills and magic level are kept; your passive tree was reset for free. Relog if anything looks stale.",
		newVoc:getDescription()))
	return false
end
ChaosCommands.register("changevocation", function(player, param) return vocTalk.onSay(player, "", param) end)
