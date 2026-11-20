-- Numbers of the spell awakening for the Python tools (O686 phase 7): run from server/ with luajit or lua5.3.
--   luajit tools/awakening_numbers.lua            prints `cfg<TAB>name<TAB>value` lines of the signature numbers and the slot costs,
--                                                 then `row<TAB>id<TAB>value<TAB>output<TAB>utility<TAB>kind` for every row of data/spells/awakened.csv
-- The value of a row is spell_awakening_core.lua A.value (the one implementation); gen_awakened.py and spell_upgrade_model.py read these lines.
dofile("data/scripts/chaos/spell_awakening_core.lua")
local A = ChaosSpellAwakeningCore
local cfg = dofile("data/scripts/chaos/spell_awakening_config.lua")
local sg = cfg.signature

local function put(name, v)
	print(string.format("cfg\t%s\t%s", name, tostring(v)))
end
put("bonus", cfg.bonus)
put("classShare", cfg.classShare)
put("perSpell", cfg.perSpell)
put("target", sg.target)
put("bandMin", sg.band.min)
put("bandMax", sg.band.max)
put("capShare", sg.capShare)
put("use", sg.use)
put("ringReach", sg.ringReach)
put("lineDensity", sg.lineDensity)
put("lineReach", sg.lineReach)
put("allies", sg.allies)
put("kills", sg.kills)
for k, v in pairs(sg.targets) do
	put("targets." .. k, v)
end
for k, v in pairs(sg.worth) do
	put("worth." .. k, v)
end
for i, s in ipairs(cfg.slots) do
	put("slot" .. i, s.waystone .. "," .. s.rift .. "," .. s.pinnacle)
end
for k, v in pairs(cfg.rates) do
	put("rates." .. k, v)
end
put("tol", cfg.tol)
put("perKillPinnacle", cfg.sources.pinnacle.perKill)

local f = io.open("data/spells/awakened.csv", "r")
if f then
	local text = f:read("*a")
	f:close()
	local rows, err = A.parse(text)
	if not rows then
		io.stderr:write(tostring(err) .. "\n")
		os.exit(1)
	end
	local ids = {}
	for id in pairs(rows) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local out, util = A.raw(rows[id], cfg)
		print(string.format("row\t%d\t%.9f\t%.9f\t%.9f\t%s", id, A.value(rows[id], cfg), out, util, rows[id].kind))
	end
end
