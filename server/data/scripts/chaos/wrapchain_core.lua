-- wrapchain_core.lua: wrap a public function of another script once, even when several of our scripts wrap the same
-- function and the hooks are installed again every minute (after a /reload of the wrapped script). Used by
-- telemetry.lua and discord.lua; tests: server/tests/telemetry_test.lua. Lua 5.1 / LuaJIT and Lua 5.3.
--
--   ChaosWrapChain.wrap(tbl, name, flag, after, log) -> true when it wrapped now
--     tbl[name] keeps running as before; after(results, ...) runs behind it, guarded by pcall (results.n, results[i]).
--     The wrappers made here are remembered with their flag and the function they wrap, so a second call walks the
--     chain of our wrappers and finds the flag again, also under another of our wrappers. (A flag that only compares
--     with tbl[name] would wrap again whenever another wrapper sits on top, and the hook would run twice.)

ChaosWrapChain = ChaosWrapChain or {}
local W = ChaosWrapChain
W.made = W.made or setmetatable({}, {__mode = "k"}) -- wrapper -> {flag, inner}

local unpack = unpack or table.unpack

local function pack(...)
	return {n = select("#", ...), ...}
end

function W.has(fn, flag)
	local seen = 0
	while type(fn) == "function" and W.made[fn] and seen < 64 do
		if W.made[fn].flag == flag then
			return true
		end
		fn = W.made[fn].inner
		seen = seen + 1
	end
	return false
end

function W.wrap(tbl, name, flag, after, log)
	if type(tbl) ~= "table" or type(tbl[name]) ~= "function" or W.has(tbl[name], flag) then
		return false
	end
	local original = tbl[name]
	local wrapped = function(...)
		local res = pack(original(...))
		local ok, err = pcall(after, res, ...)
		if not ok and log then
			log(tostring(name) .. " hook: " .. tostring(err))
		end
		return unpack(res, 1, res.n)
	end
	W.made[wrapped] = {flag = flag, inner = original}
	tbl[name] = wrapped
	return true
end

return W
