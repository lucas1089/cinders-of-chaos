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
--     a failed save takes the refund and the mark back and leaves the rows for the next login.
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
	for _, e in ipairs(take) do
		e.item:remove()
	end
	credit(player, gold)
	player:setStorageValue(STORE_DONE, 1)
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

-- ---------------------------------------------------------------- events
local login = CreatureEvent("ChaosArcheryLogin")
function login.onLogin(player)
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
