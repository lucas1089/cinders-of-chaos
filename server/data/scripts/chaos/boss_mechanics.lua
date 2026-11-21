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
--         pillars = {pos...} (fixed cover for the line-of-sight blasts), compensate = false (keep the health),
--         healthScale = the fight's health over the monster's current maximum (O698: the factor is worked out for partySize, else size),
--         partySize = the players of the fight (the party the factor is for; `size` is the boss footprint),
--         healScale = the monster's own healing defense x this (O704, the pocket bosses: the file's heal is the event's)}
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
M.hints = M.hints or {} -- O703: boss creature id -> {name, partySize, healthCurve} for the auto attach of its first think (M.hint)
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

-- O614: a boss strike that names the bolt from the sky gets the heavy code-drawn bolt on client pair 73
local function skyHeavy(name)
	if ChaosLightningFx == nil then
		ChaosLightningFx = false
		pcall(dofile, "data/lib/chaos_lightning_fx.lua")
	end
	return ChaosLightningFx and ChaosLightningFx.boss(name) or name
end

-- O637: a telegraph or an adds phase that names a `pose` (a profile row of boss_mechanics_config.lua) plays the boss's attack as an
-- effect that carries its body, so that it ends with the warning: the boss is hidden while it plays (data/lib/chaos_malgrath_fx.lua,
-- client pair 74). Below the pair, or without the lib, nothing happens and the boss stands as it always did.
local function pose(f, spec, warnMs)
	if not (spec and spec.pose) then
		return
	end
	if ChaosMalgrathFx == nil then
		ChaosMalgrathFx = false
		pcall(dofile, "data/lib/chaos_malgrath_fx.lua")
	end
	if ChaosMalgrathFx and ChaosMalgrathFx.live() then
		pcall(ChaosMalgrathFx.pose, f.id, spec.pose, warnMs or 0)
	end
end

-- an effect by name (chaos_vfx, pack and big ids), else the stock constant named `fallback`
local function fx(pos, name, fallback, who)
	if not pos then
		return
	end
	name = skyHeavy(name)
	if who and ChaosTelegraph then
		ChaosTelegraph.effectTo(who, pos, name, fallback) -- one player's sprite marks (O549)
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

-- O703: a system that spawns a boss the auto attach (below) picks up by name tells it the fight's size and the health curve of the party
-- before the first think (the generated dungeons: dungeons.lua scaleMonster), so the health factor is worked out for the real fight
function M.hint(monster, partySize, healthCurve)
	local id = monster and monster:getId() or 0
	if id ~= 0 and not M.fights[id] then
		M.hints[id] = {name = monster:getName(), partySize = partySize, healthCurve = healthCurve}
	end
end

-- ======================================================================== lookups (also used by uber.lua, guildboss.lua)
function M.profileOf(name)
	if type(name) ~= "string" then
		return nil
	end
	return C().profiles[name:lower()]
end

-- O704: the pocket-sized profile of a boss (boss_mechanics_config.lua `pocket`): key, profile; nil when it has none
function M.pocketOf(name)
	if type(name) ~= "string" then
		return nil
	end
	local key = (C().pocket and C().pocket.prefix or "pocket ") .. name:lower()
	local p = C().profiles[key]
	if p and p.pocket then
		return key, p
	end
	return nil
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
	local function lineIn(lang)
		local s = G.warnText(lang and ChaosI18n.text(lang, text) or text, name)
		if s and spell then
			s = s:gsub("{spell}", function() return spell end)
		end
		return s
	end
	local function line(p)
		return lineIn(p and Chaos.lang(p) or nil)
	end
	local boss = Monster(f.id)
	if boss then
		-- the yell reaches everyone around: each listener hears it in own language (Chaos.yell)
		Chaos.yell(boss, lineIn)
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

-- true while the boss's own scripted hit (a share of the player's max health: telegraph, soak, channel, blast) is
-- being dealt. Other systems that scale a monster's damage (dungeons.lua difficulty) leave that hit as it is: it is
-- already a percentage of the victim's health, and a x1.3 to x6 on top made the Last Hymn kill a player who stood in
-- the circle (beta 2026-10-24).
function M.scriptedHit(attacker)
	local f = attacker and M.fights[attacker:getId()]
	return f ~= nil and f.scripted == true
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
		-- O686 phase 3: adds and totems follow the boss's H of the spell ranks (f.level: the level the host plans the fight for; 1 while off)
		health = Chaos.scaleHealth(health, f.level)
		m:setMaxHealth(health)
		Chaos.heal(m, health) -- O682: a one-argument addHealth heals nothing on this engine
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
	pose(f, spec, 0)
	for _ = 1, n do
		local m = spawnNamed(f, spec.type, spec.name, hp, boss:getPosition())
		if m then
			f.adds[m:getId()] = true
		end
	end
end

-- ======================================================================== telegraphs
-- the sprite marks of one pulse. who = nil: everybody near gets them (nobody near has game_telegraph, ChaosTelegraph is
-- not loaded or its switch is off: exactly as before O549); who = a player: only that one (a player without
-- game_telegraph while others near have it)
local function drawMarks(f, tel, kind, who, art)
	local cfg = C()
	local effect = kind == "fill" and cfg.fillEffect or cfg.warnEffect
	if ChaosGapFx then -- O606: the strike circle on client pair 73
		effect = ChaosGapFx.telegraph(effect)
	end
	for _, t in ipairs(tel.plan.big) do
		fx(t, effect, "CONST_ME_MAGIC_RED", who)
	end
	if art then -- a player with game_telegraph: only the strike circle, the floor mark shows the tiles
		return
	end
	for _, t in ipairs(tel.plan.small) do
		local stock = kind == "fill" and CONST_ME_DRAWBLOOD or CONST_ME_MAGIC_RED
		if who then
			P(t):sendMagicEffect(stock, who)
		else
			P(t):sendMagicEffect(stock)
		end
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
	-- O652: the danger the tester bots read (M.dangerFor): the marks as the server sent them, until the hit
	local keep = {}
	for _, e in ipairs(f.danger or {}) do
		if e.hitAt > now - 200 then
			keep[#keep + 1] = e
		end
	end
	keep[#keep + 1] = {tel = tel, hitAt = now + warnMs, label = spec.label}
	f.danger = keep
	sendCast(f, spec.label, warnMs, "telegraph")
	pose(f, spec, warnMs)
	local id, token = f.id, f.token
	-- the floor mark of game_telegraph (O549): the area once now, again when a follow circle moves; the sprite pulses below
	-- go only to the players near it that do not have the module
	local mark
	if ChaosTelegraph then
		f.markSeq = (f.markSeq or 0) + 1
		mark = ChaosTelegraph.open("bm:" .. f.id .. ":" .. f.markSeq, tel.tiles, {ms = warnMs, user = "bossMechanics"})
	end
	local function draw(fn, art)
		if mark and ChaosTelegraph then
			ChaosTelegraph.draw(mark, fn, art)
		else
			fn(nil)
		end
	end
	for i, pulse in ipairs(tel.pulses) do
		addEvent(function()
			local fl = M.fights[id]
			if not fl or fl.token ~= token then
				return
			end
			-- a follow circle moves with its target until the lock
			if spec.kind == "follow" and mnow() < tel.lockAt then
				G.refollow(fl.st, tel, ctxOf(fl, fightPlayers(fl)), mnow())
				if mark and ChaosTelegraph then
					pcall(ChaosTelegraph.move, mark, tel.tiles)
				end
			end
			draw(function(who)
				if i == 1 then
					if who then
						pcall(ChaosTelegraph.circleTo, who, tel.tiles, true)
					else
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
				end
				drawMarks(fl, tel, pulse.kind, who)
			end, function(who)
				drawMarks(fl, tel, pulse.kind, who, true)
			end)
			-- O606 (client pair 73): the marks that had no effect. The follow circle's target is chased, the players
			-- under falling puddles spread, a meteor attack shows its shadows before the hit
			if ChaosGapFx and ChaosGapFx.name("tele_zone") then
				if i == 1 and spec.kind == "follow" then
					local boss = Monster(id)
					local target = boss and boss:getTarget()
					if target then
						ChaosGapFx.on(target, "chase")
					end
				elseif i == 1 and spec.kind == "puddles" and (spec.onPlayers or 0) > 0 then
					for _, p in ipairs(fightPlayers(fl)) do
						ChaosGapFx.on(p, "spread")
					end
				end
				if pulse.kind == "fill" and spec.hit == "meteor_strike" then
					for _, t in ipairs(tel.plan.big) do
						ChaosGapFx.at(t, "meteor_shadow")
					end
				end
			end
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
		-- O683: the tally of what was warned and what was taken (M.tallyFor): one exposure per player a telegraph could have hit
		local tally = fl.tally or {fired = 0, exposed = 0, taken = 0, by = {}}
		fl.tally = tally
		local row = tally.by[spec.label] or {fired = 0, exposed = 0, taken = 0}
		tally.by[spec.label] = row
		tally.fired, row.fired = tally.fired + 1, row.fired + 1
		for _, p in ipairs(fightPlayers(fl)) do
			local pp = p:getPosition()
			tally.exposed, row.exposed = tally.exposed + 1, row.exposed + 1
			if tel.set[G.key(pp.x, pp.y)] then
				tally.taken, row.taken = tally.taken + 1, row.taken + 1
				hit(fl, p, tel.share)
			end
		end
	end, warnMs)
end

-- O683 (the tester bots, pinnacle.lua PN.probe): what the fight's telegraphs did so far: {fired, exposed (players a telegraph could have hit,
-- summed), taken (of those, the ones standing on a marked tile at the hit), by = {label = {fired, exposed, taken}}}; nil without a fight or a hit
function M.tallyFor(bossId)
	local f = M.fights[bossId]
	if not f or not f.tally then
		return nil
	end
	local by = {}
	for label, row in pairs(f.tally.by) do
		by[label] = {fired = row.fired, exposed = row.exposed, taken = row.taken}
	end
	return {fired = f.tally.fired, exposed = f.tally.exposed, taken = f.tally.taken, by = by}
end

-- O684 (a party of bots): five players inside one blob of marks each named "the nearest safe tile", the same tile and the same way, and blocked each
-- other. A bot that asks with its player id (`who`) gets a tile and a way (`route`) that no other asking bot of the fight has taken: the claims of
-- the others (goal, steps) live until the hit, a goal is kept while it stays free, tiles under another player are no goal and no step. When no such
-- tile is in reach in the time left the claims are dropped one by one (the way may cross another's, the goal never is another's), then the plain
-- nearest tile. Only the bots ask this way (the probe passes `who`): a player's own dodge is his own walk, and the fairness step does not use it.
local function routeFor(f, who, grid, marked, pos, budget, straight, diag, now)
	f.claims = f.claims or {}
	local goals, paths, stand, stay = {}, {}, {}, {}
	for pid, c in pairs(f.claims) do
		if c.hitAt <= now - 200 then
			f.claims[pid] = nil
		elseif pid ~= who then
			goals[c.goal] = true
			for k in pairs(c.path) do
				paths[k] = true
			end
		end
	end
	for _, p in ipairs(fightPlayers(f)) do
		if p:getId() ~= who then
			local pp = p:getPosition()
			local k = G.key(pp.x, pp.y)
			stand[k] = true
			if not marked[k] then
				stay[k] = true   -- stands on a safe tile and stays: no goal for another, no step over him
			end
		end
	end
	local mine = f.claims[who]
	local prefer = mine and mine.goal or nil
	local function union(a, b)
		local u = {}
		for k in pairs(a) do
			u[k] = true
		end
		for k in pairs(b) do
			u[k] = true
		end
		return u
	end
	local tiers = {
		{goals = union(goals, stay), path = union(union(paths, stand), goals), prefer = prefer},
		{goals = union(goals, stay), path = stay, prefer = prefer},
	}
	for _, av in ipairs(tiers) do
		local tile, ms, route = G.safeRoute(grid, marked, pos, budget, straight, diag, av)
		if tile then
			return tile, route, av
		end
	end
	return nil
end

-- O652 (the tester bots' probe, testers_boss.lua): what a person sees of a boss's telegraphs now. -> {marked = {["x,y"] = true} (every tile any
-- pending mark covers), left = ms to the first hit, labels = {name...}, goal = the nearest safe tile {x, y, z} of the player when it stands in a
-- mark (G.safeSpot on the fight's own grid, within the time left), count} or nil when the boss has no fight or no mark is up.
-- O684: with `who` (a player id) the goal is one the other asking bots did not take and `route` is the tiles to walk, the goal last.
function M.dangerFor(bossId, pos, who)
	local f = M.fights[bossId]
	if not f or not f.danger then
		return nil
	end
	local now = mnow()
	local live, marked, labels, soonest = {}, {}, {}, nil
	for _, e in ipairs(f.danger) do
		if e.hitAt > now - 200 then
			live[#live + 1] = e
			for k in pairs(e.tel.set) do
				marked[k] = true
			end
			labels[#labels + 1] = e.label
			soonest = soonest and math.min(soonest, e.hitAt) or e.hitAt
		end
	end
	f.danger = live
	if #live == 0 then
		return nil
	end
	local out = {marked = marked, left = math.max(0, soonest - now), labels = labels, count = #live}
	if pos and marked[G.key(pos.x, pos.y)] then
		local straight, diag = G.stepCosts(f.profile.fair or {})
		-- O683: not through or onto the boss (a cone leaves its own tiles unmarked, the nearest "safe" tile of a bot next to him was the boss)
		local boss = Monster(bossId)
		local body = G.bodySet(boss and boss:getPosition() or nil, (f.st and f.st.size) or 1)
		local grid = {set = setmetatable({}, {__index = function(_, k)
			if body[k] then
				return nil
			end
			return f.grid.set[k]
		end})}
		local budget = math.max(300, out.left - 200)
		local tile, route
		if who then
			tile, route = routeFor(f, who, grid, marked, pos, budget, straight, diag, now)
			if tile then
				local path = {}
				for _, t in ipairs(route or {}) do
					path[G.key(t.x, t.y)] = true
				end
				f.claims[who] = {goal = G.key(tile.x, tile.y), path = path, hitAt = soonest}
			end
		end
		if not tile then
			tile = G.safeSpot(grid, marked, pos, budget, straight, diag)
		end
		out.goal = tile and {x = tile.x, y = tile.y, z = tile.z or pos.z} or nil
		if route and #route > 0 then
			out.route = {}
			for _, t in ipairs(route) do
				out.route[#out.route + 1] = {x = t.x, y = t.y, z = t.z or pos.z}
			end
		end
	end
	return out
end

-- O681 (the tester bots, pinnacle.lua PN.probe): the adds and the channel's totem a boss's fight holds now, as a person sees them in the battle
-- list: {monster id, ...} of those still alive (the shield, empower and heal phases of the adds, the totem a channel is stopped by), sorted; nil when
-- the boss has no fight or nothing of that is up. A person breaks them when the boss says so ("Break them!").
function M.addsFor(bossId)
	local f = M.fights[bossId]
	if not f then
		return nil
	end
	local out = {}
	for id in pairs(f.adds or {}) do
		if Monster(id) then
			out[#out + 1] = id
		end
	end
	local tid = f.channel and f.channel.totem
	if tid and Monster(tid) then
		out[#out + 1] = tid
	end
	table.sort(out)
	return #out > 0 and out or nil
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
	-- O606 (client pair 73): the count over the boss as the channel ends, unless it was stopped
	local count = ChaosGapFx and ChaosGapFx.ms("countdown") or 0
	if count > 0 then
		local id, token, ch = f.id, f.token, f.channel
		addEvent(function()
			local fl = M.fights[id]
			local b = fl and fl.token == token and fl.channel == ch and Monster(id)
			if b then
				ChaosGapFx.on(b, "countdown")
			end
		end, math.max(0, warnMs - count))
	end
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
	-- the drawn circle and the check below are this one set
	f.soakCircle = {x = c.x, y = c.y, z = c.z, set = set, tiles = tiles}
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
			if pp.z == c.z and set[G.key(pp.x, pp.y)] then
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
	-- O606 (client pair 73): the cover is marked while the blast charges
	local safe = ChaosGapFx and ChaosGapFx.ms("safe_zone") or 0
	if safe > 0 then
		local spots = {}
		for _, t in ipairs(made) do
			spots[#spots + 1] = t
		end
		for _, t in ipairs(f.opts.pillars or {}) do
			spots[#spots + 1] = {x = t.x, y = t.y, z = t.z or b.z}
		end
		for at = 0, math.max(0, warnMs - safe), safe do
			addEvent(function()
				local fl = M.fights[id]
				if fl and fl.token == token then
					for _, t in ipairs(spots) do
						ChaosGapFx.at(t, "safe_zone")
					end
				end
			end, at)
		end
	end
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
	if ChaosTelegraph then
		pcall(ChaosTelegraph.closePrefix, "bm:" .. f.id .. ":") -- the floor marks of a cancelled hit (O549)
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
			Chaos.heal(boss, heal)
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
	local profile = opts and opts.profile or cfg.profiles[(key or name):lower()]
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
	local f = {id = id, name = name, profile = profile, grid = grid, opts = opts, adds = {}, watched = {}, level = opts and opts.level,
		token = (M.token or 0) + 1, healScale = tonumber(opts.healScale)}
	M.token = f.token
	M.fights[id] = f
	players = math.max(1, #fightPlayers(f))
	f.st = G.newFight(profile, {now = mnow(), difficulty = difficulty, solo = opts.solo or (profile.ref and profile.ref.solo),
		players = players, size = opts.size, tier = tier}) -- size: the boss footprint (profile.size when nil); the party size is opts.partySize (O703)
	if profile.ownTelegraphs then
		f.st.p = setmetatable({telegraphs = {}}, {__index = profile})
	end
	-- keep the kill time: the boss's health x the factor the mechanics' downtime asks for (G.balance)
	if opts.compensate ~= false and profile.ref and profile.compensate ~= false then
		-- O698: a system that gives its fight a party's health (opts.healthScale: the factor on the monster's health at this size,
		-- pinnacle.lua and pocketboss.lua) gets the factor worked out for that size (the adds, the totems and the damage of that
		-- many players), not the profile's own party (the solo one for most): the solo factor cut a party of five's boss by 20% too much
		-- O703: a system whose party health is a curve of the size, not the monster's health at this moment (the generated dungeon
		-- bosses, the guild boss, the Omen guardians), passes opts.partySize and opts.healthCurve(n): the ref's health follows the curve
		local ref
		if opts.healthScale then
			ref = G.refFor(profile.ref, opts.partySize or opts.size or players, monster:getMaxHealth() * opts.healthScale)
		elseif opts.healthCurve then
			ref = G.refForCurve(profile.ref, opts.partySize or players, opts.healthCurve)
		else
			ref = G.refFor(profile.ref)
		end
		ref.tier = tier or ref.tier
		local b = G.balance(profile, ref)
		if b.hpMult < 1 then
			local share = monster:getHealth() / math.max(1, monster:getMaxHealth())
			local hp = math.max(1, math.floor(monster:getMaxHealth() * b.hpMult))
			monster:setMaxHealth(hp)
			monster:setHealth(math.max(1, math.floor(hp * share))) -- O682: the one-argument addHealth did nothing; setHealth clamps to the maximum
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
	-- O704: the boss's own healing defense (the engine's heal, attacker = the boss) x the fight's healScale: a pocket boss heals a share of
	-- the median class's damage, not the event's 1,200-3,200 a second. A heal a script gives (the heal phase's adds) has no attacker: untouched
	if f and f.healScale and primaryType == COMBAT_HEALING and primaryDamage > 0 and attacker and attacker:getId() == creature:getId() then
		primaryDamage = math.max(1, math.floor(primaryDamage * f.healScale))
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
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

-- the multiplier of a boss's hit on a player (the soft enrage, the empower of living adds, the debuff's stacks so far)
-- and the fight; nil when the hit is not one of a fight's
local function playerHitMult(creature, attacker, now)
	local f = attacker and M.fights[attacker:getId()]
	if not f or f.scripted or not creature:isPlayer() then
		return nil
	end
	local m = G.damageDealtMult(f.st, now, liveAdds(f))
	local d = f.profile.debuff
	if d then
		m = m * G.stackMult(d, G.stackDecay(f.st.stacks[creature:getGuid()], d, now))
	end
	return m, f
end

-- the debuff's stack of this hit (at most one per everyMs), with a message every third stack
local function addStack(f, creature, now)
	local d = f.profile.debuff
	if not d then
		return
	end
	local guid = creature:getGuid()
	local e = f.st.stacks[guid]
	if not e or now - (e.at or 0) >= (d.everyMs or 2000) then
		e = G.stackAdd(e, d, now)
		f.st.stacks[guid] = e
		if e.stacks >= 3 and e.stacks % 3 == 0 then
			creature:sendTextMessage(orange(), Chaos.t(creature, "%s: %d stacks (+%d%% damage taken from %s).", d.label,
				e.stacks, math.floor(d.perStack * e.stacks * 100 + 0.5), f.profile.label or f.name))
		end
	end
end

-- a player hit by a boss with a fight: the soft enrage, the empower of living adds and the debuff's stacks. A hit a
-- mana shield took was scaled by the mana event already (manashield.lua): the rest is left as it is.
local taken = CreatureEvent("ChaosBossMechTaken")
function taken.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if primaryType == COMBAT_HEALING then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local now = mnow()
	local m, f = playerHitMult(creature, attacker, now)
	if not m then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	addStack(f, creature, now)
	if m ~= 1 and not (ChaosManaShield and ChaosManaShield.scaled(creature, attacker, "bossmech")) then
		primaryDamage = math.floor(primaryDamage * m)
		secondaryDamage = math.floor(secondaryDamage * m)
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
taken:register()

-- the mana shield part of the hit (manashield.lua): the same multiplier, the stack when the mana took it all
if not ChaosManaShield or not ChaosManaShield.provide then
	dofile("data/scripts/chaos/manashield_core.lua")
end
ChaosManaShield.provide("bossmech", {
	hit = function(player, attacker, amount)
		local m = playerHitMult(player, attacker, mnow())
		return m and math.floor(amount * m) or nil
	end,
	absorbed = function(player, attacker)
		local now = mnow()
		local _, f = playerHitMult(player, attacker, now)
		if f then
			addStack(f, player, now)
		end
	end
})

-- auto attach: a monster whose shown name has a profile, at its first think (it has its id then)
local attachEv = CreatureEvent("ChaosBossMechAttach")
function attachEv.onThink(creature, interval)
	creature:unregisterEvent("ChaosBossMechAttach")
	if creature:isMonster() and creature:getId() ~= 0 and not M.fights[creature:getId()] then
		local opts = {center = creature:getPosition()}
		-- O703: the size and health curve a system left for this monster (M.hint): the dungeon's party of the run
		local id = creature:getId()
		local hint = M.hints[id]
		M.hints[id] = nil
		if hint and hint.name == creature:getName() then
			opts.partySize, opts.healthCurve = hint.partySize, hint.healthCurve
		end
		M.attach(creature, nil, opts)
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
