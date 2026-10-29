-- Run from the server/ folder: luajit tests/class_spells_test.lua (mock engine API; CI runs it with luajit and lua5.3)
-- Owner report 2026-10-17: after the Vocation Change the character kept the old class's spells and got none of the new
-- class's. Covers the plan (class_spells_core.lua), the engine part (class_spells.lua, mocked player and spellbook), the
-- spellbook push and the wiring of every class change (ascension.lua afterVocationChange, shop_services.lua).
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
local function eq(a, b, m) if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end end
local function read(path) local f = assert(io.open(path, "r")); local t = f:read("*a"); f:close(); return t end

dofile("data/scripts/chaos/class_spells_core.lua")
local C = ChaosClassSpellsCore
local BEAST, DEADEYE, MYSTIC = 15, 7, 1

local spells = {
	{name = "Wolf Call", level = 20, needLearn = true, vocations = {BEAST}},
	{name = "Quiver Rain", level = 50, needLearn = true, vocations = {DEADEYE, 3}},
	{name = "Deep Arrow", level = 300, needLearn = true, vocations = {DEADEYE}},
	{name = "Shared Shot", level = 10, needLearn = true, vocations = {BEAST, DEADEYE}},
	{name = "Mystic Bolt", level = 1, needLearn = true, vocations = {MYSTIC}},
	{name = "Free Spell", level = 1, vocations = {DEADEYE}},               -- needlearn=0: never taught or forgotten
	{name = "No List", level = 1, needLearn = true, vocations = {}},
}
local known = {["Wolf Call"] = true, ["Shared Shot"] = true, ["Mystic Bolt"] = true}
local function knows(name) return known[name] end

-- a Beastmaster becomes a Deadeye at level 100
local plan = C.plan(spells, DEADEYE, 100, knows)
eq(table.concat(plan.forget, ","), "Mystic Bolt,Wolf Call", "the old class's spells go (sorted)")
eq(table.concat(plan.learn, ","), "Quiver Rain", "the new class's spells the level allows are taught")
eq(plan.keep, 1, "a spell both classes list stays")
-- level gates the teaching, never the forgetting
eq(table.concat(C.plan(spells, DEADEYE, 49, knows).learn, ","), "", "below level 50: nothing taught")
eq(table.concat(C.plan(spells, DEADEYE, 300, knows).learn, ","), "Deep Arrow,Quiver Rain", "level 300: the late spell too")
eq(table.concat(C.plan(spells, DEADEYE, 49, knows).forget, ","), "Mystic Bolt,Wolf Call", "forgetting needs no level")
-- already right: nothing to do (idempotent)
known = {["Quiver Rain"] = true, ["Shared Shot"] = true}
plan = C.plan(spells, DEADEYE, 100, knows)
eq(#plan.forget + #plan.learn, 0, "a second pass changes nothing")
eq(#C.plan(nil, DEADEYE, 100, knows).forget, 0, "no spell list")
eq(C.lists({vocations = {1, 5}}, 5), true, "lists"); eq(C.lists({}, 5), false, "no vocations listed")

-- the line spell quests' spells (spellquest.lua): needlearn spells the line lists, but only the quest teaches them
do
	local qspells = {
		{name = "Keepfall", level = 500, needLearn = true, vocations = {DEADEYE, 3, BEAST}},
		{name = "Other Line", level = 500, needLearn = true, vocations = {MYSTIC}},
		{name = "Quiver Rain", level = 50, needLearn = true, vocations = {DEADEYE, 3}},
	}
	local quest = {isQuest = function(name) return name == "Keepfall" or name == "Other Line" end}
	local k = {["Other Line"] = true}
	local p2 = C.plan(qspells, DEADEYE, 900, function(name) return k[name] end, quest)
	eq(table.concat(p2.learn, ","), "Quiver Rain", "a quest spell is never taught by the class change")
	eq(table.concat(p2.forget, ","), "Other Line", "a quest spell of another line is forgotten")
	k = {["Keepfall"] = true}
	p2 = C.plan(qspells, DEADEYE, 900, function(name) return k[name] end, quest)
	eq(#p2.forget, 0, "a quest spell of the line stays"); eq(p2.keep, 1, "and counts as kept")
	eq(table.concat(C.plan(qspells, DEADEYE, 900, function() return false end).learn, ","), "Keepfall,Quiver Rain",
		"without the quest hook the old rule applies")
end

-- ------------------------------------------------------------------ the engine part
dofile("data/scripts/chaos/class_spells.lua")
local S = ChaosClassSpells
local learned, calls = {["Wolf Call"] = true, ["Shared Shot"] = true}, {}
local vocId = DEADEYE
local player = {id = 5}
function player:getVocation() return {getId = function() return vocId end} end
function player:getLevel() return 100 end
function player:hasLearnedSpell(name) return learned[name] == true end
function player:learnSpell(name) learned[name] = true; calls[#calls + 1] = "learn " .. name; return true end
function player:forgetSpell(name) learned[name] = nil; calls[#calls + 1] = "forget " .. name; return true end
local refreshed = 0
ChaosSpellbook = {get = function() return spells end, refresh = function(p) refreshed = refreshed + 1 return true end}
local r = S.sync(player)
eq(r.forget, 1, "Wolf Call forgotten"); eq(r.learn, 1, "Quiver Rain learned")
eq(learned["Wolf Call"], nil, "the Beastmaster spell is gone"); eq(learned["Quiver Rain"], true, "the Deadeye spell is there")
eq(learned["Shared Shot"], true, "shared spells stay"); eq(refreshed, 1, "the client's Spellbook is refreshed")
r = S.sync(player)
eq(r.forget + r.learn, 0, "second run: nothing"); eq(#calls, 2, "no repeated engine calls")
S.sync(player, true); eq(refreshed, 2, "quiet: no refresh")
eq(S.sync(nil).learn, 0, "no player")
-- an engine without forgetSpell must not break a class change
function player:forgetSpell() error("no such method") end
learned["Mystic Bolt"] = true
eq(S.sync(player, true).forget, 0, "a failing forgetSpell is skipped")
ChaosSpellbook = nil
eq(S.sync(player, true).learn, 0, "without the spellbook: nothing to do")

-- the engine part with the spell quest: its sync teaches the done spells of the line and forgets the others
do
	local forgot, taught = {}, {}
	ChaosSpellQuest = {
		isQuestSpell = function(name) return name == "Keepfall" end,
		sync = function() return {forget = 2, learn = 1} end
	}
	local qplayer = {}
	function qplayer:getVocation() return {getId = function() return DEADEYE end} end
	function qplayer:getLevel() return 900 end
	function qplayer:hasLearnedSpell() return false end
	function qplayer:learnSpell(name) taught[#taught + 1] = name; return true end
	function qplayer:forgetSpell(name) forgot[#forgot + 1] = name; return true end
	ChaosSpellbook = {get = function() return {{name = "Keepfall", level = 500, needLearn = true, vocations = {DEADEYE}}} end,
		refresh = function() end}
	local res = S.sync(qplayer)
	eq(#taught, 0, "the class sync does not teach a quest spell")
	eq(res.forget, 2, "the quest sync's numbers are added"); eq(res.learn, 1, "learn too")
	ChaosSpellQuest = nil
end

-- ------------------------------------------------------------------ every Chaos spell is needlearn="0"
local xml = read("data/spells/chaos/spells_chaos.xml")
-- except the line spell quests' spells (spellquest_config.lua): only their quest teaches them
dofile("data/scripts/chaos/chaos_constants.lua")
local questNames = {}
for _, line in ipairs(dofile("data/scripts/chaos/spellquest_config.lua").lines) do
	for _, name in ipairs(line.spells) do questNames[name:lower()] = true end
end
local total, learn = 0, 0
for tag in xml:gmatch("<instant ([^>]*)>") do
	total = total + 1
	local name = tag:match('name="([^"]*)"')
	if tag:find('needlearn="1"', 1, true) and not (name and questNames[name:lower()]) then learn = learn + 1 end
end
assert(total > 90, "the spell file is read")
eq(learn, 0, "no Chaos spell needs teaching: the vocation and the level decide, so a class change swaps them at once")

-- ------------------------------------------------------------------ wiring
local ascension = read("data/scripts/chaos/ascension.lua")
local after = ascension:match("function C%.afterVocationChange%(player%)(.-)\nend\n")
assert(after and after:find("ChaosClassSpells.sync(player)", 1, true), "afterVocationChange runs the spell sync")
local shop = read("data/scripts/chaos/shop_services.lua")
assert(shop:find("ChaosClasses.afterVocationChange(player)", 1, true), "the store's Vocation Change calls afterVocationChange")
assert(shop:find("Your spellbook now lists the spells of your new class", 1, true), "and tells the player")
assert(read("data/scripts/chaos/i18n_strings.lua"):find("Your spellbook now lists the spells of your new class", 1, true), "pt-BR text")
print("class_spells tests OK")
