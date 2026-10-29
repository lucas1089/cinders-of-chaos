-- Run from the server/ folder: luajit tests/wolf_spells_test.lua (mock engine API; CI runs it with luajit and lua5.3)
-- The Beastmaster's wolf spells (O332, server/README.md "Wolves as the main damage (O332)"): Feral Command, Pack Frenzy, Pack
-- Howl and Rending Pounce, all cast by data/spells/chaos/_wolves.lua. Covers:
--   * the numbers: Chaos.classes.companion.spells, the rotation model rows (rotation_model.csv), the spell entries
--     (spells_chaos.xml: ids 35 and 39 of the spell id pool, words, levels, the Beastmaster only) and the attack kit (the two
--     arrow spells the new ones replace, Arrowstorm and Gale Volley, no longer list the Beastmaster);
--   * the wolf factor (ChaosClasses.wolfFactor): Pack Alpha times the Vocation Trials' minion damage, read from the storage
--     the passive state mirrors into (the spell scripts run in another Lua state);
--   * the cast on a mocked engine: every companion leaps to the target, an area spell hits every monster of its circle for
--     every companion (the wolf factor in each hit), a single-target spell only the target, never an ally, and the
--     message when no companion is out.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
local fails, checks = 0, 0
local function ok(c, m) checks = checks + 1; if not c then fails = fails + 1; print("FAIL " .. m) end end
local function near(a, b, m) ok(math.abs(a - b) < 1e-6, m .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
local function read(path) local f = assert(io.open(path, "r")); local t = f:read("*a"); f:close(); return t end

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/classes.lua")
local C, CT = ChaosClasses, ChaosClassTree
local comp = Chaos.classes.companion

-- ------------------------------------------------------------------ the numbers agree everywhere
local KEYS = {
	feral = {"Feral Command", "kah ferh", 249, 110}, frenzy = {"Pack Frenzy", "kah ferh vas", 147, 320},
	howl = {"Pack Howl", "drai ferh ulv", 35, 220}, pounce = {"Rending Pounce", "kah ferh rax", 39, 240},
}
local xml = read("data/spells/chaos/spells_chaos.xml"):gsub("<!%-%-.-%-%->", "")
local model = read("data/spells/rotation_model.csv")
for key, e in pairs(KEYS) do
	local s = comp.spells[key]
	ok(s and s.mauls and s.mauls > 0, key .. ": mauls in Chaos.classes.companion.spells")
	local head = xml:match('<instant ([^>]*name="' .. e[1] .. '"[^>]*)>')
	ok(head ~= nil, e[1] .. " in spells_chaos.xml")
	head = head or ""
	local function attr(k) return head:match(k .. '="([^"]*)"') end
	ok(tonumber(attr("spellid")) == e[3], e[1] .. " spell id " .. e[3])
	ok(attr("words") == e[2], e[1] .. " words " .. e[2])
	ok(tonumber(attr("level")) == e[4], e[1] .. " level " .. e[4])
	ok(attr("group") == "attack" and attr("needtarget") == "1", e[1] .. " is an attack spell on a target")
	ok(attr("script") == "chaos/beastmaster/" .. e[1]:lower():gsub(" ", "_") .. ".lua", e[1] .. " script path")
	local block = xml:match('<instant [^>]*name="' .. e[1] .. '".-</instant>') or ""
	local vocs = {}
	for v in block:gmatch('<vocation name="([^"]+)"') do vocs[#vocs + 1] = v end
	ok(#vocs == 1 and vocs[1] == "Beastmaster", e[1] .. " is the Beastmaster's: " .. table.concat(vocs, ","))
	-- the model row has the config's number
	local row = model:match("\n" .. e[2] .. "," .. e[1]:gsub("%-", "%%-") .. ",([^,]+),")
	ok(row == string.format("%g*BITE*PETS*WOLF", s.mauls), e[1] .. " rotation model row: " .. tostring(row))
	local f = io.open("data/spells/chaos/beastmaster/" .. e[1]:lower():gsub(" ", "_") .. ".lua")
	ok(f ~= nil, e[1] .. " script file")
	if f then
		local src = f:read("*a"); f:close()
		ok(src:find("Wolves.cast('" .. key .. "'", 1, true) ~= nil, e[1] .. " casts '" .. key .. "'")
		ok(src:find("^%-%- " .. e[1] .. ":") ~= nil, e[1] .. " script starts with its description")
	end
end
ok(comp.spells.howl.radius == 2 and comp.spells.pounce.radius == 1, "Pack Howl radius 2, Rending Pounce radius 1")
ok(comp.spells.feral.radius == nil and comp.spells.frenzy.radius == nil, "Feral Command and Pack Frenzy hit the target only")
-- the replaced arrows no longer list the Beastmaster, in the server's XML and in the attack kit
for _, name in ipairs({"Arrowstorm", "Gale Volley"}) do
	local block = xml:match('<instant [^>]*name="' .. name .. '".-</instant>') or ""
	ok(block ~= "" and not block:find('name="Beastmaster"', 1, true), name .. " is not the Beastmaster's any more")
end
local kit = read("data/scripts/chaos/attack_kit_config.lua")
for _, name in ipairs({"Arrowstorm", "Gale Volley"}) do
	local vocs = kit:match('name = "' .. name .. '".-vocations = (%b{})') or ""
	ok(vocs ~= "" and not vocs:find("Beastmaster", 1, true), name .. " kit vocations: " .. vocs)
end
-- the pool of spell ids gave the two ids away
local pool = dofile("data/scripts/chaos/spell_id_pool_config.lua")
for _, id in ipairs(pool.spare) do ok(id ~= 35 and id ~= 39, "spare id " .. id .. " is not Pack Howl's or Rending Pounce's") end
-- the Spellbook draws the circles
local areas = read("data/scripts/chaos/spellbook_areas_config.lua")
ok(areas:find('["Pack Howl"] = {shape = "circle", radius = 2}', 1, true) ~= nil, "Pack Howl area in the Spellbook")
ok(areas:find('["Rending Pounce"] = {shape = "circle", radius = 1}', 1, true) ~= nil, "Rending Pounce area in the Spellbook")

-- ------------------------------------------------------------------ the wolf factor
local function mkPlayer(storage)
	local p = {st = storage or {}, level = 750, skill = 130}
	function p:getStorageValue(k) return self.st[k] or -1 end
	function p:setStorageValue(k, v) self.st[k] = v end
	function p:getLevel() return self.level end
	function p:getEffectiveSkillLevel() return self.skill end
	return p
end
SKILL_DISTANCE = 4
local plain = mkPlayer()
near(C.wolfFactor(plain), 1, "no keystone, no Trials: 1")
local alpha = mkPlayer()
CT.write(alpha, {ksPackAlpha = 1})
near(C.wolfFactor(alpha), 1.35, "Pack Alpha: 1.35")
alpha:setStorageValue(comp.minionStorage, 65)
near(C.wolfFactor(alpha), 1.35 * 1.65, "Pack Alpha and the Trials' 65% minion damage")
local trials = mkPlayer()
trials:setStorageValue(comp.minionStorage, 25)
near(C.wolfFactor(trials), 1.25, "the Trials alone")
trials:setStorageValue(comp.minionStorage, 900)
near(C.wolfFactor(trials), 2.5, "the Trials' own bound: at most x2.5")
trials:setStorageValue(comp.minionStorage, 0)
near(C.wolfFactor(trials), 1, "0 is nothing")
-- the bite and the mauls carry the factor
local lo1, hi1 = C.biteValuesFor(plain)
local lo2, hi2 = C.biteValuesFor(alpha)
ok(math.abs(hi2 / hi1 - 1.35 * 1.65) < 0.01, "the bite carries the wolf factor")
local alo, ahi = C.autoBiteValuesFor(alpha)
ok(ahi > 0 and ahi == math.floor((750 * comp.autoLevel + 130 * comp.autoSkill) * C.wolfFactor(alpha) * 1.2), "the companion's own bite carries it too")
local mlo, mhi = C.maulValuesFor(alpha, "howl")
near(mhi, hi2 * comp.spells.howl.mauls, "a maul is the spell's mauls x the bite")
local zlo, zhi = C.maulValuesFor(alpha, "nothing")
ok(zlo == 0 and zhi == 0, "an unknown spell deals nothing")

-- ------------------------------------------------------------------ the cast (mocked engine)
local P = {}
P.__index = P
function Position(x, y, z)
	if type(x) == "table" then x, y, z = x.x, x.y, x.z end
	return setmetatable({x = x, y = y, z = z}, P)
end
function P:sendMagicEffect(e) end
local center = Position(100, 100, 7)
local function creature(name, dx, dy, opts)
	opts = opts or {}
	local c = {name = name, pos = Position(100 + dx, 100 + dy, 7), hp = 1000, ally = opts.ally, wolf = opts.wolf}
	function c:getName() return self.name end
	function c:getPosition() return self.pos end
	function c:isMonster() return true end
	function c:isPlayer() return false end
	function c:getHealth() return self.hp end
	function c:getId() return self.id end
	function c:teleportTo(pos) self.pos = pos; self.teleported = true end
	function c:setTarget(t) self.target = t end
	return c
end
local function newCaster(wolves)
	local p = mkPlayer()
	CT.write(p, {ksPackAlpha = 1})
	p:setStorageValue(comp.minionStorage, 65)
	p.summons = wolves
	function p:getSummons() return self.summons end
	function p:getPosition() return Position(97, 100, 7) end
	function p:getPlayer() return self end
	function p:isPlayer() return true end
	return p
end

local hits, cancelled, shots = {}, {}, 0
local target
local mobs = {}
ChaosSpell = {
	loadClasses = function() return C end,
	loadSummons = function()
		return {
			isAlly = function(player, c) return c.ally == true end,
			nearestEnemy = function(player, list, pos, range, filter)
				for _, c in ipairs(list) do if not c.ally and not c.wolf and filter(c) then return c end end
			end,
		}
	end,
	targetOf = function(variant) return variant.target end,
	canAttack = function(caster, c) return c ~= caster and c.hp > 0 end,
	isEnemy = function(caster, c) return not c.ally and not c.wolf end,
	spectators = function() return mobs end,
	freeAround = function(center_, ref) return {{pos = Position(center_.x + 1, center_.y, center_.z)}} end,
	shoot = function() shots = shots + 1 end,
	cancel = function(player, msg) cancelled[#cancelled + 1] = msg; return false end,
	vfx = function() return true end, vfxDir = function() return true end, fx = function() end,
	dirTo = function() return 1 end,
	damageTarget = function(caster, c, ctype, min, max)
		hits[c.name] = hits[c.name] or {}
		table.insert(hits[c.name], {min = min, max = max, ctype = ctype})
		return true
	end,
}
local realDofile = dofile
dofile = function(path)
	if path == "data/spells/scripts/chaos/_common.lua" then return end -- ChaosSpell is the stub above
	return realDofile(path)
end
-- _wolves.lua lives in data/spells/chaos/ (the install copies it to data/spells/scripts/chaos/)
Wolves = nil
realDofile("data/spells/chaos/_wolves.lua")
dofile = realDofile
ok(Wolves ~= nil and type(Wolves.cast) == "function", "Wolves.cast exists")
SKILL_DISTANCE = 4

local function cast(key, wolves, variant)
	hits, cancelled, shots = {}, {}, 0
	local caster = newCaster(wolves)
	local res = Wolves.cast(key, caster, variant)
	return res, caster
end

-- Pack Howl: target (0,0); inside the circle of radius 2: (1,0) (0,2) (2,1) (-2,-1); outside: (3,0) (2,2) corner of the square? (2,2)
-- is at distance 2.83, outside a disc of radius 2
target = creature("target", 0, 0)
mobs = {target, creature("n1", 1, 0), creature("n2", 0, 2), creature("n3", 2, 1), creature("n4", -2, -1),
	creature("far", 3, 0), creature("corner", 2, 2), creature("ally", 1, 1, {ally = true})}
local wolfA, wolfB = creature("War Wolf", -3, 0, {wolf = true}), creature("War Wolf", -4, 1, {wolf = true})
local res, caster = cast("howl", {wolfA, wolfB}, {target = target})
ok(res == true, "Pack Howl casts")
for _, name in ipairs({"target", "n1", "n2", "n3", "n4"}) do
	ok(hits[name] and #hits[name] == 2, "Pack Howl hits " .. name .. " once for each of the 2 companions: " .. tostring(hits[name] and #hits[name]))
end
for _, name in ipairs({"far", "corner", "ally"}) do ok(hits[name] == nil, "Pack Howl does not hit " .. name) end
local lo, hi = C.maulValuesFor(caster, "howl")
ok(hits.target and hits.target[1].min == lo and hits.target[1].max == hi, "a howl bite is the mauls x the bite with the wolf factor")
ok(hits.target[1].ctype == COMBAT_PHYSICALDAMAGE, "physical damage")
ok(wolfA.teleported and wolfB.teleported and wolfA.target == target and wolfB.target == target, "both companions leap to the target and take it")
ok(shots == 2, "a missile for each leap")

-- Rending Pounce: radius 1
target = creature("target", 0, 0)
mobs = {target, creature("n1", 1, 0), creature("n2", 1, 1), creature("n3", 0, 2), creature("far", 2, 0)}
wolfA, wolfB = creature("War Wolf", 0, 1, {wolf = true}), creature("Wolf", 5, 5, {wolf = true})
res, caster = cast("pounce", {wolfA, wolfB}, {target = target})
ok(res == true, "Rending Pounce casts")
for _, name in ipairs({"target", "n1", "n2"}) do ok(hits[name] and #hits[name] == 2, "Rending Pounce hits " .. name) end
for _, name in ipairs({"n3", "far"}) do ok(hits[name] == nil, "Rending Pounce does not hit " .. name) end
ok(not wolfA.teleported and wolfB.teleported, "a companion next to the target stays, the far one leaps")
lo, hi = C.maulValuesFor(caster, "pounce")
ok(hits.n1[1].max == hi, "a pounce bite is the mauls x the bite")

-- Feral Command and Pack Frenzy: the target only, one hit per companion
target = creature("target", 0, 0)
mobs = {target, creature("n1", 1, 0)}
for _, key in ipairs({"feral", "frenzy"}) do
	wolfA = creature("War Wolf", 1, 1, {wolf = true})
	res, caster = cast(key, {wolfA}, {target = target})
	ok(res == true and #(hits.target or {}) == 1 and hits.n1 == nil, key .. ": one companion, one maul on the target only")
	lo, hi = C.maulValuesFor(caster, key)
	ok(hits.target[1].max == hi, key .. ": the mauls x the bite")
end
-- Pack Frenzy is a harder maul than Feral Command
local _, c1 = cast("feral", {creature("War Wolf", 1, 1, {wolf = true})}, {target = target})
local fMax = hits.target[1].max
cast("frenzy", {creature("War Wolf", 1, 1, {wolf = true})}, {target = target})
ok(hits.target[1].max > fMax, "Pack Frenzy hits harder than Feral Command")

-- an ally aimed at: the nearest enemy takes it instead
local ally = creature("ally", 0, 0, {ally = true})
local enemy = creature("enemy", 2, 0)
mobs = {ally, enemy}
res = cast("howl", {creature("War Wolf", 1, 1, {wolf = true})}, {target = ally})
ok(res == true and hits.enemy ~= nil and hits.ally == nil, "an ally target: the nearest enemy takes the spell")
-- no enemy at all
mobs = {ally}
res = cast("feral", {creature("War Wolf", 1, 1, {wolf = true})}, {target = ally})
ok(res == false and cancelled[1] == "No enemy in range.", "an ally and no enemy: cancelled")
-- no companion out
mobs = {target}
res = cast("howl", {}, {target = target})
ok(res == false and cancelled[1] == "You have no companion out. Call it with Wild Bond.", "no companion: the Wild Bond message")
-- no target
res = cast("howl", {creature("War Wolf", 1, 1, {wolf = true})}, {})
ok(res == false and #cancelled == 1, "no target: cancelled")
-- another monster in the summons (a pet) is no companion
res = cast("howl", {creature("Ember Whelp", 1, 1)}, {target = target})
ok(res == false and cancelled[1] ~= nil, "a summon that is no companion does not count")

-- the old per-spell code is gone: both old commands are three-line scripts now
for _, name in ipairs({"feral_command", "pack_frenzy"}) do
	local src = read("data/spells/chaos/beastmaster/" .. name .. ".lua")
	ok(not src:find("ChaosSpell.damageTarget", 1, true), name .. " has no cast code of its own")
end

if fails > 0 then error("wolf_spells_test: " .. fails .. " of " .. checks .. " checks failed") end
print("wolf_spells_test: " .. checks .. " checks ok")
