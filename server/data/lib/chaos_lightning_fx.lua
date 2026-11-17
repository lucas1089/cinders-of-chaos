-- chaos_lightning_fx.lua: the bolt from the sky, drawn by code (O614, client pair 73; our own art, in the sprite pair only,
-- client/tools/sprites/gen_lightning_fx.py). Owner 2026-11-17: "For the lightning falling from the sky, make the tool to
-- draw the lightning." Five effects at 5321..5325: three shapes of the bolt and two of a heavy bolt. Looks only: no damage,
-- no timing, no area changes.
--
-- Gate: config.lua `chaosClientPair` (README "Client pair guard") is 73 or more, read from the file at load (C.ON). A
-- client on pair 72 has no effect 5321+, so below 73 nothing here answers and every sender draws effect 458 as today.
--
-- What is swapped: the name `lightning_strike` (effect 458 of data/lib/chaos_vfx.lua, "energy: bolt from the sky"), at the
-- one door every named effect goes through, Vfx(). So whatever would have drawn 458 draws the new bolt, and a sender whose
-- name was changed before it reached Vfx() (a cosmetic skin, the pair 27 and 29 tables, the effects pass: Forked Storm
-- keeps the owner's donor strike) is not touched. A caller that passes `raw` gets 458.
--   C.swap(name)   the door of Vfx(): the three shapes in turn, so bolts that fall together do not look alike.
--   C.boss(name)   a boss strike asks before it calls Vfx (boss_mechanics.lua, uber.lua). A boss area draws its hit on
--                  every second tile, dozens at once, so one strike in C.heavyEvery is the heavy bolt (its two shapes in
--                  turn) and the others are the plain shapes: a storm of bolts with a few big ones, not a wall of light.
-- The senders are listed in C.senders for the docs and the test (server/README.md "Bolt from the sky (O614)").
-- The ids and send offsets are the generated data/lib/chaos_lightning_fx_ids.lua. Plain Lua, no engine call at load
-- (server/tests/lightning_fx_test.lua).

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

-- the name that is swapped (effect 458)
C.OLD = "lightning_strike"
-- the shapes, sent in turn
C.std = {"lf_bolt_a", "lf_bolt_b", "lf_bolt_c"}
C.heavy = {"lf_bolt_heavy_a", "lf_bolt_heavy_b"}

-- who names `lightning_strike` today: file (from server/) -> what it is, and which bolt it gets
C.senders = {
	["data/spells/chaos/sorcerer/cataclysm.lua"] = {what = "Doomtide: four bolts on a ring with the energy wave", bolt = "std"},
	["data/spells/chaos/sorcerer/glacial_doom.lua"] = {what = "Glacial Doom: four bolts on a ring with its energy wave", bolt = "std"},
	["data/spells/chaos/sorcerer/chain_lightning.lua"] = {what = "Forked Storm: each jump (the effects pass sends the owner's donor strike in its place, so it is not swapped)", bolt = "none"},
	["data/lib/chaos_pack_fx.lua"] = {what = "the energy snare burst (snare_energy), the energy strike of a rift modifier (rift_strike_energy)", bolt = "std"},
	["data/scripts/chaos/boss_mechanics_config.lua"] = {what = "Thalcyra's Storm Marks, Saga's Storm Verse: the hit on every second marked tile", bolt = "boss"},
	["data/scripts/chaos/uber_config.lua"] = {what = "Ascended Thalcyra: the hit of every pattern, on every second tile", bolt = "boss"},
}

-- the gate on and the ids known: the generated table is merged once into ChaosVfx
function C.live()
	if not C.ON then
		return false
	end
	if C.loaded == nil then
		C.loaded = false
		if not ChaosLightningFxIds and dofile then
			pcall(dofile, "data/lib/chaos_lightning_fx_ids.lua")
		end
		local I = ChaosLightningFxIds
		if I and ChaosVfx then
			for name, e in pairs(I.effects) do
				ChaosVfx[name] = {id = e.id, dx = e.dx, dy = e.dy, ms = e.ms}
			end
			C.loaded = true
		end
	end
	return C.loaded
end

-- of the strikes of a boss, one in this many is the heavy bolt
C.heavyEvery = 4

C.turn = {std = 0, heavy = 0, boss = 0}

local function nextOf(kind)
	local list = C[kind]
	for _ = 1, #list do
		C.turn[kind] = C.turn[kind] % #list + 1
		local name = list[C.turn[kind]]
		if ChaosVfx[name] then
			return name
		end
	end
	return nil
end

-- the name Vfx() sends in place of `name`: the next bolt when the gate is on and `name` is the old bolt, else `name`
function C.swap(name)
	if name ~= C.OLD or not C.live() then
		return name
	end
	return nextOf("std") or name
end

-- the same for a boss strike: the first of every C.heavyEvery is the next heavy bolt, the others the next plain one
function C.boss(name)
	if name ~= C.OLD or not C.live() then
		return name
	end
	C.turn.boss = C.turn.boss % math.max(1, C.heavyEvery) + 1
	return nextOf(C.turn.boss == 1 and "heavy" or "std") or name
end

ChaosLightningFx = C
return C
