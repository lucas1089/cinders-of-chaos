-- wrapchain_core.lua: hook a public function of another script once, even when several of our scripts hook the same
-- function and the hooks are installed again every minute (after a /reload of the wrapped script). Used by records,
-- season, season_journey, guild, mentor, telemetry, discord, chronicle and memorial; tests: server/tests/telemetry_test.lua
-- server/tests/wrapchain_test.lua and server/tests/season_journey_test.lua (records + journey). Lua 5.1 / LuaJIT and Lua 5.3.
--
--   ChaosWrapChain.wrap(tbl, name, flag, after, log, opts) -> true when it hooked now (or put the hooks back on top)
--     tbl[name] keeps running as before; after(results, ...) runs behind it, guarded by pcall (results.n, results[i]).
--     One dispatcher per tbl[name] runs every flag's hook once per call, in the order they were added. A second call
--     with a flag already there changes nothing. When tbl[name] is no longer our dispatcher (a /reload of the wrapped
--     script, or a wrapper of some other script put on top), a new dispatcher goes on top with the same hooks and the
--     old one only passes calls through, so no hook ever runs twice.
--     opts.outer: this hook skips calls made while another call of the same function is running (nested calls).
--   ChaosWrapChain.has(fn, flag) -> true when fn is a live dispatcher with that flag

ChaosWrapChain = ChaosWrapChain or {}
local W = ChaosWrapChain
W.made = W.made or setmetatable({}, {__mode = "k"}) -- dispatcher -> its state
W.reg = W.reg or setmetatable({}, {__mode = "k"}) -- tbl -> {name -> live state}

local unpack = unpack or table.unpack

local function pack(...)
	return {n = select("#", ...), ...}
end

function W.has(fn, flag)
	local st = W.made[fn]
	return st ~= nil and not st.retired and st.hooks[flag] ~= nil
end

local function newDispatcher(tbl, name, inner, hooks, order)
	local st = {hooks = hooks, order = order, depth = 0, inner = inner}
	local dispatcher = function(...)
		if st.retired then
			return inner(...)
		end
		st.depth = st.depth + 1
		local res = pack(pcall(inner, ...))
		st.depth = st.depth - 1
		if not res[1] then
			error(res[2], 0)
		end
		local out = {n = res.n - 1}
		for i = 2, res.n do
			out[i - 1] = res[i]
		end
		for _, flag in ipairs(st.order) do
			local h = st.hooks[flag]
			if h and not (h.outer and st.depth > 0) then
				local ok, err = pcall(h.after, out, ...)
				if not ok and h.log then
					h.log(tostring(name) .. " hook " .. tostring(flag) .. ": " .. tostring(err))
				end
			end
		end
		return unpack(out, 1, out.n)
	end
	st.dispatcher = dispatcher
	W.made[dispatcher] = st
	return st
end

function W.wrap(tbl, name, flag, after, log, opts)
	if type(tbl) ~= "table" or type(tbl[name]) ~= "function" or type(after) ~= "function" then
		return false
	end
	local byName = W.reg[tbl]
	if not byName then
		byName = {}
		W.reg[tbl] = byName
	end
	local st = byName[name]
	local changed = false
	if not st or st.retired or tbl[name] ~= st.dispatcher then
		local hooks, order = {}, {}
		if st then
			st.retired = true -- a reload or another wrapper on top: the old dispatcher only passes calls through
			hooks, order = st.hooks, st.order
		end
		st = newDispatcher(tbl, name, tbl[name], hooks, order)
		byName[name] = st
		tbl[name] = st.dispatcher
		changed = true
	end
	if not st.hooks[flag] then
		st.hooks[flag] = {after = after, log = log, outer = opts and opts.outer or false}
		st.order[#st.order + 1] = flag
		changed = true
	end
	return changed
end

return W
