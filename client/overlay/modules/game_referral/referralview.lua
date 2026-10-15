-- Referral window texts (pure, no UI calls): shared by referral.lua and referralview_test.lua.
-- `s` is the server's status (server data/scripts/chaos/referral_core.lua ChaosReferralCore.view).
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)

ReferralView = ReferralView or {}
local V = ReferralView

local function num(v) return tonumber(v) or 0 end

function V.leftText(seconds)
  seconds = num(seconds)
  if seconds <= 0 then return '' end
  local days = math.floor(seconds / 86400)
  if days >= 1 then
    return string.format('%d day%s left', days, days == 1 and '' or 's')
  end
  local hours = math.max(1, math.floor(seconds / 3600))
  return string.format('%d hour%s left', hours, hours == 1 and '' or 's')
end

-- the big code line and the line under it
function V.code(s)
  if not s then return 'Loading...', '' end
  if not s.enabled then return '-', tr('The referral program is off.') end
  if (s.code or '') == '' then return '-', s.codeNote or '' end
  local under = 'Share it: a friend enters it when creating an account on the website, or in this window in the first week.'
  if (s.shareUrl or '') ~= '' then
    under = tr('Share it, or the link %s', s.shareUrl)
  end
  return s.code, under
end

-- what the friend and the referrer get
function V.rewardsText(s)
  if not s then return '' end
  local lines = {}
  local gift = s.gift or ''
  if (s.giftTitle or '') ~= '' then gift = tr('%s and the title %s', gift, s.giftTitle) end
  lines[#lines + 1] = tr('Your friend gets: %s.', gift)
  local parts = {}
  for _, m in ipairs(s.milestones or {}) do
    parts[#parts + 1] = string.format('level %d: %s', num(m.level), m.reward or '')
  end
  if #parts > 0 then
    lines[#lines + 1] = tr('You get, when your friend\'s first character reaches %s.', table.concat(parts, '; '))
  end
  local tiers = {}
  for _, t in ipairs(s.tiers or {}) do
    tiers[#tiers + 1] = string.format('%d friends: %s%s', num(t.count), t.reward or '', t.reached and ' (yours)' or '')
  end
  if #tiers > 0 then
    lines[#lines + 1] = tr('And with friends at level %d (%d so far): %s.', num(s.qualifyLevel), num(s.qualified),
      table.concat(tiers, '; '))
  end
  return table.concat(lines, '\n')
end

-- the "got a code" part: text, whether the code box is shown
function V.entry(s)
  if not s then return '', false end
  if (s.referrer or '') ~= '' then
    local text = tr('You were referred by %s.', s.referrer)
    if s.linkStatus == 'active' then
      text = text .. (s.giftGiven and tr(' Your welcome gift was given.') or tr(' Your welcome gift comes at your next login.'))
    end
    return text, false
  end
  if s.canEnter then
    local text = tr('Got a code from a friend? Enter it here (%s).', V.leftText(s.enterLeft))
    if (s.rejected or '') ~= '' then
      text = tr('The code from your account creation was not accepted: %s You can enter another one (%s).', s.rejected, V.leftText(s.enterLeft))
    end
    return text, true
  end
  return s.enterNote or '', false
end

V.STATE_TEXT = { open = '-', due = 'waiting', paid = 'rewarded', void = 'no reward' }
V.STATE_COLOR = { open = '#8c8070', due = '#e8b84a', paid = '#80c070', void = '#e07060' }

function V.friendRows(s)
  local rows = {}
  for _, f in ipairs(s and s.friends or {}) do
    local steps = {}
    for _, st in ipairs(f.steps or {}) do
      steps[#steps + 1] = { text = string.format('Lv %d: %s', num(st.level), V.STATE_TEXT[st.state] or tostring(st.state)),
        color = V.STATE_COLOR[st.state] or '#8c8070' }
    end
    local when = num(f.linkedAt) > 0 and os.date('%Y-%m-%d', num(f.linkedAt)) or '?'
    rows[#rows + 1] = { name = f.name or '?', sub = string.format('Level %d, joined %s', num(f.level), when), steps = steps }
  end
  return rows
end

function V.friendsHeader(s)
  local n = s and #(s.friends or {}) or 0
  return n == 0 and tr('Referred friends') or tr('Referred friends (%d)', n)
end

function V.monthText(s)
  if not s then return '' end
  return tr('This month: %d / %d new friends, %d / %d rewards.   Chaos Coins earned: %d',
    num(s.linksThisMonth), num(s.monthlyLinks), num(s.paidThisMonth), num(s.monthlyRewards), num(s.coinsEarned))
end

function V.emptyText(s)
  if s and #(s.friends or {}) == 0 then
    return tr('Nobody has joined with your code yet.')
  end
  return ''
end

