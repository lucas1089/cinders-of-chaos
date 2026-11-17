-- Dungeons in closed test mode (O589; dungeons.lua, server/README.md "Dungeons in closed mode (O589)"; tests/dungeons_closed_test.lua).
-- Pure rules, no engine calls. A queue entry has a side ("tester" or "player"). A run takes the entries of ONE side and ONE
-- difficulty; testers only play among themselves and only with the switch on (testers_core.lua K.CLOSED_SYSTEMS.dungeon). The
-- testers' run is an instance of its own: its dungeon is the base map area as always (one run per dungeon), it is never ranked
-- (no board row, no record), and a player never waits behind a tester entry: players are served first.
--   K.sideRefusal(rules, closedOn, isTester)   side ("tester" | "player") and the refusal key ("closed-off" | "mixed" | nil)
--   K.pick(entries, o)                         the entries a run starts with (side, difficulty, joined): bucket per side and difficulty
--   K.guide(ctx)                               how a person plays a run: the next goal and what to do there (the bots' eyes)
-- Lua 5.1 / LuaJIT and 5.3 compatible.

ChaosDungeonsCore = ChaosDungeonsCore or {}
local K = ChaosDungeonsCore

local abs = math.abs

-- rules = ChaosTestersCore (nil when it is not loaded: a tester is then refused, a player is not)
function K.sideRefusal(rules, closedOn, isTester)
	if not isTester then
		return "player", nil
	end
	if not rules then
		return "tester", "closed-off"
	end
	return "tester", rules.joinRefusal("dungeon", closedOn, {true})
end

-- entries: list of {guid, difficulty, joined, side}; o = {size, soloWait, now, closedOn}
-- A bucket (one side, one difficulty) is ready when it holds `size` entries or its first entry waited soloWait seconds. Of the ready
-- buckets the one that waited longest goes. A tester bucket never starts while the mode is off or while a player entry is queued.
-- Returns difficulty, the entries of the bucket (the caller takes the first `size`), side; nil when nothing is ready.
function K.pick(entries, o)
	local playerWaits = false
	for _, e in ipairs(entries) do
		if (e.side or "player") == "player" then
			playerWaits = true
			break
		end
	end
	local buckets, order = {}, {}
	for _, e in ipairs(entries) do
		local side = e.side or "player"
		local key = side .. ":" .. tostring(e.difficulty)
		local b = buckets[key]
		if not b then
			b = {side = side, difficulty = e.difficulty, list = {}}
			buckets[key] = b
			order[#order + 1] = b
		end
		b.list[#b.list + 1] = e
	end
	local best
	for _, b in ipairs(order) do
		local allowed = b.side == "player" or (o.closedOn == true and not playerWaits)
		local ready = #b.list >= o.size or o.now - b.list[1].joined >= o.soloWait
		if allowed and ready and (not best or b.list[1].joined < best.list[1].joined) then
			best = b
		end
	end
	if not best then
		return nil
	end
	return best.difficulty, best.list, best.side
end

local function near(a, b, d)
	return a ~= nil and b ~= nil and a.z == b.z and abs(a.x - b.x) <= d and abs(a.y - b.y) <= d
end
K.near = near

-- How a person plays a dungeon run, one answer per look at the screen (the bots' `!tester dungeon`, nothing here moves anyone):
-- first the monsters, nearest first, until the boss is unlocked (cfg.progressNeeded percent dead), then the boss.
--   ctx = {pos = the player, percent = the kill counter, unlocked, ended, monster = {pos} the nearest live monster of the run or nil,
--          bossPos = the boss when it stands in the area or nil}
-- Returns {mode, goal, why, area}: "walk" (go to the goal), "fight" (stand, the goal is in reach), "wait" (nothing to go to: the exit
-- teleport after a clear, the boss room that opens, a hint that comes).
function K.guide(ctx)
	local out = {}
	if ctx.ended then
		out.mode, out.why = "wait", "the run is over: the exit teleports everyone out"
		return out
	end
	if not ctx.unlocked then
		out.area = "monsters"
		local m = ctx.monster
		if not m then
			out.mode, out.why = "wait", "no monster in sight: the stuck hint or the boss unlock comes"
			return out
		end
		out.goal = m.pos
		out.mode = near(ctx.pos, m.pos, 3) and "fight" or "walk"
		out.why = "the nearest monster"
		return out
	end
	out.area = "boss"
	if not ctx.bossPos then
		out.mode, out.why = "wait", "the boss is not there yet"
		return out
	end
	out.goal = ctx.bossPos
	out.mode = near(ctx.pos, ctx.bossPos, 4) and "fight" or "walk"
	out.why = "the boss"
	return out
end

return K
