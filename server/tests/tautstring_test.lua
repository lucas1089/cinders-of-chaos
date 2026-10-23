-- Run from the server/ folder: luajit tests/tautstring_test.lua (mock engine API; CI runs it with luajit and lua5.3)
-- Beta report 2026-10-20 (owner): "the auto attack stopped completely ... it came back, then stopped again". The helper's
-- Support tab kept the stock Sharpshooter (Hawkeye, "utito tempo san" / "vyr ira sol") up on a Ranger, and while it was
-- active the bow did not fire. Its base script slowed the caster 70% (CONDITION_PARALYZE) for its 10 s next to the
-- +50% distance skill (and the healing group waited 10 s). Owner decision: the stock spell goes
-- (tools/retire_cure_spells.py OTHERS) and the Chaos Tautstring takes its id 135. This test casts Tautstring on a mocked
-- player: one attribute buff of the distance skill and nothing that slows, pacifies or locks a group; the spell entry,
-- the retirement and the client data agree.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
local fails = 0
local function ok(c, m) if not c then fails = fails + 1; print("FAIL " .. m) end end
local function read(path) local f = assert(io.open(path, "r")); local t = f:read("*a"); f:close(); return t end

-- ------------------------------------------------------------------ the cast (mocked engine)
local common = read("data/spells/chaos/_common.lua")
local sub = tonumber(common:match("ChaosSpell%.SUBID = %b{}"):match("tautstring = (%d+)"))
ok(sub == 71072, "ChaosSpell.SUBID.tautstring = 71072")
ChaosSpell = {SUBID = {tautstring = sub}, vfxOr = function() return true end}
local realDofile = dofile
dofile = function(path)
	if path == "data/spells/scripts/chaos/_common.lua" then return end -- ChaosSpell is the stub above
	return realDofile(path)
end

local added = {}
local Cond = {}
Cond.__index = Cond
function Condition(ctype, cid)
	return setmetatable({type = ctype, id = cid, params = {}}, Cond)
end
function Cond:setParameter(k, v) self.params[k] = v end
function Cond:setFormula() self.formula = true end
function Cond:setTicks(t) self.params[CONDITION_PARAM_TICKS] = t end
local effects = 0
local pos = {sendMagicEffect = function() effects = effects + 1 end}
local player = {}
function player:getPlayer() return self end
function player:addCondition(c) added[#added + 1] = c; return true end
function player:getPosition() return pos end
function player:getStorageValue() return -1 end
function player:changeSpeed() error("Tautstring must not change the caster's speed") end

realDofile("data/spells/chaos/paladin/tautstring.lua")
dofile = realDofile
ok(onCastSpell(player, nil, false) == true, "the cast succeeds")
ok(#added == 1, "one condition on the caster: " .. #added)
local c = added[1] or {params = {}}
ok(c.type == CONDITION_ATTRIBUTES, "an attribute condition")
ok(c.params[CONDITION_PARAM_SUBID] == 71072, "its own sub id (the buff bar row)")
ok(c.params[CONDITION_PARAM_TICKS] == 12000, "12 s")
ok(c.params[CONDITION_PARAM_SKILL_DISTANCEPERCENT] == 125, "+25% distance skill")
ok(c.params[CONDITION_PARAM_DISABLE_DEFENSE] == nil, "defence untouched")
ok(c.params[CONDITION_PARAM_SKILL_SHIELDPERCENT] == nil, "shielding untouched")
for _, x in ipairs(added) do
	ok(x.type ~= CONDITION_PARALYZE, "no slow on the caster")
	ok(x.type ~= CONDITION_PACIFIED, "no attack lock on the caster")
	ok(x.type ~= CONDITION_SPELLGROUPCOOLDOWN and x.type ~= CONDITION_EXHAUST, "no group cooldown or exhaust")
end
ok(effects >= 1, "an effect on the caster")
local nocaster = {getPlayer = function() return nil end}
ok(onCastSpell(nocaster, nil, false) == false, "a creature that is no player: no cast")

-- ------------------------------------------------------------------ the spell entry
local xml = read("data/spells/chaos/spells_chaos.xml"):gsub("<!%-%-.-%-%->", "")
local head, body = xml:match('<instant ([^>]*name="Tautstring"[^>]*)>(.-)</instant>')
ok(head ~= nil, "Tautstring is in spells_chaos.xml")
head, body = head or "", body or ""
ok(head:find('spellid="135"', 1, true), "id 135 (Hawkeye's, freed by retire_cure_spells.py)")
ok(head:find('words="vyr sag"', 1, true), "Chaos words")
ok(head:find('group="support"', 1, true) and not head:find("secondarygroup", 1, true), "support group, no second group")
ok(head:find('level="60"', 1, true) and head:find('mana="180"', 1, true), "level 60, 180 mana (Hawkeye: 60, 450; 300 until 2026-10-22)")
ok(head:find('cooldown="30000"', 1, true) and head:find('groupcooldown="2000"', 1, true), "30 s, group 2 s")
ok(head:find('selftarget="1"', 1, true) and head:find('aggressive="0"', 1, true), "a self buff")
local vocs = {}
for v in body:gmatch('<vocation name="([^"]+)"') do vocs[#vocs + 1] = v end
ok(table.concat(vocs, ",") == "Ranger,Deadeye,Beastmaster", "the Ranger line (Hawkeye's Paladin / Royal Paladin)")
local count = 0
for _ in xml:gmatch('spellid="135"') do count = count + 1 end
ok(count == 1, "one Chaos spell with id 135")

-- ------------------------------------------------------------------ the retirement
local tool = read("tools/retire_cure_spells.py")
ok(tool:find("'support/sharpshooter.lua': (135, 'Hawkeye')", 1, true), "retire_cure_spells.py retires Sharpshooter")
ok(not read("data/spells/spell_names.csv"):find("utito tempo san", 1, true), "no Chaos name for the retired spell")
local buffs = read("data/lib/chaos_buffs.lua")
ok(buffs:find('cond("tautstring", "CONDITION_ATTRIBUTES", 71072', 1, true), "a buff bar row")
-- no Chaos spell script pacifies anyone (the stock Bulwark and Windrunner did; retired 2026-10-20, ironhold_wildstride_test.lua)
for name in xml:gmatch('script="chaos/([^"]+)"') do
	local f = io.open("data/spells/chaos/" .. name, "r")
	if f then
		local text = f:read("*a"); f:close()
		ok(not text:find("CONDITION_PACIFIED", 1, true), name .. ": no CONDITION_PACIFIED")
	end
end

-- ------------------------------------------------------------------ the client data (generated, gen_spell_data.py)
local cdata = read("../client/overlay/modules/game_chaosspells/spelldata.lua")
ok(cdata:find('{ id = 135, name = "Tautstring", words = "vyr sag"', 1, true), "the client knows Tautstring")
ok(cdata:find('["utito tempo san"] = true', 1, true), "the client hides the retired stock entry")
ok(not cdata:find('"vyr ira sol"', 1, true), "the client no longer renames to the Hawkeye words")
local support = read("../client/overlay/modules/game_helpersupport/supportspells.lua")
ok(support:find("[135] = { auto = 'timer', dur = 12 }", 1, true), "the helper's Auto setup times Tautstring (12 s)")

if fails > 0 then error("tautstring_test: " .. fails .. " failure(s)") end
print("tautstring_test: OK")
