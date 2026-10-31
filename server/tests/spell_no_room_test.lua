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

print(string.format("spell_no_room_test: %d checks, %d failures", n, fails))
if fails > 0 then os.exit(1) end
