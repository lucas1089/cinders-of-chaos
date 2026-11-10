-- Run from the server/ folder: luajit tests/starter_builds_test.lua (and lua5.3; CI runs both).
-- The Starter Builds guide (tools/gen_starter_builds.lua, tools/starter_builds_config.lua, the data file
-- website/overlay/plugins/chaos/guide/starter_builds_data.json, O448):
--   * the OWNER RULE: the guide is qualitative. Any text with a percent sign or the letters DPS stops the generator, and
--     here the test proves it does (a copy of the config with one such text is refused), for every text field;
--   * the words: every build has both languages, a style of at most 240 characters, a known price, 2 to 4 spells of the class,
--     a weapon family the class fights with (Warrior, Thief and Templar lines), a reachable card set;
--   * the facts: 21 classes x 3 builds, the keystones of each build by name and point, four codes per build that decode to
--     exactly the first N nodes, every cut a legal tree under the loadouts' rules, never more than 3 keystones;
--   * the committed data file is what the generator writes (CI also runs --check).
STARTER_GEN_NO_MAIN = true
local failures, checks = 0, 0
local function check(cond, label)
	checks = checks + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end

local Gen = dofile("tools/starter_builds_config.lua") and dofile("tools/gen_starter_builds.lua")
local G = Gen.loadGame()
local S0 = dofile("tools/starter_builds_config.lua")

-- ------------------------------------------------------------------------------------------------ the rule's own checks
check(Gen.textProblem("It adds 12% more damage") ~= nil, "a percent sign is a problem")
check(Gen.textProblem("100%") ~= nil, "a lone percent sign is a problem")
check(Gen.textProblem("A high DPS") ~= nil, "DPS is a problem")
check(Gen.textProblem("a high dps build") ~= nil, "dps in lower case is a problem")
check(Gen.textProblem("Max DpS here") ~= nil, "DpS in mixed case is a problem")
check(Gen.textProblem("Two\226\128\148dashes") ~= nil and Gen.textProblem("En\226\128\147dash") ~= nil, "an em or en dash is a problem")
check(Gen.textProblem("") ~= nil and Gen.textProblem(nil) ~= nil, "an empty text is a problem")
check(Gen.textProblem("Cleaving Arc cleaves the monsters beside you.") == nil, "plain words are fine")
check(Gen.textProblem("Every fourth hit slams the ground. It opens at level 130.") == nil, "a plain game fact (a count, a level) is fine")
check(Gen.pairProblem({"Plain words", "Palavras simples"}) == nil, "a pair of plain texts is fine")
check(Gen.pairProblem({"Plain words", "Palavras 5%"}) ~= nil, "a percent sign in the Portuguese text is a problem")
check(Gen.pairProblem({"Same", "Same"}) ~= nil and Gen.pairProblem({"Same", "Same"}, true) == nil, "the same text in both languages needs the allowance")
check(Gen.pairProblem({"only one"}) ~= nil, "a pair has two texts")
check(Gen.chars("a\195\169b") == 3, "characters, not bytes")

-- ------------------------------------------------------------------------------------------------ the config is refused when it breaks a rule
local function copy(v)
	if type(v) ~= "table" then return v end
	local out = {}
	for k, x in pairs(v) do out[k] = copy(x) end
	return out
end
local function refused(mutate, expect, label)
	local S = copy(S0)
	mutate(S)
	local ok, err = pcall(Gen.build, S, G)
	check(not ok and tostring(err):find(expect, 1, true) ~= nil, label .. " (" .. tostring(err):sub(1, 160) .. ")")
end
local ok, data, text, notes, counts = pcall(Gen.build, S0, G)
check(ok, "the real config builds: " .. tostring(data))
check(ok and counts.builds == 63 and counts.codes == 252 and #notes == 0, "63 builds, 252 codes, no cut dropped")

-- the owner rule, on every text field of a build
for _, field in ipairs({"style", "gear"}) do
	for _, i in ipairs({1, 2}) do
		refused(function(S) S.builds.warrior_slayer[field][i] = "It adds 12% damage" end, "percent sign", field .. " " .. i .. " with a percent sign")
		refused(function(S) S.builds.warrior_slayer[field][i] = "A very high DPS build" end, "DPS", field .. " " .. i .. " with DPS")
	end
end
refused(function(S) S.prices.lowDamage[1] = "Low damage, 50% less" end, "percent sign", "a price with a percent sign")
refused(function(S) S.intro[2] = "Números de dano: 10% a mais" end, "percent sign", "the intro with a percent sign")
refused(function(S) S.sets.Fire.text[1] = "Fire hits deal 4% more." end, "percent sign", "a card set text with a percent sign")
refused(function(S) S.headings.point[1] = "point %d" end, "percent sign", "a heading with a format")
refused(function(S) S.builds.warrior_slayer.cards = {"No set, DPS stays", "Nenhum conjunto"} end, "DPS", "a cards text with DPS")
refused(function(S) S.builds.thief_mine_layer.style[1] = "A trap\226\128\148a mine." end, "dash", "a dash")
-- the other rules
refused(function(S) S.builds.warrior_slayer.style[1] = string.rep("word ", 49) end, "at most 240", "a style over 240 characters")
refused(function(S) S.builds.warrior_slayer.style[2] = S.builds.warrior_slayer.style[1] end, "Portuguese text is the English", "a style not translated")
refused(function(S) S.builds.warrior_slayer.price = "nope" end, "unknown price", "an unknown price")
refused(function(S) S.builds.warrior_slayer.spells = {"Reaping Gyre", "Fireball of Doom"} end, "not a spell of the Warrior", "a spell the class does not have")
refused(function(S) S.builds.warrior_slayer.spells = {"Reaping Gyre"} end, "2 to 4 spells", "one spell")
refused(function(S) S.builds.warrior_slayer.cards = "Holy" end, "not reachable", "a card set the class cannot reach")
refused(function(S) S.builds.warrior_slayer.cards = nil end, "no cards entry", "no cards entry")
refused(function(S) S.builds.thief_venomblade.gear = {"An axe for poison.", "Um machado para veneno."} end, "does not fight with", "a weapon family the class does not use")
refused(function(S) S.builds.warrior_slayer.gear = {"Heavy armour only.", "Só armadura pesada."} end, "names no weapon family", "no weapon family for a melee class")
refused(function(S) S.builds.sentinel_bastion = nil end, "no entry", "a build without words")
refused(function(S) S.builds.warrior_extra = copy(S.builds.warrior_slayer) end, "an entry of no Recommended build", "an entry of no build")
refused(function(S) S.prices.unusedPrice = {"A price nobody pays.", "Um preco que ninguem paga."} end, "used by no build", "a price no build uses")
refused(function(S) S.classes[1].name = "Warlord" end, "the cards' name", "a class name that is not the game's")
refused(function(S) table.insert(S.classes, {key = "bard", name = "Bard", line = {"x", "y"}}) end, "not a class of the game", "a class of the config that is not in the game")

-- ------------------------------------------------------------------------------------------------ the words and the facts, build by build
local PC, B, PB, tree = G.PC, G.B, G.PB, G.tree
local nBuilds, nCodes, nKs = 0, 0, 0
local seenId = {}
for _, class in ipairs(data.__ordered[#data.__ordered][2]) do
	local fields = {}
	for _, kv in ipairs(class.__ordered) do fields[kv[1]] = kv[2] end
	check(#fields.builds == 3, fields.key .. ": three builds")
	for _, build in ipairs(fields.builds) do
		local b = {}
		for _, kv in ipairs(build.__ordered) do b[kv[1]] = kv[2] end
		nBuilds = nBuilds + 1
		check(not seenId[b.id], b.id .. ": unique")
		seenId[b.id] = true
		local role
		for _, r in ipairs(G.cfg.roles[fields.key]) do
			if fields.key .. "_" .. r.id == b.id then role = r end
		end
		check(role ~= nil and b.name == role.name, b.id .. ": the name is the Recommended build's")
		-- the keystones are the build's own, in the order they arrive, by the point of the build
		local source = PB.find(G.builds, fields.key, b.id)
		local expectKs = 0
		local seen = {}
		for _, id in ipairs(source.order) do
			if PC.isKeystone(tree.nodes[id]) and not seen[id] then seen[id] = true; expectKs = expectKs + 1 end
		end
		check(#b.keystones == expectKs and expectKs <= 3, b.id .. ": the guide names the " .. expectKs .. " keystones of the build")
		nKs = nKs + #b.keystones
		local last = 0
		for _, k in ipairs(b.keystones) do
			local name, point
			for _, kv in ipairs(k.__ordered) do
				if kv[1] == "name" then name = kv[2] else point = kv[2] end
			end
			check(point > last and PC.isKeystone(tree.nodes[source.order[point]]), b.id .. ": " .. name .. " is the keystone at point " .. point)
			last = point
		end
		-- the codes: the first N nodes, decoded, a legal slot, under the cap
		check(#b.codes == 4, b.id .. ": four codes")
		for _, c in ipairs(b.codes) do
			local code = {}
			for _, kv in ipairs(c.__ordered) do code[kv[1]] = kv[2] end
			nCodes = nCodes + 1
			local back = B.decode(code.code)
			check(back ~= nil and #back.nodes == code.points, b.id .. ": the code of " .. code.points .. " points decodes to that many nodes")
			local want = {}
			for i = 1, code.points do want[source.order[i]] = true end
			local same = back ~= nil
			for _, id in ipairs(back and back.nodes or {}) do same = same and want[id] == true end
			check(same, b.id .. ": the code of " .. code.points .. " points is the first " .. code.points .. " nodes of the build")
			check(back and back.classId == B.lineIndex(({warrior = "warrior", juggernaut = "warrior", berserker = "warrior", ranger = "ranger", deadeye = "ranger",
				beastmaster = "ranger", mystic = "mystic", elementalist = "mystic", illusionist = "mystic", thief = "thief", ninja = "thief", samurai = "thief"})[fields.key] or "none"),
				b.id .. ": the class mark of the code is the class line's")
			local sp, why = PB.planSlot(tree, {id = b.id, kind = "role", order = source.order, masteries = {}}, {classKey = fields.key, points = code.points})
			check(sp ~= nil and #sp.ids == code.points and PC.checkKeystones(tree, sp.ids) == true, b.id .. ": the cut of " .. code.points .. " is a legal slot (" .. tostring(why) .. ")")
			check(code.keystones == PC.countKeystones(tree, sp.ids), b.id .. ": the keystone count of the cut")
		end
	end
end
check(nBuilds == 63 and nCodes == 252, "63 builds, 252 codes (" .. nBuilds .. ", " .. nCodes .. ")")
check(nKs >= 90, "the guide names the keystones (" .. nKs .. ")")

-- ------------------------------------------------------------------------------------------------ the committed file
local fh = io.open(Gen.OUT, "rb")
local committed = fh and fh:read("*a")
if fh then fh:close() end
check(committed == text, "the committed data file is what the generator writes (run: cd server && luajit tools/gen_starter_builds.lua)")
check(committed and not committed:find("%%") and not committed:upper():find("DPS", 1, true), "the data file holds no percent sign and no DPS")
check(committed and not committed:find("\226\128\148", 1, true) and not committed:find("\226\128\147", 1, true), "the data file holds no dash")
-- twice the same
local _, text2 = Gen.build(S0, G)
check(text2 == text, "the generator is deterministic")

-- the texts use the build's own role text up to its price, and the role keeps its own price line (the guide has words)
local roleCount, withPct = 0, 0
for _, list in pairs(G.cfg.roles) do
	for _, r in ipairs(list) do
		roleCount = roleCount + 1
		if r.text:find("%%") then withPct = withPct + 1 end
	end
end
check(roleCount == 63 and withPct > 0, "the in-game role texts have figures in their price line (" .. withPct .. " of 63): the guide never copies that part")

if failures > 0 then
	error(failures .. " of " .. checks .. " checks failed")
end
print("starter_builds_test: " .. checks .. " checks OK")
