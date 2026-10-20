-- Run from the server/ folder: luajit tests/impact_text_test.lua (and lua5.3; CI runs both)
-- Typed impact numbers (server/README.md "Typed impact numbers"): the engine patch (src-patches/0051), the client
-- base patch (client/base-patches/0100), the server constants (Chaos.impactType) and the client module
-- (game_damagescatter scatterlogic.lua) agree on the number types, the feature ids, the login capability bit and the
-- wire layout: the same three fields (u16 percent, u8 type, u32 creature id) in the same order, after the value /
-- colour pairs and before the text, for every damage, heal, mana and experience mode, on both sides.

local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

local function read(path)
	local f = assert(io.open(path, "rb"), "cannot open " .. path)
	local text = f:read("*a")
	f:close()
	return text
end

-- the one patch with this number in a folder (the name after the number may change)
local function patchText(dir, number)
	local names = {}
	local p = io.popen('ls "' .. dir .. '"')
	for name in p:lines() do
		if name:sub(1, #number + 1) == number .. "-" and name:sub(-6) == ".patch" then
			names[#names + 1] = name
		end
	end
	p:close()
	eq(#names, 1, "one patch " .. number .. " in " .. dir)
	return read(dir .. "/" .. names[1])
end

-- the added lines of a patch (without the leading +), as one text
local function added(patch)
	local out = {}
	for line in (patch .. "\n"):gmatch("([^\n]*)\n") do
		if line:sub(1, 1) == "+" and line:sub(1, 3) ~= "+++" then
			out[#out + 1] = line:sub(2)
		end
	end
	return table.concat(out, "\n")
end

-- the new side of a patch (added and context lines), as one text
local function newSide(patch)
	local out = {}
	for line in (patch .. "\n"):gmatch("([^\n]*)\n") do
		local c = line:sub(1, 1)
		if (c == "+" and line:sub(1, 3) ~= "+++") or c == " " then
			out[#out + 1] = line:sub(2)
		end
	end
	return table.concat(out, "\n")
end

local serverPatch = patchText("src-patches", "0051")
local clientPatch = patchText("../client/base-patches", "0100")
local server = added(serverPatch)
local client = added(clientPatch)
local clientNew = newSide(clientPatch)

-- ---------------------------------------------------------------- the number types
local engine = {}
for name, value in server:gmatch("CHAOS_IMPACT_([A-Z_]+) = (%d+)") do
	engine[name] = tonumber(value)
end
local constants = read("data/scripts/chaos/chaos_constants.lua")
local block = constants:match("Chaos%.impactType = (%b{})")
assert(block, "Chaos.impactType in chaos_constants.lua")
local lua = {}
for name, value in block:gmatch("(%a+) = (%d+)") do
	lua[name] = tonumber(value)
end
dofile("../client/overlay/modules/game_damagescatter/scatterlogic.lua")
local L = DamageScatterLogic
local pairsOf = {
	{"NORMAL", "normal"}, {"CRITICAL", "critical"}, {"CONDITION", "condition"},
	{"MANA_DRAIN", "manaDrain"}, {"MANA_GAIN", "manaGain"}, {"ENERGY_SHIELD", "energyShield"}
}
local n = 0
for name in pairs(engine) do n = n + 1 end
eq(n, #pairsOf, "every engine type is listed here")
for i, p in ipairs(pairsOf) do
	eq(engine[p[1]], i - 1, "engine " .. p[1])
	eq(lua[p[2]], i - 1, "Chaos.impactType." .. p[2])
	eq(L.TYPE[p[1]], i - 1, "client TYPE." .. p[1])
end

-- ---------------------------------------------------------------- feature ids and the capability bit
eq(server:match("GameChaosImpactText = (%d+)"), "155", "engine feature id")
eq(client:match("\n%s*GameChaosImpactText = (%d+),"), "155", "client const.h feature id")
eq(client:match("\nGameChaosImpactText = (%d+)"), "155", "client const.lua feature id")
eq(client:match("\n%s*GameChaosAttachedImpactText = (%d+),"), "156", "client const.h follow feature")
eq(client:match("\nGameChaosAttachedImpactText = (%d+)"), "156", "client const.lua follow feature")
eq(client:match("\n%s*LastGameFeature = (%d+)"), "157", "client const.h LastGameFeature past both")
eq(client:match("\nLastGameFeature = (%d+)"), "157", "client const.lua LastGameFeature past both")
eq(server:match("CHAOS_CAPABILITY_IMPACT_TEXT = 1 << (%d+)"), "7", "engine capability bit")
eq(client:match("CHAOS_CAPABILITY_IMPACT_TEXT = 1U << (%d+)"), "7", "client capability bit")
eq(client:find("\n%s*CHAOS_CAPABILITY_IMPACT_TEXT |") ~= nil, true, "the client sends the bit")
eq(client:find("disableFeature%(Otc::GameChaosImpactText%)") ~= nil, true, "the client clears 155 before a login")
eq(server:find("if %(chaosImpactTextAsked%) {%s*features%[GameChaosImpactText%] = true;") ~= nil, true,
	"the engine announces 155 only when asked")

-- ---------------------------------------------------------------- the wire layout
-- engine: one writer of the three fields, in this order, called in the three groups of modes (damage, heal,
-- experience) after their value / colour pairs
local writer = server:match("const auto addImpactFields = %[&%]%(%) {(.-)\n\t};")
assert(writer, "addImpactFields in the engine patch")
local order = {}
for kind in writer:gmatch("msg%.(add[%w<>_]*)%(message%.%a+%)") do
	order[#order + 1] = kind
end
eq(table.concat(order, " "), "add<uint16_t> addByte add<uint32_t>", "engine field order")
eq(writer:find("if %(!chaosImpactText%)") ~= nil, true, "engine writes them only to a client with 155")
local calls = 0
for _ in server:gmatch("addImpactFields%(%); // Chaos") do calls = calls + 1 end
eq(calls, 3, "engine: damage, heal and experience modes all carry the fields")

-- client: the reader in both groups of modes, in the same order, before the font and the text
local reads = 0
for body in client:gmatch("if %(g_game%.getFeature%(Otc::GameChaosImpactText%)%) {(.-)}") do
	reads = reads + 1
	local got = {}
	for kind in body:gmatch("msg%->(get%w+)%(%)") do got[#got + 1] = kind end
	eq(table.concat(got, " "), "getU16 getU8 getU32", "client field order " .. reads)
end
eq(reads, 2, "client: damage and value modes both read the fields")
-- in the parser (new side of the patch: the text line is context): after each reader, the next read of the
-- message is the custom font (a feature this server never announces) or the text, before the next case
local readers = 0
local at = 1
while true do
	local s, e = clientNew:find("if %(g_game%.getFeature%(Otc::GameChaosImpactText%)%) {.-\n%s*}", at)
	if not s then break end
	readers = readers + 1
	local nextRead = clientNew:match("msg%->(get%w+)%(%)", e)
	eq(nextRead, "getString", "reader " .. readers .. ": the font / text come right after the fields")
	local textAt = clientNew:find("text = msg%->getString%(%);", e)
	local caseAt = clientNew:find("\n%s*case Otc::", e)
	eq(textAt ~= nil and (caseAt == nil or textAt < caseAt), true, "reader " .. readers .. ": the text is read last")
	at = e
end
eq(readers, 2, "two readers in the parser")

-- every number the engine builds names its creature (heal, mana shield, damage, mana gain / loss, energy shield,
-- regeneration, experience gain / loss, a summon's experience)
local named = 0
for _ in server:gmatch("message%.creatureId = ") do named = named + 1 end
eq(named >= 11, true, "creature id set on every impact message (" .. named .. ")")
eq(server:find("damage%.firstOrigin = damage%.origin;") ~= nil, true, "the origin survives the onHealthChange re-entry")

print(string.format("impact_text_test: %d checks passed", checks))
