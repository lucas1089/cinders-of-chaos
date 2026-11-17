-- chaos_area_fx.lua: area bursts, beams and markers of the purchased effect packs of pair 36 (O607, client pair 73; the art is
-- in the sprite pair only, client/tools/sprites/gen_area_fx.py, docs/CREDITS.md). The owner approved the review O604: five of
-- our area bursts are faint, the beam spells draw balls on a line, and the pack has markers we lack. Looks only: no damage,
-- no timing, no area changes.
--
-- Gate: config.lua `chaosClientPair` (README "Client pair guard") is 73 or more, read from the file at load (C.ON). Below 73
-- the pair has blank effects at the refilled ids and no effect 5300+, so nothing here answers and every spell, boss and
-- event sends exactly what it sends today. The owner raises the record when pair 73 ships.
--
-- A. Area bursts (C.names): the name of a faint burst of ours -> the pack burst that takes its place. The swap sits in
--    Vfx() of data/lib/chaos_vfx.lua, the one door every named effect goes through, so it covers the spells (the large
--    effect swap of chaos_big_fx.lua and the scripts that name a burst), the boss hits and telegraph hits of
--    boss_mechanics.lua, raids and guild bosses. The boss death effect is sent by id (deathfx.lua): C.swapId. The old ids
--    keep their art: a cosmetic skin, a pair below 73 and a caller that passes `raw` still draw them.
--    Size: a pack burst is sent on the centre tile of the area, as ours is. The blood sigil is 6 tiles wide and ours 9, so
--    a boss area wider than 7 tiles keeps ours (C.fits, ChaosBigFx.bossHit).
-- B. Beams (C.beams): a line spell of the attack kit draws one pack beam from the caster's tile toward the target in place
--    of an effect on every tile of the line (_attackkit.lua). The beam of a heading reaches `reach` tiles, so a longer line
--    is drawn as segments, end to end. The damage tiles are the line's, untouched.
-- C. Markers (C.marks): a lock over a gate that refuses a player (chronicle.lua, areagen.lua), a quest marker over the loot
--    bag that holds a main quest item (mainquest.lua); sent to that player only. Skull, checkpoint crystal and hand are in
--    the pair with no sender yet.
--
-- The ids, send offsets and beam reaches are the generated data/lib/chaos_area_fx_ids.lua. Plain Lua, no engine call at
-- load (server/tests/area_fx_test.lua).

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

-- A. our burst -> the pack burst (the element of both is the same: server/tests/area_fx_test.lua)
C.names = {
	big_shock_fire_7 = "ab_fire_rain",             -- 638: Doomtide, Colossus Fall, Falling Pyre, fire boss hits, fire boss deaths
	big_shock_blood_9 = "ab_blood_sigil",          -- 642: Judgment of Iron, the world boss enrage, physical boss hits
	donor_arcane_nova_695 = "ab_arcane_clock",     -- 4711: no sender names it today (README "Area bursts, beams and markers")
	big_nova_frost_7 = "area_whiteout",            -- 644: Primordial Squall
	big_nova_holy_7 = "area_radiant_repulse",      -- 646: Hammer of Ember Dawn, holy boss hits
}
-- the widest area (tiles across) a pack burst stands in for; none listed: any
C.maxSize = {ab_blood_sigil = 7}

-- B. [spell id] = the beam (a name of C.ids.beams); its element is the spell's
C.beams = {
	[118] = "mega_soul_chain",      -- Soulrend Beam (death, 6 tiles)
	[129] = "mega_sunbeam_lance",   -- Lance of Vigil (holy, 3 tiles)
	[151] = "mega_sunbeam_lance",   -- Dawnbreaker Shot (holy, 8 tiles)
	[155] = "mega_blood_siphon",    -- Eclipse Edge (physical, 5 tiles; its hit is a blood splash)
}
-- mega_glacier_breath is in the pair with no sender: no class has an ice line spell

-- C. the markers by use
C.marks = {
	locked = "mega_util_locked_marker",          -- a gate that refuses the player
	quest = "w_fx_quest_marker",                 -- a main quest item lies in this loot bag
	skull = "w_marker_skull",                    -- no sender yet
	checkpoint = "mega_util_checkpoint_crystal", -- no sender yet
	interact = "mega_util_interact_hand",        -- no sender yet
}

local DIRNAME = {[0] = "n", [1] = "e", [2] = "s", [3] = "w", [4] = "sw", [5] = "se", [6] = "nw", [7] = "ne"}
local STEP = {[0] = {0, -1}, [1] = {1, 0}, [2] = {0, 1}, [3] = {-1, 0}, [4] = {-1, 1}, [5] = {1, 1}, [6] = {-1, -1}, [7] = {1, -1}}
C.DIRNAME, C.STEP = DIRNAME, STEP

-- the gate on and the ids known: the new names are merged once into ChaosVfx (the refilled names are there already, from
-- chaos_pack36_fx_ids.lua, with the same ids and offsets)
function C.live()
	if not C.ON then
		return false
	end
	if C.loaded == nil then
		C.loaded = false
		if not ChaosAreaFxIds and dofile then
			pcall(dofile, "data/lib/chaos_area_fx_ids.lua")
		end
		local I = ChaosAreaFxIds
		if I and ChaosVfx then
			for name, e in pairs(I.effects) do
				if not ChaosVfx[name] then
					ChaosVfx[name] = {id = e.id, dx = e.dx, dy = e.dy, ms = e.ms}
				end
			end
			C.ids = I
			C.loaded = true
		end
	end
	return C.loaded
end

-- does the pack burst `alt` stand in on an area `size` tiles across (nil: unknown, a spell's own area)
function C.fits(alt, size)
	local max = C.maxSize[alt]
	return not (max and size and size > max)
end

-- A. the name to send in place of `name`: the pack burst when the gate is on and the pair has it, else `name` itself
function C.swap(name, size)
	local alt = type(name) == "string" and C.names[name] or nil
	if not alt or not C.live() or not ChaosVfx[alt] or not C.fits(alt, size) then
		return name
	end
	return alt
end

-- A. the same for a sender that holds an effect as {id, dx, dy} (deathfx.lua): the pack burst's entry, or `e` itself
function C.swapId(e)
	if type(e) ~= "table" or not e.id or not C.live() then
		return e
	end
	if C.byId == nil then
		C.byId = {}
		for name, alt in pairs(C.names) do
			local old = ChaosVfx[name]
			if old and ChaosVfx[alt] then
				C.byId[old.id] = ChaosVfx[alt]
			end
		end
	end
	return C.byId[e.id] or e
end

-- B. the segments of the beam of spell `spellId` along `dir` (0..7, the kit's headings) for a line of `length` tiles:
-- {{name = effect name, at = tiles from the caster}, ...}, or nil (gate off, no beam for the spell, a name the pair lacks)
function C.beam(spellId, dir, length)
	local base = spellId and C.beams[spellId]
	local d = DIRNAME[dir]
	if not base or not d or not C.live() then
		return nil
	end
	local name = base .. "_" .. d
	local reach = C.ids.beams[base] and C.ids.beams[base][d]
	if not reach or not ChaosVfx[name] then
		return nil
	end
	local n = math.max(1, math.floor((tonumber(length) or reach) / reach + 0.5))
	local out = {}
	for i = 1, n do
		out[i] = {name = name, at = (i - 1) * reach}
	end
	return out
end

-- B. draw the beam from `pos` (the caster's tile); true when it was drawn
function C.sendBeam(pos, spellId, dir, length)
	local segs = pos and C.beam(spellId, dir, length)
	if not segs or not Vfx then
		return false
	end
	local s = STEP[dir]
	for _, seg in ipairs(segs) do
		Vfx(Position(pos.x + s[1] * seg.at, pos.y + s[2] * seg.at, pos.z), seg.name, true)
	end
	return true
end

-- C. the effect entry of a marker use, or nil
function C.mark(use)
	local name = use and C.marks[use]
	if not name or not C.live() then
		return nil
	end
	return ChaosVfx[name]
end

-- C. show the marker of `use` on `pos` to `player` only (nil: to everyone who sees the tile); true when it was sent
function C.sendMark(pos, use, player)
	local e = pos and C.mark(use)
	if not e then
		return false
	end
	local ok = pcall(function()
		local p = Position(pos.x + e.dx, pos.y + e.dy, pos.z)
		if player then
			p:sendMagicEffect(e.id, player)
		else
			p:sendMagicEffect(e.id)
		end
	end)
	return ok
end

ChaosAreaFx = C
return C
