-- Inspect Monster (client game_monsterinspect, extended opcode ChaosOpcodes.monsterInspect = 166; O721). Rules, limits
-- and every row of the window are in monster_inspect_core.lua (ChaosMonsterInspect, tests/monster_inspect_test.lua), the
-- numbers in monster_inspect_config.lua; see server/README.md "Inspect Monster (O721)".
--
-- Protocol (JSON {action, data}):
--   client -> server  inspect {cid}      the monster the player clicked (Inspect in the menu, or Shift + left click): the same
--                                        floor, within cfg.rangeX / rangeY tiles and in view; a request budget per player
--   server -> client  result {cid, name, level, tier, flags = [{key, name?}], outfit, health = {cur, max, pct, hidden?},
--                              family = {cat, race, diff}, mods = [{key, name, text}], exp = {base, tier?, rate?, total,
--                              bonus?, rank?}, resist = {elements = [{name, pct}], immune, conditions}, armour = {armor,
--                              defense, class, spell, weapon}, attacks = [{name, kind, element, chance, interval, min, max,
--                              range}], abilities = [{kind, name, ...}], speed = {base, now}, loot = {total, bands, rows,
--                              locked, tierText}, uniques = [{name, cid, boss, set}], areas = [{text, count}],
--                              bestiary = {kills, stage, th, next}}
--                     denied {code}      notfound | range | rate | bad | hidden
-- Every text is an English key the client translates. Health and damage numbers are in the viewer's display scale.
-- A result bigger than 8000 bytes goes through Chaos.sendChunked. Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosMonsterInspect then
	dofile("data/scripts/chaos/monster_inspect_core.lua")
end
Chaos.monsterInspectConfig = dofile("data/scripts/chaos/monster_inspect_config.lua")

local M = ChaosMonsterInspect
local B = ChaosBestiaryCore
local unpack = table.unpack or unpack
local cfg = Chaos.monsterInspectConfig
local OPCODE = ChaosOpcodes.monsterInspect or 166
local budget = {} -- player id -> bucket
local xmlFiles -- lower case monster name -> file of data/monster
local xmlCache = {} -- lower case monster name -> parsed file (false: none)

local function nowMs()
	return os.mtime and os.mtime() or os.time() * 1000
end

local function try(fn, ...)
	local ok, v = pcall(fn, ...)
	if ok then
		return v
	end
	return nil
end

local function call(obj, method, ...)
	if not obj or not obj[method] then
		return nil
	end
	local args = {...}
	return try(function() return obj[method](obj, unpack(args)) end)
end

local function typeNameOf(creature)
	return Chaos.monsterTypeName and Chaos.monsterTypeName(creature) or creature:getName()
end

local function send(player, data)
	Chaos.sendChunked(player, OPCODE, json.encode(data))
end

local function deny(player, code)
	send(player, {action = "denied", data = {code = code}})
end

-- ---------------------------------------------------------------- the monster file
local function fileIndex()
	if xmlFiles then
		return xmlFiles
	end
	xmlFiles = {}
	local f = io.open("data/monster/monsters.xml", "r")
	if f then
		for line in f:lines() do
			local name = line:match('name%s*=%s*"([^"]+)"')
			local file = line:match('file%s*=%s*"([^"]+)"')
			if name and file then
				xmlFiles[name:lower()] = file
			end
		end
		f:close()
	end
	return xmlFiles
end

local function xmlOf(typeName)
	local key = typeName:lower()
	local hit = xmlCache[key]
	if hit ~= nil then
		return hit or nil
	end
	local file = fileIndex()[key]
	local parsed = false
	if file then
		local f = io.open("data/monster/" .. file, "r")
		if f then
			parsed = M.parseXml(f:read(65536) or "")
			f:close()
		end
	end
	xmlCache[key] = parsed
	return parsed or nil
end

-- ---------------------------------------------------------------- what the engine and the other systems know
local function levelOf(creature)
	if creature.getDisplayLevel then
		local shown = tonumber(call(creature, "getDisplayLevel"))
		if shown and shown > 0 then
			return math.floor(shown)
		end
	end
	local ML = ChaosMonsterLevels
	if ML and ML.estimate then
		local lv = tonumber(try(ML.estimate, creature))
		if lv then
			return math.floor(lv)
		end
	end
	return nil
end

local function roleOf(creature)
	local rift = ChaosRift
	local run = rift and rift.monsterRun and rift.monsterRun[creature:getId()]
	if run and run.bossIds and run.bossIds[creature:getId()] then
		return run.omen and "omen" or "guardian"
	end
	return nil
end

local function towns()
	if M.towns then
		return M.towns
	end
	local list = {}
	for _, t in ipairs(Game.getTowns() or {}) do
		local pos = try(function() return t:getTemplePosition() end)
		if pos and pos.x > 0 then
			list[#list + 1] = {name = t:getName(), x = pos.x, y = pos.y}
		end
	end
	M.towns = list
	return list
end

local function itemInfo(id)
	local it = ItemType(id)
	if not it or it:getId() == 0 then
		return nil
	end
	return it:getName(), it:getClientId()
end

local function conditionBits()
	local bits = {}
	for _, c in ipairs(cfg.conditionImmunities) do
		bits[c[2]] = tonumber(rawget(_G, c[2]))
	end
	return bits
end

-- the armour layer of O462 as this player meets it: the share of a typical hit of the monster's level it removes
local function armourOf(monster, mt, xml)
	local MD = ChaosMonsterDefence
	local class = MD and try(MD.classOf, monster) or "normal"
	local spell, weapon
	local DC = ChaosMonsterDefenceCore
	local mcfg, def = Chaos.monsterDefence, Chaos.defence
	if MD and DC and mcfg and def then
		local level = tonumber(try(MD.levelOf, monster))
		local A, Aw = try(MD.armourOf, monster), try(MD.weaponArmourOf, monster)
		if level and A then
			spell = DC.armourReduction(def, A, DC.hitAtLevel(mcfg, level))
		end
		if level and Aw then
			weapon = DC.weaponShare(def, Aw, DC.weaponHitAtLevel(mcfg, level), DC.weaponShareCap(mcfg, class))
		end
	end
	local armor = xml and xml.armor or tonumber(call(mt, "armor"))
	local defense = xml and xml.defense or tonumber(call(mt, "defense"))
	return M.armourView(armor, defense, class, spell, weapon)
end

local function bestiaryOf(player, name)
	local X = ChaosBestiary
	if not (X and X.cat and X.stateOf) then
		return nil
	end
	local e = try(function() return X.cat().byKey[name:lower()] end)
	if not e then
		return nil
	end
	local st = try(X.stateOf, player)
	local kills = st and st.kills and st.kills[e.key] or 0
	local stage = B and B.stageOf and B.stageOf(kills, e.th) or 0
	return e, {kills = kills, stage = stage, th = e.th, next = B.nextOf(kills, e.th)}, st
end

-- ---------------------------------------------------------------- the answer
local function describe(viewer, creature)
	local t = {isMonster = creature:isMonster() == true}
	local a, b = viewer:getPosition(), creature:getPosition()
	t.hidden = ChaosHuntTeleports ~= nil and ChaosHuntTeleports.isDisplaySpot ~= nil and ChaosHuntTeleports.isDisplaySpot(b) == true
	t.sameFloor = a.z == b.z
	t.dx, t.dy = a.x - b.x, a.y - b.y
	t.visible = viewer:canSeeCreature(creature) == true
	return t
end

function M.read(player, monster)
	local name = typeNameOf(monster)
	local mt = MonsterType(name)
	local xml = xmlOf(name)
	local DS = ChaosDisplayScale
	local f = DS and DS.forPlayer and tonumber(try(DS.forPlayer, player)) or 1
	local function shown(n)
		return (f ~= 1 and DS.scale) and tonumber(try(DS.scale, n, f)) or n
	end
	local tier = ChaosTierOf and ChaosTierOf(monster) or "normal"
	local tdef = ChaosTiers and ChaosTiers[tier]
	local state = ChaosTierState and ChaosTierState[monster:getId()]
	local mods = {}
	for _, key in ipairs(state and state.mods or {}) do
		if ChaosMods and ChaosMods[key] then
			mods[#mods + 1] = {key = key, name = ChaosMods[key].name}
		end
	end
	local class = ChaosMonsterDefence and try(ChaosMonsterDefence.classOf, monster) or "normal"
	local boss = (call(mt, "isBoss") and true) or tier == "boss" or class == "boss"
	local entry, bestiary = bestiaryOf(player, name)
	local stage = bestiary and bestiary.stage or 0
	local hidden = call(mt, "isHealthHidden") == true
	local info = {
		cid = monster:getId(), name = monster:getName(), level = levelOf(monster), tier = tier,
		tierLabel = (tdef and tier ~= "normal" and tier ~= "boss") and tdef.label or nil,
		elite = class == "elite", boss = boss, role = roleOf(monster), summon = monster:getMaster() ~= nil,
		outfit = monster:getOutfit(), mods = M.modRows(mods, cfg), bestiary = bestiary
	}
	local health = M.healthView(monster:getHealth(), monster:getMaxHealth(), hidden)
	if not health.hidden then
		health.cur, health.max = shown(health.cur), shown(health.max)
	end
	info.health = health
	if entry then
		local X = ChaosBestiary
		info.family = {cat = X.catNames and X.catNames[entry.cat] or entry.cat, race = entry.race, diff = entry.diff}
	end
	local bonus, rank
	if bestiary then
		local X = ChaosBestiary
		local s = try(X.stateOf, player)
		local done = s and s.completed and s.completed[name:lower()]
		bonus = done and done.exp or nil
		local r = try(X.rankOf, player)
		rank = r and r.exp or nil
	end
	local rate = tonumber(try(function() return Game.getExperienceStage(player:getLevel()) end)) or 1
	info.exp = M.expView(call(mt, "experience"), tdef and tdef.xp or 1, rate, bonus, rank)
	local MD = ChaosMonsterDefence
	info.resist = M.resistRows(MD and function(ctype) return try(MD.effectiveResist, monster, ctype, 0) end or
		function(ctype) return tonumber((call(mt, "getElementList") or {})[ctype]) end,
		call(mt, "combatImmunities"), call(mt, "conditionImmunities"), conditionBits(), cfg)
	info.armour = armourOf(monster, mt, xml)
	local dmg = tdef and tdef.damage or 1
	info.attacks = M.attackRows(xml, call(mt, "getAttackList"), dmg, cfg, f)
	info.abilities = M.abilityRows(xml or {}, cfg)
	info.speed = {base = tonumber(call(monster, "getBaseSpeed")), now = tonumber(call(monster, "getSpeed"))}
	info.loot = M.lootView(call(mt, "getLoot") or {}, itemInfo, stage, tier ~= "normal" and tier or nil, cfg)
	local list = ChaosLoot and ChaosLoot.uniqueList and try(ChaosLoot.uniqueList) or {}
	info.uniques = M.uniqueRows(list, name:lower(), stage, cfg, function(id)
		local it = ItemType(id)
		return it and it:getClientId() or id
	end)
	info.areas = entry and M.areaRows(entry.areas, towns(), stage, cfg) or {}
	return M.build(info, cfg)
end

local function inspect(player, data)
	local pid = player:getId()
	budget[pid] = budget[pid] or {}
	if not M.allow(budget[pid], nowMs(), cfg) then
		return deny(player, "rate")
	end
	local cid = M.cleanCid(data.cid)
	if not cid then
		return deny(player, "bad")
	end
	local creature = Creature(cid)
	local ok, code = M.allowed(creature and describe(player, creature) or nil, cfg)
	if not ok then
		return deny(player, code)
	end
	local result = try(M.read, player, Monster(cid))
	if not result then
		return deny(player, "notfound")
	end
	send(player, {action = "result", data = result})
end

local ext = CreatureEvent("ChaosMonsterInspectExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg or type(msg.data) ~= "table" then
		return
	end
	if msg.action == "inspect" then
		inspect(player, msg.data)
	end
end
ext:type("extendedopcode")
ext:register()

local login = CreatureEvent("ChaosMonsterInspectLogin")
function login.onLogin(player)
	player:registerEvent("ChaosMonsterInspectExtended")
	player:registerEvent("ChaosMonsterInspectLogout")
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosMonsterInspectLogout")
function logout.onLogout(player)
	budget[player:getId()] = nil
	return true
end
logout:type("logout")
logout:register()

return M
