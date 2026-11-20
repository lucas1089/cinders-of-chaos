-- Spell awakening, the engine side (O686 phase 7; docs/SPELL_UPGRADES.md section 3; server/README.md "Spell awakening (O686 phase 7)").
-- Rules: spell_awakening_core.lua, numbers: spell_awakening_config.lua, the table of names and signatures: data/spells/awakened.csv, the read
-- API data/lib/chaos_spell_awakening.lua, tests: server/tests/spell_awakening_test.lua (this file on a mocked engine).
--
-- * Nothing here acts while spell_ranks_config.lua `enabled` is false or spell_awakening_config.lua `enabled` is false: no Seal is given,
--   `awaken` answers `off`, no hit gets the bonus, no signature runs.
-- * The Seals. Three counters in storage (never items): Waystone, Rift and Pinnacle. The contents call the hooks below, each already
--   guarded by the switch: ChaosSpellAwakening.onWaystoneClear (waystone_endgame.lua, a cleared map of tier 16-25 and its first clear),
--   .onRiftRun (rift.lua greaterSettle, a Greater Rift run that ends at tier 16+), .onPinnacleKill (pinnacle.lua success, every member).
-- * Awaken. Opcode 168 `awaken {spell, slot}`: the spell is at rank 20 with both Forms picked, a slot is free (the lowest), the Seals of that
--   slot are held; the Seals are paid, bit 9 of the spell's packed state is set and the spell id is written into the slot. The answer is an
--   `awaken` message {ok, why, spell, slot, name, cost, need}; `awakened` is the state ({seals, slots, costs}) sent on `open`, after an
--   awaken and after a Seal. A spell the character no longer knows is dormant and frees its slot at once at login (design 1.6); the
--   Seals spent are not returned.
-- * The bonus. ChaosSpellAwakening.hitFactor is asked by ChaosPassiveDealt (passivetree_effects.lua) for every hit of a player, after the
--   rank and combo factors: an awakened spell's hit or heal is +10%, against a player at the PvP share of the rank. It also spends a mark.
-- * The signature. spell_forms.lua `flush` (the end of a cast, from the same hit buffer the Forms use) calls ChaosSpellAwakening.onCast: the
--   awakened spell's row is planned (spell_awakening_core.lua A.plan: held to capShare of the cast's own damage) and run inside the spell's
--   cast context, with the Forms' guard up (no passive tree bonus twice, no Form again), so the credit of the ranks goes to the spell. Never
--   in PvP. Effects are the spell's own element (the same effect names the Forms send).
-- * Look. No new effects in this phase (design 3.4: until the kit art, an awakened spell plays its normal effects with the new name).
-- Assumed engine API (TFS 1.4.2): CreatureEvent login/logout/kill, Player:get/setStorageValue/addMana/getMaxMana/hasLearnedSpell,
-- Creature:getMaxHealth, addEvent, Creature(id), Player(id), Position. Lua 5.1 / LuaJIT and Lua 5.3 compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosSpellAwakeningCore or not ChaosSpellAwakeningCore.plan then
	dofile("data/scripts/chaos/spell_awakening_core.lua")
end
if not ChaosSpellRanksCore or not ChaosSpellRanksCore.power then
	dofile("data/scripts/chaos/spell_ranks_core.lua")
end
ChaosSpellRanksConfig = ChaosSpellRanksConfig or dofile("data/scripts/chaos/spell_ranks_config.lua")
ChaosSpellAwakeningConfig = dofile("data/scripts/chaos/spell_awakening_config.lua")
dofile("data/lib/chaos_spell_ranks.lua")
dofile("data/lib/chaos_spell_awakening.lua")
pcall(dofile, "data/lib/chaos_spell_forms.lua")

local AW = ChaosSpellAwakening
local A = ChaosSpellAwakeningCore
local P = ChaosSpellRanksCore
local R = ChaosSpellRanks
local cfg = ChaosSpellAwakeningConfig
local rcfg = ChaosSpellRanksConfig
local OPCODE = (ChaosOpcodes and ChaosOpcodes.spellRanks) or rcfg.opcode
local floor, max, min = math.floor, math.max, math.min

AW.marks = {} -- creature id -> {owner, untilMs, pct}
AW.windows = {} -- player id -> list of {spellId, untilMs, cut, cap, used}
AW.rings = {} -- player id -> pulses and ring runs going now (cap)

local function nowMs()
	return os.mtime and os.mtime() or os.time() * 1000
end

local function log(text)
	print("[Chaos spell awakening] " .. text)
end

local function try(label, fn, ...)
	local ok, a, b = pcall(fn, ...)
	if not ok then
		log(label .. ": " .. tostring(a))
		return nil
	end
	return a, b
end

local function say(player, text)
	if player and player.sendTextMessage then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE or MESSAGE_STATUS_DEFAULT or MESSAGE_INFO_DESCR, text)
	end
end

local function tr(player, fmt, ...)
	if Chaos.t then
		return Chaos.t(player, fmt, ...)
	end
	return string.format(fmt, ...)
end

local function isTester(player)
	return Chaos.isTester and Chaos.isTester(player) == true
end

-- ---------------------------------------------------------------- the Seals
local SEAL_KEY = {waystone = "sealWaystone", rift = "sealRift", pinnacle = "sealPinnacle"}
local SEAL_NAME = {waystone = "Waystone Seal", rift = "Rift Seal", pinnacle = "Pinnacle Seal"}
AW.sealName = SEAL_NAME

-- the state the client shows: the Seals, the slots with the spell in each, what each slot costs
function AW.payload(player)
	local s = AW.seals(player)
	local slots = AW.slots(player)
	local costs = {}
	for i = 1, cfg.maxSlots do
		local c = cfg.slots[i]
		costs[i] = {c.waystone, c.rift, c.pinnacle}
	end
	return {v = 1, on = AW.on(), seals = {s.waystone, s.rift, s.pinnacle}, slots = slots, costs = costs, held = A.held(cfg, slots),
		bonus = cfg.bonus}
end

function AW.push(player)
	if Chaos.send then
		Chaos.send(player, OPCODE, "awakened", AW.payload(player))
	end
end

-- add Seals of a source to a character (the hooks call this). Returns the Seals added
function AW.addSeals(player, source, info)
	if not AW.on() or not player or not SEAL_KEY[source] then
		return 0
	end
	if isTester(player) and cfg.testersEarn ~= true then
		return 0
	end
	local n = A.gain(cfg, source, info)
	if n <= 0 then
		return 0
	end
	local key = rcfg.storage[SEAL_KEY[source]]
	local held = AW.seals(player)[source]
	local now = A.add(held, n, cfg.sealCap)
	if now == held then
		return 0
	end
	player:setStorageValue(key, now)
	say(player, tr(player, "%s +%d (%d held).", SEAL_NAME[source], now - held, now))
	try("push", AW.push, player)
	return now - held
end

-- waystone_endgame.lua: the map of `tier` (1-25) is cleared, first = the first clear of that tier for this character
function AW.onWaystoneClear(player, tier, first)
	return AW.addSeals(player, "waystone", {tier = tier, first = first == true})
end

-- rift.lua greaterSettle: a Greater Rift run ended at the shown `tier`; climbed = sealed, the key climbs
function AW.onRiftRun(player, tier, climbed)
	return AW.addSeals(player, "rift", {tier = tier, climbed = climbed == true})
end

-- pinnacle.lua success: the Ascended boss fell, every member of the party gets the Seals
function AW.onPinnacleKill(player)
	return AW.addSeals(player, "pinnacle", {})
end

-- ---------------------------------------------------------------- awaken
local function packedOf(player, spellId)
	return P.unpack(player:getStorageValue(rcfg.storage.rankBase + spellId))
end

local function writeBit(player, spellId, awakened)
	local rank, f1, f2 = packedOf(player, spellId)
	player:setStorageValue(rcfg.storage.rankBase + spellId, P.pack(rank, f1, f2, awakened))
end

local function knows(player, info)
	if not info then
		return false
	end
	if player.hasLearnedSpell then
		return player:hasLearnedSpell(info.name) == true
	end
	return true
end

-- the answer of an awaken request: {ok, why, spell, slot, name, namePt, cost, need}
-- a whole number from a request, nil for anything else (a fuzzed or hostile client: inf, nan, a fraction, a string)
local function wholeNumber(v)
	v = tonumber(v)
	if not v or v ~= v or v == math.huge or v == -math.huge or v ~= floor(v) or v < -1e9 or v > 1e9 then
		return nil
	end
	return v
end

function AW.awaken(player, spellId, slot)
	spellId = wholeNumber(spellId)
	-- a slot that is no whole number is a slot no free one is: refused as `slot`
	local asked = slot ~= nil and (wholeNumber(slot) or -1) or nil
	slot = asked
	if not AW.on() then
		return {ok = false, why = "off", spell = spellId}
	end
	local k = rcfg.storage
	local entry = spellId and AW.entry(spellId)
	local info = spellId and R.catalog and R.catalog[spellId]
	local rank, f1, f2, aw = 0, 0, 0, false
	if spellId and spellId >= 0 and spellId <= k.maxSpellId then
		rank, f1, f2, aw = packedOf(player, spellId)
	end
	local st = {on = true, entry = entry ~= nil and info ~= nil, known = knows(player, info), rank = rank, f1 = f1, f2 = f2, awakened = aw,
		slots = AW.slots(player), seals = AW.seals(player)}
	local d = A.decide(cfg, rcfg.maxRank, st, slot)
	d.spell = spellId
	if not d.ok then
		return d
	end
	-- pay, then write the slot and the bit (a crash between costs Seals, never gives a free awakening)
	local left = A.pay(st.seals, d.cost)
	player:setStorageValue(k.sealWaystone, left.waystone)
	player:setStorageValue(k.sealRift, left.rift)
	player:setStorageValue(k.sealPinnacle, left.pinnacle)
	player:setStorageValue(k.awakenedSlots + d.slot - 1, spellId)
	writeBit(player, spellId, true)
	player:setStorageValue(k.awakened, A.held(cfg, AW.slots(player)))
	d.name, d.namePt = entry.nameEn, entry.namePt
	say(player, tr(player, "%s awakens: %s.", info.name, entry.nameEn))
	pcall(function() player:getPosition():sendMagicEffect(CONST_ME_FIREWORK_YELLOW) end)
	return d
end

-- opcode 168 `awaken` {spell, slot} -> `awaken` {ok, why, ...}, then the new `awakened` state
function AW.receive(player, msg)
	if type(msg) ~= "table" or msg.action ~= "awaken" then
		return false
	end
	if ChaosRateLimit and not ChaosRateLimit.allow(player, "spellawaken", 500) then
		return false
	end
	local data = type(msg.data) == "table" and msg.data or msg
	local res = AW.awaken(player, data.spell, data.slot)
	Chaos.send(player, OPCODE, "awaken", res)
	if res.ok then
		AW.push(player)
	end
	return true
end

-- login: the slots match the bits, a dormant spell (the character does not know it any more) gives its slot back. Returns the number freed
function AW.sync(player)
	if not AW.on() then
		return 0
	end
	local k = rcfg.storage
	local slots = AW.slots(player)
	local freed = 0
	local known = {}
	for i, id in ipairs(slots) do
		if id > 0 then
			local info = R.catalog and R.catalog[id]
			local _, _, _, aw = packedOf(player, id)
			if not info or not aw then
				-- a slot with no awakened bit (a reset, a reassigned id): free
				player:setStorageValue(k.awakenedSlots + i - 1, 0)
				slots[i] = 0
				freed = freed + 1
			else
				known[id] = knows(player, info)
			end
		end
	end
	for _, d in ipairs(A.dormantSlots(cfg, slots, known)) do
		writeBit(player, d.spell, false)
		player:setStorageValue(k.awakenedSlots + d.slot - 1, 0)
		slots[d.slot] = 0
		freed = freed + 1
	end
	if freed > 0 or (tonumber(player:getStorageValue(k.awakened)) or 0) ~= A.held(cfg, slots) then
		player:setStorageValue(k.awakened, A.held(cfg, slots))
	end
	return freed
end

-- ---------------------------------------------------------------- the bonus and the mark (ChaosPassiveDealt)
-- the factor of one hit of a player: 1 + the bonus when the spell that made it is awakened, and a mark on the target spent by a single target
-- spell. 1 while off, outside a spell's cast context and for anything but a spell hit
function AW.hitFactor(attacker, creature, origin, primaryType, secondaryType)
	if origin ~= ORIGIN_SPELL or not AW.on() or not attacker or not attacker.isPlayer or not attacker:isPlayer() then
		return 1
	end
	local spellId = R.castSpell(attacker)
	if not spellId then
		return 1
	end
	local heal = primaryType == COMBAT_HEALING or secondaryType == COMBAT_HEALING
	local pvp = (not heal) and creature and creature ~= attacker and creature.isPlayer and creature:isPlayer() == true
	local f = 1
	if not heal and not pvp and creature and creature.getId then
		local m = AW.marks[creature:getId()]
		if m and m.owner == attacker:getId() then
			local e = AW.entry(spellId)
			local mf, spent = A.markFactor(m, nowMs(), e ~= nil and e.shape == "single")
			if spent then
				AW.marks[creature:getId()] = nil
			end
			f = f * mf
		end
	end
	if AW.isAwakened(attacker, spellId) then
		f = f * A.factor(cfg, pvp, rcfg.pvp.rank)
	end
	return f
end

-- ---------------------------------------------------------------- the signature
local function copyPos(p)
	return {x = p.x, y = p.y, z = p.z}
end

local function fx(pos, element, role)
	local F = rawget(_G, "ChaosSpellForms")
	if F and F.sendFx and pos then
		F.sendFx(pos.sendMagicEffect and pos or Position(pos.x, pos.y, pos.z), element, role)
	end
end

local function ringStart(pid)
	if (AW.rings[pid] or 0) >= cfg.signature.maxRings then
		return false
	end
	AW.rings[pid] = (AW.rings[pid] or 0) + 1
	return true
end

local function ringEnd(pid)
	AW.rings[pid] = max(0, (AW.rings[pid] or 1) - 1)
end

-- one pulse of a ring (a ground ring that stays): enemies (or allies, for a heal) near the centre, then the next pulse
local function pulse(pid, serial, spellId, a, el, ctype, left)
	local p = Player(pid)
	local F = rawget(_G, "ChaosSpellForms")
	if not p or not F or not F.ops or left <= 0 then
		ringEnd(pid)
		return
	end
	local ops = F.ops
	try("pulse", ops.withContext, p, serial, spellId, function()
		fx(a.pos, el, "ground")
		local n = 0
		if a.heal then
			for _, al in ipairs(ops.alliesNear(p, a.pos, a.radius)) do
				local c = Creature(al.id)
				if c and n < cfg.signature.maxTargets then
					ops.dealHeal(p, c, a.amount)
					n = n + 1
				end
			end
		else
			for _, f in ipairs(ops.foesNear(p, a.pos, a.radius, false)) do
				if n < cfg.signature.maxTargets then
					ops.dealHit(p, f.creature, ctype, a.amount, nil, el)
					n = n + 1
				end
			end
			if (a.mana or 0) > 0 and n >= (a.minHit or 1) and p.addMana and p.getMaxMana then
				p:addMana(floor(p:getMaxMana() * a.mana))
			end
		end
	end)
	if left > 1 then
		addEvent(pulse, a.everyMs, pid, serial, spellId, a, el, ctype, left - 1)
	else
		ringEnd(pid)
	end
end

local function ringHit(pid, serial, spellId, a, el, ctype, left)
	local p = Player(pid)
	local F = rawget(_G, "ChaosSpellForms")
	if not p or not F or not F.ops then
		ringEnd(pid)
		return
	end
	local ops = F.ops
	try("rings", ops.withContext, p, serial, spellId, function()
		fx(a.pos, el, "burst")
		local n = 0
		for _, f in ipairs(ops.foesNear(p, a.pos, a.radius, false)) do
			if n < cfg.signature.maxTargets then
				ops.dealHit(p, f.creature, ctype, a.amount, nil, el)
				n = n + 1
			end
		end
	end)
	if left > 1 then
		addEvent(ringHit, a.stepMs, pid, serial, spellId, a, el, ctype, left - 1)
	else
		ringEnd(pid)
	end
end

local function echo(pid, serial, spellId, a, el, ctype)
	local p = Player(pid)
	local F = rawget(_G, "ChaosSpellForms")
	if not p or not F or not F.ops then
		return
	end
	local ops = F.ops
	try("echo", ops.withContext, p, serial, spellId, function()
		for i, h in ipairs(a.hits) do
			local c = Creature(h.id)
			if c and c:getHealth() > 0 then
				if a.heal then
					ops.dealHeal(p, c, h.amount)
				else
					ops.dealHit(p, c, ctype, h.amount, i == 1 and "burst" or nil, el)
				end
			end
		end
	end)
end

-- run one planned action. info: {element, ctype}
function AW.run(player, spec, a, info, serial, spellId)
	local F = rawget(_G, "ChaosSpellForms")
	local ops = F and F.ops
	if not ops then
		return
	end
	local pid = player:getId()
	local el = spec.element or info.element or "physical"
	local ctype = info.ctype or (rawget(_G, "COMBAT_PHYSICALDAMAGE"))
	if a.op == "pulse" then
		if a.pos and ringStart(pid) then
			addEvent(pulse, a.everyMs, pid, serial, spellId, a, el, ctype, a.pulses)
		end
	elseif a.op == "rings" then
		if a.pos and ringStart(pid) then
			ringHit(pid, serial, spellId, a, el, ctype, a.rings)
		end
	elseif a.op == "line" then
		for _, t in ipairs(a.targets) do
			local c = Creature(t.id)
			if c and c:getHealth() > 0 then
				ops.dealHit(player, c, ctype, a.amount, "hit", el)
			end
		end
	elseif a.op == "mark" then
		local until_ = nowMs() + a.secs * 1000
		for i, id in ipairs(a.ids) do
			AW.marks[id] = {owner = pid, untilMs = until_, pct = a.pct}
			local c = Creature(id)
			if c and i == 1 then
				fx(c:getPosition(), el, "status")
			end
		end
	elseif a.op == "echo" then
		addEvent(echo, a.delay, pid, serial, spellId, a, el, ctype)
	elseif a.op == "shield" then
		for i, t in ipairs(a.targets) do
			local c = Creature(t.id)
			if c and c:getHealth() > 0 then
				local amount = t.amount or floor(c:getMaxHealth() * (t.pct or 0))
				if amount > 0 then
					ops.addShield(c, amount, a.secs)
					if i == 1 then
						fx(c:getPosition(), el, "status")
					end
				end
			end
		end
	elseif a.op == "cdcut" then
		local list = AW.windows[pid] or {}
		AW.windows[pid] = list
		for i = #list, 1, -1 do
			if list[i].spellId == a.spellId then
				table.remove(list, i)
			end
		end
		list[#list + 1] = {spellId = a.spellId, untilMs = nowMs() + a.window * 1000, cut = a.cut, cap = a.cap, used = 0}
	elseif a.op == "leech" then
		ops.dealHeal(player, player, a.amount)
	elseif a.op == "reflect" then
		for i, t in ipairs(a.targets) do
			local c = Creature(t.id)
			if c and c:getHealth() > 0 then
				ops.dealHeal(player, c, a.amount)
				if i == 1 then
					fx(c:getPosition(), el, "hit")
				end
			end
		end
	end
end

-- the end of a cast of the Forms (spell_forms.lua flush): the signature of an awakened spell.
-- b: the hit buffer {spellId, serial, hits}; info: {heal, pvp, hits = {{id, pos, amount, maxHealth}}, element, ctype, mainId, mainPos, allies}
function AW.onCast(player, b, info)
	if not AW.on() or not b or not b.spellId or not AW.isAwakened(player, b.spellId) then
		return
	end
	if info.pvp and rcfg.pvp.awakening ~= true then
		return
	end
	local spec = AW.entry(b.spellId)
	local F = rawget(_G, "ChaosSpellForms")
	local ops = F and F.ops
	if not spec or not ops or #info.hits == 0 then
		return
	end
	local total = 0
	local hits = {}
	for _, h in ipairs(info.hits) do
		total = total + h.amount
		hits[#hits + 1] = {id = h.id, pos = h.pos, amount = h.amount, maxHealth = h.maxHealth}
	end
	local casterPos = copyPos(player:getPosition())
	local cast = {heal = spec.heal, pvp = false, spellId = b.spellId, base = total / #hits, total = total,
		main = {id = info.mainId, pos = info.mainPos}, caster = {id = player:getId(), pos = casterPos}, hits = hits, foes = {}, lineFoes = {},
		allies = {}, healed = hits}
	if spec.heal then
		local healed = {}
		for _, h in ipairs(hits) do
			healed[h.id] = true
		end
		local radius = A.allyRadius(spec)
		if radius > 0 then
			for _, al in ipairs(ops.alliesNear(player, info.mainPos, radius)) do
				if not healed[al.id] then
					cast.allies[#cast.allies + 1] = {id = al.id, pos = al.pos, maxHealth = al.maxHealth}
				end
			end
		end
	else
		cast.foes = ops.foesNear(player, info.mainPos, cfg.signature.ringRadius, false)
		local len = A.lineLength(spec)
		if len > 0 then
			cast.lineFoes = A.lineFoes(casterPos, info.mainPos, len, ops.foesNear(player, casterPos, len, false), info.mainId)
		end
	end
	local plan = A.plan(spec, cast, cfg)
	if #plan.actions == 0 then
		return
	end
	local ctx = {element = info.element, ctype = info.ctype}
	try("signature", ops.withContext, player, b.serial, b.spellId, function()
		for _, a in ipairs(plan.actions) do
			try("action " .. tostring(a.op), AW.run, player, spec, a, ctx, b.serial, b.spellId)
		end
	end)
end

-- ---------------------------------------------------------------- the cooldown cut (a kill inside the window)
-- seconds of the spell's cooldown cut now for a kill of `player`; returns the seconds cut in all
function AW.onKill(player)
	local list = AW.windows[player:getId()]
	if not list then
		return 0
	end
	local t = nowMs()
	local F = rawget(_G, "ChaosSpellForms")
	local total = 0
	for i = #list, 1, -1 do
		local w = list[i]
		if w.untilMs < t then
			table.remove(list, i)
		else
			local take, used = A.cut(w.cut, w.cap, w.used)
			w.used = used
			local info = R.catalog and R.catalog[w.spellId]
			if take > 0 and info and info.cooldownMs > 0 and F and F.shortenCooldown then
				F.shortenCooldown(player, w.spellId, take * 1000 * 100 / info.cooldownMs)
				total = total + take
			end
		end
	end
	return total
end

-- ---------------------------------------------------------------- events
local killEvent = CreatureEvent("ChaosSpellAwakeningKill")
function killEvent.onKill(creature, target)
	if AW.on() and creature and creature:isPlayer() and target and target:isMonster() then
		try("kill", AW.onKill, creature)
	end
	return true
end
killEvent:type("kill")
killEvent:register()

local login = CreatureEvent("ChaosSpellAwakeningLogin")
function login.onLogin(player)
	player:registerEvent("ChaosSpellAwakeningLogout")
	player:registerEvent("ChaosSpellAwakeningKill")
	try("sync", AW.sync, player)
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosSpellAwakeningLogout")
function logout.onLogout(player)
	local id = player:getId()
	AW.windows[id], AW.rings[id] = nil, nil
	for cid, m in pairs(AW.marks) do
		if m.owner == id then
			AW.marks[cid] = nil
		end
	end
	return true
end
logout:type("logout")
logout:register()

-- a monster that dies keeps no mark
local marksTick = GlobalEvent("ChaosSpellAwakeningMarks")
function marksTick.onThink(interval)
	local t = nowMs()
	for cid, m in pairs(AW.marks) do
		if m.untilMs < t then
			AW.marks[cid] = nil
		end
	end
	return true
end
marksTick:interval(30000)
marksTick:register()

-- staff: /spellseal <waystone> <rift> <pinnacle>   sets the Seals of yourself (the live pass, phase 8); /spellseal clear sets them to 0
local talk = TalkAction("/spellseal")
function talk.onSay(player, words, param)
	if not player:getGroup():getAccess() then
		return true
	end
	if Chaos.staffCommand and not Chaos.staffCommand(player, words, param, true) then
		return false
	end
	local k = rcfg.storage
	local a, b, c = tostring(param or ""):match("^%s*(%S+)%s*(%S*)%s*(%S*)")
	if a == "clear" then
		a, b, c = 0, 0, 0
	end
	a, b, c = tonumber(a), tonumber(b), tonumber(c)
	if not a or not b or not c then
		say(player, "Usage: /spellseal <waystone> <rift> <pinnacle> | clear")
		return false
	end
	player:setStorageValue(k.sealWaystone, A.add(0, a, cfg.sealCap))
	player:setStorageValue(k.sealRift, A.add(0, b, cfg.sealCap))
	player:setStorageValue(k.sealPinnacle, A.add(0, c, cfg.sealCap))
	AW.push(player)
	say(player, string.format("Seals: waystone %d, rift %d, pinnacle %d.", a, b, c))
	return false
end
talk:separator(" ")
talk:register()

return AW
