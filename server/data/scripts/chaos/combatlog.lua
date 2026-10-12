-- DPS meter and combat log (client game_dpsmeter, extended opcode ChaosOpcodes.combatLog = 204). Part of the Hunt
-- Tracker family: its session follows the hunt session (hunt.lua), the Hunt Tracker window opens the meter.
--
-- Every damage and heal a character deals is attributed to its source; damage taken by attacker and element, and
-- healing received by healer, are counted too. Fights are cut out of that (a fight starts with the first damage dealt or
-- taken and ends cfg.idleMs after the last); the last cfg.keepFights fights and the session are kept per character.
-- The pure logic (sources, buffer, fights, views) is combatlog_core.lua (tests: server/tests/combatlog_test.lua, with
-- a benchmark); settings combatlog_config.lua; overview server/README.md "DPS meter and combat log".
--
-- Where a hit comes from (first match wins; combatlog_core.lua CL.classify):
--   proc    the hit happened inside a doTargetCombat / doAreaCombat call made by a script listed in
--           cfg.procLabels (supports, keystones, thorns, item powers, item elements, ...): both functions are wrapped
--           once and the calling file names the label. A file marked helper (the necromancer library) only counts
--           outside a cast; an unlisted file is "Other" (also only outside a cast). Calls made by data/spells/** are
--           not labelled: the cast names them.
--   summon  the attacker is a summon of the character: the summon's name
--   cast    the spell running now: the spell supports' cast context (data/spells/chaos/_supports.lua, ChaosSupportsSpell
--           .cast(): every wrapped spell, also in the addEvent callbacks it starts), else the spell / rune between
--           the engine's Player:onSpellPreCast and onSpellCast (engine patch 0008; every instant spell and rune);
--           a spell's own delayed hits named with CL.asSpell (the snares' scheduler) come first
--   origin  ORIGIN_CONDITION: damage over time by element (Bleeding, Burning, Poison, ...: the condition owner is the
--           attacker); ORIGIN_MELEE: the weapon in hand (sword, axe, club, fist); ORIGIN_RANGED: distance;
--           ORIGIN_WAND (5): wand; anything else: "Other"
-- Hits dealt with ORIGIN_NONE run no health events in the engine; the doTargetCombat wrapper measures the target's
-- health before and after such a call instead (rarity elements, pets, companion hits).
-- Damage is counted up to the target's health (no overkill), healing up to the missing health (the rest is overhealing).
--
-- Protocol (JSON {action, data}; server -> client through Chaos.sendChunked):
--   client -> server  open {seg, party, share} | close | seg {id} | party {on} | share {on} | reset
--   server -> client  state {sel, segs, v, live, share, party?} (combatlog_core.lua CL.state; party = [member]:
--                     {n = name, self = 1|nil, fd, fh, ft, fdur, live, sd, sh, st, sdur}) while the meter is open, at
--                     most every cfg.pushMs and only when something changed.
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
dofile("data/scripts/chaos/combatlog_core.lua")

Chaos.combatLogConfig = dofile("data/scripts/chaos/combatlog_config.lua")
local cfg = Chaos.combatLogConfig
local CL = ChaosCombatLog
CL.configure(cfg)
local OPCODE = ChaosOpcodes.combatLog or 204
local DMG, HEAL, TAKEN, RECV = CL.DMG, CL.HEAL, CL.TAKEN, CL.RECV
local abs, min, max = math.abs, math.min, math.max

CL.actors = CL.actors or {} -- guid -> actor (kept over /reload)
CL.watch = CL.watch or {} -- player id -> {seg, party, sig}

local O = CL.ORIGIN
O.NONE = ORIGIN_NONE or O.NONE
O.CONDITION = ORIGIN_CONDITION or O.CONDITION
O.SPELL = ORIGIN_SPELL or O.SPELL
O.MELEE = ORIGIN_MELEE or O.MELEE
O.RANGED = ORIGIN_RANGED or O.RANGED
O.WAND = ORIGIN_WAND or O.WAND

local function nowMs()
	return os.mtime and os.mtime() or os.time() * 1000
end

-- element names (the client colours and names them)
local EL = {}
for name, key in pairs({physical = "COMBAT_PHYSICALDAMAGE", energy = "COMBAT_ENERGYDAMAGE", earth = "COMBAT_EARTHDAMAGE",
	fire = "COMBAT_FIREDAMAGE", lifedrain = "COMBAT_LIFEDRAIN", manadrain = "COMBAT_MANADRAIN", drown = "COMBAT_DROWNDAMAGE",
	ice = "COMBAT_ICEDAMAGE", holy = "COMBAT_HOLYDAMAGE", death = "COMBAT_DEATHDAMAGE"}) do
	if _G[key] then
		EL[_G[key]] = name
	end
end
local HEALING = COMBAT_HEALING

-- ---------------------------------------------------------------- actors
local function actorOf(player)
	local guid = player:getGuid()
	local a = CL.actors[guid]
	if not a then
		a = CL.newActor(nowMs())
		a.share = cfg.shareByDefault and true or false
		CL.actors[guid] = a
	end
	return a
end

-- the session counts while the hunt session runs (Hunt Tracker pause)
local function huntRunning(player)
	local H = ChaosHunt
	if not cfg.followHunt or not H or not H.sessions or not H.running then
		return true
	end
	local s = H.sessions[player:getGuid()]
	return not s or H.running(s)
end

-- ---------------------------------------------------------------- spells (names, words, runes)
local spells
local function spellIndex()
	if not spells then
		local f = io.open("data/spells/spells.xml", "r")
		local text = f and f:read("*a") or ""
		if f then
			f:close()
		end
		spells = CL.parseSpells(text)
	end
	return spells
end

local castByName, castById = {}, {}
-- a spells.xml text instead of the file (tests); the source caches start over
function CL.loadSpells(text)
	spells = CL.parseSpells(text)
	castByName, castById = {}, {}
	return spells
end

local function castSource(e)
	local cid
	if e.rune then
		local ok, v = pcall(function() return ItemType(e.rune):getClientId() end)
		cid = ok and v or 0
	end
	return CL.castSource(e, cid)
end

local function castSrcByName(name)
	if type(name) ~= "string" then
		return nil
	end
	local s = castByName[name]
	if s == nil then
		local e = spellIndex().byName[name:lower()]
		s = e and castSource(e) or CL.source("s", name, "")
		castByName[name] = s
	end
	return s
end

local function castSrcById(id)
	local s = castById[id]
	if s == nil then
		local e = spellIndex().byId[id]
		s = e and castSource(e) or false
		castById[id] = s
	end
	return s or nil
end

-- the spell running now between the engine's onSpellPreCast and onSpellCast (patch 0008)
local precast = {} -- player id -> source
local rawAddEvent = addEvent
local function clearPrecast(pid, s)
	if precast[pid] == s then
		precast[pid] = nil
	end
end

if not ChaosSpellEvents or not ChaosSpellEvents.set then
	pcall(dofile, "data/lib/chaos_spell_events.lua")
end
if ChaosSpellEvents and ChaosSpellEvents.set then
	ChaosSpellEvents.set("precast", "combatlog", function(player, name)
		local s = castSrcByName(name)
		local pid = player:getId()
		precast[pid] = s
		-- a cast that fails (or a later precast handler that cancels) never reaches onSpellCast
		rawAddEvent(clearPrecast, 0, pid, s)
	end)
	ChaosSpellEvents.set("cast", "combatlog", function(player)
		precast[player:getId()] = nil
	end)
end

-- a spell's own delayed hits outside every cast context (the snares' scheduler, data/spells/chaos/_snares.lua):
-- CL.asSpell(pid, spellId, fn, ...) runs fn(...) (no results) with the hits of character pid named by spellId
-- (spells.xml), the same source a cast of that spell gets. Nothing else changes: no supports, no cast. Nested runs
-- restore the outer one.
local named = {} -- player id -> spell id
function CL.asSpell(pid, spellId, fn, ...)
	local outer = named[pid]
	named[pid] = spellId
	local ok, err = pcall(fn, ...)
	named[pid] = outer
	if not ok then
		error(err, 0)
	end
end

local function castOf(pid)
	local id = named[pid]
	if id then
		local s = castSrcById(id)
		if s then
			return s
		end
	end
	local W = ChaosSupportsSpell
	if W and W.cast then
		local cpid, spellId = W.cast()
		if cpid == pid and spellId then
			local s = castSrcById(spellId)
			if s then
				return s
			end
		end
	end
	return precast[pid]
end

-- ---------------------------------------------------------------- owners, weapons, bosses
-- the character a hit counts for: the attacker itself, or the master of a summon (then also the summon)
local function ownerOf(attacker)
	if not attacker then
		return nil
	end
	if attacker:isPlayer() then
		return attacker, nil
	end
	local master = attacker:getMaster()
	if master and master:isPlayer() then
		return master, attacker
	end
	return nil
end

local WEAPON = {}
for name, key in pairs({sword = "WEAPON_SWORD", club = "WEAPON_CLUB", axe = "WEAPON_AXE", distance = "WEAPON_DISTANCE",
	wand = "WEAPON_WAND"}) do
	if _G[key] then
		WEAPON[_G[key]] = name
	end
end
local weaponCache = {} -- item id -> weapon name | false
local HANDS = {CONST_SLOT_LEFT, CONST_SLOT_RIGHT} -- the engine's order
local function weaponOf(player)
	for i = 1, 2 do
		local item = player:getSlotItem(HANDS[i])
		if item then
			local id = item:getId()
			local w = weaponCache[id]
			if w == nil then
				local fist = ChaosFistWeapons and ChaosFistWeapons.items and ChaosFistWeapons.items[id]
				w = fist and "fist" or WEAPON[ItemType(id):getWeaponType()] or false
				weaponCache[id] = w
			end
			if w then
				return w
			end
		end
	end
	return "fist"
end

local extraBosses = {}
for _, n in ipairs(cfg.extraBosses or {}) do
	extraBosses[tostring(n):lower()] = true
end
local bossCache = {} -- monster name -> bool
local function bossName(monster)
	local name = monster:getName()
	local b = bossCache[name]
	if b == nil then
		local key = name:lower()
		b = extraBosses[key] or false
		local bp = ChaosBossPoints and ChaosBossPoints.index
		if not b and bp and bp.byName and bp.byName[key] then
			b = true
		end
		if not b then
			for _, wb in ipairs(Chaos.worldBoss and Chaos.worldBoss.bosses or {}) do
				if tostring(wb.name or ""):lower() == key then
					b = true
				end
			end
		end
		if not b and ChaosTierOf then
			local ok, tier = pcall(ChaosTierOf, monster)
			b = ok and tier == "boss"
		end
		if not b then
			local ok, res = pcall(function() return monster:getType():isBoss() end)
			b = ok and res == true
		end
		bossCache[name] = b and true or false
	end
	return b and name or nil
end

-- ---------------------------------------------------------------- proc labels (doTargetCombat / doAreaCombat)
local stack, stackPid, depth = {}, {}, 0
local labelCache = {} -- chunk source -> {src, helper} | false
local OTHER_PROC = CL.procSource({name = "Other", kind = "o", icon = "other", helper = true, other = true})

local function labelFor(source)
	if source:find("/spells/", 1, true) then
		return false -- a spell: the cast names it
	end
	local base = source:match("([^/\\]+)$") or source
	local def = cfg.procLabels and cfg.procLabels[base]
	if def then
		return CL.procSource(def)
	end
	return OTHER_PROC
end

-- the label of the script that called the wrapper (level 1 = this function, 2 = the wrapper)
local function callerLabel()
	for level = 3, 7 do
		local info = debug.getinfo(level, "S")
		if not info then
			return nil
		end
		local src = info.source or ""
		if src ~= "=[C]" and not src:find("global.lua", 1, true) then
			local l = labelCache[src]
			if l == nil then
				l = labelFor(src)
				labelCache[src] = l
			end
			return l or nil
		end
	end
	return nil
end

local function creatureArg(v)
	if type(v) == "userdata" or type(v) == "table" then
		return v
	elseif type(v) == "number" and v ~= 0 then
		return Creature(v)
	end
	return nil
end

-- the hit's source for a character (scratch table: no allocation per hit)
local h = {}
local function classifyFor(owner, summon, tab, origin, el)
	local pid = owner:getId()
	h.origin, h.el = origin, el
	h.summon = summon and summon:getName() or nil
	h.cast = castOf(pid)
	h.proc = nil
	if depth > 0 and stackPid[depth] == pid then
		h.proc = stack[depth]
	end
	h.weapon = nil
	if origin == O.MELEE and not h.summon then
		h.weapon = weaponOf(owner)
	end
	return CL.classify(tab, h)
end

-- ---------------------------------------------------------------- recording
local function takenSource(attacker)
	if not attacker then
		return CL.takenSource(nil)
	end
	return CL.takenSource(attacker:isPlayer() and "u" or "c", attacker:getName())
end

-- mana: true for the part a mana shield took (the death recap tells health and mana damage apart)
local function dealt(creature, attacker, amount, ptype, origin, critical, now, mana)
	local el = EL[ptype]
	local owner, summon = ownerOf(attacker)
	if owner and owner ~= creature then
		local a = actorOf(owner)
		a.sessionOn = huntRunning(owner)
		local src = classifyFor(owner, summon, DMG, origin, el)
		local isMonster = creature:isMonster()
		CL.add(a, now, DMG, src, amount, critical, 0, el, creature:getName(), isMonster and bossName(creature) or nil)
	end
	if creature:isPlayer() then
		local a = actorOf(creature)
		a.sessionOn = huntRunning(creature)
		local boss = attacker and attacker:isMonster() and bossName(attacker) or nil
		local src = takenSource(attacker)
		CL.add(a, now, TAKEN, src, amount, critical, 0, el, nil, boss)
		-- the death recap's rolling log (deathrecap.lua) takes the same hits with the same attribution
		local hook = CL.takenHook
		if hook then
			pcall(hook, creature, attacker, src, amount, el, critical, now, mana)
		end
	end
end

-- exact: raw is what the health went up by already (measured), not a heal still to be applied
local function healed(creature, attacker, raw, origin, critical, now, exact)
	local eff = exact and raw or min(raw, max(0, creature:getMaxHealth() - creature:getHealth()))
	local over = raw - eff
	local healer, summon = ownerOf(attacker)
	local src
	if healer then
		local a = actorOf(healer)
		a.sessionOn = huntRunning(healer)
		src = classifyFor(healer, summon, HEAL, origin, nil)
		CL.add(a, now, HEAL, src, eff, critical, over)
	end
	if creature:isPlayer() then
		local a = actorOf(creature)
		a.sessionOn = huntRunning(creature)
		local rsrc = src
		if healer ~= creature then
			if healer then
				rsrc = CL.source("u", healer:getName(), "player")
			elseif attacker then
				rsrc = CL.takenSource("c", attacker:getName())
			else
				rsrc = CL.otherSource(RECV)
			end
		end
		CL.add(a, now, RECV, rsrc, eff, critical, over)
	end
end

local function onHealth(creature, attacker, pd, pt, sd, st, origin, critical)
	if pt == HEALING then
		local raw = abs(pd or 0)
		if raw > 0 then
			healed(creature, attacker, raw, origin, critical, nowMs())
		end
		return
	end
	local total = abs(pd or 0) + abs(sd or 0)
	if total > 0 then
		dealt(creature, attacker, min(total, creature:getHealth()), pt, origin, critical, nowMs())
	end
end
CL.onHealth = onHealth

-- a doTargetCombat with ORIGIN_NONE runs no health events: the target's health before and after
local function measured(attacker, victim, ctype, before)
	local after = victim:getHealth() or 0
	local now = nowMs()
	if ctype == HEALING then
		if after > before then
			-- healing is counted as it happened: what the health went up by (the missing health was the cap)
			healed(victim, attacker, after - before, O.NONE, false, now, true)
		end
	elseif before > after then
		dealt(victim, attacker, before - after, ctype, O.NONE, false, now)
	end
end

-- the optional arguments (origin, blockArmor, ...) are passed on exactly as given: the engine reads an explicit nil
-- origin as 0 (ORIGIN_NONE, no health events: no tree bonus, class factor, keystones or healing rules) where a missing
-- one is ORIGIN_SPELL, so a wrapper that names the parameter must not pass it when the caller left it out
local function wrapTarget(raw)
	return function(cid, target, ctype, mn, mx, effect, ...)
		local origin = ...
		local label = callerLabel()
		local attacker = creatureArg(cid)
		local owner = attacker and ownerOf(attacker)
		local pushed = false
		if label and owner then
			depth = depth + 1
			stack[depth], stackPid[depth] = label, owner:getId()
			pushed = true
		end
		local victim, before
		if origin == O.NONE and cfg.enabled then
			victim = creatureArg(target)
			before = victim and victim:getHealth()
		end
		local ok, res = pcall(raw, cid, target, ctype, mn, mx, effect, ...)
		if ok and before then
			pcall(measured, attacker, victim, ctype, before)
		end
		if pushed then
			stack[depth], stackPid[depth] = nil, nil
			depth = depth - 1
		end
		if not ok then
			error(res, 0)
		end
		return res
	end
end

local function wrapArea(raw)
	return function(cid, ...)
		local label = callerLabel()
		local attacker = creatureArg(cid)
		local owner = attacker and ownerOf(attacker)
		local pushed = false
		if label and owner then
			depth = depth + 1
			stack[depth], stackPid[depth] = label, owner:getId()
			pushed = true
		end
		local ok, res = pcall(raw, cid, ...)
		if pushed then
			stack[depth], stackPid[depth] = nil, nil
			depth = depth - 1
		end
		if not ok then
			error(res, 0)
		end
		return res
	end
end

-- wrapped once; a /reload wraps the original again (never a wrapper of a wrapper)
if cfg.wrapCombat and doTargetCombat then
	CL.rawTargetCombat = CL.rawTargetCombat or doTargetCombat
	CL.wrappedTargetCombat = wrapTarget(CL.rawTargetCombat)
	doTargetCombat = CL.wrappedTargetCombat
end
if cfg.wrapCombat and doAreaCombat then
	CL.rawAreaCombat = CL.rawAreaCombat or doAreaCombat
	CL.wrappedAreaCombat = wrapArea(CL.rawAreaCombat)
	doAreaCombat = CL.wrappedAreaCombat
end

-- ---------------------------------------------------------------- engine events
local health = CreatureEvent("ChaosCombatLogHealth")
function health.onHealthChange(creature, attacker, pd, pt, sd, st, origin, critical)
	if cfg.enabled then
		onHealth(creature, attacker, pd, pt, sd, st, origin, critical)
	end
	return pd, pt, sd, st
end
health:register()

-- damage a mana shield takes (the engine runs the mana events for it before the health part)
local mana = CreatureEvent("ChaosCombatLogMana")
function mana.onManaChange(creature, attacker, pd, pt, sd, st, origin)
	if cfg.enabled and pt ~= HEALING and pt ~= COMBAT_MANADRAIN and creature:isPlayer()
		and creature:hasCondition(CONDITION_MANASHIELD) then
		local total = min(abs(pd or 0) + abs(sd or 0), creature:getMana())
		if total > 0 then
			dealt(creature, attacker, total, pt, origin, false, nowMs(), true)
		end
	elseif cfg.enabled and pt == COMBAT_MANADRAIN and CL.takenHook and creature:isPlayer() then
		-- mana drain is no damage taken for the meter, but the death recap lists it as mana damage
		local total = min(abs(pd or 0) + abs(sd or 0), creature:getMana())
		if total > 0 then
			pcall(CL.takenHook, creature, attacker, takenSource(attacker), total, "manadrain", false, nowMs(), true)
		end
	end
	return pd, pt, sd, st
end
mana:register()

local target = EventCallback
target.onTargetCombat = function(creature, victim)
	if cfg.enabled and creature and victim and victim:isMonster() and ownerOf(creature) then
		victim:registerEvent("ChaosCombatLogHealth")
	end
	return RETURNVALUE_NOERROR
end
target:register(cfg.targetIndex or 70)

-- ---------------------------------------------------------------- party, state
local function sameRealm(a, b)
	local S = ChaosSeason
	if not S or not S.current or not S.realmOf then
		return true
	end
	local okCur, cur = pcall(S.current)
	if not okCur or not cur then
		return true
	end
	local okA, ra = pcall(S.realmOf, a)
	local okB, rb = pcall(S.realmOf, b)
	return okA and okB and ra == rb
end

-- the party's totals: members in the same party and realm that share (the viewer always sees itself)
local function partyOf(player)
	local party = player:getParty()
	local out = {}
	if not party then
		local b = CL.brief(actorOf(player))
		b.n, b.self = player:getName(), 1
		out[1] = b
		return out
	end
	local members = party:getMembers() or {}
	table.insert(members, 1, party:getLeader())
	for _, m in ipairs(members) do
		if m then
			local isSelf = m:getId() == player:getId()
			local a = CL.actors[m:getGuid()]
			if isSelf or (a and a.share and sameRealm(player, m)) then
				local b = CL.brief(a or actorOf(m))
				b.n = m:getName()
				b.self = isSelf and 1 or nil
				out[#out + 1] = b
			end
		end
	end
	return out
end

local function signature(player, w, a)
	local sig = tostring(a.ver) .. ":" .. tostring(w.seg) .. ":" .. (a.share and 1 or 0)
	if w.party then
		local party = player:getParty()
		if party then
			local members = party:getMembers() or {}
			table.insert(members, 1, party:getLeader())
			for _, m in ipairs(members) do
				local ma = m and CL.actors[m:getGuid()]
				sig = sig .. "|" .. (m and m:getId() or 0) .. ":" .. (ma and ma.ver or 0) .. ":" .. (ma and ma.share and 1 or 0)
			end
		end
	end
	return sig
end

local function send(player, w)
	local a = actorOf(player)
	CL.flush(a)
	local st = CL.state(a, w.seg)
	if w.party then
		st.party = partyOf(player)
	end
	w.seg = st.sel
	w.sig = signature(player, w, a)
	Chaos.sendChunked(player, OPCODE, json.encode({action = "state", data = st}))
end
CL.send = send

-- the Hunt Tracker's reset starts the session over (hunt.lua act)
function CL.onHuntReset(player)
	local a = CL.actors[player:getGuid()]
	if a then
		CL.resetSession(a, nowMs())
	end
end

-- ---------------------------------------------------------------- tick, login, logout, opcode
local think = GlobalEvent("ChaosCombatLogThink")
function think.onThink(interval)
	local now = nowMs()
	for guid, a in pairs(CL.actors) do
		if not CL.idle(a) then
			CL.tick(a, now)
		end
	end
	for pid, w in pairs(CL.watch) do
		local player = Player(pid)
		if not player then
			CL.watch[pid] = nil
		elseif now - (w.at or 0) >= (cfg.pushMs or 1000) then
			local a = actorOf(player)
			if signature(player, w, a) ~= w.sig then
				w.at = now
				send(player, w)
			end
		end
	end
	CL.sweep(CL.actors, now, (cfg.keepOfflineMinutes or 30) * 60000)
	return true
end
think:interval(cfg.tickMs or 1000)
think:register()

local login = CreatureEvent("ChaosCombatLogLogin")
function login.onLogin(player)
	player:registerEvent("ChaosCombatLogHealth")
	player:registerEvent("ChaosCombatLogMana")
	player:registerEvent("ChaosCombatLogLogout")
	player:registerEvent("ChaosCombatLogExtended")
	local a = CL.actors[player:getGuid()]
	if a then
		a.offlineAt = nil
	end
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosCombatLogLogout")
function logout.onLogout(player)
	local a = CL.actors[player:getGuid()]
	if a then
		CL.endFight(a)
		CL.flush(a)
		a.offlineAt = nowMs()
	end
	CL.watch[player:getId()] = nil
	precast[player:getId()] = nil
	return true
end
logout:type("logout")
logout:register()

local function segArg(v)
	if v == "s" or v == "c" then
		return v
	end
	return Chaos.toInt(v, 1, 1000000000) or "c"
end

local ext = CreatureEvent("ChaosCombatLogExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg or type(msg.action) ~= "string" then
		return
	end
	if ChaosRateLimit and not ChaosRateLimit.allow(player, "combatlog", 150) then
		return
	end
	local d = type(msg.data) == "table" and msg.data or {}
	local pid = player:getId()
	local action = msg.action
	if action == "close" then
		CL.watch[pid] = nil
		return
	end
	local a = actorOf(player)
	local w = CL.watch[pid]
	if action == "open" then
		w = {seg = segArg(d.seg), party = d.party == true}
		CL.watch[pid] = w
		if d.share ~= nil then
			a.share = d.share == true
		end
	elseif not w then
		return
	elseif action == "seg" then
		w.seg = segArg(d.id)
	elseif action == "party" then
		w.party = d.on == true
	elseif action == "share" then
		a.share = d.on == true
	elseif action == "reset" then
		CL.reset(a, nowMs())
	else
		return
	end
	w.at = nowMs()
	send(player, w)
end
ext:type("extendedopcode")
ext:register()
