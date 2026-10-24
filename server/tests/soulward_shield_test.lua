-- Run from the server/ folder: luajit tests/soulward_shield_test.lua (and lua5.3; CI runs both)
-- O162: Soulward put CONDITION_MANASHIELD on the player with a sub id (the buff bar's marker, 71006). The engine asks
-- hasCondition(CONDITION_MANASHIELD) with sub id 0 (Game::combatChangeHealth), so that condition shielded nothing: a
-- monster hit went straight to the health. Test: the spell script on a mocked engine (hasCondition as the engine does
-- it: type AND sub id), the shield the engine sees, the marker the buff bar reads, and the buff bar's rows.
local count, failures = 0, 0
local function eq(a, b, what)
	count = count + 1
	if a ~= b then
		failures = failures + 1
		print("FAIL " .. tostring(what) .. ": " .. tostring(a) .. " ~= " .. tostring(b))
	end
end

CONDITION_MANASHIELD, CONDITION_REGENERATION = 4, 5
CONDITION_PARAM_SUBID, CONDITION_PARAM_TICKS, CONDITION_PARAM_MANAGAIN, CONDITION_PARAM_MANATICKS = 1, 2, 3, 4
CONST_ME_MAGIC_BLUE, CONDITIONID_COMBAT = 1, 1
ChaosSpell = {SUBID = {soul_aegis = 71006}, vfxOr = function() end}
local realDofile = dofile
function dofile(path) -- the spell loads its common file; the test needs only ChaosSpell above
	if path:find("_common.lua", 1, true) then
		return
	end
	return realDofile(path)
end
function Condition(ctype)
	local c = {type = ctype, sub = 0, ticks = 0}
	function c:setParameter(k, v)
		if k == CONDITION_PARAM_SUBID then self.sub = v elseif k == CONDITION_PARAM_TICKS then self.ticks = v end
	end
	return c
end

local player = {conds = {}}
function player:getPlayer() return self end
function player:getLevel() return 230 end
function player:getPosition() return {} end
function player:addCondition(c)
	for _, o in ipairs(self.conds) do
		if o.type == c.type and o.sub == c.sub then
			if c.ticks > o.ticks then o.ticks = c.ticks end -- the engine keeps the longer time
			return true
		end
	end
	self.conds[#self.conds + 1] = c
	return true
end
-- the engine's Creature::hasCondition(type, subId = 0)
function player:hasCondition(ctype, sub)
	sub = sub or 0
	for _, c in ipairs(self.conds) do
		if c.type == ctype and c.sub == sub and c.ticks > 0 then return true end
	end
	return false
end

local ok = realDofile("data/spells/chaos/shared/soul_aegis.lua")
eq(onCastSpell(player, nil, false), true, "Soulward casts")
eq(player:hasCondition(CONDITION_MANASHIELD), true, "the engine's check (sub id 0) sees the shield")
eq(player:hasCondition(CONDITION_MANASHIELD, 71006), true, "the buff bar's marker is there")

-- a longer Ward of the Mind (sub id 0, 200 s) keeps its time
local p2 = setmetatable({conds = {{type = CONDITION_MANASHIELD, sub = 0, ticks = 200000}}}, {__index = player})
onCastSpell(p2, nil, false)
eq(p2.conds[1].ticks, 200000, "a longer Ward of the Mind is not cut")

-- the buff bar: Soulward alone is one row, a longer Ward of the Mind shows beside it
Chaos = Chaos or {}
realDofile("data/lib/chaos_buffs.lua")
local B = ChaosBuffs
if B and B.collect then
	local function mock(conds)
		local pl = {}
		function pl:getCondition(ctype, id, sub)
			for _, c in ipairs(conds) do
				if c.type == ctype and c.sub == sub then
					return {getTicks = function() return c.ticks end}
				end
			end
		end
		function pl:getId() return 1 end
		return pl
	end
	local function keys(list)
		local k = {}
		for _, it in ipairs(list) do k[#k + 1] = it.key end
		table.sort(k)
		return table.concat(k, ",")
	end
	eq(keys(B.collect(mock(player.conds), 0)):find("manashield", 1, true), nil, "Soulward alone: no second Magic Shield row")
	eq(keys(B.collect(mock({{type = CONDITION_MANASHIELD, sub = 0, ticks = 200000},
		{type = CONDITION_MANASHIELD, sub = 71006, ticks = 15000}}), 0)):find("manashield", 1, true) ~= nil, true,
		"a long Ward of the Mind still shows")
end

if failures > 0 then
	print(string.format("soulward_shield_test: %d of %d checks FAILED", failures, count))
	os.exit(1)
end
print(string.format("soulward_shield_test: all %d checks passed", count))
