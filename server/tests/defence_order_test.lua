-- Run from the server/ folder: luajit tests/defence_order_test.lua (CI runs it with LuaJIT and Lua 5.3)
--   luajit tests/defence_order_test.lua --list   prints the player's healthchange events in the order the engine runs them
-- Monster defence (O462): the damage multipliers a monster's hit gets (the late-game boost, the rift run's multipliers, the
-- rank multiplier) reach the player BEFORE every reduction of the player, so that a hit-size armour sees the real hit.
--
-- How the order is decided (engine, creatureevent.cpp and creature.cpp, read 2026-11-10): the server runs the login events
-- of CreatureEvents::playerLogin in the order of a std::map keyed by the event's NAME (byte order), and each one calls
-- player:registerEvent for its healthchange events; Creature::registerCreatureEvent appends to the creature's event list;
-- Creature::getCreatureEvents hands the list over in that order. So the player's events run in the order of
-- (login event name, position of the registerEvent call in its onLogin). An event registered later (not at login) is last.
-- This test reads the Lua sources the same way and lists that order.
local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end

local function files()
	local out = {}
	local p = assert(io.popen("find data -name '*.lua'"))
	for line in p:lines() do
		out[#out + 1] = line
	end
	p:close()
	table.sort(out)
	return out
end

local healthEvents = {} -- event name -> file
local logins = {} -- login event name -> {file, {registered names in order}}
for _, path in ipairs(files()) do
	local f = io.open(path, "rb")
	local text = f:read("*a")
	f:close()
	if text:find("onHealthChange", 1, true) or text:find("onLogin", 1, true) then
		local var2name = {}
		local current -- the login function being read: its login event name
		for line in (text .. "\n"):gmatch("(.-)\r?\n") do
			local v, name = line:match('^%s*local%s+([%w_]+)%s*=%s*CreatureEvent%("([^"]+)"%)')
			if v then
				var2name[v] = name
			end
			local hv = line:match("^%s*function%s+([%w_]+)%.onHealthChange")
			if hv and var2name[hv] then
				healthEvents[var2name[hv]] = path
			end
			local lv = line:match("^%s*function%s+([%w_]+)%.onLogin")
			if lv and var2name[lv] then
				current = {name = var2name[lv], file = path, regs = {}}
				logins[current.name] = current
			elseif current then
				if line:match("^end") then
					current = nil
				else
					for reg in line:gmatch('registerEvent%("([^"]+)"%)') do
						current.regs[#current.regs + 1] = reg
					end
				end
			end
		end
	end
end

local names = {}
for name in pairs(logins) do
	names[#names + 1] = name
end
table.sort(names)
local order = {}
for _, login in ipairs(names) do
	for _, reg in ipairs(logins[login].regs) do
		if healthEvents[reg] then
			order[#order + 1] = {event = reg, login = login}
		end
	end
end

if arg and arg[1] == "--list" then
	for i, e in ipairs(order) do
		print(string.format("%2d  %-34s %s", i, e.event, e.login))
	end
	return
end

ok(#order > 25, "the scan finds the player's healthchange events: " .. #order)
local position = {}
for i, e in ipairs(order) do
	position[e.event] = i
end

-- the three multipliers come first, in this order
local FIRST = {"ChaosMonsterDamageHealth", "ChaosRiftPlayerHit", "ChaosTierHit"}
for i, name in ipairs(FIRST) do
	ok(position[name] == i, name .. " is the player's healthchange event number " .. i .. " (it is " .. tostring(position[name]) .. ")")
end
-- ... and everything else that changes a hit comes after them
for _, e in ipairs(order) do
	local isFirst = false
	for _, name in ipairs(FIRST) do
		isFirst = isFirst or e.event == name
	end
	if not isFirst then
		ok(position[e.event] > #FIRST, e.event .. " runs after the damage multipliers")
	end
end
-- the reductions the audit named run after
for _, name in ipairs({"ChaosItemModsTaken", "ChaosBlessingsTaken", "ChaosCharmsTaken", "ChaosGemsTaken", "ChaosItemSetsTaken",
		"ChaosKeystones", "ChaosPowersTaken", "ChaosSupportsHit"}) do
	ok(position[name] ~= nil and position[name] > position.ChaosTierHit, name .. " is behind the rank multiplier")
end
-- the names carry the order: "Chaos0..." logins sort before every other Chaos login
for _, name in ipairs({"Chaos0MonsterDamageLogin", "Chaos0RiftHitLogin", "Chaos0TierLogin"}) do
	ok(logins[name] ~= nil, "the login event " .. name .. " exists")
end
ok("Chaos0MonsterDamageLogin" < "Chaos0RiftHitLogin" and "Chaos0RiftHitLogin" < "Chaos0TierLogin" and "Chaos0TierLogin" < "Chaos1ManaShieldLogin"
	and "Chaos1ManaShieldLogin" < "ChaosAntibotLogin", "byte order of the login names")
print(string.format("defence order tests: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end
