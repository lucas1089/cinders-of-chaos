-- exercise_training.lua: the exercise (training) weapons used on a training dummy. Replaces the base server's
-- actions/scripts/other/exercise_weapons.lua (tools/patch_exercise_weapons.py takes its 21 lines out of actions.xml, so
-- this revscript owns the item ids). Rules: exercise_core.lua, numbers and lists: exercise_config.lua, tests:
-- tests/exercise_test.lua, overview: server/README.md "Training weapons". Lua 5.1 / LuaJIT compatible.
--
-- What it does differently from the base script (owner request 2026-10-23, and the review that followed):
--   * one melee weapon: the sword and club ones work the same, for the Warrior, Thief and Templar lines (the melee
--     skill that counts: the best of sword / club / axe); the Monk line has its own fist weapon (owner 2026-10-28), which
--     trains fist fighting, the skill its hits and spells use
--   * the Monk (fist, shielding), the Templar (magic level) and every class (shielding) have a weapon of their own
--   * a charge is taken only for a step that trains (the base script took it before the vocation check, so a refused
--     click used a charge); a locked class, a tile outside a protection zone or a dummy out of reach trains nothing
--   * one chain of steps per player: the base script's "already training" click reset the flag its own chain set, so
--     N clicks ran N chains, N times as fast; a ranged weapon needed no range check (allowfaruse), so a modified
--     client could train on a dummy anywhere on its floor
--   * the training flag (Exercise_Training.isTraining, read by the Idle Hall) is cleared whenever a chain ends and at
--     login (the base script left it at 1 after a logout, which kept the character out of the Idle Hall for good)
--   * a weapon the class cannot use turns into the one it can on first use, charges kept (exercise_config.lua tiers)

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
dofile("data/scripts/chaos/exercise_core.lua")
local E = ChaosExercise
local cfg = E.cfg

local unpack = unpack or table.unpack

local TRAINING_STORAGE = (type(Exercise_Training) == "table" and tonumber(Exercise_Training.isTraining)) or 37100

local SKILL_ID = {fist = SKILL_FIST, sword = SKILL_SWORD, club = SKILL_CLUB, axe = SKILL_AXE, distance = SKILL_DISTANCE,
	shield = SKILL_SHIELD}

local function nowMs()
	if os.mtime then
		return os.mtime()
	end
	return os.time() * 1000
end

local function say(player, key, ...)
	player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, key, ...))
end

local function stop(pid, gen, key)
	E.endChain(pid, gen)
	local player = Player(pid)
	if player then
		player:setStorageValue(TRAINING_STORAGE, 0)
		if key then
			say(player, key)
		end
	end
end

local function chargesOf(item)
	if item:hasAttribute(ITEM_ATTRIBUTE_CHARGES) then
		return tonumber(item:getAttribute(ITEM_ATTRIBUTE_CHARGES)) or 0
	end
	return tonumber(ItemType(item:getId()):getCharges()) or 0
end

-- a charge less, shown to the client at once (item:sendUpdate, engine patch 0003) or by a transform to the same id
local function takeCharge(item, charges)
	local left = charges - 1
	if item.sendUpdate then
		item:setAttribute(ITEM_ATTRIBUTE_CHARGES, left)
		item:sendUpdate()
	elseif left >= 1 then
		item:transform(item:getId(), left)
	else
		item:setAttribute(ITEM_ATTRIBUTE_CHARGES, 0)
	end
	return left
end

local function inProtectionZone(pos)
	local tile = Tile(pos)
	return tile ~= nil and tile:hasFlag(TILESTATE_PROTECTIONZONE)
end

local function restricted(player)
	local U = ChaosClassUnlocks
	return U ~= nil and U.isRestricted ~= nil and U.isRestricted(player) == true
end

-- the melee levels the rate and the target skill are worked out from
local function meleeFacts(player)
	local levels, percents = {}, {}
	for _, name in ipairs({"sword", "club", "axe"}) do
		levels[name] = player:getEffectiveSkillLevel(SKILL_ID[name])
		percents[name] = player:getSkillPercent(SKILL_ID[name])
	end
	return levels, percents
end

-- one training step: validate, take a charge, give the tries, schedule the next step
local function step(pid, gen, startPos, itemId, dummyPos, dummyId)
	local player = Player(pid)
	if not player then
		E.endChain(pid, gen)
		return
	end
	if not E.isCurrent(pid, gen) then
		return -- another chain replaced this one
	end
	local dummy = Tile(Position(dummyPos.x, dummyPos.y, dummyPos.z))
	if not dummy or not dummy:getItemById(dummyId) then
		return stop(pid, gen, "Your training has stopped.")
	end
	local pos = player:getPosition()
	if pos.x ~= startPos.x or pos.y ~= startPos.y or pos.z ~= startPos.z or not inProtectionZone(pos) then
		return stop(pid, gen, "Your training has stopped.")
	end
	local kind = E.kindOf(itemId)
	local vocation = player:getVocation():getId()
	if not kind or not E.allowed(kind, vocation) or restricted(player) then
		return stop(pid, gen, "Your training has stopped.")
	end
	local item = player:getItemById(itemId, true)
	if not item or not item:isItem() then
		return stop(pid, gen, "Your training has stopped.")
	end
	local charges = chargesOf(item)
	if charges < 1 then
		item:remove(1)
		return stop(pid, gen, "Your training weapon vanished.")
	end

	local bonus = E.dummyKind(dummyId) == "bonus"
	local levels, percents
	if kind == "melee" then
		levels, percents = meleeFacts(player)
	end
	local skill = E.skillFor(kind, vocation, levels, percents)
	local left = takeCharge(item, charges)
	player:resetIdleTime()
	if skill == "magic" then
		local rate = tonumber(configManager.getNumber(configKeys.RATE_MAGIC)) or 1
		player:addManaSpent(E.step(kind, player:getMagicLevel(), rate, bonus))
	else
		local rate = tonumber(configManager.getNumber(configKeys.RATE_SKILL)) or 1
		player:addSkillTries(SKILL_ID[skill], E.step(kind, player:getEffectiveSkillLevel(SKILL_ID[skill]), rate, bonus))
	end
	Position(dummyPos.x, dummyPos.y, dummyPos.z):sendMagicEffect(CONST_ME_HITAREA)
	local ani = cfg.kinds[kind].ani
	if ani and _G[ani] then
		pos:sendDistanceEffect(Position(dummyPos.x, dummyPos.y, dummyPos.z), _G[ani])
	end

	if left < 1 then
		local last = player:getItemById(itemId, true)
		if last and last:isItem() then
			last:remove(1)
		end
		return stop(pid, gen, "Your training weapon vanished.")
	end
	E.touchChain(pid, gen, nowMs())
	player:setStorageValue(TRAINING_STORAGE, 1)
	addEvent(step, cfg.tickMs, pid, gen, startPos, itemId, dummyPos, dummyId)
end

-- a weapon the class cannot train with becomes the one it can, of the same tier, charges kept (E.convertTo: the club
-- weapon of before and the fist weapon of a non-Monk become the sword one, a Monk's sword or club one the fist one); any
-- failure leaves the item as it was
local function convert(player, item)
	local to = E.convertTo(item:getId(), player:getVocation():getId())
	if not to then
		return item:getId()
	end
	local ok = pcall(item.transform, item, to, chargesOf(item))
	if ok and player:getItemById(to, true) then
		return to
	end
	return item:getId()
end

local function onUse(player, item, fromPosition, target, toPosition, isHotkey)
	local itemId = item:getId()
	local kind = E.kindOf(itemId)
	if not kind then
		return false
	end
	if target == nil or not target.isItem or not target:isItem() then
		say(player, "Use it on a training dummy.")
		return true
	end
	local dummyId = target:getId()
	if not E.dummyKind(dummyId) then
		say(player, "Use it on a training dummy.")
		return true
	end
	local vocation = player:getVocation():getId()
	if not E.allowed(kind, vocation) and E.convertTo(itemId, vocation) and not restricted(player) then
		-- the right weapon of the tier for this class (a Monk's sword weapon, a Warrior's old exercise axe): turn it now
		itemId = convert(player, item)
		kind = E.kindOf(itemId)
		item = player:getItemById(itemId, true) or item
	end
	if not E.allowed(kind, vocation) then
		local key, args = E.refusal(kind, vocation)
		say(player, key, unpack(args))
		return true
	end
	if restricted(player) then
		say(player, "Your class is locked: nothing is trained.")
		return true
	end
	local pos, dummyPos = player:getPosition(), target:getPosition()
	local reachable, why = E.reach(kind, dummyPos.x - pos.x, dummyPos.y - pos.y, dummyPos.z - pos.z)
	if not reachable then
		local text = "Get closer to the dummy."
		if why == "floor" then
			text = "The dummy is on another floor."
		end
		say(player, text)
		return true
	end
	if not inProtectionZone(pos) then
		say(player, "You can only train in a protection zone.")
		return true
	end
	if chargesOf(item) < 1 then
		item:remove(1)
		say(player, "Your training weapon vanished.")
		return true
	end
	local pid = player:getId()
	local gen = E.beginChain(pid, nowMs())
	if not gen then
		say(player, "You are already training.")
		return true
	end
	itemId = convert(player, item) -- an old club weapon (already the right one for the class otherwise)
	say(player, "You started training.")
	step(pid, gen, {x = pos.x, y = pos.y, z = pos.z}, itemId, {x = dummyPos.x, y = dummyPos.y, z = dummyPos.z}, dummyId)
	return true
end

-- the weapons that reach over a distance work from afar (the engine does not walk the player there); every use is
-- range-checked above. Melee and shield weapons keep the engine's rule: the player walks next to the dummy.
local near, far = Action(), Action()
local nearIds, farIds = {}, {}
for id, kind in pairs(cfg.items) do
	local list = cfg.kinds[kind].ani and farIds or nearIds
	list[#list + 1] = id
end
table.sort(nearIds)
table.sort(farIds)
near.onUse = onUse
far.onUse = onUse
near:id(unpack(nearIds))
far:id(unpack(farIds))
far:allowFarUse(true)
near:register()
far:register()

-- the flag the Idle Hall reads: never left at 1 after a logout or a restart (no chain survives either)
local logout = CreatureEvent("ChaosExerciseLogout")
function logout.onLogout(player)
	E.endChain(player:getId())
	player:setStorageValue(TRAINING_STORAGE, 0)
	return true
end
logout:register()

local login = CreatureEvent("ChaosExerciseLogin")
function login.onLogin(player)
	player:registerEvent("ChaosExerciseLogout")
	player:setStorageValue(TRAINING_STORAGE, 0)
	return true
end
login:register()
