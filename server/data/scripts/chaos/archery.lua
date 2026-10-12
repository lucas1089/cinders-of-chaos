-- Infinite arrows and quivers, the engine side (server/README.md "Infinite arrows and quivers"). Pure logic and numbers:
-- data/lib/chaos_archery_core.lua, data/lib/chaos_archery_config.lua; the hit: weapon_styles.lua; the totals:
-- item_mods.lua (a quiver counts only while a bow or crossbow is held). Tests: server/tests/archery_test.lua.
--
--   * the quiver's Distance Fighting: one attribute condition of its own sub id, kept at the total (ChaosArchery.apply,
--     called by item_mods.lua whenever the totals are worked out again)
--   * the quiver's Attack Speed with Bows: written on the launcher in the hands ("chaos_qspd") and folded into its
--     attack interval (chaos_item_mods.lua syncAttackSpeed); taken off again when the launcher leaves the hands
--   * launchers made before the patch: an attack attribute from a rarity roll or a unique still holds the old attack
--     without ammunition; it gets its band's attack once (A.legacyAttack), the hit chance attribute goes (the engine
--     fires with the type's hit chance). At login for the inventory, and whenever a launcher reaches a hand.
--   * the ammunition sweep, once per character (storage +0): every arrow and bolt in the inventory, the depots and the
--     inbox goes, the refund goes to the bank, then the character is saved. All of that is in memory and is saved as one
--     (Chaos.saveCharacter); a crash before the save keeps nothing and the next login sweeps again. The stash (a database
--     table) is its own step (storage +1): the refund and the mark are saved first, the rows deleted after a good save;
--     a failed save takes the refund and the mark back and leaves the rows for the next login. Nothing to sweep (a
--     character made after the update): only the marks are set, no save (they go with the next save).
--   * the hands at login (A.checkHands): the quiver is worn in the shield hand next to a bow or crossbow and the
--     ammunition slot is a second ring slot, rings only (engine src-patch 0023); the engine loads a character without
--     its slot rules, so a quiver left in the ammunition slot moves to the shield hand (else the backpack or the
--     inbox), anything else there that is no ring goes to the backpack or the inbox, as does an off-hand item the
--     rules refuse. A ring there stays. One might ring at a time (0023): with a might ring in both ring slots, the one
--     in the second ring slot goes to the backpack or the inbox. Saved at once; idempotent.
--   * later arrivals (a map chest, a trade, the market): ammunition that reaches a character's inventory is turned into
--     its refund at once; every later login looks at the inventory again (a base script reward the install tool did
--     not know).
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosArchery then
	dofile("data/lib/chaos_archery_core.lua")
end
local A = ChaosArchery
local cfg = A.config
local STORE_DONE = cfg.storage
local STASH_DONE = cfg.storage + 1

local function log(text)
	print("[Chaos archery] " .. text)
end

-- ---------------------------------------------------------------- the quiver's skill and attack speed
local appliedSkill = {} -- player id -> the Distance Fighting the condition holds

function A.applySkill(player, want)
	local id = player:getId()
	want = math.max(0, math.floor(tonumber(want) or 0))
	-- the first call of a session always clears: a condition of the last session may have been saved with the character
	if appliedSkill[id] ~= nil and appliedSkill[id] == want then
		return false
	end
	local subId = cfg.effects.conditionSubId
	player:removeCondition(CONDITION_ATTRIBUTES, CONDITIONID_DEFAULT, subId, true)
	if want > 0 then
		local c = Condition(CONDITION_ATTRIBUTES, CONDITIONID_DEFAULT)
		c:setParameter(CONDITION_PARAM_SUBID, subId)
		c:setParameter(CONDITION_PARAM_TICKS, -1)
		c:setParameter(CONDITION_PARAM_SKILL_DISTANCE, want)
		player:addCondition(c)
	end
	appliedSkill[id] = want
	return true
end

-- the launcher's quiver speed attribute to `pct` (0 removes it), and its attack interval with it
function A.setLauncherSpeed(item, pct)
	local M = ChaosItemMods
	local key = M.QUIVER_SPEED
	local have = tonumber(item:getCustomAttribute(key)) or 0
	pct = math.max(0, math.floor(tonumber(pct) or 0))
	if have == pct then
		return false
	end
	if pct > 0 then
		item:setCustomAttribute(key, pct)
	else
		item:removeCustomAttribute(key)
	end
	M.syncAttackSpeed(item)
	M.sendUpdate(item)
	return true
end

-- item_mods.lua: after the totals of a character are worked out (they hold the quiver only while it counts)
function A.apply(player, totals)
	A.applySkill(player, totals and totals.bowdistance or 0)
	local M = ChaosItemMods
	local kind, launcher = M.handLauncher(player)
	if kind and launcher then
		A.setLauncherSpeed(launcher, totals and totals.bowspeed or 0)
	end
end

-- ---------------------------------------------------------------- launchers made before the patch
local function patchedType(it)
	-- the install tool took the ammunition type away; on a base server without it nothing changes
	return it and A.isLauncherType(it) and it:getAmmoType() == 0
end

-- returns true when the item changed
function A.migrate(item)
	local id = item:getId()
	local it = ItemType(id)
	if not A.launcherOf(id, it) or not patchedType(it) then
		return false
	end
	local changed = false
	if item:hasAttribute(ITEM_ATTRIBUTE_ATTACK) then
		local v = A.legacyAttack(item:getAttribute(ITEM_ATTRIBUTE_ATTACK), it:getAttack(), id, it)
		if v then
			item:setAttribute(ITEM_ATTRIBUTE_ATTACK, v)
			changed = true
		end
	end
	if item:hasAttribute(ITEM_ATTRIBUTE_HITCHANCE) then
		item:removeAttribute(ITEM_ATTRIBUTE_HITCHANCE)
		changed = true
	end
	if changed then
		ChaosItemMods.sendUpdate(item)
	end
	return changed
end

-- ---------------------------------------------------------------- walking a character's items
local function walk(item, fn)
	fn(item)
	if item:isContainer() then
		for _, inner in ipairs(item:getItems(true) or {}) do
			fn(inner)
		end
	end
end

-- every item of the inventory, the depot chests (every town) and the inbox
function A.belongings(player, withDepots)
	local out = {}
	local function add(item)
		out[#out + 1] = item
	end
	for slot = CONST_SLOT_FIRST or 1, CONST_SLOT_LAST or 10 do
		local item = player:getSlotItem(slot)
		if item then
			walk(item, add)
		end
	end
	if withDepots then
		for _, town in ipairs(Game.getTowns() or {}) do
			local ok, chest = pcall(function() return player:getDepotChest(town:getId(), false) end)
			if ok and chest then
				for _, item in ipairs(chest:getItems(true) or {}) do
					add(item)
				end
			end
		end
		local okI, inbox = pcall(function() return player:getInbox() end)
		if okI and inbox then
			for _, item in ipairs(inbox:getItems(true) or {}) do
				add(item)
			end
		end
	end
	return out
end

local function entriesOf(items)
	local entries = {}
	for _, item in ipairs(items) do
		local id = item:getId()
		entries[#entries + 1] = {id = id, count = item:getCount(), it = ItemType(id), item = item}
	end
	return entries
end

local function credit(player, gold)
	if gold ~= 0 then
		player:setBankBalance(player:getBankBalance() + gold)
	end
end

-- ---------------------------------------------------------------- the one-time sweep
-- inventory, depots and inbox. Returns pieces, gold, saved
function A.sweepItems(player)
	if player:getStorageValue(STORE_DONE) == 1 then
		-- done once; later logins look at the inventory only (a script reward that still gave ammunition). In memory
		-- like the rest, saved with the character.
		local take, gold, pieces = A.plan(entriesOf(A.belongings(player, false)))
		for _, e in ipairs(take) do
			e.item:remove()
		end
		credit(player, gold)
		return pieces, gold, true
	end
	local take, gold, pieces = A.plan(entriesOf(A.belongings(player, true)))
	player:setStorageValue(STORE_DONE, 1)
	if #take == 0 then
		-- nothing to sweep (every character made after the update): only the mark, saved with the character. No save
		-- here: two full saves at every first login were most of its database writes (a login rush on a busy disk)
		return 0, 0, true
	end
	for _, e in ipairs(take) do
		e.item:remove()
	end
	credit(player, gold)
	local saved = Chaos.saveCharacter(player)
	if not saved then
		-- everything above is in memory: the next save (the logout's) keeps it all together
		log(player:getName() .. ": the save after the ammunition sweep failed; the logout save keeps it")
	end
	return pieces, gold, saved
end

-- the stash rows (chaos_stash: player_id, item_id, count). Returns pieces, gold, done
function A.sweepStash(player)
	if player:getStorageValue(STASH_DONE) == 1 then
		return 0, 0, true
	end
	local T = Chaos.tables and Chaos.tables.stash
	if not T or not db then
		return 0, 0, false
	end
	local guid = player:getGuid()
	local rows = Chaos.select("SELECT `item_id`, `count` FROM `" .. T .. "` WHERE `player_id` = " .. guid,
		{{"item_id", "n"}, {"count", "n"}})
	if #rows == 0 then
		-- no stash rows: only the mark, saved with the character (a crash before that looks at the empty stash again)
		player:setStorageValue(STASH_DONE, 1)
		return 0, 0, true
	end
	local entries = {}
	for _, r in ipairs(rows) do
		entries[#entries + 1] = {id = r.item_id, count = r.count, it = ItemType(r.item_id)}
	end
	local take, gold, pieces = A.plan(entries)
	-- save the refund and the mark first; the rows go only after the save, so a crash never pays twice
	credit(player, gold)
	player:setStorageValue(STASH_DONE, 1)
	if not Chaos.saveCharacter(player) then
		credit(player, -gold)
		player:setStorageValue(STASH_DONE, -1)
		log(player:getName() .. ": the save before the stash sweep failed; the stash is swept at the next login")
		return 0, 0, false
	end
	for _, e in ipairs(take) do
		db.query("DELETE FROM `" .. T .. "` WHERE `player_id` = " .. guid .. " AND `item_id` = " .. math.floor(e.id))
	end
	return pieces, gold, true
end

function A.sweep(player)
	local p1, g1 = A.sweepItems(player)
	local p2, g2 = A.sweepStash(player)
	local pieces, gold = p1 + p2, g1 + g2
	if pieces > 0 then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE or MESSAGE_INFO_DESCR, A.refundText(pieces, gold))
	end
	return pieces, gold
end

-- ---------------------------------------------------------------- the hands and the ammunition slot at login
-- The engine (src-patch 0023) takes only rings in the ammunition slot (the second ring slot) and refuses every pair of
-- hands A.handsAllowed refuses, but it loads a character without asking. A quiver of before in the ammunition slot
-- goes to the shield hand when that is free and allowed (the engine asks again: vocation and level of movements.xml),
-- else to the backpack (or a container in it), else to the inbox; so does anything else there that is no ring, and an
-- off-hand item the rules refuse. A ring in the second ring slot stays, unless it is a might ring and the ring slot
-- holds one too (one might ring at a time; the one in the ring slot stays). All of it is
-- in memory and saved with the character as one (Chaos.saveCharacter right after); a crash before the save leaves the
-- old state and the next login moves it again. Nothing to move: nothing changes (idempotent without a mark).
-- into the backpack or a container in it, else the inbox; never merged into a stack
function A.stow(player, item)
	local flags = (FLAG_NOLIMIT or 1) + (FLAG_IGNOREAUTOSTACK or 0)
	local bp = player:getSlotItem(CONST_SLOT_BACKPACK)
	if bp and bp:isContainer() then
		if item:moveTo(bp, flags) then
			return "backpack"
		end
		for _, c in ipairs(bp:getItems(true) or {}) do
			if c:isContainer() and c ~= item and item:moveTo(c, flags) then
				return "backpack"
			end
		end
	end
	local okI, inbox = pcall(function() return player:getInbox() end)
	if okI and inbox and item:moveTo(inbox, flags) then
		return "inbox"
	end
	return nil
end

-- a copy is placed in the shield hand, then the item itself is removed (one item, moved; as loadouts.lua does)
local function toOffHand(player, item)
	local copy = item:clone()
	if copy and player:addItemEx(copy, false, CONST_SLOT_RIGHT, 0) == RETURNVALUE_NOERROR then
		item:remove()
		return true
	end
	return false
end

-- returns the number of items moved
function A.checkHands(player)
	local slots = {main = CONST_SLOT_LEFT, off = CONST_SLOT_RIGHT, ammo = CONST_SLOT_AMMO}
	local items, state = {}, {}
	for key, slot in pairs(slots) do
		local item = slot and player:getSlotItem(slot)
		if item then
			items[key] = item
			state[key] = A.handKind(ItemType(item:getId())) or "other"
		end
	end
	local ring = player:getSlotItem(CONST_SLOT_RING)
	state.ringMight = ring ~= nil and A.isMightRing(ItemType(ring:getId()))
	state.ammoMight = items.ammo ~= nil and A.isMightRing(ItemType(items.ammo:getId()))
	local moved, lines, mightLines = 0, {}, {}
	for _, step in ipairs(A.loginPlan(state)) do
		local item = items[step.from]
		local name = item and item:getName() or "?"
		local where
		if item and step.to == "off" and toOffHand(player, item) then
			where = "your off-hand"
		elseif item then
			local s = A.stow(player, item)
			where = s == "backpack" and "your backpack" or s == "inbox" and "your inbox" or nil
		end
		if where then
			moved = moved + 1
			local into = step.why == "might" and mightLines or lines
			into[#into + 1] = name .. " -> " .. where
		else
			log(player:getName() .. ": could not move " .. name .. " out of slot " .. tostring(slots[step.from]))
		end
	end
	if moved > 0 then
		if not Chaos.saveCharacter(player) then
			log(player:getName() .. ": the save after the hands check failed; the logout save keeps it")
		end
		if #lines > 0 then
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE or MESSAGE_INFO_DESCR, "The ammunition slot is a second ring slot now and " ..
				"quivers are worn in the off-hand next to a bow or crossbow. Moved: " .. table.concat(lines, ", ") .. ".")
		end
		if #mightLines > 0 then
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE or MESSAGE_INFO_DESCR, "You can only wear one might ring at a time. " ..
				"Moved: " .. table.concat(mightLines, ", ") .. ".")
		end
		if ChaosItemMods and ChaosItemMods.refresh then
			pcall(ChaosItemMods.refresh, player, true)
		end
	end
	return moved
end

-- ---------------------------------------------------------------- events
local login = CreatureEvent("ChaosArcheryLogin")
function login.onLogin(player)
	local okH, errH = pcall(A.checkHands, player)
	if not okH then
		log("hands check of " .. player:getName() .. " failed: " .. tostring(errH))
	end
	local ok, err = pcall(A.sweep, player)
	if not ok then
		log("sweep of " .. player:getName() .. " failed: " .. tostring(err))
	end
	for _, item in ipairs(A.belongings(player, false)) do
		pcall(A.migrate, item)
	end
	return true
end
login:register()

local logout = CreatureEvent("ChaosArcheryLogout")
function logout.onLogout(player)
	appliedSkill[player:getId()] = nil
	return true
end
logout:register()

local function isHandPos(pos)
	local inv = CONTAINER_POSITION or 0xFFFF
	return pos.x == inv and math.floor(pos.y / 64) % 2 == 0 and (pos.y == CONST_SLOT_LEFT or pos.y == CONST_SLOT_RIGHT)
end

local moved = EventCallback
moved.onItemMoved = function(player, item, count, fromPosition, toPosition, fromCylinder, toCylinder)
	if not item or not player then
		return
	end
	local id = item:getId()
	-- ammunition that reached a character (a map chest, a trade, the market): its refund instead
	if toPosition.x == (CONTAINER_POSITION or 0xFFFF) and A.isAmmoId(id, ItemType(id)) then
		local n = item:getCount()
		local gold = A.refundOf(id, n)
		if item:remove() then
			credit(player, gold)
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE or MESSAGE_INFO_DESCR, A.refundText(n, gold))
		end
		return
	end
	if not A.launcherOf(id, ItemType(id)) then
		return
	end
	if isHandPos(toPosition) then
		A.migrate(item)
	elseif isHandPos(fromPosition) and ChaosItemMods then
		-- the quiver's speed belongs to the wielder, not to the bow
		A.setLauncherSpeed(item, 0)
	end
end
moved:register(12) -- after base_rarity.lua (10) and item_mods.lua (11)
