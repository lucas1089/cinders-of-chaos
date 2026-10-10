-- Run from the server/ folder: luajit tests/market_test.lua (CI runs it with LuaJIT and Lua 5.3).
-- The Chaos market (data/scripts/chaos/market_core.lua and market.lua) against a mocked engine with a small in-memory
-- SQL database (the statements market.lua writes: SELECT / INSERT / UPDATE / DELETE with WHERE, ORDER BY, LIMIT,
-- transactions and unique keys). Covers the pure rules (fees, tax, prices, listing refusals, seasons, the Browse query,
-- the codecs, the crash-safety plans) and the flows: listing a rolled legendary item for gold and part of a stack of
-- orbs for coins, browse and filters, tooltips, buying with gold and with coins (money moved with the tax, the item
-- delivered with every attribute and a new per-item id), refusals (own offer, own account, other season, not enough
-- money, sold twice), cancel, expiry with the seller online and offline, a failed transaction rolled back, a save that
-- fails, a crash between save and mark (no duplicate), interrupted listings recovered, and the key-list codec.
local checks, fails = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. tostring(what))
	end
end
local function eq(a, b, what)
	ok(a == b, (what or "check") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

-- ====================================================================== mini SQL
local DB = {tables = {}, auto = {}, lastId = 0, rowCount = 0, failOn = nil, tx = nil, unique = {}}
local function tbl(name)
	DB.tables[name] = DB.tables[name] or {}
	return DB.tables[name]
end
DB.unique["chaos_market_deliveries"] = {{"offer_id", "kind"}}
-- column defaults of the market tables (sql/chaos_market.sql)
DB.defaults = {
	chaos_market_offers = {buyer_id = 0, buyer_name = "", paid_currency = "", paid_amount = 0, tax = 0, closed_at = 0},
	chaos_market_deliveries = {delivered = 0, delivered_at = 0, amount = 0, reason = ""}
}
DB.unique["chaos_shop_coins"] = {{"account_id"}}
DB.unique["player_storage"] = {{"player_id", "key"}}

local function copy(v)
	if type(v) ~= "table" then
		return v
	end
	local o = {}
	for k, x in pairs(v) do
		o[k] = copy(x)
	end
	return o
end

local function tokenize(s)
	local toks, i = {}, 1
	while i <= #s do
		local c = s:sub(i, i)
		if c:match("%s") then
			i = i + 1
		elseif c == "`" then
			local j = s:find("`", i + 1, true)
			toks[#toks + 1] = {t = "id", v = s:sub(i + 1, j - 1)}
			i = j + 1
		elseif c == "'" then
			local buf, j = {}, i + 1
			while true do
				local d = s:sub(j, j)
				if d == "\\" then
					buf[#buf + 1] = s:sub(j + 1, j + 1)
					j = j + 2
				elseif d == "'" then
					break
				else
					buf[#buf + 1] = d
					j = j + 1
				end
			end
			toks[#toks + 1] = {t = "str", v = table.concat(buf)}
			i = j + 1
		elseif c:match("%d") then
			local num = s:match("^%d+%.?%d*", i)
			toks[#toks + 1] = {t = "num", v = tonumber(num)}
			i = i + #num
		elseif s:sub(i, i + 1) == ">=" or s:sub(i, i + 1) == "<=" or s:sub(i, i + 1) == "<>" then
			toks[#toks + 1] = {t = "op", v = s:sub(i, i + 1)}
			i = i + 2
		elseif c:match("[%(%),=<>%+%-%*]") then
			toks[#toks + 1] = {t = "op", v = c}
			i = i + 1
		else
			local w = s:match("^[%w_]+", i)
			toks[#toks + 1] = {t = "kw", v = w:upper()}
			i = i + #w
		end
	end
	return toks
end

local P = {}
P.__index = P
local function parser(s)
	return setmetatable({toks = tokenize(s), i = 1}, P)
end
function P:peek(k)
	return self.toks[self.i + (k or 0)]
end
function P:next()
	self.i = self.i + 1
	return self.toks[self.i - 1]
end
function P:is(v)
	local t = self:peek()
	return t and (t.t == "kw" or t.t == "op") and t.v == v
end
function P:accept(v)
	if self:is(v) then
		self.i = self.i + 1
		return true
	end
	return false
end
function P:expect(v)
	assert(self:accept(v), "SQL: expected " .. v .. " near token " .. self.i)
end

-- expressions evaluate as functions of a row
function P:term()
	local t = self:next()
	if t.t == "num" then
		return function() return t.v end
	elseif t.t == "str" then
		return function() return t.v end
	elseif t.t == "id" then
		return function(r) return r[t.v] end
	elseif t.t == "op" and t.v == "(" then
		local e = self:expr()
		self:expect(")")
		return e
	elseif t.t == "kw" and (t.v == "COUNT" or t.v == "ROW_COUNT" or t.v == "LAST_INSERT_ID" or t.v == "GREATEST") then
		self:expect("(")
		if t.v == "COUNT" then
			self:expect("*")
			self:expect(")")
			return function() return "__count" end
		elseif t.v == "GREATEST" then
			local a = self:expr()
			self:expect(",")
			local b = self:expr()
			self:expect(")")
			return function(r) return math.max(a(r), b(r)) end
		end
		self:expect(")")
		local which = t.v
		return function() return which == "ROW_COUNT" and DB.rowCount or DB.lastId end
	end
	error("SQL: bad term " .. tostring(t.v))
end
function P:arith()
	local e = self:term()
	while self:is("+") or self:is("-") do
		local op = self:next().v
		local a, b = e, self:term()
		e = op == "+" and function(r) return a(r) + b(r) end or function(r) return a(r) - b(r) end
	end
	return e
end
local function like(v, pat)
	local out, i = {"^"}, 1
	while i <= #pat do
		local ch = pat:sub(i, i)
		if ch == "\\" then
			i = i + 1
			local nx = pat:sub(i, i)
			out[#out + 1] = nx:match("%w") and nx:lower() or ("%" .. nx)
		elseif ch == "%" then
			out[#out + 1] = ".*"
		elseif ch == "_" then
			out[#out + 1] = "."
		elseif ch:match("%w") or ch == " " then
			out[#out + 1] = ch:lower()
		else
			out[#out + 1] = "%" .. ch
		end
		i = i + 1
	end
	out[#out + 1] = "$"
	return tostring(v):lower():find(table.concat(out)) ~= nil
end
function P:cmp()
	local a = self:arith()
	if self:accept("IN") then
		self:expect("(")
		local list = {}
		repeat
			list[#list + 1] = self:arith()
		until not self:accept(",")
		self:expect(")")
		return function(r)
			local v = a(r)
			for _, f in ipairs(list) do
				if f(r) == v then
					return true
				end
			end
			return false
		end
	elseif self:accept("LIKE") then
		local b = self:arith()
		return function(r) return like(a(r), b(r)) end
	end
	for _, op in ipairs({"=", ">=", "<=", ">", "<", "<>"}) do
		if self:accept(op) then
			local b = self:arith()
			return function(r)
				local x, y = a(r), b(r)
				if op == "=" then return x == y end
				if op == "<>" then return x ~= y end
				if op == ">=" then return x >= y end
				if op == "<=" then return x <= y end
				if op == ">" then return x > y end
				return x < y
			end
		end
	end
	return a
end
function P:andExpr()
	local e = self:cmp()
	while self:accept("AND") do
		local a, b = e, self:cmp()
		e = function(r) return a(r) and b(r) end
	end
	return e
end
function P:expr()
	local e = self:andExpr()
	while self:accept("OR") do
		local a, b = e, self:andExpr()
		e = function(r) return a(r) or b(r) end
	end
	return e
end

local function uniqueClash(name, row, except)
	for _, key in ipairs(DB.unique[name] or {}) do
		for _, r in ipairs(tbl(name)) do
			if r ~= except then
				local same = true
				for _, c in ipairs(key) do
					if r[c] ~= row[c] then
						same = false
					end
				end
				if same then
					return r
				end
			end
		end
	end
	return nil
end

local function run(sql, wantRows)
	if DB.failOn and sql:find(DB.failOn, 1, true) then
		DB.failOn = nil
		return false
	end
	local p = parser(sql)
	if p:accept("START") then
		DB.tx = copy(DB.tables)
		DB.txAuto = copy(DB.auto)
		return true
	elseif p:accept("COMMIT") then
		DB.tx = nil
		return true
	elseif p:accept("ROLLBACK") then
		if DB.tx then
			DB.tables, DB.auto, DB.tx = DB.tx, DB.txAuto, nil
		end
		return true
	elseif p:accept("CREATE") then
		return true
	elseif p:accept("INSERT") then
		p:expect("INTO")
		local name = p:next().v
		p:expect("(")
		local cols = {}
		repeat
			cols[#cols + 1] = p:next().v
		until not p:accept(",")
		p:expect(")")
		p:expect("VALUES")
		p:expect("(")
		local row = {}
		local n = 0
		repeat
			n = n + 1
			row[cols[n]] = p:arith()({})
		until not p:accept(",")
		p:expect(")")
		for k, v in pairs(DB.defaults[name] or {}) do
			if row[k] == nil then row[k] = v end
		end
		local clash = uniqueClash(name, row)
		if clash then
			if p:accept("ON") then
				p:expect("DUPLICATE")
				p:expect("KEY")
				p:expect("UPDATE")
				local col = p:next().v
				p:expect("=")
				local e = p:expr()
				clash[col] = e(clash)
				DB.rowCount = 2
				return true
			end
			return false -- duplicate key
		end
		DB.auto[name] = (DB.auto[name] or 0) + 1
		if row.id == nil and name:find("^chaos_market") then
			row.id = DB.auto[name]
			DB.lastId = row.id
		end
		local t = tbl(name)
		t[#t + 1] = row
		DB.rowCount = 1
		return true
	elseif p:accept("UPDATE") then
		local name = p:next().v
		p:expect("SET")
		local sets = {}
		repeat
			local col = p:next().v
			p:expect("=")
			sets[#sets + 1] = {col, p:arith()}
		until not p:accept(",")
		p:expect("WHERE")
		local where = p:expr()
		local n = 0
		for _, r in ipairs(tbl(name)) do
			if where(r) then
				local changed = false
				local new = {}
				for _, s in ipairs(sets) do
					new[s[1]] = s[2](r)
				end
				for k, v in pairs(new) do
					if r[k] ~= v then
						changed = true
					end
					r[k] = v
				end
				if changed then
					n = n + 1
				end
			end
		end
		DB.rowCount = n
		return true
	elseif p:accept("DELETE") then
		p:expect("FROM")
		local name = p:next().v
		p:expect("WHERE")
		local where = p:expr()
		local keep, n = {}, 0
		for _, r in ipairs(tbl(name)) do
			if where(r) then
				n = n + 1
			else
				keep[#keep + 1] = r
			end
		end
		DB.tables[name] = keep
		DB.rowCount = n
		return true
	elseif p:accept("SELECT") then
		local fields = {}
		repeat
			local e = p:arith()
			local alias
			local tok = p:peek(-1)
			if p:accept("AS") then
				alias = p:next().v
			elseif tok.t == "id" then
				alias = tok.v
			end
			fields[#fields + 1] = {e, alias}
		until not p:accept(",")
		local rows = {{}}
		if p:accept("FROM") then
			rows = tbl(p:next().v)
		end
		local where = p:accept("WHERE") and p:expr() or function() return true end
		local out = {}
		for _, r in ipairs(rows) do
			if where(r) then
				out[#out + 1] = r
			end
		end
		if p:accept("ORDER") then
			p:expect("BY")
			local keys = {}
			repeat
				local e = p:arith()
				local desc = p:accept("DESC")
				p:accept("ASC")
				keys[#keys + 1] = {e, desc}
			until not p:accept(",")
			table.sort(out, function(x, y)
				for _, k in ipairs(keys) do
					local a, b = k[1](x), k[1](y)
					if type(a) == "boolean" then a = a and 1 or 0 end
					if type(b) == "boolean" then b = b and 1 or 0 end
					if a ~= b then
						if k[2] then return a > b end
						return a < b
					end
				end
				return false
			end)
		end
		local limit, offset = nil, 0
		if p:accept("LIMIT") then
			limit = p:next().v
			if p:accept("OFFSET") then
				offset = p:next().v
			end
		end
		local res = {}
		if fields[1][1]({}) == "__count" then
			res[1] = {[fields[1][2]] = #out}
		else
			for i = offset + 1, limit and math.min(#out, offset + limit) or #out do
				local r = {}
				for _, f in ipairs(fields) do
					r[f[2]] = f[1](out[i])
				end
				res[#res + 1] = r
			end
		end
		return res
	end
	error("SQL: unknown statement " .. sql:sub(1, 40))
end

local results, nextResult = {}, 0
db = {
	query = function(q)
		local okq, r = pcall(run, q)
		if not okq then
			print("SQL ERROR " .. tostring(r) .. " in " .. q:sub(1, 120))
			return false
		end
		return r ~= false
	end,
	asyncQuery = function(q) return db.query(q) end,
	storeQuery = function(q)
		local okq, r = pcall(run, q)
		if not okq then
			print("SQL ERROR " .. tostring(r) .. " in " .. q:sub(1, 120))
			return false
		end
		if type(r) ~= "table" or #r == 0 then
			return false
		end
		nextResult = nextResult + 1
		results[nextResult] = {rows = r, i = 1}
		return nextResult
	end,
	escapeString = function(s)
		return "'" .. tostring(s):gsub("\\", "\\\\"):gsub("'", "\\'") .. "'"
	end
}
result = {
	getString = function(id, col) local v = results[id].rows[results[id].i][col] return v == nil and "" or tostring(v) end,
	getNumber = function(id, col) return tonumber(results[id].rows[results[id].i][col]) or 0 end,
	next = function(id) results[id].i = results[id].i + 1 return results[id].rows[results[id].i] ~= nil end,
	free = function(id) results[id] = nil end
}

-- ====================================================================== json (a registry: encode -> token)
local registry, rn = {}, 0
json = {
	encode = function(t)
		rn = rn + 1
		registry["J" .. rn] = copy(t)
		return "J" .. rn
	end,
	decode = function(s)
		local v = registry[s]
		if v == nil then
			error("not json")
		end
		return copy(v)
	end
}

-- ====================================================================== engine
os.mtime = nil
local clock = 1800000000
local realOsTime = os.time
os.time = function(t)
	if t then
		return realOsTime(t)
	end
	return clock
end
MESSAGE_EVENT_ADVANCE, MESSAGE_INFO_DESCR = 19, 20
CONST_SLOT_FIRST, CONST_SLOT_LAST, CONST_SLOT_BACKPACK = 1, 10, 3
INDEX_WHEREEVER, FLAG_NOLIMIT, RETURNVALUE_NOERROR = -1, 1, 0
ITEM_ATTRIBUTE_NAME, ITEM_ATTRIBUTE_DESCRIPTION, ITEM_ATTRIBUTE_ACTIONID, ITEM_ATTRIBUTE_UNIQUEID = 1, 2, 3, 4
ITEM_ATTRIBUTE_ATTACK, ITEM_ATTRIBUTE_CHARGES = 5, 6

local types = {
	[2400] = {name = "magic sword", stackable = false, client = 2400},
	[29856] = {name = "Orb of Upheaval", stackable = true, client = 29856},
	[1988] = {name = "backpack", stackable = false, client = 1988, container = true},
	[2160] = {name = "crystal coin", stackable = true, client = 2160},
	[2463] = {name = "plate armor", stackable = false, client = 2463}
}
function ItemType(id)
	local t = types[id] or {name = "thing", client = id}
	return {
		isStackable = function() return t.stackable == true end,
		isPickupable = function() return true end,
		isMovable = function() return true end,
		getClientId = function() return t.client end,
		getName = function() return t.name end
	}
end

local Items = {}
Item = {}
local itemMeta = {__index = Items}
local nextUid = 1
local function newItem(id, count)
	local it = setmetatable({id = id, count = count or 1, custom = {}, std = {}, uid = nextUid, children = nil}, itemMeta)
	nextUid = nextUid + 1
	if types[id] and types[id].container then
		it.children = {}
	end
	return it
end
function Items.getId(self) return self.id end
function Items.getCount(self) return self.count end
function Items.getName(self) return (types[self.id] or {}).name or "thing" end
function Items.getCustomAttribute(self, k) return self.custom[k:lower()] end
function Items.setCustomAttribute(self, k, v) self.custom[k:lower()] = v end
function Items.removeCustomAttribute(self, k) self.custom[k:lower()] = nil end
function Items.hasAttribute(self, a) return self.std[a] ~= nil end
function Items.getAttribute(self, a) return self.std[a] end
function Items.setAttribute(self, a, v) self.std[a] = v end
function Items.getActionId(self) return self.std[ITEM_ATTRIBUTE_ACTIONID] or 0 end
function Items.isStoreItem(self) return self.store == true end
function Items.isContainer(self) return self.children ~= nil end
function Items.getSize(self) return self.children and #self.children or 0 end
function Items.getItem(self, i) return self.children and self.children[i + 1] end
function Items.getParent(self) return self.parent end
function Items.getTopParent(self)
	local p = self.parent
	while p and p.parent do p = p.parent end
	return p
end
local function detach(item)
	local p = item.parent
	if p and p.children then
		for i, c in ipairs(p.children) do
			if c == item then table.remove(p.children, i) break end
		end
	elseif p and p.slots then
		for s, c in pairs(p.slots) do
			if c == item then p.slots[s] = nil end
		end
	end
	item.parent = nil
end
function Items.remove(self, n)
	if n and n < self.count then
		self.count = self.count - n
		return true
	end
	detach(self)
	return true
end
-- the engine form: every attribute (the mock writes a text; the market hex encodes it)
local function ser(item)
	local parts = {}
	local ks = {}
	for k in pairs(item.custom) do ks[#ks + 1] = k end
	table.sort(ks)
	for _, k in ipairs(ks) do
		local v = item.custom[k]
		parts[#parts + 1] = "c|" .. k .. "|" .. type(v) .. "|" .. tostring(v)
	end
	local ss = {}
	for k in pairs(item.std) do ss[#ss + 1] = k end
	table.sort(ss)
	for _, k in ipairs(ss) do
		parts[#parts + 1] = "s|" .. k .. "|" .. type(item.std[k]) .. "|" .. tostring(item.std[k])
	end
	parts[#parts + 1] = "n|count|number|" .. item.count
	return table.concat(parts, "\n") .. "\0\255"
end
local function blobMethods()
	Items.serializeAttributes = function(self) return ser(self) end
	Items.unserializeAttributes = function(self, raw)
		if raw:sub(-2) ~= "\0\255" then return false end
		for line in raw:sub(1, -3):gmatch("[^\n]+") do
			local kind, k, t, v = line:match("^(%a)|([^|]*)|(%a+)|(.*)$")
			local val = t == "number" and tonumber(v) or (t == "boolean" and v == "true") or v
			if kind == "c" then self.custom[k] = val elseif kind == "s" then self.std[tonumber(k)] = val end
			-- "n|count": the engine patch keeps the count the item was created with
		end
		return true
	end
	Item.serializeAttributes, Item.unserializeAttributes = Items.serializeAttributes, Items.unserializeAttributes
end
blobMethods()

local function addTo(container, item)
	if types[item.id] and types[item.id].stackable then
		for _, c in ipairs(container.children) do
			if c.id == item.id and next(c.custom) == nil and next(item.custom) == nil and c.count + item.count <= 100 then
				c.count = c.count + item.count
				return
			end
		end
	end
	container.children[#container.children + 1] = item
	item.parent = container
end
function Items.addItemEx(self, item)
	if item.parent then return 1 end
	addTo(self, item)
	return 0
end

local created = {}
Game = {
	createItem = function(id, count)
		local it = newItem(id, count)
		created[#created + 1] = it
		return it
	end,
	getPlayers = function() return {} end,
	getStorageValue = function() return -1 end
}

local Players = {}
local online = {}
local playerMeta = {__index = Players}
local function newPlayer(guid, account, name, bank, level)
	local p = setmetatable({guid = guid, account = account, name = name, bank = bank or 0, level = level or 100, storage = {},
		slots = {}, msgs = {}, sent = {}, saves = 0, id = 268435456 + guid}, playerMeta)
	p.inbox = newItem(1988)
	p.inbox.children = {}
	p.inbox.parent = p
	local bag = newItem(1988)
	bag.parent = p
	p.slots[CONST_SLOT_BACKPACK] = bag
	table.insert(tbl("players"), {id = guid, balance = p.bank, save = 1, name = name})
	return p
end
function Players.getGuid(self) return self.guid end
function Players.getId(self) return self.id end
function Players.getAccountId(self) return self.account end
function Players.getName(self) return self.name end
function Players.getLevel(self) return self.level end
function Players.getBankBalance(self) return self.bank end
function Players.setBankBalance(self, v) self.bank = v end
function Players.getStorageValue(self, k) return self.storage[k] or -1 end
function Players.setStorageValue(self, k, v) self.storage[k] = v end
function Players.getSlotItem(self, s) return self.slots[s] end
function Players.getInbox(self) return self.inbox end
function Players.sendTextMessage(self, t, m) self.msgs[#self.msgs + 1] = m end
function Players.sendCancelMessage(self, m) self.msgs[#self.msgs + 1] = m end
function Players.sendExtendedOpcode(self, op, buf)
	self.sent[#self.sent + 1] = {op = op, msg = registry[buf]}
	return true
end
function Players.getGroup(self) return {getAccess = function() return false end, getId = function() return 1 end} end
function Players.registerEvent() end
function Players.addItemEx(self, item) addTo(self.slots[CONST_SLOT_BACKPACK], item) return 0 end
function Players.getContainerById() return nil end
Players.failSave = false
function Players.save(self)
	if self.failSave then return false end
	self.saves = self.saves + 1
	for _, r in ipairs(tbl("players")) do
		if r.id == self.guid then r.balance = self.bank end
	end
	local keep = {}
	for _, r in ipairs(tbl("player_storage")) do
		if r.player_id ~= self.guid then keep[#keep + 1] = r end
	end
	for k, v in pairs(self.storage) do
		keep[#keep + 1] = {player_id = self.guid, key = k, value = v}
	end
	DB.tables["player_storage"] = keep
	-- the saved inventory, for the crash tests: a deep copy of the inbox and the backpack
	local function snap(list)
		local out = {}
		for _, it in ipairs(list) do out[#out + 1] = {id = it.id, count = it.count, custom = copy(it.custom), std = copy(it.std)} end
		return out
	end
	self.saved = {inbox = snap(self.inbox.children), bag = snap(self.slots[CONST_SLOT_BACKPACK].children), bank = self.bank}
	return true
end
function Player(x)
	if type(x) == "table" then return x end
	for _, p in pairs(online) do
		if p.guid == x or p.id == x or p.name == x then return p end
	end
	return nil
end
local function login(p) online[p.guid] = p end
local function logout(p) online[p.guid] = nil end

local events = {}
local function reg(kind)
	local n = 0
	return function(name)
		n = n + 1
		name = name or (kind .. n)
		local e = {name = name, kind = kind}
		e.type = function() end
		e.register = function() events[name] = e end
		e.interval = function() end
		e.id = function() end
		e.separator = function() end
		return e
	end
end
CreatureEvent, GlobalEvent, Action, TalkAction = reg("creature"), reg("global"), reg("action"), reg("talk")
local queued = {}
function addEvent(fn, ms, ...)
	queued[#queued + 1] = {fn, {...}}
end
local function runEvents()
	local q = queued
	queued = {}
	for _, e in ipairs(q) do e[1]((table.unpack or unpack)(e[2])) end
end

-- the Chaos libraries the market reads (stubs with the real names)
dofile("data/scripts/chaos/chaos_constants.lua")
ChaosCrafting = {
	customNumber = function(item, k) return tonumber(item:getCustomAttribute(k)) or 0 end,
	itemName = function(item) return item:getName() end,
	rarityOf = function(item) return tonumber(item:getCustomAttribute("rarity")) or 0 end,
	attributeKeys = function() return {"rarity", "chaos_ilvl", "combatPowerLevel", "rarity_firedamage", "rarity_firedamage_t",
		"chaos_mod_attackspeed", "chaos_mod_attackspeed_t", "chaos_mod_attackspeed_b", "chaos_quality"} end
}
ChaosItemMods = {itemLevelOf = function(item) return tonumber(item:getCustomAttribute("chaos_ilvl")) or 0 end}
ChaosGems = {ATTR_GEM = "chaos_gem", isGem = function(id) return id == 40001 end}
ChaosItemTooltip = {
	build = function(item)
		local mods = {}
		if item:getCustomAttribute("rarity_firedamage") then mods[#mods + 1] = {k = "rarity_firedamage", l = "Fire Damage"} end
		if item:getCustomAttribute("chaos_mod_attackspeed") then mods[#mods + 1] = {k = "chaos_mod_attackspeed", l = "Attack Speed"} end
		local r = tonumber(item:getCustomAttribute("rarity")) or 0
		return {id = item.id, name = item:getName(), count = item.count, rarity = r, level = tonumber(item:getCustomAttribute("chaos_ilvl")),
			kind = item.id == 2400 and "weapon" or (item.id == 2463 and "armor" or nil), mods = mods,
			unique = item:getCustomAttribute("chaos_unique") and {name = item:getName()} or nil, key = "x:y"}
	end,
	decodePos = function() return nil end
}
local season = 0
ChaosSeason = {
	current = function() return season > 0 and {id = season, name = "Season of Ash", tag = "[S1]"} or nil end,
	realmOfGuid = function(guid) local r = (ChaosSeason.rows[guid] or 0) return r == season and r or 0 end,
	rows = {}
}
ChaosRateLimit = nil

-- ====================================================================== pure rules
dofile("data/scripts/chaos/market_core.lua")
local MC = ChaosMarketCore
local cfg = dofile("data/scripts/chaos/market_config.lua")

eq(MC.fee(cfg, 100000, 0), 1000, "fee 1% of the gold price")
eq(MC.fee(cfg, 500, 0), 100, "fee minimum")
eq(MC.fee(cfg, 2000000000, 0), 1000000, "fee maximum")
eq(MC.fee(cfg, 0, 100), 100, "coins only: 100 coins x 100 gold x 1%")
eq(MC.fee(cfg, 0, 5000), 5000, "coins only, bigger")
eq(MC.fee(cfg, 300000, 50), 3000, "both prices: the gold price counts")
local tax, net = MC.tax(cfg, "gold", 100000)
eq(tax, 5000, "tax 5%")
eq(net, 95000, "net")
tax, net = MC.tax(cfg, "coins", 19)
eq(tax, 0, "coins under 20: no tax")
eq(net, 19, "all to the seller")
tax, net = MC.tax(cfg, "coins", 100)
eq(tax .. "/" .. net, "5/95", "coin tax")
local g, c, d = MC.checkPrices(cfg, 1000, 0, 3)
eq(g .. "/" .. c .. "/" .. d, "1000/0/3", "prices ok")
eq(MC.checkPrices(cfg, 0, 0, 3), nil, "no price")
eq(select(2, MC.checkPrices(cfg, 50, 0, 3)):find("between") ~= nil, true, "gold below the minimum")
eq(MC.checkPrices(cfg, 1000, 0, 5), nil, "5 days is not an option")
eq(MC.checkPrices(cfg, -5, 10, 3), nil, "negative")
eq(MC.checkPrices(cfg, 0, 200000, 3), nil, "coins over the maximum")
eq(select(3, MC.checkPrices(cfg, 0, 10, nil)), cfg.defaultDuration, "default duration")
eq(MC.checkPrices(cfg, "1e400", 0, 3), nil, "infinite price")
eq(MC.money(1234567), "1,234,567", "money")
eq(MC.money(-1000), "-1,000", "negative money")
eq(MC.money(100), "100", "small money")

local base = {id = 2400, count = 1, have = 1, pickupable = true, movable = true}
local function with(t)
	local o = copy(base)
	for k, v in pairs(t) do o[k] = v end
	return o
end
eq(MC.itemRefusal(base, cfg), nil, "a plain item can be listed")
ok(MC.itemRefusal(with({equipped = true}), cfg):find("off"), "equipped refused")
ok(MC.itemRefusal(with({locked = true}), cfg):find("locked"), "locked refused")
ok(MC.itemRefusal(with({store = true}), cfg):find("Store"), "store item refused")
ok(MC.itemRefusal(with({storeBound = true}), cfg):find("Store"), "store pouch (chaos_storebound) refused")
ok(MC.itemRefusal(with({container = true, contents = 2}), cfg):find("Empty"), "full container refused")
eq(MC.itemRefusal(with({container = true, contents = 0}), cfg), nil, "empty container allowed")
ok(MC.itemRefusal(with({id = 2160}), cfg), "coins refused")
ok(MC.itemRefusal(with({uniqueId = 5000}), cfg):find("Quest"), "unique id refused")
ok(MC.itemRefusal(with({pickupable = false}), cfg), "not pickupable refused")
ok(MC.itemRefusal(with({decaying = true}), cfg), "decaying refused")
ok(MC.itemRefusal(with({count = 5, have = 3}), cfg), "more than the stack")
ok(MC.itemRefusal(with({count = 0}), cfg), "zero")
ok(MC.itemRefusal(nil, cfg), "no item")

eq(MC.realmOf(0, 0), 0, "standard offer")
eq(MC.realmOf(1, 1), 1, "season offer while the season runs")
eq(MC.realmOf(1, 0), 0, "season over: the offer joins the standard market")
eq(MC.realmOf(1, 2), 0, "another season")
eq(MC.category("weapon", "x"), "weapon", "gear kind")
eq(MC.category(nil, "Orb of Fate"), "orb", "orb")
eq(MC.category(nil, "ruby", true), "gem", "gem")
eq(MC.category(nil, "Rift Key", false, true), "key", "key")
eq(MC.category(nil, "apple"), "misc", "misc")
eq(MC.category("other", "Orb of Fate", false, false, 0), "orb", "an orb held in the hand is not gear")
eq(MC.category("other", "Torch of Ash", false, false, 3), "other", "a rolled off-hand item is gear")
eq(MC.modsField({"Rarity_FireDamage", "chaos_mod_x", "rarity_firedamage", "bad key;"}), ",rarity_firedamage,chaos_mod_x,badkey,", "mods field")
eq(MC.modsField({}), "", "no mods")

local esc = db.escapeString
local where, order, page, offset = MC.browseQuery({q = "50%_ off", cat = "weapon", rarity = 5, ilvlMin = 100, ilvlMax = 200, cur = "gold",
	priceMin = 10, priceMax = 900, mod = "Chaos_Mod_AttackSpeed'", sort = "price", page = 3}, 1, 1000, cfg, esc)
ok(where:find("`realm` = 1", 1, true), "realm in the query")
eq(MC.realmClause(0, 1), "`realm` <> 1", "standard view during a season: every offer but the season's")
eq(MC.realmClause(0, 0), "`realm` >= 0", "no season: every offer")
eq(MC.realmClause(1, 1), "`realm` = 1", "season view")
ok(where:find("`name` LIKE '%50\\\\%\\\\_ off%'", 1, true), "LIKE escaped: " .. where)
ok(where:find("`category` = 'weapon'", 1, true), "category")
ok(where:find("`price_gold` >= 10", 1, true) and where:find("`price_gold` <= 900", 1, true), "price range")
ok(where:find("`mods` LIKE '%,chaos\\\\_mod\\\\_attackspeed,%'", 1, true), "mod key sanitized and escaped: " .. where)
eq(order, "`price_gold` ASC, `id` DESC", "sort by gold price")
eq(page .. "/" .. offset, "3/20", "page offset")
where = MC.browseQuery({cat = "nonsense'; DROP", sort = "x", page = -4}, 0, 5, cfg, esc)
ok(not where:find("category"), "unknown category ignored")
eq(select(3, MC.browseQuery({page = 99999}, 0, 5, cfg, esc)), 1000, "page clamped")
eq(MC.pages(0, cfg), 1, "pages of nothing")
eq(MC.pages(25, cfg), 3, "pages")

local done, todo = MC.deliveryPlan({{id = 9}, {id = 4}, {id = 7}}, 7)
eq(#done .. "/" .. #todo, "2/1", "plan: up to the mark applied")
eq(done[1].id .. "," .. done[2].id .. "," .. todo[1].id, "4,7,9", "plan in id order")
eq(#select(2, MC.deliveryPlan({{id = 1}}, -1)), 1, "unset mark")
eq(MC.pendingAction(10, 10), "activate", "saved listing")
eq(MC.pendingAction(10, 9), "drop", "unsaved listing")
eq(MC.pendingAction(10, -1), "drop", "never listed")

local raw = string.char(0, 1, 2, 255, 10) .. "abc"
eq(MC.unhex(MC.hex(raw)), raw, "hex round trip")
eq(MC.unhex("abc"), nil, "odd hex")
eq(MC.unhex("zz"), nil, "bad hex")
local list = MC.decodeAttrs(MC.encodeAttrs({{"rarity", 5}, {"@ITEM_ATTRIBUTE_NAME", "Doom; =blade:"}, {"x", 1.5}, {"flag", true}}))
eq(#list, 4, "attrs round trip")
eq(list[2][2], "Doom; =blade:", "string with separators")
eq(list[3][2], 1.5, "fraction")
eq(list[4][2], true, "boolean")

-- ====================================================================== flows
dofile("data/scripts/chaos/market.lua")
local MK = ChaosMarket
eq(MK.hasBlob, true, "engine patch 0017 methods found")
events.ChaosMarketStartup.onStartup()

local A = newPlayer(1, 10, "Seller", 200000)
local B = newPlayer(2, 20, "Buyer", 5000000)
local A2 = newPlayer(4, 10, "Alt", 900000)
local Cs = newPlayer(3, 30, "Ashen", 900000)
ChaosSeason.rows[3] = 1
for _, p in ipairs({A, B, A2, Cs}) do login(p) end
table.insert(tbl("chaos_shop_coins"), {account_id = 20, coins = 500})
table.insert(tbl("chaos_shop_coins"), {account_id = 30, coins = 500})

local function lastSent(p, action)
	for i = #p.sent, 1, -1 do
		local m = p.sent[i].msg
		if m and m.action == action then return m.data end
	end
	return nil
end
local function op(p, action, data)
	events.ChaosMarketExtended.onExtendedOpcode(p, 221, json.encode({action = action, data = data or {}}))
end

-- the items: a rolled legendary sword and 50 orbs in A's backpack
local bagA = A.slots[CONST_SLOT_BACKPACK]
local sword = newItem(2400)
for k, v in pairs({rarity = 5, chaos_ilvl = 150, combatpowerlevel = 150, rarity_firedamage = 12, rarity_firedamage_t = 3,
	chaos_mod_attackspeed = 9, chaos_mod_attackspeed_t = 2, chaos_mod_attackspeed_b = 1, chaos_quality = 18, chaos_sockets = 2,
	chaos_gem1 = 40001, chaos_gem2 = 0, chaos_mod_deathblast = 13, chaos_iid = 777, chaos_ext = "pw:deathblast"}) do
	sword.custom[k] = v
end
sword.std[ITEM_ATTRIBUTE_NAME] = "Doombringer"
sword.std[ITEM_ATTRIBUTE_ATTACK] = 48
addTo(bagA, sword)
local orbs = newItem(29856, 50)
addTo(bagA, orbs)
local before = ser(sword)

-- the Sell tab picker
op(A, "sellable")
local sl = lastSent(A, "sellable")
eq(#sl.items, 2, "two items in the picker")
eq(sl.items[1].ref, "s3.0", "ref of the sword")
eq(sl.items[1].why, nil, "sword listable")
sword.custom.chaos_iid = 1878632478801912 -- a real per-item id (engine patch 0003): above 2^50, printed exactly
op(A, "sellable")
eq(lastSent(A, "sellable").items[1].iid, "1878632478801912", "per-item id sent as an exact decimal string")
sword.custom.chaos_iid = 777

-- refusals
op(A, "list", {ref = "s3.0", sid = 2400, iid = "777", gold = 0, coins = 0, days = 3})
ok(lastSent(A, "error").text:find("price"), "no price refused")
op(A, "list", {ref = "s3.0", sid = 2400, iid = "1", gold = 1000, days = 3})
eq(lastSent(A, "error").text, cfg.messages.noItem, "stale per-item id refused")
op(A, "list", {ref = "s3.5", sid = 2400, iid = "777", gold = 1000, days = 3})
eq(lastSent(A, "error").text, cfg.messages.noItem, "wrong ref refused")
op(A, "list", {ref = "s3", sid = 1988, iid = "0", gold = 1000, days = 3})
ok(lastSent(A, "error").text:find("off"), "the equipped backpack refused")
sword.custom.chaos_locked = 1
op(A, "list", {ref = "s3.0", sid = 2400, iid = "777", gold = 1000, days = 3})
ok(lastSent(A, "error").text:find("locked"), "locked sword refused")
sword.custom.chaos_locked = nil
sword.custom.chaos_storebound = 1
op(A, "list", {ref = "s3.0", sid = 2400, iid = "777", gold = 1000, days = 3})
ok(lastSent(A, "error").text:find("Store"), "store-bound refused")
sword.custom.chaos_storebound = nil
ChaosPouches = {isPouch = function(item) return item.id == 2400 end}
op(A, "list", {ref = "s3.0", sid = 2400, iid = "777", gold = 1000, days = 3})
ok(lastSent(A, "error").text:find("Store"), "a store pouch (ChaosPouches.isPouch) refused")
ChaosPouches = nil
A.level = 5
op(A, "list", {ref = "s3.0", sid = 2400, iid = "777", gold = 1000, days = 3})
ok(lastSent(A, "error").text:find("level"), "low level refused")
A.level = 100
eq(#tbl("chaos_market_offers"), 0, "no offer after the refusals")
before = ser(sword) -- (the refusals set and removed attributes)

-- list the sword for 100,000 gold
local savesBefore = A.saves
op(A, "list", {ref = "s3.0", sid = 2400, iid = "777", gold = 100000, days = 3})
local done1 = lastSent(A, "done")
ok(done1 and done1.what == "list", "sword listed")
local swordOffer = done1.id
eq(A.bank, 199000, "listing fee 1,000 from the bank")
eq(#bagA.children, 1, "the sword left the backpack")
eq(A.storage[cfg.storage.listSeq], swordOffer, "listSeq marker")
eq(A.saves, savesBefore + 1, "one save")
eq(A.saved.bank, 199000, "the saved bank has the fee taken")
local row = tbl("chaos_market_offers")[1]
eq(row.state, 0, "offer active")
eq(row.codec, "blob", "escrow codec blob")
eq(row.category, "weapon", "category")
eq(row.mods, ",rarity_firedamage,chaos_mod_attackspeed,", "mods field stored")
eq(row.rarity .. "/" .. row.ilvl, "5/150", "rarity and item level stored")
eq(row.expires - row.created, 3 * 86400, "3 days")

-- list 20 of the 50 orbs for 100 coins
op(A, "list", {ref = "s3.0", sid = 29856, iid = "0", count = 20, coins = 100, days = 1})
local orbOffer = lastSent(A, "done").id
eq(orbs.count, 30, "30 orbs stay")
eq(A.bank, 198900, "coin offer fee 100")
eq(tbl("chaos_market_offers")[2].count, 20, "20 in the offer")

-- browse
op(B, "browse", {})
local pg = lastSent(B, "page")
eq(pg.total, 2, "the buyer sees both offers")
eq(pg.rows[1].id, orbOffer, "newest first")
op(B, "browse", {cur = "coins"})
eq(lastSent(B, "page").total, 1, "coins filter")
op(B, "browse", {q = "upheav"})
eq(lastSent(B, "page").rows[1].id, orbOffer, "name search")
op(B, "browse", {mod = "chaos_mod_attackspeed"})
eq(lastSent(B, "page").rows[1].id, swordOffer, "modifier filter")
op(B, "browse", {rarity = 6})
eq(lastSent(B, "page").total, 0, "rarity filter")
op(B, "browse", {sort = "price", cur = "gold", priceMax = 99999})
eq(lastSent(B, "page").total, 0, "price filter")
op(B, "browse", {cat = "weapon", ilvlMin = 100})
eq(lastSent(B, "page").total, 1, "category + item level")
op(Cs, "browse", {})
eq(lastSent(Cs, "page").total, 2, "no season running: the season row counts as standard; it sees the standard offers")
season = 1
op(Cs, "browse", {})
eq(lastSent(Cs, "page").total, 0, "season character: the standard offers are not on its market")
op(B, "browse", {})
eq(lastSent(B, "page").total, 2, "standard market unchanged")

-- tooltip
op(B, "tip", {id = swordOffer})
local tp = lastSent(B, "tip")
eq(tp.tip.name, "magic sword", "tooltip snapshot")
eq(tp.seller, "Seller", "seller")
op(Cs, "tip", {id = swordOffer})
eq(lastSent(Cs, "tip").gone, true, "another realm gets no tooltip")

-- buying refusals
op(A, "buy", {id = swordOffer, cur = "gold"})
eq(lastSent(A, "error").text, cfg.messages.ownOffer, "own offer")
op(A2, "buy", {id = swordOffer, cur = "gold"})
eq(lastSent(A2, "error").text, cfg.messages.ownAccount, "same account")
op(Cs, "buy", {id = swordOffer, cur = "gold"})
eq(lastSent(Cs, "error").text, cfg.messages.realm, "season character cannot buy a standard offer")
op(B, "buy", {id = swordOffer, cur = "coins"})
eq(lastSent(B, "error").text, cfg.messages.noCurrency, "not for coins")

-- a failed transaction rolls back: the seller's gold delivery cannot be written
DB.failOn = "'gold', 95000"
op(B, "buy", {id = swordOffer, cur = "gold"})
eq(lastSent(B, "error").text, cfg.messages.notFound, "failed purchase refused")
eq(B.bank, 5000000, "buyer's bank untouched in memory")
eq(tbl("players")[2].balance, 5000000, "buyer's balance untouched in the database (rolled back)")
eq(tbl("chaos_market_offers")[1].state, 0, "offer still active")
eq(#tbl("chaos_market_deliveries"), 0, "no delivery rows")

-- buy the sword with gold
op(B, "buy", {id = swordOffer, cur = "gold"})
eq(lastSent(B, "done").what, "buy", "bought")
eq(B.bank, 4900000, "price taken from the bank")
eq(tbl("players")[2].balance, 4900000, "and in the database")
eq(tbl("chaos_market_offers")[1].state, 1, "offer sold")
eq(tbl("chaos_market_offers")[1].tax, 5000, "tax recorded")
local got = B.inbox.children[1]
ok(got ~= nil, "the sword is in the buyer's inbox")
eq(got.custom.chaos_iid, nil, "a new per-item id (the old one is not copied)")
got.custom.chaos_iid = 777
eq(ser(got), before, "every attribute identical (rarity, item level, modifiers, tiers, bound mark, quality, sockets, gems, power, name, attack)")
eq(A.bank, 198900 + 95000, "seller online: 95,000 net to the bank")
local told = false
for _, m in ipairs(A.msgs) do if m:find("Buyer bought your") then told = true end end
ok(told, "seller told")
eq(B.storage[cfg.storage.deliverSeq] ~= nil, true, "buyer's deliverSeq set")
local logs = 0
for _, r in ipairs(tbl("chaos_market_log")) do if r.action == "buy" then logs = logs + 1 end end
eq(logs, 1, "sale logged")
op(B, "buy", {id = swordOffer, cur = "gold"})
eq(lastSent(B, "error").text, cfg.messages.notFound, "sold twice refused")
eq(#B.inbox.children, 1, "still one sword")

-- buy the orbs with coins
op(B, "buy", {id = orbOffer, cur = "coins"})
eq(lastSent(B, "done").what, "buy", "orbs bought")
local coins = {}
for _, r in ipairs(tbl("chaos_shop_coins")) do coins[r.account_id] = r.coins end
eq(coins[20], 400, "buyer's account paid 100 coins")
eq(coins[10], 95, "seller's account got 95 coins (tax 5)")
eq(B.inbox.children[2].count, 20, "20 orbs in the inbox")
local coinNote = false
for _, m in ipairs(A.msgs) do if m:find("+95 Chaos Coins", 1, true) then coinNote = true end end
ok(coinNote, "seller told about the coins (a coins notice row)")
local coinRows = 0
for _, r in ipairs(tbl("chaos_market_deliveries")) do if r.kind == "coins" and r.player_id == 1 and r.delivered == 1 then coinRows = coinRows + 1 end end
eq(coinRows, 1, "coins notice delivered once")
eq(A.bank, 198900 + 95000, "a coins notice adds no gold")
op(B, "buy", {id = orbOffer, cur = "coins"})
eq(coins[20], 400, "no second payment")
B.bank = 50
op(B, "browse", {})

-- not enough money
op(A, "list", {ref = "s3.0", sid = 29856, iid = "0", count = 5, gold = 1000, coins = 900, days = 1})
local third = lastSent(A, "done").id
op(B, "buy", {id = third, cur = "gold"})
eq(lastSent(B, "error").text, cfg.messages.noGold, "not enough gold")
op(B, "buy", {id = third, cur = "coins"})
eq(lastSent(B, "error").text, cfg.messages.noCoins, "not enough coins")

-- cancel
op(B, "cancel", {id = third})
eq(lastSent(B, "error").text, cfg.messages.notFound, "only the seller cancels")
op(A, "cancel", {id = third})
eq(lastSent(A, "done").what, "cancel", "cancelled")
local back = A.inbox.children[1]
eq(back and back.count, 5, "the 5 orbs are back in the seller's inbox")
op(A, "cancel", {id = third})
eq(lastSent(A, "error").text, cfg.messages.notFound, "second cancel refused")
eq(#A.inbox.children, 1, "nothing twice")

-- my offers and history
op(A, "mine")
local mine = lastSent(A, "mine")
eq(#mine.active .. "/" .. #mine.closed, "0/3", "my offers: none active, three closed")
op(B, "history")
eq(#lastSent(B, "history").rows, 2, "buyer history: two purchases")

-- expiry with the seller offline, delivered at login
op(A, "list", {ref = "s3.0", sid = 29856, iid = "0", count = 5, gold = 2000, days = 1})
local fourth = lastSent(A, "done").id
logout(A)
clock = clock + 86400 + 5
events.ChaosMarketSweep.onThink(60000)
local o4 = MK and nil
for _, r in ipairs(tbl("chaos_market_offers")) do if r.id == fourth then o4 = r end end
eq(o4.state, 3, "expired")
local inboxBefore = #A.inbox.children
eq(inboxBefore, 1, "offline: nothing delivered yet")
login(A)
events.ChaosMarketLogin.onLogin(A)
runEvents()
eq(#A.inbox.children, 1, "the orbs stacked onto the cancelled ones")
eq(A.inbox.children[1].count, 10, "5 + 5 orbs back")
op(B, "browse", {})
eq(lastSent(B, "page").total, 0, "expired offers are not listed")

-- a save that fails while listing: everything is given back
A.failSave = true
local bankNow = A.bank
op(A, "list", {ref = "s3.0", sid = 29856, iid = "0", count = 5, gold = 2000, days = 1})
eq(lastSent(A, "error").text, cfg.messages.busy, "listing refused when the save fails")
eq(A.bank, bankNow, "fee given back")
local inBag = 0
for _, it in ipairs(bagA.children) do if it.id == 29856 then inBag = inBag + it.count end end
eq(inBag, 20, "orbs given back")
local pending = 0
for _, r in ipairs(tbl("chaos_market_offers")) do if r.state == 9 then pending = pending + 1 end end
eq(pending, 0, "no pending row left")
A.failSave = false

-- crash between the save and the mark of a delivery: no duplicate
op(A, "list", {ref = "s3.0", sid = 29856, iid = "0", count = 5, gold = 2000, days = 1})
local fifth = lastSent(A, "done").id
B.bank = 100000
op(B, "buy", {id = fifth, cur = "gold"}) -- delivers at once; now replay a crash: unmark the delivery row
local delRow
for _, r in ipairs(tbl("chaos_market_deliveries")) do if r.offer_id == fifth and r.kind == "item" then delRow = r end end
eq(delRow.delivered, 1, "delivered")
delRow.delivered = 0 -- as if the server died after player:save() and before the UPDATE
local nInbox = #B.inbox.children
local count29856 = 0
for _, it in ipairs(B.inbox.children) do if it.id == 29856 then count29856 = count29856 + it.count end end
eq(MK.deliver(B), 0, "nothing applied again")
local count2 = 0
for _, it in ipairs(B.inbox.children) do if it.id == 29856 then count2 = count2 + it.count end end
eq(count2, count29856, "no duplicate orbs")
eq(delRow.delivered, 1, "the row is marked now")

-- a delivery whose save fails is applied once, then only marked after the next save
op(A, "list", {ref = "s3.0", sid = 29856, iid = "0", count = 5, gold = 2000, days = 1})
local sixth = lastSent(A, "done").id
B.failSave = true
op(B, "buy", {id = sixth, cur = "gold"})
eq(lastSent(B, "error").text, cfg.messages.busy, "a purchase needs a save first")
B.failSave = false
op(B, "buy", {id = sixth, cur = "gold"})
local orbsB = 0
for _, it in ipairs(B.inbox.children) do if it.id == 29856 then orbsB = orbsB + it.count end end
eq(orbsB, count2 + 5, "bought once")

-- an interrupted listing (crash): recovered from the saved listSeq
local t0 = os.time()
table.insert(tbl("chaos_market_offers"), {id = 900, state = 9, seller_id = 1, realm = 0, expires = t0 + 999, price_gold = 5, price_coins = 0,
	name = "x", category = "misc", rarity = 0, ilvl = 0, mods = "", count = 1, item_id = 2400, client_id = 2400, seller_name = "Seller",
	seller_account = 10, unique_item = 0, created = t0, buyer_id = 0, buyer_name = "", paid_currency = "", paid_amount = 0, tax = 0, closed_at = 0})
table.insert(tbl("chaos_market_offers"), {id = 901, state = 9, seller_id = 2, realm = 0, expires = t0 + 999, price_gold = 5, price_coins = 0,
	name = "y", category = "misc", rarity = 0, ilvl = 0, mods = "", count = 1, item_id = 2400, client_id = 2400, seller_name = "Buyer",
	seller_account = 20, unique_item = 0, created = t0, buyer_id = 0, buyer_name = "", paid_currency = "", paid_amount = 0, tax = 0, closed_at = 0})
logout(A)
logout(B)
for _, r in ipairs(tbl("player_storage")) do
	if r.player_id == 1 and r.key == cfg.storage.listSeq then r.value = 900 end
end
MK.recoverAll()
local s900, s901 = "gone", "gone"
for _, r in ipairs(tbl("chaos_market_offers")) do
	if r.id == 900 then s900 = r.state end
	if r.id == 901 then s901 = r.state end
end
eq(s900, 0, "listing saved before the crash: activated")
eq(s901, "gone", "listing not saved: dropped (the item stayed with the seller)")
login(A)
login(B)

-- season markets
season = 1
local bagC = Cs.slots[CONST_SLOT_BACKPACK]
local armor = newItem(2463)
armor.custom.rarity = 2
addTo(bagC, armor)
op(Cs, "list", {ref = "s3.0", sid = 2463, iid = "0", gold = 5000, days = 1})
local seasonOffer = lastSent(Cs, "done").id
for _, r in ipairs(tbl("chaos_market_offers")) do if r.id == seasonOffer then eq(r.realm, 1, "offer on the season market") end end
op(B, "browse", {})
local seen = false
for _, r in ipairs(lastSent(B, "page").rows) do if r.id == seasonOffer then seen = true end end
eq(seen, false, "standard characters do not see season offers")
B.bank = 100000
op(B, "buy", {id = seasonOffer, cur = "gold"})
eq(lastSent(B, "error").text, cfg.messages.realm, "nor buy them")
season = 0 -- the season ends: its characters and offers join the standard market
op(B, "browse", {})
seen = false
for _, r in ipairs(lastSent(B, "page").rows) do if r.id == seasonOffer then seen = true end end
eq(seen, true, "after the season the offer is on the standard market")

-- max active offers
cfg.maxActive = 1
Chaos.marketConfig.maxActive = 1
op(Cs, "list", {ref = "s3.0", sid = 1988, iid = "0", gold = 5000, days = 1})
op(A, "list", {ref = "s3.0", sid = 29856, iid = "0", count = 1, gold = 2000, days = 1})
op(A, "list", {ref = "s3.0", sid = 29856, iid = "0", count = 1, gold = 2000, days = 1})
ok(lastSent(A, "error").text:find("active offers"), "max active offers")
Chaos.marketConfig.maxActive = 20

-- the key-list codec (a server without engine patch 0017)
Items.serializeAttributes, Items.unserializeAttributes, Item.serializeAttributes, Item.unserializeAttributes = nil, nil, nil, nil
ChaosMarket = nil
dofile("data/scripts/chaos/market.lua")
local MK2 = ChaosMarket
eq(MK2.hasBlob, false, "no engine methods: key list")
local axe = newItem(2400)
for k, v in pairs({rarity = 4, chaos_ilvl = 90, combatpowerlevel = 90, rarity_firedamage = 7, rarity_firedamage_t = 2, chaos_gem1 = 40001,
	chaos_sockets = 1, chaos_iid = 55}) do axe.custom[k] = v end
axe.std[ITEM_ATTRIBUTE_NAME] = "Old Axe"
local codec, data = MK2.encode(axe)
eq(codec, "attrs", "codec attrs")
local copyAxe = MK2.decode(2400, 1, codec, data)
eq(copyAxe.custom.chaos_iid, nil, "new per-item id")
copyAxe.custom.chaos_iid = 55
blobMethods()
eq(ser(copyAxe), ser(axe), "key-list round trip of the listed keys")
local decodedBlob, why = MK2.decode(2400, 1, "blob", "00")
eq(decodedBlob, nil, "a blob row on a server without the patch is not delivered")
ok(why:find("0017"), "and says why")

print(string.format("market_test: %d checks, %d failed", checks, fails))
os.exit(fails == 0 and 0 or 1)
