-- Run from the server/ folder: luajit tests/necro_fx_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- The Necromancer line's spell effects: every pack / own-art effect name the line's spells send (NecroSpell.fx lists,
-- the Soul Rot tick, ChaosSpell.vfx / vfxOr / vshoot) is defined by chaos_vfx.lua or chaos_vfx_art.lua, each
-- NecroSpell.fx list ends in an older effect or a stock fallback, and NecroSpell.fx falls back in order.
local failures = 0
local function ok(c, msg)
	if not c then
		failures = failures + 1
		print("FAIL " .. msg)
	end
end

Position = function(x, y, z) return {x = x, y = y, z = z} end
ChaosVfx, ChaosVfxMissile = nil, nil
dofile("data/lib/chaos_vfx.lua")
dofile("data/lib/chaos_vfx_art.lua")

local function readFile(p)
	local f = io.open(p, "r")
	if not f then return nil end
	local s = f:read("*a")
	f:close()
	return s
end

local files = {
	"necromancer/bone_spear", "necromancer/raise_dead", "necromancer/withering_curse",
	"lich/soul_rot", "lich/life_siphon", "lich/corpse_explosion",
	"bonelord/bone_golem", "bonelord/banner_of_bones", "bonelord/bone_offering",
}
local used = 0
for _, f in ipairs(files) do
	local src = readFile("data/spells/chaos/" .. f .. ".lua")
	ok(src ~= nil, "spell script " .. f)
	src = src or ""
	for list, rest in src:gmatch("NecroSpell%.fx%([^{]-{([^}]*)}([^\n]*)") do
		local names = {}
		for n in list:gmatch('"([%w_]+)"') do
			names[#names + 1] = n
			ok(ChaosVfx[n] ~= nil, f .. ": effect " .. n .. " is defined")
			used = used + 1
		end
		ok(#names >= 2 or rest:find("CONST_ME_") ~= nil or f == "necromancer/bone_spear",
			f .. ": " .. list .. " has a fallback")
	end
	for n in src:gmatch('vfx = "([%w_]+)"') do
		ok(ChaosVfx[n] ~= nil, f .. ": tick effect " .. n .. " is defined")
		used = used + 1
	end
	for n in src:gmatch('ChaosSpell%.vfx%a*%([^,]+, "([%w_]+)"') do
		ok(ChaosVfx[n] ~= nil, f .. ": effect " .. n .. " is defined")
	end
	for n in src:gmatch('ChaosSpell%.vshoot%([^,]+,[^,]+, "([%w_]+)"') do
		ok(ChaosVfxMissile[n] ~= nil, f .. ": missile " .. n .. " is defined")
	end
end
ok(used >= 15, "the line's spells name their effects (" .. used .. ")")

-- the Bone Lord's and the shared bone art are distinct effects
for _, n in ipairs({"necro_spear_hit", "lich_soul_drain", "bonelord_golem_rise", "bonelord_banner", "bonelord_rally",
		"bonelord_offering", "bonelord_ward"}) do
	ok(ChaosVfx[n] and ChaosVfx[n].id >= 586, n .. " appended after the bone effects")
end

-- NecroSpell.fx: the first known effect wins; none known -> the chaos/stock fallback; nothing when there is none
local sent = {}
ChaosSpell = {
	vfx = function(pos, name) if ChaosVfx[name] then sent[#sent + 1] = name return true end return false end,
	fx = function(pos, name, fallback) sent[#sent + 1] = "fx:" .. tostring(name) .. ":" .. tostring(fallback) end,
}
local src = readFile("data/spells/chaos/_necro.lua") or ""
local body = src:match("(function S%.fx%(.-\nend)\n")
ok(body ~= nil, "_necro.lua defines S.fx")
local S = {}
local chunk = (loadstring or load)("local S = ...\n" .. (body or ""))
chunk(S)
local saved = ChaosVfx.bonelord_ward
ok(S.fx({}, {"bonelord_ward", "bone_aura"}, "bone_aura", 1) == "bonelord_ward" and sent[1] == "bonelord_ward",
	"the new effect first")
ChaosVfx.bonelord_ward = nil
sent = {}
ok(S.fx({}, {"bonelord_ward", "bone_aura"}, "bone_aura", 1) == "bone_aura", "the older effect without the new one")
local savedAura = ChaosVfx.bone_aura
ChaosVfx.bone_aura = nil
sent = {}
ok(S.fx({}, {"bonelord_ward", "bone_aura"}, "bone_aura", 7) == nil and sent[1] == "fx:bone_aura:7",
	"a server without the art sends the stock fallback")
sent = {}
S.fx({}, {"bonelord_ward"})
ok(#sent == 0, "no fallback: nothing sent")
ChaosVfx.bonelord_ward, ChaosVfx.bone_aura = saved, savedAura

if failures > 0 then
	error(failures .. " failure(s)")
end
print("necro_fx_test: all ok")
