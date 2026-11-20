-- Numbers of the spell combos for the Python tools (O686 phase 6b): run from server/ with luajit or lua5.3.
--   luajit tools/combo_numbers.lua [CONFIG]    (CONFIG: another spell_combos_config.lua, for the tests) prints
--     cfg<TAB>name<TAB>value                       the model numbers: bonus-only typical gain, the riders' mean, the typical gain with riders,
--                                                  the best legal rotation with riders, the limits, the mastery limit
--     row<TAB>id<TAB>bonus<TAB>weight<TAB>riderKind<TAB>riderGain
--     mastery<TAB>id<TAB>name<TAB>gain<TAB>shareGain
--     bad<TAB>text                                 a problem of the config (spell_combos_core.lua C.check / C.checkRiders)
-- The numbers come from spell_combos_core.lua (the one implementation); spell_upgrade_model.py reads these lines.
dofile("data/scripts/chaos/spell_combos_core.lua")
local C = ChaosSpellCombosCore
local cfg = dofile((arg and arg[1]) or "data/scripts/chaos/spell_combos_config.lua")

local function put(name, v)
	print(string.format("cfg\t%s\t%.10f", name, v))
end
put("bonusOnly", C.typicalGain(cfg))
put("meanBonus", C.meanBonus(cfg))
put("meanRider", C.meanRider(cfg))
put("typical", C.typicalWithRiders(cfg))
put("bestBonusOnly", C.bestGain(cfg))
put("best", C.bestWithRiders(cfg))
put("triggerShare", cfg.model.triggerShare)
put("typicalMax", cfg.model.typicalMax)
put("bestMax", cfg.model.bestMax)
put("maxShare", cfg.riders.maxShare)
put("masteryMax", cfg.masteries.maxGain)
for _, r in ipairs(cfg.rows) do
	print(string.format("row\t%s\t%.4f\t%.4f\t%s\t%.10f", r.id, r.bonus, r.weight, r.fx and r.fx.kind or "none", C.riderGain(cfg, r)))
end
for _, c in ipairs(cfg.masteries.choices) do
	print(string.format("mastery\t%d\t%s\t%.10f\t%.4f", c.id, c.name, C.masteryGain(cfg, c), c.shareGain))
end
for _, b in ipairs(C.check(cfg)) do
	print("bad\t" .. b)
end
for _, b in ipairs(C.checkRiders(cfg)) do
	print("bad\t" .. b)
end
