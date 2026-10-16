-- World boss event: five world bosses, an arena built at runtime, town portals, damage-share rewards.
-- Settings: Chaos.worldBoss in chaos_constants.lua. Monsters: data/monster/monsters/chaos/world_bosses/*.xml
-- (<flag isboss="1"/>). Overview, numbers and coordinates: server/README.md "World bosses".
--
-- Flow
--   start (schedule every Chaos.worldBoss.intervalHours, or /worldboss start [name|number|random])
--     -> arena + lobby are built with Game.createTile (refused if any tile of the footprint already exists and is
--        not ours), a forcefield (item 1387, action id aid.enter) appears next to every temple, broadcast + toast
--     -> after gatherSeconds the boss appears in the middle of the arena
--     -> phases at health thresholds: adds, enrage (a periodic pulse around the boss)
--     -> boss dies: rewards for every eligible participant (not only the corpse owner) by contribution score
--        (damage + healing and tanking at configured weights), extra rewards and a role title for the top 3 of each
--        category (damage, healing, tanking), broadcast with the three top 3 lists; or the fight time runs out /
--        /worldboss stop: the boss leaves, broadcast
--     -> town portals are removed, after exitDelaySeconds everybody still inside goes to their temple, the arena is
--        cleaned (monsters, corpses, loose items; walls, decor and the arena portals stay)
--   The lobby is protected by script (no combat in it, no PvP in lobby or arena unless allowPvp): dynamic tiles cannot
--   get the protection-zone flag from Lua in this engine.
--
-- Multi-client (Chaos.isMultiClient): such characters may enter and fight (the event is open to everyone and they
-- already cannot attack players), but they get no participation reward unless mcReward = true. A character counts
-- as multi-clienting if it was at entry or at any arena check (every 3 s) during the event.
--
-- Roles (Chaos.worldBoss.roles, server/README.md "World bosses"): damage on the boss (healthchange on the boss);
-- healing of other players inside the arena (healthchange registered on every player inside: the engine passes the
-- healer as attacker for spells, runes, potions used on someone and doTargetCombat heals; Chaos.heal / addHealth
-- has no origin and is not attributed), capped at the missing health and at the boss damage the target was not
-- healed for yet; tanking: damage from the boss and its adds the player survived, capped per hit, x offTargetWeight when
-- the attacker was not targeting the player, only while the player is active (attacked or healed within
-- activeSeconds).
--
-- Assumed engine API (TFS 1.4 as in the base server source): Game.createTile(pos, true),
-- Game.createItem(id, n, pos), Item:setActionId/getActionId, Tile:getGround/getItemById/getItems/getHouse/hasProperty,
-- Game.createMonster(name, pos, false, true), Creature:setMaxHealth/addHealth, CreatureEvent healthchange/death/login,
-- MoveEvent stepin with aid, EventCallback onTargetCombat, GlobalEvent onThink/onStartup, doTargetCombatHealth,
-- Player:getInbox()/addItemEx/getBankBalance/setBankBalance, Game.createItemWithRarity, Game.getTowns.
-- The pure parts (layout, schedule, rotation, shares, roles, rewards, phases) are tested in tests/worldboss_test.lua.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
if not ChaosCommands then
	dofile("data/scripts/chaos/commands_ui_core.lua")
end
dofile("data/lib/chaos_dark_paint.lua")
if not ChaosCityPortals then
	dofile("data/scripts/chaos/cityportals.lua")
end

ChaosWorldBoss = ChaosWorldBoss or {}
-- pack effects (data/lib/chaos_pack_fx.lua, switch ChaosPackFx.PACK_FX, on since 2026-10-13; off: exactly the stock effect as before)
if not ChaosPackFx then
	pcall(dofile, "data/lib/chaos_pack_fx.lua")
end
local function packFx(pos, use, stock)
	if ChaosPackFx then
		return ChaosPackFx.send(pos, use, stock)
	end
	if stock then
		pos:sendMagicEffect(stock)
	end
	return false
end
local W = ChaosWorldBoss

local function C()
	return Chaos.worldBoss
end

-- ======================================================================== pure helpers (tested)

-- Geometry of arena and lobby. Every value is derived from Chaos.worldBoss.arena.
function W.layout(a)
	a = a or C().arena
	local o = a.origin
	local last = a.inner + 1
	local L = {z = o.z}
	L.arena = {x1 = o.x, y1 = o.y, x2 = o.x + last, y2 = o.y + last}
	local half = math.floor((a.inner + 1) / 2) -- integer in Lua 5.3 too (positions are table keys in tests)
	local cx, cy = o.x + half, o.y + half
	L.center = {x = cx, y = cy, z = o.z}
	local halfW = math.floor((a.lobbyInnerW + 1) / 2)
	local ly1 = L.arena.y2 + a.lobbyGap + 1
	L.lobby = {x1 = cx - halfW, y1 = ly1, x2 = cx + halfW, y2 = ly1 + a.lobbyInnerH + 1}
	local lcy = L.lobby.y1 + math.floor((a.lobbyInnerH + 1) / 2)
	L.bossSpawn = {x = cx, y = cy, z = o.z}
	L.arenaEntry = {x = cx, y = L.arena.y2 - 3, z = o.z} -- players arrive here from the lobby
	L.arenaBack = {x = cx, y = L.arena.y2 - 1, z = o.z} -- forcefield back to the lobby
	L.lobbyArrival = {x = cx, y = L.lobby.y2 - 2, z = o.z}
	L.lobbyToArena = {x = cx, y = L.lobby.y1 + 1, z = o.z}
	L.lobbyExits = {{x = L.lobby.x1 + 1, y = lcy, z = o.z}, {x = L.lobby.x2 - 1, y = lcy, z = o.z}}
	L.pillars = {}
	for _, d in ipairs({{-7, -7}, {7, -7}, {-7, 7}, {7, 7}}) do
		L.pillars[#L.pillars + 1] = {x = cx + d[1], y = cy + d[2], z = o.z}
	end
	L.basins = {
		{x = L.arena.x1 + 1, y = L.arena.y1 + 1, z = o.z}, {x = L.arena.x2 - 1, y = L.arena.y1 + 1, z = o.z},
		{x = L.arena.x1 + 1, y = L.arena.y2 - 1, z = o.z}, {x = L.arena.x2 - 1, y = L.arena.y2 - 1, z = o.z},
		{x = L.lobby.x1 + 1, y = L.lobby.y1 + 1, z = o.z}, {x = L.lobby.x2 - 1, y = L.lobby.y1 + 1, z = o.z},
		{x = L.lobby.x1 + 1, y = L.lobby.y2 - 1, z = o.z}, {x = L.lobby.x2 - 1, y = L.lobby.y2 - 1, z = o.z}
	}
	return L
end

local function inRect(r, z, pos)
	return pos ~= nil and pos.z == z and pos.x >= r.x1 and pos.x <= r.x2 and pos.y >= r.y1 and pos.y <= r.y2
end

function W.inArena(pos, L)
	L = L or W.layout()
	return inRect(L.arena, L.z, pos)
end

function W.inLobby(pos, L)
	L = L or W.layout()
	return inRect(L.lobby, L.z, pos)
end

function W.inside(pos, L)
	L = L or W.layout()
	return inRect(L.arena, L.z, pos) or inRect(L.lobby, L.z, pos)
end

Chaos.registerInstance("worldboss", {label = "the world boss arena", at = function(pos)
	return W.inside(pos)
end, runs = function() -- /instances (instance_limits.lua)
	local st = W.state
	if not st or st.phase == "idle" then
		return {}
	end
	local n = 0
	for _, p in ipairs(Game.getPlayers()) do
		if W.inside(p:getPosition()) then
			n = n + 1
		end
	end
	return {{id = "event", what = st.phase, left = st.fightEnd and math.max(0, st.fightEnd - os.time()) or nil, players = n}}
end, close = function() -- as /worldboss stop: the boss withdraws, everyone to the temple
	if not W.state or W.state.phase == "idle" then
		return false, "No world boss event is running."
	end
	W.stop()
	return true, "World boss event stopped."
end})

-- Every tile of both rooms: {x, y, z, wall = bool, lobby = bool}
function W.footprint(L)
	L = L or W.layout()
	local list = {}
	for _, room in ipairs({{r = L.arena, lobby = false}, {r = L.lobby, lobby = true}}) do
		local r = room.r
		for x = r.x1, r.x2 do
			for y = r.y1, r.y2 do
				list[#list + 1] = {x = x, y = y, z = L.z, lobby = room.lobby,
					wall = (x == r.x1 or x == r.x2 or y == r.y1 or y == r.y2)}
			end
		end
	end
	return list
end

-- Next boss index. rotation: the one after `last`; random: any but `last` (when there is more than one).
function W.pickBoss(count, mode, last, rng)
	rng = rng or math.random
	last = tonumber(last) or 0
	if count <= 1 then
		return 1
	end
	if mode == "random" then
		if last < 1 or last > count then
			return rng(count)
		end
		local i = rng(count - 1)
		return i >= last and i + 1 or i
	end
	if last < 1 or last > count then
		return 1
	end
	return last % count + 1
end

-- First scheduled start strictly after `now` (server local time, full hours).
function W.nextStart(now, c)
	c = c or C()
	local interval = math.max(1, math.floor(c.intervalHours or 6))
	local offset = math.floor(c.offsetHours or 0) % interval
	local d = os.date("*t", now)
	for i = 0, 24 * 2 + interval do
		local t = os.time({year = d.year, month = d.month, day = d.day, hour = d.hour + i, min = 0, sec = 0})
		local h = os.date("*t", t).hour
		if t > now and (h - offset) % interval == 0 then
			return t
		end
	end
	return now + interval * 3600
end

-- Phases whose threshold `fraction` (health left / max health) has reached and that did not run yet.
function W.duePhases(phases, done, fraction)
	local list = {}
	for i, p in ipairs(phases or {}) do
		if not done[i] and fraction <= p.at then
			list[#list + 1] = i
		end
	end
	return list
end

-- Contribution score of one participant: damage + healing x healWeight + tanking x tankWeight
-- (weights = Chaos.worldBoss.roles; nil = damage only, the rule before the healer/tank roles).
function W.score(e, weights)
	if not weights then
		return e.damage or 0
	end
	return (e.damage or 0) + (e.healing or 0) * (weights.healWeight or 0) + (e.tanking or 0) * (weights.tankWeight or 0)
end

local function seqOf(e, key)
	return (e.seq and e.seq[key]) or 0
end

-- value desc; equal values: the one who reached it first (lower seq), then the lower guid
local function byValue(key)
	return function(a, b)
		local va, vb = a[key] or 0, b[key] or 0
		if va ~= vb then
			return va > vb
		end
		local sa, sb = seqOf(a, key), seqOf(b, key)
		if sa ~= sb then
			return sa < sb
		end
		return a.guid < b.guid
	end
end

-- stats = {[guid] = {name, damage, healing?, tanking?, seq? = {damage = n, ...}}}; excluded = {[guid] = true}
-- -> list of the eligible players sorted by score: {guid, name, damage, healing, tanking, score, share, scoreRank,
--    rank}, total eligible score. Eligible: score >= minPercent % of the boss max health (anti-AFK), not excluded.
--    share = score / total. rank = place by damage among the eligible (nil without damage; achievements.lua reads
--    rank 1 as "dealt the most damage"), scoreRank = place by score.
function W.computeShares(stats, maxHealth, minPercent, excluded, weights)
	excluded = excluded or {}
	local minScore = (maxHealth or 0) * (minPercent or 0) / 100
	local list, total = {}, 0
	for guid, e in pairs(stats) do
		local score = W.score(e, weights)
		if not excluded[guid] and score > 0 and score >= minScore then
			list[#list + 1] = {guid = guid, name = e.name, damage = e.damage or 0, healing = e.healing or 0,
				tanking = e.tanking or 0, score = score, seq = e.seq}
			total = total + score
		end
	end
	table.sort(list, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
		end
		return a.guid < b.guid
	end)
	local dealers = {}
	for i, e in ipairs(list) do
		e.share = total > 0 and e.score / total or 0
		e.scoreRank = i
		if e.damage > 0 then
			dealers[#dealers + 1] = e
		end
	end
	table.sort(dealers, byValue("damage"))
	for i, e in ipairs(dealers) do
		e.rank = i
	end
	return list, total
end

-- The top `pc.top` of every category (pc = Chaos.worldBoss.reward.podium: damage, healing, tanking) among the
-- eligible shares: sets s.places = {[category key] = place} and returns {[category key] = {share, ...}} in place order. One player
-- can place in several categories. Ties: who reached the value first places higher (seq), then the lower guid; a
-- value under placeMinPercent % of the boss max health does not place.
function W.placeRoles(shares, pc, maxHealth)
	local podium = {}
	pc = pc or {}
	local minValue = (maxHealth or 0) * (pc.placeMinPercent or 0) / 100
	for _, cat in ipairs(pc.categories or {}) do
		local list = {}
		for _, s in ipairs(shares) do
			local v = s[cat.key] or 0
			if v > 0 and v >= minValue then
				list[#list + 1] = s
			end
		end
		table.sort(list, byValue(cat.key))
		podium[cat.key] = {}
		for i = 1, math.min(pc.top or 3, #list) do
			local s = list[i]
			s.places = s.places or {}
			s.places[cat.key] = i
			podium[cat.key][i] = s
		end
	end
	return podium
end

-- Tanking credit of one hit from the boss or an add: only the part the player survived (a hit that kills counts
-- nothing), capped at tankHitCap, x offTargetWeight when the attacker was not targeting the player (splash).
function W.tankCredit(damage, health, targeted, roles)
	if not damage or damage <= 0 or not health or health <= 0 or damage >= health then
		return 0
	end
	local v = math.min(damage, roles.tankHitCap or damage)
	if not targeted then
		v = v * (roles.offTargetWeight or 1)
	end
	return v
end

-- Healing credit of one heal: effective healing (capped at the target's missing health), at most the boss damage
-- the target took and was not healed for yet (`debt`), so only healing of boss damage counts. Healing yourself
-- counts x selfHealWeight. -> credit, effective healing
function W.healCredit(amount, missing, debt, self, roles)
	local eff = math.max(0, math.min(amount or 0, missing or 0))
	local credit = math.min(eff, math.max(0, debt or 0))
	if self then
		credit = credit * (roles.selfHealWeight or 0)
	end
	return credit, eff
end

local function addItem(map, order, id, count)
	if count <= 0 then
		return
	end
	if not map[id] then
		map[id] = 0
		order[#order + 1] = id
	end
	map[id] = map[id] + count
end

-- shares from computeShares (+ placeRoles) -> list of {guid, name, share, rank, scoreRank, damage, healing, tanking,
-- places, bank, items = {{id, count}}, gear, gearRarity, unique, titles = {{key, text, color, place, name}}}.
-- r = Chaos.worldBoss.reward: base items for everyone, pool split by share, r.podium.categories[i].rewards[place]
-- for the top 3 of each category, plus their title and an extra unique chance (one unique at most per player).
-- pityOf (optional, conquest.lua bad-luck protection): pityOf(guid) -> the multiplier on every unique chance of that
-- player; a reward then carries pityRolled = true (the unique was rolled: the caller records the miss or the hit)
function W.computeRewards(shares, r, boss, uniquePool, rng, pityOf)
	rng = rng or math.random
	uniquePool = uniquePool or {}
	local cats = r.podium and r.podium.categories or {}
	local out = {}
	for _, s in ipairs(shares) do
		local map, order = {}, {}
		for _, it in ipairs(r.base or {}) do
			addItem(map, order, it.id, it.count)
		end
		for _, it in ipairs(r.pool or {}) do
			addItem(map, order, it.id, math.floor(it.count * s.share))
		end
		-- gems (data/lib/chaos_gems_config.lua rewards.worldboss: a count plus more by share)
		if ChaosGems and ChaosGems.rewardGems then
			for _, g in ipairs(ChaosGems.rewardGems("worldboss", {share = s.share}, function(a, b) return rng(a, b) end)) do
				addItem(map, order, g.id, g.count)
			end
		end
		local titles, uniqueRolls = {}, {}
		for _, cat in ipairs(cats) do
			local place = s.places and s.places[cat.key]
			if place then
				for _, it in ipairs((cat.rewards or {})[place] or {}) do
					addItem(map, order, it.id, it.count)
				end
				if cat.title then
					titles[#titles + 1] = {key = cat.key, text = cat.title, color = cat.color, place = place, name = cat.name}
				end
				uniqueRolls[#uniqueRolls + 1] = (cat.uniqueChance or {})[place] or 0
			end
		end
		local items = {}
		for _, id in ipairs(order) do
			items[#items + 1] = {id = id, count = map[id]}
		end
		local reward = {guid = s.guid, name = s.name, share = s.share, rank = s.rank, scoreRank = s.scoreRank,
			damage = s.damage, healing = s.healing, tanking = s.tanking, places = s.places, items = items, titles = titles,
			bank = (r.bankGold or 0) + math.floor((r.bankGoldPool or 0) * s.share)}
		local gear = boss and boss.gear or {}
		if #gear > 0 and rng(10000) <= (r.gearChance or 0) + math.floor((r.gearShareBonus or 0) * s.share) then
			reward.gear = gear[rng(#gear)]
			local lo, hi = (r.gearRarity or {0, 0})[1], (r.gearRarity or {0, 0})[2]
			reward.gearRarity = rng(lo, math.max(lo, hi))
		end
		if #uniquePool > 0 then
			local mult = pityOf and tonumber(pityOf(s.guid)) or 1
			if mult ~= mult or mult < 1 then
				mult = 1
			end
			reward.pityRolled = pityOf ~= nil or nil
			local won = rng(10000) <= math.floor(((r.uniqueChance or 0) + math.floor((r.uniqueShareBonus or 0) * s.share)) * mult)
			for _, chance in ipairs(uniqueRolls) do
				if won then
					break
				end
				won = chance > 0 and rng(10000) <= math.floor(chance * mult)
			end
			if won then
				reward.unique = uniquePool[rng(#uniquePool)]
			end
		end
		out[#out + 1] = reward
	end
	return out
end

-- "1.2M", "850k", "900"
function W.short(n)
	n = math.floor(n or 0)
	if n >= 1000000 then
		return string.format("%.1fM", n / 1000000)
	elseif n >= 10000 then
		return string.format("%dk", math.floor(n / 1000))
	end
	return tostring(n)
end

-- {"Top damage: A 1.2M, B 800k.", "Top healing: C 300k.", "Top tanking: nobody."}
function W.podiumLines(podium, pc)
	local lines = {}
	for _, cat in ipairs((pc or {}).categories or {}) do
		local names = {}
		for _, s in ipairs(podium[cat.key] or {}) do
			names[#names + 1] = s.name .. " " .. W.short(s[cat.key])
		end
		lines[#lines + 1] = string.format("Top %s: %s.", (cat.name or cat.key):lower(),
			#names > 0 and table.concat(names, ", ") or "nobody")
	end
	return lines
end

function W.podiumText(podium, pc)
	return table.concat(W.podiumLines(podium, pc), " ")
end

-- boss-only uniques of chaos_unique_items.lua that list this boss
function W.uniquePool(bossName)
	local pool = {}
	local lname = bossName:lower()
	local list = ChaosUniqueItems or {}
	for key, e in pairs(list) do
		if type(e) == "table" and e.id and e.bossOnly then
			for _, m in ipairs(e.monsters or {}) do
				if m:lower() == lname then
					pool[#pool + 1] = e.id
					break
				end
			end
		end
	end
	table.sort(pool)
	return pool
end

-- "kael", "3", "random", "" -> boss index or nil
function W.findBoss(arg)
	local list = C().bosses
	arg = tostring(arg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if arg == "" or arg == "random" then
		return nil
	end
	local n = tonumber(arg)
	if n and list[n] then
		return n
	end
	for i, b in ipairs(list) do
		if b.name:lower():find(arg, 1, true) then
			return i
		end
	end
	return false
end

-- ======================================================================== runtime state
W.state = W.state or {phase = "idle", token = 0}
W.pending = W.pending or {} -- guid -> list of rewards for players offline at the kill
local state = W.state

local function P(t)
	return Position(t.x, t.y, t.z)
end

local function effectOf(name, fallback)
	return (name and _G["CONST_ME_" .. name:upper()]) or fallback or CONST_ME_MORTAREA
end

local function combatOf(name)
	if name == "physical" then
		return COMBAT_PHYSICALDAMAGE
	end
	return _G["COMBAT_" .. tostring(name):upper() .. "DAMAGE"] or COMBAT_PHYSICALDAMAGE
end

-- text: a string or a deferred text (ChaosI18n.msg): each player reads it in their language; the toast and the log
-- are English
local function announce(text, toast)
	text = Chaos.broadcast(MESSAGE_EVENT_ADVANCE, text)
	if toast and ChaosNotify and ChaosNotify.gmBroadcast then
		ChaosNotify.gmBroadcast(nil, text)
	end
	print("[Chaos world boss] " .. text)
end

local function playerOf(creature)
	if not creature then
		return nil
	end
	if creature:isPlayer() then
		return creature
	end
	local master = creature:getMaster()
	return master and master:isPlayer() and master or nil
end

local function groundId(tile)
	local g = tile:getGround()
	if type(g) == "number" then
		return g
	end
	return g and g:getId() or nil
end

local function bossCfg()
	return state.index and C().bosses[state.index] or nil
end

local function playersInside()
	local list = {}
	local L = W.layout()
	for _, p in ipairs(Game.getPlayers()) do
		if W.inside(p:getPosition(), L) then
			list[#list + 1] = p
		end
	end
	return list
end

-- ======================================================================== arena
-- the dark tile set (Chaos.worldBoss.arena.dark): walls, pillars and lights switch to it and both rooms are painted
-- by ChaosDarkPaint when it is installed; otherwise the stock ids of the config are used unchanged
local function darkArena()
	local a = C().arena
	if a.darkActive ~= nil then
		return a.darkActive
	end
	a.darkActive = false
	local d = a.dark
	if d and d.enabled and ChaosDarkPaint and ChaosDarkTiles and ChaosDarkPaint.ready(d.arenaStyle)
		and ChaosDarkPaint.ready(d.lobbyStyle) then
		local wall, pillar, basin = ChaosDarkTiles.id(d.wall), ChaosDarkTiles.id(d.pillar), ChaosDarkTiles.id(d.basin)
		if wall and pillar and basin then
			a.wallId, a.pillarId, a.basinId = wall, pillar, basin
			a.darkActive = true
		end
	end
	return a.darkActive
end

local function fixedItemIds()
	darkArena()
	local a = C().arena
	return {[a.wallId] = true, [a.pillarId] = true, [a.basinId] = true, [a.portalId] = true}
end

local function keepItem(keep, id)
	return keep[id] or (darkArena() and ChaosDarkPaint.isDark(id))
end

-- paints the floors of both rooms (the fixtures' tiles stay plain)
local function paintArena(L, foot)
	local a = C().arena
	local walls, arena, lobby = {}, {}, {}
	for _, t in ipairs(foot) do
		if t.wall then
			walls[t.x .. "," .. t.y] = true
		elseif t.lobby then
			lobby[#lobby + 1] = t
		else
			arena[#arena + 1] = t
		end
	end
	local reserved = {L.center, L.bossSpawn, L.arenaEntry, L.arenaBack, L.lobbyArrival, L.lobbyToArena}
	for _, list in ipairs({L.lobbyExits, L.pillars, L.basins}) do
		for _, p in ipairs(list) do
			reserved[#reserved + 1] = p
		end
	end
	local opts = {walls = walls, reserved = reserved}
	ChaosDarkPaint.apply(ChaosDarkPaint.plan(arena, a.dark.arenaStyle, math.random, opts), L.z)
	ChaosDarkPaint.apply(ChaosDarkPaint.plan(lobby, a.dark.lobbyStyle, math.random, opts), L.z)
end

local function placeItem(pos, id, aid)
	local tile = Tile(pos)
	if not tile then
		return nil
	end
	local item = tile:getItemById(id)
	if not item then
		item = Game.createItem(id, 1, pos)
	end
	if item and aid and item.setActionId then
		item:setActionId(aid)
	end
	return item
end

-- returns true, or false + reason (nothing is built then)
function W.buildArena()
	local dark = darkArena()
	local a = C().arena
	local L = W.layout()
	local foot = W.footprint(L)
	local ours = {[a.groundId] = true, [a.lobbyGroundId] = true}
	for _, t in ipairs(foot) do
		local tile = Tile(P(t))
		if tile then
			local gid = groundId(tile)
			if not (ours[gid] or (dark and ChaosDarkPaint.isDark(gid))) or (tile.getHouse and tile:getHouse()) then
				return false, string.format("tile %d,%d,%d already exists in the map", t.x, t.y, t.z)
			end
		end
	end
	for _, t in ipairs(foot) do
		local pos = P(t)
		local tile = Game.createTile(pos, true)
		if tile then
			if not tile:getGround() then
				Game.createItem(t.lobby and a.lobbyGroundId or a.groundId, 1, pos)
			end
			if t.wall and not tile:getItemById(a.wallId) then
				Game.createItem(a.wallId, 1, pos)
			end
		end
	end
	for _, p in ipairs(L.pillars) do
		placeItem(P(p), a.pillarId)
	end
	for _, p in ipairs(L.basins) do
		placeItem(P(p), a.basinId)
	end
	local aid = C().aid
	placeItem(P(L.arenaBack), a.portalId, aid.lobby)
	placeItem(P(L.lobbyToArena), a.portalId, aid.arena)
	for _, p in ipairs(L.lobbyExits) do
		placeItem(P(p), a.portalId, aid.exit)
	end
	if dark and not W.painted then
		paintArena(L, foot)
		W.painted = true
	end
	return true
end

-- monsters and loose items (corpses, drops, fields) inside both rooms
local function cleanArena()
	local L = W.layout()
	local keep = fixedItemIds()
	for _, t in ipairs(W.footprint(L)) do
		if not t.wall then
			local tile = Tile(P(t))
			if tile then
				for _, c in ipairs(tile:getCreatures() or {}) do
					if c:isMonster() then
						c:remove()
					end
				end
				for _, item in ipairs(tile:getItems() or {}) do
					if not keepItem(keep, item:getId()) then
						item:remove()
					end
				end
			end
		end
	end
end

-- ======================================================================== town portals
local function spotFree(pos)
	local tile = Tile(pos)
	if not tile or not tile:getGround() then
		return false
	end
	if tile.getHouse and tile:getHouse() then
		return false
	end
	if tile:hasProperty(CONST_PROP_BLOCKSOLID) or tile:hasProperty(CONST_PROP_BLOCKPATH) then
		return false
	end
	if ITEM_TYPE_TELEPORT and tile:getItemByType(ITEM_TYPE_TELEPORT) then
		return false
	end
	return true
end

function W.portalSpots()
	local c = C()
	local spots = {}
	if c.portalPositions and #c.portalPositions > 0 then
		for _, p in ipairs(c.portalPositions) do
			spots[#spots + 1] = P(p)
		end
		return spots
	end
	local allowed
	if c.towns then
		allowed = {}
		for _, id in ipairs(c.towns) do
			allowed[id] = true
		end
	end
	local seen = {}
	for _, town in ipairs(Game.getTowns()) do
		if not allowed or allowed[town:getId()] then
			local t = town:getTemplePosition()
			local key = t.x .. "," .. t.y .. "," .. t.z
			if t.x > 0 and not seen[key] then
				seen[key] = true
				for _, off in ipairs(c.portalOffsets) do
					local p = Position(t.x + off[1], t.y + off[2], t.z)
					if spotFree(p) then
						spots[#spots + 1] = p
						break
					end
				end
			end
		end
	end
	return spots
end

-- the World Boss Portals: next to every temple (of `towns`) through cityportals.lua (the first free tile of
-- `portalOffsets`, then the shared offsets; a look text and an effect while they stand), or at `portalPositions`
local function openPortals()
	state.portals = {}
	local c = C()
	local a = c.arena
	if c.portalPositions and #c.portalPositions > 0 then
		for _, pos in ipairs(W.portalSpots()) do
			local item = Game.createItem(a.portalId, 1, pos)
			if item then
				item:setActionId(c.aid.enter)
				state.portals[#state.portals + 1] = pos
				pos:sendMagicEffect(CONST_ME_TELEPORT)
				ChaosCityPortals.register("worldboss", c.aid.enter, pos)
			end
		end
	else
		local _, positions = ChaosCityPortals.place({kind = "worldboss", aid = c.aid.enter, item = a.portalId,
			towns = c.towns, offsets = c.portalOffsets})
		for _, p in ipairs(positions) do
			local pos = Position(p.x, p.y, p.z)
			state.portals[#state.portals + 1] = pos
			pos:sendMagicEffect(CONST_ME_TELEPORT)
		end
	end
	state.portalsOpen = true
	return #state.portals
end

local function closePortals()
	local a = C().arena
	for _, pos in ipairs(state.portals or {}) do
		local tile = Tile(pos)
		local item = tile and tile:getItemById(a.portalId)
		if item and item:getActionId() == C().aid.enter then
			item:remove()
			pos:sendMagicEffect(CONST_ME_POFF)
		end
	end
	state.portals = {}
	state.portalsOpen = false
end

-- ======================================================================== rewards
local function giveStack(player, id, count)
	local added = Chaos.giveItem(player, id, count)
	local rest = count - added
	if rest > 0 then
		local inbox = player:getInbox()
		while inbox and rest > 0 do
			local n = math.min(rest, 100)
			inbox:addItem(id, n, INDEX_WHEREEVER or -1, FLAG_NOLIMIT)
			rest = rest - n
		end
		return true
	end
	return false
end

local function giveEx(player, item)
	if player:addItemEx(item, false) ~= RETURNVALUE_NOERROR then
		local inbox = player:getInbox()
		if inbox then
			inbox:addItemEx(item, INDEX_WHEREEVER or -1, FLAG_NOLIMIT)
		end
		return true
	end
	return false
end

local function itemName(id)
	local it = ItemType(id)
	return it and it:getName() or tostring(id)
end

function W.placeName(place)
	return ({"1st", "2nd", "3rd"})[place] or (tostring(place) .. "th")
end

-- ======================================================================== role titles (name plates, titles.lua)
-- A role title is held for roles.titleDays after the fight: player storage roles.titleStorage + category index - 1
-- = os.time until which it is held (saved with the character).
local function categories()
	return C().reward.podium and C().reward.podium.categories or {}
end

function W.grantTitle(player, t)
	local ro = C().roles
	for i, cat in ipairs(categories()) do
		if cat.key == t.key and ro.titleStorage then
			player:setStorageValue(ro.titleStorage + i - 1, os.time() + (ro.titleDays or 7) * 86400)
		end
	end
	if ChaosNameplate and ChaosNameplate.refresh then
		pcall(ChaosNameplate.refresh, player)
	end
end

-- titles the player holds now: {{key, text, color, at}}
function W.titlesOf(player)
	local ro = C().roles
	local out = {}
	if not ro.titleStorage then
		return out
	end
	local now = os.time()
	for i, cat in ipairs(categories()) do
		local untilAt = tonumber(player:getStorageValue(ro.titleStorage + i - 1)) or -1
		if cat.title and untilAt > now then
			out[#out + 1] = {key = "worldboss:" .. cat.key, text = cat.title, color = cat.color,
				at = untilAt - (ro.titleDays or 7) * 86400}
		end
	end
	return out
end

function W.registerTitles()
	if not (ChaosTitles and ChaosTitles.register) then
		return false
	end
	ChaosTitles.register("worldboss", W.titlesOf)
	return true
end
W.registerTitles()

function W.deliver(player, r)
	local inboxUsed = false
	if r.bank and r.bank > 0 then
		player:setBankBalance(player:getBankBalance() + r.bank)
	end
	local parts = {}
	for _, it in ipairs(r.items) do
		inboxUsed = giveStack(player, it.id, it.count) or inboxUsed
		parts[#parts + 1] = it.count .. "x " .. itemName(it.id)
	end
	if r.gear then
		-- the world boss item level (chaos_item_mods.lua itemLevel.worldBoss), rolled by ChaosCrafting.forge
		local item = ChaosCrafting and ChaosCrafting.createItem
			and ChaosCrafting.createItem(r.gear, r.gearRarity or 0, ChaosItemMods.sourceLevel({worldBoss = true}))
			or Game.createItem(r.gear, 1)
		if item then
			inboxUsed = giveEx(player, item) or inboxUsed
			parts[#parts + 1] = itemName(r.gear)
		end
	end
	if r.unique then
		local item = Game.createItem(r.unique, 1)
		if item then
			if ChaosMakeUnique then
				ChaosMakeUnique(item)
			end
			inboxUsed = giveEx(player, item) or inboxUsed
			local e = ChaosUniqueById and ChaosUniqueById[r.unique]
			parts[#parts + 1] = "the unique " .. (e and e.name or itemName(r.unique))
			announce(ChaosI18n.msg("%s received the unique %s from the world boss!", player:getName(), e and e.name or itemName(r.unique)), false)
		end
	end
	local roles = {}
	for _, t in ipairs(r.titles or {}) do
		roles[#roles + 1] = string.format("%s in %s", W.placeName(t.place), (t.name or t.key):lower())
		W.grantTitle(player, t)
	end
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player,
		"World boss reward (%.1f%% of the contribution: %s damage, %s healing, %s tanking%s): %d gold to your bank, %s.%s",
		(r.share or 0) * 100, W.short(r.damage), W.short(r.healing), W.short(r.tanking),
		#roles > 0 and ("; " .. table.concat(roles, ", ")) or "", r.bank or 0, table.concat(parts, ", "),
		inboxUsed and Chaos.t(player, " Your backpack was full: the rest is in your inbox.") or ""))
	for _, t in ipairs(r.titles or {}) do
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "You earned the title %s (%s %s) for %d days.",
			t.text, W.placeName(t.place), (t.name or t.key):lower(), C().roles.titleDays or 7))
	end
	if ChaosPack29Vfx then -- pair 29 (switch off: the stock firework)
		ChaosPack29Vfx.celebrate(player:getPosition(), "boss", CONST_ME_FIREWORK_YELLOW)
	else
		player:getPosition():sendMagicEffect(CONST_ME_FIREWORK_YELLOW)
	end
end

local function distribute()
	local c = C()
	local boss = bossCfg()
	local excluded = {}
	if not c.mcReward then
		for guid in pairs(state.mc or {}) do
			excluded[guid] = true
		end
	end
	local minPercent = c.reward.minScorePercent or c.reward.minDamagePercent
	local shares, total = W.computeShares(state.stats or {}, state.maxHealth or 0, minPercent, excluded, c.roles)
	local podium = W.placeRoles(shares, c.reward.podium, state.maxHealth or 0)
	-- bad-luck protection (conquest.lua): the participation unique chance x the player's "boss" multiplier
	local CQ = ChaosConquest
	local pityOf = nil
	if CQ and CQ.pityMult and CQ.pityRecord then
		pityOf = function(guid)
			for _, s in ipairs(shares) do
				local p = s.guid == guid and Player(s.name)
				if p and p:getGuid() == guid then
					return CQ.pityMult(p, "boss")
				end
			end
			return 1
		end
	end
	local rewards = W.computeRewards(shares, c.reward, boss, W.uniquePool(boss.name), nil, pityOf)
	local LB = ChaosLeaderboard
	if LB and LB.recordShares then LB.recordShares(shares) end -- leaderboard.lua (World Boss: damage, kills)
	local boards = c.roles.boards or {}
	for _, s in ipairs(shares) do
		local who = {guid = s.guid, name = s.name}
		if LB and LB.record then
			if boards.healing and s.healing >= 1 then
				LB.record(boards.healing, who, math.floor(s.healing), "add")
			end
			if boards.tanking and s.tanking >= 1 then
				LB.record(boards.tanking, who, math.floor(s.tanking), "add")
			end
		end
		local A = ChaosAchievements -- achievements.lua: wb_heal_top, wb_tank_top, wb_role_podium
		if A and A.progress and s.places then
			if s.places.healing == 1 then pcall(A.progress, who, "wb_heal_top", 1) end
			if s.places.tanking == 1 then pcall(A.progress, who, "wb_tank_top", 1) end
			if s.places.healing or s.places.tanking then pcall(A.progress, who, "wb_role_podium", 1) end
		end
	end
	for _, r in ipairs(rewards) do
		local player = Player(r.name)
		if player and player:getGuid() == r.guid then
			if r.pityRolled and CQ and CQ.pityRecord then
				-- a set piece of the pool resets the "set" group, any other boss unique the "boss" group
				local e = r.unique and ChaosUniqueById and ChaosUniqueById[r.unique]
				CQ.pityRecord(player, "boss", r.unique ~= nil and not (e and e.set), r.unique)
				if e and e.set then
					CQ.pityRecord(player, "set", true, r.unique)
				end
			end
			W.deliver(player, r)
			-- exclusives.lua: the rare personal drop of a visual exclusive (rewarded players online at the kill)
			if ChaosExclusives and ChaosExclusives.worldBossKill then pcall(ChaosExclusives.worldBossKill, player, boss.name) end
		else
			W.pending[r.guid] = W.pending[r.guid] or {}
			table.insert(W.pending[r.guid], r)
		end
	end
	-- the ones who fought but get nothing are told why
	local got = {}
	for _, s in ipairs(shares) do
		got[s.guid] = true
	end
	for guid, e in pairs(state.stats or {}) do
		local player = Player(e.name)
		if player and player:getGuid() == guid and not got[guid] then
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, excluded[guid]
				and Chaos.t(player, "No world boss reward: another character from your connection was online during the fight.")
				or Chaos.t(player, "No world boss reward: you need a contribution (damage, healing and tanking) of at least %.2f%% of the boss health.", minPercent))
		end
	end
	return shares, total, podium
end

-- ======================================================================== event flow
local function sendBossInfo(boss, players)
	if not (Chaos.send and ChaosOpcodes and ChaosOpcodes.monsterbar) then
		return
	end
	for _, p in ipairs(players) do
		if W.inArena(p:getPosition()) then
			Chaos.send(p, ChaosOpcodes.monsterbar, "info", {cid = boss:getId(), tier = "boss", name = boss:getName(), mods = {}})
		end
	end
end

local function randomNear(center, radius)
	local L = W.layout()
	for _ = 1, 10 do
		local x = center.x + math.random(-radius, radius)
		local y = center.y + math.random(-radius, radius)
		if x > L.arena.x1 and x < L.arena.x2 and y > L.arena.y1 and y < L.arena.y2 then
			return Position(x, y, L.z)
		end
	end
	return P(L.bossSpawn)
end

local function runPhase(token, i)
	if state.token ~= token or state.phase ~= "fight" then
		return
	end
	local boss = Monster(state.bossId)
	local b = bossCfg()
	local phase = b.phases[i]
	if not boss or not phase then
		return
	end
	if phase.yell then
		boss:say(phase.yell, TALKTYPE_MONSTER_YELL)
	end
	if phase.adds and MonsterType(phase.adds.name) then
		local pos = boss:getPosition()
		for _ = 1, phase.adds.count do
			local m = Game.createMonster(phase.adds.name, randomNear(pos, 4), false, true)
			if m then
				if phase.adds.health then
					m:setMaxHealth(phase.adds.health)
					Chaos.heal(m, phase.adds.health)
				end
				state.adds[m:getId()] = true
				packFx(m:getPosition(), "wb_adds", CONST_ME_TELEPORT)
			end
		end
	end
	if phase.enrage then
		state.enraged = true
		state.nextPulse = os.time() + (b.pulse and b.pulse.every or 8)
		packFx(boss:getPosition(), "wb_enrage", CONST_ME_MAGIC_RED)
	end
end

local function pulse(boss, b)
	local p = b.pulse
	if not p then
		return
	end
	local pos = boss:getPosition()
	local effect = effectOf(p.effect)
	pos:sendMagicEffect(effect)
	local hits = 0
	for _, target in ipairs(Game.getSpectators(pos, false, true, p.radius, p.radius, p.radius, p.radius)) do
		if W.inArena(target:getPosition()) then
			doTargetCombatHealth(boss, target, combatOf(p.type), -p.min, -p.max, effect)
			hits = hits + 1
		end
	end
	if p.healPerHit and hits > 0 then
		Chaos.heal(boss, p.healPerHit * hits)
	end
end

local function tick(token)
	if state.token ~= token or state.phase == "idle" then
		return
	end
	local inside = playersInside()
	for _, p in ipairs(inside) do
		if Chaos.isMultiClient and Chaos.isMultiClient(p) then
			state.mc[p:getGuid()] = true
		end
		W.watchPlayer(p)
	end
	local boss = state.bossId and Monster(state.bossId)
	if boss and state.phase == "fight" then
		sendBossInfo(boss, inside)
		if ChaosInstanceLimits and state.fightEnd then -- warnings before the boss withdraws (instance_limits.lua)
			ChaosInstanceLimits.warn(state, state.fightEnd - os.time(), inside, bossCfg().name, C().limits)
		end
		if state.enraged and os.time() >= (state.nextPulse or 0) then
			local b = bossCfg()
			pulse(boss, b)
			state.nextPulse = os.time() + (b.pulse and b.pulse.every or 8)
		end
	end
	addEvent(tick, 3000, token)
end

local finish

local function spawnBoss(token)
	if state.token ~= token or state.phase ~= "gather" then
		return
	end
	local b = bossCfg()
	local L = W.layout()
	local boss = Game.createMonster(b.name, P(L.bossSpawn), false, true)
	if not boss then
		announce("The world boss could not appear. The event is cancelled.", true)
		finish(false, "spawn failed")
		return
	end
	-- boss mechanics (boss_mechanics.lua): telegraphs, adds phases, blasts behind the pillars; the health factor that
	-- keeps the kill time is applied here, before the fight reads the boss's max health
	if ChaosBossMech and ChaosBossMech.attach then
		local floor = {}
		local skip = {}
		for _, t in ipairs(L.pillars) do
			skip[t.x .. "," .. t.y] = true
		end
		for _, t in ipairs(L.basins) do
			skip[t.x .. "," .. t.y] = true
		end
		for y = L.arena.y1 + 1, L.arena.y2 - 1 do
			for x = L.arena.x1 + 1, L.arena.x2 - 1 do
				if not skip[x .. "," .. y] then
					floor[#floor + 1] = {x = x, y = y, z = L.z}
				end
			end
		end
		pcall(ChaosBossMech.attach, boss, nil, {tiles = floor, players = playersInside, pillars = L.pillars})
	end
	state.bossId = boss:getId()
	state.maxHealth = boss:getMaxHealth()
	state.phase = "fight"
	state.fightStart = os.time()
	state.fightEnd = os.time() + C().fightMinutes * 60
	boss:registerEvent("ChaosWorldBossHealth")
	boss:registerEvent("ChaosWorldBossDeath")
	packFx(boss:getPosition(), "wb_arrives", CONST_ME_MORTAREA)
	boss:say(b.intro, TALKTYPE_MONSTER_YELL)
	announce(ChaosI18n.msg("%s has appeared in the world boss arena! You have %d minutes to bring it down.", b.name, C().fightMinutes), true)
	addEvent(function(t)
		if state.token == t and state.phase == "fight" then
			finish(false, "time")
		end
	end, C().fightMinutes * 60 * 1000, token)
end

local function closeOut(token)
	if state.token ~= token then
		return
	end
	for _, p in ipairs(playersInside()) do
		p:teleportTo(p:getTown():getTemplePosition())
		p:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
	end
	cleanArena()
	W.state = {phase = "idle", token = token + 1}
	state = W.state
	W.nextAt = C().enabled and W.nextStart(os.time()) or nil
end

-- victory = true when the boss died. reason: "kill", "time", "stop", "spawn failed"
finish = function(victory, reason)
	if state.phase == "idle" or state.phase == "ending" then
		return false
	end
	local b = bossCfg()
	state.phase = "ending"
	state.token = state.token + 1
	local token = state.token
	closePortals()
	for id in pairs(state.adds or {}) do
		local m = Monster(id)
		if m then
			m:getPosition():sendMagicEffect(CONST_ME_POFF)
			m:remove()
		end
	end
	local delay = C().exitDelaySeconds
	if victory then
		local shares, _, podium = distribute()
		local secs = os.time() - (state.fightStart or os.time())
		state.result = podium
		announce(ChaosI18n.msg("%s has been slain by %d champion(s) in %dm %02ds! %s Everyone inside returns home in %d seconds.",
			b.name, #shares, math.floor(secs / 60), secs % 60, W.podiumText(podium, C().reward.podium), delay), false)
		-- the client toast has room for about two lines: one toast per category (it shows three at once)
		if ChaosNotify and ChaosNotify.gmBroadcast then
			for _, line in ipairs(W.podiumLines(podium, C().reward.podium)) do
				ChaosNotify.gmBroadcast(nil, "World boss slain! " .. line)
			end
		end
	else
		local boss = state.bossId and Monster(state.bossId)
		if boss then
			boss:say("You are not worthy of my death.", TALKTYPE_MONSTER_YELL)
			boss:getPosition():sendMagicEffect(CONST_ME_POFF)
			boss:remove()
		end
		if reason == "stop" then
			delay = math.min(delay, 10)
			announce("The world boss event was stopped by the staff.", true)
		elseif reason == "time" then
			announce(ChaosI18n.msg("%s was not defeated in time and withdraws. The world boss event is over.", b.name), true)
		end
	end
	addEvent(closeOut, delay * 1000, token)
	return true
end

-- index = boss index (nil = by mode). Returns true or false + reason.
function W.start(index)
	local c = C()
	if state.phase ~= "idle" then
		return false, "a world boss event is already running"
	end
	if not index then
		index = W.pickBoss(#c.bosses, c.mode, Game.getStorageValue(c.rotationStorage))
	end
	local b = c.bosses[index]
	if not b then
		return false, "unknown boss"
	end
	if not MonsterType(b.name) then
		return false, b.name .. " is not loaded (register world_bosses/*.xml in monsters.xml)"
	end
	local ok, err = W.buildArena()
	if not ok then
		return false, "arena not built: " .. err
	end
	Game.setStorageValue(c.rotationStorage, index)
	local token = state.token + 1
	W.state = {phase = "gather", token = token, index = index, stats = {}, debt = {}, active = {}, seq = 0, mc = {},
		adds = {}, phasesDone = {},
		startedAt = os.time(), spawnAt = os.time() + c.gatherSeconds, portalsUntil = os.time() + c.portalMinutes * 60}
	state = W.state
	local n = openPortals()
	announce(ChaosI18n.msg("WORLD BOSS: %s Portals are open next to the temples for %d minutes (level %d+). The boss appears in %d seconds.",
		ChaosI18n.msg(b.intro), c.portalMinutes, c.minLevel, c.gatherSeconds), true)
	if n == 0 then
		print("[Chaos world boss] no portal spot found (Game.getTowns / portalPositions)")
	end
	addEvent(spawnBoss, c.gatherSeconds * 1000, token)
	addEvent(function(t)
		if state.token == t and state.portalsOpen then
			closePortals()
			announce("The world boss portals have closed.", false)
		end
	end, c.portalMinutes * 60 * 1000, token)
	addEvent(tick, 3000, token)
	return true
end

function W.stop()
	return finish(false, "stop")
end

function W.status()
	local c = C()
	if state.phase == "idle" then
		local nextAt = W.nextAt
		if c.enabled and nextAt then
			local b = c.bosses[W.pickBoss(#c.bosses, c.mode, Game.getStorageValue(c.rotationStorage))]
			return string.format("No world boss is active. Next one at %s%s.", os.date("%H:%M", nextAt),
				c.mode == "rotation" and (": " .. b.name) or "")
		end
		return "No world boss is active."
	end
	local b = bossCfg()
	if state.phase == "gather" then
		return string.format("%s appears in %d seconds. Portals are next to the temples.", b.name, math.max(0, state.spawnAt - os.time()))
	elseif state.phase == "fight" then
		local boss = Monster(state.bossId)
		local pct = boss and math.floor(boss:getHealth() * 100 / boss:getMaxHealth()) or 0
		return string.format("%s is fighting (%d%% health, %d minutes left).%s", b.name, pct,
			math.max(0, math.ceil((state.fightEnd - os.time()) / 60)), state.portalsOpen and " Portals are open." or "")
	end
	return "The world boss event is ending."
end

-- ======================================================================== role tracking
-- state.stats[guid] = {name, damage, healing, tanking, deaths, seq = {[key] = n}}: seq is a running counter taken
-- when the value last went up (ties in the top 3: who reached the value first).
-- state.debt[guid] = boss damage the player took and was not healed for yet (caps the healing credit of others).
-- state.active[guid] = os.time of the player's last attack on the boss or an add, or last heal on another player.
local function statsOf(player)
	local guid = player:getGuid()
	local e = state.stats[guid]
	if not e then
		e = {name = player:getName(), damage = 0, healing = 0, tanking = 0, deaths = 0, seq = {}}
		state.stats[guid] = e
	end
	return e
end

function W.credit(player, key, amount)
	if not amount or amount <= 0 then
		return
	end
	local e = statsOf(player)
	e[key] = e[key] + amount
	state.seq = (state.seq or 0) + 1
	e.seq[key] = state.seq
	if key ~= "tanking" then
		state.active[player:getGuid()] = os.time()
	end
end

-- the player attacked the boss or an add (EventCallback onTargetCombat below)
function W.markActive(player)
	if state.phase == "fight" and state.active then
		state.active[player:getGuid()] = os.time()
	end
end

local function bossSource(creature)
	if not creature then
		return false
	end
	local id = creature:getId()
	return id == state.bossId or (state.adds and state.adds[id]) or false
end

-- onHealthChange of a player inside the arena while the boss is alive (registered on everyone inside)
function W.onPlayerHealth(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType)
	if state.phase ~= "fight" or not W.inArena(creature:getPosition()) then
		return
	end
	local ro = C().roles
	local guid = creature:getGuid()
	local health, maxHealth = creature:getHealth(), creature:getMaxHealth()
	if health <= 0 then
		return
	end
	if primaryType == COMBAT_HEALING then
		local healer = playerOf(attacker)
		local self = healer and healer:getId() == creature:getId() or false
		local credit, eff = W.healCredit(math.abs(primaryDamage), maxHealth - health, state.debt[guid], self, ro)
		state.debt[guid] = math.max(0, (state.debt[guid] or 0) - eff)
		if healer and credit > 0 and W.inArena(healer:getPosition()) then
			W.credit(healer, "healing", credit)
		end
		return
	end
	if not bossSource(attacker) then
		return
	end
	local dmg = math.abs(primaryDamage) + (secondaryType ~= COMBAT_HEALING and math.abs(secondaryDamage or 0) or 0)
	state.debt[guid] = (state.debt[guid] or 0) + math.min(dmg, health)
	-- tanking only counts for players who fight (attacked the boss or an add, or healed someone) within activeSeconds
	local last = state.active[guid]
	if not last or os.time() - last > (ro.activeSeconds or 30) then
		return
	end
	local target = attacker.getTarget and attacker:getTarget()
	local targeted = target and target:getId() == creature:getId() or false
	W.credit(creature, "tanking", W.tankCredit(dmg, health, targeted, ro))
end

-- ======================================================================== engine hooks
local roleHealth = CreatureEvent("ChaosWorldBossRoles")
function roleHealth.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if state.phase == "fight" and creature:isPlayer() then
		local ok, err = pcall(W.onPlayerHealth, creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType)
		if not ok then
			print("[Chaos world boss] role tracking: " .. tostring(err))
		end
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
roleHealth:register()

-- a death keeps what was earned; the dead player is out of the arena until they come back through the portals
local roleDeath = CreatureEvent("ChaosWorldBossRoleDeath")
function roleDeath.onDeath(creature)
	if state.phase == "fight" and creature:isPlayer() and W.inArena(creature:getPosition()) then
		local e = statsOf(creature)
		e.deaths = e.deaths + 1
		state.debt[creature:getGuid()] = 0
		state.active[creature:getGuid()] = nil
	end
	return true
end
roleDeath:register()

function W.watchPlayer(p)
	p:registerEvent("ChaosWorldBossRoles")
	p:registerEvent("ChaosWorldBossRoleDeath")
end

local health = CreatureEvent("ChaosWorldBossHealth")
function health.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if state.phase == "fight" and creature:getId() == state.bossId and primaryType ~= COMBAT_HEALING then
		local dmg = math.abs(primaryDamage) + (secondaryType ~= COMBAT_HEALING and math.abs(secondaryDamage) or 0)
		dmg = math.min(dmg, creature:getHealth())
		local player = playerOf(attacker)
		if player and dmg > 0 then
			W.credit(player, "damage", dmg)
		end
		local b = bossCfg()
		local fraction = (creature:getHealth() - dmg) / creature:getMaxHealth()
		for _, i in ipairs(W.duePhases(b.phases, state.phasesDone, fraction)) do
			state.phasesDone[i] = true
			addEvent(runPhase, 100, state.token, i)
		end
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
health:register()

local death = CreatureEvent("ChaosWorldBossDeath")
function death.onDeath(creature, corpse, killer, mostDamageKiller)
	if creature:getId() == state.bossId and state.phase == "fight" then
		finish(true, "kill")
	end
	return true
end
death:register()

local login = CreatureEvent("ChaosWorldBossLogin")
function login.onLogin(player)
	local guid = player:getGuid()
	local list = W.pending[guid]
	if list then
		W.pending[guid] = nil
		addEvent(function(name, rewards)
			local p = Player(name)
			if p then
				for _, r in ipairs(rewards) do
					W.deliver(p, r)
				end
			else
				W.pending[guid] = rewards
			end
		end, 2000, player:getName(), list)
	end
	if state.phase == "idle" and W.inside(player:getPosition()) then
		player:teleportTo(player:getTown():getTemplePosition())
	end
	return true
end
login:register()

-- no PvP in arena and lobby, no combat at all against players in the lobby
-- the guard runs for every attack on a player (every monster hit): the layout is built once per arena config, not per call
local guardL, guardA, guardSig
local function guardLayout()
	local a = C().arena
	local o = a.origin
	local sig = guardSig
	if not guardL or guardA ~= a or sig[1] ~= o.x or sig[2] ~= o.y or sig[3] ~= o.z or sig[4] ~= a.inner
			or sig[5] ~= a.lobbyGap or sig[6] ~= a.lobbyInnerW or sig[7] ~= a.lobbyInnerH then
		guardL, guardA = W.layout(a), a
		guardSig = {o.x, o.y, o.z, a.inner, a.lobbyGap, a.lobbyInnerW, a.lobbyInnerH}
	end
	return guardL
end

local guard = EventCallback
guard.onTargetCombat = function(creature, target)
	if not creature or not target then
		return RETURNVALUE_NOERROR
	end
	if not target:isPlayer() then
		local attacker = state.phase == "fight" and bossSource(target) and playerOf(creature)
		if attacker then
			W.markActive(attacker)
		end
		return RETURNVALUE_NOERROR
	end
	local L = guardLayout()
	local tpos = target:getPosition()
	if not W.inside(tpos, L) then
		return RETURNVALUE_NOERROR
	end
	if W.inLobby(tpos, L) or W.inLobby(creature:getPosition(), L) then
		return RETURNVALUE_ACTIONNOTPERMITTEDINPROTECTIONZONE
	end
	if not C().allowPvp and playerOf(creature) and playerOf(creature) ~= target then
		return RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER
	end
	return RETURNVALUE_NOERROR
end
guard:register()

-- forcefields
local function pushBack(player, fromPosition, text)
	player:sendCancelMessage(Chaos.t(player, text))
	player:teleportTo(fromPosition, true)
end

local function open()
	return state.phase == "gather" or state.phase == "fight"
end

local enter = MoveEvent()
function enter.onStepIn(creature, item, position, fromPosition)
	local player = creature:getPlayer()
	if not player then
		return true
	end
	local c = C()
	if not open() or not state.portalsOpen then
		pushBack(player, fromPosition, "The world boss portal is closed.")
		return true
	end
	if player:getLevel() < c.minLevel then
		pushBack(player, fromPosition, ChaosI18n.msg("You need level %d to face the world boss.", c.minLevel))
		return true
	end
	if c.maxPlayers > 0 and #playersInside() >= c.maxPlayers then
		pushBack(player, fromPosition, "The world boss arena is full.")
		return true
	end
	if Chaos.isMultiClient and Chaos.isMultiClient(player) then
		state.mc[player:getGuid()] = true
		if not c.mcReward then
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE,
				Chaos.t(player, "Another character from your connection is online: you may fight, but you will get no world boss reward."))
		end
	end
	player:teleportTo(P(W.layout().lobbyArrival))
	player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "World boss lobby: the forcefield to the north leads to the arena, the ones on the sides take you home. %s", W.status()))
	return true
end
enter:type("stepin")
enter:aid(Chaos.worldBoss.aid.enter)
enter:register()

local toArena = MoveEvent()
function toArena.onStepIn(creature, item, position, fromPosition)
	local player = creature:getPlayer()
	if not player then
		return true
	end
	if not open() then
		pushBack(player, fromPosition, "There is no fight in the arena right now.")
		return true
	end
	W.watchPlayer(player)
	player:teleportTo(P(W.layout().arenaEntry))
	player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
	return true
end
toArena:type("stepin")
toArena:aid(Chaos.worldBoss.aid.arena)
toArena:register()

local toLobby = MoveEvent()
function toLobby.onStepIn(creature, item, position, fromPosition)
	local player = creature:getPlayer()
	if not player then
		return true
	end
	player:teleportTo(P(W.layout().lobbyArrival))
	player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
	return true
end
toLobby:type("stepin")
toLobby:aid(Chaos.worldBoss.aid.lobby)
toLobby:register()

local exit = MoveEvent()
function exit.onStepIn(creature, item, position, fromPosition)
	local player = creature:getPlayer()
	if not player then
		return true
	end
	player:teleportTo(player:getTown():getTemplePosition())
	player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
	return true
end
exit:type("stepin")
exit:aid(Chaos.worldBoss.aid.exit)
exit:register()

-- schedule
local warned = {}
local schedule = GlobalEvent("ChaosWorldBossSchedule")
function schedule.onThink(interval)
	local c = C()
	if not c.enabled then
		return true
	end
	local now = os.time()
	W.nextAt = W.nextAt or W.nextStart(now)
	if state.phase ~= "idle" then
		return true
	end
	for _, m in ipairs(c.warnMinutes or {}) do
		local key = W.nextAt .. ":" .. m
		if not warned[key] and now >= W.nextAt - m * 60 and now < W.nextAt then
			warned[key] = true
			local b = c.bosses[W.pickBoss(#c.bosses, c.mode, Game.getStorageValue(c.rotationStorage))]
			announce(ChaosI18n.msg("A world boss awakens in %d minute(s)%s! Portals will open next to the temples.", m,
				c.mode == "rotation" and (": " .. b.name) or ""), m == (c.warnMinutes or {})[1])
		end
	end
	if now >= W.nextAt then
		W.nextAt = W.nextStart(now)
		local ok, err = W.start()
		if not ok then
			print("[Chaos world boss] scheduled start failed: " .. tostring(err))
		end
	end
	return true
end
schedule:interval(30000)
schedule:register()

-- commands
local gm = TalkAction("/worldboss")
function gm.onSay(player, words, param)
	if not player:getGroup():getAccess() then
		return true
	end
	local cmd, arg = param:match("^%s*(%S*)%s*(.-)%s*$")
	cmd = (cmd or ""):lower()
	if cmd == "start" then
		local index = W.findBoss(arg)
		if index == false then
			player:sendCancelMessage("Unknown boss. Bosses: " .. (function()
				local names = {}
				for i, b in ipairs(C().bosses) do
					names[#names + 1] = i .. " " .. b.name
				end
				return table.concat(names, ", ")
			end)())
			return false
		end
		if index == nil and arg:lower() == "random" then
			index = W.pickBoss(#C().bosses, "random", Game.getStorageValue(C().rotationStorage))
		end
		local ok, err = W.start(index)
		player:sendTextMessage(MESSAGE_INFO_DESCR, ok and "World boss event started." or ("Not started: " .. tostring(err)))
	elseif cmd == "stop" then
		player:sendTextMessage(MESSAGE_INFO_DESCR, W.stop() and "World boss event stopped." or "No world boss event is running.")
	elseif cmd == "arena" then
		-- builds the arena if needed (check the footprint without starting an event) and takes you to the lobby
		local ok, err = W.buildArena()
		if not ok then
			player:sendCancelMessage("Arena not built: " .. tostring(err))
			return false
		end
		player:teleportTo(P(W.layout().lobbyArrival))
	else
		player:sendTextMessage(MESSAGE_INFO_DESCR, W.status() .. "\nUsage: /worldboss start [name|number|random], /worldboss stop, /worldboss arena")
	end
	return false
end
gm:separator(" ")
gm:register()

local info = {} -- reached from the menu: Info & Services window (commands_ui.lua, id "worldboss")
function info.onSay(player, words, param)
	player:sendTextMessage(MESSAGE_INFO_DESCR, W.status())
	return false
end
ChaosCommands.register("worldboss", function(player, param) return info.onSay(player, "", param) end)

local startup = GlobalEvent("ChaosWorldBossStartup")
function startup.onStartup()
	W.nextAt = C().enabled and W.nextStart(os.time()) or nil
	W.registerTitles() -- titles.lua may load after this file
	return true
end
startup:register()
