-- Run from the repo root: luajit client/overlay/modules/game_chronicle/chronicleview_test.lua (also lua5.3; CI runs every
-- client/overlay/modules/*/*_test.lua). The Chronicle window's pure logic on payloads shaped like the server's
-- (chronicle_core.lua K.payload, memorial_core.lua M.payload), and on a payload the real server code builds.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'chronicleview.lua')
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local V = ChronicleView

eq(V.lang('pt-BR'), 'pt', 'pt-BR is Portuguese')
eq(V.lang('pt_BR'), 'pt', 'pt_BR too')
eq(V.lang('en'), 'en', 'English')
eq(V.lang(nil), 'en', 'nothing: English')
eq(V.lang(42), 'en', 'a number: English')
eq(V.pick({ en = 'a', pt = 'b' }, 'pt'), 'b', 'pick pt')
eq(V.pick({ en = 'a' }, 'pt'), 'a', 'pick falls back to en')
eq(V.pick('plain', 'pt'), 'plain', 'a plain string')
eq(#V.paragraphs({ en = { 'one', '', 'two' } }, 'en'), 2, 'empty paragraphs dropped')
eq(V.paragraphs({ en = 'single' }, 'en')[1], 'single', 'a single text')
eq(#V.paragraphs({ en = { 1, {}, 'ok' } }, 'en'), 1, 'only strings')
eq(V.fmt(1234567), '1,234,567', 'thousands')
eq(V.fmt('x'), '0', 'not a number')
eq(V.dateText(0), '', 'no date')
eq(V.goalPercent({ p = 750, t = 1500 }), 50, 'half')
eq(V.goalPercent({ p = 3000, t = 1500 }), 100, 'capped')
eq(V.goalPercent({ p = 1, t = 0 }), 0, 'no target')
eq(V.goalPercent('bad'), 0, 'bad goal')
eq(V.goalText({ p = 1234, t = 1500 }), '1,234 / 1,500', 'goal text')
eq(V.goalLabel({ l = 'World bosses slain', lp = 'Chefes do mundo derrotados' }, 'pt'), 'Chefes do mundo derrotados', 'pt label')
eq(V.goalLabel({ l = 'World bosses slain' }, 'pt'), 'World bosses slain', 'label fallback')

local t = os.time({ year = 2026, month = 11, day = 14, hour = 12 })
local data = {
  now = t, season = 'Season of Ash', active = true, arc = 's1', done = 1,
  title = { en = 'The Ashen Chronicle: Season of Ash', pt = 'A Crônica das Cinzas: Temporada das Cinzas' },
  chapters = {
    { i = 1, state = 'done', pct = 100, doneAt = t, title = { en = 'I. The Ash Thickens', pt = 'I. As Cinzas se Adensam' },
      text = { en = { 'a', 'b' }, pt = { 'c', 'd' } }, world = { en = 'Ash', pt = 'Cinza' }, goals = {}, mine = 6,
      top = { { n = 'Bryn', p = 10 }, { n = 'Mira', p = 6 } } },
    { i = 2, state = 'open', pct = 42.5, title = { en = 'II. The Wound', pt = 'II. A Ferida' }, text = { en = { 'x' } },
      goals = { { l = 'World bosses slain', p = 3, t = 30 } }, mine = 0, top = {}, pending = { 'cinderscar_breach' } },
    { i = 3, state = 'locked', pct = 0, title = { en = 'III.' }, goals = {}, top = {} },
    'garbage',
  },
  record = { { season = 1, name = 'Season of Ash', title = { en = 'The Ashen Chronicle' },
    chapters = { { i = 1, title = { en = 'I.' }, top = { { n = 'Bryn', p = 99 } } } } }, 7 },
}
local line, color = V.chapterLine(data.chapters[1])
eq(line, 'Written on 14 Nov 2026', 'written line')
eq(color, V.COLORS.done, 'written colour')
line, color = V.chapterLine(data.chapters[2])
eq(line, 'Open: 42.5% written', 'open line')
eq(color, V.COLORS.open, 'open colour')
eq(V.chapterLine(data.chapters[3]), 'Not yet told', 'locked line')
eq(V.chapterLine('x'), '', 'bad chapter')
eq(V.defaultChapter(data), 2, 'the open chapter first')
eq(V.defaultChapter({ chapters = { { state = 'done' }, { state = 'done' } } }), 2, 'all written: the last')
eq(V.defaultChapter({}), nil, 'no chapters')
local rows = V.topRows(data.chapters[1].top)
eq(#rows, 2, 'top rows')
eq(rows[1].name .. ' ' .. rows[1].text, 'Bryn 10', 'top row text')
eq(#V.topRows({ 'x', { n = 'A', p = 1 } }), 1, 'bad rows skipped')
eq(V.pendingText(data.chapters[2]) ~= nil, true, 'a pending area is said')
eq(V.pendingText(data.chapters[1]), nil, 'nothing pending')
eq(#V.recordSeasons(data), 1, 'record seasons: tables only')
eq(V.seasonTitle(data.record[1], 'en'), 'Season of Ash: The Ashen Chronicle', 'season title')
eq(V.seasonTitle({ name = 'S' }, 'en'), 'S', 'season title without the arc')

local mem = { season = 'Season of Ash', records = true, fallen = false, ask = true,
  firsts = { { t = 'Kaelgor', n = 'Hero and Mira', at = t } },
  recs = { { t = 'World Boss Kill, Kaelgor', v = '4:12', n = 'Vexa', c = 'Templar', at = t }, { t = 'Highest Floor', v = '120', n = '', at = t } },
  falls = { { n = 'Fred', l = 88, c = 'Necromancer', k = 'killed by a dragon lord', at = t }, 'bad' } }
eq(V.memorialFirsts(mem)[1].text, 'Hero and Mira', 'firsts')
local recs = V.memorialRecords(mem)
eq(recs[1].text, '4:12, Vexa, Templar', 'a record with its holder')
eq(recs[2].text, '120, a hero who keeps their name', 'a hidden holder')
eq(recs[2].hidden, true, 'hidden flag')
local falls = V.memorialFalls(mem)
eq(#falls, 1, 'falls: tables only')
eq(falls[1].text, 'level 88 Necromancer, killed by a dragon lord', 'a fall')
local secs = V.memorialSections(mem)
eq(#secs, 4, 'four sections')
eq(secs[1].sub, 'Your fall waits for an answer', 'the question is shown')
eq(secs[4].sub, '1 remembered', 'counts')
eq(V.memorialSections(nil)[2].sub, '0 remembered', 'no data')
local req = V.choiceRequest(true, 'yes')
eq(req.records, true, 'records true')
eq(req.fallen, false, 'only true is true')

-- a payload the server code really builds (chronicle_core.lua with the shipped config and text)
local root = dir .. '../../../../server/'
local okc, cfg = pcall(dofile, root .. 'data/scripts/chaos/chronicle_config.lua')
local okt, text = pcall(dofile, root .. 'data/scripts/chaos/chronicle_text.lua')
local okk = pcall(dofile, root .. 'data/scripts/chaos/chronicle_core.lua')
if okc and okt and okk then
  local K = ChaosChronicleCore
  local st = K.newState(cfg, 's1', 1, t)
  K.addEvent(cfg, st, { kind = 'level', level = 300 }, { { guid = 1, name = 'A' } }, t)
  local pl = K.payload(cfg, text, st, { now = t, seasonName = 'Season of Ash', tops = { [1] = { { name = 'A', points = 5 } } } })
  eq(#V.chapters(pl), 5, 'server payload: five chapters')
  eq(V.defaultChapter(pl), 1, 'server payload: chapter 1 open')
  eq(V.goalLabel(pl.chapters[1].goals[1], 'pt'), 'Personagens chegando ao nível 300', 'server payload: pt label')
  eq(V.goalText(pl.chapters[1].goals[1]), '1 / 250', 'server payload: goal text')
  eq(#V.paragraphs(pl.chapters[1].text, 'pt'), 2, 'server payload: pt paragraphs')
  eq(V.chapterLine(pl.chapters[5]), 'Not yet told', 'server payload: chapter 5 locked')
  eq(V.topRows(pl.chapters[1].top)[1].name, 'A', 'server payload: top')
else
  print('FAIL the server files did not load')
  fails = fails + 1
end

print(string.format('chronicleview_test: %d checks, %d failures', checks, fails))
if fails > 0 then os.exit(1) end
