-- Run from the server/ folder: luajit tests/gapfx_test.lua (and lua5.3; CI runs both)
-- Effects for roles that had none (O606, client pair 73, data/lib/chaos_gapfx.lua and the generated chaos_gapfx_ids.lua):
-- the gate is config.lua chaosClientPair >= 73; below it a sender does exactly what it did (the stock effect or nothing),
-- with it the new id goes out at its send offset; the ids are the block 5190.. in order; every key has an effect and a
-- sender that asks for it; the boss warning pulse becomes the strike circle only with the gate on.
local n = 0
local function eq(a, b, m)
	n = n + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end
local function ok(v, m)
	n = n + 1
	if not v then
		error(m or "not true", 2)
	end
end
local function slurp(path)
	local f = assert(io.open(path, "r"), path)
	local text = f:read("*a")
	f:close()
	return text
end

-- ---------------------------------------------------------------- a small engine
local sent = {}
local PosMeta = {}
PosMeta.__index = PosMeta
function PosMeta:sendMagicEffect(id, who)
	sent[#sent + 1] = {x = self.x, y = self.y, z = self.z, id = id, who = who}
end
function Position(x, y, z)
	return setmetatable({x = x, y = y, z = z}, PosMeta)
end
local function creature(x, y, z)
	return {getPosition = function() return Position(x, y, z) end}
end
CONST_ME_FIREWORK_YELLOW = 29

local C = dofile("data/lib/chaos_gapfx.lua")
eq(C, ChaosGapFx, "the global")
eq(C.PAIR, 73, "pair 73")
eq(C.ON, false, "no config.lua next to the tests: the gate is off")

-- ---------------------------------------------------------------- the pair record
eq(C.parsePair("chaosClientPair = 73"), 73, "plain")
eq(C.parsePair("x = 1\nchaosClientPair=72 -- shipped\ny = 2\n"), 72, "comment, no spaces, other lines")
eq(C.parsePair("chaosClientPair = \"abc\"\n"), nil, "not a number")
eq(C.parsePair(nil), nil, "no text")
eq(C.recordedPair("tests/no_such_config.lua"), nil, "no file")

-- the two ways a sender asks (the idioms of the scripts)
local function daily(player) -- in place of a shared effect
	if not (ChaosGapFx and ChaosGapFx.on(player, "daily")) then
		player:getPosition():sendMagicEffect(CONST_ME_FIREWORK_YELLOW)
	end
end
local function talent(player) -- where nothing was sent
	if ChaosGapFx then
		ChaosGapFx.on(player, "talent_point")
	end
end

-- ---------------------------------------------------------------- gate off: exactly as before
ChaosVfx = {warning_zone = {id = 451, dx = 1, dy = 1, ms = 1328}, warning_fill = {id = 450, dx = 1, dy = 2, ms = 1328}}
local ann = creature(100, 200, 7)
daily(ann)
eq(#sent, 1, "gate off: one effect")
eq(sent[1].id, 29, "gate off: the yellow firework of before")
eq(sent[1].x, 100, "gate off: on the player's tile")
talent(ann)
eq(#sent, 1, "gate off: an event that sent nothing sends nothing")
eq(C.at(Position(1, 2, 7), "bounty"), false, "gate off: at answers false")
eq(C.to(ann, Position(1, 2, 7), "tele_zone"), false, "gate off: to answers false")
eq(C.name("daily"), nil, "gate off: no name")
eq(C.ms("countdown"), 0, "gate off: no length, so no timer is set")
eq(C.telegraph("warning_zone"), "warning_zone", "gate off: the red pulse of before")
eq(C.telegraph("warning_fill"), "warning_fill", "gate off: the red fill of before")
eq(C.onModule(), false, "gate off: the players with game_telegraph get no sprite")
eq(ChaosVfx.gx_daily, nil, "gate off: no name merged")
eq(ChaosGapFxIds, nil, "gate off: the ids are not even loaded")
eq(#sent, 1, "gate off: nothing else went out")

-- ---------------------------------------------------------------- gate on
C.ON = true
C.loaded = nil
sent = {}
ok(C.live(), "gate on: the ids load")
local I = ChaosGapFxIds
ok(I, "the generated ids")
daily(ann)
eq(#sent, 1, "gate on: one effect, the firework is not sent as well")
local e = I.effects.gx_daily
eq(sent[1].id, e.id, "gate on: the new id")
eq(sent[1].x, 100 + e.dx, "gate on: the send offset x")
eq(sent[1].y, 200 + e.dy, "gate on: the send offset y")
eq(sent[1].z, 7, "the floor")
eq(sent[1].who, nil, "for everybody near")
talent(ann)
eq(sent[2].id, I.effects.gx_talent_point.id, "gate on: the event that sent nothing has its effect")
ok(C.at({x = 5, y = 6, z = 7}, "rift"), "a plain table is a position")
eq(sent[3].id, I.effects.gx_rift.id, "at")
ok(C.to(ann, Position(5, 6, 7), "tele_zone"), "to one player")
eq(sent[4].who, ann, "only that player")
eq(C.at(Position(5, 6, 7), "no_such_key"), false, "an unknown key sends nothing")
eq(C.at(nil, "daily"), false, "no position sends nothing")
eq(C.at({x = 1}, "daily"), false, "half a position sends nothing")
eq(C.on(nil, "daily"), false, "no creature sends nothing")
eq(C.on({getPosition = function() error("gone") end}, "daily"), false, "a creature that is gone sends nothing")
eq(#sent, 4, "none of those went out")
eq(C.ms("countdown"), I.effects.gx_countdown.ms, "the length of an effect")

-- the boss warning pulse (owner order): the strike circle, its two parts
eq(C.telegraph("warning_zone"), "gx_tele_zone", "the danger pulse")
eq(C.telegraph("warning_fill"), "gx_tele_fill", "the last pulse before the hit")
eq(C.telegraph("big_shock_blood_9"), "big_shock_blood_9", "another name is not touched")
eq(C.telegraph(nil), nil, "no name")
eq(ChaosVfx.gx_tele_zone.id, I.effects.gx_tele_zone.id, "the name is in ChaosVfx, where the senders' fx looks")
eq(C.onModule(), true, "the players with game_telegraph get the strike circle too")
C.onModuleClients = false
eq(C.onModule(), false, "the switch")
C.onModuleClients = true
-- a 3 x 3 slot holds the ring: the canvas is 3 x 3 and its middle is the slot's centre
local csv = slurp("../client/tools/sprites/art_import/gap_fx.csv")
for _, name in ipairs({"gx_tele_zone", "gx_tele_fill"}) do
	local w, h, dx, dy = csv:match("\neffect,%d+," .. name .. ",%d+,%x+,%d+,%d+,%d+,%d+,%d+,%d+,%d+,%a+,%-?%d+,%-?%d+,(%d+),(%d+),%d+,%d+,(%d+),(%d+),")
	eq(w .. "x" .. h, "3x3", name .. " fits a 3 x 3 slot")
	eq(dx .. "," .. dy, "1,1", name .. " is centred on the slot")
end

-- the milestone look by quarter of the list
eq(C.milestoneKey(1, 15), "milestone_bronze", "first")
eq(C.milestoneKey(4, 15), "milestone_silver", "second quarter")
eq(C.milestoneKey(8, 15), "milestone_gold", "third quarter")
eq(C.milestoneKey(12, 15), "milestone_diamond", "last quarter")
eq(C.milestoneKey(15, 15), "milestone_diamond", "the last")
eq(C.milestoneKey(nil, 0), "milestone_bronze", "no list")
for i = 1, 15 do
	ok(C.events[C.milestoneKey(i, 15)], "milestone " .. i .. " has an effect")
end

-- ---------------------------------------------------------------- the ids: one block, in order, no hole
eq(I.pair, C.PAIR, "the pair of the ids")
eq(I.first, 5190, "the block starts at 5190")
local byId, count = {}, 0
for name, v in pairs(I.effects) do
	ok(name:sub(1, 3) == "gx_", name .. ": the prefix")
	ok(not byId[v.id], name .. ": its id is used once")
	byId[v.id] = name
	ok(v.ms > 0 and v.dx >= 0 and v.dy >= 0, name .. ": length and offset")
	count = count + 1
end
eq(count, I.count, "the count")
for id = I.first, I.first + I.count - 1 do
	ok(byId[id], "no hole at " .. id)
end

-- ---------------------------------------------------------------- every effect has a key, every key a sender
local where = {
	talent_point = "passivetree.lua", class_unlock = "class_unlocks.lua", spell_mastery = "spell_masteries.lua",
	paragon = "paragon.lua", title = "descent.lua", rank_up = "professions.lua", class_change = "ascension.lua",
	milestone_bronze = "../../lib/chaos_gapfx.lua", milestone_silver = "../../lib/chaos_gapfx.lua",
	milestone_gold = "../../lib/chaos_gapfx.lua", milestone_diamond = "../../lib/chaos_gapfx.lua", respec = "respec.lua",
	quest_complete = "mainquest.lua", daily = "daily.lua", bounty = "bounty.lua", chest_royal = "weeklychest.lua",
	season_tier = "seasonpass.lua", set_complete = "itemsets.lua", card_common = "cards.lua", card_rare = "cards.lua",
	relic = "uber.lua", jackpot = "prizes.lua", masterwork = "crafting.lua",
	tele_zone = "../../lib/chaos_gapfx.lua", tele_fill = "../../lib/chaos_gapfx.lua", spread = "boss_mechanics.lua",
	chase = "boss_mechanics.lua", safe_zone = "boss_mechanics.lua", countdown = "boss_mechanics.lua",
	meteor_shadow = "boss_mechanics.lua", gate = "townportal.lua", rift_open = "rift.lua", rift = "rift.lua",
	rift_close = "rift.lua", waystone = "waystone_mods.lua", dungeon_beacon = "dungeons.lua", spawn_in = "raid.lua",
	mine_armed = "../../spells/chaos/_snares.lua", trap_spikes = "../../spells/chaos/_snares.lua",
	mining = "professions.lua", herb = "professions.lua", fishing = "professions.lua", craft_success = "crafting.lua",
	craft_fail = "crafting.lua", enchant = "gems.lua", boss_beacon = "worldboss.lua", summon_gate = "guildboss.lua",
	rift_seal = "rift.lua",
}
local keys = 0
local names = {}
for key, name in pairs(C.events) do
	keys = keys + 1
	ok(I.effects[name], key .. ": its effect is in the ids")
	ok(not names[name], name .. ": one key")
	names[name] = key
	eq(C.name(key), name, key .. ": the name")
	local file = where[key]
	ok(file, key .. ": a sender is named in this test")
	ok(slurp("data/scripts/chaos/" .. file):find('"' .. key .. '"', 1, true), key .. ": " .. file .. " asks for it")
end
eq(keys, I.count, "every effect of the pair has a role")
-- the four senders of the warning pulse ask the lib for the name, the milestones script for its key
for _, file in ipairs({"boss_mechanics.lua", "uber.lua", "guildboss.lua", "raid.lua"}) do
	ok(slurp("data/scripts/chaos/" .. file):find("ChaosGapFx.telegraph(effect)", 1, true), file .. ": the warning pulse asks the lib")
end
ok(slurp("data/scripts/chaos/milestones.lua"):find("ChaosGapFx.milestoneKey(", 1, true), "milestones.lua asks for its key")
ok(slurp("data/scripts/chaos/telegraph.lua"):find("ChaosGapFx.onModule()", 1, true), "telegraph.lua asks for the switch")
ok(slurp("data/scripts/chaos/gapfx.lua"):find('dofile("data/lib/chaos_gapfx.lua")', 1, true), "the glue loads the lib")

-- no pack name in the server files
for _, p in ipairs({"data/lib/chaos_gapfx.lua", "data/lib/chaos_gapfx_ids.lua", "data/scripts/chaos/gapfx.lua"}) do
	local text = slurp(p):lower()
	ok(not text:find("mega" .. " vfx", 1, true) and not text:find("mega" .. "_vfx", 1, true), p .. ": no pack name")
end

print("gapfx_test: " .. n .. " checks, 0 failed")
