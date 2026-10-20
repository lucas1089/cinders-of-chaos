-- Run from the server/ folder: luajit tests/aoe_uniform_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- Owner decision 2026-10-20: the damage of an area skill is the same on every target of the area and the same as the
-- spell's single-target hit: no falloff per target, per jump or by distance, no area discount below 1, and an area
-- line spell is not weaker than the filler of its own class. Checks the area spell scripts (the pure parts are in the
-- scripts' source: the engine is not needed) and the rotation model that mirrors them (rotation_model.csv).
local failures, checks = 0, 0
local function ok(v, m)
	checks = checks + 1
	if not v then
		failures = failures + 1
		print("FAIL: " .. tostring(m))
	end
end
local function readFile(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local s = f:read("*a")
	f:close()
	return s
end

local DIR = "data/spells/chaos/"
-- the area spell scripts that scale their own hit (the ones whose scale is a plain factor in the script)
local AREA = {
	"knight/whirlwind.lua", "knight/leaping_strike.lua", "knight/ground_slam.lua", "knight/titans_wrath.lua", "berserker/skyfall_cleave.lua",
	"druid/thorn_cage.lua", "druid/venom_swarm.lua", "druid/ancient_tempest.lua", "sorcerer/chain_lightning.lua",
	"sorcerer/frost_nova.lua", "sorcerer/glacial_tomb.lua", "sorcerer/cataclysm.lua", "sorcerer/meteor_strike.lua",
	"illusionist/umbral_eruption.lua", "illusionist/reality_rift.lua", "paladin/piercing_volley.lua",
	"paladin/consecration.lua", "inquisitor/purging_nova.lua",
}

for _, rel in ipairs(AREA) do
	local src = readFile(DIR .. rel)
	ok(src ~= nil, rel .. " readable")
	if src then
		local n = 0
		for line in src:gmatch("[^\n]+") do
			local code = line:gsub("%-%-.*$", "")
			-- "local min = (...) * 0.7" / "local max = ... * 0.85"
			local f = code:match("^%s*local%s+m[ai][nx]%s*=.*%)%s*%*%s*([%d%.]+)%s*$")
			if f then
				n = n + 1
				ok(tonumber(f) >= 1, rel .. ": area hit scaled by " .. f .. " (< 1: a discount)")
			end
			-- ChaosSpell.mlValues(player, a, b, c, d, scale)
			local s = code:match("mlValues%(%s*[%w_:%.%(%)]+%s*,%s*[%d%.]+%s*,%s*[%d%.]+%s*,%s*[%d%.]+%s*,%s*[%d%.]+%s*,%s*([%d%.]+)%s*%)")
			if s then
				n = n + 1
				ok(tonumber(s) >= 1, rel .. ": mlValues scale " .. s .. " (< 1: a discount)")
			end
			-- a per jump / per target falloff constant
			local fo = code:match("^%s*local%s+FALLOFF%s*=%s*([%d%.]+)")
			if fo then
				ok(tonumber(fo) == 1, rel .. ": FALLOFF " .. fo .. " (the jump hit must equal the first)")
			end
		end
	end
end

-- Forked Storm: no falloff constant may scale a later jump
do
	local src = readFile(DIR .. "sorcerer/chain_lightning.lua") or ""
	local fo = src:match("local FALLOFF%s*=%s*([%d%.]+)")
	ok(fo == nil or tonumber(fo) == 1, "Forked Storm: jump falloff is 1")
	ok(not src:find("70%% damage per jump"), "Forked Storm: header no longer promises a 70% jump")
end

-- an area line spell is not weaker than its class's single-target filler (Skewering Line vs Dawnpiercer, level 80)
do
	local function coefs(rel)
		local src = readFile(DIR .. rel) or ""
		local out = {}
		for _, which in ipairs({"min", "max"}) do
			local line = src:match("local " .. which .. " = ([^\n]+)") or ""
			out[#out + 1] = tonumber(line:match("power %* ([%d%.]+)")) or 0
			out[#out + 1] = tonumber(line:match("agicLevel%(?%)?%s*%* ([%d%.]+)")) or 0
			out[#out + 1] = tonumber(line:match("%+ (%d+)%s*$")) or 0
		end
		return out
	end
	local function hit(level, power, ml, c)
		return level / 5 + power * c[1] + ml * c[2] + c[3], level / 5 + power * c[4] + ml * c[5] + c[6]
	end
	local power, ml = 80 * 40, 32 -- level 80 stats of the C4 kind: skill 80 x attack 40, magic level 32
	local lmin, lmax = hit(80, power, ml, coefs("paladin/piercing_volley.lua"))
	local smin, smax = hit(80, power, ml, coefs("paladin/holy_smite.lua"))
	ok(lmin >= smin and lmax >= smax, string.format(
		"Skewering Line per target (%.0f-%.0f) >= Dawnpiercer (%.0f-%.0f) at level 80", lmin, lmax, smin, smax))
end

-- the rotation model mirrors the scripts: no discount in the formula, no falloff in the targets
do
	local csv = readFile("data/spells/rotation_model.csv") or ""
	local want = {"Reaping Gyre", "Earthbreaker", "Skyfall Cleave", "Colossus Fall", "Briar Prison", "Blightswarm",
		"Primordial Squall", "Vaulting Cleave"}
	for _, name in ipairs(want) do
		local row = csv:match("\n[^\n,]*," .. name .. ',"?([^\n]*)')
		ok(row ~= nil, name .. " in rotation_model.csv")
		if row then
			ok(not row:match("%)%*0%.[0-9]+"), name .. ": model formula has a discount factor (" .. row:sub(1, 60) .. ")")
		end
	end
	local forked = csv:match("\n[^\n,]*,Forked Storm,\"[^\"]*\",([%d%.]+),")
	ok(tonumber(forked) == 4, "Forked Storm hits 1 + 3 jumps at full damage in the model (t5 4, got " .. tostring(forked) .. ")")
end

print(string.format("aoe_uniform_test: %d checks, %d failures", checks, failures))
if failures > 0 then
	os.exit(1)
end
print("aoe_uniform_test: OK")
