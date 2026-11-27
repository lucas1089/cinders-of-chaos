-- Items to the inbox (F47, O773): the engine's Inbox refuses every add without FLAG_NOLIMIT (inbox.cpp Inbox::queryAdd
-- answers "not enough room") and Container:addItem makes at most 100 of a stackable, so a plain inbox:addItem(id, n)
-- deleted the item. A login reward with a full backpack (the community goal token) was lost that way.
-- Checks Chaos.giveToInbox / Chaos.giveOrInbox on a mock with the engine's rules, and that no server script adds to an
-- inbox without the flag. Run from server/: luajit tests/inbox_flag_test.lua (also lua5.3).
local checks, failures = 0, 0
local function check(cond, label)
	checks = checks + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, tostring(label or "check") .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end

local STACK = {[29856] = true, [2152] = true}
function ItemType(id)
	return {isStackable = function() return STACK[id] == true end}
end
dofile("data/scripts/chaos/chaos_constants.lua")

-- a character whose backpack holds `room` more items; the inbox with the engine's rules
local function mkPlayer(room, noInbox)
	local p = {items = {}, room = room, inbox = {}, adds = {}}
	function p:getItemCount(id) return self.items[id] or 0 end
	function p:addItem(id, n)
		local k = math.min(n, self.room)
		self.room = self.room - k
		self.items[id] = (self.items[id] or 0) + k
		return k > 0 and {} or nil
	end
	function p:getInbox()
		if noInbox then
			return nil
		end
		local me = self
		return {addItem = function(_, id, n, index, flags)
			me.adds[#me.adds + 1] = {id = id, n = n, flags = flags}
			if flags ~= (FLAG_NOLIMIT or 1) then
				return nil -- RETURNVALUE_CONTAINERNOTENOUGHROOM: the item is deleted
			end
			if STACK[id] then
				n = math.min(n, 100)
				me.inbox[id] = (me.inbox[id] or 0) + n
			else
				me.inbox[id] = (me.inbox[id] or 0) + 1
			end
			return {}
		end}
	end
	return p
end

-- giveToInbox: stacks of 100 with the flag; one call per item for the rest, with its subType
local p = mkPlayer(0)
eq(Chaos.giveToInbox(p, 29856, 250), 250, "250 orbs land")
eq(p.inbox[29856], 250, "in the inbox")
eq(#p.adds, 3, "three stacks: 100, 100, 50")
eq(p.adds[3].n, 50, "the last stack")
check(p.adds[1].flags == (FLAG_NOLIMIT or 1), "with FLAG_NOLIMIT")
p = mkPlayer(0)
eq(Chaos.giveToInbox(p, 2268, 3, 5), 3, "three runes")
eq(#p.adds, 3, "one add per rune")
eq(p.adds[1].n, 5, "each with its charges")
eq(Chaos.giveToInbox(mkPlayer(0, true), 29856, 5), 0, "no inbox: nothing")
eq(Chaos.giveToInbox(mkPlayer(0), 29856, 0), 0, "nothing asked")

-- giveOrInbox: backpack first, the rest to the inbox
p = mkPlayer(3)
local bp, box = Chaos.giveOrInbox(p, 29856, 5)
eq(bp, 3, "three fit the backpack")
eq(box, 2, "two to the inbox")
eq(p.items[29856] + p.inbox[29856], 5, "nothing lost")
p = mkPlayer(10)
bp, box = Chaos.giveOrInbox(p, 29856, 5)
eq(bp, 5, "room: all in the backpack")
eq(box, 0, "the inbox untouched")
eq(#p.adds, 0, "no inbox call")
p = mkPlayer(0)
bp, box = Chaos.giveOrInbox(p, 2152, 120)
eq(bp + box, 120, "full backpack: all 120 coins in the inbox")

-- the old pattern loses the item on this mock: what the scan below forbids
p = mkPlayer(0)
p:getInbox():addItem(29856, 2)
eq(p.inbox[29856], nil, "a plain inbox:addItem is refused")

-- no server script adds to an inbox without the flag (a variable named *inbox* or *box*, or getInbox():addItem)
local ALLOWED = { -- a flags variable that carries FLAG_NOLIMIT, checked where it is built
	["data/scripts/chaos/market.lua"] = "addFlags",
	["data/scripts/chaos/store_delivery.lua"] = "placeFlags",
}
local function listLua()
	local out = {}
	local pipe = io.popen('find data -name "*.lua" -not -name "*_test.lua" 2>/dev/null')
	if pipe then
		for line in pipe:lines() do
			out[#out + 1] = line
		end
		pipe:close()
	end
	return out
end
local files, bad = listLua(), {}
check(#files > 100, "server Lua files found (" .. #files .. ")")
for _, path in ipairs(files) do
	local fh = io.open(path, "r")
	if fh then
		local n = 0
		for line in fh:lines() do
			n = n + 1
			local code = line:gsub("%-%-.*$", "")
			local hit = code:find("[%w_]*[Bb]ox[%w_]*%s*:%s*addItem") or code:find("getInbox%(%)%s*:%s*addItem")
			if hit and not code:find("FLAG_NOLIMIT", 1, true)
				and not (ALLOWED[path] and code:find(ALLOWED[path], 1, true)) then
				bad[#bad + 1] = path .. ":" .. n .. ": " .. line:gsub("^%s+", "")
			end
		end
		fh:close()
	end
end
for _, b in ipairs(bad) do
	print("  inbox add without FLAG_NOLIMIT: " .. b)
end
eq(#bad, 0, "every inbox add carries FLAG_NOLIMIT")

print(string.format("inbox_flag_test: %d checks, %d failures", checks, failures))
if failures > 0 then
	os.exit(1)
end
