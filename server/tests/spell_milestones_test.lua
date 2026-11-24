-- Run from the server/ folder: luajit tests/spell_milestones_test.lua (or lua5.3; CI runs both)
-- Spell path milestones (O752; spell_milestones_core.lua, spell_milestones_config.lua, spell_milestones.lua; server/README.md
-- "Spell path milestones (O752)"). Checks: the gate rules (Form I, Form II, awakening, slots, sockets), the list, the gaps and the
-- rule of tools/progression_model.lua --check on synthetic classes; the config against the typical character of
-- spell_upgrade_model.py (no gate binds it: Form II of an early spell before its rank 20, slots before the model's awakenings); the
-- real classes of the repo inside the limit; the wire; then spell_milestones.lua on a mocked engine (the list of a class from the
-- Spellbook, the toast at a level-up, the state field).
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
SKILL_LEVEL = 8

local failures, count = 0, 0
local function check(cond, label)
	count = count + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, label .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

dofile("data/scripts/chaos/spell_milestones_core.lua")
local K = ChaosSpellMilestonesCore
local cfg = dofile("data/scripts/chaos/spell_milestones_config.lua")
local scfg = dofile("data/lib/chaos_supports_config.lua")

-- ---------------------------------------------------------------- the gates
eq(cfg.enabled, true, "on")
eq(cfg.limit, 150, "the limit")
eq(cfg.from, 190, "from the first drought")
eq(cfg.to, 2500, "to the level cap")
eq(K.formLevel(cfg, 1, 100), 400, "Form I: the spell's level + 300")
eq(K.formLevel(cfg, 1, 500), 800, "Form I of the line spell")
eq(K.formLevel(cfg, 1, 1200), 1500, "Form I of the ultimate")
eq(K.formLevel(cfg, 2, 8), 1050, "Form II of an early spell")
eq(K.formLevel(cfg, 2, 499), 1050, "Form II of a spell learned at 499")
eq(K.formLevel(cfg, 2, 500), 1650, "Form II of the line spell")
eq(K.formLevel(cfg, 2, 1200), 2400, "Form II of the ultimate")
eq(K.formLevel(cfg, 2, "junk"), 1050, "junk level: an early spell")
eq(K.formLevel({formI = {add = 300}, formII = {{level = 100}}}, 2, 500), 800, "Form II never before Form I")
eq(K.awakenLevel(cfg, 300), 0, "an early spell: only the slot decides")
eq(K.awakenLevel(cfg, 500), 2100, "a line spell awakens at 2100")
eq(K.awakenLevel(cfg, 1200), 2500, "an ultimate at the cap")
eq(K.slotLevel(cfg, 1), 1800, "slot 1")
eq(K.slotLevel(cfg, 3), 2250, "slot 3")
eq(K.slotLevel(cfg, 4), 0, "no slot 4 gate")
local a, b = K.socketLevels(scfg, 10)
eq(a, 80, "socket 2: at least 80")
eq(b, 200, "socket 3: at least 200")
a, b = K.socketLevels(scfg, 1200)
eq(a, 1260, "socket 2 of the ultimate")
eq(b, 1350, "socket 3 of the ultimate")
eq(K.band({}, 10), nil, "no rows, no band")

-- ---------------------------------------------------------------- the gates never bind the typical character (spell_upgrade_model.py)
do
	local bal = dofile("data/scripts/chaos/spell_upgrade_balance_config.lua")
	-- slot n is open where the model's awakened count first passes n - 1
	local steps = {}
	for _, s in ipairs(bal.awakening) do steps[#steps + 1] = s end
	for slot = 1, #cfg.slots do
		local need
		for i = 2, #steps do
			if steps[i][2] > slot - 1 and not need then
				-- the count passes slot - 1 right after the point where it is slot - 1 or less
				need = steps[i - 1][2] <= slot - 1 and steps[i - 1][1] or steps[i][1]
			end
		end
		if need then
			check(cfg.slots[slot] <= need, "slot " .. slot .. " opens by level " .. need .. " (the model's awakening " .. slot .. ")")
		end
	end
	-- the main spell's Form II: the typical rank 20 comes after the gate. The model's main rank by level (spell_upgrade_model.py table):
	-- 19.2 at 1600, 20 at 2000; no early spell's gate is above 1600
	check(K.formLevel(cfg, 2, 499) <= 1600, "Form II of an early spell opens before the typical rank 20")
	-- Form I of an early spell before the typical rank 10 (main rank 9.0 at 600, 10.6 at 700)
	check(K.formLevel(cfg, 1, 300) <= 600, "Form I of a spell learned by 300 opens before the typical rank 10")
end

-- ---------------------------------------------------------------- the list, gaps and rule on synthetic classes
do
	local spells = {
		{id = 1, name = "A", level = 8, forms = true, awaken = true, sockets = true},
		{id = 2, name = "B", level = 500, forms = true, awaken = true, sockets = true},
		{id = 3, name = "C", level = 1200, forms = true, awaken = true, sockets = false},
		{id = 4, name = "Buff", level = 800, forms = false, awaken = false, sockets = true},
	}
	local list = K.list(cfg, spells, scfg)
	local kinds = {}
	for _, e in ipairs(list) do
		kinds[e.kind] = (kinds[e.kind] or 0) + 1
	end
	eq(kinds.spell, 4, "four spells")
	eq(kinds.form1, 3, "three Form I gates")
	eq(kinds.form2, 3, "three Form II gates")
	eq(kinds.awaken, 2, "the awaken gates above slot 1 only")
	eq(kinds.slot, 3, "three slots")
	eq(kinds.socket2, 3, "sockets of the spells that have them")
	for i = 2, #list do
		check(list[i - 1].level <= list[i].level, "sorted at " .. i)
	end
	local nx = K.nextAfter(list, 1200)
	eq(nx.level, 1500, "after 1200: Form I of C (C has no sockets)")
	eq(nx.entries[1].kind, "form1", "the Form I")
	nx = K.nextAfter(list, 1800)
	eq(nx.level, 1950, "after slot 1: slot 2")
	eq(nx.entries[1].kind, "slot", "the slot")
	eq(nx.entries[1].slot, 2, "slot 2")
	eq(K.nextAfter(list, 2500), nil, "nothing after the cap")
	local hit = K.reached(list, 1799, 1800, cfg.toastKinds)
	eq(#hit, 1, "1799 -> 1800 reaches slot 1")
	hit = K.reached(list, 1000, 1700, cfg.toastKinds)
	eq(#hit, 3, "1000 -> 1700: Form II of A, Form I of C, Form II of B")
	hit = K.reached(list, 1000, 1700)
	check(#hit > 3, "no kinds: every milestone, sockets too")
	-- the gaps: a class with nothing between 950 (A's sockets? no) and the next
	local _, best = K.gaps(list, cfg.from, cfg.to)
	check(best.gap > 0, "a longest stretch")
	local gaps = K.gaps({{level = 100}, {level = 300}, {level = 2400}}, 190, 2500)
	eq(#gaps, 3, "three stretches touch 190-2500")
	eq(gaps[1].gap, 200, "the stretch over `from` counts")
	eq(gaps[2].gap, 2100, "the long one")
	eq(gaps[3].gap, 100, "to the cap")
	eq(#K.gaps({{level = 100}, {level = 150}}, 190, 2500), 1, "a stretch that ends below `from` does not count")
	local probs = K.problems(cfg, {Short = {{level = 190}, {level = 2500}}, Fine = {{level = 190}, {level = 340}}})
	eq(#probs, 2, "the rule: two stretches too long (Short 190-2500, Fine 340 to the cap)")
	check(probs[1]:find("Fine", 1, true) and probs[1]:find("limit is 150", 1, true), "the problem names the class and the limit")
	local ok = {}
	for L = 190, 2500, 150 do ok[#ok + 1] = {level = L} end
	ok[#ok + 1] = {level = 2500}
	eq(#K.problems(cfg, {Steady = ok}), 0, "a milestone every 150 levels passes")
	eq(K.count({{level = 100}, {level = 200}, {level = 2600}}, 190, 2500), 1, "count inside the range")
end

-- ---------------------------------------------------------------- the real classes (the --check rule)
do
	ChaosProgressionLib = true
	local P = dofile("tools/progression_model.lua")
	ChaosProgressionLib = nil
	local ms, mcfg, KK = P.milestones()
	local classes = 0
	for voc, list in pairs(ms) do
		classes = classes + 1
		local _, best = KK.gaps(list, mcfg.from, mcfg.to)
		check(best.gap <= mcfg.limit, voc .. ": longest stretch " .. best.gap .. " (" .. best.from .. " to " .. best.to .. ")")
		local slots = 0
		for _, e in ipairs(list) do
			if e.kind == "slot" then slots = slots + 1 end
		end
		eq(slots, 3, voc .. ": three slots")
	end
	eq(classes, 21, "21 classes")
	eq(#KK.problems(mcfg, ms), 0, "the --check rule passes")
	-- the rule bites: a smaller limit fails
	local tight = {}
	for k, v in pairs(mcfg) do tight[k] = v end
	tight.limit = 100
	check(#KK.problems(tight, ms) > 0, "a limit of 100 fails")
	-- without the gates (only spells and sockets) the drought is back
	local bare = {}
	for voc, list in pairs(ms) do
		local only = {}
		for _, e in ipairs(list) do
			if e.kind == "spell" or e.kind == "socket2" or e.kind == "socket3" then only[#only + 1] = e end
		end
		bare[voc] = only
	end
	check(#KK.problems(mcfg, bare) >= 21, "without the gates every class fails (no milestone after 1350)")
end

-- ---------------------------------------------------------------- the wire
do
	local list = K.list(cfg, {{id = 9, name = "Doomtide", level = 1200, forms = true, awaken = true, sockets = true}}, scfg)
	local w = K.wire(cfg, K.nextAfter(list, 1400))
	eq(w.f1, 300, "wire: Form I add")
	eq(#w.f2, 3, "wire: Form II rows")
	eq(w.f2[1][1], 500, "wire: below")
	eq(w.f2[3][1], 0, "wire: the last row has below 0")
	eq(w.f2[3][2], 2400, "wire: its level")
	eq(w.aw[2][2], 2100, "wire: awaken")
	eq(w.sl[2], 1950, "wire: slots")
	eq(w.nx.l, 1500, "wire: next level")
	eq(w.nx.k, "form1", "wire: next kind")
	eq(w.nx.n, "Doomtide", "wire: next spell")
	eq(K.wire(cfg, nil).nx, nil, "wire: nothing next")
end

-- ================================================================ spell_milestones.lua on a mocked engine
local registry, texts, toasts = {}, {}, {}
CreatureEvent = function(name)
	local e = {name = name}
	function e:type() end
	function e:register() registry[name] = self end
	return e
end
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/i18n_core.lua")
ChaosNotify = {send = function(player, title, text, kind)
	toasts[#toasts + 1] = {title = title, text = text, kind = kind}
	return true
end}
local bookList
ChaosSpellbook = {get = function()
	bookList = bookList or {
		{id = 204, name = "Searing Orb", level = 150, vocations = {2}},
		{id = 152, name = "Doomtide", level = 500, vocations = {2}},
		{id = 154, name = "Cataclysm", level = 1200, vocations = {2}},
		{id = 999, name = "Other Class", level = 100, vocations = {5}},
		{name = "A Rune", level = 20, vocations = {2}, rune = 3000},
	}
	return bookList
end}
ChaosSpellForms = {entry = function(id) return (id == 204 or id == 152 or id == 154) and {} or nil end}
ChaosSpellAwakening = {entry = function(id) return (id == 204 or id == 152 or id == 154) and {} or nil end}
dofile("data/scripts/chaos/spell_milestones.lua")
local SM = ChaosSpellMilestones
check(registry.ChaosSpellMilestonesLogin ~= nil and registry.ChaosSpellMilestonesAdvance ~= nil, "events registered")
local level = 1499
local p = {}
function p:getLevel() return level end
function p:getVocation() return {getId = function() return 2 end} end
function p:registerEvent() end
function p:sendTextMessage(_, t) texts[#texts + 1] = t end
function p:getStorageValue() return -1 end
local list = SM.listOf(p)
local spells = 0
for _, e in ipairs(list) do
	if e.kind == "spell" then spells = spells + 1 end
	check(e.name ~= "Other Class" and e.name ~= "A Rune", "only the class's spells, no rune: " .. tostring(e.name))
end
eq(spells, 3, "the class's three spells")
check(SM.listOf(p) == list, "cached")
local w = SM.wire(p)
eq(w.nx.l, 1500, "next: 1500")
eq(w.nx.k, "form1", "next: Form I")
eq(w.nx.n, "Cataclysm", "next: of the ultimate")
-- the toast at the level-up
registry.ChaosSpellMilestonesAdvance.onAdvance(p, SKILL_LEVEL, 1499, 1500)
eq(#toasts, 1, "one toast")
eq(toasts[1].kind, "milestone", "kind milestone")
eq(toasts[1].title, "New unlock", "the title")
check(toasts[1].text:find("Form I opens for Cataclysm.", 1, true) ~= nil, "names the Form I: " .. toasts[1].text)
check(toasts[1].text:find("Next unlock: level 1650.", 1, true) ~= nil, "names the next: " .. toasts[1].text)
eq(#texts, 1, "a status line too")
-- a socket only: no toast
registry.ChaosSpellMilestonesAdvance.onAdvance(p, SKILL_LEVEL, 1349, 1350)
eq(#toasts, 1, "a socket alone does not toast")
-- a skill is no level
registry.ChaosSpellMilestonesAdvance.onAdvance(p, 1, 1799, 1800)
eq(#toasts, 1, "a skill does not toast")
-- a jump over several: one toast, the slot and the Forms
registry.ChaosSpellMilestonesAdvance.onAdvance(p, SKILL_LEVEL, 1600, 1960)
eq(#toasts, 2, "one toast for a jump")
check(toasts[2].text:find("Awakening slot 1 opens.", 1, true) and toasts[2].text:find("Awakening slot 2 opens.", 1, true),
	"both slots: " .. toasts[2].text)
check(toasts[2].text:find("Form II opens for Doomtide.", 1, true) ~= nil, "the Form II of the line spell")
-- many names: "and N more"
local header, text = SM.toastText(p, {{kind = "form1", name = "A"}, {kind = "form1", name = "B"}, {kind = "form1", name = "C"},
	{kind = "form1", name = "D"}, {kind = "form1", name = "E"}}, nil)
eq(header, "New unlock", "header")
eq(text, "Form I opens for A, B, C and 2 more.", "the rest counted")
eq(SM.toastText(p, {}, nil), nil, "nothing reached: no toast")
-- off: nothing
cfg = ChaosSpellMilestonesConfig
cfg.enabled = false
eq(SM.wire(p), nil, "off: no wire")
registry.ChaosSpellMilestonesAdvance.onAdvance(p, SKILL_LEVEL, 2249, 2250)
eq(#toasts, 2, "off: no toast")
cfg.enabled = true

print(string.format("spell_milestones_test: %d checks, %d failures", count, failures))
if failures > 0 then
	os.exit(1)
end
