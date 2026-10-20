-- Run from the server/ folder: luajit tests/market_test.lua (CI runs it with LuaJIT and Lua 5.3).
-- The Chaos market (data/scripts/chaos/market_core.lua and market.lua) against a mocked engine with a small in-memory
-- SQL database (the statements market.lua writes: SELECT / INSERT / UPDATE / DELETE with WHERE, ORDER BY, LIMIT,
-- transactions and unique keys; table.column names, EXISTS and IN subqueries, GROUP BY ... HAVING COUNT(*), INSERT of
-- several rows). Covers the pure rules (fees, tax, prices, listing refusals, seasons, the Browse query,
-- the codecs, the crash-safety plans) and the flows: listing a rolled legendary item for gold and part of a stack of
-- orbs for coins, browse and filters, tooltips, buying with gold and with coins (money moved with the tax, the item
-- delivered with every attribute and a new per-item id), refusals (own offer, own account, other season, not enough
-- money, sold twice), cancel, expiry with the seller online and offline, a failed transaction rolled back, a save that
-- fails, a crash between save and mark (no duplicate), interrupted listings recovered, and the key-list codec.
-- Buy orders (market_orders_core.lua): order checks, the filter text and matching, fill counts, the list query; posting
-- with the escrow (gold and coins), fills in part and whole with the tax, refusals (own order, own account, other kind,
-- season, a filter that does not fit), cancel and expiry refunds, a failed fill transaction, a failed save, pending
-- fills recovered after a crash, the shared listing limit and the admin report.
-- Sale notifications (market_notify_core.lua): the seller online gets one ITEM SOLD toast and one chat line; three sales
-- while it is offline are queued as sold rows and told once at login ("While you were away"), never again on a relog.
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
DB.unique["chaos_market_offer_mods"] = {{"offer_id", "mod_key"}}
DB.unique["server_config"] = {{"config"}}
-- column defaults of the market tables (sql/chaos_market.sql)
DB.defaults = {
	chaos_market_offers = {buyer_id = 0, buyer_name = "", paid_currency = "", paid_amount = 0, tax = 0, closed_at = 0, sockets = 0,
		quality = 0, free_prefix = 0, free_suffix = 0, has_power = 0, bound_mods = 0, mods_indexed = 0, order_id = 0},
	chaos_market_orders = {filled = 0, refunded = 0, closed_at = 0},
	chaos_market_offer_mods = {value = 0, tier = 0},
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
		elseif c:match("[%(%),=<>%+%-%*%.]") then
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
		if self:is(".") and self:peek(1) and self:peek(1).t == "id" then
			-- table.column: the row of that table in the scope (an outer query's row inside a subquery)
			self:next()
			local tname, col = t.v, self:next().v
			return function(r)
				for i = #DB.scope, 1, -1 do
					if DB.scope[i].name == tname then
						return DB.scope[i].row[col]
					end
				end
				return r[col]
			end
		end
		return function(r) return r[t.v] end
	elseif t.t == "kw" and t.v == "EXISTS" then
		self:expect("(")
		self:expect("SELECT")
		local sub = self:select()
		self:expect(")")
		return function() return #sub() > 0 end
	elseif t.t == "op" and t.v == "-" then
		-- a negative number (a buy order refund row's offer_id is minus the order id)
		local e = self:term()
		return function(r) return -e(r) end
	elseif t.t == "op" and t.v == "(" then
		local e = self:expr()
		self:expect(")")
		return e
	elseif t.t == "kw" and (t.v == "COUNT" or t.v == "ROW_COUNT" or t.v == "LAST_INSERT_ID" or t.v == "GREATEST") then
		self:expect("(")
		if t.v == "COUNT" then
			self:expect("*")
			self:expect(")")
			-- the count of a GROUP BY group (HAVING), else a marker: SELECT COUNT(*) counts the rows
			return function(r) return r and r.__groupCount or "__count" end
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
		if self:accept("SELECT") then
			local sub, fields = self:select()
			self:expect(")")
			local col = fields[1][2]
			return function(r)
				local v = a(r)
				for _, row in ipairs(sub()) do
					if row[col] == v then
						return true
					end
				end
				return false
			end
		end
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

-- SELECT ... (after the keyword): returns a function that runs it (inside the rows of the queries around it) and
-- the fields {expression, alias}
DB.scope = {}
function P:select()
	local p = self
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
	local from
	if p:accept("FROM") then
		from = p:next().v
	end
	local where = p:accept("WHERE") and p:expr() or function() return true end
	local groupBy, having
	if p:accept("GROUP") then
		p:expect("BY")
		groupBy = p:arith()
		if p:accept("HAVING") then
			having = p:expr()
		end
	end
	local keys
	if p:accept("ORDER") then
		p:expect("BY")
		keys = {}
		repeat
			local e = p:arith()
			local desc = p:accept("DESC")
			p:accept("ASC")
			keys[#keys + 1] = {e, desc}
		until not p:accept(",")
	end
	local limit, offset = nil, 0
	if p:accept("LIMIT") then
		limit = p:next().v
		if p:accept("OFFSET") then
			offset = p:next().v
		end
	end
	return function()
		local rows = from and tbl(from) or {{}}
		local out = {}
		for _, r in ipairs(rows) do
			DB.scope[#DB.scope + 1] = {name = from, row = r}
			local okw, hit = pcall(where, r)
			DB.scope[#DB.scope] = nil
			if not okw then error(hit) end
			if hit then
				out[#out + 1] = r
			end
		end
		if groupBy then
			local groups, order = {}, {}
			for _, r in ipairs(out) do
				local k = groupBy(r)
				if not groups[k] then
					groups[k] = copy(r)
					groups[k].__groupCount = 0
					order[#order + 1] = k
				end
				groups[k].__groupCount = groups[k].__groupCount + 1
			end
			out = {}
			for _, k in ipairs(order) do
				if not having or having(groups[k]) then
					out[#out + 1] = groups[k]
				end
			end
		end
		if keys then
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
		local res = {}
		if fields[1][1]({}) == "__count" then
			res[1] = {[fields[1][2]] = #out}
		else
			for i = offset + 1, limit and math.min(#out, offset + limit) or #out do
				local r = {}
				for _, f in ipairs(fields) do
					r[f[2] or "_"] = f[1](out[i])
				end
				res[#res + 1] = r
			end
		end
		return res
	end, fields
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
	elseif p:accept("CREATE") or p:accept("ALTER") then
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
		local tuples = {}
		repeat
			p:expect("(")
			local r = {}
			local n = 0
			repeat
				n = n + 1
				r[cols[n]] = p:arith()({})
			until not p:accept(",")
			p:expect(")")
			for k, v in pairs(DB.defaults[name] or {}) do
				if r[k] == nil then r[k] = v end
			end
			tuples[#tuples + 1] = r
		until not p:accept(",")
		if #tuples > 1 then
			for i, r in ipairs(tuples) do
				if uniqueClash(name, r) then
					return false
				end
				for j = 1, i - 1 do
					local same = true
					for _, key in ipairs(DB.unique[name] or {}) do
						for _, c in ipairs(key) do
							if tuples[j][c] ~= r[c] then same = false end
						end
					end
					if same and DB.unique[name] then return false end
				end
			end
			local t = tbl(name)
			for _, r in ipairs(tuples) do t[#t + 1] = r end
			DB.rowCount = #tuples
			return true
		end
		local row = tuples[1]
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
		if row.id == nil and name:find("^chaos_market") and name ~= "chaos_market_offer_mods" then
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
		return (p:select())()
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
-- the modifiers the mocked tooltip knows: key, label, side, power (value in the attribute, tier in <key>_t, bound <key>_b)
local MOCK_MODS = {{"rarity_firedamage", "Fire Damage", "p"}, {"chaos_mod_attackspeed", "Attack Speed", "p"},
	{"rarity_swordskill", "Sword Fighting", "s"}, {"chaos_mod_life", "Life", "s"}, {"chaos_mod_deathblast", "Death Blast", "s", true}}
ChaosCrafting.affixes = function()
	local out = {}
	for _, m in ipairs(MOCK_MODS) do out[#out + 1] = {key = m[1]} end
	out[#out + 1] = {key = "rarity_criticalhitchance"}
	return out
end
ChaosItemTooltip = {
	build = function(item)
		local mods = {}
		local p, sx = 0, 0
		for _, m in ipairs(MOCK_MODS) do
			local v = item:getCustomAttribute(m[1])
			if v then
				mods[#mods + 1] = {k = m[1], l = m[2], v = v, tr = item:getCustomAttribute(m[1] .. "_t") or 1, sd = m[3],
					bd = item:getCustomAttribute(m[1] .. "_b") == 1 or nil, pw = m[4]}
				if m[3] == "p" then p = p + 1 else sx = sx + 1 end
			end
		end
		local r = tonumber(item:getCustomAttribute("rarity")) or 0
		local lim = r >= 5 and 3 or (r >= 3 and 2 or 1)
		local q = tonumber(item:getCustomAttribute("chaos_quality")) or 0
		local so = tonumber(item:getCustomAttribute("chaos_sockets")) or 0
		return {id = item.id, name = item:getName(), count = item.count, rarity = r, level = tonumber(item:getCustomAttribute("chaos_ilvl")),
			kind = item.id == 2400 and "weapon" or (item.id == 2463 and "armor" or nil), mods = mods,
			sides = r > 0 and {p = p, s = sx, max = lim, mp = lim, ms = lim} or nil, quality = q > 0 and {q = q, cap = 20} or nil,
			sockets = so > 0 and {count = so, max = 3} or nil,
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
	priceMin = 10, priceMax = 900, mod = "Chaos_Mod_AttackSpeed", sort = "price", page = 3}, 1, 1000, cfg, esc)
ok(where:find("`realm` = 1", 1, true), "realm in the query")
eq(MC.realmClause(0, 1), "`realm` <> 1", "standard view during a season: every offer but the season's")
eq(MC.realmClause(0, 0), "`realm` >= 0", "no season: every offer")
eq(MC.realmClause(1, 1), "`realm` = 1", "season view")
ok(where:find("`name` LIKE '%50\\\\%\\\\_ off%'", 1, true), "LIKE escaped: " .. where)
ok(where:find("`category` = 'weapon'", 1, true), "category")
ok(where:find("`price_gold` >= 10", 1, true) and where:find("`price_gold` <= 900", 1, true), "price range")
ok(where:find("EXISTS (SELECT 1 FROM `chaos_market_offer_mods` WHERE `chaos_market_offer_mods`.`offer_id` = `chaos_market_offers`.`id` "
	.. "AND `mod_key` = 'chaos_mod_attackspeed')", 1, true), "the old client's one modifier: one row, key in lower case: " .. where)
eq(order, "`price_gold` ASC, `id` DESC", "sort by gold price")
eq(page .. "/" .. offset, "3/20", "page offset")
where = MC.browseQuery({cat = "nonsense'; DROP", sort = "x", page = -4}, 0, 5, cfg, esc)
ok(not where:find("category"), "unknown category ignored")
eq(select(3, MC.browseQuery({page = 99999}, 0, 5, cfg, esc)), 1000, "page clamped")

-- the modifier filter (C.modFilter / C.modClauses)
local known = {rarity_firedamage = true, chaos_mod_attackspeed = true, rarity_swordskill = true, chaos_mod_deathblast = true,
	rarity_criticalhitchance = true, rarity_arcaneabsorb = true, chaos_mod_life = true}
local mf, why = MC.modFilter({mods = {{k = "rarity_firedamage", min = 10, t = 5}, {k = "Chaos_Mod_AttackSpeed"}}}, cfg, known)
eq(#mf.mods .. "/" .. mf.need, "2/2", "two rows, all needed by default")
eq(mf.mods[1].min .. "/" .. mf.mods[1].tier, "10/5", "min value and tier")
eq(mf.mods[2].key, "chaos_mod_attackspeed", "key in lower case")
mf = MC.modFilter({mods = {{k = "rarity_firedamage", min = -5, t = 99}, {k = "rarity_swordskill", min = "1e400", t = "x"}}, need = 7,
	sockets = 500, quality = -3, freeP = true, freeS = 1, power = "1", bound = "no"}, cfg, known)
eq(mf.mods[1].min .. "/" .. mf.mods[1].tier, "0/8", "negative value and tier above T8 clamped")
eq(mf.mods[2].min .. "/" .. mf.mods[2].tier, "0/0", "unreadable numbers: no limit")
eq(mf.need, 2, "need above the rows: all")
eq(mf.sockets .. "/" .. mf.quality, "8/0", "sockets and quality clamped")
eq(tostring(mf.freePrefix) .. tostring(mf.freeSuffix) .. tostring(mf.power) .. tostring(mf.bound), "truetruetruefalse", "flags")
local seven = {}
for i = 1, 7 do seven[i] = {k = "rarity_firedamage"} end
eq(MC.modFilter({mods = seven}, cfg, known), nil, "seven rows refused")
ok(select(2, MC.modFilter({mods = seven}, cfg, known)):find("6"), "says the limit")
eq(MC.modFilter({mods = {{k = "rarity_firedamage"}, {k = "RARITY_FIREDAMAGE"}}}, cfg, known), nil, "a modifier twice refused")
eq(MC.modFilter({mods = {{k = "rarity_nothing"}}}, cfg, known), nil, "unknown key refused")
eq(MC.modFilter({mods = {{k = "x' OR 1=1 --"}}}, cfg, nil), nil, "a key with other characters refused (no known list)")
eq(MC.modFilter({mods = {{k = "rarity_nothing"}}}, cfg, nil).mods[1].key, "rarity_nothing", "no known list: any well-formed key")
eq(MC.modFilter({mods = "rarity_firedamage"}, cfg, known), nil, "rows that are not a list refused")
eq(MC.modFilter({mods = {"rarity_firedamage"}}, cfg, known), nil, "a row that is not a table refused")
eq(MC.modFilter({mods = {{k = string.rep("a", 60)}}}, cfg, nil), nil, "a key too long refused")
eq(#MC.modFilter({}, cfg, known).mods, 0, "no rows")
eq(select(2, MC.browseQuery({mods = {{k = "rarity_nothing"}}}, 0, 5, cfg, esc, 0, known)), "Unknown modifier.", "Browse refuses it")
local cl = MC.modClauses(MC.modFilter({mods = {{k = "rarity_firedamage", min = 10, t = 5}, {k = "chaos_mod_attackspeed"}}}, cfg, known), cfg, esc)
eq(#cl, 2, "all rows: one EXISTS each")
eq(cl[1], "EXISTS (SELECT 1 FROM `chaos_market_offer_mods` WHERE `chaos_market_offer_mods`.`offer_id` = `chaos_market_offers`.`id` "
	.. "AND `mod_key` = 'rarity_firedamage' AND `value` >= 10 AND `tier` >= 5)", "EXISTS with value and tier")
cl = MC.modClauses(MC.modFilter({mods = {{k = "rarity_firedamage", t = 3}, {k = "chaos_mod_attackspeed", min = 5}, {k = "chaos_mod_life"}},
	need = 2, sockets = 2, quality = 10, freeS = true, power = true, bound = true}, cfg, known), cfg, esc)
eq(cl[1], "`id` IN (SELECT `offer_id` FROM `chaos_market_offer_mods` WHERE (`mod_key` = 'rarity_firedamage' AND `tier` >= 3) OR "
	.. "(`mod_key` = 'chaos_mod_attackspeed' AND `value` >= 5) OR (`mod_key` = 'chaos_mod_life') GROUP BY `offer_id` HAVING COUNT(*) >= 2)",
	"count mode: GROUP BY HAVING")
eq(table.concat(cl, " AND ", 2), "`sockets` >= 2 AND `quality` >= 10 AND `free_suffix` > 0 AND `has_power` = 1 AND `bound_mods` > 0",
	"the other filters")

-- the searchable facts of an offer from its tooltip snapshot (C.offerIndex)
local ix = MC.offerIndex({rarity = 5, mods = {{k = "rarity_firedamage", v = 12, tr = 3, sd = "p"},
	{k = "chaos_mod_attackspeed", v = 9, tr = 2, sd = "p", bd = true}, {k = "chaos_mod_deathblast", v = 13, tr = 6, sd = "s", pw = true},
	{k = "rarity_criticalhitchance", g = "special", v = 2, v2 = 6, tr = 7, sd = "p"}, {k = "Rarity_FireDamage", v = 99}},
	sides = {p = 3, s = 1, max = 3, mp = 3, ms = 4}, quality = {q = 18, cap = 20}, sockets = {count = 2, max = 3}})
eq(#ix.mods, 4, "four modifiers (a key once)")
eq(ix.mods[4].value .. "/" .. ix.mods[4].tier, "6/7", "a critical pair by its amount")
eq(ix.sockets .. "/" .. ix.quality .. "/" .. ix.freePrefix .. "/" .. ix.freeSuffix .. "/" .. ix.hasPower .. "/" .. ix.bound, "2/18/0/3/1/1",
	"sockets, quality, free slots (the extra suffix of the Orb of Ruin counted), power, bound")
ix = MC.offerIndex({rarity = 5, ruined = true, sides = {p = 0, s = 0, max = 3, mp = 3, ms = 3}})
eq(ix.freePrefix .. "/" .. ix.freeSuffix, "0/0", "a ruined item has no free slot")
ix = MC.offerIndex({unique = {name = "x"}, mods = {{k = "rarity_firedamage", v = 5}}, sides = {p = 0, s = 0, mp = 3, ms = 3}})
eq(ix.freePrefix .. "/" .. ix.mods[1].tier, "0/0", "a unique: no free slot, its modifiers have no tier")
eq(#MC.offerIndex(nil).mods, 0, "no tooltip: nothing")
eq(MC.offerIndex({mods = {{k = "bad key'; --", v = 1}}}).mods[1].key, "badkey", "keys sanitized")
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
eq(row.mods, ",rarity_firedamage,chaos_mod_attackspeed,chaos_mod_deathblast,", "mods field stored")
local function modRows(offerId)
	local out = {}
	for _, r in ipairs(tbl("chaos_market_offer_mods")) do
		if r.offer_id == offerId then out[r.mod_key] = r.value .. "/T" .. r.tier end
	end
	return out
end
local mr = modRows(swordOffer)
eq(mr.rarity_firedamage .. " " .. mr.chaos_mod_attackspeed .. " " .. mr.chaos_mod_deathblast, "12/T3 9/T2 13/T1", "modifier rows of the offer")
eq(row.sockets .. "/" .. row.quality .. "/" .. row.free_prefix .. "/" .. row.free_suffix .. "/" .. row.has_power .. "/" .. row.bound_mods
	.. "/" .. row.mods_indexed, "2/18/1/2/1/1/1", "the filter columns (sockets, quality, free prefix / suffix, power, bound, indexed)")
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
op(B, "browse", {rarity = 10})
eq(lastSent(B, "page").total, 0, "rarity filter (Divine)")
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

-- the modifier filter: a third seller lists two more rolled items
local D = newPlayer(5, 50, "Smith", 900000)
login(D)
local bagD = D.slots[CONST_SLOT_BACKPACK]
local function listD(id, attrs, gold)
	local it = newItem(id)
	for k, v in pairs(attrs) do it.custom[k] = v end
	addTo(bagD, it)
	op(D, "list", {ref = "s3." .. (#bagD.children - 1), sid = id, iid = "0", gold = gold, days = 3})
	local d2 = lastSent(D, "done")
	return d2 and d2.id
end
-- an axe: Fire Damage 20 (T6), Attack Speed 4 (T1), no sockets; a free prefix and every suffix free
local axeOffer = listD(2400, {rarity = 5, chaos_ilvl = 140, rarity_firedamage = 20, rarity_firedamage_t = 6, chaos_mod_attackspeed = 4,
	chaos_mod_attackspeed_t = 1}, 30000)
-- an armor: Fire Damage 8 (T2), Sword Fighting 3 (T4), Life 50 (T8), one socket; suffixes full
local armorOffer = listD(2463, {rarity = 3, chaos_ilvl = 120, rarity_firedamage = 8, rarity_firedamage_t = 2, rarity_swordskill = 3,
	rarity_swordskill_t = 4, chaos_mod_life = 50, chaos_mod_life_t = 8, chaos_sockets = 1}, 20000)
ok(axeOffer and armorOffer, "two more offers")
local function found(filter)
	op(B, "browse", filter)
	local pg2 = lastSent(B, "page")
	local ids = {}
	for _, r in ipairs(pg2.rows) do ids[#ids + 1] = r.id end
	table.sort(ids)
	local names = {}
	for _, id in ipairs(ids) do
		names[#names + 1] = id == swordOffer and "sword" or id == axeOffer and "axe" or id == armorOffer and "armor" or id == orbOffer and "orbs" or tostring(id)
	end
	return table.concat(names, ","), pg2.total
end
eq(found({mods = {{k = "rarity_firedamage"}}}), "sword,axe,armor", "one modifier")
eq(found({mods = {{k = "rarity_firedamage"}, {k = "chaos_mod_attackspeed"}}}), "sword,axe", "two modifiers, all of them")
eq(found({mods = {{k = "rarity_firedamage"}, {k = "chaos_mod_attackspeed"}, {k = "chaos_mod_life"}}}), "", "three, all: none has them all")
eq(found({mods = {{k = "rarity_firedamage", min = 15}}}), "axe", "min value")
eq(found({mods = {{k = "rarity_firedamage", min = 12}}}), "sword,axe", "min value is inclusive")
eq(found({mods = {{k = "rarity_firedamage", t = 3}}}), "sword,axe", "T3 or better")
eq(found({mods = {{k = "rarity_firedamage", t = 6}, {k = "chaos_mod_attackspeed"}}}), "axe", "T6 or better and a second row")
eq(found({mods = {{k = "rarity_firedamage", t = 5}, {k = "chaos_mod_attackspeed"}, {k = "rarity_swordskill"}}, need = 2}), "axe",
	"at least 2 of 3")
eq(found({mods = {{k = "rarity_firedamage", t = 5}, {k = "chaos_mod_attackspeed"}, {k = "rarity_swordskill"}}, need = 1}),
	"sword,axe,armor", "at least 1 of 3")
eq(found({mods = {{k = "chaos_mod_life", min = 40, t = 8}, {k = "rarity_swordskill", min = 5}}, need = 1}), "armor",
	"count mode with value and tier limits")
eq(found({mods = {{k = "chaos_mod_life", min = 40, t = 8}, {k = "rarity_swordskill", min = 5}}, need = 2}), "", "count mode: 2 of 2")
eq(found({sockets = 1}), "sword,armor", "a socket or more")
eq(found({sockets = 2}), "sword", "two sockets")
eq(found({quality = 10}), "sword", "quality")
eq(found({freeP = true}), "sword,axe,armor", "a free prefix")
eq(found({freeS = true}), "sword,axe", "a free suffix (the armor's are full)")
eq(found({power = true}), "sword", "a legendary power")
eq(found({bound = true}), "sword", "a bound modifier")
eq(found({mods = {{k = "chaos_mod_deathblast", t = 1}}}), "sword", "a power as a modifier row")
eq(found({mods = {{k = "rarity_firedamage"}}, freeS = true, cur = "gold", sort = "price"}), "sword,axe", "with the other filters")
op(B, "browse", {mods = {{k = "rarity_firedamage"}}, sort = "price", cur = "gold"})
eq(lastSent(B, "page").rows[1].id, armorOffer, "sorting unchanged: cheapest first")
local okRows = {}
for i = 1, 6 do okRows[i] = {k = MOCK_MODS[(i - 1) % 5 + 1][1]} end
okRows[6] = {k = "rarity_criticalhitchance"}
eq(select(2, found({mods = okRows, need = 1})), 3, "six rows work")
local nPages = #B.sent
op(B, "browse", {mods = {{k = "rarity_nothing"}}})
eq(lastSent(B, "error").text, "Unknown modifier.", "an unknown modifier is refused")
okRows[7] = {k = "chaos_mod_life"}
op(B, "browse", {mods = okRows})
ok(lastSent(B, "error").text:find("At most 6"), "seven rows refused")
op(B, "browse", {mods = {{k = "chaos_mod_life"}, {k = "chaos_mod_life", t = 2}}})
ok(lastSent(B, "error").text:find("once"), "a modifier twice refused")
op(B, "browse", {mods = {{k = "rarity_firedamage' OR '1'='1"}}})
eq(lastSent(B, "error").text, "Unknown modifier.", "an injection attempt is refused")
local pagesAfter = 0
for i = nPages + 1, #B.sent do if B.sent[i].msg.action == "page" then pagesAfter = pagesAfter + 1 end end
eq(pagesAfter, 0, "no page for a refused filter")
-- the axe is cancelled: its rows leave the index
op(D, "cancel", {id = axeOffer})
eq(next(modRows(axeOffer)), nil, "a cancelled offer's rows are removed")
eq(found({mods = {{k = "rarity_firedamage", t = 6}}}), "", "and it is not found any more")
op(D, "cancel", {id = armorOffer})


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
local swordDeliveries = 0
for _, r in ipairs(tbl("chaos_market_deliveries")) do if r.offer_id == swordOffer then swordDeliveries = swordDeliveries + 1 end end
eq(swordDeliveries, 0, "no delivery rows")
eq(modRows(swordOffer).rarity_firedamage, "12/T3", "the index rows kept (the DELETE rolled back too)")

-- buy the sword with gold
op(B, "buy", {id = swordOffer, cur = "gold"})
eq(lastSent(B, "done").what, "buy", "bought")
eq(B.bank, 4900000, "price taken from the bank")
eq(tbl("players")[2].balance, 4900000, "and in the database")
eq(tbl("chaos_market_offers")[1].state, 1, "offer sold")
eq(tbl("chaos_market_offers")[1].tax, 5000, "tax recorded")
eq(next(modRows(swordOffer)), nil, "a sold offer's rows are removed in the purchase transaction")
local got = B.inbox.children[1]
ok(got ~= nil, "the sword is in the buyer's inbox")
eq(got.custom.chaos_iid, nil, "a new per-item id (the old one is not copied)")
got.custom.chaos_iid = 777
eq(ser(got), before, "every attribute identical (rarity, item level, modifiers, tiers, bound mark, quality, sockets, gems, power, name, attack)")
eq(A.bank, 198900 + 95000, "seller online: 95,000 net to the bank")
local told = false
for _, m in ipairs(A.msgs) do if m:find("Buyer bought your") then told = true end end
ok(told, "seller told")
local function sentOf(p, action)
	local out = {}
	for _, x in ipairs(p.sent) do
		if x.op == 79 and x.msg and x.msg.action == action then out[#out + 1] = x.msg.message end
	end
	return out
end
local saleToasts = sentOf(A, "sale")
eq(#saleToasts, 1, "seller online: one ITEM SOLD toast")
eq(saleToasts[1], "Buyer bought your magic sword for 100,000 gold (fee 5,000): +95,000 gold to your bank.",
	"the toast: item, price, fee and proceeds")
local soldLines = 0
for _, m in ipairs(A.msgs) do if m:find("bought your magic sword", 1, true) then soldLines = soldLines + 1 end end
eq(soldLines, 1, "one chat line for the sale (not two)")
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

-- sales while the seller is offline: queued as its "sold" delivery rows, summed up once at the next login
for _ = 1, 3 do addTo(bagA, newItem(2463)) end
local plateOffers = {}
for i = 1, 3 do
	op(A, "list", {ref = "s3.1", sid = 2463, iid = "0", gold = 1000000 + i * 400000, days = 1})
	plateOffers[i] = lastSent(A, "done").id
end
logout(A)
local toastsBefore, msgsBefore = #sentOf(A, "sale"), #A.msgs
B.bank = 10000000
for _, r in ipairs(tbl("players")) do if r.id == 2 then r.balance = B.bank end end
for i = 1, 3 do
	op(B, "buy", {id = plateOffers[i], cur = "gold"})
	eq(lastSent(B, "done").what, "buy", "plate " .. i .. " bought")
end
eq(#sentOf(A, "sale"), toastsBefore, "seller offline: nothing sent yet")
eq(#A.msgs, msgsBefore, "nor told in the chat")
local queuedSold = 0
for _, r in ipairs(tbl("chaos_market_deliveries")) do
	if r.player_id == 1 and r.reason == "sold" and r.delivered == 0 then queuedSold = queuedSold + 1 end
end
eq(queuedSold, 3, "three sold rows queued for the seller")
local bankBefore = A.bank
login(A)
events.ChaosMarketLogin.onLogin(A)
runEvents()
local away = sentOf(A, "sale")
eq(#away, toastsBefore + 1, "one summary toast at login")
-- 1.4M + 1.8M + 2.2M = 5.4M; minus 5% fee = 5,130,000 net (rounded down to 5.1M)
eq(away[#away], "While you were away: 3 items sold for 5.1M gold: plate armor, plate armor, plate armor.", "the summary")
eq(A.bank, bankBefore + 5130000, "the proceeds after the fee in the bank")
local feeLine = false
for i = msgsBefore + 1, #A.msgs do
	if A.msgs[i]:find("for 1,400,000 gold (fee 70,000): +1,330,000 gold to your bank.", 1, true) then feeLine = true end
end
ok(feeLine, "a chat line per sale with price, fee and proceeds")
MK.deliver(A, true)
events.ChaosMarketLogin.onLogin(A)
runEvents()
eq(#sentOf(A, "sale"), toastsBefore + 1, "never told twice (relog, another delivery)")
eq(A.bank, bankBefore + 5130000, "nor paid twice")

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

-- the backfill: offers listed before the modifier index existed are indexed once at startup from their tooltips
local tNow = os.time()
local function legacy(id, state, tip)
	table.insert(tbl("chaos_market_offers"), {id = id, state = state, seller_id = 5, realm = 0, expires = tNow + 9999, price_gold = 777,
		price_coins = 0, name = "old " .. id, category = "weapon", rarity = 5, ilvl = 100, mods = ",rarity_firedamage,", count = 1,
		item_id = 2400, client_id = 2400, seller_name = "Smith", seller_account = 50, unique_item = 0, created = tNow, buyer_id = 0,
		buyer_name = "", paid_currency = "", paid_amount = 0, tax = 0, closed_at = 0, tip = tip, sockets = 0, quality = 0, free_prefix = 0,
		free_suffix = 0, has_power = 0, bound_mods = 0, mods_indexed = 0})
end
legacy(950, 0, json.encode({rarity = 5, mods = {{k = "rarity_firedamage", v = 17, tr = 5, sd = "p"}, {k = "chaos_mod_deathblast", v = 9,
	tr = 4, sd = "s", pw = true}}, sides = {p = 1, s = 1, max = 3, mp = 3, ms = 3}, sockets = {count = 3}, quality = {q = 7}}))
legacy(951, 1, json.encode({rarity = 5, mods = {{k = "rarity_firedamage", v = 30, tr = 8}}}))
legacy(952, 0, "not json")
DB.tables["server_config"] = {}
eq(MK.backfillIndex(), 2, "two active offers indexed (the sold one left out)")
mr = modRows(950)
eq(mr.rarity_firedamage .. " " .. mr.chaos_mod_deathblast, "17/T5 9/T4", "rows from the tooltip snapshot")
eq(next(modRows(951)), nil, "a sold offer gets no rows")
local o950, o952
for _, r in ipairs(tbl("chaos_market_offers")) do
	if r.id == 950 then o950 = r elseif r.id == 952 then o952 = r end
end
eq(o950.sockets .. "/" .. o950.quality .. "/" .. o950.free_prefix .. "/" .. o950.free_suffix .. "/" .. o950.has_power .. "/" .. o950.mods_indexed,
	"3/7/2/2/1/1", "columns from the tooltip snapshot")
eq(o952.mods_indexed, 1, "an unreadable tooltip: indexed as nothing")
eq(tbl("server_config")[1].value, "1", "the backfill is recorded")
eq(MK.backfillIndex(), 0, "and runs once")
op(B, "browse", {mods = {{k = "rarity_firedamage", min = 17}, {k = "chaos_mod_deathblast"}}, sockets = 3})
eq(lastSent(B, "page").rows[1].id, 950, "a backfilled offer is found")
Chaos.marketConfig.modIndexVersion = 2
ok(MK.backfillIndex() >= 2, "a new index version builds it again (every active offer)")
eq(modRows(950).rarity_firedamage, "17/T5", "same rows")
eq(tbl("server_config")[1].value, "2", "new version recorded")
Chaos.marketConfig.modIndexVersion = 1
-- an interrupted listing that is dropped takes its rows along
legacy(953, 9, "x")
table.insert(tbl("chaos_market_offer_mods"), {offer_id = 953, mod_key = "rarity_firedamage", value = 1, tier = 1})
logout(D)
MK.recoverAll()
login(D)
eq(next(modRows(953)), nil, "a dropped pending listing leaves no rows")

-- ====================================================================== buy orders (market_orders_core.lua + market.lua)
local MO = ChaosMarketOrders
ok(MO ~= nil, "buy orders core loaded by market.lua")
-- pure rules
local mcfg = Chaos.marketConfig
local o1 = MO.checkOrder(mcfg, {quantity = 100, price = 2000, cur = "gold", days = 3})
eq(o1.total .. "/" .. o1.fee .. "/" .. o1.days, "200000/2000/3", "gold order: total and the fee of a sell offer of that price")
local oc = MO.checkOrder(mcfg, {quantity = 10, price = 50, cur = "coins", days = 1})
eq(oc.total .. "/" .. oc.fee, "500/500", "coins order: 500 coins x 100 gold x 1%")
eq(MO.checkOrder(mcfg, {quantity = 10, price = 50, days = 1}), nil, "no currency")
eq(MO.checkOrder(mcfg, {quantity = 0, price = 50, cur = "gold", days = 1}), nil, "nothing ordered")
ok(select(2, MO.checkOrder(mcfg, {quantity = 1001, price = 500, cur = "gold", days = 1})):find("1,000"), "too many: says the limit")
ok(select(2, MO.checkOrder(mcfg, {quantity = 1, price = 50, cur = "gold", days = 1})):find("between"), "gold price under the minimum")
ok(select(2, MO.checkOrder(mcfg, {quantity = 1000, price = 100000, cur = "coins", days = 1})):find("at most"), "escrow over the maximum")
eq(MO.checkOrder(mcfg, {quantity = 1, price = 500, cur = "gold", days = 5}), nil, "5 days is not an option")
eq(MO.checkOrder(mcfg, {quantity = 1, price = 500, cur = "gold", days = 1, filter = {mods = {{k = "rarity_nothing"}}}}, known), nil,
	"an unknown modifier in the filter")
eq(MO.checkOrder(mcfg, {quantity = "1e400", price = 500, cur = "gold", days = 1}), nil, "an infinite quantity")
local of = MO.checkOrder(mcfg, {quantity = 2, price = 500, cur = "gold", days = 1, filter = {rarity = 22, ilvl = 120,
	mods = {{k = "rarity_firedamage", min = 10, t = 3}, {k = "chaos_mod_attackspeed"}}, need = 1, sockets = 2, quality = 5, freeS = true,
	power = 1, bound = "1"}}, known).filter
eq(of.rarity .. "/" .. of.ilvl .. "/" .. of.need, "10/120/1", "filter clamped (rarity 15 at most, then read as the stored id of Divine), at least one of two rows")
local text = MO.encodeFilter(of)
eq(text, "r=10;l=120;n=1;s=2;q=5;fs=1;pw=1;bd=1;m=rarity_firedamage:10:3,chaos_mod_attackspeed:0:0", "filter text")
local back = MO.decodeFilter(text)
eq(MO.encodeFilter(back), text, "filter round trip")
eq(back.freePrefix, false, "no free prefix asked")
eq(MO.encodeFilter(MO.decodeFilter("")), "", "no filter")
eq(MO.decodeFilter("m=rarity_firedamage:1:0").need, 1, "need defaults to every row")
local wire = MO.filterWire(back)
eq(wire.mods[1].k .. wire.mods[1].min .. wire.mods[1].t .. tostring(wire.mods[2].min) .. wire.need .. tostring(wire.freeP), "rarity_firedamage103nil1nil",
	"the filter as the Browse request's fields")
local function facts(r, l, mods, extra)
	local idx = {mods = mods or {}, sockets = 0, quality = 0, freePrefix = 0, freeSuffix = 0, hasPower = 0, bound = 0}
	for k, v in pairs(extra or {}) do idx[k] = v end
	return {rarity = r, ilvl = l, index = idx}
end
local fire = {key = "rarity_firedamage", value = 12, tier = 3}
local full = facts(10, 130, {fire}, {sockets = 2, quality = 5, freeSuffix = 1, hasPower = 1, bound = 1})
eq(MO.matches(back, full), true, "everything matches")
eq(select(2, MO.matches(back, facts(5, 130, {fire}, {sockets = 2, quality = 5, freeSuffix = 1, hasPower = 1, bound = 1}))),
	"Its rarity is too low.", "rarity")
eq(select(2, MO.matches(back, facts(10, 119, {fire}, {sockets = 2, quality = 5, freeSuffix = 1, hasPower = 1, bound = 1}))),
	"Its item level is too low.", "item level")
eq(select(2, MO.matches(back, facts(15, 130, {{key = "rarity_firedamage", value = 9, tier = 3}}, {sockets = 2, quality = 5, freeSuffix = 1,
	hasPower = 1, bound = 1}))), "Its modifiers do not match.", "value under the minimum")
eq(MO.matches(back, facts(15, 130, {{key = "chaos_mod_attackspeed", value = 1, tier = 1}}, {sockets = 2, quality = 5, freeSuffix = 1,
	hasPower = 1, bound = 1})), true, "one of two rows is enough (need 1)")
local all = MO.decodeFilter("m=rarity_firedamage:10:4,chaos_mod_attackspeed:0:0")
eq(MO.matches(all, facts(0, 0, {fire, {key = "chaos_mod_attackspeed", value = 1, tier = 1}})), false, "T3 is under T4+")
eq(select(2, MO.matches(MO.decodeFilter("s=3"), facts(0, 0, {}, {sockets = 2}))), "Not enough sockets.", "sockets")
eq(select(2, MO.matches(MO.decodeFilter("fp=1"), facts(0, 0))), "It has no free prefix.", "free prefix")
eq(select(2, MO.matches(MO.decodeFilter("pw=1"), facts(0, 0))), "It has no legendary power.", "power")
eq(select(2, MO.matches(MO.decodeFilter("bd=1"), facts(0, 0))), "It has no bound modifier.", "bound")
eq(MO.matches(MO.decodeFilter(""), facts(0, 0)), true, "no filter: any item of the kind")
eq(MO.fillCount({quantity = 30, filled = 0}, 12, nil, true), 12, "a stack gives what it has")
eq(MO.fillCount({quantity = 30, filled = 25}, 12, nil, true), 5, "up to what the order still wants")
eq(MO.fillCount({quantity = 30, filled = 0}, 12, 4, true), 4, "or what the seller asks")
eq(MO.fillCount({quantity = 3, filled = 0}, 1, 5, false), 1, "a single item fills one")
eq(MO.fillCount({quantity = 3, filled = 3}, 9, nil, true), 0, "a full order takes nothing")
local pt, ptax, pnet = MO.payment(mcfg, "gold", 2000, 12)
eq(pt .. "/" .. ptax .. "/" .. pnet, "24000/1200/22800", "a fill pays the seller minus the tax")
local ow = MO.ordersQuery({q = "orb_", cur = "coins", cat = "orb", sort = "price", page = 0}, 0, 77, mcfg, db.escapeString, 1, 9)
ok(ow:find("`realm` <> 1", 1, true) and ow:find("`expires` > 77", 1, true), "standard view during a season")
ok(ow:find("`currency` = 'coins'", 1, true) and ow:find("`category` = 'orb'", 1, true) and ow:find("orb\\\\_", 1, true), "filters: " .. ow)
eq(select(2, MO.ordersQuery({sort = "price"}, 0, 1, mcfg, db.escapeString, 0, 9)), "`price` DESC, `id` ASC", "best paying first")
ok(MO.ordersQuery({mine = true}, 0, 1, mcfg, db.escapeString, 0, 9):find("`buyer_id` = 9", 1, true), "my orders")

-- flows: fresh characters
local E = newPlayer(10, 100, "Wanter", 1000000)
local F = newPlayer(11, 110, "Filler", 0)
local G = newPlayer(12, 100, "WanterAlt", 1000)
local S = newPlayer(13, 130, "Seasoned", 1000)
for _, p in ipairs({E, F, G, S}) do login(p) end
table.insert(tbl("chaos_shop_coins"), {account_id = 110, coins = 1000})
table.insert(tbl("chaos_shop_coins"), {account_id = 100, coins = 0})
local function coinsAcc(acc)
	for _, r in ipairs(tbl("chaos_shop_coins")) do if r.account_id == acc then return r.coins end end
	return 0
end
local function orderRow(id)
	for _, r in ipairs(tbl("chaos_market_orders")) do if r.id == id then return r end end
end
local function dbBalance(guid)
	for _, r in ipairs(tbl("players")) do if r.id == guid then return r.balance end end
end
local function countIn(container, id)
	local n = 0
	for _, it in ipairs(container.children) do if it.id == id then n = n + it.count end end
	return n
end

-- the order form's search
op(E, "orderFind", {q = "29856"})
eq(lastSent(E, "orderFind").items[1].sid, 29856, "a server id")
op(E, "orderFind", {q = "upheaval"})
local found = lastSent(E, "orderFind").items
eq(#found >= 1 and found[1].sid, 29856, "a kind ever listed on the market, by part of its name")
op(E, "orderFind", {q = "2160"})
eq(#lastSent(E, "orderFind").items, 0, "money cannot be ordered")

-- post a gold order: 30 orbs at 2,000 each
op(E, "orderPost", {sid = 2160, quantity = 1, price = 500, cur = "gold", days = 1})
eq(lastSent(E, "error").text, mcfg.messages.orderKind, "crystal coins refused")
op(E, "orderPost", {sid = 29856, quantity = 30, price = 2000, cur = "gold", days = 1})
local goldOrder = lastSent(E, "done").id
ok(goldOrder and goldOrder > 0, "gold order posted")
eq(E.bank, 1000000 - 60000 - 600, "escrow (30 x 2,000) and the fee (1%) left the bank")
eq(dbBalance(10), E.bank, "the database holds the same balance")
local row = orderRow(goldOrder)
eq(row.state .. "/" .. row.escrow .. "/" .. row.fee .. "/" .. row.quantity .. "/" .. row.currency .. "/" .. row.category, "0/60000/600/30/gold/orb",
	"the order row")
op(E, "orderPost", {sid = 29856, quantity = 1000, price = 2000000, cur = "gold", days = 1})
ok(lastSent(E, "error").text:find("at most") or lastSent(E, "error").text:find("needs"), "more than the bank holds is refused")
eq(#tbl("chaos_market_orders"), 1, "and writes nothing")

-- the list
op(F, "orders", {})
local page = lastSent(F, "orders")
eq(page.total .. "/" .. page.rows[1].id .. "/" .. tostring(page.rows[1].mine), "1/" .. goldOrder .. "/nil", "the buyer's order is listed")
eq(page.rows[1].qty .. "/" .. page.rows[1].filled .. "/" .. page.rows[1].price .. "/" .. page.rows[1].cur, "30/0/2000/gold", "row fields")
op(E, "orders", {mine = true})
eq(lastSent(E, "orders").rows[1].mine, true, "my orders")

-- fills: 12 orbs, then 5 of a stack of 20
local bagF = F.slots[CONST_SLOT_BACKPACK]
addTo(bagF, newItem(29856, 12))
op(F, "fillable", {id = goldOrder})
local fl = lastSent(F, "fillable")
eq(#fl.items .. "/" .. fl.items[1].fill .. "/" .. tostring(fl.items[1].why), "1/12/nil", "the seller's matching stack")
op(F, "fill", {id = goldOrder, ref = "s3.0", sid = 29856, iid = "0"})
ok(lastSent(F, "done") and lastSent(F, "done").text:find("22,800"), "fill done: 24,000 minus the 5% tax")
eq(F.bank, 22800, "the seller's gold is in the bank")
eq(countIn(bagF, 29856), 0, "the orbs left the seller")
eq(countIn(E.inbox, 29856), 12, "and reached the buyer's inbox")
row = orderRow(goldOrder)
eq(row.filled .. "/" .. row.escrow .. "/" .. row.state, "12/36000/0", "the order: 12 of 30, escrow 18 x 2,000 left")
local fillRow
for _, r in ipairs(tbl("chaos_market_offers")) do if r.order_id == goldOrder then fillRow = r end end
eq(fillRow.state .. "/" .. fillRow.buyer_id .. "/" .. fillRow.paid_amount .. "/" .. fillRow.tax .. "/" .. fillRow.count, "1/10/24000/1200/12",
	"the fill is a sold offer row")
addTo(bagF, newItem(29856, 20))
op(F, "fill", {id = goldOrder, ref = "s3.0", sid = 29856, iid = "0", count = 5})
eq(countIn(bagF, 29856) .. "/" .. countIn(E.inbox, 29856) .. "/" .. orderRow(goldOrder).filled, "15/17/17", "part of a stack")
op(F, "mine")
eq(lastSent(F, "mine").used, 0, "fills are not active listings")
op(F, "history")
eq(lastSent(F, "history").rows[1].side .. "/" .. lastSent(F, "history").rows[1].order, "sold/" .. goldOrder, "fills in the history")

-- refusals
op(E, "fill", {id = goldOrder, ref = "s3.0", sid = 29856, iid = "0"})
eq(lastSent(E, "error").text, mcfg.messages.ownOrder, "own order")
addTo(G.slots[CONST_SLOT_BACKPACK], newItem(29856, 3))
op(G, "fill", {id = goldOrder, ref = "s3.0", sid = 29856, iid = "0"})
eq(lastSent(G, "error").text, mcfg.messages.ownAccountOrder, "own account")
addTo(G.slots[CONST_SLOT_BACKPACK], newItem(2400))
F.sent = {}
addTo(bagF, newItem(2400))
op(F, "fill", {id = goldOrder, ref = "s3.1", sid = 2400, iid = "0"})
eq(lastSent(F, "error").text, mcfg.messages.orderItem, "another item kind")
season = 1
ChaosSeason.rows[13] = 1
addTo(S.slots[CONST_SLOT_BACKPACK], newItem(29856, 3))
op(S, "fill", {id = goldOrder, ref = "s3.0", sid = 29856, iid = "0"})
eq(lastSent(S, "error").text, mcfg.messages.orderRealm, "a season character cannot fill a standard order")
op(S, "orders", {})
eq(lastSent(S, "orders").total, 0, "nor sees it")
-- a coins order on the season market (posted before season.lua made season markets gold only) cannot be filled
ChaosSeason.marketCurrencyAllowed = function(realm, cur) return realm == 0 or cur ~= "coins" end
Chaos.seasonConfig = {market = {message = "Season markets trade for gold only."}}
table.insert(tbl("chaos_market_orders"), {id = 990, realm = 1, state = 0, buyer_id = 3, buyer_account = 30, buyer_name = "Ashen",
	item_id = 29856, client_id = 29856, name = "Orb of Upheaval", category = "orb", stackable = 1, quantity = 5, filled = 0,
	currency = "coins", price = 5, escrow = 25, refunded = 0, fee = 100, filter = "", created = os.time(), expires = os.time() + 999, closed_at = 0})
op(S, "fill", {id = 990, ref = "s3.0", sid = 29856, iid = "0"})
eq(lastSent(S, "error").text, "Season markets trade for gold only.", "no coins on a season market")
op(S, "open")
eq(lastSent(S, "meta").coinsOk, false, "the window is told: gold only")
op(F, "open")
eq(lastSent(F, "meta").coinsOk, true, "standard market: coins too")
ChaosSeason.marketCurrencyAllowed, Chaos.seasonConfig = nil, nil
for i, r in ipairs(tbl("chaos_market_orders")) do if r.id == 990 then table.remove(tbl("chaos_market_orders"), i) break end end
season = 0

-- a coins order with a filter: Legendary+, item level 100+, Fire Damage 10+ T3+
F.bank = 22800
op(F, "orderPost", {sid = 2400, quantity = 10, price = 50, cur = "coins", days = 3,
	filter = {rarity = 5, ilvl = 100, mods = {{k = "rarity_firedamage", min = 10, t = 3}}}})
local coinOrder = lastSent(F, "done").id
eq(coinsAcc(110) .. "/" .. F.bank, "500/22300", "500 coins escrowed, the 500 gold fee from the bank")
local bagE = E.slots[CONST_SLOT_BACKPACK]
local good = newItem(2400)
for k, v in pairs({rarity = 5, chaos_ilvl = 150, rarity_firedamage = 12, rarity_firedamage_t = 3, chaos_iid = 4242, chaos_sockets = 1}) do good.custom[k] = v end
good.std[ITEM_ATTRIBUTE_NAME] = "Emberfang"
local weak = newItem(2400)
for k, v in pairs({rarity = 3, chaos_ilvl = 150, rarity_firedamage = 12, rarity_firedamage_t = 3, chaos_iid = 4243}) do weak.custom[k] = v end
addTo(bagE, good)
addTo(bagE, weak)
local goodSer = ser(good)
op(E, "fillable", {id = coinOrder})
fl = lastSent(E, "fillable")
eq(#fl.items .. "/" .. tostring(fl.items[1].why) .. "/" .. fl.items[2].why, "2/nil/Its rarity is too low.", "the seller's swords, one fits")
eq(fl.order.filter.rarity .. "/" .. fl.order.filter.mods[1].k, "5/rarity_firedamage", "the order's filter is sent")
op(E, "fill", {id = coinOrder, ref = "s3.1", sid = 2400, iid = "4243"})
eq(lastSent(E, "error").text, "That item does not fit the order: Its rarity is too low.", "a sword that does not fit")
op(E, "fill", {id = coinOrder, ref = "s3.0", sid = 2400, iid = "1"})
eq(lastSent(E, "error").text, mcfg.messages.noItem, "the per-item id must match")
op(E, "fill", {id = coinOrder, ref = "s3.0", sid = 2400, iid = "4242"})
ok(lastSent(E, "done").text:find("magic sword"), "filled with the fitting sword")
eq(coinsAcc(100), 48, "the seller's account: 50 coins minus the 5% tax (2)")
local got
for _, it in ipairs(F.inbox.children) do if it.id == 2400 then got = it end end
ok(got ~= nil, "the sword is in the buyer's inbox")
eq(got.custom.chaos_iid, nil, "with a new per-item id")
got.custom.chaos_iid = 4242
eq(ser(got), goodSer, "and every attribute")
eq(orderRow(coinOrder).filled .. "/" .. orderRow(coinOrder).escrow, "1/450", "1 of 10")

-- cancel: the coins left go back to the account at once
op(E, "orderCancel", {id = coinOrder})
eq(lastSent(E, "error").text, mcfg.messages.orderGone, "only the buyer cancels")
op(F, "orderCancel", {id = coinOrder})
ok(lastSent(F, "done").text:find("450"), "cancelled")
eq(coinsAcc(110), 950, "450 coins refunded")
row = orderRow(coinOrder)
eq(row.state .. "/" .. row.escrow .. "/" .. row.refunded, "2/0/450", "closed, the refund recorded")
op(F, "orderCancel", {id = coinOrder})
eq(lastSent(F, "error").text, mcfg.messages.orderGone, "a second cancel refunds nothing")
eq(coinsAcc(110), 950, "still 950")

-- a fill whose transaction fails: rolled back, the item goes back to the seller's inbox
addTo(bagF, newItem(29856, 2))
local escrowBefore = orderRow(goldOrder).escrow
DB.failOn = "'item', 0, 'order'"
op(F, "fill", {id = goldOrder, ref = "s3.0", sid = 29856, iid = "0", count = 2})
ok(lastSent(F, "done").text:find("back in your inbox"), "the seller is told")
eq(orderRow(goldOrder).escrow .. "/" .. orderRow(goldOrder).filled, escrowBefore .. "/17", "the order is unchanged")
eq(countIn(F.inbox, 29856), 2, "the orbs are in the seller's inbox")
-- a save that fails while filling: nothing moves
F.failSave = true
local inBagF = countIn(bagF, 29856)
op(F, "fill", {id = goldOrder, ref = "s3.0", sid = 29856, iid = "0", count = 1})
eq(lastSent(F, "error").text, mcfg.messages.busy, "refused")
eq(countIn(bagF, 29856), inBagF, "the orbs are given back")
local pend = 0
for _, r in ipairs(tbl("chaos_market_offers")) do if r.state == 9 then pend = pend + 1 end end
eq(pend, 0, "no pending fill row left")
F.failSave = false

-- a crash after the seller's save: the pending fill is completed at the next startup (or returned when the order closed)
local tc = os.time()
table.insert(tbl("chaos_market_offers"), {id = 970, state = 9, realm = 0, seller_id = 11, seller_account = 110, seller_name = "Filler",
	item_id = 29856, client_id = 29856, count = 2, name = "Orb of Upheaval", category = "orb", rarity = 0, ilvl = 0, unique_item = 0, mods = "",
	price_gold = 4000, price_coins = 0, fee = 0, codec = "blob", data = MC.hex(ser(newItem(29856, 2))), tip = "x", created = tc, expires = tc,
	buyer_id = 10, buyer_name = "Wanter", paid_currency = "", paid_amount = 0, tax = 0, closed_at = 0, order_id = goldOrder})
table.insert(tbl("chaos_market_offers"), {id = 971, state = 9, realm = 0, seller_id = 11, seller_account = 110, seller_name = "Filler",
	item_id = 2400, client_id = 2400, count = 1, name = "magic sword", category = "misc", rarity = 5, ilvl = 150, unique_item = 0, mods = "",
	price_gold = 0, price_coins = 50, fee = 0, codec = "blob", data = MC.hex(ser(newItem(2400))), tip = "x", created = tc, expires = tc,
	buyer_id = 11, buyer_name = "Filler", paid_currency = "", paid_amount = 0, tax = 0, closed_at = 0, order_id = coinOrder})
logout(F)
F.storage[cfg.storage.listSeq] = 971
F:save()
MK.recoverAll()
local r970, r971
for _, r in ipairs(tbl("chaos_market_offers")) do
	if r.id == 970 then r970 = r elseif r.id == 971 then r971 = r end
end
eq(r970.state .. "/" .. orderRow(goldOrder).filled, "1/19", "a pending fill of an open order is completed")
eq(r971.state, 2, "a pending fill of a closed order is returned")
login(F)
local bankF = F.bank
MK.deliver(F)
eq(F.bank - bankF, 3800, "the recovered fill's gold (4,000 minus tax)")
eq(countIn(F.inbox, 2400), 2, "the returned sword (next to the one it bought)")

-- expiry: what is left goes back to the buyer (offline: at the next login)
logout(E)
local bankE = E.bank
clock = clock + 2 * 86400
eq(MK.sweepOrders(), 1, "the gold order expired")
row = orderRow(goldOrder)
eq(row.state .. "/" .. row.escrow .. "/" .. row.refunded, "3/0/22000", "11 x 2,000 refunded")
login(E)
events.ChaosMarketLogin.onLogin(E)
runEvents()
eq(E.bank - bankE, 22000, "the refund is in the bank after login")
ok(E.msgs[#E.msgs]:find("back from your buy order"), "and the buyer is told")
op(E, "myOrders")
local mo = lastSent(E, "myOrders")
eq(#mo.active .. "/" .. mo.closed[1].state .. "/" .. mo.closed[1].refunded, "0/expired/22000", "my orders: closed with the refund")

-- buy orders and sell offers share the active-listing limit (Chaos Pact slots included)
Chaos.marketConfig.maxActive = 1
op(E, "orderPost", {sid = 29856, quantity = 1, price = 500, cur = "gold", days = 1})
local limited = lastSent(E, "done").id
op(E, "orderPost", {sid = 29856, quantity = 1, price = 500, cur = "gold", days = 1})
ok(lastSent(E, "error").text:find("active offers and buy orders"), "a second order over the limit")
addTo(bagE, newItem(29856, 4))
local nOffers = #tbl("chaos_market_offers")
op(E, "list", {ref = "s3.1", sid = 29856, iid = "0", count = 1, gold = 2000, days = 1})
ok(lastSent(E, "error").text:find("active offers and buy orders"), "and a sell offer")
eq(#tbl("chaos_market_offers"), nOffers, "nothing listed")
Chaos.marketConfig.maxActive = 20
op(E, "orderCancel", {id = limited})

-- admin visibility
local lines, sums = MK.ordersReport(nil, 50)
eq(#lines .. "/" .. sums.gold, "0/0", "no active order left")
lines = MK.ordersReport(10, 50)
ok(#lines >= 2 and lines[1]:find("Wanter"), "one character's orders, every state: " .. tostring(lines[1]))
-- money check: everything E paid into its gold order went to the sellers, the tax or back to E
local paid = 0
for _, r in ipairs(tbl("chaos_market_offers")) do if r.order_id == goldOrder and r.state == 1 then paid = paid + r.paid_amount end end
eq(paid + orderRow(goldOrder).refunded, 60000, "fills + refund = the escrow")

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
