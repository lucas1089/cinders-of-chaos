-- idlehall_core.lua: the Idle Hall's rules, no engine calls (idlehall.lua is the glue; tests: server/tests/idlehall_test.lua;
-- numbers: idlehall_config.lua; overview: server/README.md "Idle Hall"). Lua 5.1 / LuaJIT and Lua 5.3.
--
--   K.newState(now)                   the idle record of one online character (times in ms)
--   K.touch(st, now)                  an action of the player: the idle time starts again, the warning is forgotten
--   K.posKey(pos)                     one number per tile
--   K.sample(st, key, dir, now, pushedKey) -> "moved" | "turned" | "pushed" | nil
--                                     the sampler's look at the tile and direction; a new tile that someone else pushed
--                                     the character onto (pushedKey) is no action
--   K.engineIdle(st, now, idleMs)     the engine's own idle time (when it has Player.getIdleTime): a newer action counts
--   K.due(cfg, st, now) -> "warn" | "move" | nil
--   K.step(cfg, st, now, look) -> action, reason
--                                     look() -> {exempt = reason | nil, zone = bool, zoneReason}; called only when due.
--                                     "warn": the warning is due (state marked, the move comes warnSeconds later at the
--                                     earliest); "move": move now (call K.moved after the teleport); nil, reason: nothing
--                                     (reason = why a due character was left alone: it is checked again after
--                                     recheckSeconds)
--   K.moved(st, now)                  after the move: a fresh start in the hall
--   K.townZone(cfg, pos, tile, temples) -> bool, reason   tile = {pz = bool, house = bool}
--   K.temples(cfg, towns)             towns = {{id, pos}} -> the temple positions the town rule uses
--   K.exempt(f) -> reason | nil       f = {staff, instance, training}
--   K.opcodeSet(cfg, opcodes)         activityOpcodes (names) -> {[number] = true} of the names ChaosOpcodes knows
--   K.slotPos(at, off)                the world tile of an offset from the hall's origin
--   K.warnText(cfg) -> key, args      K.movedText(cfg) -> key, args      K.signText() (both languages)
--   K.validate(cfg) -> {problems}

ChaosIdleHallCore = ChaosIdleHallCore or {}
local K = ChaosIdleHallCore

function K.idleMs(cfg)
	return math.floor((tonumber(cfg.idleMinutes) or 10) * 60000)
end

function K.warnMs(cfg)
	return math.floor((tonumber(cfg.warnSeconds) or 60) * 1000)
end

function K.newState(now)
	return {at = now, warned = false, nextCheck = 0, key = nil, dir = nil}
end

function K.touch(st, now)
	st.at = now
	st.warned = false
	st.nextCheck = 0
end

function K.posKey(pos)
	if type(pos) ~= "table" then
		return nil
	end
	return ((tonumber(pos.z) or 0) * 65536 + (tonumber(pos.y) or 0)) * 65536 + (tonumber(pos.x) or 0)
end

function K.sample(st, key, dir, now, pushedKey)
	if st.key == nil then
		st.key, st.dir = key, dir
		return nil
	end
	if key ~= st.key then
		st.key, st.dir = key, dir
		if pushedKey ~= nil and key == pushedKey then
			return "pushed"
		end
		K.touch(st, now)
		return "moved"
	end
	if dir ~= st.dir then
		st.dir = dir
		K.touch(st, now)
		return "turned"
	end
	return nil
end

function K.engineIdle(st, now, idleMs)
	idleMs = tonumber(idleMs)
	if not idleMs or idleMs < 0 then
		return false
	end
	local at = now - idleMs
	if at > st.at then
		K.touch(st, at)
		return true
	end
	return false
end

function K.due(cfg, st, now)
	if st.nextCheck and now < st.nextCheck then
		return nil
	end
	local idle, idleMs, warnMs = now - st.at, K.idleMs(cfg), K.warnMs(cfg)
	if idle >= idleMs then
		return st.warned and "move" or "warn"
	end
	if not st.warned and idle >= idleMs - warnMs then
		return "warn"
	end
	return nil
end

function K.step(cfg, st, now, look)
	local action = K.due(cfg, st, now)
	if not action then
		return nil
	end
	local f = look() or {}
	local reason = f.exempt or (not f.zone and (f.zoneReason or "away")) or nil
	if reason then
		st.nextCheck = now + math.floor((tonumber(cfg.recheckSeconds) or 60) * 1000)
		return nil, reason
	end
	if action == "warn" then
		st.warned = true
		-- the move comes warnSeconds after the warning at the earliest
		local least = now - (K.idleMs(cfg) - K.warnMs(cfg))
		if st.at < least then
			st.at = least
		end
	end
	return action
end

function K.moved(st, now)
	K.touch(st, now)
	st.key, st.dir = nil, nil
end

function K.inBox(pos, box)
	local a, b = box and (box.from or box[1]), box and (box.to or box[2])
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	local function lo(k, i) return math.min(tonumber(a[k] or a[i]) or 0, tonumber(b[k] or b[i]) or 0) end
	local function hi(k, i) return math.max(tonumber(a[k] or a[i]) or 0, tonumber(b[k] or b[i]) or 0) end
	return pos.x >= lo("x", 1) and pos.x <= hi("x", 1) and pos.y >= lo("y", 2) and pos.y <= hi("y", 2)
		and pos.z >= lo("z", 3) and pos.z <= hi("z", 3)
end

function K.townZone(cfg, pos, tile, temples)
	if type(pos) ~= "table" or not tile or not tile.pz then
		return false, "nopz"
	end
	if tile.house then
		return false, "house"
	end
	local town = cfg.town or {}
	for _, box in ipairs(town.exclude or {}) do
		if K.inBox(pos, box) then
			return false, "excluded"
		end
	end
	for _, box in ipairs(town.include or {}) do
		if K.inBox(pos, box) then
			return true, "included"
		end
	end
	local r, floors = tonumber(town.radius) or 60, tonumber(town.floors) or 2
	for _, t in ipairs(temples or {}) do
		if math.abs(pos.x - t.x) <= r and math.abs(pos.y - t.y) <= r and math.abs(pos.z - t.z) <= floors then
			return true, "town"
		end
	end
	return false, "away"
end

function K.temples(cfg, towns)
	local only
	if type(cfg.town) == "table" and type(cfg.town.townIds) == "table" then
		only = {}
		for _, id in ipairs(cfg.town.townIds) do
			only[id] = true
		end
	end
	local out = {}
	for _, t in ipairs(towns or {}) do
		if t.pos and (not only or only[t.id]) then
			out[#out + 1] = {x = t.pos.x, y = t.pos.y, z = t.pos.z}
		end
	end
	return out
end

function K.exempt(f)
	if f.staff then
		return "staff"
	end
	if f.instance then
		return "instance"
	end
	if f.training then
		return "training"
	end
	return nil
end

function K.opcodeSet(cfg, opcodes)
	local set = {}
	for _, name in ipairs(cfg.activityOpcodes or {}) do
		local n = opcodes and tonumber(opcodes[name])
		if n then
			set[n] = true
		end
	end
	return set
end

function K.slotPos(at, off)
	if type(at) ~= "table" or type(off) ~= "table" then
		return nil
	end
	return {x = at.x + (off[1] or 0), y = at.y + (off[2] or 0), z = at.z + (off[3] or 0)}
end

function K.warnText(cfg)
	local s = math.floor(tonumber(cfg.warnSeconds) or 60)
	if s == 60 then
		return "You are idle in town: you will be moved to the Idle Hall in 1 minute. Take a step to stay.", {}
	end
	return "You are idle in town: you will be moved to the Idle Hall in %d seconds. Take a step to stay.", {s}
end

function K.movedText(cfg)
	return "You stood idle in town for %d minutes and were moved to the Idle Hall. Its portal leads back to your temple.",
		{math.floor(tonumber(cfg.idleMinutes) or 10)}
end

function K.signText()
	return "The Idle Hall. Who stands idle in a town for a while is brought here, so the temples stay clear. Train on the "
		.. "dummies with exercise weapons or rest on the benches. The portal leads back to your temple.\n\n"
		.. "O Idle Hall. Quem fica parado numa cidade por um tempo é trazido para cá, para que os templos fiquem "
		.. "livres. Treine nos bonecos com armas de exercício ou descanse nos bancos. O portal leva de volta ao seu templo."
end

function K.validate(cfg)
	local bad = {}
	local function no(fmt, ...)
		bad[#bad + 1] = string.format(fmt, ...)
	end
	if not (tonumber(cfg.idleMinutes) and cfg.idleMinutes >= 2) then
		no("idleMinutes %s: at least 2", tostring(cfg.idleMinutes))
	end
	if not (tonumber(cfg.warnSeconds) and cfg.warnSeconds > 0 and cfg.warnSeconds * 1000 < K.idleMs(cfg)) then
		no("warnSeconds %s: above 0 and below idleMinutes", tostring(cfg.warnSeconds))
	end
	if not (tonumber(cfg.slices) and cfg.slices >= 1 and cfg.slices == math.floor(cfg.slices)) then
		no("slices %s: a whole number of at least 1", tostring(cfg.slices))
	elseif (cfg.thinkMs or 0) * cfg.slices > K.warnMs(cfg) / 2 then
		no("thinkMs x slices %d: each character must be sampled at least twice in the warning time", cfg.thinkMs * cfg.slices)
	end
	local aid = cfg.aid and cfg.aid.fixture
	if not (tonumber(aid) and aid >= 47910 and aid <= 47919) then
		no("aid.fixture %s: in the block 47910-47919", tostring(aid))
	end
	local hall = cfg.hall or {}
	if type(hall.at) ~= "table" or type(hall.arrival) ~= "table" then
		no("hall.at and hall.arrival are needed")
	end
	local seen = {}
	local function slot(kind, off)
		if type(off) ~= "table" or not tonumber(off[1]) or not tonumber(off[2]) then
			no("%s slot: {dx, dy}", kind)
			return
		end
		local k = off[1] .. "," .. off[2]
		if seen[k] then
			no("%s slot %s used twice", kind, k)
		end
		seen[k] = true
		if type(hall.arrival) == "table" and off[1] == hall.arrival[1] and off[2] == hall.arrival[2] then
			no("%s slot %s is the arrival", kind, k)
		end
	end
	local slots = cfg.slots or {}
	for _, off in ipairs(slots.dummies or {}) do
		slot("dummy", off)
	end
	for _, off in ipairs(slots.benches or {}) do
		slot("bench", off)
	end
	slot("sign", slots.sign)
	if #(slots.dummies or {}) < 2 then
		no("at least two dummies")
	end
	local items = cfg.items or {}
	if type(items.dummies) ~= "table" or #items.dummies == 0 or not tonumber(items.bench) or not tonumber(items.sign) then
		no("items: dummies (a list), bench and sign")
	end
	return bad
end
