-- Run from the server/ folder: luajit tests/npc_review_test.lua (and lua5.3; CI runs both)
-- NPC review (O415, server/README.md "NPC review (O415)"). Static: nothing here runs on a live server. For every
-- data/npc/*.xml the repository adds:
--   * the XML names a script that exists in data/npc/scripts and parses; the name matches the file name; the greeting,
--     farewell and walk away lines are there; every {keyword} the greeting offers is answered by the script run on a
--     mocked NPC library (a callback answer, an opened window, a keyword node or the shop module's trade words);
--   * the script loads the focus module (so "hi" and "bye" work) and reads the XML parameters;
--   * every shop item id is a base item the survey knows (data/items/base_item_values.csv) or one of ours;
--   * every Chaos.storage.X / ChaosOpcodes.X the script names is in chaos_constants.lua, and an opcode written as a
--     fallback number (`cfg.opcode or 167`) is the module's real opcode;
--   * the NPC is placed: a stall (npc_booths_config.lua), a startup placement (the system's config), the service NPC
--     list or the world event that creates it.
-- Plus the quest NPCs: every step a tale needs can be reached in dialogue (the NPC of a talk step is a faction NPC
-- whose script runs the tales' talk step; the Archivist takes every deliver and report step).
local checks, failures = 0, 0
local function check(cond, label)
	checks = checks + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, label .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end

loadstring = loadstring or load
local unpack = table.unpack or unpack

-- uppercase globals the engine defines (CALLBACK_*, MESSAGE_*, CONST_*) read as unique numbers
local constants, nextConstant = {}, 1000
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then
		nextConstant = nextConstant + 1
		rawset(t, k, nextConstant)
		return nextConstant
	end
end})

dofile("data/scripts/chaos/chaos_constants.lua")
local function readFile(path)
	local fh = io.open(path, "rb")
	if not fh then
		return nil
	end
	local text = fh:read("*a")
	fh:close()
	return text
end

-- ---------------------------------------------------------------- what is in the repository
local function listXml()
	local out = {}
	local p = io.popen('ls data/npc')
	for line in p:lines() do
		if line:match("%.xml$") then
			out[#out + 1] = line
		end
	end
	p:close()
	table.sort(out)
	return out
end

local files = listXml()
check(#files >= 22, "the NPC folder lists its XML files (" .. #files .. ")")

local baseIds = {}
do
	local text = readFile("data/items/base_item_values.csv") or ""
	for id in text:gmatch("\n(%d+),") do
		baseIds[tonumber(id)] = true
	end
	text = readFile("data/items/base_item_names.csv") or ""
	for id in text:gmatch("\n(%d+),") do
		baseIds[tonumber(id)] = true
	end
end
local BASE_MAX_ITEM = 29926
local ours = {}
do
	local text = readFile("data/items/chaos_items.xml") or ""
	for id in text:gmatch('<item%s[^>]-%f[%w]id="(%d+)"') do
		ours[tonumber(id)] = true
	end
	for _, name in ipairs({"art_items", "pack30_items", "harvest_items", "donor_items", "fist_items", "decor48_items",
			"decor49_items", "owner_decor"}) do
		local csv = readFile("data/items/" .. name .. ".csv") or ""
		local header = csv:match("^[^\n]*") or ""
		local col, i = nil, 0
		for h in header:gmatch("[^,]+") do
			i = i + 1
			if h == "server_id" or h == "id" then
				col = col or i
			end
		end
		if col then
			for line in csv:gmatch("\n([^\n]+)") do
				local j = 0
				for v in (line .. ","):gmatch("([^,]*),") do
					j = j + 1
					if j == col and tonumber(v) then
						ours[tonumber(v)] = true
					end
				end
			end
		end
	end
end
-- ids above the base items come from the item installers (install_orbs.py, install_omens.py, ...); the ranges they
-- document: gems 32001-32035, salvage 32051, omens 32071-32072, pouches 32081-32083, supports 32101-32200, orbs
-- 32251-32260
local function installerId(id)
	return (id >= 32001 and id <= 32035) or id == 32051 or (id >= 32071 and id <= 32072) or (id >= 32081 and id <= 32083)
		or (id >= 32101 and id <= 32200) or (id >= 32251 and id <= 32260)
end
-- stock ids the survey of the base has no row for (nothing in the base buys or drops them); they cannot be checked
-- here: `python3 tools/ci/check_content.py --base DATA_DIR` reads the real items.xml
local STOCK_UNSURVEYED = {[2096] = "pumpkinhead", [5908] = "obsidian knife"}
local function itemKnown(id)
	return baseIds[id] or ours[id] or installerId(id) or STOCK_UNSURVEYED[id] ~= nil
end

-- ---------------------------------------------------------------- the mocked engine
local said, sent, callbacks, nodes, modules, parsed

local function reset()
	said, sent, callbacks, nodes, modules, parsed = {}, {}, {}, {}, {}, 0
end
reset()

local params -- the XML parameters of the NPC under test
local playerLevel = 1000

KeywordHandler = {new = function()
	local kh = {}
	function kh:addKeyword(keys, fn)
		nodes[#nodes + 1] = {keys = keys, fn = fn}
	end
	return kh
end}
FocusModule = {new = function() return {name = "focus"} end}
local function newShop()
	local m = {name = "shop"}
	function m:addBuyableItem() end
	function m:addSellableItem() end
	return m
end
ShopModule = {new = newShop}
NpcSystem = {parseParameters = function(handler)
	parsed = parsed + 1
	if tonumber(params.module_shop) and tonumber(params.module_shop) ~= 0 then
		handler:addModule(newShop())
	end
end}
NpcHandler = {new = function()
	local h = {messages = {}, talkStart = {}}
	function h:setCallback(kind, fn) callbacks[kind] = fn end
	function h:getCallback(kind) return callbacks[kind] end
	function h:say(text) said[#said + 1] = type(text) == "table" and table.concat(text, " ") or text end
	function h:isFocused() return true end
	function h:addModule(m) modules[#modules + 1] = m end
	function h:getMessage(t) return self.messages[t] end
	function h:setMessage(t, m) self.messages[t] = m end
	return h
end}
ChaosNpcFocus = {hears = function() return true end}

-- one generic player: a method not listed answers nil (no item, no town, no house)
local storage = {}
local playerMethods = {}
local player = setmetatable({}, {__index = function(_, name)
	return playerMethods[name] or function() end
end})
function playerMethods.getLevel() return playerLevel end
function playerMethods.getId() return 77 end
function playerMethods.getGuid() return 7700 end
function playerMethods.getName() return "Tester" end
function playerMethods.isPremium() return true end
function playerMethods.getStorageValue(_, k) return storage[k] or -1 end
function playerMethods.setStorageValue(_, k, v) storage[k] = v end
function playerMethods.sendExtendedOpcode(_, op, json) sent[#sent + 1] = {op = op, json = json} end
function playerMethods.sendTextMessage(_, _, text) said[#said + 1] = text end
function playerMethods.sendCancelMessage(_, text) said[#said + 1] = text end
function playerMethods.getVocation() return {getId = function() return 1 end, getName = function() return "Knight" end} end
function playerMethods.getBankBalance() return 5000 end
function playerMethods.removeItem() return false end
function playerMethods.getPosition() return {x = 31672, y = 32236, z = 7} end
function playerMethods.getTown() return {getId = function() return 2 end, getName = function() return "Cinderhold" end} end
function playerMethods.getGroup() return {getId = function() return 1 end, getAccess = function() return false end} end
function playerMethods.getInbox() return nil end
function playerMethods.getItems() return {} end
function playerMethods.getItemCount() return 0 end
function playerMethods.hasLearnedSpell() return false end

Player = function() return player end
Creature = Player
Vocation = function() return {getId = function() return 1 end, getName = function() return "Knight" end} end
ItemType = function(id) return {getId = function() return id end, getName = function() return "item " .. tostring(id) end, isDoor = function() return false end} end
ModalWindow = function()
	local w = {}
	return setmetatable(w, {__index = function() return function() return w end end})
end
Game = {getStorageValue = function() return -1 end, getSpectators = function() return {} end, getTowns = function() return {} end,
	getPlayers = function() return {} end}
Town = function() return nil end
Position = function(x, y, z) return {x = x, y = y, z = z} end
db = {storeQuery = function() return false end, query = function() return true end, asyncQuery = function() end,
	escapeString = function(s) return "'" .. tostring(s) .. "'" end}
result = {getString = function() return "" end, getNumber = function() return 0 end, free = function() end}
addEvent = function() end
json = json or {encode = function() return "{}" end, decode = function() return {} end}
ChaosRateLimit = nil

-- the order of the keyword tests: an NPC says something, opens a window or a node answers
local function answered(kw, hasShop)
	said, sent = {}, {}
	local cb = callbacks[CALLBACK_MESSAGE_DEFAULT]
	local lower = kw:lower()
	if cb then
		local ok, handled = pcall(cb, 77, 1, kw)
		if not ok then
			return false, "error: " .. tostring(handled)
		end
		if handled == true or #said > 0 or #sent > 0 then
			return true
		end
	end
	for _, n in ipairs(nodes) do
		for _, key in ipairs(n.keys) do
			if tostring(key):lower() == lower then
				return true
			end
		end
	end
	-- the shop module (base library) answers these on its own
	if hasShop and (lower == "trade" or lower == "offer" or lower == "buy" or lower == "sell" or lower == "wares") then
		return true
	end
	return false, "no answer"
end

-- ---------------------------------------------------------------- the XML files
local npcs = {} -- name -> record
for _, f in ipairs(files) do
	local path = "data/npc/" .. f
	local xml = readFile(path)
	check(xml ~= nil, f .. " is readable")
	local name, script = xml:match('<npc%s[^>]*name="([^"]+)"[^>]*script="([^"]+)"')
	check(name ~= nil and script ~= nil, f .. ": <npc name= script=>")
	if name and script then
		eq(f, name .. ".xml", f .. ": the file is named after the NPC")
		local rec = {name = name, script = script, xml = xml, file = f, params = {}}
		npcs[name] = rec
		for key, value in xml:gmatch('<parameter%s+key="([%w_]+)"%s+value="([^"]*)"') do
			rec.params[key] = value:gsub("[\t\r\n]", " ")
		end
		check(xml:find("<health ", 1, true) and xml:find("<look ", 1, true), f .. ": health and look")
		check(rec.params.message_greet, f .. ": a greeting")
		check(rec.params.message_farewell, f .. ": a farewell")
		check(rec.params.message_walkaway, f .. ": a walk away line")
		check(rec.params.message_greet and rec.params.message_greet:find("|PLAYERNAME|", 1, true), f .. ": the greeting names the player")
		-- a well formed file: every tag closes (a quick check; the server's pugixml is stricter on attributes only)
		check(xml:find("</npc>", 1, true) and xml:find("</parameters>", 1, true), f .. ": closing tags")
		local scriptPath = "data/npc/scripts/" .. script
		local text = readFile(scriptPath)
		check(text ~= nil, f .. ": script " .. script .. " exists")
		if text then
			rec.text = text
			check(loadstring(text, "@" .. scriptPath) ~= nil, scriptPath .. " parses")
		end
	end
end

-- ---------------------------------------------------------------- the dialogue
-- words each NPC's shop module answers by itself (the base library: "trade", "buy <name>", "sell <name>")
local function hasShop(rec)
	if rec.params.module_shop and rec.params.module_shop ~= "0" then
		return true
	end
	return rec.text and (rec.text:find("ShopModule:new()", 1, true) ~= nil) or false
end

local names = {}
for name in pairs(npcs) do
	names[#names + 1] = name
end
table.sort(names)

local TALES = nil
for _, name in ipairs(names) do
	local rec = npcs[name]
	if rec.text then
		reset()
		params = rec.params
		storage = {}
		callbacks.script = nil
		SERVICE_KEY, FACTION_KEY = nil, nil
		local chunk = loadstring(rec.text, "@data/npc/scripts/" .. rec.script)
		local ok, err = pcall(function()
			local run, e = loadfile("data/npc/scripts/" .. rec.script)
			if not run then
				error(e)
			end
			run()
		end)
		check(ok, name .. ": the script runs on the mocked library: " .. tostring(err))
		if ok then
			local focus = false
			for _, m in ipairs(modules) do
				if m.name == "focus" then
					focus = true
				end
			end
			check(focus, name .. ": adds the focus module (hi, bye)")
			check(parsed >= 1, name .. ": reads its XML parameters (NpcSystem.parseParameters)")
			check(callbacks[CALLBACK_MESSAGE_DEFAULT] ~= nil or #nodes > 0 or hasShop(rec),
				name .. ": answers something")
			local shop = hasShop(rec)
			-- every {keyword} of the greeting
			local seen = {}
			for kw in rec.params.message_greet:gmatch("{([^}]+)}") do
				if not seen[kw] then
					seen[kw] = true
					local okA, why = answered(kw, shop)
					if os.getenv("NPC_REVIEW_VERBOSE") then
						print(string.format("%-22s {%s} -> %s %s", name, kw, tostring(okA), (said[1] or (sent[1] and ("opcode " .. sent[1].op)) or ""):sub(1, 110)))
					end
					check(okA, name .. ": the greeting offers {" .. kw .. "} and the script does not answer it (" .. tostring(why) .. ")")
				end
			end
			rec.keywords = seen
		end
	end
end

-- ---------------------------------------------------------------- the keywords the NPC's own lines promise
-- "Ask for a {trade}": every {word} in a line a script says is a keyword the player will type; it must be answered too
-- (O415: Archivist Maelis offered {chronicle} and the callback crashed on it: its `type` parameter hid the function)
local CONTEXT = {yes = true, health = true, mana = true, english = true, ["portugues"] = true}
for _, name in ipairs(names) do
	local rec = npcs[name]
	if rec.text then
		local text = rec.text
		for common in rec.text:gmatch('dofile%("data/npc/scripts/(chaos_[%w_]+%.lua)"%)') do
			local shared = readFile("data/npc/scripts/" .. common) or ""
			local key = rec.text:match('SERVICE_KEY = "(%w+)"')
			if key then
				-- the service NPCs share one file: only this NPC's block of answers
				local from = shared:find("ANSWERS." .. key .. " = {", 1, true)
				local to = from and (shared:find("\n%-%- %-%-%-%-%-%-", from + 1) or #shared)
				shared = from and shared:sub(from, to) or ""
			end
			text = text .. shared
		end
		-- only inside string literals ({name} in `addBuyableItem({name}, ...)` is a table)
		local literals = {}
		for lit in text:gmatch('"([^"\n]*)"') do
			literals[#literals + 1] = lit
		end
		text = table.concat(literals, "\n")
		reset()
		params = rec.params
		storage = {}
		SERVICE_KEY, FACTION_KEY = nil, nil
		local run = loadfile("data/npc/scripts/" .. rec.script)
		if run and pcall(run) then
			local shop = hasShop(rec)
			local promised, list = {}, {}
			for kw in text:gmatch("{([%a][%w ]*)}") do
				if not promised[kw] then
					promised[kw] = true
					list[#list + 1] = kw
				end
			end
			table.sort(list)
			for _, kw in ipairs(list) do
				if not CONTEXT[kw:lower()] then
					local okA, why = answered(kw, shop)
					check(okA, name .. ": a line promises {" .. kw .. "} and the script does not answer it (" .. tostring(why) .. ")")
				end
			end
		end
	end
end

-- ---------------------------------------------------------------- shop items exist
for _, name in ipairs(names) do
	local rec = npcs[name]
	for _, key in ipairs({"shop_buyable", "shop_sellable"}) do
		local list = rec.params[key]
		if list then
			for entry in list:gmatch("[^;]+") do
				local label, id, price = entry:match("^%s*([^,]+),%s*(%d+),%s*(%d+)%s*$")
				check(label ~= nil, name .. ": " .. key .. " entry [" .. entry .. "] is name,id,price")
				if label then
					id = tonumber(id)
					check(itemKnown(id), name .. ": " .. key .. " " .. label .. " (" .. id .. ") is a base item of the survey or ours")
					check(tonumber(price) >= 0, name .. ": " .. key .. " " .. label .. " has a price")
				end
			end
		end
	end
end

-- the shops our scripts build from config lists: the Material Broker's tools, the Wandering Merchant's wares
do
	local prof = dofile("data/scripts/chaos/professions_config.lua")
	for _, t in ipairs(prof.broker.tools or {}) do
		check(itemKnown(t.id), "Material Broker: tool " .. tostring(t.id) .. " exists")
		check(t.price and t.price > 0, "Material Broker: tool " .. tostring(t.id) .. " has a price")
	end
	local inv = dofile("data/scripts/chaos/invasion_config.lua")
	local merchant = inv.worldEvents and inv.worldEvents.merchant or {}
	check(#(merchant.items or {}) > 0, "Wandering Merchant: a ware list")
	for _, it in ipairs(merchant.items or {}) do
		check(itemKnown(it.id), "Wandering Merchant: " .. tostring(it.name) .. " (" .. tostring(it.id) .. ") exists")
		check(it.price and it.price > 0, "Wandering Merchant: " .. tostring(it.name) .. " has a price")
	end
	local harvest = dofile("data/scripts/chaos/harvest_event_config.lua")
	for _, o in ipairs(harvest.shop or {}) do
		for _, it in ipairs(o.items or {}) do
			check(itemKnown(it[1]), "Widow Hessa: " .. tostring(o.name) .. " item " .. tostring(it[1]) .. " exists")
		end
	end
	check(itemKnown(harvest.items.candy), "Widow Hessa: the hollow candy exists")
end

-- ---------------------------------------------------------------- storage keys and opcodes
local opcodeOf = {
	["conquest_config.lua"] = "conquest", ["gamble_config.lua"] = "gamble", ["candlemarks_config.lua"] = "candlemarks",
	["professions_config.lua"] = "professions"
}
for _, name in ipairs(names) do
	local rec = npcs[name]
	if rec.text then
		for key in rec.text:gmatch("Chaos%.storage%.([%w_]+)") do
			check(Chaos.storage[key] ~= nil, name .. ": Chaos.storage." .. key .. " exists")
		end
		for key in rec.text:gmatch("ChaosOpcodes%.([%w_]+)") do
			check(ChaosOpcodes[key] ~= nil, name .. ": ChaosOpcodes." .. key .. " exists")
		end
		-- `cfg.opcode or 167`: the fallback is the module's real opcode
		local cfgFile = rec.text:match('dofile%("data/scripts/chaos/([%w_]+_config%.lua)"%)')
		local fallback = rec.text:match("cfg%.opcode or (%d+)")
		if cfgFile and fallback then
			local cfg = dofile("data/scripts/chaos/" .. cfgFile)
			check(type(cfg) == "table" and cfg.opcode ~= nil, name .. ": " .. cfgFile .. " has an opcode")
			eq(tonumber(fallback), cfg and cfg.opcode, name .. ": the fallback opcode is " .. cfgFile .. " opcode")
		end
	end
end

-- ---------------------------------------------------------------- every NPC is placed
local booths = dofile("data/scripts/chaos/npc_booths_config.lua").booths
local inBooth = {}
for _, b in ipairs(booths) do
	inBooth[b.npc] = true
end
local service = dofile("data/scripts/chaos/service_npcs_config.lua")
local serviceName = {}
for _, n in pairs(service.npcs) do
	serviceName[n.name] = n
end
local function sourceMentions(name, ...)
	for _, f in ipairs({...}) do
		local text = readFile("data/scripts/chaos/" .. f) or ""
		if text:find(name, 1, true) then
			return f
		end
	end
	return nil
end
-- the system that creates or places each NPC that has no stall and is no service NPC
local placedBy = {
	["Loot Buyer"] = "item_prices_config.lua", ["Material Broker"] = "professions_config.lua",
	["Mordecai Ashwager"] = "gamble_config.lua", ["Ascendant Oracle"] = "ascension_quest_config.lua",
	["Archivist Maelis"] = "tales_config.lua", ["Wandering Merchant"] = "invasion_config.lua",
	["Widow Hessa"] = "harvest_event_config.lua", ["Cantor Velith"] = "factions_config.lua",
	["Elder Bramwyn"] = "factions_config.lua", ["Forgemaster Brannoc"] = "factions_config.lua",
	["Warden Ysolde"] = "factions_config.lua"
}
for _, name in ipairs(names) do
	local where
	if inBooth[name] then
		where = "stall"
	elseif serviceName[name] then
		where = "service"
	elseif placedBy[name] and sourceMentions(name, placedBy[name]) then
		where = placedBy[name]
	end
	check(where ~= nil, name .. ": is placed (a stall, the service NPC list or its system's startup placement)")
end

-- every NPC name a system config uses is an NPC file (a misspelt name places nothing and logs one line at startup)
do
	for _, b in ipairs(booths) do
		check(npcs[b.npc] ~= nil, "stall (" .. b.x .. "," .. b.y .. "): " .. tostring(b.npc) .. " has an NPC file")
	end
	for key, n in pairs(service.npcs) do
		check(npcs[n.name] ~= nil, "service NPC " .. key .. ": " .. n.name .. " has an NPC file")
		check(npcs[n.name] and npcs[n.name].script == n.script, "service NPC " .. key .. ": the script named in the config is the XML's")
	end
	local travel = dofile("data/scripts/chaos/npc_travel_config.lua")
	for key, n in pairs(travel.npcs) do
		check(npcs[n.name] ~= nil, "travel NPC " .. key .. ": " .. tostring(n.name) .. " has an NPC file")
	end
	for _, f in ipairs(dofile("data/scripts/chaos/factions_config.lua").factions) do
		check(f.npc and npcs[f.npc.name] ~= nil, "faction " .. f.key .. ": its NPC has a file")
	end
	for file, field in pairs({["item_prices_config.lua"] = "npc", ["gamble_config.lua"] = "npc", ["ascension_quest_config.lua"] = "npc",
			["tales_config.lua"] = "npc"}) do
		local cfg = dofile("data/scripts/chaos/" .. file)
		check(type(cfg[field]) == "table" and npcs[cfg[field].name] ~= nil, file .. ": its NPC has a file")
	end
	local poi = dofile("data/scripts/chaos/poi_config.lua")
	for lower in pairs(poi.npcs) do
		local found = false
		for name in pairs(npcs) do
			found = found or name:lower() == lower
		end
		check(found, "poi_config.lua npcs: " .. lower .. " has an NPC file")
	end
end

-- ---------------------------------------------------------------- quest NPCs: every tale step is reachable
do
	dofile("data/scripts/chaos/tales_core.lua")
	local M = ChaosTalesCore
	local archivist = M.cfg().npc.name
	check(npcs[archivist] ~= nil, "the Archivist " .. archivist .. " has an NPC file")
	local talkNpcs = {}
	for _, f in ipairs(dofile("data/scripts/chaos/factions_config.lua").factions) do
		if f.npc then
			talkNpcs[f.npc.name] = true
		end
	end
	for _, t in ipairs(M.tales()) do
		for i, step in ipairs(t.steps) do
			if step.kind == "talk" then
				check(talkNpcs[step.npc], t.key .. " step " .. i .. ": the talk NPC " .. tostring(step.npc) .. " is a faction NPC")
				check(npcs[step.npc] ~= nil, t.key .. " step " .. i .. ": " .. tostring(step.npc) .. " has an NPC file")
			end
			check(M.KINDS[step.kind], t.key .. " step " .. i .. ": a known step kind")
		end
		local last = t.steps[#t.steps].kind
		check(last == "deliver" or last == "report", t.key .. ": ends at the Archivist")
	end
	-- the Archivist answers "tales" and the faction NPCs answer it too (the talk step)
	reset()
	params = npcs[archivist].params
	dofile("data/npc/scripts/" .. npcs[archivist].script)
	local okA = answered("tales", false)
	check(okA, "the Archivist answers 'tales'")
	check(M.asksTales("tales") and M.asksTales("histórias") and M.asksTales("historias"), "tales in English and Portuguese")
end

print(string.format("npc_review_test: %d checks, %d failures", checks, failures))
if failures > 0 then
	os.exit(1)
end
print("npc_review_test: OK")
