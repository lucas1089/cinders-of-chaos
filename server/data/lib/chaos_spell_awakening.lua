-- ChaosSpellAwakening: the read API of the spell awakening (O686 phase 7) for every Lua state (the revscripts, the probes). The table is
-- data/spells/awakened.csv (the awakened name and the signature of every spell with Forms); an awakened spell is bit 9 (512) of its packed
-- state (data/lib/chaos_spell_ranks.lua, docs/SPELL_UPGRADES.md 7.1); the Seals and the slots are the storage keys of
-- spell_ranks_config.lua `storage`. Everything answers "not awakened" while spell_ranks_config.lua `enabled` is false or
-- data/scripts/chaos/spell_awakening_config.lua `enabled` is false. The writer (Seals, awaken, the signature effects, the hit hook) is
-- data/scripts/chaos/spell_awakening.lua; the rules are spell_awakening_core.lua. Lua 5.1 / LuaJIT and Lua 5.3 compatible.

if not ChaosSpellAwakeningCore or not ChaosSpellAwakeningCore.plan then
	dofile("data/scripts/chaos/spell_awakening_core.lua")
end
if not ChaosSpellRanksCore or not ChaosSpellRanksCore.power then
	dofile("data/scripts/chaos/spell_ranks_core.lua")
end
if not ChaosSpellRanksConfig then
	ChaosSpellRanksConfig = dofile("data/scripts/chaos/spell_ranks_config.lua")
end
if not ChaosSpellAwakeningConfig then
	ChaosSpellAwakeningConfig = dofile("data/scripts/chaos/spell_awakening_config.lua")
end

ChaosSpellAwakening = ChaosSpellAwakening or {}
local M = ChaosSpellAwakening
local A = ChaosSpellAwakeningCore
local P = ChaosSpellRanksCore

local function rcfg()
	return ChaosSpellRanksConfig
end

local function cfg()
	return ChaosSpellAwakeningConfig
end

function M.on()
	return rcfg().enabled == true and cfg().enabled == true
end

-- ---------------------------------------------------------------- the table (awakened.csv)
function M.table()
	if M.rows == nil then
		M.rows = false
		local f = io and io.open and io.open("data/spells/awakened.csv", "r")
		if f then
			local text = f:read("*a")
			f:close()
			local rows = A.parse(text)
			M.rows = rows or false
		end
	end
	return M.rows or {}
end

-- for tests: install a table
function M.setTable(rows)
	M.rows = rows or false
end

function M.entry(spellId)
	return M.table()[tonumber(spellId) or -1]
end

-- the awakened name of a spell, in English or (pt true) in pt-BR; nil when the spell has no row
function M.nameOf(spellId, pt)
	local e = M.entry(spellId)
	if not e then
		return nil
	end
	return pt and e.namePt or e.nameEn
end

-- ---------------------------------------------------------------- the state of a character
local function value(player, key)
	local v = tonumber(player:getStorageValue(key)) or 0
	return v > 0 and v or 0
end

-- is this spell awakened for the player (bit 9 of its packed state)
function M.isAwakened(player, spellId)
	if not M.on() or not player or not spellId then
		return false
	end
	spellId = tonumber(spellId)
	local st = rcfg().storage
	if not spellId or spellId < 0 or spellId > st.maxSpellId then
		return false
	end
	local _, _, _, awakened = P.unpack(player:getStorageValue(st.rankBase + spellId))
	return awakened == true
end

-- the Seals held: {waystone, rift, pinnacle}
function M.seals(player)
	local st = rcfg().storage
	return {waystone = value(player, st.sealWaystone), rift = value(player, st.sealRift), pinnacle = value(player, st.sealPinnacle)}
end

-- the spell ids in the slots: {id or 0, ...} for slots 1..maxSlots
function M.slots(player)
	local st = rcfg().storage
	local out = {}
	for i = 1, cfg().maxSlots do
		out[i] = value(player, st.awakenedSlots + i - 1)
	end
	return out
end

-- ---------------------------------------------------------------- what the probe runs after the cast (tools/ci/spell_fx_probe.lua)
-- the effects the signature of the spell sends itself, in the spell's own element, by role (the same names the Forms use)
function M.fxProbe(player, spellId, pos)
	local e = M.entry(spellId)
	local F = rawget(_G, "ChaosSpellForms")
	if not e or not F or not F.sendFx then
		return
	end
	local el = e.element or "physical"
	local roles = {}
	for _, p in ipairs(e.parts) do
		if p.kind == "PULSE" then
			roles.ground, roles.hit = true, true
		elseif p.kind == "RINGS" or p.kind == "ECHO" then
			roles.burst = true
		elseif p.kind == "MARK" or p.kind == "SHIELD" then
			roles.status = true
		else
			roles.hit = true
		end
	end
	for role in pairs(roles) do
		F.sendFx(pos, el, role)
	end
end

return M
