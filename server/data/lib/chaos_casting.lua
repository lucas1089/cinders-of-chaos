-- ChaosCasting: cast times for spell scripts (Lua only, no engine change). Overview: server/README.md "Cast-time spells".
--
-- A spell script builds its onCastSpell with ChaosCasting.spell(spec):
--   spec.name      the name on the cast bar
--   spec.spellId   the spells.xml id (its cooldown condition is what a refund gives back)
--   spec.ms        cast time in ms
--   spec.prepare   fn(player, variant) -> ctx | nil, cancelText   checks at the start (nil: refused, nothing is spent)
--   spec.check     fn(player, ctx) -> true | false, text            checks again when the time is up (target, range, sight)
--   spec.fire      fn(player, ctx) -> false when nothing happened     the effect
--   spec.fx        {name, fallback} effect on the caster at the start and every second (optional)
-- On the cast the script returns true at once, so the engine takes the mana and sets the cooldowns as for any spell (and
-- the spell supports / item modifiers see a normal cast). The cost the engine took is stored: from the Player:onSpellCast
-- event of engine patch 0008 (ChaosSpellEvents "cast": exact mana and health), else the mana that went down by the
-- second dispatcher tick. The cast is polled every cfg.pollMs; it is interrupted, and the stored cost given back
-- (mana, health and the spell's own cooldown; the group cooldown stays), when the caster moves, gets a new paralysis,
-- dies, logs out, casts another spell of the cast's group (attack: a heal, a healing rune or a support spell goes
-- through without touching it, server/README.md "Cooldown channels"), opens a town portal or cancels (client), or when
-- spec.check / spec.fire fail at the end. Everything runs on the server: the client only draws the bar (extended opcode ChaosOpcodes.castbar,
-- client game_castbar) and can ask to cancel. A cast is refunded at most once (cast.refunded).
-- Pure parts (C.step, C.refundOnce) are tested in tests/casting_test.lua with a mocked engine. Lua 5.1 / 5.3.

-- the text in the player's language (Chaos.t, i18n_core.lua); English where the helper is not loaded (unit tests)
local function tr(player, key, ...)
	if Chaos and Chaos.t then
		return Chaos.t(player, key, ...)
	end
	if select("#", ...) > 0 then
		return string.format(key, ...)
	end
	return key
end
ChaosCasting = ChaosCasting or {}
local C = ChaosCasting

C.cfg = C.cfg or {
	pollMs = 100, -- how often a cast checks position, paralysis and time
	fxEveryMs = 1000, -- the cast effect on the caster
	interruptOnParalyze = true, -- a paralysis that starts during the cast interrupts it (one already there does not)
	cooldownAfterRefundMs = 100, -- a refunded cooldown is replaced by this one, so the client's icon is told it ended
	minMs = 200, maxMs = 5000, -- sane cast times
	castGroup = 1, -- the group of a cast-time spell without spec.group (SPELLGROUP_ATTACK: all of them)
}
C.active = C.active or {} -- player id -> cast
C.serial = C.serial or 0
C.stats = C.stats or {started = 0, done = 0, interrupted = 0, refunds = 0}

C.TEXTS = {
	moved = "You moved: the spell is interrupted.",
	paralysed = "You were paralysed: the spell is interrupted.",
	died = nil,
	logout = nil,
	spell = "You cast another spell: the first one is interrupted.",
	portal = "You opened a town portal: the spell is interrupted.",
	cancel = "Spell cancelled.",
	failed = "The spell fails.",
}

local function nowMs()
	return os.mtime and os.mtime() or os.time() * 1000
end
C.nowMs = nowMs

local function opcode()
	return (ChaosOpcodes and ChaosOpcodes.castbar) or 231
end

local function send(player, action, data)
	if not player then
		return
	end
	if Chaos and Chaos.send then
		Chaos.send(player, opcode(), action, data)
	elseif json and player.sendExtendedOpcode then
		player:sendExtendedOpcode(opcode(), json.encode({action = action, data = data}))
	end
end
C.send = send

local function effect(pos, fx)
	if not fx or not pos then
		return
	end
	local id = Fx and Fx(fx[1], fx[2]) or fx[2]
	if id then
		pcall(function() Position(pos):sendMagicEffect(id) end)
	end
end

-- ---------------------------------------------------------------- pure parts
-- what the cast does now: "wait" | "done" | "moved" | "paralysed" | "died"
function C.step(cast, now, pos, paralysed, health)
	if (health or 1) <= 0 then
		return "died"
	end
	local p = cast.pos
	if not pos or pos.x ~= p.x or pos.y ~= p.y or pos.z ~= p.z then
		return "moved"
	end
	if paralysed and not cast.paralysedAtStart and C.cfg.interruptOnParalyze then
		return "paralysed"
	end
	if now >= cast.endMs then
		return "done"
	end
	return "wait"
end

function C.clampMs(ms)
	ms = math.floor(tonumber(ms) or 0)
	return math.max(C.cfg.minMs, math.min(C.cfg.maxMs, ms))
end

-- the refund of one cast, at most once: returns {mana, health, cooldown = bool} or nil (already refunded / cost unknown
-- yet: then it is given when the cost becomes known, see C.recordCost)
function C.refundOnce(cast)
	if cast.refunded then
		return nil
	end
	cast.refunded = true
	if not cast.cost then
		cast.refundWhenKnown = true
		return {mana = 0, health = 0, cooldown = true}
	end
	return {mana = cast.cost.mana or 0, health = cast.cost.health or 0, cooldown = true}
end

-- ---------------------------------------------------------------- engine side
local function isParalysed(player)
	local ok, c = pcall(function() return player:getCondition(CONDITION_PARALYZE) end)
	return ok and c ~= nil
end

-- the mana / health a refund gives: at most up to the maximum, and nothing to a dead player (the engine fills both to
-- the new maximum after the level loss; a refund in the death event only made the stats it sends after the loss show
-- more mana than the new maximum)
function C.refundAmounts(r, mana, maxMana, health, maxHealth)
	if (health or 0) <= 0 then
		return 0, 0
	end
	local m = math.max(0, math.min(r.mana or 0, (maxMana or 0) - (mana or 0)))
	local h = math.max(0, math.min(r.health or 0, (maxHealth or 0) - health))
	return m, h
end

local function giveBack(player, cast, r, withCooldown)
	if not player or not r then
		return
	end
	local mana, health = C.refundAmounts(r, player:getMana(), player:getMaxMana(), player:getHealth(), player:getMaxHealth())
	if mana > 0 then
		player:addMana(mana)
	end
	if health > 0 then
		player:addHealth(health)
	end
	if withCooldown and cast.spellId and CONDITION_SPELLCOOLDOWN then
		local c = player:getCondition(CONDITION_SPELLCOOLDOWN, CONDITIONID_DEFAULT, cast.spellId)
		if c then
			player:removeCondition(CONDITION_SPELLCOOLDOWN, CONDITIONID_DEFAULT, cast.spellId, true)
			local ms = C.cfg.cooldownAfterRefundMs
			if ms and ms > 0 then
				local n = Condition(CONDITION_SPELLCOOLDOWN, CONDITIONID_DEFAULT)
				n:setParameter(CONDITION_PARAM_SUBID, cast.spellId)
				n:setParameter(CONDITION_PARAM_TICKS, ms)
				player:addCondition(n)
			end
		end
	end
	C.stats.refunds = C.stats.refunds + 1
end

local function refund(player, cast)
	local r = C.refundOnce(cast)
	if r then
		giveBack(player, cast, r, true)
	end
end

-- the engine's cost of this cast is known (event or measurement); a refund asked before that is paid now
function C.recordCost(player, cast, mana, health)
	if cast.cost then
		return false
	end
	cast.cost = {mana = math.max(0, math.floor(tonumber(mana) or 0)), health = math.max(0, math.floor(tonumber(health) or 0))}
	if cast.refundWhenKnown then
		cast.refundWhenKnown = nil
		giveBack(player, cast, {mana = cast.cost.mana, health = cast.cost.health}, false)
	end
	return true
end

local function spectators(player, pos)
	local ok, list = pcall(Game.getSpectators, Position(pos), false, true)
	if not ok or type(list) ~= "table" then
		return {}
	end
	local out = {}
	for _, s in ipairs(list) do
		if s ~= player then
			out[#out + 1] = s
		end
	end
	return out
end

-- end a cast: result "done" or a reason; a reason refunds
local function finish(player, cast, result, text)
	if C.active[cast.pid] == cast then
		C.active[cast.pid] = nil
	end
	if result ~= "done" then
		C.stats.interrupted = C.stats.interrupted + 1
		refund(player, cast)
	else
		C.stats.done = C.stats.done + 1
	end
	if player then
		send(player, "end", {s = cast.serial, r = result, t = text})
		if text then
			player:sendCancelMessage(text)
		end
		if result ~= "done" then
			effect(cast.pos, {"poff", CONST_ME_POFF})
		end
		for _, s in ipairs(spectators(player, cast.pos)) do
			send(s, "otherEnd", {c = cast.pid, r = result})
		end
	end
end

-- Cooldown channels (server/README.md): another spell interrupts a cast only when it is of the cast's own group (an
-- attack spell or rune during an attack cast). A heal, a healing rune or a support spell is another channel and never
-- cuts it off. An unknown group (an event without one) interrupts, as before.
function C.interrupts(cast, group)
	group = tonumber(group)
	if not group or group == 0 then
		return true
	end
	return group == (cast.group or C.cfg.castGroup)
end

-- interrupt the player's cast, if any (reason: see C.TEXTS). Returns true when there was one.
function C.interrupt(player, reason, text)
	if not player then
		return false
	end
	local cast = C.active[player:getId()]
	if not cast then
		return false
	end
	finish(player, cast, reason, text or C.TEXTS[reason])
	return true
end

function C.isCasting(player)
	return player ~= nil and C.active[player:getId()] ~= nil
end

local function complete(player, cast)
	C.active[cast.pid] = nil
	local spec = cast.spec
	if spec.check then
		local ok, res, text = pcall(spec.check, player, cast.ctx)
		if not ok then
			print("[ChaosCasting] " .. tostring(spec.name) .. " check: " .. tostring(res))
			return finish(player, cast, "failed", C.TEXTS.failed)
		end
		if res ~= true then
			return finish(player, cast, "failed", text or C.TEXTS.failed)
		end
	end
	local ok, res = pcall(spec.fire, player, cast.ctx)
	if not ok then
		-- part of the effect may have happened: no refund
		print("[ChaosCasting] " .. tostring(spec.name) .. " fire: " .. tostring(res))
		return finish(player, cast, "done")
	end
	if res == false then
		return finish(player, cast, "failed", C.TEXTS.failed)
	end
	finish(player, cast, "done")
end

local poll
poll = function(pid, serial)
	local cast = C.active[pid]
	if not cast or cast.serial ~= serial then
		return
	end
	local player = Player(pid)
	if not player then
		C.active[pid] = nil -- gone without a logout event: nothing to refund to
		return
	end
	local now = nowMs()
	local step = C.step(cast, now, player:getPosition(), isParalysed(player), player:getHealth())
	if step == "wait" then
		if now - (cast.fxAt or 0) >= C.cfg.fxEveryMs then
			cast.fxAt = now
			effect(cast.pos, cast.spec.fx)
		end
		addEvent(poll, math.max(20, math.min(C.cfg.pollMs, cast.endMs - now)), pid, serial)
		return
	end
	if step == "done" then
		return complete(player, cast)
	end
	finish(player, cast, step, C.TEXTS[step])
end

-- fallback cost measurement (no spell events): two ticks later the engine has taken the mana and the spell supports
-- have given their Thrift share back
local function measure(pid, serial, round)
	local cast = C.waiting and C.waiting[serial] -- still there after an interrupt: its refund may wait for the cost
	if not cast or cast.cost then
		if C.waiting then
			C.waiting[serial] = nil
		end
		return
	end
	if round < 2 then
		return addEvent(measure, 0, pid, serial, round + 1)
	end
	C.waiting[serial] = nil
	local player = Player(pid)
	if player then
		C.recordCost(player, cast, cast.manaBefore - player:getMana(), 0)
	end
end

-- start a cast (called from the spell's onCastSpell). Returns what onCastSpell returns.
function C.begin(player, spec, ctx)
	local pid = player:getId()
	if ChaosTownPortal and ChaosTownPortal.casts and ChaosTownPortal.casts[pid] then
		player:sendCancelMessage(tr(player, "You are opening a town portal."))
		return false
	end
	if C.active[pid] then
		C.interrupt(player, "spell")
	end
	C.serial = C.serial + 1
	local now = nowMs()
	local pos = player:getPosition()
	local ms = C.clampMs(spec.ms)
	local cast = {
		pid = pid, serial = C.serial, spec = spec, ctx = ctx, spellId = spec.spellId, group = spec.group,
		startMs = now, endMs = now + ms, pos = {x = pos.x, y = pos.y, z = pos.z},
		paralysedAtStart = isParalysed(player), manaBefore = player:getMana(), fxAt = now,
	}
	C.active[pid] = cast
	C.waiting = C.waiting or {}
	C.waiting[cast.serial] = cast
	C.stats.started = C.stats.started + 1
	effect(cast.pos, spec.fx)
	send(player, "start", {s = cast.serial, n = spec.name, ms = ms, id = spec.spellId})
	for _, s in ipairs(spectators(player, cast.pos)) do
		send(s, "other", {c = pid, n = spec.name, ms = ms})
	end
	addEvent(measure, 0, pid, cast.serial, 1)
	addEvent(poll, math.min(C.cfg.pollMs, ms), pid, cast.serial)
	return true
end

-- the onCastSpell of a cast-time spell
function C.spell(spec)
	assert(type(spec.fire) == "function", "ChaosCasting.spell: fire missing")
	return function(creature, variant, isHotkey)
		local player = creature and creature.getPlayer and creature:getPlayer()
		if not player then
			return false
		end
		local ctx, text = {}, nil
		if spec.prepare then
			ctx, text = spec.prepare(player, variant)
			if not ctx then
				if text then
					player:sendCancelMessage(text)
				end
				effect(player:getPosition(), {"poff", CONST_ME_POFF})
				return false
			end
		end
		ctx.variant = ctx.variant or variant
		return C.begin(player, spec, ctx)
	end
end

-- shared check for a targeted cast: the target still there, alive, attackable, on the floor, in range, in sight
function C.targetCheck(player, targetId, range, attack)
	local t = Creature(targetId)
	if not t or t:getHealth() <= 0 then
		return false, "Your target is gone."
	end
	local a, b = player:getPosition(), t:getPosition()
	if a.z ~= b.z or math.max(math.abs(a.x - b.x), math.abs(a.y - b.y)) > (range or 7) then
		return false, "Your target is out of range."
	end
	if Position(a).isSightClear and not Position(a):isSightClear(b, true) then
		return false, "Your target is out of sight."
	end
	if attack and ChaosSpell and ChaosSpell.canAttack and not ChaosSpell.canAttack(player, t) then
		return false, "You may not attack this creature."
	end
	return true, t
end

-- ---------------------------------------------------------------- spell events (engine patch 0008)
if not ChaosSpellEvents or not ChaosSpellEvents.set then
	pcall(dofile, "data/lib/chaos_spell_events.lua")
end
if ChaosSpellEvents and ChaosSpellEvents.set then
	ChaosSpellEvents.set("cast", "casting", function(player, name, id, group, aggressive, mana, health)
		local cast = player and C.active[player:getId()]
		if not cast then
			return
		end
		if cast.spellId == id and not cast.cost then
			C.recordCost(player, cast, mana, health)
			if C.waiting then
				C.waiting[cast.serial] = nil
			end
		elseif cast.spellId ~= id and C.interrupts(cast, group) then
			C.interrupt(player, "spell")
		end
	end)
end

return C
