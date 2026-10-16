-- Run from the server/ folder: luajit tests/cityportals_test.lua (and lua5.3; CI runs both)
-- City portals (server/README.md "City portals"): the shipped config (every kind named, described and translated, the
-- fixed spots per town, the hall's portal row), the pure rules of cityportals_core.lua (candidates, free tiles, the
-- pick, the look text), then cityportals.lua and cityportals_fx.lua on a mocked map: the hall's portal room first,
-- a town's fixed spot, the offsets on another map, placed once, the registry, the effect pulse and the look text in
-- both languages; and the three users (hideout.lua, guild_hall.lua, npc_booths.lua) through the shared helper.
local checks, failures = 0, 0
local function check(c, m)
	checks = checks + 1
	if not c then
		failures = failures + 1
		print("FAIL " .. m)
	end
end
local function eq(a, b, m)
	check(a == b, m .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

dofile("data/scripts/chaos/cityportals_core.lua")
local C = ChaosCityPortalsCore
local cfg = C.cfg()
local pt = dofile("data/scripts/chaos/i18n_strings.lua")["pt-BR"]
local booths = dofile("data/scripts/chaos/npc_booths_config.lua")

-- ---------------------------------------------------------------- the shipped config
for _, kind in ipairs({"hideout", "guildhall", "services", "siege", "memorial", "worldboss", "chronicle", "descent", "raid", "hunt", "idlehall"}) do
	local k = cfg.kinds[kind]
	check(k ~= nil, kind .. ": a kind")
	check(k.name:find("Portal", 1, true) ~= nil or k.name:find("Gate", 1, true) ~= nil or k.name:find("Exit", 1, true) ~= nil, kind .. ": the name says it is a portal")
	check(#k.text > 20 and (k.text:find("Step in", 1, true) or k.text:find("step in", 1, true)), kind .. ": says what it does")
	-- the Descent and the raid open a window; their runs bring the party back themselves
	check(kind == "descent" or kind == "raid" or k.text:find("exit portal", 1, true) ~= nil
		or k.text:find("back to your temple", 1, true) ~= nil, kind .. ": says the way back")
	check(pt[k.name] ~= nil, kind .. ": pt-BR name")
	check(pt[k.text] ~= nil, kind .. ": pt-BR text")
	check(type(k.effect) == "string" and k.effect:match("^CONST_ME_[A-Z_]+$") ~= nil, kind .. ": an effect name")
end
check(cfg.pulseMs >= 2000 and cfg.pulseMs <= 10000, "the effect every few seconds")
eq(cfg.item, 1387, "a magic forcefield, like every other Chaos portal")

-- the fixed spots: next to the temple, the two of a town side by side, never the temple tile, never the hall entry
local nTowns = 0
for id, t in pairs(cfg.towns) do
	nTowns = nTowns + 1
	check(type(t.temple) == "table" and #t.temple == 3, id .. ": the temple the spots were chosen for")
	local h, g = t.hideout, t.guildhall
	check(h and g, id .. ": a hideout and a guild hall spot")
	for _, s in ipairs({h, g}) do
		local dist = math.max(math.abs(s[1]), math.abs(s[2]))
		check(dist >= 2 and dist <= 7, id .. ": within 2-7 squares of the temple")
	end
	check(not (h[1] == g[1] and h[2] == g[2]), id .. ": two tiles")
	eq(math.max(math.abs(h[1] - g[1]), math.abs(h[2] - g[2])), 1, id .. ": side by side")
	for _, hall in ipairs(booths.halls) do
		if hall.town == id then
			for _, o in ipairs(hall.entryOffsets or {}) do
				check(not (o[1] == h[1] and o[2] == h[2]) and not (o[1] == g[1] and o[2] == g[2]),
					id .. ": not on the Hall of Services Portal's tile")
			end
		end
	end
end
eq(nTowns, 20, "every town of the reference map")
eq(cfg.towns[2].temple[1], 32369, "Cinderhold's temple")
-- the hall: hideout and guild hall stand in the portal room's row, apart from the Descent and raid portals
check(cfg.hall.hideout and cfg.hall.guildhall and not cfg.hall.services, "hall kinds")
local row = booths.portals
local inRow = {"descent", "raid", "hideout", "guildhall", "memorial"}
for _, k in ipairs(inRow) do
	check(row[k] ~= nil, k .. ": a tile in the hall's portal room")
	eq(row[k][2], row.descent[2], k .. ": in the row of the other portals")
	for _, other in ipairs(inRow) do
		check(other == k or row[k][1] ~= row[other][1], k .. " apart from " .. other)
	end
	check(k == "descent" or k == "raid" or cfg.hall[k], k .. ": placed in the hall by cityportals.lua")
end
for _, id in ipairs({1, 2}) do
	local t = cfg.towns[id]
	local m, h, g = t.memorial, t.hideout, t.guildhall
	check(m and not (m[1] == h[1] and m[2] == h[2]) and not (m[1] == g[1] and m[2] == g[2]), id .. ": a memorial spot of its own")
	check(math.max(math.abs(m[1] - h[1]), math.abs(m[2] - h[2])) <= 2, id .. ": the memorial spot by the other two")
end

-- ---------------------------------------------------------------- the pure rules
local T = {x = 32649, y = 31925, z = 11} -- Anvildeep, town 3
local list = C.candidates(cfg, "hideout", 3, T, nil, {{9, 9}})
eq(list[1].why, "town", "the fixed spot first")
eq(list[1].x, T.x + cfg.towns[3].hideout[1], "fixed spot x")
eq(list[1].y, T.y + cfg.towns[3].hideout[2], "fixed spot y")
eq(list[2].x, T.x + 9, "then the caller's offsets")
eq(list[3].why, "offset", "then the config's offsets")
local once = {}
for _, q in ipairs(list) do
	check(not once[C.key(q)], "every candidate once " .. C.key(q))
	once[C.key(q)] = true
end
check(#list >= #cfg.offsets, "every offset a candidate")
list = C.candidates(cfg, "hideout", 3, {x = 1000, y = 1000, z = 7}, nil, nil)
eq(list[1].why, "offset", "another map (the temple moved): no fixed spot")
list = C.candidates(cfg, "hideout", 2, {x = 32369, y = 32241, z = 7}, {x = 14591, y = 14843, z = 7}, nil)
eq(list[1].why, "hall", "Cinderhold: the hall first")
eq(list[2].why, "town", "then next to the temple")
list = C.candidates(cfg, "services", 2, {x = 32369, y = 32241, z = 7}, {x = 1, y = 1, z = 7}, {{0, 2}})
eq(list[1].why, "offset", "the hall entry never stands in the hall")
eq(list[1].y, 32243, "the hall entry's own offset first")
local dup = C.candidates(cfg, "hideout", 99, {x = 100, y = 100, z = 7}, nil, {cfg.offsets[1]})
eq(#dup, #cfg.offsets, "a repeated offset once")
eq(#C.candidates(cfg, "hideout", 3, nil, nil, nil), 0, "no temple: nothing")

local free = {ground = true, loose = 0}
check(C.spotOk(free), "bare floor")
check(not C.spotOk(nil), "no tile")
check(not C.spotOk({ground = false}), "no ground")
for _, f in ipairs({"solid", "path", "house", "teleport", "floorchange"}) do
	check(not C.spotOk({ground = true, [f] = true}), "not on " .. f)
end
check(not C.spotOk({ground = true, loose = 1}), "not on a dropped item")

local a, b, c = {x = 1, y = 0, z = 7}, {x = 2, y = 0, z = 7}, {x = 3, y = 0, z = 7}
local state = {[1] = "taken", [2] = "free", [3] = "ours"}
local p, had = C.pick({a, b, c}, function(q) return state[q.x] end)
check(p == c and had, "a portal already standing anywhere is kept (never a second one)")
state[3] = "free"
p, had = C.pick({a, b, c}, function(q) return state[q.x] end)
check(p == b and not had, "else the first free tile")
eq(C.pick({a}, function() return "taken" end), nil, "nothing free")
eq(C.lookText(cfg, "hideout"), "Hideout Portal: " .. cfg.kinds.hideout.text, "look text")
eq(C.lookText(cfg, "hideout", function(s) return pt[s] end), pt["Hideout Portal"] .. ": " .. pt[cfg.kinds.hideout.text],
	"look text in pt-BR")
eq(C.lookText(cfg, "nope"), nil, "unknown kind")
eq(C.bandTitle("Sulphur Gallery", {215, 299}), "Sulphur Gallery, levels 215-299", "a hunting area's title")
eq(C.bandTitle("Pit", {50, 50}), "Pit, level 50", "one level")
eq(C.bandTitle("Pit", nil), "Pit", "no band")
eq(C.bandTitle(nil, {1, 2}), nil, "no name")
eq(C.lookText(cfg, "hunt", nil, "Pit, level 50"), "Hunting Area Portal (Pit, level 50): " .. cfg.kinds.hunt.text, "title in the look text")

-- ---------------------------------------------------------------- the engine side on a mocked map
local tiles, created, effects = {}, {}, {}
local function key(x, y, z) return x .. "," .. y .. "," .. z end
Position = function(x, y, z)
	if type(x) == "table" then x, y, z = x.x, x.y, x.z end
	local q = {x = x, y = y, z = z}
	function q:sendMagicEffect(e) effects[#effects + 1] = {x = self.x, y = self.y, e = e} end
	return q
end
local function mkItem(id, pos)
	local it = {id = id, aid = 0, pos = pos}
	function it:getId() return self.id end
	function it:getActionId() return self.aid end
	function it:setActionId(v) self.aid = v end
	function it:isItem() return true end
	function it:remove()
		local t = self.pos and tiles[key(self.pos.x, self.pos.y, self.pos.z)]
		for i, x in ipairs(t and t.items or {}) do
			if x == self then table.remove(t.items, i) return true end
		end
	end
	function it:getType() local me = self; return {isMovable = function() return me.movable == true end,
		isDoor = function() return false end} end
	return it
end
local function mkTile(x, y, z)
	local t = {pos = Position(x, y, z), items = {}, ground = mkItem(406, nil)}
	function t:getGround() return self.ground end
	function t:getItems() return self.items end
	function t:getItemById(id)
		for _, it in ipairs(self.items) do if it.id == id then return it end end
	end
	function t:hasProperty(p) return self.solid == true and p == CONST_PROP_BLOCKSOLID end
	function t:hasFlag() return false end
	tiles[key(x, y, z)] = t
	return t
end
Tile = function(p) return tiles[key(p.x, p.y, p.z)] end
Game = {createItem = function(id, n, pos)
	local t = Tile(pos)
	if not t then return nil end
	local it = mkItem(id, Position(pos.x, pos.y, pos.z))
	t.items[#t.items + 1] = it
	created[#created + 1] = it
	return it
end}
CONST_PROP_BLOCKSOLID, CONST_ME_MAGIC_BLUE, CONST_ME_MAGIC_GREEN, CONST_ME_MAGIC_RED, CONST_ME_TELEPORT = 1, 21, 22, 23, 11
local function area(cx, cy, cz, r)
	for dx = -r, r do
		for dy = -r, r do
			mkTile(cx + dx, cy + dy, cz)
		end
	end
end
local function mkTown(id, x, y, z)
	return {getId = function() return id end, getTemplePosition = function() return Position(x, y, z) end}
end
-- Anvildeep as on the reference map (its fixed spots), a town of another map (offsets), Cinderhold with its hall
local an = cfg.towns[3].temple
area(an[1], an[2], an[3], 8)
area(500, 500, 7, 8)
local ci = cfg.towns[2].temple
area(ci[1], ci[2], ci[3], 8)
dofile("data/scripts/chaos/npc_booths_core.lua")
local hall2 = ChaosNpcBoothsCore.hallOf(booths, 2)
local function hallTile(dx, dy) return mkTile(hall2.at.x + dx, hall2.at.y + dy, hall2.at.z) end
local towns = {mkTown(3, an[1], an[2], an[3]), mkTown(50, 500, 500, 7), mkTown(2, ci[1], ci[2], ci[3])}
Game.getTowns = function() return towns end

dofile("data/scripts/chaos/cityportals.lua")
local X = ChaosCityPortals
-- Cinderhold's hall is not on the map yet: its portals stand next to the temple
local made, pos = X.place({kind = "hideout", aid = 47610, offsets = {{2, -3}}})
eq(made, 3, "one Hideout Portal per town")
local by = {}
for _, q in ipairs(pos) do by[q.town] = q end
eq(by[3].why, "town", "Anvildeep: its fixed spot")
eq(by[3].x, an[1] + cfg.towns[3].hideout[1], "Anvildeep spot x")
eq(by[50].why, "offset", "another map: the caller's offsets")
eq(by[50].x, 502, "the caller's first offset")
eq(by[2].why, "town", "Cinderhold without its hall: next to the temple")
eq(Tile(Position(by[3].x, by[3].y, by[3].z)):getItemById(1387).aid, 47610, "the portal carries the action id")
eq(X.place({kind = "hideout", aid = 47610, offsets = {{2, -3}}}), 0, "placed once")
eq(X.kindOf(47610), "hideout", "the action id names the kind")
-- the fixed spot taken by something dropped: the next candidate
local g = cfg.towns[3].guildhall
local gTile = Tile(Position(an[1] + g[1], an[2] + g[2], an[3]))
local junk = mkItem(2148, nil)
junk.movable = true
gTile.items[#gTile.items + 1] = junk
made, pos = X.place({kind = "guildhall", aid = 47602, towns = {3}, offsets = {{3, -2}}})
eq(made, 1, "only the towns asked for")
eq(pos[1].x, an[1] + 3, "a dropped item on the fixed spot: the offset")
-- a border or other fixed floor dressing does not count
local border = mkItem(4526, nil)
local hTile = Tile(Position(an[1] + 4, an[2] + 4, an[3]))
hTile.items[#hTile.items + 1] = border
check(C.spotOk(X.facts(Position(an[1] + 4, an[2] + 4, an[3]))), "a border does not block a portal")
-- the hall on the map: Cinderhold's next portals go to its portal room
for dx = 0, hall2.size[1] - 1 do
	for dy = 0, hall2.size[2] - 1 do
		hallTile(dx, dy)
	end
end
local hp = X.hallPos("guildhall", 2)
check(hp and hp.x == hall2.at.x + booths.portals.guildhall[1] and hp.y == hall2.at.y + booths.portals.guildhall[2],
	"the hall's guild hall tile")
eq(X.hallPos("services", 2), nil, "the hall entry is not in the hall")
local mp = X.hallPos("memorial", 2)
check(mp and mp.x == hall2.at.x + booths.portals.memorial[1], "the hall's memorial tile")
eq(X.hallPos("guildhall", 3), nil, "no hall in Anvildeep")
made, pos = X.place({kind = "guildhall", aid = 47602, towns = {2}})
eq(pos[1].why, "hall", "Cinderhold with its hall: the portal room")

-- the effect and the look text
local globals, looks = {}, {}
GlobalEvent = function(name)
	local o = {name = name}
	function o:interval(ms) self.ms = ms end
	function o:register() globals[self.name] = self end
	return o
end
local lookFn
EventCallback = setmetatable({register = function(self, i) looks[#looks + 1] = lookFn end},
	{__newindex = function(_, k, v) if k == "onLook" then lookFn = v end end})
Chaos = nil
dofile("data/scripts/chaos/chaos_constants.lua")
ChaosI18n = nil
dofile("data/scripts/chaos/i18n_core.lua")
local langs = {}
Chaos.lang = function(player) return langs[player] or "en" end
dofile("data/scripts/chaos/cityportals_fx.lua")
local pulse = globals.ChaosCityPortalsPulse
check(pulse ~= nil and pulse.ms == cfg.pulseMs, "the pulse every pulseMs")
effects = {}
pulse.onThink(cfg.pulseMs)
local count = 0
for _ in pairs(X.placed) do count = count + 1 end
eq(#effects, count, "every portal shows its effect")
local seen = {}
for _, e in ipairs(effects) do seen[e.e] = true end
check(seen[CONST_ME_MAGIC_BLUE] and seen[CONST_ME_MAGIC_GREEN], "hideout blue, guild hall green")
-- a portal removed by hand leaves the registry
local first = created[1]
for i, it in ipairs(Tile(first.pos).items) do if it == first then table.remove(Tile(first.pos).items, i) end end
pulse.onThink(cfg.pulseMs)
eq(X.placed[C.key(first.pos)], nil, "a portal that is gone leaves the registry")

local onLook = looks[#looks]
check(type(onLook) == "function", "a look callback")
local en, br = {}, {}
langs[br] = "pt-BR"
local portal = created[2]
local d = onLook(en, portal, portal.pos, 1, "You see a magic forcefield.")
eq(d, "You see a magic forcefield.\nHideout Portal: " .. cfg.kinds.hideout.text, "look text (en)")
d = onLook(br, portal, portal.pos, 1, "Você vê um magic forcefield.")
check(d:find(pt["Hideout Portal"], 1, true) ~= nil, "look text (pt-BR)")
-- a Chronicle Gate: one spot per area (spot), its name in the look text (title), removed when the area closes
made, pos = X.place({kind = "chronicle", spot = "chronicle_ossuary_stair", aid = 47921, towns = {2},
	title = "The Ossuary Stair"})
eq(pos[1].why, "hall", "a Chronicle Gate in the hall's portal room")
eq(pos[1].x, hall2.at.x + booths.portals.chronicle_ossuary_stair[1], "its own tile there")
local gate = Tile(Position(pos[1].x, pos[1].y, pos[1].z)):getItemById(1387)
d = onLook(en, gate, nil, 1, "x")
check(d:find("Chronicle Gate (The Ossuary Stair): ", 1, true) ~= nil, "the area's name in the look text")
eq(X.remove(47921), 1, "removed when the area closes")
eq(Tile(Position(pos[1].x, pos[1].y, pos[1].z)):getItemById(1387), nil, "the gate is gone")
local left = 0
for _, p in pairs(X.placed) do if p.aid == 47921 then left = left + 1 end end
eq(left, 0, "and out of the registry")
local plain = mkItem(1387, nil)
plain.aid = 47999
eq(onLook(en, plain, nil, 1, "x"), "x", "another forcefield: untouched")

-- the users load the helper and name their kind (source check: one shared helper for every portal near a temple)
local function src(f)
	local h = io.open("data/scripts/chaos/" .. f, "r")
	local s = h:read("*a")
	h:close()
	return s
end
for f, kind in pairs({["hideout.lua"] = "hideout", ["guild_hall.lua"] = "guildhall", ["npc_booths.lua"] = "services",
		["siege.lua"] = "siege", ["memorial.lua"] = "memorial", ["worldboss.lua"] = "worldboss"}) do
	local s = src(f)
	check(s:find('dofile("data/scripts/chaos/cityportals.lua")', 1, true) ~= nil, f .. " loads the helper")
	check(s:find('ChaosCityPortals.place({kind = "' .. kind .. '"', 1, true) ~= nil
		or s:find('CP.place({kind = "' .. kind .. '"', 1, true) ~= nil, f .. " places through the helper (" .. kind .. ")")
end

print(string.format("cityportals_test: %d checks, %d failures", checks, failures))
if failures > 0 then
	os.exit(1)
end
