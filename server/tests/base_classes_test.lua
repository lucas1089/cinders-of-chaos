-- Run from the server/ folder: luajit tests/base_classes_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- The base server's vocation checks and the classes (tools/patch_base_classes.py, docs/CLASSES.md "Base scripts"):
-- condensed copies of the stock files (the lines the tool matches are verbatim; CRLF where the base server ships it),
-- patched by the tool, then run on a mock engine for every class: the stock-vocation helpers, the NPC spell teachers,
-- the familiars, the free first wand, exercise weapons, the party bonus, the vocation Oracles, the Dead Bureaucrats,
-- Arkulius, the upgrade slots and the highscores filter.
local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end
local function eq(a, b, what)
	ok(a == b, (what or "check") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local load = loadstring or load

local python = io.popen and io.popen("python3 -V 2>/dev/null")
local hasPython = python and (python:read("*a") or ""):find("Python 3")
if python then
	python:close()
end
if not hasPython then
	print("base_classes_test: python3 not found, skipped")
	return
end

-- the tool on one file: (path below data/, text) -> patched text, status
local function patch(rel, text)
	local path = os.tmpname()
	local f = assert(io.open(path, "wb"))
	f:write(text)
	f:close()
	local cmd = "python3 -I -c \"import sys; sys.path.insert(0, 'tools'); import patch_base_classes as p; "
		.. "t = open(sys.argv[2], newline='').read(); n, s = p.patch_file(sys.argv[1], t); "
		.. "open(sys.argv[2], 'w', newline='').write(n); print(s)\" '" .. rel .. "' " .. path
	local h = assert(io.popen(cmd))
	local status = (h:read("*a") or ""):gsub("%s+$", "")
	h:close()
	f = assert(io.open(path, "rb"))
	local out = f:read("*a")
	f:close()
	os.remove(path)
	return out, status
end

-- patch, check the second run and an unknown file, return the patched text
local function patched(rel, text, what)
	local out, status = patch(rel, text)
	eq(status, "patched", what .. ": the tool patches the stock lines")
	local again, status2 = patch(rel, out)
	eq(status2, "already", what .. ": second run")
	eq(again, out, what .. ": second run changes nothing")
	local _, status3 = patch(rel, "local x = 1\n")
	ok(status3:find("unexpected", 1, true) ~= nil, what .. ": a different file is reported (" .. status3 .. ")")
	if text:find("\r\n", 1, true) then
		ok(not out:gsub("\r\n", ""):find("\n", 1, true), what .. ": CRLF line ends kept")
	end
	return out
end

local function crlf(s)
	return (s:gsub("\n", "\r\n"))
end

-- ---------------------------------------------------------------- mock engine
VOCATION = {ID = {NONE = 0, SORCERER = 1, DRUID = 2, PALADIN = 3, KNIGHT = 4, MASTER_SORCERER = 5, ELDER_DRUID = 6,
	ROYAL_PALADIN = 7, ELITE_KNIGHT = 8, ILLUSIONIST = 9, ARCH_ILLUSIONIST = 10}}
VOCATION_NONE = 0
function table.contains(t, v)
	for _, x in ipairs(t) do
		if x == v then
			return true
		end
	end
	return false
end
isInArray = table.contains
local NAMES = {[0] = "None", [1] = "Mystic", [3] = "Ranger", [4] = "Warrior", [5] = "Elementalist", [7] = "Deadeye",
	[8] = "Juggernaut", [10] = "Illusionist", [11] = "Thief", [12] = "Ninja", [13] = "Samurai", [14] = "Berserker",
	[15] = "Beastmaster", [17] = "Monk", [18] = "Shadowfist", [19] = "Iron Sage", [20] = "Necromancer", [21] = "Lich",
	[22] = "Bone Lord", [23] = "Templar", [24] = "Inquisitor", [25] = "Sentinel"}
local BASE = {[5] = 1, [10] = 1, [7] = 3, [15] = 3, [8] = 4, [14] = 4, [12] = 11, [13] = 11, [18] = 17, [19] = 17,
	[21] = 20, [22] = 20, [24] = 23, [25] = 23}
local CLASSES = {1, 3, 4, 5, 7, 8, 10, 11, 12, 13, 14, 15, 17, 18, 19, 20, 21, 22, 23, 24, 25}
local function vocation(id)
	return {
		getId = function() return id end,
		getName = function() return NAMES[id] or ("voc" .. id) end,
		getBase = function() return vocation(BASE[id] or id) end,
	}
end
Player = {}
Player.__index = Player
local function player(id)
	local p = setmetatable({voc = id, items = {}, storage = {}, said = {}}, Player)
	return p
end
function Player.getVocation(self) return vocation(self.voc) end
function Player.addItem(self, id, n) self.items[id] = (self.items[id] or 0) + (n or 1) return true end

-- ---------------------------------------------------------------- 1. lib/core/player.lua
local STOCK_PLAYER = [[
function Player.getTotalMoney(self)
	return self:getMoney() + self:getBankBalance()
end


function Player.isSorcerer(self)
	return table.contains({VOCATION.ID.SORCERER, VOCATION.ID.MASTER_SORCERER}, self:getVocation():getId())
end

function Player.isDruid(self)
	return table.contains({VOCATION.ID.DRUID, VOCATION.ID.ELDER_DRUID}, self:getVocation():getId())
end

function Player.isKnight(self)
	return table.contains({VOCATION.ID.KNIGHT, VOCATION.ID.ELITE_KNIGHT}, self:getVocation():getId())
end

function Player.isIllusionist(self)
	return table.contains({VOCATION.ID.ILLUSIONIST, VOCATION.ID.ARCH_ILLUSIONIST}, self:getVocation():getId())
end

function Player.isPaladin(self)
	return table.contains({VOCATION.ID.PALADIN, VOCATION.ID.ROYAL_PALADIN}, self:getVocation():getId())
end

function Player.isMage(self)
	return table.contains({VOCATION.ID.SORCERER, VOCATION.ID.MASTER_SORCERER, VOCATION.ID.DRUID, VOCATION.ID.ELDER_DRUID},
		self:getVocation():getId())
end

function Player.sendWeatherEffect(self, groundEffect, fallEffect, thunderEffect)
end
]]
local playerLib = patched("lib/core/player.lua", STOCK_PLAYER, "player.lua")
-- an install that add_vocations.py patched first (Berserker / Beastmaster in the lists) ends the same
local former = STOCK_PLAYER:gsub("ELITE_KNIGHT}", "ELITE_KNIGHT, 14}"):gsub("ROYAL_PALADIN}", "ROYAL_PALADIN, 15}")
eq((patch("lib/core/player.lua", former)), playerLib, "player.lua: an add_vocations.py install ends the same")
ok(playerLib:find("function Player.getTotalMoney", 1, true) and playerLib:find("function Player.sendWeatherEffect", 1, true),
	"player.lua: the functions around are kept")
assert(load(playerLib))()

-- the expected stock role of every class (docs/CLASSES.md "Base scripts")
local ROLE = {[1] = "sorcerer", [5] = "sorcerer", [20] = "sorcerer", [21] = "sorcerer", [22] = "sorcerer",
	[10] = "druid",
	[3] = "paladin", [7] = "paladin", [15] = "paladin", [11] = "paladin", [12] = "paladin", [13] = "paladin",
	[17] = "paladin", [18] = "paladin", [19] = "paladin",
	[4] = "knight", [8] = "knight", [14] = "knight", [23] = "knight", [24] = "knight", [25] = "knight"}
local ASCENDED = {[5] = true, [7] = true, [8] = true, [10] = true, [12] = true, [13] = true, [14] = true, [15] = true,
	[18] = true, [19] = true, [21] = true, [22] = true, [24] = true, [25] = true}
local STOCK_BASE = {sorcerer = 1, druid = 2, paladin = 3, knight = 4}
for _, id in ipairs(CLASSES) do
	local p, role = player(id), ROLE[id]
	local name = NAMES[id]
	eq(p:getStockBaseVocationId(), STOCK_BASE[role], name .. ": stock base")
	eq(p:getStockVocationId(), STOCK_BASE[role] + (ASCENDED[id] and 4 or 0), name .. ": stock vocation (promoted when ascended)")
	eq(p:isSorcerer(), role == "sorcerer", name .. ": isSorcerer")
	eq(p:isDruid(), role == "druid", name .. ": isDruid")
	eq(p:isPaladin(), role == "paladin", name .. ": isPaladin")
	eq(p:isKnight(), role == "knight", name .. ": isKnight")
	eq(p:isMage(), role == "sorcerer" or role == "druid", name .. ": isMage")
	eq(p:isIllusionist(), false, name .. ": the base server's Illusionist is retired")
end
eq(player(0):getStockVocationId(), 0, "no vocation stays 0")
eq(player(0):isKnight(), false, "no vocation is no knight")
eq(player(99):getStockVocationId(), 99, "an unknown id counts as itself")
-- the Python table and the Lua table agree
local h = assert(io.popen("python3 -I -c \"import sys; sys.path.insert(0, 'tools'); import patch_base_classes as p; "
	.. "print(' '.join('%d=%d' % kv for kv in sorted(p.STOCK.items())))\""))
for k, v in (h:read("*a") or ""):gmatch("(%d+)=(%d+)") do
	eq(CHAOS_STOCK_VOCATION[tonumber(k)], tonumber(v), "STOCK[" .. k .. "] in Python and Lua")
end
h:close()

-- ---------------------------------------------------------------- NPC spell teachers (customModules.lua)
local STOCK_MODULES = [[
-- Adds a keyword which acts as a spell word
function KeywordHandler:addSpellKeyword(keys, parameters)
	local keys = keys
	keys.callback = FocusModule.messageMatcherDefault

	local npcHandler, spellName, price, vocationId = parameters.npcHandler, parameters.spellName, parameters.price, parameters.vocation
	local spellKeyword = self:addKeyword(keys, StdModule.say, {npcHandler = npcHandler, text = string.format("Do you want to learn the spell '%s' for %s?", spellName, price > 0 and price .. ' gold' or 'free')},
		function(player)
			local baseVocationId = player:getVocation():getBase():getId()
			if type(vocationId) == 'table' then
				return isInArray(vocationId, baseVocationId)
			else
				return vocationId == baseVocationId
			end
		end
	)

	spellKeyword:addChildKeyword({'yes'}, StdModule.learnSpell, {npcHandler = npcHandler, spellName = spellName, level = parameters.level, price = price})
	spellKeyword:addChildKeyword({'no'}, StdModule.say, {npcHandler = npcHandler, text = 'Maybe next time.', reset = true})
end
]]
local modules = patched("npc/lib/npcsystem/customModules.lua", STOCK_MODULES, "customModules.lua")
KeywordHandler, FocusModule, StdModule = {}, {}, {}
local conditions = {}
function KeywordHandler:addKeyword(keys, fn, params, condition)
	conditions[#conditions + 1] = condition
	return {addChildKeyword = function() end}
end
local SPELLS = {Bloodtrail = {"Warrior", "Juggernaut", "Berserker", "Ranger", "Deadeye", "Beastmaster", "Mystic",
	"Elementalist", "Illusionist", "Necromancer", "Lich", "Bone Lord"}}
function Spell(name)
	local list = SPELLS[name]
	return list and {vocation = function() return list end} or nil
end
assert(load(modules))()
KeywordHandler:addSpellKeyword({"find", "person"}, {spellName = "Bloodtrail", price = 80, level = 8, vocation = 4})
KeywordHandler:addSpellKeyword({"unknown"}, {spellName = "Not In Spells Xml", price = 0, level = 8, vocation = 4})
for _, id in ipairs(CLASSES) do
	local listed = table.contains(SPELLS.Bloodtrail, NAMES[id])
	eq(conditions[1](player(id)), listed, NAMES[id] .. ": offered Bloodtrail by its spells.xml list")
	eq(conditions[2](player(id)), ROLE[id] == "knight", NAMES[id] .. ": unknown spell, the NPC's stock vocation decides")
end

-- ---------------------------------------------------------------- familiars (pet_system.lua)
local STOCK_PET = crlf([[
function createPet(cid, petName)
  local player = Player(cid)
  if not player then
    return
  end

  local vocationId = getPlayerVocation(player)
  local vocationBaseId = player:getVocation():getId()

  local pet = nil

  if vocationId == VOCATION.ID.SORCERER or vocationBaseId == VOCATION.ID.MASTER_SORCERER then
      pet = "Sorcerer Familiar"
  elseif vocationId == VOCATION.ID.DRUID or vocationBaseId == VOCATION.ID.ELDER_DRUID then
      pet = "Druid Familiar"
  elseif vocationId == VOCATION.ID.KNIGHT or vocationBaseId == VOCATION.ID.ELITE_KNIGHT then
      pet = "Knight Familiar"
  elseif vocationId == VOCATION.ID.PALADIN or vocationBaseId == VOCATION.ID.ROYAL_PALADIN then
      pet = "Paladin Familiar"
  elseif vocationId == VOCATION.ID.ILLUSIONIST or vocationBaseId == VOCATION.ID.ARCH_ILLUSIONIST then
      pet = "Illusionist Familiar"
  end
  return pet
end
]])
local pet = patched("scripts/customs/pet_system/pet_system.lua", STOCK_PET, "pet_system.lua")
local playersById = {}
local function PlayerCtor(cid) return playersById[cid] end
local env = setmetatable({Player = PlayerCtor, getPlayerVocation = function(p) return p.voc end}, {__index = _G})
local chunk = assert(load(pet))
if setfenv then setfenv(chunk, env) else chunk = assert(load(pet, "pet", "t", env)) end
chunk()
local FAMILIAR = {knight = "Knight Familiar", paladin = "Paladin Familiar", sorcerer = "Sorcerer Familiar"}
for _, id in ipairs(CLASSES) do
	playersById[id] = player(id)
	local want = id == 10 and "Illusionist Familiar" or (id >= 17 and id <= 19) and "Druid Familiar"
		or (id >= 23) and "Paladin Familiar" or FAMILIAR[ROLE[id]]
	eq(env.createPet(id, ""), want, NAMES[id] .. ": familiar")
end

-- ---------------------------------------------------------------- the free first wand (Magido and the others)
local STOCK_WAND = [[
local function creatureSayCallback(cid, type, msg)
	local player = Player(cid)
	local items = {[1] = 2190, [2] = 2182}
	local itemId = items[player:getVocation():getBase():getId()]
	if msgcontains(msg, 'first rod') or msgcontains(msg, 'first wand') then
		if player:isMage() then
			player:addItem(itemId, 1)
		else
			npcHandler:say('Sorry, you aren\'t a druid either a sorcerer.', cid)
		end
	end
	return true
end
return creatureSayCallback
]]
local wand = patched("npc/scripts/Magido.lua", STOCK_WAND, "Magido.lua")
ok(not wand:find("druid either", 1, true), "Magido: the refusal names our classes")
local said
local wenv = setmetatable({Player = PlayerCtor, msgcontains = function(m, k) return m == k end,
	npcHandler = {say = function(_, text) said = text end}}, {__index = _G})
local wchunk = assert(load(wand))
if setfenv then setfenv(wchunk, wenv) else wchunk = assert(load(wand, "wand", "t", wenv)) end
local say = wchunk()
for _, id in ipairs(CLASSES) do
	local p = player(id)
	playersById[id], said = p, nil
	say(id, 1, "first wand")
	local want = (ROLE[id] == "sorcerer" and 2190) or (ROLE[id] == "druid" and 2182) or nil
	if want then
		eq(p.items[want], 1, NAMES[id] .. ": free first " .. (want == 2190 and "wand" or "rod"))
	else
		ok(next(p.items) == nil and said ~= nil, NAMES[id] .. ": no free wand, a refusal")
	end
end

-- ---------------------------------------------------------------- exercise weapons
local STOCK_EXERCISE = crlf([[
local skills = {
    [27732] = {id=SKILL_SWORD, voc={4,8}}, -- Exercise Sword
    [27733] = {id=SKILL_AXE, voc={4,8}}, -- Exercise Axe
    [27734] = {id=SKILL_CLUB, voc={4,8}}, -- Exercise Club
    [27758] = {id=SKILL_SHIELD, voc={4,8}}, -- Exercise Shield
    [27738] = {id=SKILL_SWORD, voc={4,8}}, -- Durable Exercise Sword
    [27735] = {id=SKILL_DISTANCE, voc={3,7}, range=CONST_ANI_SIMPLEARROW}, -- Exercise Bow
    [27736] = {id=SKILL_MAGLEVEL, voc={1,2,5,6,9,10}, range=CONST_ANI_SMALLICE}, -- Exercise Rod
    [27737] = {id=SKILL_MAGLEVEL, voc={1,2,5,6,9,10}, range=CONST_ANI_FIRE}, -- Exercise Wand
}
return skills
]])
SKILL_SWORD, SKILL_AXE, SKILL_CLUB, SKILL_SHIELD, SKILL_DISTANCE, SKILL_MAGLEVEL = 2, 3, 1, 5, 4, 6
local skills = assert(load(patched("actions/scripts/other/exercise_weapons.lua", STOCK_EXERCISE, "exercise_weapons.lua")))()
local LINE = {}
for _, id in ipairs(CLASSES) do
	LINE[id] = NAMES[BASE[id] or id]
end
local EXPECT = {
	[27732] = {Warrior = true, Thief = true, Templar = true}, [27733] = {Warrior = true, Templar = true},
	[27734] = {Warrior = true, Monk = true, Templar = true}, [27758] = {Warrior = true, Templar = true},
	[27738] = {Warrior = true, Thief = true, Templar = true}, [27735] = {Ranger = true, Thief = true},
	[27736] = {Mystic = true, Necromancer = true}, [27737] = {Mystic = true, Necromancer = true},
}
for item, lines in pairs(EXPECT) do
	for _, id in ipairs(CLASSES) do
		eq(table.contains(skills[item].voc, id), lines[LINE[id]] == true, NAMES[id] .. ": exercise item " .. item)
	end
end

-- ---------------------------------------------------------------- party shared experience
local STOCK_PARTY = [[
Party = {}
function Party:onShareExperience(exp)
	local sharedExperienceMultiplier = 1.20 --20%
	local vocationsIds = {}
	local rawExp = exp

	local vocationId = self:getLeader():getVocation():getBase():getId()
	if vocationId ~= VOCATION_NONE then
		table.insert(vocationsIds, vocationId)
	end

	for _, member in ipairs(self:getMembers()) do
		vocationId = member:getVocation():getBase():getId()
		if not table.contains(vocationsIds, vocationId) and vocationId ~= VOCATION_NONE then
			table.insert(vocationsIds, vocationId)
		end
	end

	local size = #vocationsIds
	if size > 1 then
		sharedExperienceMultiplier = 1.0 + ((size * (5 * (size - 1) + 10)) / 100)
	end

	exp = math.ceil((exp * sharedExperienceMultiplier) / (#self:getMembers() + 1))
	return exp
end
]]
assert(load(patched("events/scripts/party.lua", STOCK_PARTY, "party.lua")))()
local function party(ids)
	local members = {}
	for i = 2, #ids do
		members[#members + 1] = player(ids[i])
	end
	local pt = setmetatable({}, {__index = Party})
	pt.getLeader = function() return player(ids[1]) end
	pt.getMembers = function() return members end
	return pt:onShareExperience(1000)
end
eq(party({4, 3}), math.ceil(1000 * 1.3 / 2), "party: two lines, x1.3 as before")
eq(party({4, 3, 1, 11, 17}), math.ceil(1000 * 2.5 / 5), "party: five lines, x2.5")
eq(party({4, 3, 1, 11, 17, 20, 23}), math.ceil(1000 * 2.5 / 7), "party: seven lines count as five (x2.5, not x3.8)")
eq(party({4, 8, 14}), math.ceil(1000 * 1.2 / 3), "party: one line, no bonus for its ascended classes")

-- ---------------------------------------------------------------- the vocation Oracles
local STOCK_ORACLE = crlf([[
local config = {
	vocations = {
		["sorcerer"] = {
			text = "A SORCERER! ARE YOU SURE? THIS DECISION IS IRREVERSIBLE!",
			vocationId = 1,
			{{2175, 1}, {2190, 1}},
			{{2120, 1}}
		},
		["illusionist"] = {
			text = "AN ILLUSIONIST! ARE YOU SURE? THIS DECISION IS IRREVERSIBLE!",
			vocationId = 9,
			{{2175, 1}, {2190, 1}},
			{{2120, 1}}
		},
		["druid"] = {
			text = "A DRUID! ARE YOU SURE? THIS DECISION IS IRREVERSIBLE!",
			vocationId = 2,
			{{2175, 1}, {2182, 1}},
			{{2120, 1}}
		},
		["paladin"] = {
			text = "A PALADIN! ARE YOU SURE? THIS DECISION IS IRREVERSIBLE!",
			vocationId = 3,
			{{2525, 1}, {2389, 5}},
			{{2120, 1}, {2456, 1}}
		},
		["knight"] = {
			text = "A KNIGHT! ARE YOU SURE? THIS DECISION IS IRREVERSIBLE!",
			vocationId = 4,
			{{2525, 1}, {8601, 1}},
			{{8602, 1}}
		}
	}
}

function onCreatureAppear(cid) npcHandler:onCreatureAppear(cid) end
local ask = "AND WHAT PROFESSION HAVE YOU CHOSEN: {KNIGHT}, {PALADIN}, {SORCERER}, {ILLUSIONIST} OR {DRUID}?"
return config, ask
]])
local oracle = patched("npc/scripts/The Oracle3.lua", STOCK_ORACLE, "The Oracle3.lua")
local ocfg, ask = assert(load(oracle))()
ok(ask:find("{WARRIOR}, {RANGER}, {MYSTIC} OR {THIEF}", 1, true) ~= nil, "Oracle: offers the base classes")
local WORDS = {warrior = 4, knight = 4, ranger = 3, paladin = 3, mystic = 1, sorcerer = 1, druid = 1, illusionist = 1, thief = 11}
for word, id in pairs(WORDS) do
	local v = ocfg.vocations[word]
	eq(v and v.vocationId, id, "Oracle: '" .. word .. "' chooses")
	-- the equipment is looked up by the class name after the vocation is set
	local byName = ocfg.vocations[NAMES[id]:lower()]
	ok(byName and type(byName[1]) == "table" and type(byName[2]) == "table", "Oracle: equipment for " .. NAMES[id])
end
for _, v in pairs(ocfg.vocations) do
	ok(v.vocationId ~= 2 and v.vocationId ~= 9, "Oracle: no retired vocation id")
end

-- ---------------------------------------------------------------- Dead Bureaucrats, Arkulius, portals
local STOCK_B4 = [[
local config = {
	[1] = "S O R C E R E R",
	[2] = "D R U I D",
	[3] = "P A L A D I N",
	[4] = "K N I G H T"
}
return config
]]
local b4 = assert(load(patched("npc/scripts/A Dead Bureaucrat4.lua", STOCK_B4, "A Dead Bureaucrat4.lua")))()
local STOCK_B1 = [[
local config = {
	[1] = "wand",
	[2] = "rod",
	[3] = "bow",
	[4] = "sword"
}
return config
]]
local b1 = assert(load(patched("npc/scripts/A Dead Bureaucrat1.lua", STOCK_B1, "A Dead Bureaucrat1.lua")))()
for _, base in ipairs({1, 3, 4, 11, 17, 20, 23}) do
	eq(b4[base], (NAMES[base]:upper():gsub("(%S)", "%1 "):gsub(" $", "")), "Bureaucrat4: the class " .. NAMES[base])
	ok(type(b1[base]) == "string", "Bureaucrat1: a weapon for " .. NAMES[base])
end

local STOCK_ARKULIUS = crlf([[
local function reward(player)
    return (player:isSorcerer() or player:isIllusionist()) and 8867 or
                        player:isDruid() and 8869 or
                        player:isPaladin() and 8853 or
                        player:isKnight() and 8883 or
                        2160
end
return reward
]])
local reward = assert(load(patched("npc/scripts/Arkulius.lua", STOCK_ARKULIUS, "Arkulius.lua")))()
for _, id in ipairs(CLASSES) do
	local want = ({sorcerer = 8867, druid = 8869, knight = 8883})[ROLE[id]]
		or ((id == 3 or id == 7) and 8853 or 8887)
	eq(reward(player(id)), want, NAMES[id] .. ": elemental spheres reward")
end

local STOCK_PORTAL = [[
local portals = {[1] = {vocation = 1}, [2] = {vocation = 2}}
local function enter(player, uid)
	local portal = portals[uid]
	if not portal or player:getVocation():getBase():getId() ~= portal.vocation or player:getLevel() < 30 then
		return 'Only ' .. (portal.vocation == 1 and 'Sorcerers' or 'Druids') .. ' of level 30 or higher may enter this portal.'
	end
	return true
end
return enter
]]
local enter = assert(load(patched("movements/scripts/others/shrinesportal.lua", STOCK_PORTAL, "shrinesportal.lua")))()
function Player.getLevel() return 50 end
for _, id in ipairs(CLASSES) do
	eq(enter(player(id), 1) == true, ROLE[id] == "sorcerer", NAMES[id] .. ": fire / energy shrine")
	eq(enter(player(id), 2) == true, ROLE[id] == "druid", NAMES[id] .. ": ice / earth shrine")
end
ok(tostring(enter(player(4), 2)):find("Illusionists", 1, true) ~= nil, "shrine: the refusal names our classes")

-- ---------------------------------------------------------------- upgrade slots, highscores
local STOCK_UPGRADE = [[
local vocationAttributes = {
    ["Knight"] = {"Axe", "Club", "Sword", "Shield"},
    ["Illusionist"] = {"MagicLevel", "Shield"},
    ["Arch Illusionist"] = {"MagicLevel", "Shield"},
}

function stringVocations(vocationString)
    local vocationMap = {
        ["knights"] = "Knight",
        ["illusionists"] = "Illusionist",
        ["arch illusionists"] = "Arch Illusionist",
    }
    for key, value in pairs(vocationMap) do
        if vocationString:lower():find(key) then
            return value
        end
    end
    return nil
end
return vocationAttributes
]]
local attrs = assert(load(patched("scripts/customs/upgrade/upgrade_slot_item.lua", STOCK_UPGRADE, "upgrade_slot_item.lua")))()
for _, id in ipairs(CLASSES) do
	-- the engine writes the lower case name + "s" ("bone lords", "thiefs")
	local found = stringVocations("it can only be wielded properly by " .. NAMES[id]:lower() .. "s")
	ok(found ~= nil and attrs[found] ~= nil, NAMES[id] .. ": upgrade slot attributes from the item text")
end

local STOCK_HIGH = crlf([[
local function filter(req)
  local vocation    = tonumber(req.vocation) or 0
  local vocs        = req.vocations or {}
  if #vocs == 0 then vocs = { vocation } end
  local vocFilter = table.concat(vocs, ",")
  return vocFilter
end
return filter
]])
local filter = assert(load(patched("scripts/customs/highscores/highscores.lua", STOCK_HIGH, "highscores.lua")))()
local f4 = "," .. filter({vocations = {4}}) .. ","
for _, id in ipairs({4, 23}) do
	ok(f4:find("," .. id .. ",", 1, true) ~= nil, "highscores: Knight (4) lists " .. NAMES[id])
end
ok(not f4:find(",3,", 1, true), "highscores: Knight (4) does not list the Ranger")
eq(filter({vocations = {"1) OR (1=1"}}), "0", "highscores: no SQL from the request")
eq(filter({vocation = 11}):match("^11"), "11", "highscores: a class id stays")

if fails > 0 then
	print(("base_classes_test: %d of %d checks failed"):format(fails, checks))
	os.exit(1)
end
print(("base_classes_test: all %d checks passed"):format(checks))
