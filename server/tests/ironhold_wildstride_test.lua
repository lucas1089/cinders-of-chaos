-- Run from the server/ folder: luajit tests/ironhold_wildstride_test.lua (mock engine API; CI runs it with luajit and lua5.3)
-- Owner 2026-10-20 ("pode trocar essas duas também"): the stock Protector (Bulwark, "utamo tempo", id 132, Warrior line)
-- and Swift Foot (Windrunner, "utamo tempo san", id 134, Ranger line) put CONDITION_PACIFIED on the caster for 10 s (no
-- auto attack at all) and a 10 s attack group cooldown; the helper's Auto setup kept Protector up, so the Warrior stopped
-- attacking. Both go (tools/retire_cure_spells.py OTHERS) and the Chaos Ironhold (132) and Wildstride (134) take their
-- ids. This test casts Ironhold on a mocked player: one condition and nothing that pacifies, slows or locks a group;
-- the spell entry, the retirement and the client data agree. Wildstride (134) became the attack spell Gale Volley
-- (O254, attack_kit_config.lua), so its checks are gone; the file keeps its name.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
local fails = 0
local function ok(c, m) if not c then fails = fails + 1; print("FAIL " .. m) end end
local function read(path) local f = assert(io.open(path, "r")); local t = f:read("*a"); f:close(); return t end

-- ------------------------------------------------------------------ the casts (mocked engine)
local common = read("data/spells/chaos/_common.lua")
local subs = common:match("ChaosSpell%.SUBID = %b{}")
local subIron = tonumber(subs:match("ironhold = (%d+)"))
ok(subIron == 71073, "ChaosSpell.SUBID.ironhold = 71073")
ChaosSpell = {SUBID = {ironhold = subIron}, vfxOr = function() return true end}
local realDofile = dofile
dofile = function(path)
	if path == "data/spells/scripts/chaos/_common.lua" then return end -- ChaosSpell is the stub above
	return realDofile(path)
end

local Cond = {}
Cond.__index = Cond
function Condition(ctype, cid)
	return setmetatable({type = ctype, id = cid, params = {}}, Cond)
end
function Cond:setParameter(k, v) self.params[k] = v end
function Cond:setFormula(a, b, c, d) self.formula = {a, b, c, d} end
function Cond:setTicks(t) self.params[CONDITION_PARAM_TICKS] = t end

local function cast(script)
	local added, effects = {}, 0
	local pos = {sendMagicEffect = function() effects = effects + 1 end}
	local player = {}
	function player:getPlayer() return self end
	function player:addCondition(c) added[#added + 1] = c; return true end
	function player:getPosition() return pos end
	function player:changeSpeed() error("no direct speed change") end
	onCastSpell = nil
	realDofile(script)
	ok(onCastSpell(player, nil, false) == true, script .. ": the cast succeeds")
	ok(effects >= 1, script .. ": an effect on the caster")
	ok(onCastSpell({getPlayer = function() return nil end}, nil, false) == false, script .. ": no player, no cast")
	for _, x in ipairs(added) do
		ok(x.type ~= CONDITION_PACIFIED, script .. ": no attack lock on the caster")
		ok(x.type ~= CONDITION_PARALYZE, script .. ": no slow on the caster")
		ok(x.type ~= CONDITION_SPELLGROUPCOOLDOWN and x.type ~= CONDITION_EXHAUST, script .. ": no group cooldown or exhaust")
		ok(x.params[CONDITION_PARAM_DISABLE_DEFENSE] == nil, script .. ": defence untouched")
	end
	return added
end

local iron = cast("data/spells/chaos/knight/ironhold.lua")
ok(#iron == 1, "Ironhold: one condition: " .. #iron)
local c = iron[1] or {params = {}}
ok(c.type == CONDITION_ATTRIBUTES, "Ironhold: an attribute condition")
ok(c.params[CONDITION_PARAM_SUBID] == 71073, "Ironhold: its own sub id (the buff bar row)")
ok(c.params[CONDITION_PARAM_TICKS] == 12000, "Ironhold: 12 s")
ok(c.params[CONDITION_PARAM_SKILL_SHIELDPERCENT] == 140, "Ironhold: +40% shielding")
ok(c.params[CONDITION_PARAM_SKILL_MELEEPERCENT] == nil, "Ironhold: melee skill untouched")
dofile = realDofile

-- ------------------------------------------------------------------ the spell entries
local xml = read("data/spells/chaos/spells_chaos.xml"):gsub("<!%-%-.-%-%->", "")
local function entry(name, id, words, level, mana, vocs)
	local head, body = xml:match('<instant ([^>]*name="' .. name .. '"[^>]*)>(.-)</instant>')
	ok(head ~= nil, name .. " is in spells_chaos.xml")
	head, body = head or "", body or ""
	ok(head:find('spellid="' .. id .. '"', 1, true), name .. ": id " .. id .. " (freed by retire_cure_spells.py)")
	ok(head:find('words="' .. words .. '"', 1, true), name .. ": Chaos words")
	ok(head:find('group="support"', 1, true) and not head:find("secondarygroup", 1, true), name .. ": support group only")
	ok(head:find('level="' .. level .. '"', 1, true) and head:find('mana="' .. mana .. '"', 1, true), name .. ": level, mana")
	ok(head:find('cooldown="30000"', 1, true) and head:find('groupcooldown="2000"', 1, true), name .. ": 30 s, group 2 s")
	ok(head:find('selftarget="1"', 1, true) and head:find('aggressive="0"', 1, true), name .. ": a self buff")
	local got = {}
	for v in body:gmatch('<vocation name="([^"]+)"') do got[#got + 1] = v end
	ok(table.concat(got, ",") == vocs, name .. ": vocations " .. table.concat(got, ","))
	local count = 0
	for _ in xml:gmatch('spellid="' .. id .. '"') do count = count + 1 end
	ok(count == 1, name .. ": one Chaos spell with id " .. id)
end
entry("Ironhold", 132, "tor brak", 55, 120, "Warrior,Juggernaut") -- the Berserker (no shield) left it: the 15-spell cap

-- ------------------------------------------------------------------ the retirement
local tool = read("tools/retire_cure_spells.py")
ok(tool:find("'support/protector.lua': (132, 'Bulwark')", 1, true), "retire_cure_spells.py retires Protector")
ok(tool:find("'support/swift_foot.lua': (134, 'Windrunner')", 1, true), "retire_cure_spells.py retires Swift Foot")
local names = read("data/spells/spell_names.csv")
ok(not names:find("utamo tempo", 1, true), "no Chaos name for the retired spells")
local buffs = read("data/lib/chaos_buffs.lua")
ok(buffs:find('cond("ironhold", "CONDITION_ATTRIBUTES", 71073', 1, true), "Ironhold: a buff bar row")

-- ------------------------------------------------------------------ the client data (generated, gen_spell_data.py)
local cdata = read("../client/overlay/modules/game_chaosspells/spelldata.lua")
ok(cdata:find('{ id = 132, name = "Ironhold", words = "tor brak"', 1, true), "the client knows Ironhold")
ok(cdata:find('{ id = 134, name = "Gale Volley", words = "ruan vert"', 1, true), "the client knows Gale Volley (the id of Wildstride)")
ok(cdata:find('["utamo tempo"] = true', 1, true), "the client hides the retired Protector")
ok(cdata:find('["utamo tempo san"] = true', 1, true), "the client hides the retired Swift Foot")
ok(not cdata:find('"tor ira"', 1, true) and not cdata:find('"tor ira sol"', 1, true), "no rename to the old words")
local support = read("../client/overlay/modules/game_helpersupport/supportspells.lua")
ok(support:find("[132] = { auto = 'timer', dur = 12 }", 1, true), "the helper's Auto setup times Ironhold (12 s)")
ok(not support:find("[134] =", 1, true), "Gale Volley is an attack spell: no support row")

if fails > 0 then error("ironhold_wildstride_test: " .. fails .. " failure(s)") end
print("ironhold_wildstride_test: OK")
