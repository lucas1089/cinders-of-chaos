-- chaos_area_fx.lua: an area burst, beams, markers and a status effect of the purchased effect packs of pair 36 (O607, O609,
-- O613, client pair 73; the art is in the sprite pair only, client/tools/sprites/gen_area_fx.py, docs/CREDITS.md). The
-- owner approved the review O604: the beam spells draw balls on a line, and the pack has markers we lack. Looks only: no
-- damage, no timing, no area changes.
--
-- Gate: config.lua `chaosClientPair` (README "Client pair guard") is 73 or more, read from the file at load (C.ON). Below 73
-- the pair has blank effects at the refilled ids and no effect 5300+, so nothing here answers and every spell, boss and
-- event sends exactly what it sends today. The owner raises the record when pair 73 ships.
--
-- A. Area burst (C.spellBursts). O607 swapped five of our large bursts for pack ones in Vfx(), for every sender. The owner
--    saw them (O613, 2026-11-17): "the new area bursts are too weak", ours stay. So there is no swap by name any more:
--    the fire, blood, frost and holy bursts (638, 642, 644, 646), the boss hits and the boss deaths send our art again,
--    and the four pack bursts left the pair. One pack burst stays, the clock face of runes, for two spells only (the
--    owner: "the arcane big bursts of Veil of Whispers and Reality Rift"): the arcane nova 648 big_nova_arcane_7 that
--    Veil of Whispers (153) sends at the caster's feet, and each implosion of Tear in the Weave (231, the script
--    reality_rift.lua), which asks for arcane_circle: the large effects map that to 648 and pair 29 to its gravity
--    crush (775 weave_crush, which is what a client drew since pair 29). ChaosSpell.vfx (_common.lua) asks
--    C.spellBurst with the name the script sends, after the cosmetic skin and before every other swap, so a skin of the
--    spell still wins and no other sender of 648 changes. The clock is a disc of 7 tiles, as our nova is.
-- B. Beams (C.beams): a line spell of the attack kit draws one pack beam from the caster's tile toward the target in place
--    of an effect on every tile of the line (_attackkit.lua). The damage tiles are the line's, untouched.
--    O609: the pack's art is about 3 tiles long, and O607 drew a longer line as copies end to end; every copy showed its
--    own start flare and tip, so a long beam looked cut in pieces (the owner). Now the pair has ONE effect per beam,
--    heading and line length the spells use (C.ids.lengths: one start, the body run on, one tip on the last tile of the
--    line), and C.beam answers with that one. The chain of copies stays for two cases only: a length with no variant,
--    and a viewer who cannot draw the one piece. The client draws an effect from the far corner of its picture, and a
--    player gets an effect only when that tile is in its view (9 tiles east, 7 south): a player standing behind the
--    caster of a long beam east or south would get nothing, so that player alone gets the chain (C.sendBeam).
--    O613: Eclipse Edge (155) has no beam any more (a blood stream is no blade): it draws its line as before O607.
-- C. Markers (C.marks): a lock over a gate that refuses a player (chronicle.lua, areagen.lua), a quest marker over the loot
--    bag that holds a main quest item (mainquest.lua); sent to that player only. Skull, checkpoint crystal and hand are in
--    the pair with no sender yet.
-- D. Status (C.status, O613): the pack's gravity press on a slowed creature, in place of our whirlwind (783 cond_slowed).
--    data/lib/chaos_pack29_vfx.lua asks C.statusName for the aura of a state, so every slow that holds the aura (the
--    spells' slows, the status word of a root) draws it. The whirlwind keeps its art for a pair below 73.
--
-- The ids, send offsets, beam reaches and beam lengths are the generated data/lib/chaos_area_fx_ids.lua. Plain Lua, no engine call at
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

-- A. [spell id] = {the effect name the spell's script sends (ChaosSpell.vfx) = the pack burst}: only for that spell
C.spellBursts = {
	[153] = {big_nova_arcane_7 = "ab_arcane_clock"},   -- Veil of Whispers: the arcane nova at the caster's feet
	[231] = {arcane_circle = "ab_arcane_clock"},       -- Tear in the Weave (reality_rift.lua): each implosion
}

-- B. [spell id] = the beam (a name of C.ids.beams); its element is the spell's
C.beams = {
	[118] = "mega_soul_chain",      -- Soulrend Beam (death, 6 tiles)
	[129] = "mega_sunbeam_lance",   -- Lance of Vigil (holy, 3 tiles)
	[151] = "mega_sunbeam_lance",   -- Dawnbreaker Shot (holy, 8 tiles)
}
-- mega_glacier_breath is in the pair with no sender: no class has an ice line spell
-- Eclipse Edge (155) had the blood stream in O607; the owner took it off (O613): a blade spell draws its line

-- C. the markers by use
C.marks = {
	locked = "mega_util_locked_marker",          -- a gate that refuses the player
	quest = "w_fx_quest_marker",                 -- a main quest item lies in this loot bag
	skull = "w_marker_skull",                    -- no sender yet
	checkpoint = "mega_util_checkpoint_crystal", -- no sender yet
	interact = "mega_util_interact_hand",        -- no sender yet
}

-- D. a state of data/lib/chaos_pack29_vfx.lua (C.auras there) -> the pack effect that stands in for its aura
C.status = {
	slowed = "mega_gravity_press",               -- in place of the whirlwind 783 cond_slowed
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

-- A. the burst spell `spellId` sends in place of `name` (the effect name its script asks for): the pack burst when the
-- gate is on and the pair has it, else nil
function C.spellBurst(spellId, name)
	local t = spellId and C.spellBursts[spellId]
	local alt = t and type(name) == "string" and t[name] or nil
	if not alt or not C.live() or not ChaosVfx[alt] then
		return nil
	end
	return alt
end

-- B. the chain of O607 for the beam of spell `spellId` along `dir` over a line of `length` tiles: copies of the pack's own
-- beam end to end, {{name = effect name, at = tiles from the caster}, ...}, or nil. Each copy has its own start and tip.
function C.chain(spellId, dir, length)
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

-- B. the beam of spell `spellId` along `dir` (0..7, the kit's headings) for a line of `length` tiles: ONE effect of that
-- length, {{name = effect name, at = 0, len = length}}; the chain when the pair has no variant of that length; nil (gate
-- off, no beam for the spell, a name the pair lacks)
function C.beam(spellId, dir, length)
	local base = spellId and C.beams[spellId]
	local d = DIRNAME[dir]
	if not base or not d or not C.live() then
		return nil
	end
	local len = tonumber(length)
	local byLen = len and C.ids.lengths and C.ids.lengths[base] and C.ids.lengths[base][math.floor(len)]
	local name = byLen and byLen[d]
	if name and ChaosVfx[name] then
		return {{name = name, at = 0, len = math.floor(len)}}
	end
	return C.chain(spellId, dir, length)
end

-- does a player standing on `from` get an effect sent to `pos` (the engine's view around a player: 8 tiles west, 9 east,
-- 6 north, 7 south, moved by the floor difference)
function C.sees(from, pos)
	local oz = from.z - pos.z
	return pos.x >= from.x - 8 + oz and pos.x <= from.x + 9 + oz and pos.y >= from.y - 6 + oz and pos.y <= from.y + 7 + oz
end

local function sendTo(pos, name, s, at, viewer)
	local e = ChaosVfx[name]
	if e then
		Position(pos.x + s[1] * at + e.dx, pos.y + s[2] * at + e.dy, pos.z):sendMagicEffect(e.id, viewer)
	end
end

-- B. draw the beam from `pos` (the caster's tile); true when it was drawn. A beam in one piece goes to every player
-- who sees its far corner; a player near the line who does not gets the chain, as before O609.
function C.sendBeam(pos, spellId, dir, length)
	local segs = pos and C.beam(spellId, dir, length)
	if not segs or not Vfx then
		return false
	end
	local s = STEP[dir]
	local one = #segs == 1 and ChaosVfx[segs[1].name]
	local viewers
	if one and Game and Game.getSpectators then
		local ok, list = pcall(Game.getSpectators, pos, true, true, 18, 18, 14, 14)
		viewers = ok and list or nil
	end
	if not viewers then
		for _, seg in ipairs(segs) do
			Vfx(Position(pos.x + s[1] * seg.at, pos.y + s[2] * seg.at, pos.z), seg.name, true)
		end
		return true
	end
	local far = {x = pos.x + one.dx, y = pos.y + one.dy, z = pos.z}
	local chain
	for _, viewer in ipairs(viewers) do
		if C.sees(viewer:getPosition(), far) then
			sendTo(pos, segs[1].name, s, 0, viewer)
		else
			chain = chain or C.chain(spellId, dir, length) or {}
			for _, seg in ipairs(chain) do
				sendTo(pos, seg.name, s, seg.at, viewer)
			end
		end
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

-- D. the effect name that draws `state` on a creature in place of its aura, or nil (gate off, no stand-in, not in the pair)
function C.statusName(state)
	local name = type(state) == "string" and C.status[state] or nil
	if not name or not C.live() or not ChaosVfx[name] then
		return nil
	end
	return name
end

ChaosAreaFx = C
return C
