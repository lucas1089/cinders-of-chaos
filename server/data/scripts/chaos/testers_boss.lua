-- Tester copies of the key bosses (O652, testers_boss_config.lua, server/README.md "The rest of the closed audit (O589)" step 10).
--
-- A world boss, a lair boss (bosslair.lua) and an island boss are the players' content: one boss, a damage share, a kill row, a respawn clock,
-- loot, titles and boards. The tester bots must not take any of it, so none of them fights the real one (a world boss arena refuses a tester,
-- worldboss.lua O595). To play the fight all the same a tester asks for a copy of its own (`!tester boss spawn`, TEST ONLY, logged):
--   * a tester only, only while no player is within `clearRadius` tiles and no lair's boss spawn is near (the copy is made in secret, the Boss
--     Spawns tracker never sees it);
--   * the copy stands a few tiles from the bot, with its own mechanics (boss_mechanics.lua attach: telegraphs, adds, enrage) in a box arena of
--     walkable tiles, at a small share of the boss's health; only testers can hurt it (ChaosTesters.markWorld "testers": a player's hit is
--     cancelled); one copy per tester, removed after `lifeSeconds`;
--   * it says nothing to anybody, writes no kill row (bossspawns.lua skips it: B.creating), no board, no Discord line; its loot, experience and
--     boss passive point (bosspoints.lua credits the killer's own storage) are the tester's own.
-- B.probe(player) is what a person sees: the copy (place, health), its telegraphs (the tiles marked now, the time to the hit, the nearest safe
-- tile when the bot stands in one: boss_mechanics.lua M.dangerFor), the kills, the boss points, `listed` (testers named in the boss boards: 0) and
-- the guide (dodge | fight | walk | wait). B.testerClose removes the copy.
-- Assumed engine API (TFS 1.4.2): Game.createMonster, Game.getSpectators, Monster (setMaxHealth, addHealth, getHealth, registerEvent, remove),
-- CreatureEvent death, addEvent, Tile. Lua 5.1 / LuaJIT.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosTestersCore or not ChaosTestersCore.safetyProblem then
	dofile("data/scripts/chaos/testers_core.lua")
end

Chaos.testersBossConfig = Chaos.testersBossConfig or dofile("data/scripts/chaos/testers_boss_config.lua")
local cfg = Chaos.testersBossConfig
local K = ChaosTestersCore

ChaosTestersBoss = ChaosTestersBoss or {}
local B = ChaosTestersBoss
B.copies = B.copies or {} -- boss creature id -> {owner = player id, name, at = os.time(), level}
B.killed = B.killed or {} -- tester player id -> copies killed
B.creating = false -- true while a copy is made: bossspawns.lua's onSpawn leaves it alone

local function log(text)
	print("[Chaos testers boss] " .. text)
end

local function isTesterPlayer(player)
	return player ~= nil and Chaos.isTester ~= nil and Chaos.isTester(player) == true
end

local function cheb(a, b)
	return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end

local function MM()
	return rawget(_G, "ChaosBossMech")
end

-- the level a boss is for: the profile's fair.refLevel (boss_mechanics_config.lua)
local function levelOf(name)
	local M = MM()
	local fair = M and M.fairOf and M.fairOf(name)
	return fair and tonumber(fair.refLevel) or 0
end

-- the boss for a bot of this level: the highest refLevel it reaches (`which` = a part of a name asks for that boss). -> name, level | nil, why
function B.pick(level, which)
	local best
	for _, name in ipairs(cfg.bosses) do
		local lv = levelOf(name)
		local asked = which == nil or name:lower():find(tostring(which):lower(), 1, true) ~= nil
		if asked and lv > 0 and lv <= (tonumber(level) or 0) and (not best or lv > best.level) then
			best = {name = name, level = lv}
		end
	end
	if not best then
		return nil, which and "no such boss for this level" or "the level is under the lowest boss"
	end
	return best.name, best.level
end

function B.copyOf(player)
	for id, c in pairs(B.copies) do
		if c.owner == player:getId() then
			if Monster(id) then
				return id, c
			end
			B.copies[id] = nil
		end
	end
	return nil
end

function B.isCopy(creature)
	return creature ~= nil and creature.getId ~= nil and B.copies[creature:getId()] ~= nil
end

-- a lair whose boss spawn is within lairGuard tiles of the position (bosslair_config.lua), or nil
local function lairNear(pos)
	local LC, L = Chaos.bossLairConfig, rawget(_G, "ChaosBossLairCore")
	if not (LC and L and L.bossPos) then
		return nil
	end
	for _, lair in ipairs(LC.lairs or {}) do
		local bp = L.bossPos(lair)
		if bp and bp.z == pos.z and cheb(bp, pos) <= cfg.lairGuard then
			return lair
		end
	end
	return nil
end

local function freeSpot(pos)
	local best
	local want = cfg.spotDistance
	for dx = -want - 2, want + 2 do
		for dy = -want - 2, want + 2 do
			local d = math.max(math.abs(dx), math.abs(dy))
			if d >= want - 1 and d <= want + 1 then
				local q = Position(pos.x + dx, pos.y + dy, pos.z)
				local t = Tile(q)
				if t and t:getGround() and t:getCreatureCount() == 0 and not t:hasFlag(TILESTATE_PROTECTIONZONE)
						and not (TILESTATE_BLOCKSOLID and t:hasFlag(TILESTATE_BLOCKSOLID)) then
					local score = math.abs(d - want) * 10 + (math.abs(dx) + math.abs(dy)) % 3
					if not best or score < best.score then
						best = {pos = q, score = score}
					end
				end
			end
		end
	end
	return best and best.pos
end

-- TEST ONLY (`!tester boss spawn [name]`): the copy, or nil and the reason
function B.testerSpawn(player, which)
	if not cfg.enabled then
		return nil, "the boss copies are off"
	end
	if not isTesterPlayer(player) then
		return nil, "not a tester"
	end
	if B.copyOf(player) then
		return nil, "the bot has a boss copy already"
	end
	local pos = player:getPosition()
	local clear = cfg.clearRadius
	for _, p in ipairs(Game.getSpectators(pos, false, true, clear, clear, clear, clear) or {}) do
		if p:isPlayer() and not isTesterPlayer(p) then
			return nil, "a player is near: the copy is not made"
		end
	end
	local here = Tile(pos)
	if here and here:hasFlag(TILESTATE_PROTECTIONZONE) then
		return nil, "the bot stands in a protection zone"
	end
	local lair = lairNear(pos)
	if lair then
		return nil, "the lair of " .. tostring(lair.key) .. " is near: the real boss is the players'"
	end
	local name, level = B.pick(player:getLevel(), which)
	if not name then
		return nil, level
	end
	local spot = freeSpot(pos)
	if not spot then
		return nil, "no free tile near the bot"
	end
	B.creating = true
	local ok, monster = pcall(Game.createMonster, name, spot, false, true)
	B.creating = false
	if not ok or not monster then
		return nil, "the boss could not be made"
	end
	-- the copy is the testers' own: a player's hit on it is cancelled, a tester's lands (testers.lua markWorld)
	local T = rawget(_G, "ChaosTesters")
	if not (T and T.markWorld and T.markWorld(monster, K.BOSS_COPY_SIDE)) then
		monster:remove()
		return nil, "the guard could not be set: no copy"
	end
	monster:registerEvent("ChaosTestersBossDeath")
	local max = math.max(1000, math.floor(monster:getMaxHealth() * cfg.healthShare))
	monster:setMaxHealth(max)
	Chaos.heal(monster, max - monster:getHealth()) -- O682
	local M = MM()
	if M and M.attach then
		pcall(M.attach, monster, nil, {center = spot, radius = cfg.arenaRadius, solo = true,
			players = function() return {player} end})
	end
	local id = monster:getId()
	B.copies[id] = {owner = player:getId(), name = name, at = os.time(), level = level}
	addEvent(function(cid)
		local c = B.copies[cid]
		local m = c and Monster(cid)
		if m then
			B.copies[cid] = nil
			m:remove()
		end
	end, cfg.lifeSeconds * 1000, id)
	log(string.format("TEST ONLY: a copy of %s made for tester %s (level %d)", name, player:getName(), player:getLevel()))
	return monster
end

-- TEST ONLY (`!tester boss close`): the copy goes
function B.testerClose(player)
	local id = B.copyOf(player)
	if not id then
		return false
	end
	local m = Monster(id)
	B.copies[id] = nil
	if m then
		local M = MM()
		if M and M.detach then
			pcall(M.detach, m)
		end
		m:getPosition():sendMagicEffect(CONST_ME_POFF)
		m:remove()
	end
	return true
end

-- the kill: counted for the owner (the bots' probe); nothing else is written here
local death = CreatureEvent("ChaosTestersBossDeath")
function death.onDeath(creature, corpse, killer, mostDamageKiller)
	local c = B.copies[creature:getId()]
	if c then
		B.killed[c.owner] = (B.killed[c.owner] or 0) + 1
		B.copies[creature:getId()] = nil
	end
	return true
end
death:register()

-- how many testers a boss board names: the kill rows of the Boss Spawns tracker (a copy writes none). 0 is right.
function B.listed()
	local S = rawget(_G, "ChaosBossSpawns")
	if not (S and S.state and next(Chaos.testerGuids or {})) then
		return 0
	end
	local n = 0
	local function scan(v, depth)
		if type(v) == "string" then
			if K.mentions(v, Chaos.testerGuids) then
				n = n + 1
			end
		elseif type(v) == "table" and depth < 4 then
			for _, x in pairs(v) do
				scan(x, depth + 1)
			end
		end
	end
	scan(S.state, 0)
	return n
end

local function plain(pos)
	return {x = pos.x, y = pos.y, z = pos.z}
end

-- what a person sees (`!tester boss`)
function B.probe(player)
	local pos = player:getPosition()
	local out = {level = player:getLevel(), pos = plain(pos), killed = B.killed[player:getId()] or 0, listed = B.listed()}
	local P = rawget(_G, "ChaosBossPoints")
	if P and P.count then
		local ok, n = pcall(P.count, player)
		out.points = ok and n or nil
	end
	local name, level = B.pick(player:getLevel())
	out.next, out.nextLevel = name, level
	local id, c = B.copyOf(player)
	if not id then
		out.guide = {mode = "wait", why = "no boss copy of its own"}
		return out
	end
	local m = Monster(id)
	local mp = m:getPosition()
	out.boss = {pos = plain(mp), name = c.name, hp = math.floor(m:getHealth() * 100 / math.max(1, m:getMaxHealth())),
		left = math.max(0, cfg.lifeSeconds - (os.time() - c.at))}
	local M = MM()
	local danger = M and M.dangerFor and M.dangerFor(id, pos)
	local dist = mp.z == pos.z and cheb(mp, pos) or 999
	if danger then
		local marked, tiles = danger.marked, {}
		for k in pairs(marked) do
			if #tiles < 60 then
				local x, y = k:match("^(%d+),(%d+)$")
				tiles[#tiles + 1] = {tonumber(x), tonumber(y)}
			end
		end
		out.danger = {left = danger.left, labels = danger.labels, count = danger.count, here = marked[pos.x .. "," .. pos.y] == true,
			tiles = tiles}
		if danger.goal then
			out.guide = {mode = "dodge", goal = danger.goal, why = "a mark of " .. tostring(danger.labels[1]) .. " is on the bot's tile"}
			return out
		end
	end
	if dist <= cfg.reach then
		out.guide = {mode = "fight", goal = plain(mp), area = "boss", why = "in reach of the boss"}
	else
		out.guide = {mode = "walk", goal = plain(mp), reach = {1, cfg.reach}, area = "boss", why = "to the boss"}
	end
	return out
end
