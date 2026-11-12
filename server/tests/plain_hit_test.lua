-- Run from the server/ folder: luajit tests/plain_hit_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- O523: the plain energy hit (12) and ice attack (44) of a single-target spell hit are the pack's lightning blast and ice
-- explosion (ChaosSpell.plainHit in data/spells/chaos/_common.lua, asked by ChaosSpell.damageTarget and the attack kit's single
-- hit). The block is cut out of the real file and run on a mock, so the test needs no engine.
local failures = 0
local function ok(c, msg)
	if not c then
		failures = failures + 1
		print("FAIL " .. msg)
	end
end
local function eq(a, b, msg)
	ok(a == b, msg .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")")
end
local function readFile(p)
	local f = io.open(p, "r")
	if not f then return nil end
	local s = f:read("*a")
	f:close()
	return s
end

local src = readFile("data/spells/chaos/_common.lua") or ""
local a = src:find("ChaosSpell.PLAIN_HIT = {}", 1, true)
local b1, b2 = src:find("function ChaosSpell.plainHit%(pos, effect%).-\nend\n")
ok(a ~= nil and b2 ~= nil, "the plainHit block is in _common.lua")
local block = src:sub(a, b2)

local function load_(env)
	local chunk = (loadstring or load)(block, "plainhit", "t", env)
	if not chunk then chunk = (loadstring or load)(block) ; if setfenv then setfenv(chunk, env) end end
	chunk()
	return env
end

local sent = {}
local function mockEnv(sends)
	local env = {CONST_ME_ENERGYHIT = 12, CONST_ME_ICEATTACK = 44, CONST_ME_NONE = 0}
	env.ChaosSpell = {vfx = function(pos, name) sent[#sent + 1] = name; return sends end}
	return load_(env)
end

local env = mockEnv(true)
local C = env.ChaosSpell
eq(C.PLAIN_HIT[12], "blast_lightning", "energy hit -> blast_lightning")
eq(C.PLAIN_HIT[44], "mfx_ice", "ice attack -> mfx_ice")
local n = 0
for _ in pairs(C.PLAIN_HIT) do n = n + 1 end
eq(n, 2, "only those two stock effects are swapped")
eq(C.plainHit({x = 1}, 12), 0, "energy: the stock hit is dropped when the pack blast was sent")
eq(sent[1], "blast_lightning", "energy: the blast was sent")
eq(C.plainHit({x = 1}, 44), 0, "ice: the stock hit is dropped")
eq(sent[2], "mfx_ice", "ice: the explosion was sent")
sent = {}
eq(C.plainHit({x = 1}, 7), 7, "another effect (fire area, 7) passes through")
eq(C.plainHit({x = 1}, nil), nil, "no effect passes through")
eq(#sent, 0, "nothing sent for them")

local env2 = mockEnv(false)
eq(env2.ChaosSpell.plainHit({x = 1}, 12), 12, "the stock hit stays when the pack effect cannot be sent (no id file, old pair)")

-- the wiring
ok(src:find("ChaosSpell.plainHit(target:getPosition(), effect)", 1, true) ~= nil, "damageTarget asks plainHit")
local kit = readFile("data/spells/chaos/_attackkit.lua") or ""
ok(kit:find('spec.shape == "single" and not spec.hitFx', 1, true) ~= nil, "the attack kit asks it for a single-target spell with no hit effect of its own")

-- the names exist and are tagged for the element check
dofile("data/lib/chaos_fx.lua")
dofile("data/lib/chaos_vfx.lua")
dofile("data/lib/chaos_pack29_vfx_ids.lua")
dofile("data/lib/chaos_pack30_fx_ids.lua")
ok(ChaosVfx.blast_lightning and ChaosVfx.blast_lightning.id == 798, "blast_lightning is effect 798")
ok(ChaosVfx.mfx_ice and ChaosVfx.mfx_ice.id == 836, "mfx_ice is effect 836")
local tags = {}
for line in io.lines("data/spells/spell_fx_elements.csv") do
	local id, name, el = line:match("^(%d+),([^,]+),(%a+)$")
	if id then tags[name] = el end
end
eq(tags.blast_lightning, "energy", "blast_lightning is tagged energy")
eq(tags.mfx_ice, "ice", "mfx_ice is tagged ice")
eq(tags.nova_radiant_blue, "ice", "nova_radiant_blue (Eclipse of Ruin) is tagged ice")

if failures > 0 then
	print("plain_hit_test: " .. failures .. " FAILED")
	os.exit(1)
end
print("plain_hit_test: ok")
