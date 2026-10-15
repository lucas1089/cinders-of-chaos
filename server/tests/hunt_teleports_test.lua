-- Run from the server/ folder: luajit tests/hunt_teleports_test.lua (CI runs it with LuaJIT and Lua 5.3).
-- Hunt teleports (data/scripts/chaos/hunt_teleports_core.lua, hunt_teleports_config.lua, hunt_teleports.lua): the
-- config, validation of the places file, the index, labels and sign text in both languages, the level gate, the exit
-- lookup; then hunt_teleports.lua against a mocked engine: startup places the teleports and writes the signs, the
-- floating labels in each reader's language, the step-in refuses a low level (back, poff, pt-BR text) and sends a player of the band to the arrival; areagen's exit
-- lookup returns the room.
local checks, fails = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. tostring(what))
	end
end
local function eq(a, b, what)
	ok(a == b, (what or "check") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

dofile("data/scripts/chaos/hunt_teleports_core.lua")
local H = ChaosHuntTeleportsCore
local cfg = dofile("data/scripts/chaos/hunt_teleports_config.lua")

-- ------------------------------------------------------------------ the config
eq(#H.validate(cfg, nil), 0, "the shipped config is valid")
eq(#cfg.plans, 17, "seventeen plans")
local seen = {}
for _, p in ipairs(cfg.plans) do
	ok(not seen[p.id], "plan listed once: " .. p.id)
	seen[p.id] = true
	local f = io.open("tools/areaplan/plans/" .. p.id .. ".json", "r")
	ok(f ~= nil, "plan file exists: " .. p.id)
	if f then
		local text = f:read("*a")
		f:close()
		ok(text:find('"monster": "' .. p.monster .. '"', 1, true) ~= nil, p.id .. ": the display monster spawns in the plan")
	end
end
ok(cfg.aid >= 47930 and cfg.aid <= 47939, "aid in its block")
for k, v in pairs(cfg.texts["pt-BR"]) do
	local a, b = select(2, k:gsub("%%[ds]", "")), select(2, v:gsub("%%[ds]", ""))
	eq(a, b, "pt-BR keeps the conversions of " .. k)
end

local bad = {aid = 1, plans = {{id = "a", monster = "x"}, {id = "a"}}}
eq(#H.validate(bad, nil), 3, "bad aid, twice listed, no monster")

-- ------------------------------------------------------------------ places, index
local places = {
	back = {x = 100, y = 100, z = 6},
	places = {
		{id = "widowmere", name = "Widowmere", level = {480, 640}, teleport = {x = 110, y = 98, z = 6},
			sign = {x = 110, y = 96, z = 6}, arrival = {x = 500, y = 500, z = 8}, exit = {x = 500, y = 498, z = 8}},
		{id = "not_in_config", name = "X", level = {1, 2}, teleport = {x = 111, y = 98, z = 6},
			arrival = {x = 1, y = 1, z = 7}, monster = "Rat"}
	}
}
eq(#H.validate(cfg, places), 0, "places valid")
local dup = {back = places.back, places = {places.places[1], places.places[1]}}
eq(#H.validate(cfg, dup), 1, "a shared teleport tile is reported")
eq(#H.validate(cfg, {places = {{id = "q"}}}), 4, "missing back, teleport, arrival, level")
local idx = H.index(cfg, places)
eq(#idx.list, 2, "a plan missing from the config gets its teleport too")
eq(idx.byTeleport["111,98,6"].monster, "Rat", "its display monster from the places file")
eq(idx.byTeleport["111,98,6"].minLevel, 1, "its floor from the band")
local e = idx.byTeleport["110,98,6"]
ok(e ~= nil, "entry by teleport tile")
eq(e.minLevel, 480, "floor of the band")
eq(e.monster, "Nightfang Widow", "display monster from the config")
eq(H.label(cfg, e, "en"), "Widowmere, levels 480-640", "label en")
eq(H.label(cfg, e, "pt-BR"), "Widowmere, níveis 480-640", "label pt")
eq(H.signText(cfg, e), "Widowmere, levels 480-640\nWidowmere, níveis 480-640", "sign text")
local o, msg = H.enter(cfg, e, 479, "pt-BR")
ok(not o, "level 479 refused")
eq(msg, "Widowmere é para nível 480 ou mais.", "refusal pt")
o, msg = H.enter(cfg, e, 480, "en")
ok(o, "level 480 enters")
ok(msg:find("480-640", 1, true) ~= nil, "arrival message names the band")
eq(H.lang("pt-BR"), "pt-BR", "lang pt")
eq(H.lang("pt"), "pt-BR", "lang pt short")
eq(H.lang(nil), "en", "lang default")
local b = H.backFor(idx, {x = 500, y = 498, z = 8})
ok(b and b.x == 100, "exit goes back to the room")
eq(H.backFor(idx, {x = 500, y = 497, z = 8}), nil, "another tile: no room")
local cfg2 = {aid = 47930, plans = {{id = "widowmere", monster = "M", minLevel = 600}}, texts = {}}
eq(H.index(cfg2, places).list[1].minLevel, 600, "minLevel override")

-- ------------------------------------------------------------------ the engine file, mocked
local tiles = {}
local function pkey(p)
	return p.x .. "," .. p.y .. "," .. p.z
end
local effects, created = {}, {}
local function newItem(id)
	local it = {id = id, aid = 0, attrs = {}}
	function it:getActionId()
		return self.aid
	end
	function it:setActionId(a)
		self.aid = a
	end
	function it:setAttribute(k, v)
		self.attrs[k] = v
	end
	return it
end
local function addTile(p, items)
	local t = {items = items or {}}
	function t:getGround()
		return true
	end
	function t:getItemById(id)
		for _, it in ipairs(self.items) do
			if it.id == id then
				return it
			end
		end
	end
	tiles[pkey(p)] = t
	return t
end
ITEM_ATTRIBUTE_DESCRIPTION, ITEM_ATTRIBUTE_TEXT, MESSAGE_EVENT_ADVANCE = "desc", "text", 19
function Position(x, y, z)
	local p = {x = x, y = y, z = z}
	function p:sendMagicEffect(e)
		effects[#effects + 1] = {pkey(self), e}
	end
	return p
end
function Tile(p)
	return tiles[pkey(p)]
end
Game = {createItem = function(id, n, p)
	local it = newItem(id)
	local t = tiles[pkey(p)]
	t.items[#t.items + 1] = it
	created[#created + 1] = it
	return it
end}
local registered = {}
function GlobalEvent(name)
	local g = {}
	function g:interval(ms)
		g.ms = ms
	end
	function g:register()
		registered[name == "ChaosHuntTeleports" and "startup" or name] = g
	end
	return g
end
TALKTYPE_MONSTER_SAY = 36
function MoveEvent()
	local m = {}
	function m:type() end
	function m:aid(a)
		m.aidv = a
	end
	function m:register()
		registered.step = m
	end
	return m
end
Chaos = {lang = function(pl)
	return pl.lang
end}
-- places file in a temp path: the engine file reads data/lib/chaos_hunt_places.lua; point io.open at a fake
local realOpen, realDofile = io.open, dofile
local PL = "data/lib/chaos_hunt_places.lua"
io.open = function(path, mode)
	if path == PL then
		return {close = function() end}
	end
	return realOpen(path, mode)
end
dofile = function(path)
	if path == PL then
		return places
	end
	return realDofile(path)
end
local printed = {}
local realPrint = print
print = function(s)
	printed[#printed + 1] = s
end
addTile({x = 110, y = 98, z = 6})
addTile({x = 110, y = 96, z = 6}, {newItem(5360)})
dofile("data/scripts/chaos/hunt_teleports.lua")
registered.startup.onStartup()
print = realPrint
eq(#created, 1, "one teleport created")
eq(created[1].aid, 47930, "with the aid")
ok(created[1].attrs.desc:find("Widowmere, levels 480-640", 1, true) ~= nil, "description")
eq(tiles["110,96,6"].items[1].attrs.text, "Widowmere, levels 480-640\nWidowmere, níveis 480-640", "sign written")
eq(registered.step.aidv, 47930, "step-in registered on the aid")
-- a second startup keeps the one teleport
print = function() end
registered.startup.onStartup()
print = realPrint
eq(#created, 1, "startup again: no second teleport")
io.open, dofile = realOpen, realDofile

local function player(level, lang)
	local pl = {level = level, lang = lang, msgs = {}}
	function pl:getPlayer()
		return self
	end
	function pl:getLevel()
		return self.level
	end
	function pl:teleportTo(p)
		self.pos = Position(p.x, p.y, p.z)
	end
	function pl:getPosition()
		return self.pos
	end
	function pl:sendCancelMessage(m)
		self.msgs[#self.msgs + 1] = m
	end
	function pl:sendTextMessage(_, m)
		self.msgs[#self.msgs + 1] = m
	end
	return pl
end
local from = Position(110, 99, 6)
local low = player(300, "pt-BR")
registered.step.onStepIn(low, created[1], Position(110, 98, 6), from)
eq(pkey(low.pos), "110,99,6", "low level sent back")
eq(low.msgs[1], "Widowmere é para nível 480 ou mais.", "pt-BR refusal")
eq(effects[#effects][2], cfg.effects.refuse, "poff")
local hi = player(500, "en")
registered.step.onStepIn(hi, created[1], Position(110, 98, 6), from)
eq(pkey(hi.pos), "500,500,8", "sent to the arrival")
eq(effects[#effects][2], cfg.effects.go, "teleport effect")
-- the floating labels, each in the reader's language
local said = {}
local reader = player(10, "pt-BR")
function reader:say(text, kind, ghost, to, pos)
	said[#said + 1] = {text, kind, to, pkey(pos)}
end
Game.getSpectators = function(pos)
	return pkey(pos) == "110,98,6" and {reader} or {}
end
local fl = registered.ChaosHuntTeleportsLabels
ok(fl ~= nil and fl.ms == cfg.floatText.interval, "label think registered")
fl.onThink()
eq(#said, 1, "one label")
eq(said[1][1], "Widowmere, níveis 480-640", "label in the reader's language")
ok(said[1][3] == reader and said[1][4] == "110,98,6", "sent to the reader only, over the teleport")
local back = ChaosHuntTeleports.backFor({x = 500, y = 498, z = 8})
ok(back and back.x == 100 and back.z == 6, "areagen exit lookup returns the room")

print(string.format("hunt_teleports_test: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end
