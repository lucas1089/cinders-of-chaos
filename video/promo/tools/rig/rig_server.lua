-- TEST ONLY: the trailer rig's server hook (video/promo/README.md "Live rig"). Never install it on a real server.
-- rig.sh copies it to SERVER_DIR/data/scripts/zz_rig_test.lua of a scratch server and starts the engine with
-- CHAOS_RIG_QUEUE set; without that variable the file does nothing.
--  * runs the Lua in $CHAOS_RIG_QUEUE/cmd.lua whenever the file changes, the result goes to out.log (rig.sh sx)
--  * the rig characters (RigChars) take 2% of each hit, never die and are healed and refilled every 250 ms,
--    so a take is never cut short; their spell cooldowns are cleared every second while RigCdAuto is true
local Q = os.getenv("CHAOS_RIG_QUEUE")
if not Q or Q == "" then
	return
end
RigChars = RigChars or {["Ilsabet"] = true, ["Haldric"] = true, ["Sorenne"] = true, ["Ysolde"] = true}
RigCdAuto = RigCdAuto == nil and true or RigCdAuto
RigDmgScale = RigDmgScale or 0.02

local function out(s)
	local f = io.open(Q .. "/out.log", "a")
	if f then
		f:write(s .. "\n")
		f:close()
	end
end

local last = ""
local exec = GlobalEvent("RigExec")
function exec.onThink(interval)
	local f = io.open(Q .. "/cmd.lua", "r")
	if not f then
		return true
	end
	local c = f:read("*a")
	f:close()
	if c ~= "" and c ~= last then
		last = c
		local fn, err = loadstring(c)
		if not fn then
			out("compile: " .. tostring(err))
		else
			local ok, res = pcall(fn)
			out(os.date("%H:%M:%S ") .. (ok and "ok: " or "ERROR: ") .. tostring(res))
		end
	end
	return true
end
exec:interval(250)
exec:register()

local shield = CreatureEvent("RigShield")
function shield.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if creature:isPlayer() and primaryType ~= COMBAT_HEALING then
		local sign = (primaryDamage < 0 or secondaryDamage < 0) and -1 or 1
		local p = math.floor(math.abs(primaryDamage) * RigDmgScale)
		local q = math.floor(math.abs(secondaryDamage) * RigDmgScale)
		local keep = math.max(0, creature:getHealth() - 1)
		if p + q > keep then
			p, q = math.min(p, keep), math.max(0, keep - p)
		end
		primaryDamage, secondaryDamage = sign * p, sign * q
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
shield:type("healthchange")
shield:register()

local noDeath = CreatureEvent("RigNoDeath")
function noDeath.onPrepareDeath(creature, killer)
	addEvent(function(cid)
		local p = Player(cid)
		if p then
			p:setHealth(p:getMaxHealth())
		end
	end, 1, creature:getId())
	return false
end
noDeath:register()

local login = CreatureEvent("RigLogin")
function login.onLogin(player)
	if RigChars[player:getName()] then
		player:registerEvent("RigNoDeath")
		addEvent(function(cid)
			local p = Player(cid)
			if p then
				p:registerEvent("RigShield")
			end
		end, 3000, player:getId())
	end
	return true
end
login:register()

function RigCd(p)
	for id = 1, 400 do
		p:removeCondition(CONDITION_SPELLCOOLDOWN, CONDITIONID_DEFAULT, id)
	end
	for g = 1, 8 do
		p:removeCondition(CONDITION_SPELLGROUPCOOLDOWN, CONDITIONID_DEFAULT, g)
	end
end

-- the dungeon and rift queues refuse a player in a fight: end the in-fight condition at once
function RigPeace(p)
	p:removeCondition(CONDITION_INFIGHT, CONDITIONID_DEFAULT, 0, true)
	local c = Condition(CONDITION_INFIGHT)
	c:setParameter(CONDITION_PARAM_TICKS, 50)
	p:addCondition(c)
end

local heal = GlobalEvent("RigHeal")
function heal.onThink(interval)
	for _, p in ipairs(Game.getPlayers()) do
		if RigChars[p:getName()] and p:getHealth() > 0 then
			p:setHealth(p:getMaxHealth())
			p:addMana(p:getMaxMana())
		end
	end
	return true
end
heal:interval(250)
heal:register()

local cd = GlobalEvent("RigCooldowns")
function cd.onThink(interval)
	if RigCdAuto then
		for _, p in ipairs(Game.getPlayers()) do
			if RigChars[p:getName()] then
				RigCd(p)
			end
		end
	end
	return true
end
cd:interval(1000)
cd:register()
