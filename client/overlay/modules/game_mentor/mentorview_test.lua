-- luajit mentorview_test.lua (CI runs every client *_test.lua with LuaJIT and Lua 5.3)
dofile((arg and arg[0] and arg[0]:match('^(.*[/\\])') or '') .. 'mentorview.lua')
local V = MentorView
local n = 0
local function eq(a, b, m) n = n + 1 if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end end
local function has(text, part, m) eq(tostring(text):find(part, 1, true) ~= nil, true, m) end

eq(V.minutesText(45), '45 min', 'minutes')
eq(V.minutesText(125), '2h 05m', 'hours')
eq(V.leftText(0), 'expired', 'expired')
eq(V.leftText(30), '30s left', 'seconds')
eq(V.leftText(61), '2 min left', 'minutes up')

local rules = { exp = 10, dmg = 5, maxApprentices = 3, maxLevel = 79, gradLevel = 200, accountDays = 60, huntMinutes = 30,
  dailyHuntMarks = 4, monthlyCap = 300, minShared = 30, gradShared = 120, mentorLevel = 150, mentorHours = 100, mentorDays = 30 }
local lines = { { key = 'warrior', name = 'Warrior' }, { key = 'mystic', name = 'Mystic' } }

-- filters
local opts = V.lineOptions({ lines = lines })
eq(#opts, 3, 'any + two lines') eq(opts[1][2], 'Any class', 'any first') eq(opts[2][1], 'warrior', 'line key')
local f = V.filter('mystic', '  Portuguese  ', 'now')
eq(f.line, 'mystic', 'line') eq(f.lang, 'Portuguese', 'trimmed') eq(f.online, 'now', 'online')
eq(V.filter(nil, nil, 'bogus').online, 'any', 'unknown online -> any')
eq(#V.filter('', string.rep('x', 40), 'any').lang, 24, 'lang cut')

-- the Find page
eq(V.pickText(nil), 'Loading...', 'loading')
eq(V.pickText({ enabled = false }), 'The mentor system is off.', 'off')
has(V.pickText({ enabled = true, canPick = true, rules = rules }), '+10% experience', 'rules text')
eq(V.pickText({ enabled = true, canPick = false, pickNote = 'Only characters up to level 79 can pick a mentor.', rules = rules }),
  'Only characters up to level 79 can pick a mentor.', 'why not')
eq(V.pickText({ enabled = true, canPick = false, apprentice = { name = 'X' }, rules = rules }), 'You have a mentor: see My mentor.', 'has one')
local s = { enabled = true, canPick = true, rules = rules, lines = lines }
local row = V.mentorRow({ guid = 4, name = 'Brannoc', level = 60, voc = 'Juggernaut', lang = 'English, EU', hours = '18-23 UTC',
  note = 'Rifts and dungeons', graduates = 1, active = 1, max = 3, online = true }, s)
eq(row.title, 'Brannoc  -  Lv 60 Juggernaut', 'row title')
eq(row.sub, 'English, EU  -  18-23 UTC  -  1 graduate  -  2 places free', 'row sub')
eq(row.canChoose, true, 'can choose') eq(row.status, 'online', 'online') eq(row.statusColor, V.COLORS.good, 'online colour')
eq(V.mentorRow({ max = 3, active = 3 }, s).canChoose, false, 'full mentor')
eq(V.mentorRow({ max = 3, active = 0 }, { canPick = false }).canChoose, false, 'cannot pick')
eq(V.mentorRow({ max = 3, active = 0, graduates = 2 }, s).sub, '2 graduates  -  3 places free', 'no lang / hours')
eq(V.emptyList(nil), 'Press Search to see the mentors.', 'not searched')
eq(V.emptyList({}), 'No mentor matches these filters.', 'none found')
eq(V.emptyList({ {} }), '', 'rows')
local inv = V.inviteRows({ canPick = true, referrer = { guid = 9, name = 'Old Friend' },
  invites = { { guid = 4, name = 'Brannoc', level = 60, voc = 'Juggernaut', left = 300 } } })
eq(#inv, 2, 'referrer and one invitation') eq(inv[1].kind, 'referrer', 'referrer first')
has(inv[1].text, 'Old Friend', 'referrer name') has(inv[2].text, '5 min left', 'invite time')
eq(#V.inviteRows({ canPick = false, referrer = { guid = 9, name = 'x' } }), 0, 'no referrer offer when not allowed')

-- My mentor (the apprentice view)
local t, sub = V.mineHeader({ apprentice = nil })
eq(t, 'You have no mentor.', 'no mentor')
t = V.mineHeader({ graduated = true })
eq(t, 'You graduated.', 'graduated')
local app = { name = 'Brannoc', level = 60, voc = 'Juggernaut', online = true, linkedAt = os.time(), shared = 75, source = 'referral',
  bonus = false, bonusText = 'Join a party with your mentor for the bonus.',
  milestones = { { key = 'l25', name = 'Level 25', marks = 5, state = 'before', got = 0 },
    { key = 'l50', name = 'Level 50', marks = 10, state = 'paid', got = 10 },
    { key = 'rift', name = 'First rift sealed', marks = 10, state = 'open', got = 0 },
    { key = 'graduation', name = 'Level 200: graduation', marks = 50, state = 'unearned', got = 0 } } }
t, sub = V.mineHeader({ apprentice = app })
eq(t, 'Brannoc  -  Lv 60 Juggernaut  (online)', 'mentor header')
has(sub, 'your referrer', 'source') has(sub, '1h 15m', 'shared time')
local text, color = V.bonusLine({ apprentice = app })
eq(text, app.bonusText, 'bonus text') eq(color, V.COLORS.warn, 'no bonus colour')
app.bonus = true
text, color = V.bonusLine({ apprentice = app })
eq(color, V.COLORS.good, 'bonus colour')
local ms = V.milestoneRows(app.milestones)
eq(ms[1].state, 'before the link', 'before') eq(ms[1].marks, '', 'no marks before')
eq(ms[2].marks, '+10', 'paid marks') eq(ms[2].color, V.STATE_COLOR.paid, 'paid colour')
eq(ms[3].marks, '10 marks', 'open marks') eq(ms[4].state, 'no marks', 'unearned')

-- Mentoring (the mentor view)
has(V.requirementsText({ rules = rules, canMentor = true }), 'You can register', 'may register')
has(V.requirementsText({ rules = rules, canMentor = false, mentorNote = 'To mentor, ...' }), 'To mentor, ...', 'why not')
has(V.requirementsText({ rules = rules }), 'level 150 character', 'requirements')
local mentor = { marks = 42, earned = 90, graduates = 2, dayMarks = 1, dayMinutes = 40, monthMarks = 55, linksThisMonth = 1,
  monthlyLinks = 6, apprentices = { { guid = 7, name = 'Ash', level = 33, voc = 'Warrior', online = true, linkedAt = os.time(),
    shared = 30, milestones = app.milestones } } }
local st = V.mentorStats({ mentor = mentor, rules = rules })
has(st, 'Marks 42 (earned 90)', 'marks') has(st, 'Today 1/4 marks, 40 min', 'today') has(st, 'Month 55/300 marks, 1/6 new', 'month')
eq(V.mentorStats({}), '', 'not a mentor')
local ar = V.apprenticeRows({ mentor = mentor })
eq(#ar, 1, 'one apprentice') has(ar[1].title, '(online)', 'online mark')
eq(#ar[1].steps, 4, 'steps') eq(ar[1].steps[1].text, '25', 'short level') eq(ar[1].steps[3].text, 'Rift', 'short rift')
eq(ar[1].steps[4].text, 'Grad', 'short graduation') has(ar[1].steps[2].tip, 'marks paid', 'tooltip')
eq(V.apprenticesHeader({ mentor = mentor, rules = rules }), 'Apprentices (1 / 3)', 'header count')

-- shop
local shop = { { key = 'title_lantern', kind = 'title', name = 'Lanternbearer', desc = 'x', cost = 40, color = '#f0c060', owned = true },
  { key = 'cos_chat_cinder', kind = 'cosmetic', name = 'Cinder Name', desc = 'y', cost = 140, owned = false },
  { key = 'sup_health', kind = 'item', name = '50 Health Potions', desc = 'z', cost = 6, weeklyLeft = 0 },
  { key = 'sup_mana', kind = 'item', name = '50 Mana Potions', desc = 'z', cost = 6, weeklyLeft = 2 } }
local rows = V.shopRows({ mentor = mentor, shop = shop })
eq(rows[1].button, 'Owned', 'owned') eq(rows[1].buyable, false, 'owned not buyable') eq(rows[1].color, '#f0c060', 'title colour')
eq(rows[1].name, 'Title: Lanternbearer', 'kind prefix')
eq(rows[2].buyable, false, 'not enough marks') eq(rows[2].button, 'Buy', 'still a Buy button')
eq(rows[3].button, 'Next week', 'weekly limit') has(rows[4].desc, '2 left this week', 'weekly left')
eq(rows[4].buyable, true, 'buyable') eq(rows[4].price, '6 marks', 'price')
eq(V.shopRows({ shop = shop })[4].button, 'Mentors only', 'only mentors buy')
has(V.shopHeader({ mentor = mentor }), '42', 'balance')
has(V.shopHeader({}), 'Register', 'not a mentor')

-- top and the first tab
local top = V.topRows({ top = { { rank = 1, name = 'Seris', level = 300, voc = 'Illusionist', graduates = 9 }, { rank = 2, name = 'K', graduates = 1 } } })
eq(top[1].rank, '#1', 'rank') eq(top[1].value, '9 graduates', 'graduates') eq(top[2].value, '1 graduate', 'singular')
eq(V.firstTab({ apprentice = {} }), 'mine', 'apprentice opens My mentor')
eq(V.firstTab({ mentor = {} }), 'mentoring', 'mentor opens Mentoring')
eq(V.firstTab({}), 'find', 'else Find')
eq(#V.TABS, 5, 'five tabs')

print('mentorview_test: ' .. n .. ' checks passed')
