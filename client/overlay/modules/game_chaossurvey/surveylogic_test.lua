-- luajit surveylogic_test.lua (CI runs every client/overlay/modules/*/*_test.lua from the repo root, under LuaJIT and Lua 5.3)
dofile((arg and arg[0] and arg[0]:match('^(.*[/\\])') or '') .. 'surveylogic.lua')
local L = SurveyLogic
local n = 0
local function eq(a, b, m) n = n + 1 if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end end

-- cp1252 -> UTF-8, cut
eq(L.toUtf8('n\227o'), 'n\195\163o', 'a cp1252 letter to UTF-8')
eq(L.toUtf8('\128'), '\226\130\172', 'the euro sign')
eq(L.toUtf8('a\129b'), 'ab', 'an undefined byte dropped')
eq(L.toUtf8(nil), '', 'nil')
eq(L.cut('abcdef', 4), 'abcd', 'cut')
eq(L.cut(string.rep('x', 300)):len(), 200, 'default limit')
eq(L.tidy('  a \n b  '), 'a b', 'tidy')
eq(L.answer(20, nil, nil, 'n\227o sei').data.text, 'n\195\163o sei', 'the answer is sent as UTF-8')

-- open
local o = L.parseOpen({ s = 20, max = 200 })
eq(o.stage, 20, 'stage')
eq(o.max, 200, 'max')
eq(L.parseOpen({ s = 21 }), nil, 'unknown stage')
eq(L.parseOpen('x'), nil, 'not a table')
eq(L.parseOpen({ s = 50, max = 9999 }).max, 200, 'max capped')

-- answer and skip
local m = L.answer(20, 4, true, '  where is the bank  ')
eq(m.action, 'answer', 'action')
eq(m.data.s, 20, 's')
eq(m.data.fun, 4, 'fun')
eq(m.data.rec, true, 'rec')
eq(m.data.text, 'where is the bank', 'text tidied')
m = L.answer(50, nil, nil, '')
eq(m.data.fun, nil, 'no fun')
eq(m.data.rec, nil, 'no rec')
eq(m.data.text, nil, 'no text')
eq(L.answer(20, 7, 'yes', 'x').data.fun, nil, 'a bad score is left out')
eq(L.skip(50).action, 'skip', 'skip')
eq(L.skip(50).data.s, 50, 'skip stage')

-- send button and counter
eq(L.canSend(nil, nil, '  '), false, 'nothing given')
eq(L.canSend(3, nil, ''), true, 'a score')
eq(L.canSend(nil, false, ''), true, 'a no')
eq(L.canSend(nil, nil, 'hi'), true, 'a text')
eq(L.counter('n\227o', 200), '3/200', 'counter')

-- where did you hear about the game
eq(L.answer(20, nil, nil, '', nil, 'friend').data.src, 'friend', 'source at level 20')
eq(L.answer(50, nil, nil, '', nil, 'friend').data.src, nil, 'no source at level 50')
eq(L.answer(20, nil, nil, '', nil, 'bogus').data.src, nil, 'unknown source left out')
eq(L.canSend(nil, nil, '', 'forum'), true, 'a source alone')
eq(L.canSend(nil, nil, '', ''), false, 'the empty choice is nothing')
eq(#L.SOURCES, 9, 'nine sources')

print('surveylogic_test: ' .. n .. ' checks ok')
