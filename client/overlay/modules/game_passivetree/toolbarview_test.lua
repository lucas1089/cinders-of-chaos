-- run from the repo root: luajit client/overlay/modules/game_passivetree/toolbarview_test.lua (and lua5.3)
local dir = arg[0]:match('^(.*)/[^/]*$') or '.'
dofile(dir .. '/toolbarview.lua')
local T = TreeToolbar
local function eq(a, b, m) if a ~= b then error((m or '') .. ' expected ' .. tostring(b) .. ' got ' .. tostring(a), 2) end end

-- 8 buttons in a 1024 px window: 12 px sides, 4 px gaps
local r = T.row(1024, 8, 4, 12, 150)
eq(r.width, 121, 'width'); eq(r.left, 14, 'left')
-- capped at max on a wide window, the row centred
r = T.row(1920, 8, 4, 12, 150)
eq(r.width, 150); eq(r.left, math.floor((1920 - (150 * 8 + 28)) / 2))
-- a narrow window: the buttons shrink, never below 0, the row stays inside
r = T.row(800, 8, 4, 12, 150)
eq(r.width, 93); eq(r.left + r.width * 8 + 28 <= 800 - 12, true, 'inside')
eq(T.row(10, 8, 4, 12, 150).width, 0)
eq(T.row(500, 0, 4, 12).width, 0)

-- fit: 6 px per byte
local function measure(s) return #s * 6 end
local text, cut = T.fit('Primary: Strength', 200, measure)
eq(text, 'Primary: Strength'); eq(cut, false)
text, cut = T.fit('Primary: Dexterity, Distance skill, Physical damage', 120, measure)
eq(cut, true); eq(text:sub(-3), '...'); eq(#text * 6 <= 120, true, 'fits')
eq(text, 'Primary: Dexterit...')
text = T.fit('Primary: Dexterity, Distance skill, Physical damage', 132, measure)
eq(text, 'Primary: Dexterity...', 'trailing comma and space dropped')
text = T.fit('abc', 6, measure)
eq(text, '...')
eq((T.fit('', 10, measure)), '')
-- a UTF-8 character is never cut in two
text = T.fit('Secund\195\161rio: Vida', 48, measure)
eq(text, 'Secun...')
text = T.fit('Secund\195\161rio: Vida', 54, measure)
eq(text, 'Secund...')
text = T.fit('Secund\195\161rio: Vida', 66, measure)
eq(text, 'Secund\195\161...')
print('toolbarview_test: ok')
