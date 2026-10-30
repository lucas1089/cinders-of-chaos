-- Run from the server/ folder: luajit tests/hunt_teleports_test.lua (CI runs it with LuaJIT and Lua 5.3).
-- Hunt teleports (data/scripts/chaos/hunt_teleports_core.lua, hunt_teleports_config.lua, hunt_teleports.lua): the
-- config, validation of the places file, the index, labels and sign text in both languages, the level gate, the exit
-- lookup; then hunt_teleports.lua against a mocked engine: startup places the teleports and writes the signs, the
-- floating labels in each reader's language, the step-in refuses a low level (back, poff, pt-BR text) and sends a player of the band to the arrival; areagen's exit
-- lookup returns the room. The ways back (cfg.returns): every hunt of tools/hall_hunts.csv without a base teleport has
-- one, pairing with the hunt's teleport, the tile choice; startup places them, the step sends players in front of the
-- hunt's teleport and the label floats over them.
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
eq(#cfg.plans, 71, "seventy-one plans (67 generated, 4 imported from a free community map)")
local shown = {}
for _, p in ipairs(cfg.plans) do
	local k = p.monster:lower()
	-- beta 2026-10-22: Wyrmspine Hollows had `display = false` (all its monsters too big) and its showcase stood empty:
	-- no plan hides its display; a hunt whose monsters are all too big takes a stand-in
	ok(p.display ~= false, p.id .. ": the hunt shows a monster (a stand-in when its own are too big)")
	ok(not shown[k], "one slot per monster (owner 2026-10-22): " .. p.monster .. " shown by " .. p.id .. " and " .. tostring(shown[k]))
	shown[k] = p.id
end
local wyrm
for _, p in ipairs(cfg.plans) do
	if p.id == "wyrmspine_hollows" then
		wyrm = p
	end
end
ok(wyrm and wyrm.monster == "Elder Wyrm" and wyrm.standIn == true, "Wyrmspine Hollows shows the Elder Wyrm stand-in")
ok(cfg.items.counter == 1642, "the counter piece behind a teleport (the spare display cell the install opens)")
local seen = {}
for _, p in ipairs(cfg.plans) do
	ok(not seen[p.id], "plan listed once: " .. p.id)
	seen[p.id] = true
	local f = io.open("tools/areaplan/plans/" .. p.id .. ".json", "r")
	ok(f ~= nil, "plan file exists: " .. p.id)
	if f then
		local text = f:read("*a")
		f:close()
		ok(p.standIn or text:find('"monster": "' .. p.monster .. '"', 1, true) ~= nil, p.id .. ": the display monster spawns in the plan (or is a stand-in)")
	end
end
ok(cfg.aid >= 47930 and cfg.aid <= 47939, "aid in its block")
local lv = cfg.hall.levels
ok(lv and #lv == 3 and lv[1].z == 7 and lv[1].max == 500 and lv[2].z == 6 and lv[2].max == 1000 and lv[3].z == 5 and lv[3].max == nil,
	"floors by level: 7 for 1-500, 6 for 500-1000, 5 for 1000 and up")
ok(cfg.hall.quests and cfg.hall.quests.z == 7 and #cfg.hall.quests.chests == 4, "the quest hall and the four reward chests of the base plaza")
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
			sign = {x = 110, y = 96, z = 6}, arrival = {x = 500, y = 500, z = 8}, exit = {x = 500, y = 498, z = 8},
			front = {x = 110, y = 99, z = 6}},
		{id = "not_in_config", name = "X", level = {1, 2}, teleport = {x = 111, y = 98, z = 6},
			arrival = {x = 1, y = 1, z = 7}, exit = {x = 2, y = 1, z = 7}, monster = "Rat"},
		-- a hunt of levels 1-500 on the ground floor's north row, without a front in the places file
		{id = "low_hunt", name = "Low", level = {200, 300}, teleport = {x = 31630, y = 32254, z = 7},
			arrival = {x = 700, y = 700, z = 9}, exit = {x = 701, y = 700, z = 9}}
	},
	-- the hall order (tools/hall_order.py): a base hunt and the floors' bands
	hall = true,
	base = {
		{id = "base_7_120_98", name = "Rat", level = {1, 20}, teleport = {x = 120, y = 98, z = 6},
			sign = {x = 120, y = 96, z = 6}, dest = {x = 900, y = 900, z = 7}}
	},
	floors = {{z = 7, level = {1, 500}}, {z = 6, level = {500, 1000}}, {z = 5, level = {1000, 0}}},
	-- the quest hall (tools/hall_quests.py): the label's spot and how many quests stand there
	quests = {label = {x = 31, y = 24, z = 7}, entrance = {x = 26, y = 24, z = 7}, count = 16}
}
eq(#H.validate(cfg, places), 0, "places valid")
local dup = {back = places.back, places = {places.places[1], places.places[1]}}
eq(#H.validate(cfg, dup), 1, "a shared teleport tile is reported")
eq(#H.validate(cfg, {places = {{id = "q"}}}), 4, "missing back, teleport, arrival, level")
local idx = H.index(cfg, places)
eq(#idx.list, 3, "a plan missing from the config gets its teleport too")
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
-- the exit leads back in front of the plan's own teleport (beta 2026-10-20: every exit led to the middle of floor 6)
local b = H.backFor(idx, {x = 500, y = 498, z = 8})
ok(b and b.x == 110 and b.y == 99 and b.z == 6, "exit goes back in front of its teleport (places file's front)")
b = H.backFor(idx, {x = 701, y = 700, z = 9})
ok(b and b.x == 31630 and b.y == 32255 and b.z == 7, "no front in the places file: below a north-row teleport, on its floor")
b = H.backFor(idx, {x = 2, y = 1, z = 7})
ok(b and b.x == 112 and b.y == 98 and b.z == 6, "a teleport off the rows: the tile towards the stairs")
eq(H.backFor(idx, {x = 500, y = 497, z = 8}), nil, "another tile: no room")
local f = H.frontOf(cfg, {x = 31634, y = cfg.room.teleportRows[2], z = 5})
ok(f.x == 31634 and f.y == cfg.room.teleportRows[2] - 1 and f.z == 5, "front of a south-row teleport: the tile above")
f = H.frontOf(cfg, {x = 31667, y = 32256, z = 5})
ok(f.x == 31666 and f.y == 32256, "front of the east end teleport: towards the stairs")
f = H.frontOf(cfg, {x = 31629, y = 32256, z = 5})
ok(f.x == 31630 and f.y == 32256, "front of the west end teleport: towards the stairs")
eq(H.backFor({byExit = {["1,1,1"] = {}}, back = {x = 9, y = 9, z = 9}}, {x = 1, y = 1, z = 1}).x, 9,
	"an entry without any front: the room's back tile")
eq(#idx.base, 1, "the base hunt is indexed")
eq(H.label(cfg, idx.base[1], "pt-BR"), "Rat, níveis 1-20", "a base hunt's label")
local fl = H.floorLabels(cfg, idx, "en")
eq(#fl, 5, "a label per floor and one over each stairs up")
eq(fl[1].text, "Floor 7: levels 1-500", "the entry floor's label")
eq(fl[1].pos.z, 7, "on its floor")
eq(fl[2].text, "Up: floor 6, levels 500-1000", "the stairs up name the next floor")
eq(fl[2].pos.y, cfg.hall.labels[1].up.y, "over the stairs up")
eq(H.floorLabels(cfg, idx, "pt-BR")[1].text, "Andar 7: níveis 1-500", "pt-BR floor label")
local top = H.floorLabels(cfg, idx, "en")
eq(top[#top].text, "Floor 5: levels 1000+", "the top floor has no ceiling")
eq(top[4].text, "Up: floor 5, levels 1000+", "the stairs up to the top floor")
eq(H.floorLabels(cfg, idx, "pt-BR")[#top].text, "Andar 5: níveis 1000+", "pt-BR top floor label")
local ql = H.questLabel(cfg, idx, "en")
ok(ql ~= nil and ql.text == "Quests" and ql.pos.x == 31 and ql.pos.z == 7, "the quest hall's label")
eq(H.questLabel(cfg, idx, "pt-BR").text, "Missões", "pt-BR quest label")
eq(H.questLabel(cfg, H.index(cfg, {back = places.back, places = places.places}), "en"), nil, "no quest hall: no label")
local qls = H.questLabels(cfg, idx, "pt-BR")
ok(#qls == 2 and qls[2].pos.x == 26 and qls[2].text == "Missões", "a second quest label where the aisle meets the way in")
eq(#H.questLabels(cfg, H.index(cfg, {back = places.back, places = places.places}), "en"), 0, "no quest hall: no labels")
eq(#H.floorLabels(cfg, H.index(cfg, {back = places.back, places = places.places}), "en"), 0, "no hall order: no floor label")
local cfg2 = {aid = 47930, plans = {{id = "widowmere", monster = "M", minLevel = 600}}, texts = {}}
eq(H.index(cfg2, places).list[1].minLevel, 600, "minLevel override")

-- ------------------------------------------------------------------ ways back (cfg.returns)
-- the full list: every hunt of the hall must have a way back (owner 2026-10-20: "many teleports to hunts have no
-- teleport back"). A base hunt (a row with a place) has its own on the map (tools/check_hunt_returns.py checks the
-- map); a planned hunt has its camp portal (the plan's `exit`); a row without a place (added to the hall, `low_*`)
-- needs an entry in cfg.returns.
local csvHunts, csvAdded = {}, {}
do
	local fh = io.open("tools/hall_hunts.csv", "r")
	ok(fh ~= nil, "tools/hall_hunts.csv readable")
	local header = true
	for line in (fh and fh:lines() or function() end) do
		if line:sub(1, 1) ~= "#" then
			if header then
				header = false
			else
				local f, pos = {}, 1
				for _ = 1, 8 do
					local c = line:find(",", pos, true)
					f[#f + 1] = line:sub(pos, (c or 0) - 1)
					pos = (c or #line) + 1
				end
				if f[8] == "hunt" then
					csvHunts[f[1]] = {arrival = {x = tonumber(f[5]), y = tonumber(f[6]), z = tonumber(f[7])}}
					-- a base hunt whose destination moved (beta report 2026-10-22) left the base way back behind
					if f[3] == "" or line:find("destination moved", 1, true) then
						csvAdded[#csvAdded + 1] = f[1]
					end
				end
			end
		end
	end
	if fh then
		fh:close()
	end
end
ok(#csvAdded >= 7, --[[O139 took eight of the ten low_* rows away]]  "the CSV's hunts without a base teleport: " .. #csvAdded)
local listed = {}
for _, r in ipairs(cfg.returns.list) do
	listed[r.id] = r
end
for _, id in ipairs(csvAdded) do
	ok(listed[id] ~= nil, id .. ": a hunt of the hall without a way back (add it to hunt_teleports_config.lua returns)")
end
eq(#H.validateReturns(cfg, csvHunts), 0, "the shipped ways back: each a hunt of the CSV, its tile 1-radius from the arrival")
for _, p in ipairs(cfg.plans) do
	local fh = io.open("tools/areaplan/plans/" .. p.id .. ".json", "r")
	local text = fh and fh:read("*a") or ""
	if fh then
		fh:close()
	end
	ok(text:find('"exit"', 1, true) ~= nil, p.id .. ": the planned hunt has its camp portal (exit) back to the hall")
end
for k, v in pairs(csvHunts) do
	ok(v.arrival.x and v.arrival.y and v.arrival.z, k .. ": the CSV gives the arrival")
end
-- validation
local badR = {returns = {radius = 9, list = {{id = "a", at = {x = 1, y = 1, z = 7}}, {id = "a", at = {x = 1, y = 1, z = 7}},
	{id = "b"}, {at = {x = 5, y = 5, z = 7}}, {id = "far", at = {x = 50, y = 1, z = 7}}, {id = "same", at = {x = 10, y = 10, z = 7}}}}}
local probs = H.validateReturns(badR, {a = {arrival = {x = 2, y = 1, z = 7}}, b = {}, far = {arrival = {x = 1, y = 1, z = 7}},
	same = {arrival = {x = 10, y = 10, z = 7}}})
-- radius; a twice; a shares its tile; b no at; the unnamed: no id, not a hunt; far and same out of reach
eq(#probs, 8, "bad ways back: " .. table.concat(probs, "; "))
eq(#H.validateReturns({}, nil), 0, "no returns: nothing to check")
-- pairing: each way back with its hunt's teleport in the hall, wherever the hall order put it
local rcfg = {room = cfg.room, returns = {radius = 4, list = {
	{id = "low_a", at = {x = 1001, y = 1000, z = 9}},
	{id = "low_b"},
	{id = "plan_c", at = {x = 2001, y = 2000, z = 8}},
	{id = "low_gone", at = {x = 1, y = 1, z = 7}},
	{id = "low_other_floor", at = {x = 3001, y = 3000, z = 7}}}}, plans = {}}
local rplaces = {back = {x = 31648, y = 32256, z = 6}, places = {
	{id = "plan_c", name = "C", level = {1, 2}, teleport = {x = 31610, y = 32258, z = 6}, arrival = {x = 2000, y = 2000, z = 8},
		exit = {x = 2002, y = 2000, z = 8}, front = {x = 31610, y = 32257, z = 6}}},
	base = {
		{id = "low_a", name = "A", level = {4, 10}, teleport = {x = 31630, y = 32254, z = 7}, dest = {x = 1000, y = 1000, z = 9}},
		{id = "low_b", name = "B", level = {4, 10}, teleport = {x = 31634, y = 32258, z = 7}, dest = {x = 1500, y = 1500, z = 9}},
		{id = "low_other_floor", name = "O", level = {4, 10}, teleport = {x = 31638, y = 32258, z = 7}, dest = {x = 3000, y = 3000, z = 8}}
	}}
local ridx = H.index(rcfg, rplaces)
eq(#ridx.returns, 3, "paired: a, b and c; the hunt not in the hall and the `at` on another floor are left out")
local ra = ridx.returns[1]
ok(ra.id == "low_a" and ra.target.x == 31630 and ra.target.y == 32255 and ra.target.z == 7,
	"a north-row hunt: back to the tile below its teleport, on its floor")
ok(ra.arrival.x == 1000 and ra.at.x == 1001, "arrival from the places file, the tile from the config")
local rb = ridx.returns[2]
ok(rb.id == "low_b" and rb.target.y == 32257 and rb.at == nil, "a south-row hunt: the tile above; no `at`: picked")
local rc = ridx.returns[3]
ok(rc.id == "plan_c" and rc.target.x == 31610 and rc.target.y == 32257 and rc.target.z == 6, "a planned hunt: its front")
ridx.byReturn["1001,1000,9"] = ra
local t = H.returnFor(ridx, {x = 1001, y = 1000, z = 9})
ok(t and t.x == 31630 and t.y == 32255, "returnFor the way back's tile")
eq(H.returnFor(ridx, {x = 1002, y = 1000, z = 9}), nil, "another tile: nothing")
eq(H.returnFor(nil, {x = 1, y = 1, z = 1}), nil, "no index: nothing")
eq(H.returnLabel(cfg, "en"), "Back to the teleport room", "label en")
eq(H.returnLabel(cfg, "pt-BR"), "Voltar à sala de teleportes", "label pt-BR")
eq(#H.index(rcfg, {back = rplaces.back}).returns, 0, "no places: no ways back")
-- the tile choice. A map drawn as text: '#' no tile or blocked, '.' free, ',' walkable with something on it,
-- 'S' stairs, 'P' protection zone (walkable, no spot), 'A' the arrival (free)
local function grid(rows, z)
	local cells = {}
	for y, row in ipairs(rows) do
		for x = 1, #row do
			local c = row:sub(x, x)
			if c ~= "#" then
				cells[x .. "," .. y] = {walk = c ~= "S", spot = c == "." or c == "A"}
			end
		end
	end
	return function(p)
		return p.z == (z or 7) and cells[p.x .. "," .. p.y] or nil
	end
end
local function at(p)
	return p and (p.x .. "," .. p.y) or "nil"
end
local room = grid({
	"#####",
	"#...#",
	"#.A.#",
	"#...#",
	"#####"})
eq(at(H.pickReturnTile({x = 3, y = 3, z = 7}, 4, room)), "2,2", "an open room: the nearest, north-west first")
eq(at(H.pickReturnTile({x = 3, y = 3, z = 7}, 4, room, {x = 4, y = 4, z = 7})), "4,4", "the config's tile when it fits")
eq(at(H.pickReturnTile({x = 3, y = 3, z = 7}, 4, room, {x = 3, y = 3, z = 7})), "2,2", "never the arrival itself")
eq(at(H.pickReturnTile({x = 3, y = 3, z = 7}, 4, room, {x = 9, y = 9, z = 7})), "2,2", "a config tile that is not reached: picked")
-- a one-tile corridor with a nook: its tiles would block the way (a diagonal step past a corner does not count); the
-- nook and the dead end do not
local corridor = grid({
	"#######",
	"#A....#",
	"####.##",
	"#######"})
eq(at(H.pickReturnTile({x = 2, y = 2, z = 7}, 4, corridor)), "5,3", "a corridor: not on the way, the nook beside it")
ok(H.cutsWay({x = 3, y = 2, z = 7}, corridor), "a corridor tile splits the way")
ok(not H.cutsWay({x = 6, y = 2, z = 7}, corridor), "a dead end does not")
ok(not H.cutsWay({x = 5, y = 3, z = 7}, corridor), "the nook does not")
ok(H.cutsWay({x = 5, y = 2, z = 7}, corridor), "the junction does")
-- stairs, protection zone, things lying on a tile, a wall between
local busy = grid({
	"#########",
	"#S,P#...#",
	"#,A,#...#",
	"#.,.....#",
	"#########"})
eq(at(H.pickReturnTile({x = 3, y = 3, z = 7}, 4, busy)), "2,4", "not the stairs, the protection zone or a tile with things on it")
eq(at(H.pickReturnTile({x = 3, y = 3, z = 7}, 4, busy, {x = 2, y = 2, z = 7})), "2,4", "the config's tile on stairs: picked")
eq(at(H.pickReturnTile({x = 2, y = 2, z = 7}, 1, grid({"###", "#A#", "###"}))), "nil", "no tile: nil")
eq(at(H.pickReturnTile({x = 3, y = 3, z = 7}, 1, busy)), "2,4", "within the radius")
eq(at(H.pickReturnTile({x = 2, y = 2, z = 7}, 4, grid({"####", "#A,#", "#,,#", "####"}))), "nil", "only busy tiles: nil")
local behind = grid({
	"#######",
	"#,A,#.#",
	"#,,,#.#",
	"#######"})
eq(at(H.pickReturnTile({x = 3, y = 2, z = 7}, 4, behind)), "nil", "a free tile behind a wall is not reached")

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
local function addTile(p, items, flags)
	local t = {items = items or {}, flags = flags or {}}
	function t:getGround()
		return true
	end
	function t:hasFlag(f)
		return self.flags[f] == true
	end
	function t:getHouse()
		return nil
	end
	function t:getDownItemCount()
		return self.down or 0
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
TILESTATE_PROTECTIONZONE, TILESTATE_FLOORCHANGE, TILESTATE_TELEPORT, TILESTATE_MAGICFIELD = "pz", "fc", "tp", "mf"
TILESTATE_BLOCKSOLID, TILESTATE_BLOCKPATH = "bs", "bp"
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
RETURNVALUE_NOERROR, RETURNVALUE_NOTPOSSIBLE = 0, 1
EventCallback = setmetatable({}, {__newindex = function(t, k, v)
	rawset(t, k, v)
	registered[k] = v
end})
function EventCallback.register() end
COMBAT_HEALING, COMBAT_FIREDAMAGE = 128, 8
function CreatureEvent(name)
	local e = {name = name}
	function e:register()
		registered[name] = e
	end
	return e
end
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
-- an added hunt of the hall (the config's first way back) at its slot on the ground floor's north row, its arrival
-- in an open cave: the way back goes on the config's tile
local ret1 = cfg.returns.list[1]
local rArr = {x = ret1.at.x - 1, y = ret1.at.y + 1, z = ret1.at.z}
places.base[#places.base + 1] = {id = ret1.id, name = "Rat", level = {4, 5}, teleport = {x = 31630, y = 32254, z = 7},
	dest = rArr}
for dy = -4, 4 do
	for dx = -4, 4 do
		addTile({x = rArr.x + dx, y = rArr.y + dy, z = rArr.z})
	end
end
-- the second one's arrival: its config tile has something on it, so the nearest free tile is taken
local ret2 = cfg.returns.list[2]
local rArr2 = {x = ret2.at.x + 1, y = ret2.at.y + 1, z = ret2.at.z}
places.base[#places.base + 1] = {id = ret2.id, name = "Dworc", level = {9, 15}, teleport = {x = 31634, y = 32258, z = 7},
	dest = rArr2}
for dy = -4, 4 do
	for dx = -4, 4 do
		addTile({x = rArr2.x + dx, y = rArr2.y + dy, z = rArr2.z})
	end
end
tiles[pkey(ret2.at)].down = 1
addTile({x = 120, y = 96, z = 6}, {newItem(5360)})
dofile("data/scripts/chaos/hunt_teleports.lua")
registered.startup.onStartup()
print = realPrint
eq(#created, 3, "one hall teleport and two ways back created")
eq(created[1].aid, 47930, "with the aid")
eq(tiles[pkey(ret1.at)].items[1], created[2], "the first way back on the config's tile")
eq(created[2].aid, cfg.aid, "the way back has the hall's action id")
ok(created[2].attrs.desc:find("Back to the teleport room", 1, true) ~= nil, "the way back's description")
local moved = ChaosHuntTeleports.idx.returns[2].pos
ok(moved and pkey(moved) ~= pkey(ret2.at) and moved.z == ret2.at.z
	and math.max(math.abs(moved.x - rArr2.x), math.abs(moved.y - rArr2.y)) == 1,
	"the config's tile taken: the nearest free tile beside the arrival")
local warned = false
for _, line in ipairs(printed) do
	warned = warned or (tostring(line):find("its `at` is not free", 1, true) ~= nil)
end
ok(warned, "the log names a way back that stands off its config tile")
ok(created[1].attrs.desc:find("Widowmere, levels 480-640", 1, true) ~= nil, "description")
eq(tiles["110,96,6"].items[1].attrs.text, "Widowmere, levels 480-640\nWidowmere, níveis 480-640", "sign written")
eq(registered.step.aidv, 47930, "step-in registered on the aid")
eq(tiles["120,96,6"].items[1].attrs.text, "Rat, levels 1-20\nRat, níveis 1-20", "the base hunt's sign written")
-- a second startup keeps the one teleport
print = function() end
registered.startup.onStartup()
print = realPrint
eq(#created, 3, "startup again: no second teleport, no second way back")
io.open, dofile = realOpen, realDofile

local function player(level, lang)
	local pl = {level = level, lang = lang, msgs = {}}
	function pl:isMonster()
		return false
	end
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
	return (pkey(pos) == "110,98,6" or pkey(pos) == "31,24,7" or pkey(pos) == "26,24,7") and {reader} or {}
end
local fl = registered.ChaosHuntTeleportsLabels
ok(fl ~= nil and fl.ms == cfg.floatText.interval, "label think registered")
fl.onThink()
eq(#said, 3, "the teleport's label and the quest hall's two")
eq(said[1][1], "Widowmere, níveis 480-640", "label in the reader's language")
ok(said[1][3] == reader and said[1][4] == "110,98,6", "sent to the reader only, over the teleport")
local qsay
for _, m in ipairs(said) do
	if m[4] == "31,24,7" then
		qsay = m
	end
end
ok(qsay ~= nil and qsay[1] == "Missões" and qsay[3] == reader, "the quest hall's label, in the reader's language")
local esay
for _, m in ipairs(said) do
	if m[4] == "26,24,7" then
		esay = m
	end
end
ok(esay ~= nil and esay[1] == "Missões", "the label where the aisle meets the way to the quest hall")
-- the way back: in front of the hunt's teleport (north row: the tile below), with the teleport effect
local walker = player(5, "en")
registered.step.onStepIn(walker, created[2], Position(ret1.at.x, ret1.at.y, ret1.at.z), Position(rArr.x, rArr.y, rArr.z))
eq(pkey(walker.pos), "31630,32255,7", "the way back leads in front of the hunt's teleport")
eq(effects[#effects][2], cfg.effects.go, "with the teleport effect")
local rsaid = {}
local near = player(5, "pt-BR")
function near:say(text, kind, ghost, to, pos)
	rsaid[#rsaid + 1] = {text, kind, pkey(pos)}
end
local oldSpec = Game.getSpectators
Game.getSpectators = function(pos)
	return pkey(pos) == pkey(ret1.at) and {near} or {}
end
fl.onThink()
Game.getSpectators = oldSpec
ok(#rsaid == 1 and rsaid[1][1] == "Voltar à sala de teleportes" and rsaid[1][2] == TALKTYPE_MONSTER_SAY
	and rsaid[1][3] == pkey(ret1.at), "the way back's label floats over it in the reader's language (orange monster say)")
local back = ChaosHuntTeleports.backFor({x = 500, y = 498, z = 8})
ok(back and back.x == 110 and back.y == 99 and back.z == 6, "areagen exit lookup returns the tile in front of its teleport")

-- display monsters: the cells of the room are harmless (owner's bug 2026-10-16: a display Mirecoil Wyrm killed a
-- level 8 player on the carpet with its telegraphs)
local cellN, cellS = cfg.room.cellRows[1], cfg.room.cellRows[2]
ok(H.isDisplaySpot(cfg, {x = 31648, y = cellN, z = 6}), "a north cell of floor 6 is a display spot")
ok(H.isDisplaySpot(cfg, {x = 31612, y = cellS, z = 6}), "a south cell of the grown west wing")
ok(H.isDisplaySpot(cfg, {x = 31640, y = cellN, z = 5}) and H.isDisplaySpot(cfg, {x = 31640, y = cellN, z = 7}),
	"the base room's own cells on floors 5 and 7")
ok(not H.isDisplaySpot(cfg, {x = 31648, y = 32256, z = 6}), "the carpet is not")
ok(not H.isDisplaySpot(cfg, {x = 31648, y = cellN, z = 8}), "another floor is not")
ok(not H.isDisplaySpot(cfg, {x = 31500, y = cellN, z = 6}), "outside the hall is not")
ok(not H.isDisplaySpot(cfg, nil) and not H.isDisplaySpot({}, {x = 31648, y = cellN, z = 6}), "no data: not a display")
local function mon(pos, master)
	return {pos = pos, isMonster = function() return true end, getMaster = function() return master end,
		getPosition = function(self) return self.pos end}
end
local display = mon({x = 31648, y = cellN, z = 6})
local hunter = mon({x = 31648, y = 32256, z = 6})
ok(ChaosHuntTeleports.isDisplay(display), "isDisplay: the monster in a cell")
ok(not ChaosHuntTeleports.isDisplay(hunter), "isDisplay: not a monster elsewhere")
ok(not ChaosHuntTeleports.isDisplay(mon({x = 31648, y = cellN, z = 6}, {})), "isDisplay: not a summon")
local gate = registered.onTargetCombat
ok(gate ~= nil, "onTargetCombat registered")
local victim = player(8, "en")
eq(gate(display, victim), RETURNVALUE_NOTPOSSIBLE, "a display monster never hits a player")
eq(gate(hunter, victim), RETURNVALUE_NOERROR, "other monsters are left alone")
ok(ChaosHuntTeleports.isDisplaySpot({x = 31648, y = cellS, z = 6}), "HT.isDisplaySpot for the other systems")
-- nobody hurts a display monster either (beta 2026-10-22: Smoldering Aura, a direct hit, killed them)
eq(gate(hunter, display), RETURNVALUE_NOTPOSSIBLE, "no combat reaches a display monster")
local guard = registered.ChaosHallDisplayGuard
ok(guard ~= nil and guard.onHealthChange ~= nil, "the display guard is registered")
local pd, pt, sd = guard.onHealthChange(display, victim, -500, COMBAT_FIREDAMAGE, -20, COMBAT_FIREDAMAGE)
ok(pd == 0 and pt == COMBAT_FIREDAMAGE and sd == 0, "a display monster takes no direct damage")
eq(guard.onHealthChange(display, nil, 300, COMBAT_HEALING, 0, COMBAT_HEALING), 300, "it may still heal")
eq(guard.onHealthChange(hunter, victim, -500, COMBAT_FIREDAMAGE, 0, COMBAT_FIREDAMAGE), -500, "other monsters take it")
local regs = {}
local spawned = mon({x = 31648, y = cellN, z = 6})
function spawned:registerEvent(n) regs[#regs + 1] = n end
eq(registered.onSpawn(spawned, {x = 31648, y = cellN, z = 6}, true, false), true, "onSpawn lets it spawn")
eq(regs[1], "ChaosHallDisplayGuard", "a display monster gets the guard at its spawn")
regs = {}
eq(registered.onSpawn(spawned, {x = 31648, y = 32256, z = 6}, true, false), true, "onSpawn elsewhere")
eq(#regs, 0, "a monster elsewhere gets no guard")

-- the showcase shows its hunt's level (beta 2026-10-22: Dragon [42] beside a hunt of levels 665+)
do
	local dcfg = {room = {teleportRows = {32254, 32258}, cellRows = {32253, 32259}}, hall = {endRow = 32256}}
	local didx = {list = {{teleport = {x = 31638, y = 32258, z = 6}, level = {665, 840}}},
		base = {{teleport = {x = 31634, y = 32254, z = 6}, level = {100, 140}},
			{teleport = {x = 31667, y = 32256, z = 5}, level = {1850, 2000}}}}
	eq(H.displayLevel(H.entryForDisplay(dcfg, didx, {x = 31638, y = 32259, z = 6})), 753, "the cell behind: the band's middle")
	eq(H.displayLevel(H.entryForDisplay(dcfg, didx, {x = 31639, y = 32259, z = 6})), 753, "a cell beside")
	eq(H.displayLevel(H.entryForDisplay(dcfg, didx, {x = 31633, y = 32253, z = 6})), 120, "a base hunt's cell")
	eq(H.displayLevel(H.entryForDisplay(dcfg, didx, {x = 31668, y = 32255, z = 5})), 1925, "an end teleport's cell")
	eq(H.entryForDisplay(dcfg, didx, {x = 31650, y = 32253, z = 6}), nil, "no teleport by it: nil")
	eq(H.displayLevel({level = {1000, 0}}), 1000, "no ceiling: the floor")
	eq(H.displayLevel(nil), nil, "no hunt: nil")
end

print(string.format("hunt_teleports_test: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end
