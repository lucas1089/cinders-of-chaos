-- luajit journeyview_test.lua && lua5.3 journeyview_test.lua (CI runs it from the repo root)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'journeyview.lua')
local V = JourneyView
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- a header as season_journey.lua sends it
local st = V.new()
V.onHeader(st, { name = 'The Ashen Pilgrimage', set = 'Ashen Pilgrim', pieces = 1, piecesTotal = 9, finished = 1,
  current = 2, mode = 'Hardcore', chapters = {
    { key = 'embers', name = 'First Embers', state = 'done', done = 7, total = 7, level = 0 },
    { key = 'ironash', name = 'Ash and Iron', state = 'open', done = 2, total = 9, level = 150, text = 'Dungeons.' },
    { key = 'road', name = 'The Burning Road', state = 'locked', level = 250, lockedWhy = 'Finish Ash and Iron first.',
      done = 0, total = 8 },
    'junk' } })
eq(#st.chapters, 3, 'three chapters (junk dropped)')
eq(st.selected, 2, 'the current chapter is selected')
eq(V.title(st.header), 'The Ashen Pilgrimage  -  Hardcore', 'title with mode')
eq(V.summary(st.header, #st.chapters), 'Chapters 1 / 3   Ashen Pilgrim set 1 / 9', 'summary')
eq(V.chapterLabel(st.chapters[2], 2), 'II. Ash and Iron', 'chapter label')
eq(V.chapterStatus(st.chapters[1]), 'Complete', 'done status')
eq(V.chapterStatus(st.chapters[2]), '2 / 9', 'open status')
eq(V.chapterStatus(st.chapters[3]), 'Lv 250', 'locked status')
eq(V.chapterNote(st.chapters[3]), 'Locked: Finish Ash and Iron first.', 'locked note')
eq(V.chapterNote(st.chapters[2]), 'Dungeons.', 'open note')

-- chapter details
V.onChapter(st, { index = 2, objectives = {
  { key = 'lvl200', text = 'Reach level 200', target = 200, progress = 173 },
  { key = 'rift4', text = 'Seal a tier 4 rift', target = 4, progress = 4, done = true },
  { key = 'hc', text = 'Hardcore: seal a rift without a death', target = 1, progress = 0, only = 'hc' } },
  rewards = { { kind = 'passxp', text = '2000 pass XP' }, { kind = 'look', text = 'Magma Coat appearance', piece = true,
    clientId = 8000 } } })
V.onChapter(st, { index = 'x' })
V.onChapter(st, { index = 99 })
eq(#st.details[2].objectives, 3, 'objectives stored')
local r1 = V.objectiveRow(st.details[2].objectives[1])
eq(r1.percent, 86, 'percent')
eq(r1.label, '173 / 200', 'label')
local r2 = V.objectiveRow(st.details[2].objectives[2])
eq(r2.label, 'Done', 'done label')
eq(r2.percent, 100, 'done percent')
eq(V.objectiveRow({ text = 'x', target = 5, progress = 99 }).label, '5 / 5', 'progress capped')
eq(V.objectiveRow({ text = 'x', target = 0, progress = -3 }).label, '0 / 1', 'bad numbers')
local pv = V.objectiveRow(st.details[2].objectives[3], true)
eq(pv.text, 'Hardcore: seal a rift without a death', 'preview text')
eq(pv.tag, nil, 'no tag when the text starts with the mode')
eq(V.objectiveRow({ text = 'Place an order on the Orb Exchange', target = 1, only = 'nossf' }).tag, 'Not Self-Found', 'mode tag')
eq(pv.label, 'Goal: 1', 'preview goal')
eq(V.rewardLine(st.details[2].rewards[2]), 'Magma Coat appearance (set)', 'set piece reward')
eq(V.rewardLine(st.details[2].rewards[1]), '2000 pass XP', 'plain reward')

-- a new header keeps details of unchanged chapters and the selection
V.select(st, 3)
V.onHeader(st, { name = 'The Ashen Pilgrimage', chapters = {
  { key = 'embers', state = 'done' }, { key = 'ironash', state = 'done' }, { key = 'road', state = 'open' } }, current = 3 })
eq(st.selected, 3, 'selection kept')
eq(#st.details[2].objectives, 3, 'details kept')
eq(V.select(st, 9), 3, 'selecting a missing chapter does nothing')
-- a different journey drops the details
V.onHeader(st, { name = 'Other', chapters = { { key = 'frost', state = 'open' } } })
eq(st.details[2], nil, 'details dropped')
eq(st.selected, 1, 'selection reset to an existing chapter')
-- no journey
V.onHeader(st, { none = true })
eq(V.title(st.header), 'No journey this season', 'none title')
eq(V.summary(st.header), '', 'none summary')
eq(#st.chapters, 0, 'none: no chapters')

-- preview and the first chapter fallback
local p = V.new()
V.onHeader(p, { name = 'J', preview = true, set = 'S', pieces = 0, piecesTotal = 9,
  chapters = { { key = 'a', state = 'preview', total = 7 }, { key = 'b', state = 'preview', total = 9 } } })
eq(p.selected, 1, 'preview selects the first chapter')
eq(V.chapterStatus(p.chapters[2]), '9 goals', 'preview status')
eq(V.summary(p.header, 2), 'Preview   S set 0 / 9', 'preview summary')
eq(V.lastOpen({ { state = 'done' }, { state = 'done' }, { state = 'locked' } }), 2, 'last finished when none open')

-- banners
eq(V.doneText({ text = 'Seal a tier 4 rift' }), 'Objective done: Seal a tier 4 rift', 'objective banner')
eq(V.doneText({ text = 'Ash and Iron', chapter = 2 }), 'Chapter complete: Ash and Iron!', 'chapter banner')
eq(V.roman(8), 'VIII', 'roman')
eq(V.roman(20), '20', 'roman fallback')

if fails > 0 then print('journeyview_test: ' .. fails .. ' failure(s)'); os.exit(1) end
print('journeyview_test: OK')
