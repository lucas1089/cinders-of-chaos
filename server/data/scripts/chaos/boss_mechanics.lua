-- Boss mechanics: the engine part. One tested system for every key boss (server/README.md "Boss mechanics"):
--   telegraphed area attacks (a danger mark pulses on every tile of the shape until the hit; the hit lands only on
--   the tiles still marked), adds phases (immune / shield / empower / heal while they live), soft enrage, stacking
--   debuffs, soak circles, channels stopped by killing a totem, room-wide blasts hidden from behind pillars, orange
--   warnings and a cast bar on the monster bar (game_monsterbar, opcode ChaosOpcodes.monsterbar 125, action "mech").
-- The logic (shapes, timing, fairness, the state machine, balance) is boss_mechanics_core.lua; the numbers are
-- boss_mechanics_config.lua. tests/boss_mechanics_test.lua runs both, and this file against a mocked engine.
--
-- Who gets a fight:
--   * ChaosBossMech.attach(monster, key, opts) from the systems that know their arena: worldboss.lua, uber.lua,
--     guildboss.lua, rift.lua (the guardians with the rift's tier, the Omen guardians);
--   * every other monster whose shown name has a profile (the generated areas' bosses, the Hollow Vault, the donor
--     bosses): at its first think after the spawn (EventCallback onSpawn registers a think event; the monster has
--     no id in onSpawn), with a box of `radius` round its spawn as the arena.
-- opts = {tiles = {pos...} (the arena floor) | center + radius, players = function() -> {Player...}, tier, difficulty,
--         solo, size, hit = function(player, share) (the system's own hit, e.g. the Ascended lethal-hit catch),
--         pillars = {pos...} (fixed cover for the line-of-sight blasts), compensate = false (keep the health)}
-- Assumed engine API (TFS 1.4.2): addEvent, Game.createMonster / createItem / getSpectators, Tile:getGround /
-- hasFlag / hasProperty / getTopCreature / getItemById, Creature events think / healthchange / death,
-- EventCallback onSpawn, doTargetCombat, Position:sendMagicEffect, Monster:setMaxHealth / addHealth / say / getTarget.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
dofile("data/scripts/chaos/boss_mechanics_core.lua")
ChaosBossMechConfig = dofile("data/scripts/chaos/boss_mechanics_config.lua")
if not ChaosSpeed then
	pcall(dofile, "data/lib/chaos_speed.lua")
end
if not ChaosBigFx then
	pcall(dofile, "data/lib/chaos_big_fx.lua")
end
if not ChaosPack27Fx then
	pcall(dofile, "data/lib/chaos_pack27_fx.lua")
end

ChaosBossMech = ChaosBossMech or {}
local M = ChaosBossMech
local G = ChaosBossMechCore

M.fights = M.fights or {} -- boss creature id -> fight
M.addOf = M.addOf or {} -- add / totem id -> boss id

local function C()
	return ChaosBossMechConfig
end

local function mnow()
	return os.mtime and os.mtime() or os.time() * 1000
end

local function rand(a, b)
	return math.random(a, b)
end

local function P(t)
	return Position(t.x, t.y, t.z)
end

local function log(text)
	print("[Chaos boss mechanics] " .. text)
end

local function orange()
	return MESSAGE_STATUS_CONSOLE_ORANGE or MESSAGE_EVENT_ADVANCE or MESSAGE_INFO_DESCR
end

-- an effect by name (chaos_vfx, pack and big ids), else the stock constant named `fallback`
local function fx(pos, name, fallback)
	if not pos then
		return
	end
	if name and ChaosBigFx and ChaosBigFx.live and ChaosBigFx.live() and name:sub(1, 4) == "big_" then
		if ChaosBigFx.send(pos, name) then
			return
		end
	end
	if name and Vfx and ChaosVfx and ChaosVfx[name] and Vfx(P(pos), name) then
		return
	end
	local stock = type(fallback) == "string" and _G[fallback] or fallback
	if stock then
		P(pos):sendMagicEffect(stock)
	end
end

local COMBAT = {physical = "COMBAT_PHYSICALDAMAGE", death = "COMBAT_DEATHDAMAGE", energy = "COMBAT_ENERGYDAMAGE",
	fire = "COMBAT_FIREDAMAGE", ice = "COMBAT_ICEDAMAGE", earth = "COMBAT_EARTHDAMAGE", holy = "COMBAT_HOLYDAMAGE"}
local function combatOf(element)
	return _G[COMBAT[element or "physical"] or "COMBAT_PHYSICALDAMAGE"] or COMBAT_PHYSICALDAMAGE
end

-- ======================================================================== lookups (also used by uber.lua, guildboss.lua)
function M.profileOf(name)
	if type(name) ~= "string" then
		return nil
	end
	return C().profiles[name:lower()]
end

function M.sizeOf(name)
	local p = M.profileOf(name)
	return p and p.size or 1
end

function M.fairOf(name)
	local base = C().fair
	local p = M.profileOf(name)
	local out = {}
	for k, v in pairs(base) do
		out[k] = v
	end
	for k, v in pairs(p and p.fair or {}) do
		out[k] = v
	end
	return out
end

-- ======================================================================== players, the cast bar, warnings
-- a protection zone is never part of a fight: no marks, no cast bar, no hit there (a display monster in its cell
-- beside the carpet of a hub must not reach the players on it; the engine's own combat skips PZ the same way)
local function inPz(pos)
	local tile = pos and Tile(pos)
	return tile ~= nil and TILESTATE_PROTECTIONZONE ~= nil and tile.hasFlag ~= nil
		and tile:hasFlag(TILESTATE_PROTECTIONZONE) == true
end
M.inPz = inPz

local function fightPlayers(f)
	local list = {}
	if f.opts.players then
		local ok, got = pcall(f.opts.players)
		if ok and type(got) == "table" then
			for _, p in ipairs(got) do
				local pos = p:getPosition()
				if f.grid.set[G.key(pos.x, pos.y)] and pos.z == f.grid.z and not inPz(pos) then
					list[#list + 1] = p
				end
			end
			return list
		end
	end
	local r = f.grid.rect
	local cx, cy = math.floor((r.x1 + r.x2) / 2), math.floor((r.y1 + r.y2) / 2)
	local rx, ry = math.floor((r.x2 - r.x1) / 2) + 1, math.floor((r.y2 - r.y1) / 2) + 1
	for _, c in ipairs(Game.getSpectators(Position(cx, cy, f.grid.z), false, true, rx, rx, ry, ry) or {}) do
		local pos = c:getPosition()
		if c:isPlayer() and f.grid.set[G.key(pos.x, pos.y)] and not inPz(pos) then
			list[#list + 1] = c
		end
	end
	return list
end

local function positions(players)
	local out = {}
	for _, p in ipairs(players) do
		local pp = p:getPosition()
		out[#out + 1] = {x = pp.x, y = pp.y, z = pp.z}
	end
	return out
end

local function sendCast(f, label, ms, kind)
	local payload = G.castPayload(f.id, f.name, label, ms, kind)
	for _, p in ipairs(fightPlayers(f)) do
		pcall(Chaos.send, p, ChaosOpcodes.monsterbar, C().opcodeAction, payload)
	end
end

-- the cast bar of a telegraph a system draws itself (uber.lua, guildboss.lua): the boss's fight, if any
function M.cast(boss, label, ms)
	local f = boss and M.fights[boss:getId()]
	if f then
		local spec = nil
		for _, t in ipairs(f.profile.telegraphs or {}) do
			if t.key == label then
				spec = t
			end
		end
		sendCast(f, spec and spec.label or (label:sub(1, 1):upper() .. label:sub(2)), ms, "telegraph")
	end
end

-- a timed mechanic (channel, soak, blast) is running: uber.lua and guildboss.lua draw no telegraph of their own then,
-- so a blast or a soak never overlaps one
function M.busy(boss)
	local f = boss and M.fights[boss:getId()]
	return f ~= nil and f.st.busyUntil ~= nil and mnow() < f.st.busyUntil
end

-- the boss yells the English line (everyone around hears the same yell); each fighter gets the orange line in their
-- own language (Chaos.t: the config text is the key, server/README.md "Server texts in pt-BR (Chaos.t)"). {spell} in a
-- text is the name of the spell, %s the boss.
local function warn(f, text, spell)
	if not text then
		return
	end
	local name = f.profile.label or f.name
	local function line(p)
		local s = G.warnText(p and Chaos.t(p, text) or text, name)
		if s and spell then
			s = s:gsub("{spell}", function() return spell end)
		end
		return s
	end
	local boss = Monster(f.id)
	if boss then
		boss:say(line(nil), TALKTYPE_MONSTER_YELL)
	end
	for _, p in ipairs(fightPlayers(f)) do
		p:sendTextMessage(orange(), line(p))
	end
end

-- a share of max health to one player: the system's own hit when it gave one, else a combat hit from the boss
local function hit(f, player, share)
	if inPz(player:getPosition()) then
		return
	end
	if f.opts.hit then
		pcall(f.opts.hit, player, share)
		return
	end
	local dmg = math.max(1, math.floor(Chaos.percentBase(player) * share + 0.5))
	local fn = doTargetCombat or doTargetCombatHealth
	f.scripted = true
	if fn then
		pcall(fn, f.id, player, combatOf(f.profile.element), -dmg, -dmg, CONST_ME_NONE, ORIGIN_SPELL)
	end
	f.scripted = false
end

-- ======================================================================== adds and totems
local function liveAdds(f)
	local n = 0
	for id in pairs(f.adds) do
		if Monster(id) then
			n = n + 1
		else
			f.adds[id] = nil
			M.addOf[id] = nil
		end
	end
	return n
end

local function freeTile(f, near, lo, hi)
	for _ = 1, 20 do
		local a = rand(0, 359) * math.pi / 180
		local d = rand(lo, hi)
		local x, y = near.x + math.floor(math.cos(a) * d + 0.5), near.y + math.floor(math.sin(a) * d + 0.5)
		local t = f.grid.set[G.key(x, y)]
		if t then
			local tile = Tile(P(t))
			if tile and not tile:getTopCreature() then
				return P(t)
			end
		end
	end
	return nil
end

local function spawnNamed(f, typeName, shownName, health, near)
	local pos = freeTile(f, near, 3, 5) or freeTile(f, near, 1, 7)
	if not pos then
		return nil
	end
	local create = Chaos.createMonsterNamed or function(t, p, e, fo) return Game.createMonster(t, p, e, fo) end
	local ok, m = pcall(create, typeName, pos, false, true, shownName)
	if not ok or not m then
		return nil
	end
	for _, ev in ipairs({"ChaosTierRollMagic", "ChaosTierRollRare", "ChaosTierRollLegendary", "ChaosTierRollBoss"}) do
		pcall(function() m:unregisterEvent(ev) end)
	end
	if health and health > 0 then
		m:setMaxHealth(health)
		m:addHealth(health)
	end
	M.addOf[m:getId()] = f.id
	fx(pos, C().totemEffect, CONST_ME_TELEPORT)
	return m
end

local function spawnAdds(f, spec)
	local boss = Monster(f.id)
	if not boss then
		return
	end
	local n = G.addsCount(spec, f.st.players)
	local hp = G.addsHealth(spec, f.st.players)
	for _ = 1, n do
		local m = spawnNamed(f, spec.type, spec.name, hp, boss:getPosition())
		if m then
			f.adds[m:getId()] = true
		end
	end
end

-- ======================================================================== telegraphs
local function drawMarks(f, tel, kind)
	local cfg = C()
	local effect = kind == "fill" and cfg.fillEffect or cfg.warnEffect
	for _, t in ipairs(tel.plan.big) do
		fx(t, effect, "CONST_ME_MAGIC_RED")
	end
	for _, t in ipairs(tel.plan.small) do
		P(t):sendMagicEffect(kind == "fill" and CONST_ME_DRAWBLOOD or CONST_ME_MAGIC_RED)
	end
end

local function ctxOf(f, players)
	local boss = Monster(f.id)
	local bp = boss and boss:getPosition()
	local target = boss and boss:getTarget()
	local tp = target and target:getPosition()
	local ppos = positions(players)
	return {grid = f.grid, boss = bp and {x = bp.x, y = bp.y, z = bp.z} or nil, size = f.st.size, z = f.grid.z,
		target = tp and {x = tp.x, y = tp.y, z = tp.z} or ppos[1], players = ppos, rand = rand}
end

local function telegraph(f, spec, warnMs)
	local players = fightPlayers(f)
	if #players == 0 then
		return
	end
	local now = mnow()
	local tel = G.planTelegraph(f.st, spec, ctxOf(f, players), now, warnMs)
	if #tel.tiles == 0 then
		return
	end
	sendCast(f, spec.label, warnMs, "telegraph")
	local id, token = f.id, f.token
	for i, pulse in ipairs(tel.pulses) do
		addEvent(function()
			local fl = M.fights[id]
			if not fl or fl.token ~= token then
				return
			end
			-- a follow circle moves with its target until the lock
			if spec.kind == "follow" and mnow() < tel.lockAt then
				G.refollow(fl.st, tel, ctxOf(fl, fightPlayers(fl)), mnow())
			end
			if i == 1 then
				-- pair 27 (data/lib/chaos_pack27_fx.lua, off): its danger circle, else the large one
				local P27, drawn = ChaosPack27Fx, false
				if P27 and P27.PAIR27_FX and P27.telegraph then
					local ok, sent = pcall(P27.telegraph, tel.tiles)
					drawn = ok and sent == true
				end
				if not drawn and ChaosBigFx and ChaosBigFx.telegraph then
					pcall(ChaosBigFx.telegraph, tel.tiles)
				end
			end
			drawMarks(fl, tel, pulse.kind)
		end, pulse.at)
	end
	addEvent(function()
		local fl = M.fights[id]
		if not fl or fl.token ~= token then
			return
		end
		for i, t in ipairs(tel.tiles) do
			if i % 2 == 1 then
				fx(t, spec.hit, spec.fallback)
			end
		end
		if ChaosBigFx and ChaosBigFx.bossHit then
			pcall(ChaosBigFx.bossHit, tel.tiles, fl.profile.element)
		end
		for _, p in ipairs(fightPlayers(fl)) do
			local pp = p:getPosition()
			if tel.set[G.key(pp.x, pp.y)] then
				hit(fl, p, tel.share)
			end
		end
	end, warnMs)
end

-- ======================================================================== timed mechanics
local function channel(f, spec, warnMs)
	local boss = Monster(f.id)
	if not boss then
		return
	end
	local totem = spawnNamed(f, spec.totemType, spec.totemName, G.totemHealth(spec, f.st.players), boss:getPosition())
	f.channel = {spec = spec, endAt = mnow() + warnMs, totem = totem and totem:getId() or nil}
	sendCast(f, spec.label, warnMs, "channel")
end

local function channelStep(f, now)
	local ch = f.channel
	if not ch then
		return
	end
	local alive = ch.totem and Monster(ch.totem)
	if ch.totem and not alive then
		f.channel = nil
		sendCast(f, ch.spec.label, 0, "interrupted")
		warn(f, "%s's {spell} is interrupted!", ch.spec.label)
		return
	end
	if now < ch.endAt then
		return
	end
	f.channel = nil
	if alive then
		M.addOf[ch.totem] = nil
		alive:remove()
	end
	local boss = Monster(f.id)
	if boss then
		fx(boss:getPosition(), ch.spec.hit, ch.spec.fallback)
		-- status words (data/lib/chaos_status_fx.lua, switch off: nothing more): "OBLIVION!" over the boss
		if not ChaosStatusFx then
			pcall(dofile, "data/lib/chaos_status_fx.lua")
		end
		if ChaosStatusFx then
			ChaosStatusFx.send(boss:getPosition(), "channel_" .. tostring(ch.spec.key), nil, boss:getId())
		end
	end
	for _, p in ipairs(fightPlayers(f)) do
		hit(f, p, ch.spec.share)
	end
end

local function soak(f, spec, warnMs)
	local boss = Monster(f.id)
	if not boss then
		return
	end
	local centre = freeTile(f, boss:getPosition(), 3, 5) or boss:getPosition()
	local c = {x = centre.x, y = centre.y, z = centre.z}
	local tiles = G.shape({kind = "circle", radius = spec.radius or 2, at = "target"}, {grid = f.grid, target = c})
	local set = G.tileSet(tiles)
	sendCast(f, spec.label, warnMs, "soak")
	local id, token = f.id, f.token
	for _, pulse in ipairs(G.pulses(warnMs, C().pulseMs, C().fillMs)) do
		addEvent(function()
			local fl = M.fights[id]
			if not fl or fl.token ~= token then
				return
			end
			for _, t in ipairs(tiles) do
				P(t):sendMagicEffect(CONST_ME_MAGIC_GREEN)
			end
			fx(c, C().soakEffect, "CONST_ME_HOLYAREA")
		end, pulse.at)
	end
	addEvent(function()
		local fl = M.fights[id]
		if not fl or fl.token ~= token then
			return
		end
		local players = fightPlayers(fl)
		local inside = {}
		for _, p in ipairs(players) do
			local pp = p:getPosition()
			if set[G.key(pp.x, pp.y)] then
				inside[#inside + 1] = p
			end
		end
		local each, miss = G.soakShare(spec, #inside)
		fx(c, spec.hit, spec.fallback)
		if #inside > 0 then
			for _, p in ipairs(inside) do
				hit(fl, p, each)
			end
		else
			for _, p in ipairs(players) do
				hit(fl, p, miss)
			end
		end
	end, warnMs)
end

local function los(f, spec, warnMs)
	local boss = Monster(f.id)
	if not boss then
		return
	end
	local bp = boss:getPosition()
	local b = {x = bp.x, y = bp.y, z = bp.z}
	local made = {}
	for _, t in ipairs(G.pillarSpots(f.grid, b, spec.pillars)) do
		local tile = Tile(P(t))
		if tile and not tile:getTopCreature() then
			local item = Game.createItem(C().pillarId, 1, P(t))
			if item then
				made[#made + 1] = t
			end
		end
	end
	local cover = G.tileSet(made)
	for _, t in ipairs(f.opts.pillars or {}) do
		cover[G.key(t.x, t.y)] = true
	end
	sendCast(f, spec.label, warnMs, "los")
	local id, token = f.id, f.token
	addEvent(function()
		local fl = M.fights[id]
		if fl and fl.token == token then
			local boss2 = Monster(id)
			local at = boss2 and boss2:getPosition() or P(b)
			local from = {x = at.x, y = at.y}
			fx(at, spec.hit, spec.fallback)
			for _, p in ipairs(fightPlayers(fl)) do
				local pp = p:getPosition()
				if not G.hidden(from, {x = pp.x, y = pp.y}, cover) then
					hit(fl, p, spec.share)
				end
			end
		end
		for _, t in ipairs(made) do
			local tile = Tile(P(t))
			local item = tile and tile:getItemById(C().pillarId)
			if item then
				item:remove()
			end
		end
	end, warnMs)
end

-- ======================================================================== the fight
local function cleanup(f)
	for id in pairs(f.adds) do
		local m = Monster(id)
		if m then
			m:remove()
		end
		M.addOf[id] = nil
	end
	if f.channel and f.channel.totem then
		local m = Monster(f.channel.totem)
		if m then
			m:remove()
		end
		M.addOf[f.channel.totem] = nil
	end
	M.fights[f.id] = nil
end

local function tick(id, token)
	local f = M.fights[id]
	if not f or f.token ~= token then
		return
	end
	local boss = Monster(id)
	if not boss then
		cleanup(f)
		return
	end
	local now = mnow()
	local live = liveAdds(f)
	local hp = boss:getHealth() / math.max(1, boss:getMaxHealth())
	f.st.players = math.max(1, #fightPlayers(f))
	for _, a in ipairs(G.update(f.st, now, hp, live)) do
		if a.kind == "telegraph" then
			telegraph(f, a.spec, a.warnMs)
		elseif a.kind == "adds" then
			spawnAdds(f, a.spec)
		elseif a.kind == "warn" then
			warn(f, a.text)
		elseif a.kind == "channel" then
			channel(f, a.spec, a.warnMs)
		elseif a.kind == "soak" then
			soak(f, a.spec, a.warnMs)
		elseif a.kind == "los" then
			los(f, a.spec, a.warnMs)
		elseif a.kind == "softEnrage" then
			fx(boss:getPosition(), "big_shock_blood_9", CONST_ME_MAGIC_RED)
		end
	end
	channelStep(f, now)
	local V = ChaosPack29Vfx -- pair 29 (switch off: nothing): the immune and enraged auras on the boss, shown again as
	if V then                -- they end (show is throttled to the aura's length)
		if G.damageTakenMult(f.st, live) == 0 then
			pcall(V.show, boss, "invulnerable")
		end
		if f.st.enraged then
			pcall(V.show, boss, "enraged")
		end
	end
	if now >= (f.nextHeal or 0) then
		f.nextHeal = now + 5000
		local heal = G.addsHeal(f.st, live, boss:getMaxHealth())
		if heal > 0 then
			boss:addHealth(heal)
			fx(boss:getPosition(), "tick_regen", CONST_ME_MAGIC_GREEN)
		end
	end
	for _, p in ipairs(fightPlayers(f)) do
		if not f.watched[p:getId()] then
			f.watched[p:getId()] = true
			p:registerEvent("ChaosBossMechTaken")
		end
	end
	addEvent(tick, C().tickMs, id, token)
end

-- walkable for the box arena of an auto-attached boss; PZ tiles are not part of it
local function walkable(z)
	return function(x, y)
		local tile = Tile(Position(x, y, z))
		return tile ~= nil and tile:getGround() ~= nil and not tile:hasProperty(CONST_PROP_BLOCKSOLID)
			and not inPz(Position(x, y, z))
	end
end

-- a display monster of the hunt teleport room (hunt_teleports.lua): never a fight
local function isDisplaySpot(pos)
	local HT = ChaosHuntTeleports
	return pos ~= nil and HT ~= nil and HT.isDisplaySpot ~= nil and HT.isDisplaySpot(pos) == true
end
M.isDisplaySpot = isDisplaySpot

function M.attach(monster, key, opts)
	local cfg = C()
	if not cfg.enabled or not monster or isDisplaySpot(monster:getPosition()) then
		return nil
	end
	local id = monster:getId()
	if id == 0 or M.fights[id] then
		return M.fights[id]
	end
	local name = monster:getName()
	local profile = cfg.profiles[(key or name):lower()]
	if not profile then
		return nil
	end
	opts = opts or {}
	local grid
	if opts.tiles then
		grid = G.grid(opts.tiles)
	else
		local c = opts.center or monster:getPosition()
		grid = G.boxGrid({x = c.x, y = c.y, z = c.z}, opts.radius or profile.radius or 8, walkable(c.z))
	end
	if #grid.list == 0 then
		return nil
	end
	local tier = opts.tier
	local difficulty = opts.difficulty or ((profile.difficulty or 0.2) + (profile.tierDifficulty or 0) * math.max(0, (tier or 1) - 1))
	local players = 1
	local f = {id = id, name = name, profile = profile, grid = grid, opts = opts, adds = {}, watched = {},
		token = (M.token or 0) + 1}
	M.token = f.token
	M.fights[id] = f
	players = math.max(1, #fightPlayers(f))
	f.st = G.newFight(profile, {now = mnow(), difficulty = difficulty, solo = opts.solo or (profile.ref and profile.ref.solo),
		players = players, size = opts.size, tier = tier})
	if profile.ownTelegraphs then
		f.st.p = setmetatable({telegraphs = {}}, {__index = profile})
	end
	-- keep the kill time: the boss's health x the factor the mechanics' downtime asks for (G.balance)
	if opts.compensate ~= false and profile.ref and profile.compensate ~= false then
		local ref = {}
		for k, v in pairs(profile.ref) do
			ref[k] = v
		end
		ref.tier = tier or ref.tier
		local b = G.balance(profile, ref)
		if b.hpMult < 1 then
			local share = monster:getHealth() / math.max(1, monster:getMaxHealth())
			local hp = math.max(1, math.floor(monster:getMaxHealth() * b.hpMult))
			monster:setMaxHealth(hp)
			monster:addHealth(math.floor(hp * share) - monster:getHealth())
		end
		f.hpMult = b.hpMult
	end
	monster:registerEvent("ChaosBossMechHealth")
	addEvent(tick, cfg.tickMs, id, f.token)
	return f
end

function M.detach(monster)
	local f = monster and M.fights[monster:getId()]
	if f then
		cleanup(f)
	end
end

-- ======================================================================== events
-- the boss takes less (or no) damage while its adds live
local bossHealth = CreatureEvent("ChaosBossMechHealth")
function bossHealth.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	local f = M.fights[creature:getId()]
	if f and primaryType ~= COMBAT_HEALING then
		local m = G.damageTakenMult(f.st, liveAdds(f))
		if m < 1 then
			primaryDamage = math.floor(primaryDamage * m)
			secondaryDamage = math.floor(secondaryDamage * m)
			if m == 0 and mnow() >= (f.nextBlock or 0) then
				f.nextBlock = mnow() + 1000
				creature:getPosition():sendMagicEffect(CONST_ME_BLOCKHIT)
			end
		end
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
bossHealth:register()

-- a player hit by a boss with a fight: the soft enrage, the empower of living adds and the debuff's stacks
local taken = CreatureEvent("ChaosBossMechTaken")
function taken.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	local f = attacker and M.fights[attacker:getId()]
	if not f or f.scripted or primaryType == COMBAT_HEALING or not creature:isPlayer() then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local now = mnow()
	local m = G.damageDealtMult(f.st, now, liveAdds(f))
	local d = f.profile.debuff
	if d then
		local guid = creature:getGuid()
		local e = f.st.stacks[guid]
		local stacks = G.stackDecay(e, d, now)
		m = m * G.stackMult(d, stacks)
		if not e or now - (e.at or 0) >= (d.everyMs or 2000) then
			e = G.stackAdd(e, d, now)
			f.st.stacks[guid] = e
			if e.stacks >= 3 and e.stacks % 3 == 0 then
				creature:sendTextMessage(orange(), Chaos.t(creature, "%s: %d stacks (+%d%% damage taken from %s).", d.label,
					e.stacks, math.floor(d.perStack * e.stacks * 100 + 0.5), f.profile.label or f.name))
			end
		end
	end
	if m ~= 1 then
		primaryDamage = math.floor(primaryDamage * m)
		secondaryDamage = math.floor(secondaryDamage * m)
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
taken:register()

-- auto attach: a monster whose shown name has a profile, at its first think (it has its id then)
local attachEv = CreatureEvent("ChaosBossMechAttach")
function attachEv.onThink(creature, interval)
	creature:unregisterEvent("ChaosBossMechAttach")
	if creature:isMonster() and creature:getId() ~= 0 and not M.fights[creature:getId()] then
		M.attach(creature, nil, {center = creature:getPosition()})
	end
	return true
end
attachEv:register()

local spawnCb = EventCallback
spawnCb.onSpawn = function(self, position, startup, artificial)
	if C().enabled and not self:getMaster() and M.profileOf(self:getName()) and not isDisplaySpot(position) then
		self:registerEvent("ChaosBossMechAttach")
	end
	return true
end
spawnCb:register(10)
