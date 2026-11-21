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
-- * The burst (O692). The row's `burst` (spell_combos_config.lua: ChaosVfx names of its element(s), raw) is sent on the target tile with the
--   message, only while the switch is on (announce is reached only by a fired row).
-- * The client. A `combo` message on opcode 168: {id, n = English name, x, y, z of the target} (the client draws a label and plays a chime).
-- * The riders (phase 6b, config `riders` and each row's `fx`). A fired row leaves its pending rider (M.pending); ChaosPassiveDealt calls
--   M.afterHit with the FINAL amounts of that hit, and the rider runs one tick later (addEvent 0, like the Forms' extra hits): extra hits
--   through doTargetCombat with ORIGIN_SPELL, inside the proc guard (ChaosKeystones.depth, ChaosSpellForms.depth, ChaosSupports.formDepth:
--   no passive tree bonus again, no Form, no support, no combo) and inside the cast context of the second spell, so the combat log credits
--   that spell. Monsters only. brittle / holy: M.marks, read by the ChaosSpellComboMarks event on the monster. A death burst rides on the
--   kills of the player's own hits (afterHit), a hooked bonus and a heal over time window ride on later hits of the second spell (hitFactor).
--   The two critical riders are text (engine patch needed, README).
-- * The masteries (phase 6b). The tree stat comboMod = id (config `masteries`) changes the window, the repeat pause or the pause between
--   combos of that player: M.cfgOf reads ChaosPassiveCache[pid].comboMod.
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

-- the config as this player has it (a combo mastery moves the window and the pauses), cached for each choice
local effCache = {}
function M.cfgOf(player)
	local cache = rawget(_G, "ChaosPassiveCache")
	local b = cache and cache[player:getId()]
	local id = b and tonumber(b.comboMod)
	if not id then
		return cfg
	end
	local e = effCache[id]
	if e == nil then
		local choice = C.masteryChoice(cfg, id)
		e = choice and C.effective(cfg, choice) or false
		effCache[id] = e
	end
	return e or cfg
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
	C.cast(stateOf(player), M.cfgOf(player), id, nowMs(), tid, pos)
end

if ChaosSpellEvents and ChaosSpellEvents.set then
	ChaosSpellEvents.set("precast", "spellcombos", M.onCast) -- O686 phase 8: the engine fires `cast` AFTER the spell ran (patch 0008), so a ring entry made there never met its own hit
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

-- the spells that open a `hooked` row: their hits are noted on the ring entry (the enemies the hook hit)
local hookFirst
local function isHookFirst(id)
	if not hookFirst then
		hookFirst = {}
		for _, row in ipairs(cfg.rows) do
			if row.fx and row.fx.kind == "hooked" then
				for _, sid in ipairs(row.first.spells or {}) do
					hookFirst[sid] = true
				end
			end
		end
	end
	return hookFirst[id] == true
end

M.pending = nil -- the rider of the row that fired in the hit now being dealt: {pid, tid, row, pos, spell, serial, now}

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
	local ecfg = M.cfgOf(attacker)
	local heal = primaryType == COMBAT_HEALING or secondaryType == COMBAT_HEALING
	local pvp = (not heal) and creature and creature ~= attacker and creature.isPlayer and creature:isPlayer() == true
	if pvp and rcfg.pvp.combos ~= true then
		-- PvP: the entry of the cast is closed, no combo (design 5.2)
		C.onHit(st, ecfg, {spell = spellId, now = nowMs(), pvp = true, target = creature:getId(), pos = copyPos(creature:getPosition())})
		return 1
	end
	if not validTarget(attacker, creature, heal) then
		return 1
	end
	local now = nowMs()
	local tid = creature:getId()
	-- phase 6b: the enemies the first spell of a hooked row hit
	if not heal and isHookFirst(spellId) then
		C.noteHit(st, spellId, now, tid, ecfg.window.windowMs)
	end
	local pos = copyPos(creature:getPosition())
	local h = {
		spell = spellId, now = now, heal = heal, target = tid, pos = pos,
		element = (not heal) and M.elementOfHit(attacker, spellId, creature, primaryType, primaryDamage, secondaryType, secondaryDamage) or nil,
		rankOf = function(id) return R.rankOf(attacker, id) end,
	}
	local row, factor, first = C.onHit(st, ecfg, h)
	if row then
		M.announce(attacker, row, pos)
		local fx = row.fx
		if fx and fx.kind == "hooked" and first then
			C.hook(st, row, first, spellId, now, ecfg.ring.expireMs)
		elseif fx and fx.kind == "hot" then
			C.hotStart(st, row, spellId, now)
		end
		if fx and fx.kind ~= "text" and fx.kind ~= "hooked" and fx.kind ~= "hot" then
			M.pending = {pid = attacker:getId(), tid = tid, row = row, pos = pos, spell = spellId, now = now}
		end
	else
		-- phase 6b: a later hit of the second spell on an enemy the hook hit, and a heal inside the heal over time window
		if not heal then
			factor = C.hookedFactor(st, spellId, tid, now)
		else
			factor = C.hotFactor(st, spellId, now)
		end
	end
	return factor
end

-- ---------------------------------------------------------------- riders (phase 6b)
-- the proc guard of an extra hit: no passive tree bonus twice, no Form, no support effect, so no combo either
local function guarded(fn, ...)
	local FE, S, K = rawget(_G, "ChaosSpellForms"), rawget(_G, "ChaosSupports"), rawget(_G, "ChaosKeystones")
	if FE then FE.depth = (FE.depth or 0) + 1 end
	if S then S.formDepth = (S.formDepth or 0) + 1 end
	if K then K.depth = (K.depth or 0) + 1 end
	local ok, err = pcall(fn, ...)
	if K then K.depth = K.depth - 1 end
	if S then S.formDepth = S.formDepth - 1 end
	if FE then FE.depth = FE.depth - 1 end
	if not ok then
		log(tostring(err))
	end
end
M.guarded = guarded

-- the cast context of the second spell, so the combat log credits it (the Forms' withContext)
local function withContext(player, serial, spellId, fn)
	local FE = rawget(_G, "ChaosSpellForms")
	if serial and FE and FE.ops and FE.ops.withContext then
		return FE.ops.withContext(player, serial, spellId, fn)
	end
	return fn()
end

-- the other enemies of a monster target around a tile: monsters, alive, not a player's summon, not in a protection zone
local function foesNear(player, pos, radius, excludeId)
	local list = {}
	if not (rawget(_G, "Game") and Game.getSpectators and rawget(_G, "Position")) then
		return list
	end
	for _, c in ipairs(Game.getSpectators(Position(pos.x, pos.y, pos.z), false, false, radius, radius, radius, radius) or {}) do
		if c:getId() ~= excludeId and c:getHealth() > 0 and validTarget(player, c, false) then
			local tile = c.getTile and c:getTile()
			if not (tile and tile.hasFlag and tile:hasFlag(TILESTATE_PROTECTIONZONE)) then
				list[#list + 1] = c
			end
		end
	end
	table.sort(list, function(a, b) return a:getId() < b:getId() end)
	return list
end
M.foesNear = foesNear

local elementTypes = {
	physical = "COMBAT_PHYSICALDAMAGE", fire = "COMBAT_FIREDAMAGE", ice = "COMBAT_ICEDAMAGE", energy = "COMBAT_ENERGYDAMAGE",
	earth = "COMBAT_EARTHDAMAGE", holy = "COMBAT_HOLYDAMAGE", death = "COMBAT_DEATHDAMAGE",
}

local function dealRider(player, target, ctype, amount)
	if amount <= 0 or not target or target:getHealth() <= 0 then
		return false
	end
	guarded(doTargetCombat, player, target, ctype, -amount, -amount, CONST_ME_NONE, ORIGIN_SPELL)
	return true
end

-- brittle and holy marks on monsters: monster id -> {brittle = {untilMs, pct}, holy = {untilMs, pct}}
M.marks = M.marks or {}
local markCount = 0
local function registerMarks(creature)
	local f = Chaos and Chaos.registerOnce
	if f then
		f(creature, "ChaosSpellComboMarks")
	elseif creature.registerEvent then
		creature:registerEvent("ChaosSpellComboMarks")
	end
end

function M.mark(creature, key, now, ms, pct)
	local id = creature:getId()
	local marks = M.marks[id]
	if not marks then
		marks = {}
		M.marks[id] = marks
	end
	C.setMark(marks, key, now, ms, pct)
	registerMarks(creature)
	markCount = markCount + 1
	if markCount > 300 then
		markCount = 0
		for mid, m in pairs(M.marks) do
			local live = false
			for _, x in pairs(m) do
				live = live or x.untilMs >= now
			end
			if not live then
				M.marks[mid] = nil
			end
		end
	end
end

local function isBoss(creature)
	local ok, boss = pcall(function() return creature:getType():isBoss() end)
	return (ok and boss == true) or creature:getMaxHealth() > cfg.riders.stun.bossHealth
end

local function hasTimer(creature, subId)
	return creature:getCondition(CONDITION_ATTRIBUTES, CONDITIONID_COMBAT, subId) ~= nil
end

local function slow(target, fx)
	if not (Condition and CONDITION_PARALYZE) then
		return false
	end
	local c = Condition(CONDITION_PARALYZE)
	c:setParameter(CONDITION_PARAM_TICKS, fx.ms)
	c:setFormula(-fx.pct / 100, 0, -fx.pct / 100, 0)
	target:addCondition(c)
	local V = rawget(_G, "ChaosPack29Vfx")
	if V and V.hold then
		pcall(V.hold, target, "slowed", fx.ms)
	end
	return true
end

-- the weapon families' stun (weapon_families.lua applyDaze): the same sub ids and immunity timer; a boss and a rested monster are skipped
local function stun(target, fx)
	local s = cfg.riders.stun
	if not (Condition and CONDITION_PARALYZE and CONDITION_ATTRIBUTES) or isBoss(target) or hasTimer(target, s.immuneSubId)
			or target:getCondition(CONDITION_PARALYZE, CONDITIONID_COMBAT, s.subId) ~= nil then
		return false
	end
	local c = Condition(CONDITION_PARALYZE)
	c:setParameter(CONDITION_PARAM_TICKS, fx.ms)
	c:setParameter(CONDITION_PARAM_SUBID, s.subId)
	c:setFormula(-1, 0, -1, 0)
	target:addCondition(c)
	local rest = Condition(CONDITION_ATTRIBUTES)
	rest:setParameter(CONDITION_PARAM_SUBID, s.immuneSubId)
	rest:setParameter(CONDITION_PARAM_TICKS, s.restMs)
	target:addCondition(rest)
	if target.getPosition and CONST_ME_STUN then
		pcall(function() target:getPosition():sendMagicEffect(CONST_ME_STUN) end)
	end
	local V = rawget(_G, "ChaosPack29Vfx")
	if V and V.hold then
		pcall(V.hold, target, "stunned", fx.ms)
	end
	return true
end

-- runs the rider of a fired row (a tick after the hit). ctx = {pid, tid, row, pos, spell, serial, amount, ctype, now}. Returns what it did
-- (a string for the tests and the log), nil when nothing.
function M.runRider(ctx)
	local player = Player(ctx.pid)
	local fx = ctx.row.fx
	if not player or not fx then
		return nil
	end
	local target = Creature(ctx.tid)
	local k = fx.kind
	local did
	withContext(player, ctx.serial, ctx.spell, function()
		if k == "burst" or k == "chain" then
			local ctype = rawget(_G, elementTypes[fx.element or ""] or "") or ctx.ctype
			local amount = C.riderAmount(fx.share, ctx.amount)
			local n, max = 0, k == "burst" and fx.cap or fx.targets
			for _, c in ipairs(foesNear(player, ctx.pos, fx.radius, ctx.tid)) do
				if n >= max then
					break
				end
				if dealRider(player, c, ctype, amount) then
					n = n + 1
				end
			end
			did = n
		elseif k == "deathburst" then
			local st = stateOf(player)
			C.deathMark(st, fx, ctx.now, ctx.amount, rawget(_G, elementTypes[fx.element or ""] or "") or ctx.ctype)
			did = true
		elseif k == "brittle" and target then
			M.mark(target, "brittle", ctx.now, fx.ms, fx.pct)
			did = true
		elseif k == "holyamp" and target then
			M.mark(target, "holy", ctx.now, fx.ms, fx.pct)
			did = true
		elseif k == "slow" and target then
			did = slow(target, fx)
		elseif k == "stun" and target then
			did = stun(target, fx)
		elseif k == "hexrenew" and target then
			local S = rawget(_G, "ChaosSupports")
			did = S and S.renewHex and S.renewHex(target) or false
		end
	end)
	return did
end

-- a death burst: a kill of the player's own hit inside the window of a Pyre of the Dead; the other enemies near the corpse take a share
function M.runDeathBurst(pid, tid, pos, mark, serial, spell)
	local player = Player(pid)
	if not player then
		return 0
	end
	local n = 0
	local amount = C.riderAmount(mark.share, mark.amount)
	withContext(player, serial, spell, function()
		local count = 0
		for _, c in ipairs(foesNear(player, pos, mark.radius, tid)) do
			if count >= mark.targets then
				break
			end
			if dealRider(player, c, mark.ctype, amount) then
				count = count + 1
			end
		end
		n = count
	end)
	return n
end

-- ChaosPassiveDealt calls this for every hit of a player with the FINAL amounts of the hit (after the pool): a fired row's rider runs one
-- tick later, a kill inside a death burst window bursts. Cheap when nothing is pending.
function M.afterHit(attacker, creature, origin, primaryDamage, primaryType, secondaryDamage, secondaryType)
	local aid = attacker and attacker.getId and attacker:getId()
	local p = M.pending
	local st = aid and M.states[aid]
	if not st or (not p and not st.death) then
		return
	end
	local amount = math.abs(primaryDamage or 0) + math.abs(secondaryDamage or 0)
	if p and p.pid == aid and creature and p.tid == creature:getId() then
		M.pending = nil
		local ctype = primaryType
		if (ctype == nil or ctype == COMBAT_NONE) and secondaryType then
			ctype = secondaryType
		end
		local ctx = {pid = aid, tid = p.tid, row = p.row, pos = p.pos, spell = p.spell, amount = amount, ctype = ctype, now = p.now,
			serial = M.serialOf(attacker)}
		addEvent(M.runRider, 0, ctx)
	elseif p and p.pid == aid then
		M.pending = nil
	end
	if st.death and creature and creature.isMonster and creature:isMonster() and creature:getHealth() <= amount then
		local now = nowMs()
		local mark = C.deathDue(st, now)
		if mark then
			addEvent(M.runDeathBurst, 0, aid, creature:getId(), copyPos(creature:getPosition()), mark, M.serialOf(attacker), R.castSpell(attacker))
		end
	end
end

-- the serial of the cast context the player is in (nil when none)
function M.serialOf(player)
	local S = rawget(_G, "ChaosSupports")
	if S and S.ctxDecode and S.config and player.getStorageValue then
		local serial = S.ctxDecode(player:getStorageValue(S.config.storageContext))
		return serial
	end
	return nil
end

-- the marks on a monster: +pct of everything it takes (brittle), +pct of the holy it takes (holy)
local markEvent = CreatureEvent("ChaosSpellComboMarks")
function markEvent.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType)
	local marks = creature and M.marks[creature:getId()]
	if not marks or primaryType == COMBAT_HEALING then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local now = nowMs()
	local f1 = C.markFactor(marks, now, primaryType == COMBAT_HOLYDAMAGE)
	local f2 = C.markFactor(marks, now, secondaryType == COMBAT_HOLYDAMAGE)
	if next(marks) == nil then
		M.marks[creature:getId()] = nil
	end
	if f1 ~= 1 then
		primaryDamage = C.apply(primaryDamage, f1)
	end
	if f2 ~= 1 then
		secondaryDamage = C.apply(secondaryDamage, f2)
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
markEvent:register()

-- O692: the burst on the target, from existing effects of the row's element(s) (config `burst`, ChaosVfx names, sent raw: a Form's swap
-- does not touch it). Nothing for a row without `burst` or a client without the Vfx helper (a mocked engine).
function M.burst(row, pos)
	local vfx = rawget(_G, "Vfx")
	if not vfx or not row.burst or not pos then
		return 0
	end
	local n = 0
	for _, name in ipairs(row.burst) do
		if vfx(pos, name, true) then
			n = n + 1
		end
	end
	return n
end

-- the label and the chime on the client
function M.announce(player, row, pos)
	M.burst(row, pos)
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
