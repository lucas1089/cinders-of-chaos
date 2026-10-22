-- luajit goalsview_test.lua && lua5.3 goalsview_test.lua (CI runs it from the repo root)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'goalsview.lua')
local V = GoalsView
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- a panel as goals.lua sends it (server goals_core.lua K.view)
local st = V.new()
V.onGoals(st, {
  header = { level = 305, done = 14, total = 30, more = 2, next = 500, nextName = 'Hardened',
    band = { key = 'bosses', name = 'World bosses', from = 300, to = 499, index = 6, count = 13 } },
  goals = {
    { key = 'wb1', level = 300, state = 'open', title = 'Defeat a world boss', why = 'Set pieces.', effort = 'Every 6 hours.',
      where = { k = 'info', page = 'events' }, progress = 0, target = 1, reward = '1,000 XP, 7,625 gold' },
    { key = 'rift6', level = 300, state = 'open', title = 'Seal a tier 6 rift', progress = 4, target = 6,
      where = { k = 'npc', name = 'Keeper', pos = { x = 100, y = 200, z = 7 }, label = 'Keeper of Trials' } },
    { key = 'lvl300', level = 200, state = 'done', title = 'Reach level 300', progress = 300, target = 300, reward = 'x' },
    'junk' },
  upcoming = { { key = 'lvl500', level = 300, state = 'locked', title = 'Reach level 500', target = 500 } },
  gear = { { text = 'World bosses roll a piece of their set.', where = { k = 'info', page = 'events' } } },
  hunts = { { id = 'widowmere', name = 'Widowmere', lo = 480, hi = 640, where = { k = 'plan', id = 'widowmere' } } },
  hereWhere = { k = 'hunts' } })
eq(#st.goals, 3, 'junk dropped')
eq(V.headerLine(st.header), 'Level 300-499: World bosses', 'header')
eq(V.headerLine({ band = { from = 2000, name = 'The apex' } }), 'Level 2000+: The apex', 'last band')
eq(V.headerLine(nil), 'Next Goals', 'no header yet')
eq(V.summaryLine(st.header), 'Goals done: 14 / 30   Next band at level 500: Hardened', 'summary')
eq(V.summaryLine({ done = 1, total = 2 }), 'Goals done: 1 / 2', 'summary at the last band')
eq(V.bandPercent(st.header), 46, 'band percent')
eq(V.moreLine(st.header), 'and 2 more from earlier levels', 'more line')
eq(V.moreLine({ more = 0 }), '', 'no more line')

local r1 = V.goalRow(st.goals[1])
eq(r1.label, 'Not yet', 'a single step goal')
eq(r1.percent, 0, 'percent 0')
eq(r1.button, 'Open', 'a window button')
eq(r1.reward, 'Reward: 1,000 XP, 7,625 gold', 'reward')
local r2 = V.goalRow(st.goals[2])
eq(r2.label, '4 / 6', 'progress label')
eq(r2.percent, 66, 'progress percent')
eq(r2.button, 'Show on map', 'map button')
local r3 = V.goalRow(st.goals[3])
eq(r3.label, 'Done', 'done')
eq(r3.percent, 100, 'done percent')
eq(r3.reward, '', 'no reward line once done')
eq(r3.button, nil, 'no button once done')
local up = V.goalRow(st.upcoming[1])
eq(up.label, 'Unlocks at level 300', 'locked label')
eq(up.button, nil, 'no button when locked')
eq(V.upcomingLine(st.upcoming[1]), 'Level 300: Reach level 500', 'upcoming line')
eq(V.goalRow({ title = 'x', target = 5, progress = 99 }).label, '5 / 5', 'progress capped')
eq(V.goalRow({ title = 'x', target = 0, progress = -1 }).label, 'Not yet', 'bad numbers')

-- actions
local a = V.action({ k = 'window', m = 'game_bounty', f = 'toggle' })
eq(a.call, 'game_bounty.toggle', 'window action')
eq(V.action({ k = 'info', page = 'rift' }).args[1], 'rift', 'info page')
eq(V.action({ k = 'tasks' }).call, 'game_bestiary.showTasks', 'tasks')
eq(V.action({ k = 'finder', id = 2160 }).args[1], 2160, 'item finder')
local m = V.action(st.goals[2].where)
eq(m.map.x, 100, 'map x')
eq(m.label, 'Keeper of Trials', 'map label')
eq(V.action({ k = 'npc', name = 'x' }), nil, 'an NPC without a position does nothing')
eq(V.action({ k = 'hunts' }).call, 'game_bestiary.show', 'hunts without a position: the bestiary')
eq(V.action({ k = 'window', m = 'game_x' }), nil, 'a window without a function')
eq(V.action(nil), nil, 'nothing')
eq(V.whereButton({ k = 'plan', id = 'x' }), nil, 'an unresolved plan has no button')
eq(V.whereButton({ k = 'hunts' }), 'Bestiary', 'hunts button')
eq(V.huntLine(st.hunts[1]), 'Widowmere (levels 480-640)', 'hunt line')

-- tracker
V.onTracker(st, { rows = { { key = 'wb1', title = 'Defeat a world boss', progress = 0, target = 1 },
  { key = 'rift6', title = 'Seal a tier 6 rift', progress = 4, target = 6 }, 7 } })
eq(#st.tracker, 2, 'tracker rows')
local text, pct = V.trackerLine(st.tracker[2])
eq(text, 'Seal a tier 6 rift  4/6', 'tracker text')
eq(pct, 66, 'tracker percent')
eq((V.trackerLine(st.tracker[1])), 'Defeat a world boss', 'single step: no count')
V.onTracker(st, nil)
eq(#st.tracker, 0, 'empty tracker')
eq(V.doneText({ text = 'Seal a tier 6 rift' }), 'Goal done: Seal a tier 6 rift', 'done banner')
eq(V.doneText(nil), '', 'no banner')
V.onGoals(st, nil)
eq(st.header, nil, 'reset')

-- the tracker wraps long goals instead of cutting them
local w, n = V.wrapLine('Defeat a boss of the Ashen Sepulchre  1/3', 28)
eq(w, 'Defeat a boss of the Ashen\nSepulchre 1/3', 'wrapped at a space')
eq(n, 2, 'two lines')
eq(select(2, V.wrapLine('Slay an Omen guardian', 28)), 1, 'short goal: one line')
eq((V.wrapLine('', 28)), '', 'empty text')
eq(select(2, V.wrapLine('', 28)), 1, 'empty text still one line')
eq((V.wrapLine('Averyveryverylongwordwithoutspaces x', 10)), 'Averyveryverylongwordwithoutspaces\nx', 'a long word on its own line')

if fails > 0 then print('goalsview_test: ' .. fails .. ' failure(s)'); os.exit(1) end
print('goalsview_test: ' .. checks .. ' checks OK')
