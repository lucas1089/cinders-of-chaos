-- TEST ONLY: never ship this file. It is not under server/data, so install_all.py never copies it.
-- Hunting for the load-test bots of server/tools/loadtest.py (run --hunt): the bots cannot pick a monster themselves
-- (they do not parse the map description), so this script does it on the server side:
--   * every bot (a character named "Loadbot ...") without a target gets the nearest monster within 5 tiles on its
--     floor as its attack target (Creature:setTarget, as the client's attack does); with chase on (--hunt) the bot
--     walks to it, and its random steps keep the hunt moving over the area;
--   * the bots never die: a bot below half health is set back to full at its check, and onPrepareDeath refuses a
--     death and sets the bot to full health. A lethal hit runs every prepare-death event of the Chaos systems (about
--     19, the death recap's among them): a cost a real player pays once per death. A bot left at 1 health would pay
--     it at every hit (measured: about 150 a second at 300 bots, game loop tasks up to 300 ms), so keep the bots
--     healed and in areas of their level (loadtest.py setup --spread, --area-level). Note: the base server's
--     creature:addHealth takes (type, value), so the script uses creature:setHealth;
--   * the bots are checked in 4 groups, one group every 500 ms (every bot once in 2 s), so the script itself is a few
--     small tasks and no stall; one console line a minute: [loadtest-hunt] t=<unix time> bots=<n> fighting=<n>.
-- Use: copy to <server>/data/scripts/zz_loadtest_hunt.lua with the probe (loadtest_probe.lua), restart, run the load
-- test with --hunt, then DELETE both copies and restart again.
local PREFIX = "Loadbot "
local GROUPS = 4
local STEP_MS = 500
local RANGE = 5

local bots = {} -- player id -> true

local function isBot(player)
	return player:getName():sub(1, #PREFIX) == PREFIX
end

local noDeath = CreatureEvent("LoadTestHuntNoDeath")
function noDeath.onPrepareDeath(creature, killer)
	creature:setHealth(creature:getMaxHealth())
	return false
end
noDeath:register()

local login = CreatureEvent("LoadTestHuntLogin")
function login.onLogin(player)
	if isBot(player) then
		player:registerEvent("LoadTestHuntNoDeath")
		bots[player:getId()] = true
	end
	return true
end
login:register()

local function nearestMonster(player)
	local pos = player:getPosition()
	local best, bestDist
	for _, c in ipairs(Game.getSpectators(pos, false, false, RANGE, RANGE, RANGE, RANGE)) do
		if c:isMonster() and not c:getMaster() and c:getHealth() > 0 then
			local p = c:getPosition()
			local d = math.max(math.abs(p.x - pos.x), math.abs(p.y - pos.y))
			if not bestDist or d < bestDist then
				best, bestDist = c, d
			end
		end
	end
	return best
end

local stats = {group = 0, since = 0, fighting = 0}

local function step()
	local g = stats.group
	stats.group = (g + 1) % GROUPS
	for id in pairs(bots) do
		if id % GROUPS == g then
			local player = Player(id)
			if not player then
				bots[id] = nil
			else
				if player:getHealth() * 2 < player:getMaxHealth() then
					player:setHealth(player:getMaxHealth())
				end
				if not player:getTarget() then
					local monster = nearestMonster(player)
					if monster then
						player:setTarget(monster)
					end
				end
			end
		end
	end
	if os.time() - stats.since >= 60 then
		local n, fighting = 0, 0
		for id in pairs(bots) do
			local player = Player(id)
			if player then
				n = n + 1
				if player:getTarget() then
					fighting = fighting + 1
				end
			end
		end
		print(string.format("[loadtest-hunt] t=%d bots=%d fighting=%d", os.time(), n, fighting))
		stats.since = os.time()
	end
	addEvent(step, STEP_MS)
end

local start = GlobalEvent("ChaosLoadTestHunt")
function start.onStartup()
	stats.since = os.time()
	addEvent(step, STEP_MS)
	print("[loadtest-hunt] running (TEST ONLY, remove data/scripts/zz_loadtest_hunt.lua before going live)")
	return true
end
start:register()
