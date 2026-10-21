-- The Haunted Harvest, the pure part (harvest_event.lua is the engine side; numbers in harvest_event_config.lua;
-- server/README.md "Haunted Harvest"). No engine calls: tests/harvest_event_test.lua runs it under LuaJIT and Lua 5.3.
--   K.inWindow(cfg, t)            is the calendar day of time t inside the window (wraps over the new year)
--   K.isOpen(cfg, t, force, on)   the event is open: the switch is on, then the forced state, else the window
--   K.forceOf(text)               "on" / "off" / "auto" -> the stored state (1, 2, 0), or nil
--   K.windowRange(cfg, t)         start and end time (inclusive days) of the window that holds t, else the next one
--   K.dayKey(t)                   yyyymmdd of time t
--   K.pumpkin(cfg, rng, given)    the harvest of a ripe pumpkin: {candy, wake = monster or nil, charm, capped}
--   K.grave(cfg, rng) / K.coffin(cfg, rng)   {candy, key, raise = {names}}
--   K.cauldron(cfg, rng)          {trick = {names}} or {candy}
--   K.circleAdd(count, cfg)       candles on the circle after one more, and whether it lights
--   K.bossPhase(cfg, before, after, done)   the phase (index of cfg.boss.phases) crossed by a hit, or nil
--   K.wardDamage(cfg, value)      the damage the King takes through the ward
--   K.charmPick(pool, owns, rng)  one pool entry the account does not own yet, or nil
--   K.offer(cfg, key) / K.trade(cfg, key, candy)   a shop offer by key / whether a character with `candy` may buy it
--   K.dynamicEntry(cfg, t, force) the runtime event entry of events_schedule.lua while the harvest is open
--   K.checkPlaces(places, kit)    the problems of the generated places file (a list of texts)
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosHarvestCore = ChaosHarvestCore or {}
local K = ChaosHarvestCore

local floor = math.floor

local function md(t)
	local d = os.date("*t", t)
	return d.month * 100 + d.day, d.year
end

function K.inWindow(cfg, t)
	local w = cfg.window
	if not w then
		return false
	end
	local now = md(t)
	local a, b = w.from.month * 100 + w.from.day, w.to.month * 100 + w.to.day
	if a <= b then
		return now >= a and now <= b
	end
	return now >= a or now <= b
end

function K.forceOf(text)
	text = tostring(text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if text == "on" or text == "open" then
		return 1
	elseif text == "off" or text == "shut" or text == "close" then
		return 2
	elseif text == "auto" or text == "window" then
		return 0
	end
	return nil
end

-- switchOn: ChaosHarvestArt.PAIR33; force: the global storage (1 open, 2 shut, else the window)
function K.isOpen(cfg, t, force, switchOn)
	if not switchOn or not cfg.enabled then
		return false
	end
	if force == 1 then
		return true
	elseif force == 2 then
		return false
	end
	return K.inWindow(cfg, t)
end

local function stamp(year, month, day, hour, min, sec)
	return os.time({year = year, month = month, day = day, hour = hour, min = min, sec = sec})
end

function K.windowRange(cfg, t)
	local w = cfg.window
	local _, year = md(t)
	local wraps = w.from.month * 100 + w.from.day > w.to.month * 100 + w.to.day
	for _, y in ipairs({year - 1, year, year + 1}) do
		local s = stamp(y, w.from.month, w.from.day, 0, 0, 0)
		local e = stamp(wraps and y + 1 or y, w.to.month, w.to.day, 23, 59, 59)
		if t <= e then
			return s, e
		end
	end
	return nil
end

function K.dayKey(t)
	local d = os.date("*t", t)
	return d.year * 10000 + d.month * 100 + d.day
end

local function roll(rng, range)
	return rng(range[1], range[2])
end

local function pct(rng, chance)
	return rng(1, 10000) <= floor(chance * 100 + 0.5)
end

local function pickAll(rng, names, range)
	local out = {}
	for _ = 1, roll(rng, range or {1, 1}) do
		out[#out + 1] = names[rng(1, #names)]
	end
	return out
end

-- given: hollow candy this character took from pumpkins today
function K.pumpkin(cfg, rng, given)
	local p = cfg.pumpkin
	local room = math.max(0, (p.dailyCap or 0) - (given or 0))
	local out = {candy = 0, capped = false, charm = false}
	if p.dailyCap and room <= 0 then
		out.capped = true
		return out
	end
	out.candy = math.min(roll(rng, p.candy), p.dailyCap and room or math.huge)
	if pct(rng, p.wakeChance or 0) then
		out.wake = p.wake[rng(1, #p.wake)]
	end
	out.charm = pct(rng, p.charmChance or 0)
	return out
end

local function dig(part, rng)
	local out = {candy = roll(rng, part.candy), key = part.keyChance ~= nil and pct(rng, part.keyChance), raise = {}}
	if pct(rng, part.raiseChance or 0) then
		out.raise = pickAll(rng, part.raise, part.raiseCount)
	end
	return out
end

function K.grave(cfg, rng)
	return dig(cfg.grave, rng)
end

function K.coffin(cfg, rng)
	local out = dig(cfg.coffin, rng)
	out.key = false
	return out
end

function K.cauldron(cfg, rng)
	local c = cfg.cauldron
	if pct(rng, c.trickChance or 0) then
		local n = rng(1, #c.trick)
		return {trick = {c.trick[n]}}
	end
	return {candy = roll(rng, c.candy)}
end

function K.circleAdd(count, cfg)
	local n = (count or 0) + 1
	local need = cfg.circle.candles or 3
	if n >= need then
		return 0, true
	end
	return n, false
end

-- before / after: health percent around a hit; done: {[index] = true} of the phases already run
function K.bossPhase(cfg, before, after, done)
	for i, p in ipairs(cfg.boss.phases) do
		if not (done and done[i]) and before > p and after <= p then
			return i
		end
	end
	return nil
end

function K.wardDamage(cfg, value)
	local cut = cfg.boss.wardPercent or 0
	return floor(value * (100 - cut) / 100 + 0.5)
end

-- owns(entry) -> true when the account has it; rng(a, b) -> integer
function K.charmPick(pool, owns, rng)
	local free = {}
	for _, e in ipairs(pool or {}) do
		if not owns(e) then
			free[#free + 1] = e
		end
	end
	if #free == 0 then
		return nil
	end
	return free[rng(1, #free)]
end

function K.offer(cfg, key)
	key = tostring(key or ""):lower()
	for i, o in ipairs(cfg.shop) do
		if o.key == key or tostring(i) == key then
			return o
		end
	end
	return nil
end

function K.trade(cfg, key, candy)
	local o = K.offer(cfg, key)
	if not o then
		return nil, "unknown"
	end
	if (candy or 0) < o.price then
		return nil, "candy", o
	end
	return o
end

-- the runtime event of events_schedule.lua (ChaosEvents.dynamic: the login lines and !events) while open: until the
-- window's last second, or two ticks ahead while a gamemaster holds it open (the tick renews it)
function K.dynamicEntry(cfg, t, force)
	local untilTime
	if force == 1 then
		untilTime = t + 2 * (cfg.tickSeconds or 60)
	else
		local _, e = K.windowRange(cfg, t)
		untilTime = e
	end
	return {id = "harvest", name = cfg.calendar.name, description = cfg.calendar.description, untilTime = untilTime}
end

-- the places file (gen_harvest_places.py) against the kit (data/lib/chaos_pack33_kit.lua): every id a kit id, every
-- mechanic list present, the seal 4 tiles, the circle 9
function K.checkPlaces(places, kit)
	local bad = {}
	local function need(cond, text)
		if not cond then
			bad[#bad + 1] = text
		end
	end
	need(type(places) == "table", "no places table")
	if type(places) ~= "table" then
		return bad
	end
	for _, k in ipairs({"surface", "catacombs"}) do
		need(places[k] and places[k].arrival, k .. ": no arrival")
	end
	need(places.seal and #places.seal.tiles == 4, "the seal needs 4 tiles")
	need(places.circle and #places.circle.tiles == 9 and places.circle.landing, "the circle needs 9 tiles and a landing")
	for _, k in ipairs({"pumpkins", "graves", "cauldrons", "bells", "coffins", "kingGraves"}) do
		need(type(places[k]) == "table" and #places[k] > 0, k .. ": empty")
	end
	for i, d in ipairs(places.decor or {}) do
		need(d[1] >= kit.first and d[1] <= kit.last, "decor " .. i .. ": id " .. tostring(d[1]) .. " is no kit id")
	end
	return bad
end

return K
