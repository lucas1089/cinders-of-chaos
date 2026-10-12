-- luajit referralview_test.lua (CI runs every client *_test.lua)
dofile((arg and arg[0] and arg[0]:match('^(.*[/\\])') or '') .. 'referralview.lua')
local V = ReferralView
local n = 0
local function eq(a, b, m) n = n + 1 if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end end

eq(V.leftText(6 * 86400 + 5), '6 days left', 'days')
eq(V.leftText(86400), '1 day left', 'one day')
eq(V.leftText(7200), '2 hours left', 'hours')
eq(V.leftText(60), '1 hour left', 'under an hour rounds up')
eq(V.leftText(0), '', 'nothing left')

local code, under = V.code(nil)
eq(code, 'Loading...', 'no data yet')
code, under = V.code({ enabled = true, code = 'ABCD-EFGH', shareUrl = '' })
eq(code, 'ABCD-EFGH', 'code') eq(under:find('website', 1, true) ~= nil, true, 'how to share')
code, under = V.code({ enabled = true, code = 'ABCD-EFGH', shareUrl = 'https://x/register.php?ref=ABCDEFGH' })
eq(under:find('ref=ABCDEFGH', 1, true) ~= nil, true, 'share link')
code, under = V.code({ enabled = true, code = '', codeNote = 'Reach level 20 ...' })
eq(code, '-', 'no code') eq(under, 'Reach level 20 ...', 'why')
code = V.code({ enabled = false })
eq(code, '-', 'off')

local s = { enabled = true, gift = '50 health potions, 50 mana potions', giftTitle = 'Kindled',
  milestones = { { level = 50, reward = 'the title Torchbearer and 25 Chaos Coins' }, { level = 150, reward = '50 Chaos Coins' } } }
local r = V.rewardsText(s)
eq(r:find('Kindled', 1, true) ~= nil, true, 'gift title')
eq(r:find('level 50: the title Torchbearer', 1, true) ~= nil, true, 'milestone 50')
eq(r:find('level 150: 50 Chaos Coins', 1, true) ~= nil, true, 'milestone 150')

local text, box = V.entry({ canEnter = true, enterLeft = 3 * 86400 })
eq(box, true, 'code box') eq(text:find('3 days left', 1, true) ~= nil, true, 'time left')
text, box = V.entry({ canEnter = true, enterLeft = 3600, rejected = 'same connection.' })
eq(text:find('not accepted', 1, true) ~= nil, true, 'rejected shown') eq(box, true, 'may try again')
text, box = V.entry({ referrer = 'Old Friend', linkStatus = 'active', giftGiven = true })
eq(box, false, 'linked: no box') eq(text:find('Old Friend', 1, true) ~= nil, true, 'referrer') eq(text:find('was given', 1, true) ~= nil, true, 'gift')
text, box = V.entry({ canEnter = false, enterNote = 'Referral codes can only be entered in the first 7 days of a new account.' })
eq(box, false, 'old account') eq(text:find('7 days', 1, true) ~= nil, true, 'why')

local rows = V.friendRows({ friends = { { name = 'Ash', level = 77, linkedAt = os.time(), steps = { { level = 50, state = 'paid' }, { level = 150, state = 'open' } } },
  { name = 'Cinder', level = 160, linkedAt = 0, steps = { { level = 50, state = 'void' }, { level = 150, state = 'due' } } } } })
eq(#rows, 2, 'two friends')
eq(rows[1].steps[1].text, 'Lv 50: rewarded', 'paid step') eq(rows[1].steps[2].text, 'Lv 150: -', 'open step')
eq(rows[2].steps[1].text, 'Lv 50: no reward', 'void step') eq(rows[2].steps[2].text, 'Lv 150: waiting', 'due step')
eq(rows[1].sub:find('Level 77', 1, true) ~= nil, true, 'level')
eq(V.friendsHeader({ friends = { {}, {} } }), 'Referred friends (2)', 'header count')
eq(V.emptyText({ friends = {} }), 'Nobody has joined with your code yet.', 'empty')
eq(V.monthText({ linksThisMonth = 2, monthlyLinks = 10, paidThisMonth = 1, monthlyRewards = 10, coinsEarned = 25 }):find('2 / 10 new friends', 1, true) ~= nil, true, 'month')

print('referralview_test: ' .. n .. ' checks passed')
