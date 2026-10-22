-- Run from the server/ folder: luajit tests/commands_ui_test.lua (and lua5.3; CI runs both)
-- Pure logic of the Info & Services window (commands_ui_core.lua): the talkactions.xml parser (commented-out lines
-- too), the ancestral store list, the text capture around a command, the sandbox for base revscripts, and that no
-- Chaos script registers a spoken player command any more (every "!" word is gone; staff "/" words stay).
dofile("data/scripts/chaos/commands_ui_core.lua")
local K = ChaosCommandsCore

local function eq(a, b, m)
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

-- ---------------------------------------------------------------- registry
local called
ChaosCommands.register("x", function(player, param) called = param end)
ChaosCommands.register(5, function() end)
ChaosCommands.handlers.x(nil, "p")
eq(called, "p", "registered handler")
eq(ChaosCommands.handlers[5], nil, "only string ids")

-- ---------------------------------------------------------------- XML
local xml = [[
	<talkaction words="/ban" separator=" " script="ban.lua" />
	<!-- chaos-menu (Info & Services window): <talkaction words="!online;/online" script="online.lua" /> -->
	<talkaction words="!ancestralstore 2, 1" script="fiery_wings.lua" />
	<talkaction words="!ancestralstore 1, 10" script="bats.lua" />
	<talkaction words="!ancestralstore 3, 11" script="sword_chest.lua" />
	<talkaction words="!broken" />
]]
local map = K.parseXml(xml)
eq(map["/ban"], "ban.lua", "staff line")
eq(map["!online"], "online.lua", "commented line still read")
eq(map["/online"], "online.lua", "both words of a line")
eq(map["!broken"], nil, "line without script")
eq(K.label("fiery_wings.lua"), "Fiery Wings", "label")
eq(K.label("durable_bow_chest.lua"), "Durable Bow Chest", "label of three words")
local store = K.ancestralStore(map)
eq(#store, 3, "store entries")
eq(store[1].param, "2, 1", "sorted by entry number")
eq(store[2].label, "Bats", "second entry")
eq(store[3].group, 3, "group")
eq(store[1].id, 1, "entry id")
eq(store[1].script, "fiery_wings.lua", "entry script")
local dup = K.ancestralStore(K.parseXml([[<talkaction words="!ancestralstore 1, 4" script="a.lua" />
<talkaction words="!ancestralstore 2, 4" script="b.lua" />]]))
eq(#dup, 1, "an entry number used twice is kept once")

-- ---------------------------------------------------------------- ancestral store: prices and requests
local p, it = K.parseStoreScript("local ITEM_PRICE = 35\nfunction onSay()\n local item = ItemType(26652) \nend")
eq(p, 35, "price parsed"); eq(it, 26652, "item parsed")
eq(K.parseStoreScript("local ITEM_PRICE = 0\n ItemType(26652)"), nil, "zero price refused")
eq(K.parseStoreScript("local ITEM_PRICE = 99999999\n ItemType(26652)"), nil, "absurd price refused")
eq(K.parseStoreScript("ItemType(26652)"), nil, "no price")
eq(K.parseStoreScript(nil), nil, "no script")
local scripts = {["fiery_wings.lua"] = "ITEM_PRICE = 25 ItemType(26644)", ["bats.lua"] = "ITEM_PRICE = 60 ItemType(26649)",
	["sword_chest.lua"] = "ITEM_PRICE = 25 ItemType(1)"}
local entries = K.storeEntries(store, function(s) return scripts[s] end, function(id)
	return id == 26644 and {name = "Fiery Wings", clientId = 501} or id == 26649 and {name = "Bats Aura", clientId = 502} or nil
end)
eq(#entries, 2, "entries with a price and a known item")
eq(entries[1].kind, "Wings", "group 2 gives wings"); eq(entries[2].kind, "Aura", "group 1 gives an aura")
eq(entries[1].clientId, 501, "client id kept")
local e, c, cost = K.validateBuy(entries, 1)
eq(e and e.id, 1, "valid id"); eq(c, 1, "count defaults to 1"); eq(cost, 25, "cost")
e, c, cost = K.validateBuy(entries, "10", 3)
eq(e and e.id, 10, "id as a digit string"); eq(cost, 180, "3 x 60")
for _, badCount in ipairs({0, -1, 11, 1e12, 2.5, "3x", "", 0 / 0, math.huge, -math.huge, true, {}}) do
	local r, why = K.validateBuy(entries, 1, badCount)
	eq(r, nil, "bad count " .. tostring(badCount) .. " refused"); eq(why, "count", "reason count")
end
for _, badId in ipairs({999, 0, -1, 1.5, "1 OR 1=1", {}, nil}) do
	local r, why = K.validateBuy(entries, badId, 1)
	eq(r, nil, "bad id " .. tostring(badId) .. " refused"); eq(why, "id", "reason id")
end
eq(K.entryByParam(entries, "2, 1").id, 1, "legacy param"); eq(K.entryByParam(entries, "9, 9"), nil, "unknown param")
local payload = K.storePayload(entries, -5, "hi")
eq(payload.points, 0, "points never negative in the answer"); eq(payload.entries[1].item, 501, "payload item")
eq(payload.entries[1].script, nil, "server-only fields left out"); eq(payload.message, "hi", "message")
local slots = {}
eq(K.throttle(slots, 1, 1000, 1000), true, "first buy"); eq(K.throttle(slots, 1, 1500, 1000), false, "too soon")
eq(K.throttle(slots, 1, 2000, 1000), true, "after the interval")
eq(K.rewrite({"You didn't have any current Double EXP enhancement.", "x"})[1], "No Double EXP active.", "rewrite")

-- ---------------------------------------------------------------- Services state
local st = K.servicesState({nameTokens = -1, vocationTokens = 2, level = 250, familiarLevel = 200,
	frames = {"frost", 5}, activeFrame = "frost"})
eq(st.nameTokens, 0, "no token is 0"); eq(st.vocationTokens, 2, "vocation tokens")
eq(st.familiarReady, true, "familiar from level 200"); eq(#st.frames, 1, "only names kept")
eq(st.freeSwitch, "", "no free switch"); eq(st.inTutorial, false, "not in the tutorial")
eq(st.webshopOrders, -1, "web shop orders unknown")
eq(st.inBossRoom, false, "not in a boss room")
eq(K.servicesState({inBossRoom = true}).inBossRoom, true, "in a boss room: Leave Boss Room enabled")

-- ---------------------------------------------------------------- params
eq(K.cleanParam("  New\tName\n ", 64), "New Name", "trimmed, control characters out")
eq(#K.cleanParam(string.rep("a", 100), 10), 10, "cut at the maximum")
eq(K.PARAM.plateframe ~= nil and K.PARAM.plateframe >= #"sepulchre", true, "the plate frame command takes a frame name")

-- ---------------------------------------------------------------- capture
local Methods = {}
local sent = {}
function Methods.sendTextMessage(self, type, text) sent[#sent + 1] = self.id .. ":" .. text; return true end
function Methods.sendCancelMessage(self, text) sent[#sent + 1] = self.id .. ":cancel:" .. tostring(text); return true end
function Methods.popupFYI(self, text) sent[#sent + 1] = self.id .. ":fyi:" .. text; return true end
local a, b = {id = 1}, {id = 2}
local lines, restore = K.capture(Methods, 1, function(p) return p.id end, function(n) return "ret" .. n end)
Methods.sendTextMessage(a, 22, "hello")
Methods.sendCancelMessage(a, 7)
Methods.popupFYI(a, "popup")
Methods.sendTextMessage(a, 22, "hello")
Methods.sendTextMessage(b, 22, "other player")
restore()
Methods.sendTextMessage(a, 22, "after")
eq(#lines, 4, "lines caught")
eq(lines[2], "ret7", "return value turned into its text")
eq(sent[1], "2:other player", "another player's message goes through")
eq(sent[2], "1:after", "restored")
eq(#sent, 2, "nothing else sent")
eq(K.joinLines(lines), "hello\nret7\npopup", "repeats dropped")
eq(K.joinLines({}, "Done."), "Done.", "fallback")

-- ---------------------------------------------------------------- revscript sandbox
local base = {print = print}
local env, talks = K.stubEnv(base)
local chunk = [[
	local a = TalkAction("!one")
	function a.onSay(player, words) return words end
	a:separator(" ")
	a:register()
	local ev = CreatureEvent("x")
	ev:register()
	local b = TalkAction("!two")
	b.onSay = function() return "two" end
	b:register()
]]
local fn = loadstring and loadstring(chunk) or load(chunk, "chunk", "t", env)
if setfenv then setfenv(fn, env) end
fn()
eq(#talks, 2, "talk actions recorded")
eq(talks[1].onSay(nil, "!one"), "!one", "first onSay")
eq(talks[2].onSay(), "two", "second onSay")

-- ---------------------------------------------------------------- no spoken player command left
local function listDir(path)
	local p = io.popen('ls "' .. path .. '"')
	local out = {}
	for name in p:lines() do
		out[#out + 1] = name
	end
	p:close()
	return out
end
local offenders = {}
for _, name in ipairs(listDir("data/scripts/chaos")) do
	if name:match("%.lua$") then
		local f = io.open("data/scripts/chaos/" .. name)
		local text = f:read("*a")
		f:close()
		for args in text:gmatch("TalkAction%(([^)]*)%)") do
			-- the owner's exception (2026-10-15): !bless (gentledeath.lua, its words in gentledeath_config.lua)
			if args:find('"!') and not args:find('"!bless"', 1, true) then
				offenders[#offenders + 1] = name .. ": " .. args
			end
		end
		for words in text:gmatch('ipairs%(%{([^}]*)%}%) do%s+local talk = TalkAction') do
			if words:find('"!') then
				offenders[#offenders + 1] = name .. ": " .. words
			end
		end
	end
end
eq(table.concat(offenders, "; "), "", "Chaos scripts with a spoken player command")

print("commands_ui_test: OK")
