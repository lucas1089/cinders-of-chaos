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

-- the ascension section (server ascension_tracker.lua)
V.onAscension(st, { rows = {
  { key = 'calling', title = 'Hear the Calling', progress = 1, target = 1, state = 'done' },
  { key = 'proof', title = 'Slay rare beasts', progress = 4, target = 10, state = 'open' },
  { key = 'trial', title = 'Win the Trial', progress = 0, target = 1, state = 'open' }, 'junk' } })
eq(#st.ascension, 3, 'ascension rows')
local at, ap, ac = V.ascensionLine(st.ascension[1])
eq(at, 'Hear the Calling  Done', 'done row'); eq(ap, 100, 'done percent'); eq(ac, V.STATE_COLOR.done, 'done colour')
at, ap, ac = V.ascensionLine(st.ascension[2])
eq(at, 'Slay rare beasts  4/10', 'count'); eq(ap, 40, 'percent'); eq(ac, V.STATE_COLOR.open, 'open colour')
eq((V.ascensionLine(st.ascension[3])), 'Win the Trial', 'single step: no count')
eq((V.ascensionLine({ title = 'x', target = 5, progress = 99 })), 'x  Done', 'full is done')
V.onAscension(st, { rows = {} })
eq(#st.ascension, 0, 'no rows hides')
V.onAscension(st, nil)
eq(#st.ascension, 0, 'nil payload')
eq(#V.new().ascension, 0, 'new state')

-- the spell quest section (server spellquest_tracker.lua): same rows as the ascension section
V.onSpellQuest(st, { rows = {
  { key = 'kills', title = 'Slay monsters of level 500 or higher', progress = 100, target = 400, state = 'open' }, 'junk' } })
eq(#st.spellquest, 1, 'spellquest rows')
local qt, qp = V.ascensionLine(st.spellquest[1])
eq(qt, 'Slay monsters of level 500 or higher  100/400', 'spellquest count'); eq(qp, 25, 'spellquest percent')
V.onSpellQuest(st, { rows = {} })
eq(#st.spellquest, 0, 'spellquest: no rows hides')
V.onSpellQuest(st, nil)
eq(#st.spellquest, 0, 'spellquest: nil payload')
eq(#V.new().spellquest, 0, 'new state has the section')

-- tracker anchors: same result for the same panels, with and without left side panels
local a = V.trackerAnchors(true)
eq(a[1][2], 'gameLeftPanels', 'anchored to the left panels'); eq(a[1][3], 'right', 'their right edge')
eq(a[2][2], 'gameMapPanel', 'centred on the map')
a = V.trackerAnchors(false)
eq(a[1][2], 'gameMapPanel', 'no left panels: map'); eq(a[1][3], 'left', 'map left edge')

-- phone: row budget, clamp, saved position, drag threshold
local sh, hid = V.budget({ 5, 2, 1 }, 3)
eq(sh[1], 3, 'budget: goals first'); eq(sh[2], 0, 'budget: none left'); eq(sh[3], 0, 'budget: none left 2'); eq(hid, 5, 'budget: hidden')
sh, hid = V.budget({ 1, 2, 1 }, 3)
eq(sh[1], 1, 'budget 1'); eq(sh[2], 2, 'budget 2'); eq(sh[3], 0, 'budget 3'); eq(hid, 1, 'budget: one hidden')
sh, hid = V.budget({ 5, 2 }, nil)
eq(sh[1], 5, 'no max: all'); eq(hid, 0, 'no max: nothing hidden')
eq(V.hiddenLine(0), '', 'no +N line'); eq(V.hiddenLine(4), '+4 more', '+N line')
local cx, cy = V.clampPosition(-30, 900, 150, 100, 1000, 461)
eq(cx, 0, 'clamp left'); eq(cy, 361, 'clamp bottom')
cx, cy = V.clampPosition(990, -5, 150, 100, 1000, 461)
eq(cx, 850, 'clamp right'); eq(cy, 0, 'clamp top')
cx, cy = V.clampPosition(10, 10, 2000, 900, 1000, 461)
eq(cx, 0, 'bigger than the screen: x'); eq(cy, 0, 'bigger than the screen: y')
cx, cy = V.clampPosition(120.7, 40, 150, 100, 1000, 461)
eq(cx, 120, 'inside stays'); eq(cy, 40, 'inside stays y')
local px, py = V.savedPosition({ Jokr = { x = 12, y = 34 } }, 'Jokr')
eq(px, 12, 'saved x'); eq(py, 34, 'saved y')
eq(V.savedPosition({ Jokr = { x = 1 } }, 'Jokr'), nil, 'half a position'); eq(V.savedPosition(nil, 'a'), nil, 'no node')
eq(V.savedPosition({}, 'Other'), nil, 'other character')
eq(V.isDrag(2, 3), false, 'small move is a click'); eq(V.isDrag(0, -6), true, 'big move is a drag')

-- the main quest rows (server mainquest.lua, O551; they replaced the welcome path): one row, the step count in the head
local w = V.new()
eq(#w.welcome, 0, 'no welcome rows at first')
V.onWelcome(w, { title = 'Welcome Path', step = 2, count = 7,
  rows = { { key = 'kills', title = 'Slay 20 monsters', progress = 5, target = 20, state = 'open', hint = 'The hunts.',
    where = { k = 'hunts', pos = { x = 1, y = 2, z = 7 }, label = 'Rats' } }, 'junk' } })
eq(#w.welcome, 1, 'one welcome row, junk dropped')
eq(V.welcomeTitle(w), 'Main Quest 2/7', 'main quest head')
eq(V.welcomeTitle(w, true), 'Main Quest (2/7) +', 'folded main quest head')
local wt, wp = V.ascensionLine(w.welcome[1])
eq(wt, 'Slay 20 monsters  5/20', 'welcome row text'); eq(wp, 25, 'welcome row bar')
eq(V.action(w.welcome[1].where).map.x, 1, 'the row marks the hunt on the map')
-- a resistance step shows its weakest group after the line
local rl = V.welcomeLine({ key = 'res1b', title = 'Prepare', progress = 2, target = 4, state = 'open', detail = 'earth 8/30' })
eq(rl, 'Prepare  2/4  (earth 8/30)', 'the resistance row names the weakest group')
eq(V.welcomeLine(w.welcome[1]), 'Slay 20 monsters  5/20', 'no detail: the plain line')
-- the chapter name rides on the welcome message
V.onWelcome(w, { step = 3, count = 103, chapterName = 'Cinder-Born', rows = { { key = 'a', title = 'x', progress = 0, target = 1 } } })
eq(w.welcomeChapter, 'Cinder-Born', 'the chapter name')
V.onWelcome(w, { rows = {} })
eq(#w.welcome, 0, 'no rows hide the section'); eq(w.welcomeStep, 0, 'step reset')
V.onWelcome(w, nil)
eq(#w.welcome, 0, 'a bad message hides it too')
sh, hid = V.budget({ 1, 3, 0, 0 }, 3)
eq(sh[1], 1, 'budget: the welcome step first'); eq(sh[2], 2, 'budget: then two goals'); eq(hid, 1, 'budget: one goal hidden')

-- the whole quest for the chapter window (server mainquest.lua `mq`)
local mqs = V.new()
V.onMQ(mqs, { state = 0, step = 3, count = 5,
  chapters = { { n = 1, name = 'Cinder-Born', intro = 'a', from = 8, to = 14, done = 2, total = 3 },
    { n = 2, name = 'The Oath of the Forge', intro = 'b', from = 15, to = 29, done = 0, total = 2 },
    { n = 8, name = 'Beyond the Oath', intro = 'c', from = 501, to = 2000, done = 0, total = 0 } },
  steps = { { i = 1, key = 'a', ch = 1, level = 8, title = 'Meet Ysolde', hint = 'h', state = 'done' },
    { i = 2, key = 'b', ch = 1, level = 8, title = 'Cast a spell', hint = 'h', state = 'done' },
    { i = 3, key = 'c', ch = 1, level = 8, title = 'Slay 12 Trolls', hint = 'h', state = 'open' },
    { i = 4, key = 'd', ch = 2, level = 15, title = 'Save a loadout', hint = 'h', state = 'todo' },
    { i = 5, key = 'e', ch = 2, level = 20, title = 'Use an orb', hint = 'h', state = 'todo' } },
  epilogue = { { key = 'raid', level = 800, title = 'Raid', text = 't' } } })
eq(#mqs.mq.chapters, 3, 'three chapters'); eq(#mqs.mq.steps, 5, 'five steps'); eq(#mqs.mq.epilogue, 1, 'one epilogue card')
eq(V.mqChapter(mqs.mq), 1, 'the window opens on the chapter of the open step')
eq(#V.mqSteps(mqs.mq, 2), 2, 'two steps in chapter 2')
eq(V.mqChapterLine(mqs.mq.chapters[1]), 'Cinder-Born  2/3', 'chapter line'); eq(V.mqChapterLine(mqs.mq.chapters[3]), 'Beyond the Oath', 'epilogue has no count')
eq(V.mqStepLine(mqs.mq.steps[1]), '[x] Meet Ysolde', 'a done step'); eq(V.mqStepLine(mqs.mq.steps[3]), '[>] Slay 12 Trolls  (level 8)', 'the open step')
eq(V.mqStepLine(mqs.mq.steps[5]), '[ ] Use an orb  (level 20)', 'a step to come')
V.onMQ(mqs, nil)
eq(#mqs.mq.chapters, 0, 'a bad message empties it'); eq(V.mqChapter(nil), 1)

if fails > 0 then print('goalsview_test: ' .. fails .. ' failure(s)'); os.exit(1) end
print('goalsview_test: ' .. checks .. ' checks OK')
