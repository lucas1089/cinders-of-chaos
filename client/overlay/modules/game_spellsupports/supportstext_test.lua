-- Run from the repo root: luajit client/overlay/modules/game_spellsupports/supportstext_test.lua (also lua5.3)
local here = (arg and arg[0] or ''):match('^(.*)/[^/]*$') or '.'
dofile(here .. '/supportstext.lua')
local T = SupportsText
local fails, n = 0, 0
local function eq(a, b, name)
  n = n + 1
  if a ~= b then fails = fails + 1; print('FAIL ' .. name .. ': got ' .. tostring(a) .. ', want ' .. tostring(b)) end
end
local function maxLen(k) return function(s) return #s <= k end end

local long = "Heals you for 6% of the spell's damage (at most 8% of your max health per cast)"
eq((T.shorten(long, maxLen(200))), long, 'fits unchanged')
eq(select(2, T.shorten(long, maxLen(200))), false, 'fits flag')
eq((T.shorten('', maxLen(0))), '', 'empty')
eq((T.shorten(long, maxLen(30))), "Heals you for 6% of the...", 'cut at a word')
eq(select(2, T.shorten(long, maxLen(30))), true, 'cut flag')
eq(#T.shorten(long, maxLen(30)) <= 30, true, 'cut fits')
eq((T.shorten(long, maxLen(42))), "Heals you for 6% of the spell's damage...", 'trailing paren dropped')
eq((T.shorten('Supports: one, two, three', maxLen(21))), 'Supports: one, two...', 'trailing comma dropped')
eq((T.shorten('Abcdefghijklmnop qrs', maxLen(8))), 'Abcde...', 'first word cut by chars')
eq((T.shorten('Abcdefghijklmnop', maxLen(2))), '...', 'nothing fits')
-- a fits() that is not about length: at most 2 "lines" of 20 characters (wrap)
local function twoLines(s) return select(2, T.wrap(s, 20):gsub('\n', '')) <= 1 end
local cut = T.shorten(long, twoLines)
eq(twoLines(cut), true, 'two lines fit')
eq(cut:sub(-3), '...', 'two lines ellipsis')
eq(twoLines(cut:sub(1, -4) .. ' damage...'), false, 'longest that fits')

eq(T.wrap('a b c', 60), 'a b c', 'wrap short')
eq(T.wrap('one two three four', 9), 'one two\nthree\nfour', 'wrap lines')
eq(T.wrap('one two three four five', 9, '  '), 'one two\n  three\n  four\n  five', 'wrap indent')
eq(T.wrap('', 9), '', 'wrap empty')
eq(T.wrap('averyveryverylongword x', 5), 'averyveryverylongword\nx', 'wrap long word')
for line in T.wrap(long, 40, '    '):gmatch('[^\n]+') do eq(#line <= 40, true, 'wrap width ' .. line) end

print(string.format('supportstext_test: %d checks, %d failed', n, fails))
if fails > 0 then os.exit(1) end
