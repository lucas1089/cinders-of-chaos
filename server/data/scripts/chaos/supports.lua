-- Spell supports on the server (scripts state): the support window (client game_spellsupports, extended opcode
-- ChaosOpcodes.supports = 243, JSON), socketing / removing / combining runes, opening the third socket,
-- what the runes do to the hits of their spell, and the drop and reward helpers the loot layer and the rift call.
-- Rules and numbers: data/lib/chaos_supports.lua and chaos_supports_config.lua; the spell side (cast context, mana,
-- cooldown): data/spells/chaos/_supports.lua. Design and the full list: SUPPORTS.md next to this file.
--
-- Which spell a hit belongs to: the spell side writes serial * 1000 + spell id into the caster's storage
-- storageContext while the spell's own code runs (also its delayed pulses). onHealthChange (ChaosSupportsHit, on the
-- targets of players with runes, on every player, on hexed monsters) reads it; hits of a spell are collected until
-- the end of the server tick and the extra hits (Echo, Fork, Breadth, Shatter, Deathburst, Surge) are dealt from an
-- addEvent with the proc guard up (this file's depth and ChaosKeystones.depth), so they never trigger supports or
-- keystones again. Extra hits only hit monsters (never players, never a player's summon).
--
-- protocol (JSON {action, data}):
--   client -> server  open | socket {spell, slot?, rune} | socket {spell, slot?, pos = {x, y, z}, clientId} |
--                     remove {spell, slot, keep} | unlock {spell} | combine {rune}
--   server -> client  state {level, orbId, orbCount, orbsNeeded, spells = [...], runes = [...]}
--                     bar {spells = {[spell id] = [{slot, id, key, name, level, color, text}]}, words = {[words] = id}}
--                     result {ok, text}
--                     part {id, index, total, text}: a slice of a bigger answer (state or bar) as JSON text
--   spell = {id, name, words, level, kind, kindName, count, max, opened, secondLevel, thirdLevel, canOpen,
--            runes = [{slot, id, clientId, key, name, level, color, text, cost}]}
--   rune  = {id, clientId, key, name, level, color, text, fits, count, combine}
-- Lua 5.1 / LuaJIT.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end

-- the type behind a shown name (chaos_constants.lua "Monster names"; a renamed rift monster or invader is still its type)
local function typeNameOf(creature)
	return Chaos.monsterTypeName and Chaos.monsterTypeName(creature) or creature:getName()
end
if not ChaosGems and not ChaosCrafting then
	pcall(dofile, "data/lib/chaos_crafting.lua") -- loads chaos_gems.lua (reused: give, pickIndex, level weights)
end
if not ChaosSupports then
	dofile("data/lib/chaos_supports.lua")
end

local S = ChaosSupports
local cfg = S.config
local OPCODE = ChaosOpcodes.supports or 243
local E = cfg.effect

S.depth = S.depth or 0

local function now()
	return os.mtime and os.mtime() or os.time() * 1000
end

local function copyPos(p)
	return {x = p.x, y = p.y, z = p.z}
end

local function dist(a, b)
	if a.z ~= b.z then
		return math.huge
	end
	return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end

-- ---------------------------------------------------------------- the spells (read once from spells.xml)
local catalog -- spell id -> {id, name, words, level, kind, element, vocations = {[id] = true}, mana, cooldown}

local ELEMENT_TYPE = {
	fire = COMBAT_FIREDAMAGE, ice = COMBAT_ICEDAMAGE, holy = COMBAT_HOLYDAMAGE, death = COMBAT_DEATHDAMAGE,
	energy = COMBAT_ENERGYDAMAGE, earth = COMBAT_EARTHDAMAGE, physical = COMBAT_PHYSICALDAMAGE
}
S.ELEMENT_TYPE = ELEMENT_TYPE

function S.loadCatalog()
	local out = {}
	local Book = ChaosSpellbook
	local path = (Book and Book.spellsXml) or "data/spells/spells.xml"
	local f = io.open(path, "r")
	local text = f and f:read("*a") or ""
	if f then
		f:close()
	end
	local eligible = S.eligible(S.parseSpellsXml(text))
	local cache = {}
	local entries = Book and Book.parseXml and Book.parseXml(text) or {}
	for _, entry in ipairs(entries) do
		local id = tonumber(entry.attrs and entry.attrs.spellid)
		local e = id and eligible[id]
		if e and entry.tag == "instant" then
			local ok, spell = pcall(Book.buildSpell, entry, cache)
			local kind = S.kindOf(id, ok and spell and spell.type, ok and spell and spell.target)
			if kind then
				local vocs = {}
				for _, v in ipairs(ok and spell and spell.vocations or {}) do
					vocs[v] = true
				end
				out[id] = {id = id, name = e.name, words = e.words, level = e.level, kind = kind, mana = e.mana,
					cooldown = e.cooldown, vocations = vocs, element = ok and spell and spell.element or nil}
			end
		end
	end
	-- without the spellbook parser (tests, a broken install): every eligible spell, kind from the override or buff
	if not next(out) then
		for id, e in pairs(eligible) do
			out[id] = {id = id, name = e.name, words = e.words, level = e.level, kind = S.kindOf(id, nil, nil),
				mana = e.mana, cooldown = e.cooldown, vocations = {}}
		end
	end
	catalog = out
	return out
end

function S.catalog()
	return catalog or S.loadCatalog()
end

function S.spellInfo(id)
	return S.catalog()[tonumber(id) or -1]
end

-- ---------------------------------------------------------------- effects per player and spell (cached)
local fxCache = {} -- pid -> {[spell id] = {level =, fx =}}
local active = {} -- pid -> true when any spell carries a rune

local function effectsFor(player, spellId)
	local pid = player:getId()
	local level = player:getLevel()
	local byPlayer = fxCache[pid]
	if not byPlayer then
		byPlayer = {}
		fxCache[pid] = byPlayer
	end
	local c = byPlayer[spellId]
	if c and c.level == level then
		return c.fx
	end
	local info = S.spellInfo(spellId)
	local fx = S.spellEffects(player, spellId, info and info.level or 0)
	byPlayer[spellId] = {level = level, fx = fx}
	return fx
end
S.effectsFor = effectsFor

local function refreshActive(player)
	local any = false
	for id in pairs(S.catalog()) do
		local sock = S.read(player, id)
		for i = 1, cfg.maxSockets do
			if sock and sock.runes[i] > 0 then
				any = true
				break
			end
		end
		if any then
			break
		end
	end
	active[player:getId()] = any or nil
	fxCache[player:getId()] = nil
	return any
end
S.refreshActive = refreshActive

-- ---------------------------------------------------------------- targets and extra hits
local function isFoe(attacker, c)
	if not c or c:getId() == attacker:getId() or c:getHealth() <= 0 or not c:isMonster() then
		return false
	end
	local master = c:getMaster()
	if master and (master:getId() == attacker:getId() or master:isPlayer()) then
		return false
	end
	local tile = c:getTile()
	return not (tile and tile:hasFlag(TILESTATE_PROTECTIONZONE))
end

local function foesAround(attacker, pos, radius)
	local list = {}
	local center = Position(pos.x, pos.y, pos.z)
	for _, c in ipairs(Game.getSpectators(center, false, false, radius, radius, radius, radius) or {}) do
		if isFoe(attacker, c) then
			list[#list + 1] = {id = c:getId(), pos = copyPos(c:getPosition()), creature = c}
		end
	end
	return list
end

local function guarded(fn, ...)
	S.depth = S.depth + 1
	local K = ChaosKeystones
	if K then
		K.depth = (K.depth or 0) + 1
	end
	local ok, err = pcall(fn, ...)
	if K then
		K.depth = K.depth - 1
	end
	S.depth = S.depth - 1
	if not ok then
		print("[Chaos supports] " .. tostring(err))
	end
end

local function fxId(name, fallback)
	if Fx then
		local ok, id = pcall(Fx, name, fallback)
		if ok and id then
			return id
		end
	end
	return fallback
end

local function procDamage(attacker, target, ctype, amount, effect)
	amount = math.floor(math.abs(amount))
	if amount > 0 and target and target:getHealth() > 0 then
		guarded(doTargetCombat, attacker, target, ctype or COMBAT_PHYSICALDAMAGE, -amount, -amount, effect or CONST_ME_NONE,
			ORIGIN_SPELL)
	end
end

-- nearest foes around pos (not in `skip`), at most max, nearest first then lowest id
local function pickFoes(attacker, pos, radius, skip, max)
	local list = {}
	for _, c in ipairs(foesAround(attacker, pos, radius)) do
		if not skip[c.id] then
			c.d = dist(pos, c.pos)
			list[#list + 1] = c
		end
	end
	table.sort(list, function(a, b)
		if a.d ~= b.d then
			return a.d < b.d
		end
		return a.id < b.id
	end)
	for i = #list, max + 1, -1 do
		list[i] = nil
	end
	return list
end

-- ---------------------------------------------------------------- monster resistances
local resCache = {}
local function resistances(creature)
	if not creature or not creature:isMonster() then
		return nil
	end
	local name = typeNameOf(creature):lower()
	local r = resCache[name]
	if r == nil then
		r = false
		local ok, list = pcall(function()
			local t = creature:getType()
			return t and t:getElementList()
		end)
		if ok and type(list) == "table" then
			r = list
		end
		resCache[name] = r
	end
	return r or nil
end

-- ---------------------------------------------------------------- hexes (monster id -> {pct, untilTime})
local hexes = {}
local hexCount = 0
local function setHex(creature, pct)
	local id = creature:getId()
	local t = now()
	local h = hexes[id]
	if not h or h.untilTime < t or h.pct <= pct then
		if not h or h.untilTime < t then
			creature:getPosition():sendMagicEffect(fxId("arcane_circle", CONST_ME_PURPLEENERGY))
		end
		hexes[id] = {pct = pct, untilTime = t + E.hexDuration}
		creature:registerEvent("ChaosSupportsHit")
	end
	hexCount = hexCount + 1
	if hexCount > 300 then
		hexCount = 0
		for hid, x in pairs(hexes) do
			if x.untilTime < t or not Creature(hid) then
				hexes[hid] = nil
			end
		end
	end
end

-- ---------------------------------------------------------------- per cast state and the hit buffer
local casts = {} -- pid -> {serial, healed, mana, echo, burst, surge}
local buffers = {} -- pid -> {spellId, serial, hits = {}, index = {}, total}

local function castOf(pid, serial)
	local c = casts[pid]
	if not c or c.serial ~= serial then
		c = {serial = serial, healed = 0, mana = 0}
		casts[pid] = c
	end
	return c
end

local function runEcho(pid, hits, pct)
	local p = Player(pid)
	if not p then
		return
	end
	for _, h in ipairs(hits) do
		local c = Creature(h.id)
		if c and isFoe(p, c) and dist(c:getPosition(), h.pos) <= 1 then
			local pos = c:getPosition()
			pos:sendMagicEffect(fxId("arcane_burst", CONST_ME_ENERGYAREA))
			procDamage(p, c, h.type, S.part(h.amount, pct), CONST_ME_NONE)
		end
	end
end

local function flush(pid)
	local b = buffers[pid]
	buffers[pid] = nil
	local p = Player(pid)
	if not b or not p or #b.hits == 0 then
		return
	end
	local fx = effectsFor(p, b.spellId)
	local cast = castOf(pid, b.serial)
	local hits = b.hits
	local hitSet = {}
	local main = hits[1]
	for _, h in ipairs(hits) do
		hitSet[h.id] = true
		if h.amount > main.amount then
			main = h
		end
	end

	-- Bloodthirst / Siphon: capped per cast
	if fx.bloodthirst then
		local cap = math.floor(p:getMaxHealth() * E.bloodthirstMaxShare / 100)
		local heal = math.min(math.floor(b.total * fx.bloodthirst.value / 100), cap - cast.healed)
		if heal > 0 then
			cast.healed = cast.healed + heal
			guarded(doTargetCombat, p, p, COMBAT_HEALING, heal, heal, CONST_ME_NONE, ORIGIN_SPELL)
		end
	end
	if fx.siphon then
		local cap = math.floor(p:getMaxMana() * E.siphonMaxShare / 100)
		local mana = math.min(math.floor(b.total * fx.siphon.value / 1000), cap - cast.mana)
		if mana > 0 then
			cast.mana = cast.mana + mana
			p:addMana(mana)
		end
	end

	-- Echo: rolled once per cast; every hit group of that cast strikes again
	if fx.echo then
		if cast.echo == nil then
			cast.echo = S.roll(fx.echo.value)
		end
		if cast.echo then
			addEvent(runEcho, E.echoDelay, pid, hits, fx.echo.value2 or 50)
		end
	end

	-- Fork (single target): to the nearest other foes
	if fx.fork then
		local from = main.pos
		for _, c in ipairs(pickFoes(p, from, E.forkRange, hitSet, fx.fork.value)) do
			Position(from.x, from.y, from.z):sendDistanceEffect(c.pos, CONST_ANI_ENERGY)
			procDamage(p, c.creature, main.type, S.part(main.amount, fx.fork.value2 or 40), fxId("chain_lightning",
				CONST_ME_ENERGYHIT))
			hitSet[c.id] = true
		end
	end

	-- Shatter (single target): foes next to the target
	if fx.shatter then
		for _, c in ipairs(pickFoes(p, main.pos, 1, hitSet, E.shatterMax)) do
			procDamage(p, c.creature, main.type, S.part(main.amount, fx.shatter.value), CONST_ME_EXPLOSIONHIT)
			hitSet[c.id] = true
		end
	end

	-- Breadth (area): foes near the hit ones that the spell missed
	if fx.breadth then
		local avg = math.floor(b.total / #hits)
		local extra, seen = {}, {}
		for _, h in ipairs(hits) do
			for _, c in ipairs(pickFoes(p, h.pos, fx.breadth.value, hitSet, E.breadthMax)) do
				if not seen[c.id] and #extra < E.breadthMax then
					seen[c.id] = true
					extra[#extra + 1] = c
				end
			end
		end
		for _, c in ipairs(extra) do
			procDamage(p, c.creature, main.type, S.part(avg, fx.breadth.value2 or 40), fxId("shockwave",
				CONST_ME_EXPLOSIONAREA))
			hitSet[c.id] = true
		end
	end

	-- Deathburst: once per cast, on the first killing hit
	if fx.deathburst and not cast.burst then
		for _, h in ipairs(hits) do
			if h.kill then
				cast.burst = true
				local pos = Position(h.pos.x, h.pos.y, h.pos.z)
				pos:sendMagicEffect(fxId("blood_rune", CONST_ME_EXPLOSIONAREA))
				for _, c in ipairs(pickFoes(p, h.pos, E.burstRadius, {[h.id] = true}, 8)) do
					procDamage(p, c.creature, h.type, S.part(h.amount, fx.deathburst.value), CONST_ME_NONE)
				end
				break
			end
		end
	end

	-- Surge: once per cast, on the first critical hit
	if fx.surge and not cast.surge then
		for _, h in ipairs(hits) do
			if h.crit then
				cast.surge = true
				Position(h.pos.x, h.pos.y, h.pos.z):sendMagicEffect(fxId("arcane_burst", CONST_ME_ENERGYAREA))
				for _, c in ipairs(pickFoes(p, h.pos, 1, {[h.id] = true}, 8)) do
					procDamage(p, c.creature, h.type, S.part(h.amount, fx.surge.value), CONST_ME_NONE)
				end
				break
			end
		end
	end
end

local function record(pid, spellId, serial, creature, amount, ctype, crit, kill)
	local b = buffers[pid]
	if not b or b.serial ~= serial then
		if b then
			flush(pid)
		end
		b = {spellId = spellId, serial = serial, hits = {}, index = {}, total = 0}
		buffers[pid] = b
		addEvent(flush, 0, pid)
	end
	local cid = creature:getId()
	local i = b.index[cid]
	if i then
		local h = b.hits[i]
		h.amount = h.amount + amount
		h.crit = h.crit or crit
		h.kill = h.kill or kill
	else
		b.hits[#b.hits + 1] = {id = cid, pos = copyPos(creature:getPosition()), amount = amount, type = ctype, crit = crit,
			kill = kill}
		b.index[cid] = #b.hits
	end
	b.total = b.total + amount
end

-- ---------------------------------------------------------------- Reprisal (the caster is hit)
local reprisalNext = {} -- pid -> time of the next allowed strike back

local function reprisal(player, attacker, amount, origin)
	if origin == ORIGIN_CONDITION or not attacker or attacker:isPlayer() then
		return
	end
	local untilTime = player:getStorageValue(cfg.storageReprisalUntil)
	if not untilTime or untilTime < os.time() then
		return
	end
	local spellId = player:getStorageValue(cfg.storageReprisal)
	local fx = spellId and spellId > 0 and effectsFor(player, spellId)
	if not fx or not fx.reprisal then
		return
	end
	local pid, t = player:getId(), now()
	if (reprisalNext[pid] or 0) > t or not S.roll(E.reprisalChance) then
		return
	end
	reprisalNext[pid] = t + E.reprisalCooldown
	local back = math.min(math.floor(amount * fx.reprisal.value / 100),
		math.floor(player:getMaxHealth() * E.reprisalMaxShare / 100))
	local info = S.spellInfo(spellId)
	local ctype = info and ELEMENT_TYPE[info.element or ""] or COMBAT_PHYSICALDAMAGE
	local aid = attacker:getId()
	addEvent(function()
		local p, a = Player(pid), Creature(aid)
		if p and a and isFoe(p, a) then
			p:getPosition():sendDistanceEffect(a:getPosition(), CONST_ANI_ENERGY)
			procDamage(p, a, ctype, back, CONST_ME_HITAREA)
		end
	end, 0)
end

-- ---------------------------------------------------------------- the damage event
local event = CreatureEvent("ChaosSupportsHit")
function event.onHealthChange(creature, attacker, pd, pt, sd, st, origin, critical)
	if not creature or S.depth > 0 then
		return pd, pt, sd, st
	end
	-- heals: Mercy of the caster's spell
	if pt == COMBAT_HEALING then
		if attacker and attacker:isPlayer() and origin ~= ORIGIN_CONDITION then
			local serial, spellId = S.ctxDecode(attacker:getStorageValue(cfg.storageContext))
			local fx = serial and effectsFor(attacker, spellId)
			if fx and fx.mercy then
				pd, sd = S.scale(pd, fx.mercy.value), S.scale(sd, fx.mercy.value)
			end
		end
		return pd, pt, sd, st
	end
	-- hexed monster: more damage from everyone
	local hex = hexes[creature:getId()]
	if hex then
		if hex.untilTime >= now() then
			pd, sd = S.scale(pd, hex.pct), S.scale(sd, hex.pct)
		else
			hexes[creature:getId()] = nil
		end
	end
	if not attacker then
		return pd, pt, sd, st
	end
	if creature:isPlayer() and attacker:getId() ~= creature:getId() then
		reprisal(creature, attacker, math.abs(pd) + math.abs(sd), origin)
	end
	if not attacker:isPlayer() or attacker:getId() == creature:getId() or origin == ORIGIN_CONDITION then
		return pd, pt, sd, st
	end
	local serial, spellId = S.ctxDecode(attacker:getStorageValue(cfg.storageContext))
	if not serial then
		return pd, pt, sd, st
	end
	local fx = effectsFor(attacker, spellId)
	if not next(fx) then
		return pd, pt, sd, st
	end
	local res = resistances(creature)
	local resOf = res and function(t) return res[t] or 0 end or nil
	-- brand
	for _, e in pairs(fx) do
		if e.element and ELEMENT_TYPE[e.element] then
			pd, pt, sd, st = S.convert(pd, pt, sd, st, e.value, ELEMENT_TYPE[e.element], resOf)
			break
		end
	end
	-- Sunder
	if fx.sunder and resOf then
		pd = S.penetrate(pd, resOf(pt), fx.sunder.value)
		if sd ~= 0 then
			sd = S.penetrate(sd, resOf(st), fx.sunder.value)
		end
	end
	-- Keen Edge
	local crit = critical == true
	if fx.keenedge and not crit and S.roll(fx.keenedge.value) then
		crit = true
		local m = fx.keenedge.value2 or 50
		pd, sd = S.scale(pd, m), S.scale(sd, m)
		if ChaosCombatFx and ChaosCombatFx.crit then
			pcall(ChaosCombatFx.crit, creature:getPosition(), attacker:getId())
		end
	end
	-- Hex
	if fx.hex and creature:isMonster() then
		setHex(creature, fx.hex.value)
	end
	local amount = math.abs(pd) + math.abs(sd)
	if amount > 0 then
		-- the extra hits take the element of the bigger part (a brand may have moved most of it)
		local ctype = (sd ~= 0 and math.abs(sd) > math.abs(pd)) and st or pt
		record(attacker:getId(), spellId, serial, creature, amount, ctype, crit, amount >= creature:getHealth())
	end
	return pd, pt, sd, st
end
event:register()

-- the event sits on whatever a player with runes attacks (and on every player: heals, Reprisal)
-- Chaos.registerOnce / eventKnown (chaos_constants.lua): register on a monster once, not at every hit
local function registerOnce(creature, name)
	local f = Chaos and Chaos.registerOnce
	if f then
		return f(creature, name)
	end
	creature:registerEvent(name)
	return true
end
local function eventKnown(creature, name)
	local f = Chaos and Chaos.eventKnown
	return f ~= nil and f(creature, name)
end
local targetCb = EventCallback
targetCb.onTargetCombat = function(creature, target)
	if creature and target and creature ~= target and creature:isPlayer() and active[creature:getId()] then
		registerOnce(target, "ChaosSupportsHit")
	end
	return RETURNVALUE_NOERROR
end
targetCb:register(1)

-- ---------------------------------------------------------------- the window
local function clientIdOf(id)
	local ok, cid = pcall(function() return ItemType(id):getClientId() end)
	return ok and cid or 0
end

local function vocationOf(player)
	local v = player:getVocation()
	return v and v:getId() or 0
end

local function runeView(id, count)
	local r = S.runeOf(id)
	return {id = id, clientId = clientIdOf(id), key = r.type.key, name = S.runeName(id), level = r.level,
		color = S.levelColor(id), text = S.effectText(id), fits = S.fitsText(r.type), count = count,
		combine = r.level < S.LEVELS}
end

local function socketsOf(player, info)
	local sock = S.read(player, info.id)
	return sock, S.socketCount(player:getLevel(), info.level, sock.opened)
end

local function spellView(player, info)
	local sock, count = socketsOf(player, info)
	local runes = {}
	for i = 1, cfg.maxSockets do
		local id = sock.runes[i]
		if id > 0 then
			local v = runeView(id)
			v.slot = i
			v.cost = S.removeCost(id)
			v.inactive = i > count or nil
			runes[#runes + 1] = v
		end
	end
	local third = S.thirdLevel(info.level)
	return {id = info.id, name = info.name, words = info.words, level = info.level, kind = info.kind,
		kindName = cfg.kindNames[info.kind], count = count, max = cfg.maxSockets, opened = sock.opened,
		secondLevel = S.secondLevel(info.level), thirdLevel = third,
		canOpen = (not sock.opened) and player:getLevel() >= third, runes = runes}
end

-- the spells a player sees: its class kit (vocation of the spell) plus any spell that holds a rune
local function spellsOf(player)
	local voc = vocationOf(player)
	local out = {}
	for id, info in pairs(S.catalog()) do
		local mine = info.vocations[voc]
		if not mine then
			local sock = S.read(player, id)
			for i = 1, cfg.maxSockets do
				if sock.runes[i] > 0 then
					mine = true
				end
			end
		end
		if mine then
			out[#out + 1] = info
		end
	end
	table.sort(out, function(a, b)
		if a.level ~= b.level then
			return a.level < b.level
		end
		return a.id < b.id
	end)
	return out
end
S.spellsOf = spellsOf

local function runesOf(player)
	local out = {}
	for id = cfg.firstId, S.lastId do
		local n = player:getItemCount(id)
		if n > 0 then
			out[#out + 1] = runeView(id, n)
		end
	end
	return out
end

-- an answer bigger than one extended opcode string (the engine drops strings over 8 KB and the client then misreads
-- the packet): the JSON goes out in slices {action = "part", data = {id, index, total, text}}, one per server tick;
-- the client joins them and handles the whole as `action`
local PART_BYTES = 6000
local partSerial = 0
local function sendBig(player, action, data)
	local text = json.encode({action = action, data = data})
	if #text <= PART_BYTES then
		player:sendExtendedOpcode(OPCODE, text)
		return
	end
	partSerial = partSerial % 100000 + 1
	local id, pid, total = partSerial, player:getId(), math.ceil(#text / PART_BYTES)
	for i = 1, total do
		local slice = text:sub((i - 1) * PART_BYTES + 1, i * PART_BYTES)
		addEvent(function()
			local p = Player(pid)
			if p then
				Chaos.send(p, OPCODE, "part", {id = id, index = i, total = total, text = slice})
			end
		end, (i - 1) * 50)
	end
end
S.sendBig = sendBig

local function sendBar(player)
	local bar = {}
	for id in pairs(S.catalog()) do
		local sock = S.read(player, id)
		local list
		for i = 1, cfg.maxSockets do
			local r = sock.runes[i]
			if r > 0 then
				list = list or {}
				local v = runeView(r)
				v.slot = i
				list[#list + 1] = v
			end
		end
		if list then
			bar[tostring(id)] = list
		end
	end
	local words = {}
	for _, info in ipairs(spellsOf(player)) do
		if info.words then
			words[info.words] = info.id
		end
	end
	sendBig(player, "bar", {spells = bar, words = words})
end
S.sendBar = sendBar

local function sendState(player)
	local spells = {}
	for _, info in ipairs(spellsOf(player)) do
		spells[#spells + 1] = spellView(player, info)
	end
	local orb = ChaosGems and ChaosGems.config.socketOrb or {id = 24692, name = "Orb of Sockets"}
	sendBig(player, "state", {level = player:getLevel(), orbId = orb.id, orbClientId = clientIdOf(orb.id),
		orbName = orb.name, orbCount = player:getItemCount(orb.id), orbsNeeded = cfg.third.orbs, spells = spells,
		runes = runesOf(player)})
end
S.sendState = sendState

local function sendResult(player, ok, text)
	Chaos.send(player, OPCODE, "result", {ok = ok and true or false, text = text})
	if ok then
		player:sendTextMessage(MESSAGE_INFO_DESCR, text)
	end
end

local function log(player, what, name, text)
	if ChaosCraftingLog then
		pcall(ChaosCraftingLog, player, what, name, text)
	end
end

local function changed(player)
	refreshActive(player)
	sendBar(player)
end

local function give(player, id, count)
	if ChaosGems and ChaosGems.give then
		return ChaosGems.give(player, id, count)
	end
	player:addItem(id, count)
	return false
end

-- gold for a removal: carried coins, then the bank (Chaos.pay)
local function pay(player, cost)
	if cost <= 0 then
		return true
	end
	return Chaos.pay(player, cost)
end

-- the spell a player may change: in the catalog, and in the class kit or holding a rune
local function ownSpell(player, spellId)
	local info = S.spellInfo(spellId)
	if not info then
		return nil
	end
	for _, s in ipairs(spellsOf(player)) do
		if s.id == info.id then
			return info
		end
	end
	return nil
end

-- the rune of a socket request: data.rune (server id) or an item dragged from a container (pos + clientId)
local function runeOfRequest(player, data)
	local id = Chaos.toInt(data.rune, cfg.firstId, S.lastId)
	if id then
		return id
	end
	if type(data.pos) == "table" then
		local x, y, z = Chaos.toInt(data.pos.x), Chaos.toInt(data.pos.y), Chaos.toInt(data.pos.z)
		local item
		if x == 65535 and y and z and y >= 64 then
			local container = player:getContainerById(y - 64)
			item = container and container:getItem(z)
		elseif x == 65535 and y and y >= 1 and y <= 10 then
			item = player:getSlotItem(y)
		end
		if item and S.isRune(item:getId()) then
			local cid = Chaos.toInt(data.clientId, 1, 65535)
			if not cid or clientIdOf(item:getId()) == cid then
				return item:getId()
			end
		end
	end
	return nil
end

function S.socket(player, spellId, runeId, slot)
	local info = ownSpell(player, spellId)
	if not info then
		return false, S.reasons.noSpell
	end
	if not S.isRune(runeId) then
		return false, S.reasons.notRune
	end
	if player:getItemCount(runeId) < 1 then
		return false, "You do not carry that rune."
	end
	local sock, count = socketsOf(player, info)
	if count < 1 then
		return false, string.format("You need level %d to cast %s.", info.level, info.name)
	end
	local i, why = S.canSocket(sock, count, runeId, info.kind, slot)
	if not i then
		return false, why
	end
	if not player:removeItem(runeId, 1) then
		return false, "You do not carry that rune."
	end
	S.setRune(player, info.id, i, runeId)
	changed(player)
	local text = string.format("%s socketed into %s (socket %d): %s.", S.runeName(runeId), info.name, i,
		S.effectText(runeId))
	log(player, "Support", info.name, text)
	player:getPosition():sendMagicEffect(CONST_ME_MAGIC_BLUE)
	return true, text
end

function S.unsocket(player, spellId, slot, keep)
	local info = S.spellInfo(spellId)
	slot = tonumber(slot) or 0
	local sock = info and S.read(player, info.id)
	local id = sock and sock.runes[slot] or 0
	if not info or slot < 1 or slot > cfg.maxSockets or id == 0 then
		return false, S.reasons.empty
	end
	local cost = keep and S.removeCost(id) or 0
	if not pay(player, cost) then
		return false, string.format("Taking the %s out unharmed costs %d gold (bank or backpack).", S.runeName(id), cost)
	end
	S.setRune(player, info.id, slot, 0)
	changed(player)
	local text
	if keep then
		local inbox = give(player, id, 1)
		text = string.format("%s taken out of %s for %d gold.%s", S.runeName(id), info.name, cost,
			inbox and " It is in your inbox (no room)." or "")
		player:getPosition():sendMagicEffect(CONST_ME_MAGIC_BLUE)
	else
		text = string.format("%s shattered (taken out of %s).", S.runeName(id), info.name)
		player:getPosition():sendMagicEffect(CONST_ME_BLOCKHIT)
	end
	log(player, keep and "Support removed" or "Support shattered", info.name, text)
	return true, text
end

function S.unlock(player, spellId)
	local info = ownSpell(player, spellId)
	if not info then
		return false, S.reasons.noSpell
	end
	local sock = S.read(player, info.id)
	if sock.opened then
		return false, S.reasons.opened
	end
	local need = S.thirdLevel(info.level)
	if player:getLevel() < need then
		return false, string.format(S.reasons.level3, need)
	end
	local orb = ChaosGems and ChaosGems.config.socketOrb or {id = 24692, name = "Orb of Sockets"}
	local n = cfg.third.orbs
	if player:getItemCount(orb.id) < n or not player:removeItem(orb.id, n) then
		return false, string.format("Opening the third socket takes %d %s.", n, n > 1 and "Orbs of Sockets" or orb.name)
	end
	S.setOpened(player, info.id)
	changed(player)
	local text = string.format("The third support socket of %s is open (%d %s used).", info.name, n,
		n > 1 and "Orbs of Sockets" or orb.name)
	log(player, "Support socket", info.name, text)
	player:getPosition():sendMagicEffect(CONST_ME_MAGIC_GREEN)
	return true, text
end

function S.combine(player, id)
	local newId, why = S.combineResult(id)
	if not newId then
		return false, S.reasons[why] or why
	end
	if player:getItemCount(id) < 3 or not player:removeItem(id, 3) then
		return false, S.reasons.needThree
	end
	local inbox = give(player, newId, 1)
	local text = string.format("Three %ss became one %s.%s", S.runeName(id), S.runeName(newId),
		inbox and " It is in your inbox (no room)." or "")
	log(player, "Support", S.runeName(id), text)
	player:getPosition():sendMagicEffect(CONST_ME_MAGIC_GREEN)
	return true, text
end

-- ---------------------------------------------------------------- drops (loot.lua) and rewards (rift.lua, bounty.lua)
-- a kill: adds 0 or 1 rune to the corpse; returns the names (for the loot line)
function S.lootDrop(corpse, tier, level, scale, rand)
	local names = {}
	for _, id in ipairs(S.rollDrop(tier, level, scale, rand)) do
		if corpse:addItem(id, 1) then
			names[#names + 1] = S.runeName(id)
		end
	end
	return names
end

-- ---------------------------------------------------------------- events
local ext = CreatureEvent("ChaosSupportsExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg or type(msg.action) ~= "string" then
		return
	end
	if ChaosRateLimit and ChaosRateLimit.allow and not ChaosRateLimit.allow(player, "supports", 150) then
		return
	end
	local data = type(msg.data) == "table" and msg.data or {}
	local ok, text
	if msg.action == "open" then
		sendState(player)
		sendBar(player)
		return
	elseif msg.action == "socket" then
		local rune = runeOfRequest(player, data)
		if not rune then
			ok, text = false, S.reasons.notRune
		else
			ok, text = S.socket(player, Chaos.toInt(data.spell, 0, cfg.maxSpellId), rune,
				Chaos.toInt(data.slot, 1, cfg.maxSockets))
		end
	elseif msg.action == "remove" then
		ok, text = S.unsocket(player, Chaos.toInt(data.spell, 0, cfg.maxSpellId), Chaos.toInt(data.slot, 1,
			cfg.maxSockets), data.keep == true)
	elseif msg.action == "unlock" then
		ok, text = S.unlock(player, Chaos.toInt(data.spell, 0, cfg.maxSpellId))
	elseif msg.action == "combine" then
		ok, text = S.combine(player, Chaos.toInt(data.rune, cfg.firstId, S.lastId))
	else
		return
	end
	sendResult(player, ok, text)
	sendState(player)
end
ext:register()

local login = CreatureEvent("ChaosSupportsLogin")
function login.onLogin(player)
	player:registerEvent("ChaosSupportsExtended")
	player:registerEvent("ChaosSupportsHit")
	player:registerEvent("ChaosSupportsLogout")
	player:registerEvent("ChaosSupportsAdvance")
	player:setStorageValue(cfg.storageContext, -1)
	refreshActive(player)
	local pid = player:getId()
	addEvent(function()
		local p = Player(pid)
		if p then
			sendBar(p)
		end
	end, 1500)
	return true
end
login:register()

local logout = CreatureEvent("ChaosSupportsLogout")
function logout.onLogout(player)
	local pid = player:getId()
	fxCache[pid], active[pid], casts[pid], buffers[pid], reprisalNext[pid] = nil, nil, nil, nil, nil
	return true
end
logout:register()

-- a level up opens sockets: the cached effects follow the level by themselves; the bar is sent again
local advance = CreatureEvent("ChaosSupportsAdvance")
function advance.onAdvance(player, skill, oldLevel, newLevel)
	if skill == SKILL_LEVEL and newLevel > oldLevel and active[player:getId()] then
		sendBar(player)
	end
	return true
end
advance:register()

-- using a rune (plain use or use with anything) opens the window
local function onUseRune(player, item, fromPosition, target, toPosition, isHotkey)
	local id = item:getId()
	if target and type(target) ~= "number" and target.isItem and target:isItem() and target:getId() == id then
		local ok, text = S.combine(player, id)
		if ok then
			player:sendTextMessage(MESSAGE_INFO_DESCR, text)
		else
			player:sendCancelMessage(text)
		end
	else
		player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, "%s - %s. Fits %s spells. Socket it in the spell supports window (Character > Spell Supports).", S.runeName(id), S.effectText(id), S.fitsText(S.runeOf(id).type)))
	end
	sendState(player)
	sendBar(player)
	return true
end

for id = cfg.firstId, S.lastId do
	local action = Action()
	action.onUse = onUseRune
	action:id(id)
	action:allowFarUse(false)
	action:register()
end

-- staff only (players open the window from the menu): /supports reload
local talk = TalkAction("/supports")
function talk.onSay(player, words, param)
	if not player:getGroup():getAccess() then
		return false -- players open it from the menu
	end
	if param and param:lower():find("reload") and player:getGroup():getAccess() then
		local n = 0
		for _ in pairs(S.loadCatalog()) do
			n = n + 1
		end
		fxCache = {}
		player:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, string.format("Supports: %d spells with sockets.", n))
		return false
	end
	sendState(player)
	sendBar(player)
	return false
end
talk:separator(" ")
talk:register()

local startup = GlobalEvent("ChaosSupportsStartup")
function startup.onStartup()
	local n = 0
	for _ in pairs(S.loadCatalog()) do
		n = n + 1
	end
	print(string.format("[Chaos supports] %d spells with sockets, %d support runes (%d..%d), opcode %d", n,
		S.LEVELS * S.TYPES, cfg.firstId, S.lastId, OPCODE))
	return true
end
startup:register()
