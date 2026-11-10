-- Run from the server/ folder: luajit tests/blessed_earth_test.lua (and lua5.3; CI runs both)
-- Blessed Earth (spell 216, data/spells/chaos/paladin/consecration.lua, O466): the zone follows the caster. Each of the 6
-- pulses is centred on the caster's position at that moment: the damage, the ally heal and the picture. The numbers, the
-- pulse count, the interval and the end on death stay. The Templar's Consecration (templar/consecration.lua) is NOT
-- changed: it still pulses on the tile of the cast. The scripts run on a mocked engine; ChaosSpell.pulse is the real
-- function cut out of data/spells/chaos/_common.lua.
local count, failures = 0, 0
local function check(cond, label)
	count = count + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, label .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end
local function readFile(path)
	local f = assert(io.open(path, "r"), path)
	local s = f:read("*a")
	f:close()
	return s
end

-- ---------------------------------------------------------------- the mocked engine
local queue = {}
local UNPACK = table.unpack or unpack
function addEvent(fn, ms, ...)
	queue[#queue + 1] = {fn = fn, ms = ms, args = {...}}
end
local creatures = {}
function Creature(id) return creatures[id] end
function Position(t) return {x = t.x, y = t.y, z = t.z} end
function createCombatArea() return "area" end
AREA_CIRCLE2X2 = "circle2"
SKILL_DISTANCE = 4
COMBAT_HOLYDAMAGE, CONST_ME_HOLYAREA, CONST_ME_HOLYDAMAGE, CONST_ME_MAGIC_BLUE = 1, 2, 3, 4
function Fx(_, fallback) return fallback end

ChaosSpell = {}
-- the real pulse: cut out of the shared spell library, so a change there is tested here
local lib = readFile("data/spells/chaos/_common.lua")
local pulseSrc = lib:match("(function ChaosSpell%.pulse%(.-\nend\n)")
check(pulseSrc ~= nil, "ChaosSpell.pulse found in _common.lua")
assert((loadstring or load)(pulseSrc))()
local log -- what one cast did: {kind, pos, ...}
function ChaosSpell.distanceAttack() return 1 end
function ChaosSpell.vfxOr(pos) log[#log + 1] = {kind = "vfx", pos = pos} end
function ChaosSpell.alliesAround(_, pos, radius)
	log[#log + 1] = {kind = "allies", pos = pos, radius = radius}
	return {"ally"}
end
function ChaosSpell.enemiesAround(_, pos, radius)
	log[#log + 1] = {kind = "enemies", pos = pos, radius = radius}
	return {}
end
function ChaosSpell.healTarget(_, _, min, max) log[#log + 1] = {kind = "heal", min = min, max = max} end
function doAreaCombat(_, ctype, pos, area, min, max)
	log[#log + 1] = {kind = "damage", pos = pos, ctype = ctype, area = area, min = min, max = max}
end

-- a script's dofile of the engine's shared libraries is a no-op here (the mocks above are those libraries)
local realDofile = dofile
ChaosTemplar = {cfg = {consecration = {pulses = 6, intervalMs = 1000, radius = 2, allyHeal = 0.3}}}
TemplarSpell = {values = function() return 10, 20 end}
function dofile(path)
	if path:find("^data/spells/scripts/chaos/") then
		return nil
	end
	return realDofile(path)
end

local function mkCaster(id, pos)
	local c = {id = id, pos = {x = pos[1], y = pos[2], z = pos[3]}, health = 100}
	creatures[id] = c
	function c:getPlayer() return self end
	function c:getId() return self.id end
	function c:getHealth() return self.health end
	function c:getPosition() return {x = self.pos.x, y = self.pos.y, z = self.pos.z} end
	function c:getLevel() return 100 end
	function c:getMagicLevel() return 50 end
	function c:getEffectiveSkillLevel() return 200 end
	function c:registerEvent() end
	return c
end

local function load_(path)
	onCastSpell = nil
	local env = realDofile(path)
	return onCastSpell
end

-- cast, then run the queued pulses; `moves[step]` is where the caster stands before pulse `step` (step 1 = the cast itself)
local function castAndRun(cast, caster, moves, afterStep)
	log, queue = {}, {}
	check(cast(caster, {}, false) == true, "the cast succeeds")
	local step = 1
	while #queue > 0 do
		local e = table.remove(queue, 1)
		step = step + 1
		if moves[step] then
			caster.pos = {x = moves[step][1], y = moves[step][2], z = moves[step][3]}
		end
		if afterStep then afterStep(step) end
		e.fn(UNPACK(e.args))
		check(e.ms == 1000, "a second between pulses")
	end
	return log
end
local function ofKind(entries, kind)
	local out = {}
	for _, e in ipairs(entries) do
		if e.kind == kind then out[#out + 1] = e end
	end
	return out
end

-- ---------------------------------------------------------------- Blessed Earth follows the caster
local blessed = load_("data/spells/chaos/paladin/consecration.lua")
check(type(blessed) == "function", "Blessed Earth loads")
local caster = mkCaster(1, {100, 100, 7})
-- the caster walks one tile east a second, then changes floor at pulse 5
local moves = {[2] = {101, 100, 7}, [3] = {102, 100, 7}, [4] = {103, 101, 7}, [5] = {103, 101, 8}, [6] = {104, 101, 8}}
local entries = castAndRun(blessed, caster, moves)
local hits = ofKind(entries, "damage")
eq(#hits, 6, "six pulses")
local want = {{100, 100, 7}, {101, 100, 7}, {102, 100, 7}, {103, 101, 7}, {103, 101, 8}, {104, 101, 8}}
for i, w in ipairs(want) do
	local h = hits[i]
	check(h and h.pos.x == w[1] and h.pos.y == w[2] and h.pos.z == w[3], "pulse " .. i .. ": the damage is centred on the caster's position then")
end
local allies = ofKind(entries, "allies")
eq(#allies, 6, "the allies are looked up every pulse")
for i, w in ipairs(want) do
	local a = allies[i]
	check(a and a.pos.x == w[1] and a.pos.y == w[2] and a.pos.z == w[3], "pulse " .. i .. ": the heal is centred on the caster's position then")
	eq(a and a.radius, 2, "pulse " .. i .. ": the same 2 sqm")
end
local vfx = ofKind(entries, "vfx")
eq(#vfx, 3, "the picture on the odd pulses")
check(vfx[1].pos.x == 100 and vfx[2].pos.x == 102 and vfx[3].pos.x == 103 and vfx[3].pos.z == 8,
	"the picture follows the caster too (pulses 1, 3 and 5)")
eq(#ofKind(entries, "heal"), 6, "one heal per ally per pulse")
-- the numbers are the old ones: level / 5 + power * f + magic level * f + c, floor, negative
local min = 100 / 5 + 200 * 0.00325 + 50 * 0.4 + 8
local max = 100 / 5 + 200 * 0.0052 + 50 * 0.6 + 15
eq(hits[1].min, -math.floor(min), "damage min unchanged") eq(hits[1].max, -math.floor(max), "damage max unchanged")
eq(hits[6].min, hits[1].min, "the same damage on every pulse")
eq(hits[1].ctype, COMBAT_HOLYDAMAGE, "holy")
local heals = ofKind(entries, "heal")
check(math.abs(heals[1].min - min * 0.5) < 1e-9 and math.abs(heals[1].max - max * 0.5) < 1e-9, "the ally heal is half a pulse, unchanged")
-- a caster that stands still is the old behaviour: every pulse on the cast tile
local still = mkCaster(2, {200, 200, 7})
entries = castAndRun(blessed, still, {})
hits = ofKind(entries, "damage")
local same = #hits == 6
for _, h in ipairs(hits) do
	same = same and h.pos.x == 200 and h.pos.y == 200 and h.pos.z == 7
end
check(same, "a caster that does not move keeps the zone on its tile")
-- it ends when the caster dies: dead before pulse 4 -> 3 pulses
local doomed = mkCaster(3, {300, 300, 7})
entries = castAndRun(blessed, doomed, {}, function(step)
	if step == 4 then doomed.health = 0 end
end)
eq(#ofKind(entries, "damage"), 3, "no pulse after the caster died")
-- it ends when the caster logs out (the creature is gone)
local gone = mkCaster(4, {400, 400, 7})
entries = castAndRun(blessed, gone, {}, function(step)
	if step == 3 then creatures[4] = nil end
end)
eq(#ofKind(entries, "damage"), 2, "no pulse after the caster logged out")
-- not a player: no cast
check(blessed({getPlayer = function() return nil end}, {}, false) == false, "a creature that is no player does not cast")

-- ---------------------------------------------------------------- the source: no fixed centre left
local src = readFile("data/spells/chaos/paladin/consecration.lua")
local code = src:gsub("%-%-[^\n]*", "")
check(not code:find("center", 1, true), "Blessed Earth keeps no cast position")
check(code:find("caster:getPosition()", 1, true) ~= nil, "each pulse reads the caster's position")
-- the player text (first comment block, the Spellbook, the wiki) says it follows
local first = {}
for line in (src .. "\n"):gmatch("([^\n]*)\n") do
	local c = line:match("^%-%-%s?(.*)$")
	if not c then break end
	first[#first + 1] = c
end
local text = table.concat(first, " ")
check(text:find("follows the caster", 1, true) ~= nil, "the description says the zone follows the caster")
check(not text:find("caster's tile", 1, true) and not text:find("stays", 1, true), "the description no longer says it stays on a tile")
local pt = realDofile("data/scripts/chaos/i18n_strings.lua")["pt-BR"]
local key = text:gsub("^Blessed Earth:%s*", ""):gsub("%s+", " ")
key = key:sub(1, 1):upper() .. key:sub(2) -- the wiki and the Spellbook capitalise the first letter
check(pt[key] ~= nil, "pt-BR text for the new description")
check(pt[key] and pt[key]:find("acompanha", 1, true) ~= nil, "pt-BR says the zone follows (acompanha)")
check(pt["Consecrates the caster's tile for 6s. Each second holy damage hits enemies within 2 sqm and allies (party, own summons, caster) standing in it are healed a little."] == nil,
	"the old pt-BR text is gone")

-- ---------------------------------------------------------------- the Templar's Consecration still uses the cast tile
local templar = load_("data/spells/chaos/templar/consecration.lua")
check(type(templar) == "function", "the Templar's Consecration loads")
local tcaster = mkCaster(5, {500, 500, 7})
local tmoves = {[2] = {501, 500, 7}, [3] = {502, 500, 7}, [4] = {503, 500, 7}, [5] = {504, 500, 7}, [6] = {505, 500, 7}}
entries = castAndRun(templar, tcaster, tmoves)
hits = ofKind(entries, "damage")
eq(#hits, 6, "six Templar pulses")
local fixed = #hits == 6
for _, h in ipairs(hits) do
	fixed = fixed and h.pos.x == 500 and h.pos.y == 500 and h.pos.z == 7
end
check(fixed, "the Templar's Consecration stays on the tile of the cast whatever the Templar does")
local tallies = ofKind(entries, "allies")
local tfixed = #tallies == 6
for _, a in ipairs(tallies) do
	tfixed = tfixed and a.pos.x == 500 and a.pos.y == 500
end
check(tfixed, "and so does its ally heal")
check(readFile("data/spells/chaos/templar/consecration.lua"):find("local center = {x = p.x, y = p.y, z = p.z}", 1, true) ~= nil,
	"the Templar script still keeps its cast position")

print(count .. " checks, " .. failures .. " failures")
if failures > 0 then os.exit(1) end
