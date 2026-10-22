-- Run from the server/ folder: luajit tests/grave_nova_test.lua (mock engine API; CI runs it with luajit and lua5.3)
-- Grave Nova (owner 2026-10-22, "dê uma magia de ataque em área pro necromancer. depois do withering curse"): the
-- Necromancer's area attack, level 50, death damage on every enemy within 3 sqm of the caster (a circle). This test
-- casts it on a mocked caster: who is hit and who is not, the ring of effects, the cancel for another class; the spell
-- entry (id 42 of the removed Conjure Rations, after Withering Curse, the Necromancer only) and the config agree.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
local fails, checks = 0, 0
local function ok(c, m) checks = checks + 1; if not c then fails = fails + 1; print("FAIL " .. m) end end
local function read(path) local f = assert(io.open(path, "r")); local t = f:read("*a"); f:close(); return t end

local cfg = dofile("data/scripts/chaos/necro_config.lua")
local g = cfg.graveNova
ok(g and g.radius == 3, "graveNova.radius = 3")
ok(cfg.spellIds.graveNova == 42, "spellIds.graveNova = 42")

-- ------------------------------------------------------------------ the spell entry
local xml = read("data/spells/chaos/spells_chaos.xml"):gsub("<!%-%-.-%-%->", "")
local block = xml:match('<instant [^>]*name="Grave Nova".-</instant>')
ok(block ~= nil, "Grave Nova in spells_chaos.xml")
block = block or ""
local head = block:match("<instant([^>]*)>") or ""
local function attr(k) return head:match(k .. '="([^"]*)"') end
ok(attr("spellid") == "42", "spell id 42")
ok(attr("group") == "attack", "an attack spell")
ok(attr("words") == "drai nyx oss", "words drai nyx oss")
ok(attr("needtarget") == nil and attr("selftarget") == "1", "no target needed")
ok(attr("script") == "chaos/necromancer/grave_nova.lua", "script path")
local curse = tonumber(xml:match('<instant [^>]*name="Withering Curse"[^>]*level="(%d+)"'))
local shrap = tonumber(xml:match('<instant [^>]*name="Bone Shrapnel"[^>]*level="(%d+)"'))
local level = tonumber(attr("level"))
ok(level and curse and level > curse, "after Withering Curse (" .. tostring(curse) .. "): " .. tostring(level))
ok(level and shrap and level < shrap, "before Bone Shrapnel (" .. tostring(shrap) .. "): " .. tostring(level))
local vocs = {}
for v in block:gmatch('<vocation name="([^"]+)"') do vocs[#vocs + 1] = v end
ok(#vocs == 1 and vocs[1] == "Necromancer", "the Necromancer only: " .. table.concat(vocs, ","))
local model = read("data/spells/rotation_model.csv")
ok(model:find("drai nyx oss,Grave Nova,", 1, true) ~= nil, "rotation_model.csv row")
ok(model:find("ML*" .. g.mlMin .. "+" .. g.baseMin .. ",l+ML*" .. g.mlMax .. "+" .. g.baseMax, 1, true) ~= nil,
	"rotation_model.csv has the config's formula")

-- ------------------------------------------------------------------ the cast (mocked engine)
local effects, hits, cancelled = {}, {}, 0
local P = {}
P.__index = P
function Position(x, y, z)
	if type(x) == "table" then x, y, z = x.x, x.y, x.z end
	return setmetatable({x = x, y = y, z = z}, P)
end
function P:sendMagicEffect(e) effects[#effects + 1] = {x = self.x, y = self.y, e = e} end
local center = Position(100, 100, 7)
local function mob(name, dx, dy)
	return {name = name, pos = Position(100 + dx, 100 + dy, 7), getPosition = function(self) return self.pos end}
end
-- inside the circle: next to the caster, 3 straight, (3,1) and (2,2); outside: the corner (3,3) of the square
local mobs = {mob("near", 1, 0), mob("straight3", 0, -3), mob("knight3_1", 3, 1), mob("diag2", -2, 2), mob("corner", 3, 3)}
local classOk = true
NecroSpell = {cfg = cfg, fx = function(pos, vnames) effects[#effects + 1] = {x = pos.x, y = pos.y, vfx = vnames[1]} end,
	class = function() if not classOk then cancelled = cancelled + 1 end return classOk and "necromancer" or nil end}
ChaosNecro = {
	values = function(player, f) ok(f == g, "values of the graveNova row"); return 100, 200 end,
	enemiesAround = function(caster, pos, radius, withPlayers)
		ok(radius == g.radius and withPlayers == true, "enemies within the radius, players by PvP rules")
		return mobs
	end,
	damage = function(caster, target, ctype, min, max)
		ok(ctype == COMBAT_DEATHDAMAGE and min == 100 and max == 200, "death damage of the values")
		hits[target.name] = (hits[target.name] or 0) + 1
		return 150
	end,
}
local realDofile = dofile
dofile = function(path)
	if path == "data/spells/scripts/chaos/_necro.lua" then return end -- NecroSpell / ChaosNecro are the stubs above
	return realDofile(path)
end
realDofile("data/spells/chaos/necromancer/grave_nova.lua")
dofile = realDofile
local player = {getPlayer = function(self) return self end, getPosition = function() return center end}
ok(onCastSpell(player, nil, false) == true, "the cast succeeds")
for _, name in ipairs({"near", "straight3", "knight3_1", "diag2"}) do
	ok(hits[name] == 1, name .. " is hit once")
end
ok(hits.corner == nil, "the corner of the square is outside the circle")
local ring, burst = 0, 0
for _, e in ipairs(effects) do
	if e.vfx then burst = burst + 1 else ring = ring + 1 end
	ok(e.vfx or not (e.x == 100 and e.y == 100), "no ring effect under the caster")
end
ok(burst == 1, "one burst on the caster")
ok(ring == 36, "the ring covers the circle of radius 3 (36 tiles around the caster): " .. ring)
ok(onCastSpell({getPlayer = function() return nil end}, nil, false) == false, "no player, no cast")
classOk = false
hits = {}
ok(onCastSpell(player, nil, false) == false and cancelled == 1, "another class: cancelled")
ok(next(hits) == nil, "another class hits nothing")

-- ------------------------------------------------------------------ the client data and the id
local data = read("../client/overlay/modules/game_chaosspells/spelldata.lua")
ok(data:find('{ id = 42, name = "Grave Nova", words = "drai nyx oss", level = 50', 1, true) ~= nil,
	"client spelldata.lua is regenerated")
ok(read("tools/register_spells.py"):find("other_conjure_scripts", 1, true) ~= nil,
	"register_spells.py counts the removed conjure spells' ids as free")

if fails > 0 then error("grave_nova_test: " .. fails .. " failure(s)") end
print("grave_nova_test: " .. checks .. " checks ok")
