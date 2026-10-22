-- luajit patchnotesview_test.lua && lua5.3 patchnotesview_test.lua (CI runs it from the repo root)
-- What the patch notes window draws for a note from the server, the week list text and the login auto-open steps;
-- the Changelog tab: rows by date, tags and client versions, the filter, "new since your last look", the info line.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'patchnotesview.lua')
local V = PatchNotesView
function tr(s, ...) if select('#', ...) > 0 then return string.format(s, ...) end return s end
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- dates
eq(V.formatDate('2026-10-08'), '8 October 2026', 'long date')
eq(V.formatDate('2026-01-31', true), '31 Jan 2026', 'short date')
eq(V.formatDate('2026-13-01'), '2026-13-01', 'bad month kept')
eq(V.formatDate('v3.7.5'), 'v3.7.5', 'not a date')
eq(V.formatDate(nil), '', 'nil')

-- blocks
local note = {
  id = '2026-10-08', title = 'A big week', date = '2026-10-08', intro = { 'Hello.' },
  sections = {
    { name = 'New', kind = 'new', items = {
      { text = 'New contracts every day.', level = 1, lead = 'Bounty board.' },
      { text = 'a sub point', level = 2 },
      { text = 'A paragraph.', level = 0 } } },
    { name = 'Empty', kind = 'changes', items = {} },
    { name = 'Fixes', kind = 'fixes', items = { { text = 'Fixed it.', level = 1 } } },
    { name = 'Known issues', kind = 'mystery', items = { { text = '', level = 1 }, { text = 'x', level = 5 } } }
  }
}
local b = V.blocks(note)
eq(#b, 11, 'block count (empty section and empty bullet skipped)')
eq(b[1].style, 'title', 'title first'); eq(b[1].text, 'A big week', 'title text'); eq(b[1].color, V.TITLE, 'title colour')
eq(b[2].style, 'date', 'date'); eq(b[2].text, '8 October 2026', 'date text')
eq(b[3].style, 'intro', 'intro'); eq(b[3].text, 'Hello.', 'intro text')
eq(b[4].style, 'section', 'section'); eq(b[4].text, 'New', 'section name'); eq(b[4].color, V.COLORS.new, 'new is green')
eq(b[5].style, 'bullet', 'bullet'); eq(b[5].level, 1, 'bullet level'); eq(b[5].bulletColor, V.COLORS.new, 'dot in the section colour')
eq(b[5].lead, 'Bounty board.', 'lead'); eq(b[5].leadColor, V.LEAD, 'lead colour')
eq(b[6].level, 2, 'sub bullet'); eq(b[6].bulletColor, V.DIM, 'sub dot dim'); eq(b[6].lead, nil, 'no lead')
eq(b[7].style, 'paragraph', 'paragraph')
eq(b[8].text, 'Fixes', 'empty section skipped'); eq(b[8].color, V.COLORS.fixes, 'fixes colour')
eq(b[10].color, V.COLORS.other, 'unknown kind: parchment')
eq(b[11].level, 2, 'deep level clamped')

local c = V.colored(b[5])
eq(#c, 4, 'coloured pairs'); eq(c[1], 'Bounty board. ', 'lead with a space'); eq(c[2], V.LEAD, 'lead colour')
eq(c[3], 'New contracts every day.', 'text'); eq(c[4], V.TEXT, 'text colour')
eq(V.colored(b[6]), nil, 'plain bullet')
eq(#V.colored({ lead = 'Only', leadColor = V.LEAD, text = '' }), 2, 'lead only')
eq(V.plain(b[5]), 'Bounty board. New contracts every day.', 'plain with lead')
eq(V.plain(b[6]), 'a sub point', 'plain')

-- bad input from the wire never errors
eq(#V.blocks(nil), 0, 'nil note')
eq(#V.blocks({ title = 5, sections = 'x', intro = { {}, 'ok' } }), 2, 'odd types')
eq(#V.blocks({ sections = { { name = 'New', items = { { text = 'a' } } } } }), 3, 'missing kind and level')

-- parts of a long note
local parts = {
  { id = 'w', title = 'T', date = '2026-10-08', part = 1, parts = 3, intro = { 'Hi' },
    sections = { { name = 'New', kind = 'new', items = { { text = 'a' } } } } },
  { id = 'w', title = 'T', part = 2, parts = 3, intro = {},
    sections = { { name = 'New', kind = 'new', cont = true, items = { { text = 'b' } } },
                 { name = 'Fixes', kind = 'fixes', items = { { text = 'c' } } } } },
  { id = 'w', title = 'T', part = 3, parts = 3, intro = {},
    sections = { { name = 'Balance', kind = 'balance', items = { { text = 'd' } } } } }
}
local j = V.join(parts, 3)
eq(#j.sections, 3, 'joined sections')
eq(#j.sections[1].items, 2, 'continued section joined')
eq(j.sections[1].items[2].text, 'b', 'order kept')
eq(j.sections[2].name, 'Fixes', 'next section')
eq(j.intro[1], 'Hi', 'intro from part 1')
eq(j.date, '2026-10-08', 'date from part 1')
eq(V.join({ parts[1], nil, parts[3] }, 3), nil, 'a missing part')
eq(V.join(nil), nil, 'nothing')
local nc = V.join({ parts[1], { sections = { { name = 'New', kind = 'new', items = { { text = 'x' } } } } } }, 2)
eq(#nc.sections, 2, 'same name without cont is a new section')

-- week list
local w = V.weekText({ id = '2026-10-08', date = '2026-10-08', title = 'A big week', new = true })
eq(w.date, '8 Oct 2026', 'list date'); eq(w.title, 'A big week', 'list title'); eq(w.new, true, 'new')
eq(V.weekText({ id = 'v3.7.5', date = '' }).date, 'v3.7.5', 'undated: id')
eq(V.weekText(nil).new, false, 'nil week')

-- login auto-open
local st = { dailyFirst = true, since = 100 }
eq(V.autoStep(st, false, 100), 'wait', 'daily expected, not there yet')
eq(V.autoStep(st, true, 101), 'wait', 'daily open')
eq(V.autoStep(st, true, 160), 'wait', 'daily open for a minute: still waiting')
eq(V.autoStep(st, false, 161), 'wait', 'daily just closed: short pause')
eq(V.autoStep(st, false, 162), 'show', 'after the pause')
st = { dailyFirst = true, since = 100 }
eq(V.autoStep(st, false, 100 + V.DAILY_WAIT - 1), 'wait', 'expected daily, still within the wait')
eq(V.autoStep(st, false, 100 + V.DAILY_WAIT), 'show', 'expected daily never came')
st = { dailyFirst = false, since = 100 }
eq(V.autoStep(st, false, 100), 'show', 'no daily expected: at once')
st = { dailyFirst = false, since = 100 }
eq(V.autoStep(st, true, 100), 'wait', 'unexpected daily window: wait for it too')
eq(V.autoStep(st, false, 103), 'wait', 'pause after it')
eq(V.autoStep(st, false, 104), 'show', 'then show')

-- changelog
local cl = {
  { id = 'a', date = '2026-10-22', ts = 300, text = 'Bank: deposits work', tags = { 'server', 'content' } },
  { id = 'b', date = '2026-10-22', ts = 300, text = 'New bank window', tags = { 'client', 'server' }, client = 55, pending = false },
  { id = 'c', date = '2026-10-21', ts = 200, text = 'Pending window', tags = { 'client' }, pending = true },
  { id = 'd', date = '2026-10-20', ts = 100, text = 'Site page', tags = { 'website' } },
  { id = 'e', date = '2026-10-20', ts = 100, text = '', tags = { 'server' } },
  'junk', { date = '2026-10-19', ts = 50, text = 'odd tags', tags = 'server' }
}
local rows, shown = V.changelogRows(cl, 'all', 0)
eq(shown, 5, 'entries shown (empty text skipped)')
eq(#rows, 9, 'rows: four dates and five entries')
eq(rows[1].kind, 'date', 'date first'); eq(rows[1].text, '22 October 2026', 'date text')
eq(rows[2].kind, 'entry', 'entry'); eq(rows[2].plain, '[Server] [Content] Bank: deposits work', 'tags in order')
eq(rows[2].color, V.TAG_COLORS.server, 'dot: first tag colour'); eq(rows[2].new, false, 'first look: nothing new')
eq(rows[3].plain, '[Server] [Client 55] New bank window', 'client version')
eq(rows[3].parts[4], V.TAG_COLORS.client, 'client tag colour')
eq(rows[3].parts[#rows[3].parts], V.TEXT, 'text colour last')
eq(rows[4].text, '21 October 2026', 'next date')
eq(rows[5].plain, '[Client: next update] Pending window', 'pending client change')
eq(rows[7].plain, '[Website] Site page', 'website')
eq(rows[9].plain, 'odd tags', 'tags not a list: plain text only')
rows, shown = V.changelogRows(cl, 'client', 0)
eq(shown, 2, 'filter client'); eq(#rows, 4, 'filtered rows keep their dates')
rows, shown = V.changelogRows(cl, 'content', 0)
eq(shown, 1, 'filter content')
rows = V.changelogRows(cl, 'all', 200)
eq(rows[2].new, true, 'newer than the last look'); eq(rows[2].plain, 'NEW [Server] [Content] Bank: deposits work', 'NEW first')
eq(rows[2].parts[2], V.NEW, 'NEW colour'); eq(rows[5].new, false, 'seen')
eq(V.newCount(cl, 200), 2, 'two new'); eq(V.newCount(cl, 0), 0, 'never looked: none new')
eq(V.newestTs(cl), 300, 'newest'); eq(V.newestTs(nil), 0, 'none')
eq(#V.changelogRows(nil, 'all', 0), 0, 'nil list')
eq(#V.changelogRows({ { text = 'x', tags = { 'server' }, ts = 'NaN' } }, 'all', 1), 2, 'odd ts and no date')
local info = V.clientInfo({ version = 54, baseline = 53 }, { baseline = 55, package = 13 })
eq(info.version, 55, 'client version: the highest'); eq(info.build, 13, 'build')
eq(V.clientInfo(nil, nil).version, 0, 'no updater')
eq(V.clientInfo({ version = -4 }, { package = 'x' }).build, 0, 'bad values')
eq(V.infoText('2026-10-21', info), 'Server updated: 21 October 2026     Client: update 55 (build 13)', 'info line')
eq(V.infoText('', { version = 0, build = 13 }), 'Server updated: unknown     Client: build 13', 'unknown server, build only')
eq(V.infoText(nil, { version = 7 }), 'Server updated: unknown     Client: update 7', 'version only')
eq(V.infoText('2026-10-21', nil), 'Server updated: 21 October 2026     Client: version unknown', 'nothing known')
eq(V.tagLabel('nope'), 'All', 'unknown tag label')
eq(V.matches({ tags = { 'server' } }, nil), true, 'no filter')

if fails > 0 then
  print(fails .. ' failure(s)')
  os.exit(1)
end
print('patchnotesview_test: OK')
