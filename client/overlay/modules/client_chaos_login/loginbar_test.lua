-- luajit loginbar_test.lua && lua5.3 loginbar_test.lua (from the repository root or this folder)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'loginbar.lua')
local B = ChaosLoginBar
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

local data = { events = 2, boosted = true }
local function with(t)
  local s = { loginPanel = true, events = data.events, boosted = data.boosted }
  for k, v in pairs(t or {}) do s[k] = v end
  return B.state(s)
end
eq(B.key(with()), 'BIOc', 'the sign-in panel with data: schedule and boosted, no casts')
eq(with({ charList = true }).bar, false, 'hidden with the character list (it covered the play hint)')
eq(with({ loginPanel = false }).bar, false, 'hidden when the sign-in panel is not shown (the character select)')
eq(with({ inGame = true }).bar, false, 'hidden in game')
eq(with({ splash = true }).bar, false, 'hidden during the splash')
eq(with({ noRoom = true }).bar, false, 'hidden without room')
eq(B.key(with({ events = 0 })), 'BiOc', 'no event: the schedule panel is hidden')
eq(B.key(with({ boosted = false })), 'BIoc', 'no boosted creature: its panel is hidden')
eq(with({ events = 0, boosted = false }).bar, false, 'no data (service unreachable): no bar')
eq(with({ casts = true }).cast, true, 'casts only when the server has them')
eq(with({ events = 0, boosted = false, casts = true }).bar, true, 'casts alone keep the bar')

eq(B.eventCount(nil), 0, 'no schedule')
eq(B.eventCount({}), 0, 'an empty schedule')
eq(B.eventCount({ { name = 'a' }, { name = 'b' } }), 2, 'a list')
eq(B.eventCount({ x = { name = 'a' } }), 1, 'a map')

local row = B.row({ 'info', 'boost', 'cast' }, { info = true, boost = true }, { info = 300, boost = 200, cast = 200 }, 1001)
eq(#row, 2, 'only the shown panels')
eq(row[1].x, 250, 'centred')
eq(row[2].x, 551, 'side by side')
row = B.row({ 'info', 'boost', 'cast' }, { boost = true }, { info = 300, boost = 200, cast = 200 }, 1000)
eq(row[1].id .. '@' .. row[1].x, 'boost@400', 'a single panel centred')

if fails > 0 then error(fails .. ' failure(s)') end
print('loginbar_test: OK')
