-- Item finder: "where does this drop" (client game_itemfinder, extended opcode ChaosOpcodes.itemFinder = 155).
--
-- At startup one index is built in memory from the real data (itemfinder_core.lua, itemfinder_sources.lua):
--   monsters    MonsterType:getLoot() of every monster of the bestiary (or monsters.xml), chance x the loot rate, with
--               the bestiary's level and spawn places and the hunting-area level band of the map markers
--   Chaos loot  currency, gems, uniques (loot_config.lua, chaos_gems_config.lua, ChaosLoot.uniqueList)
--   recipes     the base crafting tables (global Crafting), salvage, gem combining, faction recipes, sigils, omen keys
--   NPC shops   the NPCs of the map's spawn file: data/npc/<name>.xml (shop_buyable / shop_sellable) and their scripts
--   store       shop_config.lua; the Gambler (gamble_config.lua); the professions and the Material Broker
--   rewards     daily reward, login streak, bounty, rifts, tower, world bosses, invasions, arena, battleground, guild
--               boss, the Descent, the raid, dungeons, treasure goblins, achievements (hidden ones never), factions,
--               the Ascended Omens
-- Names (items, monsters, NPCs, towns) are read from the engine and the installed files: the renamed ones.
-- Nothing is stored per player; no storages, no tables.
--
-- Protocol (JSON {action, data}; answers through Chaos.sendChunked, joined by the client's
-- ProtocolGame.registerExtendedJSONOpcode):
--   client -> server  search {q, p} | item {id} | item {cid} | page {id, k, p}
--   server -> client  results {q, p, pages, total, rows = [{id, cid, name, n, kinds}]}
--                     item {id, cid, name, total, secs = [{k, p, pages, total, rows}]} | item {.., none = true}
--                     page {id, k, p, pages, total, rows} | busy {}
--   row = {n, d, v, c, i, l, b, m = [{i, l, n, c}]} (itemfinder_core.lua)
-- One request per player per cfg.requestMs (Chaos.limited); a dropped request is not answered (the window asks again).
-- Staff: /itemfinder (index size, build time and memory), /itemfinder rebuild, /itemfinder <text> (search in the console).
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
dofile("data/scripts/chaos/itemfinder_core.lua")
dofile("data/scripts/chaos/itemfinder_sources.lua")

ChaosItemFinder = ChaosItemFinder or {}
local F = ChaosItemFinder
local cfg = dofile("data/scripts/chaos/itemfinder_config.lua")
F.cfg = cfg
local K, S = ChaosItemFinderCore, ChaosItemFinderSources
local OPCODE = ChaosOpcodes.itemFinder or cfg.opcode

local function nowMs()
	return os.mtime and os.mtime() or math.floor(os.clock() * 1000)
end

local function readFile(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local text = f:read("*a")
	f:close()
	return text
end

-- a config table: the live global when the system keeps one, else its file
local function loadTable(live, path)
	if type(live) == "table" then
		return live
	end
	local ok, t = pcall(dofile, path)
	return ok and type(t) == "table" and t or nil
end

local function call(obj, method)
	local ok, v = pcall(function() return obj[method](obj) end)
	if ok then
		return v
	end
	return nil
end

local function itemInfo(id)
	local it = ItemType(id)
	if not it or it:getId() == 0 then
		return nil
	end
	return it:getName(), it:getClientId()
end

local function towns()
	local list = {}
	for _, t in ipairs(Game.getTowns and Game.getTowns() or {}) do
		local pos = call(t, "getTemplePosition")
		if pos and pos.x > 0 then
			list[#list + 1] = {name = t:getName(), x = pos.x, y = pos.y, z = pos.z}
		end
	end
	return list
end

local function poiMarks()
	if ChaosPoi and type(ChaosPoi.all) == "table" then
		return ChaosPoi.all
	end
	local t = loadTable(nil, "data/chaos_poi.lua")
	return t and t.marks or {}
end

local function lootRate()
	if not cfg.lootRate or not configManager or not configKeys or not configKeys.RATE_LOOT then
		return 1
	end
	local ok, v = pcall(configManager.getNumber, configKeys.RATE_LOOT)
	return ok and tonumber(v) and v > 0 and v or 1
end

local function lowerSet(list)
	local s = {}
	for _, v in ipairs(list or {}) do
		s[tostring(v):lower()] = true
	end
	return s
end

local function monsterHidden(name, hidden)
	local lower = tostring(name):lower()
	if hidden[lower] then
		return true
	end
	for _, p in ipairs(cfg.hiddenMonsterPatterns or {}) do
		if lower:find(p) then
			return true
		end
	end
	return false
end

-- {{name, boss, level, band, places, loot}}: the bestiary's entries (its exclusions, levels and spawn places) or, without
-- the bestiary, every monster of monsters.xml and of Game.getMonsterTypes()
local function monsterList(townList)
	local hidden = lowerSet(cfg.hidden.monsters)
	local bands = K.huntBands(poiMarks())
	local out = {}
	local B, BC = ChaosBestiary, ChaosBestiaryCore
	local ok, cat = false, nil
	if B and B.cat then
		ok, cat = pcall(B.cat)
	end
	if ok and type(cat) == "table" and type(cat.list) == "table" then
		for _, e in ipairs(cat.list) do
			if not monsterHidden(e.name, hidden) then
				local mt = MonsterType(e.name)
				local places = {}
				if BC and BC.areaTexts and e.areas then
					for _, a in ipairs(BC.areaTexts(e.areas, townList, cfg.areasShown)) do
						places[#places + 1] = a.text
					end
				end
				-- the bestiary caps its estimate (bestiary_config.lua maxLevel): a capped level says nothing
				local level = e.level
				if Chaos.bestiaryConfig and level and level >= (Chaos.bestiaryConfig.maxLevel or math.huge) then
					level = nil
				end
				out[#out + 1] = {name = e.name, boss = e.boss, level = level, band = bands[e.key], places = places,
					loot = mt and call(mt, "getLoot") or {}}
			end
		end
		return out
	end
	local names, seen = {}, {}
	local text = readFile(cfg.monstersXml) or ""
	for name in text:gmatch('<monster[^>]-name%s*=%s*"([^"]+)"') do
		names[#names + 1] = name
	end
	for key in pairs(Game.getMonsterTypes and Game.getMonsterTypes() or {}) do
		names[#names + 1] = key
	end
	for _, raw in ipairs(names) do
		local mt = MonsterType(raw)
		local name = mt and call(mt, "name")
		if name and not seen[name:lower()] and not monsterHidden(name, hidden) and (tonumber(call(mt, "experience")) or 0) > 0 then
			seen[name:lower()] = true
			out[#out + 1] = {name = name, boss = call(mt, "isBoss") and true or false, band = bands[name:lower()],
				loot = call(mt, "getLoot") or {}}
		end
	end
	return out
end

local function monsterName(key)
	local mt = MonsterType(key)
	local name = mt and call(mt, "name")
	return name or (tostring(key):gsub("^%l", string.upper))
end

-- the NPCs of the map's spawn file with a shop: {{name, places, buy, sell}}
local function npcList(townList)
	local file = cfg.spawnFile
	if not file then
		local ok, map = pcall(function() return configManager.getString(configKeys.MAP_NAME) end)
		file = "data/world/" .. ((ok and map) or "map") .. "-spawn.xml"
	end
	local text = readFile(file)
	if not text then
		print("[Chaos itemfinder] no spawn file " .. file .. ": NPC shops are not listed")
		return {}
	end
	local spawns = K.parseSpawnNpcs(text)
	text = nil
	local byFile, order = {}, {}
	for _, s in ipairs(spawns) do
		if not byFile[s.name] then
			byFile[s.name] = {}
			order[#order + 1] = s.name
		end
		table.insert(byFile[s.name], s)
	end
	local hidden = lowerSet(cfg.hidden.npcs)
	local scripts, out = {}, {}
	for _, fileName in ipairs(order) do
		local xml = readFile(cfg.npcDir .. fileName .. ".xml")
		if xml then
			local npc = K.parseNpcXml(xml)
			if npc.script then
				local sc = scripts[npc.script]
				if sc == nil then
					local body = readFile(cfg.npcDir .. "scripts/" .. npc.script)
					if body then
						local b, s = K.parseNpcScript(body)
						sc = {buy = b, sell = s}
					else
						sc = false
					end
					scripts[npc.script] = sc
				end
				if sc then
					for _, e in ipairs(sc.buy) do
						npc.buy[#npc.buy + 1] = e
					end
					for _, e in ipairs(sc.sell) do
						npc.sell[#npc.sell + 1] = e
					end
				end
			end
			local name = npc.name or fileName
			if (#npc.buy > 0 or #npc.sell > 0) and not hidden[name:lower()] then
				out[#out + 1] = {name = name, places = K.placesText(byFile[fileName], townList, cfg.townNear, cfg.townsShown),
					buy = npc.buy, sell = npc.sell}
			end
		end
	end
	return out
end

-- every other system's tables (the live ones when loaded)
local function rewardTables()
	local base = "data/scripts/chaos/"
	return {
		daily = Chaos.daily,
		dailyStreak = loadTable(Chaos.dailyStreak, base .. "daily_config.lua"),
		bounty = loadTable(Chaos.bountyConfig, base .. "bounty_config.lua"),
		rift = loadTable(ChaosRiftConfig, base .. "rift_config.lua"),
		tower = Chaos.tower,
		worldBoss = Chaos.worldBoss,
		pocketBoss = loadTable(Chaos.pocketBossConfig, base .. "pocketboss_config.lua"),
		invasion = loadTable(nil, base .. "invasion_config.lua"),
		arena = loadTable(nil, base .. "arena_config.lua"),
		battleground = loadTable(nil, base .. "battleground_config.lua"),
		guildboss = loadTable(nil, base .. "guildboss_config.lua"),
		descent = loadTable(nil, base .. "descent_config.lua"),
		raid = loadTable(nil, base .. "raid_config.lua"),
		dungeons = Chaos.dungeons,
		goblin = loadTable(nil, base .. "treasure_goblin_config.lua"),
		achievements = loadTable(nil, base .. "achievements_data.lua"),
		factions = loadTable(nil, base .. "factions_config.lua"),
		uber = loadTable(ChaosUberConfig, base .. "uber_config.lua"),
		conquest = ChaosConquest and ChaosConquest.catalog and {cfg = ChaosConquest.cfg, offers = ChaosConquest.catalog()} or nil
	}
end

local function orbId(key)
	for _, orb in ipairs(ChaosCrafting and ChaosCrafting.config and ChaosCrafting.config.orbs or {}) do
		if orb.key == key then
			return orb.id
		end
	end
	return nil
end

function F.build()
	collectgarbage("collect")
	local mem0 = collectgarbage("count")
	local t0 = nowMs()
	local idx = K.new(cfg, itemInfo)
	local function emit(kind, id, row)
		K.add(idx, id, kind, row)
	end
	local errors = {}
	local timings = {}
	local function step(name, fn)
		local t = nowMs()
		local ok, err = pcall(fn)
		if not ok then
			errors[#errors + 1] = name .. ": " .. tostring(err)
		end
		timings[#timings + 1] = name .. " " .. (nowMs() - t)
	end
	local townList = towns()
	local base = "data/scripts/chaos/"
	step("monsters", function() S.monsters(monsterList(townList), emit, {rate = lootRate()}) end)
	step("lootlayer", function()
		local uniques = ChaosLoot and ChaosLoot.uniqueList and ChaosLoot.uniqueList() or {}
		S.lootLayer(loadTable(ChaosLootConfig, base .. "loot_config.lua"), loadTable(ChaosGemsConfig, "data/lib/chaos_gems_config.lua"),
			uniques, emit, monsterName)
	end)
	step("crafting", function() S.crafting(Crafting, cfg, emit) end)
	step("npcs", function() S.npcs(npcList(townList), emit) end)
	step("store", function() S.store(loadTable(ChaosShopConfig, base .. "shop_config.lua"), emit) end)
	step("gamble", function() S.gamble(loadTable(nil, base .. "gamble_config.lua"), emit) end)
	step("professions", function() S.professions(loadTable(nil, base .. "professions_config.lua"), emit) end)
	step("salvage", function() S.salvage(loadTable(nil, base .. "salvage_config.lua"), orbId, emit) end)
	step("gems", function() S.gemCombining(loadTable(ChaosGemsConfig, "data/lib/chaos_gems_config.lua"), emit) end)
	step("rewards", function()
		for _, e in ipairs(S.rewards(rewardTables(), emit)) do
			errors[#errors + 1] = "rewards " .. e.key .. ": " .. e.message
		end
	end)
	local stats = K.finish(idx)
	stats.ms = nowMs() - t0
	collectgarbage("collect")
	stats.kb = math.floor(collectgarbage("count") - mem0 + 0.5)
	stats.errors = errors
	stats.timings = table.concat(timings, ", ")
	F.index = idx
	F.briefs = {}
	print(string.format("[Chaos itemfinder] %d items, %d rows in %d ms (%s), about %.1f MB of Lua memory",
		stats.items, stats.rows, stats.ms, stats.timings, stats.kb / 1024))
	for _, e in ipairs(errors) do
		print("[Chaos itemfinder] " .. e)
	end
	return stats
end

-- the short sources of an item tooltip (item_tooltip.lua): K.brief and, when the Conquest vendor sells the item, its
-- token price (conquest.lua, guarded). Cached per server id until the index is rebuilt.
F.briefs = F.briefs or {}
function F.brief(id)
	id = tonumber(id)
	if not cfg.enabled or not id or not F.index or not F.index.ready then
		return nil
	end
	local cached = F.briefs[id]
	if cached == nil then
		cached = K.brief(F.index, id) or false
		if ChaosConquest and ChaosConquest.offerOf then
			local ok, o = pcall(ChaosConquest.offerOf, id)
			if ok and type(o) == "table" and tonumber(o.price) then
				cached = cached or {s = {}}
				cached.t = tonumber(o.price)
			end
		end
		F.briefs[id] = cached
	end
	return cached or nil
end

function F.send(player, action, data)
	local ok, payload = pcall(json.encode, {action = action, data = data})
	if ok then
		Chaos.sendChunked(player, OPCODE, payload)
	end
end

-- the answer to one client message (nil when nothing is sent)
function F.handle(player, buffer)
	if not cfg.enabled then
		return nil
	end
	local m = Chaos.decode(buffer)
	if not m or type(m.action) ~= "string" then
		return nil
	end
	if Chaos.limited(player, "itemfinder", cfg.requestMs) then
		return nil
	end
	if not F.index then
		local ok, err = pcall(F.build)
		if not ok then
			print("[Chaos itemfinder] build failed: " .. tostring(err))
		end
	end
	local action, data = K.request(F.index, m.action, m.data)
	if action then
		F.send(player, action, data)
	end
	return action
end

-- ---------------------------------------------------------------- events
if GlobalEvent then
	local startup = GlobalEvent("ChaosItemFinderStartup")
	function startup.onStartup()
		local ok, err = pcall(F.build)
		if not ok then
			print("[Chaos itemfinder] build failed: " .. tostring(err))
		end
		return true
	end
	startup:register()
end

if CreatureEvent then
	local login = CreatureEvent("ChaosItemFinderLogin")
	function login.onLogin(player)
		player:registerEvent("ChaosItemFinderExtended")
		return true
	end
	login:type("login")
	login:register()

	local ext = CreatureEvent("ChaosItemFinderExtended")
	function ext.onExtendedOpcode(player, opcode, buffer)
		if opcode ~= OPCODE then
			return
		end
		local ok, err = pcall(F.handle, player, buffer)
		if not ok then
			print("[Chaos itemfinder] request failed: " .. tostring(err))
		end
	end
	ext:type("extendedopcode")
	ext:register()
end

if TalkAction then
	local talk = TalkAction("/itemfinder")
	function talk.onSay(player, words, param)
		if player:getGroup():getId() < cfg.staffGroup then
			return true
		end
		param = tostring(param or ""):gsub("^%s+", ""):gsub("%s+$", "")
		if param == "rebuild" or not F.index then
			F.build()
		end
		local st = F.index and F.index.stats or {}
		if param == "" or param == "rebuild" then
			player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("Item finder: %d items, %d rows, built in %d ms, %d KB.",
				st.items or 0, st.rows or 0, st.ms or 0, st.kb or 0))
			return false
		end
		local r = K.search(F.index, param, 1)
		local parts = {}
		for _, row in ipairs(r.rows) do
			parts[#parts + 1] = string.format("%s (%d)", row.name, row.n)
		end
		player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("%d found: %s", r.total, table.concat(parts, ", ")))
		return false
	end
	talk:separator(" ")
	talk:register()
end
