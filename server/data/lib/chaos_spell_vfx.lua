-- chaos_spell_vfx.lua: the spell effects and the projectile of a purchased effect pack (O596, trimmed by O600, client pair
-- 73; the art is in the sprite pair only, client/tools/sprites/gen_spell_vfx.py, docs/CREDITS.md). O596 gave 52 spells a
-- pack piece; the owner watched the previews and kept today's effects ("use only the ones that were really bad"), so only
-- the three spells whose effect of today does not read at game size are left. Looks only: no damage, no timing, no area
-- changes.
--
-- Gate: config.lua `chaosClientPair` (README "Client pair guard") is 73 or more, read from the file at load (C.ON). A client
-- on pair 72 has no effect 4743+ and a blank projectile 46, so below 73 nothing here answers and every spell keeps today's
-- effects. The owner raises the record when pair 73 ships.
--
-- How: data/spells/chaos/_common.lua asks C.swapFor(spellId, kind, name) first, before the effects pass (chaos_fx_pass.lua),
-- pair 29, pair 36 and pair 27, for every name a spell sends through ChaosSpell.fx / vfx / vfxOr / shoot / vshoot / pshoot.
-- kind is "fx" (an effect name) or "missile"; the names are the ones the scripts ask, before any swap.
-- The ids, send offsets and elements are the generated data/lib/chaos_spell_vfx_ids.lua. Plain Lua, no engine call at load
-- (server/tests/spell_vfx_test.lua).

local C = {}

C.PAIR = 73

function C.parsePair(text)
	if type(text) ~= "string" then
		return nil
	end
	local v = text:match("^%s*chaosClientPair%s*=%s*(%d+)%s*%-?%-?[^\n]*$") or text:match("\n%s*chaosClientPair%s*=%s*(%d+)%s*%-?%-?[^\n]*")
	return v and tonumber(v) or nil
end

function C.recordedPair(path)
	local f = io.open(path or "config.lua", "r")
	if not f then
		return nil
	end
	local text = f:read("*a")
	f:close()
	return C.parsePair(text)
end

-- the gate, read once at load; tests set it by hand
C.ON = (C.recordedPair() or 0) >= C.PAIR

-- [spell id] = {fx = {asked name = piece}, missile = {asked name = piece}}
C.spells = {
	[106] = {missile = {skull_orb = "sv_death_skull"}}, -- Marrow Bolt: today's bolt is a dark dart, lost on grass; its skull hit stays
	[184] = {fx = {lich_soul_drain = "sv_death_lifesteal"}}, -- Life Siphon: today's drain is a thin dark hook on the target
	[197] = {fx = {bone_burst = "sv_death_bone_shatter"}}, -- Bone Shrapnel: today's hit is a dark smudge, lost on grass
}

-- a spell of one element that is given a piece of another, with the reason (server/tests/spell_vfx_test.lua holds every other
-- spell to its element; tools/ci/check_spell_fx.py measures with the gate off, so these rows cannot live in spell_fx_allow.csv)
C.allow = {}

-- the piece for a spell id, kind and asked name, or nil (pure: no gate, no ids)
function C.pick(spellId, kind, name)
	local s = spellId and C.spells[spellId]
	local k = s and s[kind]
	return k and type(name) == "string" and k[name] or nil
end

-- the gate on and the ids known: the generated table is merged once into ChaosVfx / ChaosVfxMissile
function C.live()
	if not C.ON then
		return false
	end
	if C.loaded == nil then
		C.loaded = false
		if not ChaosSpellVfxIds and dofile then
			pcall(dofile, "data/lib/chaos_spell_vfx_ids.lua")
		end
		local I = ChaosSpellVfxIds
		if I and ChaosVfx and ChaosVfxMissile then
			for name, e in pairs(I.effects) do
				ChaosVfx[name] = {id = e.id, dx = e.dx, dy = e.dy, ms = e.ms}
			end
			for name, e in pairs(I.missiles) do
				ChaosVfxMissile[name] = {id = e.id, dx = e.dx, dy = e.dy}
			end
			C.loaded = true
		end
	end
	return C.loaded
end

-- the piece spell `spellId` sends in place of `name` of `kind`, or nil (gate off, no entry, the id not known)
function C.swapFor(spellId, kind, name)
	local alt = C.pick(spellId, kind, name)
	if not alt or not C.live() then
		return nil
	end
	if kind == "missile" then
		return ChaosVfxMissile[alt] and alt or nil
	end
	return ChaosVfx[alt] and alt or nil
end

ChaosSpellVfx = C
return C
