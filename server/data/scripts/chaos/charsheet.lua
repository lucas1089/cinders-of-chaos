-- The character sheet, the engine side (ChaosCharSheet.read / readOwn; rules and texts: charsheet_core.lua).
-- Reads the numbers off a character from the systems that own them, the same ones the player's own Stats show, once for
-- Inspect Player (inspect.lua) and Info & Services > Character Info (commands_ui.lua, command `sheet`). Each source is
-- wrapped, so a system that is not loaded leaves its numbers out.
--   weapon attack, average hit, defence, armour, damage reduction   ChaosCombatStats.compute (combat_stats.lua)
--   critical chance and damage, attack speed, damage bonus per type ChaosPassiveTotals.build (passivetree_totals.lua)
--   life and mana leech                                              the engine's special skills
--   resistances, armour, dodge, block, suppression                   ChaosPlayerDefence.sheet (player_defence.lua, O464)
--   highest hit                                                      storage Chaos.storage.maxHit, written by combatlog.lua
--                                                                    (the biggest single hit dealt, raised once per record)
--   maximum health and mana, movement speed                          the player
-- Lua 5.1 / LuaJIT and 5.3.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not (ChaosCharSheet and ChaosCharSheet.clean) then
	dofile("data/scripts/chaos/charsheet_core.lua")
end

local K = ChaosCharSheet

local function pcallv(fn, ...)
	local ok, v = pcall(fn, ...)
	if ok then
		return v
	end
	return nil
end

local RESIST = {"physical", "fire", "energy", "earth", "ice", "holy", "death"}

-- the raw numbers of the sheet (what K.clean takes) for a player
function K.read(player)
	local raw = {}
	local S = ChaosCombatStats
	if S and S.compute then
		local c = pcallv(S.compute, player)
		if type(c) == "table" then
			raw.attack, raw.hit, raw.defense, raw.armor, raw.mitigation = c.attack, c.damage, c.defense, c.armor, c.mitigation
		end
	end
	local TT = ChaosPassiveTotals
	if TT and TT.build then
		local t = pcallv(TT.build, player)
		if type(t) == "table" then
			if type(t.crit) == "table" then
				raw.critChance = t.crit.chance and t.crit.chance.total
				raw.critAmount = t.crit.amount and t.crit.amount.total
			end
			raw.attackSpeed = type(t.attackSpeed) == "table" and t.attackSpeed.total or nil
			raw.damage = {}
			for _, row in ipairs(type(t.damage) == "table" and t.damage or {}) do
				local key = tostring(row.k):gsub("^increment", "")
				raw.damage[#raw.damage + 1] = {k = key:lower(), pct = row.eff}
			end
		end
	end
	local function special(name)
		local id = rawget(_G, name)
		return id and pcallv(function() return player:getSpecialSkill(id) end) or nil
	end
	raw.lifeLeech = {chance = special("SPECIALSKILL_LIFELEECHCHANCE"), amount = special("SPECIALSKILL_LIFELEECHAMOUNT")}
	raw.manaLeech = {chance = special("SPECIALSKILL_MANALEECHCHANCE"), amount = special("SPECIALSKILL_MANALEECHAMOUNT")}
	local PD = rawget(_G, "ChaosPlayerDefence")
	local d = PD and PD.active and PD.active() and PD.sheet and pcallv(PD.sheet, player)
	if type(d) == "table" then
		-- O464: the four resistances (sum, penalty, result), the armour, dodge, block and spell suppression
		raw.resist = d.resist
		raw.armor = d.armor
		raw.mitigation = d.physical / 100
		raw.defence = {armourShare = d.armourShare, reduction = d.reduction, dodge = d.dodge, block = d.block, suppress = d.suppress,
			penalty = d.penalty, cap = d.cap}
	else
		local R = ChaosDeathRecap
		if R and R.resistOf then
			raw.resist = {}
			for _, el in ipairs(RESIST) do
				raw.resist[#raw.resist + 1] = {k = el, pct = pcallv(R.resistOf, player, el)}
			end
		end
	end
	local key = Chaos.storage.maxHit
	local hit = key and pcallv(function() return player:getStorageValue(key) end)
	local DS = ChaosDisplayScale
	local scale = DS and DS.factor and pcallv(DS.factor, player:getLevel()) or 1
	raw.maxHit = (tonumber(hit) or 0) * (tonumber(scale) or 1)
	raw.maxHealth = pcallv(function() return player:getMaxHealth() end)
	raw.maxMana = pcallv(function() return player:getMaxMana() end)
	raw.moveSpeed = pcallv(function() return player:getSpeed() end)
	return raw
end

-- the own character's extra rows for the [ Character ] section (K.text's `character`): only ever the viewer's own
local SKILLS = {{"SKILL_FIST", "Fist Fighting"}, {"SKILL_CLUB", "Club Fighting"}, {"SKILL_SWORD", "Sword Fighting"},
	{"SKILL_AXE", "Axe Fighting"}, {"SKILL_DISTANCE", "Distance Fighting"}, {"SKILL_SHIELD", "Shielding"}, {"SKILL_FISHING", "Fishing"}}

function K.readOwn(player)
	local c = {}
	c.level = pcallv(function() return player:getLevel() end)
	c.vocation = pcallv(function() return player:getVocation():getName() end)
	c.health = pcallv(function() return player:getHealth() end)
	c.maxHealth = pcallv(function() return player:getMaxHealth() end)
	c.mana = pcallv(function() return player:getMana() end)
	c.maxMana = pcallv(function() return player:getMaxMana() end)
	c.capacity = pcallv(function() return math.floor(player:getFreeCapacity() / 100) end)
	c.speed = pcallv(function() return player:getSpeed() end)
	pcall(function()
		local level, exp = player:getLevel(), player:getExperience()
		local nextExp = Game.getExperienceForLevel and Game.getExperienceForLevel(level + 1) or nil
		local curExp = Game.getExperienceForLevel and Game.getExperienceForLevel(level) or nil
		if nextExp and curExp and nextExp > curExp then
			c.expToNext = math.max(0, nextExp - exp)
			c.expPercent = math.max(0, math.min(100, (exp - curExp) * 100 / (nextExp - curExp)))
		end
	end)
	pcall(function()
		c.magic = {level = player:getMagicLevel(), percent = player.getMagicLevelPercent and player:getMagicLevelPercent() or 0}
	end)
	c.skills = {}
	for _, s in ipairs(SKILLS) do
		local id = rawget(_G, s[1])
		local level = id and pcallv(function() return player:getEffectiveSkillLevel(id) end)
		if level then
			c.skills[#c.skills + 1] = {name = s[2], level = level, percent = pcallv(function() return player:getSkillPercent(id) end) or 0}
		end
	end
	c.soul = pcallv(function() return player:getSoul() end)
	c.stamina = pcallv(function() return player:getStamina() end)
	return c
end

return K
