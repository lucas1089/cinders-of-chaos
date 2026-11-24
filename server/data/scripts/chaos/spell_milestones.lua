-- Spell path milestones (O752), the engine side. Numbers: spell_milestones_config.lua; logic: spell_milestones_core.lua; tests:
-- tests/spell_milestones_test.lua (this file on a mocked engine); server/README.md "Spell path milestones (O752)".
-- * The gates themselves are read where they act: spell_forms.lua (FE.gateLevel, the first pick of a Form tier) and
--   spell_awakening.lua (the slot and the spell). This file only tells the player.
-- * ChaosSpellMilestones.wire(player): the `ms` field of the opcode 168 `state` (spell_ranks.lua R.state): the gate rules and the
--   next milestone of the character's class (game_spellranks shows "Next unlock: level N" and the level of a locked tier).
-- * A level-up that reaches a milestone of a kind in `toastKinds` sends one toast (ChaosNotify kind "milestone") and a status line.
-- The class's spells come from the Spellbook (ChaosSpellbook.get, spellbook.lua) and class_spells_core.lua lists; the Form and
-- awakening rows from the libs (chaos_spell_forms.lua, chaos_spell_awakening.lua); the sockets from chaos_supports_config.lua.
-- Assumed engine API (TFS 1.4.2): CreatureEvent login / advance, Player:getLevel / getVocation / sendTextMessage. Lua 5.1 / LuaJIT and
-- Lua 5.3 compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
if not ChaosSpellMilestonesCore or not ChaosSpellMilestonesCore.list then
	dofile("data/scripts/chaos/spell_milestones_core.lua")
end
ChaosSpellMilestonesConfig = ChaosSpellMilestonesConfig or dofile("data/scripts/chaos/spell_milestones_config.lua")
pcall(dofile, "data/lib/chaos_spell_forms.lua")
pcall(dofile, "data/lib/chaos_spell_awakening.lua")

ChaosSpellMilestones = ChaosSpellMilestones or {}
local SM = ChaosSpellMilestones
local K = ChaosSpellMilestonesCore
local cfg = ChaosSpellMilestonesConfig

local function log(text)
	print("[Chaos spell milestones] " .. text)
end

local function try(label, fn, ...)
	local ok, a, b = pcall(fn, ...)
	if not ok then
		log(label .. ": " .. tostring(a))
		return nil
	end
	return a, b
end

local supportsCfg
local function scfg()
	if supportsCfg == nil then
		local ok, t = pcall(dofile, "data/lib/chaos_supports_config.lua")
		supportsCfg = ok and type(t) == "table" and t or false
	end
	return supportsCfg or nil
end

local function classCore()
	local Core = rawget(_G, "ChaosClassSpellsCore")
	if not Core or not Core.lists then
		pcall(dofile, "data/scripts/chaos/class_spells_core.lua")
		Core = rawget(_G, "ChaosClassSpellsCore")
	end
	return Core
end

-- the milestone list of a vocation, cached against the Spellbook's list (a /spells reload makes a new one)
local cache, cacheBook = {}, nil
function SM.listFor(vocationId)
	local book = rawget(_G, "ChaosSpellbook")
	local spells = book and book.get and book.get()
	if type(spells) ~= "table" then
		return {}
	end
	if cacheBook ~= spells then
		cache, cacheBook = {}, spells
	end
	if cache[vocationId] then
		return cache[vocationId]
	end
	local Core = classCore()
	local s = scfg()
	local none = {}
	for _, id in ipairs(s and s.none or {}) do
		none[id] = true
	end
	local FE, AW = rawget(_G, "ChaosSpellForms"), rawget(_G, "ChaosSpellAwakening")
	local mine, seen = {}, {}
	for _, e in ipairs(spells) do
		if e.name and not seen[e.name] and not e.rune and e.type ~= "conjure" and Core and Core.lists(e, vocationId) then
			seen[e.name] = true
			local id = tonumber(e.id)
			mine[#mine + 1] = {id = id, name = e.name, level = tonumber(e.level) or 0,
				forms = id ~= nil and FE ~= nil and FE.entry ~= nil and FE.entry(id) ~= nil,
				awaken = id ~= nil and AW ~= nil and AW.entry ~= nil and AW.entry(id) ~= nil,
				sockets = id ~= nil and not none[id]}
		end
	end
	local list = K.list(cfg, mine, s)
	cache[vocationId] = list
	return list
end

local function vocationOf(player)
	local voc = player.getVocation and player:getVocation()
	return voc and voc.getId and voc:getId() or 0
end

function SM.listOf(player)
	return SM.listFor(vocationOf(player))
end

-- the `ms` field of the state message: the rules and the next milestone; nil while off
function SM.wire(player)
	if cfg.enabled ~= true then
		return nil
	end
	return K.wire(cfg, K.nextAfter(SM.listOf(player), player:getLevel()))
end

-- the toast text of what a level-up reached (nil when nothing toasts): header, text
function SM.toastText(player, reached, nxt)
	if #reached == 0 then
		return nil
	end
	local t = function(key, ...)
		return Chaos.t(player, key, ...)
	end
	local byKind, order = {}, {}
	for _, e in ipairs(reached) do
		if not byKind[e.kind] then
			byKind[e.kind] = {}
			order[#order + 1] = e.kind
		end
		local list = byKind[e.kind]
		list[#list + 1] = e
	end
	local function names(list)
		local out = {}
		for i, e in ipairs(list) do
			if i > (cfg.toastNames or 3) then
				break
			end
			out[#out + 1] = e.name or "?"
		end
		local text = table.concat(out, ", ")
		if #list > #out then
			text = text .. " " .. t("and %d more", #list - #out)
		end
		return text
	end
	local parts = {}
	table.sort(order, function(a, b)
		local ia, ib = 99, 99
		for i, k in ipairs(K.KINDS) do
			if k == a then ia = i end
			if k == b then ib = i end
		end
		return ia < ib
	end)
	for _, kind in ipairs(order) do
		local list = byKind[kind]
		if kind == "slot" then
			for _, e in ipairs(list) do
				parts[#parts + 1] = t("Awakening slot %d opens.", e.slot or 0)
			end
		elseif kind == "form1" then
			parts[#parts + 1] = t("Form I opens for %s.", names(list))
		elseif kind == "form2" then
			parts[#parts + 1] = t("Form II opens for %s.", names(list))
		elseif kind == "awaken" then
			parts[#parts + 1] = t("Awakening opens for %s.", names(list))
		end
	end
	if #parts == 0 then
		return nil
	end
	if nxt then
		parts[#parts + 1] = t("Next unlock: level %d.", nxt.level)
	end
	return t("New unlock"), table.concat(parts, " ")
end

function SM.onAdvance(player, oldLevel, newLevel)
	if cfg.enabled ~= true then
		return
	end
	local list = SM.listOf(player)
	local reached = K.reached(list, oldLevel, newLevel, cfg.toastKinds)
	local header, text = SM.toastText(player, reached, K.nextAfter(list, newLevel))
	if not header then
		return
	end
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE or MESSAGE_INFO_DESCR, header .. ": " .. text)
	if ChaosNotify and ChaosNotify.send then
		ChaosNotify.send(player, header, text, "milestone")
	end
end

local login = CreatureEvent("ChaosSpellMilestonesLogin")
function login.onLogin(player)
	player:registerEvent("ChaosSpellMilestonesAdvance")
	return true
end
login:type("login")
login:register()

local advance = CreatureEvent("ChaosSpellMilestonesAdvance")
function advance.onAdvance(player, skill, oldLevel, newLevel)
	if skill == SKILL_LEVEL and newLevel > oldLevel then
		try("advance", SM.onAdvance, player, oldLevel, newLevel)
	end
	return true
end
advance:type("advance")
advance:register()

return SM
