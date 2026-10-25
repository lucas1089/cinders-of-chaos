-- Run from the server/ folder: luajit tests/sql_key_guard_test.lua (and lua5.3; CI runs both). Pure logic, no engine.
-- O196, SQL defence in depth. Three cores build statements with a '%s' for a key or a version (achievements_core.lua,
-- class_unlocks_core.lua, legal_notice_core.lua). The key never goes through db.escapeString, so the guard in front of it
-- is the only protection: it must refuse every hostile string and let plain words through. This feeds the guards (and the
-- statement builders behind them) quotes, backslashes, semicolons, comment markers, unicode, control bytes, spaces,
-- empty and over-long strings and non-strings, and checks that a refused key yields no statement at all.
local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end
end

local A = dofile("data/scripts/chaos/achievements_core.lua")
local C = dofile("data/scripts/chaos/class_unlocks_core.lua")
dofile("data/scripts/chaos/legal_notice_core.lua")
local L = ChaosLegalNoticeCore

local HOSTILE = {
	"x'", "x\"", "x'; DROP TABLE players; --", "x' OR '1'='1", "' OR 1=1 --", "x\\", "x\\'", "a;b", "a--b", "a/**/b", "a#b",
	"a b", " a", "a ", "a\n", "\na", "a\r\nb", "a\0b", "\0", "a\tb", "a%b", "a-b", "a.b", "a`b", "`a`", "a(b)", "a,b", "a=b",
	"caf\xC3\xA9", "\xC3\xA9", "\xC0\xAF", "\xEF\xBC\x87", "\xE2\x80\x99", "a\xC2\xA0b", "\xFF\xFE", "\xF0\x9F\x92\xA5",
	"", string.rep("a", 49), string.rep("a", 1000), string.rep("'", 100), "SLEEP(5)", "1 OR 1",
}
local NOT_STRINGS = {1, 1.5, true, false, {}, function() end}
local GOOD = {"a", "kills_total", "Boss_01", "x", string.rep("a", 32)}

-- achievements_core.validKey: [%w_]+, 1..48
for _, h in ipairs(HOSTILE) do
	local want = false
	eq(A.validKey(h), want, "achievements validKey refuses " .. string.format("%q", h):sub(1, 40))
	eq(A.sqlSaveStat(1, h, 5), nil, "no save statement for a hostile key")
	eq(A.sqlOffline(1, h, 5, "add"), nil, "no offline statement for a hostile key")
	eq(A.sqlUnlock(1, h, 5), nil, "no unlock statement for a hostile key")
end
eq(A.validKey(string.rep("a", 48)), true, "48 is the limit")
eq(A.validKey(string.rep("a", 49)), false, "49 is over it")
for _, v in ipairs(NOT_STRINGS) do eq(A.validKey(v), false, "achievements validKey refuses a " .. type(v)) end
eq(A.validKey(nil), false, "achievements validKey refuses nil")
for _, g in ipairs(GOOD) do
	eq(A.validKey(g), true, "achievements validKey accepts " .. g)
	local q = A.sqlSaveStat(1, g, 5)
	eq(q ~= nil and q:find("'" .. g .. "'", 1, true) ~= nil, true, "the plain key is in the statement")
end

-- class_unlocks_core.validKey: [%w_]+, 1..32
for _, h in ipairs(HOSTILE) do
	eq(C.validKey(h), false, "class unlocks validKey refuses " .. string.format("%q", h):sub(1, 40))
	eq(C.sqlInsert(42, h, "store", 1), nil, "no insert for a hostile class key")
	eq(C.sqlInsert(42, "ninja", h, 1), nil, "no insert for a hostile source")
	eq(C.sqlDelete(42, h), nil, "no delete for a hostile class key")
end
eq(C.validKey(string.rep("a", 32)), true, "32 is the limit")
eq(C.validKey(string.rep("a", 33)), false, "33 is over it")
for _, v in ipairs(NOT_STRINGS) do eq(C.validKey(v), false, "class unlocks validKey refuses a " .. type(v)) end
eq(C.validKey(nil), false, "class unlocks validKey refuses nil")
eq(C.sqlInsert(42, "ninja", "store", 1) ~= nil, true, "plain words build the insert")
eq(C.sqlDelete(42, "ninja") ~= nil, true, "plain words build the delete")

-- legal_notice_core: a version is 16 hex digits and nothing else; the statement builders refuse the rest
for _, h in ipairs(HOSTILE) do
	local v = L.cleanVersion(h)
	-- surrounding white space is trimmed on purpose; whatever comes back must be 16 hex digits
	eq(v == nil or (#v == 16 and v:match("^[0-9a-f]+$") ~= nil), true, "cleanVersion returns nothing or 16 hex digits for " .. string.format("%q", h):sub(1, 40))
	eq(L.acceptedSql(1, h), nil, "no statement for a hostile version " .. string.format("%q", h):sub(1, 40))
end
for _, h in ipairs({"x' OR 1=1 -- abcd", "0123456789abcde'", "0123456789abcdefg", "0123456789abcde", "0123456789abcdef0", "0123456789abcde;", "0123456789abcdef'; --", "0123\0456789abcdef"}) do
	eq(L.cleanVersion(h), nil, "cleanVersion refuses " .. string.format("%q", h))
end
eq(L.cleanVersion("0123456789ABCDEF"), "0123456789abcdef", "upper case is lowered")
eq(L.acceptedSql(7, "0123456789abcdef") ~= nil, true, "a good version builds the statement")
eq(L.acceptedSql(0, "0123456789abcdef"), nil, "no account, no statement")
eq(L.acceptedSql(-3, "0123456789abcdef"), nil, "negative account, no statement")
eq(L.acceptedSql("7; DROP TABLE x", "0123456789abcdef"), nil, "a string account that is not a number, no statement")

print(string.format("sql_key_guard_test: %d checks passed", checks))
