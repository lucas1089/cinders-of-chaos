-- chaos_awakened_look.lua: an awakened spell sends the awakened look kit (O711, client pair 76; docs/SPELL_UPGRADES.md 3.4,
-- server/README.md "Awakened spell looks (O711)"). The kit and the gate are data/lib/chaos_awakened_fx.lua (chaosClientPair >= 76);
-- every rule of which effect is data/scripts/chaos/awakened_look_config.lua. This file only asks and sends.
--
-- A cast is awakened when the spell of the cast running now (ChaosSupportsSpell.cast()) is awakened for the caster
-- (ChaosSpellAwakening.isAwakened). Then, for that cast:
--   * the area / target effect is the kit effect ChaosAwakenedFx.effect(element, shape), sent ONCE a cast on the anchor tile
--     (the picture is itself the area: later sends of the same cast, by Vfx, ChaosSpell.fx and the combat's own effect, send nothing);
--   * every projectile is ChaosAwakenedFx.missile(element) (the Combat distance effect, FxMissile, VfxShoot).
-- Not changed: the effects the Forms and the signature send themselves (ChaosSpellForms.sendFx, Vfx(pos, name, true)), raw
-- sendMagicEffect calls of a spell script, damage, area, timing. PvP is not a gate: the look is cosmetic.
-- Below pair 76, with the spell ranks / awakening off, for a spell that is not awakened, or when the lookup answers nil: cast() answers
-- nil and every caller sends exactly what it sent before.
-- Callers: data/lib/chaos_vfx.lua (Vfx, VfxShoot), data/spells/chaos/_common.lua (ChaosSpell.fx, FxMissile),
-- data/lib/chaos_spell_forms.lua (the Combat wrapper). Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosAwakenedLook = ChaosAwakenedLook or {}
local L = ChaosAwakenedLook

if not ChaosAwakenedLookConfig and dofile then
	local okc, cfg = pcall(dofile, "data/scripts/chaos/awakened_look_config.lua")
	if okc and type(cfg) == "table" then
		ChaosAwakenedLookConfig = cfg
	end
end

-- the state of the last cast of each player: {key, spell, state}; state false = this cast plays its normal effects
local cache = {}
L.cache = cache

local function cfg()
	return ChaosAwakenedLookConfig
end

local function loadLibs()
	if not rawget(_G, "ChaosAwakenedFx") and dofile then
		pcall(dofile, "data/lib/chaos_awakened_fx.lua")
	end
	if not rawget(_G, "ChaosSpellAwakening") and dofile then
		pcall(dofile, "data/lib/chaos_spell_awakening.lua")
	end
end

-- THE element rule: the element the cast shows (a Form's conversion, else the spell's own) when the kit has it, else the fallback kit
function L.element(spellElement, conversion)
	local FX = rawget(_G, "ChaosAwakenedFx")
	local c = cfg()
	local el = conversion or spellElement
	for _, name in ipairs(FX and FX.ELEMENTS or {}) do
		if name == el then
			return el
		end
	end
	return c.fallbackElement
end

-- THE shape rule: the kit shape of the spell's area shape; a line or a wave that does not face east takes its eastOnly shape
function L.shape(areaShape, facingEast)
	local c = cfg()
	local s = c.shape[areaShape] or c.fallbackShape
	if not facingEast and c.eastOnly[s] then
		s = c.eastOnly[s]
	end
	return s
end

local function facesEast(player)
	local ok, d = pcall(function() return player:getDirection() end)
	return ok and d == (rawget(_G, "EAST") or 1)
end

local function build(pid, spellId)
	local FX = rawget(_G, "ChaosAwakenedFx")
	local AW = rawget(_G, "ChaosSpellAwakening")
	if not FX or not FX.on or not AW or not AW.isAwakened or not rawget(_G, "Player") or not cfg() then
		return false
	end
	local player = Player(pid)
	if not player or not AW.isAwakened(player, spellId) then
		return false
	end
	local entry = AW.entry(spellId)
	if not entry then
		return false
	end
	local conv
	local FM = rawget(_G, "ChaosSpellForms")
	if FM and FM.castConversion then
		local ok, el = pcall(FM.castConversion, player)
		conv = ok and el or nil
	end
	local element = L.element(entry.element, conv)
	local shape = L.shape(entry.shape, facesEast(player))
	local effect = FX.effect(element, shape)
	if not effect then
		return false
	end
	return {element = element, shape = shape, effect = effect, missile = FX.missile(element), sent = false, caster = player:getPosition()}
end

-- the awakened look of the cast running now: {element, shape, effect, missile, sent, caster} or nil
function L.cast()
	if not L.loaded then
		L.loaded = true
		loadLibs()
	end
	local FX = rawget(_G, "ChaosAwakenedFx")
	if not FX or not FX.on then
		return nil
	end
	local W = rawget(_G, "ChaosSupportsSpell")
	if not W or not W.cast then
		return nil
	end
	local pid, spellId = W.cast()
	if not pid then
		return nil
	end
	local ctx = W.context and W.context()
	local key = ctx and ctx.value or 0
	local c = cache[pid]
	if c and c.key == key and c.spell == spellId then
		return c.state or nil
	end
	local ok, state = pcall(build, pid, spellId)
	c = {key = key, spell = spellId, state = ok and state or false}
	cache[pid] = c
	return c.state or nil
end

-- send the kit effect of the cast on the anchor tile (once a cast); `pos` is the tile of the send being replaced.
-- true: the cast is awakened, the send is handled (sent now, or sent before).
function L.sendEffect(st, pos)
	if st.sent then
		return true
	end
	local at = pos
	if cfg().anchor[st.shape] == "caster" and st.caster then
		at = st.caster
	end
	if not at then
		return false
	end
	st.sent = true
	local e = st.effect
	Position(at.x + e.dx, at.y + e.dy, at.z):sendMagicEffect(e.id)
	return true
end

-- Vfx / ChaosSpell.fx at `pos` while an awakened cast runs: the kit effect instead, once; true = handled, nothing else is sent
function L.vfx(pos)
	local st = L.cast()
	if not st or not pos then
		return false
	end
	return L.sendEffect(st, pos)
end

-- the projectile id of the awakened cast running now, nil when none (every projectile of the cast takes it)
function L.missileId()
	local st = L.cast()
	return st and st.missile and st.missile.id or nil
end

-- for the Combat wrapper of chaos_spell_forms.lua: {missile = id or nil, send = function(pos)} or nil
function L.forCast()
	local st = L.cast()
	if not st then
		return nil
	end
	return {missile = st.missile and st.missile.id or nil, send = function(pos)
		return L.sendEffect(st, pos)
	end}
end

-- The engine's doAreaCombat(cid, type, pos, area, min, max, effect, ...) of the spells that call it direct (Doomtide, Glacial Doom,
-- Primordial Squall: an effect on every tile of the area): while an awakened cast runs the tile effect is none and the kit effect is sent
-- once on the anchor. Wrapped once, on top of whatever doAreaCombat is now (combatlog.lua wraps it too: the two compose either way).
function L.installLegacy()
	local raw = rawget(_G, "doAreaCombat")
	if L.legacy or type(raw) ~= "function" then
		return false
	end
	L.legacy = true
	_G.doAreaCombat = function(cid, ctype, pos, area, min, max, effect, ...)
		local st = L.cast()
		if not st or not pos then
			return raw(cid, ctype, pos, area, min, max, effect, ...)
		end
		local res = raw(cid, ctype, pos, area, min, max, rawget(_G, "CONST_ME_NONE") or 0, ...)
		L.sendEffect(st, pos)
		return res
	end
	return true
end

return L
