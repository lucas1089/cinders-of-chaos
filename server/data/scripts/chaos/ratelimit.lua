-- ratelimit.lua: per-player limits for client requests that cost the server real work (database reads, walking the
-- whole backpack, building big answers). The engine already kicks a connection that sends more than
-- maxPacketsPerSecond packets (config.lua), but within that limit one client could still ask for a database query on
-- every packet. Handlers call
--     if ChaosRateLimit and not ChaosRateLimit.allow(player, "stash.list", 500) then return end
-- (the `ChaosRateLimit and` guard keeps a handler working when this file is missing). A refused request is simply
-- dropped: the windows ask again on the next click, nothing is queued.
-- Pure logic in ChaosRateLimit.allowAt (tested in tests/ratelimit_test.lua); state is per player id, cleared at logout.

ChaosRateLimit = ChaosRateLimit or {}
local R = ChaosRateLimit
R.last = R.last or {} -- player id -> {key -> time in ms of the last allowed request}
R.keys = R.keys or {} -- player id -> number of keys in R.last[id]
R.maxKeys = 512 -- keys per player (every action of every module is far fewer)
R.maxKeyLength = 64

local function nowMs()
	return os.mtime and os.mtime() or os.time() * 1000
end

-- true when `key` was not allowed for this id in the last `intervalMs`; records the time when it is allowed
function R.allowAt(id, key, intervalMs, now)
	if type(id) ~= "number" or type(key) ~= "string" or #key > R.maxKeyLength then
		return false
	end
	local slots = R.last[id]
	if not slots then
		slots = {}
		R.last[id] = slots
	end
	local last = slots[key]
	-- keys are built from the client's action names ("bounty." .. action): a made-up action is a new key, so a
	-- client could grow this table until logout. Real keys are few; a player past maxKeys gets no new ones.
	if last == nil then
		local n = R.keys[id] or 0
		if n >= R.maxKeys then
			return false
		end
		R.keys[id] = n + 1
	end
	if last and now >= last and now - last < (intervalMs or 0) then
		return false
	end
	slots[key] = now
	return true
end

function R.allow(player, key, intervalMs)
	if not player then
		return false
	end
	return R.allowAt(player:getId(), key, intervalMs, nowMs())
end

function R.forget(id)
	R.last[id] = nil
	R.keys[id] = nil
end

if CreatureEvent then
	local login = CreatureEvent("ChaosRateLimitLogin")
	function login.onLogin(player)
		player:registerEvent("ChaosRateLimitLogout")
		return true
	end
	login:type("login")
	login:register()

	local logout = CreatureEvent("ChaosRateLimitLogout")
	function logout.onLogout(player)
		R.forget(player:getId())
		return true
	end
	logout:type("logout")
	logout:register()
end
