-- Spell showcase pack, the pure part (O692, TEST ONLY: server/README.md "Spell showcase video (O692)").
-- tools/ci/unity_live_check.sh with UL_SPELL_SHOWCASE=1 copies spell_showcase.lua and this file into data/scripts of the run's own server
-- (never into the install, never into the repository's data). They keep a pack of weak monsters round a showcase character so that the
-- spells of the film always have a target: no health or damage of any monster or player is changed, a monster that dies is replaced.
-- Plain Lua 5.1 / LuaJIT / 5.3; tests/spell_showcase_test.lua.

ShowcaseCore = ShowcaseCore or {}
local C = ShowcaseCore

C.PREFIX = "Showcase "       -- a showcase character is named "Showcase Elementalist" (letters only)
C.WANT = 6                   -- monsters kept round the character
C.RADIUS = 5                 -- tiles: a monster this near counts
C.INTERVAL_MS = 1500         -- how often the pack is looked at
C.MAX_PER_TICK = 3           -- at most this many are made in one look
C.MONSTERS = {"Troll", "Rotworm", "Rat"}  -- the first one the server knows is used (stock names)

-- the ring of offsets round a character, nearest first: the "around" spells of the film hit the first eight
C.OFFSETS = {
	{1, 0}, {-1, 0}, {0, 1}, {0, -1}, {1, 1}, {-1, -1}, {1, -1}, {-1, 1},
	{2, 0}, {-2, 0}, {0, 2}, {0, -2}, {2, 1}, {-2, -1}, {1, 2}, {-1, -2},
	{3, 0}, {-3, 0}, {0, 3}, {0, -3},
}

-- a name that gets a pack: "Showcase " and letters
function C.isShowcase(name)
	return type(name) == "string" and name:sub(1, #C.PREFIX) == C.PREFIX and name:match("^[%a ]+$") ~= nil
end

-- how many monsters to make now: up to the wanted count, at most MAX_PER_TICK a look
function C.needed(alive)
	local missing = C.WANT - (tonumber(alive) or 0)
	if missing <= 0 then
		return 0
	end
	return math.min(missing, C.MAX_PER_TICK)
end

-- the free offsets in the order to try, skipping those a monster already stands on. occupied: {["dx,dy"] = true}
function C.freeOffsets(occupied)
	local out = {}
	for _, o in ipairs(C.OFFSETS) do
		if not (occupied and occupied[o[1] .. "," .. o[2]]) then
			out[#out + 1] = o
		end
	end
	return out
end

return C
