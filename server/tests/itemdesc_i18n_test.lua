-- Run from the server/ folder: luajit tests/itemdesc_i18n_test.lua (and lua5.3; CI runs both)
-- The description of an item in the language of the player who looks at it (itemdesc_i18n_core.lua), with the real
-- pt-BR table (i18n_strings.lua) and the generated unique texts (data/lib/chaos_unique_desc_pt.lua).
local checks, failures = 0, 0
local function check(cond, label)
	checks = checks + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, label .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end

Game = {getPlayers = function() return {} end, broadcastMessage = function() end}
function CreatureEvent(name)
	local ev = {name = name}
	function ev:type() end
	function ev:register() end
	return ev
end
json = {decode = function() return {} end}
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/i18n_core.lua")
dofile("data/scripts/chaos/itemdesc_i18n_core.lua")
dofile("data/lib/chaos_unique_desc_pt.lua")
for i, name in ipairs({"ATTACK", "DEFENSE", "EXTRADEFENSE", "ARMOR", "HITCHANCE", "SHOOTRANGE"}) do
	_G["ITEM_ATTRIBUTE_" .. name] = i
end
dofile("data/lib/chaos_unique_specs.lua")
local D, I = ChaosItemDescI18n, ChaosI18n
local function tr(text)
	return I.translate("pt-BR", text)
end
local function pt(text)
	return D.translate(text, tr, ChaosUniqueDescPt)
end

-- ---------------------------------------------------------------- split
local sample = "One. Two three! Four?\nFive (1.5 x). Six"
eq(table.concat(D.split(sample)), sample, "split keeps every character")
eq(D.split(sample)[1], "One.", "the first sentence keeps its dot")
eq(D.split(sample)[2], " ", "the blanks are the separator")
eq(#D.split(""), 0, "an empty text has no parts")
eq(table.concat(D.split("No stop")), "No stop", "one sentence")
local key, nums = D.normalize("Quality: +5% and 12")
eq(key, "Quality: +%d%% and %d", "numbers become %d, a percent sign %%")
eq(nums[1] + nums[2], 17, "the numbers come back in order")

-- ---------------------------------------------------------------- unique items
local n, missing = 0, 0
for id, spec in pairs(ChaosUniqueSpecs) do
	n = n + 1
	if not ChaosUniqueDescPt[spec.description] then
		missing = missing + 1
		print("no pt-BR text for unique " .. id .. " " .. spec.name)
	end
end
check(n >= 150, "the specs are loaded (" .. n .. ")")
eq(missing, 0, "every unique has a pt-BR description")
local ember = ChaosUniqueSpecs[7384]
check(ember ~= nil, "Emberfall Blade is a unique")
if ember then
	local text = pt(ember.description)
	check(text ~= ember.description, "a unique is translated")
	check(text:find("Temperada no nono salão", 1, true) ~= nil, "the filled flavour text is used")
	check(text:find("Requer nível 150", 1, true) ~= nil, "the level requirement keeps its number")
end
-- no leftover placeholders in any unique text
local leftover = 0
for _, v in pairs(ChaosUniqueDescPt) do
	if v:find("%%s") or v:find("%%d") then
		leftover = leftover + 1
	end
end
eq(leftover, 0, "no unique text keeps a placeholder")

-- ---------------------------------------------------------------- texts a script wrote
eq(pt("A trophy of Ann: Ysgrath, slain once."), "Um troféu de Ann: Ysgrath, derrotado uma vez.", "hideout trophy once")
eq(pt("A trophy of Ann: Ysgrath, slain 7 times."), "Um troféu de Ann: Ysgrath, derrotado 7 vezes.", "hideout trophy times")
check(pt("Use it to return to your temple. Not usable in combat, dungeons, the tower or the world boss arena. 3 uses left."):find("Restam 3 usos", 1, true) ~= nil,
	"temple scroll")
eq(pt("Infinity Tower Season 4, place 2."), "Temporada 4 da Infinity Tower, 2º lugar.", "tower chest")
eq(pt("The banner of Ashes."), "O estandarte de Ashes.", "guild banner")
eq(pt("Teleport to Vale (level 80+)."), "Teleporte para Vale (nível 80+).", "hub portal")
-- several sentences, some with a variable part
eq(pt("Guild Siege wins: 3 of 5. World bosses: 12 victories shared by the members. The Ashen Sepulchre: 2 raid trophies."),
	"Vitórias em Guild Siege: 3 de 5. World bosses: 12 vitórias compartilhadas pelos membros. The Ashen Sepulchre: 2 troféus de raid.",
	"statue text, sentence by sentence")
eq(pt("Guild level 4 (1.2k GXP). Top contributors: Ann (5k), Bob (2k)."),
	"Nível de guild 4 (1.2k GXP). Maiores contribuintes: Ann (5k), Bob (2k).", "statue text with a decimal")
eq(pt("Mystery text nobody translated."), "Mystery text nobody translated.", "no entry: English")
eq(pt("Mystery one. Mystery two."), "Mystery one. Mystery two.", "no entry in several sentences: English")

-- ---------------------------------------------------------------- a rolled item
local rolled = "Bought with Sepulchre Marks. Item Level: 85. Quality: +5%. Ruined. Corrupted. " ..
	"Corrupted implicit: Block Chance +12% (T8). Prefixes: Melee +2 (T3); Fire +5% dmg (T2, bound). " ..
	"Suffixes: Attack Speed +7% (T4); Life on Kill +40 (T3) [Attack+2]"
eq(pt(rolled), "Comprado com Sepulchre Marks. Nível do item: 85. Qualidade: +5%. Arruinado. Corrompido. " ..
	"Implícito corrompido: Chance de bloqueio +12% (T8). Prefixos: Corpo a corpo +2 (T3); Fogo +5% de dano (T2, vinculado). " ..
	"Sufixos: Velocidade de ataque +7% (T4); Vida ao matar +40 (T3) [Attack+2]", "a rolled item line")
eq(pt("Prefixes: Executes Monsters below 20% Health (T5)."), "Prefixos: Executa monstros com menos de 20% de vida (T5).", "a modifier text")
eq(pt("Suffixes: Critical Chance +5%, Critical Hit +30% (T2)"), "Sufixos: Chance crítica +5%, acerto crítico +30% (T2)", "a pair")
eq(pt("Prefixes: Unknown Thing +4 (T1)"), "Prefixes: Unknown Thing +4 (T1)", "an unknown modifier stays English")

-- ---------------------------------------------------------------- the look description
local description = "You see a sword (Atk:20).\nIt weighs 40.00 oz.\nA trophy of Ann: Ysgrath, slain once."
local out = D.apply(description, "A trophy of Ann: Ysgrath, slain once.", tr, ChaosUniqueDescPt)
eq(out, "You see a sword (Atk:20).\nIt weighs 40.00 oz.\nUm troféu de Ann: Ysgrath, derrotado uma vez.", "the description line is swapped")
eq(D.apply(description, "Not in the text.", tr), description, "a description not in the text: unchanged")
eq(D.apply(description, "", tr), description, "an empty description: unchanged")
eq(D.apply(nil, "x", tr), nil, "no text: nil")
eq(D.apply(description, "Mystery text.", tr), description, "nothing known: unchanged")
-- a replacement with a percent sign in it does not break the swap
eq(D.apply("Look: Quality: +5%.", "Quality: +5%.", tr), "Look: Qualidade: +5%.", "percent signs in the text")

print(string.format("itemdesc_i18n_test: %d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
