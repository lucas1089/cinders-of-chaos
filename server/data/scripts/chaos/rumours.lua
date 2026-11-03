-- Tavern rumours (O394): the spawner of the rare appearances that the rumour NPC (Dorrin Alewright, a service NPC of
-- service_npcs_config.lua; dialogue in data/npc/scripts/chaos_service_npc.lua, engine side rumours_run.lua) hints at.
-- The plan is rumours_core.lua R.planHour: one appearance in some hours, decided by the hour and the config alone,
-- so the NPC (its own Lua state) and this file name the same monster, place and minute. The other rumours (the
-- invasions, the world boss) are about what invasion.lua and worldboss.lua already pre-roll; nothing is spawned here
-- for them. Settings: rumours_config.lua. server/README.md "Tavern rumours (O394)".
-- Staff: /rumours (what the keeper knows now, the planned appearances), /rumours spawn (the next planned appearance,
-- now). No player talkaction, no opcode, no storage key, no table. Lua 5.1 / LuaJIT and 5.3.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosRumoursRun then
	dofile("data/scripts/chaos/rumours_run.lua")
end

ChaosRumours = ChaosRumours or {}
local S = ChaosRumours
local R = ChaosRumoursCore
local M = ChaosRumoursRun

S.done = S.done or {} -- appearance key -> true (spawned or given up)

local function log(text)
	print("[Chaos rumours] " .. text)
end

local function onlineCount()
	local n = 0
	for _, p in ipairs(Game.getPlayers()) do
		if not (Chaos.isTester and Chaos.isTester(p)) then
			n = n + 1
		end
	end
	return n
end

-- a free spawn tile around the region's point: the ring offsets of R.lcg(key) in order, the first tile that
-- ChaosInvasion.tileOk accepts (walkable, no protection zone, house, water, teleport; no creature on it)
function S.spot(plan)
	local a = M.cfg.apparitions or {}
	local r1, r2 = (a.radius or {})[1] or 6, (a.radius or {})[2] or 18
	local p = plan.region.point
	local rng = R.lcg(plan.at)
	for _ = 1, 160 do
		local dx, dy = rng(-r2, r2), rng(-r2, r2)
		if math.max(math.abs(dx), math.abs(dy)) >= r1 then
			local pos = Position(p.x + dx, p.y + dy, p.z)
			local ok = false
			if ChaosInvasion and ChaosInvasion.tileOk then
				ok = ChaosInvasion.tileOk(pos, nil, false)
			else
				local tile = Tile(pos)
				ok = tile and tile:getGround() and not tile:hasFlag(TILESTATE_PROTECTIONZONE) and not tile:getHouse()
					and not tile:hasProperty(CONST_PROP_BLOCKSOLID) and tile:getCreatureCount() == 0
			end
			if ok then
				return pos
			end
		end
	end
	return nil
end

function S.spawn(plan)
	local pos = S.spot(plan)
	if not pos then
		log(string.format("%s at %s: no free tile near %d,%d,%d", plan.what, plan.place, plan.region.point.x,
			plan.region.point.y, plan.region.point.z))
		return nil
	end
	local m = plan.monster
	local monster
	if m.kind == "goblin" and ChaosTreasureGoblin and ChaosTreasureGoblin.spawn then
		monster = ChaosTreasureGoblin.spawn(pos, {variant = m.variant, level = plan.level})
	else
		monster = Game.createMonster(m.name, pos, true, false)
	end
	log(string.format("%s %s in %s at %d,%d,%d (level %d)", monster and "spawned" or "could not spawn", m.name,
		plan.place, pos.x, pos.y, pos.z, plan.level or 0))
	return monster
end

-- every check: the appearances whose minute has come (and not by more than graceSeconds)
function S.check(now)
	local a = M.cfg.apparitions or {}
	local grace = a.graceSeconds or 180
	for _, plan in ipairs(R.apparitions(M.cfg, now - grace, now, M.regions())) do
		if not S.done[plan.key] then
			S.done[plan.key] = true
			if onlineCount() >= (a.minOnline or 1) then
				S.spawn(plan)
			else
				log(plan.what .. " in " .. plan.place .. " skipped: too few players online")
			end
		end
	end
end

local think = GlobalEvent("ChaosRumoursSpawner")
function think.onThink(interval)
	if M.cfg.enabled and (M.cfg.sources or {}).apparition ~= false then
		local ok, err = pcall(S.check, os.time())
		if not ok then
			log("check: " .. tostring(err))
		end
	end
	return true
end
think:interval(15000)
think:register()

local startup = GlobalEvent("ChaosRumoursStartup")
function startup.onStartup()
	local regions = M.regions()
	log(#regions .. " region(s) for appearances" .. (#regions == 0 and " (none: only invasion and world boss rumours)" or ""))
	-- an appearance already past at the start is not made up for
	local now = os.time()
	for _, plan in ipairs(R.apparitions(M.cfg, now - 3 * 3600, now - ((M.cfg.apparitions or {}).graceSeconds or 180) - 1,
		regions)) do
		S.done[plan.key] = true
	end
	return true
end
startup:register()

-- ---------------------------------------------------------------- staff
local talk = TalkAction("/rumours")
function talk.onSay(player, words, param)
	if not player:getGroup():getAccess() then
		return false
	end
	if not Chaos.staffCommand(player, words, param, false) then
		return false
	end
	local now = os.time()
	local lines = {}
	if param:lower():find("spawn", 1, true) then
		local next_ = R.apparitions(M.cfg, now, now + 24 * 3600, M.regions())[1]
		if next_ then
			S.done[next_.key] = true
			local m = S.spawn(next_)
			lines[#lines + 1] = string.format("%s %s in %s (planned %s).", m and "Spawned" or "Could not spawn",
				next_.what, next_.place, os.date("%H:%M", next_.at))
		else
			lines[#lines + 1] = "No appearance planned in the next 24 hours (no regions?)."
		end
	else
		lines[#lines + 1] = string.format("Rumours %s; %d region(s).", M.cfg.enabled and "on" or "off", #M.regions())
		for _, c in ipairs(R.candidates(M.cfg, now, M.sources(now))) do
			lines[#lines + 1] = string.format("- %s %s: %s, %s", os.date("%H:%M", c.at), c.kind, tostring(c.what), tostring(c.place))
		end
		for _, plan in ipairs(R.apparitions(M.cfg, now, now + 6 * 3600, M.regions())) do
			lines[#lines + 1] = string.format("planned %s: %s in %s", os.date("%d/%m %H:%M", plan.at), plan.what, plan.place)
		end
	end
	player:sendTextMessage(MESSAGE_INFO_DESCR, table.concat(lines, "\n"))
	return false
end
talk:separator(" ")
talk:register()
