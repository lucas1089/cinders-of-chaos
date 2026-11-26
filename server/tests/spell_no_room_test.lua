-- Run from the server/ folder: luajit tests/spell_no_room_test.lua (mock engine API; CI runs it with luajit and lua5.3)
-- Live check of O85: Wild Bond cast in the temple said "There is not enough room." ChaosSpell.freeAround never picks a
-- protection zone tile, so every summon and leap failed there with that line. ChaosSpell.noRoom names the protection
-- zone instead; this test runs it on a mocked caster and checks that no Chaos spell refuses with the bare room message.
local fails, n = 0, 0
local function ok(c, m) n = n + 1 if not c then fails = fails + 1; print("FAIL " .. m) end end
local function read(path) local f = assert(io.open(path, "r")); local t = f:read("*a"); f:close(); return t end

TILESTATE_PROTECTIONZONE, RETURNVALUE_ACTIONNOTPERMITTEDINPROTECTIONZONE, RETURNVALUE_NOTENOUGHROOM = 1, 2, 3
local pz
function Tile() return {hasFlag = function(_, f) return f == TILESTATE_PROTECTIONZONE and pz end} end
local sent
ChaosSpell = {cancel = function(_, msg) sent = msg return false end}
local src = read("data/spells/chaos/_common.lua"):match("function ChaosSpell%.noRoom%(creature%).-\nend\n")
ok(src ~= nil, "ChaosSpell.noRoom is in _common.lua")
assert((loadstring or load)(src))()

local caster = {getPosition = function() return {x = 1, y = 1, z = 7} end}
pz = true
ok(ChaosSpell.noRoom(caster) == false, "noRoom: the cast fails")
ok(sent == RETURNVALUE_ACTIONNOTPERMITTEDINPROTECTIONZONE, "noRoom: a protection zone is named")
pz = false
ChaosSpell.noRoom(caster)
ok(sent == RETURNVALUE_NOTENOUGHROOM, "noRoom: elsewhere, not enough room")

local okLs, ls = pcall(io.popen, "find data/spells/chaos -name '*.lua'")
local files = 0
if okLs and ls then
	for path in ls:lines() do
		files = files + 1
		local text = read(path)
		ok(not text:find("cancel%([%w_]+, RETURNVALUE_NOTENOUGHROOM%)") or path:find("_common%.lua$"),
			path .. ": refuses through ChaosSpell.noRoom")
	end
	ls:close()
end
ok(files > 50, "spell scripts found")

-- V30 (seen in a client 2026-11-26): a Beastmaster boxed in by a pack got "There is not enough room." for Wild Bond.
-- ChaosSpell.freeNear takes the next ring out when the 8 tiles round the caster are taken, only tiles in sight past ring 1.
do
	TILESTATE_BLOCKSOLID, TILESTATE_FLOORCHANGE, TILESTATE_TELEPORT, TILESTATE_MAGICFIELD = 11, 12, 13, 14
	local taken, wall, hidden = {}, {}, {}
	local function key(x, y) return x .. "," .. y end
	function Position(x, y, z)
		return {x = x, y = y, z = z, isSightClear = function(self, p) return not hidden[key(p.x, p.y)] end}
	end
	function Tile(p)
		return {
			getGround = function() return true end,
			hasFlag = function(_, f) return f == TILESTATE_BLOCKSOLID and wall[key(p.x, p.y)] or false end,
			getTopCreature = function() return taken[key(p.x, p.y)] end,
		}
	end
	local common = read("data/spells/chaos/_common.lua")
	for _, name in ipairs({"isFreeTile", "freeNear"}) do
		local fn = common:match("function ChaosSpell%." .. name .. "%(.-\nend\n")
		ok(fn ~= nil, "ChaosSpell." .. name .. " is in _common.lua")
		assert((loadstring or load)(fn))()
	end
	local c = Position(10, 10, 7)
	local first = ChaosSpell.freeNear(c, c, 3)
	ok(#first == 8 and math.max(math.abs(first[1].pos.x - 10), math.abs(first[1].pos.y - 10)) == 1, "freeNear: an open floor gives ring 1")
	for dx = -1, 1 do for dy = -1, 1 do if dx ~= 0 or dy ~= 0 then taken[key(10 + dx, 10 + dy)] = true end end end
	ok(#ChaosSpell.freeNear(c, c) == 0, "freeNear: reach 1 boxed in: no room (as freeAround)")
	local ring2 = ChaosSpell.freeNear(c, c, 3)
	ok(#ring2 == 16, "freeNear: boxed in, the 16 tiles of ring 2 (" .. #ring2 .. ")")
	ok(ring2[1].dist == 4, "freeNear: nearest first")
	hidden[key(12, 10)] = true
	wall[key(8, 10)] = true
	local seen = ChaosSpell.freeNear(c, c, 3)
	local has = {}
	for _, s in ipairs(seen) do has[key(s.pos.x, s.pos.y)] = true end
	ok(#seen == 14 and not has[key(12, 10)] and not has[key(8, 10)], "freeNear: no tile out of sight, no wall")
	for dx = -2, 2 do for dy = -2, 2 do taken[key(10 + dx, 10 + dy)] = true end end
	ok(#ChaosSpell.freeNear(c, c, 3) == 24, "freeNear: rings 1 and 2 taken, ring 3")
	local wild = read("data/spells/chaos/beastmaster/wild_bond.lua")
	ok(wild:find("ChaosSpell.freeNear(pos, pos, CALL_REACH)", 1, true) and wild:find("local CALL_REACH = 3", 1, true)
		and not wild:find("freeAround", 1, true), "Wild Bond calls its wolves up to 3 rings out")
end

print(string.format("spell_no_room_test: %d checks, %d failures", n, fails))
if fails > 0 then os.exit(1) end
