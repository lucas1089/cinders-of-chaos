-- Run from the server/ folder: luajit tests/spell_scaling_test.lua && lua5.3 tests/spell_scaling_test.lua (CI runs both)
-- O468: the magic level share of weapon spells (spell_scaling_config.lua, spell_scaling_core.lua). The guard that every
-- spell script reads its inputs is tests/spell_inputs_test.lua; this test holds the numbers: the factor, the reference
-- magic level against server/tools/rotation_sim.py ANCHORS 'ml_other', the helpers the spell scripts call.
local checks, fails = 0, 0
local function ok(c, m)
	checks = checks + 1
	if not c then
		fails = fails + 1
		print("FAIL " .. (m or ""))
	end
end
local function near(a, b, tol, m)
	ok(math.abs(a - b) <= tol, (m or "") .. ": " .. tostring(a) .. " vs " .. tostring(b))
end

dofile("data/scripts/chaos/spell_scaling_config.lua")
dofile("data/scripts/chaos/spell_scaling_core.lua")
local S, cfg = ChaosSpellScaling, ChaosSpellScalingConfig.mlShare

-- the numbers of the rule (the owner's answer "go ahead like that", 2026-11-10)
ok(cfg.per == 300, "one magic level is 1 / 300 of a weapon spell")
ok(cfg.normalise == true, "normalised: a typical character is unchanged")

-- the reference magic level is the typical weapon class one of the balance models: read from rotation_sim.py, never copied
do
	local f = assert(io.open("tools/rotation_sim.py", "r"))
	local py = f:read("*a")
	f:close()
	local row = py:match("'ml_other':%s*(%b[])")
	ok(row ~= nil, "rotation_sim.py ANCHORS has 'ml_other'")
	local pts = {}
	for a, b in (row or ""):gmatch("%((%d+),%s*(%d+)%)") do
		pts[#pts + 1] = {tonumber(a), tonumber(b)}
	end
	ok(#pts == #cfg.ref and #pts >= 4, "the same number of anchors: " .. #pts .. " and " .. #cfg.ref)
	for i, p in ipairs(pts) do
		ok(cfg.ref[i] and cfg.ref[i][1] == p[1] and cfg.ref[i][2] == p[2],
			"anchor " .. i .. " of spell_scaling_config.lua is (" .. p[1] .. ", " .. p[2] .. ") like rotation_sim.py ANCHORS 'ml_other'")
	end
	for l = 1, 1200, 37 do -- the same line the model draws (flat above the last anchor)
		local want = pts[#pts][2]
		for i = 2, #pts do
			if l <= pts[i][1] then
				local a, b = pts[i - 1], pts[i]
				want = a[2] + (b[2] - a[2]) * (l - a[1]) / (b[1] - a[1])
				break
			end
		end
		if l <= pts[1][1] then want = pts[1][2] end
		near(S.refML(l), want, 1e-9, "refML at level " .. l)
	end
end

-- the factor: 1 at the typical magic level at every level, +- 1 / 300 per magic level around it
for _, level in ipairs({1, 50, 100, 300, 500, 600, 1000, 1500}) do
	local ref = S.refML(level)
	near(S.factor(level, ref), 1, 1e-12, "typical character at level " .. level)
	near(S.factor(level, ref + 10), (1 + (ref + 10) / 300) / (1 + ref / 300), 1e-12, "+10 magic level at level " .. level)
	ok(S.factor(level, ref + 10) > 1 and S.factor(level, math.max(0, ref - 10)) <= 1, "above typical raises, below lowers: " .. level)
end
near(S.factor(500, S.refML(500) + 30) - 1, 0.1 / (1 + S.refML(500) / 300), 1e-12, "30 magic level more is +10% before the normalisation")
near(S.factor(100, 0), 1 / (1 + 10 / 300), 1e-12, "no magic level at level 100")
near(S.factor(100, -5), S.factor(100, 0), 1e-12, "a negative magic level counts 0")
near(S.factor(100, nil), S.factor(100, 0), 1e-12, "no magic level counts 0")

-- normalise off: the plain (1 + ML / per)
do
	local plain = {mlShare = {per = 300, normalise = false, ref = cfg.ref}}
	near(S.factor(500, 30, plain), 1.1, 1e-12, "plain factor")
	near(S.factor(500, 0, plain), 1, 1e-12, "plain factor without magic level")
	ok(S.factor(500, 30, {}) == 1, "no config: 1")
end

-- a player object
do
	local p = {getLevel = function() return 500 end, getMagicLevel = function() return S.refML(500) end}
	near(S.forPlayer(p), 1, 1e-12, "forPlayer, typical")
	ok(S.forPlayer(nil) == 1 and S.forPlayer({}) == 1, "no player, no getters: 1")
end

-- the helpers the spell scripts call
do
	local n = 0
	setmetatable(_G, {__index = function(t, k)
		if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
	end})
	local realDofile = dofile -- the installed server keeps the spell scripts in data/spells/scripts/chaos/, the repository in data/spells/chaos/
	dofile = function(path) return realDofile((path:gsub("^data/spells/scripts/chaos/", "data/spells/chaos/"))) end
	realDofile("data/spells/chaos/_common.lua")
	dofile = realDofile
	local p = {getLevel = function() return 500 end, getMagicLevel = function() return S.refML(500) + 30 end}
	local k = S.factor(500, S.refML(500) + 30)
	near(ChaosSpell.weaponShare(p), k, 1e-12, "ChaosSpell.weaponShare")
	local lo, hi = ChaosSpell.weaponFormula(p, 100, 200)
	near(lo, -100 * k, 1e-9, "weaponFormula min is negative and scaled")
	near(hi, -200 * k, 1e-9, "weaponFormula max is negative and scaled")
end

if fails > 0 then
	error("spell_scaling_test: " .. fails .. " failure(s)")
end
print("spell_scaling_test: " .. checks .. " checks ok")
