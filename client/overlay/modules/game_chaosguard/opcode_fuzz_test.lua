-- Run from the repo root: luajit client/overlay/modules/game_chaosguard/opcode_fuzz_test.lua (also lua5.3)
-- Protocol fuzzer, client side (the server side is server/tests/opcode_fuzz_test.lua). Loads every module under
-- client/overlay/modules against a mocked client API (widgets, g_game, g_ui, ... answer anything), runs its onLoad and
-- onGameStart, and feeds every extended opcode handler it registers, under a fixed seed:
--   * malformed, truncated and non-JSON buffers, deep nesting, huge strings and arrays
--   * every action the module knows plus unknown ones, msg.data and every field it reads missing or of the wrong
--     type (negative, fractional, inf, 2^53, huge strings, arrays, objects, booleans)
--   * chunked answers (Chaos.sendChunked: "S", "P", "E" parts) whole, with parts missing, repeated or out of order,
--     joined the way the base client's ProtocolGame does it
-- and checks that no handler raises a Lua error (also the ones a module catches and logs), and that every opcode a
-- module registers is the one server/README.md and chaos_constants.lua give it, taken by no other module.
-- FUZZ_VERBOSE=1 lists the handlers, the actions found and what the mock lacked.

local VERBOSE = os.getenv('FUZZ_VERBOSE') == '1'
if jit then
	jit.off() -- the instruction count hook (endless loops, see run) only fires in the interpreter
end
-- The client runs its modules on LuaJIT (base client CMake option LUAJIT, client/LINUX.md), where string.format turns
-- a fraction, inf or NaN given to %d / %i / %x / %X / %c / %o / %u into an integer; Lua 5.3 raises instead. Under 5.3
-- the modules get LuaJIT's behaviour, so this test reports what fails in the real client and not a 5.3 difference.
if math.type then
	local realFormat = string.format
	local unpackArgs = table.unpack
	string.format = function(fmt, ...)
		local ok, text = pcall(realFormat, fmt, ...)
		if ok or type(fmt) ~= 'string' then
			return ok and text or realFormat(fmt, ...)
		end
		local args, n = {...}, select('#', ...)
		local i = 0
		for conv in fmt:gmatch('%%[-+ #0]*%d*%.?%d*([%a%%])') do
			if conv ~= '%' then
				i = i + 1
				local v = args[i]
				if conv:find('[diouxXc]') and math.type(v) == 'float' then
					if v ~= v or v >= 2^63 or v < -2^63 then
						args[i] = math.mininteger
					else
						args[i] = v >= 0 and math.floor(v) or math.ceil(v)
					end
				end
			end
		end
		return realFormat(fmt, unpackArgs(args, 1, n))
	end
end
local realPrint = print
local checks = 0
local failures, failureSeen = {}, {}
local function failure(kind, who, where, detail)
	local key = kind .. '|' .. who .. '|' .. tostring(where)
	if failureSeen[key] then
		return
	end
	failureSeen[key] = true
	if type(detail) == 'function' then
		detail = detail()
	end
	failures[#failures + 1] = string.format('[%s] %s: %s\n      %s', kind, who, tostring(where), tostring(detail))
end
local function check(cond, kind, who, where, detail)
	checks = checks + 1
	if not cond then
		failure(kind, who, where, detail)
	end
end

-- fixed seed (Park-Miller: the same sequence in LuaJIT and Lua 5.3)
local seed = 20261013
local function rnd(n)
	seed = (seed * 16807) % 2147483647
	return seed % n + 1
end

-- JSON as the base client's json.lua behaves: decode errors on anything malformed, null is nil, 1e999 is inf;
-- encode errors on NaN / inf, sparse arrays, mixed keys
local json = {}
do
	local escapes = {['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t"}
	local function utf8char(c)
		if c < 0x80 then
			return string.char(c)
		elseif c < 0x800 then
			return string.char(0xC0 + math.floor(c / 64), 0x80 + c % 64)
		end
		return string.char(0xE0 + math.floor(c / 4096), 0x80 + math.floor(c / 64) % 64, 0x80 + c % 64)
	end
	local function fail(i, msg)
		error(string.format("%s at char %d", msg, i), 0)
	end
	local function skip(s, i)
		local _, e = s:find("^[ \n\r\t]*", i)
		return e + 1
	end
	local function str(s, i)
		local out, j = {}, i + 1
		while true do
			local k = s:find('["\\%c]', j)
			if not k then
				fail(i, "expected closing quote for string")
			end
			out[#out + 1] = s:sub(j, k - 1)
			local c = s:sub(k, k)
			if c == '"' then
				return table.concat(out), k + 1
			elseif c == "\\" then
				local e = s:sub(k + 1, k + 1)
				if e == "u" then
					local hex = s:match("^%x%x%x%x", k + 2)
					if not hex then
						fail(k, "invalid unicode escape in string")
					end
					out[#out + 1] = utf8char(tonumber(hex, 16))
					j = k + 6
				elseif escapes[e] then
					out[#out + 1] = escapes[e]
					j = k + 2
				else
					fail(k, "invalid escape char '" .. e .. "' in string")
				end
			else
				fail(k, "control character in string")
			end
		end
	end
	local value
	value = function(s, i)
		i = skip(s, i)
		local c = s:sub(i, i)
		if c == "{" then
			local t = {}
			i = skip(s, i + 1)
			if s:sub(i, i) == "}" then
				return t, i + 1
			end
			while true do
				i = skip(s, i)
				if s:sub(i, i) ~= '"' then
					fail(i, "expected string for key")
				end
				local k
				k, i = str(s, i)
				i = skip(s, i)
				if s:sub(i, i) ~= ":" then
					fail(i, "expected ':' after key")
				end
				t[k], i = value(s, i + 1)
				i = skip(s, i)
				local d = s:sub(i, i)
				i = i + 1
				if d == "}" then
					return t, i
				elseif d ~= "," then
					fail(i, "expected '}' or ','")
				end
			end
		elseif c == "[" then
			local t, n = {}, 1
			i = skip(s, i + 1)
			if s:sub(i, i) == "]" then
				return t, i + 1
			end
			while true do
				t[n], i = value(s, i)
				n = n + 1
				i = skip(s, i)
				local d = s:sub(i, i)
				i = i + 1
				if d == "]" then
					return t, i
				elseif d ~= "," then
					fail(i, "expected ']' or ','")
				end
			end
		elseif c == '"' then
			return str(s, i)
		end
		local lit = s:match("^[^ \n\r\t,%]}]+", i)
		if not lit then
			fail(i, "unexpected character '" .. c .. "'")
		elseif lit == "true" then
			return true, i + 4
		elseif lit == "false" then
			return false, i + 5
		elseif lit == "null" then
			return nil, i + 4
		end
		local n = tonumber(lit)
		if not n then
			fail(i, "invalid number '" .. lit .. "'")
		end
		return n, i + #lit
	end
	json.decodeString = function(s)
		if type(s) ~= "string" then
			error("expected argument of type string, got " .. type(s))
		end
		local v, i = value(s, 1)
		i = skip(s, i)
		if i <= #s then
			fail(i, "trailing garbage")
		end
		return v
	end

	local escOut = {['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r",
		["\t"] = "\\t"}
	local function escChar(c)
		return escOut[c] or string.format("\\u%04x", c:byte())
	end
	local out, n, stack -- the answer being built
	local huge, format, concat = math.huge, string.format, table.concat
	local encode
	encode = function(v)
		local t = type(v)
		if t == "string" then
			if v:find('[%c"\\]') then
				v = v:gsub('[%c"\\]', escChar)
			end
			n = n + 1
			out[n] = '"' .. v .. '"'
		elseif t == "number" then
			if v ~= v or v == huge or v == -huge then
				error("unexpected number value '" .. tostring(v) .. "'")
			end
			n = n + 1
			out[n] = format("%.14g", v)
		elseif t == "table" then
			if stack[v] then
				error("circular reference")
			end
			stack[v] = true
			if rawget(v, 1) ~= nil or next(v) == nil then
				local count = 0
				for k in pairs(v) do
					if type(k) ~= "number" then
						error("invalid table: mixed or invalid key types")
					end
					count = count + 1
				end
				if count ~= #v then
					error("invalid table: sparse array")
				end
				n = n + 1
				out[n] = "["
				for i = 1, count do
					if i > 1 then
						n = n + 1
						out[n] = ","
					end
					encode(v[i])
				end
				n = n + 1
				out[n] = "]"
			else
				n = n + 1
				out[n] = "{"
				local first = true
				for k, x in pairs(v) do
					if type(k) ~= "string" then
						error("invalid table: mixed or invalid key types")
					end
					if not first then
						n = n + 1
						out[n] = ","
					end
					first = false
					encode(k)
					n = n + 1
					out[n] = ":"
					encode(x)
				end
				n = n + 1
				out[n] = "}"
			end
			stack[v] = nil
		elseif v == nil then
			n = n + 1
			out[n] = "null"
		elseif t == "boolean" then
			n = n + 1
			out[n] = v and "true" or "false"
		else
			error("unexpected type '" .. t .. "'")
		end
	end
	json.encode = function(v)
		local saved = {out, n, stack} -- encode can be re-entered from a __tostring or a nested call
		out, n, stack = {}, 0, {}
		local ok, err = pcall(encode, v)
		local result = ok and concat(out, "", 1, n) or nil
		out, n, stack = saved[1], saved[2], saved[3]
		if not ok then
			error("json.lua: " .. tostring(err), 2)
		end
		return result
	end
end

-- ---------------------------------------------------------------- client mock
-- Everything the client API has is a stub: indexable (a field is another stub, cached so modules can store into
-- widgets), callable (a method's result depends on its name: is* false, get*Width 0, getText "", getChildren {}, ...),
-- and fine with arithmetic and concatenation. `activity` counts every use, to see whether a request did anything.
local activity = 0
local missing = {}
local stubMt = {}
local function stub(name)
	return setmetatable({__stub = name or '?'}, stubMt)
end
local trueIs = {isVisible = true, isOnline = true, isEnabled = true, isExplicitlyVisible = true}
local numberGet = {'Width', 'Height', 'X', 'Y', 'Count', 'Value', 'Percent', 'Opacity', 'Index', 'Level', 'Time', 'Margin',
	'Padding', 'Minimum', 'Maximum', 'Step', 'Spacing', 'Offset', 'Id', 'Health', 'Mana', 'Speed', 'Capacity', 'Millis',
	'Seconds', 'Experience', 'Soul', 'Stamina', 'Skull', 'Shield', 'Type', 'Top', 'Bottom', 'Left', 'Right', 'Range'}
local stringGet = {getText = true, getName = true, getTooltip = true, getDescription = true, getStyleName = true,
	getImageSource = true, getCharacterName = true, getWorldName = true, getDrawText = true}
local function result(name)
	if name:find('^is') or name:find('^has') or name:find('^can') then
		return trueIs[name] == true
	elseif stringGet[name] then
		return ''
	elseif name == 'getChildren' or name == 'getItems' or name == 'getChildrenByStyleName' or name == 'getCreatures' then
		return {}
	elseif name == 'getSize' then
		return {width = 0, height = 0}
	elseif name == 'getPosition' or name == 'getPoint' then
		return {x = 0, y = 0, z = 7}
	elseif name:find('Rect$') then
		return {x = 0, y = 0, width = 0, height = 0}
	elseif name:find('Dimension$') then
		return {width = 15, height = 11}
	elseif name == 'getAwareRange' then
		return {width = 8, height = 6, left = 8, right = 9, top = 6, bottom = 7}
	elseif name:find('Child') or name:find('Widget') or name:find('ById') or name:find('Parent') then
		return stub(name)
	elseif name:find('^get') then
		for _, suffix in ipairs(numberGet) do
			if name:sub(-#suffix) == suffix then
				return 0
			end
		end
	end
	return stub(name)
end
stubMt.__index = function(t, k)
	activity = activity + 1
	if type(k) ~= 'string' then
		return nil
	end
	local s = stub(k)
	rawset(t, k, s)
	return s
end
stubMt.__call = function(self, ...)
	activity = activity + 1
	return result(rawget(self, '__stub') or '?')
end
stubMt.__tostring = function() return 'stub' end
stubMt.__concat = function(a, b) return tostring(a) .. tostring(b) end
local function zero() return 0 end
stubMt.__add, stubMt.__sub, stubMt.__mul, stubMt.__div, stubMt.__mod, stubMt.__unm, stubMt.__pow = zero, zero, zero,
	zero, zero, zero, zero
stubMt.__len = zero
stubMt.__lt = function() return false end
stubMt.__le = function() return false end

local clock = 1790000000000
local queue = {}
local sentToServer = {}
local logged = {}
local registrations = {} -- {module, opcode, kind = 'ext' | 'json', fn}
local currentModule
local gameCallbacks = {}

local protocol = stub('protocol')
rawset(protocol, 'sendExtendedOpcode', function(_, op, s)
	activity = activity + 1
	sentToServer[#sentToServer + 1] = {op, s}
end)
rawset(protocol, 'sendExtendedJSONOpcode', function(_, op, t)
	activity = activity + 1
	sentToServer[#sentToServer + 1] = {op, json.encode(t)}
end)
local localPlayer = stub('localPlayer')
for k, v in pairs({getName = 'Fuzzer', getId = 268435457, getLevel = 8, getHealth = 185, getMaxHealth = 185,
	getMana = 35, getMaxMana = 35, getVocation = 1}) do
	rawset(localPlayer, k, function() activity = activity + 1; return v end)
end

local G = {} -- the mocked client globals; anything else is a stub
local function log(level)
	return function(text)
		activity = activity + 1
		logged[#logged + 1] = {level = level, text = tostring(text)}
	end
end
G.g_logger = {error = log('error'), warning = log('warning'), info = function() end, debug = function() end,
	fatal = log('fatal'), traceError = log('error')}
G.g_game = stub('g_game')
for k, v in pairs({isOnline = true, getProtocolGame = protocol, getLocalPlayer = localPlayer, getFeature = false,
	getClientVersion = 1098, getProtocolVersion = 1098, getCharacterName = 'Fuzzer', getWorldName = 'Chaos',
	isAttacking = false, isFollowing = false, getContainers = {}}) do
	rawset(G.g_game, k, function() activity = activity + 1; return v end)
end
G.g_clock = {millis = function() return clock end, seconds = function() return math.floor(clock / 1000) end,
	realMillis = function() return clock end, realSeconds = function() return math.floor(clock / 1000) end}
G.g_settings = stub('g_settings')
for k, v in pairs({getNumber = 0, getString = '', getBoolean = false, getNode = false, exists = false}) do
	rawset(G.g_settings, k, function() activity = activity + 1; return v end)
end
G.scheduleEvent = function(fn, delay)
	activity = activity + 1
	if type(fn) == 'function' then
		queue[#queue + 1] = fn
	end
	return stub('event')
end
G.addEvent = G.scheduleEvent
G.cycleEvent = function() activity = activity + 1; return stub('event') end
G.removeEvent = function() end
G.connect = function(object, callbacks)
	activity = activity + 1
	if object == G.g_game and type(callbacks) == 'table' then
		for name, fn in pairs(callbacks) do
			if type(fn) == 'function' then
				gameCallbacks[#gameCallbacks + 1] = {module = currentModule, name = name, fn = fn}
			end
		end
	end
end
G.disconnect = function() end
G.tr = function(s, ...)
	if select('#', ...) > 0 and type(s) == 'string' then
		local ok, text = pcall(string.format, s, ...)
		return ok and text or s
	end
	return s
end
G.ProtocolGame = {
	registerExtendedOpcode = function(op, fn)
		registrations[#registrations + 1] = {module = currentModule, opcode = op, kind = 'ext', fn = fn}
	end,
	registerExtendedJSONOpcode = function(op, fn)
		registrations[#registrations + 1] = {module = currentModule, opcode = op, kind = 'json', fn = fn}
	end,
	unregisterExtendedOpcode = function() end,
	unregisterExtendedJSONOpcode = function() end,
	registerOpcode = function() end,
	unregisterOpcode = function() end,
}
G.json = {encode = json.encode}
-- OTClient's additions to the Lua libraries
G.string = setmetatable({
	split = function(s, sep)
		local out = {}
		for part in tostring(s):gmatch('([^' .. (sep or ' '):gsub('%p', '%%%0') .. ']+)') do
			out[#out + 1] = part
		end
		return out
	end,
	trim = function(s) return (tostring(s):gsub('^%s+', ''):gsub('%s+$', '')) end,
	starts = function(s, p) return tostring(s):sub(1, #p) == p end,
	ends = function(s, p) return p == '' or tostring(s):sub(-#p) == p end,
}, {__index = string})
string.split, string.trim, string.starts, string.ends = G.string.split, G.string.trim, G.string.starts, G.string.ends
G.table = setmetatable({
	find = function(t, v) for k, x in pairs(t) do if x == v then return k end end end,
	contains = function(t, v) for _, x in pairs(t) do if x == v then return true end end return false end,
	size = function(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end,
	empty = function(t) return next(t) == nil end,
	equal = function(a, b) return a == b end,
	copy = function(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end,
}, {__index = table})
G.math = setmetatable({mod = math.fmod, round = function(x) return math.floor(x + 0.5) end}, {__index = math})
G.unpack = unpack or table.unpack

local function newEnv()
	local env = {}
	setmetatable(env, {__index = function(_, k)
		local v = G[k]
		if v ~= nil then
			return v
		end
		v = _G[k]
		if v ~= nil then
			return v
		end
		missing[k] = (missing[k] or 0) + 1
		local s = stub(k)
		rawset(env, k, s)
		return s
	end})
	env._G = env
	return env
end
local function loadIn(path, env)
	if setfenv then
		local f, err = loadfile(path)
		if f then
			setfenv(f, env)
		end
		return f, err
	end
	return loadfile(path, 't', env)
end
local function loadText(text, env)
	if setfenv then
		local f, err = loadstring(text)
		if f then
			setfenv(f, env)
		end
		return f, err
	end
	return load(text, 'onLoad', 't', env)
end

-- ---------------------------------------------------------------- where errors come from
local function traced(m)
	return {msg = tostring(m), tb = debug.traceback('', 2)}
end
local function locate(err)
	local first = err.msg:match('^([^:]*modules/[^:]+:%d+):')
	if first then
		return first
	end
	for line in err.tb:gmatch('[^\n]+') do
		local at = line:match('(modules/[%w_/%.]+:%d+):')
		if at and not at:find('opcode_fuzz_test', 1, true) then
			return at .. ' (' .. err.msg:sub(1, 80) .. ')'
		end
	end
	return 'mock: ' .. err.msg:sub(1, 120)
end
local function readFile(path)
	local h = io.open(path, 'r')
	if not h then
		return nil
	end
	local s = h:read('*a')
	h:close()
	return s
end

-- ---------------------------------------------------------------- load every module
local ROOT = 'client/overlay/modules/'
local moduleNames = {}
do
	local p = io.popen('ls ' .. ROOT .. ' | LC_ALL=C sort')
	for line in p:lines() do
		moduleNames[#moduleNames + 1] = line
	end
	p:close()
end
local sources = {} -- module -> all its scripts as one text
local function drain(who, label)
	local ran = 0
	while #queue > 0 and ran < 30 do
		local fn = table.remove(queue, 1)
		ran = ran + 1
		local ok, err = xpcall(fn, traced)
		if not ok then
			failure('error in scheduleEvent', who, locate(err), function() return label() .. '\n      ' .. err.msg end)
		end
	end
	queue = {}
end
for _, name in ipairs(moduleNames) do
	local dir = ROOT .. name .. '/'
	local otmod = readFile(dir .. name .. '.otmod')
	if otmod then
		currentModule = name
		local env = newEnv()
		local list = otmod:match('scripts:%s*%[([^%]]*)%]') or ''
		local texts = {}
		for script in list:gmatch('[^,%s]+') do
			local path = dir .. script .. (script:find('%.lua$') and '' or '.lua')
			texts[#texts + 1] = readFile(path) or ''
			local f, err = loadIn(path, env)
			if not f then
				failure('load', name, path, tostring(err))
			else
				local ok, e = xpcall(f, traced)
				if not ok then
					failure('load', name, locate(e), e.msg)
				end
			end
		end
		sources[name] = table.concat(texts, '\n')
		local onLoad = otmod:match('@onLoad:%s*([^\n]+)')
		if onLoad then
			local f = loadText(onLoad, env)
			local ok, e = xpcall(f or error, traced)
			if not ok then
				failure('onLoad', name, locate(e), e.msg)
			end
		end
		drain(name, function() return 'onLoad' end)
	end
end
-- the game starts: the modules that register their opcodes then
for _, cb in ipairs(gameCallbacks) do
	if cb.name == 'onGameStart' then
		currentModule = cb.module
		local ok, e = xpcall(cb.fn, traced)
		if not ok then
			failure('onGameStart', cb.module, locate(e), e.msg)
		end
		drain(cb.module, function() return 'onGameStart' end)
	end
end
currentModule = nil
queue = {}

-- ---------------------------------------------------------------- delivering a message
-- Through the client's own ProtocolGame:onExtendedOpcode as client/base-patches/0043 leaves it (its hunk carries the
-- function and the tables before it): a plain handler gets the buffer; a JSON handler gets the parts of a chunked
-- message joined ("S" start, "P" part, "E" end; anything else is a whole message) and decoded; a stray "P" / "E" is
-- dropped with a warning; each handler runs under pcall and an error in it is logged (which fails this test, see run).
-- A message that does not decode raises "Invalid data in extended JSON opcode": that is the client's own report.
local tokens, tokenN = {}, 0
local function copy(v, depth)
	depth = depth or 0
	if type(v) ~= 'table' or depth > 1 then
		return v
	end
	local t = {}
	for k, x in pairs(v) do
		t[k] = copy(x, depth + 1)
	end
	return t
end
local function token(t)
	tokenN = tokenN + 1
	local key = '\1fuzz' .. tokenN
	tokens[key] = t
	return key
end
local realDecode = json.decodeString
local decoded = {}
G.json.decode = function(buffer)
	activity = activity + 1
	local t = tokens[buffer]
	if t ~= nil then
		return copy(t)
	end
	local d = type(buffer) == 'string' and decoded[buffer]
	if not d then
		local ok, v = pcall(realDecode, buffer)
		d = {ok = ok, v = v}
		if type(buffer) == 'string' and #buffer < 70000 then
			decoded[buffer] = d
		end
	end
	if not d.ok then
		error(d.v, 2)
	end
	return copy(d.v)
end
local dispatch, plainCallbacks, jsonCallbacks
do
	local text = readFile('client/base-patches/0043-extended-json-stray-parts.patch') or ''
	local lines, inHunk, inFunction = {}, false, false
	for line in text:gmatch('([^\n]*)\n') do
		if line:find('^@@') then
			inHunk = true
		elseif inHunk and not inFunction or (inFunction and lines[#lines] ~= 'end') then
			local c = line:sub(1, 1)
			if c == ' ' or c == '+' then
				lines[#lines + 1] = line:sub(2)
				inFunction = inFunction or line:find('^.function ProtocolGame:onExtendedOpcode') ~= nil
			end
		end
	end
	lines[#lines + 1] = 'return extendedCallbacks, extendedJSONCallbacks'
	local env = setmetatable({ProtocolGame = {}}, {__index = function(_, k)
		if G[k] ~= nil then return G[k] end
		return _G[k]
	end})
	local f = loadText(table.concat(lines, '\n'), env)
	check(f ~= nil and inFunction, 'base patch 0043', 'client/base-patches', 'onExtendedOpcode',
		'the patch no longer carries ProtocolGame:onExtendedOpcode with its tables')
	if f then
		plainCallbacks, jsonCallbacks = f()
		dispatch = env.ProtocolGame.onExtendedOpcode
	end
end
local function deliver(reg, buffer)
	plainCallbacks[reg.opcode], jsonCallbacks[reg.opcode] = nil, nil
	if reg.kind == 'ext' then
		plainCallbacks[reg.opcode] = reg.fn
	else
		jsonCallbacks[reg.opcode] = reg.fn
	end
	local ok, err = pcall(dispatch, protocol, reg.opcode, buffer)
	if not ok and not tostring(err):find('Invalid data in extended JSON opcode', 1, true) then
		error(err, 0)
	end
end

local function who(reg)
	return reg.module .. ' (' .. reg.opcode .. ')'
end
local slow = {}
local function run(reg, buffers, label)
	logged, sentToServer, queue = {}, {}, {}
	if type(buffers) ~= 'table' then
		buffers = {buffers}
	end
	local t0 = os.clock()
	for _, buffer in ipairs(buffers) do
		checks = checks + 1
		-- a loop bounded by a number from the message must not run away: 20 million VM instructions is "endless"
		debug.sethook(function() error('endless loop: over 20 million instructions for one message', 2) end, '', 20000000)
		local ok, err = xpcall(function() return deliver(reg, buffer) end, traced)
		debug.sethook()
		if not ok then
			failure('error', who(reg), locate(err), function() return label() .. '\n      ' .. err.msg end)
		end
	end
	drain(who(reg), label)
	clock = clock + 1000
	if os.clock() - t0 > 0.25 then
		slow[#slow + 1] = who(reg) .. ' ' .. label()
	end
	for _, l in ipairs(logged) do
		local at = l.text:match('(modules/[%w_/%.]+:%d+):') or l.text:match('([%w_]+%.lua:%d+):')
		checks = checks + 1
		if at then
			failure('error caught by the module', who(reg), at, function() return label() .. '\n      ' .. l.text:sub(1, 200) end)
		end
	end
end

-- ---------------------------------------------------------------- bad values
local function nested(depth)
	local t = {}
	local cur = t
	for _ = 1, depth do
		cur[1] = {}
		cur = cur[1]
	end
	return t
end
local bigArray, bigMap = {}, {}
for i = 1, 5000 do
	bigArray[i] = i
end
for i = 1, 2000 do
	bigMap['k' .. i] = i
end
local HUGE = string.rep('A', 60000)
local garbage = {
	{'absent', nil}, {'true', true}, {'false', false}, {'0', 0}, {'-1', -1}, {'0.5', 0.5}, {'2^31', 2147483648},
	{'2^53', 9007199254740992}, {'1e308', 1e308}, {'inf', math.huge}, {'-inf', -math.huge}, {'empty string', ''},
	{"'abc'", 'abc'}, {"'1'", '1'}, {'60 KB string', HUGE}, {'nul byte', 'a\0b'}, {'format string', '%s%d%n%%'},
	{'empty table', {}}, {'array', {1, 2, 3}}, {'string array', {'a', 'b'}}, {'array with hole', {1, nil, 3}},
	{'object', {a = 1, id = 1}}, {'array of tables', {{}, {id = 1}}}, {'5000 entries', bigArray}, {'2000 keys', bigMap},
	{'deep 300', nested(300)},
}
local function pick(names)
	local set, out = {}, {}
	for n in names:gmatch('[^|]+') do
		set[n] = true
	end
	for _, g in ipairs(garbage) do
		if set[g[1]] then
			out[#out + 1] = g
		end
	end
	return out
end
local fieldGarbage = pick("absent|true|0|-1|0.5|2^53|inf|-inf|empty string|'abc'|60 KB string|empty table|array|" ..
	'object|5000 entries|deep 300')
local dataGarbage = pick("true|0|inf|'abc'|60 KB string|empty table|array|array with hole|5000 entries|2000 keys|" ..
	'deep 300|string array')
local rawBuffers = {'', ' ', '{', '}', '[', 'null', 'true', '0', '-1', '1e999', '"text"', '[]', '[1,2,3]', '{"action":',
	'{"action":"x"', '{"action":"x",}', "{'action':'x'}", '{"action":"\\u0000"}', '{"action":1}', '{"action":null}',
	'{"action":{}}', '{"action":[]}', '{"data":{}}', '{"action":"x","data":null}', '{"action":"x","data":"y"}',
	'{"action":"x","data":1e999}', string.rep('[', 3000) .. string.rep(']', 3000),
	'{"action":"' .. string.rep('x', 60000) .. '"}', string.rep('\255', 100), '\0\0\0', 'S{', 'P}', 'E',
	-- the plain text messages of some modules (energy shield, monk chi, buffs, the bank)
	'es:', 'es:x:y', 'es:-1:0', 'es:1e999:nan', 'chi:', 'chi:a:b:c', 'chi:-5:0:1e999', 'chi:1:2', ':::', '|||', '1|2|3',
	string.rep('9', 400), '-0', 'nan', 'inf'}
local rawChars = '{}[]",:0123456789.-eE truefalsnul\\|S'
local function randomRaw()
	local out = {}
	for i = 1, rnd(60) do
		local k = rnd(#rawChars)
		out[i] = rawChars:sub(k, k)
	end
	return table.concat(out)
end
local function describe(v, depth)
	depth = depth or 0
	local t = type(v)
	if t == 'string' then
		return #v > 40 and string.format('<string %d bytes>', #v) or string.format('%q', v)
	elseif t ~= 'table' then
		return tostring(v)
	elseif depth > 2 then
		return '{...}'
	end
	local keys = {}
	for k in pairs(v) do
		keys[#keys + 1] = k
	end
	if #keys > 6 then
		return string.format('<table %d entries>', #keys)
	end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	local parts = {}
	for _, k in ipairs(keys) do
		parts[#parts + 1] = tostring(k) .. '=' .. describe(v[k], depth + 1)
	end
	return '{' .. table.concat(parts, ', ') .. '}'
end

-- ---------------------------------------------------------------- what each module reads
local function sortedKeys(set)
	local list = {}
	for k in pairs(set) do
		list[#list + 1] = k
	end
	table.sort(list, function(a, b) return tostring(a) < tostring(b) end)
	return list
end
local function staticActions(src)
	local set = {}
	for _, q in ipairs({'"', "'"}) do
		for a in src:gmatch('==%s*' .. q .. '([%a_][%w_%.%-]*)' .. q) do
			set[a] = true
		end
		for a in src:gmatch('%[%s*' .. q .. '([%a_][%w_]*)' .. q .. '%s*%]%s*=') do
			set[a] = true
		end
	end
	for a in src:gmatch('[%.:]([%a_][%w_]*)%s*=%s*function') do
		set[a] = true
	end
	for a in src:gmatch('\n%s*([%a_][%w_]*)%s*=%s*function') do
		set[a] = true
	end
	return set
end
local function recorder(store, prefix)
	return setmetatable({}, {__index = function(_, k)
		if k ~= nil then
			store[prefix .. tostring(k)] = k
		end
		return nil
	end})
end
local function footprint(reg, msg)
	local reads = {}
	local m = setmetatable({}, getmetatable(recorder(reads, 'msg.')))
	for k, v in pairs(msg) do
		rawset(m, k, v)
	end
	if type(msg.data) == 'table' then
		local d = recorder(reads, 'data.')
		for k, v in pairs(msg.data) do
			rawset(d, k, v)
		end
		rawset(m, 'data', d)
	end
	local key = '\1probe'
	tokens[key] = m
	local before = G.json.decode
	G.json.decode = function(b) if b == key then activity = activity + 1; return m end; return before(b) end
	logged, sentToServer, queue = {}, {}, {}
	local a0 = activity
	pcall(deliver, reg, key)
	queue = {}
	G.json.decode = before
	tokens[key] = nil
	local n = 0
	for _ in pairs(reads) do
		n = n + 1
	end
	return reads, (activity - a0) + n
end
local function setField(msg, key, raw, v)
	if key:sub(1, 5) == 'data.' then
		if type(msg.data) ~= 'table' then
			msg.data = {}
		end
		msg.data[raw] = v
	elseif raw ~= 'data' and raw ~= 'action' then
		msg[raw] = v
	end
end
local function build(entry, override, value)
	local msg = {action = entry.action, data = {}}
	for _, f in ipairs(entry.fields) do
		setField(msg, f.key, f.raw, 1)
	end
	if override then
		setField(msg, override.key, override.raw, value)
	end
	return msg
end
local fill = {1, 'a', true, {1}, 0}
local function learn(reg, entry, base)
	local seen = {}
	local reads, act = footprint(reg, build(entry))
	local active = act ~= base
	for round = 1, #fill do
		local n = 0
		for k, raw in pairs(reads) do
			if not seen[k] then
				seen[k] = raw
				n = n + 1
			end
		end
		if n == 0 and round > 1 then
			break
		end
		local msg = build(entry)
		for k, raw in pairs(seen) do
			setField(msg, k, raw, fill[round])
		end
		reads, act = footprint(reg, msg)
		active = active or act ~= base
	end
	entry.fields = {}
	for k, raw in pairs(seen) do
		if raw ~= 'action' and k ~= 'msg.data' then
			entry.fields[#entry.fields + 1] = {key = k, raw = raw}
		end
	end
	table.sort(entry.fields, function(x, y) return x.key < y.key end)
	return active
end
local function discover(reg)
	local unknown = {action = '__unknown_action__', fields = {}}
	local _, base = footprint(reg, build(unknown))
	learn(reg, unknown, base)
	local baseFields = {}
	for _, f in ipairs(unknown.fields) do
		baseFields[f.key] = true
	end
	local entries = {}
	for _, a in ipairs(sortedKeys(staticActions(sources[reg.module] or ''))) do
		local entry = {action = a, fields = {}}
		local active = learn(reg, entry, base)
		local own = false
		for _, f in ipairs(entry.fields) do
			own = own or not baseFields[f.key]
		end
		if active or own then
			entries[#entries + 1] = entry
		end
	end
	entries[#entries + 1] = unknown
	return entries
end

-- ---------------------------------------------------------------- fuzz every registration
-- First, for every module: buffers that are no JSON object, msg.data missing or not a table, unknown actions, chunk
-- sequences. Then a field or msg.data holding a list or an object of the wrong shape (a list of numbers where rows are
-- expected, ...): the second round runs last, so a failure of the first never comes from a state the second left.
local delivered = 0
local t0 = os.clock()
local function goFor(reg, e, msg, what)
	run(reg, token(msg), function() return 'action ' .. describe(e.action) .. ', ' .. what .. ': ' .. describe(msg) end)
end
for _, reg in ipairs(registrations) do
	for i, raw in ipairs(rawBuffers) do
		run(reg, raw, function() return 'raw buffer #' .. i .. ' ' .. describe(raw) end)
	end
	for _ = 1, 8 do
		local raw = randomRaw()
		run(reg, raw, function() return 'random buffer ' .. describe(raw) end)
	end
	reg.actions = discover(reg)
	for _, e in ipairs(reg.actions) do
		goFor(reg, e, {action = e.action}, 'no data')
		for _, g in ipairs(dataGarbage) do
			if type(g[2]) ~= 'table' then
				local msg = build(e)
				msg.data = g[2]
				goFor(reg, e, msg, 'data = ' .. g[1])
			end
		end
	end
	-- chunked answers (Chaos.sendChunked) with parts missing, repeated or out of order: never a Lua error in the
	-- module, and the three parts in order deliver the message exactly once
	if reg.kind == 'json' then
		local whole = json.encode({action = '__chunked__', data = {text = string.rep('z', 20000)}})
		local s, p, e = 'S' .. whole:sub(1, 8000), 'P' .. whole:sub(8001, 16000), 'E' .. whole:sub(16001)
		local sequences = {
			{'whole', {s, p, e}}, {'no start', {p, e}}, {'no middle', {s, e}}, {'no end, then a whole message', {s, p, '{"action":"x"}'}},
			{'start twice', {s, s, p, e}}, {'end twice', {s, p, e, e}}, {'reversed', {e, p, s}}, {'part first', {p, s, p, e}},
			{'only the end', {e}}, {'empty parts', {'S', 'P', 'E'}}, {'start, then nothing', {s}},
		}
		local fn = reg.fn
		for _, sq in ipairs(sequences) do
			delivered = 0
			reg.fn = function(...) delivered = delivered + 1; return fn(...) end
			run(reg, sq[2], function() return 'chunks: ' .. sq[1] end)
			reg.fn = fn
			if sq[1] == 'whole' then
				check(delivered == 1, 'chunks', who(reg), 'whole', 'S, P, E delivered ' .. delivered .. ' messages')
			end
		end
		run(reg, '{"action":"__reset__"}', function() return 'chunks: reset' end)
	end
end
-- regressions, whatever the draw: one message per place that failed before (a tier count of 1e308 ran the season
-- pass loop "for t = 1, total" for ever; the others indexed a number or a boolean, or sent inf back in a request)
local INF = math.huge
local regressions = {
	game_battlepass = {{action = 'tiers', data = {season = 77, total = 1e308, rows = {}}},
		{action = 'tiers', data = {season = 78, total = 2147483648, rows = {5}}}, {action = 'state', data = {season = 1}}},
	game_market = {{action = 'orders', data = {page = {}, pages = 0.5, rows = {5}, total = -1}},
		{action = 'meta', data = {categories = {{}, 5}, fee = 1e308, orders = 1, durations = {{}}}},
		{action = 'mine', data = {active = true}}, {action = 'myOrders', data = {active = ''}},
		{action = 'orderFind', data = {items = {5}}}, {action = 'sellable', data = {items = true}}},
	game_achievements = {{action = 'state', data = {categories = {{}, 5}, heldTitles = {5}, recent = {5}}},
		{action = 'track', data = {steps = {5}}}, {action = 'list', data = {first = true, last = true, rows = {5}}}},
	game_admin = {{action = 'catalog', data = {categories = {5, {{}}, {id = 'x', actions = {5, {id = 1}}}}}}},
	game_arena = {{action = 'state', data = {season = 1, recent = {5}}}},
	game_bestiary = {{action = 'summary', data = {cats = {5, {{}}}}}, {action = 'list', data = {first = 1, last = 1, rows = {5}}},
		{action = 'entry', data = {id = 1, th = {{}}, points = {{}}, immunities = {{}}, bonus = 1}},
		{action = 'board', data = {tasks = {5}, offers = {5}}}},
	game_bounty = {{action = 'board', data = {bands = {5, {{}}}}}},
	game_chatlinks = {{action = 'registered', data = {links = {5}, n = 1}}},
	game_cosmetics = {{action = 'state', data = {rows = {5}, lineName = true, open = true}}},
	game_crafting = {{action = 'state', data = {item = 1, items = {5}, history = {5}, open = true}}},
	game_factions = {{action = 'state', data = {factions = {5}}}, {action = 'npc', data = {f = INF}}},
	game_groundlabels = {{action = 'tiles', data = {t = {5}}}},
	game_guild = {{action = 'state', data = {guild = true, perks = 1, open = true}}},
	game_invasion = {{action = 'calendar', data = {list = {5}, open = true}}, {action = 'hud', data = {top = {5}}}},
	game_leaderboard = {{action = 'meta', data = {boards = {5, {{}}}, open = true}},
		{action = 'board', data = {key = INF, group = -INF, rows = true, champions = {5}}}},
	game_lootfilter = {{action = 'kill', data = {drops = {5}}}, {action = 'peek', data = {cid = 1, items = {5}}},
		{action = 'settings', data = {presets = {5, {key = INF}}}}},
	game_pets = {{action = 'state', data = {catalog = {5}, pets = {5, {{}}}, cooldowns = 1, active = 1, rest = true}}},
	game_raid = {{action = 'info', data = {saved = {5}}}, {action = 'loot', data = {eligible = true, lines = {{}}}}},
	game_siege = {{action = 'info', data = {signups = {5}, champions = {5}}}, {action = 'hud', data = {teams = {5}, holder = true}}},
	game_spellsupports = {{action = 'state', data = {spells = {5}, runes = {5, {{}}}}}},
	game_townportal = {{action = 'state', data = {styles = {5, {{}}}, cooldown = 1}}},
	game_unveil = {{action = 'open', data = {rarityName = true}}},
}
local regressionModules = {}
for _, reg in ipairs(registrations) do
	for i, msg in ipairs(regressions[reg.module] or {}) do
		regressionModules[reg.module] = true
		goFor(reg, {action = msg.action}, msg, 'regression ' .. i)
	end
end
for name in pairs(regressions) do
	check(regressionModules[name], 'regression', name, 'opcode handler', 'no longer registered: move its cases')
end
for _, reg in ipairs(registrations) do
	for _, e in ipairs(reg.actions) do
		for _, g in ipairs(dataGarbage) do
			if type(g[2]) == 'table' then
				local msg = build(e)
				msg.data = g[2]
				goFor(reg, e, msg, 'data = ' .. g[1])
			end
		end
		for _, f in ipairs(e.fields) do
			for _, g in ipairs(fieldGarbage) do
				goFor(reg, e, build(e, f, g[2]), f.key .. ' = ' .. g[1])
			end
		end
		for _ = 1, (#e.fields > 0 and 5 or 0) do
			local msg = build(e)
			local what = {}
			for _, f in ipairs(e.fields) do
				local g = garbage[rnd(#garbage)]
				what[#what + 1] = f.key .. ' = ' .. g[1]
				setField(msg, f.key, f.raw, g[2])
			end
			goFor(reg, e, msg, table.concat(what, ', '))
		end
	end
end

-- ---------------------------------------------------------------- opcodes
-- Every opcode a module registers is in server/README.md "Extended opcodes" with that module as its client, and is
-- ChaosOpcodes[key] in chaos_constants.lua; no two modules register the same opcode the same way (the base client
-- refuses the second: "Opcode is already taken"). A server script that answers through Chaos.sendChunked needs a
-- client that joins the parts: a JSON registration, or a plain one that handles "S" / "P" / "E" itself.
Chaos, ChaosOpcodes = nil, nil
dofile('server/data/scripts/chaos/chaos_constants.lua')
local rows = {}
local inTable = false
for line in (readFile('server/README.md') or ''):gmatch('([^\n]*)\n') do
	if line:find('^| Opcode | `ChaosOpcodes` key |') then
		inTable = true
	elseif inTable and not line:find('^|') then
		inTable = false
	end
	local op, key, servers, client = line:match('^| (%d+) | ([^|]+) | ([^|]+) | ([^|]+) |')
	if inTable and op then
		rows[tonumber(op)] = {key = key:match('^`([%w_]+)`'), servers = servers, client = client}
	end
end
check(next(rows) ~= nil, 'opcodes', 'server/README.md', 'opcode table', 'not found')
-- modules with an opcode of their own that no server script answers yet (client/MANIFEST.md)
local noServer = {game_nameshaders = 96}
local taken = {}
for _, reg in ipairs(registrations) do
	local key = reg.kind .. reg.opcode
	check(taken[key] == nil, 'opcodes', who(reg), reg.opcode, 'registered by ' .. tostring(taken[key]) .. ' too')
	taken[key] = reg.module
	local row = rows[reg.opcode]
	if noServer[reg.module] == reg.opcode then
		check(row == nil and not (function()
			for _, v in pairs(ChaosOpcodes) do
				if v == reg.opcode then
					return true
				end
			end
		end)(), 'opcodes', who(reg), reg.opcode, 'now taken on the server: list it in server/README.md')
	else
		check(row ~= nil and row.client:find('`' .. reg.module .. '`', 1, true) ~= nil, 'opcodes', who(reg), reg.opcode,
			'server/README.md does not list ' .. reg.module .. ' for this opcode')
		if row and row.key then
			check(ChaosOpcodes[row.key] == reg.opcode, 'opcodes', who(reg), reg.opcode, 'ChaosOpcodes.' .. row.key .. ' is ' ..
				tostring(ChaosOpcodes[row.key]))
		end
	end
end
for op, row in pairs(rows) do
	for script in row.servers:gmatch('`([%w_/]+%.lua)`') do
		local src = readFile('server/data/scripts/chaos/' .. script) or ''
		local ownKey = src:match('\nlocal OPCODE = %(?ChaosOpcodes[%s%a]*%.([%w_]+)')
		local own = ownKey and ChaosOpcodes[ownKey] == op
		if own and (src:find('Chaos.sendChunked(player, OPCODE', 1, true) or src:find('Chaos.sendChunked(p, OPCODE', 1, true)) then
			for _, reg in ipairs(registrations) do
				if reg.opcode == op then
					local joins = reg.kind == 'json' or (sources[reg.module] or ''):find("== 'S'", 1, true) ~= nil
					check(joins, 'opcodes', who(reg), op, script .. ' sends in parts (Chaos.sendChunked) but ' .. reg.module ..
						' registers a plain handler that does not join them')
				end
			end
		end
	end
end

if VERBOSE then
	for _, reg in ipairs(registrations) do
		local names = {}
		for _, e in ipairs(reg.actions or {}) do
			names[#names + 1] = e.action .. '(' .. #e.fields .. ')'
		end
		realPrint(who(reg), reg.kind, table.concat(names, ' '))
	end
	for _, k in ipairs(sortedKeys(missing)) do
		realPrint('stub global', k, missing[k])
	end
	for _, line in ipairs(slow) do
		realPrint('slow', line)
	end
end
if #failures > 0 then
	for _, f in ipairs(failures) do
		realPrint(f)
	end
	error(string.format('opcode_fuzz_test (client): %d failures (FUZZ_VERBOSE=1 for the details)', #failures), 0)
end
realPrint(string.format('opcode_fuzz_test (client): %d modules, %d opcode handlers, %d checks passed (%.1f s)',
	#moduleNames, #registrations, checks, os.clock() - t0))
