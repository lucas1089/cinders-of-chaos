-- Stub of the effect helper. Defines Fx/FxMissile ONLY if data/lib/chaos_fx.lua did not.
-- Without custom ids every call just returns the standard CONST_ME_* / CONST_ANI_* fallback.
if Fx == nil then
	ChaosFx = ChaosFx or {}
	function Fx(name, fallback)
		return ChaosFx[name] or fallback
	end
end

if FxMissile == nil then
	ChaosFxMissile = ChaosFxMissile or {}
	function FxMissile(name, fallback)
		return ChaosFxMissile[name] or fallback
	end
end
