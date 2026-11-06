-- Run from the server/ folder: luajit tests/charsheet_test.lua (and lua5.3; CI runs both)
-- The character sheet (charsheet_core.lua, charsheet.lua; O423): the cleaned numbers, the text of the sections shown by
-- Info & Services > Character Info, what is read off a mocked player, and that every text has a pt-BR entry.
local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/charsheet_core.lua")
local K = ChaosCharSheet

local raw = {attack = 40, hit = 1234.5, maxHit = 98765, attackSpeed = 9, critChance = 12.34, critAmount = 55,
	lifeLeech = {chance = 5, amount = 3}, manaLeech = {chance = 2, amount = 1},
	damage = {{k = "fire", pct = 20}, {k = "physical", pct = 8}}, defense = 30, armor = 22, mitigation = 0.3456,
	resist = {{k = "fire", pct = 40}, {k = "death", pct = -10}, {k = "ice", pct = 0}}, maxHealth = 5000, maxMana = 2500,
	moveSpeed = 450}
local sheet = K.clean(raw)
eq(sheet.hit, 1234.5, "hit kept")
eq(sheet.mitigation, 34.6, "mitigation is a percent")
eq(#sheet.resist, 2, "a zero resistance is not a row")
eq(K.clean({}), nil, "empty")

-- the text, in English (tx = string.format) and with every key recorded
local seen = {}
local function tx(fmt, ...)
	seen[fmt] = true
	return select("#", ...) > 0 and string.format(fmt, ...) or fmt
end
local own = {level = 120, vocation = "Berserker", health = 4000, maxHealth = 5000, mana = 1000, maxMana = 2500, capacity = 3200,
	speed = 450, expToNext = 123456, expPercent = 42.5, magic = {level = 12, percent = 30},
	skills = {{name = "Sword Fighting", level = 90, percent = 12}, {name = "Shielding", level = 80, percent = 0}}, soul = 100,
	stamina = 2400 + 5}
local text = K.text(sheet, own, tx)
local function at(s) return text:find(s, 1, true) end
eq(at("[ Offense ]") < at("[ Defense ]"), true, "offense first")
eq(at("[ Defense ]") < at("[ Resistances ]"), true, "then defense")
eq(at("[ Resistances ]") < at("[ Character ]"), true, "resistances before the character rows")
eq(at("Weapon attack: 40") ~= nil, true, "attack")
eq(at("Highest hit: 98,765") ~= nil, true, "highest hit with a thousands separator")
eq(at("Attack speed: +9%") ~= nil, true, "attack speed")
eq(at("Critical chance: 12.3%") ~= nil, true, "crit chance")
eq(at("Life leech: 5% chance, 3% of the hit") ~= nil, true, "life leech")
eq(at("Fire damage: +20%") ~= nil, true, "damage bonus")
eq(at("Physical damage taken from monsters: -34.6%") ~= nil, true, "damage reduction")
eq(at("Fire: 40%") ~= nil, true, "resistance")
eq(at("Death: -10%") ~= nil, true, "negative resistance")
eq(at("Ice: 0%"), nil, "no zero resistance")
eq(at("Health: 4,000 / 5,000") ~= nil, true, "health")
eq(at("Experience to next level: 123,456 (42.5% done)") ~= nil, true, "experience")
eq(at("Sword Fighting: 90 (12%)") ~= nil, true, "skill with percent")
eq(at("Stamina: 40h 05min") ~= nil, true, "stamina")

-- without the character rows (what a viewer would get): no section; nothing at all for an empty sheet
eq(K.text(sheet, nil, tx):find("[ Character ]", 1, true), nil, "no character section for others")
eq(K.text(nil, nil, tx), "", "empty sheet: no text")

-- every text used has a pt-BR entry
local pt = dofile("data/scripts/chaos/i18n_strings.lua")["pt-BR"]
local missing = {}
for key in pairs(seen) do
	if not pt[key] then missing[#missing + 1] = key end
end
for _, key in ipairs({"Fist Fighting", "Club Fighting", "Axe Fighting", "Distance Fighting", "Fishing"}) do
	if not pt[key] then missing[#missing + 1] = key end
end
for _, name in pairs(K.TYPES) do
	if not pt[name] then missing[#missing + 1] = name end
end
eq(table.concat(missing, "; "), "", "texts without a pt-BR entry")

-- reading a mocked player (every source optional)
local P = {}
function P:getId() return 1 end
function P:getLevel() return 100 end
function P:getMaxHealth() return 4000 end
function P:getMaxMana() return 1500 end
function P:getHealth() return 3000 end
function P:getMana() return 500 end
function P:getSpeed() return 400 end
function P:getFreeCapacity() return 250000 end
function P:getExperience() return 150 end
function P:getMagicLevel() return 7 end
function P:getStorageValue(k) return k == Chaos.storage.maxHit and 777 or -1 end
function P:getVocation() return {getName = function() return "Sentinel" end} end
function P:getSoul() return 50 end
function P:getStamina() return 600 end
SKILL_SWORD = 2
function P:getEffectiveSkillLevel(id) return id == 2 and 66 or nil end
function P:getSkillPercent() return 25 end
Game = {getExperienceForLevel = function(l) return l * 100 end}
ChaosCombatStats = {compute = function() return {attack = 10, damage = 50, defense = 5, armor = 6, mitigation = 0.1} end}
ChaosDeathRecap = {resistOf = function(_, el) return el == "fire" and 25 or 0 end}
dofile("data/scripts/chaos/charsheet.lua")
local r = K.read(P)
eq(r.maxHit, 777, "highest hit from the storage")
eq(r.maxHealth, 4000, "max health")
eq(r.attack, 10, "attack from the combat stats")
eq(r.resist[2].pct, 25, "fire resistance")
eq(K.clean(r).resist[1].k, "fire", "only fire is above 0")
local c = K.readOwn(P)
eq(c.vocation, "Sentinel", "vocation")
eq(c.capacity, 2500, "capacity in whole units")
eq(c.expToNext, 9950, "experience to the next level")
eq(c.skills[1].name, "Sword Fighting", "a skill that exists")
eq(#c.skills, 1, "skills the engine has no id for are left out")
eq(c.soul, 50, "soul")
print("charsheet_test: " .. checks .. " checks ok")
