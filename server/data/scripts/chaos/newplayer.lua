-- New players (roadmap item 21): the starter kit per class on the first login, a one-time welcome, milestone gifts at
-- levels 20 / 50 / 100 / 200 and the staff command /newplayerkit. The tutorial island is newplayer_tutorial.lua; the
-- pure logic (kit lookup, flags, milestones, island layout) newplayer_core.lua; every number newplayer_config.lua.
-- Overview: server/README.md "New players".
--
-- Kit: a brand-new character (lastLoginSaved 0, kit storage never set) gets the kit of its class. With the tutorial
-- island on, it gets it when it leaves the island instead (exit or !skiptutorial). Existing characters never get one
-- by logging in. The base server's own first-login items (creaturescripts/firstitems.lua) only equip vocation 0, which
-- the kit skips; the base starter chest (scripts/customs/actions/first_chest.lua, storage 33735) is marked as opened
-- when the kit is given, so nobody collects both. No base file is changed.
--
-- Home town: a brand-new character moves to the main city (newplayer_config.lua homeTown, Cinderhold) once, at its
-- first login (NP.settleHome); characters that have their kit keep their town (server/README.md "Main city").
--
-- Other scripts: ChaosNewPlayer.kitFor(vocationId) (newplayer_core.lua) returns a vocation's kit;
-- ChaosNewPlayer.setKit(name, def, {vocationIds}) adds or changes one (docs/CLASSES.md).
--
-- Assumed engine API (TFS 1.4): Player:getLastLoginSaved, getSlotItem, addItem(id, n, canDrop, subType, slot),
-- Container:addItem, Item:setActionId/setAttribute/setCustomAttribute, Player:addMoney, getInbox, ModalWindow,
-- CreatureEvent login/advance, TalkAction.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
if not ChaosNewPlayer or not ChaosNewPlayer.kitFor then
	dofile("data/scripts/chaos/newplayer_core.lua")
end

local NP = ChaosNewPlayer
local function C()
	return NP.cfg()
end

local SLOTS = {
	head = CONST_SLOT_HEAD, necklace = CONST_SLOT_NECKLACE, backpack = CONST_SLOT_BACKPACK, armor = CONST_SLOT_ARMOR,
	right = CONST_SLOT_RIGHT, left = CONST_SLOT_LEFT, legs = CONST_SLOT_LEGS, feet = CONST_SLOT_FEET,
	ring = CONST_SLOT_RING, ammo = CONST_SLOT_AMMO
}

local function getS(player, name)
	return player:getStorageValue(NP.key(name))
end

local function setS(player, name, value)
	player:setStorageValue(NP.key(name), value)
end
NP.getS, NP.setS = getS, setS

function NP.vocationName(vocId)
	local ok, voc = pcall(Vocation, vocId)
	if ok and voc then
		return voc:getName()
	end
	return "adventurer"
end

-- toast through game_chaosnotify (action "newplayer"; an older client ignores it)
function NP.toast(player, message)
	if ChaosOpcodes and ChaosOpcodes.notifications then
		player:sendExtendedOpcode(ChaosOpcodes.notifications, json.encode({action = "newplayer", message = message}))
	end
end

-- a server modal window (the client's game_modaldialog shows it); buttons = {{id, text}, ...}. The title and the button
-- texts are keys (Chaos.t: the player's language); the text comes translated.
function NP.modal(player, id, title, text, buttons)
	title = Chaos.t(player, title)
	if not ModalWindow then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, title .. ": " .. text)
		return
	end
	local w = ModalWindow(id, title, text)
	buttons = buttons or {{1, "Ok"}}
	for _, b in ipairs(buttons) do
		w:addButton(b[1], Chaos.t(player, b[2]))
	end
	w:setDefaultEnterButton(buttons[1][1])
	w:setDefaultEscapeButton(buttons[#buttons][1])
	w:sendToPlayer(player)
end

-- ------------------------------------------------------------------------------------------------ giving items
-- stackables into `container` (or anywhere), the rest to the inbox; returns true when the inbox was used
local function giveStack(player, container, id, count)
	local rest = count
	local stackable = ItemType(id):isStackable()
	while rest > 0 do
		local n = stackable and math.min(rest, 100) or 1
		local item = container and container:addItem(id, n)
		if not item then
			item = player:addItem(id, n, false)
		end
		if not item then
			break
		end
		rest = rest - n
	end
	if rest > 0 then
		local inbox = player:getInbox()
		while inbox and rest > 0 do
			local n = stackable and math.min(rest, 100) or 1
			inbox:addItem(id, n, INDEX_WHEREEVER or -1, FLAG_NOLIMIT)
			rest = rest - n
		end
		return true
	end
	return false
end
NP.giveStack = giveStack

-- the store's temple teleport scroll (shop_services.lua reads the same attributes)
local function makeScroll(player, container, uses)
	local cfg = Chaos.shopServices and Chaos.shopServices.templeScroll
	if not cfg or uses <= 0 then
		return nil
	end
	local item = container and container:addItem(cfg.itemId, 1) or player:addItem(cfg.itemId, 1, false)
	if not item then
		return nil
	end
	item:setActionId(cfg.actionId)
	item:setCustomAttribute("chaos_uses", uses)
	item:setAttribute(ITEM_ATTRIBUTE_NAME, cfg.name)
	item:setAttribute(ITEM_ATTRIBUTE_ARTICLE, "a")
	item:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, string.format(
		"Use it to return to your temple. Not usable in combat, dungeons, the tower or the world boss arena. %d use%s left.",
		uses, uses == 1 and "" or "s"))
	return item
end

-- the kit backpack: in the backpack slot when it is free, else inside the character's own backpack
local function kitContainer(player, kit)
	local main = player:getSlotItem(CONST_SLOT_BACKPACK)
	if not main then
		local bp = player:addItem(kit.backpackId, 1, false, 1, CONST_SLOT_BACKPACK)
		if bp and bp:isContainer() then
			return bp
		end
	elseif main:isContainer() then
		local bp = main:addItem(kit.backpackId, 1)
		if bp and bp:isContainer() then
			return bp
		end
	end
	local bp = player:addItem(kit.backpackId, 1, false)
	return (bp and bp:isContainer()) and bp or nil
end

-- give the kit of the player's vocation; returns true, kit or false, reason. Sets the kit flag.
function NP.giveKit(player)
	local vocId = player:getVocation():getId()
	local kit = NP.kitFor(vocId)
	if not kit then
		return false, "no kit for vocation " .. vocId
	end
	local container = kitContainer(player, kit)
	local inbox = false
	local level = player:getLevel()
	for _, e in ipairs(kit.equip) do
		local id, spare = NP.equipFor(e, level)
		local slot = SLOTS[e.slot]
		local placed = false
		if slot and not player:getSlotItem(slot) then
			placed = player:addItem(id, e.count or 1, false, 1, slot) ~= nil
		end
		if not placed then
			inbox = giveStack(player, container, id, e.count or 1) or inbox
		end
		if spare then
			inbox = giveStack(player, container, spare, 1) or inbox
		end
	end
	for _, b in ipairs(kit.backpack) do
		inbox = giveStack(player, container, b.id, b.count or 1) or inbox
	end
	makeScroll(player, container, kit.templeScrollUses)
	if kit.gold > 0 then
		player:addMoney(kit.gold)
	end
	setS(player, "kit", os.time())
	if C().baseChestStorage then
		player:setStorageValue(C().baseChestStorage, 1)
	end
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "You received the %s starter kit.%s",
		NP.vocationName(vocId), inbox and Chaos.t(player, " Some of it did not fit: it is in your inbox.") or ""))
	player:getPosition():sendMagicEffect(CONST_ME_GIFT_WRAPS or CONST_ME_MAGIC_BLUE)
	return true, kit
end

-- ------------------------------------------------------------------------------------------------ home town
-- a brand-new character (no kit yet) moves to the main city once (homeTown in the config, NP.homeTownFor). teleport:
-- also send it to the new temple (a first login without the tutorial island). Returns true when the town changed.
function NP.settleHome(player, teleport)
	local okT, town = pcall(function() return player:getTown() end)
	local cur = okT and town and town:getId() or 0
	local id = NP.homeTownFor(cur, NP.isSet(getS(player, "kit")))
	local home = id and Town(id)
	if not home then
		return false
	end
	player:setTown(home)
	if teleport then
		local temple = home:getTemplePosition()
		player:teleportTo(temple)
		temple:sendMagicEffect(CONST_ME_TELEPORT)
	end
	print("[newplayer] " .. player:getName() .. ": home town " .. tostring(cur) .. " -> " .. id)
	return true
end

-- ------------------------------------------------------------------------------------------------ welcome
function NP.showWelcome(player, force)
	if not force and NP.isSet(getS(player, "welcome")) then
		return false
	end
	local w = C().welcome
	setS(player, "welcome", 1)
	NP.modal(player, C().tutorial.modalBase, w.title,
		Chaos.t(player, w.text, player:getName(), NP.vocationName(player:getVocation():getId()),
			NP.giftLine(player:getLevel(), nil, Chaos.lang(player))))
	NP.toast(player, Chaos.t(player, w.toast))
	return true
end

-- kit (if not given yet) and welcome, a little later (the client must be in the game for the window)
function NP.kitAndWelcome(player, delayMs)
	local name = player:getName()
	addEvent(function()
		local p = Player(name)
		if not p then
			return
		end
		if not NP.isSet(getS(p, "kit")) then
			NP.giveKit(p)
		end
		NP.showWelcome(p)
	end, delayMs or C().welcome.delayMs)
end

-- ------------------------------------------------------------------------------------------------ milestones
function NP.giveMilestone(player, index)
	local m = C().milestones[index]
	if not m then
		return false
	end
	player:setStorageValue(NP.milestoneKey(index), os.time())
	local kit = NP.kitFor(player:getVocation():getId())
	local role = kit and kit.role or "melee"
	local parts, inbox = {}, false
	for _, it in ipairs(NP.milestoneItems(index, role)) do
		inbox = giveStack(player, nil, it.id, it.count) or inbox
		parts[#parts + 1] = it.count .. "x " .. ItemType(it.id):getName()
	end
	local text = Chaos.t(player, "Level %d gift: %s.%s", m.level, table.concat(parts, ", "),
		inbox and Chaos.t(player, " Your backpack was full: the rest is in your inbox.") or "")
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, text)
	NP.toast(player, text)
	player:getPosition():sendMagicEffect(CONST_ME_FIREWORK_YELLOW)
	return true
end

local advance = CreatureEvent("ChaosNewPlayerAdvance")
function advance.onAdvance(player, skill, oldLevel, newLevel)
	if skill ~= SKILL_LEVEL then
		return true
	end
	local due = NP.milestonesDue(oldLevel, newLevel, function(i)
		return NP.isSet(player:getStorageValue(NP.milestoneKey(i)))
	end)
	for _, i in ipairs(due) do
		NP.giveMilestone(player, i)
	end
	return true
end
advance:register()

-- ------------------------------------------------------------------------------------------------ login
local login = CreatureEvent("ChaosNewPlayerLogin")
function login.onLogin(player)
	player:registerEvent("ChaosNewPlayerAdvance")
	local first = player:getLastLoginSaved() <= 0
	-- the tutorial island (newplayer_tutorial.lua) takes new characters and resumes the ones on it
	if NP.tutorialLogin and NP.tutorialLogin(player, first) then
		return true
	end
	if NP.kitDueAtLogin(getS(player, "kit"), player:getLastLoginSaved()) and NP.kitFor(player:getVocation():getId()) then
		NP.settleHome(player, true)
		NP.kitAndWelcome(player)
	end
	return true
end
login:register()

-- ------------------------------------------------------------------------------------------------ staff command
-- /newplayerkit <name>            give the kit again (ignores the flag)
-- /newplayerkit <name>, welcome   show the welcome again
-- /newplayerkit <name>, milestone <n>  give milestone n (1..10, newplayer_config.lua milestones) again
-- /newplayerkit <name>, reset     clear every new-player flag (kit, welcome, milestones, tutorial)
-- /newplayerkit <name>, tutorial  send the character to the start of the tutorial island
local admin = TalkAction("/newplayerkit")
function admin.onSay(player, words, param)
	if not player:getGroup():getAccess() then
		return true
	end
	local name, what = param:match("^%s*([^,]+),%s*(.-)%s*$")
	name = (name or param):gsub("^%s+", ""):gsub("%s+$", "")
	what = (what or ""):lower()
	if name == "" then
		player:sendCancelMessage("Usage: /newplayerkit <player>[, welcome | milestone <n> | reset | tutorial]")
		return false
	end
	local target = Player(name)
	if not target then
		player:sendCancelMessage("Player " .. name .. " is not online.")
		return false
	end
	-- staff never give value (docs/GM_HANDBOOK.md section 2): the kit, a milestone and a reset (the kit and the
	-- milestones can be claimed again) need an administrator
	local value = what == "" or what == "kit" or what:match("^milestone") ~= nil or what == "reset"
	if not Chaos.staffCommand(player, words, param, value) then
		return false
	end
	local reply
	if what == "" or what == "kit" then
		local ok, res = NP.giveKit(target)
		reply = ok and ("Kit '" .. res.name .. "' given to " .. target:getName() .. ".") or ("No kit: " .. tostring(res))
	elseif what == "welcome" then
		NP.showWelcome(target, true)
		reply = "Welcome shown to " .. target:getName() .. "."
	elseif what:match("^milestone") then
		local n = tonumber(what:match("(%d+)"))
		reply = (n and NP.giveMilestone(target, n)) and ("Milestone " .. n .. " given.") or "Unknown milestone."
	elseif what == "reset" then
		local c = C()
		for key in pairs(c.storage) do
			if key ~= "milestone" then
				target:setStorageValue(NP.key(key), -1)
			end
		end
		for i = 1, #c.milestones do
			target:setStorageValue(NP.milestoneKey(i), -1)
		end
		reply = "New-player flags of " .. target:getName() .. " cleared."
	elseif what == "tutorial" then
		if NP.tutorialStart and NP.tutorialStart(target) then
			reply = target:getName() .. " starts the tutorial."
		else
			reply = "The tutorial island is not available."
		end
	else
		reply = "Unknown option '" .. what .. "'."
	end
	player:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, reply)
	print("[newplayer] " .. player:getName() .. ": /newplayerkit " .. param .. " -> " .. reply)
	return false
end
admin:separator(" ")
admin:register()
