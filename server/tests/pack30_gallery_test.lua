-- Run from the server/ folder: luajit tests/pack30_gallery_test.lua (and lua5.3; CI runs both). Mock of the engine API.
-- The pair 30 gallery (admin/actions_pack30_gallery.lua + pack30_gallery_core.lua): parsing, the layout of items and
-- whole groups, grounds, looks, schemes, effects, missiles, the per-admin store with its 30 minute expiry, and the
-- engine file against a mocked world (admin only, 150 object cap, grounds refuse protection zone and house tiles and
-- are restored on clear, no lib = a clear message).
local checks, failures = 0, 0
local function check(c, m)
	checks = checks + 1
	if not c then failures = failures + 1; print("FAIL: " .. tostring(m)) end
end
local function eq(a, b, m) check(a == b, tostring(m) .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")") end

dofile("data/scripts/chaos/pack30_gallery_core.lua")
local G = ChaosPack30GalleryCore

-- ---------------------------------------------------------------- parse
local c = G.parse("items", "bldg")
eq(c.cmd, "items", "items bldg"); eq(c.from, 36059, "bldg from"); eq(c.to, 36458, "bldg to"); eq(c.block, "bldg", "block name")
c = G.parse("items decor-1")
eq(c.from, 35159, "one-string form (talkaction)")
c = G.parse("items", "35200-35100")
eq(c.from, 35100, "swapped range put right"); eq(c.to, 35200, "swapped range")
c = G.parse("items", "35100")
eq(c.from, 35100, "single id"); eq(c.to, 35100, "single id to")
check(not G.parse("items", ""), "items needs an argument")
check(not G.parse("items", "nonsense"), "unknown block")
check(not G.parse("looks", ""), "looks needs a range")
check(not G.parse("looks", "a-b"), "looks needs numbers")
eq(G.parse("looks", "2237-2311").to, 2311, "looks range")
eq(G.parse("fx", "830-854").cmd, "fx", "fx")
eq(G.parse("schemes", "2240").look, 2240, "schemes look")
check(not G.parse("schemes", "x"), "schemes needs a number")
c = G.parse("wear", "2240 3")
eq(c.look, 2240, "wear look"); eq(c.scheme, 3, "wear scheme")
c = G.parse("wear 2240")
eq(c.look, 2240, "wear look (one string)"); eq(c.scheme, nil, "no scheme")
for _, w in ipairs({"groups", "grounds", "anim", "missiles", "clear"}) do eq(G.parse(w).cmd, w, w) end
check(not G.parse("", ""), "empty"); check(not G.parse("dance", ""), "unknown command")
eq(G.parse("  CLEAR  ").cmd, "clear", "case and spaces")

-- ---------------------------------------------------------------- a mock lib in the shape of the generated file
local lib = {
	items = {
		rock = {id = 38000, w = 1, h = 1, block = true, name = "rock", kind = "decor"},
		tree = {id = 38001, w = 2, h = 3, name = "tree", kind = "decor"},
		wide = {id = 38002, w = 4, h = 1, name = "wide", kind = "decor"},
		flame = {id = 39500, w = 1, h = 1, animated = true, name = "flame", kind = "decor"},
		floor_a = {id = 37860, kind = "ground", name = "floor a"}, floor_b = {id = 37861, kind = "ground", name = "floor b"},
		bare = 38300, -- a plain number is an id of a 1x1
		keep_r0c0 = {id = 39100, w = 4, h = 4, name = "keep", group = "keep"}, keep_r0c1 = {id = 39101, w = 3, h = 4, name = "keep", group = "keep"},
		keep_r1c0 = {id = 39102, w = 4, h = 2, name = "keep", group = "keep"}, keep_r1c1 = {id = 39103, w = 3, h = 2, name = "keep", group = "keep"},
	},
	groups = {
		keep = {gw = 7, gh = 6, pieces = {{key = "keep_r1c1", r = 1, c = 1}, {key = "keep_r0c0", r = 0, c = 0}, {key = "keep_r0c1", r = 0, c = 1},
			{key = "keep_r1c0", r = 1, c = 0}}},
	},
	schemes = {[2240] = {{name = "ash", head = 1, body = 2, legs = 3, feet = 4}, {name = "ember", head = 5, body = 6, legs = 7, feet = 8}}},
}
local entries = G.entries(lib)
eq(#entries, 11, "eleven entries")
eq(entries[1].id, 37860, "sorted by id")
eq(G.entries(nil)[1], nil, "nil lib is empty")

-- selection
eq(#G.selectRange(entries, 34859, 34861), 2, "client range (server id - 3000)") -- 37860, 37861
eq(#G.selectRange(entries, 38000, 38001), 2, "both bounds >= 37443: server ids")
eq(#G.selectRange(entries, 35000, 35001), 2, "client ids 35000-35001")
eq(#G.selectRange(entries, 37443, 38001), 4, "server ids when both bounds are >= 37443 (37860 61 38000 38001)")
eq(#G.selectGrounds(entries), 2, "grounds by kind")
eq(#G.selectAnim(entries), 1, "anim by flag")

-- group unit: the piece grid sizes from the pieces (columns 4+3 wide, rows 4+2 tall)
local u = G.groupUnit("keep", lib.groups.keep, lib)
eq(u.w, 7, "group width"); eq(u.h, 6, "group height"); eq(#u.parts, 4, "four parts")
local by = {}
for _, p in ipairs(u.parts) do by[p.key] = p end
eq(by.keep_r0c0.ox, 3, "r0c0 south-east tile x"); eq(by.keep_r0c0.oy, 3, "r0c0 y")
eq(by.keep_r0c1.ox, 6, "r0c1 x"); eq(by.keep_r0c1.oy, 3, "r0c1 y")
eq(by.keep_r1c0.ox, 3, "r1c0 x"); eq(by.keep_r1c0.oy, 5, "r1c0 y")
eq(by.keep_r1c1.ox, 6, "r1c1 x"); eq(by.keep_r1c1.oy, 5, "r1c1 y")
eq(u.parts[1].key, "keep_r0c0", "parts in grid order")

-- units: a selected piece pulls in the whole group, once
local sel = {}
for _, e in ipairs(entries) do if e.key:match("^keep_") or e.key == "rock" then sel[#sel + 1] = e end end
local units = G.units(lib, sel)
eq(#units, 2, "rock + one group unit")
local hasGroup = false
for _, x in ipairs(units) do if x.group then hasGroup = true; eq(#x.parts, 4, "whole group") end end
check(hasGroup, "group unit present")
eq(#G.units(lib, nil), 1, "groups command: every group of the lib")
eq(#G.units(nil, nil), 0, "no lib no units")

-- layout rows: cell = size + 1 gap, items drawn up-left from their tile
local origin = {x = 100, y = 200, z = 7}
local lay = G.layoutUnits({
	{key = "a", w = 1, h = 1, parts = {{key = "a", id = 1, ox = 0, oy = 0}}},
	{key = "b", w = 2, h = 3, parts = {{key = "b", id = 2, ox = 1, oy = 2}}},
}, origin)
eq(lay.placements[1].x, 102, "first column is 2 east of the admin"); eq(lay.placements[1].y, 200, "row 0")
eq(lay.placements[2].x, 102 + 2 + 1, "second cell: 1 + gap 1 + ox 1"); eq(lay.placements[2].y, 202, "tile of the south-east corner")
eq(lay.units, 2, "two units"); eq(lay.rows, 1, "one row")
-- wrap: wide units overflow the row
local wideUnits = {}
for i = 1, 4 do wideUnits[i] = {key = "w" .. i, w = 4, h = 2, parts = {{key = "w" .. i, id = i, ox = 3, oy = 1}}} end
lay = G.layoutUnits(wideUnits, origin, {rowTiles = 10})
eq(lay.rows, 2, "wraps to a second row")
eq(lay.placements[3].y, 200 + 2 + 1 + 1, "second row starts after the tallest unit + gap (+ oy)")
eq(lay.placements[3].x, 102 + 3, "second row back at the first column")
-- the 150 object cap
local many = {}
for i = 1, 400 do many[i] = {key = "m" .. i, w = 1, h = 1, parts = {{key = "m" .. i, id = i, ox = 0, oy = 0}}} end
lay = G.layoutUnits(many, origin)
eq(#lay.placements, 150, "at most 150 objects per call"); eq(lay.skippedUnits, 250, "the rest is reported")
-- a group is never split by the cap
local g = G.groupUnit("keep", lib.groups.keep, lib)
local near = {}
for i = 1, 148 do near[i] = many[i] end
near[149] = g
lay = G.layoutUnits(near, origin)
eq(#lay.placements, 148, "a 4 piece group does not fit into the last 2 slots, so it is cut whole"); eq(lay.skippedUnits, 1, "counted")
-- all positions distinct for the real shape
local seen, dup = {}, 0
lay = G.layoutUnits(G.units(lib, G.selectRange(entries, 35000, 35001)), origin)
for _, p in ipairs(lay.placements) do local k = p.x .. "," .. p.y; if seen[k] then dup = dup + 1 end; seen[k] = true end
eq(dup, 0, "no two objects on one tile")

-- grounds
local gl = G.layoutGrounds(G.selectGrounds(entries), origin)
eq(#gl.placements, 2, "two ground tiles"); eq(gl.placements[1].y, 202, "two tiles south of the admin"); eq(gl.placements[2].x, 103, "contiguous")
local gs = {}
for i = 1, 200 do gs[i] = {key = "g" .. i, id = i} end
gl = G.layoutGrounds(gs, origin)
eq(#gl.placements, 150, "ground cap"); eq(gl.skipped, 50, "ground rest")
eq(gl.placements[17].y, 204, "17th ground starts the next row, one blank row between"); eq(gl.placements[17].x, 102, "first column")

-- looks, schemes, wear
local ll = G.layoutLooks(G.range(2237, 2260), origin)
eq(#ll.placements, 24, "24 looks"); eq(ll.placements[8].x, 102 + 7 * 3, "8 per row"); eq(ll.placements[9].y, 203, "ninth in the second row")
eq(ll.placements[9].x, 102, "second row at the first column")
eq(#G.range(1, 1000), 150, "range cap")
local sl = G.layoutSchemes(lib, 2240, origin)
eq(#sl.placements, 2, "the lib's two schemes"); eq(sl.placements[2].head, 5, "tint of scheme 2"); check(sl.placements[2].label:find("ember"), "label")
sl = G.layoutSchemes(lib, 9999, origin)
eq(#sl.placements, #G.DEFAULT_SCHEMES, "default schemes without lib data")
sl = G.layoutSchemes(nil, 2240, origin)
eq(#sl.placements, #G.DEFAULT_SCHEMES, "no lib at all")
local o = G.wearOutfit(lib, 2240, 2)
eq(o.lookType, 2240, "wear look"); eq(o.lookLegs, 7, "wear scheme 2 legs")
eq(G.wearOutfit(lib, 2240).lookHead, 1, "default is the first scheme")
check(not G.wearOutfit(lib, 2240, 9), "unknown scheme")

-- fx and missiles
local known = G.knownFx({boom = {id = 830, dx = 1, dy = 1}, alias = {id = 830, dx = 0, dy = 0}, zap = {id = 831}, junk = 5})
eq(known[830].name, "alias", "the first name by sort order for an id"); eq(known[831].dx, 0, "defaults")
local fx = G.layoutFx(830, 854, origin, known)
eq(#fx, 25, "25 effects"); eq(fx[1].delay, 0, "first at once"); eq(fx[2].delay, 1200, "every 1.2 s"); eq(fx[25].delay, 24 * 1200, "last")
for _, e in ipairs(fx) do check(e.x >= 100 and e.x <= 108 and e.y >= 197 and e.y <= 206, "effect inside the screen east of the admin") end
eq(#G.layoutFx(1, 500, origin), 60, "fx cap")
local mi = G.missileIds({a = {id = 170}, b = {id = 187}, c = {id = 12}, d = "x"})
eq(table.concat(mi, ","), "12,170,186,187,188", "missile ids unique, sorted, with 186-188")
local ml = G.layoutMissiles(mi, origin)
eq(#ml, 5, "five missiles"); eq(ml[1].from.x, 101, "from beside the admin"); eq(ml[1].to.x, 106, "six tiles east"); eq(ml[3].delay, 2400, "timing")

-- store
local st = G.newStore()
eq(G.add(st, 7, {{kind = "item", id = 1}, {kind = "item", id = 2}}, 1000), 2, "two records")
eq(G.add(st, 7, {{kind = "monster", cid = 3}}, 5000), 3, "a second call adds")
eq(#G.expired(st, 5000 + G.TTL_MS - 1), 0, "not yet")
eq(G.expired(st, 5000 + G.TTL_MS)[1], 7, "after 30 minutes, counted from the last placement")
local taken = G.take(st, 7)
eq(#taken, 3, "all taken"); eq(taken[1].cid, 3, "newest first"); eq(#G.take(st, 7), 0, "empty after take")
eq(G.TTL_MS, 1800000, "30 minutes"); eq(G.MAX_OBJECTS, 150, "150 objects")

-- ---------------------------------------------------------------- the engine file against a mocked world
local items, tiles, monsters, nextId, events, stopped, effects, shots, worn = {}, {}, {}, 1, {}, {}, {}, {}, {}
local function key(p) return p.x .. "," .. p.y .. "," .. p.z end
local function tileAt(pos)
	local t = tiles[key(pos)]
	if not t then return nil end
	return t
end
local function mkTile(x, y, opts)
	opts = opts or {}
	local t = {x = x, y = y, z = 7, ground = opts.ground or 100, items = {}, pz = opts.pz, house = opts.house}
	function t:hasFlag() return self.pz end
	function t:getHouse() return self.house end
	function t:getGround() return self.ground and {getId = function() return t.ground end, remove = function() t.ground = nil end} or nil end
	function t:getItemById(id)
		for i, it in ipairs(self.items) do if it.id == id then return it end end
	end
	tiles[x .. "," .. y .. ",7"] = t
	return t
end
TILESTATE_PROTECTIONZONE = 1; MESSAGE_INFO_DESCR = 1; CONDITION_OUTFIT = 9
function Position(x, y, z) return {x = x, y = y, z = z, sendMagicEffect = function(self, id) effects[#effects + 1] = {id, self.x, self.y} end,
	sendDistanceEffect = function(self, to, id) shots[#shots + 1] = {id, self.x, to.x} end} end
function Tile(pos) return tileAt(pos) end
Game = {
	createItem = function(id, n, pos)
		local t = tileAt(pos)
		if not t then return nil end
		if (id >= 37860 and id <= 37899) or id < 1000 then t.ground = id; return {id = id} end -- a ground replaces the ground
		local it = {id = id}
		function it:remove() for i, x in ipairs(t.items) do if x == it then table.remove(t.items, i) break end end end
		t.items[#t.items + 1] = it
		return it
	end,
	createMonster = function(name, pos)
		if name ~= "Look Model" or not tileAt(pos) then return nil end
		local m = {cid = nextId, name = name}
		nextId = nextId + 1
		function m:getId() return self.cid end
		function m:setOutfit(o) self.outfit = o end
		function m:remove() monsters[self.cid] = nil end
		monsters[m.cid] = m
		return m
	end,
}
function Monster(cid) return monsters[cid] end
local online = {}
function Player(name) return online[name] end
function addEvent(fn, ms, ...) events[#events + 1] = {fn = fn, ms = ms, args = {...}}; return #events end
function stopEvent(id) stopped[#stopped + 1] = id end
function Condition(kind) local c = {kind = kind}; function c:setOutfit(o) self.outfit = o end; function c:setTicks(t) self.ticks = t end; return c end
os.mtime = function() return 5000 end
local talks = {}
function TalkAction(words) local t = {words = words}; function t:separator() end; function t:register() talks[words] = self end; return t end
ChaosAdmin = {isAdmin = function(p) return p.admin end}
ChaosAdminPending = {}

local libFile = {} -- what loadLib() gets: dofile is replaced for the two lib paths only
local realDofile = dofile
function dofile(path)
	if path == "data/lib/chaos_pack30_items.lua" then
		if not libFile.lib then error("cannot open") end
		return libFile.lib
	elseif path == "data/lib/chaos_pack30_fx_ids.lua" then
		ChaosVfx = {boom = {id = 830, dx = 0, dy = 0}}
		ChaosVfxMissile = {bolt = {id = 170}}
		return
	end
	return realDofile(path)
end
realDofile("data/scripts/chaos/admin/actions_pack30_gallery.lua")
local M = ChaosPack30Gallery
local def = ChaosAdminPending["tools.pack30_gallery"]
check(def and def.handler, "action tools.pack30_gallery registered")
eq(def.category, "tools", "tools category")
check(talks["/pack30gallery"], "talkaction /pack30gallery registered")
check(def.minGroup == nil, "the group is the panel's (ChaosAdminConfig.minGroup), not hard coded here")

local sent = {}
local admin = {admin = true, name = "Owner", pos = {x = 100, y = 200, z = 7}}
function admin:getGuid() return 1 end
function admin:getName() return self.name end
function admin:getPosition() return Position(self.pos.x, self.pos.y, self.pos.z) end
function admin:sendTextMessage(_, t) sent[#sent + 1] = t end
function admin:addCondition(cond) worn[#worn + 1] = cond end
online.Owner = admin
local plain = {admin = false, name = "Plain"}
function plain:getGuid() return 2 end
function plain:getName() return "Plain" end
function plain:sendTextMessage(_, t) sent[#sent + 1] = t end
function plain:getPosition() return Position(100, 200, 7) end

for x = 90, 140 do for y = 190, 230 do mkTile(x, y) end end

-- admin only
local ok, msg = def.handler(plain, {what = "clear"})
eq(ok, false, "a player is refused"); eq(msg, "Admins only.", "message")
talks["/pack30gallery"].onSay(plain, "/pack30gallery", "items bldg")
eq(#sent, 0, "the talkaction ignores a player (plain chat)")

-- no lib
ok, msg = def.handler(admin, {what = "items", arg = "bldg"})
eq(ok, false, "no lib"); check(msg:find("chaos_pack30_items.lua", 1, true), "tells which file is missing")
ok = def.handler(admin, {what = "looks", arg = "2237-2240"})
eq(ok, true, "looks need no lib")
eq(monsters[1].outfit.lookType, 2237, "setOutfit lookType"); eq(monsters[4].outfit.lookType, 2240, "four looks")
ok, msg = def.handler(admin, {what = "clear"})
eq(ok, true, "clear"); check(msg:find("4 look"), "four looks removed: " .. msg); eq(next(monsters), nil, "all monsters gone")

-- items with a lib, a group shows whole
libFile.lib = lib
local lines
ok, msg, lines = def.handler(admin, {what = "items", arg = "35000-35001"})
eq(ok, true, "items placed"); check(msg:find("2 object"), msg)
eq(tiles["102,200,7"].items[1].id, 38000, "rock at the first cell")
check(lines[1]:find("38000/rock/rock", 1, true), "id/key/name line: " .. tostring(lines[1]))
ok, msg, lines = def.handler(admin, {what = "groups"})
eq(ok, true, "groups placed"); eq(#lines, 4, "four pieces of the keep")
eq(tiles["105,203,7"].items[1].id, 39100, "south-east tile of the first piece")
ok, msg, lines = def.handler(admin, {what = "anim"})
eq(ok, true, "anim"); eq(#lines, 1, "one animated object")
-- items on a house tile are skipped
tiles["102,200,7"].house = {}
ok, msg = def.handler(admin, {what = "items", arg = "35000-35000"})
eq(ok, false, "everything skipped"); check(msg:find("skipped"), msg)
tiles["102,200,7"].house = nil
ok, msg = def.handler(admin, {what = "clear"})
check(msg:find("Cleared 7 item"), "clear removes what was placed: " .. msg)
local left = 0
for _, t in pairs(tiles) do left = left + #t.items end
eq(left, 0, "no item left on any tile")

-- grounds: PZ and house tiles are refused, the old ground comes back
tiles["103,202,7"].pz = true
tiles["104,202,7"].house = {}
ok, msg, lines = def.handler(admin, {what = "grounds"})
eq(ok, true, "the strip: x 102 is replaced, x 103 is a protection zone tile")
eq(tiles["102,202,7"].ground, 37860, "the first ground replaced the floor")
eq(tiles["103,202,7"].ground, 100, "PZ tile untouched")
check(msg:find("1 refused", 1, true), "refusal reported: " .. msg)
ok, msg = def.handler(admin, {what = "clear"})
eq(tiles["102,202,7"].ground, 100, "old ground id restored on clear")
check(msg:find("1 ground"), msg)

-- fx, missiles
ok, msg, lines = def.handler(admin, {what = "fx", arg = "830-832"})
eq(ok, true, "fx"); eq(#lines, 3, "three effects"); check(lines[1]:find("830/boom", 1, true), "named from ChaosVfx: " .. lines[1])
local before = #events
for i = #events - 2, #events do events[i].fn(unpack and unpack(events[i].args) or table.unpack(events[i].args)) end
eq(#effects, 3, "the scheduled calls send the magic effects")
eq(events[#events].ms, 2400, "1.2 s apart")
ok, msg, lines = def.handler(admin, {what = "missiles"})
eq(#lines, 4, "186 187 188 and the ChaosVfxMissile id 170")
local ev = events[#events]
ev.fn(unpack and unpack(ev.args) or table.unpack(ev.args))
eq(shots[1][1] ~= nil, true, "a distance effect was sent")
ok, msg = def.handler(admin, {what = "clear"})
check(msg:find("stopped 7"), "clear stops the scheduled effects: " .. msg)
eq(#stopped, 7, "stopEvent per scheduled effect")

-- wear
ok, msg = def.handler(admin, {what = "wear", arg = "2240 2"})
eq(ok, true, "wear"); eq(worn[1].outfit.lookLegs, 7, "scheme 2"); eq(worn[1].ticks, 600000, "10 minutes")
ok = def.handler(admin, {what = "wear", arg = "2240 5"})
eq(ok, false, "unknown scheme")

-- the 30 minute auto clear: the expiry event clears what is left
def.handler(admin, {what = "looks", arg = "2237-2238"})
eq(next(monsters) ~= nil, true, "two looks standing")
local last = events[#events]
eq(last.ms, G.TTL_MS + 1000, "expiry scheduled 30 minutes out")
os.mtime = function() return 5000 + G.TTL_MS + 10 end
last.fn()
eq(next(monsters), nil, "auto cleared"); check(sent[#sent]:find("30 minutes"), "the admin is told")

-- the talkaction for an admin
sent = {}
talks["/pack30gallery"].onSay(admin, "/pack30gallery", "looks 2237-2237")
check(#sent >= 1 and sent[1]:find("Looks 2237-2237", 1, true), "talkaction answers the admin: " .. tostring(sent[1]))
talks["/pack30gallery"].onSay(admin, "/pack30gallery", "clear")

dofile = realDofile
if failures > 0 then
	print(string.format("pack30_gallery_test: %d checks, %d FAILURES", checks, failures))
	os.exit(1)
end
print(string.format("pack30_gallery_test: %d checks, 0 failures", checks))
