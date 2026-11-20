-- Run from the server/ folder: luajit tests/forms_gen_test.lua && lua5.3 tests/forms_gen_test.lua (CI runs both)
-- O686 phase 4: tools/gen_forms_data.lua (the client's Forms data): number and string helpers, the sentence of every kind with its numbers
-- (English and pt-BR with the decimal comma), an override changing a sentence, the same bytes twice, the client file is what the data gives,
-- every sentence and name has its pt-BR entry, a missing entry is found.
local checks, fails = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end
local function eq(a, b, what)
	ok(a == b, what .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

FORMS_GEN_NO_MAIN = true
local Gen = dofile("tools/gen_forms_data.lua")
local F = ChaosSpellFormsCore

eq(Gen.num(35), "35", "a whole number")
eq(Gen.num(3.5), "3.5", "a decimal")
eq(Gen.num(7.5), "7.5", "7.5")
eq(Gen.q("a\"b"), "\"a\\\"b\"", "a quote is escaped")
eq(Gen.q("a\\b"), "\"a\\\\b\"", "a backslash is escaped")
eq(Gen.q("Heretic's"), "\"Heretic's\"", "an apostrophe stays")
eq(Gen.q("á"), "\"á\"", "UTF-8 stays")

local texts = dofile("tools/forms_text_config.lua")
for _, list in ipairs({F.kinds1, F.kinds2, F.heal1, F.heal2}) do
	for _, k in ipairs(list) do
		ok(texts.en[k] and texts.pt[k], "an English and a pt-BR sentence for " .. k)
		ok(Gen.text(texts.en[k], k, nil):find("{", 1, true) == nil, k .. ": every {name} is filled")
	end
end
for k in pairs(F.utility) do
	ok(texts.ptUtility[k], "a pt-BR utility for " .. k)
end
eq(Gen.text(texts.en.SPLIT, "SPLIT", nil), "The hit splits into 3 hits of 35% on the nearest enemies in 3 sqm.", "SPLIT sentence")
eq(Gen.text(texts.en.DELAY, "DELAY", nil), "No hit now. A marked burst lands after 1.5 seconds for 110% of the hit, with a warning circle.", "DELAY: milliseconds as seconds")
eq(Gen.textPt(texts.pt.DELAY, "DELAY", nil), "Sem golpe agora. Uma explosão marcada cai depois de 1,5 segundos com 110% do golpe, com um círculo de aviso.", "pt-BR: the decimal comma")
eq(Gen.text(texts.en.SPLIT, "SPLIT", {pct = 20}), "The hit splits into 3 hits of 20% on the nearest enemies in 3 sqm.", "an override changes the sentence")
ok(not pcall(Gen.text, "a {bogus} b", "SPLIT", nil), "a {name} that is no number stops the run")

local rows = Gen.rows()
local cfg = dofile("data/scripts/chaos/spell_ranks_config.lua")
local out1, needed = Gen.build(rows, texts, cfg)
local out2 = Gen.build(rows, texts, cfg)
eq(out1, out2, "the same bytes twice")
ok(out1:find("ChaosFormsData = {", 1, true), "the table")
ok(out1:find("[201] = {name = \"Witchfire Bolt\", heal = false, element = \"fire\"", 1, true), "a spell row")
ok(out1:find("{\"SHIFT:ice\", \"Ice Shift\"}", 1, true), "a conversion Form")
ok(out1:find("[1] = {name = \"Minor Mending\", heal = true, forms =", 1, true), "a heal row has no element")
ok(#needed >= 60, "every text is listed: " .. #needed)

-- the client file is what the data gives
local f = assert(io.open("../client/overlay/modules/game_spellranks/forms_data.lua", "r"))
local have = f:read("*a")
f:close()
ok(have == out1, "the committed client file is what the data gives")

-- the pt-BR table has every text, and the names match forms.csv
local pt = Gen.loadPt()
local bad = Gen.ptProblems(needed, pt)
ok(#bad == 0, "pt_br.lua has every Form text: " .. tostring(bad[1]))
bad = Gen.ptProblems({{en = "A text no table has"}}, pt)
ok(#bad == 1 and bad[1]:find("no entry"), "a missing text is found")
bad = Gen.ptProblems({{en = "Ripple", pt = "Errado"}}, pt)
ok(#bad == 1 and bad[1]:find("forms.csv says"), "a name that differs from forms.csv is found")
local lines = Gen.ptLines({{en = "Ripple", pt = "Ondulação"}})
eq(lines[1], "  [\"Ripple\"] = \"Ondulação\",", "a pt_br.lua line")

print(string.format("forms_gen_test: %d checks, %d failures", checks, fails))
if fails > 0 then
	os.exit(1)
end
