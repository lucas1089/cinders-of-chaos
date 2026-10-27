-- Mentor window texts and rows (pure, no UI calls): shared by mentor.lua and mentorview_test.lua.
-- `s` is the server's status (server data/scripts/chaos/mentor_core.lua ChaosMentorCore.view), `rows` its mentor list.
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)

MentorView = MentorView or {}
local V = MentorView

local function num(v) return tonumber(v) or 0 end

V.COLORS = { gold = '#e8b84a', text = '#d6c9ae', dim = '#8c8070', good = '#80c070', warn = '#e8b84a', bad = '#e07060' }

V.STATE_TEXT = { open = '-', paid = 'marks paid', unearned = 'no marks', capped = 'month cap', before = 'before the link' }
V.STATE_COLOR = { open = '#8c8070', paid = '#80c070', unearned = '#e07060', capped = '#e8b84a', before = '#6b6258' }

V.ONLINE_OPTIONS = { { 'any', 'Any time' }, { 'week', 'Seen this week' }, { 'now', 'Online now' } }

V.TABS = {
  { 'find', 'Find a mentor' }, { 'mine', 'My mentor' }, { 'mentoring', 'Mentoring' }, { 'shop', 'Marks Shop' }, { 'top', 'Top Mentors' }
}

function V.minutesText(m)
  m = math.floor(num(m))
  if m < 60 then return m .. ' min' end
  return string.format('%dh %02dm', math.floor(m / 60), m % 60)
end

function V.leftText(seconds)
  seconds = math.floor(num(seconds))
  if seconds <= 0 then return 'expired' end
  if seconds < 60 then return seconds .. 's left' end
  return tr('%s min left', math.ceil(seconds / 60))
end

-- class options of the browse filter: {{key, text}}, "any" first
function V.lineOptions(s)
  local out = { { '', 'Any class' } }
  for _, l in ipairs(s and s.lines or {}) do out[#out + 1] = { l.key, l.name } end
  return out
end

-- the filter the client sends with `list`
function V.filter(line, lang, online)
  local o = 'any'
  for _, opt in ipairs(V.ONLINE_OPTIONS) do
    if opt[1] == online then o = online end
  end
  lang = tostring(lang or ''):gsub('^%s+', ''):gsub('%s+$', '')
  return { line = line or '', lang = lang:sub(1, 24), online = o }
end

-- the top of the Find page: the rules for apprentices, or why this character may not pick
function V.pickText(s)
  if not s then return 'Loading...' end
  if not s.enabled then return tr('The mentor system is off.') end
  local r = s.rules or {}
  if s.apprentice then
    return tr('You have a mentor: see My mentor.')
  end
  if not s.canPick then return s.pickNote or '' end
  return tr('New characters (up to level %d, account up to %d days old) can pick a mentor. Hunting together in a ' ..
    'party gives you +%d%% experience and %d%% less damage from monsters while your mentor is not far above the monsters. ' ..
    'You graduate at level %d.', num(r.maxLevel), num(r.accountDays), num(r.exp), num(r.dmg), num(r.gradLevel))
end

-- a row of the mentor list: {title, sub, note, online, canChoose, guid}
function V.mentorRow(r, s)
  local places = math.max(0, num(r.max) - num(r.active))
  local sub = {}
  if (r.lang or '') ~= '' then sub[#sub + 1] = r.lang end
  if (r.hours or '') ~= '' then sub[#sub + 1] = r.hours end
  sub[#sub + 1] = tr(num(r.graduates) == 1 and '%d graduate' or '%d graduates', num(r.graduates))
  sub[#sub + 1] = tr(places == 1 and '%d place free' or '%d places free', places)
  return {
    guid = r.guid,
    title = string.format('%s  -  Lv %d %s', tostring(r.name or '?'), num(r.level), tostring(r.voc or '')),
    sub = table.concat(sub, '  -  '),
    note = r.note or '',
    online = r.online and true or false,
    status = r.online and 'online' or 'offline',
    statusColor = r.online and V.COLORS.good or V.COLORS.dim,
    canChoose = (s == nil or (s.canPick and not s.apprentice)) and places > 0
  }
end

function V.mentorRows(rows, s)
  local out = {}
  for _, r in ipairs(rows or {}) do out[#out + 1] = V.mentorRow(r, s) end
  return out
end

function V.emptyList(rows)
  if rows == nil then return tr('Press Search to see the mentors.') end
  if #rows == 0 then return tr('No mentor matches these filters.') end
  return ''
end

-- invitations and the referrer's mentor character: {{guid, text, kind}}
function V.inviteRows(s)
  local out = {}
  if not s then return out end
  if s.referrer and s.canPick then
    out[#out + 1] = { guid = s.referrer.guid, kind = 'referrer',
      text = tr('Your referrer mentors as %s.', tostring(s.referrer.name or '?')) }
  end
  for _, i in ipairs(s.invites or {}) do
    out[#out + 1] = { guid = i.guid, kind = 'invite',
      text = tr('%s (Lv %d %s) invites you - %s', tostring(i.name or '?'), num(i.level), tostring(i.voc or ''),
        V.leftText(i.left)) }
  end
  return out
end

-- milestone rows: {text, state, color, marks}
function V.milestoneRows(list)
  local out = {}
  for _, m in ipairs(list or {}) do
    local marks = ''
    if m.state == 'paid' then marks = '+' .. num(m.got)
    elseif m.state == 'open' then marks = num(m.marks) .. ' marks' end
    out[#out + 1] = { text = tostring(m.name or m.key), state = V.STATE_TEXT[m.state] or tostring(m.state),
      color = V.STATE_COLOR[m.state] or V.COLORS.dim, marks = marks }
  end
  return out
end

-- My mentor page
function V.mineHeader(s)
  if not s then return '', '' end
  local a = s.apprentice
  if not a then
    if s.graduated then return tr('You graduated.'), tr('Thank your mentor: you can become one yourself one day.') end
    return tr('You have no mentor.'), tr('Pick one in Find a mentor, or accept an invitation.')
  end
  local title = string.format('%s  -  Lv %d %s  (%s)', tostring(a.name or '?'), num(a.level), tostring(a.voc or ''),
    a.online and 'online' or 'offline')
  local since = num(a.linkedAt) > 0 and os.date('%Y-%m-%d', num(a.linkedAt)) or '?'
  local how = ({ list = 'chosen from the list', invite = 'by invitation', referral = 'your referrer' })[a.source] or a.source
  local sub = tr('Mentor since %s (%s). Hunted together: %s.', since, tostring(how), V.minutesText(a.shared))
  return title, sub
end

function V.bonusLine(s)
  local a = s and s.apprentice
  if not a then return '', V.COLORS.dim end
  return a.bonusText or '', a.bonus and V.COLORS.good or V.COLORS.warn
end

-- Mentoring page
function V.requirementsText(s)
  if not s then return '' end
  local r = s.rules or {}
  local base = tr('Mentors: an account with a level %d character, %d hours of play and %d days of age. ' ..
    'Up to %d apprentices. You earn Mentor Marks from their milestones (after %d minutes hunting together) and 1 mark per ' ..
    '%d minutes of hunting together (%d a day, %d a month in all). Marks buy titles, cosmetics and supplies, never power.',
    num(r.mentorLevel), num(r.mentorHours), num(r.mentorDays), num(r.maxApprentices), num(r.minShared), num(r.huntMinutes),
    num(r.dailyHuntMarks), num(r.monthlyCap))
  if s.mentor then return base end
  if s.canMentor then return tr('%s You can register this character.', base) end
  return base .. ' ' .. (s.mentorNote or '')
end

function V.mentorStats(s)
  local m = s and s.mentor
  if not m then return '' end
  local r = s.rules or {}
  return tr('Marks %d (earned %d)   Graduates %d   Today %d/%d marks, %s   Month %d/%d marks, %d/%d new',
    num(m.marks), num(m.earned), num(m.graduates), num(m.dayMarks), num(r.dailyHuntMarks), V.minutesText(m.dayMinutes),
    num(m.monthMarks), num(r.monthlyCap), num(m.linksThisMonth), num(m.monthlyLinks))
end

-- apprentices of the mentor: {guid, title, sub, steps = {{text, color}}}
function V.apprenticeRows(s)
  local out = {}
  for _, a in ipairs(s and s.mentor and s.mentor.apprentices or {}) do
    local steps = {}
    for _, m in ipairs(a.milestones or {}) do
      local short = tostring(m.key or '')
      short = ({ l25 = '25', l50 = '50', l100 = '100', rift = 'Rift', dungeon = 'Dng', bounty = 'Bty', worldboss = 'WB',
        graduation = 'Grad' })[short] or short
      steps[#steps + 1] = { text = short, color = V.STATE_COLOR[m.state] or V.COLORS.dim,
        tip = tostring(m.name or '') .. ': ' .. (V.STATE_TEXT[m.state] or tostring(m.state)) }
    end
    out[#out + 1] = {
      guid = a.guid,
      title = string.format('%s  -  Lv %d %s%s', tostring(a.name or '?'), num(a.level), tostring(a.voc or ''), a.online and '  (online)' or ''),
      sub = tr('Since %s, together %s', num(a.linkedAt) > 0 and os.date('%Y-%m-%d', num(a.linkedAt)) or '?', V.minutesText(a.shared)),
      steps = steps
    }
  end
  return out
end

function V.apprenticesHeader(s)
  local m = s and s.mentor
  if not m then return 'Apprentices' end
  return tr('Apprentices (%d / %d)', #(m.apprentices or {}), num(s.rules and s.rules.maxApprentices))
end

-- shop rows: {key, name, color, desc, price, buyable, button}
function V.shopRows(s)
  local out = {}
  local marks = s and s.mentor and num(s.mentor.marks) or 0
  local isMentor = s and s.mentor ~= nil
  for _, o in ipairs(s and s.shop or {}) do
    local button, buyable = 'Buy', true
    if not isMentor then buyable, button = false, tr('Mentors only')
    elseif o.owned then buyable, button = false, 'Owned'
    elseif o.weeklyLeft ~= nil and num(o.weeklyLeft) <= 0 then buyable, button = false, tr('Next week')
    elseif marks < num(o.cost) then buyable = false end
    local desc = o.desc or ''
    if o.weeklyLeft ~= nil then desc = desc .. tr(' (%d left this week)', num(o.weeklyLeft)) end
    local kind = ({ title = 'Title', cosmetic = 'Cosmetic', item = 'Supplies' })[o.kind] or ''
    out[#out + 1] = { key = o.key, name = (kind ~= '' and (kind .. ': ') or '') .. tostring(o.name or o.key),
      color = o.kind == 'title' and (o.color or V.COLORS.gold) or V.COLORS.text, desc = desc,
      price = num(o.cost) .. ' marks', buyable = buyable, button = button }
  end
  return out
end

function V.shopHeader(s)
  if not s or not s.mentor then return tr('Mentor Marks are earned by mentoring. Register in Mentoring.') end
  return tr('Your Mentor Marks: %d', num(s.mentor.marks))
end

function V.topRows(s)
  local out = {}
  for _, t in ipairs(s and s.top or {}) do
    out[#out + 1] = { rank = '#' .. num(t.rank), name = string.format('%s  -  Lv %d %s', tostring(t.name or '?'), num(t.level),
      tostring(t.voc or '')), value = tr(num(t.graduates) == 1 and '%d graduate' or '%d graduates', num(t.graduates)) }
  end
  return out
end

-- the tab to open first: My mentor for an apprentice, Mentoring for a mentor, else Find
function V.firstTab(s)
  if s and s.apprentice then return 'mine' end
  if s and s.mentor then return 'mentoring' end
  return 'find'
end
