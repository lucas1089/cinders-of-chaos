-- Reward chest sparkle: pure logic (no engine API). reward_sparkle.lua drives it from one GlobalEvent; tests:
-- tests/reward_sparkle_test.lua. Numbers: reward_sparkle_config.lua.
--
-- A system that places a reward chest registers it with a key; the shared timer asks K.due for the chests to glint
-- this tick. An entry goes when its system removes it, when its `check` says the chest has nothing left to take, when
-- the chest item is gone (the engine's `exists` callback), or after cfg.maxAge seconds.
--   K.new()                                      -> state
--   K.add(state, cfg, key, pos, itemId, now, check)  register (or refresh) a chest; check() -> false ends the glint
--   K.remove(state, key)
--   K.due(state, cfg, now, exists)               -> {{key, pos, itemId}} to glint now; drops the finished entries
--   K.count(state)
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosRewardSparkleCore = ChaosRewardSparkleCore or {}
local K = ChaosRewardSparkleCore

function K.new()
	return {entries = {}, order = {}, seq = 0}
end

local function copyPos(p)
	return {x = p.x, y = p.y, z = p.z}
end

function K.add(state, cfg, key, pos, itemId, now, check)
	if key == nil or not pos or not itemId then
		return false
	end
	state.seq = state.seq + 1
	if not state.entries[key] then
		state.order[#state.order + 1] = key
	end
	state.entries[key] = {pos = copyPos(pos), itemId = itemId, since = now or 0, seq = state.seq, check = check}
	-- too many: the oldest go
	local limit = cfg and cfg.maxEntries or 200
	while #state.order > limit do
		local old = table.remove(state.order, 1)
		state.entries[old] = nil
	end
	return true
end

function K.remove(state, key)
	if state.entries[key] == nil then
		return false
	end
	state.entries[key] = nil
	for i = #state.order, 1, -1 do
		if state.order[i] == key then
			table.remove(state.order, i)
		end
	end
	return true
end

function K.count(state)
	return #state.order
end

function K.due(state, cfg, now, exists)
	local out, keep = {}, {}
	local maxAge = cfg and cfg.maxAge or 1800
	for _, key in ipairs(state.order) do
		local e = state.entries[key]
		local live = e ~= nil and (now - e.since) <= maxAge
		if live and e.check then
			local ok, res = pcall(e.check)
			live = ok and res ~= false and res ~= nil
		end
		if live and exists then
			local ok, res = pcall(exists, e.pos, e.itemId)
			live = ok and res and true or false
		end
		if live then
			keep[#keep + 1] = key
			out[#out + 1] = {key = key, pos = e.pos, itemId = e.itemId}
		else
			state.entries[key] = nil
		end
	end
	state.order = keep
	return out
end

return K
