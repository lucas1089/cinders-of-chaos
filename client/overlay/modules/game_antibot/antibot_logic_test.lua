-- luajit antibot_logic_test.lua && lua5.3 antibot_logic_test.lua (CI runs every client/overlay/modules/*/*_test.lua)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'antibot_logic.lua')
local L = AntibotLogic
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- the check payload
local c = L.parseCheck({ t = 'Tok123', w = 'Apple', s = 75, a = 1, r = 1,
  o = { { k = 'aaaaaa', c = 3585 }, { k = 'bbbbbb', c = 3587 }, { k = 'cccccc', c = 3003 }, { k = 'dddddd', c = 3031 } } })
eq(c and #c.options, 4, 'four options')
eq(c.word, 'Apple', 'word')
eq(c.options[2].clientId, 3587, 'client id')
eq(c.retries, 1, 'retries')
eq(L.parseCheck({ t = 'x', w = 'Apple', o = { { k = 'a', c = 0 }, { k = 'b', c = 5 } } }), nil, 'bad client id')
eq(L.parseCheck({ t = 'x', w = 'Apple', o = { { k = 'a', c = 5 } } }), nil, 'at least two pictures')
eq(L.parseCheck({ w = 'Apple', o = {} }), nil, 'no token')
eq(L.parseCheck('nope'), nil, 'not a table')
eq(L.prompt('Fishing Rod'), 'Click the picture of: Fishing Rod', 'prompt')
local a = L.answer(c, 'cccccc')
eq(a.t, 'Tok123', 'answer token')
eq(a.k, 'cccccc', 'answer key')

-- countdown
eq(L.timeText(75), '1:15', 'time text')
eq(L.timeText(5), '0:05', 'seconds')
eq(L.timeText(-3), '0:00', 'never negative')
eq(L.timeColor(60), L.COLORS.text, 'calm')
eq(L.timeColor(20), L.COLORS.warn, 'hurry')
eq(L.timeColor(8), L.COLORS.bad, 'last seconds')
eq(L.timePercent(30, 60), 50, 'bar')
eq(L.timePercent(90, 60), 100, 'bar capped')
eq(L.retryText(1), 'Another picture', 'retry button')
eq(L.retryText(0), 'No more pictures', 'retry used')

-- reports
eq(#L.parseReasons(nil), 6, 'default reasons')
eq(L.parseReasons({ { k = 'botting', n = 'Botting' } })[1].k, 'botting', 'server reasons')
local m, err = L.reportMessage('  Bad Guy ', 'botting', ' same\npath ', 'Me')
eq(m and m.name, 'Bad Guy', 'name trimmed')
eq(m and m.note, 'same path', 'note cleaned')
m, err = L.reportMessage('me', 'scam', '', 'Me')
eq(err, 'You cannot report yourself.', 'self')
m, err = L.reportMessage('X', 'scam', '', 'Me')
eq(err, 'Type the name of the character you want to report.', 'short name')
m, err = L.reportMessage('Bad Guy', '', '', 'Me')
eq(err, 'Choose a reason.', 'reason')
m, err = L.reportMessage('Bad Guy', 'other', 'ok', 'Me')
eq(err, 'Describe the problem in the note (reason Other).', 'other needs a note')
eq(#L.cleanNote(string.rep('a', 300), 200), 200, 'note cut')
eq(L.cleanNote('caf\195\169', 10), 'caf', 'non-ASCII dropped')
eq(L.noteCounter('abc', 200), '3/200', 'counter')
eq(L.canReport(true, false), true, 'another player')
eq(L.canReport(true, true), false, 'not yourself')
eq(L.canReport(false, false), false, 'not a monster')

if fails > 0 then
  print('antibot_logic_test: ' .. fails .. ' failure(s)')
  os.exit(1)
end
print('antibot_logic_test: OK')
