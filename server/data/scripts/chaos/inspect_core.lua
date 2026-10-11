-- Inspect Player, the pure part (ChaosInspect): who may be inspected from where, the limits, how the answer is cut into
-- packets. No engine calls; data/scripts/chaos/inspect.lua reads the target and sends. Tested by
-- server/tests/inspect_test.lua. Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
-- What is public (and all that is ever sent): name, level, vocation and whether it is an ascended class, guild and
-- rank, achievement points, the best rift tier sealed, the highest Vocation Trial tier cleared, the outfit and the ten
-- equipment slots with their full tooltips. Nothing else: no health, mana, skills, passive tree, storages, gold,
-- containers. A character that switched "Allow others to inspect me" off (storage Chaos.storage.inspectOff, 1 = off,
-- default on) answers with a refusal.

ChaosInspect = ChaosInspect or {}
local I = ChaosInspect

I.config = {
	rangeX = 10, -- right-click inspect: the same floor, at most this many tiles away and in view
	rangeY = 10,
	cooldownMs = 1500, -- between two inspect requests of one player
	bucketSize = 6, -- and at most 6 at once, then one every 5 seconds
	bucketPerSecond = 0.2,
	packetBytes = 12000, -- equipment rows are sent in packets of at most about this many bytes of JSON
	nameLength = 29
}

I.SLOT_FIRST, I.SLOT_LAST = 1, 10 -- head .. the second ring slot (10, the old ammunition slot)

-- refusals: code -> text for the window. "notfound" is also the answer for a hidden staff member or a player in ghost mode,
-- so the window cannot be used to tell whether one is online.
I.REASONS = {
	notfound = "No player of that name is online.",
	private = "%s does not allow others to inspect them.",
	range = "%s is too far away to inspect.",
	rate = "You are inspecting too fast. Wait a moment.",
	self_hidden = "You cannot inspect that player.",
	bad = "Enter the name of a player."
}

function I.reasonText(code, name)
	local text = I.REASONS[code] or I.REASONS.notfound
	if text:find("%%s") then
		return text:format(name or "That player")
	end
	return text
end

-- a name typed by the player: letters, spaces, apostrophes, hyphens, up to 29 characters; nil when it is not one
function I.cleanName(name)
	if type(name) ~= "string" then
		return nil
	end
	name = name:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
	if #name < 2 or #name > I.config.nameLength or not name:match("^[%a][%a '%-]*$") then
		return nil
	end
	return name
end

-- may `viewer` inspect `target`? Plain tables so it can be tested:
--   target = {online, staff (a gamemaster or above, or a player flagged to stay hidden), ghost (invisible), off (privacy
--             switched off), same (viewer and target are the same character), dx, dy, sameFloor, visible}
--   how    = "range" (right-click: the creature the viewer clicked) or "name" (from the menu by name)
-- returns true, or false and a refusal code of I.REASONS
function I.allowed(target, how)
	if not target or not target.online then
		return false, "notfound"
	end
	if not target.same and (target.staff or target.ghost) then
		return false, "notfound"
	end
	if target.same then
		return true
	end
	if how == "range" then
		if not target.sameFloor or math.abs(target.dx or 99) > I.config.rangeX or math.abs(target.dy or 99) > I.config.rangeY
			or not target.visible then
			return false, "range"
		end
	end
	if target.off then
		return false, "private"
	end
	return true
end

-- request budget per player (token bucket, ms)
function I.allow(state, now)
	local size, rate = I.config.bucketSize, I.config.bucketPerSecond
	if state.at == nil then
		state.tokens, state.at = size, now
		state.last = nil
	end
	if state.last and now >= state.last and now - state.last < I.config.cooldownMs then
		return false
	end
	if now > state.at then
		state.tokens = math.min(size, state.tokens + (now - state.at) * rate / 1000)
	end
	state.at = now
	if state.tokens < 1 then
		return false
	end
	state.tokens = state.tokens - 1
	state.last = now
	return true
end

-- cuts rows (each {slot, tip}) into groups whose JSON size stays near the packet limit; sizeOf(row) -> bytes.
-- A row bigger than the limit goes alone.
function I.chunk(rows, sizeOf, limit)
	limit = limit or I.config.packetBytes
	local out, cur, size = {}, {}, 0
	for _, row in ipairs(rows) do
		local s = sizeOf(row)
		if #cur > 0 and size + s > limit then
			out[#out + 1] = cur
			cur, size = {}, 0
		end
		cur[#cur + 1] = row
		size = size + s
	end
	if #cur > 0 then
		out[#out + 1] = cur
	end
	return out
end

-- the outfit fields sent to the window
function I.outfitOf(o)
	o = o or {}
	local function n(v)
		return math.max(0, math.floor(tonumber(v) or 0))
	end
	return {type = n(o.lookType), head = n(o.lookHead), body = n(o.lookBody), legs = n(o.lookLegs), feet = n(o.lookFeet),
		addons = n(o.lookAddons), mount = n(o.lookMount)}
end

return I
