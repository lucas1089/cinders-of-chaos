-- Run from the server/ folder: luajit tests/charges_look_test.lua (and lua5.3; CI runs both)
local checks, fails = 0, 0
local function eq(a, b, what)
	checks = checks + 1
	if a ~= b then
		fails = fails + 1
		print("FAIL " .. what .. ": " .. tostring(a) .. " ~= " .. tostring(b))
	end
end
local K = dofile("data/scripts/chaos/charges_look_core.lua")
eq(K.line(5, 5), "It has 5 charges left.", "full")
eq(K.line(1, 200), "It has 1 charge left (of 200).", "one of 200")
eq(K.line(0, 5), nil, "empty: nothing")
eq(K.line(3, 0), nil, "type without charges: nothing")
eq(K.line(nil, 5), nil, "no charges")
eq(K.append("You see a stone skin amulet.", 4, 5), "You see a stone skin amulet.\nIt has 4 charges left (of 5).", "appended")
eq(K.append("You see a ring (that has 3 charges left).", 3, 5), "You see a ring (that has 3 charges left).", "engine text kept")
eq(K.append("You see x.\nIt has 2 charges left.", 2, 5), "You see x.\nIt has 2 charges left.", "no double line")
eq(K.append(nil, 2, 5), "\nIt has 2 charges left (of 5).", "nil description")
eq(K.append("a", 0, 5), "a", "no charges: unchanged")
print(string.format("charges_look_test: %d checks, %d failed", checks, fails))
os.exit(fails == 0 and 0 or 1)
