-- levelwings_core.lua: the rules of the level-up wings (client game_levelwings, extended opcode
-- ChaosOpcodes.levelWings = 191; the glue is levelwings.lua). Pure Lua, no engine calls; tests/levelwings_test.lua.
--
-- When a character gains a level, every player who sees it is told to play the wings on that creature:
--   server -> client  play {id = creature id, lv = new level, n = levels gained}
-- Throttles (levelwings_config.lua): per character (one play per playerCooldownMs), per viewer (viewerMax per
-- viewerWindowMs) and for the whole server (globalMax per globalWindowMs). A dropped play costs nothing: the stock
-- level-up text and effect are the engine's and always show.
-- Lua 5.1 / LuaJIT and 5.3.

ChaosLevelWings = ChaosLevelWings or {}
local L = ChaosLevelWings

-- a fresh throttle state
function L.newState()
	return {last = {}, viewers = {}, global = {start = nil, count = 0}, prunedAt = nil}
end

-- the message for a level gain, or nil when nothing was gained (a level lost on death, or no id)
function L.payload(creatureId, oldLevel, newLevel)
	creatureId, oldLevel, newLevel = tonumber(creatureId), tonumber(oldLevel), tonumber(newLevel)
	if not creatureId or creatureId <= 0 or not oldLevel or not newLevel or newLevel <= oldLevel then
		return nil
	end
	return {id = creatureId, lv = newLevel, n = newLevel - oldLevel}
end

-- a fixed window counter: true (and counted) while the window has room
local function take(slot, windowMs, max, now)
	if not slot.start or now - slot.start >= windowMs or now < slot.start then
		slot.start, slot.count = now, 0
	end
	if slot.count >= max then
		return false
	end
	slot.count = slot.count + 1
	return true
end

-- true when this character may play now (and records it)
function L.allowSource(st, cfg, pid, now)
	local last = st.last[pid]
	if last and now >= last and now - last < (cfg.playerCooldownMs or 0) then
		return false
	end
	st.last[pid] = now
	return true
end

-- true when the server-wide budget has room (and counts one)
function L.allowGlobal(st, cfg, now)
	return take(st.global, cfg.globalWindowMs or 1000, cfg.globalMax or 40, now)
end

-- true when this viewer may be sent one more (and counts it)
function L.allowViewer(st, cfg, vid, now)
	local slot = st.viewers[vid]
	if not slot then
		slot = {start = nil, count = 0}
		st.viewers[vid] = slot
	end
	return take(slot, cfg.viewerWindowMs or 1000, cfg.viewerMax or 3, now)
end

-- the decision for one level gain: payload or nil, reason. Checks in order: enabled, a gain, the character's
-- cooldown, the server budget. The cooldown is only spent when the play goes out.
function L.decide(st, cfg, pid, oldLevel, newLevel, now)
	if not cfg.enabled then
		return nil, "disabled"
	end
	local p = L.payload(pid, oldLevel, newLevel)
	if not p then
		return nil, "no gain"
	end
	local last = st.last[pid]
	if last and now >= last and now - last < (cfg.playerCooldownMs or 0) then
		return nil, "cooldown"
	end
	if not L.allowGlobal(st, cfg, now) then
		return nil, "busy"
	end
	L.allowSource(st, cfg, pid, now)
	return p, nil
end

-- the viewers (ids) that get this play, in order, each within its own budget
function L.recipients(st, cfg, viewerIds, now)
	local out, seen = {}, {}
	for _, vid in ipairs(viewerIds or {}) do
		if not seen[vid] then
			seen[vid] = true
			if L.allowViewer(st, cfg, vid, now) then
				out[#out + 1] = vid
			end
		end
	end
	return out
end

-- a character or viewer left: drop its entries
function L.forget(st, id)
	st.last[id] = nil
	st.viewers[id] = nil
end

-- drop entries older than cfg.pruneAfterMs (at most once per cfg.pruneEveryMs); returns how many went
function L.prune(st, cfg, now)
	local every = cfg.pruneEveryMs or 30000
	if st.prunedAt and now >= st.prunedAt and now - st.prunedAt < every then
		return 0
	end
	st.prunedAt = now
	local age, n = cfg.pruneAfterMs or 60000, 0
	for id, t in pairs(st.last) do
		if now - t >= age or now < t then
			st.last[id] = nil
			n = n + 1
		end
	end
	for id, slot in pairs(st.viewers) do
		if not slot.start or now - slot.start >= age or now < slot.start then
			st.viewers[id] = nil
			n = n + 1
		end
	end
	return n
end

return L
