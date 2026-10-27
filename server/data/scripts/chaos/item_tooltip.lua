-- Rich item tooltips (client game_itemtooltip, extended opcode ChaosOpcodes.itemTooltip). The client hovers an item in
-- its inventory or an open container and asks for its tooltip; holding Ctrl it also asks for the equipped items the
-- tooltip names in `cmp` and shows them side by side with the differences. What a tooltip holds is built by
-- item_tooltip_core.lua (ChaosItemTooltip.build); see server/README.md "Item attributes and rich tooltips".
--
-- Protocol (JSON {action, data}):
--   client -> server  get {items = [{pos = {x, y, z, s}, iid, cid, n}]}  up to ChaosItemTooltip.config.maxItems items;
--                     cid = the client id of the hovered item, n = its count (stackables): T.matchIndex
--   server -> client  tips {items = [{pos, iid, cid, tip} | {pos, iid, cid, gone = true}]}
-- pos is the client's position of the item: {0xFFFF, slot, 0} for the inventory, {0xFFFF, 0x40 + container id, slot}
-- for an open container (slot on the current page), a map position with the stack position `s` for the ground. iid
-- is the item's per-item id from its client attributes as a decimal string (0 when it has none; a JSON number would lose
-- digits: ids reach 2^51): when it is set and the item found at pos
-- has another one, the answer is `gone` (the item moved). Nothing outside the player's own inventory, the containers
-- the engine has open for this player and visible map tiles next to the player is ever read.
-- Every request spends one token per item from a budget of ChaosItemTooltip.config.bucketSize, refilled at
-- bucketPerSecond; a request over the budget is dropped (the client asks again on the next hover).
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosCrafting then
	dofile("data/lib/chaos_crafting.lua")
end
if not ChaosItemTooltip then
	dofile("data/scripts/chaos/item_tooltip_core.lua")
end
if not ChaosWeaponBalance then
	dofile("data/scripts/chaos/weapon_balance_core.lua")
end
if not ChaosWeaponPower then
	dofile("data/scripts/chaos/weapon_power_core.lua")
end
if not ChaosWeaponDps then
	dofile("data/scripts/chaos/weapon_dps_core.lua")
end
if not ChaosArchery then
	dofile("data/lib/chaos_archery_core.lua")
end

local T = ChaosItemTooltip
local OPCODE = ChaosOpcodes.itemTooltip or 242
local budget = {} -- player id -> {tokens, at}

local function nowMs()
	return os.mtime and os.mtime() or os.time() * 1000
end

-- client id and count of an item (T.matchIndex)
local function infoOf(item)
	if not item then
		return nil
	end
	local it = ItemType(item:getId())
	return it and it:getClientId() or 0, item:getCount()
end

-- the item at pos that is what the client hovers: cid / n = its client id and (stackables) count, nil from an older
-- client (no check). A container whose items shifted since the client looked: the nearest matching slot.
local function itemAt(player, pos, cid, n)
	local p = T.decodePos(pos)
	if not p then
		return nil
	end
	local item
	if p.kind == "slot" then
		item = player:getSlotItem(p.slot)
	elseif p.kind == "container" then
		local container = player:getContainerById(p.cid) -- only containers the engine has open for this player
		if not container then
			return nil
		end
		local first = tonumber(player:getContainerIndex(p.cid)) or 0
		local size = container:getSize()
		local index = T.matchIndex(first + p.index, size, function(i) return infoOf(container:getItem(i)) end, cid, n)
		return index and container:getItem(index) or nil
	else
		local target = Position(p.x, p.y, p.z)
		if not T.mapAllowed(player:getPosition(), target, player:canSee(target)) then
			return nil
		end
		local tile = Tile(target)
		local thing = tile and tile:getThing(p.stackpos)
		item = thing and thing.isItem and thing:isItem() and thing or nil
	end
	if item and T.matchIndex(0, 1, function() return infoOf(item) end, cid, n) == nil then
		return nil -- another item than the one hovered: the client asks again after its next update
	end
	return item
end

local function equippedIds(player)
	local ids = {}
	for _, slot in ipairs(T.SLOTS) do
		local item = player:getSlotItem(slot)
		if item then
			ids[item:getId()] = true
		end
	end
	return ids
end

local function answer(player, data)
	local list = type(data.items) == "table" and data.items or {}
	local n = math.min(#list, T.config.maxItems)
	if n == 0 then
		return
	end
	local pid = player:getId()
	budget[pid] = budget[pid] or {}
	if not T.allow(budget[pid], nowMs(), n) then
		return
	end
	local equipped = equippedIds(player)
	-- the viewer's worn set pieces (itemsets.lua): the set block of a piece's tooltip
	local setState = ChaosItemSets and ChaosItemSets.stateOf and ChaosItemSets.stateOf(player) or nil
	-- the viewer's attack speed inputs for "Your Attack Interval" on weapons (attack speed cap, engine patch 0011)
	local voc = player:getVocation()
	local wielder = {voc = voc and voc:getAttackSpeed() or 2000,
		dex = CHARSTAT_DEXTERITY and player.getCharacterStat and player:getCharacterStat(CHARSTAT_DEXTERITY) or 0}
	-- and the inputs of the "Estimated DPS" line (weapon_dps_core.lua): level, best melee skill (one melee skill), distance skill
	local okSkill = pcall(function()
		local best = 0
		for _, sk in ipairs({SKILL_SWORD, SKILL_CLUB, SKILL_AXE}) do
			best = math.max(best, player:getEffectiveSkillLevel(sk))
		end
		wielder.melee, wielder.distance = best, player:getEffectiveSkillLevel(SKILL_DISTANCE)
		wielder.level = player:getLevel()
	end)
	if not okSkill then
		wielder.level = nil
	end
	local out = {}
	for i = 1, n do
		local req = type(list[i]) == "table" and list[i] or {}
		local iid = tonumber(req.iid) or 0
		local row = {pos = req.pos, iid = type(req.iid) == "string" and req.iid:sub(1, 20) or iid} -- echoed as sent
		row.cid = tonumber(req.cid) -- echoed: the client checks the answer against what it asked for
		local item = itemAt(player, req.pos, req.cid, req.n)
		if item and iid > 0 then
			local own = tonumber(ChaosCrafting.customNumber(item, "chaos_iid")) or 0
			if own ~= iid then
				item = nil
			end
		end
		if item then
			local attrs
			if item.getClientAttributes then
				local ok, a = pcall(item.getClientAttributes, item)
				attrs = ok and a or nil
			end
			local ok, tip = pcall(T.build, item, {equippedIds = equipped, attrs = attrs, wielder = wielder, setState = setState})
			if ok then
				-- a card: what it gives and how to use it, in the player's language (cards_core.lua K.description; the item
				-- type's own text is the English one tools/patch_badges.py installs)
				if ChaosCardsCore and type(tip) == "table" and ChaosCardsCore.isCard(item:getId()) then
					tip.desc = ChaosCardsCore.description(Chaos.lang and Chaos.lang(player) or nil, item:getId())
				end
				-- a unique's passive line in the player's language (unique_passives_text.lua; the description holds the English one)
				if type(tip) == "table" and type(tip.desc) == "string" and ChaosUniquePassivesCore and ChaosUniquePassivesConfig
						and Chaos.lang and Chaos.lang(player) == "pt-BR" then
					local e = ChaosUniquePassivesCore.entry(ChaosUniquePassivesConfig, item:getId())
					if e then
						local en = ChaosUniquePassivesCore.text(ChaosUniquePassivesConfig, e, "en")
						local from, to = tip.desc:find(en, 1, true)
						if from then
							tip.desc = tip.desc:sub(1, from - 1) .. ChaosUniquePassivesCore.text(ChaosUniquePassivesConfig, e, "pt-BR")
								.. tip.desc:sub(to + 1)
						end
					end
				end
				-- the flavour text in the player's language: a unique's generated pt-BR text (ChaosUniqueDescPt, from
				-- unique_flavor_pt.tsv), else the sentences the pt-BR table knows (itemdesc_i18n_core.lua)
				if type(tip) == "table" and type(tip.desc) == "string" and Chaos.lang and Chaos.tx and Chaos.lang(player) ~= "en" then
					if not ChaosItemDescI18n then
						dofile("data/scripts/chaos/itemdesc_i18n_core.lua")
					end
					local spec = ChaosUniqueSpecs and ChaosUniqueSpecs[item:getId()]
					local ptd = spec and ChaosUniqueDescPt and ChaosUniqueDescPt[spec.description]
					local okD, text = pcall(function()
						return ptd or ChaosItemDescI18n.translate(tip.desc, function(t)
							return Chaos.tx(player, t)
						end, ChaosUniqueDescPt)
					end)
					if okD and type(text) == "string" then
						tip.desc = text
					end
				end
				-- the display scale of the item's level requirement (display_scale_core.lua DS.itemTip)
				row.tip = (ChaosDisplayScale and ChaosDisplayScale.itemTip and ChaosDisplayScale.itemTip(tip) or tip)
				-- where it comes from (itemfinder.lua F.brief): the first two sources, the expected effort, a token price
				if ChaosItemFinder and ChaosItemFinder.brief and type(row.tip) == "table" then
					local okb, b = pcall(ChaosItemFinder.brief, item:getId())
					if okb and b then
						row.tip.src = b
					end
				end
			else
				row.gone = true
				print("[item_tooltip] " .. tostring(tip))
			end
		else
			row.gone = true
		end
		out[#out + 1] = row
	end
	Chaos.send(player, OPCODE, "tips", {items = out})
end

local ext = CreatureEvent("ChaosItemTooltipExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg or msg.action ~= "get" or type(msg.data) ~= "table" then
		return
	end
	answer(player, msg.data)
end
ext:type("extendedopcode")
ext:register()

local login = CreatureEvent("ChaosItemTooltipLogin")
function login.onLogin(player)
	player:registerEvent("ChaosItemTooltipExtended")
	player:registerEvent("ChaosItemTooltipLogout")
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosItemTooltipLogout")
function logout.onLogout(player)
	budget[player:getId()] = nil
	return true
end
logout:type("logout")
logout:register()
