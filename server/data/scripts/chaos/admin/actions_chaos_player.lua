-- Chaos: Buffs & Gear. Ember Blessings (blessings.lua ChaosBlessings), the classic blessings and the Eternal Blessing
-- (gentledeath.lua ChaosGentleDeath), the Idle Hall (idlehall.lua ChaosIdleHall), the equipment sets of pair 28
-- (data/lib/chaos_gear_sets.lua ChaosGearSets, made with ChaosCrafting.createItem like every gear reward) with the set
-- bonus state (itemsets.lua ChaosItemSets) and charms (charms.lua, as /charm give). Items and paid things need group 5.
ChaosAdminPending = ChaosAdminPending or {}
local function reg(def) def.category = "chaos_player"; def.id = "chaos_player." .. def.id; ChaosAdminPending[def.id] = def end

local ONLINE = {name = "player", label = "Player (online)", type = "player"}

local function sys(name, fn) return ChaosAdmin.system(name, fn) end
local function nowMs() return os.mtime and os.mtime() or os.time() * 1000 end

local function target(actor, p)
	return ChaosAdmin.targetOnline(actor, p.player)
end

-- ------------------------------------------------------------------ Ember Blessings (server/README.md "Ember Blessings")
local okBl, blCfg = pcall(dofile, "data/scripts/chaos/blessings_config.lua")
local BLESSINGS = {}
for _, e in ipairs(okBl and type(blCfg) == "table" and blCfg.pool or {}) do
	BLESSINGS[#BLESSINGS + 1] = {value = e.key, label = e.name or e.key}
end
if #BLESSINGS == 0 then BLESSINGS[1] = {value = "xp", label = "xp"} end

local function emberLine(X, t)
	local K, c = ChaosBlessingsCore, ChaosBlessingsConfig
	local parts = {}
	for _, it in ipairs(K.list(c, X.state[t:getId()] or K.newState(), nowMs())) do
		parts[#parts + 1] = string.format("%s %ds", it.name, math.ceil(it.leftMs / 1000))
	end
	return t:getName() .. ": Ember Blessings " .. (#parts > 0 and table.concat(parts, ", ") or "none") .. "."
end

reg{id = "embers_blessing_view", name = "Ember Blessings: view", description = "The running Ember Blessings of a character and their time left.",
	params = {ONLINE},
	handler = function(actor, p)
		local X, why = sys("ChaosBlessings", "give")
		if not X or not ChaosBlessingsCore then return false, why or "blessings.lua is not loaded." end
		local t, err = target(actor, p)
		if not t then return false, err end
		return true, emberLine(X, t)
	end}

reg{id = "embers_blessing_give", name = "Ember Blessings: give", description = "Gives one Ember Blessing as a kill would (ChaosBlessings.give: a refresh, a new one or the weakest replaced).",
	minGroup = 5,
	params = {ONLINE, {name = "blessing", label = "Blessing", type = "select", default = BLESSINGS[1].value, options = BLESSINGS}},
	handler = function(actor, p)
		local X, why = sys("ChaosBlessings", "give")
		if not X then return false, why end
		local t, err = target(actor, p)
		if not t then return false, err end
		X.give(t, p.blessing)
		return true, emberLine(X, t)
	end}

reg{id = "embers_blessing_clear", name = "Ember Blessings: clear", description = "Takes every running Ember Blessing away (ChaosBlessings.clear).",
	params = {ONLINE},
	handler = function(actor, p)
		local X, why = sys("ChaosBlessings", "clear")
		if not X then return false, why end
		local t, err = target(actor, p)
		if not t then return false, err end
		X.clear(t)
		return true, emberLine(X, t)
	end}

-- ------------------------------------------------------------------ classic blessings and the Eternal Blessing
local function blessIds()
	return (Chaos.shopServices and Chaos.shopServices.blessings) or {1, 2, 3, 4, 5}
end

local function blessLine(t)
	local have = {}
	for _, id in ipairs(blessIds()) do
		if t:hasBlessing(id) then have[#have + 1] = tostring(id) end
	end
	local GD = rawget(_G, "ChaosGentleDeath")
	local eternal = GD and GD.hasEternal and GD.hasEternal(t)
	return string.format("%s: blessings %d / %d (%s), Eternal Blessing %s.", t:getName(), #have, #blessIds(),
		#have > 0 and table.concat(have, ", ") or "none", eternal and "yes" or "no")
end

reg{id = "blessings_view", name = "Blessings: view", description = "The classic blessings held and whether the character owns the Eternal Blessing.",
	params = {ONLINE},
	handler = function(actor, p)
		local t, err = target(actor, p)
		if not t then return false, err end
		return true, blessLine(t)
	end}

reg{id = "blessings_grant", name = "Blessings: grant all", description = "Adds every classic blessing the character is missing (free).",
	minGroup = 5, params = {ONLINE},
	handler = function(actor, p)
		local t, err = target(actor, p)
		if not t then return false, err end
		for _, id in ipairs(blessIds()) do
			if not t:hasBlessing(id) then t:addBlessing(id) end
		end
		return true, blessLine(t)
	end}

reg{id = "blessings_remove", name = "Blessings: remove all", description = "Removes every classic blessing (an Eternal Blessing owner gets them back at the next login).",
	confirm = true, params = {ONLINE},
	handler = function(actor, p)
		local t, err = target(actor, p)
		if not t then return false, err end
		if type(t.removeBlessing) ~= "function" then return false, "Player:removeBlessing is not available on this build." end
		for _, id in ipairs(blessIds()) do
			if t:hasBlessing(id) then t:removeBlessing(id) end
		end
		return true, blessLine(t)
	end}

reg{id = "eternal_grant", name = "Eternal Blessing: grant", description = "Gives the store's Eternal Blessing (ChaosGentleDeath.eternalService: kept for good, the missing blessings added).",
	minGroup = 5, params = {ONLINE},
	handler = function(actor, p)
		local GD, why = sys("ChaosGentleDeath", "hasEternal")
		if not GD or not GD.eternalService then return false, why or "gentledeath.lua is not loaded." end
		local t, err = target(actor, p)
		if not t then return false, err end
		local refusal = GD.eternalService.check(t)
		if refusal then return false, tostring(refusal) end
		GD.eternalService.apply(t)
		return true, blessLine(t)
	end}

reg{id = "eternal_remove", name = "Eternal Blessing: remove", description = "Takes the Eternal Blessing away (its storage of gentledeath_config.lua back to 0); the blessings held stay until the next death.",
	dangerous = true, params = {ONLINE},
	handler = function(actor, p)
		local GD, why = sys("ChaosGentleDeath", "hasEternal")
		local c = ChaosGentleDeathConfig
		if not GD or not c then return false, why or "gentledeath.lua is not loaded." end
		local t, err = target(actor, p)
		if not t then return false, err end
		t:setStorageValue(c.storage.base + c.storage.eternal, 0)
		return true, blessLine(t)
	end}

-- ------------------------------------------------------------------ Idle Hall (server/README.md "Idle Hall")
reg{id = "idlehall_send", name = "Idle Hall: send", description = "Moves a character into the Idle Hall now, as the idle rule does (ChaosIdleHall.moveToHall).",
	params = {ONLINE},
	handler = function(actor, p)
		local IH, why = sys("ChaosIdleHall", "moveToHall")
		if not IH then return false, why end
		local t, err = target(actor, p)
		if not t then return false, err end
		local now = nowMs()
		if not IH.moveToHall(t, IH.stateOf(t, now), now) then return false, "Not moved: the hall is not on the map (install step contentareas)." end
		return true, t:getName() .. " is in the Idle Hall."
	end}

reg{id = "idlehall_release", name = "Idle Hall: release", description = "Sends a character back to its temple and counts it as active again.",
	params = {ONLINE},
	handler = function(actor, p)
		local t, err = target(actor, p)
		if not t then return false, err end
		local town = t:getTown()
		local temple = town and town:getTemplePosition()
		if not temple then return false, "The character has no temple." end
		t:teleportTo(temple)
		temple:sendMagicEffect(CONST_ME_TELEPORT)
		local IH = rawget(_G, "ChaosIdleHall")
		if IH and IH.activity then pcall(IH.activity, t) end
		return true, t:getName() .. " is back at its temple."
	end}

-- ------------------------------------------------------------------ equipment sets (server/README.md "Equipment sets (pair 28)")
local okGS, gsLib = pcall(dofile, "data/lib/chaos_gear_sets.lua")
local GEAR_SETS = {}
for key in pairs(okGS and type(gsLib) == "table" and gsLib.sources or {}) do
	GEAR_SETS[#GEAR_SETS + 1] = {value = key, label = key}
end
table.sort(GEAR_SETS, function(a, b) return a.value < b.value end)
if #GEAR_SETS == 0 then GEAR_SETS[1] = {value = "blightfang", label = "blightfang"} end

local function gearSets()
	return rawget(_G, "ChaosGearSets") or (okGS and gsLib) or nil
end

reg{id = "gearset_list", name = "Gear sets: pieces", description = "The pieces of one set a level would drop (ids, names, levels) for Gear sets: give.",
	params = {{name = "set", label = "Set", type = "select", default = GEAR_SETS[1].value, options = GEAR_SETS},
		{name = "level", label = "Level", type = "int", min = 1, max = 2000, default = 100}},
	handler = function(actor, p)
		local G = gearSets()
		if not G or not G.eligible then return false, "data/lib/chaos_gear_sets.lua is not loaded." end
		local lines = {}
		for _, piece in ipairs(G.eligible(p.set, p.level)) do
			local it = ItemType(piece.id)
			lines[#lines + 1] = string.format("%d  %s  level %d", piece.id, it and it:getName() or "?", piece.level or 0)
		end
		return true, string.format("%d piece(s) of %s near level %d.", #lines, p.set, p.level), lines
	end}

reg{id = "gearset_give", name = "Gear sets: give piece", description = "Makes one set piece with a rarity and an item level (ChaosCrafting.createItem, the forge every gear reward uses) and gives it.",
	minGroup = 5,
	params = {ONLINE, {name = "piece", label = "Piece item id", type = "int", min = 1, max = 65535},
		{name = "rarity", label = "Rarity id (0 plain, 1 Common, 2 Uncommon, 3 Magic, 4 Rare, 5 Legendary, 10 Divine)", type = "int", min = 0, max = 10, default = 0},
		{name = "ilvl", label = "Item level", type = "int", min = 1, max = 2000, default = 100}},
	handler = function(actor, p)
		local G = gearSets()
		if not G or not G.piece then return false, "data/lib/chaos_gear_sets.lua is not loaded." end
		local C, why = sys("ChaosCrafting", "createItem")
		if not C then return false, why end
		local piece = G.piece(p.piece)
		if not piece then return false, "Item " .. p.piece .. " is no equipment set piece." end
		local t, err = target(actor, p)
		if not t then return false, err end
		local item = C.createItem(piece.id, p.rarity, p.ilvl)
		if not item then return false, "The item could not be made." end
		local ret = t:addItemEx(item, true)
		if ret ~= RETURNVALUE_NOERROR and ret ~= true then return false, "No room (capacity or backpack)." end
		return true, string.format("%s got %s (%s set, rarity %d, item level %d).", t:getName(), item:getName(), tostring(piece.set),
			p.rarity, p.ilvl)
	end}

reg{id = "itemsets_state", name = "Item sets: bonus state", description = "The item and equipment set pieces worn and which bonuses are active (ChaosItemSets, as the Item sets command).",
	params = {ONLINE},
	handler = function(actor, p)
		local S, why = sys("ChaosItemSets", "summaryLines")
		if not S then return false, why end
		local t, err = target(actor, p)
		if not t then return false, err end
		return true, t:getName() .. ": item sets", S.summaryLines(S.stateOf(t))
	end}

-- ------------------------------------------------------------------ charms (as /charm give)
reg{id = "charm_give", name = "Charms: give", description = "Makes a charm (a shape with a rarity, or a unique charm by key) and gives it (ChaosCharms.makeItem, as /charm give).",
	minGroup = 5,
	params = {ONLINE, {name = "charm", label = "Shape or unique key", type = "string", max = 32},
		{name = "rarity", label = "Rarity (shapes, 1-3)", type = "int", min = 1, max = 3, default = 3},
		{name = "ilvl", label = "Item level", type = "int", min = 1, max = 2000, default = 100}},
	handler = function(actor, p)
		local CH, why = sys("ChaosCharms", "makeItem")
		local Core, c = ChaosCharmsCore, ChaosCharmsConfig
		if not CH or not Core or not c then return false, why or "charms.lua is not loaded." end
		local opts = {ilvl = p.ilvl}
		if c.uniques[p.charm] then
			opts.unique = p.charm
		elseif c.shapes[p.charm] then
			opts.shape, opts.rarity = p.charm, p.rarity
		else
			return false, "Unknown charm " .. p.charm .. "."
		end
		local t, err = target(actor, p)
		if not t then return false, err end
		local item = CH.makeItem(Core.rollCharm(c, opts))
		if not item then return false, "The charm could not be made." end
		local ret = t:addItemEx(item, true)
		if ret ~= RETURNVALUE_NOERROR and ret ~= true then return false, "No room (capacity or backpack)." end
		return true, t:getName() .. " got a charm: " .. p.charm .. "."
	end}
