-- Spell combos, the engine side (O686 phase 6; docs/SPELL_UPGRADES.md section 4; server/README.md "Spell combos (O686 phase 6)").
-- Rules: spell_combos_core.lua, numbers: spell_combos_config.lua, tests: server/tests/spell_combos_test.lua (core, and this file with the
-- real ChaosPassiveDealt of passivetree_effects.lua on a mocked engine).
--
-- * Nothing here acts while spell_ranks_config.lua `enabled` is false or spell_combos_config.lua `enabled` is false: the cast handler
--   keeps no ring and ChaosSpellCombos.hitFactor answers 1.
-- * The cast. ChaosSpellEvents "cast" (handler key `spellcombos`, before the hit) puts the cast into the ring of the player (the last
--   four casts: spell id, time in ms, the player's target and its tile, else the player's own tile).
-- * The hit. ChaosSpellCombos.hitFactor is asked by ChaosPassiveDealt (passivetree_effects.lua) for every hit of a player, right after the
--   rank factor: the hit is the first hit of a cast (the cast's ring entry has no hit yet, younger than ring.expireMs), the target is a
--   monster (or, for a heal combo, an ally), never a player in PvP (spell_ranks_config.lua pvp.combos is false). The factor is 1 + the
--   bonus of the best row that matches (10% to 20% of the ranked hit, so it grows with the rank). A hit that keystones.depth marks as a
--   proc, and every extra hit of a Form (they run inside the proc guard) never reaches here: no combo on a Form's own hits.
--   The element of the hit is the one after a Form conversion (ChaosSpellForms.conversion), else the combat type of the biggest part.
-- * The credit. The bonus is part of the hit of the SECOND spell, inside its cast context: the combat log (combatlog.lua spellHook ->
--   spell_ranks.lua onDamage) credits that spell for the damage it dealt, bonus included. No extra hit exists, so nothing else can credit.
-- * The client. A `combo` message on opcode 168: {id, n = English name, x, y, z of the target} (the client draws a label and plays a chime).
-- Assumed engine API (TFS 1.4.2): ChaosSpellEvents cast handler, Player:getTarget/getPosition/getId, Creature:getPosition/isMonster/isPlayer/
-- getMaster, EventCallback via passivetree_effects.lua. Lua 5.1 / LuaJIT and Lua 5.3 compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosSpellCombosCore or not ChaosSpellCombosCore.onHit then
	dofile("data/scripts/chaos/spell_combos_core.lua")
end
if not ChaosSpellRanksCore or not ChaosSpellRanksCore.power then
	dofile("data/scripts/chaos/spell_ranks_core.lua")
end
ChaosSpellRanksConfig = ChaosSpellRanksConfig or dofile("data/scripts/chaos/spell_ranks_config.lua")
ChaosSpellCombosConfig = dofile("data/scripts/chaos/spell_combos_config.lua")
dofile("data/lib/chaos_spell_ranks.lua")
pcall(dofile, "data/lib/chaos_spell_forms.lua")
if not ChaosSpellEvents or not ChaosSpellEvents.set then
	pcall(dofile, "data/lib/chaos_spell_events.lua")
end

ChaosSpellCombos = ChaosSpellCombos or {}
local M = ChaosSpellCombos
local C = ChaosSpellCombosCore
local R = ChaosSpellRanks
local cfg = ChaosSpellCombosConfig
local rcfg = ChaosSpellRanksConfig
local OPCODE = (ChaosOpcodes and ChaosOpcodes.spellRanks) or rcfg.opcode

M.states = M.states or {} -- player id -> core state (the ring and the limits)

local function nowMs()
	return os.mtime and os.mtime() or os.time() * 1000
end

local function log(text)
	print("[Chaos spell combos] " .. text)
end

function M.on()
	return rcfg.enabled == true and cfg.enabled == true
end

local function stateOf(player)
	local id = player:getId()
	local st = M.states[id]
	if not st then
		st = C.newState()
		M.states[id] = st
	end
	return st
end

-- every spell id a row names (a cast of one is always kept in the ring)
local rowIds
local function isRowSpell(id)
	if not rowIds then
		rowIds = {}
		for _, row in ipairs(cfg.rows) do
			for _, side in ipairs({row.first, row.second}) do
				for _, sid in ipairs(side.spells or {}) do
					rowIds[sid] = true
				end
			end
		end
	end
	return rowIds[id] == true
end

local function copyPos(p)
	return p and {x = p.x, y = p.y, z = p.z} or nil
end

-- ---------------------------------------------------------------- the cast
function M.onCast(player, name, id, group, aggressive)
	if not M.on() or not player or not id then
		return
	end
	if not (R.catalog and R.catalog[id]) and not isRowSpell(id) and aggressive ~= true then
		return
	end
	local target = player.getTarget and player:getTarget() or nil
	local tid, pos
	if target and target.getPosition then
		tid, pos = target:getId(), copyPos(target:getPosition())
	else
		pos = copyPos(player:getPosition())
	end
	C.cast(stateOf(player), cfg, id, nowMs(), tid, pos)
end

if ChaosSpellEvents and ChaosSpellEvents.set then
	ChaosSpellEvents.set("cast", "spellcombos", M.onCast)
end

-- ---------------------------------------------------------------- the element of a hit
local combatNames = {
	physical = "COMBAT_PHYSICALDAMAGE", fire = "COMBAT_FIREDAMAGE", ice = "COMBAT_ICEDAMAGE", energy = "COMBAT_ENERGYDAMAGE",
	earth = "COMBAT_EARTHDAMAGE", holy = "COMBAT_HOLYDAMAGE", death = "COMBAT_DEATHDAMAGE",
}

local function elementOfType(ctype)
	if not ctype then
		return nil
	end
	for element, name in pairs(combatNames) do
		if rawget(_G, name) == ctype then
			return element
		end
	end
	return nil
end
M.elementOfType = elementOfType

-- the element of a hit with its Form conversion (the conversion wins, design 4.3), else of the damage parts
function M.elementOfHit(player, spellId, creature, primaryType, primaryDamage, secondaryType, secondaryDamage)
	local FE = rawget(_G, "ChaosSpellForms")
	if FE and FE.active and FE.conversion then
		local ok, specs = pcall(FE.active, player, spellId)
		if ok and specs and #specs > 0 then
			local ok2, el = pcall(FE.conversion, specs, FE.resistFn and FE.resistFn(creature) or function() return 0 end)
			if ok2 and el then
				return el
			end
		end
	end
	return C.elementOf(elementOfType(primaryType), primaryDamage, elementOfType(secondaryType), secondaryDamage, cfg)
end

-- ---------------------------------------------------------------- the hit
local function validTarget(attacker, creature, heal)
	if not creature or creature == attacker then
		return heal and creature ~= nil
	end
	if heal then
		return creature.isPlayer and creature:isPlayer() == true
	end
	if creature.isMonster and creature:isMonster() then
		local master = creature.getMaster and creature:getMaster()
		return not (master and master.isPlayer and master:isPlayer())
	end
	return false
end

-- the factor of one hit of a player (1 when no combo fires). Asked by ChaosPassiveDealt for every hit, so every guard is first and cheap.
function M.hitFactor(attacker, creature, origin, primaryType, secondaryType, primaryDamage, secondaryDamage)
	if origin ~= ORIGIN_SPELL or not M.on() or not attacker or not attacker.isPlayer or not attacker:isPlayer() then
		return 1
	end
	local st = M.states[attacker:getId()]
	if not st or #st.ring == 0 then
		return 1
	end
	local spellId = R.castSpell(attacker)
	if not spellId then
		return 1
	end
	local heal = primaryType == COMBAT_HEALING or secondaryType == COMBAT_HEALING
	local pvp = (not heal) and creature and creature ~= attacker and creature.isPlayer and creature:isPlayer() == true
	if pvp and rcfg.pvp.combos ~= true then
		-- PvP: the entry of the cast is closed, no combo (design 5.2)
		C.onHit(st, cfg, {spell = spellId, now = nowMs(), pvp = true, target = creature:getId(), pos = copyPos(creature:getPosition())})
		return 1
	end
	if not validTarget(attacker, creature, heal) then
		return 1
	end
	local pos = copyPos(creature:getPosition())
	local h = {
		spell = spellId, now = nowMs(), heal = heal, target = creature:getId(), pos = pos,
		element = (not heal) and M.elementOfHit(attacker, spellId, creature, primaryType, primaryDamage, secondaryType, secondaryDamage) or nil,
		rankOf = function(id) return R.rankOf(attacker, id) end,
	}
	local row, factor = C.onHit(st, cfg, h)
	if row then
		M.announce(attacker, row, pos)
	end
	return factor
end

-- the label and the chime on the client
function M.announce(player, row, pos)
	if Chaos.send then
		Chaos.send(player, OPCODE, "combo", {id = row.id, n = row.name, x = pos.x, y = pos.y, z = pos.z})
	end
end

-- ---------------------------------------------------------------- logout
local logout = CreatureEvent("ChaosSpellCombosLogout")
function logout.onLogout(player)
	M.states[player:getId()] = nil
	return true
end
logout:type("logout")
logout:register()

local login = CreatureEvent("ChaosSpellCombosLogin")
function login.onLogin(player)
	player:registerEvent("ChaosSpellCombosLogout")
	return true
end
login:type("login")
login:register()

return M
